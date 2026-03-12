"""Background Ollama and GPU health monitor running during test execution."""

from __future__ import annotations

import asyncio
import logging
import platform
import shutil
import subprocess

import httpx

logger = logging.getLogger(__name__)


class OllamaMonitor:
    """Polls Ollama health and GPU metrics every interval_seconds.

    The runner checks ``monitor.healthy`` before each test attempt.
    If unhealthy, subsequent tests are immediately marked ERROR with
    the specific failure reason from ``last_error``.
    """

    def __init__(
        self,
        ollama_url: str = "http://localhost:11434",
        interval_seconds: int = 10,
        vram_critical_mb: int = 500,
        temp_critical_c: int = 90,
    ):
        self.url = ollama_url
        self.interval = interval_seconds
        self.vram_critical_mb = vram_critical_mb
        self.temp_critical_c = temp_critical_c
        self._running = False
        self._task: asyncio.Task | None = None
        self.last_error: str | None = None

    @property
    def healthy(self) -> bool:
        return self.last_error is None

    async def start(self) -> None:
        self._running = True
        self._task = asyncio.create_task(self._monitor_loop())
        logger.info("Ollama monitor started (interval=%ds)", self.interval)

    async def stop(self) -> None:
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        logger.info("Ollama monitor stopped")

    async def _monitor_loop(self) -> None:
        while self._running:
            try:
                await self._check_ollama_http()
                await self._check_gpu()
            except asyncio.CancelledError:
                break
            except Exception as exc:
                self.last_error = f"Monitor error: {exc}"
                logger.warning("Monitor exception: %s", exc)

            await asyncio.sleep(self.interval)

    async def _check_ollama_http(self) -> None:
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                resp = await client.get(f"{self.url}/api/tags")
                if resp.status_code != 200:
                    self.last_error = f"Ollama returned HTTP {resp.status_code}"
                else:
                    self.last_error = None
        except Exception as exc:
            self.last_error = f"Ollama unreachable: {exc}"

    async def _check_gpu(self) -> None:
        nvidia_smi = shutil.which("nvidia-smi")
        if nvidia_smi is None and platform.system() == "Linux":
            nvidia_smi = "/usr/lib/wsl/lib/nvidia-smi"
        if nvidia_smi is None:
            return

        try:
            result = subprocess.run(
                [
                    nvidia_smi,
                    "--query-gpu=memory.free,memory.used,temperature.gpu",
                    "--format=csv,noheader,nounits",
                ],
                capture_output=True,
                text=True,
                timeout=5,
            )
            parts = result.stdout.strip().split(", ")
            if len(parts) >= 3:
                free_mb = int(parts[0])
                temp_c = int(parts[2])
                if free_mb < self.vram_critical_mb:
                    self.last_error = (
                        f"VRAM critically low: {free_mb}MB free"
                    )
                elif temp_c > self.temp_critical_c:
                    self.last_error = f"GPU temperature critical: {temp_c}°C"
        except Exception:
            pass
