# Android rollback packaging check

This check binds reader-retention evidence to the actual normal and rollback
APKs. It checks every packaged application ABI, the native credential bridge,
the bundled KDF library, private-fixture/legacy-executable/temporary-diagnostic
exclusions, identical native bridge and KDF bytes across profiles, and the
same application ID, version code and signing certificate across the pair.
It never reads wallet data or signing credentials.

```sh
python3 -m unittest discover -s android/rollback_test -p 'test_*.py' -v
python3 android/rollback_test/verify_packaged_readers.py \
  --normal /path/to/normal.apk \
  --rollback /path/to/rollback.apk \
  --aapt /path/to/android-build-tools/aapt \
  --apksigner /path/to/android-build-tools/apksigner \
  --output /path/to/reader-proof.json
python3 tool/verify_wallet_artifacts.py /path/to/normal.apk /path/to/rollback.apk
```

The APKs must be signed, using the same disposable test certificate for emulator
acceptance or the same appropriate release identity for release verification.
Never substitute a personal or production signing key for a disposable test.

String/symbol retention is a packaging prerequisite; it does not prove that a
reader successfully decrypts a credential or authorizes a user. Complete the
normal → rollback → normal installation exercise on the **same app data**, with
existing generated/unprotected, device-protected and custom-password wallets.
Record cancellation, last-wallet selection, explicit sign-out, fresh sensitive
authorization and enrollment suppression. Do not dump private app state, reveal
recovery phrases, log passwords or use funded wallets.

The source manifest and explicit build defines establish the profile. The
binary marker scan does not infer optimized Boolean values from AOT code.
Exact immutable-identity, recovery-evidence and interrupted-operation assertions
remain covered by the separate cross-process service reader tests; the emulator
exercise proves actual Android package/Keystore access across the installs.

Include short HOME/return repetitions with the launcher confirmed. Android can
emit only `inactive` and `resumed` for this transition, without `hidden` or
`paused`. Immediate locking must still require authentication; normal mode
must retain the original monotonic deadline. Diagnostic builds used to identify
this sequence are separate evidence and must not replace the clean APK pair.
