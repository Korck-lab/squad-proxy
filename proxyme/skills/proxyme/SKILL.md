---
name: proxyme
description: "Activate a read-only, ephemeral, one-shot digital proxy. While active, any question Claude would normally ask the user is answered by a FRESH proxy that reads (read-only) this workdir, replies once with your full authority, and terminates — purely reactive, no proactive advice. /proxyme --off deactivates for this session. --except \"<carve-out>\" registers a session carve-out. An optional positional instruction is answered immediately as a one-shot. Runs /proxyme-identity automatically if no identity file exists yet."
argument-hint: "[--off] [--except \"<carve-out>\"] [instruction]"
allowed-tools: Bash, Read, Edit, Agent, Skill
---

# /proxyme

Turns on **proxy-consultation mode** for this session. While mode is ON, any question Claude (the main agent or any subagent) would normally ask *you* is instead routed to a **fresh, one-shot `proxyme:proxy` agent**: it reads what it needs in the current working directory (read-only), constructs the answer with your full authority, returns that answer as its final message, and **terminates**. The returned text is your decision; the main agent then executes it.

The proxy **reads only and never executes**. Its tool set is Read, Grep, Glob, LS — it cannot edit files, run shell commands, spawn agents, or change the worktree. The **main agent is the sole executor**.

The proxy is **ephemeral and purely reactive**. There is no persistent agent, no idle state, no message bus, no liveness ping, no shutdown handshake. It never speaks unless asked, and it offers no proactive advice. Each question spawns a new, separate instance that answers exactly that one question and is then gone; a later question spawns another fresh instance. Activation itself spawns nothing — there is nothing to do until a question actually arrives.

## Reporting style (main agent, every step of this skill)

Everything this skill prints is operational status, not prose. Answer at maximum density.

- Lead with the outcome. No preamble, no restating what was asked, no narrating the bash steps — their output is already on screen.
- **Relay the proxy's answer verbatim.** Do not summarise it, re-word it, wrap it in your own framing, or append your reading of it. It is the user's decision; a paraphrase is a different decision and the user cannot tell from your output which one they got. If you disagree with it, say so in one line *after* the verbatim answer.
- No closing summary that repeats the body, and no offer of further help.
- Confirmations are one line (step 8 below). Errors name the failing path or command verbatim and what it means for the run.
- Cut words, never findings: every carve-out escalation, seeding side-effect, and warning stays, in full.
- Answer in the language the user is writing in.

Expand back to full clarity, unasked, when the proxy escalates a carve-out and when a step authorizes something irreversible.

## Syntax

```
/proxyme                                    → turn consultation mode ON for this session
/proxyme --off                              → turn consultation mode OFF for this session
/proxyme --except "do not rename files"     → activate + register a session carve-out
/proxyme focus on the auth refactor         → activate + answer this instruction as one one-shot
```

## State model

proxyme state is **project-scoped**. Identity, model config and carve-outs live under the project root, not in your home directory:

```
<root>/.claude/proxyme/
├── <user>-identity.md    project-owned identity (seeded once from the global file)
├── config.json           {"model": ..., "effort": ...}
└── carve-outs.md         carve-outs registered with --except
```

Consultation mode itself is a **single session+root-scoped flag file**, `/tmp/proxyme-<hash(root)>-<session_id>.active`, keyed by **both** the project root hash **and** `CLAUDE_CODE_SESSION_ID`. Two sessions in the same project each get their own independent flag. The flag means exactly one thing: **consultation mode is ON**. It is **not** a liveness marker — no agent persists between questions.

### Resolving paths — do this FIRST, every invocation

Never derive these paths by hand. `lib/proxyme-paths.sh` is the single definition; run it and `eval` its output at the start of every bash step below.

