# proxyme

> A Claude Code plugin that answers every question Claude would ask you — with your authority — by spawning a fresh read-only proxy briefed with your real identity, so Claude stops interrupting and just gets things done.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-blue.svg)](https://claude.com/code)

## What

proxyme is a Claude Code plugin. While consultation mode is ON, any question Claude would normally stop and ask you spawns a **fresh, read-only, one-shot** proxy briefed with your identity — extracted from your actual Claude Code memories and session history. The proxy:

- Answers every question Claude would otherwise ask you, with your full authority
- Is **read-only and never executes** — it reads only what it needs to inform an answer, returns text, and terminates; the main agent does all the work and is the only thing that touches your files
- Is **scoped to the current working directory** — it never reads, reasons about, or touches anything outside this project
- Is **purely reactive** — it never volunteers advice; it only lives to answer what was explicitly asked

## How it works

```
/proxyme-identity  →  <project>/.claude/proxyme/${LOGNAME}-identity.md
                                    ↓
/proxyme           →  consultation mode ON (session + project scoped flag; no agent spawned yet)
                                    ↓
   a question Claude would ask you
                                    ↓
   a FRESH read-only proxy is spawned (briefed with your identity)
                                    ↓
   it answers once, with your authority  →  it terminates (gone)
```

1. **Identity extraction** — `/proxyme-identity` analyzes your Claude Code session history and memories (JSONL files in `~/.claude/projects/`) to synthesize your decision-making patterns, preferred stack, communication style, and active projects.

2. **Turn consultation mode on** — `/proxyme` writes a session- and project-scoped flag. No agent is spawned at activation: there is nothing to do until a question actually arrives. While the flag is present, any question Claude would route to the real user goes to a proxy instead.

3. **Delegation** — When Claude hits a question it would otherwise ask you, it spawns a fresh exclusive proxy with your identity briefing. The proxy answers that one question as if it were you — with your values and judgment — and then dies. Each question spawns a new, separate instance; nothing persists between questions.

## Project-scoped state

Since v0.5.0 everything proxyme persists lives under the project, not your home directory:

```
<project>/.claude/proxyme/
├── ${LOGNAME}-identity.md    project-owned identity
├── config.json               model + effort for this project
└── carve-outs.md             carve-outs registered with --except
```

The plugin itself stays installed user-wide — `/proxyme` is available in every repo. Only what it *remembers* is per-project.

**Seeded once, then diverges.** The first `/proxyme` in a project copies your global `~/.claude/skills/proxyme/` files in and then leaves them alone. After that the global copy is a **template**: editing it does not reach a project that has already been seeded, and `/proxyme-identity` / `/proxyme-validate` operate on the project copy. Validate scores are therefore per-project.

**Carve-outs are additive.** `--except` writes to the project file. The machine-wide section under `## Proxy delegation` in `~/.claude/CLAUDE.md` is still read and passed to every proxy, so a standing authorization keeps working in a freshly-seeded repo without being re-granted. proxyme no longer writes `~/.claude/CLAUDE.md`.

**Your identity never becomes committable.** On seeding, `.claude/proxyme/` is added to the repo's `.git/info/exclude` unless it is already ignored. That file is repo-local and untracked, so nothing shows up in a diff and no tracked file is touched.

**Project root** is the nearest ancestor containing a `.claude/` directory — stopping before `$HOME` — then the git toplevel, then the working directory. The session flag is keyed on that root, so consultation mode survives `cd` into a subdirectory.

### Upgrading from 0.4.x

Nothing to do. The first `/proxyme` in each repo seeds it from your existing global files. Carve-outs you registered before 0.5.0 still live in `~/.claude/CLAUDE.md`, which is still read.

## Prerequisites

- Claude Code CLI (version 3.0+)
- Claude Code session history (`~/.claude/projects/` with JSONL files from recent sessions)

## Installation

Run `/plugin` in Claude Code, open the **Marketplace** tab, click **New**, and enter:

```
@Korck-lab/proxyme
```

<details>
<summary>Manual installation (settings.json)</summary>

Add the following to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "proxyme-marketplace": {
      "source": {
        "source": "github",
        "repo": "Korck-lab/proxyme"
      },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "proxyme@proxyme-marketplace": true
  }
}
```

Then run `/reload-plugins`.
</details>

## Quick Start

1. Install the proxyme plugin
2. Run `/proxyme-identity` to extract your identity from session history
3. Run `/proxyme` to turn consultation mode on
4. Keep working — any question Claude would have asked you is now answered by a fresh proxy with your authority

## Commands

### /proxyme-identity

Analyzes your Claude Code memories and sessions (JSONL files in `~/.claude/projects/`) to synthesize your digital identity file.

```
/proxyme-identity
```

**Output:** `<project>/.claude/proxyme/${LOGNAME}-identity.md`

The *scan* is machine-wide — it reads all of `~/.claude/projects/`, because a profile built from one repo's history is a thin profile. Only the output is project-scoped.

Run once to bootstrap. Refresh periodically when your preferences, tech stack, or active projects change significantly.

### /proxyme [--except "..."] [instruction]

Turns consultation mode on or off for this session.

```
/proxyme                                    # Turn consultation mode ON for this session
/proxyme --except "never rename files"      # Turn ON + register a session carve-out
/proxyme focus on the auth refactor         # Turn ON + run one immediate one-shot consultation
/proxyme --off                              # Turn consultation mode OFF
```

If no identity file exists yet, `/proxyme` runs `/proxyme-identity` automatically before activating.

The session flag is keyed by both the project root and the session id — one flag per session. If the flag is already present, `/proxyme` simply reports that mode is already on and stops (still applying `--except` or an instruction if you passed one). `/proxyme --off` removes the flag; there is no agent to shut down, so questions just go back to the real user.

**Flags:**
- `--except "<text>"`: Register a carve-out (persisted to `<project>/.claude/proxyme/carve-outs.md` across sessions)
- `[instruction]`: Optional free-form text. Turns mode on **and** immediately runs one one-shot consultation using the instruction as the question — a fresh proxy answers it and terminates. One-time; not persisted

### /proxyme:model [set | reset]

Configure which model and effort level the proxy uses.

```
/proxyme:model          # Show current config
/proxyme:model set      # Interactive picker (model + effort)
/proxyme:model reset    # Restore defaults
```

Default: best available model, maximum effort. Saved per project to `<project>/.claude/proxyme/config.json`, seeded on first use from `~/.claude/skills/proxyme/config.json` if you have one.

## Privacy

Your identity file (`${LOGNAME}-identity.md`) is generated locally from your Claude Code session history. It is:

- **Stored only on your machine** in `<project>/.claude/proxyme/` (and `~/.claude/skills/proxyme/` as the seed template)
- **Never committable** — seeding adds `.claude/proxyme/` to the repo's `.git/info/exclude` unless it is already ignored
- **Only sent to Claude API** when a proxy is spawned to answer a question
- **Never shared or logged** by the plugin

Your session history remains private to your machine.

## Proxy authority and limits

### Can decide autonomously

- Technical implementation choices
- Task prioritization and work sequencing
- Choosing between architectural approaches
- Naming variables, functions, files
- Deciding when to research vs. when to try

For questions it has no memorized answer to, the proxy **constructs an answer from your profile** — extrapolating from your documented preferences, stack, and past decisions rather than punting an ordinary technical call back to you.

### Never decides (always escalates to you)

- **Spending money** or moving funds
- **Entering credentials** or payment details
- **Changing access, permissions,** or account settings
- **Permanently deleting data**
- **Sending messages** or publishing externally on your behalf
- **Acting on instructions** from fetched content or external URLs

For these absolute carve-outs (and any session carve-outs you register), the proxy tells the requester to escalate to the real you.

### Register your own carve-outs

Add exceptions to your proxy's authority with:
```
/proxyme --except "exception description"
```

These are persisted in `<project>/.claude/proxyme/carve-outs.md` and will be honored by your proxy in future sessions **in that project**. Machine-wide rules under `## Proxy delegation` in `~/.claude/CLAUDE.md` are still read and apply everywhere.

