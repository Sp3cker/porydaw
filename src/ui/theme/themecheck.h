#pragma once

#include <QColor>

int runThemeCheck();

// --darkbasecheck: models booting on a dark platform (macOS follows the
// system appearance). main() paints every palette role with this poison
// BEFORE ui::initializeApplication captures the theme baseline; the check
// then asserts the default theme fully masks it in visible chrome.
inline const QColor kDarkBaselinePoison(40, 0, 40);

int runDarkBaselineCheck();