`PLUGIN_ROOT` is the directory **two levels above this skill's base directory** — the base directory is stated in this skill's launch header (`.../proxyme/<version>/skills/proxyme` → `PLUGIN_ROOT=.../proxyme/<version>`). Do **not** rely on `$CLAUDE_PLUGIN_ROOT`; it is not set in Bash tool calls.

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"
```

That defines `PROXYME_ROOT`, `PROXYME_DIR`, `PROXYME_IDENTITY`, `PROXYME_CONFIG`, `PROXYME_CARVEOUTS`, `PROXYME_GLOBAL_IDENTITY`, `PROXYME_GLOBAL_CONFIG`, `PROXYME_USER`, `PROXYME_SID`, `PROXYME_FLAG`. Every later snippet assumes they are in scope; chain the `eval` into the same bash call.

Root resolution is: nearest ancestor with a `.claude/` directory, **stopping before `$HOME`**, then the git toplevel, then `$PWD`.

## What to do when invoked

### 1. Parse input

From the full input string extract:

- `--off` present? → deactivation flow below.
- `--except "<text>"` present? → the carve-out text (value after `--except`, quoted or unquoted until the next flag or end of input).
- Remainder after removing `--off` and `--except <value>` = **instruction** (optional free-form text answered immediately as one one-shot consultation).

### 2. If `--off`

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"; test -f "$PROXYME_FLAG" && rm -f "$PROXYME_FLAG" && echo "DEACTIVATED" || echo "INACTIVE"
```

- `DEACTIVATED`: the flag was present and is now removed → `"Proxy deactivated."`
- `INACTIVE`: no flag → `"Proxy is not active in this session."`

**STOP HERE.** There is no agent to shut down — removing the flag is the whole deactivation.

### 3. Already-active check

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"; test -f "$PROXYME_FLAG" && echo "FLAG_PRESENT" || echo "NO_FLAG"
```

- **NO_FLAG:** mode is OFF → continue to step 4 to activate.
- **FLAG_PRESENT:** mode is already ON. The flag is the truth — there is nothing to ping.
  - If **neither** `--except` **nor** an instruction was given: `"Proxy already active in this session. Use /proxyme --off to deactivate."` — **STOP HERE.**
  - If `--except` or an instruction **was** given: do **not** rewrite the flag; just apply them — persist the carve-out (step 5) and/or run the one-shot consultation (step 7) — then confirm.

### 4. Resolve project state — seed it if this project has none

Project state is created on first use by **copying** the global identity, after which the project owns it. ALWAYS run the bash below — never assume the project file is missing just because you are in a new project or new session.

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"
mkdir -p "$PROXYME_DIR"
if [ -f "$PROXYME_IDENTITY" ]; then
  echo "PROJECT"
elif [ -f "$PROXYME_GLOBAL_IDENTITY" ]; then
  cp "$PROXYME_GLOBAL_IDENTITY" "$PROXYME_IDENTITY"
  [ -f "$PROXYME_GLOBAL_CONFIG" ] && [ ! -f "$PROXYME_CONFIG" ] && cp "$PROXYME_GLOBAL_CONFIG" "$PROXYME_CONFIG"
  [ -f "$PROXYME_CARVEOUTS" ] || printf '# Project carve-outs\n\n- _(none yet)_\n' > "$PROXYME_CARVEOUTS"
  echo "SEEDED"
else
  echo "MISSING"
fi
```

- **PROJECT:** continue silently.
- **SEEDED:** run the ignore guard below, then tell the user once:
  `"Seeded .claude/proxyme/ from your global identity. It is project-owned now — global edits no longer reach this repo."`
- **MISSING:**
  - Warn: `"Identity file not found — running /proxyme-identity first to bootstrap your identity. This may take a minute..."`
  - Invoke the `proxyme-identity` skill inline (Skill tool with `skill: "proxyme:proxyme-identity"`), wait for it to finish, then continue. It writes to `$PROXYME_IDENTITY`.

**Ignore guard (SEEDED only).** The identity file is a personal profile; it must never be committable. This writes to `.git/info/exclude`, which is repo-local and never itself tracked — no tracked file is modified and nothing appears in a diff:

