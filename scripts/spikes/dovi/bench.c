// Spike: cost of Dolby Vision Profile 7 -> 8.1 RPU conversion with libdovi, plus the surrounding
// per-sample work (find the RPU NAL, drop the enhancement layer, copy the sample).
// Build and run: scripts/spikes/dovi/run.sh   Result: docs/spikes/DOLBY_VISION_P7.md
// Uses only libdovi's public C API (dolby_vision crate built with the `capi` feature).
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>

typedef struct RpuOpaque RpuOpaque;
typedef struct { const uint8_t *data; size_t len; } Data;
typedef struct { uint8_t guessed_profile; const char *el_type; } HeaderPrefix; // first two fields of RpuDataHeader
extern RpuOpaque *dovi_parse_unspec62_nalu(const uint8_t *buf, size_t len);
extern void dovi_rpu_free(RpuOpaque *ptr);
extern const char *dovi_rpu_get_error(const RpuOpaque *ptr);
extern const Data *dovi_write_unspec62_nalu(RpuOpaque *ptr);
extern void dovi_data_free(const Data *data);
extern int32_t dovi_convert_rpu_with_mode(RpuOpaque *ptr, uint8_t mode);
extern const HeaderPrefix *dovi_rpu_get_header(const RpuOpaque *ptr);
extern void dovi_rpu_free_header(const HeaderPrefix *ptr);

static double now_ns(clockid_t c) { struct timespec t; clock_gettime(c, &t); return t.tv_sec * 1e9 + t.tv_nsec; }
static int cmpd(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return (x > y) - (x < y); }
static long maxrss_kb(void) { struct rusage u; getrusage(RUSAGE_SELF, &u); return u.ru_maxrss; }

typedef struct { double mean, p50, p99, max; } Stats;
static Stats stats(double *v, size_t n) {
    qsort(v, n, sizeof(double), cmpd);
    double s = 0; for (size_t i = 0; i < n; i++) s += v[i];
    Stats r = { s / n, v[n / 2], v[(size_t)(n * 0.99)], v[n - 1] };
    return r;
}

// ---- RPU records
static uint8_t **rpu; static uint32_t *rpu_len; static size_t rpu_n;
static void load_rpus(const char *path) {
    FILE *f = fopen(path, "rb"); if (!f) { perror(path); exit(1); }
    size_t cap = 4096; rpu = malloc(cap * sizeof *rpu); rpu_len = malloc(cap * sizeof *rpu_len);
    uint32_t len;
    while (fread(&len, 4, 1, f) == 1) {
        if (rpu_n == cap) { cap *= 2; rpu = realloc(rpu, cap * sizeof *rpu); rpu_len = realloc(rpu_len, cap * sizeof *rpu_len); }
        rpu[rpu_n] = malloc(len); rpu_len[rpu_n] = len;
        if (fread(rpu[rpu_n], 1, len, f) != len) { fprintf(stderr, "short read\n"); exit(1); }
        rpu_n++;
    }
    fclose(f);
}

// Convert one RPU NAL (with its 0x7C01 header); returns converted length, writes into out. Returns 0 on error.
static size_t convert_one(const uint8_t *in, size_t n, uint8_t *out, size_t cap, uint8_t mode) {
    RpuOpaque *r = dovi_parse_unspec62_nalu(in, n);
    if (!r) return 0;
    if (dovi_rpu_get_error(r)) { dovi_rpu_free(r); return 0; }
    if (dovi_convert_rpu_with_mode(r, mode) != 0) { dovi_rpu_free(r); return 0; }
    const Data *d = dovi_write_unspec62_nalu(r);
    size_t len = 0;
    if (d && d->len <= cap) { memcpy(out, d->data, d->len); len = d->len; }
    if (d) dovi_data_free(d);
    dovi_rpu_free(r);
    return len;
}

