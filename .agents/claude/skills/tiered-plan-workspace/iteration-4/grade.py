#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Iteration-4 grader: reviewer-focused assertions.

New vs iteration-3:
- Added: no "Why not [alternative]" subsection
- Added: no "Why this matters for the goal" filler tag
- Added: implementer section contains inline code block (deliverable IS code)
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
)
HOW_SUMMARY_KEYWORDS = ("what ships", "what's changing", "what changes")


def first_h2_heading(text: str) -> str | None:
    m = re.search(r"^##\s+(?:\d+\.\s+)?(.+)$", text, re.MULTILINE)
    return m.group(1).strip() if m else None


def check_goal_first(text: str) -> tuple[bool, str]:
    h2 = first_h2_heading(text)
    if not h2:
        return False, "no ## heading"
    lower = h2.lower()
    for kw in HOW_SUMMARY_KEYWORDS:
        if kw in lower:
            return False, f"first ## is HOW-summary: '{h2}'"
    for kw in GOAL_KEYWORDS:
        if kw in lower:
            return True, f"first ##: '{h2}'"
    return False, f"first ## not goal-oriented: '{h2}'"


def check_scope_in_out(text: str) -> tuple[bool, str]:
    in_patterns = [r"\bScope\s+IN\b", r"\bIN\s*[:\*]", r"\bIN\s+scope\b"]
    out_patterns = [r"\bScope\s+OUT\b", r"\bOUT\s*[:\*]", r"\bOUT\s+of\s+scope\b"]
    has_in = any(re.search(p, text, re.MULTILINE) for p in in_patterns)
    has_out = any(re.search(p, text, re.MULTILINE) for p in out_patterns)
    if has_in and has_out:
        return True, "found IN + OUT"
    return False, f"in={has_in}, out={has_out}"


