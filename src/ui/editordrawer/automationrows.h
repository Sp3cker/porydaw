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
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editorviewstate.h"
#include "ui/songviewmodel.h"

extern "C" {
#include "voicegroup_loader.h"
}

class AutomationCanvas;
class AutomationPage;
namespace songview {
class EditorSelectionModel;
}
struct LaneNodeIdentity {
    int engineTrack = -1;
    uint8_t controller = 0;
    DocLanePoint documentPoint;
};

struct LaneNodeDragState {
    NodeDragGesture gesture;
    std::vector<LaneNodeIdentity> identities;
};

class CCLaneAdapter final : public NodeLane
{
  public:
    CCLaneAdapter(SongDocument &document, const songview::EditorSelectionModel &selection,
                  uint32_t usedTrackMask, int engineTrack, uint8_t controller) noexcept;

    QString title() const override;
    std::vector<NodePoint> points() const override;
    int minimumValue() const override;
    int maximumValue() const override;
    QString valueText(int value) const override;
    bool pointSelected(uint64_t tick) const override;
    void deletePoints(const std::vector<uint64_t> &ticks) override;
    void movePoints(const std::vector<NodePointMove> &moves) override;
    void replaceSpan(uint64_t first, uint64_t last, const std::vector<NodePoint> &points) override;

  private:
    SongDocument &m_document;
    const songview::EditorSelectionModel &m_selection;
    uint32_t m_usedTrackMask = 0;
    int m_engineTrack = -1;
    uint8_t m_controller = 0;
};

// Row data and caches for the automation canvas. It owns the stable row
// snapshot used by painting and input throughout an AutomationCanvas frame.
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
    void applyHeight(AutomationCanvas &area, const AutomationGeometry &geometry,
                     int topInset) const;
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
