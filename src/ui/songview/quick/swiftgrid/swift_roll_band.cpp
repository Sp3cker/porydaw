#include "swift_roll_band.h"

#include <cstdlib>
#include <unordered_map>

#include "ui/pitchprojection.h"
#include "ui/songview.h"
#include "ui/songview/editactions.h"
#include "ui/songview/timecamera.h"

namespace {

std::unordered_map<uint64_t, SgbSurface *> &endpoints()
{
    static std::unordered_map<uint64_t, SgbSurface *> registry;
    return registry;
}

bool slotOccupied(const SgbSurface &slot)
{
    return slot.pointer || slot.wheel || slot.leave || slot.cancel || slot.gestureActive ||
           slot.context;
}

} // namespace

void sgb_register_surface(uint64_t target_id, SgbSurface *surface)
{
    if (target_id == 0 || !surface || slotOccupied(*surface) ||
        !endpoints().emplace(target_id, surface).second)
        std::abort();
}

void sgb_unregister_surface(uint64_t target_id)
{
    sgb_clear_surface(target_id);
    endpoints().erase(target_id);
}

bool sgb_set_surface(uint64_t target_id, const SgbSurface *surface)
{
    const auto it = endpoints().find(target_id);
    if (it == endpoints().end() || !surface)
        return false;
    SgbSurface &slot = *it->second;
    if (slotOccupied(slot))
        return false;
    slot = *surface;
    return true;
}

void sgb_clear_surface(uint64_t target_id)
{
    const auto it = endpoints().find(target_id);
    if (it != endpoints().end())
        *it->second = {};
}

uint8_t sgb_deliver_pointer(uint64_t target_id, int32_t kind, const SgbPointerEvent *event)
{
    if (!event)
        return 0;
    const auto it = endpoints().find(target_id);
    if (it == endpoints().end() || !it->second->pointer)
        return 0;
    // Copy the slot before calling out: the recipient may disconnect
    // synchronously.
    const SgbSurface recipient = *it->second;
    return recipient.pointer(kind, event, recipient.context);
}

uint8_t sgb_deliver_wheel(uint64_t target_id, const SgbWheelEvent *event)
{
    if (!event)
        return 0;
    const auto it = endpoints().find(target_id);
    if (it == endpoints().end() || !it->second->wheel)
        return 0;
    const SgbSurface recipient = *it->second;
    return recipient.wheel(event, recipient.context);
}

void sgb_deliver_leave(uint64_t target_id)
{
    const auto it = endpoints().find(target_id);
    if (it == endpoints().end() || !it->second->leave)
        return;
    const SgbSurface recipient = *it->second;
    recipient.leave(recipient.context);
}

void sgb_deliver_cancel(uint64_t target_id, int32_t reason)
{
    const auto it = endpoints().find(target_id);
    if (it == endpoints().end() || !it->second->cancel)
        return;
    const SgbSurface recipient = *it->second;
    recipient.cancel(reason, recipient.context);
}

uint8_t sgb_gesture_active(uint64_t target_id)
{
    const auto it = endpoints().find(target_id);
    if (it == endpoints().end() || !it->second->gestureActive)
        return 0;
    const SgbSurface recipient = *it->second;
    return recipient.gestureActive(recipient.context);
}

