#include "checks/automation/tst_automationediting.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <variant>
#include <vector>

#include <QApplication>
#include <QtTest>

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview/quick/timelinequickscene.h"

namespace {

constexpr uint64_t kSourceTick = 48;
constexpr uint8_t kPanController = 10;
constexpr uint64_t kTargetTick = 192;

uint64_t snappedVoiceTick(const SongView &view, qreal x, bool fine)
{
    const double rawTick = view.camera().tickAtContentX(std::max<qreal>(0.0, x));
    return view.grid().snapTick(std::max(0.0, rawTick), fine);
}

void writeVoicePoints(SongDocument &document,
                      const std::vector<SongDocument::LanePointValue> &points)
{
    document.writeLanePoints(0, DOC_CC_VOICE, 0, (std::numeric_limits<uint64_t>::max)(), points);
}

bool hasVoicePoint(const SongDocument &document, uint64_t tick, int value)
{
    const std::vector<DocLanePoint> points = document.lanePoints(0, DOC_CC_VOICE);
    return std::any_of(points.cbegin(), points.cend(), [tick, value](const DocLanePoint &point) {
        return point.tick == tick && point.value == value;
    });
}

int voicePointCount(const SongDocument &document, uint64_t tick, int value)
{
    const std::vector<DocLanePoint> points = document.lanePoints(0, DOC_CC_VOICE);
    return int(
        std::count_if(points.cbegin(), points.cend(), [tick, value](const DocLanePoint &point) {
            return point.tick == tick && point.value == value;
        }));
}

int markerCountAt(const songview::TimelineQuickLayerData &layer, qreal x)
{
    return int(std::count_if(layer.rects.cbegin(), layer.rects.cend(), [x](const auto &marker) {
        return std::abs(marker.rect.center().x() - x) <= layout::singlePixel();
    }));
}

void showVoiceChanges(SongView &view)
{
    view.setDrawerActivePage(EditorDrawerPage::VoiceChanges);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    view.setDrawerSectionHeight(EditorDrawerPage::VoiceChanges, 160);
}

} // namespace

void AutomationEditingTest::voiceHorizontalPreviewCommitsAndUndoes()
{
    showVoiceChanges(tab().view());
    QTRY_VERIFY(!voiceChangeInput().bounds().isEmpty());
    const LaneHandle pan = findRow({EditorAutomationRowKind::ControlChange, 0, kPanController});
    QVERIFY(pan.valid());
    writeVoicePoints(tab().document(), {{24, 5}, {kSourceTick, 6}});
    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(scene);
    QCOMPARE(voicePointCount(tab().document(), 24, 5), 1);
    QTRY_COMPARE(markerCountAt(scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers),
                               voicePoint(24).x()),
                 1);
    QTRY_COMPARE(markerCountAt(scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers),
                               voicePoint(kSourceTick).x()),
                 1);
    QCOMPARE(voicePointCount(tab().document(), kSourceTick, 6), 1);

    const QPointF source = voicePoint(24);
    const QPointF target = voicePoint(72);
    const uint64_t destination = snappedVoiceTick(tab().view(), target.x(), false);
    QVERIFY(destination != 24);
    const auto markersBefore = scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count(), edited.count());

    mousePress(voiceChangeInput(), Qt::LeftButton, source);
    mouseMove(voiceChangeInput(), target);

    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers).revision >
                markersBefore.revision);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);
    QVERIFY(tab().view().userGestureActive());
    QCOMPARE(voiceChangeInput().cursor().shape(), Qt::SizeHorCursor);
    const auto previewMarkers = scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers);
    QCOMPARE(markerCountAt(previewMarkers, voicePoint(destination).x()), 1);

    mouseRelease(voiceChangeInput(), Qt::LeftButton, target);

    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(tab().document().revision(), frozen.revision + 1);
    QCOMPARE(tab().document().undoStack()->count(), frozen.undoCount + 1);
    QCOMPARE(tab().document().undoStack()->index(), frozen.undoIndex + 1);
    QVERIFY(tab().document().smf().write() != frozen.smf);
    QVERIFY(!hasVoicePoint(tab().document(), 24, 5));
    QVERIFY(hasVoicePoint(tab().document(), kSourceTick, 6));
    QVERIFY(hasVoicePoint(tab().document(), destination, 5));
    QCOMPARE(int(tab().document().lanePoints(0, DOC_CC_VOICE).size()), 2);
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
    QCOMPARE(voiceChangeInput().cursor().shape(), Qt::ArrowCursor);

    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestUndo()));
    QCOMPARE(tab().document().smf().write(), frozen.smf);
}

