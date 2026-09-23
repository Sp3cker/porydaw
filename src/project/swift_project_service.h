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

// One published bank slot, mirroring VoicegroupSlotView. The tone fields
// publish the immutable loaded bank's ToneData/voiceNames for slots the
// source model does not cover with a parsed voice (read-only cry lines,
// broken lines, headers) — the same fallback VoicegroupBrowser::updateRow
// inks from bank->voices[slot]. Editable and blank slots publish no tone:
// the parsed voice / [Blank] rendering is authoritative there.
typedef struct PdBankSlotView {
    int32_t kind; // VgLineKind ordinal
    bool hasVoice;
    PdVoiceValue voice; // valid when hasVoice is true
    bool hasTone;
    const char *toneName; // trimmed voiceNames[slot]; borrowed
    int32_t toneType;     // raw ToneData.type byte
    bool toneSynth;       // toneIsSynth: fix/alt type bits + 0-size wav descriptor
    bool hasToneAdsr;     // false for keysplit/drumkit tones (no scalar envelope)
    int32_t toneAttack;
    int32_t toneDecay;
    int32_t toneSustain;
    int32_t toneRelease;
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

// One playable song's listing metadata (all strings borrowed until the
// completion returns). `id` is the SongInfo identity: the numeric song ID
// when registered, the project snapshot index for unregistered strays.
// `registrationGaps` names the registration files still missing the entry;
// empty when the registration is complete.
typedef struct PdSongListEntry {
    int32_t id;
    const char *label;
    const char *constant;
    const char *player;
    const char *midiPath;
    int32_t trackBudget;
    bool hasMid;
    bool hasCfg;
    bool registered;
    const char *const *registrationGaps;
    size_t registrationGapCount;
} PdSongListEntry;

typedef void (*PdSongListCompletion)(void *context, bool ok, const PdSongListEntry *songs,
                                     size_t songCount, const char *error);

// The registration plan behind the native Register Song confirmation
// (RegistrationPlanResult): the resolved identity plus the registration
// files still missing the entry, named exactly as SongInfo::registrationGaps
// (and the native dialog) name them. All strings borrowed.
typedef struct PdSongRegistrationPlan {
    const char *label;
    const char *constant;
    const char *player;
    int32_t songId; // proposed table index
    const char *const *missingFiles;
    size_t missingFileCount;
} PdSongRegistrationPlan;

// The removal plan behind the native Delete Song confirmation
// (DeletionPlanResult): what unregisterSong would edit plus the voicegroup
// that may be deleted with the song (raw -G arg and display name; empty when
// none applies). All strings borrowed.
typedef struct PdSongDeletionPlan {
    int32_t tableIndex; // -1 = no table entry; 0 = engine fallback, undeletable
    int32_t tableCount;
    bool lastEntry; // true: the row is removed outright; false: it becomes a free slot
    bool inSongsH;
    bool inLdScript;
    bool inCharmap;
    bool inDebugMenu;
    const char *deletableVoicegroup;
    const char *deletableVoicegroupDisplay;
} PdSongDeletionPlan;

typedef void (*PdSongRegistrationPlanCompletion)(void *context, bool ok,
                                                 const PdSongRegistrationPlan *plan,
                                                 const char *error);
typedef void (*PdSongDeletionPlanCompletion)(void *context, bool ok, const PdSongDeletionPlan *plan,
                                             const char *error);
// songId: the assigned table index after a successful register, -1 otherwise.
typedef void (*PdSongMutationCompletion)(void *context, bool ok, int32_t songId, const char *error);
typedef void (*PdStringListCompletion)(void *context, bool ok, const char *const *strings,
                                       size_t stringCount, const char *error);

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

// Preconditions for asynchronous pd_service_* operations below: `service`
// and `completion` are non-null; request/edit/lease pointers named by the
// operation are non-null; and pointer/count pairs contain readable storage for
// the duration of the call. Invalid arguments are programmer errors: the
// operation returns without enqueueing work and does not invoke its completion.

void pd_service_open(PdProjectService *service, const char *projectRoot, void *context,
                     PdOpenCompletion completion);
// Lists every playable song (isPlayable == hasMid): registered, partially
// registered and unregistered strays alike, in project snapshot order.
void pd_service_list_songs(PdProjectService *service, void *context,
                           PdSongListCompletion completion);
void pd_service_open_song(PdProjectService *service, const char *label, void *context,
                          PdSongCompletion completion);
// The two-phase register/delete transaction behind the native context-menu
// flows (WorkspaceUi::runRegisterFlow/runDeleteFlow). The plan calls are
// read-only: they resolve the song's identity and compute what the
// registration files would gain or lose, for the shell's confirmation. The
// mutations re-derive their plan on the worker before writing — the
// confirmed plan is never trusted as a commit — then refresh the project
// snapshot, so a following pd_service_list_songs sees the result.
void pd_service_song_registration_plan(PdProjectService *service, const char *label, void *context,
                                       PdSongRegistrationPlanCompletion completion);
// Registers the song with the confirmed constant/player; empty values fall
// back to the label-derived constant and MUSIC_PLAYER_BGM, like the native
// flow. songId carries the assigned table index.
void pd_service_song_register(PdProjectService *service, const char *label, const char *constant,
                              const char *player, void *context,
                              PdSongMutationCompletion completion);
void pd_service_song_deletion_plan(PdProjectService *service, const char *label, void *context,
                                   PdSongDeletionPlanCompletion completion);
// Deletes the song: its .mid moves to .porydaw/trash, its .s and midi.cfg
// flags are removed, and its registration lines are unregistered.
// deleteVoicegroupName names the confirmed plan's deletable voicegroup
// (empty = keep it); the worker re-verifies it is still unused before
// deleting. Song ID 0 (the engine fallback) refuses with an error.
void pd_service_song_delete(PdProjectService *service, const char *label,
                            const char *deleteVoicegroupName, void *context,
                            PdSongMutationCompletion completion);
// The project's -G voicegroup arguments (SongRegistry::voicegroupArgs /
// catalog groupArgs), sorted — the voice-list selector's choice feed.
void pd_service_voicegroup_args(PdProjectService *service, void *context,
                                PdStringListCompletion completion);
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
