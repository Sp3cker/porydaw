#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include <QColor>
#include <QFont>
#include <QRectF>

class QPainter;

// Value ruler for the velocity lane. The domain is always the editable MIDI
// velocity range 1-127 — the lane has no vertical zoom, so the only thing
// that changes with its height is how densely the ruler is graduated.
struct VelocityAxisGeometry {
    double height = 0.0;
    // Half a node's diameter, so the extreme velocities' nodes still fit.
    double verticalInset = 0.0;
    double labelHeight = 0.0;
    // Heights at which the ruler steps up to the next density band. Each is
    // exclusive: a lane exactly this tall already uses the denser band.
    double densityD1 = 0.0;
    double densityD2 = 0.0;
    double densityD3 = 0.0;
    double densityD4 = 0.0;
};

struct VelocityAxisTick {
    uint8_t velocity = 1;
    double y = 0.0;
};

struct VelocityAxisLabel {
    uint8_t velocity = 1;
    double y = 0.0;
};

// The extremes of the values the ruler is currently describing (the selected
// notes' velocities), called out on the ruler so a selection's span reads
// without hunting for its nodes.
struct VelocityAxisMarker {
    uint8_t velocity = 1;
    double y = 0.0;
};

struct VelocityAxisPaintStyle {
    QColor labelColor;
    QColor accentColor;
    QFont labelFont;
    QFont emphasizedFont;
    double separatorX = 0.0;
    double labelLeft = 0.0;
    double labelWidth = 0.0;
    double labelHeight = 0.0;
    double tickWidth = 1.0;
    double markerWidth = 1.5;
    double minorTickLength = 0.0;
    double majorTickLength = 0.0;
    double markerTickLength = 0.0;
};

class VelocityAxis
{
  public:
    static constexpr std::size_t MaximumTicks = 32;
    static constexpr std::size_t MaximumLabels = 17;
    static constexpr std::size_t MaximumMarkers = 2;

    VelocityAxis() = default;
    explicit VelocityAxis(const VelocityAxisGeometry &geometry,
                          const uint8_t *activeValues = nullptr, std::size_t activeValueCount = 0);

    const VelocityAxisGeometry &geometry() const { return m_geometry; }
    // y of velocity 127 and of velocity 1: the inset drawable band.
    double top() const { return m_top; }
    double bottom() const { return m_bottom; }
    double velocityToY(int velocity) const;

    const std::array<VelocityAxisTick, MaximumTicks> &ticks() const { return m_ticks; }
    std::size_t tickCount() const { return m_tickCount; }
    const std::array<VelocityAxisLabel, MaximumLabels> &labels() const { return m_labels; }
    std::size_t labelCount() const { return m_labelCount; }
    const std::array<VelocityAxisMarker, MaximumMarkers> &markers() const { return m_markers; }
    std::size_t markerCount() const { return m_markerCount; }

    void paintRuler(QPainter &painter, const VelocityAxisPaintStyle &style) const;

  private:
    void buildTicks();
    void buildMarkers(const uint8_t *activeValues, std::size_t activeValueCount);
    void addTick(uint8_t velocity);
    void addLabel(uint8_t velocity);
    bool isLabeled(uint8_t velocity) const;
    // Whether a selection marker's label would collide with a fixed one.
    bool markerNear(double y, double labelHeight) const;

    VelocityAxisGeometry m_geometry;
    std::array<VelocityAxisTick, MaximumTicks> m_ticks{};
    std::size_t m_tickCount = 0;
    std::array<VelocityAxisLabel, MaximumLabels> m_labels{};
    std::size_t m_labelCount = 0;
    std::array<VelocityAxisMarker, MaximumMarkers> m_markers{};
    std::size_t m_markerCount = 0;
    double m_top = 0.0;
    double m_bottom = 0.0;
};
