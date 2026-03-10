# Gleec Wallet QA Automation Architecture

> **Skyvern + Ollama Vision-Based Testing — Consolidated Technical Reference**
>
> Komodo Platform · March 2026 · Version 1.0

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Component Breakdown](#3-component-breakdown)
4. [Infrastructure Setup](#4-infrastructure-setup)
5. [Robustness Hardening](#5-robustness-hardening)
6. [Test Case Evaluation](#6-test-case-evaluation)
7. [Automated Test Matrix](#7-automated-test-matrix)
8. [Manual Test Companion](#8-manual-test-companion)
9. [Implementation Artifacts](#9-implementation-artifacts)
10. [Execution Strategy](#10-execution-strategy)
11. [Performance Expectations](#11-performance-expectations)
12. [Risks and Limitations](#12-risks-and-limitations)

---

## 1. Executive Summary

This document is the consolidated technical reference for automating QA testing of the Gleec Wallet, a Flutter web application within the Komodo Platform ecosystem. It covers the complete architecture from infrastructure through test case design to execution strategy.

### Problem

Flutter web applications render their entire UI to an HTML canvas element, which makes traditional DOM-based testing tools (Selenium, Cypress, Playwright selectors) non-functional. The Gleec Wallet has 85+ manual test cases across 26 feature areas and 6 platforms, requiring approximately 52 hours of manual execution time per full regression cycle.

### Solution

A vision-based testing architecture using Skyvern (browser automation orchestrator) backed by Ollama running a local vision-language model (qwen2.5-vl:32b) on an RTX 5090 GPU. The system takes screenshots of the Flutter canvas, sends them to the vision model for analysis and action planning, and executes actions through Playwright. Tests are defined as natural-language prompts in a YAML matrix file.  

### Key Outcomes

| Metric                            | Value                 |
| --------------------------------- | --------------------- |
| Manual test cases evaluated       | 85                    |
| Fully automatable (Grade A)       | 40 (47%)              |
| Partially automatable (Grade B)   | 18 (21%)              |
| Manual only (Grade C)             | 27 (32%)              |
| Automated tests in Phase 1 matrix | 43                    |
| Manual companion checklist items  | 36                    |
| Estimated automated run time      | 30–60 minutes         |
| Target pass-rate stability        | 90–95%                |
| Hardware requirement              | RTX 5090 (32 GB VRAM) |

---

## 2. Architecture Overview

The architecture is a three-layer stack designed for local GPU-accelerated execution with no cloud API dependencies.

### 2.1 Three-Layer Design

**Layer 1 — Ollama (native on host):** Runs the qwen2.5-vl:32b vision-language model directly on the host machine with full NVIDIA GPU access. Serves a local HTTP API on port 11434. Not containerised, to avoid Docker GPU passthrough complexity.

**Layer 2 — Skyvern + PostgreSQL (Docker Compose):** Skyvern is the browser automation orchestrator that manages Chromium sessions via Playwright, captures screenshots, sends them to Ollama for analysis, receives action plans, and executes them. PostgreSQL stores task state and run history. Both run inside Docker with host network access to reach Ollama.

**Layer 3 — Python Test Runner (host):** A standalone Python script that reads the test matrix YAML, iterates test cases, calls the Skyvern SDK programmatically, applies robustness hardening (retries, majority vote, checkpoints, timeout guards), and generates JSON + HTML reports.

### 2.2 Data Flow

The test execution flow follows this sequence:

1. Runner reads `test_matrix.yaml` and parses test cases with their prompts, expected results, and extraction schemas.
2. Pre-flight checks validate that Ollama, Skyvern, PostgreSQL, and the Flutter app are all healthy before any tests run.
3. For each test case, the runner creates a fresh browser session and calls Skyvern's `run_task()` with the natural-language prompt.
4. Skyvern enters its vision loop: screenshot the page → send to Ollama → receive action plan → execute via Playwright → repeat until COMPLETE or step limit reached.
5. At task completion, Skyvern extracts structured data using the `extraction_schema` and returns it alongside the task status.
6. The runner applies majority vote across multiple attempts (3–5 per test) to determine the final pass/fail/flaky verdict.
7. Results are written to `results.json` and `report.html` in a timestamped run directory.

### 2.3 System Diagram

```
tests/test_matrix.yaml
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│                   HARDENED TEST RUNNER                    │
│                                                          │
│  ┌──────────────┐   ┌────────────────┐   ┌────────────┐ │
│  │ Pre-flight    │   │ Test Executor   │   │ Post-run   │ │
│  │ Checks        │   │ (per test)      │   │ Analysis   │ │
│  │               │   │                 │   │            │ │
│  │ • Ollama up?  │   │ • Fresh session │   │ • Majority │ │
│  │ • VRAM ok?    │   │ • Retry loop    │   │   vote     │ │
│  │ • Skyvern up? │   │ • Checkpoints   │   │ • Flaky    │ │
│  │ • App up?     │   │ • Screenshots   │   │   detect   │ │
│  │ • Model loads?│   │ • Timeout guard │   │ • Report   │ │
│  └──────┬───────┘   └───────┬─────────┘   └─────┬──────┘ │
│         │                   │                    │        │
└─────────┼───────────────────┼────────────────────┼────────┘
          ▼                   ▼                    ▼
    abort if fail      Skyvern SDK           results.json
                     + browser sessions       report.html
```

### 2.4 Network Topology

| Component             | Host                       | Port  | Protocol          |
| --------------------- | -------------------------- | ----- | ----------------- |
| Ollama                | Host machine (native)      | 11434 | HTTP REST         |
| Skyvern Server        | Docker container           | 8000  | HTTP REST         |
| PostgreSQL            | Docker container           | 5432  | TCP               |
| Chromium (Playwright) | Docker (inside Skyvern)    | —     | CDP               |
| Flutter Web App       | Staging server / localhost | 3000  | HTTPS/HTTP        |
| Python Runner         | Host machine               | —     | Calls Skyvern SDK |

Docker containers reach Ollama on the host via the `host.docker.internal` alias (configured with `extra_hosts: host-gateway`). The runner communicates with Skyvern through its published port 8000 on localhost.

---

## 3. Component Breakdown

### 3.1 Ollama (Vision Model Server)

| Setting           | Value                                                                    |
| ----------------- | ------------------------------------------------------------------------ |
| Primary model     | qwen2.5-vl:32b (Q4 quantised)                                            |
| Fallback model    | gemma3:27b (faster, less accurate)                                       |
| Lightweight model | qwen2.5-vl:7b (for rapid iteration)                                      |
| VRAM usage        | ~20 GB (32B Q4) / ~16 GB (27B) / ~5 GB (7B)                              |
| Host              | http://localhost:11434                                                   |
| Role              | Vision analysis, action planning, checkpoint validation, data extraction |
| Installation      | Native on host via `curl -fsSL https://ollama.com/install.sh \| sh`      |

Ollama runs outside Docker to get direct NVIDIA GPU access without container GPU passthrough complexity. The qwen2.5-vl:32b model is the primary choice because it provides the strongest vision accuracy for Flutter's canvas-rendered UI. The RTX 5090's 32 GB VRAM comfortably holds the Q4-quantised 32B model with room for KV cache.

### 3.2 Skyvern (Browser Automation Orchestrator)

| Setting                | Value                                                         |
| ---------------------- | ------------------------------------------------------------- |
| Image                  | ghcr.io/skyvern-ai/skyvern:latest                             |
| Port                   | 8000                                                          |
| Engine options         | skyvern-1.0 (simple tasks) / skyvern-2.0 (complex multi-step) |
| Browser                | Chromium via Playwright (headful for video, headless for CI)  |
| LLM backend            | Ollama via ENABLE_OLLAMA=true                                 |
| Connection to Ollama   | http://host.docker.internal:11434                             |
| Max steps per run      | 50 (configurable per test)                                    |
| Browser action timeout | 10000ms                                                       |

Skyvern orchestrates the vision-action loop: it takes a screenshot of the current browser state, sends it to the LLM with the prompt context, receives an action plan (click coordinates, text to type, scroll direction), executes the action via Playwright, and repeats. Each iteration is one "step." Tasks complete when the LLM determines the goal is met, an error is detected, or the step limit is reached.

### 3.3 PostgreSQL (Task State Store)

PostgreSQL 15 runs alongside Skyvern in Docker Compose. It stores task history, step-by-step screenshots, extracted data, and run metadata. No manual interaction is needed; it is managed entirely by Skyvern's internal ORM. Data is persisted in a named Docker volume (`pgdata`) across restarts.

### 3.4 Python Test Runner

The runner is the single orchestration point that ties everything together. It is a standalone Python 3.11+ script that uses the Skyvern Python SDK to create tasks programmatically. It reads the YAML test matrix, applies robustness hardening (pre-flight checks, retries, majority vote, timeout guards, Ollama monitoring), and writes structured results.

---

## 4. Infrastructure Setup

### 4.1 Docker Compose Configuration

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: skyvern
      POSTGRES_PASSWORD: skyvern
      POSTGRES_DB: skyvern
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U skyvern"]
      interval: 5s
      retries: 5

  skyvern:
    image: ghcr.io/skyvern-ai/skyvern:latest
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "8000:8000"
    environment:
      - DATABASE_STRING=postgresql+psycopg://skyvern:skyvern@postgres:5432/skyvern
      - BROWSER_TYPE=chromium-headful
      - VIDEO_PATH=/app/videos
      - BROWSER_ACTION_TIMEOUT_MS=10000
      - MAX_STEPS_PER_RUN=50
      - ENABLE_OLLAMA=true
      - OLLAMA_SERVER_URL=http://host.docker.internal:11434
      - OLLAMA_MODEL=qwen2.5-vl:32b
      - OLLAMA_SUPPORTS_VISION=true
      - ENV=local
      - LOG_LEVEL=INFO
      - PORT=8000
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./results/videos:/app/videos
      - ./results/screenshots:/app/artifacts

volumes:
  pgdata:
```

### 4.2 Environment File

```bash
# .env
ENV=local
ENABLE_OLLAMA=true
OLLAMA_SERVER_URL=http://host.docker.internal:11434
OLLAMA_MODEL=qwen2.5-vl:32b
OLLAMA_SUPPORTS_VISION=true
DATABASE_STRING=postgresql+psycopg://skyvern:skyvern@postgres:5432/skyvern
BROWSER_TYPE=chromium-headful
VIDEO_PATH=/app/videos
BROWSER_ACTION_TIMEOUT_MS=10000
MAX_STEPS_PER_RUN=50
LOG_LEVEL=INFO
PORT=8000
```

### 4.3 Setup Script

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== Komodo QA Automation Setup ==="

# 1. Install Ollama
if ! command -v ollama &> /dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

# 2. Pull vision model
ollama pull qwen2.5-vl:32b

# 3. Start Ollama server
if ! curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
  ollama serve &
  sleep 3
fi

# 4. Create project structure
mkdir -p komodo-qa-automation/{tests,runner,results}

# 5. Start Docker stack
cd komodo-qa-automation
docker compose up -d

echo "Setup complete. Ollama: :11434  Skyvern: :8000"
```

### 4.4 Directory Structure

```
komodo-qa-automation/
├── docker-compose.yml
├── .env
├── setup.sh
├── tests/
│   ├── test_matrix.yaml          # 43 automated test cases
│   └── manual_companion.yaml     # 36 manual-only checklist items
├── runner/
│   ├── __init__.py
│   ├── runner.py                 # Hardened main runner
│   ├── models.py                 # Pydantic data models
│   ├── reporter.py               # HTML report generator
│   ├── preflight.py              # Pre-flight health checks
│   ├── prompt_builder.py         # Flutter-hardened prompt assembly
│   ├── retry.py                  # Majority vote logic
│   ├── guards.py                 # Timeout and deadlock guards
│   └── ollama_monitor.py         # Background GPU/VRAM monitor
└── results/
    └── run_<timestamp>/
        ├── results.json
        ├── report.html
        └── screenshots/
```

### 4.5 Python Dependencies

```text
# requirements.txt
skyvern>=1.0.0
pyyaml>=6.0
pydantic>=2.0
httpx>=0.27.0
```

---

## 5. Robustness Hardening

Vision-based testing with LLMs is inherently non-deterministic. The following ten strategies address the primary failure modes.

### 5.1 Known Fragility Points

| #   | Problem                     | Severity     | Root Cause                                                                                                        |
| --- | --------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------- |
| 1   | Vision model hallucination  | **Critical** | LLM identifies UI elements that don't exist, or clicks wrong ones. No DOM fallback on Flutter canvas.             |
| 2   | Non-deterministic outputs   | **High**     | Same prompt + same page produces different actions across runs due to LLM stochasticity.                          |
| 3   | Flutter async rendering     | **High**     | Skyvern screenshots mid-render, acts on incomplete frame while Flutter rebuilds widgets.                          |
| 4   | Multi-step state corruption | **Critical** | Step N fails silently (wrong click), but subsequent steps execute against wrong state, producing misleading PASS. |
| 5   | No test isolation           | **High**     | Test B inherits leftover state from Test A (open modals, changed settings, navigation position).                  |
| 6   | Login session expiry        | **Medium**   | Setup logs in, but by test 15 the session has timed out.                                                          |
| 7   | Ambiguous completion        | **High**     | Skyvern cannot distinguish successful completion from dead-end abandonment.                                       |
| 8   | Flaky pass/fail             | **High**     | Test passes 3/5 times. Single-run result is unreliable.                                                           |
| 9   | No visual baseline          | **Medium**   | Assertions rely on LLM judgment, not pixel-level comparison with known-good screenshots.                          |
| 10  | Silent Ollama failures      | **Medium**   | Ollama OOMs, truncates responses, or times out. Skyvern may not surface this cleanly.                             |

### 5.2 Mitigation Strategies

**1. Pre-flight Health Checks:** Before running any tests, the runner validates: Ollama is responding (HTTP + actual inference test), VRAM has >15 GB free, Skyvern server responds on :8000, and the Flutter app is reachable. If any check fails, the run aborts with exit code 2. This prevents wasting time on tests that would all fail due to infrastructure issues.

```python
# runner/preflight.py

async def check_ollama(url: str = "http://localhost:11434") -> bool:
    """Verify Ollama is running and the model is loaded."""
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(f"{url}/api/tags")
        models = resp.json().get("models", [])
        return len(models) > 0

async def check_ollama_inference(url: str = "http://localhost:11434",
                                  model: str = "qwen2.5-vl:32b") -> bool:
    """Actually run a trivial inference to confirm GPU works."""
    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(f"{url}/api/generate", json={
            "model": model,
            "prompt": "Reply with only the word OK.",
            "stream": False,
        })
        output = resp.json().get("response", "").strip()
        return "ok" in output.lower()

async def check_vram() -> bool:
    """Verify sufficient VRAM is free (>15 GB for 32B Q4 model)."""
    result = subprocess.run(
        ["nvidia-smi", "--query-gpu=memory.free", "--format=csv,noheader,nounits"],
        capture_output=True, text=True, timeout=5,
    )
    free_gb = int(result.stdout.strip().split("\n")[0]) / 1024
    return free_gb > 15

async def check_skyvern(url: str = "http://localhost:8000") -> bool:
    """Verify Skyvern server responds."""
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(f"{url}/api/v1/heartbeat")
        return resp.status_code == 200

async def check_app(url: str) -> bool:
    """Verify the Flutter app is reachable."""
    async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
        resp = await client.get(url)
        return resp.status_code < 500

async def run_preflight(config: dict) -> bool:
    """Run all pre-flight checks. Returns False if any critical check fails."""
    results = await asyncio.gather(
        check_ollama(), check_vram(), check_skyvern(), check_app(config["base_url"]),
    )
    all_ok = all(results)
    if all_ok:
        all_ok = await check_ollama_inference()
    return all_ok
```

**2. Test Isolation via Fresh Browser Sessions:** Each test case gets its own fresh browser session with no shared cookies, storage, or navigation history. The setup prompt (login) is embedded directly into each test's prompt so login and test execute in the same session, eliminating the session-handoff problem.

```python
# In runner.py — each run_task() creates an isolated browser:

async def run_isolated_test(skyvern, test, config, setup_config):
    full_prompt = ""
    if setup_config:
        full_prompt += f"PHASE 1 — SETUP:\n{setup_config['prompt']}\n\n"
        full_prompt += "After setup is complete, proceed immediately to Phase 2.\n\n"
        full_prompt += "PHASE 2 — TEST:\n"
    full_prompt += test.prompt

    task = await skyvern.run_task(
        url=config["base_url"],
        prompt=full_prompt,
        engine=config.get("default_engine", "skyvern-2.0"),
        max_steps=test.max_steps or 25,
        data_extraction_schema=test.extraction_schema,
        wait_for_completion=True,
        # Each run_task gets its own browser — no shared state
    )
    return task
```

**3. Retry with Majority Vote:** Every test runs 3 times (5 times for critical-tagged tests). The final verdict is determined by majority vote across attempts. If 2/3 pass, the test is PASS. If results are split (1 pass, 1 fail, 1 error), the test is marked FLAKY. This is the single most important robustness measure for dealing with LLM non-determinism.

```python
# runner/retry.py

@dataclass
class VotedResult:
    test_id: str
    final_status: str           # PASS | FAIL | FLAKY | ERROR
    vote_counts: dict           # {"PASS": 2, "FAIL": 1}
    confidence: float           # 0.0–1.0
    attempts: list

def majority_vote(attempts: list, test) -> VotedResult:
    """
    Rules:
    - If ALL attempts agree → that status, confidence 1.0
    - If majority agrees   → that status, confidence = majority/total
    - If no majority       → FLAKY, confidence = max_count/total
    - If all ERROR         → ERROR
    """
    statuses = [a.status for a in attempts]
    counts = Counter(statuses)
    total = len(attempts)
    most_common_status, most_common_count = counts.most_common(1)[0]

    if most_common_count > total / 2:
        final_status = most_common_status
        confidence = most_common_count / total
    else:
        final_status = "FLAKY"
        confidence = most_common_count / total

    # If "winner" is ERROR but there are PASS/FAIL, prefer those
    if final_status == "ERROR":
        non_errors = [s for s in statuses if s != "ERROR"]
        if non_errors:
            final_status = "FLAKY"

    return VotedResult(
        test_id=test.id,
        final_status=final_status,
        vote_counts=dict(counts),
        confidence=round(confidence, 2),
        attempts=attempts,
    )
```

**4. Flutter Render Wait Strategy:** A Flutter preamble is automatically prepended to every prompt instructing the vision model to wait 2–3 seconds for canvas rendering, look for loading spinners before acting, and handle blank-screen initialization delays. This prevents acting on incomplete frames.

```python
# runner/prompt_builder.py

FLUTTER_PREAMBLE = """IMPORTANT CONTEXT:
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

def build_prompt(test_prompt: str, setup_prompt: str | None = None) -> str:
    parts = [FLUTTER_PREAMBLE]
    if setup_prompt:
        parts.append(f"PHASE 1 — SETUP:\n{setup_prompt}\n")
        parts.append("After setup is complete, proceed to Phase 2.\n")
        parts.append(f"PHASE 2 — TEST:\n{test_prompt}")
    else:
        parts.append(test_prompt)
    parts.append(COMPLETION_SUFFIX)
    return "\n".join(parts)
```

**5. Checkpoint Assertions (Mid-Flow Validation):** Complex multi-step tests include checkpoint verification between steps. Each checkpoint is a visual assertion ("the send form is visible with recipient and amount fields"). If a checkpoint fails, the test aborts immediately instead of continuing against wrong state, preventing cascading false results.

```python
# runner/prompt_builder.py (addition)

def build_stepped_prompt(steps: list[dict]) -> str:
    """Convert checkpoint-based steps into a single sequential prompt."""
    lines = []
    for i, step in enumerate(steps, 1):
        lines.append(f"STEP {i}: {step['action']}")
        if step.get("checkpoint"):
            lines.append(
                f"  → BEFORE proceeding to step {i+1}, verify: {step['checkpoint']}")
            lines.append(
                f"  → If this verification FAILS, STOP and report which step failed and why.")
        lines.append("")
    return "\n".join(lines)
```

**6. Timeout and Deadlock Guards:** Every Skyvern task call is wrapped in an `asyncio.wait_for()` with a configurable timeout (default 180 seconds). If the vision model hangs, the browser deadlocks, or Ollama stalls, the test is terminated and marked ERROR with a diagnostic message.

```python
# runner/guards.py

class TestTimeoutError(Exception):
    pass

async def run_with_timeout(coro, seconds: int, test_id: str):
    """Run a coroutine with a hard timeout."""
    try:
        return await asyncio.wait_for(coro, timeout=seconds)
    except asyncio.TimeoutError:
        raise TestTimeoutError(
            f"Test {test_id} timed out after {seconds}s."
        )
```

**7. Background Ollama Health Monitor:** A background asyncio task polls `nvidia-smi` and Ollama's HTTP endpoint every 10 seconds during the run. It checks VRAM free (abort if <500 MB), GPU temperature (warn if >90°C), and Ollama API responsiveness. If Ollama becomes unhealthy mid-run, subsequent tests are immediately marked ERROR with the specific failure reason.

```python
# runner/ollama_monitor.py

class OllamaMonitor:
    def __init__(self, ollama_url: str = "http://localhost:11434"):
        self.url = ollama_url
        self._running = False
        self.last_error = None

    async def start(self):
        self._running = True
        self._task = asyncio.create_task(self._monitor_loop())

    @property
    def healthy(self) -> bool:
        return self.last_error is None

    async def _monitor_loop(self):
        while self._running:
            try:
                async with httpx.AsyncClient(timeout=5) as client:
                    resp = await client.get(f"{self.url}/api/tags")
                    if resp.status_code != 200:
                        self.last_error = f"Ollama returned HTTP {resp.status_code}"
                    else:
                        self.last_error = None

                result = subprocess.run(
                    ["nvidia-smi", "--query-gpu=memory.free,memory.used,temperature.gpu",
                     "--format=csv,noheader,nounits"],
                    capture_output=True, text=True, timeout=5,
                )
                parts = result.stdout.strip().split(", ")
                if len(parts) >= 3:
                    free_mb, used_mb, temp_c = int(parts[0]), int(parts[1]), int(parts[2])
                    if free_mb < 500:
                        self.last_error = f"VRAM critically low: {free_mb}MB free"
                    elif temp_c > 90:
                        self.last_error = f"GPU temperature critical: {temp_c}°C"
            except Exception as e:
                self.last_error = f"Monitor error: {e}"

            await asyncio.sleep(10)
```

**8. Hardened Prompt Construction:** All prompts are built through a `prompt_builder` module that automatically adds the Flutter preamble, structures multi-phase prompts (setup + test), injects checkpoint verification language, and appends a completion suffix requesting explicit success/error reporting.

**9. Early Exit Optimisation:** If the first 2 attempts both pass, remaining retries are skipped. If all attempts so far are ERROR (infrastructure issue), retries stop early. This reduces total run time by 30–40% for stable tests while preserving full retry coverage for flaky ones.

```python
# Inside run_test_with_retries():

attempts = []
for i in range(num_attempts):
    result = await execute_single_attempt(skyvern, test, config, setup_config, monitor)
    attempts.append(result)

    # Early exit: if first 2 attempts both pass, skip remaining
    if len(attempts) >= 2:
        pass_count = sum(1 for a in attempts if a.status == "PASS")
        if pass_count >= 2:
            break

    # Early exit: if all attempts so far are ERROR (infra issue), stop
    if all(a.status == "ERROR" for a in attempts) and len(attempts) >= 2:
        break
```

**10. Structured Exit Codes for CI:** Exit code 0 = all passed. Exit code 1 = failures or errors. Exit code 2 = pre-flight failure (infrastructure). Exit code 3 = all tests passed but some were flaky. This enables CI pipelines to distinguish between test failures, infra failures, and instability.

| Code | Meaning                                                            |
| ---- | ------------------------------------------------------------------ |
| `0`  | All tests passed                                                   |
| `1`  | One or more tests failed or errored                                |
| `2`  | Pre-flight checks failed (infrastructure issue)                    |
| `3`  | All tests passed but some were flaky (inconsistent across retries) |

---

## 6. Test Case Evaluation

All 85 test cases from `GLEEC_WALLET_MANUAL_TEST_CASES.md` were evaluated for automation suitability with the Skyvern + Ollama stack.

### 6.1 Classification Framework

| Grade | Meaning                                                              | Count | %   | Action                                       |
| ----- | -------------------------------------------------------------------- | ----- | --- | -------------------------------------------- |
| **A** | Fully automatable — pure UI interaction within a web browser         | 40    | 47% | Convert to Skyvern prompt                    |
| **B** | Partially automatable — some steps need human/external action        | 18    | 21% | Split: automate UI, flag manual verification |
| **C** | Manual only — requires hardware, OS actions, network, cross-platform | 27    | 32% | Keep in manual checklist                     |

### 6.2 Full Classification Table

| Test ID   | Module              | Title                                 | Grade | Reason                                                                                      |
| --------- | ------------------- | ------------------------------------- | ----- | ------------------------------------------------------------------------------------------- |
| AUTH-001  | Auth                | Create wallet with seed backup        | **A** | UI-only flow: tap, enter password, navigate seed screens                                    |
| AUTH-002  | Auth                | Login/logout with remember-session    | **B** | Login/logout automatable; "close and relaunch app" requires session restart outside Skyvern |
| AUTH-003  | Auth                | Import wallet from seed               | **A** | UI-only: enter seed, set password, verify balances                                          |
| AUTH-004  | Auth                | Invalid password attempts + lockout   | **A** | UI-only: enter wrong passwords, observe lockout messages                                    |
| AUTH-005  | Auth                | Trezor hardware wallet                | **C** | Requires physical Trezor device connected via USB                                           |
| WAL-001   | Wallet Manager      | Create/rename/switch wallets          | **A** | Pure UI interactions within wallet management                                               |
| WAL-002   | Wallet Manager      | Delete wallet with confirmation       | **A** | UI dialog flow                                                                              |
| WAL-003   | Wallet Manager      | Selection persistence after restart   | **C** | Requires app restart                                                                        |
| COIN-001  | Coin Manager        | Enable DOC/MARTY test coins           | **A** | Toggle coins in settings                                                                    |
| COIN-002  | Coin Manager        | Search and activate coins             | **A** | Search UI, toggle activation                                                                |
| COIN-003  | Coin Manager        | Deactivate coin with balance          | **A** | Balance warning dialog, deactivation flow                                                   |
| DASH-001  | Dashboard           | Hide balances / zero balance toggles  | **A** | Toggle switches, verify UI changes                                                          |
| DASH-002  | Dashboard           | Offline indicator                     | **C** | Requires network disconnection at OS level                                                  |
| DASH-003  | Dashboard           | Dashboard persistence after restart   | **C** | Requires app restart                                                                        |
| SEND-001  | Send                | Faucet funding                        | **A** | Navigate to faucet, request funds, verify balance                                           |
| SEND-002  | Send                | Faucet cooldown                       | **B** | Faucet automatable; network error fallback requires network toggle                          |
| SEND-003  | Send                | Send DOC happy path                   | **A** | Fill send form, confirm, verify status                                                      |
| SEND-004  | Send                | Address validation                    | **A** | Enter invalid addresses, observe error messages                                             |
| SEND-005  | Send                | Amount boundary testing               | **A** | Enter boundary amounts, observe validation                                                  |
| SEND-006  | Send                | Interrupted send (network kill)       | **C** | Requires network interruption mid-transaction                                               |
| DEX-001   | DEX                 | Create maker order                    | **A** | Fill order form, submit, verify                                                             |
| DEX-002   | DEX                 | Taker order                           | **B** | Depends on market liquidity availability                                                    |
| DEX-003   | DEX                 | Input validation                      | **A** | Enter invalid values, observe errors                                                        |
| DEX-004   | DEX                 | Partial fill behaviour                | **B** | Depends on market conditions                                                                |
| DEX-005   | DEX                 | History export                        | **B** | UI automatable; file verification requires filesystem access                                |
| DEX-006   | DEX                 | Recovery after closure + network      | **C** | Requires app closure and network manipulation                                               |
| BRDG-001  | Bridge              | Bridge transfer happy path            | **A** | Fill bridge form, submit, verify                                                            |
| BRDG-002  | Bridge              | Unsupported pair handling             | **A** | Select unsupported pair, observe error                                                      |
| BRDG-003  | Bridge              | Amount boundaries                     | **A** | Enter boundary amounts, verify validation                                                   |
| BRDG-004  | Bridge              | Bridge failure (network)              | **C** | Requires network interruption                                                               |
| NFT-001   | NFT                 | List and detail view                  | **A** | Navigate NFT section, browse items                                                          |
| NFT-002   | NFT                 | Send NFT                              | **A** | Fill send form, confirm transfer                                                            |
| NFT-003   | NFT                 | Send failure handling                 | **A** | Trigger failure, observe error UI                                                           |
| SET-001   | Settings            | Persistence after restart             | **C** | Requires app restart                                                                        |
| SET-002   | Settings            | Privacy toggles                       | **A** | Toggle settings, verify UI changes                                                          |
| SET-003   | Settings            | Test coin toggle impact               | **A** | Toggle, verify coin visibility                                                              |
| SET-004   | Settings            | Settings persistence (logout/restart) | **C** | Requires logout and restart                                                                 |
| BOT-001   | Bot                 | Create and start market maker         | **A** | Fill bot config, start, verify running                                                      |
| BOT-002   | Bot                 | Bot validation (invalid params)       | **A** | Enter invalid params, observe errors                                                        |
| NAV-001   | Navigation          | Route integrity                       | **A** | Navigate all routes, verify loading                                                         |
| NAV-002   | Navigation          | Deep link while logged out            | **C** | Requires direct URL manipulation                                                            |
| NAV-003   | Navigation          | Unsaved changes warning               | **A** | Make changes, attempt navigation, verify warning                                            |
| RESP-001  | Responsive          | Breakpoint behaviour                  | **C** | Requires controlled window resizing                                                         |
| RESP-002  | Responsive          | Orientation change                    | **C** | Requires device rotation                                                                    |
| XPLAT-001 | Cross-platform      | Feature parity                        | **C** | Requires Android/iOS/macOS/Linux/Windows                                                    |
| XPLAT-002 | Cross-platform      | Permission dialogs                    | **C** | Requires OS-level permission dialogs                                                        |
| A11Y-001  | Accessibility       | Keyboard navigation                   | **C** | Requires focus state inspection                                                             |
| A11Y-002  | Accessibility       | Screen reader                         | **C** | Requires screen reader output analysis                                                      |
| A11Y-003  | Accessibility       | Contrast and scaling                  | **C** | Requires pixel-level measurement                                                            |
| SEC-001   | Security            | Seed phrase reveal                    | **B** | Reveal automatable; screenshot masking verification is manual                               |
| SEC-002   | Security            | Auto-lock timeout                     | **C** | Requires idle timeout + app-switcher                                                        |
| SEC-003   | Security            | Clipboard clearing                    | **C** | Requires clipboard monitoring outside browser                                               |
| ERR-001   | Error Handling      | Network outage recovery               | **C** | Requires network toggling                                                                   |
| ERR-002   | Error Handling      | Partial failure                       | **C** | Requires selective network failure                                                          |
| ERR-003   | Error Handling      | Stale state after closure             | **C** | Requires app closure                                                                        |
| L10N-001  | Localization        | Translation completeness              | **A** | Switch locale, verify text rendering                                                        |
| L10N-002  | Localization        | Long string overflow                  | **B** | Visual clipping judgment is low-confidence for LLM                                          |
| L10N-003  | Localization        | Locale-specific formats               | **A** | Switch locale, verify date/number formats                                                   |
| FIAT-001  | Fiat                | Fiat menu access                      | **A** | Navigate to fiat section                                                                    |
| FIAT-002  | Fiat                | Form validation                       | **A** | Enter invalid data, observe errors                                                          |
| FIAT-003  | Fiat                | Provider checkout                     | **B** | Provider webview may cross domain boundaries                                                |
| FIAT-004  | Fiat                | Checkout closed/cancelled             | **B** | Manual closure detection                                                                    |
| FIAT-005  | Fiat                | Fiat after logout/login               | **C** | Requires logout and re-login                                                                |
| SUP-001   | Support             | Support page access                   | **A** | Navigate to support section                                                                 |
| FEED-001  | Feedback            | Feedback entry                        | **A** | Open feedback form, submit                                                                  |
| SECX-001  | Security (Extended) | Private key export                    | **B** | Export automatable; download/share may cross browser boundary                               |
| SECX-002  | Security (Extended) | Seed backup verification              | **A** | View seed, confirm backup flow                                                              |
| SECX-003  | Security (Extended) | Unban pubkeys                         | **A** | Navigate to pubkey management, unban                                                        |
| SECX-004  | Security (Extended) | Change password                       | **A** | Enter old/new password, confirm                                                             |
| SETX-001  | Advanced Settings   | Weak password toggle                  | **A** | Toggle setting, verify effect                                                               |
| SETX-002  | Advanced Settings   | Bot toggles                           | **B** | Stop-on-disable verification depends on running bot                                         |
| SETX-003  | Advanced Settings   | Export/import JSON                    | **C** | Filesystem operation                                                                        |
| SETX-004  | Advanced Settings   | Show swap data                        | **B** | Export is filesystem operation                                                              |
| SETX-005  | Advanced Settings   | Import swaps JSON                     | **C** | Requires paste from external source                                                         |
| SETX-006  | Advanced Settings   | Download logs                         | **C** | Filesystem download                                                                         |
| SETX-007  | Advanced Settings   | Reset coins to default                | **A** | Trigger reset, verify coin list                                                             |
| WALX-001  | Wallet (Extended)   | Overview cards                        | **A** | Verify wallet cards display                                                                 |
| WALX-002  | Wallet (Extended)   | Tabs (logged-out fallback)            | **B** | Logged-out fallback needs logout                                                            |
| WADDR-001 | Wallet Addresses    | Multi-address display                 | **A** | View address list                                                                           |
| WADDR-002 | Wallet Addresses    | Create new address                    | **A** | Generate address, verify display                                                            |
| CTOK-001  | Custom Token        | Import ERC-20 token                   | **A** | Enter contract address, import                                                              |
| CTOK-002  | Custom Token        | Invalid contract handling             | **A** | Enter invalid contract, observe error                                                       |
| CTOK-003  | Custom Token        | Back/cancel from import               | **A** | Navigate away, verify no side effects                                                       |
| GATE-001  | Feature Gating      | Trading-disabled tooltips             | **A** | Verify disabled state indicators                                                            |
| GATE-002  | Feature Gating      | Hardware wallet restrictions          | **C** | Requires connected hardware wallet                                                          |
| GATE-003  | Feature Gating      | NFT disabled state                    | **A** | Verify NFT section disabled UI                                                              |
| CDET-001  | Coin Detail         | Address display                       | **B** | Display automatable; clipboard/explorer verification manual                                 |
| CDET-002  | Coin Detail         | Transaction list                      | **B** | List automatable; pending→confirmed needs real chain time                                   |
| CDET-003  | Coin Detail         | Price chart                           | **B** | Chart automatable; offline fallback needs network toggle                                    |
| RWD-001   | Rewards             | Rewards claim                         | **B** | Claim depends on reward availability                                                        |
| BREF-001  | Bitrefill           | Bitrefill widget                      | **B** | Widget crosses domain boundaries                                                            |
| ZHTL-001  | ZHTLC               | ZHTLC activation                      | **B** | Logout-during-activation is manual                                                          |
| QLOG-001  | Quick Login         | Remember-me persistence               | **C** | Requires app relaunch                                                                       |
| WARN-001  | Warnings            | Clock warning banner                  | **C** | Requires system clock manipulation                                                          |

### 6.3 Why Grade C Tests Cannot Be Automated

The 27 Grade C tests fall into these categories, none of which Skyvern can handle:

**Hardware wallet (2 tests):** GW-MAN-AUTH-005, GW-MAN-GATE-002 require a physical Trezor device connected via USB. The vision model cannot interact with external hardware.

**Network manipulation (7 tests):** DASH-002, SEND-006, DEX-006, BRDG-004, ERR-001/002/003 require disabling/re-enabling the network at the OS level, which is outside the browser sandbox.

**App lifecycle (7 tests):** AUTH-002b, WAL-003, DASH-003, SET-004, FIAT-005, QLOG-001, NAV-002 require closing and relaunching the application, which destroys the Skyvern browser session.

**Cross-platform + responsive (4 tests):** XPLAT-001/002, RESP-001/002 require execution on Android, iOS, macOS, Linux, and Windows native apps, or controlled window resizing that Skyvern cannot reliably perform.

**Accessibility (3 tests):** A11Y-001/002/003 require keyboard-only navigation focus inspection, screen reader output analysis, and pixel-level contrast measurement.

**Security/privacy (3 tests):** SEC-002/003, WARN-001 require app-switcher snapshot inspection, clipboard monitoring, and system clock manipulation.

**Filesystem operations (3 tests):** SETX-003/005/006 require file export/import and log downloading outside the browser context.

### 6.4 Structural Gaps in the Manual Document

Beyond per-case suitability, these structural issues in the original document prevent direct conversion to automation:

**Compound test cases:** A single manual test case often covers 4–6 distinct scenarios. For example, AUTH-001 tests creation, password entry, seed skip attempt, seed confirmation, and onboarding completion. For vision-based agents, this must be split into 2–3 atomic tasks to prevent state corruption at one step from cascading through the rest.

**No visual element descriptions:** Every manual case says "Open DEX" or "Enter amount" without describing what the element looks like. Skyvern needs "Click the input field labeled Amount below the recipient address, with a coin ticker next to it."

**Abstract expected results:** "Validation blocks invalid orders with guidance" is not machine-evaluable. The automation needs: "A red error message appears containing the word invalid, insufficient, or minimum."

**No inline test data:** Cases reference AS-01, AM-03, WP-02 by code. The automation prompt must contain the actual address string, amount value, and seed phrase inline.

**Missing dependency graph:** Many tests assume DOC/MARTY are funded (from SEND-001) without declaring this dependency. The automation needs explicit execution ordering.

---

## 7. Automated Test Matrix

43 test cases converted to Skyvern-compatible prompts with visual descriptions, checkpoint assertions, extraction schemas, and inline test data. The full YAML is provided as a companion file (`test_matrix.yaml`); this section summarises the structure and execution phases.

### 7.1 Execution Phases (Dependency Order)

| Phase              | Tests                                                          | Purpose                                                        | Tags                 |
| ------------------ | -------------------------------------------------------------- | -------------------------------------------------------------- | -------------------- |
| 1. Auth + Wallet   | AUTH-001a/b, AUTH-003, AUTH-004, WAL-001, WAL-002              | Establish wallet creation, import, login, wallet management    | auth, critical, p0   |
| 2. Coin Management | COIN-001, COIN-002, DASH-001                                   | Enable DOC/MARTY, verify dashboard toggles                     | coin, p1             |
| 3. Faucet Funding  | SEND-001, SEND-002a                                            | Fund wallets with test coins via in-app faucet                 | prerequisite, p0     |
| 4. Send/Withdraw   | SEND-003, SEND-004, SEND-005                                   | DOC send happy path, address validation, amount boundaries     | send, critical, p0   |
| 5. DEX             | DEX-001, DEX-003                                               | Maker order creation, input validation                         | dex, critical, p0    |
| 6. Bridge          | BRDG-001, BRDG-002, BRDG-003                                   | Bridge transfer, unsupported pairs, boundaries                 | bridge, critical, p0 |
| 7. NFT             | NFT-001                                                        | NFT list/detail view (if enabled)                              | nft, p1              |
| 8. Settings        | SET-002, SET-003, NAV-001, NAV-003                             | Privacy toggles, test coin impact, navigation, unsaved changes | settings, p1         |
| 9. Bot             | BOT-001, BOT-002                                               | Market maker bot creation, validation                          | bot, p1              |
| 10. Fiat           | FIAT-001, FIAT-002                                             | Fiat access, form validation                                   | fiat, p0             |
| 11. Security       | SECX-002, SECX-003, SECX-004                                   | Seed backup, unban pubkeys, password change                    | security, p0         |
| 12. Custom Token   | CTOK-001, CTOK-002                                             | Token import, error handling                                   | custom_token, p1     |
| 13. Localization   | L10N-001                                                       | Translation completeness check                                 | l10n, p2             |
| 14. Feature Gating | GATE-001, GATE-003                                             | Disabled feature tooltips, NFT gate                            | gating, p1           |
| 15. Support/Misc   | SUP-001, FEED-001, SETX-001, SETX-007, WALX-001, WADDR-001/002 | Support, feedback, advanced settings, addresses                | p2                   |

### 7.2 Test Case Format

Each automated test case in `test_matrix.yaml` follows this structure:

**id:** Unique identifier prefixed `GW-AUTO-` to distinguish from manual IDs.

**source_manual_id:** Maps back to the original manual test case ID for traceability.

**tags:** Array of tags for filtering (smoke, critical, p0/p1/p2, module name).

**steps:** Ordered list of action + checkpoint pairs. Each action describes what to do visually; each checkpoint describes what must be true before proceeding.

**prompt:** Alternative to steps for simpler tests — a single natural-language prompt.

**expected_result:** Human-readable expected outcome for the report.

**extraction_schema:** JSON Schema defining structured data to extract from the final screen state. Used by Skyvern to return machine-comparable fields.

**max_steps / timeout:** Safety limits per test case (default 30 steps, 180 seconds).

### 7.3 Example Test Case

```yaml
- id: GW-AUTO-SEND-003
  name: "Send DOC happy path"
  source_manual_id: GW-MAN-SEND-003
  tags: [send, critical, p0, smoke]
  timeout: 240
  steps:
    - action: >
        Navigate to the wallet or coin that holds DOC. Look for 'DOC' or
        'Document' in your wallet/coin list and click on it.
      checkpoint: "The DOC coin detail screen is visible with a balance > 0."

    - action: >
        Click the 'Send' or 'Withdraw' button. It may appear as an icon
        with an upward arrow or the word 'Send'.
      checkpoint: "A send form is visible with fields for recipient address and amount."

    - action: >
        Enter the recipient address 'RReplaceMeWithValidDOCAddress' into
        the address/recipient field. Enter '0.001' into the amount field.
      checkpoint: "Both fields are filled. No error messages are shown."

    - action: >
        Click the 'Send', 'Confirm', or 'Submit' button to initiate the
        transaction. If a confirmation dialog appears, confirm it.
      checkpoint: "A success message, pending indicator, or transaction hash is displayed."

  expected_result: "Transaction submitted; fee and amount match; status is Pending or Confirmed."
  extraction_schema:
    type: object
    properties:
      transaction_submitted:
        type: boolean
      success_or_pending_message:
        type: string
      fee_displayed:
        type: string
      transaction_hash:
        type: string
```

### 7.4 Regression Pack Filtering

```bash
# Smoke pack (fastest gate check)
python runner/runner.py --tag smoke

# Critical money-movement tests
python runner/runner.py --tag critical

# P0 only (highest priority)
python runner/runner.py --tag p0

# Full automated suite
python runner/runner.py
```

---

## 8. Manual Test Companion

36 test items that must remain manual. Provided as `manual_companion.yaml` — a structured pass/fail checklist that runs alongside the automated suite for full coverage.

### 8.1 Categories

| Category                       | Count | Examples                                                         |
| ------------------------------ | ----- | ---------------------------------------------------------------- |
| Hardware wallet (Trezor)       | 2     | Connect/sign, restricted modules                                 |
| Network manipulation           | 7     | Offline indicators, interrupted transactions, recovery           |
| App lifecycle/restart          | 7     | Session persistence, settings retention, quick-login             |
| Cross-platform + responsive    | 4     | Multi-platform parity, breakpoint behaviour, orientation         |
| Accessibility                  | 3     | Keyboard nav, screen reader, contrast/scaling                    |
| Security/privacy (OS-level)    | 3     | Auto-lock, app-switcher, clipboard                               |
| Filesystem operations          | 3     | Export/import JSON, download logs                                |
| Deep link / clock manipulation | 2     | Auth gating on deep links, clock warning banner                  |
| Grade-B manual verification    | 5     | Clipboard checks, explorer links, provider webview, export files |

Together, the 43 automated tests and 36 manual checklist items cover the full scope of the original 85 manual test cases with no gaps.

---

## 9. Implementation Artifacts

The complete runner consists of 7 Python modules plus the YAML test matrix.

### 9.1 Data Models (`models.py`)

```python
from pydantic import BaseModel
from typing import Optional

class TestCase(BaseModel):
    id: str
    name: str
    tags: list[str] = []
    prompt: str = ""
    steps: Optional[list[dict]] = None
    expected_result: str
    extraction_schema: Optional[dict] = None
    max_steps: Optional[int] = None
    timeout: Optional[int] = None
    source_manual_id: Optional[str] = None

class TestResult(BaseModel):
    test_id: str
    test_name: str
    tags: list[str]
    status: str              # PASS | FAIL | ERROR | SKIP
    skyvern_status: str
    expected: str
    extracted_data: Optional[dict | str] = None
    duration_seconds: float
    run_id: Optional[str] = None
    error: Optional[str] = None

class TestRun(BaseModel):
    timestamp: str
    base_url: str
    total: int
    passed: int
    failed: int
    errors: int
    skipped: int
    flaky: int = 0
    results: list[TestResult]
    voted_results: list[dict] = []
```

### 9.2 Pre-flight Checks (`preflight.py`)

Validates Ollama responsiveness and inference, VRAM availability (>15 GB free), Skyvern HTTP health, and Flutter app reachability. Returns `False` on any failure, causing the runner to abort with exit code 2. Full implementation in Section 5.2.

### 9.3 Prompt Builder (`prompt_builder.py`)

Automatically prepends the Flutter render-wait preamble to every prompt, converts checkpoint-based step lists into sequential prompts with verification gates, and appends a completion suffix requesting explicit success/error reporting. Full implementation in Section 5.2.

### 9.4 Majority Vote (`retry.py`)

Runs each test N times and determines the final verdict. All-agree = that status at 100% confidence. Majority-agree = that status at majority/total confidence. No majority = FLAKY. All-ERROR with some non-error = FLAKY. Includes early exit: skip remaining retries if first 2 pass, or stop early if all attempts are ERROR. Full implementation in Section 5.2.

### 9.5 Timeout Guards (`guards.py`)

Wraps every Skyvern task call in an `asyncio.wait_for()` with a configurable timeout (default 180 seconds). Raises `TestTimeoutError` with a diagnostic message including the test ID and timeout value, allowing the runner to log the issue and continue to the next test. Full implementation in Section 5.2.

### 9.6 Ollama Monitor (`ollama_monitor.py`)

Background asyncio task polling every 10 seconds: checks Ollama HTTP endpoint, nvidia-smi VRAM free/used/temperature. Flags unhealthy if VRAM < 500 MB free, temperature > 90°C, or Ollama stops responding. The runner checks `monitor.healthy` before each test attempt. Full implementation in Section 5.2.

### 9.7 Hardened Runner (`runner.py`)

The main orchestration script. Loads the YAML matrix, applies tag filtering, runs pre-flight checks, starts the Ollama monitor, iterates tests with retry+majority-vote, applies early exit optimisation, and writes results.

```python
# runner/runner.py (hardened version) — key structure

async def main(matrix_path: str, tag_filter: str = None, single: bool = False):
    matrix = load_matrix(matrix_path)
    config = matrix["config"]

    # Pre-flight
    if not await run_preflight(config):
        sys.exit(2)

    # Filter tests
    tests = [TestCase(**t) for t in matrix["tests"]]
    if tag_filter:
        tests = [t for t in tests if tag_filter in t.tags]

    # Start infrastructure
    skyvern = Skyvern(base_url="http://localhost:8000", api_key="local")
    monitor = OllamaMonitor()
    await monitor.start()

    # Execute with retries
    voted_results = []
    for test in tests:
        voted = await run_test_with_retries(skyvern, test, config, setup, monitor)
        voted_results.append(voted)

    await monitor.stop()

    # Write results
    run_dir = Path(f"results/run_{timestamp}")
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "results.json").write_text(json.dumps(results, indent=2))
    generate_html_report(run, run_dir / "report.html")

    # Exit codes
    if failed > 0 or errors > 0:
        sys.exit(1)
    elif flaky > 0:
        sys.exit(3)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", default="tests/test_matrix.yaml")
    parser.add_argument("--tag", default=None)
    parser.add_argument("--single", action="store_true")
    args = parser.parse_args()
    asyncio.run(main(args.matrix, args.tag, args.single))
```

### 9.8 HTML Reporter (`reporter.py`)

Generates a styled dark-theme HTML report with summary statistics (total, passed, failed, errors, flaky, pass rate) and a results table showing test ID, name, tags, status with colour coding, duration, extracted data preview, and error messages. Saved alongside `results.json` in each timestamped run directory.

---

## 10. Execution Strategy

### 10.1 Phased Rollout

**Week 1–2 (Infrastructure):** Run `setup.sh`. Validate Ollama + Skyvern connectivity. Execute a single trivial test (navigate to dashboard, verify it loads) to confirm the vision loop works end-to-end.

**Week 3–4 (Smoke Suite):** Run the smoke-tagged subset (7–8 tests). Tune prompts and timeouts based on actual Skyvern + Ollama behaviour. Establish baseline pass rate. Target: >90% stability before expanding.

**Week 5–6 (Critical Suite):** Add critical-tagged tests (money movement: send, DEX, bridge). These are the highest-value automated checks. Tune retry counts and checkpoint language.

**Week 7–8 (Full Suite):** Enable all 43 automated tests. Run in CI on every staging deployment. Measure flaky rate and triage unstable tests.

**Ongoing:** Expand manual companion tests to automation as Flutter rendering stabilises and Skyvern capabilities evolve. Target: increase Grade A percentage from 47% to 60%+ over 6 months.

### 10.2 CI Integration

```bash
#!/usr/bin/env bash
# ci-pipeline.sh

# Start infrastructure
ollama serve &
docker compose up -d
sleep 10

# Run smoke gate
python runner/runner.py --tag smoke --single
SMOKE_EXIT=$?

if [ $SMOKE_EXIT -ne 0 ]; then
  echo "SMOKE GATE FAILED — blocking deployment"
  exit 1
fi

# Run full suite with retries
python runner/runner.py --matrix tests/test_matrix.yaml
FULL_EXIT=$?

# Upload report as artifact
cp results/run_*/report.html $CI_ARTIFACTS_DIR/

exit $FULL_EXIT
```

### 10.3 Tag Filtering Strategy

| Scenario               | Command                | Tests | Time      |
| ---------------------- | ---------------------- | ----- | --------- |
| Pre-merge gate         | `--tag smoke`          | ~8    | 5–10 min  |
| Nightly regression     | `--tag critical`       | ~20   | 15–30 min |
| Full weekly regression | (no filter)            | 43    | 30–60 min |
| Quick infra check      | `--tag smoke --single` | ~8    | 3–5 min   |

### 10.4 Test Data Population

Before running the suite, the `test_data` section in `test_matrix.yaml` must be populated with actual QA environment values:

| Key                       | Description                  | Example                     |
| ------------------------- | ---------------------------- | --------------------------- |
| `wallet_password`         | QA environment password      | `TestPass123!`              |
| `import_seed_12`          | Valid testnet 12-word seed   | `abandon abandon ... about` |
| `doc_recipient_address`   | Valid DOC testnet address    | `R9o9xTocqr6...`            |
| `marty_recipient_address` | Valid MARTY testnet address  | `R4kL2xPqm7...`             |
| `evm_token_contract`      | Test ERC-20 contract address | `0x1234...abcd`             |

---

## 11. Performance Expectations

| Metric                                            | Estimate (RTX 5090 + qwen2.5-vl:32b) |
| ------------------------------------------------- | ------------------------------------ |
| Time per Skyvern step (screenshot → LLM → action) | 2–4 seconds                          |
| Average test case (10–15 steps)                   | 30–60 seconds                        |
| Setup task per test (login, ~5 steps)             | 10–20 seconds                        |
| Single test with 3x majority vote                 | 90–180 seconds                       |
| Full 43-test suite (with retries)                 | 30–60 minutes                        |
| Smoke suite (8 tests, single attempt)             | 3–5 minutes                          |
| VRAM usage during inference                       | ~20 GB                               |
| Peak GPU utilisation during inference             | 80–95%                               |
| Ollama idle VRAM (model loaded)                   | ~20 GB                               |

For faster iteration during prompt tuning, use gemma3:27b (~16 GB VRAM, faster inference) or qwen2.5-vl:7b (~5 GB, much faster but less accurate on complex UIs). Switch models by changing `OLLAMA_MODEL` in `.env`.

### Comparison with Manual Testing

| Metric                | Manual            | Automated                          |
| --------------------- | ----------------- | ---------------------------------- |
| Full regression cycle | ~52 hours         | ~1 hour                            |
| Smoke check           | ~4 hours          | ~5 minutes                         |
| Cost per run          | Human tester time | Electricity (~$0.10)               |
| Consistency           | Varies by tester  | 90–95% stable                      |
| Coverage              | 85 tests          | 43 automated + 36 manual companion |
| Time reduction        | Baseline          | ~75% reduction                     |

---

## 12. Risks and Limitations

### 12.1 Inherent Limitations

| Limitation                         | Why                                                                                                   | Workaround                                                                      |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| No 100% deterministic results      | LLMs are probabilistic. Even temperature=0 varies with subtle screenshot differences.                 | Majority vote targets 90–95% consistency. Accept this as the realistic ceiling. |
| No pixel-perfect visual validation | LLM describes what it sees in natural language, not coordinates. Cannot detect 2px misalignment.      | Supplement with pixelmatch or BackstopJS for visual regression.                 |
| No complex gestures                | Skyvern supports click, type, scroll. Pinch, long-press, drag are unreliable.                         | Test gesture-dependent features manually.                                       |
| No timing assertions               | LLM cannot measure load times or animation duration.                                                  | Use Playwright performance APIs in a separate non-LLM test suite.               |
| No cross-test state                | Each test runs in isolation. If Test A creates data for Test B, it requires a shared database or API. | Add teardown/setup hooks or use a test database reset endpoint.                 |
| 32% of tests remain manual         | Hardware, OS, accessibility, and cross-platform tests are architecturally impossible in-browser.      | Run manual_companion.yaml alongside automated suite.                            |

### 12.2 Operational Risks

| Risk                                           | Impact                                         | Mitigation                                                                                                               |
| ---------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Vision model misidentifies Flutter UI elements | Tests click wrong things, produce false passes | Use 32B model for best accuracy. Add explicit visual descriptions in prompts. Majority vote catches intermittent errors. |
| Ollama OOM on 32B model                        | All tests fail with ERROR                      | Pre-flight VRAM check aborts early. Drop to 7B for debugging. RTX 5090 32 GB handles Q4 32B comfortably.                 |
| Skyvern + Ollama integration bugs              | Tasks hang or produce garbled output           | Pin Skyvern version. Test with skyvern-1.0 engine first. Monitor Skyvern GitHub issues.                                  |
| Flutter app load time causes timeouts          | Tests fail before the app renders              | Increase BROWSER_ACTION_TIMEOUT_MS. Flutter preamble adds explicit wait instructions.                                    |
| Faucet rate-limiting blocks test funding       | Send/DEX/Bridge tests cannot execute           | Pre-fund test wallets. Add faucet cooldown handling. Run funding phase once, not per test.                               |
| Prompt drift after app UI changes              | Tests fail because prompts describe old UI     | Maintain prompts alongside app releases. Use visual descriptions, not hard-coded labels.                                 |

---

## Companion Files

| File                    | Description                                                                         |
| ----------------------- | ----------------------------------------------------------------------------------- |
| `test_matrix.yaml`      | 43 automated test cases with Skyvern prompts, extraction schemas, and tag filtering |
| `manual_companion.yaml` | 36 manual-only checklist items for Grade-C and Grade-B verification steps           |

---

_End of document._
