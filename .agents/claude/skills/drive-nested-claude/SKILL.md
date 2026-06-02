---
name: drive-nested-claude
description: >-
  Drive a nested, interactive `claude` (Claude Code) session running inside a tmux pane — send it a
  prompt, reliably detect when its turn has finished generating, read its reply, navigate its TUI
  menus (/config, /theme, /agents, permission and trust dialogs), and verify behavior by real signals
  instead of the model's prose. Use whenever you need to programmatically operate ANOTHER claude
  session from the outside: "drive a nested claude session", "test the claude TUI in tmux", "automate
  / QA a Claude Code session", "send a prompt to a claude running in a container and read its output",
  "answer claude's permission dialog over tmux". Especially for QA-ing plugins/skills/hooks/MCP/LSP by
  exercising a real claude session. Builds on tmux send-keys / capture-pane (see the companion
  `tmux-interactive-driver` skill for base mechanics). NOT for using your OWN tools to answer a
  question, and NOT for one-shot `claude -p "..."` headless calls — reach for this only when you must
  drive a LIVE interactive claude session and watch what a human would see on screen.
---

# drive-nested-claude

## Overview

Driving a nested `claude` session through tmux is the only way to verify what a **human actually sees**
in an interactive Claude Code session — which is exactly what you need to QA plugins, skills, hooks,
MCP servers, LSP servers, slash commands, and TUI menus (`/config`, `/theme`, `/agents`). A one-shot
`claude -p "..."` won't do it: it has no TUI, no permission dialogs, no session-start behavior, no
`/config` panel. You must launch a real `claude` in a tmux pane and operate it from outside.

This skill is the **specialized application** of the general `tmux-interactive-driver` skill. The base
mechanics (targets, `send-keys -l` then a separate `Enter`, `capture-pane -p -S -N`, the lifecycle
verbs) are documented there — read it if you're shaky on those. What follows is everything that is
**specific and surprising about claude as the nested REPL**, almost all of it learned the hard way.

The four things that make claude different from a plain REPL:

1. **"Done generating" is not "the prompt is back."** The `❯` input prompt is on screen the *entire*
   time, including mid-generation. Readiness must gate on the **busy indicator** (`esc to interrupt`),
   not on `❯`. Use `scripts/wait_for_prompt.py` (its defaults are tuned for exactly this).
2. **The TUI shows grey "ghost" text that is not your input** — and `C-u` won't clear it. Ignore it.
3. **Bare slash commands** (`/config`, `/theme`, `/agents`) get mangled on Windows hosts unless you
   set `MSYS_NO_PATHCONV=1`. Namespaced ones (`/plugin:cmd`) are immune.
4. **A capable model describes things as if they happened.** It will narrate "the hook fired" or
   describe a bug it read — whether or not the construct actually ran. **Verify by real signals**
   (a sentinel file, a settings write, a `Called plugin:…` line, a `(source)`-tagged diagnostic), and
   establish a **causal control** so your proof isn't a coincidence.

## Examples

### Example 1 — send a prompt and detect when the turn finished (verified live)

The readiness loop is the whole game. The poller blocks until `❯` is present, `esc to interrupt` is
absent, and the screen has been stable for a few polls — i.e. the turn truly ended.

```bash
PROMPT=scripts/wait_for_prompt.py     # claude-tuned defaults: ready=❯, busy='esc to interrupt', settle=3

# Launch claude in a clean pane (inside container qa-claude here):
docker exec qa-claude tmux respawn-pane -k -t 0:0.0 -c /workspace 'bash -l'
docker exec qa-claude tmux send-keys -t 0:0.0 -l 'claude'
docker exec qa-claude tmux send-keys -t 0:0.0 Enter
python "$PROMPT" --container qa-claude --target 0:0.0 --timeout 40   # wait out the boot/first turn

# Send a prompt (text, then Enter as a SEPARATE call):
docker exec qa-claude tmux send-keys -t 0:0.0 -l 'In one short sentence, what is 2+2?'
docker exec qa-claude tmux send-keys -t 0:0.0 Enter

# Wait through generation back to idle, then read:
python "$PROMPT" --container qa-claude --target 0:0.0 --timeout 40 --verbose
docker exec qa-claude tmux capture-pane -p -t 0:0.0 -S -40 | grep -v '^[[:space:]]*$' | tail -n 6
```

The `--verbose` trace makes the state machine visible (real capture) — note `ready=True` from the
very first poll, while `busy` is what actually changes:
```text
[0.0s] ready=True busy=True  unchanged=False stable=0   ← ❯ present, but STILL GENERATING
[1.0s] ready=True busy=False unchanged=False stable=0   ← generation done, screen still settling
[2.0s] ready=True busy=False unchanged=True  stable=1
[2.5s] ready=True busy=False unchanged=True  stable=2   → exit 0  (now safe to send/read)
```
Expected reply in the capture: `● 2+2 equals 4.` This is why gating on `❯` alone fails — you'd fire
at 0.0s, mid-generation. The busy-regex + settle is the fix.

