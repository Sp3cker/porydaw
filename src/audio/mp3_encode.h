#ifndef PORYDAW_MP3_ENCODE_H
#define PORYDAW_MP3_ENCODE_H

#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PdMp3Encoder PdMp3Encoder;

enum {
    PD_MP3_CHANNELS = 2,
    PD_MP3_BITRATE_KBPS = 320,
};

/* Fixed stereo 320 kbps CBR encoder (32000/44100/48000 Hz only). NULL when the
   rate is unsupported or configuration fails. */
PdMp3Encoder *pd_mp3_create(int sample_rate);

/* Encodes interleaved s16 stereo frames. Staged bytes in out (0 while
   buffering) or a negative code for pd_mp3_error_text. */
int pd_mp3_encode_s16(PdMp3Encoder *enc, const int16_t *pcm, int frames_per_channel,
                      uint8_t *out, int out_capacity);

/* Flushes buffered frames. Returns the staged bytes or a negative error code. */
int pd_mp3_flush(PdMp3Encoder *enc, uint8_t *out, int out_capacity);

/* Rewrites the Xing/Info LAME tag (encoder delay and padding) over the first
   frame via lame_get_lametag_frame with checked seek/write. Returns 0 ok. */
int pd_mp3_write_tag(PdMp3Encoder *enc, FILE *stream);

const char *pd_mp3_error_text(int code);

void pd_mp3_free(PdMp3Encoder *enc);
#ifdef __cplusplus
}
#endif

#endif
