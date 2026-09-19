#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct M4AEngine M4AEngine;

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

#ifdef __cplusplus
}
#endif
