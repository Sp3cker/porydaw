#include "domains.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPointF>
#include <QString>

#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/songview/quick/timelinequickscene.h"

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

QPointF voicePoint(const AutomationGestureCheckRig &rig, uint64_t tick)
{
    const VoiceChangeArea &area = rig.voiceArea();
    return {rig.view().displayX(double(tick), area.plotOrigin(), area.devicePixelRatioF()),
            qreal(area.rect().center().y())};
}

uint64_t voiceSnapTick(const AutomationGestureCheckRig &rig, qreal x, bool fine)
{
    const VoiceChangeArea &area = rig.voiceArea();
    const double rawTick = std::max(
        0.0, rig.view().tickAtContentX(std::max<qreal>(area.plotOrigin(), x) - area.plotOrigin()));
    return rig.view().snapTick(rawTick, fine);
}

int markerCountAt(const songview::TimelineQuickLayerData &layer, qreal x)
{
    const qreal tolerance = layout::singlePixel();
    return int(std::count_if(layer.rects.cbegin(), layer.rects.cend(),
                             [x, tolerance](const songview::TimelineQuickRect &marker) {
                                 return std::abs(marker.rect.center().x() - x) <= tolerance;
                             }));
}

void seedVoice(AutomationGestureCheckRig &rig,
               const std::vector<SongDocument::LanePointValue> &points)
{
    rig.document().writeLanePoints(0, DOC_CC_VOICE, 0, std::numeric_limits<uint64_t>::max(),
                                   points);
    rig.documentChanged();
    rig.pump();
}

bool hasVoice(const AutomationGestureCheckRig &rig, uint64_t tick, int value)
{
    DocLanePoint point;
    return rig.document().findLanePoint(0, DOC_CC_VOICE, tick, &point) && point.value == value;
}

