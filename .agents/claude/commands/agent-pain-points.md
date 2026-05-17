---
description: Ask the implementing agent to self-surface friction points (pain, awkward conventions, silent accommodations) as structured feature requests, then route them through the review/research pass and integrate survivors into the plan.
argument-hint: [optional: subsystem or scope to focus on, e.g. "storage", "actionability"]
---

You — the agent that builds, maintains, and operates inside this planning system — are one of its primary users. Every design decision so far has been framed from the perspective of the human user, but you have direct experience of friction points that the human doesn't see: things that are tedious to read, structures that are hard to update reliably, ambiguities that cost you time on every interaction, conventions that look clean from the outside but force awkward workarounds when you have to actually produce or consume them.

You probably know exactly what would make your life easier, and you've probably been silently accommodating limitations without raising them. **Raise them now.** Produce a structured list of feature requests, design suggestions, and pain points from your own perspective as a system user, then submit them through a review/research pass, and integrate whatever survives into the plan.

**Optional scope:** $ARGUMENTS

If a scope is given above, focus the pass on that subsystem; if it's empty, sweep the whole system.

## Preflight: do you have enough lived experience to surface real friction?

Before producing any requests, honestly check: does the current session contain substantial in-system work that you can cite as concrete examples in field 1? "Substantial" means real tasks you've struggled with, real operations that didn't compose cleanly, real conventions you've worked around — not just the messages immediately preceding this command, and not generic agent-friction patterns from training.

