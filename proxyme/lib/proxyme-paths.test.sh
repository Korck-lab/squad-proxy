#!/usr/bin/env bash
#
# proxyme-paths.test.sh — real-run evidence for the path-resolution module.
#
# Asserts on the module's observable output — which names it prints and whether
# those paths resolve — never on how it derives them. A test that asserted the
# derivation expression would fail on a correct refactor and pass on a broken
# one that kept the expression.
#
# Run:  ./proxyme-paths.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATHS_SH="$SCRIPT_DIR/proxyme-paths.sh"

FAILS=0
fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS+1)); }
pass() { echo "PASS: $*"; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi; }

[ -f "$PATHS_SH" ] || { echo "FAIL: module not found: $PATHS_SH" >&2; exit 1; }

# --- Assertion 1: every export is present ------------------------------------
OUT="$(bash "$PATHS_SH")"
for name in \
  PROXYME_ROOT PROXYME_DIR PROXYME_IDENTITY PROXYME_CONFIG PROXYME_CARVEOUTS \
  PROXYME_GLOBAL_IDENTITY PROXYME_GLOBAL_CONFIG PROXYME_USER PROXYME_SID PROXYME_FLAG \
  PROXYME_PLUGIN_ROOT PROXYME_LIB PROXYME_SKILLS \
  PROXYME_CARVEOUTS_CANON PROXYME_TERSE_CONTRACT PROXYME_SMART_CLIP
do
  if printf '%s\n' "$OUT" | grep -q "^${name}="; then
    pass "exports ${name}"
  else
    fail "missing export: ${name}"
  fi
done

# --- Assertion 2: plugin paths resolve to things that exist ------------------
eval "$OUT"
[ -d "$PROXYME_PLUGIN_ROOT" ] && pass "PROXYME_PLUGIN_ROOT is a directory" \
  || fail "PROXYME_PLUGIN_ROOT does not resolve: $PROXYME_PLUGIN_ROOT"
[ -d "$PROXYME_LIB" ] && pass "PROXYME_LIB is a directory" \
  || fail "PROXYME_LIB does not resolve: $PROXYME_LIB"
[ -d "$PROXYME_SKILLS" ] && pass "PROXYME_SKILLS is a directory" \
  || fail "PROXYME_SKILLS does not resolve: $PROXYME_SKILLS"
check "PROXYME_LIB is under the plugin root" "$PROXYME_LIB" "$PROXYME_PLUGIN_ROOT/lib"
check "PROXYME_SKILLS is under the plugin root" "$PROXYME_SKILLS" "$PROXYME_PLUGIN_ROOT/skills"

# --- Assertion 3: location independence (control arm) ------------------------
# Run the module from a directory that is neither the repo nor a git worktree.
# The plugin paths must be identical; the project-state paths must follow $PWD.
# Without a location-derived plugin root this arm returns a different (or empty)
# PROXYME_PLUGIN_ROOT — the wrong implementation fails visibly rather than
# plausibly, which is the point of the arm.
CONTROL_DIR="$(mktemp -d)"
CONTROL_OUT="$(cd "$CONTROL_DIR" && bash "$PATHS_SH")"
CONTROL_PLUGIN_ROOT="$(printf '%s\n' "$CONTROL_OUT" | sed -n 's/^PROXYME_PLUGIN_ROOT="\(.*\)"$/\1/p')"
CONTROL_STATE_ROOT="$(printf '%s\n' "$CONTROL_OUT" | sed -n 's/^PROXYME_ROOT="\(.*\)"$/\1/p')"
check "plugin root is location-independent" "$CONTROL_PLUGIN_ROOT" "$PROXYME_PLUGIN_ROOT"
check "state root follows the working directory" "$CONTROL_STATE_ROOT" "$CONTROL_DIR"
if [ "$CONTROL_STATE_ROOT" = "$HOME" ]; then
  fail "state root fell back to \$HOME — the pre-\$HOME guard is gone"
else
  pass "state root did not fall back to \$HOME"
fi
rm -rf "$CONTROL_DIR"

# --- Assertion 4: the policy exists exactly once in the shipped tree ---------
# The needle is read from the canonical file at runtime, so this test file never
# contains the literal and therefore never counts itself. *.test.sh is excluded
# so a test fixture can quote the policy without tripping the invariant.
if [ -f "$PROXYME_CARVEOUTS_CANON" ]; then
  pass "canonical carve-outs file exists"
  NEEDLE="$(grep -m1 '^- ' "$PROXYME_CARVEOUTS_CANON" | sed 's/^- //')"
  HITS="$(grep -rlF "$NEEDLE" "$PROXYME_PLUGIN_ROOT" | grep -v '\.test\.sh$' | sort || true)"
  HIT_COUNT="$(printf '%s\n' "$HITS" | grep -c . || true)"
  check "policy appears exactly once in the shipped tree" "$HIT_COUNT" "1"
  check "the single hit is the canonical file" "$HITS" "$PROXYME_CARVEOUTS_CANON"
else
  fail "canonical carve-outs file missing: $PROXYME_CARVEOUTS_CANON"
fi

# --- Assertion 5: README parity ----------------------------------------------
# README.md is at the repo root, one level above the plugin root, and does not
# ship. It is checked, not generated: the six items must match the canonical
# text in the same order once markdown emphasis is stripped.
REPO_ROOT="$(cd "$PROXYME_PLUGIN_ROOT/.." && pwd)"
README="$REPO_ROOT/README.md"
# Guard on BOTH files. The script runs under `set -euo pipefail`, so an
# unguarded grep against a missing canonical file aborts the whole run — no
# RESULT: line, exit 2, and every assertion after this one silently never runs.
# That is the opposite of what a regression test is for.
if [ -f "$README" ] && [ -f "$PROXYME_CARVEOUTS_CANON" ]; then
  CANON_ITEMS="$(grep '^- ' "$PROXYME_CARVEOUTS_CANON" | sed 's/^- //')"
  README_ITEMS="$(sed -n '/^### Never decides/,/^###[^#]/p' "$README" \
    | grep '^- ' | sed 's/^- //; s/\*\*//g')"
  check "README lists the same six items in the same order" "$README_ITEMS" "$CANON_ITEMS"
else
  [ -f "$README" ] || fail "README not found: $README"
  [ -f "$PROXYME_CARVEOUTS_CANON" ] || fail "canonical file missing, README parity not checked"
fi

if [ "$FAILS" -ne 0 ]; then
  echo "RESULT: $FAILS assertion(s) failed" >&2
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