void activateVoiceDrag(AutomationGestureCheckRig &rig, const QPointF &source,
                       const QPointF &destination, Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
    rig.voiceMousePress(source);
    rig.voiceMouseMove(destination, modifiers);
    rig.pump();
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

    // Voice Change owns one phaseful horizontal drag from preview through commit.
    {
        seedVoice(rig, {{24, 5}, {48, 6}});
        const QPointF source = voicePoint(rig, 24);
        const QPointF target = voicePoint(rig, 72);
        const uint64_t destination = voiceSnapTick(rig, target.x(), false);
        const auto before = snapshot(rig.document());
        QString idleCaptureError;
        const QImage idleVoice = rig.renderVoiceChanges(&idleCaptureError);
        activateVoiceDrag(rig, source, target);
        QString previewCaptureError;
        const QImage previewVoice = rig.renderVoiceChanges(&previewCaptureError);
        check(idleCaptureError.isEmpty() && previewCaptureError.isEmpty() &&
                  isUnchanged(before, snapshot(rig.document())) && rig.view().userGestureActive() &&
                  rig.voiceArea().cursor().shape() == Qt::SizeHorCursor && !idleVoice.isNull() &&
                  idleVoice.size() == previewVoice.size() && idleVoice != previewVoice,
              QStringLiteral("Voice crossing preview capture failed (%1; %2)")
                  .arg(idleCaptureError, previewCaptureError));
        rig.voiceMouseRelease(target);
        rig.pump();
        const auto after = snapshot(rig.document());
        const auto points = rig.document().lanePoints(0, DOC_CC_VOICE);
        check(destination != 24 && isOneEdit(before, after) && !hasVoice(rig, 24, 5) &&
                  hasVoice(rig, 48, 6) && hasVoice(rig, destination, 5) && points.size() == 2 &&
                  rig.document().undoStack()->undoText() == QStringLiteral("change voice") &&
                  routeIdle(rig, panHandle) && rig.voiceArea().cursor().shape() == Qt::ArrowCursor,
              QStringLiteral("Voice crossing drag did not commit one change voice edit"));
        rig.document().undoStack()->undo();
        rig.documentChanged();
        rig.pump();
        check(rig.document().smf().write() == before.smf,
              QStringLiteral("Voice crossing drag undo was not byte-identical"));
    }
    {
        seedVoice(rig, {{48, 7}});
        const QPointF source = voicePoint(rig, 48);
        const auto before = snapshot(rig.document());
        rig.voiceMousePress(source);
        rig.voiceMouseRelease(source);
        rig.pump();
        check(isUnchanged(before, snapshot(rig.document())) && routeIdle(rig, panHandle),
              QStringLiteral("stationary Voice marker click committed a drag"));

        const int verticalSlop = QApplication::startDragDistance() + 2;
        rig.voiceMousePress(source);
        rig.voiceMouseMove(source + QPointF(0, verticalSlop));
        check(!rig.view().userGestureActive() &&
                  rig.voiceArea().cursor().shape() == Qt::ArrowCursor,
              QStringLiteral("vertical Voice jitter activated a horizontal gesture"));
        rig.voiceMouseRelease(source + QPointF(0, verticalSlop));
        rig.pump();
        check(isUnchanged(before, snapshot(rig.document())) && routeIdle(rig, panHandle),
              QStringLiteral("vertical-only Voice movement committed a retime"));

        const QPointF empty = voicePoint(rig, 144);
        rig.voiceMousePress(empty);
        rig.voiceMouseMove(empty + QPointF(QApplication::startDragDistance() + 2, 0));
        rig.voiceMouseRelease(empty + QPointF(QApplication::startDragDistance() + 2, 0));
        rig.pump();
        check(isUnchanged(before, snapshot(rig.document())) && routeIdle(rig, panHandle),
              QStringLiteral("empty Voice space armed or committed a drag"));
    }
    {
        seedVoice(rig, {{48, 8}});
        const QPointF source = voicePoint(rig, 48);
        QPointF target;
        uint64_t fineTick = 0;
        uint64_t normalTick = 0;
        const int slop = QApplication::startDragDistance();
        for (int x = rig.voiceArea().plotOrigin(); x < rig.voiceArea().width(); ++x) {
            const uint64_t fine = voiceSnapTick(rig, x, true);
            const uint64_t normal = voiceSnapTick(rig, x, false);
            if (fine != normal && fine != 48 && std::abs(qreal(x) - source.x()) >= slop) {
                target = QPointF(x, rig.voiceArea().rect().center().y());
                fineTick = fine;
                normalTick = normal;
                break;
            }
        }
        check(fineTick != normalTick,
              QStringLiteral("Voice fixture exposed no visible normal/fine snap difference"));
        if (fineTick != normalTick) {
            const auto before = snapshot(rig.document());
            activateVoiceDrag(rig, source, target, Qt::AltModifier);
            rig.voiceMouseRelease(target, Qt::AltModifier);
            rig.pump();
            check(isOneEdit(before, snapshot(rig.document())) && hasVoice(rig, fineTick, 8) &&
                      !hasVoice(rig, normalTick, 8) && routeIdle(rig, panHandle),
                  QStringLiteral("Alt Voice drag did not use fine projection snapping"));
        }
    }
    {
        seedVoice(rig, {{48, 9}, {192, 10}});
        const QPointF source = voicePoint(rig, 48);
        const QPointF target = voicePoint(rig, 192);
        const uint64_t destination = voiceSnapTick(rig, target.x(), false);
        const auto before = snapshot(rig.document());
        activateVoiceDrag(rig, source, target);
        rig.voiceMouseRelease(target);
        rig.pump();
        const auto points = rig.document().lanePoints(0, DOC_CC_VOICE);
        check(isOneEdit(before, snapshot(rig.document())) && points.size() == 1 &&
                  hasVoice(rig, destination, 9) && routeIdle(rig, panHandle),
              QStringLiteral("Voice destination collision did not keep the dragged marker"));
    }
    {
        rig.document().writeLanePoints(rig.pan.track, rig.pan.controller, 0,
                                       std::numeric_limits<uint64_t>::max(), {});
        seedVoice(rig, {{48, 11}});
        const QPointF source = voicePoint(rig, 48);
        const QPointF target = voicePoint(rig, 192);
        const auto before = snapshot(rig.document());
        activateVoiceDrag(rig, source, target);
        rig.document().addLanePoint(rig.pan.track, rig.pan.controller, 333, 42);
        const auto external = snapshot(rig.document());
        rig.voiceMouseRelease(target);
        rig.pump();
        check(isOneEdit(before, external) && isUnchanged(external, snapshot(rig.document())) &&
                  hasVoice(rig, 48, 11) && routeIdle(rig, panHandle),
              QStringLiteral("Voice release did not reject a stale document revision"));
    }
    {
        seedVoice(rig, {{48, 12}});
        const QPointF source = voicePoint(rig, 48);
        const QPointF target = voicePoint(rig, 192);
        const auto beforeEscape = snapshot(rig.document());
        activateVoiceDrag(rig, source, target);
        rig.keyToVoiceArea(QEvent::KeyPress, Qt::Key_Escape);
        rig.pump();
        check(isUnchanged(beforeEscape, snapshot(rig.document())) && routeIdle(rig, panHandle) &&
                  !rig.view().userGestureActive() &&
                  rig.voiceArea().cursor().shape() == Qt::ArrowCursor,
              QStringLiteral("Escape did not fully cancel the Voice gesture"));

        const auto beforeUngrab = snapshot(rig.document());
        activateVoiceDrag(rig, source, target);
        QEvent ungrab(QEvent::UngrabMouse);
        QCoreApplication::sendEvent(&rig.voiceArea(), &ungrab);
        rig.pump();
        check(isUnchanged(beforeUngrab, snapshot(rig.document())) && routeIdle(rig, panHandle) &&
                  !rig.view().userGestureActive() &&
                  rig.voiceArea().cursor().shape() == Qt::ArrowCursor,
              QStringLiteral("UngrabMouse did not fully cancel the Voice gesture"));
    }
    {
        seedVoice(rig, {});
        SmfEvent program;
        program.tick = 48;
        program.status = uint8_t(0xC0 | (rig.document().channelFor(0) & 0x0F));
        program.data0 = 13;
        rig.document().insertRawEvent(rig.document().smfTrackFor(0), program);
        rig.document().insertRawEvent(rig.document().smfTrackFor(0), program);
        rig.documentChanged();
        rig.pump();
        const auto modelCount =
            std::count_if(rig.view().model().voices.cbegin(), rig.view().model().voices.cend(),
                          [](const VoiceChange &change) {
                              return change.track == 0 && change.tick == 48 && change.program == 13;
                          });
        check(modelCount == 2,
              QStringLiteral("duplicate Voice fixture projected %1 model entries").arg(modelCount));
        const auto before = snapshot(rig.document());
        const QPointF source = voicePoint(rig, 48);
        const QPointF target = voicePoint(rig, 72);
        const uint64_t destination = voiceSnapTick(rig, target.x(), false);
        QString idleCaptureError;
        const QImage idleFramebuffer = rig.renderVoiceChanges(&idleCaptureError);
        const auto idleMarkers =
            rig.quickScene().layer(songview::TimelineQuickLayer::VoiceChangesMarkers);
        activateVoiceDrag(rig, source, target);
        QString previewCaptureError;
        const QImage previewFramebuffer = rig.renderVoiceChanges(&previewCaptureError);
        const auto previewMarkers =
            rig.quickScene().layer(songview::TimelineQuickLayer::VoiceChangesMarkers);
        const qreal destinationX = rig.view().displayX(
            double(destination), rig.voiceArea().plotOrigin(), rig.voiceArea().devicePixelRatioF());
        const int idleSourceCount = markerCountAt(idleMarkers, source.x());
        const int previewSourceCount = markerCountAt(previewMarkers, source.x());
        const int idleDestinationCount = markerCountAt(idleMarkers, destinationX);
        const int previewDestinationCount = markerCountAt(previewMarkers, destinationX);
        check(idleCaptureError.isEmpty() && previewCaptureError.isEmpty() &&
                  !idleFramebuffer.isNull() && !previewFramebuffer.isNull() &&
                  idleFramebuffer.size() == previewFramebuffer.size() &&
                  isUnchanged(before, snapshot(rig.document())) && rig.view().userGestureActive() &&
                  previewMarkers.revision > idleMarkers.revision,
              QStringLiteral("duplicate Voice occurrence did not publish a Quick preview"));
        check(idleSourceCount == 2 && previewSourceCount == 1,
              QStringLiteral("duplicate Voice occurrence preview did not retain one source "
                             "marker"));
        check(idleDestinationCount == 0 && previewDestinationCount == 1 &&
                  idleMarkers.rects.size() == previewMarkers.rects.size(),
              QStringLiteral("duplicate Voice occurrence preview did not add one destination "
                             "marker"));
        rig.voiceMouseRelease(target);
        rig.pump();
        const auto points = rig.document().lanePoints(0, DOC_CC_VOICE);
        const auto sourceCount =
            std::count_if(points.cbegin(), points.cend(), [](const DocLanePoint &point) {
                return point.tick == 48 && point.value == 13;
            });
        const auto destinationCount =
            std::count_if(points.cbegin(), points.cend(), [destination](const DocLanePoint &point) {
                return point.tick == destination && point.value == 13;
            });
        check(isOneEdit(before, snapshot(rig.document())) && sourceCount == 1 &&
                  destinationCount == 1 && points.size() == 2 && routeIdle(rig, panHandle),
              QStringLiteral("duplicate raw Voice identity did not move exactly one occurrence"));
        rig.document().undoStack()->undo();
        rig.documentChanged();
        rig.pump();
        check(rig.document().smf().write() == before.smf,
              QStringLiteral("duplicate raw Voice drag undo was not byte-identical"));
    }

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
        const VoiceChangeArea &voice = rig.voiceArea();
        const QPointF input(voice.plotOrigin() + rig.geometry().pointHitRadius,
                            voice.rect().center().y());
        const auto before = snapshot(rig.document());
        const auto beforeHeights = laneHeights(rig);
        const QRect tempoBefore = rig.canvas().laneBody(AutomationGestureCheckRig::kTempoHandle);
        const uint64_t cursorBefore = rig.view().editCursorTick();
        const bool accepted = rig.dispatchVoiceMousePress(input);
        check(accepted && routeIdle(rig, panHandle) &&
                  isUnchanged(before, snapshot(rig.document())) &&
                  beforeHeights == laneHeights(rig) &&
                  rig.canvas().laneBody(AutomationGestureCheckRig::kTempoHandle) == tempoBefore &&
                  rig.view().editCursorTick() == cursorBefore,
              QStringLiteral("Voice Change press did not stop at its accepted route"));
        rig.voiceMouseRelease(input);
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
