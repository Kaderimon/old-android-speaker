/* mdnsq SERVICE [seconds] - send an mDNS PTR query and print every record heard on 224.0.0.251:5353.
 * Diagnostic tool for the W200: shows what the local receivers actually advertise. */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static int read_name(const unsigned char *m, int len, int off, char *out, int outlen) {
    int o = 0, jumped = 0, ret = -1, guard = 0;
    while (off < len && guard++ < 128) {
        int l = m[off];
        if (l == 0) { if (!jumped) ret = off + 1; break; }
        if ((l & 0xC0) == 0xC0) {
            if (off + 1 >= len) return -1;
            if (!jumped) ret = off + 2;
            off = ((l & 0x3F) << 8) | m[off + 1];
            jumped = 1;
            continue;
        }
        off++;
        if (off + l > len) return -1;
        if (o + l + 2 < outlen) { memcpy(out + o, m + off, l); o += l; out[o++] = '.'; }
        off += l;
    }
    out[o] = 0;
    return ret;
}

static void dump(const unsigned char *m, int len, const char *from) {
    if (len < 12) return;
    int qd = (m[4] << 8) | m[5], an = (m[6] << 8) | m[7], ns = (m[8] << 8) | m[9], ar = (m[10] << 8) | m[11];
    int isresp = m[2] & 0x80;
    printf("--- %s from %s: %d answers, %d additional\n", isresp ? "RESPONSE" : "query", from, an, ar);
    int off = 12;
    char name[512], data[512];
    for (int i = 0; i < qd; i++) {
        off = read_name(m, len, off, name, sizeof name);
        if (off < 0 || off + 4 > len) return;
        if (!isresp) printf("  Q %s type %d\n", name, (m[off] << 8) | m[off + 1]);
        off += 4;
    }
    for (int i = 0; i < an + ns + ar; i++) {
        off = read_name(m, len, off, name, sizeof name);
        if (off < 0 || off + 10 > len) return;
        int type = (m[off] << 8) | m[off + 1];
        unsigned ttl = (m[off + 4] << 24) | (m[off + 5] << 16) | (m[off + 6] << 8) | m[off + 7];
        int rdlen = (m[off + 8] << 8) | m[off + 9];
        int rd = off + 10;
        if (rd + rdlen > len) return;
        data[0] = 0;
        if (type == 1 && rdlen == 4) snprintf(data, sizeof data, "%d.%d.%d.%d", m[rd], m[rd + 1], m[rd + 2], m[rd + 3]);
        else if (type == 28 && rdlen == 16) inet_ntop(AF_INET6, m + rd, data, sizeof data);
        else if (type == 12) read_name(m, len, rd, data, sizeof data);
        else if (type == 33 && rdlen > 6) {
            char t[256]; read_name(m, len, rd + 6, t, sizeof t);
            snprintf(data, sizeof data, "port %d -> %s", (m[rd + 4] << 8) | m[rd + 5], t);
        } else if (type == 16) {
            int p = rd, o = 0;
            while (p < rd + rdlen && o < (int)sizeof data - 4) {
                int l = m[p++];
                for (int k = 0; k < l && p < rd + rdlen && o < (int)sizeof data - 4; k++) data[o++] = m[p++];
                data[o++] = ' ';
            }
            data[o] = 0;
        } else snprintf(data, sizeof data, "(%d bytes)", rdlen);
        const char *tn = type == 1 ? "A" : type == 28 ? "AAAA" : type == 12 ? "PTR" : type == 33 ? "SRV" : type == 16 ? "TXT" : type == 47 ? "NSEC" : "?";
        printf("  %-4s %s ttl=%u  %s\n", tn, name, ttl, data);
        off = rd + rdlen;
    }
}

int main(int argc, char **argv) {
    const char *svc = argc > 1 ? argv[1] : "_raop._tcp.local";
    int secs = argc > 2 ? atoi(argv[2]) : 4;
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    int one = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET; a.sin_port = htons(5353); a.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(s, (struct sockaddr *)&a, sizeof a) < 0) { perror("bind 5353"); return 1; }
    struct ip_mreq mr; mr.imr_multiaddr.s_addr = inet_addr("224.0.0.251"); mr.imr_interface.s_addr = htonl(INADDR_ANY);
    if (setsockopt(s, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mr, sizeof mr) < 0) perror("join");

    unsigned char q[512]; int o = 12; memset(q, 0, 12); q[5] = 1;
    const char *p = svc;
    while (*p) { const char *d = strchr(p, '.'); int l = d ? (int)(d - p) : (int)strlen(p); q[o++] = l; memcpy(q + o, p, l); o += l; p += l; if (*p == '.') p++; }
    int qtype = argc > 3 ? atoi(argv[3]) : 12;              /* 12 PTR, 1 A, 33 SRV, 16 TXT */
    int qu = argc > 4 && strcmp(argv[4], "qu") == 0;        /* set the unicast-response bit */
    q[o++] = 0; q[o++] = qtype >> 8; q[o++] = qtype & 0xff; q[o++] = qu ? 0x80 : 0; q[o++] = 1;
    struct sockaddr_in g = {0}; g.sin_family = AF_INET; g.sin_port = htons(5353); g.sin_addr.s_addr = inet_addr("224.0.0.251");
    if (sendto(s, q, o, 0, (struct sockaddr *)&g, sizeof g) < 0) perror("sendto");
    printf("sent type-%d%s query for %s, listening %d s\n", qtype, qu ? " QU" : "", svc, secs);

    struct timeval tv = {0, 300000};
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    time_t end = time(NULL) + secs;
    while (time(NULL) < end) {
        unsigned char buf[9000]; struct sockaddr_in from; socklen_t fl = sizeof from;
        int n = recvfrom(s, buf, sizeof buf, 0, (struct sockaddr *)&from, &fl);
        if (n > 0) dump(buf, n, inet_ntoa(from.sin_addr));
    }
    return 0;
}
