#!/bin/bash
# Bump the version in VERSION, plugin.json and marketplace.json — atomically.
#
# Bump level:
#   PROXYME_BUMP=patch (default) | minor | major
#   Exported for the one commit that needs it, e.g.
#     PROXYME_BUMP=minor git commit -m "feat!: ..."
#   The level is validated in phase 1, before anything is written, so an invalid
#   value fails the commit instead of producing a wrong version.
#
# Skip rule (amend/no-op guard):
#   The bump only runs when there is a STAGED DELTA vs HEAD inside proxyme/
#   (`git diff --cached HEAD --quiet -- proxyme/`). This covers both:
#     * nothing relevant staged at all, and
#     * `git commit --amend` re-running this hook with proxyme/ paths staged
#       but IDENTICAL to HEAD — a no-op amend must NOT re-bump +1.
#   An amend that stages NEW proxyme/ changes DOES re-bump: the sequence
#   stays monotonic and a version number is never reused for different
#   content (the number replaced by the amend is simply skipped — by design).
#   On an unborn branch (initial commit) the diff base is the empty tree, so
#   staged proxyme/ files still trigger the bump.
#
# Atomicity (scope: the REPO files only):
#   Everything is computed and validated BEFORE anything is written. If any
#   write fails mid-way, an ERR trap restores the original bytes (no partial
#   bump, no phantom version). Cache sync runs LAST, outside the rollback
#   window — it is regenerable; a cache failure never rolls back the repo.
set -Eeuo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
VERSION_FILE="$REPO_ROOT/proxyme/VERSION"
PLUGIN_JSON="$REPO_ROOT/proxyme/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

# --- Skip guard ---
if git -C "$REPO_ROOT" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
  base_ref="HEAD"
else
  base_ref="$(git -C "$REPO_ROOT" hash-object -t tree /dev/null)"
fi
if git -C "$REPO_ROOT" diff --cached --quiet "$base_ref" -- proxyme/; then
  exit 0
fi

# --- Phase 1: read + validate inputs (nothing written yet) ---
for f in "$VERSION_FILE" "$PLUGIN_JSON" "$MARKETPLACE_JSON"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: required file not found: $f" >&2
    exit 1
  fi
done

current=$(tr -d '[:space:]' < "$VERSION_FILE")

if ! printf '%s' "$current" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "ERROR: Invalid semver format '${current}' in VERSION file" >&2
  exit 1
fi

bump_level="${PROXYME_BUMP:-patch}"
case "$bump_level" in
  patch|minor|major) ;;
  *)
    echo "ERROR: PROXYME_BUMP must be patch, minor or major (got '${bump_level}')" >&2
    exit 1
    ;;
esac

IFS='.' read -r major minor patch <<< "$current"
case "$bump_level" in
  patch) new_version="${major}.${minor}.$((patch + 1))" ;;
  minor) new_version="${major}.$((minor + 1)).0" ;;
  major) new_version="$((major + 1)).0.0" ;;
esac

# --- Phase 2: backup originals + arm rollback ---
backup_dir="$(mktemp -d)"
cp "$VERSION_FILE" "$backup_dir/VERSION"
cp "$PLUGIN_JSON" "$backup_dir/plugin.json"
cp "$MARKETPLACE_JSON" "$backup_dir/marketplace.json"

rollback() {
  cp "$backup_dir/VERSION" "$VERSION_FILE" 2>/dev/null || true
  cp "$backup_dir/plugin.json" "$PLUGIN_JSON" 2>/dev/null || true
  cp "$backup_dir/marketplace.json" "$MARKETPLACE_JSON" 2>/dev/null || true
  rm -rf "$backup_dir"
  echo "ERROR: version bump failed; original file contents restored (no partial bump)" >&2
}
trap rollback ERR

# --- Phase 3: compute + validate ALL new contents, then write ---
python3 - "$VERSION_FILE" "$PLUGIN_JSON" "$MARKETPLACE_JSON" "$current" "$new_version" <<'PY'
import json, re, sys

version_path, plugin_path, marketplace_path, current, new_version = sys.argv[1:6]


def die(msg):
    sys.stderr.write("ERROR: %s\n" % msg)
    sys.exit(1)


originals = {}
for path in (version_path, plugin_path, marketplace_path):
    try:
        with open(path) as fh:
            originals[path] = fh.read()
    except OSError as exc:
        die("cannot read %s: %s" % (path, exc))

# plugin.json: must be valid JSON and contain the old version verbatim.
try:
    json.loads(originals[plugin_path])
except ValueError as exc:
    die("%s is not valid JSON: %s" % (plugin_path, exc))
pattern = re.compile(r'("version"\s*:\s*)"%s"' % re.escape(current))
new_plugin, count = pattern.subn(
    lambda m: m.group(1) + '"%s"' % new_version, originals[plugin_path], count=1
)
if count != 1:
    die(
        '%s does not contain "version": "%s" (drifted from VERSION); '
        "refusing silent no-op" % (plugin_path, current)
    )
json.loads(new_plugin)  # sanity: substituted content still parses

# marketplace.json: must be valid JSON with a proxyme entry.
try:
    marketplace = json.loads(originals[marketplace_path])
except ValueError as exc:
    die("%s is not valid JSON: %s" % (marketplace_path, exc))
entries = [
    e for e in marketplace.get("plugins", [])
    if isinstance(e, dict) and e.get("name") == "proxyme"
]
if not entries:
    die("%s has no 'proxyme' plugin entry" % marketplace_path)
for entry in entries:
    entry["version"] = new_version
new_marketplace = json.dumps(marketplace, indent=2, ensure_ascii=False) + "\n"

# Everything validated — write the three files.
for path, content in (
    (version_path, new_version + "\n"),
    (plugin_path, new_plugin),
    (marketplace_path, new_marketplace),
):
    try:
        with open(path, "w") as fh:
            fh.write(content)
    except OSError as exc:
        die("write failed for %s: %s" % (path, exc))
PY

# --- Phase 4: stage (still under the rollback trap) ---
git -C "$REPO_ROOT" add -- "$VERSION_FILE" "$PLUGIN_JSON" "$MARKETPLACE_JSON"

trap - ERR
rm -rf "$backup_dir"

# --- Phase 5: cache sync — AFTER the trap is disarmed ---
SYNC_SCRIPT="$(dirname "$0")/sync-marketplace-cache.sh"
if [ -x "$SYNC_SCRIPT" ]; then
  "$SYNC_SCRIPT" "$new_version" "$REPO_ROOT"
fi

echo "Bumped version (${bump_level}): ${current} -> ${new_version}"
