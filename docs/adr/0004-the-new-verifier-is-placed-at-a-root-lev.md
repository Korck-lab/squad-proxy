# ADR-0004: The new verifier is placed at a root-level scripts/ directory, but ev...

- Status: accepted
- Date: 2026-08-04

## Context
Raised during decompose: The new verifier is placed at a root-level scripts/ directory, but every existing project script (bump-version.sh, sync-marketplace-cache.sh, install-hooks.sh) lives under proxyme/scripts/. The plan correctly follows the spec deliverable path and AC-1 (./scripts/verify-profile-design.sh), so this is non-blocking, but it introduces a second scripts location and diverges from the established convention.

## Decision
Same decision as ADR-0003, which this duplicates: root-level `scripts/` is
intentional and holds repository verification. This ADR is retained rather than
deleted because it records that the question was raised twice, from decompose as
well as from spec.

## Consequences
- `scripts/verify-profile-design.sh` stays where it is.
- Future reviews that re-raise the split should be answered with ADR-0003 rather than a third record.

## Alternatives
See ADR-0003.
