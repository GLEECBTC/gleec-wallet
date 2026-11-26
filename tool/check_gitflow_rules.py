#!/usr/bin/env python3
"""Read-only comparison of GitHub's merge-method rules with versioned policy."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


def mismatches(expected, actual, path=""):
    """Compare managed fields; GitHub may add optional response defaults."""
    errors = []
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            return [path + ": expected an object"]
        for key, value in expected.items():
            errors += mismatches(value, actual.get(key), f"{path}.{key}")
    elif isinstance(expected, list):
        if not isinstance(actual, list) or len(expected) != len(actual):
            return [path + ": list differs"]
        if expected and all(isinstance(item, dict) and "type" in item for item in expected):
            actual = sorted(actual, key=lambda item: item.get("type", ""))
            expected = sorted(expected, key=lambda item: item["type"])
        elif all(isinstance(item, str) for item in expected):
            actual, expected = sorted(actual), sorted(expected)
        for index, value in enumerate(expected):
            errors += mismatches(value, actual[index], f"{path}[{index}]")
    elif type(expected) is not type(actual) or expected != actual:
        errors.append(f"{path}: expected {expected!r}, got {actual!r}")
    return errors


def api(path):
    result = subprocess.run(["gh", "api", path], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def check(repo, directory):
    errors = []
    settings = api(f"repos/{repo}")
    for key, value in {"allow_merge_commit": True, "allow_squash_merge": True, "allow_rebase_merge": False}.items():
        errors += mismatches(value, settings.get(key), key)
    summaries = []
    page = 1
    while True:
        batch = api(f"repos/{repo}/rulesets?includes_parents=true&per_page=100&page={page}")
        summaries.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    for path in sorted(directory.glob("gitflow-*.json")):
        policy = json.loads(path.read_text())
        matches = [item for item in summaries if item["name"] == policy["name"] and item.get("source") == repo]
        if len(matches) != 1:
            errors.append(policy["name"] + ": expected exactly one repository ruleset")
            continue
        live = api(f"repos/{repo}/rulesets/{matches[0]['id']}")
        errors += mismatches(policy, live, policy["name"])
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"{repo}: versioned Gitflow merge rules match active GitHub settings")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, help="GitHub owner/repository")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        parser.error("--repo must be owner/repository")
    directory = Path(__file__).resolve().parents[1] / ".github" / "rulesets"
    if len(list(directory.glob("gitflow-*.json"))) != 2:
        parser.error("expected the two versioned Gitflow rule profiles")
    try:
        return check(args.repo, directory)
    except (subprocess.CalledProcessError, json.JSONDecodeError, OSError) as error:
        print(f"Cannot audit GitHub rules: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
