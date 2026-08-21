#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/timeruler.h"

#include <QPainter>
#include <QRect>

#include <algorithm>
#include <array>
#include <climits>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <numeric>

using namespace songview;
using namespace songview::detail;

void SongView::setGridFeel(GridFeel feel)
{
    if (m_gridFeel == feel)
        return;
    if (m_editorDrawer)
        m_editorDrawer->cancelVisiblePageInteraction();
    m_gridFeel = feel;
    m_ruler->syncGridControls();
    refreshTimelineViews();
    refreshDrawerPages();
}
void SongView::setGridMinDenom(int denom)
{
    if (denom != 4 && denom != 8 && denom != 16 && denom != 32)
        denom = 0;
    if (m_gridMinDenom == denom)
        return;
    if (m_editorDrawer)
        m_editorDrawer->cancelVisiblePageInteraction();
    m_gridMinDenom = denom;
    m_ruler->syncGridControls();
    refreshTimelineViews();
}
SongView::GridSeg SongView::gridSegAt(uint64_t tick) const
{
    GridSeg seg;
    if (!m_timeline)
        return seg;
    const uint64_t tpb = std::max<uint32_t>(1, m_timeline->ticksPerBeat);
    seg.beatTicks = tpb;
    for (const TimeSigPoint &ts : m_timeline->timeSigs) { // tick-sorted
        if (ts.tick > tick) {
            seg.next = ts.tick;
            break;
        }
        // Same-tick duplicates overwrite: the last at a tick wins, matching
        // forEachGridLine.
        seg.start = ts.tick;
        seg.beatTicks =
            std::max<uint64_t>(1, (uint64_t(tpb) * 4) >> std::min<int>(ts.denomPow2, 63));
        seg.beatsPerBar = ts.numerator ? ts.numerator : 4;
    }
    return seg;
}
SongView::GridCell SongView::visibleGridCellContaining(uint64_t tick) const
{
    const GridSeg seg = gridSegAt(tick);
    const bool drawBeats = pxPerBeat() >= m_geometry.timelineDetailMinimumPixelsPerBeat;
    uint64_t grid = seg.beatTicks;
    if (!drawBeats) {
        // drawGrid paints only bars at this zoom.
        grid *= seg.beatsPerBar;
    } else if (m_pxPerTick * double(seg.beatTicks) >=
               m_geometry.timelineDetailMinimumPixelsPerBeat) {
        // drawGrid also paints the current visible sub-grid in this segment.
        grid = gridTicksIn(seg, m_pxPerTick, /*snap=*/false);
    }
    grid = std::max<uint64_t>(1, grid);
    const uint64_t start = seg.start + ((tick - seg.start) / grid) * grid;
    const uint64_t next = start > UINT64_MAX - grid ? UINT64_MAX : start + grid;
    return {start, std::min(next, seg.next)};
}
uint64_t SongView::visibleGridTickDown(uint64_t tick) const
{
    return visibleGridCellContaining(tick).start;
}
uint64_t SongView::visibleGridTickUp(uint64_t tick) const
{
    return visibleGridCellContaining(tick).end;
}
uint64_t SongView::gridTicksAt(uint64_t tick) const
{
    if (!m_timeline)
        return 24;
    return gridTicksIn(gridSegAt(tick), m_pxPerTick);
}
uint64_t SongView::gridTicksAtScale(uint64_t tick, double pixelsPerTick) const
{
    if (!m_timeline)
        return 24;
    return gridTicksIn(gridSegAt(tick), pixelsPerTick);
}
uint64_t SongView::snapTicksAt(uint64_t tick) const
{
    if (!m_timeline)
        return 24;
    return gridTicksIn(gridSegAt(tick), m_pxPerTick, /*snap=*/true);
}
uint64_t SongView::gridTicksIn(const GridSeg &seg, double pixelsPerTick, bool snap) const
{
    const uint64_t clock = m_document ? m_document->ticksPerClock() : 1;
    // Finest visible subdivision at least automationGridMinimumCellWidth() wide from the
    // feel's ladder
    // (divisions per beat), floored at the mid2agb clock grid and at the
    // user's minimum note value. The floor is one division per beat of the
    // governing signature (1/4 = the beat); triplet feel fits three notes
    // where straight fits two, so the same denominator allows 3/2 the
    // divisions.
    static constexpr uint64_t kStraight[] = {32, 16, 8, 4, 2, 1};
    static constexpr uint64_t kTriplet[] = {48, 24, 12, 6, 3, 1};
    const bool triplet = m_gridFeel == GridFeel::Triplet;
    const uint64_t maxDiv =
        m_gridMinDenom == 0
            ? UINT64_MAX
            : std::max<uint64_t>(1, uint64_t(m_gridMinDenom) * (triplet ? 3 : 2) / 8);
    const double pxPerSegBeat = pixelsPerTick * double(seg.beatTicks);
    const uint64_t *ladder = triplet ? kTriplet : kStraight;
    constexpr int kSteps = 6;
    int step = kSteps - 1; // whole beats when even one-per-beat cells are
                           // too narrow (ladder[kSteps - 1] == 1)
    for (int i = 0; i < kSteps; i++) {
        if (ladder[i] > maxDiv)
            continue;
        if (pxPerSegBeat / double(ladder[i]) >= m_geometry.automationGridMinimumCellWidth) {
            step = i;
            break;
        }
    }
    // Snapping runs one ladder step finer than the drawn grid, so edits
    // aren't limited to visible lines. The minimum subdivision is a display
    // floor only — snapping steps past it too. gcd keeps the snap grid a
    // divisor of the drawn grid when a beat's ticks don't split evenly, so
    // every drawn line stays snappable.
    const uint64_t vis = std::max(std::max<uint64_t>(1, seg.beatTicks / ladder[step]), clock);
    if (!snap || step == 0)
        return vis;
    const uint64_t fine = std::max<uint64_t>(1, seg.beatTicks / ladder[step - 1]);
    return std::max(std::gcd(vis, fine), clock);
}
uint64_t SongView::fineGridTicks() const
{
    return m_document ? std::max<uint32_t>(1, m_document->ticksPerClock()) : gridTicksAt(0);
}
uint64_t SongView::snapTick(double tick, bool fine) const
{
    tick = std::max(0.0, tick);
    if (fine) {
        // The clock grid is the document's absolute resolution; it does not
        // restart at time-signature changes.
        const double g = double(fineGridTicks());
        return uint64_t(std::round(tick / g) * g);
    }
    const GridSeg seg = gridSegAt(uint64_t(tick));
    const uint64_t g = std::max<uint64_t>(1, gridTicksIn(seg, m_pxPerTick, /*snap=*/true));
    const uint64_t k = uint64_t((tick - double(seg.start)) / double(g));
    const uint64_t lo = seg.start + k * g;
    // The next signature's tick is itself a grid position (the grid
    // restarts there), so the upper candidate never crosses it.
    const uint64_t hi = std::min(lo + g, seg.next);
    return tick - double(lo) <= double(hi) - tick ? lo : hi;
}
uint64_t SongView::snapTickDown(double tick) const
{
    tick = std::max(0.0, tick);
    const GridSeg seg = gridSegAt(uint64_t(tick));
    const uint64_t g = std::max<uint64_t>(1, gridTicksIn(seg, m_pxPerTick, /*snap=*/true));
    return seg.start + uint64_t((tick - double(seg.start)) / double(g)) * g;
}
uint64_t SongView::snapTickUp(double tick) const
{
    tick = std::max(0.0, tick);
    const GridSeg seg = gridSegAt(uint64_t(tick));
    const uint64_t g = std::max<uint64_t>(1, gridTicksIn(seg, m_pxPerTick, /*snap=*/true));
    const uint64_t lo = seg.start + uint64_t((tick - double(seg.start)) / double(g)) * g;
    if (double(lo) >= tick)
        return lo;
    // The next signature's tick is itself a grid position, so the upper
    // candidate never crosses it.
    return std::min(lo + g, seg.next);
}
DrawerPageGridState SongView::gridState(uint64_t tick, bool fineMode) const
{
    return {gridTicksAt(tick), fineMode ? fineGridTicks() : snapTicksAt(tick)};
}
bool SongView::paintGrid(QPainter &painter, const QRect &rect, qreal origin) const
{
    drawGrid(painter, this, rect, origin, m_geometry.timelineDetailMinimumPixelsPerBeat,
             m_geometry.gridLineStrokeWidth);
    return true;
}
void SongView::forEachGridLine(uint64_t tickBegin, uint64_t tickEnd,
                               const std::function<void(uint64_t, bool, int, int)> &fn) const
{
    if (!m_timeline || tickEnd <= tickBegin)
        return;
    const uint32_t tpb = m_timeline->ticksPerBeat;

    struct Seg {
        uint64_t tick;
        uint64_t beatTicks;
        int beatsPerBar;
    };
    std::vector<Seg> segs;
    segs.push_back({0, tpb, 4});
    for (const TimeSigPoint &ts : m_timeline->timeSigs) {
        uint64_t beatTicks = (uint64_t(tpb) * 4) >> std::min<int>(ts.denomPow2, 63);
        if (beatTicks < 1)
            beatTicks = 1;
        const Seg seg{ts.tick, beatTicks, ts.numerator ? ts.numerator : 4};
        if (ts.tick == segs.back().tick)
            segs.back() = seg;
        else
            segs.push_back(seg);
    }

    int bar = 1;
    for (size_t i = 0; i < segs.size(); i++) {
        const Seg &seg = segs[i];
        const uint64_t segEnd =
            i + 1 < segs.size() ? segs[i + 1].tick : std::max<uint64_t>(tickEnd, seg.tick);
        const uint64_t clampedEnd = std::min(segEnd, tickEnd);
        if (seg.tick < clampedEnd) {
            uint64_t k = tickBegin > seg.tick ? (tickBegin - seg.tick) / seg.beatTicks : 0;
            for (uint64_t tick = seg.tick + k * seg.beatTicks; tick < clampedEnd;
                 tick += seg.beatTicks, k++) {
                if (tick < tickBegin)
                    continue;
                fn(tick, k % seg.beatsPerBar == 0, bar + int(k / seg.beatsPerBar),
                   int(k % seg.beatsPerBar) + 1);
            }
        }
        if (i + 1 < segs.size()) {
            const uint64_t segTicks = segs[i + 1].tick - seg.tick;
            const uint64_t barTicks = seg.beatTicks * seg.beatsPerBar;
            bar += int((segTicks + barTicks - 1) / barTicks);
        }
    }
}
