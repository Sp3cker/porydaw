#pragma once

#include <cstddef>
#include <optional>
#include <span>
#include <utility>
#include <vector>

#include <QtGlobal>

#include "core/timedefaults.h"
#include "ui/editorviewstate.h"

class AutomationProjection;
class MidiTimeline;
class SongDocument;

namespace songview {
class EditorSelectionModel;
}

struct AutomationViewModel {
    struct Row {
        EditorAutomationRowId id;
        std::size_t eventCount = 0;
        bool coversLane = false;
        bool coversNodes = false;
        bool selectionHasEvents = false;
    };

    std::optional<std::pair<Tick, Tick>> activeTickRange;
    std::vector<Row> rows;
    std::size_t visibleRowCount = 1;

    std::span<const Row> visibleRows() const noexcept;
    const Row *find(EditorAutomationRowId id) const noexcept;
    bool hitTest(EditorAutomationRowId id, qreal x, const AutomationProjection &projection,
                 qreal dpr, const songview::EditorSelectionModel &selection) const noexcept;
    std::vector<std::pair<int, uint8_t>>
    visibleLanes(const songview::EditorSelectionModel &selection) const noexcept;
    std::pair<bool, std::vector<std::pair<int, uint8_t>>>
    laneSet(EditorAutomationRowId first, EditorAutomationRowId last) const noexcept;
};

AutomationViewModel buildAutomationViewModel(const SongDocument &document,
                                             const MidiTimeline *timeline,
                                             const songview::EditorSelectionModel &selection,
                                             bool pageReady);
