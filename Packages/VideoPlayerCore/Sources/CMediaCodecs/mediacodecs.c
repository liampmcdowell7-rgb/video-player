// Implementation of mediacodecs.h on top of the codec library (dynamic frameworks on device, a locally built shared
// library in the Linux tests; docs/AUDIO_PIPELINE.md). Only the decode, FLAC encode and resample calls are used.
#include "mediacodecs.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#if __has_include(<AetherLibavcodec/avcodec.h>)
#include <AetherLibavcodec/avcodec.h>
#include <AetherLibavutil/channel_layout.h>
#include <AetherLibavutil/opt.h>
#include <AetherLibavutil/mem.h>
#include <AetherLibavutil/avutil.h>
#include <AetherLibswresample/swresample.h>
#else
#include <libavcodec/avcodec.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
#include <libavutil/mem.h>
#include <libavutil/avutil.h>
#include <libswresample/swresample.h>
#endif

static void set_err(char *err, int size, const char *what, int code) {
    if (!err || size <= 0) return;
    if (code < 0) {
        char buf[128];
        av_strerror(code, buf, sizeof buf);
        snprintf(err, (size_t)size, "%s: %s", what, buf);
    } else {
        snprintf(err, (size_t)size, "%s", what);
    }
}

// MARK: Decoder

struct mc_decoder {
    AVCodecContext *ctx;
    AVPacket *pkt;
    AVFrame *frame;
    int32_t *buf;
    size_t buf_count;
    int codec;
};

static enum AVCodecID codec_id(int codec) {
    switch (codec) {
    case MC_CODEC_DTS: return AV_CODEC_ID_DTS;
    case MC_CODEC_TRUEHD: return AV_CODEC_ID_TRUEHD;
    case MC_CODEC_MLP: return AV_CODEC_ID_MLP;
    case MC_CODEC_OPUS: return AV_CODEC_ID_OPUS;
    case MC_CODEC_VORBIS: return AV_CODEC_ID_VORBIS;
    case MC_CODEC_AC3: return AV_CODEC_ID_AC3;
    case MC_CODEC_EAC3: return AV_CODEC_ID_EAC3;
    case MC_CODEC_FLAC: return AV_CODEC_ID_FLAC;
    case MC_CODEC_MP3: return AV_CODEC_ID_MP3;
    case MC_CODEC_MP2: return AV_CODEC_ID_MP2;
    case MC_CODEC_ALAC: return AV_CODEC_ID_ALAC;
    case MC_CODEC_PCM_S16LE: return AV_CODEC_ID_PCM_S16LE;
    case MC_CODEC_PCM_S24LE: return AV_CODEC_ID_PCM_S24LE;
    case MC_CODEC_PCM_S32LE: return AV_CODEC_ID_PCM_S32LE;
    case MC_CODEC_PCM_S16BE: return AV_CODEC_ID_PCM_S16BE;
    case MC_CODEC_PCM_S24BE: return AV_CODEC_ID_PCM_S24BE;
    case MC_CODEC_PCM_S32BE: return AV_CODEC_ID_PCM_S32BE;
    case MC_CODEC_PCM_F32LE: return AV_CODEC_ID_PCM_F32LE;
    case MC_CODEC_PCM_F64LE: return AV_CODEC_ID_PCM_F64LE;
    default: return AV_CODEC_ID_NONE;
    }
}

static int map_profile(int codec, int p) {
    if (codec == MC_CODEC_DTS) {
        switch (p) {
        case AV_PROFILE_DTS: return MC_PROFILE_DTS;
        case AV_PROFILE_DTS_ES: return MC_PROFILE_DTS_ES;
        case AV_PROFILE_DTS_96_24: return MC_PROFILE_DTS_96_24;
        case AV_PROFILE_DTS_HD_HRA: return MC_PROFILE_DTS_HD_HRA;
        case AV_PROFILE_DTS_HD_MA: return MC_PROFILE_DTS_HD_MA;
        case AV_PROFILE_DTS_EXPRESS: return MC_PROFILE_DTS_EXPRESS;
#ifdef AV_PROFILE_DTS_HD_MA_X
        case AV_PROFILE_DTS_HD_MA_X: return MC_PROFILE_DTS_HD_MA_X;
#endif
#ifdef AV_PROFILE_DTS_HD_MA_X_IMAX
        case AV_PROFILE_DTS_HD_MA_X_IMAX: return MC_PROFILE_DTS_HD_MA_X_IMAX;
#endif
        default: return MC_PROFILE_UNKNOWN;
        }
    }
    if (codec == MC_CODEC_TRUEHD && p == AV_PROFILE_TRUEHD_ATMOS) return MC_PROFILE_TRUEHD_ATMOS;
    return MC_PROFILE_UNKNOWN;
}