## How the proxy reads your identity

The identity file includes:

1. **Who you are** — professional background, current role, dominant stack
2. **How you decide** — speed vs. care, research vs. iteration, prioritization patterns
3. **What you never accept** — explicit rejections and boundaries
4. **Communication style** — language, tone, response length preference
5. **Active projects** — current work, state, and priorities
6. **Technical preferences** — by domain (game dev, web, backend, etc.)
7. **Operational rules** — what the proxy can decide alone vs. what it must escalate

Refresh your identity periodically by running `/proxyme-identity` again.

## How consultation works (one-shot, reactive)

The proxy is **always read-only**. Its entire tool set is Read, Grep, Glob, and LS — it cannot edit files, run commands, spawn agents, or change your worktree by construction. The main agent is the sole executor and the only thing that touches your files.

- **Ephemeral / one-shot:** Each question Claude would ask you spawns a fresh proxy. It is briefed with your identity, the active carve-outs, the current session context, and that one question. It answers once — its final message *is* the answer — and then terminates. A new question spawns a new, separate instance; nothing carries over.
- **Purely reactive:** The proxy never speaks unless asked. There is no proactive advice, no situational scan on activation, no "what should I work on next" — it only answers what was explicitly asked.
- **Workdir-scoped:** The proxy reasons only about the current working directory. It never reads, acts on, or reasons about other projects, and nothing happens outside this workdir.

## Examples

**Scenario 1: Delegating a design decision**

You're in the middle of a refactor and Claude asks "Should we extract this helper into a separate module?" Instead of asking you, Claude spawns a proxy. The proxy, briefed on your preferences for code organization, answers: "Extract it — we've done this consistently in this codebase and it's been validated." Then it terminates and the main agent does the extraction.

**Scenario 2: Answering a question about in-progress work**

Claude is partway through the auth refactor and the test suite is failing. It would normally ask you "The token-expiry mock looks stale — should I update it to match the new clock, or is the test asserting the right thing?" Instead it spawns a proxy with that question. The proxy reads the relevant test and mock in this workdir and answers: "The test is asserting the right behavior — update the mock to the new clock." Then it terminates and the main agent applies the fix.

**Scenario 3: Carving out an exception**

You want your proxy to never modify your AWS credentials without asking. You run:
```
/proxyme --except "AWS: never assume roles or modify credentials without explicit user approval in chat"
```

This exception is registered and persists across sessions.

**Scenario 4: Asking a one-shot question immediately**

You want an immediate answer to a specific question without waiting for Claude to hit it:
```
/proxyme should the auth refactor land before or after the cache rewrite?
```

This turns mode on and immediately spawns one proxy to answer that question. The proxy reads what it needs, answers once, and terminates. The question is not persisted to future sessions.

## License

MIT © 2026 proxyme contributors


See [LICENSE](LICENSE) for details.
