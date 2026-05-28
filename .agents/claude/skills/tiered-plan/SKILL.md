---
name: tiered-plan
description: Produce a four-tier implementation plan (Tier 1 objective / Tier 2 approach / Tier 3 per-change overview / Tier 4 implementer guide) for a multi-step change. Bullets only, no tables. Tier 1 and Tier 2 answer "should we do this?" and "is the approach sound?" for a manager/decider reviewer; Tier 3 and Tier 4 answer "what changes?" and "how exactly?" for the implementer (who is also a reviewer of the WHY). Use this skill whenever the user asks for a plan, implementation plan, refactor plan, execution plan, layered plan, tiered plan, or describes wanting to plan a multi-step change — even if they don't explicitly say "tiered". Especially trigger when the change spans code + docs + tests, when there are multiple sub-changes to coordinate, when the user wants a doc both reviewers and implementers can use, or when the user is asking to think through whether a change is worth doing and how to scope it. Default to solo-developer assumptions (one PR, one commit) unless the user explicitly says they have reviewers.
---

# Tiered plan

A planning format that uses **progressive disclosure ordered by question**, not by audience. Each tier answers a different question:

1. **Tier 1 — Should we do this?** (objective + worthwhileness)
2. **Tier 2 — Is the approach sound?** (high-level how + scope)
3. **Tier 3 — What specifically changes?** (per-change overview with rationale)
4. **Tier 4 — How exactly do I do it?** (implementer guide with embedded why)

A reviewer reads from the top and stops when their question is answered. A manager-level reviewer may stop after Tier 1 ("yes, this is worth doing, ship it"). A design-level reviewer reads through Tier 3 ("the approach is sound, the changes look right"). An implementer reads everything — they need Tiers 1-3 for grounding and Tier 4 to execute.

**Bar for success**: a junior engineer reading the plan should be able to explain back both the high-level goal AND the expected implementation. If they can only parrot the steps without understanding why, the plan failed.

## When this format earns its place

- Multi-step changes that span code + docs + tests.
- Refactors with multiple sub-changes that need coordination.
- Changes that fold in pending bug fixes or review findings.
- Changes where the worthwhileness is non-obvious and a reviewer needs to be convinced before they care about the mechanics.
- Anything where the same doc needs to satisfy both a reviewer (read once, move on) and an implementer (file:line precision).

Skip this format for one-line bug fixes or trivially atomic changes. The four-tier overhead is wasted on a change that can be summarized in one sentence.

## Structure

### Tier 1 — Objective & worthwhileness (60-second manager read)

Four to six bullets. Answers the question: **should we do this?** A reviewer who stops here decides whether the goal is worth pursuing.

Cover:

- **Problem** — what's broken / missing / costly today, in plain English. Not "what ships," not "what changes" — what's the user-facing or system-level pain.
- **Why now** — the cost of NOT doing it (drift, debt, blocked work, recurring confusion). If the answer is "no urgent reason, just nicer," say so honestly.
- **Success criteria** — how we'll know the change worked when it's done. Specific. Observable.
- **Risk surface** — the one or two failure modes that could make this regret-worthy. One line each.
- *(Optional)* **Alternatives considered + dismissed** — if there's an obvious other approach, name it in one line and say why not.

Do NOT write "what ships" or "what moves" in Tier 1. Those are summaries of the HOW; they belong in Tier 2 or 3. Tier 1 is purely about the goal.

### Tier 2 — Approach & shape (60-second decider read)

Four to seven bullets. Answers the question: **is the approach sound?** A reviewer who stops here decides whether the proposed path is reasonable.

Cover:

- **Approach in one sentence** — "we'll do this by [strategy]." Plain English.
- **Why this approach** — the load-bearing reason. One bullet.
- **Why not the obvious alternative** — name the alternative, one line on why not. Skip if no obvious alternative.
- **Scope IN** — explicit bullet list of what's covered.
- **Scope OUT** — explicit bullet list of what's NOT, each item pointing at where it's tracked (ROADMAP, follow-up issue, "deferred"). Vague scope is the most common plan failure mode.
- **Delivery shape** — one PR? one commit? Which branch? Solo dev or team? (Default: one PR, one commit, solo.)
- **Done when** — a one-line verification recipe (the commands that prove success).

### Tier 3 — Per-change overview (5-minute reviewer dig-in)

One section per major change. Bullets throughout. No tables. No prose paragraphs.

For each change, cover:

