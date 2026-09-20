#pragma once

// Narrow C boundary for the Swift project service (Task 6).
//
// One owning service handle fronts a serial native worker that owns the
// DecompProject. Every operation is asynchronous: the caller returns
// immediately and the worker invokes the operation's completion exactly once
// on the worker thread. All byte/string payloads handed to a completion are
// borrowed until that completion returns; Swift copies them synchronously
// inside the completion (exactly once) and never retains them.
//
// Ownership: PdBankLease is an opaque owning handle over one published native
// bank. The Swift NativeBankLease wrapper owns it and releases it in deinit.
// Applied bank edits mint a fresh lease; the previous handle keeps its own
// bank alive, so old views stay readable.

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PdProjectService PdProjectService;
typedef struct PdBankLease PdBankLease;

// Decoded song flags, mirroring SongCfg value semantics.
typedef struct PdSongCfg {
    const char *const *rawFlags;
    size_t rawFlagCount;
    const char *voicegroupArg;
    int masterVolume;
    int reverb;
    bool hasReverb; // false means the -R flag is absent
    int priority;
    bool exactGate;
    bool extendedClocks;
    bool noCompression;
} PdSongCfg;

// One editable voice's parsed macro arguments, mirroring VgVoice.
typedef struct PdVoiceValue {
    int32_t macro; // VgMacro ordinal
    int32_t key;
    int32_t pan;
    const char *symbol;
    const char *keysplitTable;
    int32_t sweep;
    int32_t duty;
    int32_t period;
    int32_t attack;
    int32_t decay;
    int32_t sustain;
    int32_t release;
} PdVoiceValue;

// One published bank slot, mirroring VoicegroupSlotView.
typedef struct PdBankSlotView {
    int32_t kind; // VgLineKind ordinal
    bool hasVoice;
    PdVoiceValue voice; // valid when hasVoice is true
} PdBankSlotView;

// One published bank, mirroring LoadedBankView (identity strings borrowed).
typedef struct PdBankView {
    const PdBankSlotView *slotViews;
    size_t slotCount;
    const char *loadName;
    const char *sourcePath;
    const char *sectionLabel;
    bool dirty;
} PdBankView;

// Song metadata for an opened song (all strings borrowed).
typedef struct PdSongMeta {
    const char *label;
    const char *midiPath;
    const char *constant;
    const char *player;
    int32_t trackBudget;
    bool hasMid;
    bool hasCfg;
    bool registered;
    PdSongCfg cfg;
} PdSongMeta;

typedef void (*PdOpenCompletion)(void *context, bool ok, const char *error);
typedef void (*PdSongCompletion)(void *context, bool ok, const uint8_t *midiBytes,
                                 size_t midiByteCount, const PdSongMeta *meta,
                                 const PdBankView *bank, PdBankLease *lease, const char *error);
typedef void (*PdSaveCompletion)(void *context, bool ok, bool flagsWritten, const PdBankView *bank,
                                 PdBankLease *lease, const char *error);
typedef void (*PdBankEditCompletion)(void *context, int32_t outcome, const PdBankView *bank,
                                     PdBankLease *lease, uint64_t materializationToken,
                                     const char *error);

enum {
    PD_BANK_EDIT_APPLIED = 0,
    PD_BANK_EDIT_CONFLICT = 1,
    PD_BANK_EDIT_FAILED = 2,
};

// A set-slot edit. hasExpected false means the slot must still be blank.
typedef struct PdVoiceEdit {
    int32_t slot;
    PdVoiceValue value;
    bool hasExpected;
    PdVoiceValue expected;
} PdVoiceEdit;

// Ordered song save: optional bank save, then MIDI bytes, then flags.
typedef struct PdSaveRequest {
    const char *label;
    const char *midPath;
    const uint8_t *midiBytes;
    size_t midiByteCount;
    PdSongCfg cfg;
    bool flagsNeeded;
    bool saveBank;
    const char *bankSourcePath;
    const char *bankSectionLabel;
} PdSaveRequest;

PdProjectService *pd_service_create(void);
// Drains outstanding work (their completions are still delivered), then joins
// the worker. The caller must not retain borrowed payloads past their
// completion; owned leases outlive the service.
void pd_service_destroy(PdProjectService *service);

void pd_service_open(PdProjectService *service, const char *projectRoot, void *context,
                     PdOpenCompletion completion);
void pd_service_open_song(PdProjectService *service, const char *label, void *context,
                          PdSongCompletion completion);
void pd_service_save(PdProjectService *service, const PdSaveRequest *request, void *context,
                     PdSaveCompletion completion);
void pd_service_bank_apply(PdProjectService *service, PdBankLease *lease, const PdVoiceEdit *edit,
                           void *context, PdBankEditCompletion completion);
void pd_service_bank_revert(PdProjectService *service, PdBankLease *lease,
                            uint64_t materializationToken, void *context,
                            PdBankEditCompletion completion);

void pd_bank_lease_release(PdBankLease *lease);
// Identity of the underlying bank (its address as an integer, 0 when the
// handle holds none). Successive loads of one song reuse the bank; applied
// edits replace it. Test/diagnostic use only.
uintptr_t pd_bank_lease_bank_token(const PdBankLease *lease);

#ifdef __cplusplus
} // extern "C"

#include "project/voicegroupsource.h"

// C++-only native accessors for the audio engine (Task 7 binds here). The
// shared_ptr-bearing lease never crosses the Clang C importer: this section
// is compiled only as C++.
const VoicegroupLease &pd_bank_lease_native(const PdBankLease *lease);
const VoicegroupId &pd_bank_lease_identity(const PdBankLease *lease);

#endif
