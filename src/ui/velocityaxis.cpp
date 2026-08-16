#include "ui/velocityaxis.h"

#include <algorithm>
#include <cmath>
#include <initializer_list>

#include <QPainter>
#include <QString>

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

} // namespace

VelocityAxis::VelocityAxis(const VelocityAxisGeometry &geometry, const uint8_t *activeValues,
                           std::size_t activeValueCount)
    : VelocityAxis(VelocityMap(), geometry, activeValues, activeValueCount)
{}

VelocityAxis::VelocityAxis(const VelocityMap &map, const VelocityAxisGeometry &geometry,
                           const uint8_t *activeValues, std::size_t activeValueCount)
    : m_map(map)
    , m_geometry(geometry)
{
    const double height = nonNegative(m_geometry.height);
    const double inset = nonNegative(m_geometry.verticalInset);
    // A lane shorter than two insets keeps a degenerate but ordered band
    // rather than folding top past bottom.
    m_top = std::min(inset, height / 2.0);
    m_bottom = std::max(m_top, height - inset);
    buildTicks();
    buildMarkers(activeValues, activeValueCount);
    // After the markers: a level's row reads as active when a marked value
    // lands in it.
    if (mode() == Mode::Intrinsic)
        buildIntrinsicRows();
}

VelocityAxis::Mode VelocityAxis::mode() const
{
    // A channel whose volume has left it a single (silent) step has no rows
    // to snap between, so it reads as continuous rather than as a one-row
    // ruler that would rewrite every velocity it touched to 1.
    return m_map.hasDetents() ? Mode::Intrinsic : Mode::Continuous;
}

double VelocityAxis::levelToY(int level) const
{
    const int highest = std::max(0, int(m_map.levelCount()) - 1);
    return m_levelCenters[std::size_t(std::clamp(level, 0, highest))];
}

int VelocityAxis::yToLevel(double y) const
{
    // Walking down from the top: the boundaries are in descending y, so the
    // first one the pointer is below ends the search.
    const int highest = std::max(0, int(m_map.levelCount()) - 1);
    int level = highest;
    while (level > 0 && y > m_levelBoundaries[std::size_t(level - 1)])
        --level;
    return level;
}

double VelocityAxis::levelBoundaryToY(int lowerLevel) const
{
    const int highest = std::max(0, int(m_map.levelCount()) - 2);
    return m_levelBoundaries[std::size_t(std::clamp(lowerLevel, 0, highest))];
}

double VelocityAxis::velocityToY(int velocity) const
{
    const int clamped = std::clamp(velocity, kMinimumVelocity, kMaximumVelocity);
    const double span = m_bottom - m_top;
    if (span == 0.0)
        return m_bottom;
    return m_bottom -
           double(clamped - kMinimumVelocity) * span / double(kMaximumVelocity - kMinimumVelocity);
}

int VelocityAxis::yToVelocity(double y) const
{
    const double span = m_bottom - m_top;
    if (span == 0.0)
        return kMinimumVelocity;
    const double clamped = std::clamp(y, m_top, m_bottom);
    const double scaled = (m_bottom - clamped) * double(kMaximumVelocity - kMinimumVelocity) / span;
    return std::clamp(kMinimumVelocity + int(std::lround(scaled)), kMinimumVelocity,
                      kMaximumVelocity);
}

int VelocityAxis::rulerVelocityAt(double y, double labelHeight) const
{
    // Every intrinsic row prints the level it stands for, so the column has
    // no gaps to miss: the y picks a level and the level names its value.
    if (mode() == Mode::Intrinsic)
        return m_map.representative(yToLevel(y));
    const double reach = labelHeight / 2.0;
    // Exactly what paintRuler prints, and nothing else: a selection marker
    // owns its own value's row, and the fixed label it suppressed there is
    // not on screen to be aimed at.
    for (std::size_t index = 0; index < m_markerCount; index++) {
        if (std::abs(y - m_markers[index].y) <= reach)
            return m_markers[index].velocity;
    }
    for (std::size_t index = 0; index < m_labelCount; index++) {
        if (std::abs(y - m_labels[index].y) <= reach && !markerNear(m_labels[index].y, labelHeight))
            return m_labels[index].velocity;
    }
    return -1;
}

