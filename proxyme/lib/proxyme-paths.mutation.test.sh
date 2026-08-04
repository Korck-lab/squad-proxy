#!/usr/bin/env bash
#
# proxyme-paths.mutation.test.sh — mutation harness for proxyme-paths.test.sh.
#
# Turns "this assertion catches the drift it claims to catch" into something the
# suite proves rather than something a reviewer asserts. Each arm copies the
# shipped plugin tree to a throwaway directory, applies exactly ONE named
# mutation to the copy, runs the suite against the copy, and asserts that a
# NAMED assertion failed — not merely that the exit status was nonzero. A
# nonzero exit says only "something broke"; it stays green when the mutation is
# caught by an unrelated assertion, which is how a check that detects nothing
# keeps its reputation.
#
# The no-mutation arm runs first and proves the unmutated copy is green, so a
# harness that fails everything cannot pass itself.
#
# Mutations come in both directions on purpose. A renumber (`Section 7` becomes
# `Section 8`) and a deletion (the reference is removed or reworded away). The
# deletion direction is not optional: assertion 9's confirmed defect — a
# tree-wide scan satisfied by the test file's own comment — is invisible to
# renumber-only mutation, and was missed for exactly that reason during review.
#
# Run:  ./proxyme-paths.mutation.test.sh
#
# Never mutates the working tree. Every edit lands in $WORK, which is removed on
# exit, including on failure and on interrupt.
set -uo pipefail   # deliberately no -e: every arm must run, including after one fails

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/.." && pwd)"
SUITE_REL="lib/proxyme-paths.test.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

ARM=""          # current arm name
ARM_DIR=""      # throwaway tree for the current arm
ARM_OUT=""      # combined stdout+stderr of the suite run
ARM_RC=0        # exit status of the suite run
ARM_ERRS=0      # expectation failures within the current arm
FAILED_ARMS=0
TOTAL_ARMS=0

# --- arm plumbing -------------------------------------------------------------

# new_arm <name> — throwaway copy of the shipped tree, laid out as the suite
# expects: plugin root at <arm>/proxyme, README.md one level above it (assertion
# 5 reads $PLUGIN_ROOT/../README.md). The suite derives its plugin root from its
# own location, so running the copy tests the copy.
new_arm() {
  ARM="$1"
  ARM_DIR="$WORK/$ARM"
  ARM_ERRS=0
  TOTAL_ARMS=$((TOTAL_ARMS+1))
  mkdir -p "$ARM_DIR"
  cp -R "$PLUGIN_ROOT" "$ARM_DIR/proxyme"
  cp "$REPO_ROOT/README.md" "$ARM_DIR/README.md"
}

run_arm() {
  ARM_OUT="$(cd "$ARM_DIR" && bash "$ARM_DIR/proxyme/$SUITE_REL" 2>&1)"
  ARM_RC=$?
}

arm_err() {
  ARM_ERRS=$((ARM_ERRS+1))
  echo "FAIL [$ARM]: $1" >&2
}

end_arm() {
  if [ "$ARM_ERRS" -ne 0 ]; then
    FAILED_ARMS=$((FAILED_ARMS+1))
    # Report what the suite actually said, so an arm that fails to detect its
    # mutation names both the assertion that was expected to fire and the ones
    # that did.
    echo "  suite exit status: $ARM_RC" >&2
    echo "  assertions that failed in this arm:" >&2
    if printf '%s\n' "$ARM_OUT" | grep -q '^FAIL:'; then
      printf '%s\n' "$ARM_OUT" | grep '^FAIL:' | sed 's/^/    /' >&2
    else
      echo "    (none)" >&2
    fi
  else
    echo "PASS [$ARM]"
  fi
  rm -rf "$ARM_DIR"
}

# --- expectations -------------------------------------------------------------

# The suite must always reach its RESULT: line — an input it cannot read is a
# failure to report, never a reason to abort mid-run.
expect_result_line() {
  printf '%s\n' "$ARM_OUT" | grep -q '^RESULT:' \
    || arm_err "suite printed no RESULT: line (aborted mid-run, exit $ARM_RC)"
  case "$ARM_RC" in
    0|1) : ;;
    *)   arm_err "suite exited $ARM_RC; expected 0 or 1" ;;
  esac
}

