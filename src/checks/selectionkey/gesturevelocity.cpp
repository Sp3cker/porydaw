// Velocity-plot gesture scenarios for the selection-keyboard-routing Qt
// Test: the visible following node owns overlap hit priority across idle,
// hover, selected, and zoomed presentations and wins every press, while a
// selected duration-stem drag retains its captured selection and consumes
// edit keys until Escape restores it.

#include "checks/selectionkey/gesturecheck.h"

#include "checks/support/quickframebuffer.h"

#include <QApplication>
#include <QColor>
#include <QImage>
#include <QPoint>
#include <QPointF>
#include <QRect>
#include <QSize>
#include <QtTest>

#include <cmath>

namespace {

int colorDistance(const QColor &a, const QColor &b)
{
    return std::abs(a.red() - b.red()) + std::abs(a.green() - b.green()) +
           std::abs(a.blue() - b.blue());
}

} // namespace

bool SelectionKeyGestureTest::verifyNodePaintsAboveSelectedStem(
    const VelocityStemPoints &overlapPoints, const char *message)
{
    // velocityquick.cpp paints the following node center with its opaque
    // track color in idle, hover, selected, and zoomed states. Matching that
    // color proves the visible node won the stack; merely differing from
    // highlight would also accept an empty or background pixel.
    constexpr int kNodeColorTolerance = 12;
    const QColor expectedNodeColor = SongView::trackColor(kTrack);
    checks::support::pumpQuick();
    QString captureError;
    const QImage frame =
        checks::support::captureQuickBand(view(), QRect(QPoint{}, window()->size()), &captureError);
    // Canonical viewport: windowPoint is already Quick-window-local, so the
    // sampled node pixel reads straight out of the captured frame.
    const QPoint sampleInView = windowPoint(*mVelocityInput, overlapPoints.followingNode);
    const QRect sampleRect =
        checks::support::devicePixelRect(frame, QRect(sampleInView, QSize(1, 1)));
    const QColor nodePixel = frame.isNull() || !frame.rect().contains(sampleRect.center())
                                 ? QColor{}
                                 : frame.pixelColor(sampleRect.center());
    const bool painted = !frame.isNull() && captureError.isEmpty() && expectedNodeColor.isValid() &&
                         nodePixel.isValid() &&
                         colorDistance(nodePixel, expectedNodeColor) <= kNodeColorTolerance;
    if (!painted) {
        QTest::qFail(message, __FILE__, __LINE__);
        return false;
    }
    return true;
}
void SelectionKeyGestureTest::overlapNodeTargetsVisibleNode()
{
    if (!stageWorld("overlap-node", EditorDrawerPage::Velocity, kVelocitySectionHeight))
        return;
    if (!stageVelocitySurface())
        return;
    std::optional<VelocityStemPoints> points = velocityStemPoints();
    QVERIFY2(points.has_value(),
             "production velocity geometry did not expose the test stems and node");

    view().selectionModel().setNoteSelection({mWorld->notes[0]});
    if (!verifyNodePaintsAboveSelectedStem(
            *points, "following velocity node was not rendered above the selected earlier stem"))
        return;

    mouseMove(windowPoint(*mVelocityInput, points->followingNode));
    if (!verifyNodePaintsAboveSelectedStem(
            *points, "hovered following velocity node was not rendered above the selected stem"))
        return;

    view().selectionModel().setNoteSelection({mWorld->notes[0], mWorld->notes[1]});
    mouseMove(windowPoint(*mVelocityInput, points->followingStem));
    if (!verifyNodePaintsAboveSelectedStem(
            *points, "selected following velocity node was not rendered above the selected stem"))
        return;

    const double initialZoom = view().camera().pxPerBeat();
    view().setEditorTimeZoom(initialZoom * 2.0);
    selectionkey::settle();
    const std::optional<VelocityStemPoints> zoomedPoints = velocityStemPoints();
    QVERIFY2(zoomedPoints.has_value(),
             "zoomed velocity geometry did not expose the overlapping stem and node");
    if (!verifyNodePaintsAboveSelectedStem(
            *zoomedPoints,
            "zoomed selected velocity node was not rendered above the selected stem"))
        return;

    view().setEditorTimeZoom(initialZoom);
    selectionkey::settle();
    points = velocityStemPoints();
    QVERIFY2(points.has_value(),
             "restored velocity geometry did not expose the overlapping stem and node");
    view().selectionModel().setNoteSelection({mWorld->notes[0]});

    const QByteArray overlapBeforeDrag = document().smf().write();
    const uint64_t revisionBefore = document().revision();
    const int undoDepthBefore = document().undoStack()->count();
    const QPoint followingPress = windowPoint(*mVelocityInput, points->followingNode);
    QPoint followingDrag = followingPress + QPoint(0, QApplication::startDragDistance() + 4);
    followingDrag.setY(
        std::min(followingDrag.y(),
                 windowPoint(*mVelocityInput, mVelocityInput->bounds().bottomLeft()).y() - 2));
    mouseMove(followingPress);
    mousePress(Qt::LeftButton, followingPress);
    mouseMove(followingDrag);
    QTRY_VERIFY2(view().userGestureActive() && noteSelectionIs({mWorld->notes[1]}),
                 "beginning an overlap-node drag did not target the visible following node");
    // VelocityArea cancellation restores the selection captured before the
    // press ({earlier}); the committed drag's node targeting is asserted
    // above, so production cancellation stays untouched here.
    QTest::keyClick(window(), Qt::Key_Escape);
    mouseRelease(Qt::LeftButton, followingDrag);
    QVERIFY2(!view().userGestureActive() && noteSelectionIs({mWorld->notes[0]}) &&
                 document().smf().write() == overlapBeforeDrag &&
                 document().revision() == revisionBefore &&
                 document().undoStack()->count() == undoDepthBefore,
             "cancelling an overlap-node drag did not restore its pre-press selection");

    mouseMove(followingPress);
    mousePress(Qt::LeftButton, followingPress);
    QTRY_VERIFY2(noteSelectionIs({mWorld->notes[1]}),
                 "clicking the following overlap node did not replace the earlier stem selection");
    mouseRelease(Qt::LeftButton, followingPress);
    const auto followingBeforeArrow = selectionkey::noteById(document(), mWorld->notes[1]);
    const auto earlierBeforeArrow = selectionkey::noteById(document(), mWorld->notes[0]);
    QVERIFY2(followingBeforeArrow.has_value() && earlierBeforeArrow.has_value(),
             "an overlap note vanished before its arrow command");
    QTest::keyClick(window(), Qt::Key_Right);
    const auto followingAfterArrow = selectionkey::noteById(document(), mWorld->notes[1]);
    const auto earlierAfterArrow = selectionkey::noteById(document(), mWorld->notes[0]);
    QVERIFY2(followingAfterArrow.has_value() && earlierAfterArrow.has_value() &&
                 followingAfterArrow->tick > followingBeforeArrow->tick &&
                 earlierAfterArrow->tick == earlierBeforeArrow->tick,
             "arrow after overlap-node click did not target only the following note");

    QString tieError;
    const std::vector<NoteId> tiedNodes = selectionkey::insertIsolatedNotes(
        document(), kTrack, {{kLaterTick, kTiedKey, kLaterDuration, kVelocity}}, tieError);
    if (tiedNodes.size() != 1)
        QFAIL(qPrintable(
            QStringLiteral("could not create the node-overlap tie fixture: %1").arg(tieError)));
    QVERIFY2(selectionkey::noteExists(document(), mWorld->notes[2]) &&
                 selectionkey::noteExists(document(), tiedNodes.front()),
             "node-overlap tie fixture did not retain both coincident-velocity notes");
    selectionkey::settle();
    const QPointF tiedNode(
        view().camera().displayX(double(kLaterTick), 0.0, mVelocityInput->devicePixelRatio()),
        mVelocityArea->axis().velocityToY(kVelocity));
    QVERIFY2(mVelocityInput->bounds().contains(tiedNode),
             "production velocity geometry did not expose the tied nodes");
    const QPoint tiedPress = windowPoint(*mVelocityInput, tiedNode);

    // Equal unselected circles retain model-order priority: the later node
    // wins. Selecting the earlier circle then retains the higher selected
    // priority before model order is considered.
    view().selectionModel().setNoteSelection({});
    checks::support::pumpQuick();
    mouseMove(tiedPress);
    mousePress(Qt::LeftButton, tiedPress);
    QTRY_VERIFY2(noteSelectionIs({tiedNodes.front()}),
                 "equal unselected velocity nodes did not retain later-model-order priority");
    mouseRelease(Qt::LeftButton, tiedPress);

    view().selectionModel().setNoteSelection({mWorld->notes[2]});
    checks::support::pumpQuick();
    mousePress(Qt::LeftButton, tiedPress);
    QTRY_VERIFY2(noteSelectionIs({mWorld->notes[2]}),
                 "selected velocity node did not retain priority over its tied sibling");
    mouseRelease(Qt::LeftButton, tiedPress);
}

