#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# Bullseye security packages moved to Debian's signed, frozen archive after LTS.
# Disable freshness only for that archived source; signature checking stays on.
sed -i 's|deb http://deb.debian.org/debian-security |deb [check-valid-until=no] https://archive.debian.org/debian-security |' /etc/apt/sources.list
apt-get update
apt-get install -y --no-install-recommends pkg-config libudev-dev libusb-1.0-0-dev libssl-dev unzip
rustup toolchain install 1.98.0 --profile minimal --no-self-update
mkdir -p /build/cargo /build/protobuf
# Copy only dependency stores. Never import host Cargo credentials or config.
for dependency_store in registry git; do
  test -d "/cached-cargo/$dependency_store"
  cp -a "/cached-cargo/$dependency_store" /build/cargo/
done
curl --fail --location --retry 3 --output /build/protoc-25.3-linux-x86_64.zip \
  https://github.com/protocolbuffers/protobuf/releases/download/v25.3/protoc-25.3-linux-x86_64.zip
printf '%s  %s\n' f853e691868d0557425ea290bf7ba6384eef2fa9b04c323afab49a770ba9da80 /build/protoc-25.3-linux-x86_64.zip | sha256sum --check
unzip -qo /build/protoc-25.3-linux-x86_64.zip -d /build/protobuf
rustc +1.98.0 -vV
cargo +1.98.0 -V
/build/protobuf/bin/protoc --version
sha256sum /source/Cargo.lock
dpkg-query -W libc6 clang-16 pkg-config libudev-dev libusb-1.0-0-dev libssl-dev
