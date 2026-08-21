#pragma once

#include <cstdint>
#include <vector>

#include <QPoint>
#include <QRect>
#include <QString>

#include "core/songdocument.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/nodelane.h"

namespace songview {
class EditorSelectionModel;
}

class AutomationCanvas;
class AutomationPage;
class QFont;
class QPainter;

// Song-wide Tempo lives above Voice Change and the CC lanes. It shares their
// canvas but deliberately has no controller or track identity. Interaction
// goes through the canvas NodeLane dispatcher; this type owns the header
// shell, collapse, BPM prompts, and the NodeLane adapter.
class TempoLane final : public NodeLane
{
  public:
    explicit TempoLane(AutomationPage *page) noexcept;
    TempoLane(SongDocument &document, const songview::EditorSelectionModel &selection,
              uint32_t usedTrackMask) noexcept;

    QString title() const override;
    std::vector<NodePoint> points() const override;
    int minimumValue() const override;
    int maximumValue() const override;
    QString valueText(int value) const override;
    bool pointSelected(uint64_t tick) const override;
    void deletePoints(const std::vector<uint64_t> &ticks) override;
    void movePoints(const std::vector<NodePointMove> &moves) override;
    void replaceSpan(uint64_t first, uint64_t last, const std::vector<NodePoint> &points) override;
    void updateLayout(int width, const AutomationGeometry &geometry);
    int totalHeight(const AutomationGeometry &geometry) const;
    QRect bodyRect() const noexcept { return m_body; }
    QRect headerRect() const noexcept { return m_header; }
    bool expanded() const noexcept { return m_expanded; }
    bool containsHeader(const QPoint &position) const;
    void toggleExpanded();
    bool hasTimeSelection() const;
    bool selectionContains(const AutomationProjection &projection, qreal x,
                           qreal devicePixelRatio) const;
    void cancel();
    bool promptBpm(AutomationCanvas &area, int currentBpm, int *bpm) const;
    void showTempoMenu(AutomationCanvas &area, const QPoint &globalPosition);
    void showTimeSelectionMenu(const QPoint &globalPosition) const;

    void paint(QPainter &painter, const AutomationGeometry &geometry, const QRect &labelGutter,
               const QFont &titleFont, const QFont &captionFont);

  private:
    int collapsedHeight(const AutomationGeometry &geometry) const;
    int bodyHeight(const AutomationGeometry &geometry) const;
    void applyEdit(const TempoEdit &edit) const;
    SongDocument *boundDocument() const noexcept;
    const songview::EditorSelectionModel *boundSelection() const noexcept;
    uint32_t boundUsedTrackMask() const noexcept;

    AutomationPage *m_page = nullptr;
    SongDocument *m_document = nullptr;
    const songview::EditorSelectionModel *m_selection = nullptr;
    uint32_t m_usedTrackMask = 0;
    QRect m_header;
    QRect m_body;
    bool m_expanded = false;
    std::vector<TempoPoint> m_clipboard;
};