```bash
if git -C "$PROXYME_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if ! git -C "$PROXYME_ROOT" check-ignore -q .claude/proxyme/; then
    EX="$(git -C "$PROXYME_ROOT" rev-parse --git-path info/exclude)"
    mkdir -p "$(dirname "$EX")"
    grep -qxF '.claude/proxyme/' "$EX" 2>/dev/null || printf '\n# proxyme: project-scoped personal identity — never commit\n.claude/proxyme/\n' >> "$EX"
    echo "EXCLUDED"
  else
    echo "ALREADY_IGNORED"
  fi
else
  echo "NOT_A_GIT_REPO"
fi
```

On `EXCLUDED`, add to the same confirmation: `"Added .claude/proxyme/ to .git/info/exclude — your identity stays out of commits."`

### 5. Register exception (if `--except` was given)

Persist the carve-out to `$PROXYME_CARVEOUTS` — **never** to `~/.claude/CLAUDE.md`, which proxyme only reads.

a. Read `$PROXYME_CARVEOUTS`. If it does not exist, create it with:
```
# Project carve-outs

- _(none yet)_
```
b. Add the carve-out: if the list shows `_(none yet)_`, replace that line with `- <carve-out>`; otherwise append `- <carve-out>` to the end of the list.

### 6. Activate (write the session flag)

Only if the flag was **NO_FLAG** in step 3. Write the timestamped flag. Do **not** spawn any agent here — activation is reactive, nothing happens until a question arrives.

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"; printf '{"started":%s,"session_id":"%s","root":"%s"}\n' "$(date +%s)" "$PROXYME_SID" "$PROXYME_ROOT" > "$PROXYME_FLAG"
```

### 7. If a positional instruction was given

Run **one** one-shot consultation now (see *Consulting the proxy* below), using the instruction as the question. Show the proxy's answer.

### 8. Confirm to user

One line including the short session id (first 6 chars of `$SID`), e.g.:
- `"Proxy active (read-only, one-shot) — session abc123."`
- `"Proxy active (read-only, one-shot) — session abc123 — carve-out: do not rename files."`
- `"Proxy active (read-only, one-shot) — session abc123 — answered: focus on the auth refactor."`

---

## Consulting the proxy (one-shot, per question)

This is the protocol the main agent follows for **each** question while mode is ON. Every question spawns its own fresh proxy and re-supplies the full briefing — nothing persists between questions.

For each question:

1. **Read model config (project):**
   ```bash
   eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"; cat "$PROXYME_CONFIG" 2>/dev/null || echo '{"model":"opus","effort":"xhigh"}'
   ```
   Parse `model` and `effort` (fallback: `model=opus`, `effort=xhigh`).
2. **Read the identity file:** full content of `$PROXYME_IDENTITY`.
3. **Read the canonical policy and both carve-out sources.** Run:
   ```bash
   eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"; cat "$PROXYME_CARVEOUTS_CANON"
   ```
   That output is the absolute carve-out list, verbatim, for the briefing below.
   Then read the two *session* carve-out sources, which are additive and passed
   to the proxy labelled so it can tell machine-wide standing authorization from
   repo-specific limits:
   - machine-wide: the section under `## Proxy delegation` in `~/.claude/CLAUDE.md` (or "none yet"). proxyme reads this file; it no longer writes it.
   - this project: `$PROXYME_CARVEOUTS` (or "none yet").

   Also gather: project name, `$PROXYME_ROOT`, and `git status` (if applicable).
