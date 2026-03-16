"""Direct Playwright automation for tasks that Skyvern cannot handle.

Provides browser lifecycle management, viewport resizing, file downloads,
keyboard navigation auditing, accessibility scanning, and clock mocking.
These run in a separate Playwright instance from Skyvern's browser.
"""

from __future__ import annotations

import asyncio
import json
import logging
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


class PlaywrightSession:
    """Manages a direct Playwright browser session for composite tests.

    This is separate from Skyvern's internal Playwright instance.
    Used for OS-level browser manipulation that Skyvern's API doesn't expose.
    """

    def __init__(self, headless: bool = False):
        self.headless = headless
        self._pw = None
        self._browser = None
        self._context = None
        self._page = None

    async def start(self, viewport: dict | None = None) -> None:
        from playwright.async_api import async_playwright
        self._pw = await async_playwright().start()
        self._browser = await self._pw.chromium.launch(headless=self.headless)
        ctx_opts = {"accept_downloads": True}
        if viewport:
            ctx_opts["viewport"] = viewport
        self._context = await self._browser.new_context(**ctx_opts)
        await self._context.grant_permissions(
            ["clipboard-read", "clipboard-write"]
        )
        self._page = await self._context.new_page()

    async def stop(self) -> None:
        if self._browser:
            await self._browser.close()
        if self._pw:
            await self._pw.stop()

    @property
    def page(self):
        return self._page

    @property
    def context(self):
        return self._context

    @property
    def browser(self):
        return self._browser

    # -------------------------------------------------------------------
    # Browser lifecycle (simulate app restart)
    # -------------------------------------------------------------------

    async def restart_session(
        self, url: str, viewport: dict | None = None
    ) -> None:
        """Close the current context and open a fresh one (simulates app restart).

        Cookies, localStorage, and sessionStorage are wiped.
        """
        if self._context:
            await self._context.close()

        ctx_opts = {"accept_downloads": True}
        if viewport:
            ctx_opts["viewport"] = viewport
        self._context = await self._browser.new_context(**ctx_opts)
        await self._context.grant_permissions(
            ["clipboard-read", "clipboard-write"]
        )
        self._page = await self._context.new_page()
        await self._page.goto(url, wait_until="networkidle")

    # -------------------------------------------------------------------
    # Navigation
    # -------------------------------------------------------------------

    async def navigate(self, url: str, wait: str = "networkidle") -> None:
        await self._page.goto(url, wait_until=wait)

    async def wait_for_flutter(self, seconds: float = 3.0) -> None:
        """Wait for Flutter canvas to finish rendering."""
        await asyncio.sleep(seconds)

    # -------------------------------------------------------------------
    # Network simulation (per-browser-context, not system-wide)
    # -------------------------------------------------------------------

    async def set_offline(self, offline: bool = True) -> None:
        """Simulate network loss/restore at the browser context level.

        This only affects the browser — the test runner, Skyvern, and Ollama
        remain fully connected.
        """
        await self._context.set_offline(offline)

    # -------------------------------------------------------------------
    # Viewport / responsive
    # -------------------------------------------------------------------

    async def set_viewport(self, width: int, height: int) -> None:
        await self._page.set_viewport_size({"width": width, "height": height})

    async def take_screenshot(self, path: str | Path) -> str:
        await self._page.screenshot(path=str(path), full_page=True)
        return str(path)

    # -------------------------------------------------------------------
    # Clipboard
    # -------------------------------------------------------------------

    async def read_clipboard(self) -> str:
        return await self._page.evaluate(
            "async () => await navigator.clipboard.readText()"
        )

    async def write_clipboard(self, text: str) -> None:
        await self._page.evaluate(
            "async (t) => await navigator.clipboard.writeText(t)", text
        )

    # -------------------------------------------------------------------
    # Clock mocking
    # -------------------------------------------------------------------

    async def mock_clock(self, fake_time: datetime) -> None:
        """Set a fixed fake time for Date.now() and new Date()."""
        await self._page.clock.set_fixed_time(fake_time)

    async def reset_clock(self) -> None:
        """Remove clock mock by reloading without the override."""
        url = self._page.url
        await self._page.reload()
        await self.wait_for_flutter()

    # -------------------------------------------------------------------
    # File downloads
    # -------------------------------------------------------------------

    async def trigger_download_and_capture(
        self, click_selector: str | None = None, click_text: str | None = None
    ) -> dict:
        """Click an element that triggers a download and capture the file.

        Returns dict with: path, filename, size, content_preview.
        """
        async with self._page.expect_download() as dl_info:
            if click_selector:
                await self._page.click(click_selector)
            elif click_text:
                await self._page.get_by_text(click_text).click()
            else:
                raise ValueError("Provide click_selector or click_text")

        download = await dl_info.value
        tmp = tempfile.mktemp(suffix=f"_{download.suggested_filename}")
        await download.save_as(tmp)

        content = Path(tmp).read_text(encoding="utf-8", errors="replace")
        return {
            "path": tmp,
            "filename": download.suggested_filename,
            "size": Path(tmp).stat().st_size,
            "content_preview": content[:500],
            "is_valid_json": _is_valid_json(content),
        }

    # -------------------------------------------------------------------
    # Keyboard navigation audit
    # -------------------------------------------------------------------

    async def keyboard_navigation_audit(
        self, max_tabs: int = 100
    ) -> dict:
        """Tab through the page and record focus order.

        Returns dict with: focused_elements (list), traps_detected (bool),
        total_tabbable (int).
        """
        focused_elements = []
        seen_tags = set()
        trap_count = 0
        prev_element = None

        for i in range(max_tabs):
            await self._page.keyboard.press("Tab")
            await asyncio.sleep(0.15)

            info = await self._page.evaluate("""() => {
                const el = document.activeElement;
                if (!el || el === document.body) return null;
                return {
                    tag: el.tagName,
                    role: el.getAttribute('role'),
                    label: el.getAttribute('aria-label') || el.textContent?.slice(0, 50),
                    id: el.id,
                    tabIndex: el.tabIndex,
                };
            }""")

            if info is None:
                continue

            element_key = f"{info['tag']}:{info.get('id', '')}:{info.get('label', '')}"

            if element_key == prev_element:
                trap_count += 1
                if trap_count > 3:
                    break
            else:
                trap_count = 0

            if element_key not in seen_tags:
                focused_elements.append(info)
                seen_tags.add(element_key)

            prev_element = element_key

        return {
            "focused_elements": focused_elements,
            "total_tabbable": len(focused_elements),
            "traps_detected": trap_count > 3,
        }

    # -------------------------------------------------------------------
    # Accessibility audit (axe-core)
    # -------------------------------------------------------------------

    async def accessibility_audit(self) -> dict:
        """Run axe-core accessibility scan on the current page.

        Returns dict with: violations_count, violations (list),
        passes_count.
        """
        try:
            from axe_playwright_python.async_playwright import Axe
            axe = Axe()
            results = await axe.run(self._page)

            response = getattr(results, "response", {}) or {}
            raw_violations = response.get("violations", [])
            raw_passes = response.get("passes", [])

            violations = [
                {
                    "id": v.get("id"),
                    "impact": v.get("impact"),
                    "description": v.get("description"),
                    "nodes_count": len(v.get("nodes", [])),
                }
                for v in raw_violations
            ]

            return {
                "violations_count": len(raw_violations),
                "violations": violations,
                "passes_count": len(raw_passes),
            }
        except ImportError:
            logger.warning("axe-playwright-python not installed — skipping a11y audit")
            return {"violations_count": -1, "error": "axe-playwright-python not installed"}
        except Exception as exc:
            return {"violations_count": -1, "error": str(exc)}


def _is_valid_json(content: str) -> bool:
    try:
        json.loads(content)
        return True
    except (json.JSONDecodeError, ValueError):
        return False
