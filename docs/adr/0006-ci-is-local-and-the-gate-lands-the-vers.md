# ADR-0006: CI is local, and the gate is what lands the version

- Status: accepted
- Date: 2026-08-04

## Context

This repository publishes a plugin. `Korck-lab/proxyme` is also a Claude Code
marketplace: `.claude-plugin/marketplace.json` on `main` is what every installed
copy resolves against, and `autoUpdate` is on. A broken or mis-versioned commit
on `main` is a broken install for anyone who reloads plugins, with no build step
in between to catch it.

Two properties were maintained by an untracked file and verified by nothing:

- The version bump. `.git/hooks/pre-commit` calls `bump-version.sh`, which moves
  `proxyme/VERSION`, `proxyme/.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json` together. A clone that never ran
  `proxyme/scripts/install-hooks.sh` commits plugin changes with the version
  frozen. The marketplace then serves new content under a number every cache
  already holds, and the stale copy wins — the exact silent failure that
  motivated the version-skew reporting in 0.7.9.
- "Run the tests before pushing." Five suites existed and nothing required them.

The repository has no hosted CI, and the marketplace has no build step that
could act as one.

## Decision

CI compute is local, and the local runner is the executor rather than a mirror of
a hosted one. `scripts/quality-gate.sh` is the single definition of what green
means here: shell syntax, the version triple, the five suites, the version-bump
history check, and the arms that prove the two new verifiers catch what they
claim. Cheapest checks run first.

A green run writes a receipt to `<git-dir>/proxyme-gate/receipt.json`, and the
`pre-push` hook refuses any commit without a matching one. The receipt names the
sha and whether the tree was dirty, so a receipt written before a further commit,
or over uncommitted work, blocks rather than passes. `PROXYME_GATE_BYPASS=1`
pushes anyway and appends to `bypasses.log` — it exists so nobody reaches for
`git push --no-verify`, which would skip every hook and leave no record.

`--land` publishes what it just gated: push, open or reuse the pull request,
merge, then read `proxyme/VERSION` and `.claude-plugin/marketplace.json` back out
of `origin/main` and fail unless both announce the gated version. A merge that
returns successfully is not the same as a marketplace serving the new version.

`scripts/verify-version-bump.sh` carries the assertion the hook was assumed to
guarantee: every non-merge commit that touches `proxyme/` bumps `VERSION`
strictly forward, and the three version files agree. Merges are exempt — they
carry a branch's files without authoring them.

## Consequences

- A commit that changes the plugin without a bump is a build failure, on any
  machine, whether or not the hook is installed.
- Pushing without gating requires an explicit, logged bypass.
- The land step fails loudly when the remote does not serve the gated version,
  instead of reporting a successful merge and leaving the check to a human.
- Both new verifiers ship with mutation-style arms of their own, so "this
  assertion catches its defect" is proven rather than asserted — the same
  standard `proxyme-paths.mutation.test.sh` set for the suite.
- The gate is a few minutes of local compute on every plugin change. That is the
  price of having no hosted CI, and it is paid where the failure would otherwise
  be found: before publication.

## Alternatives

- **GitHub Actions.** Rejected for now: the repository has no branch protection
  and no required checks, so a workflow would report rather than gate, and the
  version bump — the property that actually breaks installs — is produced by a
  local hook that a hosted runner cannot observe before the commit exists.
- **Trust the pre-commit hook.** Rejected: it is untracked by construction, so
  trusting it means trusting that every clone ran an install script, which is
  precisely the assumption that fails silently.
- **A hard ban on non-ASCII text as part of the gate.** Rejected: the en-US rule
  has three documented exceptions, one of which is verbatim quotes of the user's
  own words. The sweep is reported as an advisory line instead.
