- Plan this as a tiered plan: Tier 1 summary, Tier 2 overview, Tier 3 implementer guide. Bullets only, no tables. Solo dev — one PR.

Full spec (for when you want explicit control)

- Plan [the change] as a tiered plan:
- - Tier 1: 60-second summary, 7-10 bullets
- - Tier 2: high-level overview, one section per major change, bullets only, no tables
- - Tier 3: implementer guide with file paths, exact edits, verification commands per checkpoint
- - Declarative style ("A happens, B happens"), not hedging
- - Solo dev — one PR/one commit by default; no multi-PR splits
- - Include explicit in/out scope lists; acknowledge deferred work honestly
- - Use git mv to preserve history when moving files; no AI co-author attribution in commits

Optional add-ons (per-project context)

- Fold in pending review findings/bugs (when there's a code-review backlog)
- Acknowledge asymmetries honestly (when one part of the change doesn't fit a uniform pattern)
- Use existing utilities at <paths>; don't reinvent (when there's prior art)
- Run Explore agents for codebase coverage; skip Plan agent unless the design surface is novel (controls subagent budget)

What signals matter most (ranked)

- "Tiered plan" — names the format; biggest single lever
- "Bullets only, no tables" — style discipline; kills tables, prose paragraphs
- "Solo dev, one PR" — kills multi-PR over-engineering recommendations
- "In/out scope lists" — forces scope discipline; prevents implicit scope creep
- "Verification commands" — forces concrete checks; prevents hand-wavy "tests should pass" prose

When to use which variant

- The minimal trigger when you're confident I have enough project context (recurring conversations on the same repo)
- The full spec for new repos or when the project has unusual constraints
- The add-ons when the project has specific patterns to respect (existing utilities, prior conventions, pending bug backlogs)

Adding a Meta section to the plan file so this prompt template is preserved as a portable artifact.