### Example 2 — answer claude's interactive dialogs

Claude blocks on dialogs (trust, edit permission, tool permission). Each is a menu with a highlighted
row; `Enter` accepts the highlighted choice. Always `wait`/`sleep` for the dialog to render first.

```bash
# After a prompt that triggers an edit, the "Do you want to make this edit?" dialog appears (~6-9s):
sleep 8
docker exec qa-claude tmux capture-pane -p -t 0:0.0 | tail -n 8     # confirm the dialog is showing
docker exec qa-claude tmux send-keys -t 0:0.0 Enter                 # option 1 "Yes" (highlighted)
# "Yes, allow all edits this session" is option 2 → send Down then Enter instead.
```
- **Trust this folder?** (first launch in a dir): `Enter` accepts. If the path was trusted before, no
  dialog appears — don't wait forever for it.
- **Tool-permission** (e.g. an MCP tool): same pattern, `Enter` to allow once.

### Example 3 — navigate a bare-slash TUI menu (`/config`, `/theme`, `/agents`)

```bash
# Bare slashes need MSYS_NO_PATHCONV=1 on Windows hosts (see Troubleshooting):
MSYS_NO_PATHCONV=1 docker exec qa-claude tmux send-keys -t 0:0.0 -l '/agents'
docker exec qa-claude tmux send-keys -t 0:0.0 Enter
sleep 3
docker exec qa-claude tmux send-keys -t 0:0.0 Left          # /agents OPENS ON "Running" — go Left to "Agents"
sleep 1
docker exec qa-claude tmux capture-pane -p -t 0:0.0 | tail -n 20    # now the Plugin agents group is visible
```
For `/config` → a setting: type to filter, `Enter` to select the row, `Space` to open the value list,
arrow to the choice, `Enter` to commit (the write lands on THIS inner Enter — see Troubleshooting).

## Troubleshooting

Sourced from this project's `PITFALLS.md` and from live dogfooding. Each is a real trap with its fix.

### You send `❯`-based "is it done?" checks and fire mid-generation
- **Cause:** the `❯` input prompt is rendered the whole time, including while Claude is generating. It
  is NOT an idle signal.
- **Solution:** gate on the **busy indicator**. Claude shows `esc to interrupt` (and a spinner like
  `✻ Cogitated…`) only while a turn is live. Ready = `❯` present AND `esc to interrupt` absent AND
  screen stable for N polls. `scripts/wait_for_prompt.py` defaults to exactly this (`--busy-regex
  'esc to interrupt'`, `--settle 3`). Never send the next prompt while a spinner is up — it queues or
  is dropped.

### Grey "ghost" text sits in the input box and `C-u` won't clear it
- **Cause:** the dimmed grey text (e.g. `explore the project`, `git init`) is an **autocomplete hint
  from session history**, rendered as an overlay — not editable input. `C-u`/`Escape` clear real typed
  characters, but the hint is not a typed character, so it stays on screen. (8 of 9 cold-read QA agents
  burned tool calls fighting this.)
- **Solution:** **Ignore it.** It never submits on its own and never concatenates with your input. Just
  `send-keys -l '<your prompt>'` — the hint vanishes the moment real characters land. Do not loop on
  `C-u`.

### A bare slash command becomes a Windows path (`/agents` → `C:/Program Files/Git/agents`)
- **Cause:** Git-for-Windows' MSYS layer rewrites Unix-looking lone arguments to Windows paths before
  the process sees them. `/agents` matches the absolute-path heuristic; claude then receives a path and
  replies "what should I do with this path?" and may open an intent picker. Namespaced slashes
  (`/dgxsparklabs-cmd:hello`) survive because the `:` makes MSYS treat the token as a PATH list.
- **Solution:** Prefix the send-keys call with `MSYS_NO_PATHCONV=1` (the `Enter` keystroke needs no
  flag), or drive tmux from PowerShell. Affects every bare-slash command: `/agents`, `/mcp`, `/config`,
  `/theme`, `/clear`, `/exit`, `/compact`.

### `/agents` shows "No subagents are currently running" — looks broken
- **Cause:** the picker has tabs `Agents | Running | Library` and **opens on `Running`**, which is empty
  unless a sub-agent is mid-flight. The plugin agents live on the `Agents` tab. This matches the
  "agent loader broken" failure signal, so it reads as a false negative.
- **Solution:** press **`Left` once** to reach the `Agents` tab; the `Plugin agents` group is there.

### `/config` → "I set it but it didn't take" (output style and friends)
- **Cause:** in `/config`, after `Space` opens the value list and you press `Enter` on a choice, the
  setting is **written immediately** (the inner Enter) and you return to the row whose footer now reads
  "Enter to save · Esc to cancel". People assume nothing committed yet and over-press or bail.
