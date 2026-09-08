// Roll and automation gesture scenarios for the selection-keyboard-routing Qt
// Test: grid size stays live through a roll note move while Delete, Shift
// resize, and grid feel remain guarded; automation range and pan gestures
// continue guarding every Timeline grid command and Shift note resize.
// Escape cancels without dropping the captured selection. The canonical
// note-selection idle clear lives in the velocity and window-resize cases.

#include "checks/selectionkey/gesturecheck.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/songviewmodel.h"

#include <QApplication>
#include <QPoint>
#include <QPointF>
#include <QRect>
#include <QTest>

#include <algorithm>
#include <cmath>
#include <optional>

void SelectionKeyGestureTest::rollNoteMoveGridChangesStayLive_data()
{
    QTest::addColumn<QString>("sizeCommand");
    QTest::addColumn<QString>("inverseSizeCommand");
    QTest::addColumn<uint>("expectedDenominator");
    QTest::addColumn<qulonglong>("expectedGridTicks");
    QTest::addColumn<qulonglong>("pointerTickDelta");
    QTest::addColumn<qulonglong>("expectedMoveTickDelta");

    QTest::newRow("narrow to three-tick snap")
        << QStringLiteral("roll.grid_narrow") << QStringLiteral("roll.grid_widen") << uint{32}
        << qulonglong{3} << qulonglong{9} << qulonglong{9};
    QTest::newRow("widen to twelve-tick snap")
        << QStringLiteral("roll.grid_widen") << QStringLiteral("roll.grid_narrow") << uint{8}
        << qulonglong{12} << qulonglong{7} << qulonglong{12};
}

