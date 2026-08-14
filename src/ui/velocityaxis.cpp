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
    : m_geometry(geometry)
{
    const double height = nonNegative(m_geometry.height);
    const double inset = nonNegative(m_geometry.verticalInset);
    // A lane shorter than two insets keeps a degenerate but ordered band
    // rather than folding top past bottom.
    m_top = std::min(inset, height / 2.0);
    m_bottom = std::max(m_top, height - inset);
    buildTicks();
    buildMarkers(activeValues, activeValueCount);
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
