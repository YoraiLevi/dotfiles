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

## Design rationale

This palette was chosen against published research, not intuition. The decisions below explain *why each color was picked* and, just as importantly, *why other obvious choices were rejected*. If the palette is ever revised, revisit this section first — most "obvious improvements" are alternatives that were already considered and ruled out for documented reasons.

### Why these hex values, not standard CSS reds and greens

Sourced from the Okabe-Ito palette (8 colorblind-safe categorical colors), with one substitution from IBM Carbon for the "done" category. Primary sources:

- Wong, B. (2011). "Points of View: Color blindness." *Nature Methods* 8:441. https://www.nature.com/articles/nmeth.1618 — the canonical publication of the palette in a peer-reviewed venue.
- Okabe, M. & Ito, K. (2008). "Color Universal Design (CUD)." https://jfly.uni-koeln.de/color/ — the originating source, with explicit CVD simulation and per-color rationale.
- IBM Carbon Design Language data-vis palettes (Shixie, IBM Carbon team, Medium): https://medium.com/carbondesign/color-palettes-and-accessibility-features-for-data-visualization-7869f4874fca — source for the ultramarine `#648FFF` used for "done".

Standard CSS color names (`red`, `green`, `blue`, `orange`, `purple`) and pure-channel hex values (`#FF0000`, `#00FF00`, `#FFFF00`) were rejected because they have not been tested under CVD simulation, have inconsistent perceived luminance across hues, and were designed for 1990s color displays rather than accessibility-aware semantic marking.

### Why blue for "done", not green — the most important decision in the palette

Conventional UI (Material Design 3, Apple HIG, GitHub success states) maps green to success/confirmed. This palette deviates from convention deliberately:

- **Prevalence of red-green deficiency:** approximately 8% of men and 0.5% of women have some form of protanopia or deuteranopia (combined including milder anomalous variants). Source: https://colorblind.io/learn/statistics
- **The confusion pair:** red vs. green is *the single most commonly confused pair* under both protanopia and deuteranopia. Source: Okabe & Ito (2008), Tableau data viz team.
- **The specific risk in this palette:** "blocker" is vermillion-red and "done" is the semantically *opposite* category. If "done" were green, ~1 in 12 male readers would silently misread the most semantically loaded color pair in the palette, without ever knowing.
- **Industry precedent for the same swap:** Tableau's design guidance and GitHub's CI status indicators both replace green with blue in red-green contexts. Source: https://www.tableau.com/blog/examining-data-viz-rules-dont-use-red-green-together
- **Robustness of blue:** blue-family colors are the most reliably preserved across all CVD types (protanopia, deuteranopia, *and* tritanopia).

The cultural friction (readers expecting green) is one-time — a reader adapts after seeing the convention once. The accessibility cost of green-paired-with-red is permanent and silent. Asymmetric costs, asymmetric decision.

### Why these specific five categories, not more or fewer

Five is the upper bound for reliable application by an AI writer:

