#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>

#include "ui/songview/timeaxis.h"
#include "ui/songview/timecamera.h"

namespace songview {

// Grid feel controls the exact whole-note subdivision ladder used by fixed
// editing selections. Visual guides may still adapt independently to zoom.
enum class GridFeel : uint8_t { Straight, Triplet };

struct GridSelection {
    enum class Kind { Musical, Clock };

    Kind kind = Kind::Musical;
    uint32_t denominator = 16;

    static constexpr GridSelection musical(uint32_t denominator) noexcept
    {
        return {Kind::Musical, denominator};
    }
    static constexpr GridSelection clock() noexcept { return {Kind::Clock, 0}; }

    constexpr bool operator==(const GridSelection &) const noexcept = default;
};

// One painted visible-grid cell. Cells are half-open [start, end): a
// tick exactly at an end belongs to the next cell.
struct GridCell {
    uint64_t start = 0;
    uint64_t end = 0;
};

// Pure grid math for the song view. Fixed selections determine editing
// spacing; the camera determines visible guides only. The axis and camera are
// stable SongView members, so Grid stores references and owns no allocations.
class Grid final
{
  public:
    using Segment = TimeAxis::GridSegment;

    Grid(const TimeAxis &axis, const TimeCamera &camera) noexcept;

    GridFeel feel() const noexcept { return m_feel; }
    GridSelection selection() const noexcept { return m_selection; }
    // Bounded cached ladder for the current feel. It remains valid until the
    // timing resolution or feel changes; it is empty while unbound.
    std::span<const GridSelection> selections() const noexcept;
    bool setSelection(GridSelection selection) noexcept;
    // Explicit feel assignment (ruler menu, restored feel). Rebuilds the
    // target feel's ladder and canonicalizes the current selection against
    // it; a selection the new feel cannot represent becomes Clock. Runs no
    // counterpart or nearest-cell heuristics — those are toggleFeel()'s.
    bool setFeel(GridFeel feel) noexcept;
    bool narrow() noexcept;
    bool widen() noexcept;
    // User counterpart command (Cmd+3): keeps the denominator when the
    // switched ladder represents it, else takes the nearest representable
    // cell in the expected direction (finer toward triplet, coarser toward
    // straight), Clock as fallback. At Clock it keeps the spacing and only
    // flips the feel preference.
    bool toggleFeel() noexcept;
    // Atomic programmatic assignment of the whole editing state: installs
    // the feel, rebuilds that feel's ladder, then canonicalizes the
    // selection against the new ladder — never against the live feel being
    // replaced. View-state restoration and setSong defaults use this.
    bool setState(GridSelection selection, GridFeel feel) noexcept;

    // Rebuilds the ladder against the current axis with this clock floor
    // (0 uses a one-tick floor). An unbound axis has an empty ladder and
    // canonical Clock selection. During synchronous song replacement,
    // setDocument may supply the incoming clock before setSong binds its
    // axis; setSong must revalidate again before the handoff completes.
    void setTicksPerClock(uint32_t ticksPerClock) noexcept;
    void setThresholds(int timelineDetailMinimumPixelsPerBeat,
                       int automationGridMinimumCellWidth) noexcept;

    // Time-signature segment governing a tick (the axis's GridSegment).
    // Musical cells restart only at signature changes, never ordinary bars.
    Segment segmentAt(uint64_t tick) const;
    GridCell visibleGridCellContaining(uint64_t tick) const;
    uint64_t visibleGridTickDown(uint64_t tick) const;
    uint64_t visibleGridTickUp(uint64_t tick) const;

    // Zoom-adaptive display-guide spacing. It deliberately ignores the fixed
    // editing selection and retains no user-selected minimum cap.
    uint64_t gridTicksAt(uint64_t tick) const;
    uint64_t gridTicksAtScale(uint64_t tick, double pixelsPerTick) const;

    // Fixed editing spacing, independent of camera zoom. Clock selection and
    // fine placement use the absolute clock lattice; musical placement is
    // anchored at the governing signature segment.
    uint64_t snapTicksAt(uint64_t tick) const;
    uint64_t fineGridTicks() const;
    uint64_t snapTick(double tick, bool fine = false) const;
    // `fine` forces the absolute clock lattice regardless of the selection
    // (pitch endpoint flooring); otherwise this is the selection's floor.
    uint64_t snapTickDown(double tick, bool fine = false) const;
    // Same contract mirrored upward: `fine` forces the absolute clock
    // lattice; otherwise this is the selection's ceil.
    uint64_t snapTickUp(double tick, bool fine = false) const;
    // The first editing boundary strictly after tick, clamped to limit. It
    // honors a signature boundary even if the fixed spacing is unchanged.
    uint64_t nextEditingTick(uint64_t tick, uint64_t limit, bool fine = false) const;

  private:
    static constexpr size_t kMaxSelections = 32;

    uint64_t clockTicks() const noexcept;
    uint64_t musicalTicks(GridSelection selection, GridFeel feel) const noexcept;
    // Editing strides are always positive: the clock base floors a musical
    // stride that a rebind could leave unrepresentable against the live axis.
    uint64_t editingTicks() const noexcept;
    uint64_t visualTicksIn(const Segment &seg, double pixelsPerTick) const;
    void rebuildSelections() noexcept;
    GridSelection canonicalSelection(GridSelection selection) const noexcept;
    int selectionIndex(GridSelection selection) const noexcept;

    const TimeAxis &m_axis;
    const TimeCamera &m_camera;
    GridFeel m_feel = GridFeel::Straight;
    GridSelection m_selection = GridSelection::clock(); // canonical Clock until the axis binds
    uint32_t m_clock = 0;
    std::array<GridSelection, kMaxSelections> m_selections = {};
    size_t m_selectionCount = 0;
    int m_timelineDetailMinimumPixelsPerBeat = 0;
    int m_automationGridMinimumCellWidth = 0;
};

} // namespace songview
