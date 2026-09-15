#pragma once

#include <array>
#include <cstdint>
#include <limits>

#include "ui/songview/timeaxis.h"
#include "ui/songview/timecamera.h"

namespace songview {

// Grid feel: which subdivision ladder the visible grid and the snap grid
// walk. Straight fits two divisions per ladder step; triplet fits three
// where straight fits two.
enum class GridFeel : uint8_t { Straight, Triplet };

// The user's editing-grid selection. Auto keeps the zoom-adaptive grid
// (snap runs one ladder step finer than the drawn grid); Musical pins the
// grid to an exact whole-note denominator; Clock pins it to the document's
// clock lattice. The selection governs both editing spacing and the painted
// sub-beat grid: a fixed selection draws exactly its own lines.
struct GridSelection {
    enum class Kind : uint8_t { Auto, Musical, Clock };

    Kind kind = Kind::Auto;
    uint32_t denominator = 0;

    static constexpr GridSelection automatic() noexcept { return {Kind::Auto, 0}; }
    static constexpr GridSelection musical(uint32_t denominator) noexcept
    {
        return {Kind::Musical, denominator};
    }
    static constexpr GridSelection clock() noexcept { return {Kind::Clock, 0}; }

    constexpr int toMenuId() const noexcept
    {
        return kind == Kind::Auto ? -1 : kind == Kind::Clock ? 0 : int(denominator);
    }
    static constexpr GridSelection fromMenuId(int id) noexcept
    {
        return id < 0 ? automatic() : id == 0 ? clock() : musical(uint32_t(id));
    }

    constexpr bool operator==(const GridSelection &) const noexcept = default;
};

// One painted visible-grid cell. Cells are half-open [start, end): a
// tick exactly at an end belongs to the next cell.
struct GridCell {
    Tick start = 0;
    Tick end = 0;
};

// Pure zoom- and editor-dependent grid math for the song view: the visible
// subdivision, the editing snap grid, and fine placement. It reads the
// camera scale and the axis segments live and holds only scalar state — the
// grid feel, the user's editing selection, the document's clock floor, and
// the two detail thresholds. The selection ladder is computed on demand, so
// no cached state can outrun an axis rebind. No widgets, no document
// pointer, no notifications; the SongView host pushes state and owns every
// side effect.
class Grid final
{
  public:
    using Segment = TimeAxis::GridSegment;

    // axis and camera are stable SongView members; Grid holds references
    // and never rebinds.
    Grid(const TimeAxis &axis, const TimeCamera &camera) noexcept;

    GridFeel feel() const noexcept { return m_feel; }
    GridSelection selection() const noexcept { return m_selection; }
    // The selectable ladder for the current feel, coarse to fine:
    // Auto, every representable musical denominator, then Clock. An
    // unbound axis still lists Auto and Clock.
    struct Selections {
        // Auto + Clock + every power-of-two denominator from 4 through
        // 2^(digits-1): digits - 2 musical rungs, so digits entries total.
        std::array<GridSelection, std::numeric_limits<uint32_t>::digits> values{};
        size_t count = 0;
        auto begin() const noexcept { return values.begin(); }
        auto end() const noexcept { return values.begin() + count; }
        size_t size() const noexcept { return count; }
        GridSelection operator[](size_t index) const noexcept { return values[index]; }
    };
    Selections selections() const noexcept;
    // Canonicalizes the selection against the live ladder: an
    // unrepresentable musical denominator becomes Clock. Returns whether
    // the effective selection changed.
    bool setSelection(GridSelection selection) noexcept;
    // Explicit feel assignment (ruler menu, restored feel). Canonicalizes
    // the current selection against the new feel's ladder; a selection the
    // new feel cannot represent becomes Clock. Runs no counterpart or
    // nearest-cell heuristics — those are toggleFeel()'s.
    bool setFeel(GridFeel feel) noexcept;
    // Step the selection one ladder position finer / coarser. Returns
    // whether the selection moved; at either end this is a no-op.
    bool narrow() noexcept;
    bool widen() noexcept;
    // User counterpart command (grid triplet toggle): keeps the denominator
    // when the switched ladder represents it, else takes the nearest
    // representable cell in the expected direction (finer toward triplet,
    // coarser toward straight), Clock as fallback. Auto and Clock
    // selections keep their spacing and only flip the feel preference.
    bool toggleFeel() noexcept;
    // Atomic programmatic assignment of the whole editing state: installs
    // the feel, then canonicalizes the selection against the new ladder —
    // never against the live feel being replaced. View-state restoration
    // and setSong defaults use this.
    bool setState(GridSelection selection, GridFeel feel) noexcept;

    // The document's clock floor in ticks; 0 = no document (unbound).
    // Re-canonicalizes the selection: a musical selection the new axis
    // cannot represent becomes Clock.
    bool setTicksPerClock(uint32_t ticksPerClock) noexcept;
    void setThresholds(int timelineDetailMinimumPixelsPerBeat,
                       int automationGridMinimumCellWidth) noexcept;

