#!/usr/bin/env bash
# Which PulseAudio API does Soloist use, and fetch a Debian 13 (trixie) armhf glibc runtime for it
set -euo pipefail
B=~/w200-build/soloist
echo "--- pa_* symbols referenced (dlsym names)"
strings -n 4 "$B/x/soloist" | grep -E '^pa_[a-z_]+$' | sort -u | tr '\n' ' '; echo
echo "--- pw_* symbols"
strings -n 4 "$B/x/soloist" | grep -E '^pw_[a-z_]+$' | sort -u | tr '\n' ' '; echo

# minimal glibc runtime from Debian trixie armhf
R=$B/rootfs; mkdir -p "$B/debs" "$R"
cd "$B/debs"
IDX=Packages
if [ ! -f $IDX ]; then
  curl -sSfL https://deb.debian.org/debian/dists/trixie/main/binary-armhf/Packages.xz | xz -d > $IDX
fi
for pkg in libc6 libatomic1 libgcc-s1 libstdc++6; do
  f=$(awk -v p="$pkg" '$1=="Package:"{cur=$2} cur==p && $1=="Filename:"{print $2; exit}' $IDX)
  [ -f "$(basename "$f")" ] || curl -sSfLO "https://deb.debian.org/debian/$f"
  echo "$pkg: $(basename "$f") ($(stat -c %s "$(basename "$f")") bytes)"
  dpkg-deb -x "$(basename "$f")" "$R"
done
ls "$R/usr/lib/arm-linux-gnueabihf" | grep -E '^(ld-linux|libc\.so|libm\.so|libatomic|librt|libdl|libpthread)' | tr '\n' ' '; echo
