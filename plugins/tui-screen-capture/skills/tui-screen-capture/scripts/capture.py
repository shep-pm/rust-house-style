# /// script
# requires-python = ">=3.11"
# dependencies = ["pyte"]
# ///
"""Run a terminal program in a pty and print the screen it drew.

Run it with `uv run` and the dependency installs itself:

    uv run scripts/capture.py --cols 160 --rows 48 -- ./target/release/myapp tui
"""

import argparse
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time


def capture(cmd, argv, cols, rows, seconds, env, keys, settle):
    """Drive `cmd` in a pty of the given size and return everything it wrote."""
    pid, fd = pty.fork()
    if pid == 0:
        os.environ.update(env)
        os.execvp(cmd, [cmd] + argv)

    # A TUI asks the terminal for its size over ioctl and ignores $COLUMNS,
    # so the window size has to be set on the pty itself.
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    out = b""
    deadline = time.time() + seconds
    sent = False
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
        if keys and not sent and time.time() > deadline - settle:
            for key in keys:
                os.write(fd, key.encode())
                time.sleep(0.25)
            sent = True

    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
    os.close(fd)
    return out


def render(raw, cols, rows, show_attrs):
    import pyte

    screen = pyte.Screen(cols, rows)
    pyte.Stream(screen).feed(raw.decode("utf-8", "replace"))

    lines = []
    for y, text in enumerate(screen.display):
        if not show_attrs:
            lines.append(f"{y:3d}| {text.rstrip()}")
            continue
        row = screen.buffer[y]
        marks = []
        for x in range(cols):
            cell = row[x]
            if cell.reverse:
                marks.append("R")
            elif cell.bg != "default":
                marks.append("B")
            elif cell.fg != "default":
                marks.append("f")
            else:
                marks.append(" ")
        lines.append(f"{y:3d}| {text.rstrip()}")
        painted = "".join(marks).rstrip()
        if painted.strip():
            lines.append(f"   : {painted}")
    return "\n".join(lines)


def main():
    p = argparse.ArgumentParser(description="Capture a TUI's screen through a pty.")
    p.add_argument("--cols", type=int, default=120)
    p.add_argument("--rows", type=int, default=40)
    p.add_argument("--seconds", type=float, default=6.0,
                   help="How long to let it run. Many TUIs draw an empty frame "
                        "before their first poll returns, so allow for that.")
    p.add_argument("--settle", type=float, default=2.0,
                   help="Seconds reserved after --keys are sent, for the redraw.")
    p.add_argument("--env", action="append", default=[], metavar="K=V")
    p.add_argument("--keys", action="append", default=[],
                   help="Keystrokes to send once the screen has settled. Repeatable. "
                        r"Use \x1b for escape, \r for enter.")
    p.add_argument("--attrs", action="store_true",
                   help="Under each line, mark cells that are Reverse video, have a "
                        "Background, or have a foreground colour. This is how you "
                        "check a band is actually painted rather than just spelled.")
    p.add_argument("--raw", metavar="PATH", help="Also write the raw bytes here.")
    p.add_argument("cmd")
    p.add_argument("argv", nargs=argparse.REMAINDER)
    a = p.parse_args()

    env = dict(kv.split("=", 1) for kv in a.env)
    env.setdefault("TERM", "xterm-256color")
    env.setdefault("COLORTERM", "truecolor")
    keys = [k.encode().decode("unicode_escape") for k in a.keys]
    argv = [x for x in a.argv if x != "--"]

    raw = capture(a.cmd, argv, a.cols, a.rows, a.seconds, env, keys, a.settle)
    if a.raw:
        with open(a.raw, "wb") as fh:
            fh.write(raw)
    if not raw:
        print("no output: the program wrote nothing before the deadline", file=sys.stderr)
        return 1
    print(render(raw, a.cols, a.rows, a.attrs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
