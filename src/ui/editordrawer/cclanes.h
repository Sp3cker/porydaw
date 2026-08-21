#pragma once

#include <cstdint>
#include <utility>
#include <vector>

#include "ui/editordrawer/nodelane/nodelane.h"
#include <QString>
#include <QtGlobal>

class AutomationPage;
class SongDocument;
struct AutomationGeometry;
struct AutomationRow;

namespace songview {
class EditorSelectionModel;
}

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

// CC lane table and CCLaneAdapter for the automation canvas. It owns the
// stable CC-row snapshot used by painting and input throughout an
// AutomationCanvas frame.
class CCLanes final
{
  public:
    static uint8_t bendController() noexcept;
    static bool rangeZoomable(uint8_t controller) noexcept;
    static uint8_t defaultRange(uint8_t controller) noexcept;
    static int autoRange(int maximum) noexcept;

    struct TimeSelection {
        uint64_t startTick = 0;
        uint64_t endTick = 0;
        std::vector<std::pair<int, uint8_t>> lanes;

        bool empty() const noexcept { return endTick <= startTick; }
        bool contains(uint64_t tick) const noexcept { return tick >= startTick && tick < endTick; }
        bool coversLane(int engineTrack, uint8_t cc) const noexcept
        {
            for (const auto &lane : lanes) {
                if (lane.first == engineTrack && lane.second == cc)
                    return true;
            }
            return false;
        }
        bool active() const noexcept { return !empty() && !lanes.empty(); }
    };

    enum class SummaryKind : uint8_t {
        None,
        Points,
        EmptyControl,
    };

    struct RowTextCache {
        QString title;
        QString secondary;
        SummaryKind summaryKind = SummaryKind::None;
        std::size_t pointCount = 0;
        int minimum = 0;
        int maximum = 0;
    };

    explicit CCLanes(AutomationPage *page) noexcept;
    ~CCLanes();

    const std::vector<AutomationRow> &rows() const noexcept { return m_rows; }
    const std::vector<RowTextCache> &rowText() const noexcept { return m_rowText; }
    std::vector<RowTextCache> &rowText() noexcept { return m_rowText; }
    const TimeSelection &timeSelection() const noexcept { return m_timeSelection; }
    TimeSelection &timeSelection() noexcept { return m_timeSelection; }

    void rebuildRows();
    void syncTimeSelection();
    int minimumHeight(const AutomationGeometry &geometry, int topInset) const;
    bool clearTimeSelection();

    QString titleFor(const AutomationRow &row) const;
    std::pair<int, uint8_t> rowIdentity(const AutomationRow &row) const;

    bool selectionContains(int rowIndex, qreal x, const AutomationGeometry &geometry,
                           qreal devicePixelRatio) const;

  private:
    AutomationPage *m_page = nullptr;
    std::vector<AutomationRow> m_rows;
    std::vector<RowTextCache> m_rowText;
    TimeSelection m_timeSelection;
};
