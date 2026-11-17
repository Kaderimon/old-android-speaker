#!/usr/bin/env bash
# Rebuild shairport-sync (keeping the W200 patches in the tree) with metadata support,
# so the launcher can show title/artist/album/cover and the sender's device name.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. ~/.cargo/env
export PATH=~/w200-build/tools/bin:$PATH
PREFIX=~/w200-build/shairport/sysroot
export CC=arm-cc CXX=arm-cxx AR=arm-ar RANLIB=arm-ranlib
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig
export CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib -static"
S=~/w200-build/shairport/src/shairport-sync
cd "$S"
echo "patches present: $(grep -c 'W200' tinysvcmdns.c common.c mdns_tinysvcmdns.c | tr '\n' ' ')"
./configure --host=arm-linux-musleabihf --with-os=linux --with-stdout --with-pipe --with-tinysvcmdns \
  --with-ssl=mbedtls --with-metadata --without-avahi --without-alsa --without-soxr \
  LIBS="-lmbedtls -lmbedx509 -lmbedcrypto" >/tmp/shairport.log 2>&1 || { tail -30 /tmp/shairport.log; exit 1; }
make clean >/dev/null 2>&1 || true
make -j"$(nproc)" >>/tmp/shairport.log 2>&1 || { grep -E 'error' -B2 -A6 /tmp/shairport.log | head -60; exit 1; }
OUT=$W/out
zig objcopy --strip-all shairport-sync "$OUT/shairport-sync"
grep -q 'CONFIG_METADATA 1' config.h && echo "metadata: enabled"
ls -l "$OUT/shairport-sync"
