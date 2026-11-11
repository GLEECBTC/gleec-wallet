# Native engine artifact validation

These tools build and exercise the unmodified KDF source at
`f9632e0ec771668a6f21b37aede01a30110141cb`. They do not publish artifacts,
change SDK pins, or provide an executable fallback. The source archive is not
included and must not be published with the resulting binaries.

The completed `native-v1` release has sanitized records in
[`provenance/linux-f9632e0-native-v1.json`](provenance/linux-f9632e0-native-v1.json)
and [`provenance/macos-f9632e0-native-v1.json`](provenance/macos-f9632e0-native-v1.json).
They include verified public archive URLs, unchanged older archives, real native
lifecycle results and final application packaging evidence. Linux additionally
records real Secret Service persistence and fail-closed provider-loss checks.
Physical authentication and distribution signing are separate validations.

Inputs:

- Exact source archive SHA-256:
  `86c8d10d6d6c7644de6011c65f5362baabb5c441539db6fe713d7b45b448e0bf`.
- Unchanged `Cargo.lock` SHA-256:
  `f160ec23242893eae6f65634eb10628b760fe1027ce11d801a253d9d6d1a428a`.
- Linux amd64 build image:
  `sha256:12c3051c751b99c5c6cad08e1c4ab9298be213e1f9d58c6b8c18e21ef9d6a8e4`
  (`komodoofficial/ci-container`, Debian 11/glibc 2.31).
- Rust 1.98.0 and the source workflow's protoc 25.3, verified against its pinned
  checksum by `prepare_linux.sh`.
- A Cargo registry/git cache for the exact locked dependencies. Do not mount
  Cargo credential files, SSH keys, GitHub tokens or the Docker socket.

Verify every extracted source file against the archive before starting. Use a
fresh container with the source and dependency cache mounted read-only:

```sh
python3 tool/auth_native_artifacts/verify_source.py \
  "$KDF_ARTIFACT_SOURCE_ARCHIVE" "$KDF_ARTIFACT_SOURCE"
docker run -d --name "$KDF_ARTIFACT_CONTAINER" --platform linux/amd64 \
  --cpus 6 --memory 12g \
  --mount "type=bind,src=$KDF_ARTIFACT_SOURCE,dst=/source,readonly" \
  --mount "type=bind,src=$KDF_ARTIFACT_CACHE,dst=/cached-cargo,readonly" \
  --mount "type=bind,src=$KDF_ARTIFACT_TOOLS,dst=/validation,readonly" \
  --mount "type=bind,src=$KDF_ARTIFACT_OUTPUT,dst=/artifacts" \
  --entrypoint sleep \
  sha256:12c3051c751b99c5c6cad08e1c4ab9298be213e1f9d58c6b8c18e21ef9d6a8e4 \
  infinity
docker exec "$KDF_ARTIFACT_CONTAINER" bash /validation/prepare_linux.sh
docker network disconnect bridge "$KDF_ARTIFACT_CONTAINER"
docker exec "$KDF_ARTIFACT_CONTAINER" bash /validation/build_linux.sh
docker exec "$KDF_ARTIFACT_CONTAINER" python3 /validation/runtime_smoke.py \
  /build/target/x86_64-unknown-linux-gnu/release/libkdflib.so
```

Set the task-specific variables to absolute paths and a new container name.
`prepare_linux.sh` needs network access to official Rust, Debian and protobuf
distribution endpoints. Debian's archived Bullseye security repository retains
signature verification; only its expired freshness timestamp is ignored. The
actual Cargo build runs disconnected, with `--offline --locked`, four jobs and
no extra Cargo features. Source and lockfile remain read-only.

The runtime check creates a fresh, unfunded wallet in a temporary directory. It
uses native FFI and loopback RPC with no P2P or enabled coins. Generated passwords
and recovery material never become arguments, environment values or report
fields. The report contains completed phases and closed failure categories.
It exercises start/status/stop, creation, fresh password proof/rejection, cold
return, password rotation, identity preservation and deletion. Its canary scan
covers process arguments/environment on Linux and temporary wallet files.
Mutable FFI configuration buffers are cleared after startup returns; no claim is
made about erasing Python strings or KDF session memory.

Before publication, inspect the actual ELF exports, architecture and dynamic
dependencies and load the library in the supported application runtime. Package
only the matching `kdf` companion and shared library into a new immutable ZIP.
The executable is retained for the build transformer's artifact identity; the
Linux and macOS application bundles use only their shared libraries.

Use an explicit new artifact revision such as `native-v1`; preserve old release
archives. Publish hashes and sanitized provenance separately, without source
archives, local paths, credentials or temporary wallet data. Regenerate the
extraction marker using the actual new archive and runtime bytes, and validate
the full Flutter application with those exact bytes before updating release
pins. The upstream build script embeds its current build time, so these pinned
inputs are not a claim of bit-for-bit reproducible independent builds.
