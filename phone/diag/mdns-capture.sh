#!/system/bin/sh
# Record mDNS traffic for N seconds (default 300) into mdns-capture.log (diagnostics)
D=/data/local/tmp/w200
exec $D/mdnsq _raop._tcp.local ${1:-300} > $D/mdns-capture.log 2>&1
