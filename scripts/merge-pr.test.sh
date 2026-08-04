#!/usr/bin/env bash
#
# merge-pr.test.sh — proves scripts/merge-pr.sh refuses every state it claims to
# refuse, and that the gate and the head sha are genuinely conditions rather than
# steps it narrates.
#
# `main` has no branch protection and the repository requires no checks, so
# nothing on GitHub's side would refuse a premature merge. These arms are the
# only evidence that the script's own refusals work.
#
# Every arm builds a throwaway repository, copies the shipped script in, and runs
# it with --dry-run. Nothing here merges or reaches the network: the pull
# request's state is injected through PROXYME_PR_JSON and the gate through
# PROXYME_GATE_CMD, both documented test-only overrides. The `gh` binary is never
# called on this path, so the suite runs on a machine without it.
#
# The allow arms matter as much as the refuse arms: a script that refused
# everything would pass a refusal-only suite and never merge anything.
#
# Real-run evidence (skill-validation-before-merge): the ten arms below ran
# against the shipped script. The red-gate and stale-sha arms were seen refusing
# by name AND printing no `gh pr merge` line — a script that ran its checks,
# ignored them and merged anyway would still have printed the refusal text
# somewhere.
#
# Run:  ./scripts/merge-pr.test.sh
#
# Never touches the working tree — every arm lives under a mktemp -d removed on
# exit, including on failure and on interrupt.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/merge-pr.sh"

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this test" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

ARM=""; ARM_DIR=""; ARM_OUT=""; ARM_RC=0; ARM_ERRS=0
FAILED_ARMS=0; TOTAL_ARMS=0
HEAD_SHA=""

[ -x "$SCRIPT" ] || { echo "FAIL: script not executable: $SCRIPT" >&2; exit 1; }

new_arm() {
  ARM="$1"; ARM_DIR="$WORK/$ARM"; ARM_ERRS=0
  TOTAL_ARMS=$((TOTAL_ARMS+1))
  mkdir -p "$ARM_DIR/scripts"
  cp "$SCRIPT" "$ARM_DIR/scripts/merge-pr.sh"
  git -C "$ARM_DIR" init -q -b main
  git -C "$ARM_DIR" config user.email fixture@example.invalid
  git -C "$ARM_DIR" config user.name Fixture
  echo base > "$ARM_DIR/file.txt"
  git -C "$ARM_DIR" add -A && git -C "$ARM_DIR" commit -qm "initial"
  git -C "$ARM_DIR" checkout -q -b feature
  echo change > "$ARM_DIR/file.txt"
  git -C "$ARM_DIR" commit -qam "feat: the change under test"
  HEAD_SHA="$(git -C "$ARM_DIR" rev-parse HEAD)"
}

# pr_json [head-sha] — the healthy pull request every arm starts from. Arms
# override single fields through jq rather than restating the whole object, so a
# field added to the script's query needs one edit here, not ten.
pr_json() {
  printf '{"number":42,"title":"feat: the change under test","state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","headRefOid":"%s","statusCheckRollup":[]}' \
    "${1:-$HEAD_SHA}"
}

run_arm() {
  ARM_OUT="$(cd "$ARM_DIR" && \
    PROXYME_GATE_CMD="${GATE_CMD:-true}" \
    PROXYME_PR_JSON="${PR_JSON_OVERRIDE:-$(pr_json)}" \
    ./scripts/merge-pr.sh --dry-run "$@" 2>&1)"
  ARM_RC=$?
}

arm_err() { ARM_ERRS=$((ARM_ERRS+1)); echo "FAIL [$ARM]: $1" >&2; }

end_arm() {
  if [ "$ARM_ERRS" -ne 0 ]; then
    FAILED_ARMS=$((FAILED_ARMS+1))
    echo "  exit status: $ARM_RC" >&2
    echo "  output:" >&2
    printf '%s\n' "$ARM_OUT" | sed 's/^/    /' >&2
  else
    echo "PASS [$ARM]"
  fi
  unset GATE_CMD PR_JSON_OVERRIDE
  rm -rf "$ARM_DIR"
}

expect_refused() {
  [ "$ARM_RC" != 0 ] || arm_err "expected a refusal; it exited 0"
  printf '%s\n' "$ARM_OUT" | grep -qF "$1" \
    || arm_err "expected a refusal naming \"$1\"; got none"
}

expect_allowed() {
  [ "$ARM_RC" = 0 ] || arm_err "expected the run to proceed; it exited $ARM_RC"
}

# A refusal must STOP the run, not merely narrate it.
expect_no_merge_planned() {
  printf '%s\n' "$ARM_OUT" | grep -qF 'gh pr merge' \
    && arm_err "output plans a merge on a path that must refuse"
  return 0
}

# with_pr <jq-filter> — the healthy pull request with one field changed.
with_pr() { PR_JSON_OVERRIDE="$(pr_json | jq -c "$1")"; }

# ==============================================================================

new_arm healthy-pr-plans-a-merge-commit
run_arm
expect_allowed
printf '%s\n' "$ARM_OUT" | grep -qF -e "gh pr merge 42 --merge --subject 'merge: feat: the change under test (#42)' --delete-branch" \
  || arm_err "did not plan the conventional merge commit with branch deletion"
end_arm

new_arm keep-branch-omits-the-deletion
run_arm --keep-branch
expect_allowed
printf '%s\n' "$ARM_OUT" | grep -qF -e '--delete-branch' \
  && arm_err "--keep-branch still planned a branch deletion"
end_arm

# The gate is a condition, not a step.
new_arm red-gate-refuses
GATE_CMD=false
run_arm
expect_refused "gate is not green"
expect_no_merge_planned
end_arm

# The decisive check: merging a head the gate never covered.
new_arm stale-head-sha-refuses
with_pr '.headRefOid = "0123456789012345678901234567890123456789"'
run_arm
expect_refused "the gate covers the local commit"
expect_no_merge_planned
end_arm

new_arm draft-pr-refuses
with_pr '.isDraft = true'
run_arm
expect_refused "is a draft"
expect_no_merge_planned
end_arm

new_arm conflicting-pr-refuses
with_pr '.mergeable = "CONFLICTING"'
run_arm
expect_refused "is CONFLICTING"
expect_no_merge_planned
end_arm

new_arm unclean-merge-state-refuses
with_pr '.mergeStateStatus = "BEHIND"'
run_arm
expect_refused "merge state is BEHIND"
expect_no_merge_planned
end_arm

new_arm closed-pr-refuses
with_pr '.state = "MERGED"'
run_arm
expect_refused "is MERGED, not OPEN"
expect_no_merge_planned
end_arm

# A pending check is an unknown, not a success.
new_arm failing-or-pending-check-refuses
with_pr '.statusCheckRollup = [{"name":"build","conclusion":"FAILURE"},{"name":"lint","conclusion":"PENDING"}]'
run_arm
expect_refused "checks that are not passing: build, lint"
expect_no_merge_planned
end_arm

new_arm on-base-branch-refuses
git -C "$ARM_DIR" checkout -q main
run_arm
expect_refused "there is no pull request to merge from the base branch"
expect_no_merge_planned
end_arm

new_arm dirty-tree-refuses
echo uncommitted >> "$ARM_DIR/file.txt"
run_arm
expect_refused "working tree is dirty"
expect_no_merge_planned
end_arm

# ==============================================================================

if [ "$FAILED_ARMS" -ne 0 ]; then
  echo "RESULT: $FAILED_ARMS of $TOTAL_ARMS arm(s) failed" >&2
  exit 1
fi
echo "RESULT: all $TOTAL_ARMS arms passed"
exit 0
