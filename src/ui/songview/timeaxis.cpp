#include "ui/songview/timeaxis.h"

#include <algorithm>
#include <cstddef>

namespace songview {
namespace {

// The fallback timebase. The default field values of GridSegment and
// ResolvedTimeSignature mirror this axis's implicit opening 4/4, so a
// default-constructed segment or signature IS the fallback shape.
constexpr uint32_t kFallbackTicksPerBeat = 24;

// Normalized signature fields shared by the segment and signature lookups:
// a blank numerator reads as 4, and the denominator shift is clamped so a
// corrupt 0x58 denominator cannot shift into undefined behavior. The floor
// keeps every beat length a valid stride.
uint64_t beatsPerBarFor(uint8_t numerator) noexcept
{
    return numerator ? numerator : 4;
}
uint64_t beatTicksFor(uint32_t ticksPerBeat, uint8_t denomPow2) noexcept
{
    return (std::max)(uint64_t(1), (uint64_t(ticksPerBeat) * 4) >> (std::min)(int(denomPow2), 63));
}

} // namespace

TimeAxis::TimeAxis() noexcept = default;

void TimeAxis::bind(const MidiTimeline *timeline) noexcept
{
    m_timeline = timeline;
}

bool TimeAxis::isBound() const noexcept
{
    return m_timeline != nullptr;
}

uint32_t TimeAxis::ticksPerBeat() const noexcept
{
    return m_timeline ? (std::max)(uint32_t(1), m_timeline->ticksPerBeat) : kFallbackTicksPerBeat;
}

uint64_t TimeAxis::lengthTicks() const noexcept
{
    return m_timeline ? m_timeline->lengthTicks : 0;
}

uint64_t TimeAxis::loopStartTick() const noexcept
{
    return m_timeline ? m_timeline->loopStartTick : UINT64_MAX;
}

uint64_t TimeAxis::loopEndTick() const noexcept
{
    return m_timeline ? m_timeline->loopEndTick : UINT64_MAX;
}

std::span<const TimeSigPoint> TimeAxis::explicitTimeSignatures() const noexcept
{
    return m_timeline ? std::span<const TimeSigPoint>(m_timeline->timeSigs)
                      : std::span<const TimeSigPoint>();
}

bool TimeAxis::hasImplicitOpeningSignature() const noexcept
{
    // Signatures are tick-sorted, so tick 0 is governed by an actual event
    // exactly when the first one sits at tick 0.
    return !m_timeline || m_timeline->timeSigs.empty() || m_timeline->timeSigs.front().tick != 0;
}

TimeAxis::ResolvedTimeSignature TimeAxis::signatureAt(uint64_t tick) const noexcept
{
    if (!m_timeline)
        return {};                                        // the fallback's implicit opening 4/4
    ResolvedTimeSignature resolved;                       // the implicit opening 4/4 at tick 0
    for (const TimeSigPoint &ts : m_timeline->timeSigs) { // tick-sorted
        if (ts.tick > tick)
            break;
        // Same-tick duplicates overwrite: the last at a tick wins.
        resolved.tick = ts.tick;
        resolved.numerator = int(beatsPerBarFor(ts.numerator));
        // Preserve raw MIDI exponent for UI and edit round-tripping;
        // beatTicksFor separately clamps the shift and timeSigLabel clamps presentation.
        resolved.denomPow2 = int(ts.denomPow2);
        resolved.implicit = false;
    }
    return resolved;
}

TimeAxis::GridSegment TimeAxis::segmentAt(uint64_t tick) const noexcept
{
    GridSegment seg; // the implicit opening 4/4 at tick 0
    seg.beatTicks = ticksPerBeat();
    if (!m_timeline)
        return seg;
    for (const TimeSigPoint &ts : m_timeline->timeSigs) { // tick-sorted
        if (ts.tick > tick) {
            seg.next = ts.tick;
            break;
        }
        // Same-tick duplicates overwrite: the last at a tick wins, matching
        // signatureAt() and forEachGridLine().
        seg.start = ts.tick;
        seg.beatTicks = beatTicksFor(ticksPerBeat(), ts.denomPow2);
        seg.beatsPerBar = beatsPerBarFor(ts.numerator);
    }
    return seg;
}

void TimeAxis::forEachGridLine(uint64_t tickBegin, uint64_t tickEnd,
                               const GridLineVisitor &visitor) const
{
    if (tickEnd <= tickBegin)
        return;
    const uint32_t tpb = ticksPerBeat();
    const std::span<const TimeSigPoint> sigs = explicitTimeSignatures();

    // Streaming walk over the implicit opening segment plus the explicit
    // signature segments, merging same-tick duplicates (the last at a tick
    // wins) instead of copying a segment list out of the timeline. `next`
    // always indexes the first signature strictly after seg.start.
    GridSegment seg; // the implicit opening 4/4 at tick 0
    seg.beatTicks = tpb;
    std::size_t next = 0;
    for (; next < sigs.size() && sigs[next].tick == 0; ++next) {
        seg.beatTicks = beatTicksFor(tpb, sigs[next].denomPow2);
        seg.beatsPerBar = beatsPerBarFor(sigs[next].numerator);
    }
    int bar = 1;
    while (seg.start < tickEnd) {
        const uint64_t segEnd = next < sigs.size() ? sigs[next].tick : tickEnd;
        const uint64_t clampedEnd = (std::min)(segEnd, tickEnd);
        if (seg.start < clampedEnd) {
            uint64_t k = tickBegin > seg.start ? (tickBegin - seg.start) / seg.beatTicks : 0;
            for (uint64_t tick = seg.start + k * seg.beatTicks; tick < clampedEnd;) {
                if (tick >= tickBegin)
                    visitor(tick, k % seg.beatsPerBar == 0, bar + int(k / seg.beatsPerBar),
                            int(k % seg.beatsPerBar) + 1);
                if (seg.beatTicks >= clampedEnd - tick)
                    break;
                tick += seg.beatTicks;
                ++k;
            }
        }
        if (next >= sigs.size())
            break;
        // Bar numbering carries across each segment's measure count,
        // including trailing partial measures, so bars stay 1-based over the
        // whole song rather than per segment.
        const uint64_t segTicks = sigs[next].tick - seg.start;
        const uint64_t barTicks = seg.beatTicks * seg.beatsPerBar;
        bar += int((segTicks + barTicks - 1) / barTicks);
        seg.start = sigs[next].tick;
        seg.beatTicks = beatTicksFor(tpb, sigs[next].denomPow2);
        seg.beatsPerBar = beatsPerBarFor(sigs[next].numerator);
        for (++next; next < sigs.size() && sigs[next].tick == seg.start; ++next) {
            seg.beatTicks = beatTicksFor(tpb, sigs[next].denomPow2);
            seg.beatsPerBar = beatsPerBarFor(sigs[next].numerator);
        }
    }
}

} // namespace songview
