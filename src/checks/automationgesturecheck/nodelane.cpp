#include "domains.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

#include <QByteArray>
#include <QImage>
#include <QRect>

#include "core/timedefaults.h"

#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"

void checkTempoInteractions(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check)
{
    const auto tempoPoint = [](uint64_t tick, int bpm) {
        return TempoPoint{tick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm)};
    };
    struct TempoSnapshot {
        QByteArray smf;
        uint64_t revision = 0;
        int undoIndex = 0;
        std::vector<TempoPoint> points;
    };
    const auto tempoSnapshot = [&rig] {
        return TempoSnapshot{rig.document().smf().write(), rig.document().revision(),
                             rig.document().undoStack()->index(), rig.document().tempoPoints()};
    };
    const auto sameTempoSnapshot = [](const TempoSnapshot &left, const TempoSnapshot &right) {
        return left.smf == right.smf && left.revision == right.revision &&
               left.undoIndex == right.undoIndex && left.points == right.points;
    };
    const auto oneTempoEdit = [](const TempoSnapshot &before, const TempoSnapshot &after) {
        return after.revision == before.revision + 1 && after.undoIndex == before.undoIndex + 1 &&
               after.points != before.points;
    };
    const std::vector<TempoPoint> initialTempo = rig.document().tempoPoints();
    const auto setTempo = [&rig](const std::vector<TempoPoint> &points) {
        if (rig.document().tempoPoints() == points)
            return;
        TempoEdit edit;
        edit.remove = rig.document().tempoPoints();
        edit.add = points;
        rig.document().applyTempoEdit(edit);
        rig.documentChanged();
    };
    const auto restoreTempo = [&rig, &setTempo, &initialTempo] {
        rig.view().selectionModel().clearTimeSelection();
        setTempo(initialTempo);
        rig.pump();
    };
    const auto seedTempo = [&restoreTempo, &setTempo](const std::vector<TempoPoint> &points) {
        restoreTempo();
        setTempo(points);
    };
    const std::vector<TempoPoint> tempoFixture{tempoPoint(0, 120), tempoPoint(96, 150),
                                               tempoPoint(288, 110)};

    rig.mousePress(rig.tempoHeaderPoint());
    rig.mouseRelease(rig.tempoHeaderPoint());
    rig.pump();
    const bool tempoExpanded = rig.canvas().contentTopInset() > rig.geometry().addLaneStripHeight;
    check(tempoExpanded, QStringLiteral("Tempo header did not expose the expanded body"));
    if (tempoExpanded) {
        seedTempo(tempoFixture);
        const auto deletionPoint = rig.tempoBodyPoint(96, 150);
        const auto deletionBefore = tempoSnapshot();
        rig.mousePress(deletionPoint);
        rig.mouseRelease(deletionPoint);
        const auto deletionAfter = tempoSnapshot();
        const std::vector<TempoPoint> withoutDeleted{tempoFixture.front(), tempoFixture.back()};
        check(deletionAfter.points == withoutDeleted && oneTempoEdit(deletionBefore, deletionAfter),
              QStringLiteral("stationary Tempo-node click did not delete exactly one point in one "
                             "edit"));
        rig.mouseDoubleClick(deletionPoint);
        rig.pump();
        check(sameTempoSnapshot(deletionAfter, tempoSnapshot()),
              QStringLiteral("Tempo-node deletion did not consume the immediate double-click"));
        restoreTempo();

        seedTempo(tempoFixture);
        const auto shiftedPoint = rig.tempoBodyPoint(96, 150);
        const auto shiftedBefore = tempoSnapshot();
        rig.mousePress(shiftedPoint, Qt::ShiftModifier);
        rig.mouseRelease(shiftedPoint, Qt::ShiftModifier);
        check(sameTempoSnapshot(shiftedBefore, tempoSnapshot()),
              QStringLiteral("Shift+stationary Tempo-node click changed document state"));
        restoreTempo();

        seedTempo(tempoFixture);
        const auto dragStart = rig.tempoBodyPoint(96, 150);
        const auto activationPoint = rig.tempoBodyPoint(120, 150);
        const auto movedPoint = rig.tempoBodyPoint(192, 150);
        const auto dragEnd = activationPoint + movedPoint - dragStart;
        const auto dragBefore = tempoSnapshot();
        rig.mousePress(dragStart);
        rig.mouseMove(activationPoint);
        rig.mouseMove(dragEnd);
        rig.mouseRelease(dragEnd);
        const std::vector<TempoPoint> movedTempo{tempoFixture.front(), tempoPoint(192, 150),
                                                 tempoFixture.back()};
        const auto dragAfter = tempoSnapshot();
        check(dragAfter.points == movedTempo && oneTempoEdit(dragBefore, dragAfter),
              QStringLiteral("dragging a Tempo node beyond activation slop did not move it"));
        restoreTempo();

        const auto selectTempoRange = [&rig](uint64_t first, uint64_t last) {
            songview::EditorSelectionModel::TimeSelection selection;
            selection.startTick = first;
            selection.endTick = last;
            selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
            selection.tempo = true;
            rig.view().selectionModel().setTimeSelection(std::move(selection));
            rig.pump();
        };
        const std::vector<TempoPoint> multiFixture{tempoPoint(0, 120), tempoPoint(96, 150),
                                                   tempoPoint(192, 110), tempoPoint(384, 130)};
        seedTempo(multiFixture);
        selectTempoRange(96, 288);
        const auto selectedDragStart = rig.tempoBodyPoint(96, 150);
        const auto selectedActivation = rig.tempoBodyPoint(120, 150);
        const auto selectedTarget = rig.tempoBodyPoint(144, 150);
        const auto selectedDragEnd = selectedActivation + selectedTarget - selectedDragStart;
        const auto selectedDragBefore = tempoSnapshot();
        rig.mousePress(selectedDragStart);
        rig.mouseMove(selectedActivation);
        rig.mouseMove(selectedDragEnd);
        rig.mouseRelease(selectedDragEnd);
        const std::vector<TempoPoint> selectedMoved{tempoPoint(0, 120), tempoPoint(144, 150),
                                                    tempoPoint(240, 110), tempoPoint(384, 130)};
        const auto selectedDragAfter = tempoSnapshot();
        const auto &movedSelection = rig.view().selectionModel().timeSelection();
        check(selectedDragAfter.points == selectedMoved &&
                  oneTempoEdit(selectedDragBefore, selectedDragAfter) &&
                  movedSelection.startTick == 144 && movedSelection.endTick == 336 &&
                  movedSelection.tempo,
              QStringLiteral("Tempo selection drag did not move every selected node and range"));
        restoreTempo();

        seedTempo(multiFixture);
        selectTempoRange(96, 288);
        const auto selectedDeleteBefore = tempoSnapshot();
        rig.keyToArea(QEvent::KeyPress, Qt::Key_Delete);
        const auto selectedDeleteAfter = tempoSnapshot();
        const std::vector<TempoPoint> selectedDeleted{tempoPoint(0, 120), tempoPoint(384, 130)};
        check(selectedDeleteAfter.points == selectedDeleted &&
                  oneTempoEdit(selectedDeleteBefore, selectedDeleteAfter),
              QStringLiteral("Delete did not remove every selected Tempo node atomically"));
        restoreTempo();

        seedTempo(tempoFixture);
        const auto axisStart = rig.tempoBodyPoint(96, 150);
        const auto timeActivation = axisStart + QPointF(28.0, 2.0);
        const auto timeTarget = rig.tempoBodyPoint(192, 110);
        const auto timeEnd = timeActivation + timeTarget - axisStart;
        rig.mousePress(axisStart, Qt::ShiftModifier);
        rig.mouseMove(timeActivation, Qt::LeftButton, Qt::ShiftModifier);
        rig.mouseMove(timeEnd, Qt::LeftButton, Qt::ShiftModifier);
        rig.mouseRelease(timeEnd, Qt::ShiftModifier);
        const std::vector<TempoPoint> timeLocked{tempoFixture.front(), tempoPoint(192, 150),
                                                 tempoFixture.back()};
        check(rig.document().tempoPoints() == timeLocked,
              QStringLiteral("horizontal Shift drag did not lock Tempo node value"));
        restoreTempo();

        seedTempo(tempoFixture);
        const auto valueActivation = axisStart + QPointF(2.0, 28.0);
        const auto valueTarget = rig.tempoBodyPoint(96, 110);
        const auto valueEnd = valueActivation + valueTarget - axisStart;
        rig.mousePress(axisStart, Qt::ShiftModifier);
        rig.mouseMove(valueActivation, Qt::LeftButton, Qt::ShiftModifier);
        rig.mouseMove(valueEnd, Qt::LeftButton, Qt::ShiftModifier);
        rig.mouseRelease(valueEnd, Qt::ShiftModifier);
        const std::vector<TempoPoint> valueLocked{tempoFixture.front(), tempoPoint(96, 110),
                                                  tempoFixture.back()};
        check(rig.document().tempoPoints() == valueLocked,
              QStringLiteral("vertical Shift drag did not lock Tempo node time"));
        restoreTempo();

        seedTempo(tempoFixture);
        const auto cancelStart = rig.tempoBodyPoint(96, 150);
        const auto cancelActivation = rig.tempoBodyPoint(120, 150);
        const auto cancelTarget = rig.tempoBodyPoint(192, 110);
        const auto cancelEnd = cancelActivation + cancelTarget - cancelStart;
        const auto cancelBefore = tempoSnapshot();
        rig.mousePress(cancelStart);
        rig.mouseMove(cancelActivation);
        rig.mouseMove(cancelEnd);
        rig.keyToArea(QEvent::KeyPress, Qt::Key_Escape);
        check(sameTempoSnapshot(cancelBefore, tempoSnapshot()),
              QStringLiteral("Escape committed an active Tempo node preview"));
        restoreTempo();

        seedTempo(tempoFixture);
        const auto sweepStart = rig.tempoBodyPoint(48, 90);
        const auto sweepActivation = rig.tempoBodyPoint(60, 90);
        const auto sweepTarget = rig.tempoBodyPoint(144, 160);
        const auto sweepEnd = sweepActivation + sweepTarget - sweepStart;
        const auto sweepBefore = tempoSnapshot();
        rig.mousePress(sweepStart);
        rig.mouseMove(sweepActivation);
        rig.mouseMove(sweepEnd);
        rig.mouseRelease(sweepEnd);
        const auto sweepAfter = tempoSnapshot();
        check(oneTempoEdit(sweepBefore, sweepAfter) &&
                  std::find(sweepAfter.points.cbegin(), sweepAfter.points.cend(),
                            tempoPoint(144, 160)) != sweepAfter.points.cend(),
              QStringLiteral("Tempo sweep did not use the shared activated-drag path"));
        restoreTempo();

        seedTempo(tempoFixture);
        const auto rampStart = rig.tempoBodyPoint(48, 90);
        const auto rampEnd = rig.tempoBodyPoint(144, 160);
        const auto rampBefore = tempoSnapshot();
        rig.mousePress(rampStart, Qt::ShiftModifier);
        rig.mouseMove(rampEnd, Qt::LeftButton, Qt::ShiftModifier);
        rig.mouseRelease(rampEnd, Qt::ShiftModifier);
        const auto rampAfter = tempoSnapshot();
        check(oneTempoEdit(rampBefore, rampAfter) &&
                  std::find(rampAfter.points.cbegin(), rampAfter.points.cend(),
                            tempoPoint(48, 90)) != rampAfter.points.cend() &&
                  std::find(rampAfter.points.cbegin(), rampAfter.points.cend(),
                            tempoPoint(144, 160)) != rampAfter.points.cend(),
              QStringLiteral("Tempo Shift-ramp did not use shared SweepGesture output"));
        restoreTempo();

        seedTempo(tempoFixture);
        const auto bandStart = rig.tempoBodyPoint(96, 120);
        const auto bandEnd = rig.tempoBodyPoint(288, 120);
        const uint64_t expectedStart = rig.projection().snapTickAt(bandStart.x(), false);
        const uint64_t expectedEnd = rig.projection().snapTickAt(bandEnd.x(), false);
        const QImage bandBefore = rig.renderArea();
        rig.mousePress(bandStart, Qt::NoModifier, Qt::RightButton);
        rig.mouseMove(bandEnd, Qt::RightButton);
        rig.pump();
        const QImage bandDuring = rig.renderArea();
        const qreal dpr = bandBefore.devicePixelRatio();
        const int sampleLeft =
            std::clamp(int(std::floor(std::min(bandStart.x(), bandEnd.x()) * dpr + 4 * dpr)), 0,
                       bandBefore.width());
        const int sampleRight =
            std::clamp(int(std::ceil(std::max(bandStart.x(), bandEnd.x()) * dpr - 4 * dpr)), 0,
                       bandBefore.width());
        const int sampleTop =
            std::clamp(int(std::lround(bandStart.y() * dpr - 2 * dpr)), 0, bandBefore.height());
        const QRect reticleSample(
            sampleLeft, sampleTop, std::max(0, sampleRight - sampleLeft),
            std::min(int(std::ceil(5 * dpr)), bandBefore.height() - sampleTop));
        const bool reticleRendered = !reticleSample.isEmpty() && bandDuring.copy(reticleSample) !=
                                                                     bandBefore.copy(reticleSample);
        check(expectedStart < expectedEnd && reticleRendered,
              QStringLiteral("active Tempo right-drag did not render a provisional band"));
        rig.mouseRelease(bandEnd, Qt::NoModifier, Qt::RightButton);
        rig.pump();
        const auto &selection = rig.view().selectionModel().timeSelection();
        check(selection.active() &&
                  selection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
                  selection.tempo && selection.lanes.empty() &&
                  selection.startTick == expectedStart && selection.endTick == expectedEnd,
              QStringLiteral("Tempo right-drag did not publish the expected time selection"));
    }
    restoreTempo();
    if (tempoExpanded) {
        rig.mousePress(rig.tempoHeaderPoint());
        rig.mouseRelease(rig.tempoHeaderPoint());
        rig.pump();
    }
}
