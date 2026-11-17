#!/usr/bin/env bash
set -euo pipefail
cd ~/w200-build/librespot
grep -E '^name = "libmdns"' -A1 Cargo.lock
SRC=$(ls -d ~/.cargo/registry/src/*/libmdns-* | tail -1)
echo "src: $SRC"
grep -rn -E 'reuse_port|reuse_address|set_multicast|join_multicast|only_v6|IPV6|setsockopt|bind' "$SRC/src" | head -40