void SelectionKeyGestureTest::velocityStemDragGuardsEdits()
{
    const auto deleteKey = selectionkey::firstBinding(QStringLiteral("roll.delete"));
    QVERIFY2(deleteKey.has_value(), "roll.delete has no single-key binding");
    if (!stageWorld("velocity-stem", EditorDrawerPage::Velocity, kVelocitySectionHeight))
        return;
    if (!stageVelocitySurface())
        return;
    const std::optional<VelocityStemPoints> points = velocityStemPoints();
    QVERIFY2(points.has_value(),
             "production velocity geometry did not expose the test stems and node");

    view().selectionModel().setNoteSelection({mWorld->notes[0], mWorld->notes[2]});
    const QByteArray velocityBeforeGesture = document().smf().write();
    const uint64_t revisionBefore = document().revision();
    const int undoDepthBefore = document().undoStack()->count();
    const QPoint earlierPress = windowPoint(*mVelocityInput, points->earlierStem);
    QPoint earlierDrag = earlierPress + QPoint(0, QApplication::startDragDistance() + 4);
    earlierDrag.setY(
        std::min(earlierDrag.y(),
                 windowPoint(*mVelocityInput, mVelocityInput->bounds().bottomLeft()).y() - 2));
    mouseMove(earlierPress);
    mousePress(Qt::LeftButton, earlierPress);
    mouseMove(earlierDrag);
    QTRY_VERIFY2(view().userGestureActive() &&
                     noteSelectionIs({mWorld->notes[0], mWorld->notes[2]}),
                 "selected velocity-stem drag did not retain its captured note selection");
    QTest::keyClick(window(), Qt::Key_Right);
    selectionkey::deliverKey(window(), deleteKey->key(), deleteKey->keyboardModifiers());
    QVERIFY2(document().smf().write() == velocityBeforeGesture &&
                 noteSelectionIs({mWorld->notes[0], mWorld->notes[2]}) &&
                 document().revision() == revisionBefore &&
                 document().undoStack()->count() == undoDepthBefore,
             "an edit key mutated selection or notes during a live velocity gesture");
    QTest::keyClick(window(), Qt::Key_Escape);
    mouseRelease(Qt::LeftButton, earlierDrag);
    QVERIFY2(!view().userGestureActive() && noteSelectionIs({mWorld->notes[0], mWorld->notes[2]}) &&
                 document().smf().write() == velocityBeforeGesture &&
                 document().revision() == revisionBefore &&
                 document().undoStack()->count() == undoDepthBefore,
             "first Escape did not cancel the velocity gesture and restore its selection");
    QTest::keyClick(window(), Qt::Key_Escape);
    QVERIFY2(view().selectionModel().noteSelection().empty(),
             "second Escape after a velocity gesture did not clear the remaining selection");

    view().selectionModel().setNoteSelection({mWorld->notes[0], mWorld->notes[2]});
    const QPoint unselectedStem = windowPoint(*mVelocityInput, points->followingStem);
    mouseMove(unselectedStem);
    mousePress(Qt::LeftButton, unselectedStem);
    mouseRelease(Qt::LeftButton, unselectedStem);
    QVERIFY2(noteSelectionIs({mWorld->notes[1]}),
             "clicking an unselected velocity stem did not replace the note selection");
}
