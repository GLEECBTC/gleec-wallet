# Gleec Wallet 0.10.0 production build

This is for the release owner who builds, signs and publishes 0.10.0 on a
private machine. No workflow in this repository signs or publishes: CI builds
unsigned validation artifacts, and its signing steps only run in the upstream
KomodoPlatform repository. Every value below was checked against this release's
tree on 4 November 2026; LI.FI profile instructions were updated on 6 November
for the owner-requested carry of wallet #3585 and the production-only follow-up.

## Order

Follow the checklist's
[promotion order](RELEASE_0.10.0_CHECKLIST.md#freeze-boundary-and-promotion-order):

1. Merge SDK #416 (`release-0.9.0` → `main`) with a merge commit and record
   the SDK `main` SHA.
2. Squash an app dev PR that pins `sdk` to that SHA, carry it into
   `release-0.10.0` with a merge commit, and prove the runtime still matches
   the frozen candidate.
3. Merge app #3575 (`release-0.10.0` → `main`) with a merge commit.
4. Tag `komodo_defi_sdk-v0.9.0` and the approved package tags on the SDK
   `main` SHA. Then run the
   [GitHub release preflight](BUILD_RELEASE.md#github-release-preflight) on the
   app `main` commit; it fails until that tag exists.
5. Build, sign and verify from the app `main` commit as below, then publish.

## Inputs

- **Source:**

  ```bash
  git clone https://github.com/GLEECBTC/gleec-wallet.git && cd gleec-wallet
  git checkout <app main commit>
  git submodule update --init --recursive
  test "$(git -C sdk rev-parse HEAD)" = "$(git rev-parse HEAD:sdk)"
  ```

- **Toolchain:** Flutter **3.41.4** (Dart 3.11.1).
  `flutter pub get --enforce-lockfile` must leave `pubspec.lock` unchanged;
  newer Flutter releases rewrite it. Windows needs Visual Studio 2022, because
  the VS 2026 toolchain breaks the build. Android uses JDK 21. Linux needs the
  packages listed in `.github/actions/releases/setup-linux/action.yml`.
- **GitHub token:** `export GITHUB_API_PUBLIC_READONLY_TOKEN=<any GitHub token>`.
  Without it, the SDK build transformer uses the unauthenticated GitHub API,
  which allows 60 requests an hour. The transformer downloads KDF `a51d69a`
  from `https://devbuilds.gleec.com`, falling back to `https://nebula.decker.im`,
  and rejects any archive whose SHA-256 differs from `build_config.json`. It
  downloads coins `cc8249e8` from GitHub. Both mirrors served all seven
  archives on 4 November.
- **Firebase:** apply the production Firebase configuration patch described in
  [FIREBASE_SETUP.md](FIREBASE_SETUP.md). The committed placeholder files turn
  Analytics off without any warning.

## Defines

Pass these to every build (bash or zsh):

```bash
DEFINES=(
  --dart-define-from-file=docs/LIFI_PRODUCTION_BUILD_DEFINES.json
  --dart-define=TRON_GASLESS_ENABLED=true
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
  --dart-define=COMMIT_HASH="$(git rev-parse HEAD | cut -c1-7)"
  --dart-define=BUILD_DATE="$(date -u '+%Y-%m-%dT%H:%MZ')"
  --dart-define=FEEDBACK_API_KEY="$FEEDBACK_API_KEY"
  --dart-define=FEEDBACK_PRODUCTION_URL="$FEEDBACK_PRODUCTION_URL"
  --dart-define=TRELLO_BOARD_ID="$TRELLO_BOARD_ID"
  --dart-define=TRELLO_LIST_ID="$TRELLO_LIST_ID"
  --dart-define=TRELLO_API_KEY="$TRELLO_API_KEY"
  --dart-define=TRELLO_TOKEN="$TRELLO_TOKEN"
  --dart-define=MATOMO_URL="$MATOMO_URL"
  --dart-define=MATOMO_SITE_ID="$MATOMO_SITE_ID"
)
```

- Production is the compiled default, including builds without defines. The
  public profile pins all five LI.FI values: `gleec-dex-production`, proxy
  `https://quicknode.gleec.com/lifi`, integrator enabled, 178 and 22 bps. Use
  the same profile in both passes. The shared CI action selects it through
  `LIFI_BUILD_ENVIRONMENT: production`; do not add conflicting LI.FI defines
  or another define file to that action's `BUILD_COMMAND`.
- Every GitHub preview, manual workflow, native release and Docker build uses
  production. Staging is unavailable while KDP is configured for the production
  integration; old staging requests are rejected before Flutter starts. See
  [LI.FI build configuration](LIFI_PRODUCTION_SETUP.md).
- The four `TRON_GASLESS_*` values equal the compiled defaults; passing them
  pins the release configuration, as CI does.
- `COMMIT_HASH` and `BUILD_DATE` appear in Settings and in feedback metadata.
  Without them both read "unknown".
- The secrets come from their owner; never commit or log them.
  **`FEEDBACK_API_KEY` is required:** without it the geo-policy lookup fails
  and no coin activates. The other secrets enable in-app feedback and Matomo
  analytics.
- Leave these unset: `GEO_BLOCK` (unset means on; `disabled` is only for UI
  tests), `BYPASS_LEGAL_DOCUMENT_GATE` (it must stay false in production),
  `ANALYTICS_DISABLED` and `CI`.

## Build

Every target needs two passes. The first downloads the KDF and coin assets and
is expected to fail; the second registers them. CI repeats the first pass up to
three times until these exist under `sdk/packages/komodo_defi_framework/`:
`assets/config/coins.json`, `assets/config/coins_config.json` and
`assets/coin_icons/png/kmd.png`. It then deletes everything in `build/` except
`build/native_assets`.

```bash
flutter pub get --enforce-lockfile
flutter build <target> --no-pub --release <flags> "${DEFINES[@]}" || true  # first pass
find build -mindepth 1 -maxdepth 1 ! -name native_assets -exec rm -rf {} +
flutter build <target> --no-pub --release <flags> "${DEFINES[@]}"
```

| Platform | `<target> <flags>` | Output |
| --- | --- | --- |
| Web | `web` | `build/web` |
| macOS | `macos --flavor production` | `build/macos/Build/Products/Release-production/Gleec DEX.app` |
| Windows | `windows` | `build/windows/x64/runner/Release` |
| Linux | `linux` | `build/linux/x64/release/bundle` |
| Android | `appbundle --build-number <N>` | `build/app/outputs/bundle/release/app-release.aab` |
| iOS | `ipa --build-number <N>` | `build/ios/ipa` |

- CI also runs `pod install` in `macos/` or `ios/` before Apple builds, and
  `flutter build apk --config-only` before Android builds.
- **Web:** testers used the RC preview, built with
  `flutter build web --no-pub --release` (dart2js, CanvasKit from Google's
  CDN). This RC wasn't tested with the `--csp --no-web-resources-cdn` or
  `--wasm` variants in [BUILD_RELEASE.md](BUILD_RELEASE.md). If you use one,
  recheck the app before deploying.

## Sign and package

Follow [SIGN_RELEASE.md](SIGN_RELEASE.md) and the 0.9.7-1 process. For 0.10.0:

- **macOS:** the `production` flavor selects Developer ID signing, its
  provisioning profile and the hardened runtime. Notarize as in
  [contrib/README.md](../contrib/README.md). The KDF helper is signed before
  Embed Pods; never use `codesign --deep`.
- **Android:** `android/app/build.gradle` signs release builds with the debug
  key, so sign the bundle with the Play upload key before uploading.
  `0.10.0+0` alone gives versionCode 1, because Flutter raises a build number
  below 1 to 1; 0.9.7-1's `0.9.7+0` gave the same. `<N>` must be higher than
  the current Play versionCode of `com.gleec.gleecdex`.
- **iOS:** CI builds unsigned (`--no-codesign`); sign with the distribution
  identity. Any re-upload of 0.10.0 needs a higher `--build-number`.
- **Desktop archives:** name them like 0.9.7-1's:
  `gleecdex_macos_0.10.0.dmg`, `gleec_wallet_windows_0.10.0.zip` and
  `gleec_wallet_linux_0.10.0.tar.gz`. Publish a detached `.asc` for each and a
  signed `SHA256SUMS.asc`.

## Verify every output

1. **Integrator:** on each unpacked output (unzip AAB, APK and IPA packages
   first), `grep -r -a -o -h 'gleec-dex-[a-z]*' <output> | sort -u` must print
   only `gleec-dex-production`, including RC previews. Staging is not a supported
   build profile. Earlier preview records remain evidence for their stated
   revisions.
2. **GasFree (web):**
   `grep -a -o -h 'gleec-gasfree-build-policy-v1:[a-z=;]*' build/web/main.dart.js | sort -u`
   must print `gleec-gasfree-build-policy-v1:send=enabled;receive=enabled`. The
   marker is only compiled into web builds. The GasFree base URL is present
   whether or not GasFree is on, so finding it proves nothing.
3. **Bundled inputs:** these files must match the RC record byte for byte. Web
   serves them at these paths under `build/web`. Native apps bundle the first
   four under `flutter_assets/packages/komodo_defi_framework/`. Save the list as
   `rc-0.10.0.sha256` and run `shasum -a 256 -c rc-0.10.0.sha256` in
   `build/web`:

   ```text
   7f648ffa210d9aeb0f7d1ab3e9454bf090f0c155383f4241c64b5ea228b712e5  assets/packages/komodo_defi_framework/app_build/build_config.json
   70f9191b8152c49b61cf2f5f45008fdd4e996ff10ee2c82bce73e9c6bb1d4976  assets/packages/komodo_defi_framework/assets/config/coins_config.json
   652be7d79b27d53fa4f6096217358c94213fd71af7bcc20a6c934b7171026d47  assets/packages/komodo_defi_framework/assets/config/coins.json
   9f8a0ebdfdea513844a72b1bcae01948cdf8f231ba0bd4e505b6d18d2e15f354  assets/packages/komodo_defi_framework/assets/config/seed_nodes.json
   f5fe0b1a44d35cc28ee3ee29b55a162a6fbb65ae4f2eaa1e4afe53e5ba636851  kdf/kdf/bin/kdflib.d.ts
   cbeda42d407d11d59730f4b5ec85bd18e2a6c2eb2e2fc7e65c0381788de91776  kdf/kdf/bin/kdflib.js
   6ea6bbaa7ba699935182b3096d984a6f7f733e93c5cf07315c7f15dd9a818be6  kdf/kdf/bin/package.json
   b21c15e4c0af09ea3ba14bf2c388f98bb5772595dcd8245df992354ccefdec05  kdf/kdf/bin/kdflib_bg.wasm.d.ts
   bd1472d656c119fdbe76333c56098c0295d913e5c532ef583efda1a59db41a5a  kdf/kdf/bin/snippets/libp2p-wasm-ext-7e5f5edb880ee0f5/src/websockets.js
   e8bccdb5f7ea2a2affcc10bfff045989d40490101a0575290a30d53009902f0a  kdf/kdf/bin/snippets/hw_common-c933ea30ea0fef0d/inline1.js
   fcaa05077e433b5cfb174377954dfe44cd466be81336b965c8e885395ca9f90e  kdf/kdf/bin/snippets/hw_common-c933ea30ea0fef0d/inline0.js
   e0bb201521f4b8f1376499755278783ad46f4cc7a86bc803fef2dc5b6d264ba9  kdf/kdf/bin/snippets/web3-3a881fca17d19cd8/inline0.js
   3224d8c5652a4ee1624bd44b9be940d06a168d23666e39243b814ada5fe34570  kdf/kdf/bin/kdflib_bg.wasm
   ```

4. **App:** Settings shows 0.10.0 and the commit, a fresh install asks for the
   legal consents, and coins activate.
5. **Web deploy:** run
   `firebase deploy --only hosting:web --project gleec-wallet-official`. Always
   pass `--project`, because the default is the preview project. Then run
   `tool/verify_web_deploy.sh https://dex.gleec.com` and recheck the served
   files against the list above.

For every final output, retain and verify the profile, dependency and artifact
records using `tool/lifi_build_provenance.py` as described in
[LI.FI artifact verification](LIFI_PRODUCTION_SETUP.md#artifact-records). Record
bytes after signing and packaging; later modifications require new trusted build
evidence. These records supplement the detached signatures above.

## Before and after publishing

- **Before:**
  - `https://privacy.gleec.com/tos_lifi_gleec_wallet.md` must serve Ilya's
    approved LI.FI text. On 4 November it was still the placeholder, with its
    marker removed for RC testing, so the app accepts it like final terms. The
    owner expects the final text to be live by publication.
  - The production KDP `/lifi` route must hold the production LI.FI key.
  - Install fresh and upgrade from 0.9.7-1 on every platform you publish.
- **After:**
  - Update `https://defistats.gleec.com/api/v3/dex_version`. The in-app update
    check reads it, and it still reports 0.9.7-1.
  - Retire the manual `rc-0-10-0-legal-testing` preview channel.

## Known limits shipping in 0.10.0

These are the owner's dispositions of 4 November; the
[checklist](RELEASE_0.10.0_CHECKLIST.md) has the details.

- Native Trezor restart and device-lock behaviour, also listed in the
  changelog's known limits.
- The optional X06/X07 liquidity and stalled DOC/MARTY testnet cases, the open
  KDF review points and three unattributed upstream KDF test failures.
- SDK #432 remains deferred. On 6 November the owner brought wallet #3585
  into this RC. The subsequent 6 November decision uses production everywhere
  and removes staging from GitHub previews. SDK #432 is not required for the wallet-side checks.