namespace songview {

SwiftRollBand::SwiftRollBand(SongView &view, SwiftGridKeyRouter &router)
    : m_view(view)
    , m_router(router)
{
    sgb_register_surface(m_router.targetId(), &m_surface);
}

SwiftRollBand::~SwiftRollBand()
{
    sgb_unregister_surface(m_router.targetId());
}

void SwiftRollBand::attachInputHost(TimelineInputHost &host)
{
    if (!m_host)
        m_host = &host;
    else
        Q_ASSERT(m_host == &host);
}

void SwiftRollBand::detachInputHost(TimelineInputHost &host)
{
    if (m_host == &host)
        m_host = nullptr;
}

bool SwiftRollBand::gestureActive() const
{
    return sgb_gesture_active(m_router.targetId()) != 0;
}

SgbPointerEvent SwiftRollBand::pointerEvent(const TimelinePointerInput &input) const
{
    const TimeCamera &camera = m_view.camera();
    const qreal dpr = m_host ? m_host->devicePixelRatio() : qreal(1);
    SgbPointerEvent event{};
    // Gutter-local x is not a content coordinate: forward the key with the
    // invalid-tick sentinel, mirroring the C++ roll (gutter presses audition
    // by key; plot position stays invalid).
    event.tick = input.surface == TimelineInputSurface::Gutter
                     ? SGB_INVALID_TICK
                     : camera.tickAtContentX(input.position.x());
    event.key = m_view.pitchProjection().yToPitch(input.position.y(), camera.keyHeight(),
                                                  camera.scrollY(), dpr);
    event.button = static_cast<int32_t>(input.button);
    event.buttons = static_cast<int32_t>(input.buttons);
    event.modifiers = static_cast<int32_t>(input.modifiers);
    event.surface =
        input.surface == TimelineInputSurface::Gutter ? SGB_SURFACE_GUTTER : SGB_SURFACE_PLOT;
    return event;
}

SgbWheelEvent SwiftRollBand::wheelEvent(const TimelineWheelInput &input) const
{
    const TimeCamera &camera = m_view.camera();
    const qreal dpr = m_host ? m_host->devicePixelRatio() : qreal(1);
    SgbWheelEvent event{};
    event.tick = input.surface == TimelineInputSurface::Gutter
                     ? SGB_INVALID_TICK
                     : camera.tickAtContentX(input.position.x());
    event.key = m_view.pitchProjection().yToPitch(input.position.y(), camera.keyHeight(),
                                                  camera.scrollY(), dpr);
    event.pixelDeltaX = input.pixelDelta.x();
    event.pixelDeltaY = input.pixelDelta.y();
    event.angleDeltaX = input.angleDelta.x();
    event.angleDeltaY = input.angleDelta.y();
    event.modifiers = static_cast<int32_t>(input.modifiers);
    event.surface =
        input.surface == TimelineInputSurface::Gutter ? SGB_SURFACE_GUTTER : SGB_SURFACE_PLOT;
    event.inverted = input.inverted ? 1 : 0;
    return event;
}

bool SwiftRollBand::deliverPointer(int32_t kind, const TimelinePointerInput &input) const
{
    const SgbPointerEvent event = pointerEvent(input);
    return sgb_deliver_pointer(m_router.targetId(), kind, &event) != 0;
}

bool SwiftRollBand::pointerPress(const TimelinePointerInput &input)
{
    return deliverPointer(SGB_POINTER_PRESS, input);
}

bool SwiftRollBand::pointerMove(const TimelinePointerInput &input)
{
    return deliverPointer(SGB_POINTER_MOVE, input);
}

bool SwiftRollBand::pointerRelease(const TimelinePointerInput &input)
{
    return deliverPointer(SGB_POINTER_RELEASE, input);
}

bool SwiftRollBand::pointerDoubleClick(const TimelinePointerInput &input)
{
    return deliverPointer(SGB_POINTER_DOUBLE_CLICK, input);
}

void SwiftRollBand::pointerLeave()
{
    sgb_deliver_leave(m_router.targetId());
}

bool SwiftRollBand::wheel(const TimelineWheelInput &input)
{
    const SgbWheelEvent event = wheelEvent(input);
    return sgb_deliver_wheel(m_router.targetId(), &event) != 0;
}

bool SwiftRollBand::keyPress(const TimelineKeyInput &input)
{
    const EditActions *const actions = m_view.editActions();
    if (!actions)
        return false;
    const std::optional<SongView::EditCommand> command =
        actions->editorCommandForKey(input.key, input.modifiers);
    if (!command)
        return false;
    SgkKeyFacts facts{};
    facts.command = static_cast<int32_t>(*command);
    facts.modifiers = static_cast<int32_t>(input.modifiers);
    facts.origin = SGK_ORIGIN_TIMELINE;
    facts.autoRepeat = input.autoRepeat ? 1 : 0;
    facts.commandAvailable = m_view.editCommandAvailable(*command) ? 1 : 0;
    // Only consume verdicts swallow the key. Execute and decline verdicts defer
    // (false) so the key returns to the existing fallback order and execution
    // stays in the single host tier.
    return m_router.deliver(facts);
}

bool SwiftRollBand::keyRelease(const TimelineKeyInput &input)
{
    return TimelineBandInteraction::keyRelease(input);
}

void SwiftRollBand::inputCancelled(TimelineInputCancelReason reason)
{
    sgb_deliver_cancel(m_router.targetId(), static_cast<int32_t>(reason));
}

void SwiftRollBand::handleTransferredWindowDeath()
{
    m_host = nullptr;
}

} // namespace songview
