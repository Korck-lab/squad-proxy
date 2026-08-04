#!/usr/bin/env bash
#
# quality-gate.sh — the whole of "CI" for this repository, run locally, plus the
# land that publishes the version it just gated.
#
#   scripts/quality-gate.sh              # gate HEAD, write a receipt
#   scripts/quality-gate.sh --land       # gate, then push, PR, merge, verify the remote
#   scripts/quality-gate.sh --land --title "..."   # PR title (default: last commit subject)
#
# Run it after any change that touches `proxyme/` — the plugin is published from
# this repository to a marketplace, so a broken or mis-versioned commit on main
# is a broken install for anyone who reloads plugins.
#
# There is no hosted CI here: this script is the executor, not a mirror of one,
# so every check has exactly one definition and the list below is it. Checks run
# cheapest-first, because a version typo should not wait on the mutation harness.
#
# The receipt is what makes the policy enforceable rather than merely documented:
# `git push` refuses a commit with no receipt once
# `proxyme/scripts/install-hooks.sh` has installed the pre-push guard. Bypass
# with PROXYME_GATE_BYPASS=1, which logs rather than hides.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LAND=0
PR_TITLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --land) LAND=1; shift ;;
    --title) PR_TITLE="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

FAILED=0
step()  { printf '\n=== %s\n' "$*"; }
ok()    { echo "  OK   $*"; }
bad()   { echo "  FAIL $*" >&2; FAILED=$((FAILED+1)); }

# run_check <label> <command...> — one definition of "this check ran and passed".
# Output is kept and printed only on failure: a green gate should be readable,
# and a red one should quote the decisive lines rather than bury them.
run_check() {
  local label="$1"; shift
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "$label"
  else
    bad "$label (exit $rc)"
    printf '%s\n' "$out" | grep -E '^(FAIL|RESULT|.*Error|.*error:)' | head -12 | sed 's/^/       /' >&2
    [ -z "$(printf '%s\n' "$out" | grep -E '^(FAIL|RESULT)')" ] && printf '%s\n' "$out" | tail -8 | sed 's/^/       /' >&2
  fi
  return 0
}

# --- Phase 1: cheap state checks ---------------------------------------------
step "Phase 1 — state"

run_check "shell syntax (bash -n over every tracked .sh)" bash -c '
  rc=0
  for f in $(git ls-files "*.sh"); do bash -n "$f" || rc=1; done
  exit $rc'

run_check "version triple agrees (VERSION, plugin.json, marketplace.json)" \
  ./scripts/verify-version-bump.sh --state-only

# Advisory, never gating. The en-US rule has three exceptions — verbatim quotes,
# product output, third-party identifiers — so a hard ban on accented characters
# would fail a correctly quoted user sentence. Reported so it is seen, not
# enforced so it is wrong.
ACCENTED="$(for f in $(git ls-files); do LC_ALL=C grep -lqE 'ç|ã|õ|é|ê|á|â|í|ó|ô|ú' "$f" 2>/dev/null && echo "$f"; done)"
if [ -n "$ACCENTED" ]; then
  echo "  NOTE non-ASCII Latin text in tracked files — check against docs/guardrails/english-us-normalization.md:"
  printf '%s\n' "$ACCENTED" | sed 's/^/         /'
else
  ok "en-US sweep: no accented text in tracked files"
fi

# --- Phase 2: the suites ------------------------------------------------------
step "Phase 2 — suites"

run_check "path module, canonical fragments, section freeze" \
  bash proxyme/lib/proxyme-paths.test.sh
run_check "mutation arms (the assertions above detect their drift)" \
  bash proxyme/lib/proxyme-paths.mutation.test.sh
run_check "identity skill: SMART-CLIP filter" \
  bash proxyme/skills/proxyme-identity/proxyme-identity.test.sh
run_check "validate skill: scorecard invariants" \
  bash proxyme/skills/proxyme-validate/proxyme-validate.test.sh
run_check "profile design doc" \
  bash scripts/verify-profile-design.sh
run_check "version bump per plugin-touching commit" \
  ./scripts/verify-version-bump.sh
run_check "version verifier catches an unbumped commit" \
  ./scripts/verify-version-bump.test.sh
