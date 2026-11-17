#!/usr/bin/env bash
# Rust + ARMv7 musl target, Zig (C cross-compiler), cargo-zigbuild
set -euo pipefail
cd ~
if [ ! -x ~/.cargo/bin/rustup ]; then
  curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal >/tmp/rustup.log 2>&1
fi
. ~/.cargo/env
rustup target add armv7-unknown-linux-musleabihf >>/tmp/rustup.log 2>&1
rustc --version
rustup target list --installed

ZIGV=0.14.1
mkdir -p ~/w200-build/tools && cd ~/w200-build/tools
if [ ! -x "zig-x86_64-linux-$ZIGV/zig" ]; then
  curl -sSfL -o zig.tar.xz "https://ziglang.org/download/$ZIGV/zig-x86_64-linux-$ZIGV.tar.xz"
  echo "zig tarball bytes: $(stat -c %s zig.tar.xz)"
  tar xf zig.tar.xz && rm zig.tar.xz
fi
ln -sf ~/w200-build/tools/zig-x86_64-linux-$ZIGV/zig ~/.cargo/bin/zig
echo "zig $(zig version)"

if ! command -v cargo-zigbuild >/dev/null; then
  cargo install --locked cargo-zigbuild >/tmp/zigbuild.log 2>&1 || { tail -20 /tmp/zigbuild.log; exit 1; }
fi
cargo-zigbuild --version
