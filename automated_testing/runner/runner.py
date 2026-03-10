"""Hardened test runner — main orchestration for Gleec QA automation.

Usage:
    python -m runner.runner [--matrix PATH] [--tag TAG] [--single]
                            [--include-manual] [--manual-only]
                            [--ollama-url URL] [--skyvern-url URL]
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import yaml

from .guards import TestTimeoutError, run_with_timeout
from .interactive import run_interactive_batch
from .models import (
    AttemptResult, CompositePhase, ManualResult, TestCase, TestRun, VotedResult,
)
from .ollama_monitor import OllamaMonitor
from .preflight import run_preflight
from .prompt_builder import build_prompt
from .reporter import generate_html_report, write_json_results
from .retry import majority_vote, should_stop_early

logger = logging.getLogger(__name__)

DEFAULT_RETRIES = 3
CRITICAL_RETRIES = 5


def load_matrix(path: str) -> dict:
    with open(path, "r") as f:
        return yaml.safe_load(f)


def load_manual_tests(path: str) -> list[dict]:
    with open(path, "r") as f:
        data = yaml.safe_load(f)
    return data.get("manual_tests", [])


def parse_tests(matrix: dict) -> list[TestCase]:
    tests_raw = matrix.get("tests", [])
    tests = []
    for raw in tests_raw:
        if "steps" in raw and raw["steps"]:
            steps_parsed = []
            for s in raw["steps"]:
                if isinstance(s, dict):
                    steps_parsed.append(s)
                else:
                    steps_parsed.append({"action": str(s), "checkpoint": None})
            raw["steps"] = steps_parsed
        if "phases" in raw and raw["phases"]:
            for phase in raw["phases"]:
                phase.setdefault("args", {})
        tests.append(TestCase(**raw))
    return tests


async def execute_single_attempt(
    test: TestCase,
    config: dict,
    setup_prompt: Optional[str],
    skyvern_url: str,
) -> AttemptResult:
    """Execute a single test attempt via the Skyvern API."""
    import httpx

    full_prompt = build_prompt(test, setup_prompt)

    start = time.monotonic()
    try:
        base_url = config.get("base_url")
        if not base_url:
            return AttemptResult(
                attempt=0,
                status="ERROR",
                error="config.base_url is missing from test matrix",
                duration_seconds=0.0,
            )

        payload = {
            "url": base_url,
            "navigation_goal": full_prompt,
            "proxy_location": "NONE",
            "navigation_payload": None,
            "extracted_information_schema": test.extraction_schema,
        }

        engine = config.get("default_engine", "skyvern-2.0")
        max_steps = test.max_steps or config.get("max_steps_per_test", 30)

        async with httpx.AsyncClient(
            base_url=skyvern_url, timeout=None
        ) as client:
            resp = await client.post(
                "/api/v1/tasks",
                json=payload,
                headers={"x-api-key": "local"},
            )
            if resp.status_code not in (200, 201):
                return AttemptResult(
                    attempt=0,
                    status="ERROR",
                    skyvern_status=f"HTTP {resp.status_code}",
                    error=resp.text[:500],
                    duration_seconds=round(time.monotonic() - start, 2),
                )

            task_data = resp.json()
            task_id = task_data.get("task_id", "")

            for _ in range(max_steps * 3):
                await asyncio.sleep(5)
                status_resp = await client.get(
                    f"/api/v1/tasks/{task_id}",
                    headers={"x-api-key": "local"},
                )
                if status_resp.status_code != 200:
                    continue

                task_status = status_resp.json()
                skyvern_status = task_status.get("status", "")

                if skyvern_status in ("completed", "failed", "terminated"):
                    extracted = task_status.get("extracted_information")
                    is_pass = skyvern_status == "completed"
                    return AttemptResult(
                        attempt=0,
                        status="PASS" if is_pass else "FAIL",
                        skyvern_status=skyvern_status,
                        extracted_data=extracted,
                        duration_seconds=round(time.monotonic() - start, 2),
                        run_id=task_id,
                    )

            return AttemptResult(
                attempt=0,
                status="ERROR",
                skyvern_status="polling_timeout",
                error=f"Task {task_id} did not complete within polling limit",
                duration_seconds=round(time.monotonic() - start, 2),
                run_id=task_id,
            )

    except TestTimeoutError as exc:
        return AttemptResult(
            attempt=0,
            status="TIMEOUT",
            error=str(exc),
            duration_seconds=round(time.monotonic() - start, 2),
        )
    except Exception as exc:
        return AttemptResult(
            attempt=0,
            status="ERROR",
            error=f"{type(exc).__name__}: {exc}",
            duration_seconds=round(time.monotonic() - start, 2),
        )


async def execute_composite_attempt(
    test: TestCase,
    config: dict,
    setup_prompt: Optional[str],
    skyvern_url: str,
) -> AttemptResult:
    """Execute a composite test with mixed Skyvern + OS/Playwright phases."""
    from .os_automation import read_clipboard
    from .playwright_helpers import PlaywrightSession

    start = time.monotonic()
    pw_session = None
    phase_results = []

    try:
        for i, phase in enumerate(test.phases):
            phase_type = phase.type
            logger.info("    Phase %d/%d: %s — %s",
                        i + 1, len(test.phases), phase_type, phase.action[:60])

            if phase_type == "skyvern":
                sub_test = TestCase(
                    id=f"{test.id}_phase{i}",
                    name=phase.action[:80],
                    prompt=phase.prompt or phase.action,
                    steps=None,
                    expected_result=phase.expected or "",
                    extraction_schema=phase.extraction_schema,
                    max_steps=phase.max_steps or test.max_steps,
                    timeout=test.timeout,
                )
                result = await execute_single_attempt(
                    sub_test, config, setup_prompt if i == 0 else None, skyvern_url
                )
                phase_results.append({
                    "phase": i + 1, "type": phase_type,
                    "status": result.status,
                    "extracted": result.extracted_data,
                })
                if result.status != "PASS":
                    label = phase.checkpoint or phase.action[:80]
                    return AttemptResult(
                        attempt=0, status=result.status,
                        error=f"Phase {i+1} ({phase_type}) failed: {label}",
                        extracted_data={"phases": phase_results},
                        duration_seconds=round(time.monotonic() - start, 2),
                    )

            elif phase_type == "os_call":
                action = phase.action
                if action == "read_clipboard":
                    ok, text = await read_clipboard()
                    phase_results.append({"phase": i+1, "type": "os_call", "action": action, "ok": ok, "text": text})
                elif action == "wait":
                    seconds = phase.args.get("seconds", 5)
                    await asyncio.sleep(seconds)
                    phase_results.append({"phase": i+1, "type": "os_call", "action": "wait", "seconds": seconds})
                else:
                    phase_results.append({"phase": i+1, "type": "os_call", "action": action, "error": "unknown action"})

            elif phase_type == "playwright":
                if pw_session is None:
                    pw_session = PlaywrightSession(headless=False)
                    await pw_session.start()
                    await pw_session.navigate(config["base_url"])
                    await pw_session.wait_for_flutter()

                action = phase.action
                result_data = {}

                if action == "set_offline":
                    await pw_session.set_offline(True)
                    result_data = {"offline": True}

                elif action == "set_online":
                    await pw_session.set_offline(False)
                    result_data = {"offline": False}

                elif action == "restart_session":
                    await pw_session.restart_session(config["base_url"])
                    await pw_session.wait_for_flutter(5.0)
                    result_data = {"restarted": True}

                elif action == "set_viewport":
                    w = phase.args.get("width", 1280)
                    h = phase.args.get("height", 800)
                    await pw_session.set_viewport(w, h)
                    await pw_session.wait_for_flutter(2.0)
                    result_data = {"viewport": f"{w}x{h}"}

                elif action == "screenshot":
                    path = phase.args.get("path", f"results/screenshots/{test.id}_phase{i}.png")
                    await pw_session.take_screenshot(path)
                    result_data = {"screenshot": path}

                elif action == "navigate":
                    base = config.get("base_url", "")
                    suffix = phase.args.get("url_suffix", "")
                    url = phase.args.get("url", base + suffix)
                    await pw_session.navigate(url)
                    await pw_session.wait_for_flutter()
                    result_data = {"navigated_to": url}

                elif action == "mock_clock":
                    from datetime import datetime as dt, timedelta
                    offset_hours = phase.args.get("offset_hours", 8760)
                    fake = dt.now() + timedelta(hours=offset_hours)
                    await pw_session.mock_clock(fake)
                    result_data = {"mocked_time": str(fake)}

                elif action == "reset_clock":
                    await pw_session.reset_clock()
                    result_data = {"clock_reset": True}

                elif action == "keyboard_audit":
                    audit = await pw_session.keyboard_navigation_audit(
                        max_tabs=phase.args.get("max_tabs", 100)
                    )
                    result_data = audit

                elif action == "accessibility_audit":
                    audit = await pw_session.accessibility_audit()
                    result_data = audit

                elif action == "capture_download":
                    dl = await pw_session.trigger_download_and_capture(
                        click_text=phase.args.get("click_text"),
                        click_selector=phase.args.get("click_selector"),
                    )
                    result_data = dl

                elif action == "read_clipboard":
                    text = await pw_session.read_clipboard()
                    result_data = {"clipboard": text}

                else:
                    result_data = {"error": f"Unknown playwright action: {action}"}

                phase_results.append({"phase": i+1, "type": "playwright", "action": action, **result_data})

            elif phase_type == "assert":
                prev = phase_results[-1] if phase_results else {}
                check_key = phase.args.get("key", "")
                check_value = phase.args.get("value")
                check_contains = phase.args.get("contains")
                actual = prev.get(check_key)

                passed = False
                if check_value is not None:
                    passed = actual == check_value
                elif check_contains is not None and isinstance(actual, str):
                    passed = check_contains in actual
                elif check_key == "ok":
                    passed = prev.get("ok", False) is True
                else:
                    passed = actual is not None

                phase_results.append({
                    "phase": i+1, "type": "assert",
                    "key": check_key, "expected": check_value or check_contains,
                    "actual": actual, "passed": passed,
                })
                if not passed:
                    return AttemptResult(
                        attempt=0, status="FAIL",
                        error=f"Assertion failed at phase {i+1}: {check_key}={actual!r}",
                        extracted_data={"phases": phase_results},
                        duration_seconds=round(time.monotonic() - start, 2),
                    )

        return AttemptResult(
            attempt=0, status="PASS",
            extracted_data={"phases": phase_results},
            duration_seconds=round(time.monotonic() - start, 2),
        )

    except Exception as exc:
        return AttemptResult(
            attempt=0, status="ERROR",
            error=f"{type(exc).__name__}: {exc}",
            extracted_data={"phases": phase_results},
            duration_seconds=round(time.monotonic() - start, 2),
        )
    finally:
        if pw_session:
            try:
                await pw_session.set_offline(False)
            except Exception:
                pass
            try:
                await pw_session.stop()
            except Exception:
                pass


async def run_test_with_retries(
    test: TestCase,
    config: dict,
    setup_prompt: Optional[str],
    monitor: OllamaMonitor,
    skyvern_url: str,
    single: bool = False,
) -> VotedResult:
    """Run a test with majority vote across multiple attempts."""
    is_critical = "critical" in test.tags
    num_attempts = 1 if single else (CRITICAL_RETRIES if is_critical else DEFAULT_RETRIES)
    timeout = test.timeout or config.get("timeout_per_test", 180)

    attempts: list[AttemptResult] = []

    for i in range(num_attempts):
        if not monitor.healthy:
            attempts.append(AttemptResult(
                attempt=i + 1,
                status="ERROR",
                error=f"Ollama unhealthy: {monitor.last_error}",
                duration_seconds=0.0,
            ))
            break

        logger.info(
            "  Attempt %d/%d for %s", i + 1, num_attempts, test.id
        )

        if test.is_composite:
            coro = execute_composite_attempt(test, config, setup_prompt, skyvern_url)
        else:
            coro = execute_single_attempt(test, config, setup_prompt, skyvern_url)
        try:
            result = await run_with_timeout(coro, timeout, test.id)
        except TestTimeoutError as exc:
            result = AttemptResult(
                attempt=i + 1,
                status="TIMEOUT",
                error=str(exc),
                duration_seconds=float(timeout),
            )

        result.attempt = i + 1
        attempts.append(result)

        if should_stop_early(attempts, num_attempts):
            logger.info("  Early exit for %s after %d attempts", test.id, len(attempts))
            break

    voted = majority_vote(
        attempts,
        test_id=test.id,
        test_name=test.name,
        tags=test.tags,
        expected=test.expected_result,
    )
    voted.manual_verification_note = test.manual_verification_note
    return voted


async def main(
    matrix_path: str,
    tag_filter: Optional[str] = None,
    single: bool = False,
    include_manual: bool = False,
    manual_only: bool = False,
    ollama_url: str = "http://localhost:11434",
    skyvern_url: str = "http://localhost:8000",
) -> int:
    matrix = load_matrix(matrix_path)
    config = matrix.get("config", {})
    setup_prompt = matrix.get("setup", {}).get("prompt")

    run = TestRun(
        base_url=config.get("base_url", ""),
        engine=config.get("default_engine", "skyvern-2.0"),
    )

    # -----------------------------------------------------------------------
    # Pre-flight
    # -----------------------------------------------------------------------
    if not manual_only:
        logger.info("Running pre-flight checks...")
        all_ok, checks = await run_preflight(
            config, ollama_url=ollama_url, skyvern_url=skyvern_url
        )
        for name, ok, msg in checks:
            status = "OK" if ok else "FAIL"
            logger.info("  [%s] %s: %s", status, name, msg)

        if not all_ok:
            logger.error("Pre-flight checks failed — aborting.")
            return 2

    # -----------------------------------------------------------------------
    # Automated tests
    # -----------------------------------------------------------------------
    if not manual_only:
        tests = parse_tests(matrix)
        if tag_filter:
            tests = [t for t in tests if tag_filter in t.tags]

        logger.info("Running %d automated test(s)...", len(tests))

        monitor = OllamaMonitor(ollama_url=ollama_url)
        await monitor.start()

        for i, test in enumerate(tests, 1):
            logger.info("[%d/%d] %s — %s", i, len(tests), test.id, test.name)
            voted = await run_test_with_retries(
                test, config, setup_prompt, monitor, skyvern_url, single
            )
            run.voted_results.append(voted)
            logger.info(
                "  Result: %s (confidence=%.0f%%)",
                voted.final_status,
                voted.confidence * 100,
            )

        await monitor.stop()

    # -----------------------------------------------------------------------
    # Interactive/manual tests
    # -----------------------------------------------------------------------
    if include_manual or manual_only:
        manual_path = Path(matrix_path).parent / "manual_companion.yaml"
        if manual_path.exists():
            manual_tests = load_manual_tests(str(manual_path))
            logger.info("Running %d interactive/manual test(s)...", len(manual_tests))
            manual_results = await run_interactive_batch(manual_tests, tag_filter)
            run.manual_results = manual_results
        else:
            logger.warning("manual_companion.yaml not found at %s", manual_path)

    # -----------------------------------------------------------------------
    # Results
    # -----------------------------------------------------------------------
    run.compute_summary()

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    run_dir = Path("results") / f"run_{timestamp}"
    run_dir.mkdir(parents=True, exist_ok=True)

    write_json_results(run, run_dir / "results.json")
    generate_html_report(run, run_dir / "report.html")

    logger.info("")
    logger.info("=" * 60)
    logger.info("  RESULTS SUMMARY")
    logger.info("=" * 60)
    logger.info("  Total: %d | Passed: %d | Failed: %d | Flaky: %d | Errors: %d | Skipped: %d",
                run.total, run.passed, run.failed, run.flaky, run.errors, run.skipped)
    logger.info("  Pass rate: %.1f%%", run.pass_rate)
    logger.info("  Duration: %.0fs", run.duration_seconds)
    logger.info("  Report:  %s", run_dir / "report.html")
    logger.info("  JSON:    %s", run_dir / "results.json")
    logger.info("=" * 60)

    if run.manual_results:
        manual_passed = sum(1 for m in run.manual_results if m.status == "PASS")
        manual_failed = sum(1 for m in run.manual_results if m.status == "FAIL")
        logger.info("  Manual: %d passed, %d failed, %d skipped",
                    manual_passed, manual_failed,
                    len(run.manual_results) - manual_passed - manual_failed)

    # Exit codes
    if run.failed > 0 or run.errors > 0:
        return 1
    elif run.flaky > 0:
        return 3
    return 0


def cli() -> None:
    parser = argparse.ArgumentParser(
        description="Gleec Wallet QA Automation Runner"
    )
    parser.add_argument(
        "--matrix",
        default="test_matrix.yaml",
        help="Path to test_matrix.yaml (default: test_matrix.yaml)",
    )
    parser.add_argument(
        "--tag",
        default=None,
        help="Filter tests by tag (e.g., smoke, critical, p0)",
    )
    parser.add_argument(
        "--single",
        action="store_true",
        help="Single attempt per test (no majority vote)",
    )
    parser.add_argument(
        "--include-manual",
        action="store_true",
        help="Include interactive/manual tests after automated suite",
    )
    parser.add_argument(
        "--manual-only",
        action="store_true",
        help="Run only manual/interactive tests (skip automated)",
    )
    parser.add_argument(
        "--ollama-url",
        default="http://localhost:11434",
        help="Ollama server URL",
    )
    parser.add_argument(
        "--skyvern-url",
        default="http://localhost:8000",
        help="Skyvern server URL",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable debug logging",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S",
    )

    exit_code = asyncio.run(main(
        matrix_path=args.matrix,
        tag_filter=args.tag,
        single=args.single,
        include_manual=args.include_manual,
        manual_only=args.manual_only,
        ollama_url=args.ollama_url,
        skyvern_url=args.skyvern_url,
    ))
    sys.exit(exit_code)


if __name__ == "__main__":
    cli()
