#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

#include <QPointF>

#include "core/velocitymodel.h"

struct VelocityAxisGeometry {
    double height = 0.0;
    double verticalInset = 0.0;
    double labelWidth = 0.0;
    double labelSideInset = 0.0;
    double labelColumnGap = 0.0;
    double labelHeight = 0.0;
    double continuousDensityD1 = 0.0;
    double continuousDensityD2 = 0.0;
    double continuousDensityD3 = 0.0;
    double continuousDensityD4 = 0.0;
};

struct VelocityAxisTick {
    uint8_t velocity = 1;
    double y = 0.0;
};

struct VelocityAxisLabel {
    uint8_t velocity = 1;
    double y = 0.0;
    bool focusable = false;
    std::array<char, 4> label{};

    std::string_view labelText() const;
};

struct VelocityAxisGraduation {
    uint8_t level = 0;
    uint8_t velocity = 1;
    bool audible = false;
    bool active = false;
    bool labelVisible = true;
    bool emphasized = false;
    bool labelFocusable = false;
    uint8_t column = 0;
    double x = 0.0;
    double width = 0.0;
    double y = 0.0;
    std::array<char, 24> label{};

    std::string_view labelText() const;
};

struct VelocityAxisMarker {
    uint8_t velocity = 1;
    double y = 0.0;
};

// The ruler always maps the editable note-velocity domain 1–127. Intrinsic
// mode additionally divides that domain into one row per compatible PSG
// volume level. Row boundaries follow the velocities where effective volume
// changes, and nodes detent to the center of each row.
class VelocityAxis
{
  public:
    enum class Mode {
        Continuous,
        Intrinsic,
    };

    static constexpr std::size_t MaximumContinuousTicks = 32;
    static constexpr std::size_t MaximumContinuousLabels = 17;
    static constexpr std::size_t MaximumIntrinsicGraduations = 16;
    static constexpr std::size_t MAXIMUM_MARKERS = 2;

    VelocityAxis(const VelocityMap &map, const VelocityAxisGeometry &geometry,
                 std::span<const uint8_t> activeValues = {});

    Mode mode() const;
    const VelocityMap &map() const;
    const VelocityAxisGeometry &geometry() const;
    double top() const;
    double bottom() const;
    double drawableSpan() const;

    double velocityToY(int velocity) const;
    int yToVelocity(double y) const;
    double levelToY(int level) const;
    int yToLevel(double y) const;
    double levelBoundaryToY(int lowerLevel) const;

    const std::array<VelocityAxisTick, MaximumContinuousTicks> &ticks() const;
    std::size_t tickCount() const;
    const std::array<VelocityAxisLabel, MaximumContinuousLabels> &labels() const;
    std::size_t labelCount() const;
    bool hasLabel(uint8_t velocity) const noexcept;
    const std::array<VelocityAxisGraduation, MaximumIntrinsicGraduations> &graduations() const;
    std::size_t graduationCount() const;
    uint8_t intrinsicColumnCount() const;
    double intrinsicColumnWidth() const;
    const std::array<VelocityAxisMarker, MAXIMUM_MARKERS> &markers() const;
    std::size_t markerCount() const;
    std::string_view accessibleDescription() const;

    bool inRuler(const QPointF &position, double rulerWidth) const;
    int rulerVelocityAt(const QPointF &position, double labelHeight) const;

    static constexpr bool nodesFocusable() { return false; }

    static constexpr bool graduationLabelsFocusable() { return false; }

  private:
    void buildContinuousTicks();
    void buildIntrinsicRows();
    void buildContinuousMarkers(std::span<const uint8_t> activeValues);
    void addTick(uint8_t velocity);
    void addLabel(uint8_t velocity);
    void setAccessibleDescription();

    VelocityMap m_map;
    VelocityAxisGeometry m_geometry;
    std::array<VelocityAxisTick, MaximumContinuousTicks> m_ticks{};
    std::size_t m_tickCount = 0;
    std::array<VelocityAxisLabel, MaximumContinuousLabels> m_labels{};
    std::size_t m_labelCount = 0;
    std::array<VelocityAxisGraduation, MaximumIntrinsicGraduations> m_graduations{};
    std::size_t m_graduationCount = 0;
    std::array<VelocityAxisMarker, MAXIMUM_MARKERS> m_markers{};
    std::size_t m_markerCount = 0;
    std::array<char, 64> m_accessibleDescription{};
    double m_top = 0.0;
    double m_bottom = 0.0;
    uint8_t m_intrinsicColumnCount = 0;
    double m_intrinsicColumnWidth = 0.0;
    std::array<double, MaximumIntrinsicGraduations> m_levelCenters{};
    std::array<double, MaximumIntrinsicGraduations - 1> m_levelBoundaries{};
};
