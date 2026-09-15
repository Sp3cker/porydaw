#pragma once

#include <cstdint>
#include <span>
#include <vector>

#include "ui/editordrawer/nodelane/nodelane.h"
#include <QString>
class SongDocument;

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
    void replaceSpan(Tick first, Tick last, const std::vector<NodePoint> &points) override;

  private:
    SongDocument &m_document;
    int m_engineTrack = -1;
    uint8_t m_controller = 0;
};

class CCLanes final
{
  public:
    static uint8_t bendController() noexcept;
    // The supported CC identities in selector display order. Tempo is
    // represented by the separate first row in AutomationViewModel.
    static std::span<const uint8_t> supportedControllers() noexcept;
    // Canonical lane title for any controller — bend, descriptor-backed XCMD
    // lanes, and plain M4A CCs. Single source of truth for lane labels.
    static QString laneLabel(uint8_t controller);
    static bool rangeZoomable(uint8_t controller) noexcept;
    static uint8_t defaultRange(uint8_t controller) noexcept;
    static int autoRange(int maximum) noexcept;
};
