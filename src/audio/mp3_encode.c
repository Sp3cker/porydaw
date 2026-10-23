#include "mp3_encode.h"

#include <stdarg.h>
#include <stdlib.h>

#include "lame.h"

struct PdMp3Encoder {
    lame_global_flags *gfp;
};

/* Export runs off the main thread; keep LAME's stderr diagnostics silent and
   surface failures through return codes instead. */
static void pd_mp3_quiet(const char *format, va_list args)
{
    (void)format;
    (void)args;
}

PdMp3Encoder *pd_mp3_create(int sample_rate)
{
    if (sample_rate != 32000 && sample_rate != 44100 && sample_rate != 48000)
        return NULL;
    PdMp3Encoder *enc = calloc(1, sizeof(*enc));
    if (!enc)
        return NULL;
    lame_global_flags *gfp = lame_init();
    if (!gfp) {
        free(enc);
        return NULL;
    }
    lame_set_errorf(gfp, pd_mp3_quiet);
    lame_set_debugf(gfp, pd_mp3_quiet);
    lame_set_msgf(gfp, pd_mp3_quiet);
    lame_set_num_channels(gfp, PD_MP3_CHANNELS);
    lame_set_in_samplerate(gfp, sample_rate);
    lame_set_brate(gfp, PD_MP3_BITRATE_KBPS);
    lame_set_mode(gfp, STEREO);
    lame_set_quality(gfp, 2);
    if (lame_init_params(gfp) < 0) {
        lame_close(gfp);
        free(enc);
        return NULL;
    }
    enc->gfp = gfp;
    return enc;
}

int pd_mp3_encode_s16(PdMp3Encoder *enc, const int16_t *pcm, int frames_per_channel,
                      uint8_t *out, int out_capacity)
{
    if (!enc || !enc->gfp || !pcm || !out || frames_per_channel <= 0 || out_capacity <= 0)
        return -1;
    return lame_encode_buffer_interleaved(enc->gfp, (short *)pcm, frames_per_channel,
                                          (char *)out, out_capacity);
}

int pd_mp3_flush(PdMp3Encoder *enc, uint8_t *out, int out_capacity)
{
    if (!enc || !enc->gfp || !out || out_capacity <= 0)
        return -1;
    return lame_encode_flush(enc->gfp, (char *)out, out_capacity);
}

int pd_mp3_write_tag(PdMp3Encoder *enc, FILE *stream)
{
    if (!enc || !enc->gfp || !stream)
        return -1;
    /* The stream carries no ID3v2 prefix (neither side emits one), so the
       tag frame starts at offset 0; lame_get_lametag_frame sizes it. */
    unsigned char tag[4096];
    size_t size = lame_get_lametag_frame(enc->gfp, tag, sizeof(tag));
    if (size == 0 || size > sizeof(tag))
        return -1;
    if (fseek(stream, 0, SEEK_SET) != 0)
        return -1;
    if (fwrite(tag, 1, size, stream) != size)
        return -1;
    if (fseek(stream, 0, SEEK_END) != 0)
        return -1;
    return 0;
}

const char *pd_mp3_error_text(int code)
{
    switch (code) {
    case -1: return "MP3 output buffer too small";
    case -2: return "MP3 encoder out of memory";
    case -3: return "MP3 encoder parameters not initialized";
    case -4: return "MP3 psychoacoustic configuration error";
    default: return "unknown MP3 encoder error";
    }
}

void pd_mp3_free(PdMp3Encoder *enc)
{
    if (!enc)
        return;
    lame_close(enc->gfp);
    free(enc);
}
