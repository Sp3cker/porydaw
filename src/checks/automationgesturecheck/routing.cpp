#include "domains.h"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <vector>

#include <QPointF>
#include <QString>

#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/songview.h"

namespace {

std::vector<int> laneHeights(const AutomationGestureCheckRig &rig)
{
    std::vector<int> heights;
    const auto &rows = rig.canvas().rows();
    heights.reserve(rows.size());
    for (auto index = std::size_t{0}; index < rows.size(); ++index)
        heights.push_back(rig.bodyFor(LaneHandle{int(index) + 1}).height());
    return heights;
}

bool onlyHeightChanged(const std::vector<int> &before, const std::vector<int> &after,
                       int changedIndex)
{
    if (before.size() != after.size() || changedIndex < 0 || changedIndex >= int(before.size()) ||
        before[std::size_t(changedIndex)] == after[std::size_t(changedIndex)])
        return false;
    for (auto index = std::size_t{0}; index < before.size(); ++index) {
        if (int(index) != changedIndex && before[index] != after[index])
            return false;
    }
    return true;
}

bool sameLanePoints(const std::vector<DocLanePoint> &left, const std::vector<DocLanePoint> &right)
{
    if (left.size() != right.size())
        return false;
    for (auto index = std::size_t{0}; index < left.size(); ++index) {
        if (left[index].smfTrack != right[index].smfTrack ||
            left[index].index != right[index].index || left[index].tick != right[index].tick ||
            left[index].value != right[index].value)
            return false;
    }
    return true;
}

bool routeIdle(const AutomationGestureCheckRig &rig, LaneHandle lane)
{
    return rig.isIdle() && !rig.canvas().isPanning() && !rig.canvas().bandPreviewContainsLane(lane);
}

} // namespace

