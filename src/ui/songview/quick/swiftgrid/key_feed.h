#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// The key-delivery direction of the writable seam (spec.md §4): the host
// performs window-tier arbitration and registry matching exactly as today
// (keymap::Registry + the handleEditKey successor path) and delivers the
// resolved command id into the Swift band. Swift evaluates band-side
// eligibility from the sgp_ policy mirror + sgs_ state and answers
// synchronously; unhandled keys return to the existing band fallback order
// (timelinequickview_keyrouting). No QKeyEvents, no QML shortcuts, no second
// dispatcher (INV-1/3).
//
// Surface origin values mirror SongView::EditKeyOrigin declaration order.
enum { SGK_ORIGIN_TIMELINE = 0, SGK_ORIGIN_EVENT_LIST = 1 };

// Synchronous band-side eligibility query for one registry-matched command.
// command is a SongView::EditCommand ordinal; modifiers carry
// Qt::KeyboardModifiers as int (already resolved into command, passed through
// for arrival observability); commandAvailable is the host's live
// editCommandAvailable answer for the command. Returns 1 when Swift consumes
// the key (no further host action) and 0 when the key returns to the existing
// fallback order. Swift returns 1 only for consume verdicts; execute and
// decline verdicts both defer so execution stays in the single host tier
// (INV-2): execute runs through the normal handleEditKey path, decline falls
// through to it the same way.
typedef struct {
    int32_t command;
    int32_t modifiers;
    int32_t origin;
    uint8_t autoRepeat;
    uint8_t commandAvailable;
} SgkKeyFacts;

typedef uint8_t (*SgcKeyDeliveryFn)(const SgkKeyFacts *facts, void *context);
typedef struct {
    SgcKeyDeliveryFn fn;
    void *context;
} SgkDelivery;

// GUI-thread-only live endpoints. Slots and callback contexts are borrowed.
// Endpoints are keyed by the SwiftGridKeyRouter target id that owns them.
void sgk_register_delivery(uint64_t target_id, SgkDelivery *delivery);
void sgk_unregister_delivery(uint64_t target_id);
bool sgk_set_delivery(uint64_t target_id, SgcKeyDeliveryFn fn, void *context);
void sgk_clear_delivery(uint64_t target_id);
// Synchronous on the GUI thread. False when no recipient is bound or facts is
// null (the caller falls back); otherwise Swift's consume/defer answer.
bool sgk_deliver(uint64_t target_id, const SgkKeyFacts *facts);

#ifdef __cplusplus
}

#include <cstdint>

namespace songview {

// C++ bridge from the host key path to the sgk_ delivery slot. The router
// mints one target id, owns the endpoint registration, and forwards one
// synchronous delivery per host key. The SongView and the Swift recipient both
// outlive the router; the router never retains either.
class SwiftGridKeyRouter final
{
  public:
    SwiftGridKeyRouter();
    ~SwiftGridKeyRouter();

    SwiftGridKeyRouter(const SwiftGridKeyRouter &) = delete;
    SwiftGridKeyRouter &operator=(const SwiftGridKeyRouter &) = delete;

    uint64_t targetId() const { return m_targetId; }
    SgkDelivery *delivery() { return &m_delivery; }
    // Swift's consume/defer answer; false when unbound (caller falls back).
    bool deliver(const SgkKeyFacts &facts) const;

  private:
    const uint64_t m_targetId;
    SgkDelivery m_delivery{};
};

} // namespace songview
#endif