// ---- Benchmark 1: libdovi only
static void bench_rpu(int reps, int fps) {
    uint8_t out[8192];
    // correctness: converted RPU must parse as profile 8, no EL
    {
        RpuOpaque *r = dovi_parse_unspec62_nalu(rpu[0], rpu_len[0]);
        const HeaderPrefix *h = dovi_rpu_get_header(r);
        printf("input  RPU[0]: %u bytes, guessed_profile=%u, el_type=%s\n", rpu_len[0], h->guessed_profile, h->el_type ? h->el_type : "(none)");
        dovi_rpu_free_header(h); dovi_rpu_free(r);
        size_t n = convert_one(rpu[0], rpu_len[0], out, sizeof out, 2);
        r = dovi_parse_unspec62_nalu(out, n);
        h = dovi_rpu_get_header(r);
        printf("output RPU[0]: %zu bytes, guessed_profile=%u, el_type=%s (mode 2 = P8.1)\n", n, h->guessed_profile, h->el_type ? h->el_type : "(none)");
        if (h->guessed_profile != 8) { fprintf(stderr, "FAIL: conversion did not give profile 8\n"); exit(2); }
        dovi_rpu_free_header(h); dovi_rpu_free(r);
    }
    size_t total = (size_t)reps * rpu_n;
    double *tp = malloc(total * sizeof(double)), *tc = malloc(total * sizeof(double)), *tw = malloc(total * sizeof(double)), *tt = malloc(total * sizeof(double));
    for (size_t i = 0; i < rpu_n; i++) convert_one(rpu[i], rpu_len[i], out, sizeof out, 2); // warm-up
    long rss0 = maxrss_kb();
    double cpu0 = now_ns(CLOCK_THREAD_CPUTIME_ID), wall0 = now_ns(CLOCK_MONOTONIC);
    size_t k = 0, bytes_in = 0, bytes_out = 0;
    for (int r = 0; r < reps; r++) for (size_t i = 0; i < rpu_n; i++, k++) {
        double a = now_ns(CLOCK_MONOTONIC);
        RpuOpaque *o = dovi_parse_unspec62_nalu(rpu[i], rpu_len[i]);
        double b = now_ns(CLOCK_MONOTONIC);
        int rc = dovi_convert_rpu_with_mode(o, 2);
        double c = now_ns(CLOCK_MONOTONIC);
        const Data *d = dovi_write_unspec62_nalu(o);
        double e = now_ns(CLOCK_MONOTONIC);
        if (rc != 0 || !d) { fprintf(stderr, "FAIL at %zu\n", k); exit(2); }
        bytes_in += rpu_len[i]; bytes_out += d->len;
        dovi_data_free(d); dovi_rpu_free(o);
        tp[k] = b - a; tc[k] = c - b; tw[k] = e - c; tt[k] = e - a;
    }
    double cpu1 = now_ns(CLOCK_THREAD_CPUTIME_ID), wall1 = now_ns(CLOCK_MONOTONIC);
    Stats sp = stats(tp, total), sc = stats(tc, total), sw = stats(tw, total), st = stats(tt, total);
    printf("\n[libdovi] %zu RPU conversions (%zu distinct RPUs x %d passes), mean in %.0f B, out %.0f B\n", total, rpu_n, reps, (double)bytes_in / total, (double)bytes_out / total);
    printf("%-22s %10s %10s %10s %10s\n", "stage (microseconds)", "mean", "p50", "p99", "max");
    printf("%-22s %10.2f %10.2f %10.2f %10.2f\n", "parse", sp.mean / 1e3, sp.p50 / 1e3, sp.p99 / 1e3, sp.max / 1e3);
    printf("%-22s %10.2f %10.2f %10.2f %10.2f\n", "convert (mode 2)", sc.mean / 1e3, sc.p50 / 1e3, sc.p99 / 1e3, sc.max / 1e3);
    printf("%-22s %10.2f %10.2f %10.2f %10.2f\n", "write (+emulation prev)", sw.mean / 1e3, sw.p50 / 1e3, sw.p99 / 1e3, sw.max / 1e3);
    printf("%-22s %10.2f %10.2f %10.2f %10.2f\n", "parse+convert+write", st.mean / 1e3, st.p50 / 1e3, st.p99 / 1e3, st.max / 1e3);
    double cpu_per = (cpu1 - cpu0) / total, wall_per = (wall1 - wall0) / total;
    printf("thread CPU per RPU %.2f us (wall %.2f us incl. timer overhead)\n", cpu_per / 1e3, wall_per / 1e3);
    printf("CPU time per second of video: %.3f ms at 24 fps, %.3f ms at 60 fps (%.4f%% / %.4f%% of one core)\n",
           cpu_per * 24 / 1e6, cpu_per * 60 / 1e6, cpu_per * 24 / 1e9 * 100, cpu_per * 60 / 1e9 * 100);
    printf("peak RSS growth during run: %ld kB\n", maxrss_kb() - rss0);
    free(tp); free(tc); free(tw); free(tt);
}

// ---- Benchmark 2: the surrounding sample work on a synthetic 4K ~100 Mbps stream
static uint64_t rng = 88172645463325252ULL;
static uint32_t rnd(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return (uint32_t)(rng >> 16); }

typedef struct { uint8_t *lp; size_t lp_len; uint8_t *ab; size_t ab_len; } AU; // length-prefixed and Annex-B copy of the same access unit
static AU *aus; static size_t au_n; static double total_bytes;

