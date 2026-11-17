#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. ~/.cargo/env
OUT=$W/out
zig cc -target arm-linux-musleabihf -mcpu=$ZIG_CPU -static -Os -s -o "$OUT/asshell" "$W/helper/asshell.c"
file "$OUT/asshell"
