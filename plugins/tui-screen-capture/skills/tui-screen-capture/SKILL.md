---
name: tui-screen-capture
description: >-
  Capture and read what a terminal UI actually draws, by running it in a pty at a chosen size and reconstructing the screen through a VT emulator. Use this whenever working on a TUI or terminal dashboard, in ratatui, bubbletea, blessed, textual, ncurses or anything else that paints a full screen: before changing a pane, after changing it, when a snapshot test passes but the screen looks wrong, when checking a colour or a band or a highlight is really painted, when column widths or truncation are in question, and when someone says a redesign "looks the same as before". Also use it to drive a TUI, by sending keystrokes and reading the screen that comes back. Reach for it early rather than after a change is written, because reading source and diffs is exactly what fails to catch a TUI defect.
---

# Reading what a TUI actually drew

A terminal UI is the one kind of program you cannot check by reading its
output, because it does not have output in the usual sense. It paints cells.
Two panes that produce identical text can look completely different, and a
pane that reads perfectly in a diff can render as an empty grey rectangle.

The failure mode this exists to prevent: writing a change, watching the
snapshot tests pass, and shipping something nobody looked at. Snapshot tests
pin characters. They will happily pin a column that renders identically on
every row, a name field 86 cells wide, or a band whose background never got
painted, and report all of it green.

## Capture a screen

```bash
uv run ${CLAUDE_SKILL_DIR}/scripts/capture.py --cols 160 --rows 48 -- <command that starts the TUI>
```

Everything after the first `--` is the command, passed through untouched, so
`-- cargo run --release -- tui` and `-- npm run dev -- --watch` both work.
`uv run` installs the one dependency on its own; without `uv`, run
`pip install pyte` and use `python3`. It needs a Unix pty: macOS, Linux, or
WSL. Output is the reconstructed screen, one numbered line per row.

Useful flags:

- `--attrs` marks, under each line, which cells carry reverse video (`R`), a
  background colour (`B`) or a foreground colour (`f`). This is the only way
  to tell a painted band from a line that merely spells the word, and it is
  usually the thing actually in question.
- `--keys` sends keystrokes once the screen has settled, so you can open a
  pane and read the result. Repeatable, and `\x1b` and `\r` work: `--keys e`
  then `--keys j` then `--keys '\x1b'`.
- `--env K=V` for anything the program reads, repeatable.
- `--seconds` for how long to let it run, and `--cols`/`--rows` for the size.
- `--raw PATH` keeps the bytes, so you can re-render at a different size or
  diff two captures without running the program again.

## Three things that will waste an hour if you improvise this

**The size has to be set on the pty, not in the environment.** A TUI asks the
terminal over `ioctl(TIOCSWINSZ)` and ignores `$COLUMNS` and `$LINES`. Set the
environment variables and you will silently measure the default 80x24 while
believing you asked for 200 columns.

**Stripping escape codes with a regex does not work.** A full-screen program
redraws by moving the cursor to absolute positions and overwriting, so the
byte stream is not the screen in order. Strip the escapes and you get one
line, or the same row eleven times. You need something that keeps a cell grid
and replays the moves into it, which is what the script does with `pyte`.

**The first frame is usually empty.** Anything that polls draws once before
its first result arrives, so a short capture shows a startup state with no
rows and a "not read yet" somewhere. If the screen looks empty, capture for
longer before concluding anything.

## Use it as a loop, not as a post-mortem

Capture the screen before the change and after it, and read both. A capture
costs a few seconds and it catches the entire class of defect that review and
tests cannot see:

- a column that renders the same string on every row, so it carries no
  information even though each cell is individually correct
- a field that eats the remainder of a wide terminal, leaving a screen that
  is mostly whitespace
- a band, highlight or selection that never got its background, because the
  style was applied only under the text rather than across the row
- content truncated off the right edge at a realistic width, where the thing
  cut is the thing worth reading
- prose in a caption or header that the same change has just made false

Capture at more than one width. Responsive rules mean the interesting bugs
live at the boundaries, and a layout that works at 160 can be unusable at 120
and absurd at 240.

When something looks wrong and the cause is not obvious, capture the old build
and the new one against the same data at the same size. Two screens side by
side settle in seconds what a conversation about what changed does not.
