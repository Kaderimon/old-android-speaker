/*
 * w200pulse - a tiny stand-in for libpulse.so.0 for running Spotify Soloist on the W200.
 *
 * Soloist dlopen()s libpulse and uses ~48 functions of the async API. There is no PulseAudio
 * server on Android 4.2, so this library implements just those functions: contexts and streams
 * become "ready" immediately, pa_stream_write() converts the audio to S16LE stereo, applies the
 * sink-input volume (so Spotify's volume slider works) and writes it to a file descriptor
 * (W200_PCM_FD, default 3), which the launcher pipes into W200Pcm (Android AudioTrack).
 *
 * Built against the real PulseAudio headers so every struct layout matches.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include <pulse/pulseaudio.h>
#include <pulse/thread-mainloop.h>

#define LOG(...) do { if (w200_debug) { fprintf(stderr, "[w200pulse] " __VA_ARGS__); fputc('\n', stderr); } } while (0)
static int w200_debug = -1;
static void init_debug(void) { if (w200_debug < 0) w200_debug = getenv("W200_PULSE_DEBUG") != NULL; }

/* W200_PULSE_TRACE=N: log the first N API calls after playback starts, with timestamps */
static int trace_left = -1, trace_armed = 0;
static unsigned long long trace_t0;
static unsigned long long mono_us(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return (unsigned long long)ts.tv_sec * 1000000ULL + ts.tv_nsec / 1000; }
#define TRACE(...) do { \
    if (trace_left < 0) { const char *e = getenv("W200_PULSE_TRACE"); trace_left = e ? atoi(e) : 0; } \
    if (trace_armed && trace_left > 0) { trace_left--; \
        fprintf(stderr, "[w200trace] %8.3f ms tid=%lu ", (mono_us() - trace_t0) / 1000.0, (unsigned long)pthread_self() % 100000); \
        fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

/* ---------------- threaded main loop + deferred callback queue ---------------- */
struct task { void (*fn)(void *); void *arg; struct task *next; };

struct pa_threaded_mainloop {
    pa_mainloop_api api;          /* must be first: context recovers the loop from the api pointer */
    pthread_mutex_t mutex;
    pthread_cond_t cond;            /* client waiters (pa_threaded_mainloop_wait) */
    pthread_cond_t wake;            /* wakes the loop thread as soon as a task is queued */
    pthread_t thread;
    int running;
    struct task *head, *tail;
};

static void enqueue(pa_threaded_mainloop *m, void (*fn)(void *), void *arg) {
    struct task *t = calloc(1, sizeof *t);
    t->fn = fn; t->arg = arg;
    if (m->tail) m->tail->next = t; else m->head = t;
    m->tail = t;
    /* Answer right away, like a real PulseAudio server on a local socket. Waiting for the next
     * 5 ms tick made each timing-info round trip cost 5-10 ms, so Soloist fell behind real time. */
    pthread_cond_signal(&m->wake);
}

static void *loop_thread(void *p) {
    pa_threaded_mainloop *m = p;
    pthread_mutex_lock(&m->mutex);
    while (m->running) {
        struct task *t;
        while ((t = m->head)) {
            m->head = t->next;
            if (!m->head) m->tail = NULL;
            t->fn(t->arg);           /* callbacks run with the lock held, like real libpulse */
            free(t);
        }
        /* Wake client waiters (also periodically: real libpulse wakes clients often, and
         * spurious wake-ups are allowed), then sleep until a task arrives or 5 ms pass. */
        pthread_cond_broadcast(&m->cond);
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_nsec += 5 * 1000000L;
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
        if (!m->head) pthread_cond_timedwait(&m->wake, &m->mutex, &ts);
    }
    pthread_mutex_unlock(&m->mutex);
    return NULL;
}

__attribute__((constructor)) static void w200pulse_loaded(void) {
    init_debug();
    LOG("library loaded");
}

pa_threaded_mainloop *pa_threaded_mainloop_new(void) {
    init_debug();
    pa_threaded_mainloop *m = calloc(1, sizeof *m);
    pthread_mutexattr_t a;
    pthread_mutexattr_init(&a);
    pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&m->mutex, &a);
    pthread_cond_init(&m->cond, NULL);
    pthread_cond_init(&m->wake, NULL);
    m->api.userdata = m;
    LOG("mainloop new");
    return m;
}
int pa_threaded_mainloop_start(pa_threaded_mainloop *m) {
    m->running = 1;
    return pthread_create(&m->thread, NULL, loop_thread, m) == 0 ? 0 : -1;
}
void pa_threaded_mainloop_stop(pa_threaded_mainloop *m) {
    pthread_mutex_lock(&m->mutex);
    int was = m->running; m->running = 0;
    pthread_cond_signal(&m->wake);
    pthread_mutex_unlock(&m->mutex);
    if (was && !pthread_equal(pthread_self(), m->thread)) pthread_join(m->thread, NULL);
}
void pa_threaded_mainloop_free(pa_threaded_mainloop *m) {
    if (!m) return;
    pa_threaded_mainloop_stop(m);
    struct task *t = m->head;
    while (t) { struct task *n = t->next; free(t); t = n; }
    free(m);
}
void pa_threaded_mainloop_lock(pa_threaded_mainloop *m) { pthread_mutex_lock(&m->mutex); }
void pa_threaded_mainloop_unlock(pa_threaded_mainloop *m) { pthread_mutex_unlock(&m->mutex); }
void pa_threaded_mainloop_wait(pa_threaded_mainloop *m) {
    TRACE("mainloop_wait");
    /* timed so a missed signal can never hang the caller */
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_nsec += 10 * 1000000L;
    if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
    pthread_cond_timedwait(&m->cond, &m->mutex, &ts);
}
void pa_threaded_mainloop_signal(pa_threaded_mainloop *m, int wait_for_accept) {
    TRACE("mainloop_signal accept=%d", wait_for_accept);
    pthread_cond_broadcast(&m->cond);
}
pa_mainloop_api *pa_threaded_mainloop_get_api(pa_threaded_mainloop *m) { return &m->api; }

