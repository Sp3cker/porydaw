#pragma once

class QApplication;
class QWidget;

namespace ui {
/// Replaces QOffscreen's macOS generic default with CoreText's system font.
/// Call before a font is resolved.
void installOffscreenSystemFont(QApplication &application);

/// Applies Porydaw's application identity and presentation, then initializes
/// the shared UI modules used by both production and check executables.
bool initializePorydawApplication(QApplication &application);

/// Installs bundled typography and initializes the shared UI modules.
bool initializeApplication(QApplication &application);

/// Shows the fully constructed window only after its first themed frame has
/// been painted. On Windows the native top-level remains DWM-cloaked during
/// that paint so an uninitialized white redirection surface cannot flash.
void showPreparedWindow(QWidget &window);

} // namespace ui
