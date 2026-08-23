#pragma once

#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

#include <QtGlobal>

#include "ui/editorviewstate.h"

class AutomationProjection;
struct AutomationRow;

namespace songview {
class EditorSelectionModel;
}

// One selection view over the song EditorSelectionModel and the current CC
// row table. Rebuilt on every row rebuild; holds borrowed references only, so
// a rebuild simply replaces the view.
class LaneSelection
{
  public:
    LaneSelection(const songview::EditorSelectionModel &model,
                  const std::vector<AutomationRow> &rows, uint32_t usedTrackMask) noexcept;

    bool active() const noexcept;
    std::optional<std::pair<uint64_t, uint64_t>> activeTickRange() const noexcept;
    // coversLane drives lane selection hit/menu/reticle behavior. Tempo uses
    // tempo coverage; CC rows require Lanes scope and a visible row identity.
    bool coversLane(EditorAutomationRowId id) const noexcept;
    // coversNodes drives selected point paint/drag behavior. Tempo uses tempo
    // coverage; CC rows use the model's lane coverage in either scope.
    bool coversNodes(EditorAutomationRowId id) const noexcept;
    bool hitTest(EditorAutomationRowId id, qreal x, const AutomationProjection &projection,
                 qreal dpr) const noexcept;
    // The selection's lanes that are still present in the row table, in row
    // order. The model sanitizes identities, so no dedupe is needed here.
    std::vector<std::pair<int, uint8_t>> visibleLanes() const noexcept;
    // {tempo, lanes} over the inclusive visual interval between endpoint
    // identities. The single time-selection publish encoder.
    std::pair<bool, std::vector<std::pair<int, uint8_t>>>
    laneSet(EditorAutomationRowId first, EditorAutomationRowId last) const noexcept;

  private:
    const songview::EditorSelectionModel &m_model;
    const std::vector<AutomationRow> &m_rows;
    uint32_t m_usedTrackMask = 0;
};