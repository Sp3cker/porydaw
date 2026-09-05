#include "checks/scrollbar/tst_scrollbar.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QInputDevice>
#include <QPointingDevice>
#include <QQuickItem>
#include <QQuickWindow>
#include <QStyleHints>
#include <QWheelEvent>
#include <QtTest>

#include <cmath>

#include "ui/songtab.h"
#include "ui/songview.h"

namespace {

constexpr qreal kGeometryTolerance = 0.01;

bool closeEnough(qreal actual, qreal expected)
{
    return std::abs(actual - expected) <= kGeometryTolerance;
}

Qt::MouseEventSource wheelSourceFor(const QPointingDevice *device)
{
    return device == QPointingDevice::primaryPointingDevice() ? Qt::MouseEventNotSynthesized
                                                              : Qt::MouseEventSynthesizedBySystem;
}

} // namespace

SongView &ScrollbarTest::view()
{
    return m_tab->view();
}

QQuickWindow &ScrollbarTest::window()
{
    return *m_window;
}

QQuickItem &ScrollbarTest::bar(Qt::Orientation orientation)
{
    return orientation == Qt::Horizontal ? *m_horizontalBar : *m_verticalBar;
}

QQuickItem &ScrollbarTest::thumb(Qt::Orientation orientation)
{
    return orientation == Qt::Horizontal ? *m_horizontalThumb : *m_verticalThumb;
}

void ScrollbarTest::press(QPointF windowPosition)
{
    m_lastWindowPosition = windowPosition;
    m_heldButton = Qt::LeftButton;
    QTest::mousePress(&window(), Qt::LeftButton, Qt::NoModifier, windowPosition.toPoint());
}

void ScrollbarTest::move(QPointF windowPosition)
{
    m_lastWindowPosition = windowPosition;
    QTest::mouseMove(&window(), windowPosition.toPoint());
}

void ScrollbarTest::release()
{
    if (m_heldButton == Qt::NoButton)
        return;
    QTest::mouseRelease(&window(), m_heldButton, Qt::NoModifier, m_lastWindowPosition.toPoint());
    m_heldButton = Qt::NoButton;
}

QPointF ScrollbarTest::beginDrag(Qt::Orientation orientation)
{
    QQuickItem &handle = thumb(orientation);
    const QPointF pressPosition = handle.mapToScene(handle.boundingRect().center());
    press(pressPosition);

    const qreal activation = QGuiApplication::styleHints()->startDragDistance() + 1.0;
    const QPointF activationOffset =
        orientation == Qt::Horizontal ? QPointF(activation, 1.0) : QPointF(1.0, activation);
    move(pressPosition + activationOffset);
    const QPointF dragPosition =
        pressPosition + activationOffset +
        (orientation == Qt::Horizontal ? QPointF(1.0, 0.0) : QPointF(0.0, 1.0));
    move(dragPosition);
    return dragPosition;
}

void ScrollbarTest::wheel(Qt::Orientation orientation, QPoint pixel, QPoint angle, bool inverted,
                          bool touchpad)
{
    const int index = orientationIndex(orientation);
    if (touchpad && !m_touchpad) {
        m_touchpad = std::make_unique<QPointingDevice>(
            QStringLiteral("scrollbar test touchpad"), 0x2001, QInputDevice::DeviceType::TouchPad,
            QPointingDevice::PointerType::Finger,
            QInputDevice::Capability::Position | QInputDevice::Capability::Scroll, 5, 0);
    }

    const QPointingDevice *const device =
        touchpad ? m_touchpad.get() : QPointingDevice::primaryPointingDevice();
    const QPointF position = bar(orientation).mapToScene(bar(orientation).boundingRect().center());
    QWheelEvent event(position, window().mapToGlobal(position.toPoint()), pixel, angle,
                      Qt::NoButton, Qt::NoModifier,
                      pixel.isNull() ? Qt::NoScrollPhase : Qt::ScrollUpdate, inverted,
                      wheelSourceFor(device), device);
    QCoreApplication::sendEvent(&window(), &event);
    m_wheelSessions[index] = {.position = position, .active = true, .touchpad = touchpad};
}

void ScrollbarTest::endWheel(Qt::Orientation orientation, bool touchpad)
{
    Q_UNUSED(touchpad);
    WheelSession &session = m_wheelSessions[orientationIndex(orientation)];
    if (!session.active)
        return;

    const QPointingDevice *const device =
        session.touchpad ? m_touchpad.get() : QPointingDevice::primaryPointingDevice();
    QWheelEvent event(session.position, window().mapToGlobal(session.position.toPoint()), QPoint(),
                      QPoint(), Qt::NoButton, Qt::NoModifier, Qt::ScrollEnd, false,
                      wheelSourceFor(device), device);
    QCoreApplication::sendEvent(&window(), &event);
    session = {};
}

bool ScrollbarTest::withinTrack(Qt::Orientation orientation)
{
    const QQuickItem &track = bar(orientation);
    const QQuickItem &handle = thumb(orientation);
    if (orientation == Qt::Horizontal) {
        return handle.x() >= -kGeometryTolerance &&
               handle.x() + handle.width() <= track.width() + kGeometryTolerance &&
               closeEnough(handle.y(), 0.0) && closeEnough(handle.height(), track.height());
    }
    return handle.y() >= -kGeometryTolerance &&
           handle.y() + handle.height() <= track.height() + kGeometryTolerance &&
           closeEnough(handle.x(), 0.0) && closeEnough(handle.width(), track.width());
}
