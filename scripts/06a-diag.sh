#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
OUT=$W/out
for b in librespot shairport-sync; do
  echo "$b: '/etc/resolv.conf' occurrences: $(grep -c -a -o '/etc/resolv.conf' "$OUT/$b")"
done
S=~/w200-build/shairport/src/shairport-sync
grep -n -E 'gethostname|hostname' "$S/mdns_tinysvcmdns.c" | head -20
