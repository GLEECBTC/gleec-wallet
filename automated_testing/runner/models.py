"""Pydantic data models for the Gleec QA test runner."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from pydantic import BaseModel, Field


class TestStep(BaseModel):
    action: str
    checkpoint: Optional[str] = None


class CompositePhase(BaseModel):
    """A single phase in a composite test that mixes Skyvern + OS/Playwright."""
    type: str  # skyvern | os_call | playwright | assert
    action: str = ""
    prompt: str = ""
    args: dict = Field(default_factory=dict)
    expected: Optional[str] = None
    checkpoint: Optional[str] = None
    extraction_schema: Optional[dict] = None
    max_steps: Optional[int] = None


class TestCase(BaseModel):
    id: str
    name: str
    tags: list[str] = Field(default_factory=list)
    prompt: str = ""
    steps: Optional[list[TestStep]] = None
    phases: Optional[list[CompositePhase]] = None
    expected_result: str = ""
    extraction_schema: Optional[dict] = None
    max_steps: Optional[int] = None
    timeout: Optional[int] = None
    source_manual_id: Optional[str] = None
    manual_verification_note: Optional[str] = None

    @property
    def is_composite(self) -> bool:
        return self.phases is not None and len(self.phases) > 0


class AttemptResult(BaseModel):
    attempt: int
    status: str  # PASS | FAIL | ERROR | TIMEOUT
    skyvern_status: str = ""
    extracted_data: Optional[dict | str] = None
    duration_seconds: float = 0.0
    run_id: Optional[str] = None
    error: Optional[str] = None
    screenshot_path: Optional[str] = None


class VotedResult(BaseModel):
    test_id: str
    test_name: str
    tags: list[str] = Field(default_factory=list)
    final_status: str  # PASS | FAIL | FLAKY | ERROR | SKIP
    vote_counts: dict[str, int] = Field(default_factory=dict)
    confidence: float = 0.0
    expected: str = ""
    manual_verification_note: Optional[str] = None
    attempts: list[AttemptResult] = Field(default_factory=list)
    duration_seconds: float = 0.0


class ManualResult(BaseModel):
    test_id: str
    title: str
    status: str  # PASS | FAIL | SKIP
    checklist_results: list[dict] = Field(default_factory=list)
    notes: str = ""


class TestRun(BaseModel):
    timestamp: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    base_url: str = ""
    engine: str = "skyvern-2.0"
    model: str = "qwen2.5-vl:32b"
    total: int = 0
    passed: int = 0
    failed: int = 0
    errors: int = 0
    skipped: int = 0
    flaky: int = 0
    pass_rate: float = 0.0
    duration_seconds: float = 0.0
    voted_results: list[VotedResult] = Field(default_factory=list)
    manual_results: list[ManualResult] = Field(default_factory=list)

    def compute_summary(self) -> None:
        self.total = len(self.voted_results)
        self.passed = sum(1 for r in self.voted_results if r.final_status == "PASS")
        self.failed = sum(1 for r in self.voted_results if r.final_status == "FAIL")
        self.errors = sum(1 for r in self.voted_results if r.final_status == "ERROR")
        self.skipped = sum(1 for r in self.voted_results if r.final_status == "SKIP")
        self.flaky = sum(1 for r in self.voted_results if r.final_status == "FLAKY")
        executed = self.passed + self.failed + self.flaky
        self.pass_rate = round(self.passed / executed * 100, 1) if executed > 0 else 0.0
        self.duration_seconds = sum(r.duration_seconds for r in self.voted_results)