    // Time-signature segment governing a tick (the axis's GridSegment).
    // The grid — beats, snap positions, sub-beat lines — restarts at every
    // signature change and scales the beat by the signature's denominator.
    Segment segmentAt(Tick tick) const;
    GridCell visibleGridCellContaining(Tick tick) const;
    Tick visibleGridTickDown(Tick tick) const;
    Tick visibleGridTickUp(Tick tick) const;

    // Every tick-spacing accessor below returns a value >= 1 (floored at
    // the clock base), so callers may divide by them or use them as loop
    // strides without clamping.
    // Painted sub-beat spacing selected for the grid before the retained
    // scene suppresses sub-beat or beat lines at low detail.
    // It is not the painted-cell spacing; use visibleGridCellContaining().
    // Auto follows the governing segment's beat at the current feel and is
    // never finer than the clock base; Musical and Clock selections return
    // their fixed spacing and ignore the position.
    Tick gridTicksAt(Tick tick) const;
    // Anchor of the painted sub-beat lattice inside a segment: the
    // segment start for Auto/Musical (the grid restarts at every
    // signature change), absolute tick zero for Clock (the document's
    // clock lattice never re-anchors at a signature seam).
    Tick subGridAnchorIn(const Segment &seg) const noexcept;
    // Whether the painted sub-beat grid is drawn inside a segment at the
    // current zoom: Auto requires the beat-width detail threshold, fixed
    // selections require their cell to stay at least the minimum cell width.
    bool drawsSubGridIn(const Segment &seg) const;
    // Editing snap spacing in ticks at a position. Auto resolves the
    // zoom-adaptive snap grid (one feel-ladder step finer than the visible
    // grid, so edits can land halfway between drawn lines); Musical and
    // Clock selections return their fixed spacing and ignore the position.
    Tick snapTicksAt(Tick tick) const;
    // Fine placement (Alt-drag in the lanes): the clock grid — the
    // document's real resolution — regardless of the selection.
    // Unbound (no document), it falls back to the grid at tick 0.
    Tick fineGridTicks() const;
    // Nearest / previous / next editing-grid position. `fine` forces the
    // absolute clock lattice; otherwise the selection decides: Auto snaps
    // on the adaptive grid anchored at the governing segment, Musical on
    // its fixed spacing anchored at the governing segment, Clock on the
    // absolute lattice.
    Tick snapTick(double tick, bool fine = false) const;
    Tick snapTickDown(double tick, bool fine = false) const;
    Tick snapTickUp(double tick, bool fine = false) const;

    // Strictly next painted subdivision. Auto/Musical re-anchor at every
    // signature seam and clamp at the next seam and kMaxTick; Clock walks
    // the absolute lattice and clamps only at kMaxTick. At kMaxTick it
    // cannot advance. Uses gridTicksAt spacing, not painted cells or the
    // snap grid.
    Tick nextSubdivisionTickAfter(Tick tick) const;
    // Strictly next editing subdivision. Auto/Musical restart at
    // signature seams; `fine` and the Clock selection walk the absolute
    // clock lattice and never clamp at a seam.
    Tick nextSnapTickAfter(Tick tick, bool fine = false) const;

  private:
    struct Lattice {
        Tick anchor;
        uint64_t stride;
        Tick limit;
        bool tiesUp;
        Tick floor(double tick) const;
        Tick ceil(double tick) const;
        Tick round(double tick) const;
    };
    Lattice latticeAt(double tick, bool fine = false) const;
    // Both exits floor at the clock base: the result is >= 1 for any
    // segment, so snap math may divide by it unchecked.
    Tick gridTicksIn(const Segment &seg, double pixelsPerTick, bool snap = false) const;
    // The fixed selection's spacing: Musical on its exact stride, Clock on
    // the absolute lattice, both floored at the clock base. Only meaningful
    // for non-Auto selections.
    Tick fixedTicks() const noexcept;
    // The clock lattice spacing: the document's tick resolution, 1 unbound.
    uint64_t clockTicks() const noexcept;
    // Exact tick spacing of a musical selection under a feel; 0 when the
    // axis cannot represent it (non-integral subdivision).
    uint64_t musicalTicks(GridSelection selection, GridFeel feel) const noexcept;
    // The selection's editing spacing: adaptive for Auto (position
    // dependent), fixed for Musical/Clock, always >= the clock base.
    Tick editingTicksAt(Tick tick) const;
    GridSelection canonicalSelection(GridSelection selection) const;

    const TimeAxis &m_axis;
    const TimeCamera &m_camera;
    GridFeel m_feel = GridFeel::Straight;
    GridSelection m_selection;
    uint32_t m_clock = 0; // clock floor in ticks; 0 = no document
    int m_timelineDetailMinimumPixelsPerBeat = 0;
    int m_automationGridMinimumCellWidth = 0;
};

} // namespace songview
