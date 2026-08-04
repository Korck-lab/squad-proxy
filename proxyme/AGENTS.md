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

### Everything tracked here is written in en-US

Skills, agents, `lib/` fragments, comments and the strings a test prints. The
three exceptions — verbatim quotes, product output that follows the user's
language, third-party identifiers — are in
`docs/guardrails/english-us-normalization.md`. The identity template's Section 7
is shipped text and is copied into generated files verbatim, untranslated.

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

## Work Guidance

- Change a canonical `lib/` fragment in one place; skills interpolate it. A
  second copy in the shipped tree is a build failure, by design.
- Prefer asserting on a shipped artifact's observable behaviour over restating
  its algorithm in a test: a test that restates the algorithm stays green
  through a full revert of the fix it protects.

## Verification

Run from anywhere; each script resolves its own paths.

```bash
proxyme/lib/proxyme-paths.test.sh              # path module, canonical fragments, section freeze
proxyme/lib/proxyme-paths.mutation.test.sh     # mutation arms proving the above assertions detect drift
proxyme/skills/proxyme-identity/proxyme-identity.test.sh
proxyme/skills/proxyme-validate/proxyme-validate.test.sh
scripts/verify-profile-design.sh               # repo-level, outside the plugin
```

The mutation harness copies the plugin tree to a throwaway directory, applies
one named mutation per arm, and asserts that a NAMED assertion in the paths
suite fails — never that the exit status was merely nonzero. It never writes to
the working tree. Adding or changing an assertion there means adding an arm.

## Child DOX Index

None. Skill directories are covered by this document.
