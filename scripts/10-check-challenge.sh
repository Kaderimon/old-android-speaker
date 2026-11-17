#!/usr/bin/env bash
# Decode an AirPlay Apple-Response with the receiver's public key to see what was signed.
# usage: 10-check-challenge.sh CHALLENGE_B64 RESPONSE_B64
set -euo pipefail
S=~/w200-build/shairport/src/shairport-sync
T=$(mktemp -d)
# shairport-sync embeds the (well-known) AirPort Express private key as a PEM string literal
python3 - "$S" "$T/key.pem" <<'EOF'
import re, sys, glob
src = ''.join(open(f, errors='ignore').read() for f in glob.glob(sys.argv[1] + '/*.c'))
m = re.search(r'-----BEGIN RSA PRIVATE KEY-----(.*?)-----END RSA PRIVATE KEY-----', src, re.S)
body = re.sub(r'\\n|"|\s', '', m.group(1))
pem = '-----BEGIN RSA PRIVATE KEY-----\n' + '\n'.join(body[i:i+64] for i in range(0, len(body), 64)) + '\n-----END RSA PRIVATE KEY-----\n'
open(sys.argv[2], 'w').write(pem)
EOF
python3 - "$2" "$T/resp.bin" <<'EOF'
import base64, sys
s = sys.argv[1]; s += '=' * (-len(s) % 4)
open(sys.argv[2], 'wb').write(base64.b64decode(s))
EOF
openssl pkeyutl -verifyrecover -inkey "$T/key.pem" -pkeyopt rsa_padding_mode:pkcs1 -in "$T/resp.bin" -out "$T/plain.bin" 2>/dev/null \
  || { echo "signature does NOT verify with PKCS#1 v1.5"; openssl pkeyutl -verifyrecover -inkey "$T/key.pem" -pkeyopt rsa_padding_mode:none -in "$T/resp.bin" | xxd | head; exit 0; }
python3 - "$1" "$T/plain.bin" <<'EOF'
import base64, sys, ipaddress
c = sys.argv[1]; c += '=' * (-len(c) % 4); ch = base64.b64decode(c)
p = open(sys.argv[2], 'rb').read()
print('signed payload (%d bytes): %s' % (len(p), p.hex()))
print('challenge matches:', p[:16] == ch)
rest = p[16:]
if len(rest) >= 22:
    print('IPv6 :', ipaddress.IPv6Address(rest[:16]), ' hw:', rest[16:22].hex())
if len(rest) >= 10:
    print('IPv4?:', ipaddress.IPv4Address(rest[:4]), ' hw?:', rest[4:10].hex())
EOF
rm -rf "$T"
