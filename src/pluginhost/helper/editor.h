#pragma once
#include "pluginhost.h"
#include <QVarLengthArray>
#include <QWindow>
#include <cstdint>

namespace pdph::helper {
void installEditors();
void shutdownEditors();
void* editorParent(QWindow&);
bool isEditorWindow(uintptr_t nativeWindow);
QVarLengthArray<uintptr_t, 1> editorWindows();
void refreshShortcutWindows();
// Called once per index, in ascending order.
using ShortcutStrokeReader = int32_t (*)(void* context, int32_t index) noexcept;
// The reader/context are borrowed only during this synchronous installation.
pdph_result setEditorShortcuts(int32_t count, ShortcutStrokeReader, void* readerContext, void (*)(void*, int32_t), void*);
bool interceptEditorKey(uintptr_t window, uint32_t key, uint32_t modifiers, uint32_t physicalKey, bool down, bool repeat);
#ifdef __APPLE__
void updateMacShortcuts(bool enabled);
void refreshMacEditorWindows();
#endif
}
