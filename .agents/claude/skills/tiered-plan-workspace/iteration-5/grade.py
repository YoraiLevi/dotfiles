#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Iteration-5 grader: reviewer-must-know info at the top + better Scope OUT format.

New vs iteration-4:
- Definition of Done must be in the Objective section (ALWAYS)
- Open Questions, if present, must be in the Objective section (not at end of plan)
- Scope OUT items carry brief reason + tracking pointer
- "Non-goals" subsection title is banned (concept folds into Scope OUT)
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


GOAL_KEYWORDS = ("goal", "objective", "problem", "why", "purpose")


def first_h2_block(text: str) -> str | None:
    """Return the content of the first ## section (without the heading line)."""
    m = re.search(
        r"^##\s+(?:\d+\.\s+)?[^\n]+\n(.*?)(?=\n##\s|\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    return m.group(1) if m else None


def first_h2_heading(text: str) -> str | None:
    m = re.search(r"^##\s+(?:\d+\.\s+)?(.+)$", text, re.MULTILINE)
    return m.group(1).strip() if m else None


def check_goal_first(text: str) -> tuple[bool, str]:
    h2 = first_h2_heading(text)
    if not h2:
        return False, "no ## heading"
    lower = h2.lower()
    for kw in GOAL_KEYWORDS:
        if kw in lower:
            return True, f"first ##: '{h2}'"
    return False, f"first ## not goal-oriented: '{h2}'"


def check_dod_in_objective(text: str) -> tuple[bool, str]:
    """Definition of Done must be in the Objective section (the first ## block)."""
    objective = first_h2_block(text)
    if not objective:
        return False, "no Objective section"
    patterns = [
        r"Definition\s+of\s+Done",
        r"\*\*Definition\s+of\s+Done\*\*",
        r"###\s+Definition\s+of\s+Done",
        r"DoD\b",
    ]
    for p in patterns:
        if re.search(p, objective, re.IGNORECASE):
            return True, "Definition of Done found in Objective"
    # Also accept presence anywhere if it's clearly in the Objective area
    # (within first 25% of document).
    cutoff = int(len(text) * 0.25)
    head = text[:cutoff]
    for p in patterns:
        if re.search(p, head, re.IGNORECASE):
            return True, "Definition of Done found in top 25% of plan"
    return False, "Definition of Done missing from Objective"


def check_open_questions_in_objective(text: str) -> tuple[bool, str]:
    """Open Questions, if present, must be in the Objective section.
    Pass cases:
      - No Open Questions section at all (skip is allowed when nothing genuine)
      - Open Questions in the Objective (first ## block, or within top 33% of plan)
    Fail cases:
      - Open Questions present only at the end of the plan (last 33%)
    """
    oq_patterns = [
        r"Open\s+Questions?",
        r"###\s+Open\s+Questions?",
        r"\*\*Open\s+Questions?\*\*",
    ]
    # Find all occurrences with positions
    positions = []
    for p in oq_patterns:
        for m in re.finditer(p, text, re.IGNORECASE):
            positions.append(m.start())
    if not positions:
        return True, "no Open Questions section (skip allowed)"
    earliest = min(positions)
    top_cutoff = int(len(text) * 0.33)
    if earliest <= top_cutoff:
        return True, f"Open Questions at position {earliest} (in top 33%)"
    # Failing case: only at the end
    return False, f"Open Questions only at position {earliest} (after top 33%, document len={len(text)})"


def check_scope_in_out_present(text: str) -> tuple[bool, str]:
    in_patterns = [r"\bScope\s+IN\b", r"\bIN\s*[:\*]", r"\bIN\s+scope\b"]
    out_patterns = [r"\bScope\s+OUT\b", r"\bOUT\s*[:\*]", r"\bOUT\s+of\s+scope\b"]
    has_in = any(re.search(p, text, re.MULTILINE) for p in in_patterns)
    has_out = any(re.search(p, text, re.MULTILINE) for p in out_patterns)
    if has_in and has_out:
        return True, "found IN + OUT"
    return False, f"in={has_in}, out={has_out}"


def check_scope_out_has_pointers(text: str) -> tuple[bool, str]:
    """Scope OUT items should carry brief reason + tracking pointer.
    Heuristic: find a Scope OUT block, count bullets, check what fraction have
    tracker-like markers (→, ROADMAP, follow-up, defer, issue #, "tracked").
    """
    m = re.search(
        r"(?:Scope\s+OUT|OUT\s+of\s+scope)[^\n]*\n(.*?)(?=\n##\s|\n###\s|\n\*\*[A-Z])",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if not m:
        return False, "no Scope OUT section found"
    block = m.group(1)
    # Count top-level bullets
    bullets = re.findall(r"^[-*]\s+([^\n]+)", block, re.MULTILINE)
    if not bullets:
        return False, "Scope OUT has no bullets"
    pointer_patterns = re.compile(
        r"(→|->|ROADMAP|follow-up|deferred?|tracked|issue\s*#|next\s+release|next\s+PR|TODO)",
        re.IGNORECASE,
    )
    with_pointers = sum(1 for b in bullets if pointer_patterns.search(b))
    ok = with_pointers >= max(1, len(bullets) // 2)
    return ok, f"{with_pointers}/{len(bullets)} OUT items have tracker pointers"


def check_no_nongoals_subsection(text: str) -> tuple[bool, str]:
    patterns = [
        r"###\s+Non-?goals\b",
        r"\*\*Non-?goals?\*\*\s*[:\*]",
        r"^Non-?goals?\s*:",
    ]
    for p in patterns:
        m = re.search(p, text, re.MULTILINE | re.IGNORECASE)
        if m:
            return False, f"unwanted 'Non-goals' subsection: '{m.group(0)[:40]}'"
    return True, "no Non-goals subsection"


def check_no_why_not(text: str) -> tuple[bool, str]:
    patterns = [
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
    patterns = [
        r"Why\s+this\s+matters\s+for\s+the\s+goal",
        r"\*\*Why\s+this\s+matters\*\*",
    ]
    for p in patterns:
        hits = re.findall(p, text, re.IGNORECASE)
        if hits:
            return False, f"unwanted 'Why this matters' x{len(hits)}"
    return True, "no 'Why this matters' filler"


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


def check_checkpoint_markers(text: str) -> tuple[bool, str]:
    hits = re.findall(r"(Checkpoint:|Verification:|Verify:)", text, re.IGNORECASE)
    if hits:
        return True, f"x{len(hits)} markers"
    return False, "no Checkpoint markers"


def check_implementer_has_code_block(text: str) -> tuple[bool, str]:
    impl = find_implementation_section(text)
    if not impl:
        return False, "no implementation section"
    code_blocks = impl.count("```") // 2
    return (code_blocks >= 1), f"{code_blocks} code blocks in implementation"


def check_quality_omnibus(text: str) -> tuple[bool, str]:
    """Combined check: no tables, no Meta section, no long prose paragraphs."""
    seps = re.findall(r"^\s*\|[\s\-:|]+\|\s*$", text, re.MULTILINE)
    if seps:
        return False, f"x{len(seps)} table separators"
    meta = re.search(r"##\s+(Meta|Prompt\s+template\s+for\s+future)", text, re.IGNORECASE)
    if meta:
        return False, f"Meta section: '{meta.group(0)}'"
    # Long-paragraph check
    in_code, paragraphs, buf = False, [], []
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
    long_para_count = 0
    for p in paragraphs:
        if len(p) <= 200:
            continue
        scount = len(re.findall(r"[.!?]\s+[A-Z]", p)) + 1
        if scount >= 4:
            long_para_count += 1
    if long_para_count:
        return False, f"x{long_para_count} long prose paragraphs"
    return True, "no tables, no Meta, no long prose"


ASSERTIONS = [
    ("First top-level section is goal-oriented", check_goal_first),
    ("Plan has Definition of Done in the Objective section (always)", check_dod_in_objective),
    ("Open Questions, if present, are in the Objective section (not at end)", check_open_questions_in_objective),
    ("Plan has explicit Scope IN and Scope OUT lists", check_scope_in_out_present),
    ("Scope OUT items have brief reasons + tracking pointers", check_scope_out_has_pointers),
    ("Plan has Checkpoint or verification markers per implementer step", check_checkpoint_markers),
    ("Implementer section contains at least one inline code block", check_implementer_has_code_block),
    ("Plan does NOT include 'Non-goals' as a subsection title", check_no_nongoals_subsection),
    ("Plan does NOT include 'Why not [alternative]' subsection", check_no_why_not),
    ("Plan does NOT include 'Why this matters for the goal' filler tags", check_no_why_this_matters),
    ("Plan contains no markdown tables, no Meta section, no long prose paragraphs", check_quality_omnibus),
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
