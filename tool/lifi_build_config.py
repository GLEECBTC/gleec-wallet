#!/usr/bin/env python3
"""Select and validate public LI.FI build settings; never load credentials."""

import argparse
import json
import os
import re
import shlex
import sys
from pathlib import Path
from urllib.parse import urlsplit


PUBLIC_DEFAULTS = {
    "LIFI_PROXY_URL": "https://quicknode.gleec.com/lifi",
    "LIFI_INTEGRATOR_ENABLED": "true",
    "LIFI_INTEGRATOR_NAME": "gleec-dex-production",
    "LIFI_INTEGRATOR_FEE_BPS": "178",
    "LIFI_FEE_BPS": "22",
}
PROFILES = {
    "production": ("docs/LIFI_PRODUCTION_BUILD_DEFINES.json", "gleec-dex-production"),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_build_defines(path=None):
    """Validate the allowlisted fields without including their values in errors."""
    values = PUBLIC_DEFAULTS.copy()
    if path is not None:
        try:
            values = json.loads(Path(path).read_text())
        except (OSError, ValueError):
            raise ValueError("Build defines must be a readable public JSON file") from None
    require(isinstance(values, dict) and set(values) == set(PUBLIC_DEFAULTS),
            "Only the five public LI.FI build defines are accepted; never supply credentials")
    require(all(isinstance(value, str) for value in values.values()),
            "LI.FI build define values must be strings")
    require(values["LIFI_INTEGRATOR_ENABLED"] == "true", "Fee validation requires the integrator enabled")
    require(values["LIFI_INTEGRATOR_NAME"] == "gleec-dex-production",
            "Only the production LI.FI integration is supported")
    require((values["LIFI_INTEGRATOR_FEE_BPS"], values["LIFI_FEE_BPS"]) == ("178", "22"),
            "This build policy requires the approved 178 + 22 bps allocation")
    try:
        raw_proxy = values["LIFI_PROXY_URL"]
        url = urlsplit(raw_proxy)
        _ = url.port
        valid_proxy = (url.scheme == "https" and url.hostname and url.username is None
                       and url.password is None and "?" not in raw_proxy and "#" not in raw_proxy
                       and not any(ord(char) <= 32 or ord(char) == 127 for char in raw_proxy))
    except ValueError:
        valid_proxy = False
    require(valid_proxy, "Proxy URL must be HTTPS without credentials, query or fragment")
    return values


def deployment_config(build_defines=None):
    """Map the same public build values to the wallet KDF startup contract."""
    values = load_build_defines(build_defines)
    return {
        "proxy": values["LIFI_PROXY_URL"],
        "integrator": {"name": values["LIFI_INTEGRATOR_NAME"], "fee_bps": 178, "lifi_fee_bps": 22},
    }


def select_build_config(environment, root=None):
    require(environment in PROFILES, "Only the production LI.FI build profile is supported")
    relative, integration = PROFILES[environment]
    root = Path(root) if root is not None else Path(__file__).resolve().parent.parent
    values = load_build_defines(root / relative)
    require(values["LIFI_INTEGRATOR_NAME"] == integration,
            "LI.FI integration identifier does not match the selected build environment")
    return relative


def event_environment(event, requested="production"):
    """Every event uses production; reject retired staging requests."""
    require(requested in PROFILES, "Only the production LI.FI build profile is supported")
    return "production"


def validate_build_command(command):
    """Reserve LI.FI defines and define files for the validated profile only.

    Do not load arbitrary files or include rejected command text in errors: a
    caller might accidentally supply a credential. Explicit defines (including
    Flutter's -D and --dart-defines aliases) override file values.
    """
    try:
        args = shlex.split(command)
    except ValueError:
        raise ValueError("Invalid build command quoting") from None
    require(args[:2] == ["flutter", "build"], "Expected a Flutter build command")
    require(not any("--dart-define-from-file" in arg for arg in args),
            "Additional define files are forbidden; select LIFI_BUILD_ENVIRONMENT")
    require(not re.search(r"LIFI_[A-Z0-9_]*\s*=", " ".join(args)),
            "Explicit LI.FI defines are forbidden; select LIFI_BUILD_ENVIRONMENT")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("environment", nargs="?", default="production")
    parser.add_argument("--event", help="Select the profile for a GitHub event")
    parser.add_argument("--validate-build-command", action="store_true",
                        help="Validate BUILD_COMMAND from the environment without printing it")
    args = parser.parse_args()
    try:
        environment = (event_environment(args.event, args.environment)
                       if args.event is not None else args.environment)
        relative = select_build_config(environment)
        if args.validate_build_command:
            validate_build_command(os.environ.get("BUILD_COMMAND", ""))
        print(environment if args.event is not None else relative)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
