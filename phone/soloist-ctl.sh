#!/system/bin/sh
# Control the running Soloist from the phone:  soloist-ctl.sh play|pause|next|seek <ms>|now|status|volume <n>
S=/data/local/tmp/w200/soloist
[ -f /data/local/tmp/w200/config.sh ] && . /data/local/tmp/w200/config.sh
cd $S
exec ./lib/ld-linux-armhf.so.3 --library-path $S/lib ./soloist ctl "$@" -w 127.0.0.1:${SOLOIST_WS_PORT:-47123}
