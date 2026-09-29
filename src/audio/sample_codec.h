#ifndef PORYDAW_SAMPLE_CODEC_H
#define PORYDAW_SAMPLE_CODEC_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    PD_SAMPLE_CODEC_MP3 = 1,
    PD_SAMPLE_CODEC_FLAC = 2,
    PD_SAMPLE_CODEC_OGG = 3,
} PdSampleCodec;

typedef enum {
    PD_SAMPLE_DECODE_OK = 0,
    PD_SAMPLE_DECODE_CORRUPT,
    PD_SAMPLE_DECODE_EMPTY,
    PD_SAMPLE_DECODE_TOO_LONG,
    PD_SAMPLE_DECODE_NO_MEMORY,
} PdSampleDecodeStatus;

typedef struct {
    uint32_t channels, sampleRate, bitsPerSample;
    uint64_t sampleCount;
    float *f32;
    int32_t *s32;
} PdSamplePcm;

PdSampleDecodeStatus pd_sample_decode(PdSampleCodec codec, const uint8_t *bytes, size_t length,
                                       uint64_t maxInterleavedSamples, PdSamplePcm *out);
void pd_sample_pcm_free(PdSamplePcm *pcm);

#ifdef __cplusplus
}
#endif

#endif
