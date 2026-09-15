#pragma once

#include <cstdint>
#include <vector>

#include <QString>

#include "core/songdocument.h"
#include "ui/editordrawer/nodelane/nodelane.h"

// Song-global NodeLane adapter for Tempo, with no controller or track identity.
// Interaction goes through the canvas NodeLane dispatcher.
class TempoLane final : public NodeLane
{
  public:
    explicit TempoLane(SongDocument &document) noexcept;

    QString title() const override;
    std::vector<NodePoint> points() const override;
    int minimumValue() const override;
    int maximumValue() const override;
    QString valueText(int value) const override;
    std::optional<NodePoint> leadIn() const override;
    void replaceSpan(Tick first, Tick last, const std::vector<NodePoint> &points) override;
    NodeValuePrompt valuePrompt(int storedValue) const override;

  private:
    SongDocument &m_document;
};
