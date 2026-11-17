#!/usr/bin/env bash
# Cross-compile shairport-sync (classic AirPlay 1 audio) as a static ARMv7 musl binary:
# built-in tinysvcmdns for discovery, mbedtls for crypto, stdout audio backend.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. ~/.cargo/env
B=~/w200-build/shairport
PREFIX=$B/sysroot
OUT=$W/out
mkdir -p "$B/src" "$PREFIX" ~/w200-build/tools/bin
cd ~/w200-build/tools/bin
# compiler wrappers so autotools sees a single-word CC
printf '#!/bin/sh\nexec zig cc -target arm-linux-musleabihf -mcpu=%s "$@"\n' "$ZIG_CPU" > arm-cc
printf '#!/bin/sh\nexec zig c++ -target arm-linux-musleabihf -mcpu=%s "$@"\n' "$ZIG_CPU" > arm-cxx
printf '#!/bin/sh\nexec zig ar "$@"\n' > arm-ar
printf '#!/bin/sh\nexec zig ranlib "$@"\n' > arm-ranlib
chmod +x arm-cc arm-cxx arm-ar arm-ranlib
export PATH=~/w200-build/tools/bin:$PATH
export CC=arm-cc CXX=arm-cxx AR=arm-ar RANLIB=arm-ranlib
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig
export CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib -static"
HOST=arm-linux-musleabihf
J=$(nproc)
cd "$B/src"

fetch() { [ -f "$2" ] || { curl -sSfL -o "$2" "$1"; echo "downloaded $2 ($(stat -c %s "$2") bytes)"; }; }

# --- popt ---
if [ ! -f "$PREFIX/lib/libpopt.a" ]; then
  fetch https://ftp.osuosl.org/pub/rpm/popt/releases/popt-1.x/popt-1.19.tar.gz popt-1.19.tar.gz
  rm -rf popt-1.19 && tar xf popt-1.19.tar.gz && cd popt-1.19
  ./configure --host=$HOST --prefix="$PREFIX" --disable-shared --enable-static --disable-nls >/tmp/popt.log 2>&1
  make -j$J >>/tmp/popt.log 2>&1 && make install >>/tmp/popt.log 2>&1 || { tail -30 /tmp/popt.log; exit 1; }
  cd ..; echo "popt ok"
fi

# --- libconfig ---
if [ ! -f "$PREFIX/lib/libconfig.a" ]; then
  fetch https://github.com/hyperrealm/libconfig/releases/download/v1.7.3/libconfig-1.7.3.tar.gz libconfig-1.7.3.tar.gz
  rm -rf libconfig-1.7.3 && tar xf libconfig-1.7.3.tar.gz && cd libconfig-1.7.3
  ./configure --host=$HOST --prefix="$PREFIX" --disable-shared --enable-static --disable-cxx --disable-examples --disable-tests >/tmp/libconfig.log 2>&1
  make -j$J >>/tmp/libconfig.log 2>&1 && make install >>/tmp/libconfig.log 2>&1 || { tail -30 /tmp/libconfig.log; exit 1; }
  cd ..; echo "libconfig ok"
fi

# --- mbedtls (3.6 LTS) ---
if [ ! -f "$PREFIX/lib/libmbedcrypto.a" ]; then
  MV=$(git ls-remote --tags https://github.com/Mbed-TLS/mbedtls.git 'refs/tags/mbedtls-3.6.*' | sed 's#.*refs/tags/##; s#\^{}##' | grep -E '^mbedtls-3\.6\.[0-9]+$' | sort -V | tail -1)
  fetch "https://github.com/Mbed-TLS/mbedtls/releases/download/$MV/$MV.tar.bz2" "$MV.tar.bz2"
  rm -rf "$MV" && tar xf "$MV.tar.bz2" && cd "$MV"
  # kernel 3.4 has no getrandom(); mbedtls would then fall back to /dev/random, which blocks
  # for minutes on this phone - use /dev/urandom instead
  make -j$J lib CC=arm-cc AR=arm-ar CFLAGS='-O2 -DMBEDTLS_PLATFORM_DEV_RANDOM=\"/dev/urandom\"' >/tmp/mbedtls.log 2>&1 || { tail -30 /tmp/mbedtls.log; exit 1; }
  make install DESTDIR="$PREFIX" >>/tmp/mbedtls.log 2>&1 || { tail -30 /tmp/mbedtls.log; exit 1; }
  cd ..; echo "$MV ok"
fi

# --- shairport-sync (latest 4.x release) ---
[ -d shairport-sync/.git ] || git clone -q https://github.com/mikebrady/shairport-sync.git
cd shairport-sync
git fetch -q --tags
ST=$(git tag --sort=-v:refname | grep -E '^4\.[0-9]+(\.[0-9]+)?$' | head -1)
echo "shairport-sync tag: $ST"
git -c advice.detachedHead=false checkout -q "$ST"
git clean -qfdx
autoreconf -fi >/tmp/shairport.log 2>&1
./configure --host=$HOST --with-os=linux --with-stdout --with-pipe --with-tinysvcmdns \
  --with-ssl=mbedtls --without-avahi --without-alsa --without-soxr \
  LIBS="-lmbedtls -lmbedx509 -lmbedcrypto" >>/tmp/shairport.log 2>&1 || { tail -40 /tmp/shairport.log; exit 1; }
make -j$J >>/tmp/shairport.log 2>&1 || { grep -E 'error|Error' -B2 -A6 /tmp/shairport.log | head -80; exit 1; }
cp shairport-sync "$OUT/shairport-sync"
zig objcopy --strip-all "$OUT/shairport-sync" "$OUT/shairport-sync.s" && mv "$OUT/shairport-sync.s" "$OUT/shairport-sync"
file "$OUT/shairport-sync"; ls -l "$OUT/shairport-sync"
