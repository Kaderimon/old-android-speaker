#!/usr/bin/env bash
# Android 4.2 compatibility fixes:
#  1. mDNS hostname: the kernel hostname is "localhost", so receivers advertised "localhost.local"
#     and clients connected to themselves. Both mDNS stacks now honour $MDNS_HOSTNAME.
#  2. DNS: Android has no /etc/resolv.conf, so musl's resolver had no nameserver. The librespot
#     binary is pointed at /sdcard/w200.dns instead (same length string), written by run-spotify.sh.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. ~/.cargo/env
OUT=$W/out

# --- 1a. libmdns: MDNS_HOSTNAME override ---
python3 - <<'EOF'
import os, re
p = os.path.expanduser('~/w200-build/patches/libmdns/src/lib.rs')
s = open(p).read()
old = '''        let hostname = hostname::get()?.into_string().map_err(|_| {
            io::Error::new(io::ErrorKind::InvalidData, "Hostname not valid unicode")
        })?;
        Self::default_handle(allowed_ips, hostname)'''
new = '''        // W200: Android's kernel hostname is "localhost"; allow an override
        let hostname = match std::env::var("MDNS_HOSTNAME") {
            Ok(h) if !h.is_empty() => h,
            _ => hostname::get()?.into_string().map_err(|_| {
                io::Error::new(io::ErrorKind::InvalidData, "Hostname not valid unicode")
            })?,
        };
        Self::default_handle(allowed_ips, hostname)'''
if 'MDNS_HOSTNAME' not in s:
    assert s.count(old) == 1, 'libmdns hostname block not found'
    s = s.replace(old, new); open(p, 'w').write(s); print('libmdns patched')
else:
    print('libmdns already patched')
EOF

# --- 1b. shairport-sync tinysvcmdns: MDNS_HOSTNAME override ---
python3 - <<'EOF'
import os
p = os.path.expanduser('~/w200-build/shairport/src/shairport-sync/mdns_tinysvcmdns.c')
s = open(p).read()
old = '  gethostname(hostname, 99);'
new = ('  { /* W200: Android kernel hostname is "localhost"; allow an override */\n'
       '    const char *w200_h = getenv("MDNS_HOSTNAME");\n'
       '    if (w200_h && *w200_h) { strncpy(hostname, w200_h, 99); } else gethostname(hostname, 99); }')
if 'MDNS_HOSTNAME' not in s:
    assert s.count(old) == 1, 'gethostname call not found'
    s = s.replace(old, new)
    if '#include <stdlib.h>' not in s: s = '#include <stdlib.h>\n' + s
    open(p, 'w').write(s); print('shairport-sync patched')
else:
    print('shairport-sync already patched')
EOF

# --- rebuild librespot ---
cd ~/w200-build/librespot
export RUSTFLAGS="-C target-cpu=$RUST_CPU"
cargo zigbuild --release --target armv7-unknown-linux-musleabihf \
  --no-default-features --features "rustls-tls-webpki-roots,with-libmdns" \
  >/tmp/librespot-build.log 2>&1 || { grep -E '^error' -A12 /tmp/librespot-build.log | head -60; exit 1; }
zig objcopy --strip-all target/armv7-unknown-linux-musleabihf/release/librespot "$OUT/librespot"

# --- 2. DNS path swap in librespot (both strings are 16 bytes) ---
python3 - "$OUT/librespot" <<'EOF'
import sys
p = sys.argv[1]; b = open(p, 'rb').read()
old, new = b'/etc/resolv.conf\0', b'/sdcard/w200.dns\0'
assert len(old) == len(new)
n = b.count(old); assert n == 1, f'expected 1 occurrence, found {n}'
open(p, 'wb').write(b.replace(old, new)); print('librespot DNS path -> /sdcard/w200.dns')
EOF

# --- rebuild shairport-sync ---
export PATH=~/w200-build/tools/bin:$PATH
cd ~/w200-build/shairport/src/shairport-sync
make -j"$(nproc)" >/tmp/shairport.log 2>&1 || { grep -E 'error' -B2 -A6 /tmp/shairport.log | head -60; exit 1; }
zig objcopy --strip-all shairport-sync "$OUT/shairport-sync"
ls -l "$OUT/librespot" "$OUT/shairport-sync"
