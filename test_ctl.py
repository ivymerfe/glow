#!/usr/bin/env python3
"""
glow controller (single-file)

Starts glow.bin as a subprocess, then reads textual commands from THIS program's
stdin, encodes them into Glow's binary protocol, and writes them to glow.bin's stdin.

Protocol (from glow/commands.odin):
  frame = u8 type + u32 payload_size_le + payload

Command types (enum u8):
  0 WINDOW_CREATE:     payload = u32 window_id
  1 WINDOW_DESTROY:    payload = u32 window_id
  2 WINDOW_VISIBLE:    payload = u32 window_id + u8 visible(0/1)
  3 WINDOW_FULLSCREEN: payload = u32 window_id + u8 fullscreen(0/1)
  4 WINDOW_SUSPEND:    payload = u32 window_id + u8 suspend(0/1)
  5 WINDOW_PROGRAM:    payload = u32 window_id + u32 path_len + u32 source_len + path_bytes + source_bytes

Text commands this controller accepts (whitespace / quotes supported):
  create <window_id>
  destroy <window_id>
  visible <window_id> <true|false|1|0>
  fullscreen <window_id> <true|false|1|0>
  suspend <window_id> <true|false|1|0>
  program <window_id> <path> <file>
      - reads <file> as UTF-8 text (errors='replace') and sends it as source_bytes
      - sends <path> as UTF-8 bytes (often a virtual filename or key used by your app)
  quit

Example:
  echo 'create 1
  visible 1 true
  program 1 "shaders/main.slang" "./examples/main.slang"
  ' | ./glow_controller.py ./glow.bin

Notes:
  - Child stdout/stderr are forwarded to this program's stdout/stderr.
"""

from __future__ import annotations

import argparse
import os
import shlex
import struct
import subprocess
import sys
import threading
from typing import BinaryIO, Optional


# GlowCommandType (must match glow/commands.odin order)
WINDOW_CREATE = 0
WINDOW_DESTROY = 1
WINDOW_VISIBLE = 2
WINDOW_FULLSCREEN = 3
WINDOW_SUSPEND = 4
WINDOW_PROGRAM = 5


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
    # header: u8 type + u32 payload_size_le
    return struct.pack("<BI", cmd_type, len(payload)) + payload


def encode_create(window_id: int) -> bytes:
    return _frame(WINDOW_CREATE, _u32(window_id))


def encode_destroy(window_id: int) -> bytes:
    return _frame(WINDOW_DESTROY, _u32(window_id))


def encode_visible(window_id: int, visible: bool) -> bytes:
    return _frame(WINDOW_VISIBLE, _u32(window_id) + _u8(1 if visible else 0))


def encode_fullscreen(window_id: int, fullscreen: bool) -> bytes:
    return _frame(WINDOW_FULLSCREEN, _u32(window_id) + _u8(1 if fullscreen else 0))


def encode_suspend(window_id: int, suspend: bool) -> bytes:
    return _frame(WINDOW_SUSPEND, _u32(window_id) + _u8(1 if suspend else 0))


def encode_program(window_id: int, path: str, source_text: str) -> bytes:
    path_bytes = path.encode("utf-8")
    src_bytes = source_text.encode("utf-8")
    payload = _u32(window_id) + _u32(len(path_bytes)) + _u32(len(src_bytes)) + path_bytes + src_bytes
    return _frame(WINDOW_PROGRAM, payload)


def _pump_stream(src: BinaryIO, dst: BinaryIO) -> None:
    try:
        while True:
            chunk = src.read(8192)
            if not chunk:
                break
            dst.write(chunk)
            dst.flush()
    except Exception:
        # Best-effort forwarding; ignore pump errors.
        pass


def _write_all(pipe: BinaryIO, data: bytes) -> None:
    view = memoryview(data)
    total = 0
    while total < len(view):
        n = pipe.write(view[total:])
        if n is None:
            # Some file-like objects return None; treat as no progress -> flush and retry.
            pipe.flush()
            continue
        total += n
    pipe.flush()


def run_controller(glow_bin: str, glow_args: list[str]) -> int:
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/opt/slang/lib:" + env.get("LD_LIBRARY_PATH", "")

    try:
        child = subprocess.Popen(
            [glow_bin, *glow_args],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
            env=env
        )
    except FileNotFoundError:
        print(f"error: glow binary not found: {glow_bin}", file=sys.stderr)
        return 127

    assert child.stdin is not None
    assert child.stdout is not None
    assert child.stderr is not None

    t_out = threading.Thread(target=_pump_stream, args=(child.stdout, sys.stdout.buffer), daemon=True)
    t_err = threading.Thread(target=_pump_stream, args=(child.stderr, sys.stderr.buffer), daemon=True)
    t_out.start()
    t_err.start()

    def send(frame: bytes) -> None:
        try:
            _write_all(child.stdin, frame)
        except BrokenPipeError:
            raise RuntimeError("glow.bin stdin closed (process exited?)")
    
    send(encode_create(0))
    path = "glow/shaders/test.slang"
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        src_text = f.read()
    send(encode_program(0, path, src_text))

    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        # If the child already exited, stop.
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

            elif cmd == "suspend":
                if len(parts) != 3:
                    raise ValueError("usage: suspend <window_id> <true|false|1|0>")
                send(encode_suspend(int(parts[1], 0), _parse_bool(parts[2])))

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

    # EOF or quit: close child's stdin so it can react if it wants.
    try:
        child.send_signal(subprocess.signal.SIGINT)
        child.stdin.close()
    except Exception:
        pass

    return int(child.wait())


def main(argv: Optional[list[str]] = None) -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("glow_bin", nargs="?", default="./glow.bin", help="path to glow.bin (default: ./glow.bin)")
    ap.add_argument("glow_args", nargs=argparse.REMAINDER, help="args passed to glow.bin (prefix with -- if needed)")
    ns = ap.parse_args(argv)

    glow_bin = ns.glow_bin
    glow_args = ns.glow_args
    if glow_args and glow_args[0] == "--":
        glow_args = glow_args[1:]

    glow_bin = os.path.expanduser(glow_bin)
    return run_controller(glow_bin, glow_args)


if __name__ == "__main__":
    raise SystemExit(main())
