#pragma once
#include "pluginhost.h"
#include <QWindow>
#include <cstdint>
#include <vector>

namespace pdph::helper {
void installEditors();
void shutdownEditors();
void* editorParent(QWindow&);
bool isEditorWindow(uintptr_t nativeWindow);
std::vector<uintptr_t> editorWindows();
void refreshShortcutWindows();
pdph_result setEditorShortcuts(const int32_t*, int32_t, void (*)(void*, int32_t), void*);
bool interceptEditorKey(uintptr_t window, uint32_t key, uint32_t modifiers, uint32_t physicalKey, bool down, bool repeat);
#ifdef __APPLE__
void updateMacShortcuts(bool enabled);
void refreshMacEditorWindows();
#endif
}
