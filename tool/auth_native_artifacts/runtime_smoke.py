"""Unfunded, network-isolated native engine lifecycle and persistence check.

Passwords and the generated recovery phrase stay in process memory. The report
contains only phase names and booleans; native output is discarded.
"""
import ctypes
from contextlib import contextmanager
import json
import os
from pathlib import Path
import secrets
import resource
import socket
import sys
import tempfile
import time
import urllib.error
import urllib.request


report_fd = os.dup(1)
null_fd = os.open(os.devnull, os.O_WRONLY)
os.dup2(null_fd, 1)
os.dup2(null_fd, 2)
os.close(null_fd)
phase = "load"
completed = []
diagnostics = {}
library = None
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def require(condition, check="condition"):
    diagnostics["check"] = check
    if not condition:
        raise AssertionError("native artifact validation failed")


def wait_status(expected):
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        if library.mm2_main_status() == expected:
            return
        time.sleep(0.05)
    raise TimeoutError("native artifact status deadline")


@contextmanager
def isolated_workspace():
    previous = os.getcwd()
    with tempfile.TemporaryDirectory(prefix="kdf-artifact-smoke-") as temporary:
        os.chdir(temporary)
        try:
            yield temporary
        finally:
            try:
                library.mm2_stop()
                wait_status(0)
            finally:
                os.chdir(previous)


def generated_secret(label):
    while True:
        value = label + "1-" + secrets.token_hex(20)
        if not any(value[index] == value[index + 1] == value[index + 2] for index in range(len(value) - 2)):
            return value


