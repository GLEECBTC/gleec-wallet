"""Prompt construction for Skyvern tasks targeting Flutter web apps."""

from __future__ import annotations

from .models import TestCase

FLUTTER_PREAMBLE = """\
IMPORTANT CONTEXT:
This is a Flutter web application rendered entirely on an HTML canvas element.
You cannot use DOM selectors — you must identify all elements visually.

Before taking any action on each new screen:
1. Wait 2 seconds for the page to fully render (Flutter animations to complete).
2. If you see a loading spinner, circular progress indicator, or skeleton
   placeholders, wait until they disappear before proceeding.
3. If the screen appears blank or only shows a solid color, wait 3 more
   seconds — Flutter may still be initialising.

If you are unsure whether an element is a button or just text, look for
visual cues: rounded corners, drop shadows, background color contrast,
or iconography that suggests interactivity.
"""

COMPLETION_SUFFIX = """
After completing the task, clearly state whether you succeeded or encountered
an error. If you see an error message, snackbar, or alert dialog on screen,
report its exact text in your response."""


def build_stepped_prompt(steps: list[dict]) -> str:
    """Convert checkpoint-based steps into a single sequential prompt."""
    lines = []
    for i, step in enumerate(steps, 1):
        action = step.get("action", "") if isinstance(step, dict) else step.action
        checkpoint = step.get("checkpoint") if isinstance(step, dict) else step.checkpoint

        lines.append(f"STEP {i}: {action.strip()}")
        if checkpoint:
            lines.append(
                f"  → BEFORE proceeding to step {i + 1}, verify: {checkpoint}"
            )
            lines.append(
                f"  → If this verification FAILS, STOP and report which step "
                f"failed and why."
            )
        lines.append("")
    return "\n".join(lines)


def build_prompt(
    test: TestCase,
    setup_prompt: str | None = None,
) -> str:
    """Assemble the full prompt for a Skyvern task.

    Combines the Flutter preamble, optional setup phase, the test body
    (either stepped or freeform), and the completion suffix.
    """
    parts: list[str] = [FLUTTER_PREAMBLE]

    if setup_prompt:
        parts.append(f"PHASE 1 — SETUP:\n{setup_prompt.strip()}\n")
        parts.append("After setup is complete, proceed immediately to Phase 2.\n")
        parts.append("PHASE 2 — TEST:")

    if test.steps:
        step_dicts = [
            {"action": s.action, "checkpoint": s.checkpoint}
            for s in test.steps
        ]
        parts.append(build_stepped_prompt(step_dicts))
    elif test.prompt:
        parts.append(test.prompt.strip())
    else:
        parts.append(f"Complete the following: {test.name}")

    parts.append(COMPLETION_SUFFIX)
    return "\n".join(parts)
