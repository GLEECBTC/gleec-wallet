"""Pre-flight health checks — validates infrastructure before any tests run."""

from __future__ import annotations

import asyncio
import platform
import shutil
import subprocess

import httpx


async def check_ollama(url: str = "http://localhost:11434") -> tuple[bool, str]:
    """Verify Ollama is running and has at least one model loaded."""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(f"{url}/api/tags")
            models = resp.json().get("models", [])
            if len(models) > 0:
                names = [m.get("name", "?") for m in models]
                return True, f"Ollama OK — models: {', '.join(names)}"
            return False, "Ollama running but no models loaded"
    except Exception as exc:
        return False, f"Ollama unreachable: {exc}"


async def check_ollama_inference(
    url: str = "http://localhost:11434",
    model: str = "qwen2.5-vl:32b",
) -> tuple[bool, str]:
    """Run a trivial inference to confirm the GPU pipeline works."""
    try:
        async with httpx.AsyncClient(timeout=120) as client:
            resp = await client.post(
                f"{url}/api/generate",
                json={
                    "model": model,
                    "prompt": "Reply with only the word OK.",
                    "stream": False,
                },
            )
            output = resp.json().get("response", "").strip()
            if "ok" in output.lower():
                return True, "Ollama inference OK"
            return False, f"Ollama inference unexpected output: {output!r}"
    except Exception as exc:
        return False, f"Ollama inference failed: {exc}"


async def check_vram(min_gb: float = 15.0) -> tuple[bool, str]:
    """Verify sufficient VRAM is free.

    Handles both Linux native nvidia-smi and Windows (via WSL2 or native).
    """
    nvidia_smi = shutil.which("nvidia-smi")
    if nvidia_smi is None and platform.system() == "Linux":
        nvidia_smi = "/usr/lib/wsl/lib/nvidia-smi"

    if nvidia_smi is None:
        return True, "nvidia-smi not found — skipping VRAM check"

    try:
        result = subprocess.run(
            [nvidia_smi, "--query-gpu=memory.free", "--format=csv,noheader,nounits"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        free_mb = int(result.stdout.strip().split("\n")[0])
        free_gb = free_mb / 1024
        if free_gb >= min_gb:
            return True, f"VRAM OK — {free_gb:.1f} GB free"
        return False, f"VRAM low — {free_gb:.1f} GB free (need {min_gb}+ GB)"
    except Exception as exc:
        return True, f"VRAM check skipped: {exc}"


async def check_skyvern(url: str = "http://localhost:8000") -> tuple[bool, str]:
    """Verify Skyvern server responds to heartbeat."""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(f"{url}/api/v1/heartbeat")
            if resp.status_code == 200:
                return True, "Skyvern OK"
            return False, f"Skyvern returned HTTP {resp.status_code}"
    except Exception as exc:
        return False, f"Skyvern unreachable: {exc}"


async def check_app(url: str) -> tuple[bool, str]:
    """Verify the Flutter app is reachable."""
    try:
        async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
            resp = await client.get(url)
            if 200 <= resp.status_code < 300:
                return True, f"App OK — HTTP {resp.status_code}"
            return False, f"App returned HTTP {resp.status_code}"
    except Exception as exc:
        return False, f"App unreachable: {exc}"


async def run_preflight(
    config: dict,
    *,
    ollama_url: str = "http://localhost:11434",
    skyvern_url: str = "http://localhost:8000",
    vram_min_gb: float = 15.0,
) -> tuple[bool, list[tuple[str, bool, str]]]:
    """Run all pre-flight checks. Returns (all_ok, list of (name, ok, message))."""
    base_url = config.get("base_url")
    if not base_url:
        return False, [("Config", False, "config.base_url is missing from test matrix")]

    checks = await asyncio.gather(
        check_ollama(ollama_url),
        check_vram(vram_min_gb),
        check_skyvern(skyvern_url),
        check_app(base_url),
    )

    names = ["Ollama", "VRAM", "Skyvern", "App"]
    results = [(names[i], checks[i][0], checks[i][1]) for i in range(len(checks))]
    all_ok = all(ok for _, ok, _ in results)

    if all_ok:
        model = config.get("ollama_model", "qwen2.5-vl:32b")
        inf_ok, inf_msg = await check_ollama_inference(ollama_url, model)
        results.append(("Inference", inf_ok, inf_msg))
        all_ok = inf_ok

    return all_ok, results
