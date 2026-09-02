#pragma once

#include <QRect>

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>

namespace songview {

enum class TimelineBand : uint8_t {
    Ruler,
    Roll,
    OtherEvents,
    Automation,
    Velocity,
    VoiceChanges,
    Count,
};

constexpr std::size_t timelineBandIndex(TimelineBand band)
{
    return static_cast<std::size_t>(band);
}

// Value contract: rect is the visible SongView-local band rectangle, already
// clipped/limited by the band's parent layout owner (spacer row, roll page
// minus scrollbar, drawer viewport/body). Hidden or fully occluded bands are
// nullopt. timelineOrigin is the band's timeline x inside rect. Consumers can
// therefore intersect SongView's rect alone; no ancestor widget walking.
struct TimelineBandGeometry {
    QRect rect;
    int timelineOrigin;

    friend bool operator==(const TimelineBandGeometry &, const TimelineBandGeometry &) = default;
};

// Canonical snapshot resolved and published by SongView; every engaged
// optional satisfies the TimelineBandGeometry contract above.
struct TimelineBandLayout {
    std::array<std::optional<TimelineBandGeometry>, timelineBandIndex(TimelineBand::Count)> bands;

    const std::optional<TimelineBandGeometry> &geometry(TimelineBand band) const
    {
        return bands.at(timelineBandIndex(band));
    }

    std::optional<TimelineBandGeometry> &geometry(TimelineBand band)
    {
        return bands.at(timelineBandIndex(band));
    }

    friend bool operator==(const TimelineBandLayout &, const TimelineBandLayout &) = default;
};

} // namespace songview