void checkAutomationRouting(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check)
{
    rig.resetView();
    rig.setPersistentPencil(false);
    rig.canvas().cancelInteraction();
    rig.pump();
    const LaneHandle panHandle = rig.handleFor(rig.pan);
    const int panRow = rig.rowIndex(rig.pan);
    check(panHandle.valid() && panRow >= 0,
          QStringLiteral("routing fixture did not expose the pan lane"));
    if (!panHandle.valid() || panRow < 0)
        return;

    // Accepted routes: middle pan, Voice Change, and the Tempo header.
    {
        const auto input = rig.pointAt(rig.pan, 48, 64);
        const auto before = snapshot(rig.document());
        const auto beforeHeights = laneHeights(rig);
        const uint64_t cursorBefore = rig.view().editCursorTick();
        const bool accepted =
            rig.dispatchMousePress(input.position, Qt::NoModifier, Qt::MiddleButton);
        check(accepted && rig.canvas().isPanning() && rig.view().userGestureActive() &&
                  !rig.canvas().bandPreviewContainsLane(panHandle) &&
                  isUnchanged(before, snapshot(rig.document())) &&
                  beforeHeights == laneHeights(rig) && rig.view().editCursorTick() == cursorBefore,
              QStringLiteral("middle-button press did not exclusively enter accepted pan state"));
        rig.mouseRelease(input.position, Qt::NoModifier, Qt::MiddleButton);
        rig.pump();
        check(routeIdle(rig, panHandle),
              QStringLiteral("middle-button pan did not end cleanly on release"));
    }
    {
        const QRect voice = rig.voiceBounds();
        const QPointF input(rig.geometry().plotOrigin + rig.geometry().pointHitRadius,
                            voice.center().y());
        const auto before = snapshot(rig.document());
        const auto beforeHeights = laneHeights(rig);
        const QRect tempoBefore = rig.canvas().laneBody(AutomationGestureCheckRig::kTempoHandle);
        const uint64_t cursorBefore = rig.view().editCursorTick();
        const bool accepted = rig.dispatchMousePress(input);
        check(accepted && routeIdle(rig, panHandle) &&
                  isUnchanged(before, snapshot(rig.document())) &&
                  beforeHeights == laneHeights(rig) &&
                  rig.canvas().laneBody(AutomationGestureCheckRig::kTempoHandle) == tempoBefore &&
                  rig.view().editCursorTick() == cursorBefore,
              QStringLiteral("Voice Change press did not stop at its accepted route"));
        rig.mouseRelease(input);
    }
    {
        const QPointF input = rig.tempoHeaderPoint();
        const bool expandedBefore =
            !rig.canvas().laneBody(AutomationGestureCheckRig::kTempoHandle).isEmpty();
        const auto before = snapshot(rig.document());
        const auto beforeHeights = laneHeights(rig);
        const uint64_t cursorBefore = rig.view().editCursorTick();
        const bool accepted = rig.dispatchMousePress(input);
        const bool expandedAfter =
            !rig.canvas().laneBody(AutomationGestureCheckRig::kTempoHandle).isEmpty();
        check(accepted && expandedAfter != expandedBefore && routeIdle(rig, panHandle) &&
                  isUnchanged(before, snapshot(rig.document())) &&
                  beforeHeights == laneHeights(rig) && rig.view().editCursorTick() == cursorBefore,
              QStringLiteral("Tempo header press did not exclusively toggle its accepted route"));
        rig.mouseRelease(input);
    }

    // Bare-return routes: row resize, body-right band, Pencil, and default body.
    {
        const QRect body = rig.bodyFor(panHandle);
        const auto beforeHeights = laneHeights(rig);
        const auto before = snapshot(rig.document());
        const uint64_t cursorBefore = rig.view().editCursorTick();
        const QPointF input(rig.geometry().plotOrigin + rig.geometry().pointHitRadius,
                            body.top() + body.height());
        const int grow = rig.geometry().rowMaximumHeight - body.height();
        const int shrink = body.height() - rig.geometry().rowMinimumHeight;
        const int distance = std::max(1, rig.geometry().rowWheelIncrement);
        const int delta = grow > 0 ? std::min(grow, distance) : -std::min(shrink, distance);
        const bool accepted = rig.dispatchMousePress(input);
        check(!accepted && !rig.canvas().isPanning() && rig.view().userGestureActive() &&
                  !rig.canvas().bandPreviewContainsLane(panHandle) &&
                  isUnchanged(before, snapshot(rig.document())) &&
                  beforeHeights == laneHeights(rig) && rig.view().editCursorTick() == cursorBefore,
              QStringLiteral("row-boundary press did not stop in unaccepted resize state"));
        const QPointF moved = input + QPointF(0, delta);
        rig.mouseMove(moved);
        const auto afterHeights = laneHeights(rig);
        check(delta != 0 && onlyHeightChanged(beforeHeights, afterHeights, panRow) &&
                  afterHeights[std::size_t(panRow)] == beforeHeights[std::size_t(panRow)] + delta &&
                  isUnchanged(before, snapshot(rig.document())) &&
                  rig.view().editCursorTick() == cursorBefore,
              QStringLiteral("resize route changed state outside its target row"));
        rig.mouseRelease(moved);
        rig.pump();
        check(routeIdle(rig, panHandle),
              QStringLiteral("row resize did not end cleanly on release"));
    }
    {
        const auto input = rig.pointAt(rig.pan, 144, 48);
        const auto before = snapshot(rig.document());
        const auto beforeHeights = laneHeights(rig);
        const uint64_t cursorBefore = rig.view().editCursorTick();
        const bool accepted =
            rig.dispatchMousePress(input.position, Qt::NoModifier, Qt::RightButton);
        check(!accepted && !rig.canvas().isPanning() && rig.view().userGestureActive() &&
                  !rig.canvas().bandPreviewContainsLane(panHandle) &&
                  isUnchanged(before, snapshot(rig.document())) &&
                  beforeHeights == laneHeights(rig) && rig.view().editCursorTick() == cursorBefore,
              QStringLiteral("body-right press did not stop in unaccepted band state"));
        rig.mouseMove(input.position + QPointF(20, 0), Qt::RightButton);
        check(rig.canvas().bandPreviewContainsLane(panHandle) &&
                  isUnchanged(before, snapshot(rig.document())) &&
                  beforeHeights == laneHeights(rig) && rig.view().editCursorTick() == cursorBefore,
              QStringLiteral("body-right route did not activate only its band preview"));
        rig.canvas().cancelInteraction();
        rig.pump();
        check(routeIdle(rig, panHandle), QStringLiteral("body-right band did not cancel cleanly"));
    }
    {
        rig.document().writeLanePoints(rig.pan.track, rig.pan.controller, 0,
                                       std::numeric_limits<uint64_t>::max(), {});
        rig.documentChanged();
        rig.setPersistentPencil(true);
        rig.pump();
        const auto input = rig.pointAt(rig.pan, 192, 83);
        const auto before = snapshot(rig.document());
        const auto beforeHeights = laneHeights(rig);
        const auto lfoBefore = rig.document().lanePoints(rig.lfo.track, rig.lfo.controller);
        const auto volumeBefore =
            rig.document().lanePoints(rig.volume.track, rig.volume.controller);
        const auto voiceBefore = rig.document().lanePoints(rig.pan.track, DOC_CC_VOICE);
        const auto tempoBefore = rig.document().tempoPoints();
        const uint64_t cursorBefore = rig.view().editCursorTick();
        const bool accepted = rig.dispatchMousePress(input.position);
        check(!accepted && !rig.canvas().isPanning() && rig.view().userGestureActive() &&
                  !rig.canvas().bandPreviewContainsLane(panHandle) &&
                  isUnchanged(before, snapshot(rig.document())) &&
                  beforeHeights == laneHeights(rig) && rig.view().editCursorTick() == cursorBefore,
              QStringLiteral("Pencil press did not stop in its unaccepted gesture state"));
        rig.mouseRelease(input.position);
        rig.commitTimers();
        const auto after = snapshot(rig.document());
        DocLanePoint inserted;
        const bool insertedExpected =
            rig.document().findLanePoint(rig.pan.track, rig.pan.controller, input.mapped.point.tick,
                                         &inserted) &&
            inserted.value == input.mapped.point.value;
        check(insertedExpected && before.smf != after.smf && isOneEdit(before, after) &&
                  sameLanePoints(lfoBefore,
                                 rig.document().lanePoints(rig.lfo.track, rig.lfo.controller)) &&
                  sameLanePoints(volumeBefore, rig.document().lanePoints(rig.volume.track,
                                                                         rig.volume.controller)) &&
                  sameLanePoints(voiceBefore,
                                 rig.document().lanePoints(rig.pan.track, DOC_CC_VOICE)) &&
                  tempoBefore == rig.document().tempoPoints() &&
                  beforeHeights == laneHeights(rig) &&
                  rig.view().editCursorTick() == cursorBefore && routeIdle(rig, panHandle),
              QStringLiteral("Pencil route fell through or changed state outside its lane edit"));
    }
    {
        rig.document().writeLanePoints(rig.pan.track, rig.pan.controller, 0,
                                       std::numeric_limits<uint64_t>::max(), {});
        rig.documentChanged();
        rig.setPersistentPencil(false);
        rig.pump();
        const auto input = rig.pointAt(rig.pan, 384, 41);
        const auto before = snapshot(rig.document());
        const auto beforeHeights = laneHeights(rig);
        const uint64_t cursorBefore = rig.view().editCursorTick();
        const uint64_t expectedCursor =
            rig.view().snapTick(rig.projection().rawTickAt(input.position.x()), false);
        const bool accepted = rig.dispatchMousePress(input.position);
        check(!accepted && !rig.canvas().isPanning() && rig.view().userGestureActive() &&
                  !rig.canvas().bandPreviewContainsLane(panHandle) &&
                  isUnchanged(before, snapshot(rig.document())) &&
                  beforeHeights == laneHeights(rig) && rig.view().editCursorTick() == cursorBefore,
              QStringLiteral("default body press did not stop in its unaccepted gesture state"));
        rig.mouseRelease(input.position);
        rig.pump();
        check(expectedCursor != cursorBefore && rig.view().editCursorTick() == expectedCursor &&
                  isUnchanged(before, snapshot(rig.document())) &&
                  beforeHeights == laneHeights(rig) && routeIdle(rig, panHandle),
              QStringLiteral("default body route fell through or changed state beyond the cursor"));
    }
}
