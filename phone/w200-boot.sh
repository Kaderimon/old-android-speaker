#!/system/bin/sh
# W200 speaker boot script - started as root by /system/etc/install-recovery.sh at every boot.
# Create /data/local/tmp/w200/autostart.off to skip starting the receivers.
D=/data/local/tmp/w200
LOG=$D/boot.log
echo "=== boot $(date)" > $LOG
chmod 644 $LOG

# 1. wait for Android to finish booting
n=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $n -lt 120 ]; do sleep 5; n=$((n+1)); done
echo "boot completed $(date)" >> $LOG

# 2. wait for internal storage (resolver file lives on /sdcard) and a Wi-Fi address
STORAGE=${EXTERNAL_STORAGE:-/sdcard}    # /storage/sdcard0 on the W200
n=0
while [ ! -d $STORAGE/Android ] && [ $n -lt 60 ]; do sleep 2; n=$((n+1)); done
n=0
while ! ip -o addr show wlan0 2>/dev/null | grep -q 'inet '; do
  [ $n -ge 150 ] && break
  sleep 2; n=$((n+1))
done
echo "storage+wifi ready $(date): $(ip -o addr show wlan0 2>/dev/null | grep 'inet ')" >> $LOG
sleep 5

# 3. keep the CPU awake (the screen can still turn off) so Wi-Fi and the receivers stay reachable
echo w200speaker > /sys/power/wake_lock && echo "wake lock held" >> $LOG

# 4. start AirPlay + Spotify as the adb shell user (same as deploy.ps1 / w200ctl.sh start)
if [ -f $D/autostart.off ]; then echo "autostart.off present - not starting receivers" >> $LOG; exit 0; fi
$D/asshell /system/bin/sh $D/w200ctl.sh start >> $LOG 2>&1
sleep 10
$D/asshell /system/bin/sh $D/w200ctl.sh status >> $LOG 2>&1
echo "done $(date)" >> $LOG
