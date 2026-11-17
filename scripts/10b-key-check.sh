#!/usr/bin/env bash
set -euo pipefail
S=~/w200-build/shairport/src/shairport-sync
grep -n 'BEGIN RSA PRIVATE KEY' "$S"/*.c | head
T=$(mktemp -d)
python3 - "$S" "$T/key.pem" <<'EOF'
import re, sys, glob
src = ''.join(open(f, errors='ignore').read() for f in glob.glob(sys.argv[1] + '/*.c'))
m = re.search(r'-----BEGIN RSA PRIVATE KEY-----(.*?)-----END RSA PRIVATE KEY-----', src, re.S)
body = re.sub(r'\\n|"|\s', '', m.group(1))
pem = '-----BEGIN RSA PRIVATE KEY-----\n' + '\n'.join(body[i:i+64] for i in range(0, len(body), 64)) + '\n-----END RSA PRIVATE KEY-----\n'
open(sys.argv[2], 'w').write(pem)
EOF
openssl rsa -in "$T/key.pem" -check -noout && openssl rsa -in "$T/key.pem" -noout -text | grep -E 'Private-Key|publicExponent'
grep -n -A30 'rsa_apply' "$S/common.c" | grep -n -i -E 'mbedtls_(pk|rsa)_|MODE|padding|sign|private|RSA_SIGN|rsa_apply' | head -30
rm -rf "$T"
