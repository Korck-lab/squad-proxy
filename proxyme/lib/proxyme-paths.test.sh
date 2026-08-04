#!/usr/bin/env bash
#
# proxyme-paths.test.sh — real-run evidence for the path-resolution module.
#
# Asserts on the module's observable output — which names it prints and whether
# those paths resolve — never on how it derives them. A test that asserted the
# derivation expression would fail on a correct refactor and pass on a broken
# one that kept the expression.
#
# Run:  ./proxyme-paths.test.sh
#
# Mutation coverage: ./proxyme-paths.mutation.test.sh runs this suite against
# mutated copies of the shipped tree and asserts that a NAMED assertion here
# fires for each mutation. Add an arm there when you add or change an assertion.
#
# Real-run evidence for /proxyme (skill-validation-before-merge)
#
# Observed result (real run, project-scoped state):
#   1. Path resolution against the live machine, three arms:
#      - repo root -> PROXYME_ROOT is the repo; PROXYME_FLAG is
#        /tmp/proxyme-<12-hex>-<session_id>.active
#      - control arm, temp dir with no .claude/ and no git -> PROXYME_ROOT is the
#        temp dir, NOT $HOME. Without the [ "$d" != "$HOME" ] guard this arm
#        resolves to $HOME and every such repo silently shares one state
#        directory. The control arm is what proves the class, not just the path.
#      - subdirectory of a repo -> same PROXYME_ROOT and identical PROXYME_FLAG
#        as the repo root. This is the regression root-keying fixes: $PWD-keying
#        returned a different flag path from a subdirectory, so consultation mode
#        read as OFF.
#   2. CLAUDE_PLUGIN_ROOT is UNSET in Bash tool calls
#      (echo "[${CLAUDE_PLUGIN_ROOT:-UNSET}]" -> [UNSET]). The plugin root is
#      therefore derived from this module's own location.
#   3. Seed path against a second real project: SEEDED ->
#      .claude/proxyme/{<user>-identity.md,config.json,carve-outs.md} created,
#      identity byte-identical to the global file, global checksum unchanged
#      afterwards — proving the global copy is a template, not shared state.
#   4. Ignore guard: git check-ignore -q .claude/proxyme/ on a repo whose
#      .gitignore does not cover .claude/ -> EXCLUDED, entry appended to
#      .git/info/exclude, git status clean.
#   No PII is captured here — only path structure and config, never identity
#   contents.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATHS_SH="$SCRIPT_DIR/proxyme-paths.sh"

FAILS=0
fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS+1)); }
pass() { echo "PASS: $*"; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi; }

# have_file <path> <label> — true when the file exists AND is readable. Reports
# a missing or unreadable input at most ONCE per path, whichever assertion
# reaches it first, so one root cause produces one failure line however many
# checks read that file. Callers skip their own check when it returns false;
# they never add a second failure for the same absence.
MISSING_REPORTED=""
have_file() {
  if [ -f "$1" ] && [ -r "$1" ]; then return 0; fi
  case "$MISSING_REPORTED" in
    *"[$1]"*) : ;;
    *) fail "$2 missing or unreadable: $1"; MISSING_REPORTED="${MISSING_REPORTED}[$1]" ;;
  esac
  return 1
}

[ -f "$PATHS_SH" ] || { echo "FAIL: module not found: $PATHS_SH" >&2; exit 1; }

# --- Assertion 1: every export is present ------------------------------------
OUT="$(bash "$PATHS_SH" 2>/dev/null || true)"
for name in \
  PROXYME_ROOT PROXYME_DIR PROXYME_IDENTITY PROXYME_CONFIG PROXYME_CARVEOUTS \
  PROXYME_GLOBAL_IDENTITY PROXYME_GLOBAL_CONFIG PROXYME_USER PROXYME_SID PROXYME_FLAG \
  PROXYME_PLUGIN_ROOT PROXYME_LIB PROXYME_SKILLS \
  PROXYME_CARVEOUTS_CANON PROXYME_TERSE_CONTRACT PROXYME_SMART_CLIP \
  PROXYME_SCORECARDS PROXYME_VERSION PROXYME_VERSION_LATEST PROXYME_VERSION_NOTE
do
  if printf '%s\n' "$OUT" | grep -q "^${name}="; then
    pass "exports ${name}"
  else
    fail "missing export: ${name}"
  fi
