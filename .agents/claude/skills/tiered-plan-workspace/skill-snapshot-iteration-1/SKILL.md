---
name: tiered-plan
description: Produce a three-tier implementation plan (Tier 1 summary / Tier 2 overview / Tier 3 implementer guide) for a multi-step change. Bullets only, no tables, scannable in 60 seconds at the top, executable as step-by-step at the bottom. Use this skill whenever the user asks for a plan, implementation plan, refactor plan, execution plan, layered plan, tiered plan, or describes wanting to plan a multi-step change — even if they don't explicitly say "tiered". Especially trigger when the change spans code + docs + tests, when there are multiple sub-changes to coordinate, when the user wants a doc both reviewers and implementers can use, or when they reference "progressive disclosure" or "layered" as a format goal. Default to solo-developer assumptions (one PR, one commit) unless the user explicitly says they have reviewers.
---

# Tiered plan

A planning format that uses **progressive disclosure**: three tiers, reader picks depth. Tier 1 is the 60-second skim. Tier 2 is the high-level reviewer's dig-in. Tier 3 is the implementer's reference.

The same document serves three audiences: someone deciding whether to approve the PR, someone reviewing the design before code lands, and someone (often a future you, often an agent) executing the change file-by-file.

## When this format earns its place

- Multi-step changes that span code + docs + tests.
- Refactors with multiple sub-changes that need coordination.
- Changes that fold in pending bug fixes or review findings.
- Anything where the same doc needs to satisfy both a reviewer (read once, move on) and an implementer (file:line precision).

Skip this format for one-line bug fixes or trivially atomic changes. The three-tier overhead is wasted on a change that can be summarized in one sentence.

## Structure

### Tier 1 — Summary (top of file, 60-second read)

Five to seven bullets. Each bullet is a complete thought a reader can pick up cold. Cover:

- **What ships** — the change in one sentence.
- **What moves / what's renamed / what's added** — structural delta.
- **What gets fixed** — bug fixes folded in (if any).
- **What changes for users** — observable impact (plugin count, install command, API shape, etc.).
- **What's still paused / deferred** — out-of-scope items, with pointer to where they're tracked.
- **Delivery** — single PR, branch name, commit count expectation.
- **Done when** — the verification commands that prove success (one line, not a section).

A reader who stops here should know what the PR is, what it changes, and how to verify it. No deeper read required.

### Tier 2 — High-level overview (middle of file)

One section per major change. Bullets throughout. No tables. No prose paragraphs.

For each major change, cover:

