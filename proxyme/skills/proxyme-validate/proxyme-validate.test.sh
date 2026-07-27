#!/usr/bin/env bash
#
# Real-run evidence for the proxyme-validate skill (skill-validation-before-merge).
#
# Validates fixtures/sample-scorecard.json — the documented observed result of one
# real adversarial actor/critic run — against the rubric/threshold schema:
#   - only the GATING dimensions produce the average; voice_fidelity never gates
#   - `rubric_scored` records which dimensions produced the average (schema v2),
#     so averages from runs with different critic instructions are not compared
#   - each question average == mean of its gating dimension scores
#   - run average == mean of the per-question averages
#   - the 8.5/10 acceptance threshold and accept/iterate logic are consistent
#   - the mandatory edge re-probe ran, and every defect the fixes themselves
#     introduced is recorded AND repaired
#   - the anti-overfit invariant: specific_case_inserted == false
#
# Observed result (real run, 2026-07-27): pass 1 cleared the gating threshold at
#   9.2 and STILL carried four technical defects the score did not block on. Four
#   general rules were added; all four defects verified fixed at 9.0 on four
#   scenario-different questions. The edge re-probe then caught two NEW defects
#   introduced by those very fixes (an absolute with no infeasibility branch, and a
#   widened rule with no duration threshold), both repaired, 3/3 re-probes passing.
#
# Exits 0 only when every assertion holds.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="${SCRIPT_DIR}/fixtures/sample-scorecard.json"
SKILL="${SCRIPT_DIR}/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || fail "jq is required to run this test"
[ -f "$FIXTURE" ] || fail "fixture not found: $FIXTURE"
[ -f "$SKILL" ]   || fail "skill not found: $SKILL"

jq -e . "$FIXTURE" >/dev/null 2>&1 || fail "fixture is not valid JSON"

# All schema + arithmetic + threshold + anti-overfit checks run inside one jq pass.
JQ_CHECKS='
def absdiff($a;$b): ($a-$b) | if . < 0 then -. else . end;
def approx($a;$b): absdiff($a;$b) < 0.05;
. as $sc
| $sc.rubric.threshold as $th
| $sc.rubric.gating_dimensions as $gate
| $sc.rubric.reported_only_dimensions as $rep
| [ $sc.held_out_questions[] | . as $q | ($gate|map($q.scores[.])) | (add/length) ] as $qavgs
| [
    (if $th == 8.5 then empty else "threshold is not 8.5/10: \($th)" end),
    (if ($gate|length) >= 3 then empty else "need at least 3 gating dimensions" end),

    # voice_fidelity must be reported-only and must never gate.
    (if ($rep|index("voice_fidelity")) then empty
     else "voice_fidelity must be listed as a reported-only dimension" end),
    (if ($gate|index("voice_fidelity")) == null then empty
     else "voice_fidelity must NOT be a gating dimension" end),

    # rubric_scored must exist and must match exactly the dimensions used for the average.
    (if ($sc.rubric_scored|type) == "array" then empty
     else "rubric_scored missing: averages become non-comparable across runs" end),
    (if ($sc.rubric_scored|sort) == ($gate|sort) then empty
     else "rubric_scored does not match the gating dimensions that produced the average" end),

    ( $sc.held_out_questions[] | . as $q | ($gate|map($q.scores[.])) as $v
      | (if ($v|any(. == null)) then "\($q.id): missing gating dimension score" else empty end),
        (if ($v|any(. < 0 or . > 10)) then "\($q.id): score out of [0,10] range" else empty end),
        (if approx(($v|add/($v|length)); $q.average) then empty
         else "\($q.id): stored average \($q.average) != mean of gating scores" end),
        # a reported-only dimension must never leak into the gating scores block
        (if ($rep|map($q.scores[.])|any(. != null)) then
            "\($q.id): reported-only dimension found inside gating scores"
         else empty end)
    ),
    (if approx(($qavgs|add/($qavgs|length)); $sc.result.average) then empty
     else "result.average \($sc.result.average) != mean of per-question averages" end),
    (if $sc.result.accepted == ($sc.result.average >= $th) then empty
     else "result.accepted is inconsistent with average vs threshold" end),
    (if $sc.result.accepted then empty else "documented run did not pass the 8.5/10 threshold" end),
    (if $sc.result.specific_case_inserted == false then empty
     else "anti-overfit violated: specific case inserted into identity" end),

    # every iteration must be self-consistent about accept-vs-threshold
    ( $sc.iterations[] | . as $it
      | if $it.accepted == ($it.average >= $th) then empty
        else "iteration \($it.pass): accepted flag inconsistent with its average" end ),
    (if ($sc.iterations|length) >= 1 then empty else "no iterations recorded" end),
    (if ($sc.iterations[-1].average >= $th) then empty
     else "final iteration is below threshold" end),
    (if approx($sc.iterations[-1].average; $sc.result.average) then empty
     else "result.average != final iteration average" end),

    # the mandatory edge re-probe must have run after the identity was edited
    (if $sc.edge_reprobe.ran == true then empty
     else "edge re-probe did not run after the identity was edited" end),
    (if ($sc.edge_reprobe.probes_run // 0) >= 1 then empty
     else "edge re-probe recorded no probes" end),
    (if ($sc.edge_reprobe.probes_passed // -1) == ($sc.edge_reprobe.probes_run // 0) then empty
     else "edge re-probe has unresolved failing probes" end),
    # any defect the fixes themselves introduced must be repaired, not just noted
    ( $sc.edge_reprobe.new_defects_introduced[]? | . as $d
      | if $d.repaired == true then empty
        else "new defect \($d.id) introduced by a fix was never repaired" end )
  ]
| if length == 0 then "PASS" else (.[]|tostring) end
'

RESULT="$(jq -r "$JQ_CHECKS" "$FIXTURE")"
[ "$RESULT" = "PASS" ] || fail "scorecard validation:
$RESULT"

# The skill must document the threshold, the observed real run, the non-gating
# voice dimension, and the mandatory edge re-probe.
grep -q '8.5/10' "$SKILL"              || fail "SKILL.md does not document the 8.5/10 threshold"
grep -q 'Observed result' "$SKILL"     || fail "SKILL.md does not document the observed real-run result"
grep -q 'rubric_scored' "$SKILL"       || fail "SKILL.md does not require rubric_scored on the scorecard"
grep -q 'Edge re-probe' "$SKILL"       || fail "SKILL.md does not document the mandatory edge re-probe"
grep -qi 'never gates\|reported only' "$SKILL" \
  || fail "SKILL.md does not state that voice_fidelity is reported-only and never gates"

echo "PASS: gating rubric, rubric_scored provenance, 8.5/10 threshold, accept/iterate logic,"
echo "      edge re-probe with repaired self-inflicted defects, and anti-overfit invariant verified"
exit 0
