#!/system/bin/sh
# Spotify Connect via Spotify's official Soloist client:
# soloist (glibc from ./lib) -> w200pulse (fake libpulse, fd 3) -> W200Pcm (AudioTrack) -> 3.5 mm jack
D=/data/local/tmp/w200
S=$D/soloist
[ -f $D/config.sh ] && . $D/config.sh
NAME=${SPOTIFY_NAME:-W200}
export ANDROID_DATA=$D
export CLASSPATH=$D/w200pcm.jar
export HOME=$S
export W200_PCM_FD=3
export W200_PCM_FRAMED=1      # audio frames + pause/resume/flush markers for W200Pcm
# Android 4.2 has no /etc/ssl/certs: use the bundled Mozilla CA list
export SSL_CERT_FILE=$S/ca-certificates.crt
[ -n "$W200_PULSE_DEBUG" ] && export W200_PULSE_DEBUG
[ -n "$W200_PULSE_TRACE" ] && export W200_PULSE_TRACE
mkdir -p $S/data $S/cache $D/dalvik-cache
echo $$ > $D/soloist.pid
while true; do
  KEY=$(cat $D/soloist.key 2>/dev/null)
  if [ -z "$KEY" ]; then echo "$(date) no API key in $D/soloist.key" >> $S/soloist.log; sleep 60; continue; fi
  # glibc reads its nameservers from /sdcard/w200.dns (Android has no /etc/resolv.conf)
  { for p in net.dns1 net.dns2; do v=$(getprop $p); [ -n "$v" ] && echo "nameserver $v"; done
    echo "nameserver 1.1.1.1"; } > /sdcard/w200.dns
  echo "=== start $(date) ===" >> $S/soloist.log
  cd $S
  ./lib/ld-linux-armhf.so.3 --library-path $S/lib --preload $S/lib/w200reuse.so ./soloist -n "$NAME" -k "$KEY" -D $S/data -C $S/cache \
      -i ${SOLOIST_VOLUME:-60} -w 127.0.0.1:${SOLOIST_WS_PORT:-47123} $SOLOIST_VERBOSE 3>&1 >> $S/soloist.log 2>&1 \
    | app_process /system/bin W200Pcm 44100 framed 2>> $D/pcm-soloist.log
  rc=$?
  echo "=== exit $(date) ===" >> $S/soloist.log
  sleep 5
  for f in $S/soloist.log $D/pcm-soloist.log; do
    set -- $(ls -l $f 2>/dev/null)
    [ "${4:-0}" -gt 1000000 ] 2>/dev/null && mv $f $f.old
  done
done
