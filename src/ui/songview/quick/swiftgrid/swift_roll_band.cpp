#include "swift_roll_band.h"

#include <cstdlib>
#include <unordered_map>

#include <QCoreApplication>
#include <QThread>

#include "ui/keymap.h"
#include "ui/pitchprojection.h"
#include "ui/songview.h"
#include "ui/songview/editactions.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timecamera.h"

namespace {

// The sgb_ endpoints are GUI-thread-only by contract (slots and callback
// contexts are borrowed from GUI-thread objects). Fail loudly on a
// cross-thread delivery instead of corrupting the borrowed slot.
inline void assertGuiThread()
{
    Q_ASSERT(QCoreApplication::instance() &&
             QCoreApplication::instance()->thread() == QThread::currentThread());
}

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
    assertGuiThread();
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
    assertGuiThread();
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
    assertGuiThread();
    const auto it = endpoints().find(target_id);
    if (it == endpoints().end() || !it->second->leave)
        return;
    const SgbSurface recipient = *it->second;
    recipient.leave(recipient.context);
}

void sgb_deliver_cancel(uint64_t target_id, int32_t reason)
{
    assertGuiThread();
    const auto it = endpoints().find(target_id);
    if (it == endpoints().end() || !it->second->cancel)
        return;
    const SgbSurface recipient = *it->second;
    recipient.cancel(reason, recipient.context);
}

uint8_t sgb_gesture_active(uint64_t target_id)
{
    assertGuiThread();
    const auto it = endpoints().find(target_id);
    if (it == endpoints().end() || !it->second->gestureActive)
        return 0;
    const SgbSurface recipient = *it->second;
    return recipient.gestureActive(recipient.context);
}

namespace songview {

SwiftRollBand::SwiftRollBand(SongView &view, SwiftGridKeyRouter &router)
    : m_view(view)
    , m_targetId(router.targetId())
{
    sgb_register_surface(m_targetId, &m_surface);
}

SwiftRollBand::~SwiftRollBand()
{
    sgb_unregister_surface(m_targetId);
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
    return sgb_gesture_active(m_targetId) != 0;
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
    return sgb_deliver_pointer(m_targetId, kind, &event) != 0;
}

bool SwiftRollBand::pointerPress(const TimelinePointerInput &input)
{
    // No timeline, no gesture: PianoRoll::pointerPress declines everything
    // here, and Swift has no timeline fact on the seam (INV-3), so the host
    // enforces it before delivery instead of absorbing into a void.
    if (!m_view.timeline())
        return false;
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
    if (!m_view.timeline())
        return false;
    return deliverPointer(SGB_POINTER_DOUBLE_CLICK, input);
}

void SwiftRollBand::pointerLeave()
{
    sgb_deliver_leave(m_targetId);
}

bool SwiftRollBand::wheel(const TimelineWheelInput &input)
{
    const SgbWheelEvent event = wheelEvent(input);
    return sgb_deliver_wheel(m_targetId, &event) != 0;
}

bool SwiftRollBand::keyPress(const TimelineKeyInput &input)
{
    // Bare modifier keys never reach command lookup: like PianoRoll::keyPress
    // they only refresh the note-text layer (chord-spelling labels follow the
    // held modifiers) and decline, so the key returns to the fallback order.
    // PianoRoll reaches the retained host through SongView's private
    // requestPianoRollQuickUpdate via friendship; the band takes the public
    // equivalent — quickView()->requestUpdate() — which is exactly what the
    // private forwarder calls.
    if (!input.autoRepeat && keymap::Registry::isModifierKey(input.key)) {
        if (TimelineQuickView *const quick = m_view.quickView())
            quick->requestUpdate(PianoRollQuickDirty::NoteText);
        return false;
    }
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
    return sgk_deliver(m_targetId, &facts);
}

bool SwiftRollBand::keyRelease(const TimelineKeyInput &input)
{
    // Symmetric with PianoRoll::keyRelease: releasing a bare modifier
    // refreshes the note-text layer the press dirtied.
    if (!input.autoRepeat && keymap::Registry::isModifierKey(input.key)) {
        if (TimelineQuickView *const quick = m_view.quickView())
            quick->requestUpdate(PianoRollQuickDirty::NoteText);
    }
    return TimelineBandInteraction::keyRelease(input);
}

void SwiftRollBand::inputCancelled(TimelineInputCancelReason reason)
{
    sgb_deliver_cancel(m_targetId, static_cast<int32_t>(reason));
}

void SwiftRollBand::handleTransferredWindowDeath()
{
    m_host = nullptr;
}

} // namespace songview
