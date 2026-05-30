package glow

import "core:log"
import "core:mem"
import "core:sys/linux"

SOCKET_PATH :: "/tmp/glow.sock"
SERVER_BACKLOG :: 32
CLIENT_BUF_SIZE :: 8192

GlowClient :: struct {
	fd:       linux.Fd,
	rbuf:     [dynamic]u8,
	rbuf_len: int,
	wbuf:     [dynamic]u8,
	wbuf_len: int,
}

GlowServer :: struct {
	ec:      ^EPollController,
	sock_fd: linux.Fd,
	clients: map[linux.Fd]GlowClient,
	on_cmd:  Command_Callback,
}

server_init :: proc(
	srv: ^GlowServer,
	ec: ^EPollController,
	on_cmd: Command_Callback,
	socket_path: cstring = SOCKET_PATH,
) {
	srv.ec = ec
	srv.clients = make(map[linux.Fd]GlowClient)
	srv.on_cmd = on_cmd

	sock, err := linux.socket(.UNIX, .STREAM, {}, .HOPOPT)
	ensure(err == .NONE, "socket() failed")
	srv.sock_fd = sock

	linux.unlink(socket_path)

	addr := linux.Sock_Addr_Un{}
	addr.sun_family = linux.Address_Family.UNIX
	mem.copy(&addr.sun_path[0], transmute([^]u8)socket_path, len(socket_path) + 1)

	berr := linux.bind(sock, &addr)
	ensure(berr == .NONE, "bind() failed")

	lerr := linux.listen(sock, SERVER_BACKLOG)
	ensure(lerr == .NONE, "listen() failed")

	set_nonblocking(linux.Fd(sock))
	epoll_add(srv.ec, sock, {.IN}, server_accept_handler, srv)
	log.infof("Server is running at %s", socket_path)
}

server_destroy :: proc(srv: ^GlowServer) {
	for fd, &client in srv.clients {
		client_close(srv, fd)
	}
	linux.close(srv.sock_fd)
	linux.unlink(SOCKET_PATH)
	delete(srv.clients)
}

server_send :: proc(srv: ^GlowServer, fd: linux.Fd, msg: ^Message) {
	client := &srv.clients[fd]
	needed := client.wbuf_len + len(msg.buf)
	if len(client.wbuf) < needed {
		resize(&client.wbuf, needed)
	}
	copy(client.wbuf[client.wbuf_len:], msg.buf[:])
	client.wbuf_len += len(msg.buf)
	epoll_modify(srv.ec, fd, {.IN, .RDHUP, .OUT})
}

server_broadcast :: proc(srv: ^GlowServer, msg: ^Message) {
	for fd in srv.clients {
		server_send(srv, fd, msg)
	}
}

@(private)
server_accept_handler :: proc(fd: linux.Fd, events: linux.EPoll_Event_Set, user_data: rawptr) {
	srv := cast(^GlowServer)user_data
	for {
		addr: linux.Sock_Addr_In
		client_fd, err := linux.accept(srv.sock_fd, &addr, {.NONBLOCK})
		if err == .EAGAIN || err == .EWOULDBLOCK {
			break
		}
		ensure(err == .NONE, "accept() failed")

		client := GlowClient {
			fd   = client_fd,
			rbuf = make([dynamic]u8, CLIENT_BUF_SIZE),
			wbuf = make([dynamic]u8, CLIENT_BUF_SIZE),
		}
		srv.clients[client_fd] = client

		// Only watch IN + RDHUP until we have something to write.
		epoll_add(srv.ec, client_fd, {.IN, .RDHUP}, client_io_handler, srv)
		log.infof("Client connected: fd=%d", client_fd)
	}
}

@(private)
client_io_handler :: proc(fd: linux.Fd, events: linux.EPoll_Event_Set, user_data: rawptr) {
	srv := cast(^GlowServer)user_data

	if .RDHUP in events || .HUP in events || .ERR in events {
		client_close(srv, fd)
		return
	}
	if .IN in events {
		client_do_read(srv, fd)
	}
	if .OUT in events {
		client_do_write(srv, fd)
	}
}

@(private)
client_do_read :: proc(srv: ^GlowServer, fd: linux.Fd) -> (ok: bool) {
	client := &srv.clients[fd]
	for {
		cap_needed := client.rbuf_len + CLIENT_BUF_SIZE
		if len(client.rbuf) < cap_needed {
			resize(&client.rbuf, cap_needed)
		}
		n, err := linux.read(fd, client.rbuf[client.rbuf_len:])
		if err == .EAGAIN || err == .EWOULDBLOCK {
			break
		}
		if err != .NONE || n == 0 {
			client_close(srv, fd)
			return false
		}
		client.rbuf_len += n
	}
	client_read_commands(srv, fd)
	return true
}

@(private)
client_do_write :: proc(srv: ^GlowServer, fd: linux.Fd) {
	client := &srv.clients[fd]
	for client.wbuf_len > 0 {
		n, err := linux.write(fd, client.wbuf[:client.wbuf_len])
		if err == .EAGAIN || err == .EWOULDBLOCK {
			break
		}
		if err != .NONE || n == 0 {
			client_close(srv, fd)
			return
		}
		// Compact the write buffer.
		remaining := client.wbuf_len - n
		if remaining > 0 {
			copy(client.wbuf[0:remaining], client.wbuf[n:client.wbuf_len])
		}
		client.wbuf_len = remaining
	}
	// Nothing left to write — stop polling for OUT to avoid a busy loop.
	if client.wbuf_len == 0 {
		epoll_modify(srv.ec, fd, {.IN, .RDHUP})
	}
}

@(private)
client_read_commands :: proc(srv: ^GlowServer, fd: linux.Fd) {
	client := &srv.clients[fd]
	consume := 0
	for {
		available := client.rbuf_len - consume
		if available < 4 {
			break
		}
		payload_size := int(read_u32(client.rbuf[consume:consume + 4]))
		ensure(
			payload_size >= 0 && payload_size <= COMMAND_MAX_SIZE,
			"Invalid payload size from client",
		)
		total := 4 + payload_size
		if available < total {
			break
		}
		payload := client.rbuf[consume + 4:consume + total]
		cmd, success := decode_command(payload)
		if success {
			srv.on_cmd(cmd)
		}
		consume += total
	}
	if consume > 0 {
		remaining := client.rbuf_len - consume
		if remaining > 0 {
			copy(client.rbuf[0:remaining], client.rbuf[consume:client.rbuf_len])
		}
		client.rbuf_len = remaining
	}
}

@(private)
client_close :: proc(srv: ^GlowServer, fd: linux.Fd) {
	epoll_remove(srv.ec, fd)
	if client, ok := &srv.clients[fd]; ok {
		delete(client.rbuf)
		delete(client.wbuf)
	}
	delete_key(&srv.clients, fd)
	linux.close(fd)
	log.infof("Client disconnected: fd=%d", fd)
}

@(private)
set_nonblocking :: proc(fd: linux.Fd) {
	flags, err := linux.fcntl(fd, linux.F_GETFL)
	ensure(err == .NONE, "fcntl F_GETFL failed")
	err2 := linux.fcntl(fd, linux.F_SETFL, flags | {.NONBLOCK})
	ensure(err2 == .NONE, "fcntl F_SETFL failed")
}

