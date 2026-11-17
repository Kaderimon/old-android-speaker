#!/system/bin/sh
# W200 speaker autostart (added 2026-11-16). Delete this file to remove the autostart.
[ -x /data/local/tmp/w200/w200-boot.sh ] && /data/local/tmp/w200/daemonize /data/local/tmp/w200/w200-boot.sh
exit 0
