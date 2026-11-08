#include "editor.h"
#include <QChar>
#import <Cocoa/Cocoa.h>

namespace pdph::helper {
namespace {
id monitor = nil;
uint32_t qtKey(NSEvent* event) {
    NSString* text = event.charactersIgnoringModifiers;
    if (text.length != 1) return 0;
    const unichar key = [text characterAtIndex:0];
    if (key >= NSF1FunctionKey && key <= NSF35FunctionKey) return Qt::Key_F1 + key - NSF1FunctionKey;
    switch (key) {
    case NSUpArrowFunctionKey: return Qt::Key_Up;
    case NSDownArrowFunctionKey: return Qt::Key_Down;
    case NSLeftArrowFunctionKey: return Qt::Key_Left;
    case NSRightArrowFunctionKey: return Qt::Key_Right;
    case NSHomeFunctionKey: return Qt::Key_Home;
    case NSEndFunctionKey: return Qt::Key_End;
    case NSPageUpFunctionKey: return Qt::Key_PageUp;
    case NSPageDownFunctionKey: return Qt::Key_PageDown;
    case NSDeleteFunctionKey: return Qt::Key_Delete;
    case NSInsertFunctionKey: return Qt::Key_Insert;
    case 0x7f: return Qt::Key_Backspace;
    case 0x1b: return Qt::Key_Escape;
    case '\t': return Qt::Key_Tab;
    case '\r': return Qt::Key_Return;
    case 0x03: return Qt::Key_Enter;
    default: return uint32_t(QChar::toUpper(char32_t(key)));
    }
}
}
void* editorParent(QWindow& window) { return reinterpret_cast<void*>(window.winId()); }
void updateMacShortcuts(bool enabled) {
    if (!enabled && monitor) { [NSEvent removeMonitor:monitor]; monitor = nil; }
    if (!enabled || monitor) return;
    monitor = [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskKeyDown | NSEventMaskKeyUp)
        handler:^NSEvent* (NSEvent* event) {
            NSView* content = event.window.contentView;
            if (!content) return event;
            uint32_t modifiers = 0;
            const auto flags = event.modifierFlags;
            if (flags & NSEventModifierFlagShift) modifiers |= Qt::ShiftModifier;
            if (flags & NSEventModifierFlagCommand) modifiers |= Qt::ControlModifier;
            if (flags & NSEventModifierFlagOption) modifiers |= Qt::AltModifier;
            if (flags & NSEventModifierFlagControl) modifiers |= Qt::MetaModifier;
            if (flags & NSEventModifierFlagNumericPad) modifiers |= Qt::KeypadModifier;
            if (interceptEditorKey(reinterpret_cast<uintptr_t>((__bridge void*)content), qtKey(event), modifiers,
                event.keyCode, event.type == NSEventTypeKeyDown, event.type == NSEventTypeKeyDown && event.isARepeat)) return nil;
            return event;
        }];
}
}