void VelocityAxis::paintRuler(QPainter &painter, const VelocityAxisPaintStyle &style) const
{
    painter.save();
    if (mode() == Mode::Intrinsic) {
        // One graduation per real loudness level, named for the volume step
        // it is rather than the stored velocity that happens to reach it.
        // The level index IS that step — the CGB envelope goal (the wave
        // channel's NR32 class) — so the naming is zero-based: the bottom
        // row is Vol 0, the step the hardware plays silently.
        // The levels holding an active value take the accent, which is what
        // the continuous ruler's markers say in the same place.
        for (std::size_t index = 0; index < m_graduationCount; ++index) {
            const VelocityAxisGraduation &graduation = m_graduations[index];
            painter.setPen(QPen(graduation.active ? style.accentColor : style.labelColor,
                                graduation.active ? style.markerWidth : style.tickWidth));
            painter.drawLine(QPointF(style.separatorX - style.majorTickLength, graduation.y),
                             QPointF(style.separatorX, graduation.y));
            // An active row always names itself; a fixed label that close
            // yields rather than overprinting it, exactly as the continuous
            // ruler's labels yield to a marker.
            if (!graduation.active &&
                (!graduation.labelVisible || activeNear(graduation.y, style.labelHeight)))
                continue;
            painter.setFont(graduation.active ? style.emphasizedFont : style.labelFont);
            painter.setPen(graduation.active ? style.accentColor : style.labelColor);
            painter.drawText(QRectF(style.labelLeft, graduation.y - style.labelHeight / 2.0,
                                    style.labelWidth, style.labelHeight),
                             Qt::AlignRight | Qt::AlignVCenter,
                             tr("Vol %1").arg(unsigned(graduation.level)));
        }
        painter.restore();
        return;
    }
    painter.setPen(QPen(style.labelColor, style.tickWidth));
    for (std::size_t index = 0; index < m_tickCount; ++index) {
        const VelocityAxisTick &tick = m_ticks[index];
        const double length =
            isLabeled(tick.velocity) ? style.majorTickLength : style.minorTickLength;
        painter.drawLine(QPointF(style.separatorX - length, tick.y),
                         QPointF(style.separatorX, tick.y));
    }
    painter.setFont(style.labelFont);
    for (std::size_t index = 0; index < m_labelCount; ++index) {
        const VelocityAxisLabel &label = m_labels[index];
        // A marker's own value is printed in this column below; the fixed
        // label yields rather than letting the two strings overprint.
        if (markerNear(label.y, style.labelHeight))
            continue;
        painter.drawText(QRectF(style.labelLeft, label.y - style.labelHeight / 2.0,
                                style.labelWidth, style.labelHeight),
                         Qt::AlignRight | Qt::AlignVCenter, QString::number(label.velocity));
    }
    // The selection's extremes sit on top of the graduations, labeled in the
    // emphasized face so they read apart from the fixed ruler values.
    for (std::size_t index = 0; index < m_markerCount; ++index) {
        const VelocityAxisMarker &marker = m_markers[index];
        painter.setPen(QPen(style.accentColor, style.markerWidth));
        painter.drawLine(QPointF(style.separatorX - style.markerTickLength, marker.y),
                         QPointF(style.separatorX, marker.y));
        painter.setFont(style.emphasizedFont);
        painter.setPen(style.accentColor);
        painter.drawText(QRectF(style.labelLeft, marker.y - style.labelHeight / 2.0,
                                style.labelWidth, style.labelHeight),
                         Qt::AlignRight | Qt::AlignVCenter, QString::number(marker.velocity));
    }
    painter.restore();
}

