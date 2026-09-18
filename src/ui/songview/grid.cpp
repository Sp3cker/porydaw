#include "ui/songview/grid.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <numeric>

using namespace songview;

// --- songview::Grid: pure grid math ---

Grid::Grid(const TimeAxis &axis, const TimeCamera &camera) noexcept : m_axis(axis), m_camera(camera)
{}

Grid::Selections Grid::selections() const noexcept
{
    Selections ladder;
    ladder.values[ladder.count++] = GridSelection::automatic();
    const uint64_t floor = clockTicks();
    for (uint64_t denominator = 4; denominator <= std::numeric_limits<uint32_t>::max();
         denominator *= 2) {
        const GridSelection candidate = GridSelection::musical(uint32_t(denominator));
        const uint64_t ticks = musicalTicks(candidate, m_feel);
        if (ticks == 0 || ticks <= floor)
            break;
        ladder.values[ladder.count++] = candidate;
        if (denominator > std::numeric_limits<uint32_t>::max() / 2)
            break;
    }
    ladder.values[ladder.count++] = GridSelection::clock();
    return ladder;
}

GridSelection Grid::canonicalSelection(GridSelection selection) const
{
    if (selection.kind == GridSelection::Kind::Auto)
        return GridSelection::automatic();
    if (selection.kind == GridSelection::Kind::Musical &&
        musicalTicks(selection, m_feel) > clockTicks())
        return selection;
    return GridSelection::clock();
}

bool Grid::setSelection(GridSelection selection) noexcept
{
    return setState(selection, m_feel);
}

bool Grid::setFeel(GridFeel feel) noexcept
{
    return setState(m_selection, feel);
}

bool Grid::narrow() noexcept
{
    const auto ladder = selections();
    const auto current = std::find(ladder.begin(), ladder.end(), m_selection);
    if (current == ladder.end())
        return setSelection(m_selection);
    if (current + 1 == ladder.end())
        return false;
    return setSelection(*(current + 1));
}

bool Grid::widen() noexcept
{
    const auto ladder = selections();
    const auto current = std::find(ladder.begin(), ladder.end(), m_selection);
    if (current == ladder.end())
        return setSelection(m_selection);
    if (current == ladder.begin())
        return false;
    return setSelection(*(current - 1));
}