mc_decoder *mc_decoder_open(int codec, const uint8_t *extradata, int extradata_size, int sample_rate, int channels,
                            int flags, char *err, int err_size) {
    const AVCodec *c = avcodec_find_decoder(codec_id(codec));
    if (!c) { set_err(err, err_size, "no decoder for this codec in the library build", 0); return NULL; }
    mc_decoder *d = calloc(1, sizeof *d);
    if (!d) { set_err(err, err_size, "out of memory", 0); return NULL; }
    d->codec = codec;
    d->ctx = avcodec_alloc_context3(c);
    d->pkt = av_packet_alloc();
    d->frame = av_frame_alloc();
    if (!d->ctx || !d->pkt || !d->frame) { set_err(err, err_size, "out of memory", 0); mc_decoder_close(d); return NULL; }
    d->ctx->pkt_timebase = (AVRational){1, 1000000000};
    if (sample_rate > 0) d->ctx->sample_rate = sample_rate;
    if (channels > 0) av_channel_layout_default(&d->ctx->ch_layout, channels);
    if (flags & MC_FLAG_BITEXACT) d->ctx->flags |= AV_CODEC_FLAG_BITEXACT;
    if (extradata && extradata_size > 0) {
        d->ctx->extradata = av_mallocz((size_t)extradata_size + AV_INPUT_BUFFER_PADDING_SIZE);
        if (!d->ctx->extradata) { set_err(err, err_size, "out of memory", 0); mc_decoder_close(d); return NULL; }
        memcpy(d->ctx->extradata, extradata, (size_t)extradata_size);
        d->ctx->extradata_size = extradata_size;
    }
    AVDictionary *opts = NULL;
    if (codec == MC_CODEC_DTS && (flags & MC_FLAG_CORE_ONLY)) av_dict_set(&opts, "core_only", "1", 0);
    int r = avcodec_open2(d->ctx, c, &opts);
    av_dict_free(&opts);
    if (r < 0) { set_err(err, err_size, "decoder did not open", r); mc_decoder_close(d); return NULL; }
    return d;
}

int mc_decoder_send(mc_decoder *d, const uint8_t *data, int size, int64_t pts_ns) {
    if (!d || !data || size <= 0) return AVERROR(EINVAL);
    av_packet_unref(d->pkt);
    int r = av_new_packet(d->pkt, size);
    if (r < 0) return r;
    memcpy(d->pkt->data, data, (size_t)size);
    d->pkt->pts = pts_ns == INT64_MIN ? AV_NOPTS_VALUE : pts_ns;
    d->pkt->dts = d->pkt->pts;
    r = avcodec_send_packet(d->ctx, d->pkt);
    av_packet_unref(d->pkt);
    return r;
}

int mc_decoder_send_eof(mc_decoder *d) {
    if (!d) return AVERROR(EINVAL);
    int r = avcodec_send_packet(d->ctx, NULL);
    return r == AVERROR_EOF ? 0 : r;
}

static int ensure_buf(mc_decoder *d, size_t count) {
    if (d->buf_count >= count) return 0;
    int32_t *n = realloc(d->buf, count * sizeof(int32_t));
    if (!n) return AVERROR(ENOMEM);
    d->buf = n; d->buf_count = count;
    return 0;
}

