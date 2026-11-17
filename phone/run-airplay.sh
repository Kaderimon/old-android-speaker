#!/system/bin/sh
# AirPlay receiver: shairport-sync -> raw PCM -> W200Pcm (AudioTrack) -> 3.5 mm jack
D=/data/local/tmp/w200
[ -f $D/config.sh ] && . $D/config.sh
NAME=${AIRPLAY_NAME:-W200}
export ANDROID_DATA=$D
export CLASSPATH=$D/w200pcm.jar
export MDNS_HOSTNAME=${AIRPLAY_HOST:-w200-airplay}
mkdir -p $D/dalvik-cache
echo $$ > $D/airplay.pid
while true; do
  echo "=== start $(date) ===" >> $D/shairport.log
  $D/shairport-sync -c $D/shairport-sync.conf -a "$NAME" ${AIRPLAY_VERBOSE} -o stdout 2>> $D/shairport.log \
    | app_process /system/bin W200Pcm 44100 2>> $D/pcm-airplay.log
  sleep 3
  for f in $D/shairport.log $D/pcm-airplay.log; do
    set -- $(ls -l $f 2>/dev/null)
    [ "${4:-0}" -gt 1000000 ] 2>/dev/null && mv $f $f.old
  done
done