static void put_nal(uint8_t **lp, uint8_t **ab, int type, const uint8_t *payload, size_t plen, int layer_marker) {
    // 2-byte HEVC NAL header: forbidden(1) type(6) layer_id(6) tid_plus1(3)
    uint8_t h0 = (uint8_t)(type << 1), h1 = (uint8_t)(layer_marker ? 1 : 1);
    uint32_t n = (uint32_t)(plen + 2);
    (*lp)[0] = n >> 24; (*lp)[1] = n >> 16; (*lp)[2] = n >> 8; (*lp)[3] = n; (*lp)[4] = h0; (*lp)[5] = h1; memcpy(*lp + 6, payload, plen); *lp += 6 + plen;
    (*ab)[0] = 0; (*ab)[1] = 0; (*ab)[2] = 0; (*ab)[3] = 1; (*ab)[4] = h0; (*ab)[5] = h1; memcpy(*ab + 6, payload, plen); *ab += 6 + plen;
}
static void build_stream(size_t frames, double mbps_bl, double mbps_el, int fps) {
    aus = calloc(frames, sizeof(AU)); au_n = frames;
    double bl_bytes = mbps_bl * 1e6 / 8 / fps, el_bytes = mbps_el * 1e6 / 8 / fps;
    for (size_t f = 0; f < frames; f++) {
        size_t bl = (size_t)(bl_bytes * (0.5 + (rnd() % 1000) / 1000.0)); // 0.5x .. 1.5x
        size_t el = (size_t)(el_bytes * (0.5 + (rnd() % 1000) / 1000.0));
        size_t cap = bl + el + 2 * 4096 + 64;
        uint8_t *lp = malloc(cap), *ab = malloc(cap), *lp0 = lp, *ab0 = ab;
        uint8_t *payload = malloc(bl > el ? bl : el);
        for (size_t i = 0; i < (bl > el ? bl : el); i++) payload[i] = (uint8_t)(1 + rnd() % 255); // never 0x00: no accidental start codes
        int slices = 4; size_t each = bl / slices;
        for (int s = 0; s < slices; s++) put_nal(&lp, &ab, (f % 24 == 0) ? 19 : 1, payload, each, 0);   // base-layer slices
        put_nal(&lp, &ab, 63, payload, el, 1);                                                          // enhancement layer (UNSPEC63)
        // RPU NAL (UNSPEC62): rpu[] records already contain the 0x7C01 header: copy as-is after our own length/start code
        const uint8_t *r = rpu[f % rpu_n]; uint32_t rl = rpu_len[f % rpu_n];
        lp[0] = rl >> 24; lp[1] = rl >> 16; lp[2] = rl >> 8; lp[3] = rl; memcpy(lp + 4, r, rl); lp += 4 + rl;
        ab[0] = 0; ab[1] = 0; ab[2] = 0; ab[3] = 1; memcpy(ab + 4, r, rl); ab += 4 + rl;
        aus[f].lp = lp0; aus[f].lp_len = lp - lp0; aus[f].ab = ab0; aus[f].ab_len = ab - ab0;
        total_bytes += aus[f].lp_len; free(payload);
    }
}

static inline int nal_type(const uint8_t *p) { return (p[0] >> 1) & 0x3f; }