bool Grid::toggleFeel() noexcept
{
    const GridFeel previousFeel = m_feel;
    const GridSelection previousSelection = m_selection;
    const uint64_t previousSpacing = musicalTicks(previousSelection, previousFeel);

    m_feel = previousFeel == GridFeel::Straight ? GridFeel::Triplet : GridFeel::Straight;

    // Auto and Clock keep their spacing; only the feel preference flips.
    if (previousSelection.kind != GridSelection::Kind::Musical) {
        m_selection = previousSelection;
        return true;
    }

    const GridSelection counterpart = GridSelection::musical(previousSelection.denominator);
    if (canonicalSelection(counterpart) == counterpart) {
        m_selection = counterpart;
        return true;
    }

    // No representable counterpart: walk the new ladder once for the nearest
    // representable spacing in the expected direction — finer toward triplet
    // (at or below the old stride), coarser toward straight (at or above).
    const bool towardFiner = previousFeel == GridFeel::Straight;
    GridSelection nearest = GridSelection::clock();
    uint64_t nearestSpacing = towardFiner ? 0 : std::numeric_limits<uint64_t>::max();
    for (const GridSelection candidate : selections()) {
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
    m_selection = canonicalSelection(selection);
    return previousFeel != feel || previousSelection != m_selection;
}

bool Grid::setTicksPerClock(uint32_t ticksPerClock) noexcept
{
    const bool clockChanged = m_clock != ticksPerClock;
    m_clock = ticksPerClock;
    // Re-canonicalization runs even when the clock is unchanged; the
    // result reports a moved clock floor as a grid change too.
    return setState(m_selection, m_feel) || clockChanged;
}

void Grid::setThresholds(int timelineDetailMinimumPixelsPerBeat, int automationGridMinimumCellWidth,
                         int clockMinimumCellWidth) noexcept
{
    m_timelineDetailMinimumPixelsPerBeat = timelineDetailMinimumPixelsPerBeat;
    m_automationGridMinimumCellWidth = automationGridMinimumCellWidth;
    m_clockMinimumCellWidth = clockMinimumCellWidth;
}

Grid::Segment Grid::segmentAt(Tick tick) const
{
    return m_axis.segmentAt(tick);
}

GridCell Grid::visibleGridCellContaining(Tick tick) const
{
    const Segment seg = segmentAt(tick);
    const bool drawBeats = m_camera.pxPerBeat() >= m_timelineDetailMinimumPixelsPerBeat;
    uint64_t grid = seg.beatTicks;
    if (!drawBeats) {
        // The retained scene draws only bars at this zoom.
        grid *= seg.beatsPerBar;
    } else if (drawsSubGridIn(seg)) {
        // The retained scene also draws the current visible sub-grid in this segment.
        grid = uint64_t(gridTicksAt(tick));
    }
    grid = std::max<uint64_t>(1, grid);
    const uint64_t startRaw = (uint64_t(tick) - seg.start) / grid * grid + seg.start;
    const Tick start = Tick(startRaw);
    // One explicit uint64 computation keeps the overflow guard exact: test
    // `start`, not `tick`, since start <= tick.
    const uint64_t nextRaw = uint64_t(start) > CoreTimeDefaults::kMaxTick - grid
                                 ? CoreTimeDefaults::kNoTick
                                 : uint64_t(start) + grid;
    return {start, std::min(Tick(nextRaw), seg.next)};
}

Tick Grid::visibleGridTickDown(Tick tick) const
{
    return visibleGridCellContaining(tick).start;
}

Tick Grid::visibleGridTickUp(Tick tick) const
{
    return visibleGridCellContaining(tick).end;
}

Tick Grid::gridTicksAt(Tick tick) const
{
    if (m_selection.kind != GridSelection::Kind::Auto)
        return fixedTicks();
    return gridTicksIn(segmentAt(tick), m_camera.pxPerTick());
}

Tick Grid::subGridAnchorIn(const Segment &seg) const noexcept
{
    return m_selection.kind == GridSelection::Kind::Clock ? Tick(0) : seg.start;
}

bool Grid::drawsSubGridIn(const Segment &seg) const
{
    // A fixed selection draws its own lines while its cell clears the
    // selection's floor: the user pinned the denomination, so zoom cannot
    // retune the spacing — only suppress it. Snapping is unaffected.
    // Musical keeps the automation drawer's minimum cell width; Clock is
    // the document's real resolution, so it draws as many lines as
    // helpful — while its cells stay at least one grid-line stroke wide.
    if (m_selection.kind == GridSelection::Kind::Clock)
        return m_camera.pxPerTick() * double(fixedTicks()) >= m_clockMinimumCellWidth;
    if (m_selection.kind != GridSelection::Kind::Auto)
        return m_camera.pxPerTick() * double(fixedTicks()) >= m_automationGridMinimumCellWidth;
    return m_camera.pxPerTick() * double(seg.beatTicks) >= m_timelineDetailMinimumPixelsPerBeat;
}

Tick Grid::snapTicksAt(Tick tick) const
{
    return editingTicksAt(tick);
}

Tick Grid::gridTicksIn(const Segment &seg, double pixelsPerTick, bool snap) const
{
    const uint32_t clock = m_clock == 0 ? 1 : m_clock;
    // Finest visible subdivision at least automationGridMinimumCellWidth() wide from the
    // feel's ladder
    // (divisions per beat), floored at the mid2agb clock grid. The floor is
    // one division per beat of the governing signature (1/4 = the beat);
    // triplet feel fits three notes where straight fits two, so the same
    // denominator allows 3/2 the divisions.
    static constexpr uint64_t kStraight[] = {32, 16, 8, 4, 2, 1};
    static constexpr uint64_t kTriplet[] = {48, 24, 12, 6, 3, 1};
    const bool triplet = m_feel == GridFeel::Triplet;
    const double pxPerSegBeat = pixelsPerTick * double(seg.beatTicks);
    const uint64_t *ladder = triplet ? kTriplet : kStraight;
    constexpr int kSteps = 6;
    int step = kSteps - 1; // whole beats when even one-per-beat cells are
                           // too narrow (ladder[kSteps - 1] == 1)
    for (int i = 0; i < kSteps; i++) {
        if (pxPerSegBeat / double(ladder[i]) >= m_automationGridMinimumCellWidth) {
            step = i;
            break;
        }
    }
    // Snapping runs one ladder step finer than the drawn grid, so edits
    // aren't limited to visible lines. gcd keeps the snap grid a
    // divisor of the drawn grid when a beat's ticks don't split evenly, so
    // every drawn line stays snappable.
    const uint32_t vis = std::max(uint32_t(seg.beatTicks / ladder[step]), clock);
    if (!snap || step == 0)
        return vis;
    const uint32_t fine = std::max<uint32_t>(1, seg.beatTicks / ladder[step - 1]);
    return std::max(uint32_t(std::gcd(vis, fine)), clock);
}

Tick Grid::fineGridTicks() const
{
    return m_clock == 0 ? gridTicksAt(0) : std::max<uint32_t>(1, m_clock);
}

uint64_t Grid::clockTicks() const noexcept
{
    return std::max<uint64_t>(1, m_clock);
}

uint64_t Grid::musicalTicks(GridSelection selection, GridFeel feel) const noexcept
{
    if (selection.kind != GridSelection::Kind::Musical || selection.denominator < 4 ||
        (selection.denominator & (selection.denominator - 1)) != 0)
        return 0;

    const uint64_t ppqn = std::max<uint32_t>(1, m_axis.ticksPerBeat());
    const uint64_t numerator = ppqn * (feel == GridFeel::Straight ? 4 : 8);
    const uint64_t divisor = uint64_t(selection.denominator) * (feel == GridFeel::Straight ? 1 : 3);
    return numerator % divisor == 0 ? numerator / divisor : 0;
}

Tick Grid::fixedTicks() const noexcept
{
    if (m_selection.kind == GridSelection::Kind::Musical)
        // The clock base floors the stride: a musical selection whose
        // live-axis stride collapsed (unrepresentable denominator) falls
        // back to the clock lattice instead of feeding a zero stride to
        // the modulo/division consumers.
        return Tick(std::max(clockTicks(), musicalTicks(m_selection, m_feel)));
    return Tick(clockTicks());
}

Tick Grid::editingTicksAt(Tick tick) const
{
    if (m_selection.kind == GridSelection::Kind::Auto)
        return gridTicksIn(segmentAt(tick), m_camera.pxPerTick(), /*snap=*/true);
    return fixedTicks();
}

Tick Grid::Lattice::floor(double tick) const
{
    const double position = std::clamp(tick, double(anchor), double(limit));
    return CoreTimeDefaults::tickFromDouble(std::min(
        double(limit), double(anchor) + std::floor((position - anchor) / stride) * stride));
}

Tick Grid::Lattice::ceil(double tick) const
{
    const Tick lo = floor(tick);
    return double(lo) >= tick ? lo : Tick(std::min<uint64_t>(uint64_t(lo) + stride, limit));
}

Tick Grid::Lattice::round(double tick) const
{
    const Tick lo = floor(tick);
    const Tick hi = ceil(tick);
    const double lowerDistance = tick - double(lo);
    const double upperDistance = double(hi) - tick;
    return (tiesUp ? lowerDistance < upperDistance : lowerDistance <= upperDistance) ? lo : hi;
}

Grid::Lattice Grid::latticeAt(double tick, bool fine) const
{
    if (fine || m_selection.kind == GridSelection::Kind::Clock)
        return {0, uint64_t(fineGridTicks()), CoreTimeDefaults::kMaxTick, true};
    const Tick position = CoreTimeDefaults::tickFromDouble(tick);
    const Segment segment = segmentAt(position);
    return {segment.start, uint64_t(editingTicksAt(position)),
            std::min(segment.next, CoreTimeDefaults::kMaxTick), false};
}

Tick Grid::snapTick(double tick, bool fine) const
{
    return latticeAt(tick, fine).round(std::max(0.0, tick));
}

Tick Grid::snapTickDown(double tick, bool fine) const
{
    return latticeAt(tick, fine).floor(std::max(0.0, tick));
}

Tick Grid::snapTickUp(double tick, bool fine) const
{
    return latticeAt(tick, fine).ceil(std::max(0.0, tick));
}

Tick Grid::nextSubdivisionTickAfter(Tick tick) const
{
    const Segment segment = segmentAt(tick);
    const uint64_t grid = uint64_t(gridTicksAt(tick));
    const uint64_t anchor = uint64_t(subGridAnchorIn(segment));
    const uint64_t next = anchor + ((uint64_t(tick) - anchor) / grid + 1) * grid;
    // The absolute clock lattice crosses signature seams; segment-anchored
    // selections clamp at the next seam where their grid restarts.
    const uint64_t limit = m_selection.kind == GridSelection::Kind::Clock
                               ? uint64_t(CoreTimeDefaults::kMaxTick)
                               : std::min<uint64_t>(segment.next, CoreTimeDefaults::kMaxTick);
    return Tick(std::min(next, limit));
}

Tick Grid::nextSnapTickAfter(Tick tick, bool fine) const
{
    if (fine || m_selection.kind == GridSelection::Kind::Clock) {
        const uint64_t stride = uint64_t(fineGridTicks());
        const uint64_t next = (uint64_t(tick) / stride + 1) * stride;
        return Tick(std::min(next, uint64_t(CoreTimeDefaults::kMaxTick)));
    }
    const Segment segment = segmentAt(tick);
    const uint64_t stride = snapTicksAt(tick);
    const uint64_t anchor = segment.start;
    const uint64_t next = anchor + ((uint64_t(tick) - anchor) / stride + 1) * stride;
    return Tick(std::min({next, uint64_t(segment.next), uint64_t(CoreTimeDefaults::kMaxTick)}));
}