- **Solution:** the write lands on the **inner (list) Enter**. Verify persistence right then (e.g.
  `cat .claude/settings.local.json`); the outer Enter/Esc only closes the panel and does not revert.
  Note also: there is no `/output-style` command in recent CLIs — output style is a `/config` setting;
  `/theme` is still its own picker.

### `capture-pane | tail` is blank, clipped, or missing the answer
- **Cause:** `capture-pane -p` returns only the visible screen, padded with blank rows below the cursor;
  a chatty turn also scrolls the block past a small `tail`. (The permission dialog alone is ~14 lines.)
- **Solution:** widen and de-blank: `capture-pane -p -t T -S -40 | grep -v '^[[:space:]]*$' | tail -n N`.
  When the proof is a **file** (hook sentinels `/tmp/hook-fired-*.log`, an MCP proxy log, an LSP input
  log), read the file with `cat` — the screen is for dialogs, files are for evidence.

### You "verified" a construct but it may never have run (prose ≠ proof)
- **Cause:** a capable model narrates plausibly: "the hook fired", "the LSP flagged an undefined name",
  "monitors reported disk usage" — from its own reasoning, whether or not the construct executed. The
  in-chat text is not evidence.
- **Solution:** assert on a **machine signal**: a sentinel file written, a `settings.json`/`.local.json`
  value, a `Called plugin:…:<tool>` line, a `(example-lsp)`-tagged diagnostic, a `--debug` log line. For
  monitors specifically, forbid tool use in your probe ("Without running any tool, quote the
  session-start monitor context") so the model can't just re-run `df` and fake it.

### Your "proof" would pass even if you'd done nothing (no causal control)
- **Cause:** the session/container persists state — a theme may already be the target value, hook
  sentinels from session-start already exist before your action. Checking "is the value present now?"
  can't distinguish your action from prior state.
- **Solution:** establish a control first. Hooks: `rm -f /tmp/hook-fired-*.log` before the action (the
  `rm` is the experiment, and remember SessionStart/Stop already fired at launch). Settings: set a
  *different* value first, confirm it, then set the target — so the `before → after` change is one you
  caused.

### In-session timestamps don't match the host clock
- **Cause:** a long-running container's clock can lag the host; all in-container output (`date`, hook
  payloads, skill output) uses the container clock.
- **Solution:** match the **shape** of timestamped output, never the literal date/time. A date mismatch
  with everything else correct is clock skew, not a defect.

### Exit / restart cleanly
- **Cause:** `Ctrl-C` interrupts the current turn, it does not quit claude; a half-typed prompt blocks
  the next send.
- **Solution:** quit with `MSYS_NO_PATHCONV=1 … send-keys -l '/exit'` then `Enter` (this also fires the
  `SessionEnd` hook). To force a clean slate, `tmux respawn-pane -k -t T -c /abs 'bash -l'` then relaunch
  `claude`. Use a unique session name per concurrent driver so parallel QA runs don't share one pane.

## Test suites

### Trigger suite

**Should trigger:**
- "Launch a claude session in the qa-claude container and ask it to run `/dgxsparklabs-command…:hello`, then tell me what rendered."
- "Drive a nested claude session over tmux and verify the hook plugin actually fires (check the sentinel files)."
- "I need to QA the `/config` output-style picker in a real Claude Code TUI — operate it and confirm the persisted value."
- "Send a prompt to the claude running in pane 0:0.0, wait for it to finish, and capture the reply."
- "Answer the permission dialog in the claude session and continue the flow."

**Should NOT trigger (near-misses):**
- "What does `claude -p 'summarize this'` output?" → one-shot headless call; just run it.
- "Explain how Claude Code hooks work." → a knowledge question, no live session to drive.
- "Use your tools to read this file and find the bug." → use your own tools; no nested claude needed.
- "Drive a python REPL in tmux." → use the general `tmux-interactive-driver` skill (no claude TUI).
- "Install the claude CLI." → setup, not driving a running session.

### Functionality suite

- **Given** a freshly launched nested claude, **when** the agent sends a prompt and calls
  `wait_for_prompt.py` (claude defaults), **then** it blocks while `esc to interrupt` is shown and only
  returns ready once the spinner clears and the screen is stable — never mid-generation.
- **Given** a grey ghost-suggestion in the input box, **when** the agent sends its prompt, **then** it
  does NOT loop on `C-u` and the prompt is delivered correctly.
- **Given** a Windows host and a `/agents` command, **when** the agent sends it, **then** it uses
  `MSYS_NO_PATHCONV=1` and presses `Left` to reach the Agents tab before reading.
- **Given** a claim that a hook fired, **when** the agent verifies, **then** it reads the sentinel
  **file** (after a pre-action `rm` control), not the model's chat narration.
