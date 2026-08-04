#!/usr/bin/env bash
#
# verify-version-bump.sh — the version contract, checked rather than trusted.
#
#   scripts/verify-version-bump.sh                  # HEAD state + origin/main..HEAD history
#   scripts/verify-version-bump.sh --range A..B     # check an explicit commit range
#   scripts/verify-version-bump.sh --state-only     # skip history, check HEAD's three files
#
# Two properties, both of which the pre-commit hook is SUPPOSED to maintain and
# neither of which anything verified until now:
#
#   1. The three version files agree. `proxyme/VERSION`,
#      `proxyme/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
#      are read by different consumers — the path module, the plugin loader, and
#      the marketplace — so a partial bump installs one version while announcing
#      another.
#
#   2. Every non-merge commit that touches `proxyme/` also bumps `VERSION`, to a
#      STRICTLY GREATER version. The bump lives in `.git/hooks/pre-commit`, which
#      is not tracked: a clone that never ran `proxyme/scripts/install-hooks.sh`
#      commits plugin changes with the version frozen, and nothing says so. The
#      marketplace then serves new content under an old version number, and every
#      cache that already holds that number keeps the stale copy.
#
# Merge commits are exempt: they carry their branch's files without authoring
# them, and requiring a bump there would demand a version per merge.
#
# Exits 0 when every assertion holds, 1 otherwise, naming each offending commit.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="proxyme/VERSION"
PLUGIN_JSON="proxyme/.claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"

RANGE=""
STATE_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --range) RANGE="${2:-}"; shift 2 ;;
    --state-only) STATE_ONLY=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

FAILS=0
fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS+1)); }
pass() { echo "PASS: $*"; }

# version_in <file-content-kind> — the version a given file announces.
version_of_plugin_json()      { grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '[0-9][0-9.]*'; }
version_of_marketplace_json() { grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '[0-9][0-9.]*'; }

# --- 1. the three files agree at HEAD's working tree --------------------------
V_VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/$VERSION_FILE" 2>/dev/null || true)"
V_PLUGIN="$(version_of_plugin_json < "$REPO_ROOT/$PLUGIN_JSON" 2>/dev/null || true)"
V_MARKET="$(version_of_marketplace_json < "$REPO_ROOT/$MARKETPLACE_JSON" 2>/dev/null || true)"

if [ -z "$V_VERSION" ]; then
  fail "$VERSION_FILE is missing or empty"
elif [ "$V_PLUGIN" != "$V_VERSION" ]; then
  fail "$PLUGIN_JSON announces '$V_PLUGIN', $VERSION_FILE says '$V_VERSION'"
elif [ "$V_MARKET" != "$V_VERSION" ]; then
  fail "$MARKETPLACE_JSON announces '$V_MARKET', $VERSION_FILE says '$V_VERSION'"
else
  pass "version $V_VERSION agrees across VERSION, plugin.json and marketplace.json"
fi

[ "$STATE_ONLY" -eq 1 ] && { [ "$FAILS" -eq 0 ] && exit 0 || exit 1; }

# --- 2. every plugin-touching commit in range bumped VERSION ------------------
# Default range: what this branch adds on top of the published main. On main
# itself the range is empty and the history check passes trivially — the state
# check above still runs, which is the point of splitting them.
if [ -z "$RANGE" ]; then
  if git -C "$REPO_ROOT" rev-parse --verify -q origin/main >/dev/null; then
    RANGE="origin/main..HEAD"
  else
    RANGE="HEAD~1..HEAD"
  fi
fi

COMMITS="$(git -C "$REPO_ROOT" log --no-merges --format=%H "$RANGE" 2>/dev/null || true)"
if [ -z "$COMMITS" ]; then
  pass "no non-merge commits in $RANGE to check"
else
  CHECKED=0
  for sha in $COMMITS; do
    FILES="$(git -C "$REPO_ROOT" show --name-only --format= "$sha" || true)"
    printf '%s\n' "$FILES" | grep -q '^proxyme/' || continue
    CHECKED=$((CHECKED+1))
    SUBJECT="$(git -C "$REPO_ROOT" log -1 --format=%s "$sha" | cut -c1-60)"
    if ! printf '%s\n' "$FILES" | grep -qx "$VERSION_FILE"; then
      fail "${sha:0:7} touches proxyme/ without bumping $VERSION_FILE — '$SUBJECT'
      the pre-commit bump did not run; install it with proxyme/scripts/install-hooks.sh"
      continue
    fi
    BEFORE="$(git -C "$REPO_ROOT" show "${sha}^:$VERSION_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
    AFTER="$(git -C "$REPO_ROOT" show "${sha}:$VERSION_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
    # Strictly greater, compared field by field — a rollback or a repeated
    # number republishes different content under a version some cache already
    # holds, which is the failure the bump exists to prevent.
    NEWEST="$(printf '%s\n%s\n' "$BEFORE" "$AFTER" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
    if [ -z "$BEFORE" ]; then
      pass "${sha:0:7} introduces $VERSION_FILE at $AFTER"
    elif [ "$AFTER" = "$BEFORE" ] || [ "$NEWEST" != "$AFTER" ]; then
      fail "${sha:0:7} moved $VERSION_FILE from $BEFORE to $AFTER — not a forward bump — '$SUBJECT'"
    else
      pass "${sha:0:7} bumped $BEFORE -> $AFTER"
    fi
  done
  [ "$CHECKED" -eq 0 ] && pass "no commit in $RANGE touches proxyme/"
fi

if [ "$FAILS" -ne 0 ]; then
  echo "RESULT: $FAILS version assertion(s) failed" >&2
  exit 1
fi
echo "RESULT: version contract holds"
exit 0
