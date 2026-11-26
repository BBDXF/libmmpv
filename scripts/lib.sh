#!/usr/bin/env bash
# Shared helpers. Source me; do not execute.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/upstream.lock"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

SRC_DIR="${SRC_DIR:-$ROOT/build/src}"

# read_opts FILE -> one option per line (comments/blank stripped)
read_opts() {
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true
}

# parse_target TARGET -> sets OS (linux|windows), ARCH (x86_64|arm64), TRIPLE
parse_target() {
  case "$1" in
    linux-x86_64) OS=linux;   ARCH=x86_64; TRIPLE= ;;
    linux-arm64)  OS=linux;   ARCH=arm64;  TRIPLE= ;;
    win-x86_64)   OS=windows; ARCH=x86_64; TRIPLE=x86_64-w64-mingw32 ;;
    win-arm64)    OS=windows; ARCH=arm64;  TRIPLE=aarch64-w64-mingw32 ;;
    *) die "unknown target '$1' (linux-x86_64|linux-arm64|win-x86_64|win-arm64)" ;;
  esac
  if [ "$ARCH" = arm64 ]; then FF_ARCH=aarch64; else FF_ARCH=x86_64; fi
}

check_profile() {
  case "$1" in music|video) ;; *) die "unknown profile '$1' (music|video)";; esac
}
