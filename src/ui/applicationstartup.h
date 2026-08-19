#pragma once

#include <functional>

class QApplication;
class QWidget;

namespace ui {

/// Applies Porydaw's application identity and presentation, then initializes
/// the shared UI modules used by both production and check executables.
bool initializePorydawApplication(QApplication &application);

/// Installs bundled typography and initializes the shared UI modules.
bool initializeApplication(QApplication &application);

/// Shows the window beneath a flat window-background cover, paints one frame,
/// runs the restore step, then reveals the finished UI. The up-front paint
/// keeps the first visible frame themed (Windows otherwise flashes a white
/// frame until the first paint after restore), and the cover hides the
/// intermediate layouts restore produces.
void showCoveredWhileRestoring(QWidget &window, const std::function<void()> &restore);

} // namespace ui
