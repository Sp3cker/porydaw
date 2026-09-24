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
    PDC_SUITE_EVENT_EDITS = 6,
    PDC_SUITE_XCMD_EDITS = 7,
    PDC_SUITE_MIDI_IMPORT = 8,
    PDC_SUITE_TIME_EDITS = 9,
    PDC_SUITE_PROJECT_SESSION = 10,
    PDC_SUITE_BANK_HISTORY = 11,
    PDC_SUITE_PROJECT_IDENTITY = 12,
    PDC_SUITE_SONG_MODEL = 13,
    PDC_SUITE_MIDI_CFG = 14,
    PDC_SUITE_SONGS_MK = 15,
    PDC_SUITE_SONG_CATALOG = 16,
    PDC_SUITE_SYNTH_CATALOG = 17,
    PDC_SUITE_VOICE_VALUES = 18,
    PDC_SUITE_SAVECORE = 19,
    PDC_SUITE_VOICE_EDITING = 20,
    PDC_SUITE_CATALOG_ABSENT = 21,
    PDC_SUITE_PROJECTSTORE_CHECKS = 22,
    PDC_SUITE_VOICE_CONTEXT = 23,
    PDC_SUITE_VOICE_BANKLOGIC = 24,
};

typedef void (*PdcCheckReport)(void *context, int failed, const char *cppId, const char *message);

void pdc_suite_run(uint32_t suite, PdcCheckReport report, void *context);

#ifdef __cplusplus
}
#endif
