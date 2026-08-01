#include "ui/velocityaxis.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <initializer_list>
#include <cstdio>

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
                           const uint8_t *activeValues, std::size_t activeValueCount)
    : m_map(map)
    , m_geometry(geometry)
{
    const double height = nonNegative(m_geometry.height);
    const double inset = nonNegative(m_geometry.verticalInset);
    m_top = std::min(inset, height / 2.0);
    m_bottom = std::max(m_top, height - inset);
    setAccessibleDescription();
    if (mode() == Mode::Continuous) {
        buildContinuousTicks();
        buildContinuousMarkers(activeValues, activeValueCount);
    } else {
        buildIntrinsicGraduations(activeValues, activeValueCount);
    }
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
    const double scaled = (m_bottom - clampedY) * double(kMaximumVelocity - kMinimumVelocity) /
                          drawableSpan();
    return std::clamp(kMinimumVelocity + int(std::lround(scaled)), kMinimumVelocity,
                      kMaximumVelocity);
}

double VelocityAxis::levelToY(int level) const
{
    const std::size_t levelCount = m_map.levelCount();
    if (levelCount <= 1 || drawableSpan() == 0.0)
        return m_bottom;
    const int clamped = std::clamp(level, 0, int(levelCount) - 1);
    return m_bottom - double(clamped) * drawableSpan() / double(levelCount - 1);
}

int VelocityAxis::yToLevel(double y) const
{
    const std::size_t levelCount = m_map.levelCount();
    if (levelCount <= 1 || drawableSpan() == 0.0)
        return 0;
    const double clampedY = std::clamp(y, m_top, m_bottom);
    const double scaled = (m_bottom - clampedY) * double(levelCount - 1) / drawableSpan();
    return std::clamp(int(std::lround(scaled)), 0, int(levelCount) - 1);
}

const std::array<VelocityAxisTick, VelocityAxis::MaximumContinuousTicks> &VelocityAxis::ticks() const
{
    return m_ticks;
}

std::size_t VelocityAxis::tickCount() const
{
    return m_tickCount;
}