void AutomationEditingTest::voiceStationaryVerticalJitterAndEmptySpaceDoNotCommit()
{
    showVoiceChanges(tab().view());
    QTRY_VERIFY(!voiceChangeInput().bounds().isEmpty());
    const LaneHandle pan = findRow({EditorAutomationRowKind::ControlChange, 0, kPanController});
    QVERIFY(pan.valid());
    writeVoicePoints(tab().document(), {{kSourceTick, 7}});
    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(scene);
    QTRY_COMPARE(markerCountAt(scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers),
                               voicePoint(kSourceTick).x()),
                 1);
    const QPointF source = voicePoint(kSourceTick);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count(), edited.count());

    mousePress(voiceChangeInput(), Qt::LeftButton, source);
    mouseRelease(voiceChangeInput(), Qt::LeftButton, source);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);

    const QPointF vertical = source + QPointF(0, QApplication::startDragDistance() + 2);
    mousePress(voiceChangeInput(), Qt::LeftButton, source);
    mouseMove(voiceChangeInput(), vertical);
    QVERIFY(!tab().view().userGestureActive());
    QCOMPARE(voiceChangeInput().cursor().shape(), Qt::ArrowCursor);
    mouseRelease(voiceChangeInput(), Qt::LeftButton, vertical);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);

    const QPointF empty = voicePoint(144);
    const QPointF draggedEmpty = empty + QPointF(QApplication::startDragDistance() + 2, 0);
    mousePress(voiceChangeInput(), Qt::LeftButton, empty);
    mouseMove(voiceChangeInput(), draggedEmpty);
    mouseRelease(voiceChangeInput(), Qt::LeftButton, draggedEmpty);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
}

void AutomationEditingTest::voiceAltDragUsesFineSnap()
{
    showVoiceChanges(tab().view());
    QTRY_VERIFY(!voiceChangeInput().bounds().isEmpty());
    const LaneHandle pan = findRow({EditorAutomationRowKind::ControlChange, 0, kPanController});
    QVERIFY(pan.valid());
    writeVoicePoints(tab().document(), {{kSourceTick, 8}});
    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(scene);
    QTRY_COMPARE(markerCountAt(scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers),
                               voicePoint(kSourceTick).x()),
                 1);
    const QPointF source = voicePoint(kSourceTick);
    QPointF target;
    uint64_t fineTick = 0;
    uint64_t normalTick = 0;
    for (int x = int(std::ceil(voiceChangeInput().bounds().left()));
         x < int(std::floor(voiceChangeInput().bounds().right())); ++x) {
        const uint64_t fine = snappedVoiceTick(tab().view(), x, true);
        const uint64_t normal = snappedVoiceTick(tab().view(), x, false);
        if (fine != normal && fine != kSourceTick &&
            std::abs(qreal(x) - source.x()) >= QApplication::startDragDistance()) {
            target = {qreal(x), voiceChangeInput().bounds().center().y()};
            fineTick = fine;
            normalTick = normal;
            break;
        }
    }
    QVERIFY(fineTick != normalTick);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count(), edited.count());

    mousePress(voiceChangeInput(), Qt::LeftButton, source, Qt::AltModifier);
    mouseMove(voiceChangeInput(), target, Qt::AltModifier);
    mouseRelease(voiceChangeInput(), Qt::LeftButton, target, Qt::AltModifier);

    QCOMPARE(documentChanged.count(), frozen.documentChanges + 1);
    QCOMPARE(edited.count(), frozen.edits + 1);
    QCOMPARE(tab().document().revision(), frozen.revision + 1);
    QCOMPARE(tab().document().undoStack()->count(), frozen.undoCount + 1);
    QCOMPARE(tab().document().undoStack()->index(), frozen.undoIndex + 1);
    QVERIFY(hasVoicePoint(tab().document(), fineTick, 8));
    QVERIFY(!hasVoicePoint(tab().document(), normalTick, 8));
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
}

