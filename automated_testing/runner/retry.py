"""Majority vote and retry logic for non-deterministic vision-based tests."""

from __future__ import annotations

from collections import Counter

from .models import AttemptResult, VotedResult


def majority_vote(attempts: list[AttemptResult], test_id: str, test_name: str,
                  tags: list[str], expected: str) -> VotedResult:
    """Determine final verdict from multiple attempts using majority vote.

    Rules:
    - If ALL attempts agree → that status, confidence 1.0
    - If majority agrees   → that status, confidence = majority/total
    - If no majority       → FLAKY, confidence = max_count/total
    - If all ERROR         → ERROR
    - If "winner" is ERROR but PASS/FAIL exist → FLAKY
    """
    statuses = [a.status for a in attempts]
    counts = Counter(statuses)
    total = len(attempts)

    if total == 0:
        return VotedResult(
            test_id=test_id,
            test_name=test_name,
            tags=tags,
            final_status="SKIP",
            vote_counts={},
            confidence=0.0,
            expected=expected,
            attempts=[],
        )

    most_common_status, most_common_count = counts.most_common(1)[0]

    if most_common_count > total / 2:
        final_status = most_common_status
        confidence = most_common_count / total
    else:
        final_status = "FLAKY"
        confidence = most_common_count / total

    if final_status == "ERROR":
        non_errors = [s for s in statuses if s != "ERROR"]
        if non_errors:
            final_status = "FLAKY"

    total_duration = sum(a.duration_seconds for a in attempts)

    return VotedResult(
        test_id=test_id,
        test_name=test_name,
        tags=tags,
        final_status=final_status,
        vote_counts=dict(counts),
        confidence=round(confidence, 2),
        expected=expected,
        attempts=attempts,
        duration_seconds=round(total_duration, 2),
    )


def should_stop_early(attempts: list[AttemptResult], max_attempts: int) -> bool:
    """Determine if remaining retries can be skipped.

    Early exit conditions:
    - First 2 attempts both PASS → skip remaining
    - All attempts so far are ERROR (infra issue) and at least 2 done → stop
    """
    if len(attempts) < 2:
        return False

    pass_count = sum(1 for a in attempts if a.status == "PASS")
    if pass_count >= 2:
        return True

    if all(a.status == "ERROR" for a in attempts):
        return True

    return False
