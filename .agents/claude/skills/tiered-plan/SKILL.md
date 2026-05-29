---
name: tiered-plan
description: Produce a depth-tiered implementation plan optimized for the REVIEWER who has to decide whether to approve the change. Reviewer-facing sections (Objective, Approach, Per-change overview) are concise, dense, and decision-supporting — no filler. Implementer-facing section (steps + verification) is grounded in the same goal. Plans read in this order — what's the goal? is the approach sound? what specifically changes? how exactly? — with section names that fit the actual change, not a fixed template. Use sub-lists for multi-part thoughts. Inline code blocks when the deliverable IS a small file or snippet. Use this skill whenever the user asks for a plan, implementation plan, refactor plan, execution plan, layered plan, tiered plan, or describes wanting to plan a multi-step change — even if they don't explicitly say "tiered". Especially trigger when the change spans code + docs + tests, when there are multiple sub-changes to coordinate, when the user wants a doc both reviewers and implementers can use, or when the user is asking to think through whether a change is worth doing and how to scope it. Default to solo-developer assumptions (one PR, one commit) unless the user explicitly says they have reviewers.
---

# Tiered plan

A planning style optimized for the **reviewer** — the person deciding whether to approve the change and whether the approach is sound. The implementer is a secondary reader who uses the same document to execute. Both audiences are served by the same plan, but the reviewer's needs set the bar.

## The reviewer's read

A reviewer reads top-down and stops when their question is answered. They ask:

1. **What's the goal?** — should we do this at all?
2. **Is the approach sound?** — including the load-bearing technical decisions?
3. **What specifically changes?** — file-level scope of the work?
4. *(Sometimes)* **How exactly does the implementer execute?** — only if the reviewer wants to spot-check feasibility.

The reviewer-facing sections (1, 2, 3) must be CONCISE, DENSE, and DECISION-SUPPORTING. No filler. No "why this matters for the goal" tags. No padded subsections that exist for completeness.

## Principles (these are load-bearing — every plan follows them)

### 1. Lead with the goal — and put ALL reviewer-must-know info at the top

The Objective is the reviewer's must-know section. It contains, in this order:

1. **Goal / problem** — what we're doing and why. Brief (1-3 bullets, or a paragraph + bullets).
2. **Definition of Done** — ALWAYS present, every plan. A list of observable success criteria the reviewer can use to recognize the change is complete. This is the contract: when these are true, the work is done.
3. **Open questions for you** — when they exist. Things the planner can't decide alone (version targets, project conventions, CI policies, packaging choices). Surface these in the Objective, not at the end of the plan — they may change the reviewer's decision.

Why these three at the top: a reviewer evaluates worthwhileness, success-recognition, and outstanding uncertainty BEFORE they care about the Approach. If the goal isn't sound, or the open questions are unanswered, or the Definition of Done is ambiguous, the reviewer needs to know NOW — before reading on.

Section name fits the change: "Objective" for a refactor, "Goal" for a feature, "Why this change" for a migration.

**Anti-patterns**:

- Forcing Problem / Why now / Success criteria / Risk surface as four mandatory `###` subsections on every plan. Use them when the change has multiple concerns; skip when it doesn't.
- Burying Definition of Done in the Approach section under "Done when:" — promote it to Objective.
- Putting Open Questions as a footer at the end of the plan — the reviewer reads top-down and may already have decided by then. Surface them in Objective.
- Using "Non-goals" as a subsection title — it's awkward. Move that concept to Scope OUT in the Approach (where it belongs).

### 2. Approach has TECHNICAL DEPTH

The Approach section is where the reviewer evaluates whether the proposed path is sound. This is the section where you spend the most words on substance — not on labels, but on the actual technical decisions that make or break the change.

Include:

- The strategy in one sentence — "we'll do this by [shape]."
- **Why this strategy** — the load-bearing reason. One bullet.
- **Specific mechanics** when they matter — deprecation tactics, migration order, library choices, compatibility shims, PEP references, key code constructs. This is where readers like to see `stacklevel=2`, `__getattr__`, `git mv`, etc. mentioned with one-line rationale.
- **Scope IN** — explicit list of what's covered.
- **Scope OUT** — explicit list of what's NOT covered. **Format**: each item carries a brief reason + a tracking pointer.
  - **Bad**: `- structured JSON output`
  - **Good**: `- structured JSON output — out because no consumer asked; defer until one does → follow-up issue #N`
  - Scope OUT absorbs the "non-goals" concept: anything we're intentionally excluding goes here with its reason and tracker.
- **Delivery shape** — one PR, one commit, which branch. (Default: solo.)

DO NOT include:

- **"Why not [alternative]"** — by the time you're writing the plan, the decision is made. Documenting rejected alternatives is post-hoc justification, not decision support. Skip unless the user explicitly asks.
- Filler-like labels that just describe the section ("This approach is reasonable because…"). Just say what's sound.

### 3. Per-change overview is a LIST OF CHANGES

For multi-component changes, list the specific changes the implementer will make at file-level granularity. Each change is a short subsection — 3-5 bullets — describing what changes and where.

DO NOT add:

