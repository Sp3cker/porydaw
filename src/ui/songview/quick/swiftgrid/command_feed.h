#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// The writable direction of the document seam (spec.md §1–2): Swift submits
// one SgcIntentCommand through sgc_submit; the registered C++ executor routes
// by intent — document intents become undoable SongDocument commands, session
// intents become SongView state. Swift calls C++, never the reverse.
//
// NoteId tokens are document-scoped uint64 values delivered by the sgd_/sgs_
// feeds; token 0 is never valid. String payloads are UTF-8 pointer+length,
// copied during the synchronous call and never retained.

typedef enum {
    // Document intents (undoable; one intent = one undo entry).
    SGC_NOTE_ADD = 0,
    SGC_NOTE_MOVE = 1,
    SGC_NOTE_RESIZE = 2,
    SGC_NOTE_DELETE = 3,
    SGC_TRACK_ADD = 4,
    SGC_TRACK_DUPLICATE = 5,
    SGC_TRACK_DELETE = 6,
    SGC_TRACK_REORDER = 7,
    SGC_TRACK_RENAME = 8,
    // Session intents (no undo entries).
    SGC_SELECTION_SET_NOTES = 9,
    SGC_SELECTION_CLEAR = 10,
    SGC_TRACK_MUTE = 11,
    SGC_TRACK_SOLO = 12,
} SgcIntent;

typedef enum {
    SGC_EXECUTED = 0,
    // Malformed payload, stale NoteId token, or out-of-range field; nothing
    // was mutated.
    SGC_REJECTED_INVALID = 1,
    // Eligibility said no (no executor bound, document refused the edit);
    // nothing was mutated.
    SGC_REJECTED_UNAVAILABLE = 2,
} SgcResult;

typedef struct {
    int32_t trackIndex;
    int32_t key;
    uint32_t onTick;
    uint32_t durationTicks;
    int32_t velocity;
} SgcNoteAdd;

typedef struct {
    uint64_t noteId;
    int64_t deltaTicks;
    int32_t deltaKeys;
} SgcNoteMove;

typedef struct {
    uint64_t noteId;
    uint32_t durationTicks;
} SgcNoteResize;

// Token list for SGC_NOTE_DELETE and SGC_SELECTION_SET_NOTES.
typedef struct {
    const uint64_t *noteIds;
    int32_t count;
} SgcNoteList;

// The voicegroup program seeding the new track's slot.
typedef struct {
    int32_t voice;
} SgcTrackAdd;

typedef struct {
    int32_t trackIndex;
} SgcTrackIndex;

typedef struct {
    int32_t trackIndex;
    int32_t newIndex;
} SgcTrackReorder;

typedef struct {
    int32_t trackIndex;
    const char *name;
    int32_t nameLength;
} SgcTrackRename;

// on is 0 or 1.
typedef struct {
    int32_t trackIndex;
    uint8_t on;
} SgcTrackFlag;

typedef struct {
    // Routes to the executor registered for this document feed id.
    uint64_t documentId;
    SgcIntent intent;
    union {
        SgcNoteAdd noteAdd;
        SgcNoteMove noteMove;
        SgcNoteResize noteResize;
        SgcNoteList noteList;
        SgcTrackAdd trackAdd;
        SgcTrackIndex trackIndex;
        SgcTrackReorder trackReorder;
        SgcTrackRename trackRename;
        SgcTrackFlag trackFlag;
    } payload;
} SgcIntentCommand;

typedef struct {
    SgcResult result;
    // SGC_NOTE_ADD only: the minted NoteId token of the new note; 0 otherwise.
    uint64_t noteId;
} SgcOutcome;

typedef SgcResult (*SgcExecuteFn)(const SgcIntentCommand *command, SgcOutcome *outcome,
                                  void *context);
typedef struct {
    SgcExecuteFn fn;
    void *context;
} SgcExecutor;

// GUI-thread-only live endpoints. Slots and callback contexts are borrowed.
void sgc_register_executor(uint64_t document_id, SgcExecutor *executor);
void sgc_unregister_executor(uint64_t document_id);
bool sgc_set_executor(uint64_t document_id, SgcExecuteFn fn, void *context);
void sgc_clear_executor(uint64_t document_id);
// Synchronous on the GUI thread; returns the same code written to outcome.
SgcResult sgc_submit(const SgcIntentCommand *command, SgcOutcome *outcome);

#ifdef __cplusplus
}
#endif