try:
    library = ctypes.CDLL(sys.argv[1])
    callback_type = ctypes.CFUNCTYPE(None, ctypes.c_void_p)
    callback = callback_type(lambda unused: None)
    library.mm2_main.argtypes = [ctypes.c_char_p, callback_type]
    library.mm2_main.restype = ctypes.c_int8
    library.mm2_main_status.restype = ctypes.c_int8
    library.mm2_stop.restype = ctypes.c_int8
    require(library.mm2_main_status() == 0)
    completed.append(phase)
    password = generated_secret("Linux")
    replacement = generated_secret("Rotate")
    wrong_password = generated_secret("Wrong")
    rpc_password = generated_secret("Rpc")
    wallet_name = "artifact-smoke-" + secrets.token_hex(6)
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0))
        port = reserved.getsockname()[1]
    with isolated_workspace() as temporary:
        # The SDK creates db_root before no-login engine startup.
        Path(temporary, "db").mkdir(mode=0o700)
        base = {
            "mm2": 1, "gui": "native-artifact-validation", "netid": 9999,
            "rpc_password": rpc_password, "rpcip": "127.0.0.1", "rpcport": port,
            "rpc_local_only": True, "https": False, "disable_p2p": True,
            "coins": [], "silent_console": True, "allow_weak_password": False, "enable_hd": False,
            "dbdir": temporary + "/db", "userhome": temporary,
        }

        def start(credential=None, create=False):
            config = dict(base, allow_registrations=create)
            if credential is not None:
                config.update(wallet_name=wallet_name, wallet_password=credential, enable_hd=True)
            buffer = ctypes.create_string_buffer(json.dumps(config).encode())
            try:
                result = library.mm2_main(buffer, callback)
                diagnostics["last_start_code"] = result
                diagnostics["last_status"] = library.mm2_main_status()
            finally:
                ctypes.memset(buffer, 0, ctypes.sizeof(buffer))
            if result == 0:
                wait_status(3)
            return result

        def stop():
            require(library.mm2_stop() in (0, 1))
            wait_status(0)

        def rpc(method, params=None, expect_error=None):
            diagnostics["rpc_method"] = method
            payload = {"userpass": rpc_password, "method": method, "params": params}
            # version is a legacy RPC in this exact pinned KDF.
            if method != "version":
                payload["mmrpc"] = "2.0"
            request = urllib.request.Request(
                f"http://127.0.0.1:{port}/", data=json.dumps(payload).encode(),
                headers={"Content-Type": "application/json"})
            try:
                response = urllib.request.urlopen(request, timeout=20)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                decoded = json.loads(response.read())
            if "error_type" in decoded:
                error_kind = decoded["error_type"]
                diagnostics["rpc_error_type"] = error_kind if error_kind in {"InvalidRequest", "InvalidPassword", "WalletsStorageError", "InternalError", "Internal", "UnknownMethod", "UserpassIsInvalid"} else "Other"
            if expect_error is not None:
                require(decoded.get("error_type") == expect_error)
                return None
            require("error" not in decoded and "error_type" not in decoded)
            return decoded.get("result", decoded)

        phase = "read_only_start_stop"
        require(start() == 0, "read_only_start_code")
        require(rpc("get_wallet_names")["wallet_names"] == [], "empty_wallet_catalog")
        require("f9632e0" in json.dumps(rpc("version")), "pinned_source_version")
        stop()
        completed.append(phase)

        phase = "generated_wallet_creation"
        require(start(password, create=True) == 0)
        identity = rpc("get_public_key_hash", {})["public_key_hash"]
        require(bool(identity))
        require(rpc("get_wallet_names")["activated_wallet"] == wallet_name)
        mnemonic = rpc("get_mnemonic", {"format": "plaintext", "password": password})["mnemonic"]
        require(isinstance(mnemonic, str) and len(mnemonic.split()) >= 12)
        completed.append(phase)

        phase = "fresh_password_verification"
        rpc("get_mnemonic", {"format": "plaintext", "password": wrong_password}, "InvalidPassword")
        stop()
        completed.append(phase)

        phase = "wrong_password_cold_start_preserves_wallet"
        require(start(wrong_password) != 0)
        wait_status(0)
        require(start(password) == 0)
        require(rpc("get_public_key_hash", {})["public_key_hash"] == identity)
        require(rpc("get_mnemonic", {"format": "plaintext", "password": password})["mnemonic"] == mnemonic)
        completed.append(phase)

        phase = "password_rotation_and_cold_return"
        rpc("change_mnemonic_password", {"current_password": password, "new_password": replacement})
        rpc("get_mnemonic", {"format": "plaintext", "password": password}, "InvalidPassword")
        require(rpc("get_mnemonic", {"format": "plaintext", "password": replacement})["mnemonic"] == mnemonic)
        stop()
        require(start(replacement) == 0)
        require(rpc("get_public_key_hash", {})["public_key_hash"] == identity)
        stop()
        completed.append(phase)

        phase = "credential_transport_and_storage_canaries"
        canaries = [value.encode() for value in (password, replacement, rpc_password, mnemonic)]
        for surface in (Path("/proc/self/cmdline"), Path("/proc/self/environ")):
            if surface.exists():
                require(not any(value in surface.read_bytes() for value in canaries))
        files = [entry for entry in Path(temporary).rglob("*") if entry.is_file()]
        require(bool(files))
        for entry in files:
            require(not any(value in entry.read_bytes() for value in canaries))
        completed.append(phase)

        phase = "read_only_deletion"
        require(start() == 0)
        require(rpc("get_wallet_names")["wallet_names"] == [wallet_name])
        rpc("delete_wallet", {"wallet_name": wallet_name, "password": wrong_password}, "InvalidPassword")
        require(rpc("get_wallet_names")["wallet_names"] == [wallet_name])
        rpc("delete_wallet", {"wallet_name": wallet_name, "password": replacement})
        require(rpc("get_wallet_names")["wallet_names"] == [])
        stop()
        completed.append(phase)
    result = {"passed": True, "phases": completed, "network_required": False, "funds_used": False}
except Exception as error:
    result = {"passed": False, "phase": phase, "error_type": type(error).__name__, "completed": completed, "diagnostics": diagnostics}
finally:
    if library is not None:
        try:
            library.mm2_stop()
        except Exception:
            pass
os.write(report_fd, (json.dumps(result, sort_keys=True) + "\n").encode())
os.close(report_fd)
sys.exit(0 if result["passed"] else 1)
