---
name: structured-feedback
description: Build a browser-based feedback form for collecting structured user opinions on multiple items at once — rate, toggle, edit, multi-select, rank, or annotate per item — then parse the JSON the user returns. Use this skill whenever you have a generated artifact (or several) and want richer user feedback than a single AskUserQuestion can capture: when you have 3+ items the user needs to review side-by-side, when each item needs multi-dimensional feedback (rating + comment + decision), when you want the user to edit text in-place, when you're proposing options for the user to pick + annotate, when AskUserQuestion would need 5+ separate questions to capture the feedback shape, OR when the conversation pattern is "here are N things — tell me what you think of each." The skill generates an HTML form; you send it via SendUserFile; the user fills it in their browser and downloads a JSON file; you parse the JSON when they drop it back. Pushy on triggering — if you're about to ask the user the same question 4+ times in sequence, use this instead.
---

# structured-feedback

A way to collect structured per-item feedback from the user without ping-ponging through `AskUserQuestion` calls.

## When to use this skill

- **You have multiple items to review** (plans, code samples, designs, ranked options) and want the user's opinion on each.
- **Each item needs multi-dimensional feedback** — not just "approve/reject" but "rating + comment + decision".
- **The user needs to edit text in place** — proposed names, summaries, descriptions they should refine before you proceed.
- **You're proposing N options** and want the user to pick + annotate why.
- **AskUserQuestion would need many separate calls** to capture the feedback shape — for instance, asking "rate option A on 3 dimensions" → "rate option B on 3 dimensions" → "comment on A" → "comment on B" is 4 questions; one form replaces them.

If you're about to send the same question 3+ times in a row, switch to this skill instead.

## When NOT to use this skill

- **Single yes/no question**: `AskUserQuestion` is the right tool.
- **Free-form chat reply expected**: just ask in chat.
- **The user is mid-flow on something else** and an HTML detour would break their concentration.

## The workflow

1. **Design the form.** Decide what items the user needs to give feedback on and what controls each item should have. (Defaults below; you can mix and match.)
2. **Write a config JSON** describing the form. Save it somewhere (e.g., your workspace dir).
3. **Generate the HTML** by running the bundled script:
   ```bash
   python C:/Users/devic/.claude/skills/structured-feedback/scripts/build_form.py \
     --config <path-to-config.json> \
     --output <path-to-output.html>
   ```
4. **Send the HTML to the user** via the `SendUserFile` tool with a short caption explaining what to do.
5. **Wait for the user to paste back** the `feedback.json` (the form downloads it when they click Submit).
6. **Parse the JSON** and act on it.

## The config JSON

The minimum: a title and a list of items. Items contain controls. Each control has a type, a key (for the returned JSON), and a label.

```json
{
  "title": "Pick which plan iteration to ship",
  "context": "Optional intro paragraph shown above the form.",
  "items": [
    {
      "id": "iter-3",
      "heading": "Iteration 3 plan",
      "content_html": "<p>Standard depth. 9 implementation steps.</p>",
      "controls": [
        {"type": "rating", "key": "quality", "label": "Quality (1-5)", "min": 1, "max": 5},
        {"type": "freetext", "key": "comments", "label": "Comments", "rows": 3}
      ]
    },
    {
      "id": "iter-4",
      "heading": "Iteration 4 plan",
      "content_html": "<p>Reviewer-first rewrite.</p>",
      "controls": [
        {"type": "rating", "key": "quality", "label": "Quality (1-5)", "min": 1, "max": 5},
        {"type": "freetext", "key": "comments", "label": "Comments", "rows": 3}
      ]
    }
  ],
  "global_controls": [
    {"type": "radio", "key": "ship", "label": "Which iteration to ship?", "options": ["iter-3", "iter-4", "neither"]}
  ]
}
```

The returned `feedback.json` will look like:

```json
{
  "items": {
    "iter-3": {"quality": 4, "comments": "good but Tier 1 is too long"},
    "iter-4": {"quality": 5, "comments": "ship this"}
  },
  "global": {"ship": "iter-4"},
  "submitted_at": "2026-05-29T01:42:00Z"
}
```

## Available control types

See `references/control_types.md` for the full table with examples. The common ones:

- **toggle** — boolean true/false (good for keep/drop)
- **rating** — numeric scale (good for quality scores)
- **freetext** — multi-line comment (good for "what would you change?")
- **shorttext** — single-line input (good for names/labels)
- **edittext** — text the user starts with and modifies (good for proposed-text refinement)
- **select** — dropdown, single choice
- **multiselect** — checkboxes, multiple choices
- **radio** — radio buttons, single choice with all visible

## Common patterns

See `references/examples.md` for full configs you can copy and adapt. Quick reference:

- **Pick + annotate N options**: each item gets a toggle ("keep") + freetext ("why"); global radio for "which to ship".
- **Rate N items on dimensions**: each item gets multiple ratings + one freetext.
- **Refine proposed text**: each item gets an edittext with the proposed content + a toggle ("approve").
- **Rank-and-rate**: each item gets a rating; global multiselect for "include in final cut".

## Creative freedom

The bundled script handles ~80% of cases. When you need something the script doesn't support:

- **Read** `assets/form_template.html` for the base structure.
- **Copy it**, write your own HTML directly (with custom controls / layout / JS), populate it with your content, send to the user.
- **Keep the submit-downloads-json contract** so your parsing code on the receiving side stays the same.

Your job is to know what feedback you need from the user — the skill is the building blocks. If a creative form serves the user better than the bundled controls, write the creative form.

## Tone for the SendUserFile caption

When sending the HTML, the caption should:

- Tell the user what they're looking at and what to do (open it in browser, fill it in, click Submit).
- Note that the form downloads a `feedback.json` they need to paste/upload back to you.
- Keep it short — one sentence + maybe one secondary detail.

Example: `"Pick which plan iteration to ship. Each card has a quality rating + comment box; the global radio at the bottom captures your overall pick. Click Submit when done — feedback.json downloads; drop it back here."`

## Hygiene

- **Don't pre-fill controls with mocked-up user opinions**. The user fills it; the agent designs it.
- **Pick item IDs and control keys you can parse later**. `iter-3`, `quality`, `ship` — short, kebab-case, no spaces.
- **Use `content_html` for substantial content** (a plan, a code sample, a paragraph) rather than cramming it into the heading or label. Headings and labels stay short.
- **One form per turn**. If you have two unrelated feedback rounds, do them sequentially — don't merge them into one mega-form that fatigues the user.
- **Don't ask for opinions you won't use**. Every control should map to a decision or action you'll take based on the answer.

## After the user returns the JSON

- Parse it (it's standard JSON).
- Acknowledge the answers — show the user you read them, summarize the verdict.
- Act on the feedback. If "ship: iter-4" → ship iter-4. If `quality: 2` with a critical comment → iterate.
- Don't over-thank or pad. Move forward.
