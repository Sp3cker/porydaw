#include "editor.h"
#include <QChar>
#import <Cocoa/Cocoa.h>
#include <cstring>
#include <libproc.h>
#include <unistd.h>

namespace pdph::helper {
namespace {
id monitor = nil;
id activationObserver = nil;
struct EditorProcessFamily {
    const pid_t helper = getpid();
    const pid_t parent = getppid();
    char executable[PROC_PIDPATHINFO_MAXSIZE] = {};
    const int executableLength = proc_pidpath(helper, executable, sizeof(executable));
};
bool isEditorFamily(NSRunningApplication* application) {
    static const EditorProcessFamily family;
    const pid_t pid = application.processIdentifier;
    if (!application || pid <= 0) return false;
    if (pid == family.helper || pid == family.parent) return true;
    if (family.executableLength <= 0) return false;
    proc_bsdinfo info = {};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)
        || info.pbi_ppid != uint32_t(family.parent)) return false;
    char executable[PROC_PIDPATHINFO_MAXSIZE] = {};
    return proc_pidpath(pid, executable, sizeof(executable)) > 0 && std::strcmp(executable, family.executable) == 0;
}
void applyEditorOrdering(NSRunningApplication* application, const QVarLengthArray<uintptr_t, 1>& windows) {
    const bool family = isEditorFamily(application);
    for (const auto handle : windows) {
        NSView* content = (__bridge NSView*)reinterpret_cast<void*>(handle);
        NSWindow* window = content.window;
        if (!window) continue;
        window.level = family ? NSFloatingWindowLevel : NSNormalWindowLevel;
        if (!family && !NSApp.hidden && window.visible && !window.miniaturized) [window orderBack:nil];
    }
}
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
void refreshMacEditorWindows() {
    const auto windows = editorWindows();
    NSNotificationCenter* center = NSWorkspace.sharedWorkspace.notificationCenter;
    if (windows.empty()) {
        if (activationObserver) {
            [center removeObserver:activationObserver];
            activationObserver = nil;
        }
        return;
    }
    if (!activationObserver) {
        activationObserver = [center addObserverForName:NSWorkspaceDidActivateApplicationNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* notification) {
                applyEditorOrdering(notification.userInfo[NSWorkspaceApplicationKey], editorWindows());
            }];
    }
    applyEditorOrdering(NSWorkspace.sharedWorkspace.frontmostApplication, windows);
}
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
