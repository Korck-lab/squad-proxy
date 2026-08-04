#!/usr/bin/env bash
#
# verify-version-bump.test.sh — proves the version verifier catches what it claims.
#
# Each arm builds a throwaway git repository, commits a history with exactly one
# defect (or none), runs the verifier against that copy, and asserts on the
# named failure — not merely on a nonzero exit. A verifier that fails everything
# passes an exit-status-only test; the no-defect arm and the exempt arms are
# what stop that.
#
# Run:  ./scripts/verify-version-bump.test.sh
#
# Real-run evidence (skill-validation-before-merge): the six arms below were run
# against the shipped script; the unbumped-commit and non-forward-bump arms were
# each seen failing the verifier by name before this file was considered done.
# Never touches the working tree: every arm lives under a mktemp -d removed on
# exit, including on failure and on interrupt.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="$SCRIPT_DIR/verify-version-bump.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

ARM=""; ARM_DIR=""; ARM_OUT=""; ARM_RC=0; ARM_ERRS=0
FAILED_ARMS=0; TOTAL_ARMS=0

[ -x "$VERIFIER" ] || { echo "FAIL: verifier not executable: $VERIFIER" >&2; exit 1; }

# --- fixture plumbing ---------------------------------------------------------

# new_arm <name> — a fresh repository carrying the three version files and the
# verifier itself, so the script under test resolves ITS OWN location to the
# fixture rather than to this repository.
new_arm() {
  ARM="$1"; ARM_DIR="$WORK/$ARM"; ARM_ERRS=0
  TOTAL_ARMS=$((TOTAL_ARMS+1))
  mkdir -p "$ARM_DIR/proxyme/.claude-plugin" "$ARM_DIR/.claude-plugin" "$ARM_DIR/scripts"
  cp "$VERIFIER" "$ARM_DIR/scripts/verify-version-bump.sh"
  git -C "$ARM_DIR" init -q
  git -C "$ARM_DIR" config user.email fixture@example.invalid
  git -C "$ARM_DIR" config user.name Fixture
  set_version 0.1.0
  echo "shipped" > "$ARM_DIR/proxyme/lib.sh"
  commit "initial"
}

set_version() {
  printf '%s\n' "$1" > "$ARM_DIR/proxyme/VERSION"
  printf '{"name":"proxyme","version":"%s"}\n' "$1" > "$ARM_DIR/proxyme/.claude-plugin/plugin.json"
  printf '{"plugins":[{"name":"proxyme","version":"%s"}]}\n' "$1" > "$ARM_DIR/.claude-plugin/marketplace.json"
}

commit() { git -C "$ARM_DIR" add -A && git -C "$ARM_DIR" commit -qm "$1"; }

run_arm() {
  ARM_OUT="$(cd "$ARM_DIR" && ./scripts/verify-version-bump.sh "$@" 2>&1)"
  ARM_RC=$?
}

arm_err() { ARM_ERRS=$((ARM_ERRS+1)); echo "FAIL [$ARM]: $1" >&2; }

end_arm() {
  if [ "$ARM_ERRS" -ne 0 ]; then
    FAILED_ARMS=$((FAILED_ARMS+1))
    echo "  verifier exit status: $ARM_RC" >&2
    echo "  verifier said:" >&2
    printf '%s\n' "$ARM_OUT" | sed 's/^/    /' >&2
  else
    echo "PASS [$ARM]"
  fi
  rm -rf "$ARM_DIR"
}

expect_green() {
  [ "$ARM_RC" -eq 0 ] || arm_err "expected the verifier to pass, it exited $ARM_RC"
}

# expect_fail <substring> — the NAMED assertion must have fired.
expect_fail() {
  [ "$ARM_RC" -eq 1 ] || arm_err "expected exit 1, got $ARM_RC"
  printf '%s\n' "$ARM_OUT" | grep -F 'FAIL:' | grep -qF "$1" \
    || arm_err "expected a failure naming \"$1\"; it did not fire"
}

# expect_output <substring> — for the repair hint, which is a continuation line
# of the failure and therefore carries no `FAIL:` prefix of its own.
expect_output() {
  printf '%s\n' "$ARM_OUT" | grep -qF "$1" \
    || arm_err "expected the output to name \"$1\""
}

# ==============================================================================

# Baseline: a compliant history must pass, or every arm below is meaningless.
new_arm compliant-history
set_version 0.2.0
echo "changed" > "$ARM_DIR/proxyme/lib.sh"
commit "feat: change the plugin, bump the version"
run_arm --range HEAD~1..HEAD
expect_green
end_arm

# The defect this exists to catch: the pre-commit hook never ran, so plugin
# content changed under a frozen version number.
new_arm plugin-change-without-bump
echo "changed" > "$ARM_DIR/proxyme/lib.sh"
commit "feat: change the plugin and forget the bump"
run_arm --range HEAD~1..HEAD
expect_fail "touches proxyme/ without bumping proxyme/VERSION"
expect_output "install-hooks.sh"
end_arm

# A rollback or a reused number republishes different content under a version
# some cache already holds.
new_arm non-forward-bump
set_version 0.0.9
echo "changed" > "$ARM_DIR/proxyme/lib.sh"
commit "feat: change the plugin, move the version backwards"
run_arm --range HEAD~1..HEAD
expect_fail "not a forward bump"
end_arm

# Partial bump: the three files are read by three different consumers, so one
# left behind installs one version while announcing another.
new_arm plugin-json-out-of-step
set_version 0.2.0
printf '{"name":"proxyme","version":"0.1.0"}\n' > "$ARM_DIR/proxyme/.claude-plugin/plugin.json"
echo "changed" > "$ARM_DIR/proxyme/lib.sh"
commit "feat: bump VERSION only"
run_arm --range HEAD~1..HEAD
expect_fail "plugin.json announces '0.1.0'"
end_arm

new_arm marketplace-json-out-of-step
set_version 0.2.0
printf '{"plugins":[{"name":"proxyme","version":"0.1.0"}]}\n' > "$ARM_DIR/.claude-plugin/marketplace.json"
echo "changed" > "$ARM_DIR/proxyme/lib.sh"
commit "feat: bump VERSION and plugin.json only"
run_arm --range HEAD~1..HEAD
expect_fail "marketplace.json announces '0.1.0'"
end_arm

# Exempt, and it must stay exempt: a commit that touches nothing under proxyme/
# has no version to bump. Without this arm, a verifier that demands a bump from
# every commit would look correct.
new_arm docs-only-commit-needs-no-bump
mkdir -p "$ARM_DIR/docs"
echo "prose" > "$ARM_DIR/docs/note.md"
commit "docs: add a note"
run_arm --range HEAD~1..HEAD
expect_green
end_arm

# Also exempt: a merge carries its branch's files without authoring them, so
# demanding a bump there would demand one version per merge.
new_arm merge-commit-is-exempt
git -C "$ARM_DIR" checkout -q -b feature
set_version 0.2.0
echo "changed" > "$ARM_DIR/proxyme/lib.sh"
commit "feat: change the plugin on a branch"
git -C "$ARM_DIR" checkout -q master 2>/dev/null || git -C "$ARM_DIR" checkout -q main
git -C "$ARM_DIR" merge -q --no-ff -m "merge: feature" feature
run_arm --range HEAD~2..HEAD
expect_green
end_arm

# ==============================================================================

if [ "$FAILED_ARMS" -ne 0 ]; then
  echo "RESULT: $FAILED_ARMS of $TOTAL_ARMS arm(s) failed" >&2
  exit 1
fi
echo "RESULT: all $TOTAL_ARMS arms passed"
exit 0
