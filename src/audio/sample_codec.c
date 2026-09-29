#include "sample_codec.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define DR_MP3_IMPLEMENTATION
#define DR_MP3_NO_STDIO
#include "dr_mp3.h"

#define DR_FLAC_IMPLEMENTATION
#define DR_FLAC_NO_STDIO
#include "dr_flac.h"

#define STB_VORBIS_NO_STDIO
#include "stb_vorbis.c"

enum { kChunkFrames = 4096 };

void pd_sample_pcm_free(PdSamplePcm *pcm)
{
    if (!pcm) return;
    free(pcm->f32);
    free(pcm->s32);
    memset(pcm, 0, sizeof(*pcm));
}

/* Reserve ahead of each read, without reallocating on every decoded chunk. */
static PdSampleDecodeStatus reserve_float(float **samples, size_t *capacity, size_t used,
                                          size_t chunk)
{
    if (chunk > SIZE_MAX / sizeof(float) - used) return PD_SAMPLE_DECODE_TOO_LONG;
    const size_t needed = used + chunk;
    if (needed <= *capacity) return PD_SAMPLE_DECODE_OK;
    size_t next = *capacity;
    if (next < chunk) next = chunk;
    while (next < needed) {
        if (next > SIZE_MAX / sizeof(float) / 2) {
            next = needed;
            break;
        }
        next *= 2;
    }
    float *grown = realloc(*samples, next * sizeof(float));
    if (!grown) return PD_SAMPLE_DECODE_NO_MEMORY;
    *samples = grown;
    *capacity = next;
    return PD_SAMPLE_DECODE_OK;
}

static PdSampleDecodeStatus decode_mp3(const uint8_t *bytes, size_t length,
                                        uint64_t maxSamples, PdSamplePcm *out)
{
    drmp3 mp3;
    if (!drmp3_init_memory(&mp3, bytes, length, NULL)) return PD_SAMPLE_DECODE_CORRUPT;
    const uint32_t channels = mp3.channels;
    const uint32_t rate = mp3.sampleRate;
    float *samples = NULL;
    size_t count = 0, capacity = 0;
    PdSampleDecodeStatus status = PD_SAMPLE_DECODE_OK;
    if (!channels) {
        status = PD_SAMPLE_DECODE_CORRUPT;
        goto done;
    }
    const size_t chunk = kChunkFrames * (size_t)channels;
    for (;;) {
        status = reserve_float(&samples, &capacity, count, chunk);
        if (status != PD_SAMPLE_DECODE_OK) goto done;
        const drmp3_uint64 frames = drmp3_read_pcm_frames_f32(&mp3, kChunkFrames, samples + count);
        if (!frames) break;
        count += (size_t)frames * channels;
        if (count > maxSamples) {
            status = PD_SAMPLE_DECODE_TOO_LONG;
            goto done;
        }
    }
    if (!count) {
        status = PD_SAMPLE_DECODE_EMPTY;
        goto done;
    }
    out->channels = channels;
    out->sampleRate = rate;
    out->sampleCount = count;
    out->f32 = samples;
done:
    drmp3_uninit(&mp3);
    if (status != PD_SAMPLE_DECODE_OK) free(samples);
    return status;
}

static PdSampleDecodeStatus decode_flac(const uint8_t *bytes, size_t length,
                                         uint64_t maxSamples, PdSamplePcm *out)
{
    drflac *flac = drflac_open_memory(bytes, length, NULL);
    if (!flac) return PD_SAMPLE_DECODE_CORRUPT;
    PdSampleDecodeStatus status = PD_SAMPLE_DECODE_OK;
    const uint32_t channels = flac->channels;
    const uint64_t frames = flac->totalPCMFrameCount;
    if (!channels || !frames) {
        status = PD_SAMPLE_DECODE_EMPTY;
    } else if (frames > maxSamples / channels || frames > SIZE_MAX / sizeof(int32_t) / channels) {
        status = PD_SAMPLE_DECODE_TOO_LONG;
    } else {
        const size_t count = (size_t)frames * channels;
        int32_t *samples = malloc(count * sizeof(int32_t));
        if (!samples) {
            status = PD_SAMPLE_DECODE_NO_MEMORY;
        } else if (drflac_read_pcm_frames_s32(flac, frames, samples) < frames) {
            free(samples);
            status = PD_SAMPLE_DECODE_CORRUPT;
        } else {
            out->channels = channels;
            out->sampleRate = flac->sampleRate;
            out->bitsPerSample = flac->bitsPerSample;
            out->sampleCount = count;
            out->s32 = samples;
        }
    }
    drflac_close(flac);
    return status;
}

static PdSampleDecodeStatus decode_ogg(const uint8_t *bytes, size_t length,
                                        uint64_t maxSamples, PdSamplePcm *out)
{
    if (length > INT_MAX) return PD_SAMPLE_DECODE_TOO_LONG;
    int error = 0;
    stb_vorbis *vorbis = stb_vorbis_open_memory(bytes, (int)length, &error, NULL);
    if (!vorbis) return PD_SAMPLE_DECODE_CORRUPT;
    const stb_vorbis_info info = stb_vorbis_get_info(vorbis);
    const int channels = info.channels;
    float *samples = NULL;
    size_t count = 0, capacity = 0;
    PdSampleDecodeStatus status = PD_SAMPLE_DECODE_OK;
    if (channels < 1 || channels > INT_MAX / kChunkFrames) {
        status = PD_SAMPLE_DECODE_CORRUPT;
        goto done;
    }
    const size_t chunk = kChunkFrames * (size_t)channels;
    for (;;) {
        status = reserve_float(&samples, &capacity, count, chunk);
        if (status != PD_SAMPLE_DECODE_OK) goto done;
        const int frames = stb_vorbis_get_samples_float_interleaved(
            vorbis, channels, samples + count, (int)chunk);
        if (frames <= 0) break;
        count += (size_t)frames * channels;
        if (count > maxSamples) {
            status = PD_SAMPLE_DECODE_TOO_LONG;
            goto done;
        }
    }
    if (!count) {
        status = PD_SAMPLE_DECODE_EMPTY;
        goto done;
    }
    out->channels = (uint32_t)channels;
    out->sampleRate = info.sample_rate;
    out->sampleCount = count;
    out->f32 = samples;
done:
    stb_vorbis_close(vorbis);
    if (status != PD_SAMPLE_DECODE_OK) free(samples);
    return status;
}

PdSampleDecodeStatus pd_sample_decode(PdSampleCodec codec, const uint8_t *bytes, size_t length,
                                       uint64_t maxInterleavedSamples, PdSamplePcm *out)
{
    if (!out) return PD_SAMPLE_DECODE_CORRUPT;
    memset(out, 0, sizeof(*out));
    if (!bytes || !length) return PD_SAMPLE_DECODE_CORRUPT;
    switch (codec) {
    case PD_SAMPLE_CODEC_MP3:
        return decode_mp3(bytes, length, maxInterleavedSamples, out);
    case PD_SAMPLE_CODEC_FLAC:
        return decode_flac(bytes, length, maxInterleavedSamples, out);
    case PD_SAMPLE_CODEC_OGG:
        return decode_ogg(bytes, length, maxInterleavedSamples, out);
    }
    return PD_SAMPLE_DECODE_CORRUPT;
}