// (a) length-prefixed: walk NAL lengths only (find types), no copy
static size_t walk_lp(const AU *a) { size_t o = 0, c = 0; while (o + 4 <= a->lp_len) { uint32_t n = (uint32_t)a->lp[o] << 24 | a->lp[o + 1] << 16 | a->lp[o + 2] << 8 | a->lp[o + 3]; c += nal_type(a->lp + o + 4) == 62; o += 4 + n; } return c; }
// (b) length-prefixed: drop EL (type 63), copy the rest; RPU passed through unchanged
static size_t filter_lp(const AU *a, uint8_t *out, int convert) {
    size_t o = 0, w = 0; uint8_t tmp[8192];
    while (o + 4 <= a->lp_len) {
        uint32_t n = (uint32_t)a->lp[o] << 24 | a->lp[o + 1] << 16 | a->lp[o + 2] << 8 | a->lp[o + 3];
        int t = nal_type(a->lp + o + 4);
        if (t == 63) { o += 4 + n; continue; }
        if (t == 62 && convert) {
            size_t m = convert_one(a->lp + o + 4, n, tmp, sizeof tmp, 2);
            out[w] = m >> 24; out[w + 1] = m >> 16; out[w + 2] = m >> 8; out[w + 3] = m; memcpy(out + w + 4, tmp, m); w += 4 + m;
        } else { memcpy(out + w, a->lp + o, 4 + n); w += 4 + n; }
        o += 4 + n;
    }
    return w;
}
// (c) Annex-B: find start codes with a byte scan (memchr for 0x01 then check the two bytes before), drop EL, optional convert
static size_t filter_ab(const AU *a, uint8_t *out, int convert) {
    const uint8_t *p = a->ab, *end = a->ab + a->ab_len;
    // collect NAL boundaries
    const uint8_t *starts[16]; size_t ns = 0;
    const uint8_t *q = p;
    while (q < end) {
        const uint8_t *z = memchr(q, 1, end - q);
        if (!z) break;
        if (z - p >= 2 && z[-1] == 0 && z[-2] == 0) { if (ns < 16) starts[ns++] = z + 1; }
        q = z + 1;
    }
    size_t w = 0; uint8_t tmp[8192];
    for (size_t i = 0; i < ns; i++) {
        const uint8_t *s = starts[i]; const uint8_t *e = (i + 1 < ns) ? starts[i + 1] - 4 : end; // next start code is 00 00 00 01
        size_t n = e - s; int t = nal_type(s);
        if (t == 63) continue;
        out[w] = 0; out[w + 1] = 0; out[w + 2] = 0; out[w + 3] = 1; w += 4;
        if (t == 62 && convert) { size_t m = convert_one(s, n, tmp, sizeof tmp, 2); memcpy(out + w, tmp, m); w += m; }
        else { memcpy(out + w, s, n); w += n; }
    }
    return w;
}

typedef size_t (*Fn)(const AU *, uint8_t *, int);
static void run_variant(const char *name, int which, int convert, int passes, int fps, uint8_t *out) {
    size_t total = (size_t)passes * au_n; double *t = malloc(total * sizeof(double)); size_t k = 0; volatile size_t sink = 0;
    for (size_t i = 0; i < au_n; i++) { sink += which == 0 ? walk_lp(&aus[i]) : which == 1 ? filter_lp(&aus[i], out, convert) : filter_ab(&aus[i], out, convert); } // warm-up
    double c0 = now_ns(CLOCK_THREAD_CPUTIME_ID);
    for (int p = 0; p < passes; p++) for (size_t i = 0; i < au_n; i++, k++) {
        double a = now_ns(CLOCK_MONOTONIC);
        sink += which == 0 ? walk_lp(&aus[i]) : which == 1 ? filter_lp(&aus[i], out, convert) : filter_ab(&aus[i], out, convert);
        t[k] = now_ns(CLOCK_MONOTONIC) - a;
    }
    double c1 = now_ns(CLOCK_THREAD_CPUTIME_ID); (void)sink;
    Stats s = stats(t, total); double cpu_per = (c1 - c0) / total;
    printf("%-52s mean %8.1f us  p99 %8.1f us  max %8.1f us | CPU/video-second @%dfps: %7.2f ms\n", name, s.mean / 1e3, s.p99 / 1e3, s.max / 1e3, fps, cpu_per * fps / 1e6);
    free(t);
}

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "p7_rpus.bin"; int reps = argc > 2 ? atoi(argv[2]) : 100;
    load_rpus(path);
    printf("loaded %zu P7 RPUs from %s\n", rpu_n, path);
    bench_rpu(reps, 24);

    int fps = 24; size_t frames = 240; // 10 s
    long rss0 = maxrss_kb();
    build_stream(frames, 80.0, 20.0, fps);
    printf("\n[stream] synthetic P7 4K stream: %zu access units, %.1f MB, %.1f Mbps average at %d fps (base layer ~80 Mbps + enhancement layer ~20 Mbps + RPU)\n",
           frames, total_bytes / 1e6, total_bytes * 8 / (frames / (double)fps) / 1e6, fps);
    uint8_t *out = malloc(4 << 20);
    run_variant("A  length-prefixed: walk NAL lengths only", 0, 0, 40, fps, out);
    run_variant("B  length-prefixed: drop EL + copy, RPU untouched", 1, 0, 40, fps, out);
    run_variant("C  length-prefixed: drop EL + copy + libdovi convert", 1, 1, 40, fps, out);
    run_variant("D  Annex-B: memchr scan, drop EL + copy, RPU untouched", 2, 0, 40, fps, out);
    run_variant("E  Annex-B: memchr scan, drop EL + copy + convert", 2, 1, 40, fps, out);
    printf("peak RSS growth while holding the stream (both layouts): %ld kB\n", maxrss_kb() - rss0);
    // same at 60 fps budget note
    printf("\nframe budgets: 24 fps = 41.67 ms, 30 fps = 33.3 ms, 60 fps = 16.67 ms per frame\n");
    return 0;
}
