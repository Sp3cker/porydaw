#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum OracleSemanticValueOperation {
    ORACLE_CC_CLASS = 1,
    ORACLE_CC_LANE = 2,
    ORACLE_CC_EXPORT = 3,
    ORACLE_XCMD_LANE = 4,
    ORACLE_EFFECTIVE_VELOCITY = 5,
    ORACLE_EFFECTIVE_DURATION = 6,
    ORACLE_VELOCITY_IS_PSG = 10,
    ORACLE_VELOCITY_COMPATIBLE = 11,
    ORACLE_VELOCITY_LEVEL_COUNT = 12,
    ORACLE_VELOCITY_LEVEL_RANGE = 13,
    ORACLE_VELOCITY_LEVEL = 14,
    ORACLE_VELOCITY_REPRESENTATIVE = 15,
    ORACLE_VELOCITY_CANONICALIZE = 16,
    ORACLE_VELOCITY_MOVE_LEVELS = 17,
    ORACLE_CONTROLLER_DEFAULT = 20,
    ORACLE_LANE_MINIMUM = 21,
    ORACLE_LANE_MAXIMUM = 22,
    ORACLE_LANE_CENTERED = 23,
    ORACLE_LANE_ZOOMABLE = 24,
    ORACLE_HAS_ENGINE_DEFAULT = 25,
    ORACLE_TEMPO_FROM_BPM = 26,
    ORACLE_BPM_FROM_TEMPO = 27,
    ORACLE_CLAMP_TEMPO = 28,
    ORACLE_SHIFT_TICK = 29,
    ORACLE_TICK_FROM_DOUBLE = 30,
    ORACLE_TRACK_CAPACITY = 31,
    ORACLE_NOTE_ID_ASSIGNED = 33,
    ORACLE_NOTE_ID_STORAGE = 34,
};

enum OracleSemanticTextOperation {
    ORACLE_CC_NAME = 1,
    ORACLE_CC_DISPLAY = 2,
    ORACLE_LANE_NAME = 3,
    ORACLE_CC_VALUE = 4,
    ORACLE_ADVANCED_CC_LABEL = 5,
    ORACLE_BEND = 6,
    ORACLE_VOICE_TYPE = 7,
    ORACLE_KEY_NAME = 8,
    ORACLE_TIME_SIGNATURE = 9,
    ORACLE_VELOCITY_NAME = 10,
};

int64_t oracle_codec_roundtrip(const uint8_t *input, size_t inputCount, uint8_t *output,
                               size_t outputCapacity, uint8_t *wasFormatZero, char *summary,
                               size_t summaryCapacity, size_t *summarySize, char *errorOut,
                               size_t errorCapacity, size_t *errorSize);
int64_t oracle_blank_song(uint8_t *output, size_t outputCapacity);
int64_t oracle_semantic_value(uint32_t operation, int64_t a, int64_t b, int64_t c, int64_t d);
int64_t oracle_semantic_text(uint32_t operation, int64_t a, int64_t b, char *output,
                             size_t outputCapacity);
void oracle_check_set_fixture_root(const char *path);
const char *oracle_check_fixture_root(void);

typedef struct OraclePlaybackEvent {
    uint64_t sample;
    uint32_t tick;
    uint8_t type;
    uint8_t track;
    uint8_t data0;
    uint8_t data1;
    uint64_t noteID;
} OraclePlaybackEvent;

typedef struct OraclePlaybackData {
    size_t eventCount;
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
} OraclePlaybackData;

typedef struct OraclePlaybackEngine OraclePlaybackEngine;

int64_t oracle_playback_project_file(const char *path, double sampleRate,
                                     OraclePlaybackEvent *events, size_t eventCapacity,
                                     OraclePlaybackData *data, char *errorOut,
                                     size_t errorCapacity);
bool oracle_playback_render_files(const char *path, const char *replacementPath, double sampleRate,
                                  OraclePlaybackEngine *engine, float *left, float *right,
                                  size_t frames, size_t replacementFrame, bool looping,
                                  uint32_t muteMask, char *errorOut, size_t errorCapacity);
bool oracle_playback_prepare_file(const char *path, double sampleRate, OraclePlaybackEngine *engine,
                                  uint64_t position, bool chase, bool prime, char *errorOut,
                                  size_t errorCapacity);

OraclePlaybackEngine *oracle_playback_engine_create(double sampleRate);
void oracle_playback_engine_destroy(OraclePlaybackEngine *engine);
void *oracle_playback_engine_pointer(OraclePlaybackEngine *engine);
void oracle_playback_engine_set_features(OraclePlaybackEngine *engine, bool portamento, bool pwm);
void oracle_playback_engine_note_on(OraclePlaybackEngine *engine, uint8_t track, uint8_t key,
                                    uint8_t velocity);
bool oracle_playback_engine_renders_audibly(OraclePlaybackEngine *engine);
int oracle_playback_engine_track_program(const OraclePlaybackEngine *engine, int track);
bool oracle_playback_engine_track_has_voice(const OraclePlaybackEngine *engine, int track);
int oracle_playback_engine_controller(const OraclePlaybackEngine *engine, int track,
                                      uint8_t controller);

#ifdef __cplusplus
}
#endif
