"""Cross-platform OS-level automation utilities.

Provides clipboard access and (opt-in) system-wide network toggling.

IMPORTANT: Network toggling here is SYSTEM-WIDE — it kills connectivity
for the entire host, including the test runner, Skyvern, and Ollama.
For normal test runs, use PlaywrightSession.set_offline() instead, which
simulates network loss at the browser context level without affecting
the runner's infrastructure.

The OS-level network functions are retained for CI environments where
the runner and Skyvern run on a separate machine from the app under test.
"""

from __future__ import annotations

import asyncio
import logging
import platform
import shutil
import subprocess

logger = logging.getLogger(__name__)


def _detect_platform() -> str:
    """Detect the runtime platform category."""
    system = platform.system()
    if system == "Darwin":
        return "macos"
    if system == "Linux":
        with open("/proc/version", "r") as f:
            if "microsoft" in f.read().lower():
                return "wsl2"
        return "linux"
    if system == "Windows":
        return "windows"
    return "unknown"


PLATFORM = _detect_platform()


# ---------------------------------------------------------------------------
# Network toggling
# ---------------------------------------------------------------------------

async def set_network_enabled(enabled: bool) -> tuple[bool, str]:
    """Toggle the network connection at the OS level.

    Returns (success, message).
    """
    action = "enable" if enabled else "disable"
    logger.info("Network %s on platform=%s", action, PLATFORM)

    try:
        if PLATFORM == "macos":
            return await _network_macos(enabled)
        elif PLATFORM == "linux":
            return await _network_linux(enabled)
        elif PLATFORM == "wsl2":
            return await _network_wsl2(enabled)
        else:
            return False, f"Unsupported platform: {PLATFORM}"
    except Exception as exc:
        return False, f"Network toggle failed: {exc}"


