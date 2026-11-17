#!/usr/bin/env bash
# Fetch librespot at the latest release tag and show its feature flags
set -euo pipefail
cd ~/w200-build
[ -d librespot/.git ] || git clone -q https://github.com/librespot-org/librespot.git
cd librespot
git fetch -q --tags
T=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
echo "latest tag: $T"
git -c advice.detachedHead=false checkout -q "$T"
echo "--- [features] ---"
sed -n '/^\[features\]/,/^\[[a-z]/p' Cargo.toml
echo "--- playback backends ---"
sed -n '/^\[features\]/,/^\[[a-z]/p' playback/Cargo.toml | head -40
