"""Human-in-the-loop interactive prompting for Grade-C and hardware tests.

When the runner encounters tests tagged 'manual_step' or loaded from
manual_companion.yaml with interactive_steps, this module pauses execution,
presents clear instructions to the human tester, and awaits confirmation.
"""

from __future__ import annotations

import asyncio
import sys
from typing import Optional

from .models import ManualResult

try:
    from rich.console import Console
    from rich.panel import Panel
    from rich.prompt import Prompt

    _console = Console()
    _HAS_RICH = True
except ImportError:
    _HAS_RICH = False


def _print_header(text: str) -> None:
    if _HAS_RICH:
        _console.print(Panel(text, title="Manual Test", border_style="yellow"))
    else:
        print(f"\n{'=' * 60}")
        print(f"  MANUAL TEST: {text}")
        print(f"{'=' * 60}\n")


def _print_instruction(text: str) -> None:
    if _HAS_RICH:
        _console.print(f"  [bold cyan]>>>[/bold cyan] {text}")
    else:
        print(f"  >>> {text}")


def _get_response(prompt_text: str = "Result (y=pass / n=fail / s=skip)") -> str:
    if _HAS_RICH:
        return Prompt.ask(f"  {prompt_text}", choices=["y", "n", "s"], default="s")
    while True:
        resp = input(f"  {prompt_text} [y/n/s]: ").strip().lower()
        if resp in ("y", "n", "s"):
            return resp
        print("  Please enter y, n, or s.")


def _get_keypress(prompt_text: str = "Press Enter when ready...") -> None:
    if _HAS_RICH:
        _console.input(f"  [dim]{prompt_text}[/dim] ")
    else:
        input(f"  {prompt_text} ")


async def run_interactive_test(test_def: dict) -> ManualResult:
    """Execute a manual/interactive test with human-in-the-loop prompting.

    Args:
        test_def: A dict from manual_companion.yaml containing at minimum:
            id, title, and either 'interactive_steps' or 'checklist'.

    Returns:
        ManualResult with human-provided pass/fail/skip status.
    """
    test_id = test_def["id"]
    title = test_def.get("title", test_id)
    reason = test_def.get("reason", "")
    checklist = test_def.get("checklist", [])
    interactive_steps = test_def.get("interactive_steps", [])

    _print_header(f"{test_id}: {title}")
    if reason:
        _print_instruction(f"Reason for manual execution: {reason}")
        print()

    checklist_results: list[dict] = []

    if interactive_steps:
        for i, step in enumerate(interactive_steps, 1):
            prompt_text = step.get("prompt", "")
            wait_for = step.get("wait_for", "confirmation")

            print(f"\n  Step {i}/{len(interactive_steps)}:")
            _print_instruction(prompt_text)

            if wait_for == "keypress":
                _get_keypress()
                checklist_results.append({"step": i, "prompt": prompt_text, "result": "acknowledged"})
            elif wait_for == "confirmation":
                resp = _get_response()
                status = {"y": "pass", "n": "fail", "s": "skip"}[resp]
                checklist_results.append({"step": i, "prompt": prompt_text, "result": status})
                if status == "fail":
                    notes = input("  Failure notes (optional): ").strip()
                    checklist_results[-1]["notes"] = notes
            else:
                _get_keypress(f"{wait_for} — Press Enter when done...")
                checklist_results.append({"step": i, "prompt": prompt_text, "result": "acknowledged"})

    elif checklist:
        for i, item in enumerate(checklist, 1):
            item_text = item.replace("[ ] ", "").replace("[x] ", "").strip()
            print(f"\n  Checklist item {i}/{len(checklist)}:")
            _print_instruction(item_text)
            resp = _get_response()
            status = {"y": "pass", "n": "fail", "s": "skip"}[resp]
            checklist_results.append({"item": i, "text": item_text, "result": status})

    print()
    overall = _get_response("Overall test result (y=pass / n=fail / s=skip)")
    overall_status = {"y": "PASS", "n": "FAIL", "s": "SKIP"}[overall]
    notes = ""
    if overall_status == "FAIL":
        notes = input("  Failure notes: ").strip()

    return ManualResult(
        test_id=test_id,
        title=title,
        status=overall_status,
        checklist_results=checklist_results,
        notes=notes,
    )


async def run_interactive_batch(
    manual_tests: list[dict],
    tag_filter: Optional[str] = None,
) -> list[ManualResult]:
    """Run a batch of interactive/manual tests sequentially.

    Args:
        manual_tests: List of test defs from manual_companion.yaml
        tag_filter: If set, only run tests whose tags include this value

    Returns:
        List of ManualResult objects.
    """
    results: list[ManualResult] = []
    filtered = manual_tests
    if tag_filter:
        filtered = [
            t for t in manual_tests
            if tag_filter in t.get("tags", [])
        ]

    total = len(filtered)
    print(f"\n{'=' * 60}")
    print(f"  INTERACTIVE TEST SESSION — {total} manual tests")
    print(f"{'=' * 60}")

    for i, test_def in enumerate(filtered, 1):
        print(f"\n  [{i}/{total}]")
        result = await run_interactive_test(test_def)
        results.append(result)

        if i < total:
            resp = input("\n  Continue to next test? (Enter=yes, q=quit): ").strip()
            if resp.lower() == "q":
                print("  Skipping remaining manual tests.")
                for remaining in filtered[i:]:
                    results.append(ManualResult(
                        test_id=remaining["id"],
                        title=remaining.get("title", ""),
                        status="SKIP",
                        notes="Skipped by user",
                    ))
                break

    return results
