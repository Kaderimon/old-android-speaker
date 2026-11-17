#!/usr/bin/env bash
# Kernel 3.4 has no SO_REUSEPORT (added in 3.9): make libmdns ignore that failure.
set -euo pipefail
SRC=$(ls -d ~/.cargo/registry/src/*/libmdns-0.10.1)
P=~/w200-build/patches/libmdns
rm -rf "$P" && mkdir -p ~/w200-build/patches && cp -r "$SRC" "$P"
sed -n '24,40p' "$P/src/address_family.rs"
sed -i 's/^\(\s*\)socket\.set_reuse_port(true)?;/\1let _ = socket.set_reuse_port(true); \/\/ W200: kernel 3.4 lacks SO_REUSEPORT/' "$P/src/address_family.rs"
echo "--- patched ---"
grep -n 'set_reuse_port' "$P/src/address_family.rs"

cd ~/w200-build/librespot
if ! grep -q 'W200 patch' Cargo.toml; then
  printf '\n# W200 patch: old-kernel friendly libmdns\n[patch.crates-io]\nlibmdns = { path = "%s" }\n' "$P" >> Cargo.toml
fi
tail -4 Cargo.toml