done

# --- Assertion 2: plugin paths resolve to things that exist ------------------
# Only assignment lines are eval'd: if the module errored, its diagnostics must
# not run as shell. Every assertion below dereferences these names under
# `set -u`, where an unset one aborts the script instead of failing a check, so
# a module that produced nothing usable stops the run HERE, with a RESULT: line.
eval "$(printf '%s\n' "$OUT" | grep -E '^PROXYME_[A-Z_]+="' || true)"
for name in PROXYME_PLUGIN_ROOT PROXYME_LIB PROXYME_SKILLS PROXYME_USER \
            PROXYME_CARVEOUTS_CANON PROXYME_TERSE_CONTRACT PROXYME_SMART_CLIP \
            PROXYME_DIR PROXYME_SCORECARDS PROXYME_VERSION PROXYME_VERSION_LATEST
do
  [ -n "${!name:-}" ] && continue
  fail "path module produced no $name; the assertions below cannot run"
  echo "RESULT: $FAILS assertion(s) failed" >&2
  exit 1
done
[ -d "$PROXYME_PLUGIN_ROOT" ] && pass "PROXYME_PLUGIN_ROOT is a directory" \
  || fail "PROXYME_PLUGIN_ROOT does not resolve: $PROXYME_PLUGIN_ROOT"
[ -d "$PROXYME_LIB" ] && pass "PROXYME_LIB is a directory" \
  || fail "PROXYME_LIB does not resolve: $PROXYME_LIB"
[ -d "$PROXYME_SKILLS" ] && pass "PROXYME_SKILLS is a directory" \
  || fail "PROXYME_SKILLS does not resolve: $PROXYME_SKILLS"
check "PROXYME_LIB is under the plugin root" "$PROXYME_LIB" "$PROXYME_PLUGIN_ROOT/lib"
check "PROXYME_SKILLS is under the plugin root" "$PROXYME_SKILLS" "$PROXYME_PLUGIN_ROOT/skills"

# --- Assertion 3: location independence (control arm) ------------------------
# Run the module from a directory that is neither the repo nor a git worktree.
# The plugin paths must be identical; the project-state paths must follow $PWD.
# Without a location-derived plugin root this arm returns a different (or empty)
# PROXYME_PLUGIN_ROOT — the wrong implementation fails visibly rather than
# plausibly, which is the point of the arm.
CONTROL_DIR="$(mktemp -d)"
CONTROL_OUT="$(cd "$CONTROL_DIR" && bash "$PATHS_SH")"
CONTROL_PLUGIN_ROOT="$(printf '%s\n' "$CONTROL_OUT" | sed -n 's/^PROXYME_PLUGIN_ROOT="\(.*\)"$/\1/p')"
CONTROL_STATE_ROOT="$(printf '%s\n' "$CONTROL_OUT" | sed -n 's/^PROXYME_ROOT="\(.*\)"$/\1/p')"
check "plugin root is location-independent" "$CONTROL_PLUGIN_ROOT" "$PROXYME_PLUGIN_ROOT"
check "state root follows the working directory" "$CONTROL_STATE_ROOT" "$CONTROL_DIR"
if [ "$CONTROL_STATE_ROOT" = "$HOME" ]; then
  fail "state root fell back to \$HOME — the pre-\$HOME guard is gone"
else
  pass "state root did not fall back to \$HOME"
fi
rm -rf "$CONTROL_DIR"

# --- Assertion 4: the policy exists exactly once in the shipped tree ---------
# The needle is read from the canonical file at runtime, so this test file never
# contains the literal and therefore never counts itself. *.test.sh is excluded
# so a test fixture can quote the policy without tripping the invariant.
if [ -f "$PROXYME_CARVEOUTS_CANON" ]; then
  pass "canonical carve-outs file exists"
  NEEDLE="$(grep -m1 '^- ' "$PROXYME_CARVEOUTS_CANON" | sed 's/^- //')"
  # 2>/dev/null and `|| true`: an unreadable file under the plugin root makes
  # `grep -r` write "Permission denied" and exit 2, which under pipefail + set -e
  # would abort the run in an assignment like this one.
  HITS="$(grep -rlF "$NEEDLE" "$PROXYME_PLUGIN_ROOT" 2>/dev/null | grep -v '\.test\.sh$' | sort || true)"
  HIT_COUNT="$(printf '%s\n' "$HITS" | grep -c . || true)"
  check "policy appears exactly once in the shipped tree" "$HIT_COUNT" "1"
  check "the single hit is the canonical file" "$HITS" "$PROXYME_CARVEOUTS_CANON"
