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
# Both endpoints serve Ubuntu-signed indexes. The second has independent DNS;
# registration: https://launchpad.net/ubuntu/+archivemirrors (Kernel.org).
apt_ready=false
for archive in https://archive.ubuntu.com/ubuntu https://mirrors.edge.kernel.org/ubuntu; do
  security=$archive
  if [[ "$archive" == https://archive.ubuntu.com/ubuntu ]]; then
    security=https://security.ubuntu.com/ubuntu
  fi
  : > "$apt_sources"
  for suite in "$ubuntu_codename" "$ubuntu_codename-updates"; do
    printf 'deb [signed-by=%s] %s %s main restricted universe multiverse\n' "$keyring" "$archive" "$suite" >> "$apt_sources"
  done
  printf 'deb [signed-by=%s] %s %s-security main restricted universe multiverse\n' "$keyring" "$security" "$ubuntu_codename" >> "$apt_sources"
  apt_options=(
    -o "Dir::Etc::sourcelist=$apt_sources"
    -o 'Dir::Etc::sourceparts=-'
    -o "Dir::State::lists=$apt_lists"
    -o 'APT::Update::Error-Mode=any'
    -o 'Acquire::Retries=2'
    -o 'Acquire::http::Timeout=30'
    -o 'Acquire::https::Timeout=30'
  )
  if sudo apt-get "${apt_options[@]}" update; then
    apt_ready=true
    break
  fi
  echo "Package indexes unavailable; trying the next Ubuntu-signed mirror."
  sudo rm -rf -- "$apt_lists"
  apt_lists=$(mktemp -d /tmp/gleec-ubuntu-lists.XXXXXX)
  chmod 755 "$apt_lists"
done
if [[ "$apt_ready" != true ]]; then
  echo "Complete, signed Ubuntu package indexes could not be obtained."
  exit 1
fi
packages=(
  ninja-build libgtk-3-dev libblkid-dev liblzma-dev libsecret-1-dev
  libjsoncpp-dev libsqlite3-dev libxdg-basedir-dev cmake pkg-config clang
  binutils git xz-utils zip libglu1-mesa curl libstdc++-12-dev
)
if (( $# > 0 )); then
  packages=("$@")
fi
sudo env DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" install -y -- "${packages[@]}"
