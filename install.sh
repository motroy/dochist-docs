#!/usr/bin/env sh
# dochist installer — downloads a pre-built, fully-static (musl) binary for Linux.
# No Rust toolchain or system libraries required.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/motroy/dochist-docs/main/install.sh | sh
#
# Override the install directory:
#   DOCHIST_INSTALL_DIR=/usr/local/bin sh install.sh
set -eu

# motroy/dochist is the private development repo; release binaries are
# mirrored to the public motroy/dochist-docs repo, so that's what this
# script (and anyone fetching it anonymously) needs to point at.
REPO="motroy/dochist-docs"
BIN="dochist"
INSTALL_DIR="${DOCHIST_INSTALL_DIR:-${HOME}/.local/bin}"

# ── OS check ──────────────────────────────────────────────────────────────────
OS=$(uname -s)
if [ "$OS" != "Linux" ]; then
  printf 'This installer only supports Linux.\nFor macOS/Windows, download from:\n  https://github.com/%s/releases\n' "$REPO" >&2
  exit 1
fi

# ── Architecture ──────────────────────────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)        TARGET="x86_64-unknown-linux-musl" ;;
  aarch64|arm64) TARGET="aarch64-unknown-linux-musl" ;;
  *)
    printf 'Unsupported architecture: %s\nPre-built binaries are only available for x86_64 and aarch64.\n' "$ARCH" >&2
    exit 1 ;;
esac

# ── Downloader ────────────────────────────────────────────────────────────────
if command -v curl >/dev/null 2>&1; then
  fetch()        { curl -fsSL "$1" -o "$2"; }
  fetch_stdout() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch()        { wget -qO  "$2" "$1"; }
  fetch_stdout() { wget -qO- "$1"; }
else
  echo "curl or wget is required but neither was found." >&2
  exit 1
fi

# ── Latest release tag ────────────────────────────────────────────────────────
TAG=$(fetch_stdout "https://api.github.com/repos/${REPO}/releases/latest" \
      | grep '"tag_name"' \
      | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')

if [ -z "$TAG" ]; then
  printf 'Could not determine the latest release.\nCheck https://github.com/%s/releases\n' "$REPO" >&2
  exit 1
fi

ARCHIVE="${BIN}-${TAG}-${TARGET}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE}"

# ── Download and install ──────────────────────────────────────────────────────
TMP=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT INT TERM

printf 'Installing %s %s for %s...\n' "$BIN" "$TAG" "$TARGET"
fetch "$URL" "${TMP}/${ARCHIVE}"
tar -xzf "${TMP}/${ARCHIVE}" -C "$TMP"

mkdir -p "$INSTALL_DIR"
install -m 755 "${TMP}/${BIN}-${TAG}-${TARGET}/${BIN}" "${INSTALL_DIR}/${BIN}"

printf '\nInstalled: %s/%s\n' "$INSTALL_DIR" "$BIN"

case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *)
    printf '\n%s is not in your PATH. Add it with:\n  export PATH="%s:$PATH"\n' "$INSTALL_DIR" "$INSTALL_DIR"
    ;;
esac
