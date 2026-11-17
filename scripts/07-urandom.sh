#!/usr/bin/env bash
# Rebuild mbedtls with /dev/urandom fallback, then relink shairport-sync (keeps the hostname patch).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. ~/.cargo/env
P=~/w200-build/shairport/sysroot
rm -f "$P"/lib/libmbed*.a
rm -rf "$P"/include/mbedtls "$P"/include/psa "$P"/include/everest
bash "$W/scripts/05-shairport.sh" 2>&1 | grep -E 'mbedtls|error' || true
# 05-shairport.sh does a clean checkout of shairport-sync, which drops the hostname patch:
# re-apply it via 06-fixes.sh's patch step and relink.
python3 - <<'EOF'
import os
p = os.path.expanduser('~/w200-build/shairport/src/shairport-sync/mdns_tinysvcmdns.c')
s = open(p).read()
old = '  gethostname(hostname, 99);'
new = ('  { /* W200: Android kernel hostname is "localhost"; allow an override */\n'
       '    const char *w200_h = getenv("MDNS_HOSTNAME");\n'
       '    if (w200_h && *w200_h) { strncpy(hostname, w200_h, 99); } else gethostname(hostname, 99); }')
if 'MDNS_HOSTNAME' not in s:
    assert s.count(old) == 1
    s = s.replace(old, new)
    if '#include <stdlib.h>' not in s: s = '#include <stdlib.h>\n' + s
    open(p, 'w').write(s); print('shairport-sync hostname patch re-applied')
EOF
export PATH=~/w200-build/tools/bin:$PATH
cd ~/w200-build/shairport/src/shairport-sync
rm -f shairport-sync
make -j"$(nproc)" >/tmp/shairport.log 2>&1 || { grep -E 'error' -B2 -A6 /tmp/shairport.log | head -60; exit 1; }
OUT=$W/out
zig objcopy --strip-all shairport-sync "$OUT/shairport-sync"
echo "urandom refs in binary: $(grep -c -a -o /dev/urandom "$OUT/shairport-sync")  /dev/random-only refs: $(grep -a -o '/dev/random[^_]' "$OUT/shairport-sync" | wc -l)"
grep -c MDNS_HOSTNAME -a "$OUT/shairport-sync"
ls -l "$OUT/shairport-sync"
