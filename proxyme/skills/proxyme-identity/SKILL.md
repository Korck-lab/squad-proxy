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

**Version skew, first line, only when it exists.** When `$PROXYME_VERSION_NOTE` is non-empty, print it before the report and carry on. It means this skill is running from a cached version older than the newest installed one, so `lib/smart-clip.sh` and the path module come from that older copy — which the user must know when reading a profile built by it. Empty note, print nothing.

**To the user (this skill's own output).** Lead with the result — file written, counts, projects found. No preamble, no narration of which agent you spawned, no closing summary, no offer of further help. Anything dropped as stale (step 3) is named explicitly; silence there reads as "nothing changed" when something did. Answer in en-US, whatever language the user writes in.

**To the collector and synthesis agents.** Append the contents of `$PROXYME_TERSE_CONTRACT` verbatim to every agent prompt in steps 1 and 2, followed by this delta:

> **Your delta:** respect the word cap stated in your own prompt — if a pattern is about to go over it, keep the pattern and cut the prose around it. Quoted user text is translated to en-US and tagged with the language it was said in — `"…" [translated from pt-BR]`. Translating is not license to paraphrase: keep every negation, condition and hedge the original carried, and never soften a blunt sentence into a polite one. A quote whose source is already English carries no tag. The tag names the language of **that quote**, taken from the clip or memory file it came from — never the session's or the file's dominant language. People switch language turn by turn, so a tag inferred from the surrounding context is a guess, and a guessed tag is worse than none: it is a claim about provenance.

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

**Agent D — Sessions (SMART-CLIP extraction)** (`name: "proxyme-identity-sessions"`).

Resolve the filter's absolute path in **your own** shell before you spawn Agent D. A subagent cannot expand `<PLUGIN_ROOT>`, and it gets no shell state from you — every Bash tool call is a fresh shell — so a placeholder or a bare `$PROXYME_SMART_CLIP` reaches it as an empty string:

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"; echo "$PROXYME_SMART_CLIP"
```

**Agent D prompt (use verbatim — interpolate the field between [ ]).** The one field is `[SMART_CLIP_PATH]`: the absolute path just printed. Never hand Agent D the literal `<PLUGIN_ROOT>` or an unexpanded variable name.

> Sample real user turns from the longest sessions with SMART-CLIP: map each real user
> turn to its line offset, then pull only a bounded context window around it by line
> index. Never load a whole .jsonl into context — clip, do not dump.
>
> 1. Pick the 5 longest sessions (most lines), excluding subagents and workflows:
>
> ```bash
> find ~/.claude/projects -name "*.jsonl" \
>   ! -path "*/subagents/*" ! -path "*/workflows/*" \
>   | xargs wc -l 2>/dev/null | sort -rn | head -6 | grep -v total
> ```
>
> 2. For each session, run the shipped SMART-CLIP module at `[SMART_CLIP_PATH]`. It
>    emits one compact JSON record per real human turn — `{user_line, window_lines,
>    before, user, after}` — pulling only a bounded window by line index. Never load
>    a whole `.jsonl` into context; the module never does either.
>
> ```bash
> "[SMART_CLIP_PATH]" "$SESSION"
> ```
>
>    `before` holds the model question of the Q/A pair; `after` holds the answer
>    and the model's confirmation-of-understanding, where it restates what it will
>    do.
>
> 3. **Call the module — never reimplement it.** The classification of real human
>    turns and the line-index windowing are the module's job, not yours. Do not
>    write your own filter, do not inline an equivalent `jq`/`awk`/`grep` pipeline,
>    and do not fall back to reading the `.jsonl` directly. If `[SMART_CLIP_PATH]`
>    is empty, missing, or fails to run, **stop and report that** — return the
>    error instead of substituting a filter of your own.
>
> 4. **Why the filter is strict, and why you must not weaken it.** Two classes of
>    `type=="user"` line are not human turns. Harness-injected noise (command
>    echoes, system reminders, task notifications, image metadata, compaction
>    summaries, slash-command caveats) is 20-50% of them. Agent-authored text
>    (`<agent-message>`, cross-session messages, context-usage dumps,
>    `<bash-input>` echoes) is the bigger trap: measured on a real 8.9k-line
>    session, 231 lines passed the pre-2026-07-27 filter and only 98 were human —
>    58% was the proxy's own prose being recycled as if the user had written it,
>    which makes the generated identity self-referential. The module excludes both.
>    `proxyme-identity.test.sh` asserts it, against a synthetic fixture.
>
> 5. Label each clip as one of: request / correction-rejection / confirmation / answer,
>    **and record the language that clip was written in**, per clip. A session mixes
>    languages turn by turn, so a single dominant-language answer cannot tag a quote
>    accurately downstream. Keep only the most informative ~40 clips across the 5
>    sessions.
>
> Then consolidate the patterns below in <=600 words (consolidated patterns, not transcriptions):
>
> 1. How they formulate requests: style, level of detail, use of slash commands
> 2. What they reject mid-task: direct quotes of when they asked to stop, change, or simplify
> 3. How much autonomy they give: let you decide or ask for options?
> 4. Tone and register, and which language they actually type in — name it, because
>    it tells the proxy what a blunt sentence from them looks like. Your own output
>    stays en-US whatever you find, with every quote translated and tagged.
> 5. Process patterns: prefer research first? Quick iteration? Parallel agents?

### 2. Synthesize identity

After the 4 agents return, spawn 1 Opus agent with the following prompt (interpolating the outputs):

```
You will write the user-identity.md file based on 4 analyses of Claude Code sessions and memories.

You will receive 4 analysis outputs. Combine them to write the complete file in the exact format below.

RULES:
- Sections with [auto] should be generated from the outputs
- Write the WHOLE file in en-US, whatever language the user writes in, and copy each
  section heading from this template exactly — same number, same words, never
  translated. `[auto]` is an authoring marker telling you to generate that section;
  strip it from the heading you write. The file is read by an agent running in
  English, and the answer built from it is executed verbatim (ADR-0007).
- Quoted user text is translated to en-US and tagged with the language it was said
  in — `"…" [translated from pt-BR]`. The tag is what stops a translation from
  being read as the user's exact words. Translating is not license to paraphrase:
  every negation, condition and hedge the original carried survives, and a blunt
  sentence stays blunt. A quote whose source is already English carries no tag.
- Section 7 is shipped template text: copy it VERBATIM in en-US, do not modify, do
  not translate and do not reword it. Translation is where a clause silently loses a condition, and Section 7
  is the section the proxy's authority is read from (see
  `docs/guardrails/english-us-normalization.md`). A user-authored carve-out block
  appended to it is the user's own words: it is translated and tagged like any other
  captured user text, content-complete, never summarized.