void SelectionKeyGestureTest::rollNoteMoveGridChangesStayLive()
{
    QFETCH(QString, sizeCommand);
    QFETCH(QString, inverseSizeCommand);
    QFETCH(uint, expectedDenominator);
    QFETCH(qulonglong, expectedGridTicks);
    QFETCH(qulonglong, pointerTickDelta);
    QFETCH(qulonglong, expectedMoveTickDelta);

    const auto sizeKey = selectionkey::firstBinding(sizeCommand);
    const auto inverseSizeKey = selectionkey::firstBinding(inverseSizeCommand);
    const auto tripletKey = selectionkey::firstBinding(QStringLiteral("roll.grid_triplet"));
    const auto deleteKey = selectionkey::firstBinding(QStringLiteral("roll.delete"));
    const auto lengthenKey = selectionkey::firstBinding(QStringLiteral("roll.lengthen_note"));
    QVERIFY2(sizeKey.has_value() && inverseSizeKey.has_value() && tripletKey.has_value() &&
                 deleteKey.has_value() && lengthenKey.has_value(),
             "roll grid size, triplet, Delete, and resize commands need single-key bindings");
    if (!stageWorld("roll-gesture", EditorDrawerPage::Automations, kAutomationSectionHeight))
        return;
    mRollInput = selectionkey::rigInput(*mWorld, "timelineRollInput");
    QVERIFY2(mRollInput && !mRollInput->bounds().isEmpty(), "roll Quick input is unavailable");
    QVERIFY2(focusPointerSurface(mRollInput, songview::TimelineBand::Roll),
             "roll drag surface did not own live Quick and native focus");

    view().setGridFeel(songview::GridFeel::Straight);
    view().setGridSelection(songview::GridSelection::musical(16));
    QVERIFY2(view().gridSelection() == songview::GridSelection::musical(16) &&
                 view().grid().feel() == songview::GridFeel::Straight &&
                 view().grid().snapTicksAt(0) == 6,
             "the 24-PPQN gesture fixture did not stage the independent six-tick grid");

    // Reveal through the production SongView seams first, then read camera
    // geometry. The roll hit-test reads the published view model.
    view().ensureTickVisible(kEarlierTick);
    view().ensureKeyVisible(kEarlierKey);
    selectionkey::settle();
    view().selectionModel().setNoteSelection({mWorld->notes[0]});
    const NoteId routedNoteId = mWorld->notes[0];
    QTRY_VERIFY2(
        [&] {
            const auto &notes = view().model().notes;
            return std::any_of(notes.cbegin(), notes.cend(),
                               [routedNoteId](const ViewNote &viewNote) {
                                   return viewNote.noteId == routedNoteId;
                               });
        }(),
        "the roll view model never exposed the fixture note for the gesture");
    const std::optional<DocNote> original = selectionkey::noteById(document(), routedNoteId);
    QVERIFY2(original.has_value(), "the routed note vanished before the move");

    const qreal rollDpr = mRollInput->devicePixelRatio();
    const double pressTick = double(kEarlierTick) + double(kEarlierDuration) / 2.0;
    const qreal rollX = view().camera().displayX(pressTick, 0.0, rollDpr);
    const auto rollEdge = [&](int row) {
        return std::round((row * view().camera().keyHeight() - view().camera().scrollY()) *
                          rollDpr) /
               rollDpr;
    };
    const qreal rollY = (rollEdge(127 - kEarlierKey) + rollEdge(128 - kEarlierKey)) / 2.0;
    const QPointF rollPoint(rollX, rollY);
    QVERIFY2(mRollInput->bounds().contains(rollPoint),
             "production roll geometry did not expose the fixture note for the drag");
    const QPoint rollPress = windowPoint(*mRollInput, rollPoint);
    const QPoint moveTarget = windowPoint(
        *mRollInput,
        QPointF(view().camera().displayX(pressTick + double(pointerTickDelta), 0.0, rollDpr),
                rollY));
    QVERIFY2(mRollInput->bounds().contains(mRollInput->mapFromScene(moveTarget)),
             "live-grid move target is outside the production Quick input");

    const QByteArray rollBeforeGesture = document().smf().write();
    const uint64_t revisionBefore = document().revision();
    const int undoCountBefore = document().undoStack()->count();
    const int undoIndexBefore = document().undoStack()->index();
    mouseMove(rollPress);
    mousePress(Qt::LeftButton, rollPress);
    mouseMove(rollPress + QPoint(QApplication::startDragDistance() + 4, 0));
    QTRY_VERIFY2(view().userGestureActive() && window()->mouseGrabberItem() == mRollInput,
                 "roll note move did not retain its live native grab");

    QVERIFY2(selectionkey::deliverKey(window(), sizeKey->key(), sizeKey->keyboardModifiers()),
             "held-pointer grid size command did not reach the live roll input");
    QVERIFY2(view().gridSelection() == songview::GridSelection::musical(expectedDenominator) &&
                 view().grid().feel() == songview::GridFeel::Straight &&
                 view().grid().snapTicksAt(0) == uint64_t(expectedGridTicks) &&
                 view().userGestureActive() && window()->mouseGrabberItem() == mRollInput &&
                 noteSelectionIs({routedNoteId}) && document().smf().write() == rollBeforeGesture,
             "grid size delivery changed the move owner, selection, or document");

    const selectionkey::GridCommandState sizedGrid = selectionkey::gridCommandState(view());
    QVERIFY2(
        selectionkey::deliverKey(window(), tripletKey->key(), tripletKey->keyboardModifiers()) &&
            selectionkey::sameGridCommandState(view(), sizedGrid),
        "triplet feel escaped the live note-move guard");
    selectionkey::deliverKey(window(), deleteKey->key(), deleteKey->keyboardModifiers());
    QVERIFY2(document().smf().write() == rollBeforeGesture && noteSelectionIs({routedNoteId}) &&
                 view().userGestureActive() && window()->mouseGrabberItem() == mRollInput,
             "Delete mutated the note or disturbed its live move");
    QVERIFY2(
        selectionkey::deliverKey(window(), lengthenKey->key(), lengthenKey->keyboardModifiers()) &&
            view().userGestureActive() && window()->mouseGrabberItem() == mRollInput &&
            document().smf().write() == rollBeforeGesture && noteSelectionIs({routedNoteId}),
        "note resize escaped the live note-move guard");

    mouseMove(moveTarget);
    QVERIFY2(view().userGestureActive() && window()->mouseGrabberItem() == mRollInput &&
                 document().smf().write() == rollBeforeGesture,
             "movement on the changed grid lost the grab or committed before release");
    mouseRelease(Qt::LeftButton, moveTarget);

    const std::optional<DocNote> moved = selectionkey::noteById(document(), routedNoteId);
    QVERIFY2(moved.has_value() && moved->tick == original->tick + uint64_t(expectedMoveTickDelta) &&
                 moved->key == original->key && moved->duration == original->duration &&
                 moved->velocity == original->velocity && noteSelectionIs({routedNoteId}) &&
                 !view().userGestureActive() && document().smf().write() != rollBeforeGesture &&
                 document().revision() == revisionBefore + 1 &&
                 document().undoStack()->count() == undoCountBefore + 1 &&
                 document().undoStack()->index() == undoIndexBefore + 1,
             "release did not commit the same selected note once at the literal live-grid snap");

    document().undoStack()->undo();
    selectionkey::settle();
    const std::optional<DocNote> undone = selectionkey::noteById(document(), routedNoteId);
    QVERIFY2(undone.has_value() && undone->tick == original->tick && undone->key == original->key &&
                 undone->duration == original->duration && undone->velocity == original->velocity &&
                 document().smf().write() == rollBeforeGesture && noteSelectionIs({routedNoteId}) &&
                 document().undoStack()->index() == undoIndexBefore,
             "one undo did not restore the original selected NoteId and document");

    // Start a second native move on the restored note. The inverse size
    // command must also stay live, while Escape cancels its changed-grid
    // preview without a release-time commit.
    const uint64_t cancelRevisionBefore = document().revision();
    const int cancelUndoCountBefore = document().undoStack()->count();
    mouseMove(rollPress);
    mousePress(Qt::LeftButton, rollPress);
    mouseMove(rollPress + QPoint(QApplication::startDragDistance() + 4, 0));
    QTRY_VERIFY2(view().userGestureActive() && window()->mouseGrabberItem() == mRollInput,
                 "cancel probe did not establish a second native note-move grab");
    QVERIFY2(selectionkey::deliverKey(window(), inverseSizeKey->key(),
                                      inverseSizeKey->keyboardModifiers()),
             "inverse held-pointer grid size command did not reach the live roll input");
    QVERIFY2(view().gridSelection() == songview::GridSelection::musical(16) &&
                 view().grid().feel() == songview::GridFeel::Straight &&
                 view().grid().snapTicksAt(0) == 6 && view().userGestureActive() &&
                 window()->mouseGrabberItem() == mRollInput && noteSelectionIs({routedNoteId}),
             "inverse grid size delivery changed the cancel probe's owner or selection");
    mouseMove(moveTarget);
    QTest::keyClick(window(), Qt::Key_Escape);
    QVERIFY2(!view().userGestureActive() && noteSelectionIs({routedNoteId}),
             "Escape did not cancel only the changed-grid note move");
    mouseRelease(Qt::LeftButton, moveTarget);
    const std::optional<DocNote> cancelled = selectionkey::noteById(document(), routedNoteId);
    QVERIFY2(cancelled.has_value() && cancelled->tick == original->tick &&
                 cancelled->key == original->key && cancelled->duration == original->duration &&
                 cancelled->velocity == original->velocity &&
                 document().smf().write() == rollBeforeGesture &&
                 document().revision() == cancelRevisionBefore &&
                 document().undoStack()->count() == cancelUndoCountBefore &&
                 document().undoStack()->index() == undoIndexBefore &&
                 noteSelectionIs({routedNoteId}),
             "physical release after Escape committed or changed the restored note");
}

