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

void checkAutomationPencilStroke(AutomationGestureCheckRig &rig,
                                 const AutomationGestureCheck &check)
{
    if (!rig.pencilModeAction()) {
        check(false, QStringLiteral("Pencil Mode action is unavailable"));
        return;
    }
    using LanePoints = std::vector<std::pair<uint64_t, int>>;
    const auto points = [&] {
        LanePoints result;
        for (const DocLanePoint &point : rig.snapshot(rig.pan.track, rig.pan.controller).lanePoints)
            result.emplace_back(point.tick, point.value);
        return result;
    };
    const auto formatPoints = [](const LanePoints &values) {
        QStringList result;
        for (const auto &[tick, value] : values)
            result.append(QStringLiteral("{%1,%2}").arg(tick).arg(value));
        return QStringLiteral("[%1]").arg(result.join(QStringLiteral(", ")));
    };
    const auto pointValue = [](const LanePoints &values, uint64_t tick, int *value) {
        const auto point =
            std::find_if(values.cbegin(), values.cend(),
                         [tick](const auto &candidate) { return candidate.first == tick; });
        if (point == values.cend())
            return false;
        *value = point->second;
        return true;
    };
    const auto heldValue = [](const LanePoints &values, uint64_t tick, int *value) {
        const auto next = std::upper_bound(
            values.cbegin(), values.cend(), tick,
            [](uint64_t candidate, const auto &point) { return candidate < point.first; });
        if (next == values.cbegin())
            return false;
        *value = std::prev(next)->second;
        return true;
    };
    const auto sampleTick = [](const auto &cell) {
        return double(cell.tickBegin) + double(cell.tickEnd - cell.tickBegin) / 2.0;
    };
    const auto probeTick = [&](const auto &cell) { return uint64_t(sampleTick(cell)); };
    const auto resetPan = [&] {
        rig.setAutomationZoom(96.0);
        rig.setAutomationScroll(0.0);
        if (!points().empty()) {
            rig.document().writeLanePoints(rig.pan.track, rig.pan.controller, 0,
                                           std::numeric_limits<uint64_t>::max(), {});
            rig.documentChanged();
        }
        rig.setPersistentPencil(true);
        rig.pump();
    };
    const auto cellPoint = [&](const auto &cell, int value) {
        return rig.pointAt(rig.pan, sampleTick(cell), value);
    };
    const auto nextCell = [&](const auto &cell) {
        return rig.projection().snapCellAt(double(cell.tickEnd));
    };

    resetPan();
    const auto jitterCellA = rig.pointAt(rig.pan, 36, 64).mapped.cell;
    const auto jitterCellB = nextCell(jitterCellA);
    const auto jitterCellC = nextCell(jitterCellB);
    const auto jitterStart = cellPoint(jitterCellA, 64);
    const auto jitterEnd = cellPoint(jitterCellC, jitterStart.mapped.point.value);
    const int horizontalJitter = std::max(0, rig.geometry().nodeDragActivationDistance - 1);
    rig.mousePress(jitterStart.position);
    rig.mouseMove(jitterStart.position + QPointF(horizontalJitter, 0.0));
    rig.mouseMove(jitterEnd.position);
    rig.mouseRelease(jitterEnd.position);
    rig.waitForTimers(0);
    const auto jitterPoints = points();
    int jitterAValue = -1;
    int jitterBValue = -1;
    int jitterCValue = -1;
    check(horizontalJitter > 0 && heldValue(jitterPoints, probeTick(jitterCellA), &jitterAValue) &&
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

    resetPan();
    const auto zigzagCellA = rig.pointAt(rig.pan, 36, 32).mapped.cell;
    const auto zigzagCellB = nextCell(zigzagCellA);
    const auto zigzagCellC = nextCell(zigzagCellB);
    const auto zigzagCellD = nextCell(zigzagCellC);
    const auto zigzagCellE = nextCell(zigzagCellD);
    const auto zigzagCellF = nextCell(zigzagCellE);
    const std::array zigzagCells{zigzagCellA, zigzagCellB, zigzagCellC,
                                 zigzagCellD, zigzagCellE, zigzagCellF};
    const std::array<int, 6> zigzagValues{32, 100, 28, 92, 44, 84};
    std::array<AutomationGestureCheckRig::InputPoint, 6> zigzag{};
    for (std::size_t index = 0; index < zigzag.size(); ++index)
        zigzag[index] = cellPoint(zigzagCells[index], zigzagValues[index]);
    rig.mousePress(zigzag.front().position);
    for (std::size_t index = 1; index < zigzag.size(); ++index)
        rig.mouseMove(zigzag[index].position);
    rig.mouseRelease(zigzag.back().position);
    rig.waitForTimers(0);
    const auto zigzagPoints = points();
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
    check(zigzagMatches && zigzagTurns,
          QStringLiteral("Pencil six-cell zigzag did not preserve both turns"));

    resetPan();
    const auto verticalCell = rig.pointAt(rig.pan, 48, 32).mapped.cell;
    const auto verticalStart = cellPoint(verticalCell, 32);
    const auto verticalEnd = rig.pointAt(rig.pan, sampleTick(verticalCell), 96);
    rig.mousePress(verticalStart.position);
    rig.mouseMove(verticalEnd.position);
    rig.mouseRelease(verticalEnd.position);
    rig.waitForTimers(0);
    int verticalValue = -1;
    check(pointValue(points(), verticalStart.mapped.cell.tickBegin, &verticalValue) &&
              verticalValue == verticalEnd.mapped.point.value,
          QStringLiteral("Pencil vertical motion within one snap cell did not keep its last value "
                         "(%1, expected %2)")
              .arg(verticalValue)
              .arg(verticalEnd.mapped.point.value));

    struct DiagonalCapture {
        LanePoints values;
        std::array<std::pair<uint64_t, int>, 6> expected;
    };
    const auto diagonalGesture = [&](double zoom, bool dense, bool canonicalValues) {
        resetPan();
        rig.setAutomationZoom(zoom);
        rig.setAutomationScroll(0.0);
        const auto cellA = rig.pointAt(rig.pan, 36, 32).mapped.cell;
        const auto cellB = nextCell(cellA);
        const auto cellC = nextCell(cellB);
        const auto cellD = nextCell(cellC);
        const auto cellE = nextCell(cellD);
        const auto cellF = nextCell(cellE);
        const std::array cells{cellA, cellB, cellC, cellD, cellE, cellF};
        const auto projection = rig.projection();
        const int panRow = rig.rowIndex(rig.pan);
        std::array<AutomationGestureCheckRig::InputPoint, 6> input{};
        std::array<std::pair<uint64_t, int>, 6> expected{};
        if (canonicalValues) {
            const std::array<int, 6> values{32, 44, 56, 68, 80, 92};
            for (std::size_t index = 0; index < input.size(); ++index) {
                input[index] = cellPoint(cells[index], values[index]);
                expected[index] = {cells[index].tickBegin, values[index]};
            }
        } else {
            const auto start = cellPoint(cellA, 8);
            const auto end = cellPoint(cellF, 120);
            for (std::size_t index = 0; index < input.size(); ++index) {
                const qreal x = cellPoint(cells[index], 64).position.x();
                const qreal fraction = (x - start.position.x()) /
                                       std::max<qreal>(1.0, end.position.x() - start.position.x());
                const QPointF position(x, start.position.y() +
                                              (end.position.y() - start.position.y()) * fraction);
                input[index] = {position,
                                projection.pointerMapping(panRow, position.x(), position.y())};
                expected[index] = {cells[index].tickBegin, input[index].mapped.point.value};
            }
        }
        rig.mousePress(input.front().position);
        for (std::size_t index = 1; index < input.size(); ++index) {
            if (dense && (canonicalValues || index > 1)) {
                for (int sample = 1; sample < 4; ++sample) {
                    const qreal fraction = qreal(sample) / 4.0;
                    rig.mouseMove(input[index - 1].position +
                                  (input[index].position - input[index - 1].position) * fraction);
                }
            }
            rig.mouseMove(input[index].position);
        }
        rig.mouseRelease(input.back().position);
        rig.waitForTimers(0);
        return DiagonalCapture{points(), expected};
    };
    for (const double zoom : {96.0, 256.0, 512.0}) {
        const auto sparse = diagonalGesture(zoom, false, false);
        const auto dense = diagonalGesture(zoom, true, false);
        bool equivalent = !sparse.values.empty() && !dense.values.empty();
        for (const auto &expected : sparse.expected) {
            int sparseValue = -1;
            int denseValue = -1;
            equivalent = heldValue(sparse.values, expected.first, &sparseValue) &&
                         heldValue(dense.values, expected.first, &denseValue) &&
                         std::abs(sparseValue - denseValue) <= 1 &&
                         std::abs(sparseValue - expected.second) <= 1 &&
                         std::abs(denseValue - expected.second) <= 1 && equivalent;
        }
        check(equivalent,
              QStringLiteral("Pencil sparse and dense diagonal streams diverged at zoom %1 "
                             "(sparse %2, dense %3)")
                  .arg(zoom)
                  .arg(formatPoints(sparse.values))
                  .arg(formatPoints(dense.values)));
    }
    const auto canonicalSparse = diagonalGesture(96.0, false, true);
    const auto canonicalDense = diagonalGesture(96.0, true, true);
    bool canonicalEquivalent = !canonicalSparse.values.empty() && !canonicalDense.values.empty();
    for (const auto &expected : canonicalSparse.expected) {
        int sparseValue = -1;
        int denseValue = -1;
        canonicalEquivalent = heldValue(canonicalSparse.values, expected.first, &sparseValue) &&
                              heldValue(canonicalDense.values, expected.first, &denseValue) &&
                              std::abs(sparseValue - denseValue) <= 1 &&
                              std::abs(sparseValue - expected.second) <= 1 &&
                              std::abs(denseValue - expected.second) <= 1 && canonicalEquivalent;
    }
    check(canonicalEquivalent,
          QStringLiteral("Pencil canonical 96x sparse/dense staircase diverged "
                         "(sparse %1, dense %2)")
              .arg(formatPoints(canonicalSparse.values))
              .arg(formatPoints(canonicalDense.values)));

    resetPan();
    const auto revisitCellA = rig.pointAt(rig.pan, 36, 28).mapped.cell;
    const auto revisitCellB = nextCell(revisitCellA);
    const auto revisitCellC = nextCell(revisitCellB);
    const auto revisitStart = cellPoint(revisitCellA, 28);
    const auto revisitFar = cellPoint(revisitCellC, 100);
    const auto revisitFinish = cellPoint(revisitCellA, 68);
    rig.mousePress(revisitStart.position);
    rig.mouseMove(revisitFar.position);
    rig.mouseMove(revisitFinish.position);
    rig.mouseRelease(revisitFinish.position);
    rig.waitForTimers(0);
    const auto revisitPoints = points();
    int revisitAValue = -1;
    int revisitCValue = -1;
    check(heldValue(revisitPoints, probeTick(revisitCellA), &revisitAValue) &&
              heldValue(revisitPoints, probeTick(revisitCellC), &revisitCValue) &&
              std::abs(revisitAValue - revisitFinish.mapped.point.value) <= 1 &&
              std::abs(revisitCValue - revisitFar.mapped.point.value) <= 1 &&
              std::is_sorted(revisitPoints.cbegin(), revisitPoints.cend()),
          QStringLiteral("Pencil reverse/revisit did not retain last visit in A and far value in C "
                         "(%1/%2, expected %3/%4)")
              .arg(revisitAValue)
              .arg(revisitCValue)
              .arg(revisitFinish.mapped.point.value)
              .arg(revisitFar.mapped.point.value));

    struct ShiftCapture {
        LanePoints values;
        uint64_t middleTick = 0;
        uint64_t endTick = 0;
        int middleValue = 0;
        int endValue = 0;
    };
    const auto shiftGesture = [&](bool locked) {
        resetPan();
        const auto cellA = rig.pointAt(rig.pan, 36, 64).mapped.cell;
        const auto cellB = nextCell(cellA);
        const auto cellC = nextCell(cellB);
        const auto start = cellPoint(cellA, 64);
        const auto middle = cellPoint(cellB, 48);
        const auto end = cellPoint(cellC, 96);
        const auto modifiers = locked ? Qt::ShiftModifier : Qt::NoModifier;
        rig.mousePress(start.position);
        rig.mouseMove(middle.position);
        rig.mouseMove(end.position, Qt::LeftButton, modifiers);
        rig.mouseRelease(end.position, modifiers);
        rig.waitForTimers(0);
        return ShiftCapture{points(), probeTick(cellB), probeTick(cellC), middle.mapped.point.value,
                            end.mapped.point.value};
    };
    const auto plainShift = shiftGesture(false);
    const auto lockedShift = shiftGesture(true);
    int plainMiddle = -1;
    int plainEnd = -1;
    int lockedMiddle = -1;
    int lockedEnd = -1;
    check(heldValue(plainShift.values, plainShift.middleTick, &plainMiddle) &&
              heldValue(plainShift.values, plainShift.endTick, &plainEnd) &&
              heldValue(lockedShift.values, lockedShift.middleTick, &lockedMiddle) &&
              heldValue(lockedShift.values, lockedShift.endTick, &lockedEnd) &&
              std::abs(plainMiddle - plainShift.middleValue) <= 1 &&
              std::abs(plainEnd - plainShift.endValue) <= 1 && plainEnd != plainMiddle &&
              std::abs(lockedMiddle - lockedShift.middleValue) <= 1 && lockedEnd == lockedMiddle,
          QStringLiteral("Shift Pencil changed Y while locked (%1 -> %2)")
              .arg(lockedMiddle)
              .arg(lockedEnd));

    struct CommandCapture {
        LanePoints values;
        uint64_t turnTick = 0;
        int turnValue = 0;
        uint64_t terminalTick = 0;
        int terminalValue = 0;
    };
    const auto clockTickFor = [&](const AutomationGestureCheckRig::InputPoint &point) {
        const uint64_t rawTick = uint64_t(std::floor(std::max(0.0, point.mapped.rawTick)));
        const uint64_t clocks = rig.document().ticksPerClock();
        return (rawTick / clocks) * clocks;
    };
    const auto rawPoint = [&](double tick, int value) {
        auto point = rig.pointAt(rig.pan, uint64_t(std::floor(tick)), value);
        point.position.setX(
            rig.view().displayX(tick, rig.geometry().plotOrigin, rig.canvas().devicePixelRatioF()));
        point.mapped = rig.projection().pointerMapping(rig.rowIndex(rig.pan), point.position.x(),
                                                       point.position.y());
        return point;
    };
    const auto commandGesture = [&](bool reverse, bool dense) {
        resetPan();
        const auto start = rawPoint(31.25, 30);
        const auto turn = rawPoint(103.375, reverse ? 60 : 90);
        const auto far = rawPoint(181.625, 30);
        const auto end = rawPoint(55.75, 90);
        const auto moveSegment = [&](const auto &from, const auto &to) {
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
        rig.waitForTimers(0);
        return CommandCapture{points(), clockTickFor(turn), turn.mapped.point.value,
                              clockTickFor(finish), finish.mapped.point.value};
    };
    const auto forwardSparse = commandGesture(false, false);
    const auto forwardDense = commandGesture(false, true);
    const auto reverseSparse = commandGesture(true, false);
    const auto reverseDense = commandGesture(true, true);
    const auto commandCaptureMatches = [&](const CommandCapture &sparse,
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
    check(commandCaptureMatches(forwardSparse, forwardDense) &&
              commandCaptureMatches(reverseSparse, reverseDense),
          QStringLiteral("Command Pencil freehand timing or last revisit diverged"));

    resetPan();
    const auto mixedCellA = rig.pointAt(rig.pan, 36, 36).mapped.cell;
    const auto mixedCellB = nextCell(mixedCellA);
    const auto mixedCellC = nextCell(mixedCellB);
    const auto mixedStart = cellPoint(mixedCellA, 36);
    const auto mixedMiddle = cellPoint(mixedCellB, 76);
    const auto mixedEnd = cellPoint(mixedCellC, 104);
    rig.mousePress(mixedStart.position, Qt::ControlModifier);
    const QPointF mixedInterior =
        mixedStart.position + (mixedMiddle.position - mixedStart.position) * 0.4;
    rig.mouseMove(mixedInterior, Qt::LeftButton, Qt::ControlModifier);
    rig.mouseMove(mixedMiddle.position, Qt::LeftButton, Qt::ControlModifier);
    rig.mouseMove(mixedEnd.position);
    rig.mouseRelease(mixedEnd.position);
    rig.waitForTimers(0);
    const auto mixedPoints = points();
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
    check(retainedFreehand && snappedReplacement,
          QStringLiteral("Command freehand detail and later snapped Pencil cell did not compose "
                         "(%1)")
              .arg(formatPoints(mixedPoints)));

    const auto altGesture = [&](Qt::KeyboardModifiers modifiers) {
        resetPan();
        const auto cellA = rig.pointAt(rig.pan, 36, 36).mapped.cell;
        const auto cellB = nextCell(cellA);
        const auto start = cellPoint(cellA, 36);
        const auto end = cellPoint(cellB, 96);
        rig.mousePress(start.position, modifiers);
        rig.mouseMove(end.position, Qt::LeftButton, modifiers);
        rig.mouseRelease(end.position, modifiers);
        rig.waitForTimers(0);
        return points();
    };
    const auto plainAlt = altGesture(Qt::NoModifier);
    const auto alt = altGesture(Qt::AltModifier);
    check(!plainAlt.empty() && plainAlt == alt,
          QStringLiteral("Alt changed Pencil time placement or held values"));
}
