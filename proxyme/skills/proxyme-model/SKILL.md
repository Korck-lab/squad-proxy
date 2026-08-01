---
name: proxyme-model
description: "Configure which model and effort level your proxyme proxy uses. Shows current config and lets you pick a new one. /proxyme:model → show current; /proxyme:model set → interactive picker; /proxyme:model reset → restore defaults."
argument-hint: "[set | reset]"
allowed-tools: Bash, Read, Write
---

# /proxyme:model

Configure the model and effort level used when `/proxyme` spawns your proxy agent.

Config is **project-scoped**: it is saved to `<root>/.claude/proxyme/config.json` and read every time `/proxyme` activates in that project. Each repo carries its own model/effort budget.

Resolve the path first — never hand-write it. `PLUGIN_ROOT` is the directory two levels above this skill's base directory (stated in the launch header); `$CLAUDE_PLUGIN_ROOT` is **not** set in Bash tool calls.

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"
```

That defines `PROXYME_DIR` and `PROXYME_CONFIG`, assumed in scope by every snippet below.

## Reporting style

Print the blocks below and nothing else — no preamble, no explanation of what the config does, no closing summary, no offer of further help. If a write fails, say so and quote the error verbatim. Ask the picker questions in the language the user is writing in.

## Syntax

```
/proxyme:model           → show current configuration
/proxyme:model set       → interactive picker (model + effort)
/proxyme:model reset     → restore defaults (opus, xhigh)
```

## What to do when invoked

### No argument or `show`

Read and display current config:
```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"; cat "$PROXYME_CONFIG" 2>/dev/null || echo '{"model":"opus","effort":"xhigh"}'
```

Display as:
```
Current proxy config:
  Model:  <model>
  Effort: <effort>

Run /proxyme:model set to change.
```

---

### `set` — interactive picker

**Step 1 — Show model options and ask:**

```
Choose proxy model:

  1. opus    — Most capable. Best judgment, highest cost. (default)
  2. sonnet  — Balanced. Fast and capable, lower cost.
  3. haiku   — Fastest. Good for simple delegation tasks.
```

Wait for user to pick 1, 2, or 3 (or type the name directly).

**Step 2 — Show effort options and ask:**

```
Choose effort level:

  1. xhigh  — Maximum reasoning depth. (default)
  2. high   — Strong reasoning, slightly faster.
  3. medium — Standard effort.
  4. low    — Minimal reasoning. Fast, cheap.
```

Wait for user to pick 1–4 (or type the name directly).

**Step 3 — Save config:**

```bash
eval "$(bash "<PLUGIN_ROOT>/lib/proxyme-paths.sh")"; mkdir -p "$PROXYME_DIR"
```

Write `$PROXYME_CONFIG`:
```json
{"model": "<chosen>", "effort": "<chosen>"}
```

**Step 4 — Confirm:**
```
Proxy config updated:
  Model:  <model>
  Effort: <effort>

Takes effect on next /proxyme activation.
```

---

### `reset`

Write defaults to `$PROXYME_CONFIG`:
```json
{"model": "opus", "effort": "xhigh"}
```

Confirm: `"Proxy config reset to defaults: opus / xhigh."`

---

## Notes

- Config persists across sessions, **per project** — setting it in one repo does not change any other
- If the project has no config file, `/proxyme` seeds it from `~/.claude/skills/proxyme/config.json` on first activation, or defaults to `opus` + `xhigh`
- Changing model while proxy is active has no effect until next `/proxyme` activation
