/* netcheck HOST... - resolve each host with glibc (as Soloist does) and try TCP 443 on each address */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static double ms(struct timeval a, struct timeval b) { return (b.tv_sec - a.tv_sec) * 1000.0 + (b.tv_usec - a.tv_usec) / 1000.0; }

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        struct addrinfo hints, *res = NULL, *ai;
        memset(&hints, 0, sizeof hints);
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;
        struct timeval t0, t1;
        gettimeofday(&t0, NULL);
        int rc = getaddrinfo(argv[i], "443", &hints, &res);
        gettimeofday(&t1, NULL);
        if (rc) { printf("%s: getaddrinfo FAILED after %.0f ms: %s\n", argv[i], ms(t0, t1), gai_strerror(rc)); continue; }
        printf("%s: resolved in %.0f ms\n", argv[i], ms(t0, t1));
        for (ai = res; ai; ai = ai->ai_next) {
            char ip[64];
            void *a = ai->ai_family == AF_INET ? (void *)&((struct sockaddr_in *)ai->ai_addr)->sin_addr
                                               : (void *)&((struct sockaddr_in6 *)ai->ai_addr)->sin6_addr;
            inet_ntop(ai->ai_family, a, ip, sizeof ip);
            int s = socket(ai->ai_family, SOCK_STREAM, 0);
            fcntl(s, F_SETFL, O_NONBLOCK);
            gettimeofday(&t0, NULL);
            int c = connect(s, ai->ai_addr, ai->ai_addrlen);
            const char *result = "connected";
            if (c < 0 && errno == EINPROGRESS) {
                struct pollfd p = { s, POLLOUT, 0 };
                if (poll(&p, 1, 3000) <= 0) result = "TIMEOUT";
                else { int e = 0; socklen_t l = sizeof e; getsockopt(s, SOL_SOCKET, SO_ERROR, &e, &l); if (e) result = strerror(e); }
            } else if (c < 0) result = strerror(errno);
            gettimeofday(&t1, NULL);
            printf("    %-5s %-40s %s (%.0f ms)\n", ai->ai_family == AF_INET ? "IPv4" : "IPv6", ip, result, ms(t0, t1));
            close(s);
        }
        freeaddrinfo(res);
    }
    return 0;
}
