# Shipping a KDF change to the app

End-to-end runbook for taking a change in the Rust KDF and getting it in front
of the app: push → build all seven targets → publish to Cloudflare R2 → point
the SDK at it → verify it actually arrived → validate it in the app.

Three repos are involved and none of them is a submodule of another:

| repo | role |
|---|---|
| `komodo-defi-framework` (sibling checkout) | the Rust source. **All code edits happen here.** |
| `nitride-kdf-builds` (sibling checkout) | builds the seven platform artifacts and publishes them |
| this repo | consumes the artifact, and holds the probes/harness that validate it |

> Only doing local measurement, not shipping? You do **not** need any of this.
> `cargo build --release --target aarch64-apple-darwin --bin kdf` and point the
> probe at the binary with `--kdf`. See
> [`HANDOFF_EVM_ACTIVATION_LATENCY.md`](HANDOFF_EVM_ACTIVATION_LATENCY.md).

---

## 0. Before you start

* **Docker running** (Linux and Android targets build in the upstream CI image).
* `wasm-pack`, `cargo-xwin`, `lipo` — `local_release.py --install-missing`
  installs the first two and the Rust targets.
* Publishing credentials, **one of**:
  * `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_R2_ACCESS_KEY_ID`,
    `CLOUDFLARE_R2_SECRET_ACCESS_KEY` → use `local_release.py deploy`, or
  * an authenticated `wrangler` session (`wrangler whoami`) → use
    `wrangler_backfill.py`.
* Budget ~40-60 min for a cold seven-target build. The Android leg alone
  downloads a 691 MB NDK.

---

## 1. Push the KDF branch

```bash
cd ../komodo-defi-framework
git push -u fork <your-branch>
```

**`fork` only.** The remotes are:

| remote | points at | push here? |
|---|---|---|
| `fork` | `CharlVS/komodo-defi-framework` | **yes** |
| `origin` | `GLEECBTC/kdf-internal` | no |
| `upstream` | `KomodoPlatform/komodo-defi-framework` | no |

---

## 2. Build all seven targets

```bash
cd ../nitride-kdf-builds
KDF_REPO=$(cd ../komodo-defi-framework && pwd)

python3 scripts/local_release.py run \
  --kdf-repo "$KDF_REPO" \
  --expect-commit "$(git -C "$KDF_REPO" rev-parse HEAD)" \
  --expect-branch "$(git -C "$KDF_REPO" rev-parse --abbrev-ref HEAD)" \
  --install-missing --start-docker --no-serve
```

The `--expect-*` guards are the point: they fail the run if the checkout moves
underneath you, so the artifacts always correspond to a known commit.

Output lands in `public/<safe-branch>/` with a `manifest.json`. The run
self-validates — recomputes every SHA-256, tests each ZIP, checks architectures
with `file`/`lipo`/`llvm-objdump`, and runs the macOS universal binary with
`--version`.

> **The KDF worktree must be clean**, or the run refuses to start. If the dirt
> is untracked files that are *not* build inputs (notes, scratch scripts), add
> them to `.git/info/exclude` — local-only, never committed, and it preserves
> the guarantee that the build matches the commit. Do **not** delete someone's
> files, and do not exclude modified tracked files.

---

## 3. Publish to Cloudflare R2

With R2 S3 credentials:

```bash
python3 scripts/local_release.py deploy \
  --kdf-repo "$KDF_REPO" \
  --expect-commit "$KDF_COMMIT" --expect-branch "$KDF_BRANCH" \
  --platform all --provider cloudflare
```

With only a wrangler session — **dry run first**:

```bash
python3 scripts/wrangler_backfill.py --dry-run --jobs 4
python3 scripts/wrangler_backfill.py --jobs 4
```

Both are additive and never delete remote objects. `wrangler_backfill.py`
reuploads *all* selected keys including historical branches, so expect ~100
objects even for one new build.

Confirm the mirror actually serves it:

```bash
curl -s https://kdf-dev-builds.nitride.app/<safe-branch>/manifest.json | head -20
```

> `source_urls` in the SDK config historically leads with
> `https://nitride-kdf-builds.web.app` — that is **Firebase**, a different
> target. If you published to R2 only, Firebase cannot serve your commit. Either
> deploy to both (`--provider all`) or make sure the R2 host is in `source_urls`
> (step 4).

---

## 4. Point the SDK at the new artifact

Edit `sdk/packages/komodo_defi_framework/app_build/build_config.json`:

* `api.api_commit_hash` → the full commit SHA
* `api.branch` → the branch name
* `api.platforms.<each>.valid_zip_sha256_checksums` → the new checksums
* `api.source_urls` → must contain the host you actually published to

**Take the checksums from the manifest, not from the build log.** A single
mistyped checksum fails the download at verification with an error that looks
like a network problem:

