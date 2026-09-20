#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum PdcSuite {
    PDC_SUITE_MIDI_CODEC = 1,
    PDC_SUITE_MUSICAL_SEMANTICS = 2,
    PDC_SUITE_PLAYBACK = 3,
    PDC_SUITE_NOTE_EDITS = 4,
    PDC_SUITE_DOCUMENT_HISTORY = 5,
};

typedef void (*PdcCheckReport)(void *context, int failed, const char *cppId, const char *message);

void pdc_suite_run(uint32_t suite, PdcCheckReport report, void *context);

#ifdef __cplusplus
}
#endif
