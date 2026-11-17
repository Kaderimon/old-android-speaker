/* w200reuse.so - preloaded into Soloist: before any bind() to UDP port 5353 (mDNS), set
 * SO_REUSEADDR so Soloist can share the port with shairport-sync's mDNS responder.
 * (Linux only allows sharing when every socket on the port sets it; Soloist relies on
 * SO_REUSEPORT, which this phone's 3.4 kernel doesn't have.) */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <netinet/in.h>
#include <sys/socket.h>

int bind(int fd, const struct sockaddr *addr, socklen_t len) {
    static int (*real_bind)(int, const struct sockaddr *, socklen_t);
    if (!real_bind) real_bind = (int (*)(int, const struct sockaddr *, socklen_t))dlsym(RTLD_NEXT, "bind");
    int port = -1;
    if (addr && addr->sa_family == AF_INET && len >= (socklen_t)sizeof(struct sockaddr_in))
        port = ntohs(((const struct sockaddr_in *)addr)->sin_port);
    else if (addr && addr->sa_family == AF_INET6 && len >= (socklen_t)sizeof(struct sockaddr_in6))
        port = ntohs(((const struct sockaddr_in6 *)addr)->sin6_port);
    if (port == 5353) {
        int type = 0; socklen_t tl = sizeof type;
        if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &tl) == 0 && type == SOCK_DGRAM) {
            int on = 1;
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
        }
    }
    return real_bind(fd, addr, len);
}
