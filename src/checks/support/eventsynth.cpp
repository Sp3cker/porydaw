#include "checks/support/eventsynth.h"

#include <array>

#include <QtTest>

#include <QCoreApplication>
#include <QHoverEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QWheelEvent>
#include <QWidget>

namespace checks::events {

songview::TimelinePointerInput pointerInput(const QQuickItem &input, QPointF position,
                                            Qt::MouseButton button, Qt::MouseButtons buttons,
                                            Qt::KeyboardModifiers modifiers)
{
    return {position, input.mapToGlobal(position), button, buttons, modifiers};
}

void sendMouse(QWidget &target, QEvent::Type type, const QPointF &localPosition,
               Qt::MouseButton button, Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers)
{
    QMouseEvent event(type, localPosition, QPointF(target.mapToGlobal(localPosition.toPoint())),
                      button, buttons, modifiers);
    QCoreApplication::sendEvent(&target, &event);
}

void sendWheel(QWidget &target, const QPointF &localPosition, const QPoint &pixelDelta,
               const QPoint &angleDelta, Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers,
               Qt::ScrollPhase phase, bool inverted)
{
    QWheelEvent event(localPosition, QPointF(target.mapToGlobal(localPosition.toPoint())),
                      pixelDelta, angleDelta, buttons, modifiers, phase, inverted);
    QCoreApplication::sendEvent(&target, &event);
}

void sendMouse(QQuickItem &target, QEvent::Type type, const QPointF &localPosition,
               Qt::MouseButton button, Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers)
{
    if (type == QEvent::Leave || (type == QEvent::MouseMove && buttons == Qt::NoButton)) {
        const QEvent::Type hoverType =
            type == QEvent::Leave ? QEvent::HoverLeave : QEvent::HoverMove;
        QHoverEvent event(hoverType, localPosition, target.mapToGlobal(localPosition),
                          localPosition, modifiers);
        QCoreApplication::sendEvent(&target, &event);
        return;
    }
    QMouseEvent event(type, localPosition, target.mapToGlobal(localPosition), button, buttons,
                      modifiers);
    QCoreApplication::sendEvent(&target, &event);
}

void sendWheel(QQuickItem &target, const QPointF &localPosition, const QPoint &pixelDelta,
               const QPoint &angleDelta, Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers,
               Qt::ScrollPhase phase, bool inverted)
{
    QWheelEvent event(localPosition, target.mapToGlobal(localPosition), pixelDelta, angleDelta,
                      buttons, modifiers, phase, inverted);
    QCoreApplication::sendEvent(&target, &event);
}

bool primeMouseMove(QQuickWindow &window, const QQuickItem &surface, const QPoint &target)
{
    if (surface.window() != &window)
        return false;

    const QRectF bounds = surface.boundingRect();
    const QRect windowBounds{QPoint{}, window.size()};
    const auto contains = [&surface, &bounds, &windowBounds](QPoint position) {
        return windowBounds.contains(position) &&
               bounds.contains(surface.mapFromScene(QPointF(position)));
    };
    if (!contains(target))
        return false;

    constexpr std::array offsets{QPoint{1, 0}, QPoint{-1, 0}, QPoint{0, 1}, QPoint{0, -1}};
    for (const QPoint offset : offsets) {
        const QPoint adjacent = target + offset;
        if (contains(adjacent)) {
            QTest::mouseEvent(QTest::MouseMove, &window, Qt::NoButton, Qt::NoModifier, adjacent);
            return true;
        }
    }
    return false;
}

void sendKey(QObject &target, QEvent::Type type, int key, Qt::KeyboardModifiers modifiers,
             const QString &text, bool autoRepeat, ushort count)
{
    QKeyEvent event(type, key, modifiers, text, autoRepeat, count);
    QCoreApplication::sendEvent(&target, &event);
}

} // namespace checks::events
