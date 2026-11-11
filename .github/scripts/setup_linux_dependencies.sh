#!/usr/bin/env bash
set -euo pipefail

# GitHub's image can route every Ubuntu suite through an unavailable Azure
# mirror. Use signed Canonical indexes, independently of cached mirror lists.
# The runner supplies this system file; local macOS lint cannot read it.
# shellcheck disable=SC1091
ubuntu_codename=$( . /etc/os-release; printf '%s' "$VERSION_CODENAME")
if [[ ! "$ubuntu_codename" =~ ^[a-z]+$ ]] || [[ ! -f /usr/share/keyrings/ubuntu-archive-keyring.gpg ]]; then
  echo "The Linux build requires an Ubuntu runner with its archive keyring."
  exit 1
fi
apt_sources=$(mktemp /tmp/gleec-ubuntu-sources.XXXXXX.list)
apt_lists=$(mktemp -d /tmp/gleec-ubuntu-lists.XXXXXX)
trap 'sudo rm -rf -- "$apt_lists"; rm -f -- "$apt_sources"' EXIT
chmod 644 "$apt_sources"
chmod 755 "$apt_lists"
keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg
for suite in "$ubuntu_codename" "$ubuntu_codename-updates"; do
  printf 'deb [signed-by=%s] https://archive.ubuntu.com/ubuntu %s main restricted universe multiverse\n' "$keyring" "$suite" >> "$apt_sources"
done
printf 'deb [signed-by=%s] https://security.ubuntu.com/ubuntu %s-security main restricted universe multiverse\n' "$keyring" "$ubuntu_codename" >> "$apt_sources"
apt_options=(
  -o "Dir::Etc::sourcelist=$apt_sources"
  -o 'Dir::Etc::sourceparts=-'
  -o "Dir::State::lists=$apt_lists"
  -o 'APT::Update::Error-Mode=any'
  -o 'Acquire::Retries=2'
  -o 'Acquire::http::Timeout=30'
  -o 'Acquire::https::Timeout=30'
)
sudo apt-get "${apt_options[@]}" update
sudo env DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" install -y \
  ninja-build libgtk-3-dev libblkid-dev liblzma-dev libsecret-1-dev \
  libjsoncpp-dev libsqlite3-dev libxdg-basedir-dev cmake pkg-config clang \
  binutils git xz-utils zip libglu1-mesa curl libstdc++-12-dev