void AutomationEditingTest::voiceCollisionAndStaleRevision()
{
    showVoiceChanges(tab().view());
    QTRY_VERIFY(!voiceChangeInput().bounds().isEmpty());
    const LaneHandle pan = findRow({EditorAutomationRowKind::ControlChange, 0, kPanController});
    QVERIFY(pan.valid());
    const QPointF source = voicePoint(kSourceTick);
    const QPointF target = voicePoint(kTargetTick);
    const uint64_t destination = snappedVoiceTick(tab().view(), target.x(), false);

    writeVoicePoints(tab().document(), {{kSourceTick, 9}, {kTargetTick, 10}});
    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(scene);
    QTRY_COMPARE(markerCountAt(scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers),
                               voicePoint(kSourceTick).x()),
                 1);
    QTRY_COMPARE(markerCountAt(scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers),
                               voicePoint(kTargetTick).x()),
                 1);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState collisionFrozen =
        frozenDocumentState(documentChanged.count(), edited.count());
    mousePress(voiceChangeInput(), Qt::LeftButton, source);
    mouseMove(voiceChangeInput(), target);
    mouseRelease(voiceChangeInput(), Qt::LeftButton, target);
    QCOMPARE(documentChanged.count(), collisionFrozen.documentChanges + 1);
    QCOMPARE(edited.count(), collisionFrozen.edits + 1);
    QCOMPARE(tab().document().revision(), collisionFrozen.revision + 1);
    QCOMPARE(tab().document().undoStack()->count(), collisionFrozen.undoCount + 1);
    QCOMPARE(tab().document().undoStack()->index(), collisionFrozen.undoIndex + 1);
    QCOMPARE(int(tab().document().lanePoints(0, DOC_CC_VOICE).size()), 1);
    QVERIFY(hasVoicePoint(tab().document(), destination, 9));
    QCOMPARE(voiceChangeInput().cursor().shape(), Qt::ArrowCursor);
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));

    writeVoicePoints(tab().document(), {{kSourceTick, 11}});
    QTRY_COMPARE(markerCountAt(scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers),
                               voicePoint(kSourceTick).x()),
                 1);
    const FrozenDocumentState staleFrozen =
        frozenDocumentState(documentChanged.count(), edited.count());
    mousePress(voiceChangeInput(), Qt::LeftButton, source);
    mouseMove(voiceChangeInput(), target);
    tab().document().addLanePoint(0, kPanController, 333, 42);
    const QByteArray externalSmf = tab().document().smf().write();
    const uint64_t externalRevision = tab().document().revision();
    QCOMPARE(documentChanged.count(), staleFrozen.documentChanges + 1);
    QCOMPARE(edited.count(), staleFrozen.edits + 1);
    mouseRelease(voiceChangeInput(), Qt::LeftButton, target);
    QCOMPARE(tab().document().smf().write(), externalSmf);
    QCOMPARE(tab().document().revision(), externalRevision);
    QCOMPARE(documentChanged.count(), staleFrozen.documentChanges + 1);
    QCOMPARE(edited.count(), staleFrozen.edits + 1);
    QVERIFY(hasVoicePoint(tab().document(), kSourceTick, 11));
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
}

