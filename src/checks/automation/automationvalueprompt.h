#pragma once

#include <QQuickItem>
#include <QQuickWindow>

#include "ui/editordrawer/drawerchrome.h"

// Shared view of the inline Quick value prompt (drawer plan Cleanup phase 2).
// The canvas publishes the pending edit through DrawerChrome and the prompt
// TextInput takes active focus with its initial text selected on open, so
// checks observe the live surface through the chrome property and the window's
// active focus item instead of fishing for QML object names.
namespace automation_valueprompt {

// True exactly while the canvas holds a pending value prompt.
inline bool promptVisible(const DrawerChrome &chrome)
{
    return chrome.valuePromptVisible();
}

// The focused prompt TextInput, or null when no text item owns active focus.
inline QQuickItem *focusedTextInput(QQuickWindow &window)
{
    QQuickItem *const focus = window.activeFocusItem();
    return focus && focus->metaObject()->indexOfProperty("text") >= 0 ? focus : nullptr;
}

// True when the automation input item, or one of its children, owns focus.
inline bool inputOwnsFocus(const QQuickWindow &window, const QQuickItem &input)
{
    const QQuickItem *const focus = window.activeFocusItem();
    return focus && (focus == &input || input.isAncestorOf(focus));
}

} // namespace automation_valueprompt
