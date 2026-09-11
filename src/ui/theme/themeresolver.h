#pragma once

#include "theme.h"

namespace themes {

// This boundary maps fixed preset tables to the runtime role table.
// Controllers and paint code consume the resolved Theme.

/// Adjusts the Song View grid line color around the theme default at 50.
/// Values below 50 reduce contrast; values above 50 increase it.
Theme withGridLineContrast(Theme theme, int contrast);

/// Returns the deterministic fixed Vanilla role table.
Theme vanilla();
/// Returns the fixed Dark Neutral High role table.
Theme darkNeutralHigh();
/// Returns the fixed Immaterial role table.
Theme immaterial();

} // namespace themes