- **"Why this matters for the goal"** tags on every subsection. The reader can connect dots; the change is in the plan because it serves the goal. Tagging it is filler.
- "Why this change is necessary" preambles. The Approach section already answered that at the level the reviewer needs.

Use numbered subsections when natural (Change 3.1, 3.2 or just numbered bullets) — it helps linearity. Or use `### <change name>` if numbering feels forced.

For SIMPLE changes (one file, one component, one concept), the per-change overview can be skipped entirely or collapsed into a short bullet list inside the Approach section. Match depth to complexity.

### 4. Implementer section: rationale when ordering is non-obvious, INLINE CODE when the deliverable IS code

The implementer section is the executable reference. Two specific things make it work:

- **Inline code blocks** when the deliverable IS a small file, snippet, or pattern. If Step 3 says "write a deprecation shim at src/utils/log.py," show the shim. If Step 5 says "add this hooks.json event," show the JSON. The implementer can copy-paste. Don't describe code that fits in 20 lines — show it.
- **Step rationale only when ordering is non-obvious.** "Step 1: branch off main" doesn't need "this lands first because…" — branching first is obvious. "Step 3: write the shim" might need "this lands here because the shim depends on the canonical module existing." Use rationale where the reader might wonder; skip it where they don't.

Each step ends with a **Checkpoint** line — concrete verification command or observable state that proves the step worked.

### 5. Scope IN / OUT discipline (always)

Every plan has explicit IN and OUT lists. OUT items point at where they're tracked. "Out of scope" without a pointer is a black hole.

### 6. Sub-lists for multi-part thoughts

When a concern has multiple parts, do NOT cram them into a single inline-bold bullet with prose inside. Break them out.

**Bad**: `- **Success criteria**: the new path works, the old path warns, all tests pass.`

**Good** (sub-list under inline-bold):
```
- **Success criteria**:
  - new path works
  - old path warns once per process
  - all tests pass
```

**Also good** when there are enough items: promote to a `###` heading with a flat bullet list under it.

### 7. Bullets > tables > prose

- Bullets for almost everything.
- Tables ONLY when the data is genuinely tabular (two independent axes).
- No prose paragraphs longer than two sentences.

### 8. Solo dev default

One PR, one commit, one branch. Multi-PR splits only when the user explicitly has reviewers and the change is genuinely too big for one PR.

### 9. No Meta / prompt-template footer

The skill encodes the format. Generated plans don't include a "prompt template for future tiered plans" footer.

### 10. Definition of Done and Open Questions live in the Objective, not at the end

Both are reviewer-must-know. Both go in the Objective section at the top of the plan.

- **Definition of Done** is ALWAYS present. A flat list of observable success criteria. When all are true, the work is complete. Reviewers use it to recognize "done"; implementers use it to know when to stop.
- **Open Questions** are present when genuine uncertainty exists — version targets, project conventions, CI policies, packaging choices. The planner can't decide alone; the reviewer must.
  - Include ONLY when there are genuine open questions. Skip when there's nothing real to ask. Empty section is worse than no section.
  - Don't pad with "is this fine?" filler.

DO NOT put Definition of Done as "Done when:" inside the Approach section. DO NOT put Open Questions as a footer at the end of the plan. Both demote reviewer-must-know info below content the reviewer hasn't decided to read yet.

## When to make the plan deeper vs lighter

- **Lightweight** (~50-100 lines): single-file change, one-component addition, simple migration. Objective + Approach + Implementation skeleton. Maybe 3 implementation steps. Skip per-change overview entirely if the Approach + Implementation cover it.
- **Standard** (~150-300 lines): multi-file change, code + tests + docs, one round of backwards-compat. Include per-change overview as a middle layer; 5-8 implementation steps; explicit IN/OUT.
- **Heavy** (300+ lines): multi-component refactor, multi-PR-worth-of-work-in-one-PR, folds in pending bugs. Add `###` sub-headings under each top section; embed counts/math; honest debt notes.

Don't pad simple changes to look thorough. Don't crunch complex changes to look concise. Match depth to work.

## Sample skeleton (standard depth)

```markdown
# Plan: [meaningful title that names the change in plain English]

## 1. Objective

[1-3 bullets: what we're doing and why it matters. Brief.]

**Definition of Done** (always — observable criteria that say "this is finished"):
- [criterion 1: observable, testable]
- [criterion 2]
- [criterion 3]

**Open questions** (only if genuine — surface here, not at the end):
- [thing the planner can't decide alone, with a brief note on what info would resolve it]
- [another]

## 2. Approach

**Strategy: [one-sentence shape — "keep the implementation in the new location; make the old location a thin shim"].**

Why this shape:
- [load-bearing reason]
- [another]

[Technical mechanics — specific deprecation tactics, library choices, code constructs that matter. This is where the reviewer evaluates soundness. Use sub-lists or bullets; don't write paragraphs.]

**Scope IN**:
- [what's covered]
- [...]

**Scope OUT** (each item: brief reason + tracking pointer; this absorbs the "non-goals" concept):
- [item] — out because [reason] → [where tracked: ROADMAP entry, follow-up issue, "deferred to next PR", etc.]
- [item] — out because [reason] → [tracker]

**Delivery**: one PR, one commit on branch `<name>`. Solo.

## 3. Per-change overview

### 3.1 [Change name — usually file path or component]

- [3-5 bullets describing what changes]
- [no "why this matters for the goal" tag]

### 3.2 [Next change]

- …

## 4. Implementer guide

### Step 1 — [title]

[Rationale only if ordering is non-obvious. Skip if obvious.]

- [action with file path]
- [action with inline code block when the deliverable IS code]

```python
# Example: show the actual shim source, the actual __getattr__ block,
# the actual regex pattern — when 20 lines or fewer
```

Checkpoint: [verification command].

### Step 2 — [title]

…

### [Critical files / Hygiene constraints subsections if heavy]
```

