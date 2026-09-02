#pragma once

#include <cstdint>

#include "ui/songview/timeaxis.h"
#include "ui/songview/timecamera.h"

namespace songview {

// Grid feel: which subdivision ladder the visible grid and the snap grid
// walk. Straight fits two divisions per ladder step; triplet fits three
// where straight fits two.
enum class GridFeel : uint8_t { Straight, Triplet };

// One painted visible-grid cell. Cells are half-open [start, end): a
// tick exactly at an end belongs to the next cell.
struct GridCell {
    uint64_t start = 0;
    uint64_t end = 0;
};

// Pure zoom- and editor-dependent grid math for the song view: the visible
// subdivision, the snap grid, and fine placement. It reads the camera scale
// and the axis segments live and holds only scalar state — the grid feel,
// the user's minimum note denominator, the document's clock floor, and the
// two detail thresholds. No widgets, no document pointer, no notifications,
// no allocations; the SongView host pushes state and owns every side
// effect.
class Grid final
{
  public:
    using Segment = TimeAxis::GridSegment;

    // axis and camera are stable SongView members; Grid holds references
    // and never rebinds.
    Grid(const TimeAxis &axis, const TimeCamera &camera) noexcept;

    GridFeel feel() const noexcept { return m_feel; }
    int minDenom() const noexcept { return m_minDenom; }
    void setFeel(GridFeel feel) noexcept { m_feel = feel; }
    // 4/8/16/32; anything else normalizes to 0.
    static int normalizeMinDenom(int denom) noexcept;
    void setMinDenom(int denom) noexcept; // normalizes
    // The document's clock floor in ticks; 0 = no document (unbound).
    void setTicksPerClock(uint32_t ticksPerClock) noexcept;
    void setThresholds(int timelineDetailMinimumPixelsPerBeat,
                       int automationGridMinimumCellWidth) noexcept;

    // Time-signature segment governing a tick (the axis's GridSegment).
    // The grid — beats, snap positions, sub-beat lines — restarts at every
    // signature change and scales the beat by the signature's denominator.
    Segment segmentAt(uint64_t tick) const;
    GridCell visibleGridCellContaining(uint64_t tick) const;
    uint64_t visibleGridTickDown(uint64_t tick) const;
    uint64_t visibleGridTickUp(uint64_t tick) const;

    // Every tick-spacing accessor below returns a value >= 1 (floored at
    // the clock base), so callers may divide by them or use them as loop
    // strides without clamping.
    // Zoom-adaptive subdivision selected for the grid before the retained
    // scene suppresses sub-beat or beat lines at low detail.
    // It is not the painted-cell spacing; use visibleGridCellContaining().
    // The subdivision follows the governing segment's beat at the current
    // feel, floored at the minimum and never finer than the clock base.
    uint64_t gridTicksAt(uint64_t tick) const;
    // Visible grid at an explicit pixels-per-tick scale, using the
    // time-signature segment governing tick.
    uint64_t gridTicksAtScale(uint64_t tick, double pixelsPerTick) const;
    // Snap grid in ticks at a position: one feel-ladder step finer than the
    // visible grid, so edits can land halfway between drawn lines (thirds
    // stepping from beats in triplet feel). The minimum subdivision is a
    // display floor only — snapping steps past it too.
    uint64_t snapTicksAt(uint64_t tick) const;
    // Fine placement (Alt-drag in the lanes): the clock grid — the
    // document's real resolution — regardless of the zoom-dependent grid.
    // Unbound (no document), it falls back to the grid at tick 0.
    uint64_t fineGridTicks() const;
    // Nearest / previous snap-grid position, anchored at the governing
    // time-signature segment (fine snap stays on the absolute clock grid).
    uint64_t snapTick(double tick, bool fine = false) const;
    uint64_t snapTickDown(double tick) const;
    uint64_t snapTickUp(double tick) const;

  private:
    // Both exits floor at the clock base: the result is >= 1 for any
    // segment, so snap math may divide by it unchecked.
    uint64_t gridTicksIn(const Segment &seg, double pixelsPerTick, bool snap = false) const;

    const TimeAxis &m_axis;
    const TimeCamera &m_camera;
    GridFeel m_feel = GridFeel::Straight;
    int m_minDenom = 0;   // note denominator; 0 = clock-grid floor
    uint32_t m_clock = 0; // clock floor in ticks; 0 = no document
    int m_timelineDetailMinimumPixelsPerBeat = 0;
    int m_automationGridMinimumCellWidth = 0;
};

} // namespace songview
