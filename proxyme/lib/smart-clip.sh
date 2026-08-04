#!/usr/bin/env bash
#
# proxyme — SMART-CLIP: emit one windowed Q/A record per real human turn.
#
# Maps every line of a Claude Code session transcript to its offset and class,
# then pulls a bounded window around each real human turn by line index. The
# whole .jsonl is never loaded — clip, do not dump.
#
# Usage:  smart-clip.sh <session.jsonl> [before] [after]
#           before  assistant turns kept before each human turn (default 2)
#           after   assistant turns kept after  each human turn (default 2)
#
# Output: one compact JSON object per human turn, one per line:
#   {user_line, window_lines, before, user, after}
#
# Two classes of line are excluded from "human turn" and both matter:
#   - harness-injected noise (command echoes, system reminders, task
#     notifications, image metadata, compaction summaries, slash-command
#     caveats) — 20-50% of type=="user" lines on a real session;
#   - AGENT-AUTHORED turns (<agent-message>, cross-session messages, context
#     usage dumps, <bash-input> echoes), which also arrive on type=="user"
#     lines. Measured on a real 8.9k-line session: 231 lines passed the
#     pre-2026-07-27 filter and only 98 were human — 58% was another agent's
#     prose, which makes a profile built from it self-referential.
set -euo pipefail

SESSION="${1:-}"
BEFORE="${2:-2}"
AFTER="${3:-2}"

if [ -z "$SESSION" ]; then
  echo "usage: smart-clip.sh <session.jsonl> [before] [after]" >&2
  exit 2
fi
if [ ! -f "$SESSION" ]; then
  echo "ERROR: session not found: $SESSION" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

# Pass 1: classify every line by offset without loading content.
#   A = assistant turn, U = real human turn, O = other.
classify() {
  jq -rc '"\(input_line_number) \(
    if .type=="assistant" then "A"
    elif (.type=="user" and (.message.content|type=="string")
          and ((.message.content)|test("<command-name>|<system-reminder>|<local-command|<task-notification>|<agent-message|<bash-input|Another Claude session sent a message|## Context Usage|^\\[Image:|^\\[Request interrupted|session is being continued|Caveat: The messages below were generated")|not)) then "U"
    else "O" end)"' "$SESSION"
}

# Readable text of a single line, by offset (one sed -n, never the file).
text_of() {
  sed -n "${1}p" "$SESSION" | jq -rc 'if (.message.content|type)=="string"
    then (.message.content|gsub("\n";" "))
    else (.message.content|map(.text//"")|join(" ")|gsub("\n";" ")) end'
}

# Walk outward from a human turn collecting up to $max assistant lines, skipping
# other lines and stopping at the next human turn.
collect() {
  local n=$1 step=$2 max=$3 c=0 out=""
  while [ "$n" -ge 1 ] && [ "$n" -le "$TOTAL" ] && [ "$c" -lt "$max" ]; do
    case "${CLASS[$n]:-O}" in
      U) break ;;
      A) out="$out $n"; c=$((c+1)) ;;
    esac
    n=$((n+step))
  done
  echo "$out"
}

emit_record() {
  local uline=$1 blist=$2 alist=$3 wl bt at
  wl=$( { echo "$uline"; printf '%s\n' $blist $alist; } | grep -E '^[0-9]+$' | sort -n | jq -nc '[inputs]' )
  bt=$( for x in $(printf '%s\n' $blist | grep -E '^[0-9]+$' | sort -n); do text_of "$x"; done | jq -Rnc '[inputs]' )
  at=$( for x in $alist; do text_of "$x"; done | jq -Rnc '[inputs]' )
  jq -nc --argjson ul "$uline" --argjson wl "$wl" --argjson b "$bt" \
         --arg u "$(text_of "$uline")" --argjson a "$at" \
    '{user_line:$ul, window_lines:$wl, before:$b, user:$u, after:$a}'
}

cls=$(classify)
CLASS=(); TOTAL=0
while read -r ln cl; do CLASS[$ln]=$cl; TOTAL=$ln; done <<< "$cls"

for n in $(seq 1 "$TOTAL"); do
  [ "${CLASS[$n]:-O}" = "U" ] || continue
  emit_record "$n" "$(collect $((n-1)) -1 "$BEFORE")" "$(collect $((n+1)) 1 "$AFTER")"
done