/* ---------------- operations ---------------- */
struct pa_operation { int refs; pa_operation_state_t state; };
static pa_operation *op_new(void) { pa_operation *o = calloc(1, sizeof *o); o->refs = 2; o->state = PA_OPERATION_RUNNING; return o; }
static void op_release(pa_operation *o) { if (o && --o->refs == 0) free(o); }
pa_operation_state_t pa_operation_get_state(const pa_operation *o) { return o ? o->state : PA_OPERATION_DONE; }
void pa_operation_unref(pa_operation *o) { op_release(o); }

/* ---------------- proplist (ignored) ---------------- */
struct pa_proplist { int dummy; };
pa_proplist *pa_proplist_new(void) { return calloc(1, sizeof(pa_proplist)); }
void pa_proplist_free(pa_proplist *p) { free(p); }
int pa_proplist_sets(pa_proplist *p, const char *key, const char *value) { (void)p; (void)key; (void)value; return 0; }

/* ---------------- context ---------------- */
struct pa_context {
    pa_threaded_mainloop *m;
    pa_context_state_t state;
    pa_context_notify_cb_t state_cb; void *state_ud;
    pa_context_subscribe_cb_t sub_cb; void *sub_ud;
    double gain;                    /* linear gain from the sink-input volume */
};
static pa_context *g_ctx;           /* streams look up the volume here */

pa_context *pa_context_new(pa_mainloop_api *api, const char *name) {
    init_debug();
    pa_context *c = calloc(1, sizeof *c);
    c->m = (pa_threaded_mainloop *)api;   /* api is the first member of the loop */
    c->state = PA_CONTEXT_UNCONNECTED;
    c->gain = 1.0;
    g_ctx = c;
    LOG("context new '%s'", name ? name : "");
    return c;
}
void pa_context_unref(pa_context *c) { if (g_ctx == c) g_ctx = NULL; free(c); }
void pa_context_set_state_callback(pa_context *c, pa_context_notify_cb_t cb, void *ud) { c->state_cb = cb; c->state_ud = ud; }
void pa_context_set_subscribe_callback(pa_context *c, pa_context_subscribe_cb_t cb, void *ud) { c->sub_cb = cb; c->sub_ud = ud; }
int pa_context_errno(const pa_context *c) { (void)c; return 0; }
pa_context_state_t pa_context_get_state(const pa_context *c) { return c->state; }

