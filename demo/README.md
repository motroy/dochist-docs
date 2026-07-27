# Demo recording

`dochist-demo.gif` (embedded in the main [README](../README.md)) and
`dochist-demo.cast` are generated from a scripted walkthrough: `dochist init`
→ `run` a fake `fastqc` / `spades.py` pipeline → `meta set` → `log` →
`artifacts` → `report` → a quick tour of `dochist browse` (switch tabs,
filter, inspect a command's detail pane).

## Files

- `record.sh` — the script that's actually recorded. Sets up its own scratch
  directory (never the repo working tree), puts `fake-tools/` on `PATH` so
  the pipeline runs without needing real bioinformatics tools installed, and
  "types" each command with a short per-character delay before running it.
- `fake-tools/fastqc`, `fake-tools/spades.py` — minimal stand-ins that print
  realistic progress output and write real files, so dochist has genuine
  artifacts to hash and track.
- `pty_type.py` — a small generic pty driver used to script the
  `dochist browse` segment (it launches a program in its own pty, streams
  the program's output live to stdout, and injects a timed sequence of
  keystrokes — see its docstring for the step format).

## Re-recording

Requires [asciinema](https://asciinema.org) and
[agg](https://github.com/asciinema/agg) (`cargo install --git
https://github.com/asciinema/agg`):

```sh
cargo build --release
export PATH="$PWD/target/release:$PATH"

asciinema rec demo/dochist-demo.cast --cols 100 --rows 26 \
  --overwrite -c "bash demo/record.sh"

agg --font-family "DejaVu Sans Mono" --cols 100 --rows 26 \
  demo/dochist-demo.cast demo/dochist-demo.gif
```

Play the raw recording locally (with real terminal colors/timing) via:

```sh
asciinema play demo/dochist-demo.cast
```
