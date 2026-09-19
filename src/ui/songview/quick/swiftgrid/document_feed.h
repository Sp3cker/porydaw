#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t noteId; // raw NoteId token; document-scoped, never persisted to MIDI
    int32_t trackIndex;
    int32_t key;
    uint32_t onTick;
    uint32_t durationTicks;
    int32_t velocity;
} SgdNote;

typedef struct {
    uint32_t startTick;
    uint8_t numerator;
    uint8_t denomPow2;
} SgdTimeSignature;

typedef struct {
    uint64_t documentId;
    uint64_t revision;
    int32_t ticksPerBeat;
    int32_t trackCount;
    int32_t noteCount;
    int32_t timeSignatureCount;
} SgdDocumentHeader;

typedef void (*SgdDeliveryFn)(const SgdDocumentHeader *header, const SgdNote *notes,
                              const SgdTimeSignature *signatures, void *context);
typedef struct {
    SgdDeliveryFn fn;
    void *context;
} SgdDelivery;

// GUI-thread-only live endpoints. Slots and callback contexts are borrowed.
void sgd_register_feed(uint64_t document_id, SgdDelivery *delivery);
void sgd_unregister_feed(uint64_t document_id);
bool sgd_set_delivery(uint64_t document_id, SgdDeliveryFn fn, void *context);
void sgd_clear_delivery(uint64_t document_id);

#ifdef __cplusplus
}
#endif
