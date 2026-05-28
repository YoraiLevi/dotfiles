#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Grade each plan.md against the 9 structural assertions for the tiered-plan skill.

Writes grading.json to each <eval>/<condition>/ directory with the schema
{eval_dir, condition, assertions: [{text, passed, evidence}], summary}.
"""

import json
import re
import sys
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parent
EVALS = [
    "eval-1-logging-refactor",
    "eval-2-cli-dry-run-flag",
    "eval-3-settings-consolidation",
]
CONDITIONS = ["with_skill", "without_skill"]


def check_tier_1_section(text: str) -> tuple[bool, str]:
    m = re.search(r"##\s+(Tier\s*1|Summary)", text, re.IGNORECASE)
    if m:
        return True, f"found heading: '{m.group(0)}'"
    return False, "no Tier 1 / Summary heading"


def check_tier_1_bullets(text: str) -> tuple[bool, str]:
    # Find Tier 1 section content between heading and next ## heading
    m = re.search(
        r"##\s+(?:Tier\s*1|Summary)[^\n]*\n(.*?)(?=\n##\s|\Z)",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if not m:
        return False, "no Tier 1 section to count"
    section = m.group(1)
    bullets = re.findall(r"^[-*]\s+", section, re.MULTILINE)
    count = len(bullets)
    ok = 5 <= count <= 12
    return ok, f"{count} bullets (want 5-12)"


def check_tier_2_section(text: str) -> tuple[bool, str]:
    m = re.search(
        r"##\s+(Tier\s*2|High-level\s+overview|Overview)",
        text,
        re.IGNORECASE,
    )
    if m:
        return True, f"found heading: '{m.group(0)}'"
    return False, "no Tier 2 / Overview heading"


def check_tier_3_section(text: str) -> tuple[bool, str]:
    m = re.search(
        r"##\s+(Tier\s*3|Implementer)",
        text,
        re.IGNORECASE,
    )
    if m:
        return True, f"found heading: '{m.group(0)}'"
    return False, "no Tier 3 / Implementer heading"


def check_in_out_scope(text: str) -> tuple[bool, str]:
    in_hits = re.findall(r"(?<![A-Za-z])IN[:\s]", text)
    out_hits = re.findall(r"(?<![A-Za-z])OUT[:\s]", text)
    if in_hits and out_hits:
        return True, f"IN: x{len(in_hits)}, OUT: x{len(out_hits)}"
    return False, f"IN: x{len(in_hits)}, OUT: x{len(out_hits)}"


def check_checkpoint(text: str) -> tuple[bool, str]:
    hits = re.findall(r"Checkpoint:", text)
    if hits:
        return True, f"x{len(hits)} Checkpoint: markers"
    return False, "no Checkpoint: marker"


def check_no_tables(text: str) -> tuple[bool, str]:
    # Markdown table separator: a line like |---|---| or |:---|:---:|
    separators = re.findall(r"^\s*\|[\s\-:|]+\|\s*$", text, re.MULTILINE)
    if not separators:
        return True, "no table separators found"
    return False, f"x{len(separators)} table separator lines"


def check_meta_section(text: str) -> tuple[bool, str]:
    # Look in last 40% of file
    cutoff = int(len(text) * 0.6)
    last_part = text[cutoff:]
    m = re.search(r"##\s+(Meta|Prompt\s+template)", last_part, re.IGNORECASE)
    if m:
        return True, f"found in last 40%: '{m.group(0)}'"
    # Fall back to full file (some plans put Meta earlier)
    m_full = re.search(r"##\s+(Meta|Prompt\s+template)", text, re.IGNORECASE)
    if m_full:
        return True, f"found (not at end): '{m_full.group(0)}'"
    return False, "no Meta / Prompt template section"


def check_no_long_paragraphs(text: str) -> tuple[bool, str]:
    # Strip code blocks first
    in_code = False
    paragraphs: list[str] = []
    buf: list[str] = []
    for raw in text.split("\n"):
        s = raw.strip()
        if s.startswith("```"):
            in_code = not in_code
            if buf:
                paragraphs.append(" ".join(buf))
                buf = []
            continue
        if in_code:
            continue
        # Treat headings, bullets, blockquotes, table rows as paragraph terminators
        if (
            s.startswith("#")
            or s.startswith("-")
            or s.startswith("*")
            or s.startswith(">")
            or s.startswith("|")
            or s.startswith("1.")
            or s == ""
        ):
            if buf:
                paragraphs.append(" ".join(buf))
                buf = []
            continue
        buf.append(s)
    if buf:
        paragraphs.append(" ".join(buf))

    offenders: list[str] = []
    for p in paragraphs:
        if len(p) <= 200:
            continue
        # Count sentence-ends followed by space + capital letter
        sentence_count = len(re.findall(r"[.!?]\s+[A-Z]", p)) + 1
        if sentence_count >= 4:
            offenders.append(f"{sentence_count} sentences / {len(p)} chars")

    if not offenders:
        return True, "no long prose paragraphs"
    return False, f"x{len(offenders)} long paragraphs: " + "; ".join(offenders[:3])


ASSERTIONS = [
    ("Plan has a Tier 1 / Summary section", check_tier_1_section),
    ("Tier 1 contains 5-12 bullets", check_tier_1_bullets),
    ("Plan has a Tier 2 / Overview section", check_tier_2_section),
    ("Plan has a Tier 3 / Implementer section", check_tier_3_section),
    ("Plan has explicit IN: and OUT: scope lists", check_in_out_scope),
    ("Plan has Checkpoint: markers in Tier 3", check_checkpoint),
    ("Plan contains no markdown tables", check_no_tables),
    ("Plan ends with a Meta section / prompt template", check_meta_section),
    ("No multi-sentence prose paragraphs longer than 200 chars", check_no_long_paragraphs),
]


def grade_run(plan_path: Path, eval_dir: str, condition: str) -> dict:
    text = plan_path.read_text(encoding="utf-8")
    results = []
    for assertion_text, check_fn in ASSERTIONS:
        passed, evidence = check_fn(text)
        results.append({
            "text": assertion_text,
            "passed": passed,
            "evidence": evidence,
        })
    return {
        "eval_dir": eval_dir,
        "condition": condition,
        "assertions": results,
        "summary": {
            "total": len(results),
            "passed": sum(1 for r in results if r["passed"]),
        },
    }


def main() -> None:
    print(f"{'eval':<35} {'condition':<15} {'passed/total':<12}")
    print("-" * 65)
    for eval_dir in EVALS:
        for cond in CONDITIONS:
            plan_path = WORKSPACE / eval_dir / cond / "outputs" / "plan.md"
            if not plan_path.exists():
                print(f"{eval_dir:<35} {cond:<15} MISSING ({plan_path})")
                continue
            out = grade_run(plan_path, eval_dir, cond)
            out_path = plan_path.parent.parent / "grading.json"
            out_path.write_text(
                json.dumps(out, indent=2), encoding="utf-8", newline=""
            )
            s = out["summary"]
            print(f"{eval_dir:<35} {cond:<15} {s['passed']}/{s['total']}")


if __name__ == "__main__":
    main()
