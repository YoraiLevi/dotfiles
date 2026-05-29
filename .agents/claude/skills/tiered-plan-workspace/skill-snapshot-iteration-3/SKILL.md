---
name: tiered-plan
description: Produce a depth-tiered implementation plan that a reviewer can scan top-down and an implementer can execute step-by-step. Plans read in this order — what's the goal? is the approach sound? what specifically changes? how exactly? — with section names that fit the actual change, not a fixed template. Use sub-lists for multi-part thoughts (never cram multiple ideas into one bullet). Embed WHY in every implementer step so a junior reader can explain the plan back. Use this skill whenever the user asks for a plan, implementation plan, refactor plan, execution plan, layered plan, tiered plan, or describes wanting to plan a multi-step change — even if they don't explicitly say "tiered". Especially trigger when the change spans code + docs + tests, when there are multiple sub-changes to coordinate, when the user wants a doc both reviewers and implementers can use, or when the user is asking to think through whether a change is worth doing and how to scope it. Default to solo-developer assumptions (one PR, one commit) unless the user explicitly says they have reviewers.
---

# Tiered plan

A planning style that ladders top-down by **question**, not by template. The plan answers reviewer questions in order — should we do this? is the approach sound? what changes? how exactly? — and stops adding depth when the change doesn't need it. Section names fit the specific change; they're not boilerplate Tier 1 / Tier 2 labels.

## Principles (these are load-bearing — every plan follows them)

### 1. Lead with the goal, not the changes

The first content of the plan must answer "what are we trying to do and why?" — not "what's about to ship." A reader who only reads the first section should know what problem this solves and whether it's worth solving.

Section name fits the change. For a refactor, "Objective" or "Problem". For a feature, "Goal" or "What we're building". For a migration, "Why move + what success looks like". Don't paste a fixed label; pick what reads naturally.

### 2. Top-down by question

Reading order is non-negotiable:

- First: **what's the goal and is it worthwhile?** (problem / why now / success criteria / risk if any of those matter)
- Then: **how are we going to do it at a high level + what's NOT in scope?** (approach + scope IN / OUT)
- Then: **what specifically changes?** (per-change overview with rationale)
- Last: **how exactly does the implementer execute?** (step-by-step with embedded why)

Each level is shorter than the one below. A reviewer stops when their question is answered.

### 3. Section names fit the change, not a template

A simple change (add a CLI flag, rename a function) does not need a 4-tier scaffold. A complex change (multi-file refactor with backwards-compat + tests + docs) does. Match depth to complexity.

**Bad**: forcing "Tier 1 — Objective" + "Tier 2 — Approach" + "Tier 3 — Per-change overview" + "Tier 4 — Implementer guide" on a one-flag-addition. The result feels mechanical and padded.

**Good**: for the same one-flag-addition, write `## Goal`, `## Approach`, `## Implementation`, done. The depth matches the work.

For complex changes, the question-ladder is the same but each level has more depth and `###` sub-headings under it.

### 4. Sub-lists for multi-part thoughts

This is the most common style failure. When a concern has multiple parts, do NOT cram them into a single inline-bold bullet with prose inside it. Break them out.

**Bad**:
```
- **Success criteria**: the new import path works, the old import path warns once per process, all tests pass, no callers still use the old name.
```

**Good** (sub-list under inline-bold):
```
- **Success criteria**:
  - new import path works
  - old import path warns once per process
  - all tests pass
  - no callers still use the old name
```

**Also good** (when there are enough items, promote to a sub-heading):
```
### Success criteria

- new import path works
- old import path warns once per process
- all tests pass
- no callers still use the old name
```

Apply the same rule to Problem, Why now, Risk surface, Scope IN/OUT, per-change descriptions, etc. Whenever a thought has 3+ parts, sub-list it.

### 5. Scope IN / OUT discipline (always)

Every plan has an explicit list of what's IN scope and what's OUT. OUT items point at where they're tracked (ROADMAP, follow-up issue, "deferred to next PR"). "Out of scope" without a pointer is a black hole.

### 6. Every implementer step explains WHY

