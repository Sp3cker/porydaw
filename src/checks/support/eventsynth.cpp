#include "checks/support/eventsynth.h"

#include <QCoreApplication>
#include <QHoverEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQuickItem>
#include <QWheelEvent>
#include <QWidget>

namespace checks::events {

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
    if (type == QEvent::Leave) {
        const QPointF scenePosition = target.mapToScene(localPosition);
        QHoverEvent event(QEvent::HoverLeave, scenePosition, target.mapToGlobal(localPosition),
                          scenePosition);
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

void sendKey(QObject &target, QEvent::Type type, int key, Qt::KeyboardModifiers modifiers,
             const QString &text, bool autoRepeat, ushort count)
{
    QKeyEvent event(type, key, modifiers, text, autoRepeat, count);
    QCoreApplication::sendEvent(&target, &event);
}

} // namespace checks::events
