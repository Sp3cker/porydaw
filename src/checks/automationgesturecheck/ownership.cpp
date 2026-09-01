#include "domains.h"

#include <algorithm>
#include <cmath>
#include <iterator>
#include <limits>
#include <vector>

#include <QColor>
#include <QImage>

#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/layout.h"
#include "ui/songview/quick/timelinequickscene.h"

#include "ui/songview.h"

namespace {

bool hasRingAt(const songview::TimelineQuickLayerData &layer, const QPointF &center, qreal radius,
               qreal width, const QColor &color)
{
    const qreal tolerance = layout::singlePixel();
    const qreal inner = std::max<qreal>(0.0, radius - width / 2.0 - tolerance);
    const qreal outer = radius + width / 2.0 + tolerance;
    const qreal innerSquared = inner * inner;
    const qreal outerSquared = outer * outer;
    const auto onRing = [&](const QPointF &point) {
        const QPointF delta = point - center;
        const qreal distanceSquared = delta.x() * delta.x() + delta.y() * delta.y();
        return distanceSquared >= innerSquared && distanceSquared <= outerSquared;
    };
    return std::count_if(layer.triangles.cbegin(), layer.triangles.cend(),
                         [&](const songview::TimelineQuickTriangle &triangle) {
                             return triangle.firstColor == color && triangle.secondColor == color &&
                                    triangle.thirdColor == color && onRing(triangle.first) &&
                                    onRing(triangle.second) && onRing(triangle.third);
                         }) >= 4;
}

} // namespace

