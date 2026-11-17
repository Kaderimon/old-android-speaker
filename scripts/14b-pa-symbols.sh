#!/usr/bin/env bash
# Compare the pa_* names Soloist references with what w200pulse exports
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
S=~/w200-build/soloist/x/soloist
L=$W/out/soloist/lib/libpulse.so.0
strings -n 4 "$S" | grep -E '^pa_[a-z0-9_]+$' | sort -u > /tmp/need.txt
readelf -Ws --dyn-syms "$L" | awk '$7!="UND" && $8 ~ /^pa_/ {print $8}' | sort -u > /tmp/have.txt
echo "needed: $(wc -l < /tmp/need.txt)  exported: $(wc -l < /tmp/have.txt)"
echo "--- missing:"; comm -23 /tmp/need.txt /tmp/have.txt
# also: any pa_ names embedded inside longer strings (e.g. format strings)
echo "--- other pa_ mentions:"; strings -n 4 "$S" | grep -oE '\bpa_[a-z0-9_]{3,}' | sort -u | comm -23 - /tmp/need.txt | head -20
