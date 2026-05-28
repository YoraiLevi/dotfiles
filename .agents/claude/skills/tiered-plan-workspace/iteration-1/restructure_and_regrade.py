#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Move existing outputs/timing.json into a run-1/ subdir per the aggregate_benchmark
expected layout, then rewrite grading.json with the schema the viewer + aggregator
require: top-level `expectations` array (text/passed/evidence) plus a summary with
pass_rate/passed/failed/total.

Run this once after the initial grading; subsequent iterations should be structured
correctly from the start.
"""

import json
import re
import shutil
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parent
EVALS = [
    "eval-1-logging-refactor",
    "eval-2-cli-dry-run-flag",
    "eval-3-settings-consolidation",
]
CONDITIONS = ["with_skill", "without_skill"]


# Re-use the assertion checks from grade.py so output is consistent.
import importlib.util
spec = importlib.util.spec_from_file_location("grade", WORKSPACE / "grade.py")
grade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grade)


def restructure(condition_dir: Path) -> Path:
    """Move outputs/ + timing.json into <condition>/run-1/.

    Idempotent: if run-1/ already exists with outputs/, do nothing.
    """
    run_dir = condition_dir / "run-1"
    run_dir.mkdir(exist_ok=True)

    # Move outputs/ if it's still at the condition root
    outputs_src = condition_dir / "outputs"
    outputs_dst = run_dir / "outputs"
    if outputs_src.exists() and not outputs_dst.exists():
        shutil.move(str(outputs_src), str(outputs_dst))

    # Move timing.json if it's at the condition root
    timing_src = condition_dir / "timing.json"
    timing_dst = run_dir / "timing.json"
    if timing_src.exists() and not timing_dst.exists():
        shutil.move(str(timing_src), str(timing_dst))

    # Move legacy grading.json (if any) to run-1/ then we'll rewrite it below
    grading_src = condition_dir / "grading.json"
    grading_dst = run_dir / "grading.json"
    if grading_src.exists() and not grading_dst.exists():
        shutil.move(str(grading_src), str(grading_dst))

    return run_dir


def grade_to_viewer_schema(plan_path: Path) -> dict:
    """Produce a grading.json shaped for the aggregator + viewer."""
    text = plan_path.read_text(encoding="utf-8")
    expectations = []
    for assertion_text, check_fn in grade.ASSERTIONS:
        passed, evidence = check_fn(text)
        expectations.append({
            "text": assertion_text,
            "passed": passed,
            "evidence": evidence,
        })
    passed_n = sum(1 for e in expectations if e["passed"])
    total = len(expectations)
    failed = total - passed_n
    pass_rate = (passed_n / total) if total else 0.0
    return {
        "expectations": expectations,
        "summary": {
            "passed": passed_n,
            "failed": failed,
            "total": total,
            "pass_rate": round(pass_rate, 4),
        },
    }


def main() -> None:
    print(f"{'eval':<35} {'condition':<15} {'passed/total':<14} {'pass_rate':<10}")
    print("-" * 75)
    for eval_dir in EVALS:
        for cond in CONDITIONS:
            cond_dir = WORKSPACE / eval_dir / cond
            if not cond_dir.exists():
                continue
            run_dir = restructure(cond_dir)
            plan_path = run_dir / "outputs" / "plan.md"
            if not plan_path.exists():
                print(f"{eval_dir:<35} {cond:<15} MISSING ({plan_path})")
                continue
            data = grade_to_viewer_schema(plan_path)
            (run_dir / "grading.json").write_text(
                json.dumps(data, indent=2), encoding="utf-8", newline=""
            )
            s = data["summary"]
            print(f"{eval_dir:<35} {cond:<15} {s['passed']}/{s['total']:<12} {s['pass_rate']}")


if __name__ == "__main__":
    main()
