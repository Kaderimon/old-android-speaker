#!/system/bin/sh
# Start Soloist for N seconds with a placeholder key and log everything (diagnostics only)
S=/data/local/tmp/w200/soloist
mkdir -p $S/data $S/cache
{ for p in net.dns1 net.dns2; do v=$(getprop $p); [ -n "$v" ] && echo "nameserver $v"; done
  echo "nameserver 1.1.1.1"; } > /sdcard/w200.dns
cd $S
HOME=$S ./lib/ld-linux-armhf.so.3 --library-path ./lib ./soloist -n W200-probe -k PLACEHOLDER \
  -D $S/data -C $S/cache -v > $S/probe.log 2>&1 &
p=$!
sleep ${1:-20}
kill $p 2>/dev/null
sleep 1
kill -9 $p 2>/dev/null
echo done