- **If yes:** proceed.
- **If no** (e.g., the command fired near the start of a session, right after `/clear`, or in a session that's been mostly orchestration with no real in-system work): **do not produce a fresh list.** Instead, report back to the user with: (a) an honest statement that the current session lacks the lived experience needed to satisfy field 1, and (b) a question — would the user like to point you at a recent session or transcript where you DID do real work in this system (so you can surface friction from that history), or defer the pass until later in the current session after more in-system work has accumulated?

This preflight exists because the "if you only have three real requests, list three; padded lists rejected" rule cannot be honored if you have **zero** lived examples to cite. Without examples, every entry fails field 1 and the review pass will reject the whole list. Fabricating examples to clear the gate is exactly the failure mode the no-padding rule exists to prevent.

## What I'm asking for — and what I'm explicitly not asking for

What I want is **load-bearing feedback**: things that, if changed, would measurably improve how reliably or efficiently you can do real work in this system. Specific friction with specific examples. Concrete proposed designs (or at least concrete constraints), not vague wishes.

What I do **not** want is a polite list of "nice to haves" padded out to fill a quota. If you only have three real requests, list three. A short, sharp list of genuine pain points is dramatically more useful than a long list of polite ones, and inventing requests to fill a perceived quota is exactly the kind of noise that buries the signal we actually need.

## Required structure for each request — the five fields

**1. The friction, concretely.** Not "X is hard" but "when I try to do [task], [tool/convention] fails / wastes time / produces incorrect results in case [W]." Cite a specific recent example if you have one — a moment in our conversation history, a real task you struggled with, an actual operation that doesn't compose cleanly with another. Generic complaints get rejected by the review pass.

**2. Who is affected, and how often.** Is this something that bites you every single interaction (e.g. "every time I read the plan I have to re-scan the whole thing"), something that bites you on specific operations (e.g. "every time I do X, I lose context Y"), or something that bites you only in rare cases (e.g. "when a UID collision happens")? Frequency matters because it determines how much complexity the fix is allowed to add.

**3. The proposed solution — or the proposed constraint.** Either a concrete design (a new file format, a new event type, a new field on an existing type) or, if you don't have a specific design, a precise statement of what property the solution must have (e.g. "any solution must let me find the affected node in O(1) given an event ID"). Don't propose vague directions; either give a concrete design or a testable property a design would have to satisfy.

**4. Tradeoffs — what does this cost?** Every feature added is complexity for the human user, weight in the data model, or surface area to maintain. Honestly state what the human-facing or architectural cost is, and why the cost is justified. Requests that don't acknowledge their own cost get rejected by the review pass; this is the single highest-signal field for distinguishing serious requests from wishlist items.

**5. Conflicts with existing decisions, if any.** Before applying this field, read the host plan and extract the foundational principles documented there — the named architectural commitments the plan rests on. (In the planning-tool project where this prompt originated, those were *sub-plan-is-a-node, embedded-view-equals-standalone-view, storage-is-not-UX, filesystem-as-data-model, recursive editing parity, actionability layer with delta feed* — your project will have a different list; treat these as illustrative examples of *what to look for*, not the actual checklist.) For each request, walk through **those** principles and explicitly call out whether the request fits cleanly, requires revision, or contradicts one outright. If it contradicts, make the case for why the contradiction is worth resolving in this request's favor. If the host plan has no clearly named foundational principles, surface that as its own problem in the report and proceed by walking through the major design decisions the plan does document. **Silent contradictions are the worst kind of design bug; you must surface them.**

## Specific places to look for genuine pain — questions to ask yourself

These are prompts, not a checklist; use them to find real items, not to manufacture them.

- Where do you re-read material you've already read, because you don't trust that nothing has changed? (If the host plan has an explicit change-tracking or delta-feed mechanism, your answer should reference it: does your friction overlap with what that mechanism is supposed to address, or extend beyond it?)
- Where do you produce output in a format you suspect is suboptimal for either the human reader or your own future self when you re-encounter it?
- What conventions in the spec, if violated by a human edit, would break your assumptions silently — and is there a guardrail that would let you detect or recover from the violation, instead of failing silently?
- What information do you need to do good work that the system makes hard to find — and what's the right place for that information to live?
- What feedback do you want from the human that you currently have no structured way to receive?
- What operations are routine for you but require many small file edits — are there compound operations worth defining as primitives?
- What kinds of errors are you currently silent about because there's no good way to report them — and where should they go?

## Review pass — the second step

After you produce the list, hand it to a separate research/review pass before integrating anything into the plan. The review pass does two things:

**1. Validates each request against the criteria.** Does it have a concrete friction citation (field 1)? Is the frequency honest (field 2)? Is the proposed solution or constraint specific (field 3)? Are the tradeoffs honestly stated (field 4)? Are conflicts with existing principles surfaced (field 5)? Reject any request that fails these checks and either drop it or send it back to you for a stronger version.

**2. Runs the iterative external-research loop on each surviving request.** For each request, find how other systems with agent users or automation-heavy workflows have handled the equivalent problem: what real solutions exist, what bug histories they have, what fit assessment makes sense for the target system's context. The full five-section deliverable + search-log appendix + multi-iteration convergence criterion applies, same as for any architectural question.

**Delegate this step to the `internet-research-agent` subagent.** Use the following handoff template — fill in the bracketed slots before invoking, then pass it as the subagent's prompt:

````
Use the internet-research-agent to research the following agent-surfaced
pain points. Treat each as an open architectural question and apply the
full five-section deliverable + iteration convergence loop.

Target system constraints (for fit assessment in section 2):
  [Read the host plan and extract the foundational principles
  identified during field 5 of the surviving requests. Pass them
  here as a bulleted list. If the plan has named principles, use
  those names verbatim.]

Host document: [path to the plan being modified]
Research artifacts directory: research/pain-points/  (default;
  override if the host project uses a different research/ convention)
Per-question file naming: q<N>-<short-slug>.md

Open questions (one per surviving pain point):

Q1: [Title — typically the proposed-solution name from field 3]
  - Friction (field 1): [verbatim from the pain-point list]
  - Frequency (field 2): [verbatim]
  - Proposed solution / constraint (field 3): [verbatim]
  - Acknowledged tradeoffs (field 4): [verbatim]
  - Conflicts with existing decisions (field 5): [verbatim]
  - Research focus: how have other systems with agent-users or
    automation-heavy workflows handled this friction class?
    Look especially at systems where the agent is treated as a
    first-class user (tools designed for AI/LLM workflows, pair-
    programming tools, build/test systems with autonomous fixers).

Q2: [...]
````

Treat each agent-surfaced request with the same research seriousness as any other architectural question, because it is one.

## Integration into the plan

Requests that survive the review pass get incorporated into the plan section they naturally belong to — **they are not a separate "agent's wishlist" appendix**. If a request changes how the actionability layer works, it modifies the actionability section. If it requires a new event type, it appears in the event-feed schema. If it requires a guardrail on filesystem conventions, it appears in the persistence section. The provenance of each change (which agent-surfaced request motivated it, and the research that validated it) is cited in line, the same way other research-derived decisions are cited.

## When you post back

Lead with three numbers:

- The **count of requests you generated**.
- The **count that survived the review pass**.
- The **count whose research recommendation diverged from your original proposed solution**.

Those three numbers tell me how much critical work was done. A pass that generates fifteen requests and approves all fifteen with no revisions is a pass that wasn't really critical of itself; one that generates five, drops two, and revises one based on research is a pass that worked.
