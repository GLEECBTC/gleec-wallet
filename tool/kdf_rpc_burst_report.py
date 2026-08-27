#!/usr/bin/env python3
"""Turn the raw bench JSON into the before/after tables."""
import json
import statistics
import sys
from collections import defaultdict

ORDER = ["bd413dc", "ed8de23", "34ab0e7", "a86fa37", "4254e19", "25f6e1f"]
LABEL = {
    "bd413dc": "bd413dc  BEFORE (last shipped)",
    "ed8de23": "ed8de23  + concurrent gap scan",
    "34ab0e7": "34ab0e7  + pool lock released",
    "a86fa37": "a86fa37  + 429 backpressure",
    "4254e19": "4254e19  - single-node throttle",
    "25f6e1f": "25f6e1f  AFTER (shipped now)",
}


def rows(path):
    with open(path) as handle:
        payload = json.load(handle)
    grouped = defaultdict(list)
    for result in payload["results"]:
        grouped[result["sha"]].append(result)
    out = []
    for sha in ORDER:
        runs = grouped.get(sha)
        if not runs:
            continue
        metrics = [r.get("metrics", {}).get("all", {}) for r in runs]

        def med(key, default=0):
            values = [m.get(key) or default for m in metrics]
            return statistics.median(values) if values else 0

        seconds = [r.get("login_total_s") or r.get("activation_s") or 0 for r in runs]
        ok = sum(1 for r in runs if r.get("ok"))
        out.append({
            "sha": sha,
            "label": LABEL.get(sha, sha),
            "runs": len(runs),
            "ok": f"{ok}/{len(runs)}",
            "seconds": round(statistics.median(seconds), 2),
            "http": int(med("http_requests")),
            "peak": int(med("peak_req_per_s")),
            "first_s": int(med("requests_in_first_second")),
            "http_429": int(med("http_429")),
            "addrs": int(med("distinct_addresses")),
        })
    return payload, out


def table(title, payload, data):
    print()
    print(title)
    print(f"  mode={payload['mode']}  rate_limit={payload['rate_limit_per_s']}/s  "
          f"latency={payload.get('latency_ms')}ms  hd={payload['hd']}")
    print(f"  {'build':32} {'ok':>5} {'secs':>7} {'HTTP':>6} {'peak/s':>7} "
          f"{'1st s':>6} {'429':>5} {'addrs':>6}")
    print("  " + "-" * 84)
    for row in data:
        print(f"  {row['label']:32} {row['ok']:>5} {row['seconds']:>7} "
              f"{row['http']:>6} {row['peak']:>7} {row['first_s']:>6} "
              f"{row['http_429']:>5} {row['addrs']:>6}")


for path, title in [
    ("out/gleec_unlimited.json", "GLEEC platform coin only - node answers everything (offered load)"),
    ("out/gleec_limited.json", "GLEEC platform coin only - node serves 20 req/s, refuses the rest"),
    ("out/gleec_tokens_unlimited.json", "GLEEC + all 6 GRC-20 tokens - node answers everything"),
    ("out/gleec_tokens_limited.json", "GLEEC + all 6 GRC-20 tokens - node serves 20 req/s"),
]:
    try:
        payload, data = rows(path)
    except FileNotFoundError:
        continue
    table(title, payload, data)

# Method histogram and the address list, from one representative run.
try:
    with open("out/gleec_unlimited.json") as handle:
        payload = json.load(handle)
    for result in payload["results"]:
        if result["sha"] != "25f6e1f":
            continue
        summary = result["metrics"]["all"]
        print("\nWhat the 44 calls actually are (25f6e1f, one run):")
        for method, count in summary["methods"].items():
            print(f"  {count:>4}  {method}")
        print(f"\n  distinct addresses probed: {summary['distinct_addresses']}")
        for i, addr in enumerate(summary["addresses"][:25]):
            print(f"    {i}: {addr}")
        break
except FileNotFoundError:
    pass
