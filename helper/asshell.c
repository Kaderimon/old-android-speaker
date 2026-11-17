/* asshell PROG [ARGS...] - (run as root) drop to the adb "shell" user with its usual groups, then exec.
 * Used at boot so the receivers run exactly as they do when started from `adb shell`. */
#include <grp.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s PROG [ARGS...]\n", argv[0]); return 2; }
    /* shell's groups on Android 4.2: graphics input log mount adb sdcard_rw sdcard_r
       net_bt_admin net_bt inet net_bw_stats (same as `adb shell id`) */
    gid_t groups[] = { 1003, 1004, 1007, 1009, 1011, 1015, 1028, 3001, 3002, 3003, 3006 };
    if (setgroups(sizeof groups / sizeof groups[0], groups) != 0) { perror("setgroups"); return 1; }
    if (setgid(2000) != 0) { perror("setgid"); return 1; }
    if (setuid(2000) != 0) { perror("setuid"); return 1; }
    execv(argv[1], argv + 1);
    perror("execv");
    return 127;
}
