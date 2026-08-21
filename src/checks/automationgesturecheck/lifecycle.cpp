#include "domains.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include <QApplication>
#include <QCoreApplication>
#include <QDialog>
#include <QEvent>
#include <QImage>
#include <QListWidget>
#include <QRect>
#include <QResizeEvent>
#include <QSize>
#include <QTimer>

#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/songview.h"

void checkAutomationLifecycle(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check)
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
    const auto idleInteraction = [&rig] {
        return !rig.canvas().isPanning() && !rig.view().userGestureActive() &&
               !rig.view().selectionModel().timeSelection().active();
    };
    const auto cropVoice = [&rig] { return rig.canvas().grab(rig.voiceBounds()).toImage(); };
    const auto labelSample = [](const QImage &image, qreal lineX, qreal origin, qreal dpr) {
        const int line = qRound((lineX - origin) * dpr);
        const int gap = std::max(2, qRound(6.0 * dpr));
        const int left = std::clamp(line + gap, 0, image.width());
        const int width = std::max(0, std::min(qRound(140.0 * dpr), image.width() - left));
        return image.copy(QRect(left, 0, width, image.height()));
    };

    rig.setAutomationZoom(96.0);
    rig.setAutomationScroll(0.0);
    rig.setPersistentPencil(false);
    rig.pump();

    const auto geometry = rig.geometry();
    const qreal dpr = rig.canvas().devicePixelRatioF();
    const QRect voice = rig.voiceBounds();
    check(!voice.isEmpty(),
          QStringLiteral("Voice Change strip is missing from the lifecycle fixture"));
    if (!voice.isEmpty()) {
        QEvent leave(QEvent::Leave);
        QCoreApplication::sendEvent(&rig.canvas(), &leave);
        rig.pump();
        const QImage idleVoice = cropVoice();
        const QPointF onMarker(rig.view().displayX(24, geometry.plotOrigin, dpr),
                               voice.center().y());
        const QPointF offMarker(rig.view().displayX(96, geometry.plotOrigin, dpr),
                                voice.center().y());
        const qreal markerSeparation = std::abs(offMarker.x() - onMarker.x());
        check(
            markerSeparation > qreal(geometry.deleteTimeRadius * 2),
            QStringLiteral("Voice hover fixture did not separate on-marker and off-marker probes"));
        rig.mouseMove(offMarker, Qt::NoButton);
        rig.pump();
        const QImage offMarkerVoice = cropVoice();
        const uint64_t offTick =
            rig.view().snapTick(rig.projection().rawTickAt(offMarker.x()), true);
        const qreal offLineX = rig.view().displayX(double(offTick), geometry.plotOrigin, dpr);
        const QImage idleOffLabel = labelSample(idleVoice, offLineX, voice.x(), dpr);
        const QImage hoverOffLabel = labelSample(offMarkerVoice, offLineX, voice.x(), dpr);
        check(!idleOffLabel.isNull() && idleOffLabel.size() == hoverOffLabel.size() &&
                  !idleOffLabel.size().isEmpty() && idleOffLabel != hoverOffLabel,
              QStringLiteral("Voice held-voice hover label was not rendered off-marker"));
        rig.mouseMove(onMarker, Qt::NoButton);
        rig.pump();
        const QImage onMarkerVoice = cropVoice();
        const qreal onLineX = rig.view().displayX(24, geometry.plotOrigin, dpr);
        const QImage idleOnLabel = labelSample(idleVoice, onLineX, voice.x(), dpr);
        const QImage hoverOnLabel = labelSample(onMarkerVoice, onLineX, voice.x(), dpr);
        check(!idleOnLabel.isNull() && idleOnLabel.size() == hoverOnLabel.size() &&
                  idleOnLabel == hoverOnLabel,
              QStringLiteral("Voice held-voice hover label was not suppressed on-marker"));
        QEvent clearHover(QEvent::Leave);
        QCoreApplication::sendEvent(&rig.canvas(), &clearHover);
        rig.pump();
    }

    const int panRow = rig.rowIndex(rig.pan);
    check(panRow >= 0, QStringLiteral("lifecycle fixture did not expose the pan CC lane"));
    if (panRow >= 0) {
        const auto source = rig.pointAt(rig.pan, 72, 64);
        rig.document().writeLanePoints(rig.pan.track, rig.pan.controller, 0,
                                       std::numeric_limits<uint64_t>::max(),
                                       {{source.mapped.point.tick, source.mapped.point.value}});
        rig.documentChanged();
        const auto grab = rig.pointAt(rig.pan, source.mapped.point.tick, source.mapped.point.value);
        const qreal armDistance = qreal(rig.geometry().nodeDragActivationDistance + 2);
        const QPointF arm = grab.position + QPointF(armDistance, 0.0);
        const auto beforeDrag = rig.snapshot(rig.pan.track, rig.pan.controller);
        rig.mousePress(grab.position);
        rig.mouseMove(arm);
        rig.pump();
        check(rig.view().userGestureActive(),
              QStringLiteral("CC node drag did not activate before the stack rebuild"));
        const QSize canvasSize = rig.canvas().size();
        QResizeEvent resizeEvent(QSize(canvasSize.width() + 48, canvasSize.height()), canvasSize);
        QCoreApplication::sendEvent(&rig.canvas(), &resizeEvent);
        rig.pump();
        rig.mouseRelease(arm);
        rig.pump();
        const auto afterRebuildRelease = rig.snapshot(rig.pan.track, rig.pan.controller);
        check(sameSnapshot(beforeDrag, afterRebuildRelease) && idleInteraction() &&
                  !rig.canvas().bandPreviewContainsRow(panRow),
              QStringLiteral(
                  "release after a geometry stack rebuild committed a stale CC node drag"));
        const auto followGrab =
            rig.pointAt(rig.pan, source.mapped.point.tick, source.mapped.point.value);
        const auto followTarget = rig.pointAt(rig.pan, followGrab.mapped.cell.tickEnd + 96, 96);
        const QPointF followArm = followGrab.position + QPointF(armDistance, 0.0);
        const QPointF followEnd = followTarget.position + QPointF(armDistance, 0.0);
        const auto beforeFollow = rig.snapshot(rig.pan.track, rig.pan.controller);
        rig.mousePress(followGrab.position);
        rig.mouseMove(followArm);
        rig.mouseMove(followEnd);
        rig.mouseRelease(followEnd);
        rig.pump();
        const auto afterFollow = rig.snapshot(rig.pan.track, rig.pan.controller);
        check(oneLaneEdit(beforeFollow, afterFollow) && !rig.canvas().isPanning() &&
                  !rig.view().userGestureActive(),
              QStringLiteral(
                  "automation input did not recover after a geometry stack rebuild cancel"));
    }

    auto capturedTrack = -1;
    for (int track = 0; track < rig.document().engineTrackCount(); ++track) {
        if (track != 0 && rig.document().smfTrackFor(track) >= 0) {
            capturedTrack = track;
            break;
        }
    }
    if (capturedTrack < 0) {
        capturedTrack = rig.document().addTrack(0);
        check(capturedTrack >= 0,
              QStringLiteral("lifecycle fixture could not add a second engine track"));
        if (capturedTrack >= 0)
            rig.documentChanged();
    }
    if (capturedTrack >= 0 && capturedTrack < rig.document().engineTrackCount() &&
        rig.document().smfTrackFor(capturedTrack) >= 0) {
        rig.setAutomationZoom(96.0);
        rig.setAutomationScroll(0.0);
        const auto voiceBeforePrimary = rig.document().lanePoints(0, DOC_CC_VOICE);
        const auto voiceBeforeCaptured = rig.document().lanePoints(capturedTrack, DOC_CC_VOICE);
        const auto beforePicker = rig.snapshot(capturedTrack, DOC_CC_VOICE);
        rig.view().selectTrack(capturedTrack);
        rig.canvas().rebuildRows();
        rig.pump();
        const QRect capturedVoice = rig.voiceBounds();
        check(!capturedVoice.isEmpty(),
              QStringLiteral("Voice Change strip is missing after capturing the rebuilt track"));
        const qreal origin = rig.geometry().plotOrigin;
        const qreal dpr = rig.canvas().devicePixelRatioF();
        const qreal maxX = qreal(std::max(0, rig.canvas().width() - 1));
        QPointF pickerPos;
        auto foundPickerTick = false;
        for (int candidate = 48; candidate <= 144; candidate += 24) {
            const QPointF pos(rig.view().displayX(candidate, origin, dpr),
                              capturedVoice.center().y());
            if (pos.x() < origin || pos.x() >= maxX)
                continue;
            DocLanePoint existing{};
            if (rig.document().findLanePoint(capturedTrack, DOC_CC_VOICE, uint64_t(candidate),
                                             &existing) &&
                existing.value == 4)
                continue;
            pickerPos = pos;
            foundPickerTick = true;
            break;
        }
        check(foundPickerTick,
              QStringLiteral("lifecycle fixture had no on-screen Voice picker tick"));
        if (foundPickerTick && !capturedVoice.isEmpty()) {
            QTimer::singleShot(0, [] {
                if (auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget())) {
                    if (auto *list = dialog->findChild<QListWidget *>())
                        list->setCurrentRow(4);
                    dialog->accept();
                }
            });
            rig.mouseDoubleClick(pickerPos);
            rig.mouseRelease(pickerPos);
            rig.pump();
            const auto afterPicker = rig.snapshot(capturedTrack, DOC_CC_VOICE);
            DocLanePoint inserted{};
            const uint64_t insertTick =
                rig.view().snapTick(rig.projection().rawTickAt(pickerPos.x()), false);
            const bool insertedOnCaptured =
                rig.document().findLanePoint(capturedTrack, DOC_CC_VOICE, insertTick, &inserted) &&
                inserted.value == 4;
            check(sameLanePoints(voiceBeforePrimary, rig.document().lanePoints(0, DOC_CC_VOICE)) &&
                      insertedOnCaptured && oneLaneEdit(beforePicker, afterPicker) &&
                      !sameLanePoints(voiceBeforeCaptured, afterPicker.lanePoints),
                  QStringLiteral("Voice picker did not commit DOC_CC_VOICE to the rebuilt captured "
                                 "track in one undo step"));
        }
    }
}
