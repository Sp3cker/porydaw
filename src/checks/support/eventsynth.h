#pragma once

#include <QEvent>
#include <QPoint>
#include <QPointF>
#include <QString>
#include <QtGlobal>

class QObject;
class QWidget;
class QQuickItem;
class QQuickWindow;

namespace checks::events {

void sendMouse(QWidget &target, QEvent::Type type, const QPointF &localPosition,
               Qt::MouseButton button, Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers);
void sendWheel(QWidget &target, const QPointF &localPosition, const QPoint &pixelDelta,
               const QPoint &angleDelta, Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers,
               Qt::ScrollPhase phase, bool inverted);
void sendKey(QObject &target, QEvent::Type type, int key, Qt::KeyboardModifiers modifiers,
             const QString &text, bool autoRepeat, ushort count);

// Direct delivery into a converted band's Quick input item. sendKey()
// already targets QObject; the mouse overload maps passive moves and Leave
// to the QQuickItem hover events they represent in production.
void sendMouse(QQuickItem &target, QEvent::Type type, const QPointF &localPosition,
               Qt::MouseButton button, Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers);
void sendWheel(QQuickItem &target, const QPointF &localPosition, const QPoint &pixelDelta,
               const QPoint &angleDelta, Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers,
               Qt::ScrollPhase phase, bool inverted);

// Sends one adjacent QPA mouse move inside surface when target is within that
// surface. Callers retain window-enter delivery and the final target move.
bool primeMouseMove(QQuickWindow &window, const QQuickItem &surface, const QPoint &target);

} // namespace checks::events
