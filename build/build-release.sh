#!/usr/bin/env bash
# Build TOS-Release from TOS-Dev.
#
# Usage:  bash TOS-Dev/build/build-release.sh
#
# Resolves its own location, then runs strip.lua with the canonical
# Release-build excludes (dev-only trees that should never ship):
#   /build/            the build tool itself
#   /usr/lib/tests/    development unit tests (excluded from manifest too)
#   /run_tests.sh      the dev test runner (don't ship a runner with no tests)
#   /.claude/          editor/agent settings
#
# After the walk, strip.lua auto-prunes /tos/system_manifest.lua so any
# manifest entry whose target file isn't in the dist tree is dropped.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$DEV_DIR/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/TOS-Release"

if ! command -v lua >/dev/null 2>&1; then
  echo "error: lua not found in PATH" >&2
  echo "       install with:  winget install DEVCOM.Lua    (Windows)" >&2
  echo "                      apt install lua5.3            (Debian/Ubuntu)" >&2
  exit 1
fi

# Wipe any stale dist tree so we never inherit files that no longer exist in Dev.
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

cd "$ROOT_DIR"

# Windows/Git-Bash (MSYS) gotcha: a native `lua` needs Windows-form path args,
# and MSYS otherwise rewrites the /build/-style --exclude patterns into
# C:/Program Files/Git/build/ before lua sees them — so NOTHING is excluded and
# the Release silently ships the dev tests + build tooling. On MSYS we convert
# the path args to mixed (forward-slash) Windows form and set
# MSYS2_ARG_CONV_EXCL='*' so the patterns pass through verbatim. On real POSIX
# this branch is skipped and nothing changes. (The native wrapper is
# build-release.cmd; this keeps the .sh correct under Git Bash too.)
LUA_DEV="$DEV_DIR"
LUA_REL="$RELEASE_DIR"
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    if command -v cygpath >/dev/null 2>&1; then
      LUA_DEV="$(cygpath -m "$DEV_DIR")"
      LUA_REL="$(cygpath -m "$RELEASE_DIR")"
    fi
    export MSYS2_ARG_CONV_EXCL='*'
    ;;
esac

lua "$LUA_DEV/build/strip.lua" "$LUA_DEV" "$LUA_REL" --minify \
    --exclude /build/ \
    --exclude /usr/lib/tests/ \
    --exclude /run_tests.sh \
    --exclude /run_tests.py \
    --exclude /todo_index.py \
    --exclude /.claude/ \
    --exclude /README.md \
    --exclude /CHANGELOG.md \
    --exclude /CONTRIBUTING.md \
    --exclude /ROADMAP.md \
    --exclude /Codenames.txt \
    --exclude /TODO.txt \
    --exclude /MANUAL.md \
    --exclude /EMULATOR_CHECKLIST.md

echo
echo "Release built at: $RELEASE_DIR"
