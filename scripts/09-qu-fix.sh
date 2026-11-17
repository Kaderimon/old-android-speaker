#!/usr/bin/env bash
# tinysvcmdns fixes so Apple devices can resolve the receiver:
#  - answer "QU" (unicast-response-requested) questions by multicast instead of ignoring them;
#    iOS/macOS set QU on SRV/TXT/A lookups, so the device was listed in the cache but never resolved
#  - mask the QU / cache-flush bit correctly (0x8000, not 0x80) when reading the record class
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. ~/.cargo/env
S=~/w200-build/shairport/src/shairport-sync
python3 - "$S/tinysvcmdns.c" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
skip = '''      // check if it's a unicast query - we ignore those
      if (qn->unicast_query) {
        DEBUG_PRINTF("skipping unicast query\\n");
        continue;
      }
'''
if 'W200: answer QU' not in s:
    assert s.count(skip) == 1, 'unicast-skip block not found'
    s = s.replace(skip, '      // W200: answer QU (unicast-response) questions too - by multicast, which RFC 6762 allows\n')
    n = s.count('rr->rr_class = mdns_read_u16(p) & ~0x80;')
    assert n == 2, f'class mask lines: {n}'
    s = s.replace('rr->rr_class = mdns_read_u16(p) & ~0x80;', 'rr->rr_class = mdns_read_u16(p) & ~0x8000;')
    open(p, 'w').write(s); print('tinysvcmdns patched (QU answered, class mask fixed)')
else:
    print('tinysvcmdns already patched')
EOF
export PATH=~/w200-build/tools/bin:$PATH
cd "$S"
make -j"$(nproc)" >/tmp/shairport.log 2>&1 || { grep -E 'error' -B2 -A6 /tmp/shairport.log | head -60; exit 1; }
OUT=$W/out
zig objcopy --strip-all shairport-sync "$OUT/shairport-sync"
ls -l "$OUT/shairport-sync"
