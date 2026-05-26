> **You don't have memory. These files do.** Everything you learn this session is lost when it ends.
> Write to `STATE.md` (live), `HANDOFF.md` (throughout and by end-of session), and `PITFALLS.md` (lessons). See Persistence below.
> History lives in `git log`.
> The question isn't "did I complete the task?" — it's "would the next agent thank me for how I left when they came for their shift?"

---

# Persistence

The three-file memory model compensates for the no-memory gap. Each file has one job.

| File          | Lifetime         | Purpose                                          | Updated                            | If missing, create with header                                                |
| ------------- | ---------------- | ------------------------------------------------ | ---------------------------------- | ----------------------------------------------------------------------------- |
| `STATE.md`    | within-session   | live truth: current step, what's done, blockers  | continuously                       | `# Session State` + one bullet on where you are now.                          |
| `HANDOFF.md`  | between-sessions | what the next agent needs to start fast          | periodically and by end of session | `# Handoff to Next Agent` + "Nothing in flight" if the session ended cleanly. |
| `PITFALLS.md` | cross-session    | lessons learned, append-only                     | when surprised                     | `# Lessons Learned (append-only)`                                             |

All three live at repo root. They are operator-facing — not vault content, not under `docs/`. Subagents read `HANDOFF.md` + `PITFALLS.md` on spawn.

Don't pre-populate templates or section scaffolding. A nearly-empty file with the right header is more honest than a structured file with no real content.

Before any other action in a new session:

1. Read `HANDOFF.md`.
2. Read `PITFALLS.md`.
3. Read `STATE.md` if it exists.
4. Produce a state-check confirming where you're picking up. If any file is missing, bootstrap it per above and note "fresh start."
## PITFALLS write criteria

Append when a future agent would be misled or burn time without the lesson. That's the test.

Entry format — three lines under a `##` symptom heading:

- **Cause:** what was actually wrong.
- **Fix:** what worked, or what to avoid.
- **Detect:** how to recognize this next time before it bites.

Don't log routine bugs or one-off typos. PITFALLS is the future agent's smoke detector, not their bug tracker.

## PITFALLS pruning

Append-only doesn't mean append-forever. Prune when:

- An entry references a superseded library/API/tool version whose new release doesn't have the same failure mode.
- The same pitfall hasn't been hit in three+ sessions touching the relevant area.

Move pruned entries to `PITFALLS-ARCHIVED.md` — preserves the lesson, removes it from active scan.

---

# Per-response behavior

## Chat-reply style

Chat responses are read aloud by TTS. Write conversationally for chat output — short sentences, plain words, the kind of phrasing that survives a listening audience. This applies to chat messages only, not to file content. Files (planning docs, code, markdown notes) follow their own placement and structure rules.

ASCII art and special characters are fine; the TTS handles them without breaking. Use them when they actually communicate something a sentence wouldn't — diagrams, tables, code. Don't sprinkle them for decoration.

## Placement of summaries and key info

Where the summary goes depends on how the reader scans.

- **In chat replies:** summary or state-check at the *bottom*. Chat UIs are reverse-chronological — the bottom of the latest message is the first thing in view. The reader then skims upward through the message body if they want detail.
- **In files:** summary or key info at the *top*, near or in the TOC. Readers open a file, scan the TOC, read the top, then jump around — they reach the bottom last, if at all.

Same content, opposite placement, driven by reader behavior. The per-response state-check (below) and plan-document summary (top of file) are both instances of this rule.

## State-check protocol

1. **Before responding** to any project-progression message, produce a one-line state-check at the *bottom* of the response (per Placement above): where we are, what just happened, what's next. This is the visible artifact that proves the protocol ran.
2. **After completing a meaningful step** that changes project state (task completion, phase advance, new gap surfaced, decision made), **update** `STATE.md`.
3. **When asked where we are**, immediately produce the current state-check line. Fast-failure detection for cases where step 1 or step 2 was skipped.

**Counts as project-progression:**

- Executing or completing a task
- Proposing the next concrete step
- Reporting validation or research findings
- Making a design or commit decision
- Asking a clarifying question that branches the project

**Not project-progression** (state-check optional):

- Pure conversational reply (e.g., explaining a concept)
- Answering a meta question about Claude Code itself
- Responding to "how does X work" with no project action

