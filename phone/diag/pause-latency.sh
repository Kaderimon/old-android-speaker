#!/system/bin/sh
# Measure how fast the audio output stops after pause / reacts to skip (diagnostics)
C="sh /data/local/tmp/w200/soloist-ctl.sh"
state() {   # print the Soloist AudioTrack's state letter from AudioFlinger (A=active, P=paused, S=stopped...)
  dumpsys media.audio_flinger | grep -E '^ +[0-9]+ +[0-9]+ +3 ' | while read n client type fmt chn sess fr fc st rest; do echo "$st"; done | while read l; do echo -n "$l "; done
}
$C play >/dev/null 2>&1; sleep 6
echo "playing:        $(state)"
$C pause >/dev/null 2>&1
echo "right after pause: $(state)"
sleep 1
echo "1 s after pause:   $(state)"
$C play >/dev/null 2>&1; sleep 4
echo "resumed:        $(state)"
$C next >/dev/null 2>&1; sleep 3
echo "after next:     $(state)  now: $($C now 2>&1 | while read l; do echo -n "$l | "; done)"
$C pause >/dev/null 2>&1