- The shape of the change (3-5 bullets).
- Rationale — why this approach, in one bullet if it's obvious or three if it's not.
- Honest acknowledgment of asymmetries (if part of the change doesn't fit a uniform pattern, say so explicitly).

Then add cross-cutting sections:

- **Scope decisions** — explicit IN list + explicit OUT list. Bullets. The OUT items should point at where they're tracked (ROADMAP item, follow-up issue).
- **Math / counts** — plugin counts, file counts, anything that anchors the scale of the change.
- **Why one PR (not three)** — for solo devs, this is one bullet; for teams with reviewers, omit or replace with a PR-sequencing plan.

Each section: bullets only. Read it once, internalize the shape, move on. If the reader stops here, they understand the design + scope without reading implementation.

### Tier 3 — Implementer guide (bottom of file)

Step-by-step. Each step is a numbered section with:

- A short rationale (one sentence) — why this step lands here in the sequence.
- Bulleted action items with **specific file paths**.
- Exact edits when they're non-obvious (e.g., regex patterns, function signatures).
- A **Checkpoint** line at the end describing the verification command(s) that prove the step worked.

For patterns that repeat across many files, describe the pattern once and list a few representative paths. Do not enumerate every file:line — the implementer can grep.

Also include in Tier 3:

- **Critical files** — concise list of the load-bearing paths the implementer will touch. Pattern-based, not exhaustive.
- **Reusable utilities** — existing functions / helpers / scripts the implementer should call rather than reinvent. Cite them by path.

If using `git mv`, say so explicitly so history follows. If commit messages must avoid AI co-author attribution (or have any other commit hygiene constraint), call it out.

## Style rules

- **Bullets only.** No tables. No prose paragraphs longer than three sentences.
- **Declarative.** "A happens, then B happens." Not "We might want to consider A, then perhaps B."
- **Read once, move on.** Each section is self-contained. A reader should not have to scroll back to interpret a section.
- **Honest about asymmetries.** If part of the change doesn't fit the uniform pattern, say so in plain words. Don't paper over.
- **No multi-PR splits for solo devs.** Default to one PR. Multi-PR ceremony is for teams with parallel reviewers; if the user is solo, skip it. If the change is genuinely too big for one PR, that's a sign the scope is wrong, not that you need three PRs.
- **Scope discipline.** Always include explicit IN / OUT lists. Vague scope is the most common plan failure mode.

## Sample skeleton

When generating a plan, follow this exact skeleton:

```markdown
# Plan — [meaningful title with the three or so big things this change does]

> Layered by reader depth. Tier 1 is the 60-second read. Tier 2 is the reviewer's dig-in. Tier 3 is the implementer's reference.

---

## Tier 1 — Summary (30-60 second read)

- **What ships**: …
- **What moves**: …
- **What gets fixed**: …
- **What changes for users**: …
- **What's still paused**: …
- **Delivery**: one commit on PR #N (currently M commits → M+1). Push to <branch>.
- **Done when**: <one-line verification recipe>.

---

## Tier 2 — High-level overview

### Change 1: [title]

- [bullets describing the shape of change 1]

### Change 2: [title]

- [bullets describing the shape of change 2]

### Scope decisions (what's explicitly in vs out)

- IN: …
- OUT: … (points at where the OUT items are tracked)

### [Counts / math anchoring scale]

- [plugin count, file count, etc.]

### Why one PR (not three)

- We're solo. No external reviewers, no review-surface budget to amortize.
- [other context-specific reasons]

---

## Tier 3 — Implementer guide

### Step 1: [title]

[One-sentence rationale for ordering.]

- [bulleted action items with file paths]

Checkpoint: [verification command].

### Step 2: [title]

[…]

### Critical files (patterns repeat; representative paths only)

- [grouped by purpose]

### Reusable utilities (referenced, not reinvented)

- [path → what it does]
```

## Anti-patterns (don't do these)

- **Tables everywhere.** Tables look organized but force the reader to scan two dimensions. Bullets are one-dimensional and faster. Skip tables unless the data is genuinely tabular (e.g., a config matrix).
- **Prose paragraphs.** A 5-line paragraph hides 5 facts. Five bullets surface 5 facts. The reader gets the same content in less cognitive load.
- **Multi-PR splits as the default.** They add ceremony without value when the team is one person. Recommend only when there's a concrete review-surface reason.
- **Enumerating every file:line in the implementer guide.** That belongs in the diff, not the plan. Patterns + representative paths is the right grain.
- **"We might consider…" hedging language.** Plans are commitments. Hedge in the scope section if you must; the rest of the document is declarative.
- **Hiding deferred work.** Always link OUT items to their tracking (ROADMAP, follow-up issue). "Deferred" without a pointer is a black hole.

## Optional Meta section

At the very end of the plan file, include a Meta section that captures the prompt template the user (or a future agent) can paste to trigger the same format. This makes the skill self-propagating: future plans cite the format by name and reproduce it.

```markdown
## Meta — prompt template for future tiered plans

Reusable across projects. Paste one of these into a future prompt to get this same three-tier format.

### Minimal trigger
- `Plan this as a tiered plan: Tier 1 summary, Tier 2 overview, Tier 3 implementer guide. Bullets only, no tables. Solo dev — one PR.`

### Full spec
- [full spec bullets]
```

## Workflow

When this skill triggers:

1. **Confirm scope first.** Ask 1-4 clarifying questions via `AskUserQuestion` if any of these are unclear: the IN/OUT boundary, the delivery target (which PR / branch), the solo-vs-team assumption, whether to fold pending bugs in. Skip questions you can answer from context.
2. **Run focused exploration if needed.** If the codebase is unfamiliar, launch one Explore agent (not three) to map the change's blast radius. Skip if context is clear.
3. **Draft the plan in the skeleton above.** Write Tier 1 last, after Tier 2 crystallizes — that way the summary reflects what the plan actually says.
4. **Save the plan** to wherever the user's harness expects plans (`~/.claude/plans/<name>.md` for plan-mode workflows, or wherever they direct).
5. **End the planning turn with ExitPlanMode** if in plan mode, or with a short summary if not.

## Why this format works

- **Reviewer ergonomics.** A reviewer who has 60 seconds gets the shape of the change from Tier 1. A reviewer who has 5 minutes gets the design from Tier 2. A reviewer who wants to verify mechanics digs into Tier 3.
- **Implementer ergonomics.** The implementer (often a future agent) has the file paths + verification commands they need, without wading through prose.
- **Self-correcting.** If Tier 1 doesn't capture the plan, the gap is obvious to anyone re-reading. If Tier 2 drifts from Tier 3, that's a review surface too. Each tier is a check on the others.
- **Portable.** The Meta section means the format propagates without re-explanation.
