# proxyme/ — the shipped plugin

## Purpose

Everything inside this directory ships to users as the `proxyme` plugin: the
skills (`skills/`), the read-only proxy agent (`agents/`), the canonical prompt
fragments and path module (`lib/`), and the maintenance scripts
(`scripts/`). Content here is loaded into a model's context or executed on a
user's machine, so it is a product surface, not working material.

## Ownership

- `lib/` — one home for anything more than one skill needs: `proxyme-paths.sh`
  (the single definition of where project state lives), `carve-outs.md` and
  `terse-contract.md` (canonical prompt text, interpolated by skills rather than
  restated in them), `smart-clip.sh`.
- `skills/<name>/` — one skill per directory, its fixtures beside it.
- Evidence of a real run lives in a colocated `.test.sh`, never inline in a
  `SKILL.md`: a skill body is loaded into the model's context on every
  invocation, and evidence prose there is paid for on every call.

## Local Contracts

### Everything here is written in en-US, and everything it produces is too

Skills, agents, `lib/` fragments, comments and the strings a test prints — and,
since ADR-0007, the product's own output: the generated identity file, the
proxy's answer, and every status block a skill prints. The consumer is an agent
running in English and it executes the proxy's answer verbatim, so following the
installer's language would put a translation step between the decision and the
action. The two remaining exceptions — quoted user text, which is translated to
en-US and tagged with its source language, and third-party identifiers, which
are never translated — are in
`docs/guardrails/english-us-normalization.md`. The identity template's Section 7
is shipped text and is copied into generated files verbatim, untranslated.

The rule is **set** in five shipped files: `lib/terse-contract.md`, which every
agent prompt interpolates, plus the four skills that also print status blocks of
their own directly to the user (`proxyme`, `proxyme-identity`, `proxyme-model`,
`proxyme-validate`). One identical sentence in all five; what each file adds
after that sentence is file-specific. Assertion 12 of
`lib/proxyme-paths.test.sh` fails the build if the shared sentence drifts or if a
superseded follow-the-user clause reappears beside it.

This file **describes** the rule and is deliberately not in that covered set — it
is contributor documentation, never interpolated into a prompt. A file joins the
covered set when it tells a model what language to answer in, not when it
explains the policy.

### Section 7, the operational-rules section, is a frozen number

`## 7. Proxy operational rules` is not a source-internal constant. The number is
already written into every identity file on every user's disk, and the shipped
staleness guard in `skills/proxyme-identity/SKILL.md` reads THOSE files with
`sed -n '/^## 7\./,$p'`. Renumbering the template renumbers only this repo: the
guard then scopes for a section that a user's existing identity does not have,
extracts nothing, and reports "nothing stale" forever — silently, which is the
worst shape this failure can take. Handling files written by older versions is
explicitly in that skill's scope.

**Migration precondition.** Before any renumber, a guard that reads BOTH
generations must ship first. Renumber only after that guard is released.

**Covered files.** These shipped files name Section 7 in prose and are checked
individually by `lib/proxyme-paths.test.sh` (assertion 9, check (c)):

- `lib/carve-outs.md`
- `skills/proxyme-identity/SKILL.md`
- `AGENTS.md` (this file)

Adding prose that names the section to any other shipped file means adding that
file to `SECTION_REF_FILES` in the test — the covered set is an explicit list, so
a new file is not covered until it is listed. Prose about a *different* section
of the template (it defines 1 through 7) is fine and is not constrained.

The mechanical values — the template heading, the guard's `sed` anchor, and the
fixture at `skills/proxyme-identity/fixtures/stale-flags.md` — are frozen by the
same assertion. Rationale is recorded in `docs/adr/0005-the-operational-rules-section-number-is.md`.

### The running version is stated, never assumed

A marketplace install lives at `<cache>/proxyme/<version>/` and the cache keeps
several versions at once, so a skill can launch from an older one while a newer
is installed. Every path is derived from the running copy's own location, so that
older copy's `lib/` is what actually executes. `proxyme-paths.sh` exports
`PROXYME_VERSION`, `PROXYME_VERSION_LATEST` and `PROXYME_VERSION_NOTE`; every
skill prints the note as its first line when it is non-empty and prints nothing
when it is empty. Running an older version deliberately is fine — not knowing
which one ran is not.

### Per-project state written by the skills

`PROXYME_DIR` holds everything a run writes for a project: the identity, the
config, the project carve-outs, and `PROXYME_SCORECARDS` for `/proxyme-validate`.
All of it is user data, excluded from git, and never committed or copied into the
global template directory.

## Work Guidance

- Change a canonical `lib/` fragment in one place; skills interpolate it. A
  second copy in the shipped tree is a build failure, by design.
- Prefer asserting on a shipped artifact's observable behaviour over restating
  its algorithm in a test: a test that restates the algorithm stays green
  through a full revert of the fix it protects.

## Verification

**One command after any change under `proxyme/`:**

```bash
scripts/quality-gate.sh            # every check below, cheapest first
scripts/quality-gate.sh --land     # …then push, open the PR, merge, and verify origin/main serves the new version
```

There is no hosted CI: this script is the executor, not a mirror of one, so the
check list has exactly one definition and that file is it. A green run writes a
receipt to `<git-dir>/proxyme-gate/receipt.json`; the `pre-push` hook installed
by `proxyme/scripts/install-hooks.sh` refuses to push a commit with no matching
receipt. Bypass with `PROXYME_GATE_BYPASS=1`, which logs to
`<git-dir>/proxyme-gate/bypasses.log` rather than hiding.

Individual checks, runnable on their own; each resolves its own paths.

```bash
proxyme/lib/proxyme-paths.test.sh              # path module, canonical fragments, section freeze
proxyme/lib/proxyme-paths.mutation.test.sh     # mutation arms proving the above assertions detect drift
proxyme/skills/proxyme-identity/proxyme-identity.test.sh
proxyme/skills/proxyme-validate/proxyme-validate.test.sh
scripts/verify-profile-design.sh               # repo-level, outside the plugin
scripts/verify-version-bump.sh                 # version triple agrees; every plugin-touching commit bumps
scripts/verify-version-bump.test.sh            # arms proving that verifier catches an unbumped commit
scripts/prepush-guard.test.sh                  # arms proving the guard blocks an unGated push
```

The version checks exist because the bump lives in an untracked hook: a clone
that never ran `install-hooks.sh` ships plugin changes under a frozen version,
and the marketplace then serves new content under a number every cache already
holds. See `docs/adr/0006-ci-is-local-and-the-gate-lands-the-vers.md`.

The mutation harness copies the plugin tree to a throwaway directory, applies
one named mutation per arm, and asserts that a NAMED assertion in the paths
suite fails — never that the exit status was merely nonzero. It never writes to
the working tree. Adding or changing an assertion there means adding an arm.

## Child DOX Index

None. Skill directories are covered by this document.
