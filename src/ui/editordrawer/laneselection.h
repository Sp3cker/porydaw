#pragma once

#include <cstdint>
#include <utility>
#include <vector>

#include <QtGlobal>

#include "ui/editordrawer/nodelane/nodelane.h"

class AutomationProjection;
struct AutomationRow;

namespace songview {
class EditorSelectionModel;
}

// One selection view over the song EditorSelectionModel and the current CC
// row table, mapping LaneHandles (0 = tempo, 1..N = rows in row order) to
// selection coverage. Rebuilt on every row rebuild; holds borrowed pointers
// only, so a rebuild simply replaces the view.
class LaneSelection
{
  public:
    LaneSelection(const songview::EditorSelectionModel &model,
                  const std::vector<AutomationRow> &rows, uint32_t usedTrackMask) noexcept;

    bool active() const noexcept;
    // Tempo handle 0 -> timeSelectionCoversTempo(mask); a CC handle is
    // covered only when the selection is Lanes-scoped AND names that exact
    // (track, cc) row AND the row is present in the current row table.
    bool covers(LaneHandle handle) const noexcept;
    bool hitTest(LaneHandle handle, qreal x, const AutomationProjection &projection,
                 qreal dpr) const noexcept;
    // The selection's lanes that are still present in the row table, in row
    // order. The model sanitizes identities, so no dedupe is needed here.
    std::vector<std::pair<int, uint8_t>> visibleLanes() const noexcept;
    // {tempo, lanes} over the inclusive handle range [first, last]
    // (order-insensitive). The single time-selection publish encoder.
    std::pair<bool, std::vector<std::pair<int, uint8_t>>> laneSet(LaneHandle first,
                                                                  LaneHandle last) const noexcept;

  private:
    const songview::EditorSelectionModel *m_model = nullptr;
    const std::vector<AutomationRow> *m_rows = nullptr;
    uint32_t m_usedTrackMask = 0;
};