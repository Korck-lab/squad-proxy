#!/usr/bin/env bash
#
# proxyme-identity.test.sh — real-run evidence for the Agent D SMART-CLIP extractor.
#
# What this tests (skill-validation-before-merge guardrail):
#   The SMART-CLIP jq line-offset window helper documented in SKILL.md (Agent D).
#   It maps each real user turn's line offset in a .jsonl session and pulls only a
#   bounded window (default up to 2 assistant turns BEFORE + 2 AFTER each real user
#   turn) via line index — it never loads the whole .jsonl into the agent. The output
#   is one windowed Q/A-context record per real user turn (model question -> user
#   answer -> model confirmation-of-understanding), ready for clip classification.
#
# Fixture: fixtures/sample-session.jsonl — a synthetic placeholder session about
#   building a "widget-store" checkout. No real PII, emails, tokens, or personal paths.
#
# Observed result (real run, 2026-06-30, GNU bash 3.2.57 + jq 1.7.1):
#   3 real user turns indexed (lines 3, 9, 13); command/system-reminder/tool_result
#   lines (1, 6, 8, 11) excluded. User turn at line 3 yields after=[4,5] only — the
#   third following assistant turn (line 7) is capped out, proving the window is
#   bounded and the whole file is never loaded. User turn at line 9 (a correction)
#   captures the model confirmation-of-understanding at line 10. The widened filter
#   also drops harness-injected noise (task-notification @15, image-meta @16) — these
#   are NOT user turns; on real sessions 20-50% of user-typed lines are this kind of
#   noise (task-notification, [Image:...], compaction summaries, slash-command caveats).
#   All assertions pass; the script exits 0.
#
# Extended (real run, 2026-07-27): AGENT-AUTHORED turns (@17-20) added to the fixture.
#   Another agent's prose also arrives on type=="user" lines — <agent-message>,
#   "Another Claude session sent a message", "## Context Usage", <bash-input>. Measured
#   on a real 8.9k-line session: 231 lines passed the pre-2026-07-27 filter and only
#   98 were human — 58% was the proxy's own voice being recycled as if the user had
#   written it, which makes the generated identity self-referential. The widened
#   filter excludes them; assertions prove they are neither indexed as user turns nor
#   pulled into any window. 10/10 assertions pass.
#
# Extended (real run, 2026-08-04, ADR-0007): a pt-BR human turn (@22) added to the
#   fixture. The identity is now written in en-US whatever the user types in, and
#   translation happens at synthesis — which only holds if extraction classifies by
#   structure and never by language. Observed: 4 user turns indexed (3, 9, 13, 22),
#   the pt-BR turn keeping its Q/A window like the English ones. Proven by mutation,
#   not by inspection: deleting the two fixture lines fires both language assertions,
#   and stripping the tag rule from the shipped skill fires the two instruction
#   assertions — 6 failures in total, restored to 16/16 green.
#
# Run:  ./proxyme-identity.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/sample-session.jsonl"
# The SMART-CLIP logic lives in the shipped module; this test exercises that
# module, not a copy of it. Resolve it the way the skills do.
eval "$(bash "$SCRIPT_DIR/../../lib/proxyme-paths.sh")"
[ -x "$PROXYME_SMART_CLIP" ] || { echo "FAIL: smart-clip not executable: $PROXYME_SMART_CLIP" >&2; exit 1; }

smart_clip() { "$PROXYME_SMART_CLIP" "$FIXTURE"; }

# --- run + assert --------------------------------------------------------------
RECORDS="$(smart_clip)"
FAILS=0
check() { # check <desc> <jq-filter-returning-true>
  if printf '%s\n' "$RECORDS" | jq -e -s "$2" >/dev/null; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"; FAILS=$((FAILS+1))
  fi
}

echo "--- SMART-CLIP windowed records ---"
printf '%s\n' "$RECORDS"
echo "-----------------------------------"

# Exactly the 4 real user turns are indexed (lines 3, 9, 13, 22).
check "indexes only real user turns (lines 3,9,13,22)" \
  '(length==4) and ([.[].user_line]==[3,9,13,22])'

# Command / system-reminder / tool_result lines are never treated as user turns.
check "excludes command/system-reminder/tool_result user lines" \
  'all(.[]; (.user|test("<command-name>|<system-reminder>|tool_result"))|not)'

# Every window is bounded: <=2 before, <=2 after, <=5 lines total (never the file).
check "window is bounded (<=2 before, <=2 after, <=5 lines)" \
  'all(.[]; (.before|length)<=2 and (.after|length)<=2 and (.window_lines|length)<=5)'

# Cap proven: user line 3 keeps after=[4,5]; the 3rd following assistant (line 7,
# "Webhook handler scaffolded") is dropped — the whole file is not loaded.
check "caps at 2 after-turns (line 7 excluded from user 3)" \
  'any(.[]; .user_line==3 and (.after|length)==2 and (any(.after[]; test("Webhook handler scaffolded"))|not))'

# Q/A pair: the model question precedes the user answer in the before-window.
check "captures Q/A pair (model question before user answer)" \
  'any(.[]; .user_line==3 and any(.before[]; test("Which payment provider")) and (.user|test("Stripe first")))'

# model confirmation-of-understanding captured after a correction (user line 9).
check "captures model confirmation-of-understanding after a correction" \
  'any(.[]; .user_line==9 and any(.after[]; test("reverting the discount-engine")))'

# Bounded reach: meta/command/reminder/tool_result offsets (1,6,8,11) never pulled.
check "never pulls non-conversational offsets (1,6,8,11)" \
  '([.[].window_lines[]]|unique) as $w | ([1,6,8,11]|all(. as $x | ($w|index($x))==null))'

