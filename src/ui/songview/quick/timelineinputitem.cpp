#include "ui/songview/quick/timelineinputitem.h"

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
    setInteraction(nullptr);
}

void TimelineInputItem::setInteraction(TimelineBandInteraction *interaction,
                                       TimelineInputSurface surface, bool attachHost)
{
    if (m_interaction == interaction && m_surface == surface && m_attachHost == attachHost)
        return;

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

void TimelineInputItem::hoverMoveEvent(QHoverEvent *event)
{
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
    if (m_interaction)
        m_interaction->pointerLeave();
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
    if (!m_interaction || !m_interaction->keyPress(keyInput(*event))) {
        event->ignore();
        return;
    }
    event->accept();
}

void TimelineInputItem::keyReleaseEvent(QKeyEvent *event)
{
    if (!m_interaction || !m_interaction->keyRelease(keyInput(*event))) {
        event->ignore();
        return;
    }
    event->accept();
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
    }
    QQuickItem::itemChange(change, data);
}

} // namespace songview