expect_green() {
  expect_result_line
  printf '%s\n' "$ARM_OUT" | grep -qF 'RESULT: all assertions passed' \
    || arm_err "expected a green run; the suite reported failures"
}

# expect_fail <substring> — a named assertion must have fired.
expect_fail() {
  expect_result_line
  printf '%s\n' "$ARM_OUT" | grep -F 'FAIL:' | grep -qF "$1" \
    || arm_err "expected the assertion naming \"$1\" to fire; it did not"
}

# expect_fail_count <n> <substring> — one failure per root cause.
expect_fail_count() {
  local want="$1" needle="$2" got
  got="$(printf '%s\n' "$ARM_OUT" | grep -F 'FAIL:' | grep -cF "$needle")"
  [ "$got" = "$want" ] \
    || arm_err "expected $want failure(s) naming \"$needle\", got $got"
}

# expect_absent <substring> — raw tool errors must never reach the report.
expect_absent() {
  printf '%s\n' "$ARM_OUT" | grep -qF "$1" \
    && arm_err "output contains \"$1\", which must never appear in the report"
  return 0
}

# --- cross-suite arms ---------------------------------------------------------
# The helpers above are shaped for the paths suite: it reports every assertion and
# always reaches a RESULT: line. The other two colocated suites report differently
# — the validate one exits on its first failure and never prints RESULT: — so an
# arm aimed at them asserts on exit status plus a NAMED message instead. Same
# standard as everywhere else here: "something broke" is not evidence that the
# assertion under test is the thing that broke.
run_suite() {
  ARM_OUT="$(cd "$ARM_DIR" && bash "$ARM_DIR/proxyme/$1" 2>&1)"
  ARM_RC=$?
}

expect_suite_green() {
  [ "$ARM_RC" = 0 ] || arm_err "expected a green suite run; it exited $ARM_RC"
}

# expect_suite_fail <substring> — nonzero exit AND a failure line naming it.
expect_suite_fail() {
  [ "$ARM_RC" != 0 ] || arm_err "expected the suite to fail; it exited 0"
  printf '%s\n' "$ARM_OUT" | grep -qF "$1" \
    || arm_err "expected a failure naming \"$1\"; the suite named none"
}

# --- mutation helpers ---------------------------------------------------------

# edit <file> <sed-script>… — in-place edit without GNU/BSD `sed -i` skew.
edit() {
  local f="$1"; shift
  sed "$@" "$f" > "$f.mutated" && mv "$f.mutated" "$f"
}

ident_skill()  { echo "$ARM_DIR/proxyme/skills/proxyme-identity/SKILL.md"; }
sess_fixture() { echo "$ARM_DIR/proxyme/skills/proxyme-identity/fixtures/sample-session.jsonl"; }
score_fixture(){ echo "$ARM_DIR/proxyme/skills/proxyme-validate/fixtures/sample-scorecard.json"; }
proxy_skill()  { echo "$ARM_DIR/proxyme/skills/proxyme/SKILL.md"; }
model_skill()  { echo "$ARM_DIR/proxyme/skills/proxyme-model/SKILL.md"; }
valid_skill()  { echo "$ARM_DIR/proxyme/skills/proxyme-validate/SKILL.md"; }
contract()     { echo "$ARM_DIR/proxyme/lib/terse-contract.md"; }
carve_outs()   { echo "$ARM_DIR/proxyme/lib/carve-outs.md"; }
plugin_dox()   { echo "$ARM_DIR/proxyme/AGENTS.md"; }
fixture()      { echo "$ARM_DIR/proxyme/skills/proxyme-identity/fixtures/stale-flags.md"; }
suite_file()   { echo "$ARM_DIR/proxyme/$SUITE_REL"; }

