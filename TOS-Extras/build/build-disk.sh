#!/bin/sh
# Build the Optional Utilities disk from TOS-Extras (POSIX wrapper).
#
# Usage:  TOS-Extras/build/build-disk.sh [--install <dir>]
#
# Output: TOS-Extras/dist/optional-utilities
# --install also copies the disk contents into <dir> — point it at an
# OpenComputers floppy folder (saves/<world>/opencomputers/<address>/)
# to "burn" the disk in one step.

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
EXTRAS_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

command -v lua >/dev/null 2>&1 || {
  echo "error: lua not found in PATH" >&2
  exit 1
}

exec lua "$SCRIPT_DIR/build-disk.lua" "$EXTRAS_DIR" "$EXTRAS_DIR/dist/optional-utilities" "$@"
