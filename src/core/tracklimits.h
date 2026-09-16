#pragma once

#include <QtGlobal>
#include <cstddef>
#include <limits>

namespace track_limits {

inline constexpr int kHardwareCapacity = 16;

// Single size→int narrow for track counts. Counts stay int (Qt rowCount,
// QCOMPARE, hardware cap); vector assign/resize/indexing takes size_t at
// the call site. Asserts int-range; SMF counts may exceed kHardwareCapacity.
inline int checkedTrackInt(std::size_t n)
{
    Q_ASSERT(n <= std::size_t((std::numeric_limits<int>::max)()));
    return static_cast<int>(n);
}

} // namespace track_limits