The lowest tier (implementation steps) must embed rationale. Two mechanisms:

- **Step-level**: each numbered step opens with a one-sentence "because…" tying it to the goal or to a sequencing constraint. Example: `### Step 1: git mv the file — this lands first because moving before editing keeps git's rename detection working.`
- **Inline**: load-bearing bullets within a step get an inline `because…` clause when the choice is non-obvious. Example: `- Use stacklevel=2 in the DeprecationWarning, because we want the warning to point at the caller's import line, not at the shim itself.`

Skip the inline clause on bullets where the action is self-explanatory. The bar: a junior reader of the implementation steps should be able to explain backwards from any step to the goal.

### 7. Verification per checkpoint

Each implementer step ends with how to prove it worked — concrete commands, expected output, or observable state. Don't write "test it works" without saying what command to run.

### 8. Bullets > tables > prose

- Bullets for almost everything.
- Tables ONLY when the data is genuinely tabular (e.g., a config matrix with two independent axes).
- Prose paragraphs only for the one-line section preambles. No paragraphs longer than two sentences.

### 9. Solo dev default

One PR, one commit, one branch. Do not propose multi-PR splits unless the user explicitly says they have reviewers and the change is large enough to justify the ceremony. For solo work, multi-PR splits add overhead without value.

### 10. No Meta / prompt-template footer

The skill encodes the format. Generated plans do NOT include a "prompt template for future tiered plans" footer. If someone outside the skill ecosystem needs the format, point them at this SKILL.md.

## When to make the plan deeper vs lighter

- **Lightweight** (~50-100 lines): single-file change, one-component addition, simple migration. The Goal / Approach / Implementation skeleton is enough. Maybe 3 implementation steps, each with one-sentence rationale.
- **Standard** (~150-300 lines): multi-file change, code + tests + docs, one round of backwards-compat. Add a per-change overview as a middle layer; 5-8 implementation steps; explicit IN/OUT lists.
- **Heavy** (300+ lines): multi-component refactor, multi-PR-worth-of-work-in-one-PR, folds in pending bug fixes. Add sub-headings under each top section; embed counts/math anchoring scale; honest debt notes.

Don't pad a simple change to make it look thorough. Don't crunch a complex change to make it look concise. Match the depth to the work.

## Sample skeletons by depth

### Lightweight skeleton (simple change)

```markdown
# Plan — [meaningful title naming the goal]

## Goal

[2-4 bullets covering what we're doing and why it matters. Use sub-lists if any concern has multiple parts.]

## Approach

- **What we're going to do**: …
- **Why this approach**: …
- **Scope IN**:
  - …
- **Scope OUT**:
  - … (each points at where it's tracked)
- **Delivery**: one PR, one commit. Solo.

## Implementation

### Step 1: [title]

This step lands here because …

- [action with file path]
- [action], because [inline why if non-obvious].

Checkpoint: [verification command].

### Step 2: [title]

…
```

### Standard skeleton (multi-file change)

```markdown
# Plan — [meaningful title]

## Goal & worthwhileness

### Problem
- …

### Why now
- …

### Success criteria
- …
- …

### Risk surface
- …

## Approach

- **Strategy**: …
- **Why this approach**: …
- **Why not [alternative]**: …
- **Scope IN**:
  - …
- **Scope OUT**:
  - … (each points at where it's tracked)
- **Delivery**: one PR, one commit on branch X. Solo.
- **Done when**: [one-line verification recipe].

## Per-change overview

### Change 1: [title]
- [shape bullets]
- **Why this matters for the goal**: …

### Change 2: [title]
- …

## Implementation

### Step 1: [title]
This step lands here because …
- [action]
- [action], because [inline why].
Checkpoint: …

### Step 2: [title]
…

### Critical files

- [grouped by purpose]

### Reusable utilities

- [path → what it does]

### Hygiene constraints

- [git mv, no AI co-author attribution, etc.]
```

### Heavy skeleton (multi-component refactor)

Same as standard, but:

- Each `## Goal & worthwhileness` sub-concern gets its own bulleted list under a `###` subheading.
- `## Per-change overview` has more `### Change N` sections + `### Math / counts` + `### Honest debt`.
- `## Implementation` has 10+ steps, sometimes grouped under `### Phase 1: …` / `### Phase 2: …` if the work has natural phases.

## Anti-patterns (don't do these)

### Starting the plan with "What ships"

That's a summary of the HOW. The plan must start with the problem and the why. The reader needs to be convinced the goal is worthwhile before they care about what's changing.

### Inline-bold bullets with prose-y content

```
- **Success criteria**: the new path works, old warns, tests pass.
```

Bad. Three concerns crammed into one line. Break them out into a sub-list. See Principle 4.

### Implementer steps without rationale

A step that says "rename X to Y" without explaining why it's in this position is fragile. The implementer can't recover when reality doesn't match. The one-sentence step opener is non-negotiable.

### Forced 4-tier scaffold on simple changes

If the change is "add a --dry-run flag," do not write Tier 1 Objective / Tier 2 Approach / Tier 3 Per-change overview / Tier 4 Implementer guide. Just write Goal / Approach / Implementation. The lightweight skeleton fits.

### Multi-PR splits as the default

Single PR, single commit, solo. Only suggest splits if the user has actual reviewers and the change is large enough.

### Tables for data that isn't tabular

A list of files to change is a bullet list, not a table. A "Change | Reason | File" table is bullets with sub-bullets. Reserve tables for two-axis data.

### Prose paragraphs longer than two sentences

If you have a 5-line paragraph, you have 5 facts hiding inside it. Split into bullets.

### Enumerating every file:line

The diff has those. The plan describes patterns and lists representative paths. The implementer can grep.

### Hiding deferred work

Every OUT-scope item must point at where it's tracked (ROADMAP item, follow-up issue, "explicitly deferred to next PR"). "Out of scope" with no pointer is a black hole.

### Meta / prompt-template footer

The skill encodes the format. Generated plans don't paste it back in.

## Workflow

When this skill triggers:

1. **Confirm scope if unclear.** Ask 1-4 clarifying questions via `AskUserQuestion` if the IN/OUT boundary, the delivery target (which PR / branch), the solo-vs-team assumption, or what success looks like is uncertain.
2. **Run focused exploration if needed.** If the codebase is unfamiliar, launch one Explore agent to map the change's blast radius. Skip if context is clear.
3. **Pick the depth.** Decide lightweight / standard / heavy based on the work, not the user's request length. A short user request can describe a heavy change; respond at the right depth.
4. **Draft the goal first.** Write the first section (Goal / Objective / Why) before any other content. If you find yourself wanting to write "what ships" in the first section, stop — you're conflating goal with change. Restart.
5. **Sub-list multi-part thoughts.** Before finalizing, scan every bullet that has comma-separated concerns inside it. Promote each to a sub-list. This is the most common style failure; catch it before delivering.
6. **Embed WHY in every implementer step.** Step openers + inline `because…` on load-bearing bullets. The bar: a junior reader can explain backwards from a step to the goal.
7. **Save the plan** where the user's harness expects (`~/.claude/plans/<name>.md` for plan-mode, or wherever they direct).
8. **End with ExitPlanMode** if in plan mode, or with a short summary if not.

## Why this style works

- **Question-ordered reading.** A reviewer's first question is "should we do this?" — the first section answers it. A reviewer who hasn't decided yet doesn't wade through implementation detail to get to the decision-support content.
- **Depth fits the change.** A simple change gets a simple plan. A complex change gets a thorough one. The plan doesn't pad or crunch.
- **Sub-lists make breakdown visible.** When success criteria has 4 items, they're 4 bullets that a reader can scan in 5 seconds. When it's a comma-separated sentence, the reader has to parse it twice.
- **Implementer grounding.** The WHY embedded in every step means a junior can read the plan and explain it back — both the goal and the mechanics. They can recover when reality doesn't match exactly because they understand which constraints are load-bearing.
- **Self-correcting on every iteration.** If the Goal section doesn't capture the problem, the gap is obvious. If implementer steps don't trace back to the goal, that's a review surface. Each section checks the others.
