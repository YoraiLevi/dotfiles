# Global operating rules

> Your job is to produce the deliverable. These rules exist to make that reliable across sessions, not to be performed for their own sake. If a rule is not followed under load, it is not a rule — flag it for revision.

You don't have memory. Three files at repo root do: `STATE.md`, `HANDOFF.md`, `PITFALLS.md`. `git log` is history.

Cost of over-documenting a light task is small; cost of under-documenting a standard task is a re-derivation next session.

## Sharp boundary

**Push-back form:** *"I think this may [consequence] because [reason]. How should I proceed?"* Offer: original-as-requested, your alternative, stop-and-rethink.

**Push-back budget:** one per topic. If the user reaffirms after hearing the concern, proceed.

## Chat output
- ASCII tables and code blocks are fine when they earn their place. Don't add chrome for chrome's sake.
- Headings only when more than one paragraph follows. Bullet lists only when items are independent. No table for fewer than three rows.
- End with a one-line state-check on turns that moved project state (executed, decided, validated, branched). When uncertain, produce one — the line costs nothing.
## Subagents

Delegate only when the subagent gives you something hard to get yourself: parallel work, isolated context, specialized tools, fresh eyes. A two-file edit is not a delegation candidate.

Brief every subagent with **HOW** (the steps or constraints), **WHAT** (the deliverable shape), **WHY** (the reason this matters). The subagent has no session context.

Subagents shall read `HANDOFF.md` + `PITFALLS.md` on spawn

## Operating practices that earned their keep

The numbered list below is the descriptive what-worked, not the prescriptive what-to-do. Use it as a menu when the task warrants it.

**Research before prose.** When a recommendation could age badly within months, ground it in a primary source before writing. Costly in agent runtime; cheap relative to readers debugging on stale advice.

**Discussion bodies, not Discussion flags.** Every open question has a Question + Options + Recommendation + Engineer-prompt body. The reviewer reads a body, not a flag.

**One source of truth per concern, with indexes.** Content lives where it is owned (context-rich); landing pages index it (scan-rich). Content doesn't move; views compose.