else
  fail "canonical carve-outs file missing: $PROXYME_CARVEOUTS_CANON"
fi

# --- Assertion 5: README parity ----------------------------------------------
# README.md is at the repo root, one level above the plugin root, and does not
# ship. It is checked, not generated: the six items must match the canonical
# text in the same order once markdown emphasis is stripped.
REPO_ROOT="$(cd "$PROXYME_PLUGIN_ROOT/.." && pwd)"
README="$REPO_ROOT/README.md"
# Guard on BOTH files. The script runs under `set -euo pipefail`, so an
# unguarded grep against a missing canonical file aborts the whole run — no
# RESULT: line, exit 2, and every assertion after this one silently never runs.
# That is the opposite of what a regression test is for.
if [ -f "$README" ] && [ -f "$PROXYME_CARVEOUTS_CANON" ]; then
  CANON_ITEMS="$(grep '^- ' "$PROXYME_CARVEOUTS_CANON" | sed 's/^- //')"
  README_ITEMS="$(sed -n '/^### Never decides/,/^###[^#]/p' "$README" \
    | grep '^- ' | sed 's/^- //; s/\*\*//g')"
  check "README lists the same six items in the same order" "$README_ITEMS" "$CANON_ITEMS"
else
  [ -f "$README" ] || fail "README not found: $README"
  [ -f "$PROXYME_CARVEOUTS_CANON" ] || fail "canonical file missing, README parity not checked"
fi

# --- Assertion 6: the density contract exists exactly once -------------------
# "Quote evidence verbatim" is the distinguishing phrase of the AGENT-PROMPT
# contract. The skills' own reporting-style sections stay inline by design and
# do not contain it. As with assertion 4 the needle is read from the file, and
# *.test.sh is excluded.
if [ -f "$PROXYME_TERSE_CONTRACT" ]; then
  pass "canonical terse-contract file exists"
  TNEEDLE="$(grep -m1 -o 'Quote evidence verbatim' "$PROXYME_TERSE_CONTRACT" || true)"
  if [ -z "$TNEEDLE" ]; then
    fail "terse-contract is missing its distinguishing phrase 'Quote evidence verbatim'"
  else
    THITS="$(grep -rlF "$TNEEDLE" "$PROXYME_PLUGIN_ROOT" 2>/dev/null | grep -v '\.test\.sh$' | sort || true)"
    THIT_COUNT="$(printf '%s\n' "$THITS" | grep -c . || true)"
    check "density contract appears exactly once in the shipped tree" "$THIT_COUNT" "1"
    check "the single hit is the canonical contract" "$THITS" "$PROXYME_TERSE_CONTRACT"
  fi
else
  fail "canonical terse-contract file missing: $PROXYME_TERSE_CONTRACT"
fi

# --- smart-clip is present and executable ------------------------------------
[ -x "$PROXYME_SMART_CLIP" ] && pass "PROXYME_SMART_CLIP is executable" \
  || fail "PROXYME_SMART_CLIP is not executable: $PROXYME_SMART_CLIP"

# --- Assertion 7: the staleness guard reads a real file ----------------------
# The guard compares flags an identity mentions against flags /proxyme actually
# documents. It used to derive the skill path from $0, which under the Bash tool
# is the tool's own temp script — so the grep read nothing and reported nothing
# stale, whatever the identity said. First prove the old derivation is broken,
# then prove the new one works.
OLD_STYLE="$SCRIPT_DIR/../proxyme/SKILL.md"     # what $(dirname "$0")/../proxyme/ resolved to
[ ! -f "$OLD_STYLE" ] && pass "old \$0-derived skill path does not resolve (regression proven)" \
  || fail "old \$0-derived path unexpectedly resolves: $OLD_STYLE"

PROXY_SKILL="$PROXYME_SKILLS/proxyme/SKILL.md"
if have_file "$PROXY_SKILL" "/proxyme skill"; then
  pass "PROXYME_SKILLS resolves the /proxyme skill"
fi

