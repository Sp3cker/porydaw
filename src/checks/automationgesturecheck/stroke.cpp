#include "domains.h"

#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/songview.h"

#include <QStringList>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <utility>
#include <vector>

namespace {

using LanePoints = std::vector<std::pair<uint64_t, int>>;

struct StrokeContext {
    AutomationGestureCheckRig &rig;
    const AutomationGestureCheck &check;
};

LanePoints lanePoints(AutomationGestureCheckRig &rig)
{
    LanePoints result;
    for (const DocLanePoint &point : rig.snapshot(rig.pan.track, rig.pan.controller).lanePoints)
        result.emplace_back(point.tick, point.value);
    return result;
}

QString formatPoints(const LanePoints &values)
{
    QStringList result;
    for (const auto &[tick, value] : values)
        result.append(QStringLiteral("{%1,%2}").arg(tick).arg(value));
    return QStringLiteral("[%1]").arg(result.join(QStringLiteral(", ")));
}

bool pointValue(const LanePoints &values, uint64_t tick, int *value)
{
    const auto point = std::find_if(values.cbegin(), values.cend(), [tick](const auto &candidate) {
        return candidate.first == tick;
    });
    if (point == values.cend())
        return false;
    *value = point->second;
    return true;
}

bool heldValue(const LanePoints &values, uint64_t tick, int *value)
{
    const auto next = std::upper_bound(
        values.cbegin(), values.cend(), tick,
        [](uint64_t candidate, const auto &point) { return candidate < point.first; });
    if (next == values.cbegin())
        return false;
    *value = std::prev(next)->second;
    return true;
}

double sampleTick(const AutomationGridCell &cell)
{
    return double(cell.tickBegin) + double(cell.tickEnd - cell.tickBegin) / 2.0;
}

uint64_t probeTick(const AutomationGridCell &cell)
{
    return uint64_t(sampleTick(cell));
}

void resetPan(AutomationGestureCheckRig &rig)
{
    rig.resetView();
    if (!lanePoints(rig).empty()) {
        rig.document().writeLanePoints(rig.pan.track, rig.pan.controller, 0,
                                       std::numeric_limits<uint64_t>::max(), {});
        rig.documentChanged();
    }
    rig.setPersistentPencil(true);
    rig.pump();
}

AutomationGestureCheckRig::InputPoint cellPoint(AutomationGestureCheckRig &rig,
                                                const AutomationGridCell &cell, int value)
{
    return rig.pointAt(rig.pan, sampleTick(cell), value);
}

AutomationGridCell nextCell(AutomationGestureCheckRig &rig, const AutomationGridCell &cell)
{
    return rig.projection().snapCellAt(double(cell.tickEnd));
}

uint64_t clockTickFor(AutomationGestureCheckRig &rig,
                      const AutomationGestureCheckRig::InputPoint &point)
{
    const uint64_t rawTick = uint64_t(std::floor(std::max(0.0, point.mapped.rawTick)));
    const uint64_t clocks = rig.document().ticksPerClock();
    return (rawTick / clocks) * clocks;
}

AutomationGestureCheckRig::InputPoint rawPoint(AutomationGestureCheckRig &rig, double tick,
                                               int value)
{
    auto point = rig.pointAt(rig.pan, uint64_t(std::floor(tick)), value);
    point.position.setX(rig.view().displayX(tick, rig.geometry().plotOrigin, rig.automationDpr()));
    point.mapped = rig.mappingAt(rig.handleFor(rig.pan), point.position);
    return point;
}

void runJitter(StrokeContext &ctx)
{
    AutomationGestureCheckRig &rig = ctx.rig;
    resetPan(rig);
    const auto jitterCellA = rig.pointAt(rig.pan, 36, 48).mapped.cell;
    const auto jitterCellB = nextCell(rig, jitterCellA);
    const auto jitterCellC = nextCell(rig, jitterCellB);
    const auto jitterStart = cellPoint(rig, jitterCellA, 48);
    const auto jitterEnd = cellPoint(rig, jitterCellC, jitterStart.mapped.point.value);
    const int horizontalJitter = std::max(0, rig.geometry().nodeDragActivationDistance - 1);
    rig.mousePress(jitterStart.position);
    rig.mouseMove(jitterStart.position + QPointF(horizontalJitter, 0.0));
    rig.mouseMove(jitterEnd.position);
    rig.mouseRelease(jitterEnd.position);
    rig.commitTimers();
    const auto jitterPoints = lanePoints(rig);
    int jitterAValue = -1;
    int jitterBValue = -1;
    int jitterCValue = -1;
    ctx.check(horizontalJitter > 0 &&
                  heldValue(jitterPoints, probeTick(jitterCellA), &jitterAValue) &&
                  heldValue(jitterPoints, probeTick(jitterCellB), &jitterBValue) &&
                  heldValue(jitterPoints, probeTick(jitterCellC), &jitterCValue) &&
                  jitterAValue == jitterStart.mapped.point.value &&
                  jitterBValue == jitterStart.mapped.point.value &&
                  jitterCValue == jitterStart.mapped.point.value,
              QStringLiteral("Pencil sub-cell horizontal jitter changed a straight stroke "
                             "(%1/%2/%3, expected %4, slop %5)")
                  .arg(jitterAValue)
                  .arg(jitterBValue)
                  .arg(jitterCValue)
                  .arg(jitterStart.mapped.point.value)
                  .arg(horizontalJitter));
}

void runZigzag(StrokeContext &ctx)
{
    AutomationGestureCheckRig &rig = ctx.rig;
    resetPan(rig);
    const auto zigzagCellA = rig.pointAt(rig.pan, 36, 32).mapped.cell;
    const auto zigzagCellB = nextCell(rig, zigzagCellA);
    const auto zigzagCellC = nextCell(rig, zigzagCellB);
    const auto zigzagCellD = nextCell(rig, zigzagCellC);
    const auto zigzagCellE = nextCell(rig, zigzagCellD);
    const auto zigzagCellF = nextCell(rig, zigzagCellE);
    const std::array zigzagCells{zigzagCellA, zigzagCellB, zigzagCellC,
                                 zigzagCellD, zigzagCellE, zigzagCellF};
    const std::array<int, 6> zigzagValues{32, 100, 28, 92, 44, 84};
    std::array<AutomationGestureCheckRig::InputPoint, 6> zigzag{};
    for (std::size_t index = 0; index < zigzag.size(); ++index)
        zigzag[index] = cellPoint(rig, zigzagCells[index], zigzagValues[index]);
    rig.mousePress(zigzag.front().position);
    for (std::size_t index = 1; index < zigzag.size(); ++index)
        rig.mouseMove(zigzag[index].position);
    rig.mouseRelease(zigzag.back().position);
    rig.commitTimers();
    const auto zigzagPoints = lanePoints(rig);
    std::array<int, 6> zigzagHeld{};
    bool zigzagMatches = true;
    for (std::size_t index = 0; index < zigzagCells.size(); ++index) {
        zigzagMatches =
            heldValue(zigzagPoints, probeTick(zigzagCells[index]), &zigzagHeld[index]) &&
            std::abs(zigzagHeld[index] - zigzag[index].mapped.point.value) <= 1 && zigzagMatches;
    }
    const bool zigzagTurns = zigzagHeld[0] < zigzagHeld[1] && zigzagHeld[1] > zigzagHeld[2] &&
                             zigzagHeld[2] < zigzagHeld[3] && zigzagHeld[3] > zigzagHeld[4] &&
                             zigzagHeld[4] < zigzagHeld[5];
    ctx.check(zigzagMatches && zigzagTurns,
              QStringLiteral("Pencil six-cell zigzag did not preserve both turns"));
}

void runVertical(StrokeContext &ctx)
{
    AutomationGestureCheckRig &rig = ctx.rig;
    resetPan(rig);
    const auto verticalCell = rig.pointAt(rig.pan, 48, 32).mapped.cell;
    const auto verticalStart = cellPoint(rig, verticalCell, 32);
    const auto verticalEnd = rig.pointAt(rig.pan, sampleTick(verticalCell), 96);
    rig.mousePress(verticalStart.position);
    rig.mouseMove(verticalEnd.position);
    rig.mouseRelease(verticalEnd.position);
    rig.commitTimers();
    int verticalValue = -1;
    ctx.check(pointValue(lanePoints(rig), verticalStart.mapped.cell.tickBegin, &verticalValue) &&
                  verticalValue == verticalEnd.mapped.point.value,
              QStringLiteral("Pencil vertical motion within one snap cell did not keep its last "
                             "value (%1, expected %2)")
                  .arg(verticalValue)
                  .arg(verticalEnd.mapped.point.value));
}

void runDiagonal(StrokeContext &ctx)
{
    struct DiagonalCapture {
        LanePoints values;
        std::array<std::pair<uint64_t, int>, 6> expected;
    };
    struct DiagonalInput {
        std::array<AutomationGestureCheckRig::InputPoint, 6> input;
        std::array<std::pair<uint64_t, int>, 6> expected;
    };
    const auto buildInput = [](AutomationGestureCheckRig &rig, bool canonicalValues) {
        const auto cellA = rig.pointAt(rig.pan, 36, 32).mapped.cell;
        const auto cellB = nextCell(rig, cellA);
        const auto cellC = nextCell(rig, cellB);
        const auto cellD = nextCell(rig, cellC);
        const auto cellE = nextCell(rig, cellD);
        const auto cellF = nextCell(rig, cellE);
        const std::array cells{cellA, cellB, cellC, cellD, cellE, cellF};
        const auto panHandle = rig.handleFor(rig.pan);
        DiagonalInput result{};
        if (canonicalValues) {
            const std::array<int, 6> values{32, 44, 56, 68, 80, 92};
            for (std::size_t index = 0; index < result.input.size(); ++index) {
                result.input[index] = cellPoint(rig, cells[index], values[index]);
                result.expected[index] = {cells[index].tickBegin, values[index]};
            }
        } else {
            const auto start = cellPoint(rig, cellA, 8);
            const auto end = cellPoint(rig, cellF, 120);
            for (std::size_t index = 0; index < result.input.size(); ++index) {
                const qreal x = cellPoint(rig, cells[index], 64).position.x();
                const qreal fraction = (x - start.position.x()) /
                                       std::max<qreal>(1.0, end.position.x() - start.position.x());
                const QPointF position(x, start.position.y() +
                                              (end.position.y() - start.position.y()) * fraction);
                result.input[index] = {position, rig.mappingAt(panHandle, position)};
                result.expected[index] = {cells[index].tickBegin,
                                          result.input[index].mapped.point.value};
            }
        }
        return result;
    };
    const auto diagonalGesture = [buildInput](AutomationGestureCheckRig &rig, double zoom,
                                              bool dense, bool canonicalValues) {
        resetPan(rig);
        rig.setAutomationZoom(zoom);
        rig.setAutomationScroll(0.0);
        const auto input = buildInput(rig, canonicalValues);
        rig.mousePress(input.input.front().position);
        for (std::size_t index = 1; index < input.input.size(); ++index) {
            if (dense && (canonicalValues || index > 1)) {
                for (int sample = 1; sample < 4; ++sample) {
                    const qreal fraction = qreal(sample) / 4.0;
                    rig.mouseMove(input.input[index - 1].position +
                                  (input.input[index].position - input.input[index - 1].position) *
                                      fraction);
                }
            }
            rig.mouseMove(input.input[index].position);
        }
        rig.mouseRelease(input.input.back().position);
        rig.commitTimers();
        return DiagonalCapture{lanePoints(rig), input.expected};
    };
    const auto capturesMatch = [](const DiagonalCapture &sparse, const DiagonalCapture &dense,
                                  const std::array<std::pair<uint64_t, int>, 6> &expected) {
        if (sparse.values.empty() || dense.values.empty())
            return false;
        for (const auto &[tick, value] : expected) {
            int sparseValue = -1;
            int denseValue = -1;
            if (!heldValue(sparse.values, tick, &sparseValue) ||
                !heldValue(dense.values, tick, &denseValue) ||
                std::abs(sparseValue - denseValue) > 1 || std::abs(sparseValue - value) > 1 ||
                std::abs(denseValue - value) > 1)
                return false;
        }
        return true;
    };
    for (const double zoom : {96.0, 256.0, 512.0}) {
        const auto sparse = diagonalGesture(ctx.rig, zoom, false, false);
        const auto dense = diagonalGesture(ctx.rig, zoom, true, false);
        const bool equivalent = capturesMatch(sparse, dense, sparse.expected);
        ctx.check(equivalent,
                  QStringLiteral("Pencil sparse and dense diagonal streams diverged at zoom %1 "
                                 "(sparse %2, dense %3)")
                      .arg(zoom)
                      .arg(formatPoints(sparse.values))
                      .arg(formatPoints(dense.values)));
    }
    const auto canonicalSparse = diagonalGesture(ctx.rig, 96.0, false, true);
    const auto canonicalDense = diagonalGesture(ctx.rig, 96.0, true, true);
    const bool canonicalEquivalent =
        capturesMatch(canonicalSparse, canonicalDense, canonicalSparse.expected);
    ctx.check(canonicalEquivalent,
              QStringLiteral("Pencil canonical 96x sparse/dense staircase diverged "
                             "(sparse %1, dense %2)")
                  .arg(formatPoints(canonicalSparse.values))
                  .arg(formatPoints(canonicalDense.values)));
}

void runRevisit(StrokeContext &ctx)
{
    AutomationGestureCheckRig &rig = ctx.rig;
    resetPan(rig);
    const auto revisitCellA = rig.pointAt(rig.pan, 36, 28).mapped.cell;
    const auto revisitCellB = nextCell(rig, revisitCellA);
    const auto revisitCellC = nextCell(rig, revisitCellB);
    const auto revisitStart = cellPoint(rig, revisitCellA, 28);
    const auto revisitFar = cellPoint(rig, revisitCellC, 100);
    const auto revisitFinish = cellPoint(rig, revisitCellA, 68);
    rig.mousePress(revisitStart.position);
    rig.mouseMove(revisitFar.position);
    rig.mouseMove(revisitFinish.position);
    rig.mouseRelease(revisitFinish.position);
    rig.commitTimers();
    const auto revisitPoints = lanePoints(rig);
    int revisitAValue = -1;
    int revisitCValue = -1;
    ctx.check(heldValue(revisitPoints, probeTick(revisitCellA), &revisitAValue) &&
                  heldValue(revisitPoints, probeTick(revisitCellC), &revisitCValue) &&
                  std::abs(revisitAValue - revisitFinish.mapped.point.value) <= 1 &&
                  std::abs(revisitCValue - revisitFar.mapped.point.value) <= 1 &&
                  std::is_sorted(revisitPoints.cbegin(), revisitPoints.cend()),
              QStringLiteral("Pencil reverse/revisit did not retain last visit in A and far value "
                             "in C (%1/%2, expected %3/%4)")
                  .arg(revisitAValue)
                  .arg(revisitCValue)
                  .arg(revisitFinish.mapped.point.value)
                  .arg(revisitFar.mapped.point.value));
}

void runShift(StrokeContext &ctx)
{
    struct ShiftCapture {
        LanePoints values;
        uint64_t middleTick = 0;
        uint64_t endTick = 0;
        int middleValue = 0;
        int endValue = 0;
    };
    const auto shiftGesture = [](AutomationGestureCheckRig &rig, bool locked) {
        resetPan(rig);
        const auto cellA = rig.pointAt(rig.pan, 36, 64).mapped.cell;
        const auto cellB = nextCell(rig, cellA);
        const auto cellC = nextCell(rig, cellB);
        const auto start = cellPoint(rig, cellA, 64);
        const auto middle = cellPoint(rig, cellB, 48);
        const auto end = cellPoint(rig, cellC, 96);
        const auto modifiers = locked ? Qt::ShiftModifier : Qt::NoModifier;
        rig.mousePress(start.position);
        rig.mouseMove(middle.position);
        rig.mouseMove(end.position, Qt::LeftButton, modifiers);
        rig.mouseRelease(end.position, modifiers);
        rig.commitTimers();
        return ShiftCapture{lanePoints(rig), probeTick(cellB), probeTick(cellC),
                            middle.mapped.point.value, end.mapped.point.value};
    };
    const auto plainShift = shiftGesture(ctx.rig, false);
    const auto lockedShift = shiftGesture(ctx.rig, true);
    int plainMiddle = -1;
    int plainEnd = -1;
    int lockedMiddle = -1;
    int lockedEnd = -1;
    ctx.check(heldValue(plainShift.values, plainShift.middleTick, &plainMiddle) &&
                  heldValue(plainShift.values, plainShift.endTick, &plainEnd) &&
                  heldValue(lockedShift.values, lockedShift.middleTick, &lockedMiddle) &&
                  heldValue(lockedShift.values, lockedShift.endTick, &lockedEnd) &&
                  std::abs(plainMiddle - plainShift.middleValue) <= 1 &&
                  std::abs(plainEnd - plainShift.endValue) <= 1 && plainEnd != plainMiddle &&
                  std::abs(lockedMiddle - lockedShift.middleValue) <= 1 &&
                  lockedEnd == lockedMiddle,
              QStringLiteral("Shift Pencil changed Y while locked (%1 -> %2)")
                  .arg(lockedMiddle)
                  .arg(lockedEnd));
}

void runCommand(StrokeContext &ctx)
{
    AutomationGestureCheckRig &rig = ctx.rig;
    struct CommandCapture {
        LanePoints values;
        uint64_t turnTick = 0;
        int turnValue = 0;
        uint64_t terminalTick = 0;
        int terminalValue = 0;
    };
    const auto commandGesture = [](AutomationGestureCheckRig &rig, bool reverse, bool dense) {
        resetPan(rig);
        const auto start = rawPoint(rig, 31.25, 30);
        const auto turn = rawPoint(rig, 103.375, reverse ? 60 : 90);
        const auto far = rawPoint(rig, 181.625, 30);
        const auto end = rawPoint(rig, 55.75, 90);
        const auto moveSegment = [&rig, dense](const auto &from, const auto &to) {
            if (dense) {
                for (int index = 1; index < 4; ++index) {
                    const qreal fraction = qreal(index) / 4.0;
                    rig.mouseMove(from.position + (to.position - from.position) * fraction,
                                  Qt::LeftButton, Qt::ControlModifier);
                }
            }
            rig.mouseMove(to.position, Qt::LeftButton, Qt::ControlModifier);
        };
        rig.mousePress(start.position, Qt::ControlModifier);
        if (reverse) {
            moveSegment(start, far);
            moveSegment(far, turn);
            moveSegment(turn, end);
        } else {
            moveSegment(start, turn);
            moveSegment(turn, far);
        }
        const auto &finish = reverse ? end : far;
        rig.mouseRelease(finish.position, Qt::ControlModifier);
        rig.commitTimers();
        return CommandCapture{lanePoints(rig), clockTickFor(rig, turn), turn.mapped.point.value,
                              clockTickFor(rig, finish), finish.mapped.point.value};
    };
    const auto forwardSparse = commandGesture(rig, false, false);
    const auto forwardDense = commandGesture(rig, false, true);
    const auto reverseSparse = commandGesture(rig, true, false);
    const auto reverseDense = commandGesture(rig, true, true);
    const auto commandCaptureMatches = [](const CommandCapture &sparse,
                                          const CommandCapture &dense) {
        int sparseTurn = -1;
        int denseTurn = -1;
        int sparseTerminal = -1;
        int denseTerminal = -1;
        return pointValue(sparse.values, sparse.turnTick, &sparseTurn) &&
               pointValue(dense.values, dense.turnTick, &denseTurn) &&
               pointValue(sparse.values, sparse.terminalTick, &sparseTerminal) &&
               pointValue(dense.values, dense.terminalTick, &denseTerminal) &&
               std::abs(sparseTurn - sparse.turnValue) <= 1 &&
               std::abs(denseTurn - sparse.turnValue) <= 1 &&
               std::abs(sparseTerminal - sparse.terminalValue) <= 1 &&
               std::abs(denseTerminal - sparse.terminalValue) <= 1;
    };
    ctx.check(commandCaptureMatches(forwardSparse, forwardDense) &&
                  commandCaptureMatches(reverseSparse, reverseDense),
              QStringLiteral("Command Pencil freehand timing or last revisit diverged"));
}

void runMixed(StrokeContext &ctx)
{
    AutomationGestureCheckRig &rig = ctx.rig;
    resetPan(rig);
    const auto mixedCellA = rig.pointAt(rig.pan, 36, 36).mapped.cell;
    const auto mixedCellB = nextCell(rig, mixedCellA);
    const auto mixedCellC = nextCell(rig, mixedCellB);
    const auto mixedStart = cellPoint(rig, mixedCellA, 36);
    const auto mixedMiddle = cellPoint(rig, mixedCellB, 76);
    const auto mixedEnd = cellPoint(rig, mixedCellC, 104);
    rig.mousePress(mixedStart.position, Qt::ControlModifier);
    const QPointF mixedInterior =
        mixedStart.position + (mixedMiddle.position - mixedStart.position) * 0.4;
    rig.mouseMove(mixedInterior, Qt::LeftButton, Qt::ControlModifier);
    rig.mouseMove(mixedMiddle.position, Qt::LeftButton, Qt::ControlModifier);
    rig.mouseMove(mixedEnd.position);
    rig.mouseRelease(mixedEnd.position);
    rig.commitTimers();
    const auto mixedPoints = lanePoints(rig);
    const bool retainedFreehand =
        std::any_of(mixedPoints.cbegin(), mixedPoints.cend(), [&](const auto &point) {
            return point.first > mixedCellA.tickBegin && point.first < mixedCellB.tickBegin;
        });
    int mixedEndValue = -1;
    const bool snappedReplacement =
        pointValue(mixedPoints, mixedEnd.mapped.cell.tickBegin, &mixedEndValue) &&
        std::abs(mixedEndValue - mixedEnd.mapped.point.value) <= 1 &&
        std::none_of(mixedPoints.cbegin(), mixedPoints.cend(), [&](const auto &point) {
            return point.first > mixedCellC.tickBegin && point.first < mixedCellC.tickEnd;
        });
    ctx.check(retainedFreehand && snappedReplacement,
              QStringLiteral("Command freehand detail and later snapped Pencil cell did not "
                             "compose (%1)")
                  .arg(formatPoints(mixedPoints)));
}

void runAlt(StrokeContext &ctx)
{
    AutomationGestureCheckRig &rig = ctx.rig;
    const auto altGesture = [](AutomationGestureCheckRig &rig, Qt::KeyboardModifiers modifiers) {
        resetPan(rig);
        const auto cellA = rig.pointAt(rig.pan, 36, 36).mapped.cell;
        const auto cellB = nextCell(rig, cellA);
        const auto start = cellPoint(rig, cellA, 36);
        const auto end = cellPoint(rig, cellB, 96);
        rig.mousePress(start.position, modifiers);
        rig.mouseMove(end.position, Qt::LeftButton, modifiers);
        rig.mouseRelease(end.position, modifiers);
        rig.commitTimers();
        return lanePoints(rig);
    };
    const auto plainAlt = altGesture(rig, Qt::NoModifier);
    const auto alt = altGesture(rig, Qt::AltModifier);
    ctx.check(!plainAlt.empty() && plainAlt == alt,
              QStringLiteral("Alt changed Pencil time placement or held values"));
}

using StrokeScenario = void (*)(StrokeContext &);
constexpr std::array<std::pair<const char *, StrokeScenario>, 9> kStrokeScenarios{
    {{"jitter", &runJitter},
     {"zigzag", &runZigzag},
     {"vertical", &runVertical},
     {"diagonal", &runDiagonal},
     {"revisit", &runRevisit},
     {"shift", &runShift},
     {"command", &runCommand},
     {"mixed", &runMixed},
     {"alt", &runAlt}}};

} // namespace

void checkAutomationPencilStroke(AutomationGestureCheckRig &rig,
                                 const AutomationGestureCheck &check)
{
    if (!rig.pencilModeAction()) {
        check(false, QStringLiteral("Pencil Mode action is unavailable"));
        return;
    }
    StrokeContext ctx{rig, check};
    for (const auto &[name, run] : kStrokeScenarios)
        run(ctx);
}