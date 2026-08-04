#!/bin/bash
# Install this repository's two git hooks:
#
#   pre-commit  auto-bump the proxyme version when any proxyme/ file is staged
#   pre-push    refuse to push a commit scripts/quality-gate.sh has not passed
#
# Both live in .git/hooks/, which git does not track, so a fresh clone has
# neither until this runs — that is exactly why scripts/verify-version-bump.sh
# checks the bump in history rather than trusting the hook to exist.
#
# Safe to run repeatedly — each hook is skipped if its marker is already there.
# Pass a hook name to install only that one.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
ONLY="${1:-}"

install_hook() {
  local name="$1" marker="$2" body="$3"
  local file="${REPO_ROOT}/.git/hooks/${name}"

  if [ -n "$ONLY" ] && [ "$ONLY" != "$name" ]; then
    return 0
  fi
  if [ -f "$file" ] && grep -qF "$marker" "$file"; then
    echo "Hook already installed in ${file}"
    return 0
  fi
  if [ ! -f "$file" ]; then
    printf '#!/bin/bash\n%s\n' "$body" > "$file"
  else
    cp "$file" "${file}.bak"
    printf '\n%s\n' "$body" >> "$file"
  fi
  chmod +x "$file"
  echo "Installed ${name} hook at ${file}"
}

install_hook pre-commit '# proxyme-auto-version-bump' \
'REPO_ROOT="$(git rev-parse --show-toplevel)"
# proxyme-auto-version-bump
"$REPO_ROOT/proxyme/scripts/bump-version.sh"'

install_hook pre-push '# proxyme-gate-receipt-guard' \
'REPO_ROOT="$(git rev-parse --show-toplevel)"
# proxyme-gate-receipt-guard
"$REPO_ROOT/scripts/prepush-guard.sh"'