# Execute the guard AS THE SKILL SHIPS IT — do not reimplement its grep/comm here.
# A test that restates the algorithm stays green through a full revert of the fix,
# which is the failure this assertion exists to prevent. Same reasoning as Task 4:
# exercise the artifact, not a copy of it.
IDENT_SKILL="$PROXYME_SKILLS/proxyme-identity/SKILL.md"
STALE_FIXTURE="$PROXYME_SKILLS/proxyme-identity/fixtures/stale-flags.md"
# Pull the fenced bash block that contains the guard, by content not by position.
# Keyed on `comm -23`, the guard's defining operation. (It used to key on the
# temp-file name /tmp/proxyme-skill-flags; the guard now compares with process
# substitution and writes no temp files, so that needle no longer exists. The
# locator changed, the assertions below did not.)
#
# Extracted once, above both users: assertion 7 runs this block, assertion 9
# reads its section anchor. A second copy of the locator could drift from this
# one and then fail as if the anchor had moved — and a second emptiness test
# would report one edit (a guard whose block no longer contains the needle) as
# two distinct failures, so that test lives here, once, beside the extraction.
#
# The `|| true` is load-bearing: a plain assignment takes the substitution's
# exit status, so without it an unreadable skill aborts the whole file under
# `set -e` — no RESULT: line, exit 2, and every assertion below silently never
# runs. Substitutions in ARGUMENT position (inside a `check` call) cannot do
# that; this one, being an assignment, can.
GUARD_BLOCK=""
if have_file "$IDENT_SKILL" "/proxyme-identity skill"; then
  GUARD_BLOCK="$(awk '
    /^```bash$/ { inblk=1; buf=""; next }
    /^```$/     { if (inblk && buf ~ /comm -23/) { printf "%s", buf; exit }
                  inblk=0; next }
    inblk       { buf = buf $0 "\n" }
  ' "$IDENT_SKILL" 2>/dev/null || true)"
  if [ -n "$GUARD_BLOCK" ]; then
    pass "extracted the staleness-guard block from the shipped skill"
  else
    fail "could not find the staleness-guard bash block in $IDENT_SKILL"
  fi
fi

# Each input is guarded by `have_file`, which reports it once for the whole run:
# a missing fixture is one failure here, not a failure plus a raw `grep:` error
# interleaved into the PASS/FAIL stream. Same policy as assertion 5's comment.
if [ -n "$GUARD_BLOCK" ] \
   && have_file "$STALE_FIXTURE" "staleness fixture" \
   && have_file "$PROXY_SKILL" "/proxyme skill"; then
  RUNNABLE="$(printf '%s' "$GUARD_BLOCK" | sed "s|<PLUGIN_ROOT>|$PROXYME_PLUGIN_ROOT|g" || true)"
  TMP_PROJ="$(mktemp -d)"
  mkdir -p "$TMP_PROJ/.claude/proxyme"
  cp "$STALE_FIXTURE" "$TMP_PROJ/.claude/proxyme/${PROXYME_USER}-identity.md"
  STALE="$(cd "$TMP_PROJ" && bash -c "$RUNNABLE" 2>/dev/null || true)"
  rm -rf "$TMP_PROJ"

  case "$STALE" in
    *--nonew*) pass "shipped guard reports --nonew as stale" ;;
    *)         fail "shipped guard did not report --nonew as stale (got: '$STALE')" ;;
  esac
  case "$STALE" in
    *--off*) fail "shipped guard wrongly reported --off, which /proxyme still documents" ;;
    *)       pass "shipped guard does not report --off, which is current" ;;
  esac
fi

# --- Assertion 8: evidence lives in tests, and every skill points at one ------
# The validation guardrail accepts evidence inline in the skill OR in a
# colocated .test.sh. This project standardises on the test file, because a
# skill body is loaded into the model's context on every invocation.
for skill in proxyme proxyme-identity proxyme-validate proxyme-model; do
  SKILL_MD="$PROXYME_SKILLS/$skill/SKILL.md"
  have_file "$SKILL_MD" "$skill skill" || continue
  if grep -q 'Observed result' "$SKILL_MD"; then
    fail "$skill: evidence prose still inline (found 'Observed result')"
  else
    pass "$skill: no inline evidence prose"
  fi
  if grep -q '\.test\.sh' "$SKILL_MD"; then
    pass "$skill: points at a test file"
  else
    fail "$skill: names no .test.sh"
  fi
  # Every skill resolves its paths from this module, so every skill can be the
  # one running from a stale cached version. A skill that never surfaces the
  # note is a skill whose user cannot tell which version answered them.
  if grep -q 'PROXYME_VERSION_NOTE' "$SKILL_MD"; then
    pass "$skill: surfaces the version-skew note"
  else
    fail "$skill: never surfaces PROXYME_VERSION_NOTE"
  fi
