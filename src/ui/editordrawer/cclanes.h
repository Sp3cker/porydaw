#pragma once

#include <cstdint>
#include <span>
#include <vector>

#include "ui/editordrawer/nodelane/nodelane.h"
#include <QString>

class AutomationPage;
class SongDocument;
struct AutomationRow;

class CCLaneAdapter final : public NodeLane
{
  public:
    CCLaneAdapter(SongDocument &document, int engineTrack, uint8_t controller) noexcept;

    QString title() const override;
    std::vector<NodePoint> points() const override;
    int minimumValue() const override;
    int maximumValue() const override;
    QString valueText(int value) const override;
    NodeValuePrompt valuePrompt(int storedValue) const override;
    int neutralValue() const override;
    std::optional<NodePoint> leadIn() const override;
    void replaceSpan(uint64_t first, uint64_t last, const std::vector<NodePoint> &points) override;

  private:
    SongDocument &m_document;
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
    // The eight supported CC identities in selector display order; Tempo is
    // not a CC and is appended by the canvas catalog after these.
    static std::span<const uint8_t> supportedControllers() noexcept;
    // Canonical lane title for any controller — bend, descriptor-backed XCMD
    // lanes, and plain M4A CCs. Single source of truth for lane labels.
    static QString laneLabel(uint8_t controller);
    static bool rangeZoomable(uint8_t controller) noexcept;
    static uint8_t defaultRange(uint8_t controller) noexcept;
    static int autoRange(int maximum) noexcept;

    struct RowTextCache {
        QString title;
    };

    explicit CCLanes(AutomationPage *page) noexcept;
    ~CCLanes();

    const std::vector<AutomationRow> &rows() const noexcept { return m_rows; }
    const std::vector<RowTextCache> &rowText() const noexcept { return m_rowText; }
    std::vector<RowTextCache> &rowText() noexcept { return m_rowText; }

    void rebuildRows();
    QString titleFor(const AutomationRow &row) const;

  private:
    AutomationPage *m_page = nullptr;
    std::vector<AutomationRow> m_rows;
    std::vector<RowTextCache> m_rowText;
};