static inline int32_t float_to_24(double x) {
    // Round to nearest, clip, no dither (the source is lossy already; see docs/AUDIO_PIPELINE.md).
    double v = x * 8388608.0;
    if (v >= 8388607.0) return 8388607 * 256;
    if (v <= -8388608.0) return -8388608 * 256;
    return (int32_t)lrint(v) * 256;
}

int mc_decoder_receive(mc_decoder *d, mc_frame *out) {
    if (!d || !out) return AVERROR(EINVAL);
    int r = avcodec_receive_frame(d->ctx, d->frame);
    if (r == AVERROR(EAGAIN) || r == AVERROR_EOF) return 0;
    if (r < 0) return r;
    AVFrame *f = d->frame;
    const int ch = f->ch_layout.nb_channels;
    const int n = f->nb_samples;
    if (ch <= 0 || n < 0) { av_frame_unref(f); return AVERROR_INVALIDDATA; }
    if (ensure_buf(d, (size_t)ch * (size_t)(n > 0 ? n : 1)) < 0) { av_frame_unref(f); return AVERROR(ENOMEM); }
    int bits = 32, from_float = 0;
    const enum AVSampleFormat fmt = f->format;
    int32_t *o = d->buf;
    switch (fmt) {
    case AV_SAMPLE_FMT_S16: {
        const int16_t *s = (const int16_t *)f->data[0];
        for (int i = 0; i < n * ch; i++) o[i] = (int32_t)s[i] * 65536;
        bits = 16; break;
    }
    case AV_SAMPLE_FMT_S16P:
        for (int c = 0; c < ch; c++) { const int16_t *s = (const int16_t *)f->extended_data[c]; for (int i = 0; i < n; i++) o[i * ch + c] = (int32_t)s[i] * 65536; }
        bits = 16; break;
    case AV_SAMPLE_FMT_S32:
        memcpy(o, f->data[0], (size_t)n * (size_t)ch * sizeof(int32_t));
        bits = d->ctx->bits_per_raw_sample > 0 && d->ctx->bits_per_raw_sample <= 32 ? d->ctx->bits_per_raw_sample : 32; break;
    case AV_SAMPLE_FMT_S32P:
        for (int c = 0; c < ch; c++) { const int32_t *s = (const int32_t *)f->extended_data[c]; for (int i = 0; i < n; i++) o[i * ch + c] = s[i]; }
        bits = d->ctx->bits_per_raw_sample > 0 && d->ctx->bits_per_raw_sample <= 32 ? d->ctx->bits_per_raw_sample : 32; break;
    case AV_SAMPLE_FMT_FLT: {
        const float *s = (const float *)f->data[0];
        for (int i = 0; i < n * ch; i++) o[i] = float_to_24(s[i]);
        bits = 24; from_float = 1; break;
    }
    case AV_SAMPLE_FMT_FLTP:
        for (int c = 0; c < ch; c++) { const float *s = (const float *)f->extended_data[c]; for (int i = 0; i < n; i++) o[i * ch + c] = float_to_24(s[i]); }
        bits = 24; from_float = 1; break;
    case AV_SAMPLE_FMT_DBL: {
        const double *s = (const double *)f->data[0];
        for (int i = 0; i < n * ch; i++) o[i] = float_to_24(s[i]);
        bits = 24; from_float = 1; break;
    }
    case AV_SAMPLE_FMT_DBLP:
        for (int c = 0; c < ch; c++) { const double *s = (const double *)f->extended_data[c]; for (int i = 0; i < n; i++) o[i * ch + c] = float_to_24(s[i]); }
        bits = 24; from_float = 1; break;
    default:
        av_frame_unref(f);
        return AVERROR_PATCHWELCOME;
    }
    out->samples = o;
    out->nb_samples = n;
    out->channels = ch;
    out->channel_mask = f->ch_layout.order == AV_CHANNEL_ORDER_NATIVE ? f->ch_layout.u.mask : 0;
    out->sample_rate = f->sample_rate > 0 ? f->sample_rate : d->ctx->sample_rate;
    out->bits = bits;
    out->from_float = from_float;
    out->pts_ns = f->pts != AV_NOPTS_VALUE ? f->pts : (f->best_effort_timestamp != AV_NOPTS_VALUE ? f->best_effort_timestamp : INT64_MIN);
    out->profile = map_profile(d->codec, d->ctx->profile);
    av_frame_unref(f);
    return 1;
}

