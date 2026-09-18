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
        """Max of one FD type over the whole run.

        Deliberately independent of `peak`: the total peak and a given type's
        peak happen at different instants, and the two must never be presented
        as one measurement. Summing `peak.by_type` across types, or pairing
        `peak.total` with `peak_of("socket")`, describes a state the process
        was never in.
        """
        return max((s.by_type.get(kind, 0) for s in self.samples), default=0)

    def median_total(self) -> float:
        return statistics.median(s.total for s in self.samples) if self.samples else 0.0

    def at_time(self, when: float, window: float = 2.0) -> Optional[Sample]:
        """The sample nearest `when` seconds into the run, if one is close."""
        if not self.samples:
            return None
        nearest = min(self.samples, key=lambda s: abs(s.at - when))
        return nearest if abs(nearest.at - when) <= window else None

    def idle_floor(self, idle_from: float) -> Optional[Sample]:
        """The lowest reading after activation stopped issuing requests.

        Only meaningful when the run actually held the process idle: without an
        idle period this measures teardown, not steady state, and a build whose
        activation happened to finish mid-burst looks worse than one that did
        not. See `--idle-seconds`.
        """
        tail = [s for s in self.samples if s.at >= idle_from]
        return min(tail, key=lambda s: s.total) if tail else None


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
            began = time.time()
            counts = read_fd_table(self._pid)
            if counts is not None:
                self.trace.samples.append(
                    Sample(
                        at=began - self.trace.started,
                        total=sum(counts.values()),
                        by_type=dict(counts),
                    )
                )
            # Subtract the read: waiting a full interval *after* the read makes
            # the true period interval + read time, which quietly inflates the
            # stated sampling rate (25ms nominal measured out at ~29ms).
            self._stop.wait(max(0.0, self.interval - (time.time() - began)))

    def stop(self) -> None:
        self._stop.set()


def patch_electrum_max_connected(max_connected: int) -> None:
    """Make the probe's electrum activation match what the app actually sends.

    `kdf_latency_probe.utxo_activation_params` omits `max_connected`, and KDF
    defaults it to the *server count*: 6-12 per UTXO coin in the shipped config
    (12 sockets across `app-default`'s two, 30 across the top20 sets' four, and
    proportionally more for a long `--coin-list`). The app sends
    `max_connected: 1` (`activation_params.dart`:
    `'max_connected': (maxConnected ?? 1)`), so an unpatched probe holds many
    times more electrum sockets than the thing it is standing in for, and those
    sockets are long-lived by design - they never drain, which reads as a pool
    that will not release.

    Patched here rather than in the latency probe because that script's
    recorded baselines were measured with the current behaviour, and silently
    changing what they mean is worse than the narrow duplication.
    """
    original = probe.utxo_activation_params

    def with_max_connected(*args, **kwargs):
        params = original(*args, **kwargs)
        rpc_data = params.get("mode", {}).get("rpc_data")
        if isinstance(rpc_data, dict) and max_connected > 0:
            rpc_data["min_connected"] = 1
            rpc_data["max_connected"] = max_connected
        return params

    probe.utxo_activation_params = with_max_connected


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
    idle_seconds: float,
    verbose: bool,
) -> dict:
    sampler = FdSampler(interval)
    sampler.start()

    # Wrap rather than reimplement: `run_scenario` owns the KdfProcess, and the
    # pid is the only thing needed from it.
    original_start = probe.KdfProcess.start
    original_stop = probe.KdfProcess.stop
    idle_began: List[float] = []

    def start_and_attach(self, timeout: float = 60.0):
        original_start(self, timeout)
        sampler.attach(self.proc.pid)

    def idle_then_stop(self):
        # `run_scenario` goes from the last RPC straight to stop, so without
        # this the tail measures a dying process rather than a resting one -
        # and nothing ever waits out HYPER_POOLED's 20s idle timeout, which is
        # the only way to tell a transient connect burst from a held pool.
        if idle_seconds > 0 and not idle_began:
            idle_began.append(time.time() - sampler.trace.started)
            print(f"    holding idle {idle_seconds:.0f}s to watch the pool drain...",
                  flush=True)
            time.sleep(idle_seconds)
        original_stop(self)

    probe.KdfProcess.start = start_and_attach
    probe.KdfProcess.stop = idle_then_stop
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
        probe.KdfProcess.stop = original_stop
        sampler.stop()
        sampler.join(timeout=5)

    trace = sampler.trace
    peak = trace.peak
    idle_at = idle_began[0] if idle_began else None

    # Sampled across the idle hold, so a pool that drains and one that does not
    # are distinguishable. `+2` skips the moment activation stopped.
    drain = {}
    if idle_at is not None:
        for label_, offset in (("idle_5s", 5), ("idle_15s", 15), ("idle_25s", 25)):
            sample = trace.at_time(idle_at + offset)
            if sample:
                drain[label_] = {
                    "total": sample.total,
                    "sockets": sample.by_type.get("socket", 0),
                }
        floor = trace.idle_floor(idle_at + 2)
        if floor:
            drain["floor_total"] = floor.total
            drain["floor_sockets"] = floor.by_type.get("socket", 0)

    return {
        "label": label,
        "binary": binary,
        "error": result.error,
        "wall_seconds": result.total_seconds,
        "samples": len(trace.samples),
        "peak_total": peak.total if peak else 0,
        "peak_at_seconds": round(peak.at, 2) if peak else 0,
        # A snapshot of one instant - the instant total peaked. NOT a
        # decomposition of any other number here.
        "peak_by_type_at_total_peak": peak.by_type if peak else {},
        # Independent maxima, each from its own instant. Never sum these.
        "max_by_type": {
            kind: trace.peak_of(kind)
            for kind in ("socket", "kqueue", "vnode", "pipe", "netpolicy")
            if trace.peak_of(kind)
        },
        "median_total": round(trace.median_total(), 1),
        "idle_seconds": idle_seconds,
        "drain": drain,
    }


