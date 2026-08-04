---
name: english-us-normalization
description: Every tracked artifact in this repository is written in en-US — docs, skills, code, comments, commit messages, issues and PRs.
---

## Rule

Everything this repository tracks is written in **en-US**: guardrails, ADRs, specs, plans, `AGENTS.md` files, skill and agent definitions, shell and code comments, the strings a test prints, commit messages, and issue and pull-request text. Prefer American spelling over British (`behavior`, `normalize`, `license` as a noun).

The repository is public and its skills load into a model's context on every invocation. One language across the tree means a contributor never has to switch to read the rule that binds their change, and a reader of a diff never has to guess whether a phrase is a term of art or a translation.

## Three exceptions, and nothing else

1. **A quote of someone's own words stays in the language they said it in.** Test headers, evidence blocks and rationale comments that cite what a user or reviewer actually wrote are evidence; translating a quote falsifies it. Quote verbatim, then explain in en-US around it.
2. **Product output follows the user, not this rule.** The skills instruct their agents to answer in the language the user is writing in, and the identity file's generated `[auto]` sections are written in the user's language. That is behavior the product ships, not prose this repository authors. Only the shipped template text inside those artifacts is bound by this rule.
3. **Third-party identifiers are never translated** — API names, CLI flags, config keys, error strings, file names.

## Applies to generated identity files

`/proxyme-identity` writes `<root>/.claude/proxyme/<user>-identity.md`. Its `[auto]` sections follow the user's language (exception 2). Its operational-rules section is shipped template text and is copied **verbatim in en-US**, untranslated — translation is where a clause silently loses a condition, and that section is the one the proxy's authority is read from. A user-authored carve-out block appended to that section is the user's own words and stays in whatever language they wrote it (exception 1).
