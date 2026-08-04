# ADR-0003: Existing project scripts live under proxyme/scripts/ (bump-version, i...

- Status: accepted
- Date: 2026-08-04

## Context
Raised during spec: Existing project scripts live under proxyme/scripts/ (bump-version, install-hooks, sync-marketplace-cache); the new verification script is placed at repo-root scripts/, splitting the script-location convention.

## Decision
Keep both directories. They hold different kinds of thing, and the release sync
already encodes the difference: `proxyme/scripts/` holds release tooling and is
excluded from the shipped payload (`--exclude='/scripts/'` in
`sync-marketplace-cache.sh`), so those scripts never reach a user's plugin cache.
Repo-root `scripts/` holds verification that runs against this repository and is
likewise not part of the plugin. Shared shell that *does* ship belongs in
`proxyme/lib/`, which is where `proxyme-paths.sh` and `smart-clip.sh` live.

## Consequences
- A new script has an unambiguous home: ships and is called by a skill -> `proxyme/lib/`; release tooling -> `proxyme/scripts/`; repository verification -> root `scripts/`.
- The rule is testable rather than conventional: anything in `proxyme/lib/` is asserted to resolve by `proxyme-paths.test.sh`.
- Nothing moves, so no path in any skill, hook or CI step changes.

## Alternatives
- **Consolidate into one directory.** Rejected: it would put non-shipping tooling inside the shipped payload or require a new exclude rule per file.
- **Move the root verifier under `proxyme/scripts/`.** Rejected: it verifies a repository document, not the plugin, and would then be excluded from the payload for the wrong reason.