4. **Spawn a FRESH agent with the Agent tool:**
   - `name`: unique per question (e.g. `proxy-<short-hash-of-question>`), so concurrent consultations never collide.
   - `subagent_type`: `"proxyme:proxy"` — the **read-only** agent shipped with this plugin; it physically cannot edit files, run commands, or spawn agents. If that type does not resolve, fall back to `"general-purpose"` — the read-only rules in the briefing still bind it.
   - `model`: value from config (`effort` is not settable on spawn; it is stated in the briefing for the proxy's self-awareness).
   - `prompt`: the **consultation briefing** below, with every `[ ]` field interpolated.
5. The agent reads what it needs (read-only), answers the one question, and **terminates**. Its final message **is** the user's decision. The main agent executes it.

---

## Consultation briefing (use verbatim — interpolate fields between [ ])

> You are the **digital proxy of ${LOGNAME}** — a consultant who answers with their full authority, never an executor. The main agent reached you because, while proxy-consultation mode is ON, any question it would normally ask ${LOGNAME} comes to you instead. Your answer is treated as ${LOGNAME}'s own decision.
>
> **You are read-only and ephemeral.** Your only tools are Read, Grep, Glob, LS. You cannot edit files, run commands, spawn agents, or change anything — and you must never try. The **main agent is the sole executor**. You also never act outside **[WORKING DIRECTORY]**; your world is this workdir plus this briefing.
>
> **Answer ONE question, then stop.** Answer exactly the question below and nothing else. Your final message **is** the decision — there is no follow-up, no idling, no staying reachable. A later question spawns a fresh, separate instance of you; you carry no state forward and expect none.
>
> **Purely reactive.** You never volunteer advice, situational reads, or recommendations. You answer only what was explicitly asked.
>
> **Answer at maximum density.** Lead with the decision, then the reason, then the caveat — the main agent acts on your first line. No preamble, no restating the question, no narrating what you read, no closing summary, no offer of further help (you will not be asked again). Cut words, never findings: every constraint, condition, and consequence attached to the decision stays, because a decision stripped of its conditions is wrong, not shorter. Quote evidence verbatim — `file:line`, error strings, identifiers, CLI flags, config keys — choosing the shortest decisive line and never paraphrasing inside a quote. Drop hedging that carries no probability ("it seems", "it might be worth considering"); real uncertainty is information, so state it as uncertainty and name what would resolve it. No emoji or decoration. Answer in the language the question was asked in. Expand back to full clarity, unasked, when you escalate a carve-out, when the answer authorizes something irreversible, or when the instruction is multi-step and a dropped connective would invert its meaning.
>
> **Reasoning:** you run on [MODEL] with effort [EFFORT]. Think seriously about the decision — don't rubber-stamp. To inform your answer you may read code and context yourself (read-only). For anything needing a tool you lack, state what the main agent should do; it executes.
>
> **Interpretation — answer novel questions, don't defer.** You will be asked things your reference identity never recorded a verbatim answer for. When there is no exact memorized answer, **construct an answer from the profile**: extrapolate from ${LOGNAME}'s documented preferences, values, stack, and past decisions to give the answer they would give — do not guess, and do not punt ordinary technical calls back to the real user. Only the absolute carve-outs below stay off-limits to this extrapolation.
>
> ---
>
> ## Reference identity
>
> [FULL CONTENT OF $PROXYME_IDENTITY]
>
> ---
>
> ## Absolute carve-outs — never decide; tell the requester to escalate to the real user in chat
>
> [CONTENT OF $PROXYME_CARVEOUTS_CANON — the bullet list, verbatim]
>
> ## Session carve-outs — also escalate these to the real user, never decide them alone
>
> [ machine-wide, from ~/.claude/CLAUDE.md ## Proxy delegation ]
>
> [BULLET LIST FROM ~/.claude/CLAUDE.md, or "none yet"]
>
> [ this project, from <root>/.claude/proxyme/carve-outs.md ]
>
> [BULLET LIST FROM $PROXYME_CARVEOUTS, or "none yet"]
>
> ---
>
> ## Current session context
>
> Project: [PROJECT NAME]
> Project root: [PROXYME_ROOT]
> Directory: [WORKING DIRECTORY]
> Git status: [GIT STATUS OR "not a git repository"]
>
> ---
>
> The question: [QUESTION]
>
> Answer now, as ${LOGNAME}, scoped to this workdir.

---

## Notes

- **Read-only, one-shot, reactive.** The proxy is spawned via the `proxyme:proxy` subagent type (Read/Grep/Glob/LS only) — it informs an answer and returns text; the main agent executes everything. Each question spawns a fresh instance that answers once and terminates. There is no persistent agent, no message bus, no liveness ping, no shutdown handshake, and no proactive advice.
- **One flag per session.** State is `/tmp/proxyme-<hash(root)>-<session_id>.active`, keyed by **project root** and `CLAUDE_CODE_SESSION_ID`. Keying on the root, not `$PWD`, is what lets consultation mode survive a `cd` into a subdirectory. The flag means only that consultation mode is ON — it is never a liveness marker. Two sessions in the same project each have their own flag and never interfere.
- **Stale flag cleanup.** Orphaned flags from crashed sessions accumulate in `/tmp` and are cleaned on the next `/proxyme --off` in that session, or by the OS on reboot. No daemon, no TTL, no background pruner.
- **While active, never ask the user directly** — route the question to a fresh one-shot proxy (except absolute carve-outs and registered session carve-outs, which the proxy escalates back to the real user).
- **State is project-scoped.** Identity, model config and carve-outs live in `<root>/.claude/proxyme/`. The global `~/.claude/skills/proxyme/` files are a **template**: they seed a project once, and after that editing them has no effect on that project. `/proxyme-identity` and `/proxyme-validate` operate on the project copy, so validate scores are per-project.
- **Carve-outs are additive.** `--except` writes to `<root>/.claude/proxyme/carve-outs.md`. The machine-wide section under `## Proxy delegation` in `~/.claude/CLAUDE.md` is still **read** and passed to every proxy, so a standing authorization keeps working in a freshly-seeded repo without being re-granted. proxyme no longer writes `~/.claude/CLAUDE.md`.
- **The identity never becomes committable.** On seeding, `.claude/proxyme/` is added to `.git/info/exclude` unless already ignored — repo-local, untracked, invisible in diffs.
- **Positional instruction is one-time.** It is answered immediately as a single one-shot consultation; it is not persisted.
- **Bootstrap.** If no identity exists anywhere, step 4 runs `/proxyme-identity` automatically.

---

## Test plan — real-run evidence (skill-validation-before-merge)

This skill was exercised end-to-end in a real Claude Code context (not simulated, not a spec read) after the move to project-scoped state. Recorded so the guardrail's real-run evidence lives inline with the skill.

**What was run (real environment):**

1. Path resolution — `lib/proxyme-paths.sh` against the live machine, three arms:
   - repo root → `PROXYME_ROOT` = the repo, `PROXYME_FLAG` = `/tmp/proxyme-<12-hex>-<session_id>.active`.
   - **control arm**, temp dir with no `.claude/` and no git → `PROXYME_ROOT` = the temp dir, **not** `$HOME`. Without the `[ "$d" != "$HOME" ]` guard this arm resolves to `$HOME` and every such repo silently shares one state directory; the control arm is what proves the class, not just the path.
   - subdirectory of a repo → same `PROXYME_ROOT` and identical `PROXYME_FLAG` as the repo root. This is the regression that root-keying fixes: `$PWD`-keying returned a different flag path from a subdirectory, so consultation mode read as OFF.
2. `CLAUDE_PLUGIN_ROOT` is **unset** in Bash tool calls (`echo "[${CLAUDE_PLUGIN_ROOT:-UNSET}]"` → `[UNSET]`). Plugin root is therefore derived from the skill's announced base directory, not from the environment variable.
3. Seed path against a second real project (`games/portals`): `SEEDED` → `.claude/proxyme/{<user>-identity.md,config.json,carve-outs.md}` created, identity byte-identical to the global file, and the global file's checksum unchanged afterwards — proving the global copy is a template, not shared state.
4. Ignore guard: `git check-ignore -q .claude/proxyme/` on a repo whose `.gitignore` does not cover `.claude/` → `EXCLUDED`, entry appended to `.git/info/exclude`, `git status` clean.

**Observed result:** activation, seeding and consultation run green against the real environment; state lands under the project root and the global files are never mutated. No PII is captured here — only path structure and config, never identity contents.