done

# --- Assertion 9: section 7 is a FROZEN, PERSISTED schema number --------------
# The staleness guard scopes the identity side with `sed -n '/^## N\./,$p'`. That
# N is not a source-internal constant: it is already written into every identity
# file on every user's disk, and the guard reads THOSE files, not this repo's.
#
# So checking that the template and the anchor merely agree with each other is not
# enough. Consider: a release inserts a section, operational rules becomes 8, and
# the template, anchor and fixture are all updated together. Perfectly consistent
# — and the shipped guard then runs `sed` for `## 8.` against a user's existing
# `## 7.` identity, extracts nothing, and reports "nothing stale" forever. The
# skill exists precisely to handle files generated by older versions (see its
# "generated by an older version of this skill" paragraph), so that is in scope.
#
# The number is therefore frozen. Renumbering requires migration support in the
# guard first — a guard that reads both generations — and this assertion is what
# makes that a build failure instead of a silent one.
#
# Why a number and not the heading text: identity files already on disk were
# generated before the en-US rule and carry a translated heading — e.g.
# "## 7. Regras operacionais do proxy". The guard reads those files too, so the
# heading text is not stable across generations. Only the number is.
SECTION_NUM=7

# The four checks do NOT share a detection property; each states its own below.
# Every input is guarded by `have_file`, so a missing one is reported once for
# the whole run and only the check that reads it is skipped — the checks that do
# not read it still run and still report. Nothing here is silently skipped.

# (a) the synthesis template's heading. Compares the whole matched text, so a
# duplicated heading (two lines), a renumbered one (wrong digit) and a missing
# one (empty) all fail this one equality, each with a distinguishable `got`.
if have_file "$IDENT_SKILL" "/proxyme-identity skill"; then
  check "template heading is section $SECTION_NUM, exactly once" \
    "$(grep -oE '^## [0-9]+\. Proxy operational rules' "$IDENT_SKILL")" \
    "## $SECTION_NUM. Proxy operational rules"
fi

# (b) the guard's own anchor — read out of the EXTRACTED BLOCK, never the whole
# file. Prose elsewhere in the skill can legitimately quote a sed anchor (an
# example, a changelog line, a description of the old behaviour); grepping the
# file and taking the first hit would silently check that instead of the guard.
# Same whole-text comparison as (a), so a duplicated anchor also fails. An
# unfindable block is reported once, where it is extracted, not again here.
if [ -n "$GUARD_BLOCK" ]; then
  check "guard anchor is section $SECTION_NUM, exactly once" \
    "$(printf '%s\n' "$GUARD_BLOCK" | grep -oE '\^## [0-9]+')" "^## $SECTION_NUM"
fi

# (c) prose references to the section, so updating the two mechanical values
# above cannot leave the surrounding instructions saying something else.
#
# The covered set is EXPLICIT, listed here and reviewable in a diff, rather than
# whatever a recursive grep reaches. A `grep -r` over the plugin root read this
# test's own comments (so the assertion could be satisfied — and a correct
# renumber blocked — by prose that never ships), and read untracked working-tree
# debris such as a `SKILL.md.orig` left by a conflicted merge, letting an
# unversioned file decide the build result.
#
# Checked per file, presence-wise: each covered file must still name the frozen
# number. That is what makes deletion in ONE file a failure — set-equality
# across the tree passed as long as any other file still said Section 7 — and
# what lets legitimate prose about a DIFFERENT section of the template (the
# template defines 1 through 7) coexist with it. The converse is not covered: a
# file that names the frozen number and ALSO names another one passes, so this
# check does not detect a stray duplicate reference.
#
# Adding a shipped file that names the section means adding it here — and to the
# covered-file list in proxyme/AGENTS.md, which documents this freeze for
# contributors who meet it while editing prose rather than while running tests.
SECTION_REF_FILES="lib/carve-outs.md skills/proxyme-identity/SKILL.md AGENTS.md"
for rel in $SECTION_REF_FILES; do
  ref_file="$PROXYME_PLUGIN_ROOT/$rel"
  have_file "$ref_file" "section-reference file" || continue
  ref_hit="$(grep -noE "Section [0-9]+" "$ref_file" | grep -E ":Section ${SECTION_NUM}\$" | head -1 || true)"
  if [ -n "$ref_hit" ]; then
    pass "$rel names Section $SECTION_NUM (line ${ref_hit%%:*})"
  else
    # Name the file — and the numbers it does carry — so the repair does not
    # start with a manual `grep -rn` to find which file went stale.
    ref_found="$(grep -hoE 'Section [0-9]+' "$ref_file" | sort -u | tr '\n' ' ' | sed 's/ *$//' || true)"
    fail "$rel no longer names Section $SECTION_NUM (numbers found: ${ref_found:-none})"
  fi