void AutomationEditingTest::voiceEscapeAndUngrabCancel()
{
    showVoiceChanges(tab().view());
    QTRY_VERIFY(!voiceChangeInput().bounds().isEmpty());
    const LaneHandle pan = findRow({EditorAutomationRowKind::ControlChange, 0, kPanController});
    QVERIFY(pan.valid());
    writeVoicePoints(tab().document(), {{kSourceTick, 12}});
    const QPointF source = voicePoint(kSourceTick);
    const QPointF target = voicePoint(kTargetTick);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(scene);
    QTRY_COMPARE(markerCountAt(scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers),
                               voicePoint(kSourceTick).x()),
                 1);
    const FrozenDocumentState escapeFrozen =
        frozenDocumentState(documentChanged.count(), edited.count());
    mousePress(voiceChangeInput(), Qt::LeftButton, source);
    mouseMove(voiceChangeInput(), target);
    keyClick(Qt::Key_Escape);
    mouseRelease(voiceChangeInput(), Qt::LeftButton, target);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == escapeFrozen);
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
    QCOMPARE(voiceChangeInput().cursor().shape(), Qt::ArrowCursor);

    const FrozenDocumentState ungrabFrozen =
        frozenDocumentState(documentChanged.count(), edited.count());
    mousePress(voiceChangeInput(), Qt::LeftButton, source);
    mouseMove(voiceChangeInput(), target);
    QTRY_VERIFY(quickWindow().mouseGrabberItem() == &voiceChangeInput());
    voiceChangeInput().ungrabMouse();
    QTRY_VERIFY(!quickWindow().mouseGrabberItem());
    mouseRelease(voiceChangeInput(), Qt::LeftButton, target);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == ungrabFrozen);
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
    QCOMPARE(voiceChangeInput().cursor().shape(), Qt::ArrowCursor);
}

void AutomationEditingTest::voiceDuplicateOccurrenceMovesSingleIdentity()
{
    showVoiceChanges(tab().view());
    QTRY_VERIFY(!voiceChangeInput().bounds().isEmpty());
    const LaneHandle pan = findRow({EditorAutomationRowKind::ControlChange, 0, kPanController});
    QVERIFY(pan.valid());
    writeVoicePoints(tab().document(), {{kSourceTick, 13}, {kSourceTick, 13}});
    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(scene);
    const QPointF source = voicePoint(kSourceTick);
    const QPointF target = voicePoint(72);
    const uint64_t destination = snappedVoiceTick(tab().view(), target.x(), false);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QTRY_COMPARE(markerCountAt(scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers),
                               voicePoint(kSourceTick).x()),
                 2);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count(), edited.count());
    const auto markersBefore = scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers);

    mousePress(voiceChangeInput(), Qt::LeftButton, source);
    mouseMove(voiceChangeInput(), target);

    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers).revision >
                markersBefore.revision);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);
    const auto previewMarkers = scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers);
    QCOMPARE(markerCountAt(markersBefore, source.x()), 2);
    QCOMPARE(markerCountAt(previewMarkers, source.x()), 1);
    QCOMPARE(markerCountAt(markersBefore, voicePoint(destination).x()), 0);
    QCOMPARE(markerCountAt(previewMarkers, voicePoint(destination).x()), 1);
    QCOMPARE(previewMarkers.rects.size(), markersBefore.rects.size());

    mouseRelease(voiceChangeInput(), Qt::LeftButton, target);
    QCOMPARE(documentChanged.count(), frozen.documentChanges + 1);
    QCOMPARE(edited.count(), frozen.edits + 1);
    QCOMPARE(tab().document().revision(), frozen.revision + 1);
    QCOMPARE(tab().document().undoStack()->count(), frozen.undoCount + 1);
    QCOMPARE(tab().document().undoStack()->index(), frozen.undoIndex + 1);
    QCOMPARE(voicePointCount(tab().document(), kSourceTick, 13), 1);
    QCOMPARE(voicePointCount(tab().document(), destination, 13), 1);
    QCOMPARE(int(tab().document().lanePoints(0, DOC_CC_VOICE).size()), 2);
    QVERIFY(!tab().view().userGestureActive());
    QVERIFY(!page().canvas()->isPanning());
    QVERIFY(!page().canvas()->bandPreviewContainsLane(pan));
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestUndo()));
    QCOMPARE(tab().document().smf().write(), frozen.smf);
}
