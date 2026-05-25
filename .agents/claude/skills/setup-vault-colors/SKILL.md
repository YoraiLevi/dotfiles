---
name: setup-vault-colors
description: Install the claude-semantic colorblind-safe color palette (5 categories — blocker, caution, done, info, action) into an Obsidian vault's fast-text-color plugin config. Takes a vault path as the argument. Use when the user wants to set up colored text in a new Obsidian vault, replicate the standard palette across vaults, or restore the palette after a reset. Do NOT use for installing the plugin itself — Obsidian's Community Plugins UI must do that first.
---

# setup-vault-colors

Install the `claude-semantic` semantic color palette into a target Obsidian vault's `fast-text-color` plugin config.

## Inputs

- `$1` (required) — absolute path to the Obsidian vault root (the folder that contains `.obsidian/`).
- `--force` (optional) — overwrite an existing `data.json` without asking.

If `$1` is omitted or empty, ask the user for the vault path via `AskUserQuestion`.

## Procedure

Follow these steps in order. Stop at the first failure and report what went wrong; do not continue past a failed precondition.

### 1. Validate the vault path

- The path must exist and be a directory. Use `Glob` or `Read` to confirm.
- The path must contain a `.obsidian/` subdirectory. If it does not, the path is not an Obsidian vault — ask the user to confirm the path or correct it; do not proceed.

### 2. Verify the plugin is installed

- The expected plugin folder is `<vault>/.obsidian/plugins/fast-text-color/`.
- If that folder does not exist, the user has not installed the plugin in this vault yet. Stop and tell the user:
  > "The fast-text-color plugin is not installed in this vault. Open the vault in Obsidian, go to Settings → Community plugins → Browse, search for 'Fast Text Color', then install and enable it. After that, re-run this skill."
- Do not attempt to install the plugin yourself.

### 3. Check for an existing config

- If `<vault>/.obsidian/plugins/fast-text-color/data.json` already exists:
  - If `--force` was passed, proceed.
  - Otherwise, read the file and inspect it. If it contains only the `claude-semantic` theme already (no other themes, same five color IDs), the config is already current — report that and stop, no write needed.
  - If it contains other themes or custom colors, warn the user explicitly: name the themes that will be lost, then ask via `AskUserQuestion` whether to overwrite, merge, or abort. Default to abort.

### 4. Write the config

- Source file: `~/.claude/skills/setup-vault-colors/data.json` (sibling to this SKILL.md).
- Destination: `<vault>/.obsidian/plugins/fast-text-color/data.json`.
- Use a direct file copy. On Windows, prefer `Copy-Item` via the PowerShell tool. On POSIX, use `cp`.
- Verify the destination file size matches the source after copy.

### 5. Report

Tell the user three things:

1. The destination path that was written.
2. That Obsidian must be restarted (or the plugin disabled-and-re-enabled) for the config to take effect — Obsidian caches plugin settings in memory and will overwrite the file on next save otherwise.
3. The five color IDs now available: `blocker`, `caution`, `done`, `info`, `action`. Reference the syntax: `~={blocker} BLOCKER: text =~`.

## The palette installed by this skill

| ID | Hex | Source | Use for |
|---|---|---|---|
| blocker | `#D55E00` | Okabe-Ito vermillion | Hard stop, must-fix, missing dependency |
| caution | `#E69F00` | Okabe-Ito orange | Warning, risk, decision needed |
| done | `#648FFF` | IBM Carbon ultramarine | Confirmed fact, verified outcome |
| info | `#56B4E9` | Okabe-Ito sky blue | Definition, neutral annotation |
| action | `#CC79A7` | Okabe-Ito reddish purple | TODO, next step, owner-assigned action |

Note: "done" is blue, not green, deliberately. Red-green is the most common color-vision-deficient confusion pair (~8% of men); pairing the vermillion blocker against a green done would silently break for those readers. Sourcing: Wong 2011 (Nature Methods), Okabe & Ito 2008 (jfly.uni-koeln.de), IBM Carbon design language.

All five colors are set to `bold: true` in the config to improve light-theme contrast — the Okabe-Ito hex values were designed for chart marks on white paper, not for text strokes, and bold roughly doubles the perceived contrast without shifting the hue.

## Notes for the executing agent

- This skill writes exactly one file. It does not install the plugin, does not edit the user's CLAUDE.md, and does not modify any other vault files.
- The `data.json` bundled with this skill is the source of truth for the palette. If the palette ever changes (different hex values, added/removed categories), edit the bundled `data.json` and re-run the skill against each vault that needs updating.
- If the user has many vaults and asks for a batch run, do not extend this skill — invoke it once per vault and report the aggregate.
