#include "domains.h"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <vector>

#include <QCoreApplication>
#include <QImage>
#include <QPixmap>
#include <QRect>

#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"

void checkAutomationPencilTransactions(AutomationGestureCheckRig &rig,
                                       const AutomationGestureCheck &check)
{
    const auto sameLanePoints = [](const std::vector<DocLanePoint> &left,
                                   const std::vector<DocLanePoint> &right) {
        if (left.size() != right.size())
            return false;
        for (auto index = size_t{0}; index < left.size(); ++index) {
            if (left[index].smfTrack != right[index].smfTrack ||
                left[index].index != right[index].index || left[index].tick != right[index].tick ||
                left[index].value != right[index].value)
                return false;
        }
        return true;
    };
    const auto sameSnapshot = [&sameLanePoints](const AutomationGestureCheckRig::Snapshot &left,
                                                const AutomationGestureCheckRig::Snapshot &right) {
        return left.smf == right.smf && left.revision == right.revision &&
               left.undoIndex == right.undoIndex &&
               sameLanePoints(left.lanePoints, right.lanePoints);
    };
    const auto oneLaneEdit = [&sameLanePoints](const AutomationGestureCheckRig::Snapshot &before,
                                               const AutomationGestureCheckRig::Snapshot &after) {
        return after.smf != before.smf && after.revision == before.revision + 1 &&
               after.undoIndex == before.undoIndex + 1 &&
               !sameLanePoints(before.lanePoints, after.lanePoints);
    };
    const auto pointInCell = [&rig](const AutomationGestureCheckRig::Lane &lane, uint64_t tick,
                                    int value) {
        const auto probe = rig.pointAt(lane, tick, value);
        const auto &cell = probe.mapped.cell;
        return rig.pointAt(lane, cell.tickBegin + (cell.tickEnd - cell.tickBegin) / 2, value);
    };
    const auto nextCellPoint = [&pointInCell](const AutomationGestureCheckRig::Lane &lane,
                                              const AutomationGestureCheckRig::InputPoint &point,
                                              int value) {
        return pointInCell(lane, point.mapped.cell.tickEnd, value);
    };
    const auto seedPan = [&rig](int value) {
        rig.document().writeLanePoints(rig.pan.track, rig.pan.controller, 0,
                                       std::numeric_limits<uint64_t>::max(), {{0, value}});
        rig.documentChanged();
    };
    const auto rowsHaveUniqueIds = [&rig] {
        const auto &rows = rig.canvas().rows();
        for (auto left = size_t{0}; left < rows.size(); ++left) {
            for (auto right = left + 1; right < rows.size(); ++right) {
                if (rows[left].id == rows[right].id)
                    return false;
            }
        }
        return true;
    };

    rig.setAutomationZoom(96.0);
    rig.setPersistentPencil(true);

    constexpr uint8_t expressionController = 11;
    const AutomationGestureCheckRig::Lane expression{
        {EditorAutomationRowKind::ControlChange, 0, expressionController}, 0, expressionController};
    const auto emptyLaneBefore = rig.snapshot(expression.track, expression.controller);
    check(emptyLaneBefore.lanePoints.empty(),
          QStringLiteral("CC 11 empty-lane fixture unexpectedly contains document points"));

    const int lfoRowBefore = rig.rowIndex(rig.lfo);
    QImage lfoTitleBefore;
    if (lfoRowBefore >= 0) {
        const auto projection = rig.projection();
        const auto &rows = rig.canvas().rows();
        lfoTitleBefore =
            rig.canvas()
                .grab(QRect(0, projection.rowTop(lfoRowBefore), rig.canvas().plotOrigin(),
                            projection.rowHeight(rows[size_t(lfoRowBefore)])))
                .toImage();
    }
    rig.page().addEmptyLane(expression.track, expression.controller);
    rig.pump();
    const int lfoRowAfter = rig.rowIndex(rig.lfo);
    QImage lfoTitleAfter;
    if (lfoRowAfter >= 0) {
        const auto projection = rig.projection();
        const auto &rows = rig.canvas().rows();
        lfoTitleAfter =
            rig.canvas()
                .grab(QRect(0, projection.rowTop(lfoRowAfter), rig.canvas().plotOrigin(),
                            projection.rowHeight(rows[size_t(lfoRowAfter)])))
                .toImage();
    }
    check(lfoRowBefore >= 0 && lfoRowAfter >= 0 && lfoTitleBefore == lfoTitleAfter,
          QStringLiteral("adding CC 11 changed the existing LFO lane title"));
    check(rig.rowIndex(expression) >= 0 && rowsHaveUniqueIds(),
          QStringLiteral("adding CC 11 did not create one uniquely identified automation lane"));

    if (rig.rowIndex(expression) >= 0) {
        const auto emptyStart = pointInCell(expression, 48, 40);
        const auto emptyEnd =
            nextCellPoint(expression, nextCellPoint(expression, emptyStart, 72), 96);
        const auto before = rig.snapshot(expression.track, expression.controller);
        rig.mousePress(emptyStart.position);
        rig.mouseMove(emptyEnd.position);
        rig.mouseRelease(emptyEnd.position);
        const auto after = rig.snapshot(expression.track, expression.controller);
        check(!after.lanePoints.empty() && oneLaneEdit(before, after),
              QStringLiteral("Pencil stroke on an empty CC 11 lane did not commit one SMF, "
                             "revision, and Undo transaction"));
    }
    rig.setPersistentPencil(false);
    rig.page().removeEmptyLane(expression.track, expression.controller);
    rig.pump();

    seedPan(12);
    rig.setPersistentPencil(true);
    const auto previewStart = pointInCell(rig.pan, 48, 28);
    const auto previewEnd = nextCellPoint(rig.pan, nextCellPoint(rig.pan, previewStart, 72), 104);
    const auto previewBefore = rig.snapshot(rig.pan.track, rig.pan.controller);
    const QImage previewImageBefore = rig.canvas().grab().toImage();
    rig.mousePress(previewStart.position);
    rig.mouseMove(previewEnd.position);
    rig.pump();
    const auto previewDuring = rig.snapshot(rig.pan.track, rig.pan.controller);
    const QImage previewImageDuring = rig.canvas().grab().toImage();
    check(sameSnapshot(previewBefore, previewDuring) && previewImageDuring != previewImageBefore,
          QStringLiteral("Pencil live preview was not visible while preserving SMF, revision, "
                         "Undo, and lane points before release"));
    rig.mouseRelease(previewEnd.position);
    const auto previewAfter = rig.snapshot(rig.pan.track, rig.pan.controller);
    check(oneLaneEdit(previewBefore, previewAfter),
          QStringLiteral("Pencil preview release did not commit exactly one SMF, revision, and "
                         "Undo transaction"));

    const auto restoreProbe = pointInCell(rig.pan, 96, 72);
    const int restoredValue = restoreProbe.mapped.point.value;
    seedPan(restoredValue);
    rig.setPersistentPencil(true);
    const auto restoreStart = pointInCell(rig.pan, 96, 28);
    const auto restoreEnd = nextCellPoint(rig.pan, restoreStart, 104);
    const uint64_t restoreEndpoint = restoreEnd.mapped.cell.tickEnd;
    const auto restoreBefore = rig.snapshot(rig.pan.track, rig.pan.controller);
    rig.mousePress(restoreStart.position);
    rig.mouseMove(restoreEnd.position);
    rig.mouseRelease(restoreEnd.position);
    const auto restoreAfter = rig.snapshot(rig.pan.track, rig.pan.controller);
    DocLanePoint restoredEndpoint;
    const bool restored = rig.document().findLanePoint(rig.pan.track, rig.pan.controller,
                                                       restoreEndpoint, &restoredEndpoint);
    check(restored && restoredEndpoint.value == restoredValue &&
              oneLaneEdit(restoreBefore, restoreAfter),
          QStringLiteral("Pencil transaction did not restore the prior held endpoint value in "
                         "one SMF, revision, and Undo edit"));

    const auto flatProbe = pointInCell(rig.pan, 144, 60);
    const int flatValue = flatProbe.mapped.point.value;
    seedPan(flatValue);
    rig.setPersistentPencil(true);
    const auto flatStart = pointInCell(rig.pan, 144, flatValue);
    const auto flatEnd = nextCellPoint(rig.pan, flatStart, flatValue);
    const auto flatBefore = rig.snapshot(rig.pan.track, rig.pan.controller);
    rig.mousePress(flatStart.position);
    rig.mouseMove(flatEnd.position);
    rig.mouseRelease(flatEnd.position);
    const auto flatAfter = rig.snapshot(rig.pan.track, rig.pan.controller);
    check(sameSnapshot(flatBefore, flatAfter),
          QStringLiteral("Pencil flat stroke changed an already-held value's SMF, revision, "
                         "Undo, or lane points"));

    const auto noOpBefore = rig.snapshot(rig.pan.track, rig.pan.controller);
    rig.mousePress(flatStart.position);
    rig.mouseRelease(flatStart.position);
    const auto noOpAfter = rig.snapshot(rig.pan.track, rig.pan.controller);
    check(sameSnapshot(noOpBefore, noOpAfter),
          QStringLiteral("Pencil semantic no-op click changed SMF, revision, Undo, or lane "
                         "points"));

    auto deletionPoint = pointInCell(rig.pan, 192, 60);
    if (deletionPoint.mapped.cell.tickBegin == 0)
        deletionPoint = nextCellPoint(rig.pan, deletionPoint, 60);
    const auto deletionCell = deletionPoint.mapped.cell;
    const int deletionHeldValue = deletionPoint.mapped.point.value;
    const int deletionExcursionValue =
        deletionHeldValue < 64 ? deletionHeldValue + 32 : deletionHeldValue - 32;
    rig.document().writeLanePoints(rig.pan.track, rig.pan.controller, 0,
                                   std::numeric_limits<uint64_t>::max(),
                                   {{0, deletionHeldValue},
                                    {deletionCell.tickBegin, deletionExcursionValue},
                                    {deletionCell.tickEnd, deletionHeldValue}});
    rig.documentChanged();
    rig.setPersistentPencil(true);
    const auto deletionBefore = rig.snapshot(rig.pan.track, rig.pan.controller);
    rig.mousePress(deletionPoint.position);
    rig.mouseRelease(deletionPoint.position);
    const auto deletionAfter = rig.snapshot(rig.pan.track, rig.pan.controller);
    const bool deletionRangeEmpty = std::none_of(
        deletionAfter.lanePoints.cbegin(), deletionAfter.lanePoints.cend(),
        [&deletionCell](const DocLanePoint &point) {
            return point.tick >= deletionCell.tickBegin && point.tick <= deletionCell.tickEnd;
        });
    const bool deletionLeavesHeldValue =
        deletionAfter.lanePoints.size() == 1 && deletionAfter.lanePoints.front().tick == 0 &&
        deletionAfter.lanePoints.front().value == deletionHeldValue;
    check(deletionRangeEmpty && deletionLeavesHeldValue &&
              oneLaneEdit(deletionBefore, deletionAfter),
          QStringLiteral("Pencil deletion-only completion did not remove the local excursion in "
                         "one SMF, revision, and Undo transaction"));

    const auto checkCancellation = [&](const QString &route, const auto &cancel) {
        seedPan(36);
        rig.setPersistentPencil(true);
        const auto cancelStart = pointInCell(rig.pan, 240, 28);
        const auto cancelEnd = nextCellPoint(rig.pan, cancelStart, 100);
        const auto before = rig.snapshot(rig.pan.track, rig.pan.controller);
        rig.mousePress(cancelStart.position);
        rig.mouseMove(cancelEnd.position);
        rig.pump();
        cancel();
        rig.pump();
        rig.mouseRelease(cancelEnd.position);
        rig.pump();
        const auto after = rig.snapshot(rig.pan.track, rig.pan.controller);
        check(sameSnapshot(before, after),
              QStringLiteral("Pencil %1 cancellation changed SMF, revision, Undo, or lane "
                             "points")
                  .arg(route));
    };
    checkCancellation(QStringLiteral("Escape"),
                      [&rig] { rig.keyToArea(QEvent::KeyPress, Qt::Key_Escape); });
    checkCancellation(QStringLiteral("page-hide"), [&rig] {
        rig.page().hide();
        rig.pump();
        rig.page().show();
    });
    checkCancellation(QStringLiteral("window-deactivation"), [&rig] {
        QEvent event(QEvent::WindowDeactivate);
        QCoreApplication::sendEvent(&rig.page(), &event);
    });
    checkCancellation(QStringLiteral("document-refresh"), [&rig] { rig.documentChanged(); });
    rig.setPersistentPencil(false);
}