done

# (d) the fixture, so assertion 7 cannot pass while exercising an empty
# extraction. Frozen at the same number for the same reason: it is this repo's
# only representation of the on-disk identity format.
#
# The whole list of numbered headings is compared, in file order, so a renumber
# ('8'), a lost heading ('') and a grown section ('7 8') are three different
# `got` values and three different repairs. A count could not tell them apart.
#
# A grown section must fail: the shipped guard scopes with
# `sed -n '/^## 7\./,$p'`, and `,$p` prints to the LAST line of the file. It
# excludes sections before 7 only; anything after 7 is swept in. Verified: a
# `## 8.` section holding `--dryrun` yields `--dryrun --nonew --off` from the
# guard's scope, which assertion 7's two `case` tests do not surface.
#
# A section BEFORE the frozen one is what would finally exercise that scoping,
# and assertion 7 has no such arm today. If that fixture is wanted, widen the
# expectation here deliberately — e.g. to "1 7" — rather than by weakening the
# check into something a grown later section also satisfies.
FIXTURE_SECTIONS="$SECTION_NUM"
if have_file "$STALE_FIXTURE" "staleness fixture"; then
  check "staleness fixture's numbered sections are exactly '$FIXTURE_SECTIONS'" \
    "$(grep -oE '^## [0-9]+\.' "$STALE_FIXTURE" | grep -oE '[0-9]+' | tr '\n' ' ' | sed 's/ *$//')" \
    "$FIXTURE_SECTIONS"
fi

