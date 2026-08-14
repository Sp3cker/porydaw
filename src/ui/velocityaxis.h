#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include <QColor>
#include <QCoreApplication>
#include <QFont>
#include <QRectF>

#include "core/velocitymodel.h"

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

// One row of an Intrinsic (PSG) ruler: the level's own graduation, drawn at
// the center of the velocity band that level owns. The label is dropped on
// the rows a stride skips, so a short lane graduates every level but only
// names as many as fit.
struct VelocityAxisGraduation {
    uint8_t level = 0;
    uint8_t velocity = 1; // the level's representative
    bool active = false;  // an active value falls in this level
    bool labelVisible = true;
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
    Q_DECLARE_TR_FUNCTIONS(VelocityAxis) // the intrinsic rows' "Vol N" labels

  public:
    // Continuous: the plain 1-127 graduations. Intrinsic: one row per real
    // loudness level of the PSG voice the lane is editing, which is the only
    // thing that voice can hear the difference between.
    enum class Mode { Continuous, Intrinsic };

    static constexpr std::size_t MaximumTicks = 32;
    static constexpr std::size_t MaximumLabels = 17;
    static constexpr std::size_t MaximumMarkers = 2;
    static constexpr std::size_t MaximumGraduations = 16;

    VelocityAxis() = default;
    // Without a map the ruler is Continuous; a PSG map makes it Intrinsic.
    explicit VelocityAxis(const VelocityAxisGeometry &geometry,
                          const uint8_t *activeValues = nullptr, std::size_t activeValueCount = 0);
    VelocityAxis(const VelocityMap &map, const VelocityAxisGeometry &geometry,
                 const uint8_t *activeValues = nullptr, std::size_t activeValueCount = 0);

    Mode mode() const;
    const VelocityMap &map() const { return m_map; }
    const VelocityAxisGeometry &geometry() const { return m_geometry; }
    // y of velocity 127 and of velocity 1: the inset drawable band.
    double top() const { return m_top; }
    double bottom() const { return m_bottom; }
    double velocityToY(int velocity) const;
    // The inverse: the velocity a y in the plot stands for, clamped to the
    // drawable band so a drag past either inset simply pins at 1 or 127.
    int yToVelocity(double y) const;

    // Intrinsic only (a Continuous axis has no levels): the y a level's row
    // centers on, the level a y falls in, and the y where two levels meet.
    double levelToY(int level) const;
    int yToLevel(double y) const;
    double levelBoundaryToY(int lowerLevel) const;

    const std::array<VelocityAxisTick, MaximumTicks> &ticks() const { return m_ticks; }
    std::size_t tickCount() const { return m_tickCount; }
    const std::array<VelocityAxisLabel, MaximumLabels> &labels() const { return m_labels; }
    std::size_t labelCount() const { return m_labelCount; }
    const std::array<VelocityAxisMarker, MaximumMarkers> &markers() const { return m_markers; }
    std::size_t markerCount() const { return m_markerCount; }
    const std::array<VelocityAxisGraduation, MaximumGraduations> &graduations() const
    {
        return m_graduations;
    }
    std::size_t graduationCount() const { return m_graduationCount; }

    // The velocity a click in the ruler column asks for: a printed value
    // within half a label's height of y — a selection marker's or a fixed
    // label's — so the ruler reads as a row of clickable values rather than a
    // continuous slider (the un-labeled graduations between them are not
    // targets, and neither is a label a marker is covering). Build the axis
    // with the same active values the painted one has, or the markers it
    // must honor are missing. -1 when y hits nothing.
    //
    // An Intrinsic ruler answers instead with the representative of the level
    // the y falls in: every row is labeled with the value it stands for, so
    // the whole column is a target and there is nothing between the rows.
    int rulerVelocityAt(double y, double labelHeight) const;

    void paintRuler(QPainter &painter, const VelocityAxisPaintStyle &style) const;

  private:
    void buildTicks();
    void buildIntrinsicRows();
    // Whether an accented intrinsic label would overprint one at this y.
    bool activeNear(double y, double labelHeight) const;
    void buildMarkers(const uint8_t *activeValues, std::size_t activeValueCount);
    void addTick(uint8_t velocity);
    void addLabel(uint8_t velocity);
    bool isLabeled(uint8_t velocity) const;
    // Whether a selection marker's label would collide with a fixed one.
    bool markerNear(double y, double labelHeight) const;

    VelocityMap m_map;
    VelocityAxisGeometry m_geometry;
    std::array<VelocityAxisTick, MaximumTicks> m_ticks{};
    std::size_t m_tickCount = 0;
    std::array<VelocityAxisLabel, MaximumLabels> m_labels{};
    std::size_t m_labelCount = 0;
    std::array<VelocityAxisMarker, MaximumMarkers> m_markers{};
    std::size_t m_markerCount = 0;
    std::array<VelocityAxisGraduation, MaximumGraduations> m_graduations{};
    std::size_t m_graduationCount = 0;
    // Parallel to the graduations: each level's center and, one shorter, the
    // y where each level meets the one above it.
    std::array<double, MaximumGraduations> m_levelCenters{};
    std::array<double, MaximumGraduations - 1> m_levelBoundaries{};
    double m_top = 0.0;
    double m_bottom = 0.0;
};
