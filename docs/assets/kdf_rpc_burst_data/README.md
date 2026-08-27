# KDF RPC burst data

The raw JSON captures behind `docs/KDF_RPC_BURST_REPORT.md` are no longer
committed here. They were ~11,300 lines of machine-generated benchmark output
that every clone carried forever and that nobody reads during review.

## Retrieving the original captures

This is the only way to get *these* numbers back. They remain in git history on
`add/gas-free-tron` at `ca0212a1b31b`:

```sh
git checkout ca0212a1b31b -- docs/assets/kdf_rpc_burst_data/
git show ca0212a1b31b:docs/assets/kdf_rpc_burst_data/gleec_limited.json
```

Keep that SHA with the report if this branch is ever squash-merged, since the
tree would not otherwise survive.

## Regenerating is NOT reproducing

`tool/kdf_rpc_burst_bench.py` will happily produce fresh captures into `out/`,
which is where `tool/kdf_rpc_burst_report.py` reads from:

```sh
python3 tool/kdf_rpc_burst_bench.py     # writes out/*.json
python3 tool/kdf_rpc_burst_report.py    # renders the tables
```

But that gives you **new measurements against today's KDF, not the report's
numbers**. The report's tables were measured against a ladder of nine KDF
commits — `bd413dc`, `ed8de23`, `34ab0e7`, `25f6e1f`, `407cf6c0`, `4254e19`,
`a86fa37`, `d56a7bc`, `08d2228e` — and **none of them is reachable from the SDK
submodule any more** (the fork they lived on is gone; the wallet now pins KDF
`main`). Re-running the bench cannot recreate that ladder.

So treat the tables in `KDF_RPC_BURST_REPORT.md` as a historical record whose
inputs are recoverable only from the SHA above, and do not present a fresh
bench run as a reproduction of them.