- Be concrete and specific — avoid generalizations
- Use examples from outputs when relevant
- When the outputs disagree on a fact about the user (a figure, a credential, a
  current number), never pick one silently: state that it is disputed, name both
  values and their sources, and let the proxy ask rather than assert. Prefer the
  newer source when one is clearly newer, and say so.
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

- **User-authored carve-outs** (extra escalation rules, exceptions, project-specific limits the user wrote themselves): **preserve content-complete**, appended into the new Section 7. Preserving means every rule, condition and exception survives — not that the bytes do. A carve-out written in another language is translated to en-US and tagged, the same as any other captured user text; nothing in it is summarized away on the trip.
- **Template structure** (the read-only/ephemeral paragraph, can-decide list, always-escalate list, the `--except` line): **always take from the current template above**, even if the existing file differs.

"Different from the default template" does **not** imply the user edited it — it usually means the file was generated by an **older version of this skill**. Preserving that wholesale re-introduces stale behaviour: a real refresh found a Section 7 still documenting a `--nonew` flag that had been removed from `/proxyme`, so blind preservation would have shipped a briefing describing a mode that no longer exists.

**Staleness check before preserving anything:** grep the current `/proxyme` skill for every flag and mode the existing Section 7 mentions. Anything not found there is stale — drop it, and say so in the step-4 report.

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"
comm -23 \
  <(sed -n '/^## 7\./,$p' "$PROXYME_IDENTITY" | grep -oE '\-\-[a-z-]+' | sort -u) \
  <(grep -oE '\-\-[a-z-]+' "$PROXYME_SKILLS/proxyme/SKILL.md" | sort -u)