async def _network_macos(enabled: bool) -> tuple[bool, str]:
    """Toggle Wi-Fi on macOS via networksetup."""
    iface = await _get_macos_wifi_interface()
    if not iface:
        return False, "No Wi-Fi interface found on macOS"

    state = "on" if enabled else "off"
    proc = await asyncio.create_subprocess_exec(
        "networksetup", "-setairportpower", iface, state,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await proc.communicate()
    if proc.returncode == 0:
        return True, f"macOS Wi-Fi ({iface}) set to {state}"
    return False, f"networksetup failed: {stderr.decode()}"


async def _get_macos_wifi_interface() -> str | None:
    """Find the Wi-Fi network interface name on macOS."""
    proc = await asyncio.create_subprocess_exec(
        "networksetup", "-listallhardwareports",
        stdout=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    lines = stdout.decode().splitlines()
    for i, line in enumerate(lines):
        if "Wi-Fi" in line or "AirPort" in line:
            for j in range(i + 1, min(i + 3, len(lines))):
                if lines[j].strip().startswith("Device:"):
                    return lines[j].split(":", 1)[1].strip()
    return None


async def _network_linux(enabled: bool) -> tuple[bool, str]:
    """Toggle network on Linux via nmcli or ip."""
    if shutil.which("nmcli"):
        state = "on" if enabled else "off"
        proc = await asyncio.create_subprocess_exec(
            "nmcli", "networking", state,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        _, stderr = await proc.communicate()
        if proc.returncode == 0:
            return True, f"nmcli networking {state}"
        return False, f"nmcli failed: {stderr.decode()}"

    iface = await _get_linux_default_interface()
    if not iface:
        return False, "No default network interface found"

    action = "up" if enabled else "down"
    proc = await asyncio.create_subprocess_exec(
        "sudo", "ip", "link", "set", iface, action,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await proc.communicate()
    if proc.returncode == 0:
        return True, f"ip link set {iface} {action}"
    return False, f"ip link failed: {stderr.decode()}"


async def _get_linux_default_interface() -> str | None:
    """Find the default network interface on Linux."""
    proc = await asyncio.create_subprocess_exec(
        "ip", "route", "show", "default",
        stdout=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    parts = stdout.decode().split()
    if "dev" in parts:
        idx = parts.index("dev")
        if idx + 1 < len(parts):
            return parts[idx + 1]
    return None


async def _network_wsl2(enabled: bool) -> tuple[bool, str]:
    """Toggle network from WSL2 by calling PowerShell on the Windows host.

    Uses iptables to block/unblock outbound traffic from WSL2 since
    directly toggling the Windows adapter from WSL2 requires elevated
    privileges on the host.
    """
    if shutil.which("iptables"):
        if enabled:
            proc = await asyncio.create_subprocess_exec(
                "sudo", "iptables", "-D", "OUTPUT", "-j", "DROP",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        else:
            proc = await asyncio.create_subprocess_exec(
                "sudo", "iptables", "-A", "OUTPUT", "-j", "DROP",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        _, stderr = await proc.communicate()
        if proc.returncode == 0:
            state = "restored" if enabled else "blocked"
            return True, f"WSL2 outbound traffic {state} via iptables"
        return False, f"iptables failed: {stderr.decode()}"

    return False, "iptables not available in WSL2"


# ---------------------------------------------------------------------------
# Clipboard
# ---------------------------------------------------------------------------

async def read_clipboard() -> tuple[bool, str]:
    """Read the system clipboard contents.

    Returns (success, clipboard_text_or_error).
    """
    try:
        if PLATFORM == "macos":
            proc = await asyncio.create_subprocess_exec(
                "pbpaste",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await proc.communicate()
            if proc.returncode == 0:
                return True, stdout.decode()
            return False, f"pbpaste failed (rc={proc.returncode}): {stderr.decode()}"

        elif PLATFORM in ("linux", "wsl2"):
            for cmd in (["xclip", "-selection", "clipboard", "-o"],
                        ["xsel", "--clipboard", "--output"]):
                if shutil.which(cmd[0]):
                    proc = await asyncio.create_subprocess_exec(
                        *cmd,
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.PIPE,
                    )
                    stdout, _ = await proc.communicate()
                    if proc.returncode == 0:
                        return True, stdout.decode()

            if PLATFORM == "wsl2" and shutil.which("powershell.exe"):
                proc = await asyncio.create_subprocess_exec(
                    "powershell.exe", "-Command", "Get-Clipboard",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, _ = await proc.communicate()
                if proc.returncode == 0:
                    return True, stdout.decode().strip()

            return False, "No clipboard tool found (install xclip or xsel)"

        return False, f"Unsupported platform: {PLATFORM}"
    except Exception as exc:
        return False, f"Clipboard read failed: {exc}"


async def write_clipboard(text: str) -> tuple[bool, str]:
    """Write text to the system clipboard."""
    try:
        if PLATFORM == "macos":
            proc = await asyncio.create_subprocess_exec(
                "pbcopy",
                stdin=asyncio.subprocess.PIPE,
            )
            await proc.communicate(input=text.encode())
            return True, "Clipboard written (macOS)"

        elif PLATFORM in ("linux", "wsl2"):
            for cmd in (["xclip", "-selection", "clipboard"],
                        ["xsel", "--clipboard", "--input"]):
                if shutil.which(cmd[0]):
                    proc = await asyncio.create_subprocess_exec(
                        *cmd,
                        stdin=asyncio.subprocess.PIPE,
                    )
                    await proc.communicate(input=text.encode())
                    if proc.returncode == 0:
                        return True, f"Clipboard written ({cmd[0]})"

            if PLATFORM == "wsl2" and shutil.which("powershell.exe"):
                proc = await asyncio.create_subprocess_exec(
                    "powershell.exe", "-Command",
                    "$input | Set-Clipboard",
                    stdin=asyncio.subprocess.PIPE,
                )
                await proc.communicate(input=text.encode())
                if proc.returncode == 0:
                    return True, "Clipboard written (WSL2/PowerShell)"
                return False, f"PowerShell Set-Clipboard failed (rc={proc.returncode})"

            return False, "No clipboard tool found"

        return False, f"Unsupported platform: {PLATFORM}"
    except Exception as exc:
        return False, f"Clipboard write failed: {exc}"
