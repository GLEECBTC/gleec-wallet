#!/usr/bin/env bash
# Builds the security-key bridge's libfido2 work against a scripted
# libfido2.so.1 (fake_fido2.cc) and runs its checks. Needs the libfido2-dev
# headers and GLib; the real library is never loaded and no key is touched.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cxx=${CXX:-c++}
flags=(-std=c++14 -Wall -Werror -O1 -g -pthread)
read -ra fido <<< "$(pkg-config --cflags libfido2)"
read -ra glib <<< "$(pkg-config --cflags --libs glib-2.0)"

"$cxx" "${flags[@]}" "${fido[@]}" -fPIC -shared \
  -Wl,-soname,libfido2.so.1 -o "$work/libfido2.so.1" "$here/fake_fido2.cc"
"$cxx" "${flags[@]}" "${fido[@]}" \
  "-DGLEEC_SECURITY_KEY_PATH_PREFIX=\"$work/hidraw\"" \
  -o "$work/security_key_jobs_test" \
  "$here/security_key_jobs_test.cc" "$here/../security_key_channel_jobs.cc" \
  "${glib[@]}" -ldl
LD_LIBRARY_PATH="$work" "$work/security_key_jobs_test"