# renumber_shipped <from> <to> — the migration this freeze anticipates, applied
# correctly and completely: template heading, guard anchor, prose references,
# fixture heading, and the frozen constant in the suite itself.
renumber_shipped() {
  local from="$1" to="$2"
  edit "$(ident_skill)" \
    -e "s/Section $from/Section $to/g" \
    -e "s/^## $from\. Proxy operational rules/## $to. Proxy operational rules/" \
    -e "s|/\^## $from|/^## $to|g"
  edit "$(carve_outs)" -e "s/Section $from/Section $to/g"
  edit "$(plugin_dox)" -e "s/Section $from/Section $to/g"
  edit "$(fixture)"    -e "s/^## $from\./## $to./"
  edit "$(suite_file)" -e "s/^SECTION_NUM=$from\$/SECTION_NUM=$to/"
}

# ==============================================================================
# Baseline
# ==============================================================================

new_arm no-mutation
run_arm
expect_green
end_arm

# ==============================================================================
# Ticket 02 — the section-reference check (assertion 9, check (c))
# ==============================================================================

# Defect 1: the recursive scan read the test file itself, whose comment contains
# the literal `Section 7`. With every shipped reference reworded away the suite
# still reported all assertions passed.
new_arm section-ref-reworded-everywhere
edit "$(carve_outs)"  -e 's/Section 7/that section/g'
edit "$(ident_skill)" -e 's/Section 7/that section/g'
edit "$(plugin_dox)"  -e 's/Section 7/that section/g'
run_arm
expect_fail "lib/carve-outs.md no longer names Section 7"
expect_fail "skills/proxyme-identity/SKILL.md no longer names Section 7"
expect_fail "AGENTS.md no longer names Section 7"
end_arm

# Defect 5: deletion in ONE covered file at a time — set-equality across the
# tree passed as long as any other file still said Section 7.
new_arm section-ref-deleted-in-carve-outs
edit "$(carve_outs)" -e 's/the generated identity.s Section 7 does not restate it/it is not restated there/'
run_arm
expect_fail "lib/carve-outs.md no longer names Section 7"
end_arm

new_arm section-ref-deleted-in-identity-skill
edit "$(ident_skill)" -e 's/Section 7/that section/g'
run_arm
expect_fail "skills/proxyme-identity/SKILL.md no longer names Section 7"
end_arm

new_arm section-ref-deleted-in-plugin-dox
edit "$(plugin_dox)" -e 's/Section 7/that section/g'
run_arm
expect_fail "AGENTS.md no longer names Section 7"
end_arm

# Defect 6: the failure must name the file holding the stale reference, so the
# maintainer does not re-run `grep -rn` by hand.
new_arm section-ref-failure-names-the-file
edit "$(carve_outs)" -e 's/Section 7/Section 8/g'
run_arm
expect_fail "lib/carve-outs.md"
end_arm

# Defect 2: a correct, complete renumber must pass. It used to fail on the
# test's own comment, sending the maintainer hunting the shipped tree for a
# stale reference that lived in the assertion itself.
new_arm correct-renumber-passes
renumber_shipped 7 8
run_arm
expect_green
end_arm

# Defect 3: the template defines sections 1..7. Prose about a DIFFERENT section
# is legitimate and must not fail the build.
new_arm other-section-prose-passes
printf '\nWrite active projects into Section 5 of the template.\n' >> "$(ident_skill)"
run_arm
expect_green
end_arm

# Defect 4: `grep -r` honours neither .gitignore nor .claudignore, so working
# tree debris decided the build result.
new_arm untracked-debris-is-ignored
cp "$(ident_skill)" "$(ident_skill).orig"
edit "$(ident_skill).orig" -e 's/Section 7/Section 8/g'
printf 'Section 9\n' > "$ARM_DIR/proxyme/lib/.DS_Store"
run_arm
expect_green
end_arm

# ==============================================================================
# Ticket 03 — the staleness fixture (assertion 9, check (d))
# ==============================================================================

# The shipped guard scopes with `sed -n '/^## 7\./,$p'`, and `,$p` prints to the
# last line of the file: it excludes sections BEFORE 7 only. A fixture that
# grows a later section sweeps that section's flags into the guard's input.
new_arm fixture-grows-a-later-section
printf '\n## 8. Notes\n\nDry runs use `--dryrun`.\n' >> "$(fixture)"
run_arm
expect_fail "staleness fixture"
end_arm