void SelectionKeyGestureTest::automationPanGuardsSharedCommands()
{
    const auto deleteKey = selectionkey::firstBinding(QStringLiteral("roll.delete"));
    const auto lengthenKey = selectionkey::firstBinding(QStringLiteral("roll.lengthen_note"));
    const auto shortenKey = selectionkey::firstBinding(QStringLiteral("roll.shorten_note"));
    QVERIFY2(deleteKey.has_value() && lengthenKey.has_value() && shortenKey.has_value(),
             "roll delete and resize commands have no single-key bindings");
    if (!stageWorld("automation-gesture", EditorDrawerPage::Automations, kAutomationSectionHeight))
        return;
    mAutomationInput = selectionkey::rigInput(*mWorld, "timelineAutomationInput");
    AutomationPage *const automation =
        view().editorDrawer() ? view().editorDrawer()->automationPage() : nullptr;
    QVERIFY2(automation != nullptr && !mAutomationInput.isNull() &&
                 QTest::qWaitFor([this] { return !mAutomationInput->bounds().isEmpty(); }),
             "automation Quick input is unavailable");
    QVERIFY2(focusPointerSurface(mAutomationInput, songview::TimelineBand::Automation),
             "automation pan surface did not own live Quick and native focus");

    const auto laneRow = [&]() -> std::optional<LaneHandle> {
        const auto &rows = automation->canvas()->rows();
        for (int index = 0; index < int(rows.size()); ++index) {
            const AutomationRow &candidate = rows[std::size_t(index)];
            if (candidate.id.kind == EditorAutomationRowKind::ControlChange &&
                candidate.id.track == kTrack && candidate.id.controller == kAutomationController)
                return LaneHandle{index + 1};
        }
        return std::nullopt;
    };
    QTRY_VERIFY2(laneRow().has_value(), "automation fixture lane was not presented");
    const QRect body = automation->canvas()->laneBody(*laneRow());
    const QPointF automationPoint(
        view().camera().displayX(double(kFollowingTick), 0.0, mAutomationInput->devicePixelRatio()),
        body.center().y() - automation->verticalScroll());
    QVERIFY2(mAutomationInput->bounds().contains(automationPoint),
             "production automation geometry did not expose the gesture point");
    // A real right-button sweep establishes the lane time selection. The grid
    // bindings are delivered while that drag still owns the surface, before
    // release publishes its selection.
    const QPoint automationPress = windowPoint(*mAutomationInput, automationPoint);
    const QPointF rangeEndPoint =
        automationPoint + QPointF(QApplication::startDragDistance() + 12.0, 0.0);
    QVERIFY2(mAutomationInput->bounds().contains(rangeEndPoint),
             "automation range endpoint is outside the production Quick input");
    const QPoint rangeEnd = windowPoint(*mAutomationInput, rangeEndPoint);
    const QByteArray rangeBefore = document().smf().write();
    const uint64_t rangeRevisionBefore = document().revision();
    const int rangeUndoDepthBefore = document().undoStack()->count();
    mouseMove(automationPress);
    mousePress(Qt::RightButton, automationPress);
    mouseMove(rangeEnd);
    QTRY_VERIFY2(view().userGestureActive(),
                 "automation range sweep did not become a live gesture");
    QVERIFY2(selectionkey::guardedGridCommandsLeaveStateUnchanged(window(), view()),
             "a Timeline grid command mutated selection or feel during a live automation range");
    QVERIFY2(
        selectionkey::deliverKey(window(), lengthenKey->key(), lengthenKey->keyboardModifiers()) &&
            view().userGestureActive() && document().smf().write() == rangeBefore &&
            document().revision() == rangeRevisionBefore &&
            document().undoStack()->count() == rangeUndoDepthBefore,
        "note resize mutated the song during a live automation range sweep");
    mouseRelease(Qt::RightButton, rangeEnd);
    QVERIFY2(!view().userGestureActive() && view().selectionModel().timeSelection().active() &&
                 document().smf().write() == rangeBefore &&
                 document().revision() == rangeRevisionBefore &&
                 document().undoStack()->count() == rangeUndoDepthBefore,
             "automation right-button range sweep did not publish only a time selection");

    const QByteArray automationBeforeGesture = document().smf().write();
    const uint64_t revisionBefore = document().revision();
    const int undoDepthBefore = document().undoStack()->count();
    mouseMove(automationPress);
    mousePress(Qt::MiddleButton, automationPress);
    QTRY_VERIFY2(view().userGestureActive(), "automation pan did not become a live gesture");
    QVERIFY2(selectionkey::guardedGridCommandsLeaveStateUnchanged(window(), view()),
             "a Timeline grid command mutated selection or feel during a live automation pan");
    selectionkey::deliverKey(window(), deleteKey->key(), deleteKey->keyboardModifiers());
    QVERIFY2(
        selectionkey::deliverKey(window(), shortenKey->key(), shortenKey->keyboardModifiers()) &&
            view().userGestureActive() && document().smf().write() == automationBeforeGesture &&
            document().revision() == revisionBefore &&
            document().undoStack()->count() == undoDepthBefore,
        "note resize mutated the song during a live automation pan");
    QTest::keyClick(window(), Qt::Key_Escape);
    mouseRelease(Qt::MiddleButton, automationPress);
    QVERIFY2(!view().userGestureActive() && document().smf().write() == automationBeforeGesture &&
                 view().selectionModel().timeSelection().active() &&
                 document().revision() == revisionBefore &&
                 document().undoStack()->count() == undoDepthBefore,
             "automation gesture did not block Delete and preserve its time selection on "
             "Escape");
    QTest::keyClick(window(), Qt::Key_Escape);
    QVERIFY2(!view().selectionModel().timeSelection().active(),
             "second Escape after automation cancellation did not clear time selection");
}
