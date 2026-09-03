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
QFont bodyMono(const QFont &body);
/// Fixed-pitch tabular font for compact numeric table cells.
QFont tableMono(const QFont &body);
QFont caption(const QFont &source);
QFont regular(const QFont &source);
QFont italic(const QFont &source);
QFont bold(const QFont &source);
/// Finds the largest caption-or-smaller version of base's face that fits the
/// available height. The result never exceeds base's current pixel size.
std::optional<QFont> fitted(const QFont &base, int availableHeight);
/// Bundled note-label face: Regular on macOS, SemiBold elsewhere.
QFont noteName(const QFont &source);
/// Aligns the visible bounds of a substituted glyph with the reference face.
QPointF glyphCenteringOffset(const QFont &reference, const QFont &displayed, QStringView text);

} // namespace typography
