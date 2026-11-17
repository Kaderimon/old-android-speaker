/* daemonize PROG [ARGS...] - run PROG fully detached (new session, no tty, SIGHUP ignored).
 * Android 4.2's toolbox has no nohup/setsid, so processes started from `adb shell`
 * would otherwise die when the adb session closes. */
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s PROG [ARGS...]\n", argv[0]);
        return 2;
    }
    pid_t p = fork();
    if (p < 0) return 1;
    if (p > 0) {
        /* wait until the child has called setsid() and forked the grandchild, so an
         * adb session closing right after we return can't take the job down with it */
        int st;
        waitpid(p, &st, 0);
        return 0;
    }
    setsid();
    signal(SIGHUP, SIG_IGN);
    p = fork();
    if (p < 0) _exit(1);
    if (p > 0) _exit(0);          /* session leader exits; grandchild can't get a tty */
    int fd = open("/dev/null", O_RDWR);
    if (fd >= 0) {
        dup2(fd, 0); dup2(fd, 1); dup2(fd, 2);
        if (fd > 2) close(fd);
    }
    if (chdir("/") != 0) { /* ignore */ }
    execv(argv[1], argv + 1);
    _exit(127);
}
