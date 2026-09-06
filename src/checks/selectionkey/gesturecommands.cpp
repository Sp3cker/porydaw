// Roll and automation gesture scenarios for the selection-keyboard-routing
// Qt Test: a roll note drag and an automation middle-button pan are both
// live surface owners — the shared Delete resolved through the live keymap
// is a consumed no-op mid-gesture, and the first Escape cancels only the
// gesture and restores or preserves the staged selection. The pan case keeps
// its second idle Escape clearing the time selection; the canonical
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

songview::EditorSelectionModel::TimeSelection SelectionKeyGestureTest::automationSelection()
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = kFollowingTick;
    selection.endTick = kFollowingTick + 24;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes = {{kTrack, kAutomationController}};
    return selection;
}

void SelectionKeyGestureTest::rollNoteDragGuardsSharedCommands()
{
    const auto deleteKey = selectionkey::firstBinding(QStringLiteral("roll.delete"));
    QVERIFY2(deleteKey.has_value(), "roll.delete has no single-key binding");
    if (!stageWorld("roll-gesture", EditorDrawerPage::Automations, kAutomationSectionHeight))
        return;
    mRollInput = selectionkey::rigInput(*mWorld, "timelineRollInput");
    QVERIFY2(mRollInput && !mRollInput->bounds().isEmpty(), "roll Quick input is unavailable");
    QVERIFY2(focusPointerSurface(mRollInput, songview::TimelineBand::Roll),
             "roll drag surface did not own live Quick and native focus");

    // Reveal through the production SongView seams first (the camera mutators
    // that wrap the shared camera state), then read camera().displayX —
    // computing coordinates from a stale camera is what left the press
    // missing the note. The roll hit-test reads the view model, so the
    // fixture note must also be published there before the press.
    view().ensureTickVisible(kEarlierTick);
    view().ensureKeyVisible(kEarlierKey);
    selectionkey::settle();
    // Stage the selection before the press: the gesture captures the
    // pre-press selection, so the cancel-restore assertion needs the same
    // staging order as a user selecting, then dragging.
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

    const qreal rollDpr = mRollInput->devicePixelRatio();
    const qreal rollX = view().camera().displayX(
        double(kEarlierTick) + double(kEarlierDuration) / 2.0, 0.0, rollDpr);
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
    const QByteArray rollBeforeGesture = document().smf().write();
    const uint64_t revisionBefore = document().revision();
    const int undoDepthBefore = document().undoStack()->count();
    mouseMove(rollPress);
    mousePress(Qt::LeftButton, rollPress);
    mouseMove(rollPress + QPoint(QApplication::startDragDistance() + 4, 0));
    QTRY_VERIFY2(view().userGestureActive(), "roll note drag did not become a live gesture");
    selectionkey::deliverKey(window(), deleteKey->key(), deleteKey->keyboardModifiers());
    QTest::keyClick(window(), Qt::Key_Escape);
    mouseRelease(Qt::LeftButton, rollPress);
    QVERIFY2(!view().userGestureActive() && document().smf().write() == rollBeforeGesture &&
                 noteSelectionIs({mWorld->notes[0]}) && document().revision() == revisionBefore &&
                 document().undoStack()->count() == undoDepthBefore,
             "roll gesture did not block Delete and restore selection on Escape");
}

void SelectionKeyGestureTest::automationPanGuardsSharedCommands()
{
    const auto deleteKey = selectionkey::firstBinding(QStringLiteral("roll.delete"));
    QVERIFY2(deleteKey.has_value(), "roll.delete has no single-key binding");
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
    view().selectionModel().setTimeSelection(automationSelection());
    const QByteArray automationBeforeGesture = document().smf().write();
    const uint64_t revisionBefore = document().revision();
    const int undoDepthBefore = document().undoStack()->count();
    const QPoint automationPress = windowPoint(*mAutomationInput, automationPoint);
    mouseMove(automationPress);
    mousePress(Qt::MiddleButton, automationPress);
    QTRY_VERIFY2(view().userGestureActive(), "automation pan did not become a live gesture");
    selectionkey::deliverKey(window(), deleteKey->key(), deleteKey->keyboardModifiers());
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