Installed because methodology skips recurred and only the user caught them — this is fast-failure detection, not failure prevention. Real prevention would require hooks; until then the state-check converts invisible skips into visible *missing lines* the user can call out.

## TaskCreate

Call TaskCreate before starting work whenever any of these are true:

- The task requires 3+ tool calls
- The task has distinct sequential steps
- The user has provided multiple things to do (numbered, comma-separated, or implied)
- You are about to spend significant time / tokens on a multi-stage workflow

Mark tasks `in_progress` before starting each one. Mark `completed` immediately on finish — don't batch updates.

## AskUserQuestion

Use AskUserQuestion (don't guess) when any are true:

- The user's intent has multiple reasonable interpretations.
- You are about to make a hard-to-reverse decision (delete, force-push, large refactor).
- Two or more design paths exist and there's no strong reason to prefer one.
- You are about to spend significant effort on a path the user might not want.
- **Push-back:** the request would lose data the user might not realize is there (uncommitted changes, files outside scope, untracked work).
- **Push-back:** the request contradicts a rule the user themselves established (in CLAUDE.md, PITFALLS, or earlier this session).
- **Push-back:** a simpler or safer path exists with the same outcome.
- **Push-back:** the request rests on a factual misunderstanding (file doesn't exist, command doesn't do what they think, API changed).

Default to asking. A 30-second clarifying question saves minutes of misaligned output.

**Counter-rule — don't pile up clarifiers.** One clarifier per decision per turn. If you find yourself drafting a second AskUserQuestion in the same reply, pick a default and proceed, surfacing the choice in your text ("I went with X because Y; say so if you'd prefer Z"). Three+ questions in a single turn is a sign of paralysis, not diligence — make the call. The two-step confirmation pattern below is the one exception, and only when moving from design to execution.

Two-step confirmations: when moving from discussion to action, ask twice. First question establishes the design. Second question authorizes execution. The user may reject the premise of either — leave room to redirect.

### Push-back style

When asking because something seems wrong (any "Push-back" trigger above), shape the AskUserQuestion as:

- Question: "I think this may *consequence* because *reason*. How should I proceed?"
- Options: original-as-requested, your proposed alternative, stop-and-rethink.

Don't lecture, don't moralize. If the user reaffirms after hearing the concern, proceed — they may know something you don't. Push back once, not repeatedly. Push-back is not refusal; refusal is reserved for genuinely harmful actions.

---

# Writing artifacts

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

## Obsidian vaults

Every project is also an Obsidian vault. When writing .md files in the vault, keep the reader put. they shouldn't chase references to understand the current note. kebab-case filenames for new .md files.

### Folder lifecycle (cold → hot → cold)

- `docs/` — settled facts: project intent, decisions, anything stable enough to skim.
- `docs/.research/` — active research artifacts. Promote to `docs/` when settled.
- `docs/.discussion/` — pending arguments and open questions shaping the vault's direction.
- `.archive/` — once-useful, no longer load-bearing. Move here instead of deleting.

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

---

# Subagent workflow

Delegate when a subagent gives you something you can't easily get yourself: parallel work, isolated context, specialized tools, or fresh eyes.

Don't delegate when the round-trip costs more than just doing it. A two-file edit is not a delegation candidate.

Every delegation includes HOW, WHAT, and WHY. The subagent has no session context — brief it like a new hire.

---

# Git etiquette

`git log` is the historical truth. Treat it as documentation for the next agent.

## Commit cadence

- One logical unit of work per commit — a feature, a fix, a refactor. Not every file save, not "end of day."
- If a unit grows beyond one commit's worth of explanation, it's two units — split it.

## Commit messages

- Imperative mood: "add X", "fix Y" — never "added" or "fixes."
- Summary line under 72 characters.
- Body (optional) explains *why*, not *what*. The diff already shows what.

## WIP and incomplete work

- If leaving work unfinished, commit as `wip: one-line` and reference it in `HANDOFF.md`.
- Don't leave uncommitted changes for the next session — they're invisible until the next agent runs `git status`.

## Don't

- Don't squash without asking — squashing loses history the next agent may need.
- Don't amend pushed commits.
- Don't commit with a placeholder message ("update", "fix stuff", bare "wip"). The next agent has to read these.