static void ctx_set_state(pa_context *c, pa_context_state_t s) { c->state = s; if (c->state_cb) c->state_cb(c, c->state_ud); }
static void ctx_connect_task(void *p) {
    pa_context *c = p;
    ctx_set_state(c, PA_CONTEXT_AUTHORIZING);
    ctx_set_state(c, PA_CONTEXT_SETTING_NAME);
    ctx_set_state(c, PA_CONTEXT_READY);
    LOG("context ready");
}
int pa_context_connect(pa_context *c, const char *server, pa_context_flags_t flags, const pa_spawn_api *api) {
    (void)flags; (void)api;
    LOG("context connect server=%s", server ? server : "(default)");
    /* like real libpulse: CONNECTING is entered synchronously, the rest happens on the loop */
    ctx_set_state(c, PA_CONTEXT_CONNECTING);
    enqueue(c->m, ctx_connect_task, c);
    return 0;
}
static void ctx_disconnect_task(void *p) { ctx_set_state(p, PA_CONTEXT_TERMINATED); }
void pa_context_disconnect(pa_context *c) {
    if (c->state != PA_CONTEXT_TERMINATED) enqueue(c->m, ctx_disconnect_task, c);
}

struct succ_task { pa_context *c; pa_context_success_cb_t cb; void *ud; pa_operation *o; };
static void ctx_success_task(void *p) {
    struct succ_task *t = p;
    if (t->cb) t->cb(t->c, 1, t->ud);
    t->o->state = PA_OPERATION_DONE;
    op_release(t->o);
    free(t);
}
static pa_operation *ctx_success_later(pa_context *c, pa_context_success_cb_t cb, void *ud) {
    struct succ_task *t = calloc(1, sizeof *t);
    t->c = c; t->cb = cb; t->ud = ud; t->o = op_new();
    enqueue(c->m, ctx_success_task, t);
    return t->o;
}
pa_operation *pa_context_subscribe(pa_context *c, pa_subscription_mask_t mask, pa_context_success_cb_t cb, void *ud) {
    (void)mask;
    return ctx_success_later(c, cb, ud);
}

struct sii_task { pa_context *c; pa_sink_input_info_cb_t cb; void *ud; pa_operation *o; uint32_t idx; };
static void sii_task_fn(void *p) {
    struct sii_task *t = p;
    if (t->cb) {
        pa_sink_input_info i;
        memset(&i, 0, sizeof i);
        i.index = t->idx;
        i.name = "w200";
        i.sink = 0;
        i.sample_spec.format = PA_SAMPLE_S16LE; i.sample_spec.rate = 44100; i.sample_spec.channels = 2;
        pa_channel_map_init_stereo(&i.channel_map);
        /* report the volume we are applying, as a cubic PulseAudio volume */
        pa_volume_t v = (pa_volume_t)(cbrt(t->c->gain) * PA_VOLUME_NORM + 0.5);
        i.volume.channels = 2; i.volume.values[0] = i.volume.values[1] = v;
        i.has_volume = 1; i.volume_writable = 1;
        i.driver = "w200"; i.resample_method = "";
        t->cb(t->c, &i, 0, t->ud);
        t->cb(t->c, NULL, 1, t->ud);
    }
    t->o->state = PA_OPERATION_DONE;
    op_release(t->o);
    free(t);
}
pa_operation *pa_context_get_sink_input_info(pa_context *c, uint32_t idx, pa_sink_input_info_cb_t cb, void *ud) {
    struct sii_task *t = calloc(1, sizeof *t);
    t->c = c; t->cb = cb; t->ud = ud; t->idx = idx; t->o = op_new();
    enqueue(c->m, sii_task_fn, t);
    return t->o;
}
pa_operation *pa_context_set_sink_input_volume(pa_context *c, uint32_t idx, const pa_cvolume *vol, pa_context_success_cb_t cb, void *ud) {
    (void)idx;
    if (vol && vol->channels) {
        double v = (double)pa_cvolume_avg(vol) / PA_VOLUME_NORM;
        if (v < 0) v = 0;
        if (v > 1.5) v = 1.5;
        c->gain = v * v * v;            /* PulseAudio volumes are cubic */
        LOG("volume -> %.3f (gain %.4f)", v, c->gain);
    }
    return ctx_success_later(c, cb, ud);
}

