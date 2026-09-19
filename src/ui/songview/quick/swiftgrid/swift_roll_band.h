#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "../swift-grid-prototype/native/window_cancel.h"
#include "key_feed.h"

#ifdef __cplusplus
extern "C" {
#endif

// The Swift roll's band surface (spec.md §4): pointer, wheel, leave, and
// cancel events cross as plain values. Ticks and keys are band-local,
// computed C++-side with the same TimeCamera/PitchProjection math the C++
// bands use; Swift never sees the window (INV-3).
//
// Pointer kinds and surface values are order-frozen; the surface values mirror
// TimelineInputSurface declaration order.
enum {
    SGB_POINTER_PRESS = 0,
    SGB_POINTER_MOVE = 1,
    SGB_POINTER_RELEASE = 2,
    SGB_POINTER_DOUBLE_CLICK = 3
};
enum { SGB_SURFACE_PLOT = 0, SGB_SURFACE_GUTTER = 1 };
// Gutter-local x is not a content coordinate (the C++ roll never interprets
// it as one: gutter presses audition by key). Gutter samples forward the key
// with this tick in place of a tick; plot ticks from tickAtContentX are
// always >= 0, so the sentinel is unambiguous.
#define SGB_INVALID_TICK (-1.0)

typedef struct {
    double tick;       // SGB_INVALID_TICK for gutter samples (gutter-local x is not
                       // a content coordinate); plot ticks are always >= 0.
    int32_t key;       // yToPitch result; -1 when the row maps to no pitch
    int32_t button;    // Qt::MouseButton as int
    int32_t buttons;   // Qt::MouseButtons as int
    int32_t modifiers; // Qt::KeyboardModifiers as int
    int32_t surface;
} SgbPointerEvent;

typedef struct {
    double tick; // SGB_INVALID_TICK for gutter samples; plot ticks >= 0.
    int32_t key;
    int32_t pixelDeltaX;
    int32_t pixelDeltaY;
    int32_t angleDeltaX;
    int32_t angleDeltaY;
    int32_t modifiers;
    int32_t surface;
    uint8_t inverted;
} SgbWheelEvent;

// 1 when Swift handles the sample, 0 when it declines. A declined pointer
// sample keeps the existing band fallback (absorption is per-sample verdicts,
// not per-callback wiring).
typedef uint8_t (*SgbPointerFn)(int32_t kind, const SgbPointerEvent *event, void *context);
typedef uint8_t (*SgbWheelFn)(const SgbWheelEvent *event, void *context);
typedef void (*SgbLeaveFn)(void *context);
// Reuses the existing sgw_ filter type so hide/deactivate keep the four named
// TimelineInputCancelReason values end to end.
typedef SgwInputCancelledFn SgbCancelFn;
typedef uint8_t (*SgbGestureQueryFn)(void *context);
typedef struct {
    SgbPointerFn pointer;
    SgbWheelFn wheel;
    SgbLeaveFn leave;
    SgbCancelFn cancel;
    SgbGestureQueryFn gestureActive;
    void *context;
} SgbSurface;

// GUI-thread-only live endpoints. Slots and callback contexts are borrowed.
// Endpoints are keyed by the SwiftGridKeyRouter target id the band shares;
// ids must come from SwiftGridKeyRouter::targetId() (the router owns the
// registration lifetime, so only its ids are ever present).
void sgb_register_surface(uint64_t target_id, SgbSurface *surface);
void sgb_unregister_surface(uint64_t target_id);
bool sgb_set_surface(uint64_t target_id, const SgbSurface *surface);
void sgb_clear_surface(uint64_t target_id);
// Delivery entry points. Pointer/wheel deliveries return Swift's
// handled/declined verdict (0 when unbound); cancel and leave are
// notifications. gestureActive answers from the Swift surface (0 when
// unbound).
uint8_t sgb_deliver_pointer(uint64_t target_id, int32_t kind, const SgbPointerEvent *event);
uint8_t sgb_deliver_wheel(uint64_t target_id, const SgbWheelEvent *event);
void sgb_deliver_leave(uint64_t target_id);
void sgb_deliver_cancel(uint64_t target_id, int32_t reason);
uint8_t sgb_gesture_active(uint64_t target_id);

#ifdef __cplusplus
}

#include "ui/songview/quick/timelineinput.h"

#include <QObject>

class SongView;

namespace songview {

// SwiftRollBand is the Swift roll's TimelineBandInteraction peer (spec.md
// §4-5). It forwards pointer press/move/release/double-click, wheel, and leave
// as plain SgbPointerEvent/SgbWheelEvent values, answers band-side key input
// with registry-matched command ids through the sgk_ seam, reports
// gesture-active from the Swift surface, and delivers inputCancelled as the
// four named cancel reasons through the existing sgw_ filter mapping.
//
// The SongView and the TimelineInputHost outlive the band; both are borrowed,
// never retained. The sgb_/sgk_ endpoint id is cached by value: the router is
// only a construction witness, so endpoint unregistration in the destructor
// never depends on another object's lifetime or member order.
class SwiftRollBand final : public TimelineBandInteraction
{
  public:
    SwiftRollBand(SongView &view, SwiftGridKeyRouter &router);
    ~SwiftRollBand() override;

    Q_DISABLE_COPY_MOVE(SwiftRollBand)

    uint64_t targetId() const { return m_targetId; }

    // Only the plot input (timelineRollInput, bound with attachHost=true)
    // ever attaches: the gutter input (timelineRollGutterInput) binds with
    // attachHost=false, so the host pointer always names the plot item.
    void attachInputHost(TimelineInputHost &host) override;

    void detachInputHost(TimelineInputHost &host) override;
    bool gestureActive() const override;
    bool pointerPress(const TimelinePointerInput &input) override;
    bool pointerMove(const TimelinePointerInput &input) override;
    bool pointerRelease(const TimelinePointerInput &input) override;
    bool pointerDoubleClick(const TimelinePointerInput &input) override;
    void pointerLeave() override;
    bool wheel(const TimelineWheelInput &input) override;
    bool keyPress(const TimelineKeyInput &input) override;
    bool keyRelease(const TimelineKeyInput &input) override;
    void inputCancelled(TimelineInputCancelReason reason) override;
    void handleTransferredWindowDeath();

  private:
    SgbPointerEvent pointerEvent(const TimelinePointerInput &input) const;
    SgbWheelEvent wheelEvent(const TimelineWheelInput &input) const;
    bool deliverPointer(int32_t kind, const TimelinePointerInput &input) const;

    SongView &m_view;
    const uint64_t m_targetId;
    TimelineInputHost *m_host = nullptr;
    SgbSurface m_surface{};
};

} // namespace songview
#endif
