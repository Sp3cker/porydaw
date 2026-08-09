#include "ui/editordrawer/automationpencilgesture.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

namespace {

bool finiteSample(const AutomationPencilGesture::Sample &sample)
{
    return std::isfinite(sample.rawTick) && std::isfinite(sample.logicalX) &&
           std::isfinite(sample.continuousValue);
}

double clampedRawTick(double tick, uint64_t songEndTick)
{
    if (tick <= 0.0)
        return 0.0;
    const double songEnd = double(songEndTick);
    return tick >= songEnd ? songEnd : tick;
}

uint64_t clampedTick(double tick, uint64_t songEndTick)
{
    const double clamped = clampedRawTick(tick, songEndTick);
    return clamped >= double(songEndTick) ? songEndTick : uint64_t(std::floor(clamped));
}

AutomationPencilGesture::Sample normalizedSample(AutomationPencilGesture::Sample sample,
                                                 uint64_t songEndTick)
{
    sample.rawTick = clampedRawTick(sample.rawTick, songEndTick);
    return sample;
}

uint64_t nextClockTick(uint64_t tick, uint64_t clockTicks, uint64_t songEndTick)
{
    if (tick >= songEndTick || clockTicks > songEndTick - tick)
        return songEndTick;
    return tick + clockTicks;
}

bool collinearForward(double previousDeltaAxis, double previousDeltaValue, double currentDeltaAxis,
                      double currentDeltaValue)
{
    if (previousDeltaAxis == 0.0 || currentDeltaAxis == 0.0 ||
        ((previousDeltaAxis > 0.0) != (currentDeltaAxis > 0.0)))
        return false;
    const double leftProduct = previousDeltaAxis * currentDeltaValue;
    const double rightProduct = previousDeltaValue * currentDeltaAxis;
    const double tolerance = std::numeric_limits<double>::epsilon() * 64.0 *
                             std::max({1.0, std::abs(leftProduct), std::abs(rightProduct)});
    return std::abs(leftProduct - rightProduct) <= tolerance;
}

} // namespace

std::optional<AutomationPencilGesture>
AutomationPencilGesture::start(Target target, int minimumValue, int maximumValue,
                               uint64_t songEndTick, uint64_t documentClockTicks,
                               std::vector<AutomationLaneEdit::Point> originalPoints,
                               Sample firstSample, AutomationGridCell firstCell)
{
    if (target.engineTrack < 0 || minimumValue > maximumValue || documentClockTicks == 0 ||
        !finiteSample(firstSample) || !validCell(firstCell, songEndTick))
        return std::nullopt;
    return AutomationPencilGesture(target, minimumValue, maximumValue, songEndTick,
                                   documentClockTicks, std::move(originalPoints), firstSample,
                                   firstCell);
}

AutomationPencilGesture::AutomationPencilGesture(
    Target target, int minimumValue, int maximumValue, uint64_t songEndTick,
    uint64_t documentClockTicks, std::vector<AutomationLaneEdit::Point> originalPoints,
    Sample firstSample, AutomationGridCell firstCell)
    : m_minimumValue(minimumValue)
    , m_maximumValue(maximumValue)
    , m_songEndTick(songEndTick)
    , m_documentClockTicks(documentClockTicks)
    , m_previous(normalizedSample(firstSample, songEndTick))
    , m_laneEdit(target, std::move(originalPoints))
    , m_initialCell(firstCell)
    , m_initialPoint(m_previous.point)
    , m_tickBegin(firstCell.tickBegin)
    , m_tickEnd(firstCell.tickEnd)
{
    m_initialPoint.tick = firstCell.tickBegin;
    m_initialPoint.value = roundedValue(m_previous.continuousValue);
    eraseStrokePointsIn(firstCell.tickBegin, firstCell.tickEnd);
    upsertPoint(m_strokePoints, m_initialPoint.tick, m_initialPoint.value);
    rebuildPreview();
}