# A renumbered fixture must name the number found — `got '0'` cannot tell a
# renumber from a truncation from a lost heading, three different repairs.
new_arm fixture-heading-renumbered
edit "$(fixture)" -e 's/^## 7\./## 8./'
run_arm
expect_fail "(got '8', want '7')"
end_arm

new_arm fixture-heading-removed
edit "$(fixture)" -e '/^## 7\./d'
run_arm
expect_fail "(got '', want '7')"
end_arm

# ==============================================================================
# Ticket 04 — one failure per root cause, no silent skips, no mid-run abort
# ==============================================================================

# Defect 1: assertion 9 was gated on the identity skill existing, including the
# two checks that never read it. Drift in carve-outs.md went unreported until
# the unrelated missing file was restored.
new_arm missing-identity-skill-still-runs-unrelated-checks
rm "$(ident_skill)"
edit "$(carve_outs)" -e 's/Section 7/that section/g'
run_arm
expect_fail_count 1 "/proxyme-identity skill missing"
expect_fail "lib/carve-outs.md no longer names Section 7"
end_arm

# Defect 2: an absent fixture emitted a raw grep error interleaved into the
# PASS/FAIL stream plus a failure reading as "zero section-7 headings".
new_arm missing-fixture-reports-once
rm "$(fixture)"
run_arm
expect_fail_count 1 "staleness fixture missing"
expect_absent "No such file or directory"
end_arm

# Defect 3: the guard-block emptiness test existed in two places after the
# extraction was hoisted, so one edit produced two distinct FAIL lines.
new_arm unfindable-guard-block-reports-once
edit "$(ident_skill)" -e 's/^comm -23 \\$/comm --no-such-mode \\/'
run_arm
expect_fail_count 1 "staleness-guard"
end_arm

# Defect 4: the hoisted extraction was a plain assignment, so under `set -e` an
# unreadable identity skill aborted the run — no RESULT: line, exit 2, and
# assertions 7 through 9 never ran.
new_arm unreadable-identity-skill-does-not-abort
chmod 000 "$(ident_skill)"
run_arm
chmod 644 "$(ident_skill)"
expect_result_line
expect_fail_count 1 "/proxyme-identity skill missing"
end_arm

# ==============================================================================
# Ticket 21 — the output-language rule (assertion 12)
# ==============================================================================

# The reverted clause is the likelier regression: it reads as a correct sentence
# wherever it survives, so nothing about the file looks wrong. Reverting the
# canonical contract must fire BOTH directions — the rule is gone and the
# superseded clause is back.
new_arm language-rule-reverted-in-contract
edit "$(contract)" \
  -e 's/^- Answer in en-US, whatever language the user writes in\..*$/- Answer in the language the question was asked in./' \
  -e '/^  translated to en-US and tagged/d' \
  -e '/^  from pt-BR\]` — so a translation/d'
run_arm
expect_fail "lib/terse-contract.md no longer states the en-US output rule"
expect_fail "lib/terse-contract.md still tells the agent to follow the user's language"
end_arm

# Deletion, one covered file at a time. Each skill prints its own status block
# without spawning an agent, so a skill that loses the rule stops being en-US
# even while the contract still says it — per-file presence is what catches that.
new_arm language-rule-deleted-in-proxy-skill
edit "$(proxy_skill)" -e 's/Answer in en-US, whatever language the user writes in\./Answer briefly./'
run_arm
expect_fail "skills/proxyme/SKILL.md no longer states the en-US output rule"
end_arm

new_arm language-rule-deleted-in-identity-skill
edit "$(ident_skill)" -e 's/Answer in en-US, whatever language the user writes in\./Answer briefly./'
run_arm
expect_fail "skills/proxyme-identity/SKILL.md no longer states the en-US output rule"
end_arm

new_arm language-rule-deleted-in-model-skill
edit "$(model_skill)" -e 's/Answer in en-US, whatever language the user writes in\./Answer briefly./'
run_arm
expect_fail "skills/proxyme-model/SKILL.md no longer states the en-US output rule"
end_arm

new_arm language-rule-deleted-in-validate-skill
edit "$(valid_skill)" -e 's/Answer in en-US, whatever language the user writes in\./Answer briefly./'
run_arm
expect_fail "skills/proxyme-validate/SKILL.md no longer states the en-US output rule"
end_arm