```bash
python3 - <<'PY'
import json
man = json.load(open('../nitride-kdf-builds/public/<safe-branch>/manifest.json'))
by = {a['platform']: a for a in man['artifacts']}
p = 'sdk/packages/komodo_defi_framework/app_build/build_config.json'
cfg = json.load(open(p)); api = cfg['api']
api['api_commit_hash'] = man['commit']
api['branch'] = man['branch']
missing = [k for k in api['platforms'] if k not in by]
assert not missing, f"manifest missing platforms: {missing}"
for name, entry in api['platforms'].items():
    entry['valid_zip_sha256_checksums'] = [by[name]['sha256']]
with open(p, 'w') as f:
    json.dump(cfg, f, indent=2); f.write('\n')
print('updated to', man['commit'][:7])
PY
```

> **Watch `bundled_coins_repo_commit` in the same file.** The build transformer
> rewrites it to whatever the coins repo currently points at, on every build and
> every `flutter test`. That is a separate concern from the KDF artifact — leave
> it at its committed value unless you *intend* to ship new coin definitions,
> otherwise an unrelated coins bump rides along in your diff.

---

## 5. Fetch and verify

The transformer only runs during a **real asset build**. `--config-only` does
not trigger it.

```bash
rm -f sdk/packages/komodo_defi_framework/macos/bin/kdf   # force a refetch
flutter build web --release \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=<url> \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=<address>
```

Then check what actually landed — do not assume:

```bash
sdk/packages/komodo_defi_framework/macos/bin/kdf --version
strings sdk/packages/komodo_defi_framework/web/kdf/bin/kdflib_bg.wasm \
  | grep -oE '3\.0\.0-beta_[a-f0-9]{7}' | sort -u
```

Both must report your commit's short SHA. On a deployed preview, the equivalent
check is to fetch the served wasm in the browser console and search it for the
version string — a 200 response only proves *something* is there.

---

## 6. Validate in the app

```bash
# Real KDF through the real SDK - the number the app actually experiences
cd sdk/packages/komodo_defi_harness
KDF_HARNESS=1 KDF_TEST_SEED='<throwaway seed>' \
  flutter test test/process/real_kdf_smoke_test.dart

# Suites
cd ../komodo_defi_sdk && flutter test
cd ../../.. && flutter test test_units/main.dart --dart-define=...   # the 4 GasFree defines
```

The process tier prints `PROCESS TIER (hd): ... activation_ms=... 
first_post_activation_balance_ms=...`. Compare against the numbers in
[`KDF_LATENCY_REPORT.md`](KDF_LATENCY_REPORT.md); the per-PR harness gate also
compares `first_post_activation_balance_ms` to `tool/bench_baseline.json` with a
30% regression threshold.

For KDF-in-isolation numbers (no Flutter, no Dart, no SDK), use
`tool/kdf_latency_probe.py` — see [`../tool/README.md`](../tool/README.md).

---

## Gotchas

Every one of these cost real time at least once.

| symptom | cause | fix |
|---|---|---|
| `flutter pub get --enforce-lockfile` fails in CI, every job red before doing any work | `pubspec.lock` generated on a different Flutter than CI pins | regenerate with the pinned version — `fvm flutter pub get`. See [`FLUTTER_VERSION.md`](FLUTTER_VERSION.md) |
| `macos/Podfile.lock` drops from ~61 pods to ~5 | a `pod install` ran before plugin symlinks resolved | `git checkout -- macos/Podfile.lock`. Never commit it — the macOS build then fails to link Firebase, secure storage, local_auth… |
| `macos/Runner.xcodeproj` churns on every build, plus a new `Runner.xcworkspace/xcshareddata/swiftpm/` | Flutter auto-adds SwiftPM integration | `flutter config --no-enable-swift-package-manager` (per machine), revert the files |
| `403 rate limit exceeded` fetching `GLEECBTC/coins` | a step runs `flutter test`/asset transformer without `GITHUB_API_PUBLIC_READONLY_TOKEN` | set it from `secrets.GITHUB_TOKEN`. **Presents as flake** — it passes until the runner's shared IP budget is spent |
| build refuses to start: "KDF worktree is dirty" | untracked or modified files in the KDF checkout | see the note in step 2 |
| downloaded artifact rejected | checksum in `build_config.json` does not match the published ZIP | re-derive from `manifest.json` (step 4) |
| a CI job shows "failure" but no step failed | it was **cancelled** by a newer push (concurrency) | check `.jobs[].conclusion == "cancelled"` before diagnosing |

## Rolling back

The SDK's artifact reference is the only pointer, so a rollback is a revert of
`build_config.json` (commit hash, branch, seven checksums) to the previous
values, then a rebuild so the transformer refetches. Nothing needs to be
unpublished — R2 publication is additive and prior commits stay served.