bool AutomationPencilGesture::applySnappedSegment(Sample sample,
                                                  const std::vector<AutomationGridCell> &cells)
{
    if (!finiteSample(sample) || cells.empty())
        return false;
    for (const AutomationGridCell &cell : cells)
        if (!validCell(cell, m_songEndTick))
            return false;

    sample = normalizedSample(sample, m_songEndTick);
    const bool previousWasFreehand = m_freehandSegmentStart.has_value();
    m_provisionalFreehandEndpoint.reset();
    m_freehandSegmentStart.reset();

    const Sample previous = m_previous;
    bool continuesSnappedLine = false;
    if (m_snappedSegmentStart) {
        const Sample &start = *m_snappedSegmentStart;
        continuesSnappedLine = collinearForward(
            previous.logicalX - start.logicalX, previous.continuousValue - start.continuousValue,
            sample.logicalX - previous.logicalX, sample.continuousValue - previous.continuousValue);
    }
    const Sample &anchor = continuesSnappedLine ? *m_snappedSegmentStart : previous;
    const double deltaTick = sample.rawTick - anchor.rawTick;
    const double interpolationBegin = std::min(anchor.rawTick, sample.rawTick);
    const double interpolationEnd = std::max(anchor.rawTick, sample.rawTick);
    std::size_t endingCell = cells.size() - 1;
    std::optional<std::size_t> startingCell;
    for (std::size_t index = 0; index < cells.size(); ++index) {
        const AutomationGridCell &cell = cells[index];
        if (previous.rawTick >= double(cell.tickBegin) && previous.rawTick < double(cell.tickEnd))
            startingCell = index;
        if (sample.rawTick >= double(cell.tickBegin) && sample.rawTick < double(cell.tickEnd))
            endingCell = index;
    }

    const AutomationGridCell &initialCell = m_initialCell;
    const bool previousInInitialCell = previous.rawTick >= double(initialCell.tickBegin) &&
                                       previous.rawTick < double(initialCell.tickEnd);
    const bool sampleInInitialCell = sample.rawTick >= double(initialCell.tickBegin) &&
                                     sample.rawTick < double(initialCell.tickEnd);
    const bool exitsInitialCell =
        !m_initialCellExited && previousInInitialCell && !sampleInInitialCell;
    const bool restoreInitialPoint =
        exitsInitialCell && (!m_snappedSegmentStart || continuesSnappedLine);

    for (std::size_t index = 0; index < cells.size(); ++index) {
        const AutomationGridCell &cell = cells[index];
        if (m_snappedSegmentStart && startingCell && index == *startingCell &&
            index != endingCell && !previousWasFreehand && !continuesSnappedLine)
            continue;
        const double cellMidpoint =
            double(cell.tickBegin) + double(cell.tickEnd - cell.tickBegin) / 2.0;
        const double sampleTick = std::clamp(cellMidpoint, interpolationBegin, interpolationEnd);
        const double fraction =
            deltaTick == 0.0 ? 1.0
                             : std::clamp((sampleTick - anchor.rawTick) / deltaTick, 0.0, 1.0);
        const double continuousValue =
            anchor.continuousValue + (sample.continuousValue - anchor.continuousValue) * fraction;
        eraseStrokePointsIn(cell.tickBegin, cell.tickEnd);
        upsertPoint(m_strokePoints, cell.tickBegin, roundedValue(continuousValue));
        m_tickBegin = std::min(m_tickBegin, cell.tickBegin);
        m_tickEnd = std::max(m_tickEnd, cell.tickEnd);
    }

    if (restoreInitialPoint)
        upsertPoint(m_strokePoints, m_initialPoint.tick, m_initialPoint.value);
    if (exitsInitialCell)
        m_initialCellExited = true;

    m_previous = sample;
    if (!continuesSnappedLine)
        m_snappedSegmentStart = previous;
    rebuildPreview();
    return true;
}

