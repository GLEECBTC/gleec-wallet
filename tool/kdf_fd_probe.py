#!/usr/bin/env python3
"""Peak file-descriptor usage of a KDF binary during activation.

Answers one question: does a given KDF build come close to exhausting the FD
table on iOS, where the soft `RLIMIT_NOFILE` is 256 for an app process and KDF
is a static library sharing that budget with Flutter, the network stack and
everything else in the process.

Why measure here rather than on the device: the quantity at issue is how many
sockets KDF's own networking holds open at once, which is a property of the
Rust code and is identical on every native target. The device contributes only
the *limit* to compare against, which is a constant. Measuring a spawned binary
costs no signing, no wallet, and no hardware, and it samples fast enough to see
a burst that a 60s in-app poll cannot.

    python3 tool/kdf_fd_probe.py --kdf before=/path/kdf --kdf after=/path/kdf

Pass `--port` if the wallet itself is running: it holds 7783, which is also
this probe's default, and the run fails rather than disturbing it.

Reuses `kdf_latency_probe` wholesale for the activation itself, so the workload
is exactly the one the latency work measured, down to the seed and coin set.
The only addition is a sampler thread reading the child's FD table.

macOS only: it reads the FD table through `proc_pidinfo`, which has no portable
equivalent. On Linux the same numbers come from `/proc/<pid>/fd`.
"""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import json
import os
import statistics
import sys
import threading
import time
from collections import Counter
from dataclasses import dataclass, field
from typing import Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import kdf_latency_probe as probe  # noqa: E402

# <sys/proc_info.h>. `struct proc_fdinfo` is {int32 proc_fd; uint32 proc_fdtype}.
PROC_PIDLISTFDS = 1
PROC_FDINFO_SIZE = 8

FD_TYPES = {
    0: "atalk",
    1: "vnode",  # files, directories
    2: "socket",  # the one that tracks KDF's networking
    3: "pshm",
    4: "psem",
    5: "kqueue",
    6: "pipe",
    7: "fsevents",
    9: "netpolicy",
    10: "channel",
}

_libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
_libc.proc_pidinfo.restype = ctypes.c_int
_libc.proc_pidinfo.argtypes = [
    ctypes.c_int,  # pid
    ctypes.c_int,  # flavor
    ctypes.c_uint64,  # arg
    ctypes.c_void_p,  # buffer
    ctypes.c_int,  # buffersize
]


