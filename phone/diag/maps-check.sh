#!/system/bin/sh
# Which audio libraries has the running Soloist process loaded? (diagnostics)
ps | while read u pid ppid rest; do
  case "$rest" in *ld-linux*)
    echo "pid $pid:"
    grep -E 'libpulse|libpipewire' /proc/$pid/maps | while read a b c d e path; do echo "  $path"; done
  ;; esac
done
echo "w200pulse log lines: $(grep -c w200pulse /data/local/tmp/w200/soloist/soloist.log)"
