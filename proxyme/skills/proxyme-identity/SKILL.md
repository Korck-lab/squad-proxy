---
name: proxyme-identity
description: "Analyzes your Claude Code memories and session history to synthesize your digital identity file for THIS project (<root>/.claude/proxyme/${LOGNAME}-identity.md). Run once to bootstrap, then refresh when your preferences or active projects change significantly. Requires Claude Code session history (JSONL files in ~/.claude/projects/)."
allowed-tools: Agent, Read, Write, Bash
---

# /proxyme-identity

Analyzes all your memories and sessions to generate or update the **project-scoped** identity at `<root>/.claude/proxyme/${LOGNAME}-identity.md`.

The *scan* stays machine-wide — synthesis reads all of `~/.claude/projects/` because a profile built from one repo's history is a thin profile. Only the *output* is project-scoped.

Resolve paths first; `PLUGIN_ROOT` is the directory two levels above this skill's base directory (stated in the launch header). `$CLAUDE_PLUGIN_ROOT` is **not** set in Bash tool calls.

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"
```

That defines `PROXYME_DIR` and `PROXYME_IDENTITY`, assumed in scope below.

Run this whenever you want to refresh your proxy identity. You don't need to run it every session.

## Reporting style

Two audiences, one rule: maximum density, cut words but never findings.

**To the user (this skill's own output).** Lead with the result — file written, counts, projects found. No preamble, no narration of which agent you spawned, no closing summary, no offer of further help. Anything dropped as stale (step 3) is named explicitly; silence there reads as "nothing changed" when something did. Answer in the language the user is writing in.

**To the collector and synthesis agents.** Append the contents of `$PROXYME_TERSE_CONTRACT` verbatim to every agent prompt in steps 1 and 2, followed by this delta:

> **Your delta:** respect the word cap stated in your own prompt — if a pattern is about to go over it, keep the pattern and cut the prose around it. Quote the user's own words verbatim when you quote at all; never paraphrase inside quotation marks.

Read it with:
```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"; cat "$PROXYME_TERSE_CONTRACT"
```

## What to do when invoked

### 1. Collect in parallel (4 simultaneous agents)

Spawn the 4 agents below with the Agent tool in parallel (single message with 4 Agent tool calls):

**Agent A — Feedback** (`name: "proxyme-identity-feedback"`):
```
Read all memory files of feedback type in:
~/.claude/projects/**/memory/feedback*.md
~/.claude/projects/**/memory/*feedback*.md

List each file found with `find ~/.claude/projects -path "*/memory/*" -name "*feedback*" -name "*.md"`, read all, and consolidate the behavioral patterns of the user in structured text.

Extract and organize by theme:
- What they reject (with concrete examples)
- What they value and want you to always do
- How they prefer to be operated (automation, decisions, communication)
- Corrections they have given (what went wrong and was fixed)
- Confirmed-as-correct behaviors

Return as text with subtitles by theme. Be specific and cite examples from memories. Maximum 800 words.
```

**Agent B — Profile** (`name: "proxyme-identity-profile"`):
```
Read all memory files of user/profile type in:
~/.claude/projects/**/memory/user*.md
~/.claude/projects/**/memory/*profile*.md
~/.claude/projects/**/memory/*identity*.md

List each file with `find ~/.claude/projects -path "*/memory/*" -name "*.md" | xargs grep -l "type: user" 2>/dev/null`, read all, and extract:

1. Professional identity: role, mode of work, type of client
2. Career: relevant history, important milestones
3. Dominant technical stack: languages, platforms, tools
4. Domains of expertise: game dev, web, data, consulting, etc.
5. Personal context relevant to work decisions

Return as structured text with subtitles. Maximum 500 words.
```

**Agent C — Projects** (`name: "proxyme-identity-projects"`):
```
Read all memory files of project type. Filter by frontmatter CONTENT, not by
filename — a project's memories are usually named by topic (architecture.md,
playtest-*.md, MEMORY.md), so a "*project*.md" filename glob silently misses
whole active projects. Match the `type: project` marker (under `metadata:`,
indented) the same way Agent B matches `type: user`:

List with `find ~/.claude/projects -path "*/memory/*" -name "*.md" | xargs grep -lE "type: *project" 2>/dev/null`, dedupe by project directory (ignore `*--claude-worktrees-*` mirrors), read found files, and for each active project (with activity in last 90 days — check file dates), extract:

- Project name
- Current state (in progress, stalled, complete)
- What is in progress or pending
- Implicit priority based on activity frequency
- Relevant technical context (stack, important decisions)

Ignore clearly completed or abandoned projects. Return as bulleted project list. Maximum 400 words.
```

**Agent D — Sessions (SMART-CLIP extraction)** (`name: "proxyme-identity-sessions"`):
```
Sample real user turns from the longest sessions with SMART-CLIP: map each real user
turn to its line offset, then pull only a bounded context window around it by line
index. Never load a whole .jsonl into context — clip, do not dump.

1. Pick the 5 longest sessions (most lines), excluding subagents and workflows:

```bash
find ~/.claude/projects -name "*.jsonl" \
  ! -path "*/subagents/*" ! -path "*/workflows/*" \
  | xargs wc -l 2>/dev/null | sort -rn | head -6 | grep -v total
```

2. For each session, run the shipped SMART-CLIP module. It emits one compact
   JSON record per real human turn — `{user_line, window_lines, before, user,
   after}` — pulling only a bounded window by line index. Never load a whole
   `.jsonl` into context; the module never does either.

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"
"$PROXYME_SMART_CLIP" "$SESSION"
```

   `before` holds the model question of the Q/A pair; `after` holds the answer
   and the model's confirmation-of-understanding, where it restates what it will
   do.

3. **Why the filter is strict, and why you must not weaken it.** Two classes of
   `type=="user"` line are not human turns. Harness-injected noise (command
   echoes, system reminders, task notifications, image metadata, compaction
   summaries, slash-command caveats) is 20-50% of them. Agent-authored text
   (`<agent-message>`, cross-session messages, context-usage dumps,
   `<bash-input>` echoes) is the bigger trap: measured on a real 8.9k-line
   session, 231 lines passed the pre-2026-07-27 filter and only 98 were human —
   58% was the proxy's own prose being recycled as if the user had written it,
   which makes the generated identity self-referential. The module excludes both.
   `proxyme-identity.test.sh` asserts it, against a synthetic fixture.

4. Label each clip as one of: request / correction-rejection / confirmation / answer,
   and keep only the most informative ~40 clips across the 5 sessions.

Then consolidate the patterns below in <=600 words (consolidated patterns, not transcriptions):

1. How they formulate requests: style, level of detail, use of slash commands
2. What they reject mid-task: direct quotes of when they asked to stop, change, or simplify
3. How much autonomy they give: let you decide or ask for options?
4. Tone and language: PT-BR? English? Mixed?
5. Process patterns: prefer research first? Quick iteration? Parallel agents?
```

### 2. Synthesize identity

After the 4 agents return, spawn 1 Opus agent with the following prompt (interpolating the outputs):

```
You will write the user-identity.md file based on 4 analyses of Claude Code sessions and memories.

You will receive 4 analysis outputs. Combine them to write the complete file in the exact format below.

RULES:
- Sections with [auto] should be generated from the outputs
- Section 7 should be copied VERBATIM from the template below — do not modify
- Be concrete and specific — avoid generalizations
- Use examples from outputs when relevant
- Use the user's preferred language in all content
- Return ONLY the file content, without explanations

TEMPLATE:

# [${LOGNAME}] Identity — Digital Proxy Briefing
<!-- generated by /proxyme-identity on [TODAY'S DATE] -->

## 1. Who you are [auto]
[synthesis of OUTPUT B: concise professional background, current mode of work, dominant stack]

## 2. How you decide [auto]
[synthesis of OUTPUT A + OUTPUT D: decision heuristics in bullets — speed vs. care, prioritization, tolerance for ambiguity, when to research vs. try]

## 3. What you never accept [auto]
[synthesis of OUTPUT A: bullet list of strongest negative patterns — what they explicitly rejected]

## 4. Communication style [auto]
[synthesis of OUTPUT D: language, tone, preferred response length, format]

## 5. Active projects and context [auto]
[synthesis of OUTPUT C: list of active projects with state and key context]

## 6. Domains and technical preferences [auto]
[synthesis of OUTPUT A + OUTPUT B: by domain, what they prefer and what they reject — be specific with real technical examples]

## 7. Proxy operational rules

**The proxy is read-only, ephemeral, and reactive.** It is spawned FRESH for each question, answers that ONE question once with the user's full authority, then terminates. It never executes and never acts outside the current workdir; the main agent is the sole executor and the only one that touches the worktree.

**Can decide / advise alone:** technical implementation choices, task prioritization, what to continue or start next when context indicates what is missing, choosing between architectures when neither is clearly wrong, naming variables/functions/files, deciding when to research vs. try. The proxy returns these as its decision/answer; the main agent carries them out.

**ALWAYS escalate to real user:** the absolute carve-outs, which arrive in the spawn prompt from `/proxyme` and are not restated here. This file is per-user and per-project; the policy belongs to the plugin.

**Session carve-outs (from CLAUDE.md):** add your own carve-outs with `/proxyme --except "<exception>"`.

---
OUTPUT A (feedback): {output_agente_A}
OUTPUT B (profile): {output_agente_B}
OUTPUT C (projects): {output_agente_C}
OUTPUT D (sessions): {output_agente_D}
```

### 3. Write the file

**Check if previous version exists:**
```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"; test -f "$PROXYME_IDENTITY" && echo "EXISTS" || echo "MISSING"
```

**If EXISTS:** Read the current Section 7 and split it into two kinds of content — they are handled differently:

- **User-authored carve-outs** (extra escalation rules, exceptions, project-specific limits the user wrote themselves): **preserve verbatim**, appended into the new Section 7.
- **Template structure** (the read-only/ephemeral paragraph, can-decide list, always-escalate list, the `--except` line): **always take from the current template above**, even if the existing file differs.

"Different from the default template" does **not** imply the user edited it — it usually means the file was generated by an **older version of this skill**. Preserving that wholesale re-introduces stale behaviour: a real refresh found a Section 7 still documenting a `--nonew` flag that had been removed from `/proxyme`, so blind preservation would have shipped a briefing describing a mode that no longer exists.

**Staleness check before preserving anything:** grep the current `/proxyme` skill for every flag and mode the existing Section 7 mentions. Anything not found there is stale — drop it, and say so in the step-4 report.

```bash
grep -oE '`--[a-z-]+`' "$PROXYME_IDENTITY" | sort -u
grep -oE '\-\-[a-z-]+' "$(dirname "$0")/../proxyme/SKILL.md" | sort -u
```

Anything in the first list and missing from the second is a removed flag: do not carry it forward.

**Save:** `mkdir -p "$PROXYME_DIR"`, then write the synthesis agent's output to `$PROXYME_IDENTITY`.

### 4. Confirm to user

One compact block, no prose around it — counts, projects, path, next command:

```
Identity written: <path to $PROXYME_IDENTITY>
Memories: <n> feedback, <n> user, <n> project · Sessions: <n>
Active projects: <comma-separated list>
Dropped as stale: <flag/mode names, or omit this line entirely if none>
Next: /proxyme-validate, then /proxyme
```

**Next:** run `/proxyme-validate` to score the new identity against held-out questions before relying on it.

**Note:** The generated identity file is a personal profile and must never be committed. `/proxyme` adds `.claude/proxyme/` to `.git/info/exclude` when it seeds a project; if you ran this skill directly in a repo where that has not happened, add it yourself before committing anything.