void mc_decoder_reset(mc_decoder *d) {
    if (d && d->ctx) avcodec_flush_buffers(d->ctx);
}

void mc_decoder_info(mc_decoder *d, int *sample_rate, int *channels, int *profile) {
    if (!d || !d->ctx) return;
    if (sample_rate) *sample_rate = d->ctx->sample_rate;
    if (channels) *channels = d->ctx->ch_layout.nb_channels;
    if (profile) *profile = map_profile(d->codec, d->ctx->profile);
}

void mc_decoder_close(mc_decoder *d) {
    if (!d) return;
    avcodec_free_context(&d->ctx);
    av_packet_free(&d->pkt);
    av_frame_free(&d->frame);
    free(d->buf);
    free(d);
}

// MARK: FLAC encoder

struct mc_flac_encoder {
    AVCodecContext *ctx;
    AVFrame *frame;
    AVPacket *pkt;
    int bits;
    int channels;
};

static void flac_layout(AVChannelLayout *l, int channels) {
    // The layouts the FLAC encoder accepts, in FLAC channel order (the caller already ordered the samples).
    switch (channels) {
    case 1: *l = (AVChannelLayout)AV_CHANNEL_LAYOUT_MONO; break;
    case 2: *l = (AVChannelLayout)AV_CHANNEL_LAYOUT_STEREO; break;
    case 3: *l = (AVChannelLayout)AV_CHANNEL_LAYOUT_SURROUND; break;
    case 4: *l = (AVChannelLayout)AV_CHANNEL_LAYOUT_QUAD; break;
    case 5: *l = (AVChannelLayout)AV_CHANNEL_LAYOUT_5POINT0_BACK; break;
    case 6: *l = (AVChannelLayout)AV_CHANNEL_LAYOUT_5POINT1_BACK; break;
    case 7: *l = (AVChannelLayout)AV_CHANNEL_LAYOUT_6POINT1; break;
    default: *l = (AVChannelLayout)AV_CHANNEL_LAYOUT_7POINT1; break;
    }
}

mc_flac_encoder *mc_flac_open(int sample_rate, int channels, int bits, int block_size, int compression,
                              uint8_t streaminfo[34], char *err, int err_size) {
    if (channels < 1 || channels > 8 || (bits != 16 && bits != 24) || block_size < 16 || block_size > 65535) {
        set_err(err, err_size, "unsupported FLAC parameters", 0); return NULL;
    }
    const AVCodec *c = avcodec_find_encoder(AV_CODEC_ID_FLAC);
    if (!c) { set_err(err, err_size, "no FLAC encoder in the library build", 0); return NULL; }
    mc_flac_encoder *e = calloc(1, sizeof *e);
    if (!e) { set_err(err, err_size, "out of memory", 0); return NULL; }
    e->bits = bits; e->channels = channels;
    e->ctx = avcodec_alloc_context3(c);
    e->frame = av_frame_alloc();
    e->pkt = av_packet_alloc();
    if (!e->ctx || !e->frame || !e->pkt) { set_err(err, err_size, "out of memory", 0); mc_flac_close(e); return NULL; }
    e->ctx->sample_rate = sample_rate;
    flac_layout(&e->ctx->ch_layout, channels);
    e->ctx->sample_fmt = bits == 16 ? AV_SAMPLE_FMT_S16 : AV_SAMPLE_FMT_S32;
    e->ctx->bits_per_raw_sample = bits;
    e->ctx->frame_size = block_size;
    e->ctx->compression_level = compression;
    e->ctx->time_base = (AVRational){1, sample_rate};
    // 24-bit input with a 32-bit sample format and rates above 48 kHz with large blocks are both valid FLAC; the
    // encoder asks for "experimental" compliance only outside the FLAC subset, which these settings stay inside.
    int r = avcodec_open2(e->ctx, c, NULL);
    if (r < 0) { set_err(err, err_size, "FLAC encoder did not open", r); mc_flac_close(e); return NULL; }
    if (!e->ctx->extradata || e->ctx->extradata_size < 34) { set_err(err, err_size, "FLAC encoder gave no STREAMINFO", 0); mc_flac_close(e); return NULL; }
    memcpy(streaminfo, e->ctx->extradata, 34);
    return e;
}

