#!/usr/bin/env python3
"""Drive an interactive terminal program in its own pty for scripted demo
recordings (e.g. under `asciinema rec -c`).

Streams the child's output live to our own stdout — so it shows up as it
happens in an asciinema recording — while sending a scripted sequence of
(delay, keys) after launch. A handful of key names are recognized (TAB,
ENTER, ESC, UP, DOWN, PAGEUP, PAGEDOWN); anything else is sent as literal
text, one write() per step (which is enough for the target program to see
it as a sequence of keystrokes).

Usage:
    pty_type.py --steps '[[1.0, "TAB"], [1.5, "/spades"], [1.0, "ENTER"], [0.5, "q"]]' -- dochist browse
"""
import argparse
import fcntl
import json
import os
import pty
import select
import struct
import sys
import termios
import time

NAMED_KEYS = {
    "TAB": b"\t",
    "ENTER": b"\r",
    "ESC": b"\x1b",
    "UP": b"\x1b[A",
    "DOWN": b"\x1b[B",
    "LEFT": b"\x1b[D",
    "RIGHT": b"\x1b[C",
    "PAGEUP": b"\x1b[5~",
    "PAGEDOWN": b"\x1b[6~",
}


def to_bytes(key: str) -> bytes:
    return NAMED_KEYS.get(key, key.encode())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--steps",
        default="[]",
        help='JSON list of [delay_seconds, key_or_text] pairs, delays relative to the previous step',
    )
    ap.add_argument(
        "--settle",
        type=float,
        default=2.0,
        help="seconds to wait after the last step before force-killing the child if it hasn't exited",
    )
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    args = ap.parse_args()

    argv = args.cmd
    if argv and argv[0] == "--":
        argv = argv[1:]
    if not argv:
        ap.error("no command given (pass it after --)")

    steps = json.loads(args.steps)
    cumulative = []
    t = 0.0
    for delay, key in steps:
        t += delay
        cumulative.append((t, key))

    try:
        size = os.get_terminal_size(sys.stdout.fileno())
        cols, rows = size.columns, size.lines
    except OSError:
        cols, rows = 100, 30

    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(argv[0], argv)
        os._exit(127)

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    os.set_blocking(fd, False)

    start = time.time()
    step_idx = 0
    deadline = start + (cumulative[-1][0] if cumulative else 0.0) + args.settle

    while True:
        readable, _, _ = select.select([fd], [], [], 0.05)
        if fd in readable:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            os.write(sys.stdout.fileno(), chunk)

        now = time.time()
        while step_idx < len(cumulative) and now - start >= cumulative[step_idx][0]:
            os.write(fd, to_bytes(cumulative[step_idx][1]))
            step_idx += 1

        try:
            wpid, _status = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            break
        if wpid != 0:
            break

        if now > deadline:
            try:
                os.kill(pid, 15)
            except ProcessLookupError:
                pass
            break

    return 0


if __name__ == "__main__":
    sys.exit(main())
