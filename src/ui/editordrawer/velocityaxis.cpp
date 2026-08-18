#include "ui/editordrawer/velocityaxis.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <initializer_list>

#include <QPainter>

namespace {

constexpr int kMinimumVelocity = 1;
constexpr int kMaximumVelocity = 127;

double nonNegative(double value)
{
    return std::max(0.0, value);
}

uint8_t clampVelocity(int velocity)
{
    return uint8_t(std::clamp(velocity, kMinimumVelocity, kMaximumVelocity));
}

bool hasLabel(const VelocityAxis &axis, uint8_t velocity)
{
    for (std::size_t index = 0; index < axis.labelCount(); ++index) {
        if (axis.labels()[index].velocity == velocity)
            return true;
    }
    return false;
}

} // namespace

std::string_view VelocityAxisLabel::labelText() const
{
    return label.data();
}

std::string_view VelocityAxisGraduation::labelText() const
{
    return label.data();
}

VelocityAxis::VelocityAxis(const VelocityMap &map, const VelocityAxisGeometry &geometry,
                           std::span<const uint8_t> activeValues)
    : m_map(map)
    , m_geometry(geometry)
{
    const double height = nonNegative(m_geometry.height);
    const double inset = nonNegative(m_geometry.verticalInset);
    m_top = std::min(inset, height / 2.0);
    m_bottom = std::max(m_top, height - inset);
    setAccessibleDescription();
    buildContinuousTicks();
    buildContinuousMarkers(activeValues);
    if (mode() == Mode::Intrinsic)
        buildIntrinsicRows();
}

VelocityAxis::Mode VelocityAxis::mode() const
{
    return m_map.levelCount() == 0 ? Mode::Continuous : Mode::Intrinsic;
}

const VelocityMap &VelocityAxis::map() const
{
    return m_map;
}

const VelocityAxisGeometry &VelocityAxis::geometry() const
{
    return m_geometry;
}

double VelocityAxis::top() const
{
    return m_top;
}

double VelocityAxis::bottom() const
{
    return m_bottom;
}

double VelocityAxis::drawableSpan() const
{
    return m_bottom - m_top;
}

double VelocityAxis::velocityToY(int velocity) const
{
    const int clamped = std::clamp(velocity, kMinimumVelocity, kMaximumVelocity);
    if (drawableSpan() == 0.0)
        return m_bottom;
    return m_bottom - double(clamped - kMinimumVelocity) * drawableSpan() /
                          double(kMaximumVelocity - kMinimumVelocity);
}

int VelocityAxis::yToVelocity(double y) const
{
    if (drawableSpan() == 0.0)
        return kMinimumVelocity;
    const double clampedY = std::clamp(y, m_top, m_bottom);
    const double scaled =
        (m_bottom - clampedY) * double(kMaximumVelocity - kMinimumVelocity) / drawableSpan();
    return std::clamp(kMinimumVelocity + int(std::lround(scaled)), kMinimumVelocity,
                      kMaximumVelocity);
}

double VelocityAxis::levelToY(int level) const
{
    const int highestLevel = std::max(0, int(m_map.levelCount()) - 1);
    return m_levelCenters[std::size_t(std::clamp(level, 0, highestLevel))];
}

int VelocityAxis::yToLevel(double y) const
{
    const int highestLevel = std::max(0, int(m_map.levelCount()) - 1);
    int level = 0;
    while (level < highestLevel && y <= m_levelBoundaries[std::size_t(level)])
        ++level;
    return level;
}

double VelocityAxis::levelBoundaryToY(int lowerLevel) const
{
    const int highestBoundary = std::max(0, int(m_map.levelCount()) - 2);
    return m_levelBoundaries[std::size_t(std::clamp(lowerLevel, 0, highestBoundary))];
}

const std::array<VelocityAxisTick, VelocityAxis::MaximumContinuousTicks> &
VelocityAxis::ticks() const
{
    return m_ticks;
}

std::size_t VelocityAxis::tickCount() const
{
    return m_tickCount;
}

const std::array<VelocityAxisLabel, VelocityAxis::MaximumContinuousLabels> &
VelocityAxis::labels() const
{
    return m_labels;
}

std::size_t VelocityAxis::labelCount() const
{
    return m_labelCount;
}

const std::array<VelocityAxisGraduation, VelocityAxis::MaximumIntrinsicGraduations> &
VelocityAxis::graduations() const
{
    return m_graduations;
}

std::size_t VelocityAxis::graduationCount() const
{
    return m_graduationCount;
}

uint8_t VelocityAxis::intrinsicColumnCount() const
{
    return m_intrinsicColumnCount;
}

double VelocityAxis::intrinsicColumnWidth() const
{
    return m_intrinsicColumnWidth;
}

