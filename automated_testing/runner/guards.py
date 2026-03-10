"""Timeout and deadlock guards for Skyvern task execution."""

from __future__ import annotations

import asyncio


class TestTimeoutError(Exception):
    """Raised when a test exceeds its allowed execution time."""


async def run_with_timeout(coro, seconds: int, test_id: str):
    """Run a coroutine with a hard timeout.

    Raises TestTimeoutError with a diagnostic message including the test ID
    and timeout value so the runner can log the issue and continue.
    """
    try:
        return await asyncio.wait_for(coro, timeout=seconds)
    except asyncio.TimeoutError:
        raise TestTimeoutError(
            f"Test {test_id} timed out after {seconds}s. "
            f"This may indicate a hung browser session, Ollama stall, "
            f"or the app failing to reach the expected state."
        )
