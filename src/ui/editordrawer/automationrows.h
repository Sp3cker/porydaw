#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

#include <QColor>
#include <QFont>
#include <QPointF>
#include <QString>

#include "core/songdocument.h"
#include "ui/editordrawer/automationgesture.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editorviewstate.h"
#include "ui/songviewmodel.h"

extern "C" {
#include "voicegroup_loader.h"
}

class AutomationArea;
class AutomationPage;
struct LaneNodeIdentity {
    int engineTrack = -1;
    uint8_t controller = 0;
    DocLanePoint documentPoint;
};

struct LaneNodeDragState {
    NodeDragGesture gesture;
    std::vector<LaneNodeIdentity> identities;
};

// Row data and caches for the automation canvas. It owns the stable row
// snapshot used by painting and input throughout an AutomationArea frame.
class AutomationRows final
{
  public:
    struct TimeSelection {
        SongDocument::TimeRange range;
        SongDocument::TimeScope scope;
        int firstRow = -1;
        int lastRow = -1;

        bool active() const noexcept
        {
            return !range.empty() && firstRow >= 0 && !scope.lanes.empty();
        }
    };

    enum class SummaryKind : uint8_t {
        None,
        Points,
        EmptyControl,
        VoiceChanges,
    };

    struct RowTextCache {
        QString title;
        QString secondary;
        SummaryKind summaryKind = SummaryKind::None;
        std::size_t pointCount = 0;
        int minimum = 0;
        int maximum = 0;
        int changeCount = 0;
    };

    struct ValueTextCache {
        EditorAutomationRowId row;
        int value = 0;
        QString text;
        bool valid = false;
    };

    struct VoicePaintText {
        const LoadedVoiceGroup *group = nullptr;
        int type = -1;
        std::array<char, VG_VOICE_NAME_LEN> sourceName{};
        QString label;
        QString hoverLabel;
    };

    explicit AutomationRows(AutomationPage *page) noexcept;

    const std::vector<AutomationRow> &rows() const noexcept { return m_rows; }
    const std::vector<RowTextCache> &rowText() const noexcept { return m_rowText; }
    std::vector<RowTextCache> &rowText() noexcept { return m_rowText; }
    const TimeSelection &timeSelection() const noexcept { return m_timeSelection; }
    TimeSelection &timeSelection() noexcept { return m_timeSelection; }

    void rebuildRows();
    void syncTimeSelection();
    void applyHeight(AutomationArea &area, const AutomationGeometry &geometry, int topInset) const;
    bool clearTimeSelection();

    const std::vector<LanePoint> &pointsFor(const AutomationRow &row,
                                            const AutomationProjection &projection) const;
    QString titleFor(const AutomationRow &row) const;
    const VoicePaintText &voicePaintTextFor(int program) const;
    QString valueTextFor(const AutomationRow &row, int value) const;
    bool rowTarget(const AutomationRow &row, int *track, uint8_t *controller) const;
    std::pair<int, uint8_t> rowIdentity(const AutomationRow &row) const;

    bool selectionContains(int rowIndex, qreal x, const AutomationGeometry &geometry,
                           qreal devicePixelRatio) const;
    bool pointInTimeSelection(int rowIndex, uint64_t tick) const;
    bool selectionHasMultipleNodes() const;
    LaneNodeDragState collectSelectedNodeDrags(const AutomationProjection &projection) const;
    bool cachedPointHit(const AutomationRow &row, int rowIndex, const QPointF &position,
                        const AutomationProjection &projection, const AutomationGeometry &geometry,
                        qreal devicePixelRatio, DocLanePoint *hit) const;
    std::optional<LaneNodeDragState>
    nodeDragGestureAt(int rowIndex, const QPointF &position, bool axisLockArmed,
                      const AutomationProjection &projection, bool pencilMode,
                      const AutomationGeometry &geometry, qreal devicePixelRatio) const;

  private:
    AutomationPage *m_page = nullptr;
    std::vector<AutomationRow> m_rows;
    std::vector<RowTextCache> m_rowText;
    TimeSelection m_timeSelection;
    mutable ValueTextCache m_valueTextCache;
    mutable std::array<VoicePaintText, VOICEGROUP_SIZE> m_voicePaintTexts;
};
