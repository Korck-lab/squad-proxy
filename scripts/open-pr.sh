#!/usr/bin/env bash
#
# open-pr.sh — push the current branch and open its pull request, but only when
# scripts/quality-gate.sh passes green.
#
# Why a command and not a hook:
#   The gate runs many times while work is in progress — a single session can
#   green it half a dozen times before the change is finished. An automation
#   that fired on every green run would push work in progress to a public
#   repository and open a pull request for it. So the trigger is explicit and
#   the CONDITION is the gate: you say when, the gate says whether.
#
#   Git also has no post-push hook, and a pre-push hook runs before the remote
#   ref exists — `gh pr create` there would target a branch GitHub has not seen.
#
# What enforces the gate:
#   This script runs `scripts/quality-gate.sh` and stops on a nonzero exit, then
#   pushes. The push is where enforcement actually lives: `.git/hooks/pre-push`
#   runs `scripts/prepush-guard.sh`, which demands a receipt covering exactly
#   this commit, written over a clean tree. That check is NOT duplicated here —
#   one definition of "gated", in the guard, whichever path reaches the remote.
#
# Refuses, before touching the network:
#   - on the default branch (a pull request needs a branch to come from)
#   - on a dirty tree (the receipt would be marked dirty and the push blocked
#     anyway, but failing here names the reason instead of the symptom)
#   - with nothing ahead of the base (an empty pull request)
#
# Idempotent: when a pull request already exists for the branch, the commits are
# pushed and the existing URL is reported. It never merges and never closes.
#
# Usage:
#   scripts/open-pr.sh [--base <branch>] [--title <text>] [--body-file <path>]
#                      [--dry-run]
#
#   --dry-run  runs every refusal check and the gate, prints the push and
#              `gh` commands it would run, and exits without touching the
#              network. This is what the test suite exercises.
#
# Overrides, for tests only:
#   PROXYME_GATE_CMD  command run in place of scripts/quality-gate.sh
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "open-pr: not inside a git repository" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

BASE=""
TITLE=""
BODY_FILE=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --base)      BASE="${2:-}"; shift 2 ;;
    --title)     TITLE="${2:-}"; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   sed -n '2,45p' "$0"; exit 0 ;;
    *) echo "open-pr: unknown argument: $1" >&2; exit 2 ;;
  esac
done

die() { echo "open-pr: $*" >&2; exit 1; }

# --- who we are ---------------------------------------------------------------
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || die "detached HEAD — check out a branch first"

if [ -z "$BASE" ]; then
  # The remote's default branch when it is knowable, else main. Not $BRANCH.
  BASE="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  [ -n "$BASE" ] || BASE=main
fi

[ "$BRANCH" != "$BASE" ] || \
  die "on $BASE — a pull request needs a branch to come from. Create one: git checkout -b <name>"

# --- refuse a dirty tree ------------------------------------------------------
# The gate stamps its receipt `dirty: true` here and the pre-push guard blocks
# the push. Failing now names the cause rather than making the guard report the
# consequence three steps later.
if [ -n "$(git status --porcelain)" ]; then
  git status --short >&2
  die "working tree is dirty — commit or stash before opening a pull request"
fi

# --- refuse an empty pull request --------------------------------------------
# Compared against the base as the REMOTE has it when that ref exists: a local
# base branch can lag behind and make a real change look empty.
BASE_REF="$BASE"
git rev-parse --verify --quiet "refs/remotes/origin/$BASE" >/dev/null && BASE_REF="origin/$BASE"
AHEAD="$(git rev-list --count "$BASE_REF..HEAD" 2>/dev/null || echo 0)"
[ "$AHEAD" -gt 0 ] || die "nothing ahead of $BASE_REF — no commits to open a pull request for"

# --- the condition: the gate ---------------------------------------------------
GATE_CMD="${PROXYME_GATE_CMD:-$REPO_ROOT/scripts/quality-gate.sh}"
echo "open-pr: running the gate ($GATE_CMD)"
if ! $GATE_CMD; then
  die "gate is not green — nothing pushed, no pull request opened"
fi

# --- title and body ------------------------------------------------------------
[ -n "$TITLE" ] || TITLE="$(git log -1 --pretty=%s)"

BODY_ARGS=""
if [ -n "$BODY_FILE" ]; then
  [ -f "$BODY_FILE" ] || die "body file not found: $BODY_FILE"
  BODY_ARGS="--body-file $BODY_FILE"
else
  # The commit bodies are the change's own description; anything better than
  # that belongs in --body-file, written deliberately.
  BODY_ARGS="--body-file -"
fi

# --- push, then create or report ------------------------------------------------
EXISTING="$(gh pr list --head "$BRANCH" --state open --json url --jq '.[0].url' 2>/dev/null)"

if [ "$DRY_RUN" = 1 ]; then
  echo "open-pr: DRY RUN — nothing pushed, no pull request opened"
  echo "  git push -u origin $BRANCH"
  if [ -n "$EXISTING" ]; then
    echo "  (pull request already open: $EXISTING — would push only)"
  else
    echo "  gh pr create --base $BASE --head $BRANCH --title '$TITLE' $BODY_ARGS"
  fi
  exit 0
fi

git push -u origin "$BRANCH" || die "push refused — see the pre-push guard's reason above"

if [ -n "$EXISTING" ]; then
  echo "open-pr: pull request already open, commits pushed to it: $EXISTING"
  exit 0
fi

if [ -n "$BODY_FILE" ]; then
  gh pr create --base "$BASE" --head "$BRANCH" --title "$TITLE" --body-file "$BODY_FILE"
else
  git log "$BASE_REF..HEAD" --reverse --pretty=%b \
    | gh pr create --base "$BASE" --head "$BRANCH" --title "$TITLE" --body-file -
fi
