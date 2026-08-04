---
name: english-us-normalization
description: Everything this repository tracks and everything the product emits is en-US — docs, skills, code, comments, commit messages, issues and PRs, the generated identity file, the proxy's answer, and every status block a skill prints.
---

## Rule

Everything this repository tracks is written in **en-US**: guardrails, ADRs, specs, plans, `AGENTS.md` files, skill and agent definitions, shell and code comments, the strings a test prints, commit messages, and issue and pull-request text. Prefer American spelling over British (`behavior`, `normalize`, `license` as a noun).

The repository is public and its skills load into a model's context on every invocation. One language across the tree means a contributor never has to switch to read the rule that binds their change, and a reader of a diff never has to guess whether a phrase is a term of art or a translation.

**The product's own output is bound by the same rule** (ADR-0007). The generated identity file, the proxy's answer, the validation loop's questions and scorecards, and the status blocks the skills print are all en-US, whatever language the installer writes in. This is not a stylistic preference: the proxy exists to be read by autonomous agents that run in English in every harness, and `/proxyme` instructs the main agent to relay the proxy's answer **verbatim** as the user's decision. An answer in another language puts a translation step between the decision and the action — and translation is where a clause silently loses a condition, which is the reason this repository already refuses to translate the operational-rules section.

## Three exceptions, and nothing else

1. **Quoted user text is translated to en-US and tagged with its source language** — `"…" [translated from pt-BR]`. Translating a quote does destroy its verbatim property, and the tag is what keeps that loss visible instead of silent: nobody reading a tagged line can mistake it for the user's exact words. Translating is not license to paraphrase — every negation, condition and hedge survives, and a blunt sentence stays blunt. A quote whose source is already English carries no tag. Historical records already in the tree — ADRs, plans, specs, test headers written before ADR-0007 — keep their original quotes: they are audit trail, and rewriting them would falsify what was actually said.
2. **Third-party identifiers are never translated** — API names, CLI flags, config keys, error strings, file names.
3. **Synthetic non-English test input stays in the language it exercises.** A fixture whose whole job is to prove the pipeline handles a non-English turn cannot be written in English — translating it deletes the condition under test. This covers fixture *input* only, never a fixture's prose, comments, or expected output, and the fixture must be synthetic: real captured user text is exception 1, and personal content never enters a tracked file at all.

## Applies to generated identity files

`/proxyme-identity` writes `<root>/.claude/proxyme/<user>-identity.md`. The **whole file** is en-US: the generated `[auto]` sections, the section headings, and the user-authored carve-out block appended to the operational-rules section, whose content is preserved completely and rendered as a tagged translation (exception 1). Its operational-rules section is shipped template text and is copied **verbatim in en-US**, untranslated and unreworded — translation is where a clause silently loses a condition, and that section is the one the proxy's authority is read from. ADR-0007 widened the rule around that section; it did not touch the section's own treatment.

A refresh that meets an identity file written before ADR-0007 **converts it in place** rather than appending to it, and names the conversion in its report. A half-converted file is worse than either language on its own, and a conversion that goes unreported reads exactly like a refresh that changed a few bullets.

## Where the rule is set, and what fails if it drifts

Five shipped files state one identical sentence: `proxyme/lib/terse-contract.md`, which every agent prompt interpolates, and the four skills that also print their own status blocks without spawning an agent. Assertion 12 of `proxyme/lib/proxyme-paths.test.sh` checks both directions per file — the sentence is present, and no superseded follow-the-user clause survives beside it — because a reverted clause reads as a correct sentence wherever it lands and would otherwise be invisible. `proxyme/lib/proxyme-paths.mutation.test.sh` proves that check detects its own drift.
