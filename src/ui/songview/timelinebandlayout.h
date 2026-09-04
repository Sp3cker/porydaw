#pragma once

#include <QRect>
#include <QSize>

#include <algorithm>
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
    TrackHeaders,
    Count,
};

constexpr std::size_t timelineBandIndex(TimelineBand band)
{
    return static_cast<std::size_t>(band);
}

// Value contract: rect is the visible SongView-local band rectangle, already
// clipped/limited by the band's parent layout owner (spacer row, roll page
// minus scrollbar, drawer viewport/body). Hidden or fully occluded bands are
// nullopt. plotRect is the band's SongView-local time-plot rectangle; every
// time plot starts at SongView's canonical split, and a band without a time
// plot (TrackHeaders) carries an empty QRect(). Consumers can therefore
// intersect SongView's rect alone; no ancestor widget walking.
struct TimelineBandGeometry {
    QRect rect;
    QRect plotRect;

    QRect gutterRect() const noexcept
    {
        if (plotRect.isNull())
            return rect;

        const int gutterWidth = std::clamp(plotRect.left() - rect.left(), 0, rect.width());
        return {rect.topLeft(), QSize(gutterWidth, rect.height())};
    }
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
