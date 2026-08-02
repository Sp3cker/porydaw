#pragma once

#include <QFont>
#include <QPointF>
#include <QStringView>

#include <optional>

class QApplication;

namespace typography {

/// Installs the application typeface while preserving the platform-resolved
/// base font pixel size for the semantic font scale.
bool installBundledFonts(QApplication &application);
/// Returns the platform-resolved base font pixel size captured during font
/// installation.
std::optional<int> baseFontPx();
/// Returns the application Body font installed by installBundledFonts, so
/// callers can reassert it against desktop components that reset the
/// application font behind Qt's back.
std::optional<QFont> bodyFont();
/// Swaps the semantic font scale between the bundled typeface and the
/// platform font captured before installation. Callers must reapply the
/// theme afterwards so already-polished widgets pick up the change.
void setUseSystemFont(bool preferred);
/// Resolved family of the platform font captured before the bundled install.
QString systemFontFamily();
/// Family of the platform's fixed-pitch font, used for Body Mono when the
/// system font is preferred.
QString systemMonoFamily();
QFont bodyMono(const QFont &body);
QFont caption(const QFont &source);
QFont bold(const QFont &source);
/// Finds the largest caption-or-smaller version of base's face that fits the
/// available height. The result never exceeds base's current pixel size.
std::optional<QFont> fitted(const QFont &base, int availableHeight);
/// Bundled note-label face: Regular on macOS, SemiBold elsewhere.
QFont noteName(const QFont &source);
/// Aligns the visible bounds of a substituted glyph with the reference face.
QPointF glyphCenteringOffset(const QFont &reference, const QFont &displayed, QStringView text);

} // namespace typography
