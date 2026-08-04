#!/usr/bin/env bash
#
# prepush-guard.test.sh — proves the pre-push guard blocks what it claims to.
#
# Each arm builds a throwaway repository, writes (or withholds) a receipt, feeds
# the guard a real pre-push stdin line, and asserts on the NAMED refusal. The
# allow arms matter as much as the block arms: a guard that blocks everything
# would pass a block-only test and stop all work.
#
# Run:  ./scripts/prepush-guard.test.sh
#
# Real-run evidence (skill-validation-before-merge): the five arms below ran
# against the shipped guard; the missing-receipt and stale-receipt arms were seen
# blocking by name, and the bypass arm was seen appending to bypasses.log.
# Never touches the working tree — every arm lives under a mktemp -d removed on
# exit, including on failure and on interrupt.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/prepush-guard.sh"
ZERO="0000000000000000000000000000000000000000"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

ARM=""; ARM_DIR=""; ARM_OUT=""; ARM_RC=0; ARM_ERRS=0
FAILED_ARMS=0; TOTAL_ARMS=0
SHA=""

[ -x "$GUARD" ] || { echo "FAIL: guard not executable: $GUARD" >&2; exit 1; }

new_arm() {
  ARM="$1"; ARM_DIR="$WORK/$ARM"; ARM_ERRS=0
  TOTAL_ARMS=$((TOTAL_ARMS+1))
  mkdir -p "$ARM_DIR/scripts"
  cp "$GUARD" "$ARM_DIR/scripts/prepush-guard.sh"
  git -C "$ARM_DIR" init -q
  git -C "$ARM_DIR" config user.email fixture@example.invalid
  git -C "$ARM_DIR" config user.name Fixture
  echo content > "$ARM_DIR/file.txt"
  git -C "$ARM_DIR" add -A && git -C "$ARM_DIR" commit -qm "initial"
  SHA="$(git -C "$ARM_DIR" rev-parse HEAD)"
}

# write_receipt <sha> <dirty>
write_receipt() {
  mkdir -p "$ARM_DIR/.git/proxyme-gate"
  printf '{"sha":"%s","branch":"main","version":"9.9.9","gated_at":"2026-08-04T00:00:00Z","dirty":%s}\n' \
    "$1" "$2" > "$ARM_DIR/.git/proxyme-gate/receipt.json"
}

# run_arm <pushed-sha> — feeds one pre-push line exactly as git formats it.
run_arm() {
  ARM_OUT="$(cd "$ARM_DIR" && printf 'refs/heads/main %s refs/heads/main %s\n' "$1" "$ZERO" \
    | ./scripts/prepush-guard.sh 2>&1)"
  ARM_RC=$?
}

arm_err() { ARM_ERRS=$((ARM_ERRS+1)); echo "FAIL [$ARM]: $1" >&2; }

end_arm() {
  if [ "$ARM_ERRS" -ne 0 ]; then
    FAILED_ARMS=$((FAILED_ARMS+1))
    echo "  guard exit status: $ARM_RC" >&2
    echo "  guard said:" >&2
    printf '%s\n' "$ARM_OUT" | sed 's/^/    /' >&2
  else
    echo "PASS [$ARM]"
  fi
  rm -rf "$ARM_DIR"
}

expect_blocked() {
  [ "$ARM_RC" -eq 1 ] || arm_err "expected the push to be blocked, guard exited $ARM_RC"
  printf '%s\n' "$ARM_OUT" | grep -qF "$1" || arm_err "expected the refusal to name \"$1\""
}

expect_allowed() {
  [ "$ARM_RC" -eq 0 ] || arm_err "expected the push to be allowed, guard exited $ARM_RC"
}

# ==============================================================================

new_arm receipt-matches-pushed-commit
write_receipt "$SHA" false
run_arm "$SHA"
expect_allowed
end_arm

new_arm no-receipt-blocks
run_arm "$SHA"
expect_blocked "no gate receipt"
end_arm

# The commit moved after the gate ran — the receipt describes other content.
new_arm stale-receipt-blocks
write_receipt "1111111111111111111111111111111111111111" false
run_arm "$SHA"
expect_blocked "the receipt covers 1111111"
end_arm

# A receipt written over a dirty tree describes neither the commit nor the tree.
new_arm dirty-receipt-blocks
write_receipt "$SHA" true
run_arm "$SHA"
expect_blocked "dirty tree"
end_arm

# A branch deletion carries the all-zero sha: no content exists to gate.
new_arm deletion-is-allowed
run_arm "$ZERO"
expect_allowed
end_arm

# The bypass must work AND leave a record — an unrecorded bypass is the same as
# no guard at all, and is why this is an env var rather than `--no-verify`.
new_arm bypass-is-allowed-and-logged
PROXYME_GATE_BYPASS=1 ARM_OUT="$(cd "$ARM_DIR" && printf 'refs/heads/main %s refs/heads/main %s\n' "$SHA" "$ZERO" \
  | PROXYME_GATE_BYPASS=1 ./scripts/prepush-guard.sh 2>&1)"; ARM_RC=$?
expect_allowed
printf '%s\n' "$ARM_OUT" | grep -qF "PROXYME_GATE_BYPASS=1" || arm_err "bypass printed no warning"
[ -s "$ARM_DIR/.git/proxyme-gate/bypasses.log" ] || arm_err "bypass left no entry in bypasses.log"
end_arm

# ==============================================================================

if [ "$FAILED_ARMS" -ne 0 ]; then
  echo "RESULT: $FAILED_ARMS of $TOTAL_ARMS arm(s) failed" >&2
  exit 1
fi
echo "RESULT: all $TOTAL_ARMS arms passed"
exit 0
