# Examples — copy and adapt

Concrete configs for common patterns. Pick the one closest to your case, swap in your content.

## Pattern 1 — Pick one of N options + annotate each

You generated 3 plan iterations. You want the user to rate each + pick which one to ship.

```json
{
  "title": "Pick which plan iteration to ship",
  "context": "Each card has the plan content + a rating + a comment box. Use the global radio at the bottom to pick which iteration to ship.",
  "items": [
    {
      "id": "iter-3",
      "heading": "Iteration 3 plan",
      "content_html": "<p>Standard depth, 9 implementation steps. Goal-first organization.</p>",
      "controls": [
        {"type": "rating", "key": "quality", "label": "Quality (1-5)", "min": 1, "max": 5},
        {"type": "freetext", "key": "comments", "label": "What would you change?", "rows": 3}
      ]
    },
    {
      "id": "iter-4",
      "heading": "Iteration 4 plan",
      "content_html": "<p>Reviewer-first rewrite. Approach has technical depth.</p>",
      "controls": [
        {"type": "rating", "key": "quality", "label": "Quality (1-5)", "min": 1, "max": 5},
        {"type": "freetext", "key": "comments", "label": "What would you change?", "rows": 3}
      ]
    }
  ],
  "global_controls": [
    {"type": "radio", "key": "ship", "label": "Which iteration to ship?", "options": ["iter-3", "iter-4", "neither — iterate again"]}
  ]
}
```

## Pattern 2 — Rate N items on multiple dimensions

You wrote 4 candidate commit messages. You want the user to score each on clarity, accuracy, and conciseness.

```json
{
  "title": "Rate the candidate commit messages",
  "items": [
    {
      "id": "msg-a",
      "heading": "Candidate A",
      "content_html": "<pre><code>refactor(auth): swap session cookies for JWTs</code></pre>",
      "controls": [
        {"type": "rating", "key": "clarity", "label": "Clarity", "min": 1, "max": 5},
        {"type": "rating", "key": "accuracy", "label": "Accuracy", "min": 1, "max": 5},
        {"type": "rating", "key": "conciseness", "label": "Conciseness", "min": 1, "max": 5}
      ]
    },
    {
      "id": "msg-b",
      "heading": "Candidate B",
      "content_html": "<pre><code>feat(auth): JWT-based auth replacing session cookies</code></pre>",
      "controls": [
        {"type": "rating", "key": "clarity", "label": "Clarity", "min": 1, "max": 5},
        {"type": "rating", "key": "accuracy", "label": "Accuracy", "min": 1, "max": 5},
        {"type": "rating", "key": "conciseness", "label": "Conciseness", "min": 1, "max": 5}
      ]
    }
  ],
  "global_controls": [
    {"type": "select", "key": "winner", "label": "Use which?", "options": ["msg-a", "msg-b", "msg-c", "msg-d", "I'll write my own"]}
  ]
}
```

## Pattern 3 — Refine proposed text in place

You drafted 3 README sections. You want the user to edit each in place + approve when satisfied.

```json
{
  "title": "Edit the proposed README sections",
  "context": "Each section is pre-filled with my draft. Edit in place; toggle 'looks good' when each is ready.",
  "items": [
    {
      "id": "section-install",
      "heading": "## Install",
      "controls": [
        {"type": "edittext", "key": "body", "label": "Section body (markdown)", "rows": 8, "default": "Run `pip install foo` to install.\n\nVerify with `foo --version`."},
        {"type": "toggle", "key": "approved", "label": "Looks good"}
      ]
    },
    {
      "id": "section-quickstart",
      "heading": "## Quickstart",
      "controls": [
        {"type": "edittext", "key": "body", "label": "Section body (markdown)", "rows": 8, "default": "```python\nimport foo\nfoo.do_the_thing()\n```"},
        {"type": "toggle", "key": "approved", "label": "Looks good"}
      ]
    }
  ]
}
```

## Pattern 4 — Triage list (keep / drop / modify per item)

You found 12 candidate bug-fix targets. You want the user to triage each.

```json
{
  "title": "Triage the bug-fix candidates",
  "context": "Three options per item: keep (fix in this PR), drop (not now), or note (defer with a comment).",
  "items": [
    {
      "id": "bug-1",
      "heading": "auth.py:42 — race condition in token refresh",
      "content_html": "<p>Found via thread-safety audit. Reproduces in ~5% of concurrent runs.</p>",
      "controls": [
        {"type": "radio", "key": "verdict", "label": "Verdict", "options": ["keep", "drop", "note"]},
        {"type": "freetext", "key": "note", "label": "Note (if applicable)", "rows": 2}
      ]
    },
    {
      "id": "bug-2",
      "heading": "logging.py:88 — formatter ignores stacklevel",
      "content_html": "<p>Stack frames point at the logger, not the caller. Affects ~30 log sites.</p>",
      "controls": [
        {"type": "radio", "key": "verdict", "label": "Verdict", "options": ["keep", "drop", "note"]},
        {"type": "freetext", "key": "note", "label": "Note (if applicable)", "rows": 2}
      ]
    }
  ]
}
```

## Pattern 5 — Multi-dimensional vote across categories

You're scoping a roadmap. You want the user to mark which features land in which release.

```json
{
  "title": "Roadmap scoping",
  "context": "For each candidate feature, pick the release and tag the affected platforms.",
  "items": [
    {
      "id": "feat-rate-limit",
      "heading": "API rate limiting",
      "content_html": "<p>Per-user token-bucket rate limiting on POST endpoints.</p>",
      "controls": [
        {"type": "select", "key": "release", "label": "Target release", "options": ["v2.0", "v2.1", "v2.2", "backlog"]},
        {"type": "multiselect", "key": "platforms", "label": "Affected platforms", "options": ["web", "mobile-ios", "mobile-android", "cli"]},
        {"type": "rating", "key": "priority", "label": "Priority (1=low, 5=urgent)", "min": 1, "max": 5}
      ]
    }
  ],
  "global_controls": [
    {"type": "freetext", "key": "overall_notes", "label": "Overall roadmap notes", "rows": 4}
  ]
}
```

## Combining content_html with code

`content_html` accepts any HTML. To show code, wrap it in `<pre><code>`. To show markdown, render it to HTML first in your script (Python's `markdown` library works well via `uv add markdown`).

```python
import markdown
md = "## Some heading\n- bullet\n- bullet"
content_html = markdown.markdown(md, extensions=["fenced_code"])
```

Then pass `content_html` into your config.

## A note on item IDs and control keys

The returned JSON keys come straight from your `id` and `key` fields. Pick them so your parsing code reads naturally:

```python
verdict = feedback["items"]["bug-1"]["verdict"]   # "keep" / "drop" / "note"
note    = feedback["items"]["bug-1"]["note"]
ship    = feedback["global"]["ship"]
```

Keep IDs short, kebab-case, no spaces. The user never sees them — they're for you.