/* ---------------- volume / time helpers ---------------- */
pa_volume_t pa_cvolume_avg(const pa_cvolume *a) {
    if (!a || a->channels == 0) return PA_VOLUME_MUTED;
    uint64_t s = 0;
    for (unsigned i = 0; i < a->channels; i++) s += a->values[i];
    return (pa_volume_t)(s / a->channels);
}
pa_cvolume *pa_cvolume_set(pa_cvolume *a, unsigned channels, pa_volume_t v) {
    if (channels > PA_CHANNELS_MAX) channels = PA_CHANNELS_MAX;
    a->channels = (uint8_t)channels;
    for (unsigned i = 0; i < channels; i++) a->values[i] = v;
    return a;
}
struct timeval *pa_gettimeofday(struct timeval *tv) { gettimeofday(tv, NULL); return tv; }
pa_usec_t pa_timeval_diff(const struct timeval *a, const struct timeval *b) {
    int64_t d = ((int64_t)a->tv_sec - b->tv_sec) * 1000000LL + (a->tv_usec - b->tv_usec);
    TRACE("timeval_diff -> %lld us", (long long)(d < 0 ? -d : d));
    return (pa_usec_t)(d < 0 ? -d : d);
}
static size_t frame_bytes(const pa_sample_spec *s) {
    size_t b = (s->format == PA_SAMPLE_S16LE || s->format == PA_SAMPLE_S16BE) ? 2 :
               (s->format == PA_SAMPLE_U8 || s->format == PA_SAMPLE_ALAW || s->format == PA_SAMPLE_ULAW) ? 1 :
               (s->format == PA_SAMPLE_S24LE || s->format == PA_SAMPLE_S24BE) ? 3 : 4;
    return b * s->channels;
}
size_t pa_usec_to_bytes(pa_usec_t t, const pa_sample_spec *spec) {
    size_t fb = frame_bytes(spec);
    size_t r = (size_t)((t * spec->rate) / 1000000ULL) * fb;
    TRACE("usec_to_bytes %llu us -> %zu", (unsigned long long)t, r);
    return r;
}
static int stream_state_traced(void) { return 0; }
const char *pa_strerror(int error) { return error ? "w200pulse error" : "OK"; }

/* ---------------- stream ---------------- */
static uint64_t now_us(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return (uint64_t)ts.tv_sec * 1000000ULL + ts.tv_nsec / 1000; }

struct pa_stream {
    pa_context *c;
    pa_sample_spec ss;
    pa_stream_state_t state;
    pa_stream_notify_cb_t state_cb; void *state_ud;
    pa_stream_notify_cb_t started_cb; void *started_ud;
    pa_stream_notify_cb_t underflow_cb; void *underflow_ud;
    int corked, started;
    uint64_t written, consumed;     /* bytes in the stream's own format */
    uint64_t base_us;               /* playback clock origin ... */
    uint64_t base_bytes;            /* ... and bytes consumed at that origin */
    uint64_t clock_us;              /* unused (kept for layout clarity) */
    size_t target;                  /* emulated server buffer (bytes) */
    pa_timing_info ti;
    int fd;
    int framed;                     /* W200_PCM_FRAMED: frame audio + send pause/resume/flush markers */
    int16_t *conv; size_t conv_cap;
};

