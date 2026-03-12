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
    - Any status has already reached the required majority for max_attempts
    - No status can still reach majority with remaining attempts
    """
    if not attempts:
        return False

    counts = Counter(a.status for a in attempts)
    majority = max_attempts // 2 + 1
    completed = len(attempts)
    remaining_attempts = max(0, max_attempts - completed)

    leading_count = counts.most_common(1)[0][1]
    if leading_count >= majority:
        return True

    # Even if all remaining attempts match the current leader, majority is impossible.
    if leading_count + remaining_attempts < majority:
        return True

    return False