def find_implementation_section(text: str) -> str | None:
    m = re.search(
        r"##\s+(?:\d+\.\s+)?(Implementation|Implementer|Steps|Execution|How)\b[^\n]*\n(.*?)(?=\n##\s|\Z)",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if m:
        return m.group(2)
    sections = re.findall(r"##\s+[^\n]+\n(.*?)(?=\n##\s|\Z)", text, re.DOTALL)
    return sections[-1] if sections else None


def check_step_rationale(text: str) -> tuple[bool, str]:
    """Iter-4: rationale is OPTIONAL per step. Plans pass if either:
       - rationale appears at least once somewhere in the plan, OR
       - the plan is lightweight (<=6 steps) — meaning ordering is mostly obvious.
    """
    impl = find_implementation_section(text)
    if not impl:
        return False, "no implementation section"
    steps = re.findall(r"^###\s+(Step\s+\d+|\d+\.\s+\w+)", impl, re.MULTILINE)
    step_count = len(steps)
    if step_count == 0:
        return False, "no ### Step subsections"
    rationale_hits = re.findall(r"\b(because|since|so\s+that|lands\s+here)\b", impl, re.IGNORECASE)
    if step_count <= 6 and len(rationale_hits) == 0:
        return True, f"{step_count} steps (lightweight), no rationale OK"
    return (len(rationale_hits) >= 1), f"{step_count} steps, {len(rationale_hits)} rationale hits"


def check_checkpoint_markers(text: str) -> tuple[bool, str]:
    hits = re.findall(r"(Checkpoint:|Verification:|Verify:|Done when:)", text, re.IGNORECASE)
    if hits:
        return True, f"x{len(hits)} markers"
    return False, "no Checkpoint/Verify markers"


def check_no_tables(text: str) -> tuple[bool, str]:
    seps = re.findall(r"^\s*\|[\s\-:|]+\|\s*$", text, re.MULTILINE)
    return (not seps), ("no table separators" if not seps else f"x{len(seps)}")


def check_no_meta_section(text: str) -> tuple[bool, str]:
    m = re.search(r"##\s+(Meta|Prompt\s+template\s+for\s+future)", text, re.IGNORECASE)
    return (m is None), ("no Meta" if m is None else f"found: '{m.group(0)}'")


def check_sublist_breakdown(text: str) -> tuple[bool, str]:
    """Pass if the plan shows BREAKDOWN structure: nested bullets OR ###
    subheadings OR code blocks. The user's concern was prose-y bullets that
    cram multi-part thoughts into one line; any of these signals indicate
    proper breakdown."""
    cleaned, in_code = [], False
    for line in text.split("\n"):
        if line.strip().startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            continue
        cleaned.append(line)
    body = "\n".join(cleaned)
    nested = len(re.findall(r"^( {2,})[-*]\s+", body, re.MULTILINE))
    h3s = len(re.findall(r"^###\s+", body, re.MULTILINE))
    code_blocks = text.count("```") // 2
    total_signal = nested + h3s + code_blocks
    ok = total_signal >= 8
    return ok, f"{nested} nested + {h3s} ### + {code_blocks} code blocks = {total_signal} (want >=8)"


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
        if (s.startswith("#") or s.startswith("-") or s.startswith("*") or s.startswith(">")
            or s.startswith("|") or s == "" or re.match(r"^\d+\.", s)):
            if buf:
                paragraphs.append(" ".join(buf))
                buf = []
            continue
        buf.append(s)
    if buf:
        paragraphs.append(" ".join(buf))
    offenders = []
    for p in paragraphs:
        if len(p) <= 200:
            continue
        scount = len(re.findall(r"[.!?]\s+[A-Z]", p)) + 1
        if scount >= 4:
            offenders.append(f"{scount}s/{len(p)}c")
    return (not offenders), ("no long prose" if not offenders else f"x{len(offenders)}: " + "; ".join(offenders[:2]))


def check_no_why_not(text: str) -> tuple[bool, str]:
    """The skill explicitly drops 'Why not [alternative]' subsections."""
    patterns = [
        r"\bWhy\s+not\b.{0,40}\balternative\b",
        r"###\s+Why\s+not\b",
        r"\*\*Why\s+not\b",
        r"\bAlternatives\s+considered\b",
        r"\bAlternatives\s+rejected\b",
    ]
    for p in patterns:
        m = re.search(p, text, re.IGNORECASE)
        if m:
            return False, f"unwanted 'Why not' pattern: '{m.group(0)[:50]}'"
    return True, "no 'Why not' patterns"


def check_no_why_this_matters(text: str) -> tuple[bool, str]:
    """Drop the 'Why this matters for the goal' filler tag."""
    patterns = [
        r"Why\s+this\s+matters\s+for\s+the\s+goal",
        r"Why\s+this\s+matters\s*[:\*]",
        r"\*\*Why\s+this\s+matters\*\*",
    ]
    for p in patterns:
        hits = re.findall(p, text, re.IGNORECASE)
        if hits:
            return False, f"unwanted 'Why this matters' filler x{len(hits)}"
    return True, "no 'Why this matters' filler"


def check_implementer_has_code_block(text: str) -> tuple[bool, str]:
    """Implementer section should contain at least one inline code block."""
    impl = find_implementation_section(text)
    if not impl:
        return False, "no implementation section"
    code_blocks = re.findall(r"```", impl)
    pairs = len(code_blocks) // 2
    return (pairs >= 1), f"{pairs} code block(s) in implementation"


ASSERTIONS = [
    ("First top-level section is goal-oriented", check_goal_first),
    ("Plan has explicit Scope IN and Scope OUT lists", check_scope_in_out),
    ("Implementer steps include rationale where needed", check_step_rationale),
    ("Plan has Checkpoint or verification markers per step", check_checkpoint_markers),
    ("Plan contains no markdown tables", check_no_tables),
    ("Plan does NOT include a Meta / prompt-template section", check_no_meta_section),
    ("Plan uses sub-lists for multi-part thoughts (>= 5 nested bullets)", check_sublist_breakdown),
    ("No multi-sentence prose paragraphs longer than 200 chars", check_no_long_paragraphs),
    ("Plan does NOT include 'Why not [alternative]' subsection", check_no_why_not),
    ("Plan does NOT include 'Why this matters for the goal' filler tags", check_no_why_this_matters),
    ("Implementer section contains at least one inline code block", check_implementer_has_code_block),
]


def grade_run(plan_path: Path) -> dict:
    text = plan_path.read_text(encoding="utf-8")
    expectations = []
    for assertion_text, check_fn in ASSERTIONS:
        passed, evidence = check_fn(text)
        expectations.append({"text": assertion_text, "passed": passed, "evidence": evidence})
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