bool AutomationPencilGesture::applyFreehandSegment(Sample sample)
{
    if (!finiteSample(sample))
        return false;

    sample = normalizedSample(sample, m_songEndTick);
    m_snappedSegmentStart.reset();
    const Sample previous = m_previous;
    const double deltaX = sample.logicalX - previous.logicalX;
    std::optional<uint64_t> preservedTurnTick;
    if (m_provisionalFreehandEndpoint) {
        bool continuesFreehandLine = false;
        if (m_freehandSegmentStart) {
            const Sample &start = *m_freehandSegmentStart;
            continuesFreehandLine =
                collinearForward(previous.logicalX - start.logicalX,
                                 previous.continuousValue - start.continuousValue, deltaX,
                                 sample.continuousValue - previous.continuousValue);
        }
        if (!continuesFreehandLine) {
            upsertPoint(m_strokePoints, m_provisionalFreehandEndpoint->tick,
                        m_provisionalFreehandEndpoint->value);
            preservedTurnTick = m_provisionalFreehandEndpoint->tick;
        }
    }
    m_provisionalFreehandEndpoint.reset();
    const auto applyAtX = [this, &previous, &sample, &preservedTurnTick,
                           deltaX](double logicalX, bool provisionalEndpoint, bool interiorSample) {
        const double fraction =
            deltaX == 0.0 ? 1.0 : std::clamp((logicalX - previous.logicalX) / deltaX, 0.0, 1.0);
        const double rawTick = previous.rawTick + (sample.rawTick - previous.rawTick) * fraction;
        const double continuousValue =
            previous.continuousValue +
            (sample.continuousValue - previous.continuousValue) * fraction;
        const uint64_t rawIntegerTick = clampedTick(rawTick, m_songEndTick);
        const uint64_t clockTick = (rawIntegerTick / m_documentClockTicks) * m_documentClockTicks;
        const automation::ValuePoint point{clockTick, roundedValue(continuousValue)};
        if (provisionalEndpoint)
            m_provisionalFreehandEndpoint = point;
        else if (!interiorSample || !preservedTurnTick || point.tick != *preservedTurnTick)
            upsertPoint(m_strokePoints, point.tick, point.value);
        const uint64_t rangeEnd = nextClockTick(clockTick, m_documentClockTicks, m_songEndTick);
        m_tickBegin = std::min(m_tickBegin, clockTick);
        m_tickEnd = std::max(m_tickEnd, rangeEnd);
    };

    if (deltaX > 0.0) {
        for (double logicalX = std::floor(previous.logicalX) + 1.0; logicalX < sample.logicalX;
             logicalX += 1.0)
            applyAtX(logicalX, false, true);
    } else if (deltaX < 0.0) {
        for (double logicalX = std::ceil(previous.logicalX) - 1.0; logicalX > sample.logicalX;
             logicalX -= 1.0)
            applyAtX(logicalX, false, true);
    }
    applyAtX(sample.logicalX, std::floor(sample.logicalX) != sample.logicalX, false);

    m_freehandSegmentStart = previous;
    m_previous = sample;
    rebuildPreview();
    return true;
}

bool AutomationPencilGesture::lessPointTick(const automation::ValuePoint &left,
                                            uint64_t tick) noexcept
{
    return left.tick < tick;
}

bool AutomationPencilGesture::validCell(const AutomationGridCell &cell,
                                        uint64_t songEndTick) noexcept
{
    return cell.tickBegin < cell.tickEnd && cell.tickEnd <= songEndTick;
}

void AutomationPencilGesture::rebuildPreview()
{
    std::vector<AutomationLaneEdit::Point> points;
    points.reserve(m_strokePoints.size() + (m_provisionalFreehandEndpoint ? 1 : 0));
    for (const automation::ValuePoint &point : m_strokePoints)
        points.push_back({point.tick, point.value});
    if (m_provisionalFreehandEndpoint && m_provisionalFreehandEndpoint->tick >= m_tickBegin &&
        m_provisionalFreehandEndpoint->tick <= m_tickEnd) {
        const automation::ValuePoint &endpoint = *m_provisionalFreehandEndpoint;
        const auto position = std::lower_bound(
            points.begin(), points.end(), endpoint.tick,
            [](const AutomationLaneEdit::Point &left, uint64_t tick) { return left.tick < tick; });
        if (position != points.end() && position->tick == endpoint.tick)
            position->value = endpoint.value;
        else
            points.insert(position, {endpoint.tick, endpoint.value});
    }
    m_cachedPreview = m_laneEdit.replaceHeldSpan(m_tickBegin, m_tickEnd, m_songEndTick,
                                                 m_minimumValue, m_maximumValue, std::move(points));
}

void AutomationPencilGesture::eraseStrokePointsIn(uint64_t tickBegin, uint64_t tickEnd)
{
    const auto first =
        std::lower_bound(m_strokePoints.begin(), m_strokePoints.end(), tickBegin, lessPointTick);
    const auto last =
        std::lower_bound(m_strokePoints.begin(), m_strokePoints.end(), tickEnd, lessPointTick);
    m_strokePoints.erase(first, last);
}

void AutomationPencilGesture::upsertPoint(std::vector<automation::ValuePoint> &points,
                                          uint64_t tick, int value)
{
    const auto position = std::lower_bound(points.begin(), points.end(), tick, lessPointTick);
    if (position != points.end() && position->tick == tick)
        position->value = value;
    else
        points.insert(position, {tick, value});
}

int AutomationPencilGesture::roundedValue(double continuousValue) const noexcept
{
    const double clamped =
        std::clamp(continuousValue, double(m_minimumValue), double(m_maximumValue));
    return int(std::llround(clamped));
}
