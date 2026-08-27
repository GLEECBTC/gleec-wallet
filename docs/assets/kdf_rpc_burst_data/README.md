# KDF RPC burst data

The raw JSON captures that back `docs/KDF_RPC_BURST_REPORT.md` are no longer
committed here. They were ~11,300 lines of machine-generated benchmark output
that every clone carried forever and that nobody reads during review.

## Regenerating

`tool/kdf_rpc_burst_bench.py` writes fresh captures to `out/`, which is where
`tool/kdf_rpc_burst_report.py` already reads them from:

```sh
python3 tool/kdf_rpc_burst_bench.py     # writes out/*.json
python3 tool/kdf_rpc_burst_report.py    # renders the tables in the report
```

## Retrieving the original captures

They remain in git history on `add/gas-free-tron` at `ca0212a1b31b`:

```sh
git show ca0212a1b31b:docs/assets/kdf_rpc_burst_data/gleec_limited.json
git checkout ca0212a1b31b -- docs/assets/kdf_rpc_burst_data/
```

Keep that SHA with the report if this branch is ever squash-merged, since the
tree would not otherwise survive.
