#!/usr/bin/env bash
#
# merge-pr.sh — merge the open pull request for the current branch, but only when
# scripts/quality-gate.sh passes green AND the pull request's head is exactly the
# commit the gate covered.
#
# Why a command and not an automatic trigger:
#   Same reason as scripts/open-pr.sh — the gate runs many times while work is in
#   progress, so firing on every green run would land work in progress on main.
#   Here the stakes are higher: `main` is what the marketplace publishes, so a
#   bad merge is a broken install for anyone who reloads plugins. You say when,
#   the gate and the pull request's own state say whether.
#
#   `main` carries no branch protection and the repository has no required
#   checks, so nothing on GitHub's side would refuse a premature merge. That
#   makes the checks below the only gate there is, which is exactly why they are
#   explicit and why every one of them names its own refusal.
#
# The decisive check is the sha:
#   The gate covers a local commit. Merging is a claim about a REMOTE ref. Those
#   are the same thing only when the pull request's head sha equals local HEAD —
#   otherwise something was pushed, or amended, since the gate ran, and the merge
#   would land content nothing verified. Every other check here is cheap; this
#   one is the reason the script exists.
#
# Refuses, before any write:
#   - on the base branch, on a dirty tree (as open-pr.sh does)
#   - no open pull request for this branch
#   - the pull request is a draft
#   - it is not MERGEABLE, or its merge state is not CLEAN
#   - its head sha is not local HEAD
#   - any status check is failing
#
# Convention it follows: a merge commit (never squash, never rebase) with the
# subject `merge: <pull request title> (#<number>)`, matching every merge already
# in this history. The merged branch is deleted on the remote — its commits live
# in the base branch afterwards — unless --keep-branch is passed.
#
# Usage:
#   scripts/merge-pr.sh [--keep-branch] [--dry-run]
#
#   --dry-run  runs every refusal check and the gate, prints the `gh pr merge`
#              command it would run, and exits without writing anything. This is
#              what the test suite exercises.
#
# Overrides, for tests only:
#   PROXYME_GATE_CMD  command run in place of scripts/quality-gate.sh
#   PROXYME_PR_JSON   literal JSON used in place of the `gh pr view` call
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "merge-pr: not inside a git repository" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

KEEP_BRANCH=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --keep-branch) KEEP_BRANCH=1; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     sed -n '2,50p' "$0"; exit 0 ;;
    *) echo "merge-pr: unknown argument: $1" >&2; exit 2 ;;
  esac
done

die() { echo "merge-pr: $*" >&2; exit 1; }

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || die "detached HEAD — check out a branch first"

BASE="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
[ -n "$BASE" ] || BASE=main
[ "$BRANCH" != "$BASE" ] || die "on $BASE — there is no pull request to merge from the base branch"

if [ -n "$(git status --porcelain)" ]; then
  git status --short >&2
  die "working tree is dirty — the gate would not describe what gets merged"
fi

# --- the pull request's own state ---------------------------------------------
if [ -n "${PROXYME_PR_JSON:-}" ]; then
  PR_JSON="$PROXYME_PR_JSON"
else
  PR_JSON="$(gh pr view --json number,title,state,isDraft,mergeable,mergeStateStatus,headRefOid,statusCheckRollup 2>/dev/null)"
fi
[ -n "$PR_JSON" ] || die "no pull request found for $BRANCH — open one first: scripts/open-pr.sh"

pr_field() { printf '%s' "$PR_JSON" | jq -r "$1 // empty"; }

PR_NUM="$(pr_field .number)"
PR_TITLE="$(pr_field .title)"
PR_STATE="$(pr_field .state)"
PR_DRAFT="$(pr_field .isDraft)"
PR_MERGEABLE="$(pr_field .mergeable)"
PR_MERGESTATE="$(pr_field .mergeStateStatus)"
PR_HEAD="$(pr_field .headRefOid)"

[ -n "$PR_NUM" ] || die "no pull request found for $BRANCH — open one first: scripts/open-pr.sh"
[ "$PR_STATE" = "OPEN" ] || die "pull request #$PR_NUM is $PR_STATE, not OPEN"
[ "$PR_DRAFT" != "true" ] || die "pull request #$PR_NUM is a draft — mark it ready first"
[ "$PR_MERGEABLE" = "MERGEABLE" ] || \
  die "pull request #$PR_NUM is $PR_MERGEABLE — resolve that before merging"
[ "$PR_MERGESTATE" = "CLEAN" ] || \
  die "pull request #$PR_NUM merge state is $PR_MERGESTATE, not CLEAN"

# Failing checks, named. `neutral`, `skipped` and a still-running check are not
# successes: merging on a pending check is merging on an unknown.
FAILING="$(printf '%s' "$PR_JSON" \
  | jq -r '[.statusCheckRollup[]? | select((.conclusion // .state // "") as $c
      | $c != "SUCCESS" and $c != "NEUTRAL" and $c != "SKIPPED")
      | (.name // .context // "check")] | join(", ")')"
[ -z "$FAILING" ] || die "pull request #$PR_NUM has checks that are not passing: $FAILING"

# --- the decisive check --------------------------------------------------------
LOCAL_HEAD="$(git rev-parse HEAD)"
if [ "$PR_HEAD" != "$LOCAL_HEAD" ]; then
  die "pull request #$PR_NUM points at ${PR_HEAD:0:7}, local HEAD is ${LOCAL_HEAD:0:7} — the gate covers the local commit, so merging would land content nothing verified. Push first: scripts/open-pr.sh"
fi

# --- the condition: the gate ---------------------------------------------------
GATE_CMD="${PROXYME_GATE_CMD:-$REPO_ROOT/scripts/quality-gate.sh}"
echo "merge-pr: running the gate ($GATE_CMD)"
if ! $GATE_CMD; then
  die "gate is not green — pull request #$PR_NUM left open"
fi

# --- merge ---------------------------------------------------------------------
SUBJECT="merge: $PR_TITLE (#$PR_NUM)"
MERGE_ARGS="--merge --subject"
[ "$KEEP_BRANCH" = 1 ] || MERGE_ARGS="$MERGE_ARGS --delete-branch"

if [ "$DRY_RUN" = 1 ]; then
  echo "merge-pr: DRY RUN — nothing merged"
  if [ "$KEEP_BRANCH" = 1 ]; then
    echo "  gh pr merge $PR_NUM --merge --subject '$SUBJECT'"
  else
    echo "  gh pr merge $PR_NUM --merge --subject '$SUBJECT' --delete-branch"
  fi
  exit 0
fi

if [ "$KEEP_BRANCH" = 1 ]; then
  gh pr merge "$PR_NUM" --merge --subject "$SUBJECT" || die "merge refused by GitHub"
else
  gh pr merge "$PR_NUM" --merge --subject "$SUBJECT" --delete-branch || die "merge refused by GitHub"
fi

echo "merge-pr: merged #$PR_NUM into $BASE"
