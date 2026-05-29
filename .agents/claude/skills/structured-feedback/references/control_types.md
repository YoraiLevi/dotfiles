# Control types reference

Every control object in a config has at minimum:

- `type` — one of the names below.
- `key` — the field name returned in the JSON. Kebab-case, no spaces.
- `label` — what the user sees above the control.

Per-type extras:

## `toggle` — boolean

```json
{"type": "toggle", "key": "approve", "label": "Approve this item", "default": false}
```

**Returns**: `true` or `false`.

When to use: keep/drop decisions, approve/reject, include/exclude in final cut.

## `rating` — integer scale

```json
{"type": "rating", "key": "quality", "label": "Quality (1-5)", "min": 1, "max": 5, "default": null}
```

**Returns**: integer in `[min, max]` or `null` if nothing selected.

When to use: scoring items on a dimension. Keep `max - min + 1 <= 7` so the buttons fit comfortably in one row.

## `freetext` — multi-line comment

```json
{"type": "freetext", "key": "comments", "label": "Comments", "rows": 3, "placeholder": "what would you change?", "default": ""}
```

**Returns**: string (possibly empty).

When to use: open-ended commentary, "what would you change?", reviewer notes.

## `shorttext` — single-line input

```json
{"type": "shorttext", "key": "name", "label": "Proposed name", "placeholder": "kebab-case-name", "default": ""}
```

**Returns**: string.

When to use: short labels, file names, version strings.

## `edittext` — textarea pre-filled with content

Semantically identical to `freetext`, but the agent provides a `default` value that the user is meant to refine.

```json
{"type": "edittext", "key": "summary", "label": "Edit this summary", "rows": 5, "default": "The current summary text the agent wrote..."}
```

**Returns**: the user's edited string.

When to use: when you're proposing a paragraph/snippet for the user to tune (commit message, summary, description).

## `select` — dropdown, single choice

```json
{"type": "select", "key": "priority", "label": "Priority", "options": ["P0", "P1", "P2", "P3"], "default": "P2"}
```

**Returns**: the chosen option string, or `null` if "— pick one —" stayed selected.

When to use: short option lists (3-8 items) where horizontal space matters.

## `multiselect` — checkboxes, multiple choices

```json
{"type": "multiselect", "key": "platforms", "label": "Affected platforms", "options": ["Claude", "Codex", "Gemini", "Cursor", "Windsurf", "Devin"], "default": ["Claude"]}
```

**Returns**: array of strings (possibly empty).

When to use: "pick any number that apply" — affected systems, components to include, dimensions that matter.

## `radio` — radio buttons, single choice, all visible

```json
{"type": "radio", "key": "verdict", "label": "Verdict", "options": ["ship as-is", "ship with edits", "block"], "default": null}
```

**Returns**: the chosen option string, or `null` if nothing selected.

When to use: 2-5 mutually exclusive options where you want all of them visible (instead of hidden in a dropdown).

## Defaults

Every control accepts an optional `default` field. The user can change it; the value just sets the initial state.

- For `toggle`, default is `false` if omitted.
- For `rating`, default is `null` if omitted (no value pre-selected).
- For `freetext`/`shorttext`/`edittext`, default is `""` if omitted.
- For `select`/`radio`, default is `null` (no selection) if omitted.
- For `multiselect`, default is `[]` (nothing pre-checked) if omitted.

## What's NOT bundled

If you need any of these, write the HTML yourself by copying `assets/form_template.html` and modifying:

- File uploads
- Drag-and-drop ranking / reordering
- Conditional show/hide (show control B only if control A is true)
- Date/time pickers
- Numeric inputs with min/max validation
- Inline markdown rendering (use `content_html` to pre-render markdown to HTML in your code)
- Multi-step forms / pagination

The skill is for the common case. For creative needs, the template is your foundation.
