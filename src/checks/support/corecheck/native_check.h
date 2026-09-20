#pragma once

#ifdef __cplusplus
extern "C" {
#endif
void pdc_check_set_fixture_root(const char *path);
const char *pdc_check_fixture_root(void);

// Native engine fixture boundary for permanent Swift playback checks.
typedef struct PdcPlaybackEngine PdcPlaybackEngine;

PdcPlaybackEngine *pdc_playback_engine_create(double sampleRate);
void pdc_playback_engine_destroy(PdcPlaybackEngine *engine);
void *pdc_playback_engine_pointer(PdcPlaybackEngine *engine);

#ifdef __cplusplus
}
#endif
