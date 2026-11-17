#!/usr/bin/env bash
# Stage Soloist + the minimal glibc runtime into out/soloist (for adb push)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
B=~/w200-build/soloist
OUT=$W/out/soloist
rm -rf "$OUT" && mkdir -p "$OUT/lib"
L=$B/rootfs/usr/lib/arm-linux-gnueabihf
for f in ld-linux-armhf.so.3 libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1 libatomic.so.1 libgcc_s.so.1 libstdc++.so.6 libresolv.so.2 libnss_dns.so.2 libnss_files.so.2; do
  [ -e "$L/$f" ] && cp -L "$L/$f" "$OUT/lib/$f"
done
cp "$B/x/soloist" "$OUT/soloist"
# Android 4.2 has no /etc/ssl: ship the current Mozilla CA bundle (used via SSL_CERT_FILE)
cp -L /etc/ssl/certs/ca-certificates.crt "$OUT/ca-certificates.crt"
echo "CA bundle: $(grep -c 'BEGIN CERTIFICATE' "$OUT/ca-certificates.crt") certificates"
# Android has no /etc/resolv.conf: point glibc's resolver at /sdcard/w200.dns (same length)
python3 - "$OUT/lib/libc.so.6" <<'EOF'
import sys
p = sys.argv[1]; b = open(p, 'rb').read()
old, new = b'/etc/resolv.conf\0', b'/sdcard/w200.dns\0'
n = b.count(old); assert n >= 1, 'resolv.conf path not found in libc'
open(p, 'wb').write(b.replace(old, new)); print(f'libc: {n} resolv.conf path(s) -> /sdcard/w200.dns')
EOF
du -sh "$OUT"; ls "$OUT/lib"
