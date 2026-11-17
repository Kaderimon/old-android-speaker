#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. ~/.cargo/env
OUT=$W/out
SRC=$W/helper
zig cc -target arm-linux-musleabihf -mcpu=$ZIG_CPU -static -Os -s -o "$OUT/daemonize" "$SRC/daemonize.c"
file "$OUT/daemonize"
