#!/system/bin/sh
# Log TCP/UDP sockets on the AirPlay ports once a second for N seconds (default 300) - diagnostics
D=/data/local/tmp/w200
n=${1:-300}
: > $D/netmon.log
while [ $n -gt 0 ]; do
  s=$(netstat 2>/dev/null | grep -E ':(5000|600[0-9]|601[0-9]) ' | grep -v LISTEN)
  [ -n "$s" ] && { echo "== $(date +%H:%M:%S)"; echo "$s"; } >> $D/netmon.log
  sleep 1
  n=$((n-1))
done