## Anti-patterns (don't do these)

### Starting the plan with "What ships"

That's a summary of the HOW. The first section answers the WHY. The reader needs to be convinced the goal is worthwhile before they care about what's changing.

### Inline-bold bullets with prose-y content

```
- **Success criteria**: the new path works, old warns, tests pass.
```

Bad. Three concerns crammed into one line. Break them out into a sub-list.

### "Why not [alternative]" in the Approach section

The decision is already made by the time you're writing the plan. Skip alternatives unless the user explicitly asks.

### "Why this matters for the goal" tags on per-change subsections

The reader connects the dots. Tagging every change with its goal-relevance is filler that wastes the reviewer's time.

### Mandatory 4-subsection Problem / Why now / Success / Risk in every Objective

Some changes have all four concerns; some have one. Use the structure when it fits the change. Forcing it everywhere makes simple plans look padded.

### Step rationale on every implementer step

Use rationale when the reader might wonder why a step lands in that position. Skip when ordering is obvious. "Step 1: branch off main" needs no defense.

### Describing code instead of showing it

When the deliverable is a 20-line file (a shim, a config snippet, a regex, a hooks.json event), SHOW the code in an inline block. Describing it in prose makes the implementer write it twice.

### Forced 4-tier scaffold on simple changes

If the change is "add a --dry-run flag," don't write Tier 1 Objective / Tier 2 Approach / Tier 3 Per-change overview / Tier 4 Implementer guide. Just write Goal / Approach / Implementation.

### Tables for data that isn't tabular

A list of files to change is a bullet list, not a table.

### Prose paragraphs longer than two sentences

If you have a 5-line paragraph, you have 5 facts hiding inside it. Split into bullets.

### Hiding deferred work

Every OUT-scope item must point at where it's tracked.

### Meta / prompt-template footer

The skill encodes the format. Generated plans don't paste it back in.

## Workflow

When this skill triggers:

1. **Confirm scope if unclear.** Ask 1-4 clarifying questions via `AskUserQuestion` if the IN/OUT boundary, the delivery target, the solo-vs-team assumption, or what success looks like is uncertain.
2. **Run focused exploration if needed.** If the codebase is unfamiliar, launch one Explore agent to map the change's blast radius. Skip if context is clear.
3. **Pick the depth.** Decide lightweight / standard / heavy based on the work, not the user's request length.
4. **Write the Objective first.** Brief. If you find yourself wanting to write "what ships" in the Objective, stop — you're conflating goal with change.
5. **Make the Approach dense.** This is the section where the reviewer decides "is this sound?" — give it substance. Specific mechanics, load-bearing technical decisions, PEP references when relevant, library choices. Don't strip it down to "Strategy + Why + Scope" labels with empty bullets underneath.
6. **Per-change overview: just list the changes.** No "why this matters" tags.
7. **Sub-list multi-part thoughts.** Before delivering, scan every bullet that has comma-separated concerns inside it. Promote to a sub-list.
8. **Inline code blocks for small deliverables.** If a step's output is a 20-line file, show the file.
9. **Step rationale only when ordering is non-obvious.** Don't pad obvious ordering.
10. **Add "Open questions" section ONLY if you have genuine open questions.** Empty section is worse than no section.
11. **Save the plan** to where the user's harness expects (`~/.claude/plans/<name>.md` or where they direct).
12. **End with ExitPlanMode** if in plan mode, or a short summary if not.

## Why this style works for reviewers

- **Reviewer time is the bottleneck.** A reviewer reads many plans; each one that's padded loses them seconds. Concise + dense + decision-supporting wins.
- **Technical depth in the Approach earns trust.** A reviewer who sees `stacklevel=2 because we want the warning to point at the caller's import line, not at the shim itself` knows the planner thought about it. A reviewer who sees `Strategy: keep the implementation in the new location` with no mechanics has to dig deeper to evaluate soundness.
- **Per-change overview is a contract.** It tells the reviewer exactly what file-level work is in scope. Adding "why this matters" tags clutters the contract.
- **Open questions surface honesty.** A planner who marks "What is vX.Y?" as an open question is honest about what they can't decide. A planner who fills in `vX.Y` as a placeholder forces the reviewer to chase whether that's intentional.
- **Implementer grounding stays.** The implementer can still execute from the same plan — inline code blocks + step verification + checkpoints. The plan serves both audiences; the reviewer-facing optimization doesn't harm the implementer.
