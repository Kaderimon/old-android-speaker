#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. ~/.cargo/env
OUT=$W/out/soloist
zig cc -target arm-linux-gnueabihf.2.17 -mcpu=$ZIG_CPU -O2 -o "$OUT/netcheck" "$W/helper/netcheck.c"
file "$OUT/netcheck"
# which dealer/spclient hosts does Soloist talk to?
strings -n 8 ~/w200-build/soloist/x/soloist | grep -oE '[a-z0-9.-]*dealer[a-z0-9.-]*\.spotify\.com|apresolve\.spotify\.com|[a-z0-9-]*spclient[a-z0-9.-]*\.spotify\.com' | sort -u | head