run_check "pre-push guard blocks an unGated commit" \
  ./scripts/prepush-guard.test.sh

# --- Verdict ------------------------------------------------------------------
VERSION="$(tr -d '[:space:]' < proxyme/VERSION)"
SHA="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [ "$FAILED" -ne 0 ]; then
  printf '\nRESULT: %d check(s) failed at %s on %s — nothing was pushed\n' "$FAILED" "${SHA:0:7}" "$BRANCH" >&2
  exit 1
fi

RECEIPT_DIR="$(git rev-parse --git-dir)/proxyme-gate"
mkdir -p "$RECEIPT_DIR"
printf '{"sha":"%s","branch":"%s","version":"%s","gated_at":"%s","dirty":%s}\n' \
  "$SHA" "$BRANCH" "$VERSION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$([ -n "$(git status --porcelain)" ] && echo true || echo false)" \
  > "$RECEIPT_DIR/receipt.json"

printf '\nRESULT: gate green at %s on %s, version %s\n' "${SHA:0:7}" "$BRANCH" "$VERSION"
echo "Receipt: $RECEIPT_DIR/receipt.json"

# A dirty tree means the receipt covers a commit that is not what was tested.
if [ -n "$(git status --porcelain)" ]; then
  echo "NOTE: working tree is dirty — the receipt covers ${SHA:0:7}, not your uncommitted changes" >&2
fi

[ "$LAND" -eq 0 ] && exit 0

# --- Phase 3: land ------------------------------------------------------------
step "Phase 3 — land"

if [ -n "$(git status --porcelain)" ]; then
  echo "  FAIL refusing to land a dirty tree — commit or stash first" >&2
  exit 1
fi
if [ "$BRANCH" = "main" ]; then
  echo "  FAIL on main: this repository lands through a pull request, so create a branch first" >&2
  exit 1
fi
command -v gh >/dev/null 2>&1 || { echo "  FAIL gh CLI not found; cannot open or merge the pull request" >&2; exit 1; }

[ -n "$PR_TITLE" ] || PR_TITLE="$(git log -1 --format=%s)"

git push -q -u origin "$BRANCH" || { echo "  FAIL push rejected" >&2; exit 1; }
ok "pushed $BRANCH"

PR="$(gh pr list --head "$BRANCH" --state open --json number -q '.[0].number' 2>/dev/null || true)"
if [ -z "$PR" ]; then
  gh pr create --base main --head "$BRANCH" --title "$PR_TITLE" \
    --body "Landed by \`scripts/quality-gate.sh --land\` with a green local gate at ${SHA:0:7}, version $VERSION.

Checks run: shell syntax, version triple, path module, mutation arms, identity SMART-CLIP filter, validate scorecard invariants, profile design doc, version-bump-per-commit, and the version verifier's own arms." >/dev/null \
    || { echo "  FAIL could not create the pull request" >&2; exit 1; }
  PR="$(gh pr list --head "$BRANCH" --state open --json number -q '.[0].number')"
  ok "opened PR #$PR"
else
  ok "reusing open PR #$PR"
fi

gh pr merge "$PR" --merge --delete-branch --subject "merge: $PR_TITLE (#$PR)" >/dev/null \
  || { echo "  FAIL merge rejected for PR #$PR" >&2; exit 1; }
ok "merged PR #$PR"

# The land is not done when the merge returns — it is done when the remote
# announces the version this gate approved. Anything else is a report of
# intention rather than of outcome.
git fetch -q origin
REMOTE_VERSION="$(git show origin/main:proxyme/VERSION | tr -d '[:space:]')"
REMOTE_MARKET="$(git show origin/main:.claude-plugin/marketplace.json | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '[0-9][0-9.]*')"
if [ "$REMOTE_VERSION" = "$VERSION" ] && [ "$REMOTE_MARKET" = "$VERSION" ]; then
  ok "origin/main serves version $VERSION (VERSION and marketplace.json agree)"
else
  echo "  FAIL origin/main announces VERSION=$REMOTE_VERSION marketplace=$REMOTE_MARKET, gate approved $VERSION" >&2
  exit 1
fi

printf '\nRESULT: version %s landed on origin/main via PR #%s\n' "$VERSION" "$PR"
exit 0
