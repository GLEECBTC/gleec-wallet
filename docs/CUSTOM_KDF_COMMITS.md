# Custom KDF commit builds

The wallet pins Komodo DeFi Framework (KDF) artifacts in
`sdk/packages/komodo_defi_framework/app_build/build_config.json`.
To build against a **specific KDF commit** instead of the branch tip, run
`update_api_config.dart` with `-m` / `--commit`.

Initialize the SDK submodule first (`git submodule update --init --recursive`).
From the wallet repo root:

```bash
dart run sdk/packages/komodo_wallet_cli/bin/update_api_config.dart \
    --branch dev \
    --source mirror \
    --config sdk/packages/komodo_defi_framework/app_build/build_config.json \
    --output-dir sdk/packages/komodo_defi_framework/app_build/temp_downloads \
    -m 9aa41b4
```

The script finds artifacts for that commit, writes their SHA-256 checksums into
`build_config.json`, and sets `api.api_commit_hash`. A short hash is resolved to
the full SHA when GitHub can see the commit.

If you are already inside the SDK checkout, drop the `sdk/` prefix on the
script and config paths. Flag help also lives in the
[SDK CLI README](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/blob/main/packages/komodo_wallet_cli/README.md).

## Flags

| Flag | Meaning |
| --- | --- |
| `-b`, `--branch <name>` | Branch used to locate artifacts (default: `main`) |
| `-m`, `--commit <hash>` | Pin this commit (short or full). Skips "latest on branch" |
| `-s`, `--source` (`github` or `mirror`) | Where to fetch artifacts (default: `github`) |
| `--mirror-url <url>` | Mirror base URL (default: `https://devbuilds.gleec.com`) |
| `-c`, `--config <path>` | Path to `build_config.json` |
| `-o`, `--output-dir <dir>` | Temp download directory (removed after the run) |
| `-p`, `--platform` (`web`, `macos`, … or `all`) | One platform or `all` (default: `all`) |
| `--repo <owner/repo>` | Artifact repo (default: `GLEECBTC/komodo-defi-framework`) |
| `-t`, `--token <token>` | GitHub token, or env `GITHUB_API_PUBLIC_READONLY_TOKEN` |
| `-v`, `--verbose` | Verbose logging |
| `--strict` / `--no-strict` | Require exact commit-matching assets (strict is the default) |
| `-h`, `--help` | Print usage |

`--branch` still matters with `-m`: the mirror layout is branch-scoped
(`…/<branch>/`), so the commit has to exist under that branch on the source you
picked.

After the config updates, a real Flutter asset build fetches the binaries
(see [Build release](BUILD_RELEASE.md)). For the full publish-and-verify path,
see [Shipping a KDF change](KDF_RELEASE_RUNBOOK.md).
