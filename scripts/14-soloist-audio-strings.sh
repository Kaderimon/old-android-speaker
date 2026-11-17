#!/usr/bin/env bash
# Show strings stored near Soloist's audio-driver selection messages
B=~/w200-build/soloist/x/soloist
strings -t d -n 4 "$B" > /tmp/soloist.strings
for pat in 'Using PulseAudio' 'skipping PipeWire' 'Unable to initialize AudioDriver' 'PipeWire daemon not reachable' 'libpulse.so.0' 'PIPEWIRE_CONFIG_DIR'; do
  echo "=== around: $pat"
  n=$(grep -n -F "$pat" /tmp/soloist.strings | head -1 | cut -d: -f1)
  [ -n "$n" ] && sed -n "$((n-8)),$((n+8))p" /tmp/soloist.strings | cut -c1-140
done