int mc_flac_encode(mc_flac_encoder *e, const int32_t *interleaved, int nb_samples, const uint8_t **packet) {
    if (!e || !interleaved || nb_samples <= 0 || !packet) return AVERROR(EINVAL);
    av_packet_unref(e->pkt);
    av_frame_unref(e->frame);
    e->frame->nb_samples = nb_samples;
    e->frame->format = e->ctx->sample_fmt;
    e->frame->sample_rate = e->ctx->sample_rate;
    int r = av_channel_layout_copy(&e->frame->ch_layout, &e->ctx->ch_layout);
    if (r < 0) return r;
    r = av_frame_get_buffer(e->frame, 0);
    if (r < 0) return r;
    const int count = nb_samples * e->channels;
    if (e->bits == 16) {
        int16_t *o = (int16_t *)e->frame->data[0];
        for (int i = 0; i < count; i++) o[i] = (int16_t)(interleaved[i] >> 16);
    } else {
        int32_t *o = (int32_t *)e->frame->data[0];
        // The encoder reads the top 24 bits; clear the low byte so nothing below the declared depth is carried.
        for (int i = 0; i < count; i++) o[i] = interleaved[i] & ~0xFF;
    }
    r = avcodec_send_frame(e->ctx, e->frame);
    if (r < 0) return r;
    r = avcodec_receive_packet(e->ctx, e->pkt);
    if (r == AVERROR(EAGAIN)) { *packet = NULL; return 0; }
    if (r < 0) return r;
    *packet = e->pkt->data;
    return e->pkt->size;
}

void mc_flac_close(mc_flac_encoder *e) {
    if (!e) return;
    avcodec_free_context(&e->ctx);
    av_frame_free(&e->frame);
    av_packet_free(&e->pkt);
    free(e);
}

// MARK: Resampler

struct mc_resampler { SwrContext *swr; int channels; };

mc_resampler *mc_resampler_open(int in_rate, int out_rate, int channels, char *err, int err_size) {
    mc_resampler *r = calloc(1, sizeof *r);
    if (!r) { set_err(err, err_size, "out of memory", 0); return NULL; }
    r->channels = channels;
    AVChannelLayout layout;
    av_channel_layout_default(&layout, channels);
    int e = swr_alloc_set_opts2(&r->swr, &layout, AV_SAMPLE_FMT_S32, out_rate, &layout, AV_SAMPLE_FMT_S32, in_rate, 0, NULL);
    av_channel_layout_uninit(&layout);
    if (e < 0 || !r->swr) { set_err(err, err_size, "resampler did not open", e); free(r); return NULL; }
    // Longer filter than the default for a cleaner pass band; no dither (docs/AUDIO_PIPELINE.md).
    av_opt_set_int(r->swr, "filter_size", 64, 0);
    av_opt_set_int(r->swr, "phase_shift", 10, 0);
    av_opt_set_double(r->swr, "cutoff", 0.97, 0);
    av_opt_set_int(r->swr, "dither_method", 0, 0);
    e = swr_init(r->swr);
    if (e < 0) { set_err(err, err_size, "resampler did not start", e); swr_free(&r->swr); free(r); return NULL; }
    return r;
}

int mc_resample(mc_resampler *r, const int32_t *in, int nb_in, int32_t *out, int out_capacity) {
    if (!r) return AVERROR(EINVAL);
    const uint8_t *ip[1] = { (const uint8_t *)in };
    uint8_t *op[1] = { (uint8_t *)out };
    return swr_convert(r->swr, op, out_capacity, in ? ip : NULL, in ? nb_in : 0);
}

void mc_resampler_close(mc_resampler *r) {
    if (!r) return;
    swr_free(&r->swr);
    free(r);
}

const char *mc_library_version(void) { return av_version_info(); }
