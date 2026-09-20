#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
void pdc_check_set_fixture_root(const char *path);
const char *pdc_check_fixture_root(void);

void pdc_check_set_mid2agb_path(const char *path);

typedef struct PdcMidiExportResult {
    uint32_t matchingSongBits;
    uint32_t missingSongBits;
    uint32_t originalCompileFailureBits;
    uint32_t encodedCompileFailureBits;
    int32_t projectOpenFailed;
    int32_t xcmdCompileFailed;
    int32_t xiecvCount;
    int32_t xieclCount;
    int32_t xiecv64Count;
    int32_t xiecl51Count;
    int32_t unknown127Count;
} PdcMidiExportResult;

// Runs the complete test-only mid2agb boundary check over the Swift-written
// song and XCMD fixtures in the current swiftcore scratch directory.
PdcMidiExportResult pdc_check_midi_exports(void);
// Reopens one saved song from the specified project and compiles its persisted
// MIDI with the flags read from that project's registry.
int32_t pdc_check_compile_saved_midi(const char *projectRoot, const char *songLabel);

// Native engine fixture boundary for permanent Swift playback checks.
typedef struct PdcPlaybackEngine PdcPlaybackEngine;

PdcPlaybackEngine *pdc_playback_engine_create(double sampleRate);
void pdc_playback_engine_destroy(PdcPlaybackEngine *engine);
void *pdc_playback_engine_pointer(PdcPlaybackEngine *engine);

#ifdef __cplusplus
}
#endif
