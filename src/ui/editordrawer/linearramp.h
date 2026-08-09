#pragma once

#include <algorithm>

namespace ui {

inline double linearRampValue(double position, double startPosition, double startValue,
                              double endPosition, double endValue) noexcept
{
    if (startPosition == endPosition)
        return endValue;
    const double fraction =
        std::clamp((position - startPosition) / (endPosition - startPosition), 0.0, 1.0);
    return startValue + fraction * (endValue - startValue);
}

} // namespace ui
