#include "ui/pitchprojection.h"

#include <algorithm>
#include <cassert>
#include <cmath>

namespace songview {

namespace {

qreal snappedRowEdge(int row, double keyHeight, double scrollY, qreal dpr)
{
    const qreal scale = dpr > 0.0 ? dpr : 1.0;
    return std::round((row * keyHeight - scrollY) * scale) / scale;
}

} // namespace

PitchProjection::PitchProjection()
{
    buildChromatic();
}

void PitchProjection::buildChromatic()
{
    std::fill(std::begin(m_pitchToRow), std::end(m_pitchToRow), int8_t(cHiddenRow));
    std::fill(std::begin(m_scalePitchRow), std::end(m_scalePitchRow), true);
    m_visibleRowCount = cMaxRows;
    for (int row = 0; row < m_visibleRowCount; ++row) {
        const int pitch = cMaxRows - 1 - row;
        m_visiblePitches[row] = uint8_t(pitch);
        m_pitchToRow[pitch] = int8_t(row);
    }
    ++m_revision;
}

void PitchProjection::buildFromPitches(const uint8_t *pitches, int count)
{
    assert(count >= 0 && count <= cMaxRows);
    assert(pitches != nullptr || count == 0);
    for (int index = 0; index < count; ++index) {
        assert(pitches[index] < 128);
        assert(index == 0 || pitches[index] > pitches[index - 1]);
    }
    std::fill(std::begin(m_pitchToRow), std::end(m_pitchToRow), int8_t(cHiddenRow));
    std::fill(std::begin(m_scalePitchRow), std::end(m_scalePitchRow), false);
    m_visibleRowCount = count;
    for (int row = 0; row < count; ++row) {
        const uint8_t pitch = pitches[count - 1 - row];
        m_visiblePitches[row] = pitch;
        m_pitchToRow[pitch] = int8_t(row);
        m_scalePitchRow[row] = true;
    }
    ++m_revision;
}

int PitchProjection::visiblePitchAt(int row) const
{
    assert(row >= 0 && row < m_visibleRowCount);
    return m_visiblePitches[row];
}

int PitchProjection::rowForPitch(int midiPitch) const
{
    if (midiPitch < 0 || midiPitch >= 128)
        return cHiddenRow;
    return m_pitchToRow[midiPitch];
}

void PitchProjection::setScalePitchClassification(const bool *isScalePitch)
{
    assert(isScalePitch != nullptr);
    for (int row = 0; row < m_visibleRowCount; ++row)
        m_scalePitchRow[row] = isScalePitch[m_visiblePitches[row]];
}

bool PitchProjection::isScalePitchRow(int row) const
{
    assert(row >= 0 && row < m_visibleRowCount);
    return m_scalePitchRow[row];
}

int PitchProjection::nearestVisiblePitch(int midiPitch) const
{
    if (m_visibleRowCount == 0)
        return cHiddenRow;
    int firstNotHigher = 0;
    int end = m_visibleRowCount;
    while (firstNotHigher < end) {
        const int middle = firstNotHigher + (end - firstNotHigher) / 2;
        if (m_visiblePitches[middle] > midiPitch)
            firstNotHigher = middle + 1;
        else
            end = middle;
    }
    if (firstNotHigher == 0)
        return m_visiblePitches[0];
    if (firstNotHigher == m_visibleRowCount)
        return m_visiblePitches[m_visibleRowCount - 1];
    const int lower = m_visiblePitches[firstNotHigher];
    const int higher = m_visiblePitches[firstNotHigher - 1];
    return std::abs(midiPitch - lower) <= std::abs(higher - midiPitch) ? lower : higher;
}

void PitchProjection::buildRowEdges(std::array<qreal, cMaxRows + 1> &edges, int &edgeCount,
                                    double keyHeight, double scrollY, qreal dpr) const
{
    edgeCount = m_visibleRowCount + 1;
    for (int row = 0; row < edgeCount; ++row)
        edges[row] = snappedRowEdge(row, keyHeight, scrollY, dpr);
}

qreal PitchProjection::rowTop(int row, double keyHeight, double scrollY, qreal dpr) const
{
    assert(row >= 0 && row < m_visibleRowCount);
    return snappedRowEdge(row, keyHeight, scrollY, dpr);
}

qreal PitchProjection::rowBottom(int row, double keyHeight, double scrollY, qreal dpr) const
{
    assert(row >= 0 && row < m_visibleRowCount);
    return snappedRowEdge(row + 1, keyHeight, scrollY, dpr);
}

QRectF PitchProjection::rowRect(int row, qreal x, qreal width, double keyHeight, double scrollY,
                                qreal dpr) const
{
    const qreal top = rowTop(row, keyHeight, scrollY, dpr);
    return QRectF(x, top, width, rowBottom(row, keyHeight, scrollY, dpr) - top);
}

int PitchProjection::yToRow(qreal y, double keyHeight, double scrollY, qreal dpr) const
{
    if (m_visibleRowCount == 0 || y < rowTop(0, keyHeight, scrollY, dpr) ||
        y >= rowBottom(m_visibleRowCount - 1, keyHeight, scrollY, dpr)) {
        return cHiddenRow;
    }
    int first = 0;
    int end = m_visibleRowCount;
    while (first < end) {
        const int middle = first + (end - first) / 2;
        if (y < snappedRowEdge(middle + 1, keyHeight, scrollY, dpr))
            end = middle;
        else
            first = middle + 1;
    }
    return first;
}

int PitchProjection::yToPitch(qreal y, double keyHeight, double scrollY, qreal dpr) const
{
    const int row = yToRow(y, keyHeight, scrollY, dpr);
    return row == cHiddenRow ? cHiddenRow : visiblePitchAt(row);
}

} // namespace songview
