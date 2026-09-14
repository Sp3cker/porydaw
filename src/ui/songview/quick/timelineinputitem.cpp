#include "ui/songview/quick/timelineinputitem.h"
#include "ui/mousehints/hintprofiles.h"

#include "ui/mousehints/mousehints.h"

#include <QCoreApplication>
#include <QCursor>
#include <QFocusEvent>
#include <QGuiApplication>
#include <QHoverEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQuickWindow>
#include <QWheelEvent>

namespace songview {

namespace {

TimelinePointerInput pointerInput(const QMouseEvent &event, TimelineInputSurface surface,
                                  TimelineInputHost *host)
{
    return TimelinePointerInput{
        .position = event.position(),
        .globalPosition = event.globalPosition(),
        .button = event.button(),
        .buttons = event.buttons(),
        .modifiers = event.modifiers(),
        .surface = surface,
        .host = host,
    };
}

TimelinePointerInput pointerInput(const QHoverEvent &event, TimelineInputSurface surface,
                                  TimelineInputHost *host)
{
    return TimelinePointerInput{
        .position = event.position(),
        .globalPosition = event.globalPosition(),
        .button = event.button(),
        .buttons = event.buttons(),
        .modifiers = event.modifiers(),
        .surface = surface,
        .host = host,
    };
}

TimelineWheelInput wheelInput(const QWheelEvent &event, TimelineInputSurface surface,
                              TimelineInputHost *host)
{
    return TimelineWheelInput{
        .position = event.position(),
        .globalPosition = event.globalPosition(),
        .pixelDelta = event.pixelDelta(),
        .angleDelta = event.angleDelta(),
        .modifiers = event.modifiers(),
        .phase = event.phase(),
        .inverted = event.inverted(),
        .surface = surface,
        .host = host,
    };
}

TimelineKeyInput keyInput(const QKeyEvent &event)
{
    return TimelineKeyInput{
        .key = event.key(),
        .modifiers = event.modifiers(),
        .text = event.text(),
        .autoRepeat = event.isAutoRepeat(),
    };
}

} // namespace
TimelineGestureScrollbar::TimelineGestureScrollbar(QQuickItem *parent) : QQuickItem(parent) {}

bool TimelineGestureScrollbar::gestureActive() const noexcept
{
    return m_gestureActive;
}

void TimelineGestureScrollbar::setGestureActive(bool active)
{
    if (m_gestureActive == active)
        return;
    m_gestureActive = active;
    emit gestureActiveChanged();
}

TimelineInputItem::TimelineInputItem(QQuickItem *parent)
    : QQuickItem(parent)
    , m_hostFont(qGuiApp->font())
    , m_hostPalette(qGuiApp->palette())
{
    setAcceptedMouseButtons(Qt::AllButtons);
    setAcceptHoverEvents(true);
}

TimelineInputItem::~TimelineInputItem()
{
    clearKeyPolicy();
    // Clear only this item's ownership; the guarded borrow never recreates
    // the service during application teardown.
    clearMouseHint();
    setInteraction(nullptr);
}

void TimelineInputItem::setInteraction(TimelineBandInteraction *interaction,
                                       TimelineInputSurface surface, bool attachHost)
{
    if (!interaction || m_interaction != interaction)
        clearKeyPolicy();
    if (m_interaction == interaction && m_surface == surface && m_attachHost == attachHost)
        return;
    // A detach or rebind ends this item's hint ownership; the next idle
    // hover pass or resync republishes from the new interaction.
    clearMouseHint();

    if (m_attachedInputHost) {
        Q_ASSERT(m_interaction);
        m_interaction->detachInputHost(*this);
        m_attachedInputHost = false;
    }
    m_interaction = interaction;
    m_surface = surface;
    m_attachHost = attachHost;
    if (m_interaction && m_attachHost) {
        m_interaction->attachInputHost(*this);
        m_attachedInputHost = true;
    }
}

TimelineBandInteraction *TimelineInputItem::interaction() const noexcept
{
    return m_interaction;
}

void TimelineInputItem::setKeyPolicy(TimelineKeyPolicy policy)
{
    m_keyPolicy = std::move(policy);
}

void TimelineInputItem::clearKeyPolicy()
{
    m_keyPolicy = {};
}

void TimelineInputItem::notifyHostAppearanceChanged()
{
    if (m_interaction)
        m_interaction->hostAppearanceChanged();
}
void TimelineInputItem::setHostAppearance(const QFont &font, const QPalette &palette)
{
    m_hostFont = font;
    m_hostPalette = palette;
}

QString TimelineInputItem::accessibilityDescription() const
{
    return m_accessibilityDescription;
}

QRectF TimelineInputItem::bounds() const
{
    return QRectF{0.0, 0.0, width(), height()};
}

qreal TimelineInputItem::devicePixelRatio() const
{
    return window() ? window()->effectiveDevicePixelRatio() : qGuiApp->devicePixelRatio();
}

QFont TimelineInputItem::font() const
{
    return m_hostFont;
}

QPalette TimelineInputItem::palette() const
{
    return m_hostPalette;
}

// Popup positioning and hit queries map through the attached Quick window;
// a detached item cannot produce meaningful coordinates, so assert the
// invariant instead of silently falling back to identity mapping.
QPointF TimelineInputItem::mapFromGlobal(QPointF position) const
{
    QQuickWindow *const itemWindow = window();
    Q_ASSERT(itemWindow);
    return mapFromScene(itemWindow->mapFromGlobal(position));
}

QPointF TimelineInputItem::mapToGlobal(QPointF position) const
{
    QQuickWindow *const itemWindow = window();
    Q_ASSERT(itemWindow);
    return itemWindow->mapToGlobal(mapToScene(position));
}

void TimelineInputItem::requestFocus(Qt::FocusReason reason)
{
    QQuickWindow *const itemWindow = window();
    if (!itemWindow)
        return;
    forceActiveFocus(reason);
    itemWindow->requestActivate();
}

void TimelineInputItem::setCursor(const QCursor &cursor)
{
    QQuickItem::setCursor(cursor);
}

void TimelineInputItem::clearCursor()
{
    unsetCursor();
}

void TimelineInputItem::releasePointerGrab()
{
    ungrabMouse();
}

void TimelineInputItem::setAccessibilityDescription(const QString &description)
{
    if (m_accessibilityDescription == description)
        return;
    m_accessibilityDescription = description;
    emit accessibilityDescriptionChanged();
}

ui::MouseHints *TimelineInputItem::mouseHints()
{
    // Borrow once and cache through QPointer. instance() asserts on a dead
    // or closing application, so a late borrow during teardown stays null
    // instead of recreating the singleton.
    if (!m_mouseHints && qApp && !QCoreApplication::closingDown())
        m_mouseHints = &ui::MouseHints::instance();
    return m_mouseHints;
}

void TimelineInputItem::clearMouseHint()
{
    if (ui::MouseHints *const hints = mouseHints())
        hints->clear(this);
}

bool TimelineInputItem::hintSourceActive() const noexcept
{
    if (m_hovered)
        return true;
    const QQuickWindow *const itemWindow = window();
    return itemWindow && itemWindow->mouseGrabberItem() == this;
}

bool TimelineInputItem::cursorInside() const
{
    // mapFromGlobal asserts a live window; a detached item cannot contain
    // the cursor.
    return window() && bounds().contains(mapFromGlobal(QCursor::pos()));
}

void TimelineInputItem::setMouseHint(ui::hint_profiles::Id profile)
{
    // Bands call this from inside an idle hover pass; the flag lets the
    // adapter claim its empty profile only when no band claimed at all.
    m_hintDispatchClaimed = true;
    ui::MouseHints *const hints = mouseHints();
    if (!hints || m_hintMuted || !hintSourceActive())
        return;
    hints->claim(this, profile);
}

void TimelineInputItem::refreshMouseHint(ui::hint_profiles::Id profile)
{
    // Non-claiming stationary update: only an item that still owns the
    // display may republish, so a replaced or unhovered source cannot
    // reacquire through this path. Participating in a hover pass still
    // counts as a claim so the adapter does not overwrite it with empty.
    m_hintDispatchClaimed = true;
    ui::MouseHints *const hints = mouseHints();
    if (!hints || hints->currentSource() != this)
        return;
    hints->claim(this, profile);
}

void TimelineInputItem::setHintMuted(bool muted)
{
    if (m_hintMuted == muted)
        return;
    m_hintMuted = muted;
    // Muting suppresses even empty claims; clearing is always source-checked.
    if (muted)
        clearMouseHint();
}

void TimelineInputItem::resyncMouseHint()
{
    // Explicit reacquisition, not refresh: only a visible, windowed,
    // unmuted, still-hovered item inside the current input scope with no
    // exclusive grab and no active domain gesture may reclaim through the
    // idle hover pass at the actual cursor position.
    if (m_hintMuted || !m_hovered || !isVisible())
        return;
    ui::MouseHints *const hints = mouseHints();
    if (!hints || !hints->allowsNativeInput(this))
        return;
    QQuickWindow *const itemWindow = window();
    if (!itemWindow || itemWindow->mouseGrabberItem())
        return;
    const QPointF globalPosition = QCursor::pos();
    const QPointF position = mapFromGlobal(globalPosition);
    if (!bounds().contains(position))
        return;
    if (m_interaction && m_interaction->gestureActive())
        return;
    dispatchIdleMouseHint(TimelinePointerInput{
        .position = position,
        .globalPosition = globalPosition,
        .button = Qt::NoButton,
        .buttons = Qt::NoButton,
        .modifiers = QGuiApplication::keyboardModifiers(),
        .surface = m_surface,
        .host = this,
    });
}

bool TimelineInputItem::dispatchIdleMouseHint(const TimelinePointerInput &input)
{
    m_hintDispatchClaimed = false;
    const bool handled = m_interaction && m_interaction->pointerMove(input);
    // A band that published nothing — including a pure no-hint interaction —
    // leaves this item unclaimed; the adapter claims its empty profile once
    // per pass rather than churning empty-then-text on every move.
    if (!m_hintDispatchClaimed)
        setMouseHint(ui::hint_profiles::Id::Empty);
    return handled;
}

void TimelineInputItem::settleMouseHintAfterUngrab()
{
    // The grab is already gone or stolen: settle by actual containment.
    // Inside recomputes the idle hover pass (guarded by resync); outside
    // ends this item's ownership.
    if (cursorInside())
        resyncMouseHint();
    else
        clearMouseHint();
}

void TimelineInputItem::mousePressEvent(QMouseEvent *event)
{
    if (!m_interaction || !m_interaction->pointerPress(pointerInput(*event, m_surface, this))) {
        event->ignore();
        return;
    }
    event->accept();
}

void TimelineInputItem::mouseDoubleClickEvent(QMouseEvent *event)
{
    if (!m_interaction ||
        !m_interaction->pointerDoubleClick(pointerInput(*event, m_surface, this))) {
        event->ignore();
        return;
    }
    event->accept();
}

void TimelineInputItem::mouseMoveEvent(QMouseEvent *event)
{
    if (!m_interaction || !m_interaction->pointerMove(pointerInput(*event, m_surface, this))) {
        event->ignore();
        return;
    }
    event->accept();
}

void TimelineInputItem::mouseReleaseEvent(QMouseEvent *event)
{
    if (!m_interaction || !m_interaction->pointerRelease(pointerInput(*event, m_surface, this))) {
        event->ignore();
        return;
    }
    event->accept();
}

void TimelineInputItem::hoverEnterEvent(QHoverEvent *event)
{
    m_hovered = true;
    // First idle entry forwards the existing hover computation once. An
    // active domain gesture keeps its press-time target, so the entry is
    // accepted without dispatching a move into it.
    if (m_interaction && !m_interaction->gestureActive()) {
        if (dispatchIdleMouseHint(pointerInput(*event, m_surface, this)))
            event->accept();
        else
            event->ignore();
        return;
    }
    // No interaction, or a live gesture: the adapter still claims its empty
    // profile for a band-less surface, and the event keeps the base
    // implementation's acceptance.
    if (!m_interaction)
        dispatchIdleMouseHint(pointerInput(*event, m_surface, this));
    event->accept();
}

void TimelineInputItem::hoverMoveEvent(QHoverEvent *event)
{
    // Delivery implies membership; keep the flag honest even if an enter
    // was missed.
    m_hovered = true;
    if (!m_interaction || !m_interaction->pointerMove(pointerInput(*event, m_surface, this))) {
        event->ignore();
        return;
    }
    event->accept();
}

void TimelineInputItem::hoverLeaveEvent(QHoverEvent *event)
{
    // Termination, not a handled/unhandled query: the hover has ended
    // regardless of the interaction's state.
    m_hovered = false;
    if (m_interaction)
        m_interaction->pointerLeave();
    // An own exclusive grab retains its source: Qt freezes ordinary hover
    // during the grab and the ungrab settle decides by actual containment.
    const QQuickWindow *const itemWindow = window();
    if (!itemWindow || itemWindow->mouseGrabberItem() != this)
        clearMouseHint();
    event->accept();
}

void TimelineInputItem::wheelEvent(QWheelEvent *event)
{
    if (!m_interaction || !m_interaction->wheel(wheelInput(*event, m_surface, this))) {
        event->ignore();
        return;
    }
    event->accept();
}

void TimelineInputItem::keyPressEvent(QKeyEvent *event)
{
    const TimelineKeyInput input = keyInput(*event);
    // Restricted local interaction handling first, then the shared song
    // policy. Either claiming the key accepts the event exactly once; an
    // unclaimed key is ignored so the Quick root fallback can route it.
    if ((m_interaction && m_interaction->keyPress(input)) ||
        (m_keyPolicy.press && m_keyPolicy.press(input))) {
        event->accept();
        return;
    }
    event->ignore();
}

void TimelineInputItem::keyReleaseEvent(QKeyEvent *event)
{
    const TimelineKeyInput input = keyInput(*event);
    if ((m_interaction && m_interaction->keyRelease(input)) ||
        (m_keyPolicy.release && m_keyPolicy.release(input))) {
        event->accept();
        return;
    }
    event->ignore();
}

void TimelineInputItem::focusOutEvent(QFocusEvent *event)
{
    if (m_interaction)
        m_interaction->inputCancelled(TimelineInputCancelReason::FocusLost);
    QQuickItem::focusOutEvent(event);
}

void TimelineInputItem::mouseUngrabEvent()
{
    if (m_interaction)
        m_interaction->inputCancelled(TimelineInputCancelReason::PointerUngrabbed);
    // Normal and cancelled/stolen ungrabs settle the same way: actual
    // cursor containment keeps/refreshes the source, outside clears it.
    settleMouseHintAfterUngrab();
}

void TimelineInputItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (m_interaction && newGeometry.size() != oldGeometry.size())
        m_interaction->hostAppearanceChanged();
}

void TimelineInputItem::itemChange(ItemChange change, const ItemChangeData &data)
{
    if (change == ItemDevicePixelRatioHasChanged && m_interaction)
        m_interaction->hostAppearanceChanged();
    if (change == ItemVisibleHasChanged && !data.boolValue) {
        if (m_interaction)
            m_interaction->inputCancelled(TimelineInputCancelReason::Hidden);
        // Drop our Quick focus selection so a hidden band cannot be handed
        // active focus again when its host returns to the focus chain.
        setFocus(false);
        // A hidden item is no longer a live source; end its ownership.
        m_hovered = false;
        clearMouseHint();
    }
    if (change == ItemSceneChange && !data.window) {
        // Window detachment terminates this source even during a grab; the
        // service's own window observation clears too, this keeps the item
        // authoritative without depending on signal order.
        m_hovered = false;
        clearMouseHint();
    }
    QQuickItem::itemChange(change, data);
}

} // namespace songview
