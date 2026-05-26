from __future__ import annotations

import argparse
import os
import shlex
import struct
import subprocess
import sys
import threading
import signal
from typing import IO


WINDOW_CREATE = 0
WINDOW_DESTROY = 1
WINDOW_VISIBLE = 2
WINDOW_FULLSCREEN = 3
WINDOW_PROGRAM = 4


def _u32(x: int) -> bytes:
    if x < 0 or x > 0xFFFFFFFF:
        raise ValueError(f"u32 out of range: {x}")
    return struct.pack("<I", x)


def _u8(x: int) -> bytes:
    if x < 0 or x > 0xFF:
        raise ValueError(f"u8 out of range: {x}")
    return struct.pack("<B", x)


def _parse_bool(s: str) -> bool:
    t = s.strip().lower()
    if t in ("1", "true", "t", "yes", "y", "on"):
        return True
    if t in ("0", "false", "f", "no", "n", "off"):
        return False
    raise ValueError(f"invalid bool: {s!r}")


def _frame(cmd_type: int, payload: bytes) -> bytes:
    return struct.pack("<BI", cmd_type, len(payload)) + payload


def encode_create(window_id: int) -> bytes:
    return _frame(WINDOW_CREATE, _u32(window_id))


def encode_destroy(window_id: int) -> bytes:
    return _frame(WINDOW_DESTROY, _u32(window_id))


def encode_visible(window_id: int, visible: bool) -> bytes:
    return _frame(WINDOW_VISIBLE, _u32(window_id) + _u8(1 if visible else 0))


def encode_fullscreen(window_id: int, fullscreen: bool) -> bytes:
    return _frame(WINDOW_FULLSCREEN, _u32(window_id) + _u8(1 if fullscreen else 0))


def encode_program(window_id: int, path: str, source_text: str) -> bytes:
    path_bytes = path.encode("utf-8")
    src_bytes = source_text.encode("utf-8")
    payload = (
        _u32(window_id)
        + _u32(len(path_bytes))
        + path_bytes
        + _u32(len(src_bytes))
        + src_bytes
    )
    return _frame(WINDOW_PROGRAM, payload)


def _pump_stream(src: IO[bytes], dst: IO[bytes]) -> None:
    try:
        while True:
            chunk = src.read(8192)
            if not chunk:
                break
            dst.write(chunk)
            dst.flush()
    except Exception:
        pass


def _write_all(pipe: IO[bytes], data: bytes) -> None:
    view = memoryview(data)
    total = 0
    while total < len(view):
        total += pipe.write(view[total:])
    pipe.flush()


def run_controller(glow_bin: str, glow_args: list[str]):
    env = os.environ.copy()

    try:
        child = subprocess.Popen(
            [
                # "perf",
                # "record",
                # "-F", "99",
                # "--delay", "2000",
                # "-g",
                # "--quiet",
                # "-o", "perf.data",
                # "--call-graph",
                # "dwarf",
                # "--",
                glow_bin,
                *glow_args,
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
            env=env,
        )
    except FileNotFoundError:
        print(f"error: glow binary not found: {glow_bin}", file=sys.stderr)
        return 127

    assert child.stdin is not None
    assert child.stdout is not None
    assert child.stderr is not None

    t_out = threading.Thread(
        target=_pump_stream, args=(child.stdout, sys.stdout.buffer), daemon=True
    )
    t_err = threading.Thread(
        target=_pump_stream, args=(child.stderr, sys.stderr.buffer), daemon=True
    )
    t_out.start()
    t_err.start()

    def send(frame: bytes) -> None:
        assert child.stdin is not None
        try:
            _write_all(child.stdin, frame)
        except BrokenPipeError:
            raise RuntimeError("glow.bin stdin closed (process exited?)")

    send(encode_create(0))
    path = "tests/test_camera.slang"
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        src_text = f.read()
    send(encode_program(0, path, src_text))

    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        rc = child.poll()
        if rc is not None:
            return int(rc)

        try:
            parts = shlex.split(line)
            if not parts:
                continue

            cmd = parts[0].lower()

            if cmd == "quit":
                break

            elif cmd == "create":
                if len(parts) != 2:
                    raise ValueError("usage: create <window_id>")
                send(encode_create(int(parts[1], 0)))

            elif cmd == "destroy":
                if len(parts) != 2:
                    raise ValueError("usage: destroy <window_id>")
                send(encode_destroy(int(parts[1], 0)))

            elif cmd == "visible":
                if len(parts) != 3:
                    raise ValueError("usage: visible <window_id> <true|false|1|0>")
                send(encode_visible(int(parts[1], 0), _parse_bool(parts[2])))

            elif cmd == "fullscreen":
                if len(parts) != 3:
                    raise ValueError("usage: fullscreen <window_id> <true|false|1|0>")
                send(encode_fullscreen(int(parts[1], 0), _parse_bool(parts[2])))

            elif cmd == "program":
                if len(parts) != 4:
                    raise ValueError("usage: program <window_id> <path> <file>")
                window_id = int(parts[1], 0)
                path = parts[2]
                file_path = parts[3]
                with open(file_path, "r", encoding="utf-8", errors="replace") as f:
                    src_text = f.read()
                send(encode_program(window_id, path, src_text))

            else:
                raise ValueError(f"unknown command: {cmd}")

        except Exception as e:
            print(f"error: {e}", file=sys.stderr)

    try:
        child.send_signal(signal.SIGINT)
        child.stdin.close()
    except Exception:
        pass

    code = int(child.wait())
    print(f"glow exited with code {code}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument(
        "glow_bin",
        nargs="?",
        default="./glow.bin",
        help="path to glow.bin (default: ./glow.bin)",
    )
    ap.add_argument(
        "glow_args",
        nargs=argparse.REMAINDER,
        help="args passed to glow.bin (prefix with -- if needed)",
    )
    ns = ap.parse_args(sys.argv[1:])

    glow_bin = ns.glow_bin
    glow_args = ns.glow_args
    if glow_args and glow_args[0] == "--":
        glow_args = glow_args[1:]

    glow_bin = os.path.expanduser(glow_bin)
    run_controller(glow_bin, glow_args)
