#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Iteration-3 grader: check principles, not template labels.

Iteration-3 of the tiered-plan skill replaced the fixed 4-tier template with
guidance. The assertions follow: they check that plans satisfy the load-bearing
principles (goal-first, scope discipline, step rationale, checkpoints, sub-lists,
no Meta, no tables, no prose) — without requiring specific tier headings.
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
CONDITIONS = ["new_skill", "without_skill"]


GOAL_KEYWORDS = (
    "goal", "objective", "problem", "why", "purpose", "background",
    "what we", "what we're",
)
HOW_SUMMARY_KEYWORDS = (
    "what ships", "what's changing", "what changes",
)


def first_h2_heading(text: str) -> str | None:
    m = re.search(r"^##\s+(.+)$", text, re.MULTILINE)
    return m.group(1).strip() if m else None


def check_goal_first(text: str) -> tuple[bool, str]:
    h2 = first_h2_heading(text)
    if not h2:
        return False, "no ## heading found"
    lower = h2.lower()
    for kw in HOW_SUMMARY_KEYWORDS:
        if kw in lower:
            return False, f"first ## is HOW-summary: '{h2}'"
    for kw in GOAL_KEYWORDS:
        if kw in lower:
            return True, f"first ## is goal-oriented: '{h2}'"
    return False, f"first ## is neither goal nor obvious HOW: '{h2}'"


def check_scope_in_out(text: str) -> tuple[bool, str]:
    in_patterns = [
        r"\bScope\s+IN\b",
        r"\bIN\s*[:\*]",
        r"\bIN\s+scope\b",
        r"^[*-]?\s*\**\s*IN\b",
    ]
    out_patterns = [
        r"\bScope\s+OUT\b",
        r"\bOUT\s*[:\*]",
        r"\bOUT\s+of\s+scope\b",
        r"^[*-]?\s*\**\s*OUT\b",
    ]
    has_in = any(re.search(p, text, re.MULTILINE) for p in in_patterns)
    has_out = any(re.search(p, text, re.MULTILINE) for p in out_patterns)
    if has_in and has_out:
        return True, "found Scope IN + Scope OUT (or equivalent)"
    return False, f"has_in={has_in}, has_out={has_out}"


def find_implementation_section(text: str) -> str | None:
    # Find a section that looks like the implementer guide
    m = re.search(
        r"##\s+(Implementation|Implementer|Steps|Execution|How)\b[^\n]*\n(.*?)(?=\n##\s|\Z)",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if m:
        return m.group(2)
    # Fall back to last ## section
    sections = re.findall(r"##\s+[^\n]+\n(.*?)(?=\n##\s|\Z)", text, re.DOTALL)
    return sections[-1] if sections else None


def check_step_rationale(text: str) -> tuple[bool, str]:
    impl = find_implementation_section(text)
    if not impl:
        return False, "no implementation section found"
    # Count ### Step headings
    steps = re.findall(r"^###\s+(Step\s+\d+[^\n]*|\d+\.\s+[^\n]+)", impl, re.MULTILINE)
    step_count = len(steps)
    if step_count == 0:
        return False, "no ### Step subsections in implementation"
    # Count rationale markers: "because", "since", "so that", "lands here", "first because"
    rationale_pattern = re.compile(
        r"\b(because|since|so\s+that|lands\s+here|comes\s+first|goes\s+last)\b",
        re.IGNORECASE,
    )
    rationale_hits = rationale_pattern.findall(impl)
    # Heuristic: pass if rationale hits >= half the step count and >= 2 absolute
    ok = step_count >= 2 and len(rationale_hits) >= max(2, step_count // 2)
    return ok, f"{step_count} steps, {len(rationale_hits)} rationale markers (want >= half)"


def check_checkpoint_markers(text: str) -> tuple[bool, str]:
    hits = re.findall(r"(Checkpoint:|Verification:|Verify:|Done when:)", text, re.IGNORECASE)
    if hits:
        return True, f"x{len(hits)} verification markers"
    return False, "no Checkpoint/Verification markers"


def check_no_tables(text: str) -> tuple[bool, str]:
    separators = re.findall(r"^\s*\|[\s\-:|]+\|\s*$", text, re.MULTILINE)
    if not separators:
        return True, "no table separators"
    return False, f"x{len(separators)} table separators"


def check_no_meta_section(text: str) -> tuple[bool, str]:
    m = re.search(r"##\s+(Meta|Prompt\s+template\s+for\s+future)", text, re.IGNORECASE)
    if m:
        return False, f"unwanted Meta section: '{m.group(0)}'"
    return True, "no Meta section"


def check_sublist_breakdown(text: str) -> tuple[bool, str]:
    # Strip code blocks so fenced examples don't count.
    cleaned: list[str] = []
    in_code = False
    for line in text.split("\n"):
        if line.strip().startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            continue
        cleaned.append(line)
    body = "\n".join(cleaned)
    # Count nested bullets — bullets indented at least 2 spaces.
    nested = re.findall(r"^( {2,})[-*]\s+", body, re.MULTILINE)
    count = len(nested)
    ok = count >= 5
    return ok, f"{count} nested bullets (want >= 5)"


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
            offenders.append(f"{sentence_count}s/{len(p)}c")

    if not offenders:
        return True, "no long prose"
    return False, f"x{len(offenders)}: " + "; ".join(offenders[:2])


ASSERTIONS = [
    ("First top-level section is goal-oriented (Goal/Objective/Problem/Why)", check_goal_first),
    ("Plan has explicit Scope IN and Scope OUT (or equivalent) lists", check_scope_in_out),
    ("Implementer steps include rationale (because/since/so that)", check_step_rationale),
    ("Plan has Checkpoint: or verification markers per step", check_checkpoint_markers),
    ("Plan contains no markdown tables", check_no_tables),
    ("Plan does NOT include a Meta / prompt-template section", check_no_meta_section),
    ("Plan uses sub-lists for multi-part thoughts (>= 5 nested bullets)", check_sublist_breakdown),
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
    return {
        "expectations": expectations,
        "summary": {
            "passed": passed_n,
            "failed": total - passed_n,
            "total": total,
            "pass_rate": round(passed_n / total, 4) if total else 0.0,
        },
    }


def main() -> None:
    print(f"{'eval':<35} {'condition':<14} {'passed/total':<14} {'rate':<8}")
    print("-" * 74)
    for eval_dir in EVALS:
        for cond in CONDITIONS:
            run_dir = WORKSPACE / eval_dir / cond / "run-1"
            plan_path = run_dir / "outputs" / "plan.md"
            if not plan_path.exists():
                print(f"{eval_dir:<35} {cond:<14} MISSING")
                continue
            data = grade_run(plan_path)
            (run_dir / "grading.json").write_text(
                json.dumps(data, indent=2), encoding="utf-8", newline=""
            )
            s = data["summary"]
            print(f"{eval_dir:<35} {cond:<14} {s['passed']}/{s['total']:<12} {s['pass_rate']}")


if __name__ == "__main__":
    main()
