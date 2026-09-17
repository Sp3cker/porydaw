#pragma once

#include "theme.h"

class QApplication;
class QObject;

namespace themes {

/// Captures the platform palette once, before any theme changes it.
void initialize(QApplication &application);
/// Applies colors over the captured palette; themes cannot supply geometry.
void apply(QApplication &application, const Theme &theme);
/// Registers a widget or Quick coordinator that consumes song_view_grid.
void registerGridLineRefreshTarget(QObject &target);
/// Returns a color from the currently applied complete theme.
const QColor &color(Role role);
/// Resolves text for the exact opaque surface it is painted on.
const QColor &textOn(const Theme &theme, Role surface, Role restingText);
/// Preserves resting text when readable; otherwise chooses black or white for an exact fill.
QColor textOn(const Theme &theme, const QColor &surface, Role restingText);
/// Runtime form using the currently applied theme.
const QColor &textOn(Role surface, Role restingText);
/// Runtime form for a computed fill color.
QColor textOn(const QColor &surface, Role restingText);
} // namespace themes