# Presence alone is not enough: a file can state the en-US rule and, further
# down, still tell the agent to follow the user. This arm keeps the rule intact
# so the presence check passes, and proves the absence check fires anyway.
new_arm language-rule-present-but-superseded-clause-reintroduced
printf '\nWhen replying to the picker, answer in the language the user is writing in.\n' >> "$(model_skill)"
run_arm
expect_fail "skills/proxyme-model/SKILL.md still tells the agent to follow the user's language"
expect_fail_count 0 "skills/proxyme-model/SKILL.md no longer states the en-US output rule"
end_arm

# ==============================================================================
# Ticket 21 — the sibling suites' ADR-0007 assertions
# ==============================================================================
#
# The language rule spans three suites, so mutation coverage has to as well.
# Without these arms the identity and validate assertions would rest on a manual
# run recorded in a comment — which is exactly the "reviewer asserts it" shape
# this harness exists to replace.

IDENT_SUITE="skills/proxyme-identity/proxyme-identity.test.sh"
VALID_SUITE="skills/proxyme-validate/proxyme-validate.test.sh"

new_arm identity-suite-baseline
run_suite "$IDENT_SUITE"
expect_suite_green
end_arm

# Extraction must stay language-agnostic: a filter that quietly dropped
# non-English turns would thin a pt-BR user's identity without failing anything.
new_arm session-fixture-loses-its-non-english-turn
edit "$(sess_fixture)" -e '$d'
edit "$(sess_fixture)" -e '$d'
run_suite "$IDENT_SUITE"
expect_suite_fail "indexes a non-English human turn"
end_arm

# The tag is what stops a translation from being read as the user's exact words.
new_arm identity-skill-drops-the-translation-tag
edit "$(ident_skill)" -e 's/\[translated from pt-BR\]/[quoted]/g'
run_suite "$IDENT_SUITE"
expect_suite_fail "skill requires the translation tag"
end_arm

# The in-place conversion of a pre-ADR-0007 file, and the report line that makes
# it visible, are one condition — deleting the report line deletes the evidence.
new_arm identity-skill-drops-the-conversion-report-line
edit "$(ident_skill)" -e 's/^Converted to en-US: .*/Notes: <free text>/'
run_suite "$IDENT_SUITE"
expect_suite_fail "converts a pre-ADR-0007 identity in place"
end_arm

# A language check that always answers ALREADY_EN_US reads exactly like a working
# one and would silently convert nothing, forever. The suite extracts the shipped
# snippet and runs it, so a snippet blind to its input fails.
new_arm identity-skill-language-check-goes-blind
edit "$(ident_skill)" -e 's|^headings() [{] grep .*|headings() { echo same; }|'
run_suite "$IDENT_SUITE"
expect_suite_fail "shipped language check on a translated identity"
end_arm

new_arm validate-suite-baseline
run_suite "$VALID_SUITE"
expect_suite_green
end_arm

# Without answer_language a voice_fidelity score from before the flip and one
# from after compare as if they measured the same thing.
new_arm scorecard-loses-answer-language
edit "$(score_fixture)" -e '/"answer_language":/d'
run_suite "$VALID_SUITE"
expect_suite_fail "answer_language"
end_arm

# A run may record the field truthfully and still be off-policy; the assertion
# pins the value, not just the key.
new_arm scorecard-records-a-non-en-us-answer-language
edit "$(score_fixture)" -e 's/"answer_language": "en-US"/"answer_language": "pt-BR"/'
run_suite "$VALID_SUITE"
expect_suite_fail "answer_language"
end_arm

new_arm validate-skill-stops-documenting-answer-language
edit "$(valid_skill)" -e 's/answer_language/answer_lang/g'
run_suite "$VALID_SUITE"
expect_suite_fail "does not document answer_language"
end_arm

# ==============================================================================

if [ "$FAILED_ARMS" -ne 0 ]; then
  echo "RESULT: $FAILED_ARMS of $TOTAL_ARMS mutation arm(s) failed" >&2
  exit 1
fi
echo "RESULT: all $TOTAL_ARMS mutation arms passed"
exit 0