def read_fd_table(pid: int) -> Optional[Counter]:
    """FD type counts for `pid`, or None if the process is gone.

    Two calls: the first sizes the table, the second fills it. The size can
    grow between them, which only ever undercounts by the growth - acceptable
    for a sampler, and cheaper than looping to a fixed point at 25ms.
    """
    needed = _libc.proc_pidinfo(pid, PROC_PIDLISTFDS, 0, None, 0)
    if needed <= 0:
        return None

    buf = ctypes.create_string_buffer(needed)
    written = _libc.proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buf, needed)
    if written <= 0:
        return None

    counts: Counter = Counter()
    raw = buf.raw
    for offset in range(0, (written // PROC_FDINFO_SIZE) * PROC_FDINFO_SIZE, PROC_FDINFO_SIZE):
        fdtype = int.from_bytes(raw[offset + 4:offset + 8], sys.byteorder)
        counts[FD_TYPES.get(fdtype, f"type{fdtype}")] += 1
    return counts


@dataclass
class Sample:
    at: float
    total: int
    by_type: Dict[str, int]


@dataclass
class FdTrace:
    samples: List[Sample] = field(default_factory=list)
    started: float = 0.0

    @property
    def peak(self) -> Optional[Sample]:
        return max(self.samples, key=lambda s: s.total) if self.samples else None

    def peak_of(self, kind: str) -> int:
        return max((s.by_type.get(kind, 0) for s in self.samples), default=0)

    def median_total(self) -> float:
        return statistics.median(s.total for s in self.samples) if self.samples else 0.0

    def settled(self, tail_seconds: float = 5.0) -> Optional[Sample]:
        """The last sample, i.e. what the process holds once activation is done.

        This is what a periodic in-app poll would have seen, and the gap
        between it and `peak` is exactly the blind spot the watermark exists
        to close.
        """
        if not self.samples:
            return None
        cutoff = self.samples[-1].at - tail_seconds
        tail = [s for s in self.samples if s.at >= cutoff]
        return min(tail, key=lambda s: s.total) if tail else self.samples[-1]


class FdSampler(threading.Thread):
    """Polls one child process's FD table until told to stop."""

    def __init__(self, interval: float) -> None:
        super().__init__(daemon=True)
        self.interval = interval
        self.trace = FdTrace()
        self._pid: Optional[int] = None
        self._stop = threading.Event()
        self._attached = threading.Event()

    def attach(self, pid: int) -> None:
        self._pid = pid
        self.trace.started = time.time()
        self._attached.set()

    def run(self) -> None:
        self._attached.wait()
        while not self._stop.is_set():
            counts = read_fd_table(self._pid)
            if counts is not None:
                self.trace.samples.append(
                    Sample(
                        at=time.time() - self.trace.started,
                        total=sum(counts.values()),
                        by_type=dict(counts),
                    )
                )
            self._stop.wait(self.interval)

    def stop(self) -> None:
        self._stop.set()


def run_one(
    *,
    label: str,
    binary: str,
    seed: str,
    coins_index: Dict[str, dict],
    tickers: List[str],
    wallet_type: str,
    gap_limit: int,
    scan_policy: str,
    port: int,
    interval: float,
    verbose: bool,
) -> dict:
    sampler = FdSampler(interval)
    sampler.start()

    # Wrap rather than reimplement: `run_scenario` owns the KdfProcess, and the
    # pid is the only thing needed from it.
    original_start = probe.KdfProcess.start

    def start_and_attach(self, timeout: float = 60.0):
        original_start(self, timeout)
        sampler.attach(self.proc.pid)

    probe.KdfProcess.start = start_and_attach
    try:
        result = probe.run_scenario(
            binary=binary,
            coins_index=coins_index,
            seed=seed,
            tickers=tickers,
            wallet_type=wallet_type,
            gap_limit=gap_limit,
            scan_policy=scan_policy,
            port=port,
            keep_workdir=False,
            verbose=verbose,
            label=label,
        )
    finally:
        probe.KdfProcess.start = original_start
        sampler.stop()
        sampler.join(timeout=5)

    trace = sampler.trace
    peak = trace.peak
    settled = trace.settled()

    return {
        "label": label,
        "binary": binary,
        "error": result.error,
        "wall_seconds": result.total_seconds,
        "samples": len(trace.samples),
        "peak_total": peak.total if peak else 0,
        "peak_at_seconds": round(peak.at, 2) if peak else 0,
        "peak_by_type": peak.by_type if peak else {},
        "peak_sockets": trace.peak_of("socket"),
        "median_total": round(trace.median_total(), 1),
        "settled_total": settled.total if settled else 0,
        "settled_sockets": settled.by_type.get("socket", 0) if settled else 0,
    }


IOS_SOFT_LIMIT = 256


def print_report(runs: List[dict], meta: dict) -> None:
    print()
    print("=" * 78)
    print("KDF peak file-descriptor usage during activation")
    print("=" * 78)
    for key, value in meta.items():
        print(f"  {key}: {value}")
    print()

    header = f"{'build':<14} {'peak fd':>8} {'peak sock':>10} {'settled':>8} {'median':>8} {'peak at':>9} {'wall':>8}"
    print(header)
    print("-" * len(header))
    for run in runs:
        if run["error"]:
            print(f"{run['label']:<14} FAILED: {run['error']}")
            continue
        print(
            f"{run['label']:<14} {run['peak_total']:>8} {run['peak_sockets']:>10} "
            f"{run['settled_total']:>8} {run['median_total']:>8} "
            f"{run['peak_at_seconds']:>8.1f}s {run['wall_seconds']:>7.1f}s"
        )

    ok = [r for r in runs if not r["error"]]
    print()
    for run in ok:
        print(f"  {run['label']} peak breakdown: " + " ".join(
            f"{k}={v}" for k, v in sorted(run["peak_by_type"].items(), key=lambda kv: -kv[1])
        ))

    print()
    print(f"Against the iOS soft RLIMIT_NOFILE of {IOS_SOFT_LIMIT}:")
    for run in ok:
        pct = run["peak_total"] / IOS_SOFT_LIMIT * 100
        print(f"  {run['label']:<14} {run['peak_total']:>4}/{IOS_SOFT_LIMIT} ({pct:.0f}%)")

    if len(ok) == 2:
        before, after = ok
        d_peak = after["peak_total"] - before["peak_total"]
        d_sock = after["peak_sockets"] - before["peak_sockets"]
        print()
        print(f"Delta ({after['label']} - {before['label']}): "
              f"peak {d_peak:+d} fd, peak sockets {d_sock:+d}")

    print()
    print("Caveats: this is the KDF process alone, so the app's own descriptors")
    print("(Flutter, Hive, sockets outside KDF) sit on top of these numbers.")
    print("Endpoint behaviour varies run to run - a node that answers on HTTP/1.1")
    print("instead of h2 costs one socket per concurrent request rather than one")
    print("per host, so repeat before drawing a fine conclusion.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--kdf",
        action="append",
        required=True,
        metavar="LABEL=PATH",
        help="A KDF binary to measure. Repeat to compare builds.",
    )
    parser.add_argument("--coins", help="Path to coins_config.json")
    parser.add_argument(
        "--coin-set",
        default="app-default",
        choices=sorted(probe.COIN_SETS),
        help="Which coin set to activate (default: what a real login enables)",
    )
    parser.add_argument("--wallet-type", choices=["hd", "iguana"], default="hd")
    parser.add_argument("--gap-limit", type=int, default=20)
    parser.add_argument("--scan-policy", default="scan_if_new_wallet")
    parser.add_argument("--port", type=int, default=probe.DEFAULT_PORT)
    parser.add_argument(
        "--interval", type=float, default=0.025,
        help="Sampling period in seconds (default 25ms)",
    )
    parser.add_argument("--json", help="Write the full result here")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if sys.platform != "darwin":
        print("This probe reads the FD table via proc_pidinfo (macOS only).",
              file=sys.stderr)
        return 2

    binaries: List[tuple] = []
    for entry in args.kdf:
        label, _, path = entry.partition("=")
        if not path:
            label, path = os.path.basename(os.path.dirname(label)) or "kdf", label
        if not os.path.exists(path):
            print(f"No such KDF binary: {path}", file=sys.stderr)
            return 2
        binaries.append((label, os.path.abspath(path)))

    # Same contract as the latency probe: a throwaway seed from the environment.
    # This starts a real KDF that talks to real servers.
    seed = os.environ.get("KDF_TEST_SEED", "").strip()
    if not seed:
        print(
            "KDF_TEST_SEED is not set.\n"
            "  export KDF_TEST_SEED='abandon abandon abandon abandon abandon "
            "abandon abandon abandon abandon abandon abandon about'\n"
            "Use a throwaway seed - the seed is passed as argv to the spawned "
            "process and is readable by any local user while it runs.",
            file=sys.stderr,
        )
        return 2

    coins_path = probe.find_coins_config(args.coins)
    if not coins_path:
        print("Could not find coins_config.json (pass --coins)", file=sys.stderr)
        return 2

    with open(coins_path, encoding="utf-8") as handle:
        raw_coins = json.load(handle)
    coins_index = raw_coins if isinstance(raw_coins, dict) else {
        c["coin"]: c for c in raw_coins
    }

    tickers = probe.COIN_SETS[args.coin_set]

    runs = []
    for label, path in binaries:
        print(f"\n--- {label}: {path} ---", flush=True)
        runs.append(run_one(
            label=label,
            binary=path,
            seed=seed,
            coins_index=coins_index,
            tickers=tickers,
            wallet_type=args.wallet_type,
            gap_limit=args.gap_limit,
            scan_policy=args.scan_policy,
            port=args.port,
            interval=args.interval,
            verbose=args.verbose,
        ))

    meta = {
        "coin set": f"{args.coin_set} ({', '.join(tickers)})",
        "wallet type": args.wallet_type,
        "gap limit": args.gap_limit,
        "sampling": f"{args.interval * 1000:.0f}ms",
        "coins config": coins_path,
    }
    print_report(runs, meta)

    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump({"meta": meta, "runs": runs}, handle, indent=2)
        print(f"\nWrote {args.json}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