void checkAutomationPencilOwnership(AutomationGestureCheckRig &rig,
                                    const AutomationGestureCheck &check)
{
    const auto heldValueAt = [](const std::vector<DocLanePoint> &points, uint64_t tick,
                                int *value) {
        const auto firstAfterTick = std::upper_bound(
            points.cbegin(), points.cend(), tick,
            [](uint64_t needle, const DocLanePoint &point) { return needle < point.tick; });
        if (firstAfterTick == points.cbegin())
            return false;
        *value = std::prev(firstAfterTick)->value;
        return true;
    };
    const auto resetPan = [&] {
        rig.setPersistentPencil(false);
        const auto pan = rig.snapshot(rig.pan.track, rig.pan.controller);
        if (!pan.lanePoints.empty()) {
            rig.document().deleteLanePoints(rig.pan.track, rig.pan.controller, pan.lanePoints);
            rig.documentChanged();
        }
        rig.view().selectionModel().clearTimeSelection();
        rig.pump();
    };
    const auto geometry = rig.geometry();
    const double detailThreshold = double(geometry.pointDetailThreshold);
    resetPan();
    {
        // Tracks scope has no CC lane reticle/menu coverage, but every point
        // in the selected track range is one node-selection set. The endpoint
        // is half-open: the point at 192 remains outside [24, 192).
        rig.setAutomationZoom(detailThreshold);
        rig.document().writeLanePoints(rig.pan.track, rig.pan.controller, 0,
                                       std::numeric_limits<uint64_t>::max(),
                                       {{48, 32}, {96, 64}, {144, 96}, {192, 80}});
        rig.documentChanged();

        const auto nodesBefore =
            rig.quickScene().layer(songview::TimelineQuickLayer::AutomationNodes);

        const auto selected48 = rig.pointAt(rig.pan, 48, 32);
        const auto selected96 = rig.pointAt(rig.pan, 96, 64);
        const auto selected144 = rig.pointAt(rig.pan, 144, 96);
        const auto endpoint = rig.pointAt(rig.pan, 192, 80);
        songview::EditorSelectionModel::TimeSelection tracksSelection;
        tracksSelection.startTick = 24;
        tracksSelection.endTick = 192;
        tracksSelection.scope = songview::EditorSelectionModel::TimeSelection::Tracks;
        rig.view().selectionModel().setTimeSelection(tracksSelection);
        rig.pump();
        QString selectionCaptureError;
        const QImage selectionFramebuffer = rig.renderAutomationViewport(&selectionCaptureError);
        const auto &nodeLayer =
            rig.quickScene().layer(songview::TimelineQuickLayer::AutomationNodes);
        const qreal ringRadius = geometry.selectedNodeRingRadius;
        const qreal ringWidth = geometry.selectedNodeRingDipWidth;
        const QColor selectionColor = rig.canvas().palette().highlight().color();
        const auto ringPaintedAt = [&](const QPointF &position) {
            return hasRingAt(nodeLayer, rig.automationContentToViewport(position), ringRadius,
                             ringWidth, selectionColor);
        };
        check(selectionCaptureError.isEmpty() && !selectionFramebuffer.isNull() &&
                  nodeLayer.revision > nodesBefore.revision && ringPaintedAt(selected48.position) &&
                  ringPaintedAt(selected96.position) && ringPaintedAt(selected144.position) &&
                  !ringPaintedAt(endpoint.position),
              QStringLiteral("Tracks-scope CC selection did not retain one half-open Quick node "
                             "ring set"));

        const auto before = snapshot(rig.document());
        const auto grab = rig.pointAt(rig.pan, 96, 64);
        const auto target = rig.pointAt(rig.pan, 120, 64);
        const qreal activationDistance = qreal(geometry.nodeDragActivationDistance + 2);
        const QPointF activation = grab.position + QPointF(activationDistance, 0.0);
        const QPointF end = activation + target.position - grab.position;
        rig.mousePress(grab.position);
        rig.mouseMove(activation);
        rig.mouseMove(end, Qt::LeftButton, Qt::AltModifier);
        rig.mouseRelease(end, Qt::AltModifier);
        rig.pump();

        const auto after = snapshot(rig.document());
        const auto &selectionAfter = rig.view().selectionModel().timeSelection();
        const bool movedTogether =
            rawValuesAt(rig.document(), rig.pan.track, rig.pan.controller, 72) ==
                std::vector<int>{32} &&
            rawValuesAt(rig.document(), rig.pan.track, rig.pan.controller, 120) ==
                std::vector<int>{64} &&
            rawValuesAt(rig.document(), rig.pan.track, rig.pan.controller, 168) ==
                std::vector<int>{96} &&
            rawValuesAt(rig.document(), rig.pan.track, rig.pan.controller, 192) ==
                std::vector<int>{80} &&
            rawValuesAt(rig.document(), rig.pan.track, rig.pan.controller, 48).empty() &&
            rawValuesAt(rig.document(), rig.pan.track, rig.pan.controller, 96).empty() &&
            rawValuesAt(rig.document(), rig.pan.track, rig.pan.controller, 144).empty();
        const bool selectionMoved =
            selectionAfter.startTick == 48 && selectionAfter.endTick == 216 &&
            selectionAfter.scope == songview::EditorSelectionModel::TimeSelection::Tracks &&
            selectionAfter.lanes.empty() && !selectionAfter.tempo;
        check(isOneEdit(before, after),
              QStringLiteral("Tracks-scope CC selection drag was not one edit"));
        check(movedTogether,
              QStringLiteral("Tracks-scope CC selection drag did not move its node set"));
        check(selectionMoved,
              QStringLiteral("Tracks-scope CC selection drag did not move its time range"));

        rig.document().undoStack()->undo();
        rig.documentChanged();
        const auto undone = snapshot(rig.document());
        check(undone.smf == before.smf && undone.undoIndex == before.undoIndex,
              QStringLiteral("Tracks-scope CC selection drag undo did not restore the edit"));
        rig.document().undoStack()->redo();
        rig.documentChanged();
    }

    rig.setPersistentPencil(true);
    const auto lfoHandle = rig.handleFor(rig.lfo);
    check(lfoHandle.valid(),
          QStringLiteral("Pencil ownership fixture did not expose the LFO lane"));
    if (lfoHandle.valid()) {
        const auto lfoPoint = rig.pointAt(rig.lfo, 24, 64);
        const QRect lfoBody = rig.bodyFor(lfoHandle);
        const QPointF boundary(lfoPoint.position.x(), lfoBody.top() + lfoBody.height());
        rig.mouseMove(boundary, Qt::NoButton);
        rig.pump();
        check(rig.canvas().cursor().shape() == Qt::SplitVCursor,
              QStringLiteral("Pencil row boundary did not retain resize cursor precedence"));
    }

    resetPan();
    rig.setAutomationZoom(detailThreshold);
    rig.setPersistentPencil(true);
    const auto pencilStart = rig.pointAt(rig.pan, 24, 36);
    const auto pencilEnd = rig.pointAt(rig.pan, 120, 92);
    rig.mousePress(pencilStart.position);
    rig.keyToView(QEvent::KeyPress, Qt::Key_B);
    rig.mouseMove(pencilEnd.position);
    rig.mouseRelease(pencilEnd.position);
    rig.keyToView(QEvent::KeyRelease, Qt::Key_B);
    rig.pump();
    const auto pencilResult = rig.snapshot(rig.pan.track, rig.pan.controller);
    const uint64_t pencilSample =
        pencilEnd.mapped.cell.tickBegin +
        (pencilEnd.mapped.cell.tickEnd - pencilEnd.mapped.cell.tickBegin) / 2;
    int pencilValue = -1;
    const bool pencilOwned = heldValueAt(pencilResult.lanePoints, pencilSample, &pencilValue) &&
                             pencilValue == pencilEnd.mapped.point.value;
    check(
        pencilOwned,
        QStringLiteral("active Pencil gesture lost ownership when Pencil mode changed while held"));

    resetPan();
    rig.setAutomationZoom(detailThreshold);
    const auto normalSource = rig.pointAt(rig.pan, 72, 64);
    rig.document().addLanePoint(rig.pan.track, rig.pan.controller, normalSource.mapped.point.tick,
                                normalSource.mapped.point.value);
    rig.documentChanged();
    const auto normalGrab =
        rig.pointAt(rig.pan, normalSource.mapped.point.tick, normalSource.mapped.point.value);
    const auto normalTarget = rig.pointAt(rig.pan, normalGrab.mapped.cell.tickEnd + 96, 96);
    songview::EditorSelectionModel::TimeSelection normalSelection;
    normalSelection.startTick = normalGrab.mapped.point.tick;
    normalSelection.endTick = normalGrab.mapped.cell.tickEnd;
    normalSelection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    normalSelection.lanes = {{rig.pan.track, rig.pan.controller}};
    rig.view().selectionModel().setTimeSelection(normalSelection);
    const qreal armDistance = qreal(geometry.nodeDragActivationDistance + 2);
    const QPointF normalArm = normalGrab.position + QPointF(armDistance, 0.0);
    const QPointF normalEnd = normalTarget.position + QPointF(armDistance, 0.0);
    rig.mousePress(normalGrab.position);
    rig.keyToView(QEvent::KeyPress, Qt::Key_B);
    rig.mouseMove(normalArm);
    rig.mouseMove(normalEnd);
    rig.mouseRelease(normalEnd);
    rig.keyToView(QEvent::KeyRelease, Qt::Key_B);
    rig.pump();
    DocLanePoint normalMoved{};
    DocLanePoint normalOriginal{};
    const bool normalTargetFound = rig.document().findLanePoint(
        rig.pan.track, rig.pan.controller, normalTarget.mapped.point.tick, &normalMoved);
    const bool normalSourceGone = !rig.document().findLanePoint(
        rig.pan.track, rig.pan.controller, normalGrab.mapped.point.tick, &normalOriginal);
    const auto normalSelectionAfter = rig.view().selectionModel().timeSelection();
    const int64_t normalDelta =
        int64_t(normalTarget.mapped.point.tick) - int64_t(normalGrab.mapped.point.tick);
    const bool normalSelectionMoved =
        normalSelectionAfter.startTick ==
            uint64_t(int64_t(normalSelection.startTick) + normalDelta) &&
        normalSelectionAfter.endTick == uint64_t(int64_t(normalSelection.endTick) + normalDelta) &&
        normalSelectionAfter.scope == normalSelection.scope &&
        normalSelectionAfter.lanes == normalSelection.lanes;
    check(normalTarget.mapped.point.tick > normalGrab.mapped.point.tick && normalTargetFound &&
              normalMoved.value == normalTarget.mapped.point.value && normalSourceGone &&
              normalSelectionMoved,
          QStringLiteral("normal node selection/drag lost ownership when Pencil mode changed "
                         "while held"));

    resetPan();
    rig.setPersistentPencil(true);
    songview::EditorSelectionModel::TimeSelection pencilSelection;
    pencilSelection.startTick = 24;
    pencilSelection.endTick = 72;
    pencilSelection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    pencilSelection.lanes = {{rig.pan.track, rig.pan.controller}};
    rig.view().selectionModel().setTimeSelection(pencilSelection);
    const auto selectionStart = rig.pointAt(rig.pan, 144, 32);
    const auto selectionEnd = rig.pointAt(rig.pan, 216, 96);
    rig.mousePress(selectionStart.position);
    rig.mouseMove(selectionEnd.position);
    rig.mouseRelease(selectionEnd.position);
    rig.pump();
    const auto selectionAfterPencil = rig.view().selectionModel().timeSelection();
    check(!selectionAfterPencil.active(),
          QStringLiteral("Pencil stroke outside the time selection did not clear it"));

    check(
        detailThreshold > 1.0,
        QStringLiteral("Pencil node detail threshold did not permit a hidden visibility fixture"));
    rig.setAutomationZoom(detailThreshold - 1.0);
    const bool nodesHidden = !rig.projection().nodeMarkersVisible();
    check(nodesHidden,
          QStringLiteral("Pencil node markers remained visible below the detail threshold"));
    rig.setAutomationZoom(detailThreshold);
    const bool nodesVisible = rig.projection().nodeMarkersVisible();
    check(nodesVisible,
          QStringLiteral("Pencil node markers were not visible at the detail threshold"));

    if (nodesHidden) {
        resetPan();
        rig.setAutomationZoom(detailThreshold - 1.0);
        rig.setPersistentPencil(true);
        const auto hiddenSource = rig.pointAt(rig.pan, 72, 40);
        rig.document().addLanePoint(rig.pan.track, rig.pan.controller,
                                    hiddenSource.mapped.point.tick,
                                    hiddenSource.mapped.point.value);
        rig.documentChanged();
        const auto hiddenGrab =
            rig.pointAt(rig.pan, hiddenSource.mapped.point.tick, hiddenSource.mapped.point.value);
        const auto hiddenEnd = rig.pointAt(rig.pan, hiddenGrab.mapped.cell.tickEnd + 96, 96);
        rig.mousePress(hiddenGrab.position);
        rig.mouseMove(hiddenEnd.position);
        rig.mouseRelease(hiddenEnd.position);
        rig.pump();
        DocLanePoint hiddenOriginal{};
        const auto hiddenResult = rig.snapshot(rig.pan.track, rig.pan.controller);
        const uint64_t hiddenSample =
            hiddenEnd.mapped.cell.tickBegin +
            (hiddenEnd.mapped.cell.tickEnd - hiddenEnd.mapped.cell.tickBegin) / 2;
        int hiddenValue = -1;
        const bool hiddenSourceRetained =
            rig.document().findLanePoint(rig.pan.track, rig.pan.controller,
                                         hiddenGrab.mapped.point.tick, &hiddenOriginal) &&
            hiddenOriginal.value == hiddenGrab.mapped.point.value;
        check(hiddenSourceRetained &&
                  heldValueAt(hiddenResult.lanePoints, hiddenSample, &hiddenValue) &&
                  hiddenValue == hiddenEnd.mapped.point.value,
              QStringLiteral("hidden Pencil node intercepted a stroke instead of remaining "
                             "non-interactive"));
    }

    if (nodesVisible) {
        resetPan();
        rig.setAutomationZoom(detailThreshold);
        rig.setPersistentPencil(true);
        const auto visibleSource = rig.pointAt(rig.pan, 72, 40);
        rig.document().addLanePoint(rig.pan.track, rig.pan.controller,
                                    visibleSource.mapped.point.tick,
                                    visibleSource.mapped.point.value);
        rig.documentChanged();
        const auto visibleGrab =
            rig.pointAt(rig.pan, visibleSource.mapped.point.tick, visibleSource.mapped.point.value);
        const auto visibleTarget = rig.pointAt(rig.pan, visibleGrab.mapped.cell.tickEnd + 96, 96);
        const QPointF visibleArm = visibleGrab.position + QPointF(armDistance, 0.0);
        const QPointF visibleEnd = visibleTarget.position + QPointF(armDistance, 0.0);
        rig.mousePress(visibleGrab.position);
        rig.mouseMove(visibleArm);
        rig.mouseMove(visibleEnd);
        rig.mouseRelease(visibleEnd);
        rig.pump();
        DocLanePoint visibleMoved{};
        DocLanePoint visibleOriginal{};
        const bool visibleTargetFound = rig.document().findLanePoint(
            rig.pan.track, rig.pan.controller, visibleTarget.mapped.point.tick, &visibleMoved);
        const bool visibleSourceGone = !rig.document().findLanePoint(
            rig.pan.track, rig.pan.controller, visibleGrab.mapped.point.tick, &visibleOriginal);
        check(visibleTarget.mapped.point.tick > visibleGrab.mapped.point.tick &&
                  visibleTargetFound && visibleMoved.value == visibleTarget.mapped.point.value &&
                  visibleSourceGone,
              QStringLiteral("visible Pencil node did not retain normal point-drag precedence"));

        const auto visibleDelete =
            rig.pointAt(rig.pan, visibleTarget.mapped.point.tick, visibleTarget.mapped.point.value);
        const auto beforeDelete = rig.snapshot(rig.pan.track, rig.pan.controller);
        rig.mousePress(visibleDelete.position);
        rig.mouseRelease(visibleDelete.position);
        rig.commitTimers();
        DocLanePoint visibleAfterDelete{};
        const bool visibleStillPresent =
            rig.document().findLanePoint(rig.pan.track, rig.pan.controller,
                                         visibleTarget.mapped.point.tick, &visibleAfterDelete);
        const auto afterDelete = rig.snapshot(rig.pan.track, rig.pan.controller);
        check(visibleTargetFound && !visibleStillPresent &&
                  afterDelete.lanePoints.size() + 1 == beforeDelete.lanePoints.size(),
              QStringLiteral("visible Pencil node click did not take delete precedence over "
                             "Pencil insertion"));
    }
}