IOS_SOFT_LIMIT = 256


def print_report(runs: List[dict], meta: dict, electrum_max_connected: int) -> None:
    print()
    print("=" * 78)
    print("KDF peak file-descriptor usage during activation")
    print("=" * 78)
    for key, value in meta.items():
        print(f"  {key}: {value}")
    print()

    header = f"{'build':<14} {'peak fd':>8} {'max sock':>9} {'max kq':>7} {'median':>8} {'peak at':>9} {'wall':>8}"
    print(header)
    print("-" * len(header))
    for run in runs:
        if run["error"]:
            print(f"{run['label']:<14} FAILED: {run['error']}")
            continue
        m = run["max_by_type"]
        print(
            f"{run['label']:<14} {run['peak_total']:>8} {m.get('socket', 0):>9} "
            f"{m.get('kqueue', 0):>7} {run['median_total']:>8} "
            f"{run['peak_at_seconds']:>8.1f}s {run['wall_seconds']:>7.1f}s"
        )

    ok = [r for r in runs if not r["error"]]

    print()
    print("'peak fd' is the highest total at one instant. 'max sock' and 'max kq'")
    print("are each that type's own maximum, from their own instants - they do not")
    print("co-occur and must not be added to each other or to 'peak fd'.")

    for run in ok:
        print()
        print(f"  {run['label']}:")
        print("    at the total peak: " + " ".join(
            f"{k}={v}" for k, v in
            sorted(run["peak_by_type_at_total_peak"].items(), key=lambda kv: -kv[1])
        ))
        if run["drain"]:
            d = run["drain"]
            points = " ".join(
                f"{k.replace('idle_', '+')}={d[k]['total']}fd/{d[k]['sockets']}sock"
                for k in ("idle_5s", "idle_15s", "idle_25s") if k in d
            )
            print(f"    draining over {run['idle_seconds']:.0f}s idle: {points}")
            if "floor_total" in d:
                print(f"    idle floor: {d['floor_total']} fd, {d['floor_sockets']} sockets")
        elif run["idle_seconds"] == 0:
            print("    (no idle hold - steady state not measured; pass --idle-seconds)")

    print()
    print(f"Against the iOS soft RLIMIT_NOFILE of {IOS_SOFT_LIMIT}:")
    for run in ok:
        pct = run["peak_total"] / IOS_SOFT_LIMIT * 100
        print(f"  {run['label']:<14} {run['peak_total']:>4}/{IOS_SOFT_LIMIT} ({pct:.0f}%)")

    if len(ok) == 2:
        before, after = ok
        print()
        print(f"Delta ({after['label']} - {before['label']}): "
              f"peak fd {after['peak_total'] - before['peak_total']:+d}, "
              f"max sockets {after['max_by_type'].get('socket', 0) - before['max_by_type'].get('socket', 0):+d}")

    print()
    print("Caveats:")
    print("  * KDF alone. The app's own descriptors - Flutter, Hive, sockets")
    print("    outside KDF - sit on top of these numbers.")
    if electrum_max_connected > 0:
        print(f"  * Electrum is pinned to max_connected: {electrum_max_connected}, "
              "matching what the app")
        print("    sends (activation_params.dart). KDF's own default is the server")
        print("    count, so an unpinned run is not comparable to this one.")
    else:
        print("  * Electrum connections are overstated relative to the app. The app")
        print("    sends max_connected: 1 (activation_params.dart); this run sends")
        print("    nothing, so KDF defaults it to the server count.")
    print("  * n=1 per build. Endpoint health varies run to run; repeat before")
    print("    drawing a fine conclusion.")


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
    parser.add_argument(
        "--coin-list",
        help="Comma-separated tickers, overriding --coin-set. Use for portfolios "
             "larger than any named set - the FD ceiling scales with the number "
             "of distinct EVM platform chains, so a long list is the case that "
             "actually stresses it.",
    )
    parser.add_argument("--wallet-type", choices=["hd", "iguana"], default="hd")
    parser.add_argument("--gap-limit", type=int, default=20)
    parser.add_argument("--scan-policy", default="scan_if_new_wallet")
    parser.add_argument("--port", type=int, default=probe.DEFAULT_PORT)
    parser.add_argument(
        "--interval", type=float, default=0.025,
        help="Sampling period in seconds (default 25ms)",
    )
    parser.add_argument(
        "--electrum-max-connected", type=int, default=1,
        help="What to send as electrum max_connected. Default 1, matching the "
             "app. 0 omits it, which makes KDF default to the server count "
             "(12 sockets across app-default, 30 across top20) and inflates "
             "the socket numbers.",
    )
    parser.add_argument(
        "--idle-seconds", type=float, default=0,
        help="Hold KDF idle this long after activation before stopping it, "
             "sampling throughout. Needs to exceed HYPER_POOLED's 20s "
             "pool_idle_timeout to tell a transient connect burst from a "
             "pool that stays held. 0 skips it (steady state unmeasured).",
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

    if args.coin_list:
        tickers = [t.strip() for t in args.coin_list.split(",") if t.strip()]
        unknown = [t for t in tickers if t not in coins_index]
        if unknown:
            print(f"Not in the coins config: {', '.join(unknown)}", file=sys.stderr)
            return 2
        set_label = f"custom ({len(tickers)} coins)"
    else:
        tickers = probe.COIN_SETS[args.coin_set]
        set_label = args.coin_set

    patch_electrum_max_connected(args.electrum_max_connected)

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
            idle_seconds=args.idle_seconds,
            verbose=args.verbose,
        ))

    meta = {
        "coin set": f"{set_label} ({', '.join(tickers)})",
        "wallet type": args.wallet_type,
        "gap limit": args.gap_limit,
        "sampling": f"{args.interval * 1000:.0f}ms",
        "idle hold": f"{args.idle_seconds:.0f}s" if args.idle_seconds else "none",
        "electrum max_connected": (args.electrum_max_connected or "unset (KDF default = server count)"),
        "coins config": coins_path,
    }
    print_report(runs, meta, args.electrum_max_connected)

    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump({"meta": meta, "runs": runs}, handle, indent=2)
        print(f"\nWrote {args.json}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