/* Emulated playback position. Computed from a fixed origin (base_us/base_bytes) rather than by
 * adding small increments, so frequent polling cannot lose time to rounding. (The incremental
 * version made the clock run at ~55% speed: slow-motion audio and a stalled player.) */
static void rebase(pa_stream *s) { s->base_us = now_us(); s->base_bytes = s->consumed; }

static void advance_clock(pa_stream *s) {
    if (s->corked || !s->started) return;
    uint64_t bps = (uint64_t)s->ss.rate * frame_bytes(&s->ss);
    uint64_t c = s->base_bytes + (now_us() - s->base_us) * bps / 1000000ULL;
    if (c >= s->written) {          /* underrun: playback can't run ahead of the data */
        s->consumed = s->written;
        rebase(s);
    } else {
        s->consumed = c;
    }
}

static pa_stream *stream_new(pa_context *c, const char *name, const pa_sample_spec *ss) {
    pa_stream *s = calloc(1, sizeof *s);
    s->c = c; s->ss = *ss; s->state = PA_STREAM_UNCONNECTED;
    const char *fd = getenv("W200_PCM_FD");
    s->fd = fd ? atoi(fd) : 3;
    s->framed = getenv("W200_PCM_FRAMED") != NULL;
    rebase(s);
    fprintf(stderr, "[w200pulse] stream '%s': format=%s rate=%u channels=%u\n", name ? name : "",
            pa_sample_format_to_string(ss->format), ss->rate, ss->channels);
    return s;
}
pa_stream *pa_stream_new(pa_context *c, const char *name, const pa_sample_spec *ss, const pa_channel_map *map) {
    (void)map; return stream_new(c, name, ss);
}
pa_stream *pa_stream_new_with_proplist(pa_context *c, const char *name, const pa_sample_spec *ss, const pa_channel_map *map, pa_proplist *p) {
    (void)map; (void)p; return stream_new(c, name, ss);
}
void pa_stream_unref(pa_stream *s) { if (s) { free(s->conv); free(s); } }
pa_stream_state_t pa_stream_get_state(const pa_stream *s) { TRACE("stream_get_state"); (void)stream_state_traced; return s->state; }
int pa_stream_is_corked_traced(void);
uint32_t pa_stream_get_index(const pa_stream *s) { (void)s; return 1; }
void pa_stream_set_state_callback(pa_stream *s, pa_stream_notify_cb_t cb, void *ud) { s->state_cb = cb; s->state_ud = ud; }
void pa_stream_set_started_callback(pa_stream *s, pa_stream_notify_cb_t cb, void *ud) { s->started_cb = cb; s->started_ud = ud; }
void pa_stream_set_underflow_callback(pa_stream *s, pa_stream_notify_cb_t cb, void *ud) { s->underflow_cb = cb; s->underflow_ud = ud; }

static void stream_set_state(pa_stream *s, pa_stream_state_t st) { s->state = st; if (s->state_cb) s->state_cb(s, s->state_ud); }
static void stream_ready_task(void *p) { pa_stream *s = p; stream_set_state(s, PA_STREAM_READY); LOG("stream ready"); }
int pa_stream_connect_playback(pa_stream *s, const char *dev, const pa_buffer_attr *attr, pa_stream_flags_t flags, const pa_cvolume *volume, pa_stream *sync) {
    (void)dev; (void)sync;
    uint64_t bps = (uint64_t)s->ss.rate * frame_bytes(&s->ss);
    s->target = (size_t)(bps / 4);                  /* 250 ms default */
    if (attr && attr->tlength != (uint32_t)-1 && attr->tlength > 0 && attr->tlength < bps * 2) s->target = attr->tlength;
    s->corked = (flags & PA_STREAM_START_CORKED) ? 1 : 0;
    if (volume && volume->channels) pa_context_set_sink_input_volume(s->c, 1, volume, NULL, NULL);
    LOG("connect_playback target=%zu corked=%d", s->target, s->corked);
    stream_set_state(s, PA_STREAM_CREATING);   /* synchronous, like real libpulse */
    enqueue(s->c->m, stream_ready_task, s);
    return 0;
}
static void stream_term_task(void *p) { stream_set_state(p, PA_STREAM_TERMINATED); }
int pa_stream_disconnect(pa_stream *s) { enqueue(s->c->m, stream_term_task, s); return 0; }

