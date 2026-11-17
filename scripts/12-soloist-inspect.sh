#!/usr/bin/env bash
# Download Spotify Soloist (ARM32) and inspect what it needs at runtime
set -euo pipefail
B=~/w200-build/soloist
mkdir -p "$B/dl" && cd "$B/dl"
curl -sSfL -o soloist_release_arm32.tar.gz https://soloist-builds.spotifycdn.com/soloist_release_arm32.tar.gz
echo "bytes: $(stat -c %s soloist_release_arm32.tar.gz)  sha256: $(sha256sum soloist_release_arm32.tar.gz | cut -c1-16)..."
rm -rf ../x && mkdir ../x && tar xzf soloist_release_arm32.tar.gz -C ../x
cd ../x
echo "--- contents"; find . -maxdepth 3 | head -30
BIN=$(find . -type f -name 'soloist*' -perm -u+x | head -1)
[ -z "$BIN" ] && BIN=$(find . -type f -perm -u+x | head -1)
echo "--- main binary: $BIN"
file "$BIN"
echo "--- interpreter / NEEDED"
readelf -l "$BIN" | grep -i 'interpreter' || true
readelf -d "$BIN" | grep -E 'NEEDED|RPATH|RUNPATH' || true
echo "--- required GLIBC symbol versions (max)"
readelf -V "$BIN" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -3
echo "--- other libs shipped"
find . -name '*.so*' | head -20
echo "--- audio-related strings"
strings -n 6 "$BIN" | grep -iE 'libpipewire|libpulse|pa_simple|pw_stream|alsa|snd_pcm' | sort -u | head -20
