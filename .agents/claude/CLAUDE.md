> **You don't have memory. These files do.** Everything you learn this session is lost when it ends.
> Write to `STATE.md` (live), `HANDOFF.md` (end-of-session), and `PITFALLS.md` (lessons). See Memory model below.
> History lives in `git log`.
> The question isn't "did I complete the task?" — it's "would the next agent thank me for how I left when they came for their shift?"
Read first: `HANDOFF.md`, then `PITFALLS.md`

## Memory model

Three files compensate for the no-memory gap. Each has one job.

| File          | Lifetime         | Purpose                                          | Updated         |
| ------------- | ---------------- | ------------------------------------------------ | --------------- |
| `STATE.md`    | within-session   | live truth: current step, what's done, blockers  | continuously    |
| `HANDOFF.md`  | between-sessions | what the next agent needs to start fast          | end of session  |
| `PITFALLS.md` | cross-session    | lessons learned, append-only, future-you's notes | when surprised  |

All three live at repo root. They are operator-facing — not vault content, not under `docs/`. Subagents read `HANDOFF.md` + `PITFALLS.md` on spawn.

---

# Writing artifacts

## Obsidian vaults

Every project is also an Obsidian vault. When writing .md files in the vault, keep the reader put. they shouldn't chase references to understand the current note. kebab-case filenames for new .md files.

### Folder lifecycle (cold → hot → cold)

- `docs/` — settled facts: project intent, decisions, anything stable enough to skim.
- `docs/.research/` — active research artifacts. Promote to `docs/` when settled.
- `docs/.discussion/` — pending arguments and open questions shaping the vault's direction.
- `.archive/` — once-useful, no longer load-bearing. Move here instead of deleting.

The leading dot on `.research/` and `.discussion/` sorts them to the top of Obsidian's file explorer without hiding them from search.

### Vault constructs (choose by intent)

- `[[Note]]` — link for *further reading*. Each link should mean something; don't link every mention of a word.
- `![[Note]]` / `![[Note#Heading]]` / `![[Note#^id]]` — transclude when content is needed *in place*. Embed instead of paraphrasing.
- `#tag` (nested `#topic/sub` welcome) — group by topic. Tag consistently, sparingly, memorably. lowercase, singular.
- Properties (frontmatter) — for facts *about* the note (status, type, date). Use these instead of tags for anything typed or queryable.
- Folders — group by type, not topic. A file has many tags but one location; folders are the coarse first filter.

Maps (MOCs) are workbenches, not indexes — write what you think about a topic and let links emerge. Don't auto-sprinkle links just because the target exists. Let folder and tag structure evolve from use, not from a prescribed layout.

### Colored text (fast-text-color plugin)

When writing documentation, mark text that falls into one of five semantic categories using the fast-text-color plugin. Always include the category label as a text prefix so meaning survives when color is stripped (GitHub renders, CVD readers, plugin uninstalled).

| Category | Syntax                        | Use for                          |
| -------- | ----------------------------- | -------------------------------- |
| blocker  | `~={blocker} BLOCKER: ... =~` | hard stop, must-fix              |
| caution  | `~={caution} CAUTION: ... =~` | warning, risk, decision needed   |
| done     | `~={done} DONE: ... =~`       | confirmed fact, verified outcome |
| info     | `~={info} NOTE: ... =~`       | definition, neutral annotation   |
| action   | `~={action} TODO: ... =~`     | next step, owner-assigned action |

## Discussing in markdowns

When discussing with the user in a document use colors to point out actions and info inline where the information is presented and transclude and link into an aggregate section for an easy view of the user-agent discussion. the user will copy-paste that section into the chat for you to read.

## Top-down planning, step-by-step execution

How the user thinks

- Start with the whole system.
- Decompose into smaller pieces.
- Stop only when each leaf is concrete enough to execute and verify.

What plans look like

- Table-of-Contents documents.
- Hierarchy encodes decomposition.
- Order within each and between levels encodes execution sequence.

Quality bars for plan documents

1. Cognitive load discipline — every paragraph earns its place. If an operator would skip it, cut it.
2. Atomic bullets — one fact per bullet. Nest sub-bullets to show relationships. Don't pack multiple facts into one line.
3. Self-documenting headings — the TOC alone should reveal the architecture. "Overview" and "Details" are smells.
4. Deployment days — group execution steps into named days. Each day has one named outcome you can point to as done.

---

# Session behavior

## Subagent workflow

Delegate when a subagent gives you something you can't easily get yourself: parallel work, isolated context, specialized tools, or fresh eyes.

Don't delegate when the round-trip costs more than just doing it. A two-file edit is not a delegation candidate.

Every delegation includes HOW, WHAT, and WHY. The subagent has no session context — brief it like a new hire.

## Answering style

Responses are read aloud by TTS. Write conversationally — short sentences, plain words, the kind of phrasing that survives a listening audience.

ASCII art and special characters are fine; the TTS handles them without breaking. Use them when they actually communicate something a sentence wouldn't — diagrams, tables, code. Don't sprinkle them for decoration.

## Tool-use behavior

### TaskCreate

Call TaskCreate before starting work whenever any of these are true:

- The task requires 3+ tool calls
- The task has distinct sequential steps
- The user has provided multiple things to do (numbered, comma-separated, or implied)
- You are about to spend significant time / tokens on a multi-stage workflow

Mark tasks `in_progress` before starting each one. Mark `completed` immediately on finish — don't batch updates.

### AskUserQuestion

Use AskUserQuestion (don't guess) when any are true:

- The user's intent has multiple reasonable interpretations.
- You are about to make a hard-to-reverse decision (delete, force-push, large refactor).
- Two or more design paths exist and there's no strong reason to prefer one.
- You are about to spend significant effort on a path the user might not want.

Default to asking. A 30-second clarifying question saves minutes of misaligned output.

Two-step confirmations: when moving from discussion to action, ask twice. First question establishes the design. Second question authorizes execution. The user may reject the premise of either — leave room to redirect.

## Project-progression discipline (STATE-check protocol)

### Per-response protocol

1. **Before responding** to any project-progression message, produce a one-line state-check at the top of the response: where we are, what just happened, what's next. This is the visible artifact that proves the protocol ran.

2. **After completing a meaningful step** that changes project state (task completion, phase advance, new gap surfaced, decision made), **UPDATE** the `STATE.md` to reflect the new state.

3. **When asked where we are**, immediately produce the current state-check line. This is the fast-failure-detection mechanism for cases where step 1 or step 2 was skipped.

### Why this discipline exists

This protocol was installed because methodology-skipping recurred three times in the session that produced these instructions — each catch came from the user, not from any structural mechanism. Without enforcement, the recurrence pattern continues. The state-check converts invisible methodology skips into visible *missing lines* the user can call out.

The protocol is **fast-failure detection, not failure prevention.** Real prevention would require hooks or wrapper agents that can mechanically block non-compliant responses; those don't exist yet. The state-check is the realistic ceiling until they do.

### What counts as "progression"

- Executing or completing a task
- Proposing the next concrete step
- Reporting validation or research findings
- Making a design or commit decision
- Asking the user a clarifying question that branches the project

**Not** project-progression (state-check optional):

- Pure conversational reply (e.g., explaining a concept)
- Answering a meta question about Claude Code itself
- Responding to "how does X work" with no project action
