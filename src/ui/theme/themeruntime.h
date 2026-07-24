#pragma once

#include "theme.h"

class QApplication;
class QWidget;

namespace themes {

/// Captures the platform palette once, before any theme changes it.
void initialize(QApplication &application);
/// Applies colors over the captured palette; themes cannot supply geometry.
void apply(QApplication &application, const Theme &theme);
using GridLineRefresh = void (*)(QWidget &);

/// Registers a custom-painted widget that consumes song_view_grid.
void registerGridLineRefreshTarget(QWidget &widget,
                                   GridLineRefresh refresh = nullptr);
/// Returns a color from the currently applied complete theme.
const QColor &color(Role role);
} // namespace themes
