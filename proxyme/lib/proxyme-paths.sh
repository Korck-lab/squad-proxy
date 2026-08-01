#!/bin/bash
# proxyme — resolve project-scoped state paths.
#
# Prints eval-able shell assignments. Every proxyme skill sources this rather
# than re-deriving paths inline, so there is exactly one definition of where
# project state lives.
#
# Usage from a skill:
#   eval "$(bash "<plugin-root>/lib/proxyme-paths.sh")"
#
# Root resolution, in order:
#   1. nearest ancestor containing a .claude/ directory, stopping BEFORE $HOME
#   2. git toplevel
#   3. $PWD
#
# The walk stops before $HOME on purpose: $HOME/.claude always exists, so
# without the guard every repo that has no .claude/ of its own would resolve to
# $HOME and silently share one global state directory — the exact behaviour this
# file exists to remove.
#
# Deliberately no `pipefail`: the SID fallback pipes `tty`, which fails in every
# non-interactive shell (all subagents), and under pipefail + `set -e` that
# aborts the script before anything is printed.

set -eu

d="$PWD"
ROOT=""
while [ "$d" != "/" ] && [ "$d" != "$HOME" ]; do
  if [ -d "$d/.claude" ]; then ROOT="$d"; break; fi
  d=$(dirname "$d")
done
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] || ROOT="$PWD"

USER_NAME="${LOGNAME:-}"
[ -n "$USER_NAME" ] || USER_NAME="$(id -un)"

# CLAUDE_CODE_SESSION_ID is set by Claude Code. The tty fallback covers manual
# shell use; in a non-tty shell it hashes empty input to a constant, which is
# correct enough — that path never runs inside Claude Code.
SID="${CLAUDE_CODE_SESSION_ID:-}"
[ -n "$SID" ] || SID="$(tty 2>/dev/null | shasum | cut -c1-12)"
[ -n "$SID" ] || SID="nosession"

ROOT_HASH="$(printf '%s' "$ROOT" | shasum | cut -c1-12)"

cat <<EOF
PROXYME_ROOT="${ROOT}"
PROXYME_DIR="${ROOT}/.claude/proxyme"
PROXYME_IDENTITY="${ROOT}/.claude/proxyme/${USER_NAME}-identity.md"
PROXYME_CONFIG="${ROOT}/.claude/proxyme/config.json"
PROXYME_CARVEOUTS="${ROOT}/.claude/proxyme/carve-outs.md"
PROXYME_GLOBAL_IDENTITY="${HOME}/.claude/skills/proxyme/${USER_NAME}-identity.md"
PROXYME_GLOBAL_CONFIG="${HOME}/.claude/skills/proxyme/config.json"
PROXYME_USER="${USER_NAME}"
PROXYME_SID="${SID}"
PROXYME_FLAG="/tmp/proxyme-${ROOT_HASH}-${SID}.active"
EOF