size_t pa_stream_writable_size(const pa_stream *cs) {
    pa_stream *s = (pa_stream *)cs;
    advance_clock(s);
    uint64_t buffered = s->written - s->consumed;
    size_t fb = frame_bytes(&s->ss);
    size_t w = buffered >= s->target ? 0 : (size_t)(s->target - buffered);
    w -= w % fb;
    TRACE("writable_size -> %zu (buffered %llu)", w, (unsigned long long)buffered);
    return w;
}

static void started_task(void *p) { pa_stream *s = p; if (s->started_cb) s->started_cb(s, s->started_ud); }

static void write_all(int fd, const void *buf, size_t len) {
    const uint8_t *p = buf;
    while (len > 0) {
        ssize_t n = write(fd, p, len);
        if (n < 0) { if (errno == EINTR) continue; return; }   /* no reader: drop */
        p += n; len -= (size_t)n;
    }
}

/* framed protocol for W200Pcm: "W2AU"<u32 len><pcm>  or  "W2CT"<u32 code> (1 pause, 2 resume, 3 flush) */
static void send_ctl(pa_stream *s, uint32_t code) {
    if (!s->framed) return;
    uint8_t h[8] = { 'W', '2', 'C', 'T', code & 0xff, (code >> 8) & 0xff, (code >> 16) & 0xff, code >> 24 };
    write_all(s->fd, h, sizeof h);
}

static void emit(pa_stream *s, const void *data, size_t nbytes) {
    /* convert to interleaved S16LE stereo with the current gain */
    unsigned ch = s->ss.channels ? s->ss.channels : 2;
    size_t bps = frame_bytes(&s->ss) / ch;
    size_t frames = nbytes / (bps * ch);
    if (s->conv_cap < frames * 2) { free(s->conv); s->conv_cap = frames * 2; s->conv = malloc(s->conv_cap * sizeof(int16_t)); }
    double g = s->c ? s->c->gain : 1.0;
    for (size_t f = 0; f < frames; f++) {
        for (unsigned k = 0; k < 2; k++) {
            unsigned src_ch = ch == 1 ? 0 : k;
            const uint8_t *p = (const uint8_t *)data + (f * ch + src_ch) * bps;
            double v;
            switch (s->ss.format) {
            case PA_SAMPLE_FLOAT32LE: { float x; memcpy(&x, p, 4); v = x * 32767.0; break; }
            case PA_SAMPLE_S32LE: { int32_t x; memcpy(&x, p, 4); v = x / 65536.0; break; }
            case PA_SAMPLE_S16LE: { int16_t x; memcpy(&x, p, 2); v = x; break; }
            default: v = 0; break;
            }
            v *= g;
            if (v > 32767) v = 32767;
            if (v < -32768) v = -32768;
            s->conv[f * 2 + k] = (int16_t)lrint(v);
        }
    }
    uint32_t len = (uint32_t)(frames * 2 * sizeof(int16_t));
    if (s->framed) {
        uint8_t h[8] = { 'W', '2', 'A', 'U', len & 0xff, (len >> 8) & 0xff, (len >> 16) & 0xff, len >> 24 };
        write_all(s->fd, h, sizeof h);
    }
    write_all(s->fd, s->conv, len);
}

