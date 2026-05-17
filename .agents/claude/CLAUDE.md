# Claude Code — User-level memory

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

**Trigger:** This applies whenever you are working in a project directory that contains a top-level `INDEX.md` with a `## STATE` section.

### Per-response protocol

1. **Before responding** to any message that constitutes a project-progression — executing a phase, completing a task, proposing a next step, asking for clarification on what to do next — **READ** the `INDEX.md` `STATE` section first.

2. **Open the response** with a one-line state-check of the form:

   `[state: track=<X> | phase=<Y> | next=<Z> | prereqs=<met | missing-W>]`

3. **After completing a meaningful step** that changes project state (task completion, phase advance, new gap surfaced, decision made), **UPDATE** the `STATE` section of `INDEX.md` to reflect the new state.

4. **If the user says `"state?"`**, immediately produce the current state-check line. This is the fast-failure-detection mechanism for cases where step 1 or step 2 was skipped.

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
