#!/usr/bin/env bash
#
# prepush-guard.sh — refuse to push a commit the local gate has not passed.
#
# Installed as `.git/hooks/pre-push` by proxyme/scripts/install-hooks.sh. Git
# hands a pre-push hook one line per ref on stdin:
#
#     <local-ref> <local-sha> <remote-ref> <remote-sha>
#
# For every non-deletion we demand a receipt from `scripts/quality-gate.sh`
# covering exactly that sha. Without this, "run the gate before pushing" is a
# documented intention, and this repository publishes a plugin: an unGated
# commit on main is a broken install for anyone who reloads plugins.
#
# Deletions carry the all-zero sha — no content to gate, so they pass.
#
# Escape hatch: PROXYME_GATE_BYPASS=1 pushes anyway, prints a loud warning and
# appends to <git-dir>/proxyme-gate/bypasses.log. It exists so nobody reaches
# for `git push --no-verify`, which would skip every hook silently. A bypass is
# recorded, never invisible.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
GATE_DIR="$(git rev-parse --git-dir)/proxyme-gate"
RECEIPT="$GATE_DIR/receipt.json"
ZERO="0000000000000000000000000000000000000000"

json_field() { grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$RECEIPT" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//'; }

bypass() {
  mkdir -p "$GATE_DIR"
  printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:-}" >> "$GATE_DIR/bypasses.log"
  echo "WARNING: PROXYME_GATE_BYPASS=1 — pushing $1 without a gate receipt, recorded in $GATE_DIR/bypasses.log" >&2
}

BLOCKED=0
while read -r _local_ref local_sha _remote_ref _remote_sha; do
  [ -n "${local_sha:-}" ] || continue
  [ "$local_sha" = "$ZERO" ] && continue

  RECEIPT_SHA="$(json_field sha)"
  RECEIPT_DIRTY="$(grep -o '"dirty"[[:space:]]*:[[:space:]]*[a-z]*' "$RECEIPT" 2>/dev/null | grep -o '[a-z]*$')"

  if [ -n "${PROXYME_GATE_BYPASS:-}" ]; then
    bypass "${local_sha:0:7}" "${RECEIPT_SHA:-no-receipt}"
    continue
  fi

  if [ ! -f "$RECEIPT" ]; then
    echo "BLOCKED ${local_sha:0:7}: no gate receipt. Run: $REPO_ROOT/scripts/quality-gate.sh" >&2
    BLOCKED=$((BLOCKED+1))
    continue
  fi
  if [ "$RECEIPT_SHA" != "$local_sha" ]; then
    echo "BLOCKED ${local_sha:0:7}: the receipt covers ${RECEIPT_SHA:0:7}, not this commit. Re-run: $REPO_ROOT/scripts/quality-gate.sh" >&2
    BLOCKED=$((BLOCKED+1))
    continue
  fi
  if [ "$RECEIPT_DIRTY" = "true" ]; then
    echo "BLOCKED ${local_sha:0:7}: the receipt was written over a dirty tree, so it does not describe this commit's content. Re-run the gate on a clean tree." >&2
    BLOCKED=$((BLOCKED+1))
    continue
  fi
done

[ "$BLOCKED" -eq 0 ] || exit 1
exit 0
