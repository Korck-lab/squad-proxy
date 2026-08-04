---
name: proxyme-validate
description: "Adversarial actor/critic validation of your digital proxy. Generates analogous, held-out questions from the info collected by /proxyme-identity, queries the proxy hypothesis (actor), scores each answer on a documented scorecard (critic), and iterates the GENERAL identity until the scorecard averages 8.5/10 — never inserting the specific case. Run after /proxyme-identity and before trusting /proxyme."
allowed-tools: Agent, Read, Edit, Bash
---

# /proxyme-validate

Closes the loop on `/proxyme-identity`. The identity file is a *hypothesis* about how you decide; this skill stress-tests it with an **adversarial actor/critic** scorecard and tunes the *general* profile until the proxy answers held-out questions the way you would.

Run it after `/proxyme-identity` (which produces `<root>/.claude/proxyme/${LOGNAME}-identity.md`) and before relying on `/proxyme` in anger.

The identity under test is **project-scoped**, so scores are per-project: a profile tuned against this repo's decisions says nothing about another repo's. Resolve the path first — `PLUGIN_ROOT` is the directory two levels above this skill's base directory (stated in the launch header); `$CLAUDE_PLUGIN_ROOT` is **not** set in Bash tool calls.

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"
```

That defines `$PROXYME_IDENTITY`, `$PROXYME_CARVEOUTS_CANON` and `$PROXYME_TERSE_CONTRACT` — the three names used below. Every Bash tool call is a **fresh shell**, so nothing survives between blocks: chain the `eval` into the same call as whatever reads those names.

## How it works (actor/critic)

- **Actor** — a read-only `proxyme:proxy` spawned *fresh* for each held-out question with the *candidate* identity. It answers that one question (one-shot) exactly as the live proxy would, then terminates.
- **Critic** — a separate Opus agent. It never sees the "right" answer; it scores each actor answer on the rubric below and proposes only *general* identity adjustments.
- **Adversarial** — the questions are deliberately analogous to (never copied from) the clips used to build the identity, so a memorised answer cannot pass; only a correctly-generalised profile scores well.

## Scorecard rubric

The critic scores every answer 0–10 on five dimensions. **Four of them gate acceptance; `voice_fidelity` is measured and reported but never gates.**

| Dimension | Gates? | What it measures |
| --- | --- | --- |
| `decision_alignment` | **yes** | Matches how the user actually decides (speed vs. care, autonomy) |
| `technical_accuracy` | **yes** | Picks defaults consistent with the user's real stack and documented recipes |
| `boundary_respect` | **yes** | Honours the carve-outs — neither under- **nor over**-escalating (over-escalating an ordinary technical call is also a failure) |
| `specificity` | **yes** | Concrete and grounded: named paths, commands, numbers, criteria — not filler |
| `voice_fidelity` | no — reported only | Sounds like the user — tone, language, length |

**Acceptance threshold: the mean of the four gating dimensions must reach 8.5/10.** Below that, the loop iterates.

Why voice does not gate: a wrong-sounding right answer is a cosmetic defect; a right-sounding wrong answer is the one that costs. Voice is still scored, because a collapse there is a signal worth seeing — it just never blocks a run or triggers an iteration on its own.

**Every iteration records `defects_reported` and `adjustments_applied`.** They are what makes the two accepted shapes machine-readable: an accepted pass with `defects_reported > 0` and `adjustments_applied: false` is the state this skill forbids — defects known, file unchanged, report indistinguishable from a clean run. `proxyme-validate.test.sh` asserts it.

**Every scorecard must record `rubric_scored`** — the exact dimension list that produced the average. Scores computed under different critic instructions are **not comparable**: a run where the critic was told to penalise each voice violation per-occurrence will report a lower `voice_fidelity` than one where it was not, and reading that as a regression is a measurement error, not a finding. Without `rubric_scored` written down, nobody can tell the two apart later. The canonical schema and a documented real run live in `fixtures/sample-scorecard.json`.

## Reporting style

**Version skew, first line, only when it exists.** When `$PROXYME_VERSION_NOTE` is non-empty, print it before the verdict and carry on. It means this run scored the identity using a cached version older than the newest installed one, which is exactly the kind of difference that makes two scorecards incomparable. Empty note, print nothing.

**To the user.** Lead with the verdict — accepted or escalated — then the gating average, then the per-dimension scores. No preamble, no narrating which agents you spawned, no closing summary, no offer of further help. Report the run as a compact block:

```
<ACCEPTED at 9.0/10 | ACCEPTED WITH DEFECTS at 9.46/10, 7 found, adjustments applied | ESCALATED after 3 iterations, best 8.1/10>
decision_alignment <n> · technical_accuracy <n> · boundary_respect <n> · specificity <n> · voice_fidelity <n> (non-gating)
Iterations: <n> · Edits applied: <one line each, general rules only>
Re-probe: <n>/<n> passed · New defects introduced: <list, or "none">
Scorecard: <path written under $PROXYME_SCORECARDS>
Remaining gaps: <list, or omit the line>
```

The first word of the verdict separates the two accepted shapes. `ACCEPTED` means the critic reported no defect; `ACCEPTED WITH DEFECTS` means it did, and the line says how many and whether the adjustments were applied. A reader who stops at the first line must not mistake one for the other.

Cut words, never findings. Every defect the critic found stays in the report even on an accepted run — the 2026-07-27 pass cleared 9.2/10 while carrying four real defects, so a score-only report actively misleads. Failures and remaining gaps get named in full; padding around bad news reads as evasion.

**To the critic agent.** Append the contents of `$PROXYME_TERSE_CONTRACT` verbatim to the critic prompt, followed by this delta:

> **Your delta:** return the scorecard and nothing else. For every score below 8, name the specific defect and quote the exact span of the actor's answer that caused it, verbatim and never paraphrased. Proposed adjustments are concrete rewrites of general identity text, not advice about what to consider. An unreported defect is indistinguishable from a clean run.

## Anti-overfit rule

**Tune the *general* identity only — never insert the specific case.** Adjustments edit the general sections of `$PROXYME_IDENTITY` (heuristics, preferences, voice). The exact validation question/answer pair is **never** written into the file, and held-out questions are re-drawn each pass so the score reflects generalisation, not memorisation.

## What to do when invoked

1. **Draw held-out questions.** From the collected feedback/session info, generate ~6 analogous questions that probe decisions the identity *implies* but does not state verbatim. Keep them general — no real names, emails, tokens, or absolute personal paths.
2. **Run the actor.** First read the two canonical fragments the briefing needs — one call, `eval` chained in:
   ```bash
   eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"
   sed -n '/^- /p' "$PROXYME_CARVEOUTS_CANON"
   cat "$PROXYME_TERSE_CONTRACT"
   ```
   The `sed` yields the absolute carve-out bullets and nothing else; the `cat` yields the density contract. These are the same canonical files the live briefing interpolates, extracted the same way, so a score says something about the proxy that will actually run.
   Then spawn a FRESH `proxyme:proxy` per held-out question, briefed with the *candidate* identity, the question, those carve-out bullets, and that density contract. Collect each one-shot answer.
3. **Run the critic.** Spawn one Opus agent, hand it the rubric and the actor answers, and have it return a scorecard (per-dimension scores + per-question and overall averages, plus `rubric_scored`) in the `fixtures/sample-scorecard.json` shape.
4. **Decide (conditional 1).** If the gating average is **≥ 8.5/10**, accept — but accepting is a statement about the SCORE, not about the file. Read the critic's defect list before stopping.
   - **Accepted, no defects reported** → write the scorecard (step 8), report `ACCEPTED`, stop.
   - **Accepted, defects reported (conditional 2)** → apply the critic's *general* adjustments to `$PROXYME_IDENTITY`, run the **edge re-probe** in step 6, repair whatever it finds, write the scorecard, and report `ACCEPTED WITH DEFECTS`. Do **not** re-draw and re-score: the threshold is already met, and the re-probe — not another scored pass — is what proves the edits introduced no contradiction. This is what the documented 2026-07-27 run did at pass 1 (accepted at 9.2, four defects, four general rules added), and it is the intended behaviour, not an exception to it.
5. **Iterate (conditional 3).** If the average is **below** the threshold and retries remain (cap below), apply the critic's *general* adjustments to `$PROXYME_IDENTITY`, then run the **edge re-probe** in step 6 before re-drawing and looping to step 2.
6. **Edge re-probe (mandatory after any edit).** A rule added to fix one defect can contradict a rule already in the file. After applying adjustments, draw **1–2 extra questions aimed at the edge the new rule created** — not at the case that failed — and have the critic report `new_defects_introduced`. Fix those before continuing; an adjustment that introduces a contradiction is not an improvement. This obligation attaches to EVERY path that edits the identity, including the accepted-with-defects path above.
7. **Give up gracefully (conditional 4).** If the **retry cap** is reached without passing, stop, report the best scorecard and the remaining gaps, and recommend the real user review the identity manually — do not keep tuning.
8. **Write the scorecard.** Every run — accepted, accepted-with-defects, or escalated — writes its scorecard to `$PROXYME_SCORECARDS`, one file per run named for the run's UTC timestamp:

   ```bash
   eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"; mkdir -p "$PROXYME_SCORECARDS"
   # then write the JSON to "$PROXYME_SCORECARDS/$(date -u +%Y%m%dT%H%M%SZ)-scorecard.json"
   ```

   A run never overwrites an earlier scorecard — the history is the point. The directory sits under `$PROXYME_DIR`, which the plugin already excludes from git, so a run in a clean repo leaves `git status` clean; the file holds behavioural findings about the user and belongs there, never in the repository and never in the global template directory. If the write fails, report that as one failure line quoting the error verbatim and still print the verdict — persistence never swallows the result.

   **Comparing two scorecards:** compare `rubric_scored` first. Averages produced under different dimension lists are **not comparable**, and reading their delta as a regression is a measurement error, not a finding. Only when the two lists match does the difference in `result.average` mean anything.

### Why step 6 exists

Observed in a real run: the critic's four proposed adjustments were applied and all four original defects verified fixed — but two of the *fixes themselves* introduced new contradictions.

- A migration rule was written as an absolute ("always diff every field") with no infeasibility branch, contradicting a census rule two lines above that explicitly allowed sampling when a full diff is unviable. At sufficient scale the proxy could only over-demand or improvise an unauthorised exception.
- An observability rule was widened to "anything that runs for minutes" with no duration threshold, colliding with the same identity's anti-scope-inflation rule — a 90-second lint would nominally require progress instrumentation.

Neither was visible from the questions that motivated the fix; both surfaced only when new questions probed the boundary the new wording created. **Re-probe the edge the rule created, not the case that failed.** Instruct the critic explicitly to hunt for defects its own proposed edits introduced — it will not do this unprompted.

**Retry cap: 3 iterations** (the standard actor/critic bound). The loop always terminates: accept on pass, or stop and escalate after 3 tries.

**Orchestration budget:** this loop uses 4 conditionals — within the ≤5 limit of the no-overthink rule, so a fresh agent runs it end-to-end in one session.

## Delegation contract (who decides / what authority / carve-outs)

- **Who decides:** the **critic** (Opus) decides the per-answer scores; the **validate orchestrator** decides accept-vs-iterate purely from the 8.5/10 threshold and the retry cap. No human is asked mid-loop.
- **With what authority — bounded:** the loop may edit *only* the project identity at `<root>/.claude/proxyme/${LOGNAME}-identity.md` (`$PROXYME_IDENTITY`) — never the global template at `~/.claude/skills/proxyme/`, and only its *general* sections. It is read-only everywhere else: it never touches the worktree, never runs project commands, never sends anything externally.
- **Carve-outs that limit it:**
  - Never insert the specific case (anti-overfit) — general profile edits only.
  - The actor is the read-only `proxyme:proxy`; it inherits the absolute carve-outs from `$PROXYME_CARVEOUTS_CANON` and never executes.
  - If the score cannot reach 8.5/10 within the retry cap, the decision escalates to the **real user** — the loop does not silently accept a weak identity.

## Real-run evidence

Recorded in the header of `proxyme-validate.test.sh`, which asserts the
scorecard invariants that evidence describes: gating-only averages,
`rubric_scored` provenance, the 8.5/10 threshold, accept/iterate logic, the edge
re-probe with every self-inflicted defect repaired, and the anti-overfit
`specific_case_inserted: false` flag.

Run the evidence check:

```bash
./proxyme/skills/proxyme-validate/proxyme-validate.test.sh
```