# Harness-injected noise (task-notification @15, image-meta @16) is NOT a user turn.
# Without the widened filter these would be sampled as the user "speaking" — 20-50%
# of real-session user turns are exactly this kind of noise.
check "excludes task-notification and image-meta from user turns (widened filter)" \
  '([.[].user_line]==[3,9,13,22]) and all(.[]; (.user|test("<task-notification>|^\\[Image:"))|not)'

# AGENT-AUTHORED turns (lines 17-20) are the bigger trap: another agent's prose also
# lands on type=="user" lines. On a real 8.9k-line session 231 lines passed the old
# filter and only 98 were human — 58% was the proxy's own voice being recycled. If
# these are sampled the identity converges on the proxy instead of the user.
check "excludes agent-message / cross-session / context-usage / bash-input turns" \
  'all(.[]; (.user|test("<agent-message|Another Claude session sent a message|## Context Usage|<bash-input"))|not)'

# The agent-noise lines must not be indexed as user turns at all, and must never be
# pulled into any window.
check "agent-authored offsets (17,18,19,20) are never user turns nor windowed" \
  '([.[].user_line]) as $u | ([17,18,19,20]|all(. as $x | ($u|index($x))==null))
   and ([.[].window_lines[]]|unique) as $w
       | ([17,18,19,20]|all(. as $x | ($w|index($x))==null))'

# --- Language: the filter classifies by structure, never by language ----------
# The identity is written in en-US whatever the user types in (ADR-0007), and
# translation happens at synthesis. That split only holds if extraction is
# language-agnostic: a filter that quietly dropped non-English turns would make a
# pt-BR user's identity thinner without failing anything. Line 22 is a real human
# turn written in pt-BR; it must be indexed exactly like the English ones.
check "indexes a non-English human turn (line 22, pt-BR)" \
  'any(.[]; .user_line==22 and (.user|test("mantem o checkout minimo")))'

# And it must carry its Q/A context like any other turn — the model question in
# the before-window is what the synthesis agent reads to label the clip.
check "non-English turn keeps its Q/A window" \
  'any(.[]; .user_line==22 and any(.before[]; test("coupon field")))'

# --- The shipped instruction that turns those clips into en-US ----------------
# The extractor emits original-language text on purpose; the tag rule is what
# stops the synthesis agent from presenting a translation as the user's exact
# words. Asserted against the shipped skill, so deleting the rule is a build
# failure rather than a silent change in what the identity claims.
IDENT_SKILL="$SCRIPT_DIR/SKILL.md"
check_file() { # check_file <desc> <fixed-string needle> <file>
  if [ -f "$3" ] && grep -qF "$2" "$3"; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 (needle not found in $3: '$2')"; FAILS=$((FAILS+1))
  fi
}
check_file "skill requires the translation tag on quoted user text" \
  '[translated from pt-BR]' "$IDENT_SKILL"
check_file "skill forbids paraphrasing while translating" \
  'Translating is not license to paraphrase' "$IDENT_SKILL"
check_file "skill writes the whole identity file in en-US" \
  'Write the WHOLE file in en-US' "$IDENT_SKILL"
check_file "skill converts a pre-ADR-0007 identity in place and reports it" \
  'Converted to en-US:' "$IDENT_SKILL"

# --- The shipped language check, executed rather than described ---------------
# The skill ships an executable snippet that decides whether an identity file
# predates ADR-0007. Asserting that the prose mentions it would prove nothing: a
# snippet that always answers ALREADY_EN_US reads exactly like a working one and
# would silently convert nothing, forever. So the snippet is EXTRACTED FROM THE
# SHIPPED SKILL and run — a copy pasted here would drift and still pass.
LANG_SNIPPET="$(awk '/^headings\(\) \{/,/echo "ALREADY_EN_US"/' "$IDENT_SKILL")"
if [ -z "$LANG_SNIPPET" ]; then
  echo "FAIL: the shipped language check could not be extracted from $IDENT_SKILL"
  FAILS=$((FAILS+1))
else
  TMPD="$(mktemp -d)"
  trap 'rm -rf "$TMPD"' EXIT
  # The en-US arm is built from the template itself, so it cannot drift from what
  # the check compares against. The translated arm is that same file with every
  # heading's text replaced — the shape of a file generated before ADR-0007,
  # numbers intact (ADR-0005: the number is the part that survives translation).
  grep -oE '^## [0-9]+\. .*' "$IDENT_SKILL" | sed 's/ \[auto\]$//' > "$TMPD/en-us.md"
  sed 's/^## \([0-9][0-9]*\)\. .*/## \1. Titulo Traduzido/' "$TMPD/en-us.md" > "$TMPD/translated.md"

  lang_check() { PROXYME_IDENTITY="$1" PROXYME_SKILLS="$PROXYME_SKILLS" bash -c "$LANG_SNIPPET"; }

  GOT_EN="$(lang_check "$TMPD/en-us.md")"
  if [ "$GOT_EN" = "ALREADY_EN_US" ]; then
    echo "PASS: shipped language check leaves an en-US identity alone"
  else
    echo "FAIL: shipped language check on an en-US identity (got '$GOT_EN', want 'ALREADY_EN_US')"
    FAILS=$((FAILS+1))
  fi

  GOT_TR="$(lang_check "$TMPD/translated.md")"
  if [ "$GOT_TR" = "CONVERTED" ]; then
    echo "PASS: shipped language check flags a translated identity for conversion"
  else
    echo "FAIL: shipped language check on a translated identity (got '$GOT_TR', want 'CONVERTED')"
    FAILS=$((FAILS+1))
  fi
fi

if [ "$FAILS" -ne 0 ]; then
  echo "RESULT: $FAILS assertion(s) failed" >&2
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
