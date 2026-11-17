#!/system/bin/sh
# Exercise Soloist's controls and time each one (diagnostics)
C="sh /data/local/tmp/w200/soloist-ctl.sh"
t() { echo "--- $(date +%H:%M:%S) $*"; $C "$@" 2>&1 | while read l; do echo "    $l"; done; }
t activate; sleep 2
t play;     sleep 7
t now
t next;     sleep 7
t now
t pause;    sleep 3
t play;     sleep 5
t seek 60000; sleep 5
t now
t pause