- Each additional category increases miscategorization risk. Fewer categories with broader semantic coverage produce more consistent vault state than many narrow ones.
- The Okabe-Ito palette provides eight colors total, but using all eight reduces inter-color distinguishability under CVD simulation and adds memorization burden for the writer.
- Yellow (`#F0E442` in Okabe-Ito) was explicitly *excluded* — it has approximately 1.3:1 contrast against a white background, far below the WCAG AA 4.5:1 threshold for small text. Source: easystats/see R package documentation (https://easystats.github.io/see/reference/scale_color_okabeito.html), which provides `#F5C710` as the light-background-safe variant; we still don't use it because adding a sixth category exceeds the AI-reliability bound above.
- Black, gray, and white are reserved for plain prose. Coloring text "black" against an already-black-text default conveys nothing.

### Why `bold: true` on every color

The Okabe-Ito hex values were designed for chart *areas* on white paper — filled regions where contrast comes from coverage, not stroke weight. Used as inline text on a light theme, several colors fall below WCAG AA 4.5:1 contrast for small text: vermillion, sky blue, and reddish purple all fail at the default text weight against white. Bold roughly doubles perceived contrast without shifting hue, restoring readability without redesigning the palette. Sources: W3C WCAG 2.0 SC 1.4.3 Contrast (Minimum) https://www.w3.org/TR/WCAG20/#visual-audio-contrast-contrast and the Okabe-Ito documentation noting the chart-area design context.

If a future user prefers non-bold and accepts the light-theme contrast tradeoff, flip all five `bold` fields to `false` in `data.json` — this is a personal-comfort knob, not a research-mandated requirement.

### Why the BLOCKER: / CAUTION: / DONE: / NOTE: / TODO: text prefix is required

Color alone is not allowed to carry semantic meaning under any modern accessibility standard. The requirement comes from:

- W3C WCAG 2.0 Success Criterion 1.4.1 "Use of Color" (Level A, the most basic tier): https://www.w3.org/TR/UNDERSTANDING-WCAG20/visual-audio-contrast-without-color.html — "color is not used as the only visual means of conveying information."

Beyond the formal accessibility requirement, the prefix survives every degraded-rendering case the plugin can encounter:

- Color stripping when files render on GitHub/GitLab (the platform's Markdown engine drops the plugin's CSS classes entirely).
- Plugin uninstallation or version migration breaks.
- Reading the file as plain text via `cat`, `bat`, or any non-Obsidian viewer.
- Color vision deficiency in the reader.

The prefix costs four to seven characters per use and pays off in every one of those cases.

### Palettes considered and explicitly rejected

- **ColorBrewer qualitative palettes** (Cynthia Brewer, Penn State, https://colorbrewer2.org): well-researched for cartography. Some palettes are flagged "colorblind safe" but support a maximum of 5–6 categories in that mode, with provenance optimized for filled map regions rather than text. Okabe-Ito has cleaner provenance for non-cartographic use and equivalent CVD safety.
- **Viridis / Cividis** (Berkeley Visualization Lab): designed for *sequential* (ordered) data — gradients. Categorical use is an explicit anti-pattern in the documentation. Wrong tool entirely.
- **Material Design 3 semantic colors** (Google): well-designed for UI, but uses the conventional red-error / green-success pairing this palette specifically rejects for the CVD reason above. We borrowed the *naming convention* (error / warning / success / info) but not the colors.
- **Apple HIG semantic colors:** same red-green confusion as Material; rejected for the same reason.
- **Bright "primary" CSS values** (`#FF0000`, `#00FF00`, `#0000FF`): no CVD testing, inconsistent perceived luminance, designed for 1990s CRT displays. Rejected.

### Formatting choices considered and rejected

- **Italic-only emphasis:** italic does not survive screen readers consistently and is harder to read at small sizes (Source: NN/g, "Typography for the Web"). Rejected as the sole signal.
- **All-caps for category labels:** discouraged by WCAG 1.4.8 (Visual Presentation) when applied to blocks of text. Acceptable for the short prefix word ("BLOCKER") but not for the body of the colored span — which is why the plugin's `cap_mode` is left at `normal` in `data.json` and only the prefix is uppercased manually in the convention.
- **Underline:** historically reserved for hyperlinks in web contexts (Source: Nielsen Norman Group, "Guidelines for Visualizing Links"). Using underline as a non-link signal causes false-affordance confusion. Rejected.

## Notes for the executing agent

- This skill writes exactly one file. It does not install the plugin, does not edit the user's CLAUDE.md, and does not modify any other vault files.
- The `data.json` bundled with this skill is the source of truth for the palette. If the palette ever changes (different hex values, added/removed categories), edit the bundled `data.json` and re-run the skill against each vault that needs updating.
- If the user has many vaults and asks for a batch run, do not extend this skill — invoke it once per vault and report the aggregate.
