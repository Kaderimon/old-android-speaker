#!/usr/bin/env bash
# Build the AudioTrack helper (W200Pcm) into a dex jar for Android 4.2 (API 17)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
R8V=8.5.35
SRC=$W/helper
OUT=$W/out
B=~/w200-build/helper
mkdir -p "$B/classes" "$B/dex" "$OUT" ~/w200-build/tools
cd ~/w200-build/tools
if [ ! -f "r8-$R8V.jar" ]; then
  curl -sSfL -o "r8-$R8V.jar" "https://dl.google.com/android/maven2/com/android/tools/r8/$R8V/r8-$R8V.jar"
  echo "r8 jar bytes: $(stat -c %s r8-$R8V.jar)"
fi
rm -rf "$B/classes"/* "$B/dex"/*
javac --release 8 -d "$B/classes" "$SRC/W200Pcm.java"
java -cp "r8-$R8V.jar" com.android.tools.r8.D8 --release --min-api 17 --output "$B/dex" "$B/classes"/*.class
cd "$B/dex" && rm -f "$OUT/w200pcm.jar" && zip -q "$OUT/w200pcm.jar" classes.dex
ls -l "$OUT/w200pcm.jar"

# 2-second 440 Hz test tone (quiet), S16LE stereo 44.1 kHz
python3 - "$OUT/tone.raw" <<'EOF'
import math, struct, sys
r = 44100
with open(sys.argv[1], 'wb') as f:
    for i in range(r * 2):
        v = int(0.15 * 32767 * math.sin(2 * math.pi * 440 * i / r))
        f.write(struct.pack('<hh', v, v))
EOF
ls -l "$OUT/tone.raw"
