#!/usr/bin/env bash
#
# open-pr.test.sh — proves scripts/open-pr.sh refuses what it claims to refuse,
# and that the gate is genuinely the condition rather than a step it narrates.
#
# Every arm builds a throwaway repository, copies the shipped script in, and runs
# it with --dry-run. Nothing here pushes, opens a pull request, or reaches the
# network: --dry-run stops after the last refusal check and the gate, which is
# exactly the surface worth testing. The `gh` binary may be absent — the script
# tolerates that on the dry-run path, so this suite runs on a machine without it.
#
# The allow arm matters as much as the refuse arms: a script that refused
# everything would pass a refusal-only suite and never open a pull request.
#
# The gate is injected through PROXYME_GATE_CMD, the documented test override, so
# a red gate can be exercised without breaking the repository's real one.
#
# Real-run evidence (skill-validation-before-merge): the six arms below ran
# against the shipped script. The red-gate arm was seen refusing with
# "gate is not green" AND printing no push line, which is the property that
# matters — a script that ran the gate, ignored it, and pushed anyway would still
# have printed the refusal text somewhere.
#
# Run:  ./scripts/open-pr.test.sh
#
# Never touches the working tree — every arm lives under a mktemp -d removed on
# exit, including on failure and on interrupt.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/open-pr.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

ARM=""; ARM_DIR=""; ARM_OUT=""; ARM_RC=0; ARM_ERRS=0
FAILED_ARMS=0; TOTAL_ARMS=0

[ -x "$SCRIPT" ] || { echo "FAIL: script not executable: $SCRIPT" >&2; exit 1; }

# new_arm <name> — a repository with `main` plus a feature branch one commit
# ahead, which is the shape the happy path expects. Arms narrow from there.
new_arm() {
  ARM="$1"; ARM_DIR="$WORK/$ARM"; ARM_ERRS=0
  TOTAL_ARMS=$((TOTAL_ARMS+1))
  mkdir -p "$ARM_DIR/scripts"
  cp "$SCRIPT" "$ARM_DIR/scripts/open-pr.sh"
  git -C "$ARM_DIR" init -q -b main
  git -C "$ARM_DIR" config user.email fixture@example.invalid
  git -C "$ARM_DIR" config user.name Fixture
  echo base > "$ARM_DIR/file.txt"
  git -C "$ARM_DIR" add -A && git -C "$ARM_DIR" commit -qm "initial"
  git -C "$ARM_DIR" checkout -q -b feature
  echo change > "$ARM_DIR/file.txt"
  git -C "$ARM_DIR" commit -qam "feat: the change under test"
}

# run_arm [extra args…] — always --dry-run, always with a green injected gate
# unless the arm overrode PROXYME_GATE_CMD itself.
run_arm() {
  ARM_OUT="$(cd "$ARM_DIR" && PROXYME_GATE_CMD="${GATE_CMD:-true}" \
    ./scripts/open-pr.sh --dry-run "$@" 2>&1)"
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
  unset GATE_CMD
  rm -rf "$ARM_DIR"
}

# expect_refused <substring> — nonzero exit AND the named reason.
expect_refused() {
  [ "$ARM_RC" != 0 ] || arm_err "expected a refusal; it exited 0"
  printf '%s\n' "$ARM_OUT" | grep -qF "$1" \
    || arm_err "expected a refusal naming \"$1\"; got none"
}

expect_allowed() {
  [ "$ARM_RC" = 0 ] || arm_err "expected the run to proceed; it exited $ARM_RC"
}

# expect_absent <substring> — the refusal must stop the run, not merely narrate.
expect_absent() {
  printf '%s\n' "$ARM_OUT" | grep -qF "$1" \
    && arm_err "output contains \"$1\", which must not happen on this path"
  return 0
}

# ==============================================================================

# The happy path plans a push and a pull request, and says it did neither.
new_arm dry-run-plans-push-and-pr
run_arm
expect_allowed
printf '%s\n' "$ARM_OUT" | grep -qF 'git push -u origin feature' \
  || arm_err "dry run did not plan the push"
printf '%s\n' "$ARM_OUT" | grep -qF 'gh pr create --base main --head feature' \
  || arm_err "dry run did not plan the pull request"
printf '%s\n' "$ARM_OUT" | grep -qF -e "--title 'feat: the change under test'" \
  || arm_err "title did not default to the newest commit subject"
end_arm

# The gate is the condition. A red gate must stop the run before it plans
# anything — not print a warning and carry on.
new_arm red-gate-refuses-and-plans-nothing
GATE_CMD=false
run_arm
expect_refused "gate is not green"
expect_absent "git push"
expect_absent "gh pr create"
end_arm

new_arm on-base-branch-refuses
git -C "$ARM_DIR" checkout -q main
run_arm
expect_refused "a pull request needs a branch to come from"
expect_absent "git push"
end_arm

# A dirty tree would make the gate stamp its receipt dirty and the pre-push guard
# block the push three steps later; refusing here names the cause instead.
new_arm dirty-tree-refuses
echo uncommitted >> "$ARM_DIR/file.txt"
run_arm
expect_refused "working tree is dirty"
expect_absent "git push"
end_arm

# Nothing ahead of the base is an empty pull request.
new_arm nothing-ahead-refuses
git -C "$ARM_DIR" checkout -q -b empty-branch main
run_arm
expect_refused "nothing ahead of"
expect_absent "git push"
end_arm

# An explicit title survives; the commit subject is only the default.
new_arm explicit-title-wins
run_arm --title "chore: an explicit title"
expect_allowed
printf '%s\n' "$ARM_OUT" | grep -qF -e "--title 'chore: an explicit title'" \
  || arm_err "explicit --title was not used"
end_arm

# ==============================================================================

if [ "$FAILED_ARMS" -ne 0 ]; then
  echo "RESULT: $FAILED_ARMS of $TOTAL_ARMS arm(s) failed" >&2
  exit 1
fi
echo "RESULT: all $TOTAL_ARMS arms passed"
exit 0