const std::array<VelocityAxisMarker, VelocityAxis::MAXIMUM_MARKERS> &VelocityAxis::markers() const
{
    return m_markers;
}

std::size_t VelocityAxis::markerCount() const
{
    return m_markerCount;
}

std::string_view VelocityAxis::accessibleDescription() const
{
    return m_accessibleDescription.data();
}

void VelocityAxis::paintRuler(QPainter &painter, const VelocityAxisPaintStyle &style) const
{
    painter.save();
    if (mode() == Mode::Intrinsic && !style.continuousRuler) {
        for (std::size_t index = 0; index < m_graduationCount; ++index) {
            const VelocityAxisGraduation &graduation = m_graduations[index];
            const bool emphasizeLabel =
                graduation.active && (style.relativeGesture || !graduation.labelVisible);
            painter.setPen(QPen(graduation.active ? style.accentColor : style.labelColor,
                                graduation.active ? style.markerWidth : style.tickWidth));
            painter.drawLine(QPointF(style.separatorX - style.graduationTickLength, graduation.y),
                             QPointF(style.separatorX, graduation.y));
            if ((!style.relativeGesture && graduation.labelVisible) || emphasizeLabel) {
                painter.setFont(emphasizeLabel ? style.emphasizedFont : style.labelFont);
                painter.setPen(style.labelColor);
                const QString label =
                    style.showIntrinsicVelocity
                        ? QString::number(graduation.velocity)
                        : QStringLiteral("Vol %1").arg(unsigned(graduation.level) + 1);
                painter.drawText(QRectF(style.labelLeft, graduation.y - style.labelHeight / 2.0,
                                        style.labelWidth, style.labelHeight),
                                 Qt::AlignRight | Qt::AlignVCenter, label);
            }
        }
    } else {
        painter.setPen(QPen(style.labelColor, style.tickWidth));
        for (std::size_t index = 0; index < m_tickCount; ++index) {
            const VelocityAxisTick &tick = m_ticks[index];
            const double tickLength =
                hasLabel(*this, tick.velocity) ? style.majorTickLength : style.minorTickLength;
            painter.drawLine(QPointF(style.separatorX - tickLength, tick.y),
                             QPointF(style.separatorX, tick.y));
        }
        if (!style.relativeGesture) {
            painter.setFont(style.labelFont);
            painter.setPen(style.labelColor);
            for (std::size_t index = 0; index < m_labelCount; ++index) {
                const VelocityAxisLabel &label = m_labels[index];
                painter.drawText(QRectF(style.labelLeft, label.y - style.labelHeight / 2.0,
                                        style.labelWidth, style.labelHeight),
                                 Qt::AlignRight | Qt::AlignVCenter,
                                 QString::fromLatin1(label.label.data()));
            }
        }
        for (std::size_t index = 0; index < m_markerCount; ++index) {
            const VelocityAxisMarker &marker = m_markers[index];
            painter.setPen(QPen(style.accentColor, style.markerWidth));
            painter.drawLine(QPointF(style.separatorX - style.markerTickLength, marker.y),
                             QPointF(style.separatorX, marker.y));
            if (style.relativeGesture) {
                painter.setFont(style.emphasizedFont);
                painter.setPen(style.labelColor);
                painter.drawText(QRectF(style.labelLeft, marker.y - style.labelHeight / 2.0,
                                        style.labelWidth, style.labelHeight),
                                 Qt::AlignRight | Qt::AlignVCenter,
                                 QString::number(marker.velocity));
            }
        }
    }
    painter.restore();
}

bool VelocityAxis::inRuler(const QPointF &position, double rulerWidth) const
{
    return position.x() >= 0.0 && position.x() < rulerWidth;
}

int VelocityAxis::rulerVelocityAt(const QPointF &position, double labelHeight) const
{
    if (mode() == Mode::Intrinsic)
        return m_map.representative(yToLevel(position.y()));
    const double textRadius = labelHeight / 2.0;
    for (std::size_t index = 0; index < m_labelCount; ++index) {
        const VelocityAxisLabel &label = m_labels[index];
        if (std::abs(position.y() - label.y) <= textRadius)
            return label.velocity;
    }
    return -1;
}