```

The `sed` scopes the identity side to Section 7 — the only section this step preserves. Unscoped, the grep also matches flags the user quoted elsewhere in their own profile, and the step below would then drop a carve-out it was told to keep. The `/proxyme` side stays unscoped: the full flag vocabulary is spread across that whole skill.

Whatever that `comm` prints is a flag the identity mentions and `/proxyme` no longer documents: do not carry it forward, and name it in the step-4 report under `Dropped as stale:`.

An empty output means nothing is stale.

Before the path resolved through `$PROXYME_SKILLS`, the second `grep` read a file that did not exist and produced an empty list, so every flag the identity mentioned looked absent from the skill — including current ones like `--off`. The broken check over-reported, it did not go silent.

**Language check before saving.** Identity files written before ADR-0007 carry headings translated into the installer's language rather than the template's `## 1. Who you are`. A refresh **converts such a file in place**: the whole file is rewritten in en-US, including the user-authored carve-outs, and nothing is appended to a half-translated file. The headings are the cheap signal, because they are the one part of the file the template fixes:

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"
headings() { grep -oE '^## [0-9]+\. .*' "$1" | sed 's/ \[auto\]$//'; }
diff <(headings "$PROXYME_IDENTITY") \
     <(headings "$PROXYME_SKILLS/proxyme-identity/SKILL.md") >/dev/null \
  && echo "ALREADY_EN_US" || echo "CONVERTED"
```

The expected list is read out of the template in this very file rather than restated here, so the check cannot drift from the template it is checking, and this skill keeps exactly one literal copy of each heading. The `sed` strips the `[auto]` authoring marker, which the template carries and a written identity never does.

That one comparison decides both things: `CONVERTED` means this run changed the file's language, and the same `CONVERTED` is what adds the conversion line to the step-4 report — one condition, not two. A heading list that differs for any other reason — a renamed section, a missing one — is also a mismatch, and reporting the conversion when nothing needed converting is the harmless direction. Silence is not: a converted file is a rewritten file, and a report that does not say so reads exactly like a refresh that changed a few bullets.

**Save:** `mkdir -p "$PROXYME_DIR"`, then write the synthesis agent's output to `$PROXYME_IDENTITY`.

### 4. Confirm to user

One compact block, no prose around it — counts, projects, path, next command:

```
Identity written: <path to $PROXYME_IDENTITY>
Memories: <n> feedback, <n> user, <n> project · Sessions: <n>
Active projects: <comma-separated list>
Dropped as stale: <flag/mode names, or omit this line entirely if none>
Converted to en-US: <what the previous file was written in, and that the carve-outs were translated and tagged — or omit this line entirely if the file was already en-US>
Conflicting facts: <one per fact: what disagrees, both values, which source won and why — or omit this line entirely if none>
Next: /proxyme-validate, then /proxyme
```

`Conflicting facts` is not optional when the collectors disagreed. A conflict the
report swallows reads as a clean run, and the identity then carries a number the
proxy will assert with the user's authority.

**Next:** run `/proxyme-validate` to score the new identity against held-out questions before relying on it. When the report carried the conversion line, that run is not optional: a conversion rewrote every heuristic in the file, and a heuristic quietly weakened in translation shows up in the scorecard and nowhere else.

**Note:** The generated identity file is a personal profile and must never be committed. `/proxyme` adds `.claude/proxyme/` to `.git/info/exclude` when it seeds a project; if you ran this skill directly in a repo where that has not happened, add it yourself before committing anything.
