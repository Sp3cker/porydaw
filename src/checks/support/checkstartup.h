#pragma once

class QApplication;

namespace checks {

/// Replaces QOffscreen's generic default with the platform UI face. Call
/// before a font is resolved.
void installOffscreenSystemFont(QApplication &application);

/// Gives the check process Porydaw's application identity and the bundled
/// Atkinson Hyperlegible body font the production shell loads, so Swift
/// typography measures the same faces it measures in the app.
bool initializeCheckApplication(QApplication &application);

} // namespace checks
