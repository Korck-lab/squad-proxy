# ADR-0007: Every proxyme artifact and utterance is en-US, unconditionally

- Status: accepted
- Date: 2026-08-04
- Supersedes: the "product output follows the user" exception in
  `docs/guardrails/english-us-normalization.md`

## Context

Until this decision the repository ran two language rules at once. Prose the
repository authors was en-US; output the product emits followed the installer.
`lib/terse-contract.md` told every agent to "answer in the language the question
was asked in", the four skills restated the same rule for the blocks they print
directly, and `/proxyme-identity` was instructed to write the generated `[auto]`
sections "in the user's own language". Only the operational-rules section of the
identity file was pinned to en-US, on the grounds that translation is where a
clause silently loses a condition.

That split was settled deliberately, and its reasoning was fidelity to the
**user**: a translated preference loses the phrasing that carries it, so a
profile written in the installer's own words describes them more exactly.

The reasoning left out who reads the result. The proxy exists to be consulted by
autonomous agents, and those agents run in English in every harness. `/proxyme`
instructs the main agent to relay the proxy's answer **verbatim** — "It is the
user's decision; a paraphrase is a different decision and the user cannot tell
from your output which one they got." So a pt-BR installer produced a pt-BR
identity, a pt-BR answer, and an English-running executor that had to translate
the decision before acting on it. The translation still happened; it just
happened downstream, unrecorded, by whoever needed it.

Two smaller costs came with it. An identity written in one language and consumed
in another cannot be diffed or graded against another installer's without a
translation step in between. And `voice_fidelity`, defined as "sounds like the
user — tone, language, length", was partly measuring language, which made two
scorecards incomparable in a way nothing in the schema revealed.

## Decision

Every proxyme artifact and every proxyme utterance is en-US, whatever language
the installer writes in.

The scope is total, and was confirmed as total: the generated identity file end
to end — profile sections, headings, and the user-authored carve-out block; the
live proxy's answer; the validation loop's held-out questions, actor answers and
scorecards; and the status blocks the skills print to the user.

Captured user text is **translated to en-US and tagged with its source
language** — `"…" [translated from pt-BR]`. The tag is load-bearing. Translating
a quote destroys its verbatim property, which this repository's own guardrail
previously called falsification; the tag does not restore that property, it
keeps the loss visible instead of silent. Translating is not license to
paraphrase: every negation, condition and hedge survives, and a blunt sentence
stays blunt.

The rule is set in exactly five shipped files — `lib/terse-contract.md`, which
every agent prompt interpolates, plus the four skills that print status blocks of
their own directly to the user rather than only through an agent. Each states the
rule in **one identical sentence**; what follows that sentence is
file-specific and deliberately differs. Assertion 12 of
`lib/proxyme-paths.test.sh` pins the shared sentence and checks both directions
per file — present, and no superseded follow-the-user clause beside it — against
an explicit covered set rather than a recursive grep, for the reason assertion 9
already records.

`proxyme/AGENTS.md` describes this covered set but is not in it: it documents the
rule for contributors and is not interpolated into any prompt. A file joins the
covered set when it *sets* output language for a model, not when it explains it.

`voice_fidelity` is redefined as register fidelity **in en-US** — verdict first,
terse, conditions kept, no softening — and stays reported-only, never gating.
Every scorecard records `run.answer_language`.

Historical records keep their original quotes. ADRs, plans, specs and test
headers written before this decision are audit trail; rewriting them would
falsify what was actually said. The rule binds artifacts generated from here on.

**ADR-0005 is confirmed, not superseded.** It froze the operational-rules section
*number* on the grounds that heading text "is not stable across generations",
citing identity files carrying a translated heading. That premise survives this
decision intact and for the same reason: every identity file already on a user's
disk still carries whatever language it was generated in, and the shipped
staleness guard still reads those files. The new language check depends on that
instability rather than denying it — mismatched headings are exactly the signal
that a file predates ADR-0007. The number stays the only stable anchor.

## Consequences

A refresh that meets an identity file written before this decision converts it
in place and says so on its own line in the confirmation block. Appending to a
half-translated file is the one outcome worse than either language alone, and a
conversion that goes unreported reads exactly like a refresh that changed a few
bullets.

Scorecard comparability breaks at this boundary. A `voice_fidelity` score taken
while answers followed the installer's language and one taken after measure
different things. `rubric_scored` already recorded *which* dimensions produced an
average; `run.answer_language` now records what the actor was answering in when
they were measured, so the two are distinguishable by a later reader instead of
silently comparable.

The identity loses the installer's own phrasing as its surface text. That is the
accepted cost, bounded by the tag and by the anti-paraphrase rule: the *content*
of a heuristic is preserved completely, only its surface language changes.

Acceptance is a full loop, not a diff: the change is proven when a fresh identity
generation produces an en-US file with tagged translations and the validation
loop then scores it at or above the 8.5/10 gating threshold. A conversion that
quietly weakened a heuristic surfaces there and nowhere else.

## Alternatives

**Keep the split, translate downstream.** Rejected: that is the status quo, and
its translation step is invisible. Someone still translates; nobody records that
they did, and a lost condition looks identical to a preserved one.

**Translate but keep the original alongside every quote.** Rejected on the
explicit instruction that captured messages are always converted. It also leaves
the file carrying both languages, which is the half-converted state this ADR
exists to rule out.

**Translate without the tag.** Rejected: it reads cleaner and it is the one
option that makes the loss undetectable. A reader auditing a heuristic, or a
critic quoting a defect span, would be citing a translation as the user's exact
words with nothing to warn them.

**A per-project language setting.** Rejected: the consumer does not vary. Every
harness the proxy is read in runs in English, so a switch would only add a way
to get it wrong.
