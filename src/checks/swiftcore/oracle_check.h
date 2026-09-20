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
int64_t oracle_document_summary(const uint8_t *input, size_t inputCount, char *output,
                                size_t outputCapacity);
// Unknown operations return INT64_MIN from the value adapter and -1 from the
// text adapter. The text adapter does not write output for an unknown operation.
int64_t oracle_semantic_value(uint32_t operation, int64_t a, int64_t b, int64_t c, int64_t d);
int64_t oracle_semantic_text(uint32_t operation, int64_t a, int64_t b, char *output,
                             size_t outputCapacity);
void oracle_check_set_fixture_root(const char *path);
const char *oracle_check_fixture_root(void);

// Native engine fixture boundary only; playback assertions live in Swift.
typedef struct PdcPlaybackEngine PdcPlaybackEngine;

PdcPlaybackEngine *pdc_playback_engine_create(double sampleRate);
void pdc_playback_engine_destroy(PdcPlaybackEngine *engine);
void *pdc_playback_engine_pointer(PdcPlaybackEngine *engine);

#ifdef __cplusplus
}
#endif
