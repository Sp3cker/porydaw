#include "ui/songview/grid.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>

namespace songview {
namespace {

uint64_t saturatingAdd(uint64_t left, uint64_t right) noexcept
{
    return right > std::numeric_limits<uint64_t>::max() - left
               ? std::numeric_limits<uint64_t>::max()
               : left + right;
}

uint64_t saturatingMultiply(uint64_t left, uint64_t right) noexcept
{
    if (left == 0 || right == 0)
        return 0;
    return right > std::numeric_limits<uint64_t>::max() / left
               ? std::numeric_limits<uint64_t>::max()
               : left * right;
}

double boundedTick(double tick) noexcept
{
    if (!(tick > 0.0))
        return 0.0;
    const double maximum = std::nextafter(double(std::numeric_limits<uint64_t>::max()), 0.0);
    return std::min(tick, maximum);
}

uint64_t absoluteTickDown(double tick, uint64_t spacing) noexcept
{
    const double bounded = boundedTick(tick);
    const uint64_t whole = uint64_t(std::floor(bounded / double(spacing)));
    return whole * spacing;
}

uint64_t absoluteTickUp(double tick, uint64_t spacing) noexcept
{
    const double bounded = boundedTick(tick);
    const uint64_t lower = absoluteTickDown(bounded, spacing);
    return double(lower) >= bounded ? lower : saturatingAdd(lower, spacing);
}

} // namespace

Grid::Grid(const TimeAxis &axis, const TimeCamera &camera) noexcept : m_axis(axis), m_camera(camera)
{}

std::span<const GridSelection> Grid::selections() const noexcept
{
    return std::span<const GridSelection>(m_selections.data(), m_selectionCount);
}

bool Grid::setSelection(GridSelection selection) noexcept
{
    if (!m_axis.isBound())
        return false;
    const GridSelection canonical = canonicalSelection(selection);
    if (canonical == m_selection)
        return false;
    m_selection = canonical;
    return true;
}

bool Grid::setFeel(GridFeel feel) noexcept
{
    if (feel == m_feel)
        return false;
    m_feel = feel;
    if (!m_axis.isBound()) {
        // The feel preference flips freely; the unbound grid stays Clock.
        m_selection = GridSelection::clock();
        return true;
    }
    rebuildSelections();
    m_selection = canonicalSelection(m_selection);
    return true;
}

bool Grid::narrow() noexcept
{
    if (!m_axis.isBound())
        return false;
    const int index = selectionIndex(m_selection);
    if (index < 0 || size_t(index + 1) >= m_selectionCount)
        return false;
    m_selection = m_selections[size_t(index + 1)];
    return true;
}

bool Grid::widen() noexcept
{
    if (!m_axis.isBound())
        return false;
    const int index = selectionIndex(m_selection);
    if (index <= 0)
        return false;
    m_selection = m_selections[size_t(index - 1)];
    return true;
}

bool Grid::toggleFeel() noexcept
{
    const GridFeel previousFeel = m_feel;
    const GridSelection previousSelection = m_selection;
    const uint64_t previousSpacing = editingTicks();
    m_feel = previousFeel == GridFeel::Straight ? GridFeel::Triplet : GridFeel::Straight;
    if (!m_axis.isBound()) {
        // Same unbound contract as setFeel: the preference flips freely and
        // the grid stays canonical Clock.
        m_selection = GridSelection::clock();
        return true;
    }

    rebuildSelections();
    if (previousSelection.kind == GridSelection::Kind::Clock) {
        m_selection = GridSelection::clock();
        return true;
    }

    const GridSelection counterpart = GridSelection::musical(previousSelection.denominator);
    if (selectionIndex(counterpart) >= 0) {
        m_selection = counterpart;
        return true;
    }

    // No representable counterpart: walk the new ladder once for the nearest
    // representable spacing in the expected direction — finer toward triplet
    // (at or below the old stride), coarser toward straight (at or above).
    const bool towardFiner = previousFeel == GridFeel::Straight;
    GridSelection nearest = GridSelection::clock();
    uint64_t nearestSpacing = towardFiner ? 0 : std::numeric_limits<uint64_t>::max();
    for (size_t i = 0; i < m_selectionCount; ++i) {
        const GridSelection candidate = m_selections[i];
        if (candidate.kind != GridSelection::Kind::Musical)
            continue;
        const uint64_t spacing = musicalTicks(candidate, m_feel);
        const bool closer = towardFiner ? spacing <= previousSpacing && spacing > nearestSpacing
                                        : spacing >= previousSpacing && spacing < nearestSpacing;
        if (closer) {
            nearest = candidate;
            nearestSpacing = spacing;
        }
    }
    m_selection = nearest;
    return true;
}

bool Grid::setState(GridSelection selection, GridFeel feel) noexcept
{
    const GridFeel previousFeel = m_feel;
    const GridSelection previousSelection = m_selection;
    m_feel = feel;
    rebuildSelections();
    m_selection = canonicalSelection(selection);
    return previousFeel != feel || previousSelection != m_selection;
}

void Grid::setTicksPerClock(uint32_t ticksPerClock) noexcept
{
    m_clock = ticksPerClock;
    rebuildSelections();
    // An unbound axis leaves the ladder empty, so canonicalSelection forces
    // Clock: an unbound grid never retains an invalid musical label.
    m_selection = canonicalSelection(m_selection);
}

void Grid::setThresholds(int timelineDetailMinimumPixelsPerBeat,
                         int automationGridMinimumCellWidth) noexcept
{
    m_timelineDetailMinimumPixelsPerBeat = timelineDetailMinimumPixelsPerBeat;
    m_automationGridMinimumCellWidth = automationGridMinimumCellWidth;
}

Grid::Segment Grid::segmentAt(uint64_t tick) const
{
    return m_axis.segmentAt(tick);
}

GridCell Grid::visibleGridCellContaining(uint64_t tick) const
{
    const Segment seg = segmentAt(tick);
    const bool drawBeats = m_camera.pxPerBeat() >= m_timelineDetailMinimumPixelsPerBeat;
    uint64_t grid = seg.beatTicks;
    if (!drawBeats) {
        // The retained scene draws only bars at this zoom.
        grid = saturatingMultiply(grid, seg.beatsPerBar);
    } else if (m_camera.pxPerTick() * double(seg.beatTicks) >=
               m_timelineDetailMinimumPixelsPerBeat) {
        // The retained scene also draws the current visible sub-grid in this segment.
        grid = visualTicksIn(seg, m_camera.pxPerTick());
    }
    grid = std::max<uint64_t>(1, grid);
    const uint64_t start = seg.start + ((tick - seg.start) / grid) * grid;
    return {start, std::min(saturatingAdd(start, grid), seg.next)};
}

uint64_t Grid::visibleGridTickDown(uint64_t tick) const
{
    return visibleGridCellContaining(tick).start;
}

uint64_t Grid::visibleGridTickUp(uint64_t tick) const
{
    return visibleGridCellContaining(tick).end;
}

uint64_t Grid::gridTicksAt(uint64_t tick) const
{
    return visualTicksIn(segmentAt(tick), m_camera.pxPerTick());
}

uint64_t Grid::gridTicksAtScale(uint64_t tick, double pixelsPerTick) const
{
    return visualTicksIn(segmentAt(tick), pixelsPerTick);
}

// Editing spacing is fixed by the selection alone, so the queried position
// cannot change it; the parameter keeps call sites symmetric with the
// zoom-adaptive gridTicksAt().
uint64_t Grid::snapTicksAt(uint64_t /*tick*/) const
{
    return editingTicks();
}

uint64_t Grid::fineGridTicks() const
{
    return clockTicks();
}

uint64_t Grid::snapTick(double tick, bool fine) const
{
    const double bounded = boundedTick(tick);
    if (fine || m_selection.kind == GridSelection::Kind::Clock) {
        const uint64_t spacing = fineGridTicks();
        const uint64_t lower = absoluteTickDown(bounded, spacing);
        const uint64_t upper = absoluteTickUp(bounded, spacing);
        // Round half up on the absolute clock lattice: an exact midpoint
        // tie takes the upper line (37 -> 38 at spacing 2).
        return bounded - double(lower) < double(upper) - bounded ? lower : upper;
    }

    const Segment seg = segmentAt(uint64_t(bounded));
    const uint64_t spacing = editingTicks();
    const uint64_t lower =
        seg.start + (uint64_t((bounded - double(seg.start)) / double(spacing)) * spacing);
    const uint64_t upper = std::min(saturatingAdd(lower, spacing), seg.next);
    // Musical ties keep the lower cell (existing contract).
    return bounded - double(lower) <= double(upper) - bounded ? lower : upper;
}

uint64_t Grid::snapTickDown(double tick, bool fine) const
{
    const double bounded = boundedTick(tick);
    if (fine || m_selection.kind == GridSelection::Kind::Clock)
        return absoluteTickDown(bounded, fineGridTicks());

    const Segment seg = segmentAt(uint64_t(bounded));
    const uint64_t spacing = editingTicks();
    return seg.start + (uint64_t((bounded - double(seg.start)) / double(spacing)) * spacing);
}

// Mirror of snapTickDown: shared floor, then one spacing step clamped to the
// governing segment; `fine` keeps both directions on the absolute clock.
uint64_t Grid::snapTickUp(double tick, bool fine) const
{
    const double bounded = boundedTick(tick);
    const uint64_t lower = snapTickDown(bounded, fine);
    if (double(lower) >= bounded)
        return lower;
    if (fine || m_selection.kind == GridSelection::Kind::Clock)
        return saturatingAdd(lower, fineGridTicks());
    return std::min(saturatingAdd(lower, editingTicks()), segmentAt(uint64_t(bounded)).next);
}

uint64_t Grid::nextEditingTick(uint64_t tick, uint64_t limit, bool fine) const
{
    if (tick >= limit)
        return limit;

    uint64_t next = 0;
    if (fine || m_selection.kind == GridSelection::Kind::Clock) {
        const uint64_t spacing = fineGridTicks();
        next = saturatingAdd(tick, spacing - tick % spacing);
    } else {
        const Segment seg = segmentAt(tick);
        const uint64_t spacing = editingTicks();
        const uint64_t offset = tick - seg.start;
        next = saturatingAdd(tick, spacing - offset % spacing);
        next = std::min(next, seg.next);
    }
    if (next <= tick)
        next = saturatingAdd(tick, 1);
    return std::min(next, limit);
}

uint64_t Grid::clockTicks() const noexcept
{
    return std::max<uint64_t>(1, m_clock);
}

uint64_t Grid::musicalTicks(GridSelection selection, GridFeel feel) const noexcept
{
    if (selection.kind != GridSelection::Kind::Musical || selection.denominator == 0)
        return 0;

    const uint64_t ppqn = std::max<uint32_t>(1, m_axis.ticksPerBeat());
    const uint64_t numerator = ppqn * (feel == GridFeel::Straight ? 4 : 8);
    const uint64_t divisor = uint64_t(selection.denominator) * (feel == GridFeel::Straight ? 1 : 3);
    return numerator % divisor == 0 ? numerator / divisor : 0;
}

uint64_t Grid::editingTicks() const noexcept
{
    // The clock base floors the stride: a musical selection whose live-axis
    // stride collapsed (unrepresentable denominator, or a rebind that
    // outran the cached ladder) falls back to the clock lattice instead of
    // feeding a zero stride to the modulo/division consumers.
    return std::max(clockTicks(), musicalTicks(m_selection, m_feel));
}

uint64_t Grid::visualTicksIn(const Segment &seg, double pixelsPerTick) const
{
    // Keep the existing adaptive guide ladder. It is entirely display policy:
    // selection never caps or otherwise changes its density.
    static constexpr uint64_t kStraight[] = {32, 16, 8, 4, 2, 1};
    static constexpr uint64_t kTriplet[] = {48, 24, 12, 6, 3, 1};
    const uint64_t *ladder = m_feel == GridFeel::Triplet ? kTriplet : kStraight;
    constexpr int kSteps = 6;
    const double pixelsPerBeat = pixelsPerTick * double(seg.beatTicks);
    int step = kSteps - 1;
    for (int i = 0; i < kSteps; ++i) {
        if (pixelsPerBeat / double(ladder[i]) >= m_automationGridMinimumCellWidth) {
            step = i;
            break;
        }
    }
    return std::max(clockTicks(), std::max<uint64_t>(1, seg.beatTicks / ladder[step]));
}

void Grid::rebuildSelections() noexcept
{
    m_selectionCount = 0;
    if (!m_axis.isBound())
        return;

    const uint64_t floor = clockTicks();
    for (uint64_t denominator = 4; denominator <= std::numeric_limits<uint32_t>::max();
         denominator *= 2) {
        const GridSelection candidate = GridSelection::musical(uint32_t(denominator));
        const uint64_t ticks = musicalTicks(candidate, m_feel);
        if (ticks == 0 || ticks <= floor)
            break;
        m_selections[m_selectionCount++] = candidate;
        if (denominator > std::numeric_limits<uint32_t>::max() / 2)
            break;
    }
    m_selections[m_selectionCount++] = GridSelection::clock();
}

GridSelection Grid::canonicalSelection(GridSelection selection) const noexcept
{
    if (selection.kind == GridSelection::Kind::Musical) {
        for (size_t i = 0; i < m_selectionCount; ++i) {
            if (m_selections[i] == selection)
                return selection;
        }
    }
    return GridSelection::clock();
}

int Grid::selectionIndex(GridSelection selection) const noexcept
{
    for (size_t i = 0; i < m_selectionCount; ++i) {
        if (m_selections[i] == selection)
            return int(i);
    }
    return -1;
}

} // namespace songview
