#!/system/bin/sh
# W200 speaker control:  w200ctl.sh start|stop|restart|status
# Spotify: Soloist (official client) if an API key is installed, otherwise librespot.
D=/data/local/tmp/w200

kill_named() {   # kill processes whose ps NAME matches one of the args (SIGTERM, then SIGKILL)
  sig=TERM
  for round in 1 2; do
    ps | while read u pid ppid vsz rss wchan pc s name; do
      for n in "$@"; do
        case "$name" in *"$n"*) kill -$sig "$pid" 2>/dev/null ;; esac
      done
    done
    sleep 2
    sig=KILL
  done
}

stop_all() {
  for f in $D/spotify.pid $D/airplay.pid $D/soloist.pid; do
    [ -f $f ] && kill $(cat $f) 2>/dev/null
    rm -f $f
  done
  kill_named librespot shairport-sync ld-linux-armhf soloist
  sleep 1
}

start_all() {
  if [ -s $D/soloist.key ] && [ -x $D/soloist/soloist ]; then
    $D/daemonize $D/run-soloist.sh
  elif [ -x $D/librespot ]; then
    $D/daemonize $D/run-spotify.sh
  fi
  [ -x $D/shairport-sync ] && $D/daemonize $D/run-airplay.sh
  return 0
}

case "$1" in
  start)   stop_all; start_all ;;
  stop)    stop_all ;;
  restart) stop_all; start_all ;;
  status)  ps | while read u pid ppid vsz rss wchan pc s name; do
             case "$name" in *librespot*|*shairport*|*app_process*|*ld-linux*|*soloist*) echo "$pid $name" ;; esac
           done
           for f in $D/spotify.pid $D/airplay.pid $D/soloist.pid; do [ -f $f ] && n=${f##*/} && echo "${n%.pid} loop pid $(cat $f)"; done ;;
  *) echo "usage: $0 start|stop|restart|status" ;;
esac
