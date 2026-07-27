#!/usr/bin/env bash
# Drives a scripted dochist walkthrough for an asciinema recording. Not meant
# to be run outside that context: it sets up its own throwaway scratch
# directory (never the repo working tree) and uses the fake pipeline tools in
# demo/fake-tools/ so the demo is reproducible without real bioinformatics
# tools installed. See demo/README.md for how to (re-)record it.
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$DEMO_DIR/fake-tools:$PATH"
export TERM="${TERM:-xterm-256color}"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/dochist-demo.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

clear

# Simulate a human typing the command, then actually run it.
type_cmd() {
  local cmd="$1"
  printf '\033[1;32m$\033[0m '
  local i
  for ((i = 0; i < ${#cmd}; i++)); do
    printf '%s' "${cmd:$i:1}"
    sleep 0.02
  done
  printf '\n'
  sleep 0.3
  eval "$cmd"
}

touch sample.fastq.gz

type_cmd "dochist init rnaseq-batch3 -d 'QC and assembly for batch 3'"
sleep 1.5

type_cmd "dochist run -- fastqc sample.fastq.gz"
sleep 1

type_cmd "dochist run -- spades.py -s sample.fastq.gz -o assembly/"
sleep 1

type_cmd "dochist meta set license MIT"
sleep 0.8

type_cmd "dochist log"
sleep 1.8

type_cmd "dochist artifacts"
sleep 2.2

type_cmd "dochist report --output FAIR-report.md"
sleep 2

clear
printf 'Browsing the session with \033[1mdochist browse\033[0m ...\n\n'
sleep 1.2
python3 "$DEMO_DIR/pty_type.py" \
  --steps '[[1.6,"TAB"],[1.6,"TAB"],[1.2,"/spades"],[1.4,"ENTER"],[1.2,"q"]]' \
  --settle 1.0 \
  -- dochist browse

clear
printf 'Full command reference: https://github.com/motroy/dochist#command-reference\n'
sleep 2
