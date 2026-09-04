#pragma once

#include <cstdint>
#include <vector>

#include <QPoint>
#include <QRect>
#include <QString>

#include "core/songdocument.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/nodelane.h"

class AutomationPage;
// Song-wide Tempo is pinned to the canvas viewport bottom over Voice Change
// and the CC lanes. It deliberately has no controller or track identity.
// Interaction goes through the canvas NodeLane dispatcher; this type owns the
// header shell, collapse, BPM prompts, and the NodeLane adapter.
class TempoLane final : public NodeLane
{
  public:
    explicit TempoLane(AutomationPage *page) noexcept;
    explicit TempoLane(SongDocument &document) noexcept;

    QString title() const override;
    std::vector<NodePoint> points() const override;
    int minimumValue() const override;
    int maximumValue() const override;
    QString valueText(int value) const override;
    std::optional<NodePoint> leadIn() const override;
    void replaceSpan(uint64_t first, uint64_t last, const std::vector<NodePoint> &points) override;
    void updateLayout(int width, int top, int gutterWidth, const AutomationGeometry &geometry);
    int totalHeight(const AutomationGeometry &geometry) const;
    QRect bodyRect() const noexcept { return m_body; }
    QRect headerRect() const noexcept { return m_header; }
    bool expanded() const noexcept { return m_expanded; }
    bool containsHeader(const QPoint &position) const;
    void toggleExpanded();
    void cancel();
    bool promptValue(QWidget *parent, int currentValue, int *storedValue) const override;

  private:
    int collapsedHeight(const AutomationGeometry &geometry) const;
    int bodyHeight(const AutomationGeometry &geometry) const;

    AutomationPage *m_page = nullptr;
    SongDocument *m_document = nullptr;
    QRect m_header;
    QRect m_body;
    bool m_expanded = false;
};