const std::array<VelocityAxisLabel, VelocityAxis::MaximumContinuousLabels> &VelocityAxis::labels() const
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
    if (mode() == Mode::Continuous) {
        painter.setPen(QPen(style.labelColor, style.tickWidth));
        for (std::size_t index = 0; index < m_tickCount; ++index) {
            const VelocityAxisTick &tick = m_ticks[index];
            const double tickLength = hasLabel(*this, tick.velocity) ? style.majorTickLength
                                                                      : style.minorTickLength;
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
            if (style.relativeGesture || !hasLabel(*this, marker.velocity)) {
                painter.setFont(style.emphasizedFont);
                painter.drawText(
                    QRectF(style.labelLeft, marker.y - style.labelHeight / 2.0,
                           style.labelWidth, style.labelHeight),
                    Qt::AlignRight | Qt::AlignVCenter, QString::number(marker.velocity));
            }
        }
    } else {
        for (std::size_t index = 0; index < m_graduationCount; ++index) {
            const VelocityAxisGraduation &graduation = m_graduations[index];
            painter.setPen(QPen(graduation.emphasized ? style.accentColor : style.labelColor,
                                graduation.emphasized ? style.emphasizedWidth
                                                       : style.tickWidth));
            painter.drawLine(
                QPointF(style.separatorX - style.graduationTickLength, graduation.y),
                QPointF(style.separatorX, graduation.y));
            painter.setFont(graduation.emphasized ? style.emphasizedFont : style.labelFont);
            painter.drawText(QRectF(graduation.x, graduation.y - style.labelHeight / 2.0,
                                    graduation.width, style.labelHeight),
                             Qt::AlignRight | Qt::AlignVCenter,
                             QString::fromLatin1(graduation.label.data()));
        }
    }
    painter.setClipRect(style.contentClip);
    if (mode() == Mode::Intrinsic) {
        for (std::size_t index = 0; index < m_graduationCount; ++index) {
            const VelocityAxisGraduation &graduation = m_graduations[index];
            painter.setPen(QPen(graduation.emphasized ? style.accentColor : style.labelColor,
                                graduation.emphasized ? style.emphasizedWidth
                                                       : style.tickWidth));
            painter.drawLine(
                QPointF(style.separatorX, graduation.y),
                QPointF(style.separatorX + style.graduationTickLength, graduation.y));
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
    const double textRadius = labelHeight / 2.0;
    if (mode() == Mode::Continuous) {
        for (std::size_t index = 0; index < m_labelCount; ++index) {
            const VelocityAxisLabel &label = m_labels[index];
            if (std::abs(position.y() - label.y) <= textRadius)
                return label.velocity;
        }
        return -1;
    }
    for (std::size_t index = 0; index < m_graduationCount; ++index) {
        const VelocityAxisGraduation &graduation = m_graduations[index];
        const QRectF labelRect(graduation.x, graduation.y - textRadius, graduation.width,
                               textRadius * 2.0);
        if (labelRect.contains(position))
            return graduation.velocity;
    }
    return -1;
}

void VelocityAxis::buildContinuousTicks()
{
    const double span = nonNegative(m_geometry.height);
    if (span < m_geometry.continuousDensityD1) {
        for (const uint8_t velocity : {uint8_t{127}, uint8_t{96}, uint8_t{64}, uint8_t{32}, uint8_t{1}})
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

// An active level shows its correct value only when all active values at that
// level agree. Different values use the level representative, so one value
// cannot set the text for the active set.
void VelocityAxis::buildIntrinsicGraduations(const uint8_t *activeValues,
                                             std::size_t activeValueCount)
{
    std::array<bool, MaximumIntrinsicGraduations> active{};
    std::array<bool, MaximumIntrinsicGraduations> conflicting{};
    std::array<uint8_t, MaximumIntrinsicGraduations> exactValues{};
    for (std::size_t index = 0; index < activeValueCount; ++index) {
        const std::optional<std::size_t> level = m_map.levelOf(activeValues[index]);
        if (!level)
            continue;
        const std::size_t slot = *level;
        if (!active[slot]) {
            active[slot] = true;
            exactValues[slot] = clampVelocity(activeValues[index]);
        } else if (exactValues[slot] != clampVelocity(activeValues[index])) {
            conflicting[slot] = true;
        }
    }

    std::size_t activeLevelCount = 0;
    std::size_t lowestActiveLevel = m_map.levelCount();
    std::size_t highestActiveLevel = 0;
    for (std::size_t level = 0; level < m_map.levelCount(); ++level) {
        if (!active[level])
            continue;
        ++activeLevelCount;
        lowestActiveLevel = std::min(lowestActiveLevel, level);
        highestActiveLevel = std::max(highestActiveLevel, level);
    }

    m_intrinsicColumnCount = m_map.levelCount() > 8 ? 2 : 1;
    const double sideInset = nonNegative(m_geometry.labelSideInset);
    const double usableWidth = std::max(0.0, nonNegative(m_geometry.labelWidth) - 2.0 * sideInset);
    const double columnGap = nonNegative(m_geometry.labelColumnGap);
    m_intrinsicColumnWidth = m_intrinsicColumnCount == 1
                                 ? usableWidth
                                 : std::max(0.0, (usableWidth - columnGap) / 2.0);

    for (std::size_t level = 0; level < m_map.levelCount(); ++level) {
        VelocityAxisGraduation &graduation = m_graduations[m_graduationCount++];
        const uint8_t displayVelocity = active[level] && !conflicting[level]
                                            ? exactValues[level]
                                            : m_map.representative(int(level));
        graduation.level = uint8_t(level);
        graduation.velocity = displayVelocity;
        graduation.audible = level != 0;
        graduation.active = active[level];
        graduation.emphasized = active[level] &&
                                (activeLevelCount <= 2 || level == lowestActiveLevel ||
                                 level == highestActiveLevel);
        graduation.column = m_intrinsicColumnCount == 2 ? uint8_t((level + 1) % 2) : uint8_t{0};
        graduation.x = sideInset + double(graduation.column) *
                                       (m_intrinsicColumnWidth + columnGap);
        graduation.width = m_intrinsicColumnWidth;
        graduation.y = levelToY(int(level));
        std::snprintf(graduation.label.data(), graduation.label.size(), "Volume %u (%u)",
                      unsigned(level + 1), unsigned(displayVelocity));
    }
}

void VelocityAxis::buildContinuousMarkers(const uint8_t *activeValues,
                                          std::size_t activeValueCount)
{
    if (activeValueCount == 0)
        return;
    uint8_t minimum = clampVelocity(activeValues[0]);
    uint8_t maximum = minimum;
    for (std::size_t index = 1; index < activeValueCount; ++index) {
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
