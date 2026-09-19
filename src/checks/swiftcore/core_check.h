#pragma once

#include <stddef.h>
#include <stdint.h>

#include "audio/swift_playback.h"

#ifdef __cplusplus
extern "C" {
#endif

enum PdcSemanticValueOperation {
    PDC_CC_EVENT_CLASS = 1,
    PDC_CC_LANE = 2,
    PDC_CC_EXPORT_SUPPORT = 3,
    PDC_XCMD_LANE = 4,
    PDC_EFFECTIVE_VELOCITY = 5,
    PDC_EFFECTIVE_DURATION = 6,
    PDC_VELOCITY_IS_PSG = 10,
    PDC_VELOCITY_COMPATIBLE = 11,
    PDC_VELOCITY_LEVEL_COUNT = 12,
    PDC_VELOCITY_LEVEL_RANGE = 13,
    PDC_VELOCITY_LEVEL_OF = 14,
    PDC_VELOCITY_REPRESENTATIVE = 15,
    PDC_VELOCITY_CANONICALIZE = 16,
    PDC_VELOCITY_MOVE_LEVELS = 17,
    PDC_CONTROLLER_DEFAULT = 20,
    PDC_LANE_MINIMUM = 21,
    PDC_LANE_MAXIMUM = 22,
    PDC_LANE_CENTERED = 23,
    PDC_LANE_ZOOMABLE = 24,
    PDC_HAS_ENGINE_DEFAULT = 25,
    PDC_TEMPO_USPQN_FOR_BPM = 26,
    PDC_TEMPO_BPM_BITS = 27,
    PDC_CLAMP_TEMPO_USPQN = 28,
    PDC_SHIFT_TICK = 29,
    PDC_TICK_FROM_DOUBLE_BITS = 30,
    PDC_TRACK_CAPACITY = 31,
    PDC_NOTE_ID_IS_ASSIGNED = 33,
    PDC_NOTE_ID_DOES_NOT_AFFECT_STORAGE = 34,
};

enum PdcSemanticTextOperation {
    PDC_CC_NAME = 1,
    PDC_CC_DISPLAY = 2,
    PDC_LANE_NAME = 3,
    PDC_FORMAT_CC_VALUE = 4,
    PDC_ADVANCED_CC_LABEL = 5,
    PDC_FORMAT_BEND = 6,
    PDC_VOICE_TYPE_NAME = 7,
    PDC_MIDI_KEY_NAME = 8,
    PDC_TIME_SIGNATURE_LABEL = 9,
    PDC_VELOCITY_VOICE_NAME = 10,
};

// Decodes and canonically re-encodes one file. A nonnegative return value is
// the required output byte count; -1 means complete decode/encode failure.
// summary_size and error_size exclude a trailing NUL. Passing null output
// buffers performs the sizing call used by the C++ driver.
int64_t pdc_codec_roundtrip(const uint8_t *input, size_t input_count, uint8_t *output,
                            size_t output_capacity, uint8_t *was_format_zero, char *summary,
                            size_t summary_capacity, size_t *summary_size, char *error,
                            size_t error_capacity, size_t *error_size);

// Projects one MIDI file through the production Swift playback timeline. The
// return value is the required event count; -1 reports decode/projection failure.
int64_t pdc_playback_project_file(const char *path, double sample_rate, bool exact_gate,
                                  bool extended_clocks, PdPlaybackEvent *events,
                                  size_t event_capacity, PdPlaybackData *data, char *error,
                                  size_t error_capacity);

// Renders one Swift timeline, optionally replacing it at replacement_frame.
// All engine and sample buffers are borrowed for the duration of the call.
bool pdc_playback_render_files(const char *path, const char *replacement_path, double sample_rate,
                               bool exact_gate, bool extended_clocks, M4AEngine *engine,
                               float *left, float *right, size_t frames, size_t replacement_frame,
                               bool looping, uint32_t mute_mask, bool chase, bool prime,
                               char *error, size_t error_capacity);

// Applies Swift chase and/or voice priming to the caller's real engine.
bool pdc_playback_prepare_file(const char *path, double sample_rate, bool exact_gate,
                               bool extended_clocks, M4AEngine *engine, uint64_t position,
                               bool chase, bool prime, char *error, size_t error_capacity);

// Applies the native-publication chase/prime path to the caller's real engine.
bool pdc_playback_prepare_file_native(const char *path, double sample_rate, M4AEngine *engine,
                                      uint64_t position, bool chase, bool prime, char *error,
                                      size_t error_capacity);

int64_t pdc_blank_song(uint8_t *output, size_t output_capacity);

int64_t pdc_semantic_value(uint32_t operation, int64_t a, int64_t b, int64_t c, int64_t d);
int64_t pdc_semantic_text(uint32_t operation, int64_t a, int64_t b, char *output,
                          size_t output_capacity);

#ifdef __cplusplus
}
#endif
