#pragma once

#include "roll_content.h"

#include <QtCore/qstring.h>

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace RollProjection {

struct Rect {
    double x = 0;
    double y = 0;
    double w = 0;
    double h = 0;
    uint32_t argb = 0;
};

struct Camera {
    double pixelsPerTick = 0;
    double keyHeight = 0;
    double scrollX = 0;
    double scrollY = 0;
    double dpr = 1;

    bool finite() const
    {
        return std::isfinite(pixelsPerTick) && std::isfinite(keyHeight) && std::isfinite(scrollX)
            && std::isfinite(scrollY) && std::isfinite(dpr) && dpr > 0;
    }
    double pixel() const { return 1.0 / dpr; }
    double scrollOriginX() const { return std::round(scrollX * dpr) / dpr; }
    double scrollOriginY() const { return std::round(scrollY * dpr) / dpr; }
    double contentTickX(double tick) const { return std::round(tick * pixelsPerTick * dpr) / dpr; }
    double viewX(double tick) const { return contentTickX(tick) - scrollOriginX(); }
    double contentRowEdge(int row) const { return std::round(double(row) * keyHeight * dpr) / dpr; }
    double viewRowTop(int row) const { return contentRowEdge(row) - scrollOriginY(); }
    double viewRowBottom(int row) const { return contentRowEdge(row + 1) - scrollOriginY(); }
    double totalHeight(int rowCount) const { return double(rowCount) * std::max(0.0, keyHeight); }
    int noteBorderPixels() const { return std::max(1, int(std::round(dpr))); }
    int selectionRingPixels(double selectionRingDip) const
    {
        return std::max(1, int(std::round(selectionRingDip * dpr)));
    }
};

inline Rect noteBox(const Camera &c, int row, double tick, double end,
                    const RollContent::Metrics &m)
{
    const double pixel = c.pixel();
    const double x0 = c.contentTickX(tick);
    const double x1 = c.contentTickX(end);
    const double top = c.contentRowEdge(row);
    const double bottom = c.contentRowEdge(row + 1);
    return Rect{x0 - c.scrollOriginX(), top + pixel - c.scrollOriginY(),
                std::max(m.noteMinWidth, x1 - x0),
                std::max(m.noteMinHeight * pixel, bottom - top - pixel) - pixel};
}

inline int fittedFrameThickness(double rectWidth, double rectHeight, double dpr,
                                int requestedPixels, int insetPixels)
{
    const int minDim = int(std::round(std::min(rectWidth, rectHeight) * dpr));
    return std::min(requestedPixels, std::max(0, (minDim - 1) / 2 - insetPixels));
}

inline const RollContent::GridSegment &segmentAt(const RollContent::TimeAxis &axis, uint64_t tick)
{
    const RollContent::GridSegment *result = &axis.segments.front();
    for (const RollContent::GridSegment &segment : axis.segments) {
        if (segment.start > tick)
            break;
        result = &segment;
    }
    return *result;
}

inline uint64_t clockTicks(const RollContent::TimeAxis &axis)
{
    return std::max<uint64_t>(1, axis.clockTicks);
}

inline uint64_t musicalTicks(const RollContent::TimeAxis &axis)
{
    const uint64_t denominator = axis.musicalDenominator;
    if (denominator < 4 || (denominator & (denominator - 1)) != 0)
        return 0;
    const bool triplet = axis.feel == 1;
    const uint64_t numerator = uint64_t(axis.ticksPerBeat) * (triplet ? 8 : 4);
    const uint64_t divisor = denominator * (triplet ? 3 : 1);
    return numerator % divisor == 0 ? numerator / divisor : 0;
}

inline uint64_t fixedTicks(const RollContent::TimeAxis &axis)
{
    return axis.selectionMode == 1 ? std::max(clockTicks(axis), musicalTicks(axis))
                                   : clockTicks(axis);
}

inline uint64_t gridTicksAt(const RollContent::TimeAxis &axis,
                            const RollContent::GridSegment &segment, double pixelsPerTick,
                            const RollContent::Metrics &m)
{
    if (axis.selectionMode != 0)
        return fixedTicks(axis);
    static constexpr uint64_t straight[] = {32, 16, 8, 4, 2, 1};
    static constexpr uint64_t triplet[] = {48, 24, 12, 6, 3, 1};
    const uint64_t *ladder = axis.feel == 1 ? triplet : straight;
    const uint64_t beat = segment.beatTicks;
    const double width = double(beat) * pixelsPerTick;
    int step = 5;
    for (int i = 0; i < 6; ++i) {
        if (width / double(ladder[i]) >= m.autoGridMinCell) {
            step = i;
            break;
        }
    }
    return std::max(clockTicks(axis), beat / ladder[step]);
}

inline bool drawsSubGridIn(const RollContent::TimeAxis &axis,
                           const RollContent::GridSegment &segment, double pixelsPerTick,
                           const RollContent::Metrics &m, double gridLineStroke)
{
    switch (axis.selectionMode) {
    case 2:
        return double(fixedTicks(axis)) * pixelsPerTick >= gridLineStroke;
    case 1:
        return double(fixedTicks(axis)) * pixelsPerTick >= m.autoGridMinCell;
    default:
        return double(segment.beatTicks) * pixelsPerTick >= m.detailMinPxPerBeat;
    }
}

template <typename Visit>
void forEachSubdivision(const RollContent::TimeAxis &axis, uint64_t begin, uint64_t end,
                        double pixelsPerTick, const RollContent::Metrics &m,
                        double gridLineStroke, Visit &&visit)
{
    const bool triplet = axis.feel == 1;
    uint64_t start = begin;
    while (start < end) {
        const RollContent::GridSegment &segment = segmentAt(axis, start);
        const uint64_t stop = std::min(end, segment.next);
        const uint64_t beat = segment.beatTicks;
        const uint64_t stride = gridTicksAt(axis, segment, pixelsPerTick, m);
        if (stride < beat && drawsSubGridIn(axis, segment, pixelsPerTick, m, gridLineStroke)) {
            const uint64_t anchor = axis.selectionMode == 2 ? 0 : segment.start;
            const uint64_t relative = start - anchor;
            uint64_t tick = anchor + (relative / stride + (relative % stride == 0 ? 0 : 1)) * stride;
            const uint64_t half = std::max<uint64_t>(1, beat / (triplet ? 3 : 2));
            const uint64_t quarter = std::max<uint64_t>(1, beat / (triplet ? 6 : 4));
            while (tick < stop) {
                const uint64_t beatRelative = (tick - segment.start) % beat;
                if (beatRelative != 0)
                    visit(tick, beatRelative % half == 0 ? 1 : beatRelative % quarter == 0 ? 2 : 3);
                tick += stride;
            }
        }
        start = stop;
    }
}

template <typename Visit>
void forEachGridLine(const RollContent::TimeAxis &axis, uint64_t begin, uint64_t end,
                     Visit &&visit)
{
    for (const RollContent::GridSegment &segment : axis.segments) {
        if (segment.start >= end)
            break;
        const uint64_t stop = std::min(segment.next, end);
        const uint64_t beat = segment.beatTicks;
        uint64_t k = begin > segment.start ? (begin - segment.start) / beat : 0;
        uint64_t tick = segment.start + k * beat;
        while (tick < stop) {
            if (tick >= begin)
                visit(segment, tick, k % segment.beatsPerBar == 0);
            if (beat >= stop - tick)
                break;
            tick += beat;
            ++k;
        }
    }
}

template <typename Visit>
void forEachNumberedGridLine(const RollContent::TimeAxis &axis, uint64_t begin, uint64_t end,
                             Visit &&visit)
{
    uint64_t bar = 1;
    const RollContent::GridSegment *current = nullptr;
    forEachGridLine(axis, begin, end,
                    [&](const RollContent::GridSegment &segment, uint64_t tick, bool isBar) {
        if (&segment != current) {
            const auto first = axis.segments.data();
            const auto target = &segment;
            const auto previous = current ? current + 1 : first;
            for (auto it = previous; it != target; ++it) {
                const uint64_t measure = uint64_t(it->beatTicks) * it->beatsPerBar;
                const uint64_t ticks = it->next - it->start;
                bar += ticks / measure + (ticks % measure != 0);
            }
            current = target;
        }
        const uint64_t k = (tick - segment.start) / segment.beatTicks;
        visit(segment, tick, isBar, bar + k / segment.beatsPerBar,
              k % segment.beatsPerBar + 1);
    });
}

inline QString keyName(int pitch)
{
    static const char *const names[] = {"C",  "C#", "D",  "D#", "E",  "F",
                                        "F#", "G",  "G#", "A",  "A#", "B"};
    const int p = std::clamp(pitch, 0, 127);
    return QString::fromLatin1(names[p % 12]) + QString::number(p / 12 - 1);
}

inline bool isBlackKey(int pitch)
{
    const int k = pitch % 12;
    return k == 1 || k == 3 || k == 6 || k == 8 || k == 10;
}

inline QString argbToHex(uint32_t argb)
{
    const uint32_t a = (argb >> 24) & 0xFF;
    const uint32_t r = (argb >> 16) & 0xFF;
    const uint32_t g = (argb >> 8) & 0xFF;
    const uint32_t b = argb & 0xFF;
    return a == 255 ? QString::asprintf("#%02X%02X%02X", r, g, b)
                    : QString::asprintf("#%02X%02X%02X%02X", a, r, g, b);
}

inline double srgbToLinear(double channel)
{
    return channel <= 0.04045 ? channel / 12.92 : std::pow((channel + 0.055) / 1.055, 2.4);
}

inline double relativeLuminance(uint32_t argb)
{
    return 0.2126 * srgbToLinear(double((argb >> 16) & 0xFF) / 255.0)
        + 0.7152 * srgbToLinear(double((argb >> 8) & 0xFF) / 255.0)
        + 0.0722 * srgbToLinear(double(argb & 0xFF) / 255.0);
}

inline double contrastRatio(uint32_t first, uint32_t second)
{
    const double lighter = std::max(relativeLuminance(first), relativeLuminance(second));
    const double darker = std::min(relativeLuminance(first), relativeLuminance(second));
    return (lighter + 0.05) / (darker + 0.05);
}

inline uint32_t contrastingTextColor(uint32_t fill, uint32_t light, uint32_t dark)
{
    return contrastRatio(fill, light) >= contrastRatio(fill, dark) ? light : dark;
}

inline uint32_t aaContrastInk(uint32_t fill, uint32_t light, uint32_t dark)
{
    const uint32_t preferred = contrastingTextColor(fill, light, dark);
    if (contrastRatio(fill, preferred) >= 4.5)
        return preferred;
    return contrastingTextColor(fill, 0xFFFFFFFFu, 0xFF000000u);
}

} // namespace RollProjection
