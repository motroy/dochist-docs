# dochist

[![CI](https://github.com/motroy/dochist/actions/workflows/ci.yml/badge.svg)](https://github.com/motroy/dochist/actions/workflows/ci.yml)
[![Release](https://github.com/motroy/dochist/actions/workflows/release.yml/badge.svg)](https://github.com/motroy/dochist-docs/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**dochist** is a session-based command history and artifact provenance logger, written in Rust. It records every command you run through it into a named session, tracks the files each command creates or modifies (with SHA-256 checksums), and renders the whole session as a [FAIR](https://www.go-fair.org/fair-principles/) compliance document. Sessions are plain JSON and can be saved and reloaded, so work can be paused and continued — even on a different machine.

Typical use case: documenting a data-analysis or bioinformatics pipeline as you build it, so that at the end you have an auditable, reproducible record of exactly what was run, in what order, and which outputs each step produced.

![dochist demo: init, run, log, artifacts, report, and browse](demo/dochist-demo.gif)

*(recorded with [asciinema](https://asciinema.org) + [agg](https://github.com/asciinema/agg); raw, replayable recording at [`demo/dochist-demo.cast`](demo/dochist-demo.cast) — play it locally with `asciinema play demo/dochist-demo.cast`. See [`demo/README.md`](demo/README.md) for how it's put together / re-recorded.)*

## Install

### Linux (no Rust required)

Run the installer — it downloads a fully-static (musl) binary for your architecture (x86_64 or aarch64) and places it in `~/.local/bin`:

```sh
curl -fsSL https://raw.githubusercontent.com/motroy/dochist-docs/main/install.sh | sh
```

Or with wget:

```sh
wget -qO- https://raw.githubusercontent.com/motroy/dochist-docs/main/install.sh | sh
```

Override the install directory:

```sh
DOCHIST_INSTALL_DIR=/usr/local/bin curl -fsSL https://raw.githubusercontent.com/motroy/dochist-docs/main/install.sh | sh
```

The musl binaries are fully self-contained — no glibc, no Rust runtime, no system libraries beyond the Linux kernel are required.

### Other platforms

Download a prebuilt binary for macOS (Intel/Apple Silicon) or Windows from the [Releases page](https://github.com/motroy/dochist-docs/releases).

### Build from source

```sh
cargo install --git https://github.com/motroy/dochist
```

### Updating

Once installed, `dochist update` checks GitHub for a newer release and, if one exists, downloads and swaps in the matching prebuilt binary for your platform in place — no need to re-run the installer:

```sh
dochist update            # check, and install if a newer version is found (asks first)
dochist update --check    # only report whether an update is available
dochist update -y         # install without the confirmation prompt
```

## Quick start

```sh
# Start a session in the current directory
dochist init my-analysis -d "QC and assembly of sample batch 42"

# Run your commands through dochist — history and artifacts are recorded
dochist run -- fastqc sample.fastq.gz
dochist run -- "spades.py -s sample.fastq.gz -o assembly/"

# Attach FAIR metadata
dochist meta set license MIT
dochist meta set author "Jane Doe"
dochist meta set keywords "assembly, QC, batch-42"

# Inspect what happened
dochist log
dochist artifacts
dochist status

# Generate the FAIR compliance document
dochist report --output FAIR-report.md
dochist report --format json --output FAIR-report.json
```

Commands are executed through the platform shell (`sh -c` / `cmd /C`), so pipes, redirects, and globs work as usual. `dochist run` relays the command's stdout/stderr and propagates its exit code, so it is transparent to wrap in scripts.

## Artifact provenance

Before and after each `dochist run`, the session root is scanned and every file is hashed. The diff attributes created and modified files to the command that ran, so each artifact carries:

- SHA-256 checksum and size
- media type (MIME)
- the command that created it and every command that later modified it
- timestamps of first observation and last update

Files produced outside a `dochist run` (e.g. downloaded manually) can be registered with `dochist artifact-add <path>`.

### Excluding paths (`.dochistignore`)

Not every file that changes is a meaningful artifact — build trees, caches, and workflow-engine bookkeeping (Snakemake's `.snakemake/`, Nextflow's `work/`) just add noise. `dochist init` writes a `.dochistignore` template at the store root that you can edit to control what is tracked.

- **Always excluded** (cannot be re-enabled): `.dochist/`, `.git/`, and `.dochistignore` itself.
- **Excluded by default:** `target`, `node_modules`, `__pycache__`, `.snakemake`, `.nextflow`, `work`, `.ipynb_checkpoints`, `.DS_Store`.
- **Your patterns**, one per line in `.dochistignore`:
  - a pattern **without** `/` matches any file or directory of that name anywhere in the tree and supports `*` and `?` wildcards — e.g. `*.tmp`, `*.log`;
  - a pattern **with** `/` matches a path prefix relative to the store root — e.g. `results/scratch/` excludes everything beneath it.

The active user patterns are recorded in the FAIR report (under **Reusable → Provenance scope** in Markdown, and `provenance_exclusions` in JSON) so exclusions are themselves documented for reproducibility.

Two limitations worth knowing when wrapping a whole pipeline in a single `dochist run`: all outputs are attributed to that one command (not per workflow rule), and files that are both created and deleted within the run — such as Snakemake `temp()` intermediates — are never observed by the before/after snapshot. Invoke per target (`dochist run -- snakemake results/x.bam`) for finer, per-command provenance.

### Provenance documents

Workflow engines produce their own provenance records that capture the per-rule detail dochist's session-level history cannot — Snakemake's `--report report.html`, `--detailed-summary`, and DAG graphs; Nextflow's `report.html` / `timeline.html` / `trace.txt`; CWL RO-Crate metadata; and so on. Emit them inside a `dochist run` (or register them with `dochist artifact-add`) and dochist tracks them as checksummed artifacts:

```sh
dochist run -- snakemake --cores 4
dochist run -- 'snakemake --report report.html'
dochist run -- 'snakemake --detailed-summary > provenance.tsv'
dochist run -- 'snakemake --filegraph | dot -Tsvg > filegraph.svg'
```

The report gains a **Provenance documents** section listing these, so a reader knows where to find rule-level detail. dochist recognises common names automatically (`report.html`, `*dag*.svg`, `rulegraph`/`filegraph`, `trace.txt`, `timeline.*`, `execution_*`, `*provenance*`, `ro-crate-metadata.json`, `cwl.output.json`, `*summary*.tsv`). For anything auto-detection misses, tag it explicitly — this is the authoritative marker:

```sh
dochist artifact-add METHODS.md --role provenance
```

The section is emitted in Markdown and under `fair.interoperable.provenance_documents` in JSON. This is deliberately tool-agnostic — it works the same for Snakemake, Nextflow, CWL, or a hand-written methods file.

## Software environments (conda, mamba, pixi, venv)

For a session to be reusable, the report needs to record *what software* ran, not just which commands. dochist captures the active package-manager environment in two ways.

**Per command, automatically.** Every `dochist run` records the environment detected from its variables — conda/mamba (`CONDA_DEFAULT_ENV`, `CONDA_PREFIX`), [pixi](https://pixi.sh) (`PIXI_ENVIRONMENT_NAME`, `PIXI_PROJECT_NAME`; pixi also sets `CONDA_PREFIX`, and dochist labels it as pixi), and Python virtualenvs (`VIRTUAL_ENV`). The FAIR report's **Software environments** section then shows which environment each command ran under. `dochist env show` prints what is detected right now.

```sh
pixi shell                       # or: conda activate bio
dochist run -- bwa mem ref.fa reads.fq   # recorded as running under pixi:default / conda:bio
```

Detection reads the variables dochist itself inherits, so activate the environment *before* invoking dochist. Wrapping activation inside the run — `dochist run -- 'conda run -n bio bwa ...'` or `dochist run -- 'pixi run bwa ...'` — still executes correctly, but those variables live only in the child process, so use `dochist env snapshot` (below) to record that environment explicitly.

**As a full export, on demand.** `dochist env snapshot` captures the complete environment specification as a tracked, checksummed artifact:

```sh
dochist env snapshot                       # auto-detects the manager and export command
dochist env snapshot -m conda -c "conda env export -n bio"   # force manager / command
dochist env snapshot -o environment.yml    # choose the output filename
```

By manager the default export is `conda env export` → `environment.yml`, the mamba/micromamba binary's `env export` for mamba, `pixi list` → `environment-pixi.txt`, and `pip freeze` → `requirements.txt` otherwise. Any authoritative manifest/lock files present in the store root (`pixi.lock`, `pixi.toml`, `conda-lock.yml`, `environment.yml`, `requirements.txt`) are registered as artifacts too, since the lockfile is the reproducible source of truth. The snapshots appear in the report's **Software environments** section and under `fair.reusable.environment_snapshots` in JSON.

### Tool versions

Every `dochist run` also fingerprints the programs the command invokes — the first word of each pipeline stage and `&&` / `;` list element, skipping shell builtins and `VAR=value` prefixes. Wrappers (`time`, `env`, `nice`, `nohup`, `sudo`, `timeout`, `stdbuf`, `ionice`, `exec`, `command`) are looked through to the program they run, including options that take a value, so `nice -n 5 sort` records `sort` and `sudo -u alice make` records `make`. `xargs` and GNU `parallel` are treated the same way, so `find … | xargs -P 4 gzip` records `find` and `gzip`, and `parallel -j 8 'gzip -k {}' ::: *.fq` records `gzip`. Before the command runs, each tool is resolved on `PATH` exactly as the shell would, and dochist records:

- the resolved executable path (symlinks followed)
- the executable's SHA-256
- the tool's version line, and which probe produced it. Tools disagree on how to report a version, so dochist tries `--version`, `-V`, `-v` and a `version` subcommand, then falls back to the `--help` and `-h` banners. Output from a version flag is accepted if a line contains a dotted number such as `0.7.17`, as with `bwa`'s usage banner. Help text is full of unrelated numbers such as defaults and thresholds, so there a line must say "version" or put the number straight after the tool name (`mapper v2.4.1`). Each probe runs in a temporary directory with no stdin and a 3-second timeout, and dochist stops trying new probes after 8 seconds per tool.

```sh
dochist run -- "samtools view -b in.sam | samtools sort -o out.bam && go run ./report"
dochist log
# [cmd-0001] ... | samtools view -b in.sam | samtools sort -o out.bam && go run ./report
#     tool samtools: samtools 1.19 (/opt/conda/envs/bio/bin/samtools)
#     tool go: go version go1.24.7 linux/amd64 [via version] (/usr/local/go/bin/go)
```

Tools are fingerprinted **before** the command runs, so the record describes the binaries that actually executed, even if the command later upgrades them. Once the command finishes, a second pass fills two gaps:

- **`PATH` changed inside the command** (`conda activate bio; bwa ...`, `export PATH=...; tool`). On Unix, dochist runs the command in a way that makes its shell report the `PATH` it ended with, and passes on the command's own exit status unchanged. If that `PATH` differs from dochist's, every tool is looked up again on it. Any tool that resolves to a different executable, such as the env's `bwa` rather than `/usr/bin/bwa`, is fingerprinted and version-probed with that `PATH`, and marked `"resolution": "command_path"`. The recorded command line stays exactly as you typed it. A command that calls `exit` itself or stops early under `set -e` skips the report and falls back to dochist's own `PATH`, as does `cmd.exe` on Windows. dochist uses the final `PATH` for every tool, so in `bwa ...; conda activate other` it would record the wrong `bwa`.
- **The command installs or builds the tool** (`conda install -y samtools && samtools ...`, `make && ./mytool`). Tools that couldn't be found before are retried and marked `"resolution": "after_run"`.

Both markers mean the fingerprint was taken after the command ran. `dochist log` and the reports show them as "resolved on the command's PATH" and "resolved after run".

#### Shell scripts and Snakemake workflows

A command like `bash pipeline.sh` or `snakemake -j 8` runs a single program, but the tools that matter for provenance are the ones the script or workflow runs. dochist reads these files statically before the command runs (nothing is executed) and records the tools inside them, each tagged with the file that invokes it (`from pipeline.sh`):

- **Shell scripts**: `bash|sh|zsh|dash|ksh script.sh`, `bash -c '…'`, `source x.sh` / `. x.sh`, and scripts run directly (`./run.sh`) when they have a shell shebang and live inside the working directory. Scripts that call other scripts are followed (up to 5 levels deep, with cycle protection). The parser understands comments, `if`/`then`/`do` lines, `case` patterns, `[[ … ]]`, `(( … ))`, here-documents and shell functions, so `usage() { … }` or `ont_r9|ont_r10) ;;` are not mistaken for programs.
- **Snakemake**: the Snakefile is found the way Snakemake finds it (`-s` / `--snakefile`, then `Snakefile`, `workflow/Snakefile`). Every `shell:` directive and `shell(…)` call in it is scanned, as are `include:`d `.smk` files, `.sh` files named by `script:`, and `configfile:` / `--configfile` files.

The script, Snakefile, included files, `conda:` environment files and config files are recorded too, with their SHA-256 (version shown as "shell script", "Snakemake workflow file", "conda environment file" or "Snakemake config file"), so the report pins the exact workflow definition that ran.

##### What the workflow actually ran

Reading the Snakefile only says which tools a workflow *could* use. When a command runs Snakemake, dochist also reads the run records Snakemake writes to `.snakemake/metadata/` (in the working directory, or the one given with `-d` / `--directory`) once the command finishes, and keeps the jobs that ran during it:

- **Jobs**: one entry per job with the rule, inputs, outputs, log files, duration, and the **rendered shell command** with wildcards filled in (for example `bwa mem ref.fa sampleA.fq > sampleA.bam`). They are saved in the session's command record (`jobs`), shown by `dochist log` and `dochist browse` (where `/` also matches rules and commands), and listed in the report (a "Workflow jobs" table in Markdown and HTML, `reusable.workflow_jobs` in JSON). A rerun where every output was already up to date records no jobs, so skipped rules are never claimed. A job that started but was not marked finished is flagged `incomplete`.
- **Tools inside conda environments**: with `--use-conda`, a job's tools live in `.snakemake/conda/<hash>`, not on your `PATH`. After the run dochist looks up each program a job ran in that job's environment, probes its version there, and records which conda package provided it from the environment's `conda-meta` (for example `samtools 1.19 h50ea8bc_0 (bioconda)`). These tools are marked "resolved in the job's conda environment". If no version flag works, or probing is off, the package version is used. A tool of the same name on your system `PATH` is kept as a separate entry.
- **Containers**: the job's container image is recorded; tools inside containers are not versioned.

Both pieces come from Snakemake's own records, so they need a run of this dochist version; they are not reconstructed for earlier sessions. At most 10,000 jobs are kept per command, each command truncated to 4 KB, and rendered reports list the first 200 (the session file keeps them all).

The static part is best-effort. Commands built from variables (`$tool …`), `eval`, `run:` blocks that compute the command, and job lists piped into `parallel` (as in `echo "tool …" >> jobs.txt; parallel < jobs.txt`) cannot be resolved from the files alone. For Snakemake the jobs it ran and the conda environments it used are read back after the run (see above), so conda-only tools are located and versioned then; before the first run those environments do not exist yet, and tools inside containers are recorded as "not found on `PATH`".

A version is probed once per distinct binary. Later commands that use the same path with the same checksum reuse it. Pass `--no-version-probe` (or set `DOCHIST_NO_VERSION_PROBE=1`) to skip running the tools, for example when a tool might treat `-v` or `version` as real input. The path and checksum are still recorded. The tools appear in the report's **Software environments** section, per command in the session JSON (`commands[].tools`), and aggregated under `fair.reusable.tools` in the JSON report. Programs referenced through variables (`$TOOL args`) cannot be resolved statically and are not recorded. Commands run inside `dochist tui` are fingerprinted too (see [Live TUI](#live-tui-dochist-tui)).

## Saving and reloading sessions

Sessions live under `.dochist/sessions/` as self-contained JSON documents.

```sh
# Export the active session to a portable file
dochist save --output my-analysis.dochist.json

# ...later, possibly in another directory or on another machine:
dochist load my-analysis.dochist.json   # becomes the active session
dochist run -- next-step.sh             # history continues where it left off
```

Multiple sessions can coexist in one store; switch between them:

```sh
dochist sessions          # list all sessions ('*' marks the active one)
dochist resume other-work # make another session active
dochist end               # close the active session
```

An ended session refuses new `run` commands until it is resumed, so a finished record cannot be accidentally amended.

### Concurrent sessions (and tmux)

dochist sessions are switchable records, not concurrently-live processes like tmux sessions — there is one active session (`HEAD`) per store, and `resume` switches it. Two mechanisms make concurrent use safe:

- **`--session <name>` (global flag)** targets a specific session for a single command *without* changing `HEAD`. So two terminals or tmux panes can log to different sessions in the same store at once — `dochist run --session build -- …` in one pane, `dochist run --session analysis -- …` in another — without fighting over the active pointer.
- **Advisory file locking.** Each session takes an exclusive lock for the duration of any operation that modifies it, so concurrent `dochist run` invocations into the *same* session serialize instead of racing (no lost records). Writes are also atomic (temp-file + rename), so a reader never sees a half-written session. Locks are per session name, so different sessions never block each other. If a session is momentarily busy, dochist prints `waiting…` and proceeds once the lock frees.

One caveat remains for *truly overlapping* commands: `dochist run` detects artifacts by snapshotting the whole store tree before/after, so two commands executing at the same instant in the same directory tree can misattribute each other's file changes. For genuinely parallel work, give each stream its own directory (hence its own `.dochist/` store, discovered by walking up from the working directory) — that isolates both the snapshots and the active session.

## Browsing a session (`dochist browse`)

`dochist browse` opens an interactive terminal UI for exploring a session's command history and artifact provenance without paging through `dochist log` / `dochist artifacts` output:

```sh
dochist browse                  # browse the active session
dochist browse --session other  # browse a named session, without changing HEAD
```

- `Tab` / `Shift+Tab` — switch between the Commands and Artifacts tabs
- `j`/`k` or `↑`/`↓` — move the selection; `g`/`G` or `Home`/`End` jump to the first/last item
- `/` — filter the list by substring (command text/id or tool version, e.g. `/3.15`; or artifact path); `Esc` clears it, `Enter` keeps it and resumes navigating
- `PageUp`/`PageDown` — scroll the detail pane (e.g. long stdout/stderr tails)
- `r` — reload the session from disk (useful if it's still active in another terminal)
- `q` / `Esc` / `Ctrl+C` — quit

A command's detail pane lists the tools it invoked: each one's version (and how it was found), its resolved path, and its checksum.

## Live TUI (`dochist tui`)

`dochist tui` opens a real, interactive shell in a terminal UI, with a side panel that updates live as you work — the commands you run and the artifacts they produce appear next to the shell as they happen, instead of only after the fact via `dochist log`:

```sh
dochist tui                      # requires an active session; dochist init first
dochist tui --no-version-probe   # record tool paths/checksums without running --version
```

Layout: the shell fills the main pane (colors, `$EDITOR`, curses apps like `vim`/`htop` all work normally — it's a full PTY, not a captured/replayed transcript); the side panel shows the session's Commands and Artifacts, auto-scrolled to the latest. Press **F10** to exit — this ends the wrapped shell, like closing a terminal tab; everything recorded up to that point stays in the session.

Per-command tracking is automatic for **bash** and **zsh**: dochist injects a `preexec`/`precmd`-style hook (in the spirit of the OSC 133 shell-integration sequences used by iTerm2, VS Code, and others) that reports each command's boundaries privately, so the store gets snapshotted before/after exactly as `dochist run` does — artifacts get attributed to the command that produced them, and the active conda/mamba/pixi/venv environment is captured per command too. The tools each command invokes are fingerprinted as with [`dochist run`](#tool-versions), but resolved on your interactive shell's own `PATH`. That means an environment you `conda activate` at the prompt is picked up automatically, and so is a `PATH` change made inside the command line. Fingerprinting runs in the background while the command runs, so it never delays the prompt. The side panel shows each command's tool versions (`↳ fastqc 0.12.1 · samtools 1.19`). Your normal `~/.bashrc` / `~/.zshrc` still loads. Other shells (fish, plain `sh`, `cmd.exe`, ...) still get a fully working terminal — just without automatic per-command records; use `dochist run` there instead.

Known limitations: `stdout`/`stderr` tails aren't captured into the session for commands run this way (they're visible live on screen, just not embedded in the FAIR report as text) — use `dochist run` when you need that. Command-boundary detection is best-effort shell scripting, not a kernel-level guarantee. Tool fingerprinting runs alongside the command rather than strictly before it, so a tool that the same command line installs (`pip install x && x`) may be recorded as already present instead of `resolved after run`.

## The FAIR report

`dochist report` produces a document organised around the FAIR principles:

- **Findable** — globally unique session identifier, per-artifact SHA-256 content checksums, rich metadata.
- **Accessible** — plain files and UTF-8 JSON, portable export/import.
- **Interoperable** — JSON session schema, MIME media types, qualified artifact→command references.
- **Reusable** — declared license, complete command history, execution environment, and a reproduction script.

Markdown output is for humans; `--format json` emits a machine-readable version embedding the full session document.

## Extracting a reproduction script

The FAIR report's reproduction script is a literal, unfiltered replay of everything that happened — failed attempts and debugging one-offs included. `dochist extract` turns a session into a curated, runnable script instead:

```sh
dochist extract                          # successful commands only, in order, to stdout
dochist extract -o pipeline.sh           # same, written to a file and made executable
dochist extract --include-failed         # keep non-zero-exit commands too
dochist extract --only assembly/scaffolds.fasta   # only commands that created/modified this artifact
dochist extract --with-env               # annotate with `# [manager:env]` wherever the environment changes
```

Multiple sessions can be combined with `--merge <file>` (repeatable, using files from `dochist save`), interleaving all sessions' commands by start time:

```sh
dochist extract --merge qc-session.dochist.json --merge assembly-session.dochist.json -o pipeline.sh
```

`--only` restricts to commands that directly produced or touched the given artifact path(s) — dochist records what each command *output*, not what it *read*, so this prunes dead-end explorations but doesn't build a full input/output dependency graph; use `dochist browse`'s Artifacts tab to trace less obvious chains by hand.

## Command reference

| Command | Description |
|---|---|
| `dochist init <name> [-d DESC]` | Start a new session in the current directory |
| `dochist run [--no-version-probe] -- <command>` | Run a command, logging it, its artifacts, and the versions of the tools it invokes |
| `dochist log [-n N]` | Show command history |
| `dochist status` | Show active session summary |
| `dochist prompt [--format prefix\|suffix\|prompt\|title]` | Print session name for shell/tmux integration (silent outside a session) |
| `dochist artifacts` | List tracked artifacts with provenance |
| `dochist browse` | Interactive TUI to browse command history and artifacts |
| `dochist tui [--no-version-probe]` | Live TUI: a real shell with a side panel tracking commands, tool versions and artifacts (F10 to exit) |
| `dochist artifact-add <path> [--role R]` | Manually register a file as an artifact (optionally tagging a role, e.g. `provenance`) |
| `dochist meta set <key> <value>` | Set FAIR metadata (license, author, ...) |
| `dochist meta show` | Show session metadata |
| `dochist env show` | Show the detected package-manager environment |
| `dochist env snapshot [-m M] [-c CMD] [-o FILE]` | Capture an environment export as an artifact |
| `dochist report [-f markdown\|json\|html\|pdf] [-o FILE]` | Generate the FAIR compliance document (PDF requires wkhtmltopdf) |
| `dochist extract [-o FILE] [--only PATH]... [--include-failed] [--with-env] [--merge FILE]...` | Extract a curated, runnable reproduction script (successful commands only, by default) |
| `dochist save [-o FILE]` | Export the session to a portable file |
| `dochist load <file>` | Import a saved session and make it active |
| `dochist sessions` | List all sessions in the store |
| `dochist resume <name>` | Make an existing session active |
| `dochist end` | Mark the active session as ended |
| `dochist update [--check] [-y\|--yes]` | Check GitHub for a newer dochist release and install it (`--check` only reports, `-y` skips the confirmation prompt) |

The global `--session <name>` (`-s`) flag makes any command operate on a named session instead of the active one, without changing `HEAD` — useful for concurrent use across terminals or tmux panes.

## Shell and terminal integration

`dochist prompt` prints the active session name — or nothing when outside a store — and always exits 0, so it is safe to embed in any shell prompt. The `--format` flag selects the output style.

| Format | Output | Use case |
|---|---|---|
| `prefix` | `(dochist:name) ` | Prepend to PS1 — matches conda/pixi parenthesis style |
| `suffix` | ` (dochist:name)` | Append to PS1 before `$` |
| `prompt` | ` ● dochist:name` | zsh RPROMPT or tmux right status (default) |
| `title` | OSC title-bar escape | Terminal tab/window title via PROMPT_COMMAND |

### zsh right prompt (`prompt` — recommended)

```sh
# ~/.zshrc
RPROMPT='$(dochist prompt --format prompt 2>/dev/null)'
```

### bash / zsh left prompt prefix

```sh
# ~/.bashrc or ~/.zshrc  (prefix — before conda/pixi)
PS1='$(dochist prompt --format prefix 2>/dev/null)'"$PS1"

# or suffix — after the path, before $
PS1="${PS1%\\$}"'$(dochist prompt --format suffix 2>/dev/null)'"\\$"
```

### Terminal tab / window title

```sh
# bash — ~/.bashrc
PROMPT_COMMAND='printf "%s" "$(dochist prompt --format title 2>/dev/null)"'

# zsh — ~/.zshrc
precmd() { print -Pn "%{$(dochist prompt --format title 2>/dev/null)%}" }
```

### tmux status bar or pane border

```sh
# ~/.tmux.conf

# Option A — right side of the status bar
set -g status-right '#(cd #{pane_current_path}; dochist prompt --format prompt 2>/dev/null)  %H:%M'

# Option B — pane border title (visible when panes are split)
set -g pane-border-status bottom
set -g pane-border-format ' #(cd #{pane_current_path}; dochist prompt --format prompt 2>/dev/null) '
```

The indicator disappears automatically when you leave a store directory or end a session, leaving your prompt exactly as it was.

## Development

```sh
cargo test                                  # unit + end-to-end tests
cargo clippy --all-targets -- -D warnings   # lints
cargo fmt --all --check                     # formatting
```

CI runs formatting, clippy, docs, and the test suite on Linux, macOS, and Windows for every push and pull request. Pushing a version tag (`git tag v0.1.0 && git push origin v0.1.0`) triggers the release workflow, which builds binaries for all supported platforms and publishes them — with SHA-256 checksums — to the Releases page.

## License

[MIT](LICENSE)
