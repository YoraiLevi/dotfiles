# Claude Code — User-level memory

## Obsidian vaults

Every project is also an Obsidian vault. When writing .md files in the vault, keep the
reader put. they shouldn't chase references to understand the current note.

Choose constructs by intent:

- `[[Note]]` — link for *further reading*. Each link should mean something;
  don't link every mention of a word.
- `![[Note]]` / `![[Note#Heading]]` / `![[Note#^id]]` — transclude when
  content is needed *in place*. Embed instead of paraphrasing.
- `#tag` (nested `#topic/sub` welcome) — group by topic. Tag consistently,
  sparingly, memorably. lowercase, singular.
- Properties (frontmatter) — for facts *about* the note (status, type,
  date). Use these instead of tags for anything typed or queryable.
- Folders — group by type, not topic. A file has many tags but one
  location; folders are the coarse first filter.

Maps (MOCs) are workbenches, not indexes — write what you think about a
topic and let links emerge. Don't auto-sprinkle links just because the
target exists. Let folder and tag structure evolve from use, not from a
prescribed layout.
### Colored text (fast-text-color plugin)

When writing documentation, mark text that falls into one of five semantic
categories using the fast-text-color plugin. Always include the category
label as a text prefix so meaning survives when color is stripped
(GitHub renders, CVD readers, plugin uninstalled).

| Category | Syntax                        | Use for                          |
| -------- | ----------------------------- | -------------------------------- |
| blocker  | `~={blocker} BLOCKER: ... =~` | hard stop, must-fix              |
| caution  | `~={caution} CAUTION: ... =~` | warning, risk, decision needed   |
| done     | `~={done} DONE: ... =~`       | confirmed fact, verified outcome |
| info     | `~={info} NOTE: ... =~`       | definition, neutral annotation   |
| action   | `~={action} TODO: ... =~`     | next step, owner-assigned action |
## Subagent Workflow

Whenever possible, assign subagents to perform the task instead of doing it yourself.
Inform the subagent with the HOW WHAT and WHY.
Delegating work is always intentional and made to help us do more rather than less
Don't delegate if it's not going to ease our life and improve our outputs.

## Answering style

In addition to existing styles, phrase sentences in a converstational form.
Keep the response style digestable to to a listening audience
Responses to the user are converted automatically to audio and read to the user.
The TTS is smart and can handle ASCII art and other special character inputs

## Tool-use behavior

### TaskCreate

Call TaskCreate before starting work whenever any of these are true:

- The task requires 3+ tool calls
- The task has distinct sequential steps
- The user has provided multiple things to do (numbered, comma-separated, or implied)
- You are about to spend significant time / tokens on a multi-stage workflow

Mark tasks `in_progress` before starting each one. Mark `completed` immediately on finish — don't batch updates.

### AskUserQuestion

Use AskUserQuestion (don't guess) whenever any of these are true:

- The user's intent has multiple reasonable interpretations
- You are about to make a hard-to-reverse decision (file deletion, force-push, destructive operation, large-scope refactor)
- Two or more design paths exist with no strong reason to prefer one
- You are about to spend significant tokens on a path the user might not want

Default to asking, not assuming. A 30-second clarifying question saves minutes of misaligned output.

---

## Project-progression discipline (STATE-check protocol)

### Per-response protocol

1. **Before responding** to any message that constitutes a project-progression — executing a phase, completing a task, proposing a next step, asking for clarification on what to do next

2. **After completing a meaningful step** that changes project state (task completion, phase advance, new gap surfaced, decision made), **UPDATE** the `STATE.md` to reflect the new state.

3. **If the user asks what we have been up to so far?, where we are at?, immediately produce the current state-check line. This is the fast-failure-detection mechanism for cases where step 1 or step 2 was skipped.

### Why this discipline exists

This protocol was installed because methodology-skipping recurred three times in the session that produced these instructions — each catch came from the user, not from any structural mechanism. Without enforcement, the recurrence pattern continues. The state-check converts invisible methodology skips into visible *missing lines* the user can call out in one word.

The protocol is **fast-failure detection, not failure prevention.** Real prevention would require hooks or wrapper agents that can mechanically block non-compliant responses; those don't exist yet. The state-check is the realistic ceiling until they do.

### What counts as "project-progression"

- Executing or completing a task
- Proposing the next concrete step
- Reporting validation or research findings
- Making a design or commit decision
- Asking the user a clarifying question that branches the project

**Not** project-progression (state-check optional):

- Pure conversational reply (e.g., explaining a concept)
- Answering a meta question about Claude Code itself
- Responding to "how does X work" with no project action