// Five density bands. Each adds graduations as the lane grows; the labels
// follow one band behind the ticks so text never crowds even where the tick
// spacing is already tight.
void VelocityAxis::buildTicks()
{
    const double span = nonNegative(m_geometry.height);
    if (span < m_geometry.densityD1) {
        for (const uint8_t velocity :
             {uint8_t{127}, uint8_t{96}, uint8_t{64}, uint8_t{32}, uint8_t{1}})
            addTick(velocity);
        for (const uint8_t velocity : {uint8_t{127}, uint8_t{64}, uint8_t{1}})
            addLabel(velocity);
        return;
    }
    if (span < m_geometry.densityD3) {
        addTick(127);
        for (int velocity = 112; velocity >= 16; velocity -= 16)
            addTick(uint8_t(velocity));
        addTick(1);
        if (span < m_geometry.densityD2) {
            for (const uint8_t velocity : {uint8_t{127}, uint8_t{64}, uint8_t{1}})
                addLabel(velocity);
        } else {
            for (const uint8_t velocity :
                 {uint8_t{127}, uint8_t{96}, uint8_t{64}, uint8_t{32}, uint8_t{1}})
                addLabel(velocity);
        }
        return;
    }
    if (span < m_geometry.densityD4) {
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
    // Stepping from 124 (not 123) keeps every label below on a tick, so the
    // labeled graduations stay the long ones; the run lands exactly on
    // MaximumTicks.
    addTick(127);
    for (int velocity = 124; velocity >= 8; velocity -= 4)
        addTick(uint8_t(velocity));
    addTick(1);
    addLabel(127);
    for (int velocity = 120; velocity >= 8; velocity -= 8)
        addLabel(uint8_t(velocity));
    addLabel(1);
}

// One row per level, centered in the velocity band that level owns, with the
// boundaries halfway between the levels' adjacent stored velocities. A lane
// too short to name every row drops labels by a power-of-two stride rather
// than dropping graduations: the rows are where edits land, so they all stay
// on screen.
void VelocityAxis::buildIntrinsicRows()
{
    const std::size_t levelCount = std::min(m_map.levelCount(), MaximumGraduations);
    if (levelCount == 0)
        return;
    const double span = m_bottom - m_top;
    std::size_t labelStride = 1;
    while (labelStride < levelCount &&
           span / double(levelCount) * double(labelStride) < nonNegative(m_geometry.labelHeight))
        labelStride *= 2;
    for (std::size_t level = 0; level + 1 < levelCount; ++level) {
        const VelocityLevelRange lower = m_map.levelRange(int(level));
        const VelocityLevelRange upper = m_map.levelRange(int(level + 1));
        m_levelBoundaries[level] = (velocityToY(lower.last) + velocityToY(upper.first)) / 2.0;
    }
    for (std::size_t level = 0; level < levelCount; ++level) {
        // The outermost levels run to the ruler's own ends, so their rows
        // center on the band they really cover rather than on a boundary
        // they do not have.
        const double lower = level == 0 ? m_bottom : m_levelBoundaries[level - 1];
        const double upper = level + 1 == levelCount ? m_top : m_levelBoundaries[level];
        m_levelCenters[level] = (lower + upper) / 2.0;
        VelocityAxisGraduation &graduation = m_graduations[m_graduationCount++];
        graduation.level = uint8_t(level);
        graduation.velocity = m_map.representative(int(level));
        graduation.labelVisible = (level + 1) % labelStride == 0;
        graduation.y = m_levelCenters[level];
        for (std::size_t index = 0; index < m_markerCount; ++index) {
            const std::optional<std::size_t> marked = m_map.levelOf(m_markers[index].velocity);
            if (marked && *marked == level)
                graduation.active = true;
        }
    }
}

bool VelocityAxis::activeNear(double y, double labelHeight) const
{
    for (std::size_t index = 0; index < m_graduationCount; ++index) {
        if (m_graduations[index].active && std::abs(m_graduations[index].y - y) < labelHeight)
            return true;
    }
    return false;
}

void VelocityAxis::buildMarkers(const uint8_t *activeValues, std::size_t activeValueCount)
{
    if (!activeValues || activeValueCount == 0)
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
    if (m_tickCount == MaximumTicks)
        return;
    VelocityAxisTick &tick = m_ticks[m_tickCount++];
    tick.velocity = velocity;
    tick.y = velocityToY(velocity);
}

void VelocityAxis::addLabel(uint8_t velocity)
{
    if (m_labelCount == MaximumLabels)
        return;
    VelocityAxisLabel &label = m_labels[m_labelCount++];
    label.velocity = velocity;
    label.y = velocityToY(velocity);
}

bool VelocityAxis::markerNear(double y, double labelHeight) const
{
    for (std::size_t index = 0; index < m_markerCount; ++index) {
        if (std::abs(m_markers[index].y - y) < labelHeight)
            return true;
    }
    return false;
}

bool VelocityAxis::isLabeled(uint8_t velocity) const
{
    for (std::size_t index = 0; index < m_labelCount; ++index) {
        if (m_labels[index].velocity == velocity)
            return true;
    }
    return false;
}