- The shape of the change in 3-5 bullets.
- The **embedded rationale** — why this change is necessary to hit the objective from Tier 1.
- Honest acknowledgment of asymmetries — if part of the change doesn't fit the uniform pattern of other changes, say so explicitly.

Add cross-cutting subsections if needed:

- **Math / counts** — plugin counts, file counts, line counts. Anything that anchors scale.
- **Honest debt** — items you're folding the change AROUND rather than fixing. Acknowledge growth.

If a reader stops at Tier 3, they understand the design + scope at a level where they could write the implementation themselves (slower than reading Tier 4, but possible).

### Tier 4 — Implementer guide (executor's reference, but WHY embedded)

Step-by-step. Each step is a numbered section with two specific demands:

1. **A one-sentence rationale at the top of each step**, in this shape: *"This step lands here because [reason]."* The rationale grounds the implementer (who is also a reviewer) so they understand why this step exists in this position. Without it, a junior reading the plan can't recover when something doesn't match exactly — they don't know which constraints are load-bearing.

2. **Inline `because …` clauses on load-bearing bullets** — when a bulleted action depends on a non-obvious constraint (e.g. "do the rename FIRST because it's visible in git log; later commits would bury it"), include a brief `because …` clause. Skip the inline clause on bullets where the action is self-explanatory; don't bloat with rationale on every line.

Each step also has:

- Bulleted action items with **specific file paths**.
- Exact edits when they're non-obvious (regex patterns, function signatures, specific commits to cite).
- A **Checkpoint** line at the end describing the verification command(s) that prove the step worked.

For patterns that repeat across many files, describe the pattern once and list a few representative paths. Do not enumerate every file:line — the implementer can grep.

Also include in Tier 4:

- **Critical files** — concise list of the load-bearing paths the implementer will touch. Pattern-based, not exhaustive.
- **Reusable utilities** — existing functions / helpers / scripts the implementer should call rather than reinvent. Cite by path.
- **Hygiene constraints** — if `git mv` is required, say so. If commit messages must avoid AI co-author attribution (or any other constraint), call it out.

## Style rules

- **Bullets only.** No tables. No prose paragraphs longer than three sentences.
- **Declarative.** "A happens, then B happens." Not "We might want to consider A, then perhaps B."
- **Read once, move on.** Each section is self-contained. A reader should not have to scroll back to interpret a section.
- **Honest about asymmetries.** If part of the change doesn't fit the uniform pattern, say so in plain words.
- **No multi-PR splits for solo devs.** Default to one PR. Multi-PR ceremony is for teams with parallel reviewers; if the user is solo, skip it.
- **Lead with the problem, not the change.** Tier 1 starts with the user-facing or system-level pain, not with "what ships." The order of reading matters — reviewers need the WHY before the WHAT.
- **WHY embedded throughout the implementer tier.** A junior reader of Tier 4 should be able to explain why each step lands where it does. Step openers + inline `because …` clauses are the mechanism.
- **No Meta section.** Generated plans do not include a "prompt template for future tiered plans" footer. The skill itself encodes the format; reproducing it in every plan is noise. (The format propagates via the skill, not via copy-paste.)

## Sample skeleton

When generating a plan, follow this exact skeleton:

```markdown
# Plan — [meaningful title that names the goal, not just the changes]

> Read top-down. Tier 1 is the manager's "should we do this?" — Tier 2 is the decider's "is the approach sound?" — Tier 3 is the reviewer's per-change dig-in — Tier 4 is the implementer's grounded step-by-step.

---

## Tier 1 — Objective & worthwhileness

- **Problem**: …
- **Why now**: …
- **Success criteria**: …
- **Risk surface**: …
- *(Optional)* **Alternatives considered**: …

---

## Tier 2 — Approach & shape

- **Approach**: …
- **Why this approach**: …
- **Why not [alternative]**: …
- **Scope IN**: …
- **Scope OUT**: … (each item points at where it's tracked)
- **Delivery**: one commit on PR #N (currently M commits → M+1). Push to <branch>. Solo dev.
- **Done when**: <one-line verification recipe>.

---

## Tier 3 — Per-change overview

### Change 1: [title]

- [bullets describing the shape of change 1]
- **Why this matters for the objective**: …

### Change 2: [title]

- [bullets describing the shape of change 2]
- **Why this matters for the objective**: …

### [Counts / math anchoring scale, if relevant]

- [plugin count, file count, etc.]

### [Honest debt, if any]

- [what's deferred or worked around, and where it's tracked]

---

## Tier 4 — Implementer guide

### Step 1: [title]

This step lands here because [one-sentence rationale tying it to the objective or to a sequencing constraint].

- [bulleted action items with file paths]
- [bulleted action that has a non-obvious dependency], because [brief inline why].

Checkpoint: [verification command].

### Step 2: [title]

This step lands here because […].

- […]

Checkpoint: […]

### Critical files (patterns repeat; representative paths only)

- [grouped by purpose]

### Reusable utilities (referenced, not reinvented)

- [path → what it does]

### Hygiene constraints

- [git mv requirements, commit message constraints, no AI co-author attribution, etc.]
```

