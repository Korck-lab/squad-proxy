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

# Exactly the 3 real user turns are indexed (lines 3, 9, 13).
check "indexes only real user turns (lines 3,9,13)" \
  '(length==3) and ([.[].user_line]==[3,9,13])'

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
  '([.[].user_line]==[3,9,13]) and all(.[]; (.user|test("<task-notification>|^\\[Image:"))|not)'

# AGENT-AUTHORED turns (lines 17-20) are the bigger trap: another agent's prose also
# lands on type=="user" lines. On a real 8.9k-line session 231 lines passed the old
# filter and only 98 were human — 58% was the proxy's own voice being recycled. If
# these are sampled the identity converges on the proxy instead of the user.
check "excludes agent-message / cross-session / context-usage / bash-input turns" \
  'all(.[]; (.user|test("<agent-message|Another Claude session sent a message|## Context Usage|<bash-input"))|not)'

# The agent-noise lines must not be indexed as user turns at all, and must never be
# pulled into any window.
check "agent-authored offsets (17,18,19,20) are never user turns nor windowed" \
  '([.[].user_line]|any(. >= 17)|not)
   and ([.[].window_lines[]]|unique) as $w
       | ([17,18,19,20]|all(. as $x | ($w|index($x))==null))'

if [ "$FAILS" -ne 0 ]; then
  echo "RESULT: $FAILS assertion(s) failed" >&2
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
