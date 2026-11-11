#!/bin/bash
set -euo pipefail
export CARGO_HOME=/build/cargo
export CARGO_TARGET_DIR=/build/target
export KDF_BUILD_TAG=f9632e0
export PATH=/build/protobuf/bin:/root/.cargo/bin:$PATH
cd /source
test "$(sha256sum Cargo.lock | cut -d ' ' -f 1)" = f160ec23242893eae6f65634eb10628b760fe1027ce11d801a253d9d6d1a428a
cargo +1.98.0 build --offline --locked --release --package mm2_bin_lib --lib \
  --target x86_64-unknown-linux-gnu --jobs 4
sha256sum Cargo.lock /build/target/x86_64-unknown-linux-gnu/release/libkdflib.so