## Anti-patterns (don't do these)

- **Starting the plan with "What ships."** That's a summary of the HOW. Tier 1 must start with the problem and the why. The reader needs to be convinced the goal is worthwhile before they care about what's changing.
- **Implementer steps without rationale.** A step that says "rename X to Y" without explaining why it's in this position is fragile — the implementer can't recover when reality doesn't match. The one-sentence step opener is non-negotiable.
- **Tables everywhere.** Tables look organized but force the reader to scan two dimensions. Bullets are one-dimensional and faster. Skip tables unless the data is genuinely tabular (e.g., a config matrix).
- **Prose paragraphs.** A 5-line paragraph hides 5 facts. Five bullets surface 5 facts. The reader gets the same content in less cognitive load.
- **Multi-PR splits as the default.** They add ceremony without value when the team is one person. Recommend only when there's a concrete review-surface reason.
- **Enumerating every file:line in the implementer guide.** That belongs in the diff, not the plan. Patterns + representative paths is the right grain.
- **"We might consider…" hedging language.** Plans are commitments. Hedge in Tier 1's risk surface or Tier 2's alternatives if you must; the rest of the document is declarative.
- **Hiding deferred work.** Every OUT item in Tier 2 must point at where it's tracked (ROADMAP, follow-up issue). "Deferred" without a pointer is a black hole.
- **Including a Meta section / prompt template footer.** The skill encodes the format. Generated plans should not paste in a copy-the-prompt template. (If you genuinely need to teach the format to someone outside the skill ecosystem, point them at this SKILL.md.)

## Workflow

When this skill triggers:

1. **Confirm scope first if unclear.** Ask 1-4 clarifying questions via `AskUserQuestion` if any of these are uncertain: the IN/OUT boundary, the delivery target (which PR / branch), the solo-vs-team assumption, whether to fold pending bugs in, what success looks like. Skip questions you can answer from context.
2. **Run focused exploration if needed.** If the codebase is unfamiliar, launch one Explore agent (not three) to map the change's blast radius. Skip if context is clear.
3. **Draft Tier 1 FIRST and re-check.** The plan must start from the problem. If you find yourself wanting to write "what ships" in Tier 1, stop — you're conflating goal with change. Restart the bullet.
4. **Draft Tier 4 LAST.** The implementer guide depends on Tiers 1-3 being settled; writing it first leads to rationales that don't match the final scope.
5. **Re-check rationale embedding before finalizing Tier 4.** Every numbered step needs the one-sentence opener. Every load-bearing bullet needs an inline `because …` clause (judgment call on which bullets qualify).
6. **Save the plan** to wherever the user's harness expects plans (`~/.claude/plans/<name>.md` for plan-mode workflows, or wherever they direct).
7. **End the planning turn with ExitPlanMode** if in plan mode, or with a short summary if not.

## Why this format works

- **Reviewer ergonomics by question, not by audience.** A reviewer's first question is "should we do this?" — Tier 1 answers it. The second is "is the approach sound?" — Tier 2 answers it. The reader stops when their question is answered, without scrolling through detail they don't need.
- **Implementer grounding.** The WHY embedded in Tier 4 means a junior reading the plan can explain it back — both the goal and the mechanics. They can recover when something doesn't match exactly because they understand which constraints are load-bearing.
- **Self-correcting.** If Tier 1 doesn't capture the problem clearly, the gap is obvious. If Tier 4 has steps that don't trace back to Tier 1's objective, that's a review surface. Each tier checks the others.
- **Solo-dev defaults.** No multi-PR ceremony, no review-surface budgeting, no team-coordination overhead. The format scales up if you have reviewers; it doesn't waste tokens on ceremony when you don't.
