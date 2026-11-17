#!/system/bin/sh
# Spotify Connect receiver: librespot -> raw PCM -> W200Pcm (AudioTrack) -> 3.5 mm jack
D=/data/local/tmp/w200
[ -f $D/config.sh ] && . $D/config.sh
NAME=${SPOTIFY_NAME:-W200}
export ANDROID_DATA=$D
export CLASSPATH=$D/w200pcm.jar
export MDNS_HOSTNAME=${SPOTIFY_HOST:-w200-spotify}
# Android has no /tmp; librespot streams each track through a temp file
export TMPDIR=$D/tmp
mkdir -p $D/cache $D/dalvik-cache $D/tmp
rm -f $D/tmp/.tmp* 2>/dev/null
echo $$ > $D/spotify.pid
while true; do
  # musl reads its nameservers from /sdcard/w200.dns (Android has no /etc/resolv.conf)
  { for p in net.dns1 net.dns2; do v=$(getprop $p); [ -n "$v" ] && echo "nameserver $v"; done
    echo "nameserver 1.1.1.1"; } > /sdcard/w200.dns
  echo "=== start $(date) ===" >> $D/librespot.log
  $D/librespot --name "$NAME" --backend pipe --format S16 --bitrate 320 \
      --cache $D/cache --initial-volume 80 --device-type speaker 2>> $D/librespot.log \
    | app_process /system/bin W200Pcm 44100 2>> $D/pcm-spotify.log
  sleep 3
  # keep logs small
  for f in $D/librespot.log $D/pcm-spotify.log; do
    set -- $(ls -l $f 2>/dev/null)   # toolbox ls -l: perms user group SIZE date time name
    [ "${4:-0}" -gt 1000000 ] 2>/dev/null && mv $f $f.old
  done
done
