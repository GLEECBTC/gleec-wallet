# Gleec QA Automation — runbook

Vision-based end-to-end testing for the Gleec Wallet **web** build. Flutter web renders
its UI to an HTML canvas, so DOM-based tools (Selenium, Cypress, Playwright selectors)
have nothing to select. Instead Skyvern drives a real browser and a local vision model
reads the screen.

This file is the runbook. The design — component breakdown, prompt strategy, the
automatability grading behind the matrix — is in
[gleec-qa-architecture.md](gleec-qa-architecture.md); where that document's commands
disagree with this one, **this one is correct**.

For every other test surface in the repo, see [../docs/TESTING.md](../docs/TESTING.md).

## What it tests

A **deployed URL**, not a local build. The target is `config.base_url` in
[test_matrix.yaml](test_matrix.yaml) (default `https://app.gleecwallet.com`); the runner
aborts if it is missing. `APP_BASE_URL` in `.env` is *not* read by the runner — change the
matrix.

## Prerequisites

- **macOS or Linux**, or **WSL2** on Windows. `setup.sh` refuses to run on native Windows.
- **Ollama** on the host (not containerised), serving `:11434`, with `qwen2.5-vl:32b`
  pulled. On WSL2, run Ollama natively on Windows for GPU access.
- **~15 GB free VRAM.** Pre-flight aborts below this; the check is skipped when
  `nvidia-smi` is absent.
- **Docker Compose** — brings up Skyvern (`:8000`) and PostgreSQL 15.
- **Python 3.10+** with `requirements.txt` installed.

## Setup

```bash
cd automated_testing
./setup.sh
```

`setup.sh` installs and starts Ollama, pulls the vision model, creates
`results/screenshots` and `results/videos`, copies `.env.example` to `.env` if absent,
installs the Python dependencies, and runs `docker compose up -d`.

Then edit `.env` — it is git-ignored and is consumed by the **Skyvern container** via
`env_file`, not by the runner. The value that usually needs changing is
`OLLAMA_SERVER_URL` (`http://host.docker.internal:11434` is correct for both Docker
Desktop and WSL2).

Before a real run, fill in the `test_data` block at the top of `test_matrix.yaml` with
your QA-environment addresses and credentials.

## Running

All commands run **from `automated_testing/`**. The runner is a Python *package*:
`python runner/runner.py` fails with an `ImportError`, because `runner/runner.py` uses
relative imports. Use `-m`.

```bash
python -m runner.runner --tag smoke --single   # fast gate, one attempt per test
python -m runner.runner --tag critical         # money-movement tests
python -m runner.runner --tag p0               # highest priority
python -m runner.runner                        # full suite, with retries and majority vote
python -m runner --tag smoke                   # equivalent, via runner/__main__.py
```

Flags: `--matrix PATH` (default `test_matrix.yaml`), `--tag`, `--single`,
`--include-manual`, `--manual-only`, `--ollama-url`, `--skyvern-url`, `--verbose`.

CI wrapper — smoke gate, then the full suite, then artifact collection:

```bash
./ci-pipeline.sh          # MATRIX and CI_ARTIFACTS_DIR are overridable
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | all passed |
| 1 | test failures or errors |
| 2 | pre-flight / infrastructure failure (Ollama, VRAM, Skyvern, app unreachable) |
| 3 | all passed, but some tests were flaky |

`ci-pipeline.sh` aborts on 2 and blocks deployment on 1.

## Output

Each run writes `results/run_<timestamp>/` with `results.json`, `report.html`, and
screenshots. Videos land in `results/videos` via the container mount.

## Not wired into CI

Nothing under `.github/` references `automated_testing`. `ci-pipeline.sh` exists but no
workflow invokes it — someone has to run it.

## Companion files

| File | Purpose |
|---|---|
| `test_matrix.yaml` | automated cases, prompts, extraction schemas, tags, `config.base_url` |
| `manual_companion.yaml` | manual-only checklist, loaded with `--include-manual` / `--manual-only` |
| `gleec-qa-architecture.md` | design reference — for commands, this README wins |
| `gleec-qa-evaluation.md` | per-case automatability grading (A/B/C) |
| `GLEEC_WALLET_MANUAL_TEST_CASES.md` | the source manual cases the matrix was converted from |
