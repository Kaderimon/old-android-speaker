#!/usr/bin/env bash
# shairport-sync + mbedtls 3: the Apple-Challenge response used mbedtls_rsa_pkcs1_encrypt, which in
# mbedtls 3 is always a PUBLIC-key encryption (the PRIVATE mode argument was removed), so iOS/macOS
# rejected the response and hung up. Use a raw PKCS#1 v1.5 private-key signature instead.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. ~/.cargo/env
S=~/w200-build/shairport/src/shairport-sync
python3 - "$S/common.c" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
old = '''    rc = mbedtls_rsa_pkcs1_encrypt(trsa, mbedtls_ctr_drbg_random, &ctr_drbg,
                                   inlen, input, outbuf);'''
new = '''    /* W200: mbedtls 3 dropped the PRIVATE mode flag - pkcs1_encrypt would use the public key.
       A PKCS#1 v1.5 signature with MD_NONE signs the raw challenge, which is what AirPlay needs. */
    rc = mbedtls_rsa_pkcs1_sign(trsa, mbedtls_ctr_drbg_random, &ctr_drbg, MBEDTLS_MD_NONE,
                                inlen, input, outbuf);'''
if 'W200: mbedtls 3 dropped' not in s:
    assert s.count(old) == 1, 'pkcs1_encrypt call not found'
    s = s.replace(old, new); open(p, 'w').write(s); print('rsa_apply patched')
else:
    print('rsa_apply already patched')
EOF
export PATH=~/w200-build/tools/bin:$PATH
cd "$S"
make -j"$(nproc)" >/tmp/shairport.log 2>&1 || { grep -E 'error' -B2 -A6 /tmp/shairport.log | head -60; exit 1; }
OUT=$W/out
zig objcopy --strip-all shairport-sync "$OUT/shairport-sync"
ls -l "$OUT/shairport-sync"