void VelocityAxis::buildContinuousTicks()
{
    const double span = nonNegative(m_geometry.height);
    if (span < m_geometry.continuousDensityD1) {
        for (const uint8_t velocity :
             {uint8_t{127}, uint8_t{96}, uint8_t{64}, uint8_t{32}, uint8_t{1}})
            addTick(velocity);
        for (const uint8_t velocity : {uint8_t{127}, uint8_t{64}, uint8_t{1}})
            addLabel(velocity);
        return;
    }
    if (span < m_geometry.continuousDensityD2) {
        addTick(127);
        for (int velocity = 112; velocity >= 16; velocity -= 16)
            addTick(uint8_t(velocity));
        addTick(1);
        for (const uint8_t velocity : {uint8_t{127}, uint8_t{64}, uint8_t{1}})
            addLabel(velocity);
        return;
    }
    if (span < m_geometry.continuousDensityD3) {
        addTick(127);
        for (int velocity = 112; velocity >= 16; velocity -= 16)
            addTick(uint8_t(velocity));
        addTick(1);
        for (const uint8_t velocity :
             {uint8_t{127}, uint8_t{96}, uint8_t{64}, uint8_t{32}, uint8_t{1}})
            addLabel(velocity);
        return;
    }
    if (span < m_geometry.continuousDensityD4) {
        addTick(127);
        for (int velocity = 120; velocity >= 8; velocity -= 8)
            addTick(uint8_t(velocity));
        addTick(1);
        addLabel(127);
        for (int velocity = 112; velocity >= 16; velocity -= 16)
            addLabel(uint8_t(velocity));
        addLabel(1);
        return;
    }

    addTick(127);
    for (int velocity = 123; velocity >= 7; velocity -= 4)
        addTick(uint8_t(velocity));
    addTick(1);
    addLabel(127);
    for (int velocity = 120; velocity >= 8; velocity -= 8)
        addLabel(uint8_t(velocity));
    addLabel(1);
}

void VelocityAxis::buildIntrinsicRows()
{
    const std::size_t levelCount = m_map.levelCount();
    std::size_t labelStride = 1;
    const double levelHeight = levelCount == 0 ? 0.0 : drawableSpan() / double(levelCount);
    while (labelStride <= levelCount &&
           levelHeight * double(labelStride) < nonNegative(m_geometry.labelHeight))
        labelStride *= 2;
    for (std::size_t level = 0; level + 1 < levelCount; ++level) {
        const VelocityLevelRange lower = m_map.levelRange(int(level));
        const VelocityLevelRange upper = m_map.levelRange(int(level + 1));
        m_levelBoundaries[level] = (velocityToY(lower.last) + velocityToY(upper.first)) / 2.0;
    }
    for (std::size_t level = 0; level < levelCount; ++level) {
        const double lowerBoundary = level == 0 ? m_bottom : m_levelBoundaries[level - 1];
        const double upperBoundary = level + 1 == levelCount ? m_top : m_levelBoundaries[level];
        m_levelCenters[level] = (lowerBoundary + upperBoundary) / 2.0;
        VelocityAxisGraduation &graduation = m_graduations[m_graduationCount++];
        graduation.level = uint8_t(level);
        graduation.velocity = m_map.representative(int(level));
        graduation.audible = level != 0;
        graduation.labelVisible = (level + 1) % labelStride == 0;
        graduation.y = m_levelCenters[level];
        for (std::size_t markerIndex = 0; markerIndex < m_markerCount; ++markerIndex) {
            const auto markerLevel = m_map.levelOf(m_markers[markerIndex].velocity);
            if (markerLevel && *markerLevel == level)
                graduation.active = true;
        }
    }
}

void VelocityAxis::buildContinuousMarkers(std::span<const uint8_t> activeValues)
{
    if (activeValues.empty())
        return;
    uint8_t minimum = clampVelocity(activeValues.front());
    uint8_t maximum = minimum;
    for (std::size_t index = 1; index < activeValues.size(); ++index) {
        const uint8_t value = clampVelocity(activeValues[index]);
        minimum = std::min(minimum, value);
        maximum = std::max(maximum, value);
    }
    m_markers[m_markerCount++] = {minimum, velocityToY(minimum)};
    if (maximum != minimum)
        m_markers[m_markerCount++] = {maximum, velocityToY(maximum)};
}

void VelocityAxis::addTick(uint8_t velocity)
{
    VelocityAxisTick &tick = m_ticks[m_tickCount++];
    tick.velocity = velocity;
    tick.y = velocityToY(velocity);
}

void VelocityAxis::addLabel(uint8_t velocity)
{
    VelocityAxisLabel &label = m_labels[m_labelCount++];
    label.velocity = velocity;
    label.y = velocityToY(velocity);
    std::snprintf(label.label.data(), label.label.size(), "%u", unsigned(velocity));
}

void VelocityAxis::setAccessibleDescription()
{
    if (m_map.levelCount() == 0) {
        std::snprintf(m_accessibleDescription.data(), m_accessibleDescription.size(), "Velocity");
        return;
    }
    std::snprintf(m_accessibleDescription.data(), m_accessibleDescription.size(),
                  "Velocity. %s has %zu volume levels.", m_map.voiceName(), m_map.levelCount());
}
