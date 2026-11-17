// Small C interface over the codec library (docs/AUDIO_PIPELINE.md names it and its licence). Swift never sees the
// library's own types: everything goes through the opaque handles and plain structs below.
//
// Samples crossing this interface are always interleaved int32, MSB-aligned ("left-justified"): a 24-bit sample s is
// stored as s << 8, a 16-bit sample as s << 16. `bits` says how many of the top bits carry the sample.
#ifndef MEDIACODECS_H
#define MEDIACODECS_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Source codecs the decoder can open.
typedef enum {
    MC_CODEC_DTS = 1,
    MC_CODEC_TRUEHD = 2,
    MC_CODEC_MLP = 3,
    MC_CODEC_OPUS = 4,
    MC_CODEC_VORBIS = 5,
    MC_CODEC_AC3 = 6,
    MC_CODEC_EAC3 = 7,
    MC_CODEC_FLAC = 8,
    MC_CODEC_MP3 = 9,
    MC_CODEC_MP2 = 10,
    MC_CODEC_ALAC = 11,
    MC_CODEC_PCM_S16LE = 12,
    MC_CODEC_PCM_S24LE = 13,
    MC_CODEC_PCM_S32LE = 14,
    MC_CODEC_PCM_S16BE = 15,
    MC_CODEC_PCM_S24BE = 16,
    MC_CODEC_PCM_S32BE = 17,
    MC_CODEC_PCM_F32LE = 18,
    MC_CODEC_PCM_F64LE = 19
} mc_codec;

/// Decoder flags.
enum {
    /// Integer (fixed-point) decoding where the codec offers it (DTS core): deterministic output.
    MC_FLAG_BITEXACT = 1,
    /// DTS: decode the core only (ignore extension substreams).
    MC_FLAG_CORE_ONLY = 2
};

/// Profiles the decoder reports (after the first decoded frame).
enum {
    MC_PROFILE_UNKNOWN = -1,
    MC_PROFILE_DTS = 1,
    MC_PROFILE_DTS_ES = 2,
    MC_PROFILE_DTS_96_24 = 3,
    MC_PROFILE_DTS_HD_HRA = 4,
    MC_PROFILE_DTS_HD_MA = 5,
    MC_PROFILE_DTS_EXPRESS = 6,
    MC_PROFILE_DTS_HD_MA_X = 7,
    MC_PROFILE_DTS_HD_MA_X_IMAX = 8,
    MC_PROFILE_TRUEHD_ATMOS = 20
};

/// Channel bits (same meaning as the library's native channel mask bits).
enum {
    MC_CH_FL = 1 << 0, MC_CH_FR = 1 << 1, MC_CH_FC = 1 << 2, MC_CH_LFE = 1 << 3,
    MC_CH_BL = 1 << 4, MC_CH_BR = 1 << 5, MC_CH_FLC = 1 << 6, MC_CH_FRC = 1 << 7,
    MC_CH_BC = 1 << 8, MC_CH_SL = 1 << 9, MC_CH_SR = 1 << 10
};

typedef struct mc_decoder mc_decoder;
typedef struct mc_flac_encoder mc_flac_encoder;
typedef struct mc_resampler mc_resampler;

/// One block of decoded audio. Valid until the next call on the same decoder.
typedef struct {
    const int32_t *samples;     // interleaved, nb_samples * channels values, MSB-aligned
    int nb_samples;
    int channels;
    uint64_t channel_mask;      // 0 when the library reports no native order for this layout
    int sample_rate;
    int bits;                   // 16, 24 or 32 (32: a full-range integer source); 24 for a decoder that outputs floats
    int from_float;             // 1 when the decoder produced floating point (lossy codecs), converted here without dither
    int64_t pts_ns;             // INT64_MIN when unknown
    int profile;                // MC_PROFILE_*
} mc_frame;

/// Opens a decoder. `extradata` may be NULL. Returns NULL on failure and writes a short reason to `err`.
mc_decoder *mc_decoder_open(int codec, const uint8_t *extradata, int extradata_size, int sample_rate, int channels,
                            int flags, char *err, int err_size);
/// Sends one compressed frame. Returns 0, or a negative library error code (damaged data: the caller conceals and goes on).
int mc_decoder_send(mc_decoder *d, const uint8_t *data, int size, int64_t pts_ns);
/// Ends the stream: the next receives return the frames still held by the decoder.
int mc_decoder_send_eof(mc_decoder *d);
/// 1: a frame was written to `out`. 0: the decoder needs more input (or is drained). < 0: a decode error.
int mc_decoder_receive(mc_decoder *d, mc_frame *out);
/// Drops all decoder state (used before decoding from a new position).
void mc_decoder_reset(mc_decoder *d);
/// What the decoder knows before the first frame (filled from the stream header): 0 when unknown.
void mc_decoder_info(mc_decoder *d, int *sample_rate, int *channels, int *profile);
void mc_decoder_close(mc_decoder *d);

/// FLAC encoder with a fixed block size. `bits` is 16 or 24. `compression` 0...12 (5 is the library default).
/// `streaminfo` receives the 34-byte STREAMINFO block (total samples and MD5 left zero).
mc_flac_encoder *mc_flac_open(int sample_rate, int channels, int bits, int block_size, int compression,
                              uint8_t streaminfo[34], char *err, int err_size);
/// Encodes one block (nb_samples == block size, except the very last block of a stream, which may be shorter).
/// On success returns the packet size and sets *packet (valid until the next call). < 0 on error.
int mc_flac_encode(mc_flac_encoder *e, const int32_t *interleaved, int nb_samples, const uint8_t **packet);
void mc_flac_close(mc_flac_encoder *e);

/// Sample-rate converter for interleaved MSB-aligned int32 audio (no dither).
mc_resampler *mc_resampler_open(int in_rate, int out_rate, int channels, char *err, int err_size);
/// Converts `nb_in` input samples (per channel). Returns the number of output samples written (<= out_capacity).
int mc_resample(mc_resampler *r, const int32_t *in, int nb_in, int32_t *out, int out_capacity);
void mc_resampler_close(mc_resampler *r);

/// The library's version string (shown in diagnostics only).
const char *mc_library_version(void);

#ifdef __cplusplus
}
#endif
#endif
