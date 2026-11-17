#!/usr/bin/env bash
# Cross-compile librespot as a static ARMv7 (Cortex-A7) musl binary for the W200
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. ~/.cargo/env
OUT=$W/out
TARGET=armv7-unknown-linux-musleabihf
cd ~/w200-build/librespot
export RUSTFLAGS="-C target-cpu=$RUST_CPU"
cargo zigbuild --release --target "$TARGET" \
  --no-default-features --features "rustls-tls-webpki-roots,with-libmdns" \
  >/tmp/librespot-build.log 2>&1 || { grep -E '^(error|warning: build failed)' -A12 /tmp/librespot-build.log | head -80; exit 1; }
BIN=target/$TARGET/release/librespot
mkdir -p "$OUT"
cp "$BIN" "$OUT/librespot"
llvm-strip "$OUT/librespot" 2>/dev/null || zig objcopy --strip-all "$OUT/librespot" "$OUT/librespot.s" && mv "$OUT/librespot.s" "$OUT/librespot" || true
file "$OUT/librespot"
ls -l "$OUT/librespot"
