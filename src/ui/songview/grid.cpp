#include "ui/songview/grid.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <numeric>

using namespace songview;

// --- songview::Grid: pure grid math ---

Grid::Grid(const TimeAxis &axis, const TimeCamera &camera) noexcept : m_axis(axis), m_camera(camera)
{}
int Grid::normalizeMinDenom(int denom) noexcept
{
    if (denom != 4 && denom != 8 && denom != 16 && denom != 32)
        return 0;
    return denom;
}
void Grid::setMinDenom(int denom) noexcept
{
    m_minDenom = normalizeMinDenom(denom);
}
void Grid::setTicksPerClock(uint32_t ticksPerClock) noexcept
{
    m_clock = ticksPerClock;
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
        grid *= seg.beatsPerBar;
    } else if (m_camera.pxPerTick() * double(seg.beatTicks) >=
               m_timelineDetailMinimumPixelsPerBeat) {
        // The retained scene also draws the current visible sub-grid in this segment.
        grid = gridTicksIn(seg, m_camera.pxPerTick(), /*snap=*/false);
    }
    grid = std::max<uint64_t>(1, grid);
    const uint64_t start = seg.start + ((tick - seg.start) / grid) * grid;
    const uint64_t next = start > UINT64_MAX - grid ? UINT64_MAX : start + grid;
    return {start, std::min(next, seg.next)};
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
    return gridTicksIn(segmentAt(tick), m_camera.pxPerTick());
}
uint64_t Grid::gridTicksAtScale(uint64_t tick, double pixelsPerTick) const
{
    return gridTicksIn(segmentAt(tick), pixelsPerTick);
}
uint64_t Grid::snapTicksAt(uint64_t tick) const
{
    return gridTicksIn(segmentAt(tick), m_camera.pxPerTick(), /*snap=*/true);
}
uint64_t Grid::gridTicksIn(const Segment &seg, double pixelsPerTick, bool snap) const
{
    const uint64_t clock = m_clock == 0 ? 1 : m_clock;
    // Finest visible subdivision at least automationGridMinimumCellWidth() wide from the
    // feel's ladder
    // (divisions per beat), floored at the mid2agb clock grid and at the
    // user's minimum note value. The floor is one division per beat of the
    // governing signature (1/4 = the beat); triplet feel fits three notes
    // where straight fits two, so the same denominator allows 3/2 the
    // divisions.
    static constexpr uint64_t kStraight[] = {32, 16, 8, 4, 2, 1};
    static constexpr uint64_t kTriplet[] = {48, 24, 12, 6, 3, 1};
    const bool triplet = m_feel == GridFeel::Triplet;
    const uint64_t maxDiv =
        m_minDenom == 0 ? UINT64_MAX
                        : std::max<uint64_t>(1, uint64_t(m_minDenom) * (triplet ? 3 : 2) / 8);
    const double pxPerSegBeat = pixelsPerTick * double(seg.beatTicks);
    const uint64_t *ladder = triplet ? kTriplet : kStraight;
    constexpr int kSteps = 6;
    int step = kSteps - 1; // whole beats when even one-per-beat cells are
                           // too narrow (ladder[kSteps - 1] == 1)
    for (int i = 0; i < kSteps; i++) {
        if (ladder[i] > maxDiv)
            continue;
        if (pxPerSegBeat / double(ladder[i]) >= m_automationGridMinimumCellWidth) {
            step = i;
            break;
        }
    }
    // Snapping runs one ladder step finer than the drawn grid, so edits
    // aren't limited to visible lines. The minimum subdivision is a display
    // floor only — snapping steps past it too. gcd keeps the snap grid a
    // divisor of the drawn grid when a beat's ticks don't split evenly, so
    // every drawn line stays snappable.
    const uint64_t vis = std::max(seg.beatTicks / ladder[step], clock);
    if (!snap || step == 0)
        return vis;
    const uint64_t fine = std::max<uint64_t>(1, seg.beatTicks / ladder[step - 1]);
    return std::max(std::gcd(vis, fine), clock);
}
uint64_t Grid::fineGridTicks() const
{
    return m_clock == 0 ? gridTicksAt(0) : std::max<uint32_t>(1, m_clock);
}
uint64_t Grid::snapTick(double tick, bool fine) const
{
    tick = std::max(0.0, tick);
    if (fine) {
        // The clock grid is the document's absolute resolution; it does not
        // restart at time-signature changes.
        const double g = double(fineGridTicks());
        return uint64_t(std::round(tick / g) * g);
    }
    const Segment seg = segmentAt(uint64_t(tick));
    const uint64_t g = gridTicksIn(seg, m_camera.pxPerTick(), /*snap=*/true);
    const uint64_t k = uint64_t((tick - double(seg.start)) / double(g));
    const uint64_t lo = seg.start + k * g;
    // The next signature's tick is itself a grid position (the grid
    // restarts there), so the upper candidate never crosses it.
    const uint64_t hi = std::min(lo + g, seg.next);
    return tick - double(lo) <= double(hi) - tick ? lo : hi;
}
uint64_t Grid::snapTickDown(double tick) const
{
    tick = std::max(0.0, tick);
    const Segment seg = segmentAt(uint64_t(tick));
    const uint64_t g = gridTicksIn(seg, m_camera.pxPerTick(), /*snap=*/true);
    return seg.start + uint64_t((tick - double(seg.start)) / double(g)) * g;
}
uint64_t Grid::snapTickUp(double tick) const
{
    tick = std::max(0.0, tick);
    const Segment seg = segmentAt(uint64_t(tick));
    const uint64_t g = gridTicksIn(seg, m_camera.pxPerTick(), /*snap=*/true);
    const uint64_t lo = seg.start + uint64_t((tick - double(seg.start)) / double(g)) * g;
    if (double(lo) >= tick)
        return lo;
    // The next signature's tick is itself a grid position, so the upper
    // candidate never crosses it.
    return std::min(lo + g, seg.next);
}

// --- SongView: host setters and axis iteration ---

void SongView::setGridFeel(songview::GridFeel feel)
{
    if (m_grid.feel() == feel)
        return;
    if (m_editorDrawer)
        m_editorDrawer->cancelVisiblePageInteraction();
    m_grid.setFeel(feel);
    m_rulerControls->syncFromView();
    refreshTimelineViews(PianoRollQuickDirty::Grid);
    refreshDrawerPages();
}
void SongView::setGridMinDenom(int denom)
{
    denom = Grid::normalizeMinDenom(denom);
    if (m_grid.minDenom() == denom)
        return;
    if (m_editorDrawer)
        m_editorDrawer->cancelVisiblePageInteraction();
    m_grid.setMinDenom(denom);
    m_rulerControls->syncFromView();
    refreshTimelineViews(PianoRollQuickDirty::Grid);
    refreshDrawerPages();
}
void SongView::forEachGridLine(uint64_t tickBegin, uint64_t tickEnd,
                               const std::function<void(uint64_t, bool, int, int)> &fn) const
{
    m_timeAxis.forEachGridLine(tickBegin, tickEnd, fn);
}
