#pragma once

#include <QEvent>
#include <QPoint>
#include <QPointF>
#include <QString>
#include <QtGlobal>

class QObject;
class QWidget;

namespace checks::events {

void sendMouse(QWidget &target, QEvent::Type type, const QPointF &localPosition,
               Qt::MouseButton button, Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers);
void sendWheel(QWidget &target, const QPointF &localPosition, const QPoint &pixelDelta,
               const QPoint &angleDelta, Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers,
               Qt::ScrollPhase phase, bool inverted);
void sendKey(QObject &target, QEvent::Type type, int key, Qt::KeyboardModifiers modifiers,
             const QString &text, bool autoRepeat, ushort count);

} // namespace checks::events
