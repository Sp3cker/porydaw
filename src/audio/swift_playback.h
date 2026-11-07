#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "m4a_engine.h"

#ifdef __cplusplus
extern "C" {
#endif

// Natural alignment is part of the boundary: do not pack this structure.
typedef struct PdPlaybackEvent {
    uint64_t sample;
    uint32_t tick;
    uint8_t type;
    uint8_t track;
    uint8_t data0;
    uint8_t data1;
    uint64_t noteID;
} PdPlaybackEvent;

typedef struct PdPlaybackTempoPoint {
    uint32_t tick;
    uint32_t microsecondsPerQuarterNote;
    double sampleOrigin;
} PdPlaybackTempoPoint;

#ifdef __cplusplus
static_assert(sizeof(PdPlaybackEvent) == 24);
static_assert(offsetof(PdPlaybackEvent, noteID) == 16);
static_assert(sizeof(PdPlaybackTempoPoint) == 16);
#else
_Static_assert(sizeof(PdPlaybackEvent) == 24, "PdPlaybackEvent natural layout changed");
_Static_assert(offsetof(PdPlaybackEvent, noteID) == 16, "PdPlaybackEvent NoteID offset changed");
_Static_assert(sizeof(PdPlaybackTempoPoint) == 16, "PdPlaybackTempoPoint layout changed");
#endif

// Immutable borrowed view. The ownerContext is private to the Swift publication
// and is used only by the control-thread retain/release entry points. Renderers
// borrow every pointer and never retain, release, or dereference ownerContext.
typedef struct PdPlaybackData {
    const PdPlaybackEvent *events;
    size_t eventCount;
    const PdPlaybackTempoPoint *tempoMap;
    size_t tempoPointCount;

    double sampleRate;
    uint64_t lengthSamples;
    uint64_t loopStartSample;
    uint64_t loopEndSample;
    uint32_t ticksPerBeat;
    uint32_t lengthTicks;
    uint32_t loopStartTick;
    uint32_t loopEndTick;
    uint32_t usedTrackCount;
    uint32_t droppedTracks;
    bool exactGate;
    bool extendedClocks;

    const void *ownerContext;
} PdPlaybackData;

// One successful load returns one owned reference. Native shared_ptr adoption
// consumes that reference and uses pd_playback_data_release as its deleter.
// Copies of that shared_ptr share the control block and must not call retain.
// Callback-time code borrows data and must not retain or release it.
void pd_playback_data_retain(const PdPlaybackData *data);
void pd_playback_data_release(const PdPlaybackData *data);
bool pd_playback_data_load_file(const char *path, double sampleRate, PdPlaybackData **out,
                                char *error, size_t errorCapacity);

void *pd_player_create(void);
void pd_player_destroy(void *player);
void pd_player_reset(void *player);
uint64_t pd_player_position(const void *player);
void pd_player_seek(void *player, uint64_t position, const PdPlaybackData *data);
void pd_player_replace(void *player, uint64_t position, const PdPlaybackData *data);
void pd_player_chase(M4AEngine *engine, const PdPlaybackData *data, uint64_t position);
void pd_player_prime(M4AEngine *engine, const PdPlaybackData *data, uint64_t position);
void pd_player_render(void *player, M4AEngine *engine, const PdPlaybackData *data, float *left,
                      float *right, size_t frames, bool looping, uint32_t muteMask);

// Callback-only mixer cursor for the primary/shadow pcmChannels index. This is
// the next source frame mixed, which can lead audible output in the DMA FIFO.
static inline bool pd_audio_pcm_source_frame(const M4AEngine *engine, int channelIndex, uint32_t *frame)
{
    if (!engine || !frame || channelIndex < 0 || channelIndex >= TOTAL_PCM_CHANNELS)
        return false;
    const M4ADriver *driver = channelIndex < MAX_PCM_CHANNELS ? engine->driver : engine->shadowDriver;
    if (!driver)
        return false;
    const M4ADriverPcmChan *channel = &driver->pcmChans[channelIndex % MAX_PCM_CHANNELS];
    if (!(channel->status & M4A_CHN_ON) || !channel->wav || !channel->wav->data || !channel->wav->size)
        return false;

    const bool reverse = (channel->type & VOICE_TYPE_REV) != 0;
    int64_t position;
    if (driver->active_pcm_mode == M4A_PCM_MIXER_IPATIX) {
        const M4APcmIpatixChannelState *state = &channel->ipatix;
        position = state->source_position;
        if (!state->compressed && state->current_pointer) {
            const ptrdiff_t offset = state->current_pointer - channel->wav->data;
            if (offset >= 0 && (uint64_t)offset <= channel->wav->size)
                position = reverse && offset > 0 ? offset - 1 : offset;
        } else if (state->compressed && reverse && position > 0) {
            --position;
        }
    } else if (driver->active_pcm_mode == M4A_PCM_MIXER_SAPPY) {
        const M4APcmSappyChannelState *state = &channel->sappy;
        if (channel->status & M4A_CHN_START) {
            const uint32_t offset = state->start_offset < channel->wav->size
                ? state->start_offset : channel->wav->size;
            position = reverse ? (int64_t)channel->wav->size - offset - 1 : offset;
        } else {
            position = (int64_t)state->source_position - (reverse ? 1 : 0);
        }
    } else {
        return false;
    }
    if (position < 0 || (uint64_t)position >= channel->wav->size)
        return false;
    *frame = (uint32_t)position;
    return true;
}

#ifdef __cplusplus
}
#endif
