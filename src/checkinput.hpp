#pragma once

#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPoint>
#include <QWidget>

#include "liveshortcuts.hpp"

namespace check_input
{

inline bool focusShortcutTarget(QWidget &target)
{
    auto *const window = target.window();
    window->show();
    window->raise();
    window->activateWindow();
    QCoreApplication::processEvents();
    target.setFocus(Qt::OtherFocusReason);
    QCoreApplication::processEvents();
    return QApplication::activeWindow() == window &&
           QApplication::focusWidget() == &target;
}

inline void sendKey(QWidget &widget, int key, Qt::KeyboardModifiers modifiers)
{
    if (!focusShortcutTarget(widget))
        return;
    QKeyEvent press(QEvent::KeyPress, key, modifiers);
    QCoreApplication::sendEvent(&widget, &press);
    QKeyEvent release(QEvent::KeyRelease, key, modifiers);
    QCoreApplication::sendEvent(&widget, &release);
}

inline void sendMouse(QWidget &widget, QEvent::Type type, QPoint position,
                      Qt::MouseButton button, Qt::MouseButtons buttons,
                      Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
    QMouseEvent event(type, QPointF(position), QPointF(widget.mapToGlobal(position)),
                      button, buttons, modifiers);
    QCoreApplication::sendEvent(&widget, &event);
}

inline void click(QWidget &widget, QPoint position)
{
    sendMouse(widget, QEvent::MouseButtonPress, position, Qt::LeftButton,
              Qt::LeftButton);
    sendMouse(widget, QEvent::MouseButtonRelease, position, Qt::LeftButton,
              Qt::NoButton);
}

inline QAction *findAction(QWidget &widget, live_shortcuts::Command command)
{
    const auto shortcutId = QString::fromLatin1(live_shortcuts::descriptor(command).shortcutId);
    for (auto *action : widget.actions())
    {
        if (action->property("liveShortcutId").toString() == shortcutId)
            return action;
    }
    return nullptr;
}

} // namespace check_input
