#!/usr/bin/env bash
# Build w200pulse (libpulse.so.0 stand-in) for armhf glibc, against the real PulseAudio headers
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
. ~/.cargo/env
B=~/w200-build/soloist
SRC=$W/helper/w200pulse.c
OUT=$W/out/soloist/lib
cd "$B/debs"
f=$(awk '$1=="Package:"{cur=$2} cur=="libpulse-dev" && $1=="Filename:"{print $2; exit}' Packages)
[ -f "$(basename "$f")" ] || curl -sSfLO "https://deb.debian.org/debian/$f"
echo "libpulse-dev: $(basename "$f") ($(stat -c %s "$(basename "$f")") bytes)"
rm -rf "$B/pulse-dev" && dpkg-deb -x "$(basename "$f")" "$B/pulse-dev"
INC="$B/pulse-dev/usr/include"
# pa_channel_map_init_stereo / pa_sample_format_to_string are real libpulse functions: provide tiny versions
cat > "$B/w200pulse-extra.c" <<'EOF'
#include <pulse/channelmap.h>
#include <pulse/sample.h>
#include <string.h>
pa_channel_map *pa_channel_map_init_stereo(pa_channel_map *m) {
    memset(m, 0, sizeof *m); m->channels = 2;
    m->map[0] = PA_CHANNEL_POSITION_LEFT; m->map[1] = PA_CHANNEL_POSITION_RIGHT; return m;
}
const char *pa_sample_format_to_string(pa_sample_format_t f) {
    switch (f) { case PA_SAMPLE_S16LE: return "s16le"; case PA_SAMPLE_FLOAT32LE: return "float32le";
                 case PA_SAMPLE_S32LE: return "s32le"; case PA_SAMPLE_S24LE: return "s24le"; default: return "other"; }
}
EOF
zig cc -target arm-linux-gnueabihf.2.17 -mcpu=$ZIG_CPU -O2 -fPIC -shared -Wall \
  -Wl,-soname,libpulse.so.0 -I"$INC" -o "$OUT/libpulse.so.0" "$SRC" "$B/w200pulse-extra.c" -lpthread -lm
zig cc -target arm-linux-gnueabihf.2.17 -mcpu=$ZIG_CPU -O2 -fPIC -shared -Wall \
  -o "$OUT/w200reuse.so" "$W/helper/w200reuse.c" -ldl
file "$OUT/w200reuse.so"
file "$OUT/libpulse.so.0"
readelf -d "$OUT/libpulse.so.0" | grep -E 'NEEDED|SONAME'
echo "exported pa_ symbols: $(readelf -Ws --dyn-syms "$OUT/libpulse.so.0" | grep -c ' pa_')"