int pa_stream_write(pa_stream *s, const void *data, size_t nbytes, pa_free_cb_t free_cb, int64_t offset, pa_seek_mode_t seek) {
    (void)offset; (void)seek;
    advance_clock(s);
    TRACE("write %zu bytes (offset %lld seek %d)", nbytes, (long long)offset, (int)seek);
    if (w200_debug) {   /* throughput stats every ~5 s */
        static uint64_t t0, bytes, calls;
        uint64_t t = now_us();
        if (!t0) t0 = t;
        bytes += nbytes; calls++;
        if (t - t0 > 5000000ULL) {
            double secs = (t - t0) / 1e6, fb = (double)frame_bytes(&s->ss);
            LOG("writes: %.0f frames/s (%.1f%% of %u Hz), %.1f writes/s, avg %.0f frames",
                bytes / fb / secs, 100.0 * bytes / fb / secs / s->ss.rate, s->ss.rate, calls / secs, bytes / fb / calls);
            t0 = t; bytes = calls = 0;
        }
    }
    if (data && nbytes) emit(s, data, nbytes);
    s->written += nbytes;
    if (!s->started && !s->corked) { s->started = 1; rebase(s); enqueue(s->c->m, started_task, s); }
    if (free_cb) free_cb((void *)data);
    return 0;
}

struct ssucc_task { pa_stream *s; pa_stream_success_cb_t cb; void *ud; pa_operation *o; };
static void stream_success_task(void *p) {
    struct ssucc_task *t = p;
    if (t->cb) t->cb(t->s, 1, t->ud);
    t->o->state = PA_OPERATION_DONE;
    op_release(t->o);
    free(t);
}
static pa_operation *stream_success_later(pa_stream *s, pa_stream_success_cb_t cb, void *ud) {
    struct ssucc_task *t = calloc(1, sizeof *t);
    t->s = s; t->cb = cb; t->ud = ud; t->o = op_new();
    enqueue(s->c->m, stream_success_task, t);
    return t->o;
}
pa_operation *pa_stream_cork(pa_stream *s, int b, pa_stream_success_cb_t cb, void *ud) {
    advance_clock(s);               /* freeze the position at the moment of corking */
    if (!b && !trace_armed) { trace_armed = 1; trace_t0 = mono_us(); }
    TRACE("cork %d", b);
    if ((b ? 1 : 0) != s->corked) send_ctl(s, b ? 1 : 2);   /* pause / resume the output right away */
    s->corked = b ? 1 : 0;
    rebase(s);                      /* resume counting from here when uncorked */
    if (!s->corked && s->written > s->consumed && !s->started) { s->started = 1; enqueue(s->c->m, started_task, s); }
    LOG("cork %d", s->corked);
    return stream_success_later(s, cb, ud);
}
int pa_stream_is_corked(const pa_stream *s) { return s->corked; }
pa_operation *pa_stream_flush(pa_stream *s, pa_stream_success_cb_t cb, void *ud) {
    advance_clock(s);
    s->consumed = s->written;
    rebase(s);
    send_ctl(s, 3);                 /* drop audio already queued downstream (skip / seek) */
    LOG("flush");
    return stream_success_later(s, cb, ud);
}
pa_operation *pa_stream_update_timing_info(pa_stream *s, pa_stream_success_cb_t cb, void *ud) {
    TRACE("update_timing_info cb=%p", (void *)cb);
    return stream_success_later(s, cb, ud);
}
const pa_timing_info *pa_stream_get_timing_info(pa_stream *s) {
    advance_clock(s);
    uint64_t bps = (uint64_t)s->ss.rate * frame_bytes(&s->ss);
    memset(&s->ti, 0, sizeof s->ti);
    gettimeofday(&s->ti.timestamp, NULL);
    s->ti.synchronized_clocks = 1;
    s->ti.sink_usec = bps ? (pa_usec_t)((s->written - s->consumed) * 1000000ULL / bps) : 0;
    s->ti.transport_usec = 0;
    s->ti.playing = !s->corked && s->started;
    s->ti.write_index = (int64_t)s->written;
    s->ti.read_index = (int64_t)s->consumed;
    s->ti.configured_sink_usec = bps ? (pa_usec_t)(s->target * 1000000ULL / bps) : 0;
    s->ti.since_underrun = (int64_t)s->written;
    TRACE("get_timing_info sink_usec=%llu w=%lld r=%lld playing=%d", (unsigned long long)s->ti.sink_usec,
          (long long)s->ti.write_index, (long long)s->ti.read_index, s->ti.playing);
    return &s->ti;
}
