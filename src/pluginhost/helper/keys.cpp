#include "editor.h"
#include <QChar>
#include <QAbstractNativeEventFilter>
#include <QCoreApplication>
#include <QGuiApplication>
#include <array>
#include <cstdlib>
#include <bitset>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#elif defined(__linux__)
#include <X11/XKBlib.h>
#include <X11/keysym.h>
#include <xcb/xcb.h>
#endif

namespace pdph::helper {
namespace {
constexpr uint32_t modifierMask = Qt::ShiftModifier | Qt::ControlModifier | Qt::AltModifier | Qt::MetaModifier | Qt::KeypadModifier;
std::vector<int32_t> shortcuts;
std::bitset<256> swallowed;
void (*onShortcut)(void*, int32_t) = nullptr;
void* shortcutUser = nullptr;
#ifdef _WIN32
uint32_t qtKey(WPARAM key) {
    if ((key >= '0' && key <= '9') || (key >= 'A' && key <= 'Z')) return uint32_t(key);
    if (key >= VK_NUMPAD0 && key <= VK_NUMPAD9) return '0' + uint32_t(key - VK_NUMPAD0);
    if (key >= VK_F1 && key <= VK_F24) return Qt::Key_F1 + uint32_t(key - VK_F1);
    switch (key) {
    case VK_SPACE: return Qt::Key_Space;
    case VK_RETURN: return Qt::Key_Return;
    case VK_ESCAPE: return Qt::Key_Escape;
    case VK_TAB: return Qt::Key_Tab;
    case VK_BACK: return Qt::Key_Backspace;
    case VK_DELETE: return Qt::Key_Delete;
    case VK_INSERT: return Qt::Key_Insert;
    case VK_HOME: return Qt::Key_Home;
    case VK_END: return Qt::Key_End;
    case VK_PRIOR: return Qt::Key_PageUp;
    case VK_NEXT: return Qt::Key_PageDown;
    case VK_LEFT: return Qt::Key_Left;
    case VK_RIGHT: return Qt::Key_Right;
    case VK_UP: return Qt::Key_Up;
    case VK_DOWN: return Qt::Key_Down;
    case VK_ADD: return Qt::Key_Plus;
    case VK_SUBTRACT: return Qt::Key_Minus;
    case VK_MULTIPLY: return Qt::Key_Asterisk;
    case VK_DIVIDE: return Qt::Key_Slash;
    case VK_DECIMAL: return Qt::Key_Period;
    default: break;
    }
    BYTE state[256] = {};
    if (GetKeyState(VK_SHIFT) & 0x8000) state[VK_SHIFT] = 0x80;
    WCHAR text[4] = {};
    if (ToUnicode(UINT(key), MapVirtualKeyW(UINT(key), MAPVK_VK_TO_VSC), state, text, 4, 4) == 1)
        return uint32_t(QChar::toUpper(char32_t(text[0])));
    return 0;
}
class KeyFilter final : public QAbstractNativeEventFilter {
    bool nativeEventFilter(const QByteArray& type, void* message, qintptr*) override {
        if (type != "windows_dispatcher_MSG" && type != "windows_generic_MSG") return false;
        const auto& event = *static_cast<MSG*>(message);
        const bool down = event.message == WM_KEYDOWN || event.message == WM_SYSKEYDOWN;
        if (!down && event.message != WM_KEYUP && event.message != WM_SYSKEYUP) return false;
        const auto root = GetAncestor(event.hwnd, GA_ROOT);
        if (!isEditorWindow(reinterpret_cast<uintptr_t>(root))) return false;
        uint32_t modifiers = 0;
        if (GetKeyState(VK_SHIFT) & 0x8000) modifiers |= Qt::ShiftModifier;
        if (GetKeyState(VK_CONTROL) & 0x8000) modifiers |= Qt::ControlModifier;
        if (GetKeyState(VK_MENU) & 0x8000) modifiers |= Qt::AltModifier;
        if ((GetKeyState(VK_LWIN) | GetKeyState(VK_RWIN)) & 0x8000) modifiers |= Qt::MetaModifier;
        auto key = qtKey(event.wParam);
        if (event.wParam == VK_RETURN && (event.lParam & (1 << 24))) key = Qt::Key_Enter;
        if ((event.wParam >= VK_NUMPAD0 && event.wParam <= VK_DIVIDE) || key == Qt::Key_Enter) modifiers |= Qt::KeypadModifier;
        return interceptEditorKey(reinterpret_cast<uintptr_t>(root), key, modifiers, uint32_t(event.wParam), down, down && (event.lParam & (1 << 30)));
    }
};
KeyFilter filter;
#elif defined(__linux__)
struct Grab { xcb_window_t window; xcb_keycode_t key; uint16_t modifiers; uint32_t qtKey; uint32_t qtModifiers; };
std::vector<Grab> grabs;
xcb_connection_t* connection() {
    auto* native = qGuiApp->nativeInterface<QNativeInterface::QX11Application>();
    return native ? native->connection() : nullptr;
}
KeySym nativeKey(uint32_t key, uint32_t modifiers) {
    if (modifiers & Qt::KeypadModifier) {
        if (key >= '0' && key <= '9') return XK_KP_0 + key - '0';
        switch (key) {
        case Qt::Key_Plus: return XK_KP_Add;
        case Qt::Key_Minus: return XK_KP_Subtract;
        case Qt::Key_Asterisk: return XK_KP_Multiply;
        case Qt::Key_Slash: return XK_KP_Divide;
        case Qt::Key_Period: return XK_KP_Decimal;
        default: break;
        }
    }
    if (key >= Qt::Key_F1 && key <= Qt::Key_F35) return XK_F1 + key - Qt::Key_F1;
    if (key >= 0x20 && key <= 0x7e) return key >= 'A' && key <= 'Z' ? key + ('a' - 'A') : key;
    switch (key) {
    case Qt::Key_Return: return XK_Return;
    case Qt::Key_Enter: return XK_KP_Enter;
    case Qt::Key_Escape: return XK_Escape;
    case Qt::Key_Tab: return XK_Tab;
    case Qt::Key_Backspace: return XK_BackSpace;
    case Qt::Key_Delete: return XK_Delete;
    case Qt::Key_Insert: return XK_Insert;
    case Qt::Key_Home: return XK_Home;
    case Qt::Key_End: return XK_End;
    case Qt::Key_PageUp: return XK_Page_Up;
    case Qt::Key_PageDown: return XK_Page_Down;
    case Qt::Key_Left: return XK_Left;
    case Qt::Key_Right: return XK_Right;
    case Qt::Key_Up: return XK_Up;
    case Qt::Key_Down: return XK_Down;
    default: return NoSymbol;
    }
}
class KeyFilter final : public QAbstractNativeEventFilter {
    bool nativeEventFilter(const QByteArray& type, void* message, qintptr*) override {
        if (type != "xcb_generic_event_t") return false;
        const auto* event = static_cast<xcb_key_press_event_t*>(message);
        const auto kind = event->response_type & 0x7f;
        if (kind != XCB_KEY_PRESS && kind != XCB_KEY_RELEASE) return false;
        if (!isEditorWindow(event->event)) return false;
        if (swallowed.test(event->detail))
            return interceptEditorKey(event->event, 0, 0, event->detail, kind == XCB_KEY_PRESS, kind == XCB_KEY_PRESS);
        for (const auto& grab : grabs) {
            if (grab.window == event->event && grab.key == event->detail && grab.modifiers == (event->state & 0xff))
                return interceptEditorKey(event->event, grab.qtKey, grab.qtModifiers, event->detail, kind == XCB_KEY_PRESS, false);
        }
        return false;
    }
};
KeyFilter filter;
#endif
#ifndef __APPLE__
bool filterInstalled = false;
#endif
}
bool interceptEditorKey(uintptr_t window, uint32_t key, uint32_t modifiers, uint32_t physicalKey, bool down, bool repeat) {
    if (!isEditorWindow(window) || physicalKey >= swallowed.size()) return false;
    if (swallowed.test(physicalKey)) {
        if (!down) swallowed.reset(physicalKey);
        return true;
    }
    if (!down) return false;
    for (size_t index = 0; index < shortcuts.size(); ++index) {
        const auto stroke = uint32_t(shortcuts[index]);
        if ((stroke & ~uint32_t(Qt::KeyboardModifierMask)) != key || (stroke & modifierMask) != (modifiers & modifierMask)) continue;
        swallowed.set(physicalKey);
        if (!repeat && onShortcut) onShortcut(shortcutUser, int32_t(index));
        return true;
    }
    return false;
}
void refreshShortcutWindows() {
    if (editorWindows().empty()) swallowed.reset();
#if defined(__linux__)
    auto* xcb = connection();
    if (!xcb) return;
    for (const auto& grab : grabs) xcb_ungrab_key(xcb, grab.key, grab.window, grab.modifiers);
    grabs.clear();
    if (shortcuts.empty()) { xcb_flush(xcb); return; }
    const auto* setup = xcb_get_setup(xcb);
    const auto count = uint8_t(setup->max_keycode - setup->min_keycode + 1);
    auto* mapping = xcb_get_keyboard_mapping_reply(xcb, xcb_get_keyboard_mapping(xcb, setup->min_keycode, count), nullptr);
    if (!mapping) return;
    const auto* symbols = xcb_get_keyboard_mapping_keysyms(mapping);
    uint16_t numLock = 0;
    auto* modifiers = xcb_get_modifier_mapping_reply(xcb, xcb_get_modifier_mapping(xcb), nullptr);
    if (modifiers) {
        const auto* codes = xcb_get_modifier_mapping_keycodes(modifiers);
        for (int mod = 0; mod < 8; ++mod) for (int index = 0; index < modifiers->keycodes_per_modifier; ++index) {
            const auto code = codes[mod * modifiers->keycodes_per_modifier + index];
            if (code < setup->min_keycode || code > setup->max_keycode) continue;
            for (int column = 0; column < mapping->keysyms_per_keycode; ++column)
                if (symbols[(code - setup->min_keycode) * mapping->keysyms_per_keycode + column] == XK_Num_Lock) numLock |= uint16_t(1 << mod);
        }
        std::free(modifiers);
    }
    const auto windows = editorWindows();
    for (const auto strokeValue : shortcuts) {
        const auto stroke = uint32_t(strokeValue);
        const auto key = stroke & ~uint32_t(Qt::KeyboardModifierMask);
        const auto symbol = nativeKey(key, stroke & modifierMask);
        uint16_t mods = 0;
        if (stroke & Qt::ShiftModifier) mods |= XCB_MOD_MASK_SHIFT;
        if (stroke & Qt::ControlModifier) mods |= XCB_MOD_MASK_CONTROL;
        if (stroke & Qt::AltModifier) mods |= XCB_MOD_MASK_1;
        if (stroke & Qt::MetaModifier) mods |= XCB_MOD_MASK_4;
        for (unsigned code = setup->min_keycode; code <= setup->max_keycode; ++code) {
            bool matches = false;
            for (int column = 0; column < mapping->keysyms_per_keycode; ++column)
                if (symbols[(code - setup->min_keycode) * mapping->keysyms_per_keycode + column] == symbol) matches = true;
            if (symbol == NoSymbol || !matches) continue;
            for (const auto window : windows) for (const uint16_t locks : std::array<uint16_t, 4>{0, XCB_MOD_MASK_LOCK, numLock, uint16_t(XCB_MOD_MASK_LOCK | numLock)}) {
                const uint16_t mask = mods | locks;
                xcb_grab_key(xcb, false, xcb_window_t(window), mask, xcb_keycode_t(code), XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
                grabs.push_back({xcb_window_t(window), xcb_keycode_t(code), mask, key, stroke & modifierMask});
            }
        }
    }
    std::free(mapping);
    xcb_flush(xcb);
#endif
}
pdph_result setEditorShortcuts(int32_t count, ShortcutStrokeReader readStroke, void* readerContext,
    void (*callback)(void*, int32_t), void* user) {
    if (count < 0 || (count && (!readStroke || !callback))) return PDPH_ERR_ARGUMENT;
    try {
        shortcuts.reserve(static_cast<size_t>(count));
        shortcuts.clear();
        for (int32_t index = 0; index < count; ++index) shortcuts.push_back(readStroke(readerContext, index));
        onShortcut = callback; shortcutUser = user;
        if (shortcuts.empty()) swallowed.reset();
#ifdef __APPLE__
        updateMacShortcuts(!shortcuts.empty());
#else
        if (QCoreApplication::instance()) {
            if (!shortcuts.empty() && !filterInstalled) {
                QCoreApplication::instance()->installNativeEventFilter(&filter); filterInstalled = true;
            } else if (shortcuts.empty() && filterInstalled) {
                QCoreApplication::instance()->removeNativeEventFilter(&filter); filterInstalled = false;
            }
        }
#if defined(__linux__)
        if (auto* native = qGuiApp->nativeInterface<QNativeInterface::QX11Application>()) {
            Bool supported = False;
            XkbSetDetectableAutoRepeat(native->display(), True, &supported);
        }
#endif
#endif
        refreshShortcutWindows();
        return PDPH_OK;
    } catch (...) { return PDPH_ERR_INTERNAL; }
}
}
