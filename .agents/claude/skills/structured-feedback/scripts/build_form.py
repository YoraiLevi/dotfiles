#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
build_form.py — turn a config JSON into a self-contained HTML feedback form.

Usage:
    python build_form.py --config <path/to/config.json> --output <path/to/form.html>

The output HTML is fully self-contained (inline CSS + inline JS). When the user
clicks Submit, the form downloads a `feedback.json` they paste/upload back
to the calling agent.

See ../SKILL.md and ../references/control_types.md for the config schema.
"""

import argparse
import json
import html
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
TEMPLATE_PATH = SCRIPT_DIR.parent / "assets" / "form_template.html"


# ─── HTML helpers ─────────────────────────────────────────────────────────────


def esc(s: object) -> str:
    """Escape user-supplied text for safe HTML embedding."""
    return html.escape(str(s), quote=True)


def render_toggle(c: dict) -> str:
    key = esc(c["key"])
    label = esc(c.get("label", c["key"]))
    checked = "checked" if c.get("default") else ""
    return f'''
      <div class="control control-toggle">
        <label class="control-label" for="{key}">{label}</label>
        <label class="toggle">
          <input type="checkbox" id="{key}" name="{key}" data-control="toggle" {checked}>
          <span class="slider"></span>
        </label>
      </div>
    '''


def render_rating(c: dict) -> str:
    key = esc(c["key"])
    label = esc(c.get("label", c["key"]))
    lo = int(c.get("min", 1))
    hi = int(c.get("max", 5))
    default = c.get("default")
    options = ""
    for n in range(lo, hi + 1):
        selected = "data-selected" if default is not None and int(default) == n else ""
        options += f'<button type="button" class="rating-option" data-value="{n}" {selected}>{n}</button>'
    return f'''
      <div class="control control-rating">
        <label class="control-label">{label}</label>
        <div class="rating" data-key="{key}" data-control="rating">
          {options}
        </div>
      </div>
    '''


def render_freetext(c: dict) -> str:
    key = esc(c["key"])
    label = esc(c.get("label", c["key"]))
    rows = int(c.get("rows", 3))
    placeholder = esc(c.get("placeholder", ""))
    default = esc(c.get("default", ""))
    return f'''
      <div class="control control-freetext">
        <label class="control-label" for="{key}">{label}</label>
        <textarea id="{key}" name="{key}" rows="{rows}" placeholder="{placeholder}" data-control="freetext">{default}</textarea>
      </div>
    '''


def render_shorttext(c: dict) -> str:
    key = esc(c["key"])
    label = esc(c.get("label", c["key"]))
    placeholder = esc(c.get("placeholder", ""))
    default = esc(c.get("default", ""))
    return f'''
      <div class="control control-shorttext">
        <label class="control-label" for="{key}">{label}</label>
        <input type="text" id="{key}" name="{key}" placeholder="{placeholder}" value="{default}" data-control="shorttext">
      </div>
    '''


def render_edittext(c: dict) -> str:
    """Same as freetext but semantically: the agent provided default content
    for the user to refine. Uses textarea so the user can rewrite freely."""
    return render_freetext(c)


def render_select(c: dict) -> str:
    key = esc(c["key"])
    label = esc(c.get("label", c["key"]))
    opts = c.get("options", [])
    default = c.get("default")
    option_html = '<option value="">— pick one —</option>'
    for o in opts:
        sel = "selected" if default == o else ""
        option_html += f'<option value="{esc(o)}" {sel}>{esc(o)}</option>'
    return f'''
      <div class="control control-select">
        <label class="control-label" for="{key}">{label}</label>
        <select id="{key}" name="{key}" data-control="select">
          {option_html}
        </select>
      </div>
    '''


def render_multiselect(c: dict) -> str:
    key = esc(c["key"])
    label = esc(c.get("label", c["key"]))
    opts = c.get("options", [])
    defaults = set(c.get("default", []))
    checks = ""
    for i, o in enumerate(opts):
        checked = "checked" if o in defaults else ""
        oid = f"{key}-{i}"
        checks += f'''
          <label class="check-row">
            <input type="checkbox" id="{oid}" value="{esc(o)}" {checked}>
            <span>{esc(o)}</span>
          </label>
        '''
    return f'''
      <div class="control control-multiselect">
        <label class="control-label">{label}</label>
        <div class="multiselect" data-key="{key}" data-control="multiselect">
          {checks}
        </div>
      </div>
    '''


def render_radio(c: dict) -> str:
    key = esc(c["key"])
    label = esc(c.get("label", c["key"]))
    opts = c.get("options", [])
    default = c.get("default")
    radios = ""
    for i, o in enumerate(opts):
        checked = "checked" if default == o else ""
        oid = f"{key}-{i}"
        radios += f'''
          <label class="radio-row">
            <input type="radio" id="{oid}" name="{key}-grp" value="{esc(o)}" {checked}>
            <span>{esc(o)}</span>
          </label>
        '''
    return f'''
      <div class="control control-radio">
        <label class="control-label">{label}</label>
        <div class="radio-group" data-key="{key}" data-control="radio">
          {radios}
        </div>
      </div>
    '''


CONTROL_RENDERERS = {
    "toggle": render_toggle,
    "rating": render_rating,
    "freetext": render_freetext,
    "shorttext": render_shorttext,
    "edittext": render_edittext,
    "select": render_select,
    "multiselect": render_multiselect,
    "radio": render_radio,
}


def render_controls(controls: list[dict]) -> str:
    out = []
    for c in controls or []:
        renderer = CONTROL_RENDERERS.get(c.get("type"))
        if not renderer:
            raise ValueError(
                f"Unknown control type: {c.get('type')!r}. "
                f"Supported: {sorted(CONTROL_RENDERERS)}"
            )
        out.append(renderer(c))
    return "\n".join(out)


def render_item(item: dict) -> str:
    item_id = esc(item["id"])
    heading_html = ""
    if item.get("heading"):
        heading_html = f'<h2 class="item-heading">{esc(item["heading"])}</h2>'
    content_html = item.get("content_html", "") or ""
    if item.get("content_text") and not content_html:
        content_html = f'<pre class="item-content-text">{esc(item["content_text"])}</pre>'
    return f'''
    <section class="item-card" data-item-id="{item_id}">
      {heading_html}
      {content_html}
      <div class="item-controls">
        {render_controls(item.get("controls", []))}
      </div>
    </section>
    '''


def render_global_controls(controls: list[dict]) -> str:
    if not controls:
        return ""
    return f'''
    <section class="global-card" id="global-controls">
      <h2 class="global-heading">Overall</h2>
      <div class="item-controls">
        {render_controls(controls)}
      </div>
    </section>
    '''


# ─── main ─────────────────────────────────────────────────────────────────────


def build_form(config: dict) -> str:
    if not TEMPLATE_PATH.exists():
        raise FileNotFoundError(
            f"Form template not found at {TEMPLATE_PATH}. "
            "Reinstall the structured-feedback skill."
        )
    template = TEMPLATE_PATH.read_text(encoding="utf-8")

    title = esc(config.get("title", "Feedback"))
    context = config.get("context", "") or ""
    context_html = f'<p class="context">{esc(context)}</p>' if context else ""

    items_html = "\n".join(render_item(it) for it in config.get("items", []))
    global_html = render_global_controls(config.get("global_controls", []))

    return (template
        .replace("__TITLE_PLACEHOLDER__", title)
        .replace("__CONTEXT_PLACEHOLDER__", context_html)
        .replace("__ITEMS_PLACEHOLDER__", items_html)
        .replace("__GLOBAL_CONTROLS_PLACEHOLDER__", global_html))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--config", required=True, help="Path to config JSON")
    ap.add_argument("--output", required=True, help="Path for the generated HTML")
    args = ap.parse_args()

    config_path = Path(args.config)
    output_path = Path(args.output)

    config = json.loads(config_path.read_text(encoding="utf-8"))
    html_out = build_form(config)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(html_out, encoding="utf-8", newline="")

    print(f"Wrote {output_path} ({len(html_out)} chars)")
    print(f"Items: {len(config.get('items', []))}")
    print(f"Global controls: {len(config.get('global_controls', []))}")


if __name__ == "__main__":
    main()
