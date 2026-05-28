#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Grade iteration-2 plans against the 4-tier format assertions.

Differences vs iteration-1:
- Tier 1 = Objective (not Summary). Tier 2 = Approach. Tier 3 = Per-change. Tier 4 = Implementer.
- New checks for embedded WHY rationale in Tier 4 steps.
- NO Meta section allowed (the skill explicitly drops it).
"""

import json
import re
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parent
EVALS = [
    "eval-1-logging-refactor",
    "eval-2-cli-dry-run-flag",
    "eval-3-settings-consolidation",
]
CONDITIONS = ["new_skill", "old_skill"]


# ─── per-assertion check functions ────────────────────────────────────────────


def check_tier_1_objective(text: str) -> tuple[bool, str]:
    """Tier 1 should be an Objective section (problem / why / success / risk)."""
    m = re.search(
        r"##\s+(Tier\s*1|Objective|Why)\b",
        text,
        re.IGNORECASE,
    )
    if not m:
        return False, "no Tier 1 / Objective heading"
    # Check for problem / why-now / success / risk hints
    section_match = re.search(
        r"##\s+(?:Tier\s*1|Objective|Why)[^\n]*\n(.*?)(?=\n##\s|\Z)",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if not section_match:
        return False, "Tier 1 section content not extractable"
    section = section_match.group(1).lower()
    hits = []
    for keyword, label in (
        ("problem", "Problem"),
        ("why now", "Why now"),
        ("success", "Success"),
        ("risk", "Risk"),
    ):
        if keyword in section:
            hits.append(label)
    ok = len(hits) >= 3
    return ok, f"found: {', '.join(hits) or 'none'} (want ≥3)"


def check_tier_1_bullets(text: str) -> tuple[bool, str]:
    m = re.search(
        r"##\s+(?:Tier\s*1|Objective|Why)[^\n]*\n(.*?)(?=\n##\s|\Z)",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if not m:
        return False, "no Tier 1 section"
    bullets = re.findall(r"^[-*]\s+", m.group(1), re.MULTILINE)
    count = len(bullets)
    ok = 4 <= count <= 12
    return ok, f"{count} bullets (want 4-12)"


def check_tier_2_approach(text: str) -> tuple[bool, str]:
    m = re.search(
        r"##\s+(Tier\s*2|Approach|Shape)\b",
        text,
        re.IGNORECASE,
    )
    if m:
        return True, f"found: '{m.group(0)}'"
    return False, "no Tier 2 / Approach heading"


def check_in_out_scope(text: str) -> tuple[bool, str]:
    in_hits = re.findall(r"(?<![A-Za-z])IN[:\s]", text)
    out_hits = re.findall(r"(?<![A-Za-z])OUT[:\s]", text)
    if in_hits and out_hits:
        return True, f"IN: x{len(in_hits)}, OUT: x{len(out_hits)}"
    return False, f"IN: x{len(in_hits)}, OUT: x{len(out_hits)}"


def check_tier_3_per_change(text: str) -> tuple[bool, str]:
    m = re.search(
        r"##\s+(Tier\s*3|Per-change|Overview)\b",
        text,
        re.IGNORECASE,
    )
    if not m:
        return False, "no Tier 3 / Per-change heading"
    # Should have at least one ### Change subsection
    section_match = re.search(
        r"##\s+(?:Tier\s*3|Per-change|Overview)[^\n]*\n(.*?)(?=\n##\s|\Z)",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if not section_match:
        return False, "Tier 3 section content not extractable"
    section = section_match.group(1)
    change_subsections = re.findall(r"^###\s+(Change\b|.*?\bChange\b)", section, re.MULTILINE | re.IGNORECASE)
    if not change_subsections:
        # Allow ### per-change subheadings with other names if there are ≥2 ### headings in Tier 3
        all_h3 = re.findall(r"^###\s+", section, re.MULTILINE)
        if len(all_h3) >= 2:
            return True, f"{len(all_h3)} ### subsections (no 'Change' label but ≥2 found)"
        return False, "no ### Change subsections"
    return True, f"{len(change_subsections)} ### Change subsections"


def check_tier_4_implementer(text: str) -> tuple[bool, str]:
    m = re.search(
        r"##\s+(Tier\s*4|Implementer)\b",
        text,
        re.IGNORECASE,
    )
    if m:
        return True, f"found: '{m.group(0)}'"
    return False, "no Tier 4 / Implementer heading"


def check_tier_4_step_rationale(text: str) -> tuple[bool, str]:
    """Tier 4 steps should open with rationale ("This step lands here because…")."""
    m = re.search(
        r"##\s+(?:Tier\s*4|Implementer)[^\n]*\n(.*?)(?=\n##\s|\Z)",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if not m:
        return False, "no Tier 4 section"
    section = m.group(1)
    # Find ### Step N headings
    steps = re.findall(r"^###\s+(Step\s+\d+[^\n]*)", section, re.MULTILINE)
    step_count = len(steps)
    if step_count == 0:
        return False, "no ### Step subsections in Tier 4"
    # Count rationale openers — "This step lands here because" or "This step…because"
    rationale_pattern = re.compile(
        r"(?:This step|It|Lands here|Goes here|First|Last)[^.\n]{0,80}\bbecause\b",
        re.IGNORECASE,
    )
    rationales = rationale_pattern.findall(section)
    # Pass if ≥ half of steps have rationale, AND at least 2 steps total
    ok = step_count >= 2 and len(rationales) >= max(2, step_count // 2)
    return ok, f"{step_count} steps, {len(rationales)} with rationale (want ≥ half)"


def check_checkpoint_markers(text: str) -> tuple[bool, str]:
    hits = re.findall(r"Checkpoint:", text)
    if hits:
        return True, f"x{len(hits)} Checkpoint: markers"
    return False, "no Checkpoint: marker"


def check_no_tables(text: str) -> tuple[bool, str]:
    separators = re.findall(r"^\s*\|[\s\-:|]+\|\s*$", text, re.MULTILINE)
    if not separators:
        return True, "no table separators"
    return False, f"x{len(separators)} table separators"


def check_no_meta_section(text: str) -> tuple[bool, str]:
    """The new skill explicitly drops the Meta section. Plans should NOT include one."""
    m = re.search(r"##\s+(Meta|Prompt\s+template\s+for\s+future)", text, re.IGNORECASE)
    if m:
        return False, f"unwanted Meta section found: '{m.group(0)}'"
    return True, "no Meta section"


def check_no_long_paragraphs(text: str) -> tuple[bool, str]:
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
        if (
            s.startswith("#")
            or s.startswith("-")
            or s.startswith("*")
            or s.startswith(">")
            or s.startswith("|")
            or s == ""
            or re.match(r"^\d+\.", s)
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
        sentence_count = len(re.findall(r"[.!?]\s+[A-Z]", p)) + 1
        if sentence_count >= 4:
            offenders.append(f"{sentence_count} sentences / {len(p)} chars")

    if not offenders:
        return True, "no long prose paragraphs"
    return False, f"x{len(offenders)}: " + "; ".join(offenders[:2])


ASSERTIONS = [
    ("Plan has a Tier 1 / Objective section (problem, why now, success, risk)", check_tier_1_objective),
    ("Tier 1 contains 4-12 bullets", check_tier_1_bullets),
    ("Plan has a Tier 2 / Approach section", check_tier_2_approach),
    ("Tier 2 has explicit IN: and OUT: scope lists", check_in_out_scope),
    ("Plan has a Tier 3 / Per-change overview with at least 2 sub-sections", check_tier_3_per_change),
    ("Plan has a Tier 4 / Implementer section", check_tier_4_implementer),
    ("Tier 4 steps include rationale (because…)", check_tier_4_step_rationale),
    ("Plan has Checkpoint: markers in Tier 4", check_checkpoint_markers),
    ("Plan contains no markdown tables", check_no_tables),
    ("Plan does NOT include a Meta / prompt template section", check_no_meta_section),
    ("No multi-sentence prose paragraphs longer than 200 chars", check_no_long_paragraphs),
]


def grade_run(plan_path: Path) -> dict:
    text = plan_path.read_text(encoding="utf-8")
    expectations = []
    for assertion_text, check_fn in ASSERTIONS:
        passed, evidence = check_fn(text)
        expectations.append({
            "text": assertion_text,
            "passed": passed,
            "evidence": evidence,
        })
    passed_n = sum(1 for e in expectations if e["passed"])
    total = len(expectations)
    failed = total - passed_n
    return {
        "expectations": expectations,
        "summary": {
            "passed": passed_n,
            "failed": failed,
            "total": total,
            "pass_rate": round(passed_n / total, 4) if total else 0.0,
        },
    }


def main() -> None:
    print(f"{'eval':<35} {'condition':<12} {'passed/total':<14} {'rate':<8}")
    print("-" * 72)
    for eval_dir in EVALS:
        for cond in CONDITIONS:
            run_dir = WORKSPACE / eval_dir / cond / "run-1"
            plan_path = run_dir / "outputs" / "plan.md"
            if not plan_path.exists():
                print(f"{eval_dir:<35} {cond:<12} MISSING ({plan_path})")
                continue
            data = grade_run(plan_path)
            (run_dir / "grading.json").write_text(
                json.dumps(data, indent=2), encoding="utf-8", newline=""
            )
            s = data["summary"]
            print(f"{eval_dir:<35} {cond:<12} {s['passed']}/{s['total']:<12} {s['pass_rate']}")


if __name__ == "__main__":
    main()
