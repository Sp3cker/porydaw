#pragma once

#include <stddef.h>
#include <stdint.h>

// Native audio session bridge for the Swift grid prototype. Every call
// must run on the main UI thread (Swift wrapper is @MainActor). The session
// owns a production AudioEngine, the fixture_rich voicegroup lease, and the
// latest projection of the Swift-owned musical state into a MidiTimeline.
// No global state; each handle is independent.

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SGAudioSession SGAudioSession;

typedef struct SGNote {
    int64_t tick;
    int64_t duration;
    int32_t track;
    int32_t pitch;
    int32_t velocity;
} SGNote;

// controller 255 denotes a signed pitch bend in [-8192, 8191]; 1 modulation,
// 20 bend range, 21 LFO speed. Other ordinary MIDI CC numbers remain
// representable with data values clamped to [0, 127].
typedef struct SGController {
    int64_t tick;
    int32_t track;
    int32_t controller;
    int32_t value;
} SGController;

// fixture_root must be a directory containing the bundled decompproject
// `sound` tree. Returns null on engine/bank failure with a diagnostic copied
// into error_buffer (when provided with positive capacity).
SGAudioSession *sga_create(const char *fixture_root, char *error_buffer, size_t error_capacity);

// Stops the engine before releasing the voicegroup bank.
void sga_destroy(SGAudioSession *session);

// Both arrays are borrowed only for the duration of the call. The first
// sync performs the cold engine load; subsequent syncs hot-update the
// timeline and are safe during playback. Always emits program changes on
// engine tracks 0 and 1 (programs 0 and 2) so empty Swift tracks keep the
// engine mapping intact.
void sga_sync(SGAudioSession *session, const SGNote *notes, size_t note_count,
              const SGController *controllers, size_t controller_count);
void sga_play(SGAudioSession *session);
void sga_pause(SGAudioSession *session);
void sga_stop(SGAudioSession *session);
void sga_seek_tick(SGAudioSession *session, double tick);

// Audition one note outside the timeline; velocity 0 releases it.
void sga_preview(SGAudioSession *session, int track, int key, int velocity);

int sga_is_playing(SGAudioSession *session);
double sga_playhead_tick(SGAudioSession *session);
double sga_sample_rate(SGAudioSession *session);
int sga_using_null_backend(SGAudioSession *session);

// Borrowed until the next mutating call on the same session or destroy.
const char *sga_backend_name(SGAudioSession *session);
#ifdef __cplusplus
} // extern "C"
#endif
