from __future__ import annotations

import readline  
import shlex
import socket
import struct
import sys
import threading

SOCKET_PATH = "/tmp/glow.sock"

SHADER_SOURCE = 0
TOGGLE_FULLSCREEN = 1
REMOVE_SHADER = 2
COMPILE_SHADER = 3


def u8(x: int) -> bytes:
    return struct.pack("<B", x)


def u32(x: int) -> bytes:
    return struct.pack("<I", x)


def lstr(s: str) -> bytes:
    b = s.encode()
    return u32(len(b)) + b


def frame(cmd_type: int, payload: bytes) -> bytes:
    # command type is a part of payload
    return struct.pack("<IB", len(payload) + 1, cmd_type) + payload


def encode_source(path: str, source: str) -> bytes:
    return frame(SHADER_SOURCE, lstr(path) + lstr(source))


def encode_fullscreen(path: str) -> bytes:
    return frame(TOGGLE_FULLSCREEN, lstr(path))


def encode_remove(path: str) -> bytes:
    return frame(REMOVE_SHADER, lstr(path))


def recv_loop(sock: socket.socket) -> None:
    """Print messages from the server (u32 size + payload)."""
    buf = b""
    try:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                print("\n[server disconnected]")
                break
            buf += chunk
            while len(buf) >= 4:
                size = struct.unpack_from("<I", buf)[0]
                if len(buf) < 4 + size:
                    break
                payload = buf[4 : 4 + size]
                buf = buf[4 + size :]
                print(f"[server] type={payload[0]} payload={payload[1:].hex()}")
    except Exception:
        pass


HELP = """\
Commands:
  s <path>
  f <path>
  r  <path>
  q
"""


def repl(sock: socket.socket) -> None:
    def send(data: bytes) -> None:
        sock.sendall(data)

    print(HELP)

    while True:
        try:
            raw = input("> ")
        except (EOFError, KeyboardInterrupt):
            print("\nExiting...")
            break

        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        try:
            parts = shlex.split(line)
            cmd = parts[0].lower()

            if cmd == "q":
                break
            elif cmd == "s":
                path = parts[1]
                send(encode_source(path, open(path).read()))
            elif cmd == "f":
                send(encode_fullscreen(parts[1]))
            elif cmd == "r":
                send(encode_remove(parts[1]))
            else:
                print(f"unknown command: {cmd}")
        except (IndexError, ValueError) as e:
            print(f"error: {e}\n{HELP}")


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else SOCKET_PATH
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(path)
    print(f"connected to {path}")

    threading.Thread(target=recv_loop, args=(sock,), daemon=True).start()
    try:
        repl(sock)
    finally:
        sock.close()


if __name__ == "__main__":
    main()
