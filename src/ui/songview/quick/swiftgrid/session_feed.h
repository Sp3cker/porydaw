#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Time-selection scope values mirror
// songview::EditorSelectionModel::TimeSelection::Scope declaration order.
enum { SGS_TIME_SELECTION_TRACKS = 0, SGS_TIME_SELECTION_LANES = 1 };

typedef struct {
    int32_t track;
    uint8_t controller;
} SgsLane;

typedef struct {
    uint32_t startTick;
    uint32_t endTick;
    int32_t scope;
    int32_t laneCount;
    uint8_t tempo;
} SgsTimeSelection;

// Complete session state (spec §3): every push is authoritative, never a
// delta. Note-selection tokens are raw NoteId tokens, document-scoped.
typedef struct {
    uint64_t sessionId;
    uint64_t revision;
    int32_t primaryTrack;
    uint32_t trackScope;
    int32_t selectedNoteCount;
    SgsTimeSelection timeSelection;
    uint32_t muteMask;
    uint32_t soloMask;
} SgsSessionState;

typedef void (*SgsDeliveryFn)(const SgsSessionState *state, const uint64_t *noteIds,
                              const SgsLane *lanes, void *context);
typedef struct {
    SgsDeliveryFn fn;
    void *context;
} SgsDelivery;

// GUI-thread-only live endpoints. Slots and callback contexts are borrowed.
void sgs_register_feed(uint64_t session_id, SgsDelivery *delivery);
void sgs_unregister_feed(uint64_t session_id);
bool sgs_set_delivery(uint64_t session_id, SgsDeliveryFn fn, void *context);
void sgs_clear_delivery(uint64_t session_id);

#ifdef __cplusplus
}
#endif
