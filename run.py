from __future__ import annotations

import shlex
import socket
import struct
import sys
import threading

SOCKET_PATH = "/tmp/glow.sock"

WINDOW_CREATE     = 0
WINDOW_DESTROY    = 1
WINDOW_VISIBLE    = 2
WINDOW_FULLSCREEN = 3
WINDOW_PROGRAM    = 4

def u8(x: int) -> bytes:   return struct.pack("<B", x)
def u32(x: int) -> bytes:  return struct.pack("<I", x)
def lstr(s: str) -> bytes: b = s.encode(); return u32(len(b)) + b

def frame(cmd_type: int, payload: bytes) -> bytes:
    return struct.pack("<BI", cmd_type, len(payload)) + payload

def encode_create(wid: int) -> bytes:
    return frame(WINDOW_CREATE, u32(wid))

def encode_destroy(wid: int) -> bytes:
    return frame(WINDOW_DESTROY, u32(wid))

def encode_visible(wid: int, v: bool) -> bytes:
    return frame(WINDOW_VISIBLE, u32(wid) + u8(v))

def encode_fullscreen(wid: int) -> bytes:
    return frame(WINDOW_FULLSCREEN, u32(wid))

def encode_program(wid: int, path: str, source: str) -> bytes:
    return frame(WINDOW_PROGRAM, u32(wid) + lstr(path) + lstr(source))

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
                payload = buf[4:4 + size]
                buf = buf[4 + size:]
                print(f"[server] type={payload[0]} payload={payload[1:].hex()}")
    except Exception:
        pass

HELP = """\
Commands:
  create <wid>
  destroy <wid>
  visible <wid> <0|1>
  fullscreen <wid>
  program <wid> <path>          (reads file from disk)
  quit
"""

def repl(sock: socket.socket) -> None:
    def send(data: bytes) -> None:
        sock.sendall(data)

    print(HELP)
    send(encode_create(0))
    path = "tests/test_camera.slang"
    send(encode_program(0, path, open(path).read())) 
    for raw in sys.stdin:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            parts = shlex.split(line)
            cmd = parts[0].lower()

            if cmd == "quit":
                break
            elif cmd == "create":
                send(encode_create(int(parts[1], 0)))
            elif cmd == "destroy":
                send(encode_destroy(int(parts[1], 0)))
            elif cmd == "visible":
                send(encode_visible(int(parts[1], 0), bool(int(parts[2]))))
            elif cmd == "fullscreen":
                send(encode_fullscreen(int(parts[1], 0)))
            elif cmd == "program":
                wid, path = int(parts[1], 0), parts[2]
                send(encode_program(wid, path, open(path).read()))
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

