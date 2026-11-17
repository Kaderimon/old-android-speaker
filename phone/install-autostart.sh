#!/system/bin/sh
# (run as root) install / remove the W200 autostart hook: /system/etc/install-recovery.sh
#   install-autostart.sh install | remove
D=/data/local/tmp/w200
T=/system/etc/install-recovery.sh
mount -o remount,rw /system || { echo "remount rw failed"; exit 1; }
case "$1" in
  install)
    if [ -e $T ] && ! grep -q 'W200 speaker autostart' $T; then
      echo "refusing: $T exists and is not ours"; mount -o remount,ro /system; exit 1
    fi
    cat $D/install-recovery.sh > $T
    chown root:root $T
    chmod 755 $T
    echo "installed $T" ;;
  remove)
    grep -q 'W200 speaker autostart' $T 2>/dev/null && rm $T && echo "removed $T" ;;
  *) echo "usage: $0 install|remove" ;;
esac
sync
mount -o remount,ro /system
ls -l $T 2>&1
mount | grep ' /system '