# --- Assertion 10: scorecard state lives under the project state directory -----
# /proxyme-validate writes one scorecard per run. It holds behavioural findings
# about the user, so it belongs beside the identity — under the directory the
# plugin already excludes from git — and never in the repository or the global
# template directory. Containment is the invariant: a path that escapes
# $PROXYME_DIR escapes the exclusion that was set up for it.
case "$PROXYME_SCORECARDS" in
  "$PROXYME_DIR"/*) pass "scorecard directory is under the project state directory" ;;
  *) fail "scorecard directory escapes $PROXYME_DIR: $PROXYME_SCORECARDS" ;;
esac

# --- Assertion 11: the running version is reported, and skew is visible -------
# A marketplace install lives at <cache>/proxyme/<version>/, and the cache keeps
# several versions at once. Every path here is derived from this file's own
# location, so a launch from an older cached version silently reads that
# version's lib/ — an old path module resolves by old rules, an old smart-clip
# applies an old filter, and the run reports success either way. The failure
# mode to close is the silence: running an older version on purpose is fine,
# not knowing which one ran is not.
VERSION_FILE="$PROXYME_PLUGIN_ROOT/VERSION"
if have_file "$VERSION_FILE" "VERSION file"; then
  check "PROXYME_VERSION is the shipped VERSION file" \
    "$PROXYME_VERSION" "$(tr -d '[:space:]' < "$VERSION_FILE")"
fi
# A checkout has no sibling version directories, so it is its own latest and
# must stay silent — the check costs nothing on the happy path.
# `:-` because an empty note is the correct value here, so this one name cannot
# be required to be non-empty the way the others are.
check "a checkout reports no version skew" "${PROXYME_VERSION_NOTE:-}" ""

# Fixture with two versions present: the module runs from the OLDER one and must
# name both. Built here rather than committed, so it cannot drift from the
# layout the cache actually uses.
VER_FIXTURE="$(mktemp -d)"
mkdir -p "$VER_FIXTURE/proxyme/0.0.1/lib" "$VER_FIXTURE/proxyme/9.9.9/lib"
cp "$PATHS_SH" "$VER_FIXTURE/proxyme/0.0.1/lib/proxyme-paths.sh"
printf '0.0.1\n' > "$VER_FIXTURE/proxyme/0.0.1/VERSION"
printf '9.9.9\n' > "$VER_FIXTURE/proxyme/9.9.9/VERSION"
VER_OUT="$(bash "$VER_FIXTURE/proxyme/0.0.1/lib/proxyme-paths.sh" 2>/dev/null || true)"
ver_of() { printf '%s\n' "$VER_OUT" | sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p"; }
check "stale install reports its own version" "$(ver_of PROXYME_VERSION)" "0.0.1"
check "stale install finds the newest cached version" "$(ver_of PROXYME_VERSION_LATEST)" "9.9.9"
VER_NOTE="$(ver_of PROXYME_VERSION_NOTE)"
case "$VER_NOTE" in
  *0.0.1*9.9.9*) pass "skew note names the running version and the newest one" ;;
  "") fail "skew note is empty while 0.0.1 runs beside 9.9.9" ;;
  *) fail "skew note names neither version pair (got '$VER_NOTE')" ;;
esac
rm -rf "$VER_FIXTURE"

# --- Assertion 12: one output language, stated wherever output language is set -
# The proxy's consumer is an autonomous agent running in English, and the main
# agent is instructed to relay the proxy's answer verbatim. So every artifact
# and every utterance is en-US, whatever language the installer writes in
# (ADR-0007). The rule is set in five shipped places: the canonical density
# contract, which is interpolated into every agent prompt, and the four skills
# that also print their own status blocks without spawning an agent.
#
# One literal sentence in all five. The duplication is load-bearing — a skill
# that prints directly never sees the contract — so what is pinned is that shared
# sentence, byte for byte, which makes a partial edit a build failure rather than
# a drift nobody notices. What each file writes AFTER the sentence is
# file-specific and deliberately differs; this check does not constrain it.
#
# Both directions, per file. Presence alone would pass a file that states the
# en-US rule and, two lines below, still tells the agent to follow the user's
# language: the reverted clause is the likelier regression, because it reads as
# a correct sentence anywhere it survives. Absence alone would pass a file that
# says nothing about language at all.
#
# Checked against an EXPLICIT covered set rather than a recursive grep, for the
# reason assertion 9 records: `grep -r` honours neither .gitignore nor
# .claudignore, so a `SKILL.md.orig` left by a conflicted merge would decide the
# build result. Adding a shipped file that sets output language means adding it
# here.
LANG_RULE="Answer in en-US, whatever language the user writes in."
LANG_SUPERSEDED_1="the language the question was asked in"
LANG_SUPERSEDED_2="the language the user is writing in"
LANG_RULE_FILES="lib/terse-contract.md skills/proxyme/SKILL.md
skills/proxyme-identity/SKILL.md skills/proxyme-model/SKILL.md
skills/proxyme-validate/SKILL.md"
for rel in $LANG_RULE_FILES; do
  lang_file="$PROXYME_PLUGIN_ROOT/$rel"
  have_file "$lang_file" "language-rule file" || continue

  if grep -qF "$LANG_RULE" "$lang_file"; then
    pass "$rel states the en-US output rule"
  else
    fail "$rel no longer states the en-US output rule verbatim: '$LANG_RULE'"
  fi

  # The needles live in variables and this file is never the file being read,
  # so the check cannot be satisfied — or broken — by its own text.
  lang_stale=""
  grep -qF "$LANG_SUPERSEDED_1" "$lang_file" && lang_stale="$LANG_SUPERSEDED_1"
  grep -qF "$LANG_SUPERSEDED_2" "$lang_file" && lang_stale="$LANG_SUPERSEDED_2"
  if [ -z "$lang_stale" ]; then
    pass "$rel does not restate the superseded follow-the-user clause"
  else
    fail "$rel still tells the agent to follow the user's language: '$lang_stale'"
  fi
done

if [ "$FAILS" -ne 0 ]; then
  echo "RESULT: $FAILS assertion(s) failed" >&2
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
