// Selection keyboard routing, protected-local-input tier: the event list page.
// Row-local navigation, Select All, and the registered reorder binding stay
// inside the page/controller, Copy with event-list focus fires exactly once
// through its one window owner, and Delete removes exactly the selected
// raw-event rows while a note selected in the song — but not in the page —
// survives untouched (plan 11). Every key posts into the production Quick
// window; the destructive Delete runs last in the case.
#include "checks/selectionkey/tst_localinputtier.h"

#include "ui/eventtablemodel.h"
#include "ui/songview/quick/eventlistcontroller.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QQuickItem>
#include <QQuickWindow>

#include <QtTest>

#include <algorithm>
#include <optional>
#include <vector>

namespace {

constexpr int kTrack = 0;
constexpr uint64_t kProtectedTick = 6720;

int totalEvents(const SongDocument &document)
{
    int total = 0;
    for (const SmfTrack &track : document.smf().tracks)
        total += int(track.events.size());
    return total;
}

QString rowSummary(const eventlist::EventTableModel *model, int row)
{
    return model->data(model->index(row, eventlist::EventTableModel::ColSummary), Qt::DisplayRole)
        .toString();
}

} // namespace

void SelectionLocalInputTierTest::eventListKeepsRowLocalKeys()
{
    SongView &view = this->view();
    SongDocument &document = this->document();
    const selectionkey::ScenarioRollback rollback(view, document);
    QVERIFY2(stageKnownNonterminalGrid(),
             "the Event List fixture did not stage the supported six-tick 1/16 grid");
    // The pitch-bend overlay self-activated on top of the shell; the window
    // Copy owner below only fires while the shell is the active window again.
    activateShellForCommands();
    view.setEventListVisible(true);
    selectionkey::settle();
    auto *const controller = view.eventListController();
    QVERIFY2(controller && controller->isVisible(), "the event list page is unavailable");
    auto *const model = controller->model();
    QVERIFY2(model != nullptr, "the event list model is missing");
    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view);
    QVERIFY2(quick && quick->quickWindow(), "the tab Quick window is missing");
    QQuickWindow *const quickWindow = quick->quickWindow();
    const int rows = model->rowCount();
    QVERIFY2(rows >= 4, "the event-list fixture has too few rows");
    const int copyBefore = m_counts.copy;
    QVERIFY2(quick->focusEventListInput(Qt::OtherFocusReason),
             "the event list input did not take focus");
    selectionkey::settle();
    const auto gridNarrow = selectionkey::firstBinding(QStringLiteral("roll.grid_narrow"));
    QVERIFY2(gridNarrow.has_value(), "narrow-grid has no single-key binding");
    const selectionkey::GridCommandState gridBeforeEventList = selectionkey::gridCommandState(view);
    QTest::keyClick(quickWindow, gridNarrow->key(), gridNarrow->keyboardModifiers());
    selectionkey::settle();
    QVERIFY2(
        selectionkey::sameGridCommandState(view, gridBeforeEventList),
        "Event List delivery leaked the Timeline narrow-grid command through context fallback");

    // Production keeps timelineEventListInput focused while the list is the
    // visible surface: page window-Shortcuts (nav keys, Select All) match at
    // the window, and the interaction chain consumes its local commands.
    const auto focusInput = [quick]() -> bool {
        return quick->focusEventListInput(Qt::OtherFocusReason);
    };
    QVERIFY2(focusInput(), "the event list input did not take focus");

    // Row navigation stays list-local.
    controller->selectRow(0, Qt::NoModifier);
    selectionkey::settle();
    QTest::keyClick(quickWindow, Qt::Key_Down);
    selectionkey::settle();
    QCOMPARE(controller->currentRow(), 1);
    QTest::keyClick(quickWindow, Qt::Key_Up);
    selectionkey::settle();
    QCOMPARE(controller->currentRow(), 0);

    // Plain Left/Right stay the page's own column navigation: the focused
    // input declines them, so the page's window Shortcuts move the current
    // column within the table.
    QQuickItem *const root = quick->rootObject();
    QQuickItem *const page =
        root ? root->findChild<QQuickItem *>(QStringLiteral("eventListPage")) : nullptr;
    QVERIFY2(page, "the event list page item is missing");
    const int columnCount = page->property("columnCount").toInt();
    const int columnBefore = page->property("currentColumn").toInt();
    QVERIFY2(columnCount >= 2 && columnBefore >= 0 && columnBefore < columnCount,
             "the event list page did not report a navigable column geometry");
    QTest::keyClick(quickWindow, Qt::Key_Right);
    selectionkey::settle();
    QCOMPARE(page->property("currentColumn").toInt(),
             std::clamp(columnBefore + 1, 0, columnCount - 1));
    QTest::keyClick(quickWindow, Qt::Key_Left);
    selectionkey::settle();
    QCOMPARE(page->property("currentColumn").toInt(), columnBefore);

    // Select All stays local to the event rows.
    QTest::keyClick(quickWindow, Qt::Key_A, Qt::ControlModifier);
    selectionkey::settle();
    QCOMPARE(controller->selectedRows().count(), rows);

    // The registered reorder binding swaps adjacent rows without changing the
    // event set.
    const auto moveUp = selectionkey::firstBinding(QStringLiteral("eventlist.move_up"));
    QVERIFY2(moveUp.has_value(), "eventlist.move_up has no single binding");
    const int totalBefore = totalEvents(document);
    const QString row0Before = rowSummary(model, 0);
    const QString row1Before = rowSummary(model, 1);
    controller->selectRow(1, Qt::NoModifier);
    selectionkey::settle();
    QVERIFY2(focusInput(), "the event list input did not take focus");
    QTest::keyClick(quickWindow, moveUp->key(), moveUp->keyboardModifiers());
    selectionkey::settle();
    QVERIFY2(rowSummary(model, 0) == row1Before && rowSummary(model, 1) == row0Before,
             "the reorder key did not swap the first two rows");
    QVERIFY2(model->rowCount() == rows && totalEvents(document) == totalBefore,
             "reordering changed the event count");

    // Copy with event-list focus keeps exactly one window Copy owner; the
    // delivery is window-scoped, so the shell must be the active window.
    const auto copy = selectionkey::firstBinding(QStringLiteral("roll.copy"));
    QVERIFY2(copy.has_value(), "Copy has no single-key binding");
    activateShellForCommands();
    QVERIFY2(focusInput(), "the event list input did not take focus for Copy");
    QTest::keyClick(quickWindow, copy->key(), copy->keyboardModifiers());
    selectionkey::settle();
    QCOMPARE(m_counts.copy, copyBefore + 1);

    // The new Shift+Arrow resize chords own note editing from the timeline,
    // but the event list keeps them away from the song: a note selected in
    // the song keeps its exact shape through both deliveries, and its
    // selection survives.
    const std::optional<NoteRef> protectedNote = addNote(kTrack, kProtectedTick, 60, 48);
    QVERIFY2(protectedNote.has_value(),
             "the reserved tick-6720 protected note could not be inserted and resolved");
    selectionkey::settle();
    const uint64_t protectedEndTick = protectedNote->note.tick + protectedNote->note.duration;
    const std::optional<DocNote> noteBeforeResize =
        selectionkey::noteById(document, protectedNote->id);
    const QByteArray songBeforeResize = document.smf().write();
    view.selectionModel().setNoteSelection({protectedNote->id});
    selectionkey::settle();
    const auto lengthen = selectionkey::firstBinding(QStringLiteral("roll.lengthen_note"));
    const auto shorten = selectionkey::firstBinding(QStringLiteral("roll.shorten_note"));
    QVERIFY2(lengthen.has_value() && shorten.has_value(),
             "Lengthen/Shorten Note have no single-key bindings");
    QVERIFY2(focusInput(), "the event list input did not take focus for the resize chords");
    QTest::keyClick(quickWindow, lengthen->key(), lengthen->keyboardModifiers());
    selectionkey::settle();
    QTest::keyClick(quickWindow, shorten->key(), shorten->keyboardModifiers());
    selectionkey::settle();
    const std::optional<DocNote> noteAfterResize =
        selectionkey::noteById(document, protectedNote->id);
    QVERIFY2(document.smf().write() == songBeforeResize && noteBeforeResize.has_value() &&
                 noteAfterResize.has_value() && noteAfterResize->tick == noteBeforeResize->tick &&
                 noteAfterResize->duration == noteBeforeResize->duration &&
                 view.selectionModel().noteSelection() == std::vector<NoteId>{protectedNote->id},
             "event-list Shift+Arrow resized, moved, or deselected the song note");

    // Delete removes the selected rows; a note that is selected in the song
    // but whose row is not selected must survive untouched.
    int protectedRow = -1;
    bool duplicateProtectedTick = false;
    for (int row = 0; row < model->rowCount(); ++row) {
        const auto tick = model->exactTickForRow(row);
        if (tick && *tick == protectedNote->note.tick) {
            if (protectedRow >= 0) {
                duplicateProtectedTick = true;
                break;
            }
            protectedRow = row;
        }
    }
    QVERIFY2(!duplicateProtectedTick, "the protected tick is not unique in the fixture");
    QVERIFY2(protectedRow >= 0, "the protected note row is missing");
    // Victims need a list-unique tick so the post-delete scan cannot be
    // confused by a second event sharing their tick. Only raw-event rows
    // qualify: a tempo row's Delete is the tempo-map operation, not the
    // raw-event removal this scenario asserts, and the protected note's
    // note-end row belongs to the note that must survive untouched.
    const auto countRowsWithTick = [&](uint64_t tick) {
        int count = 0;
        for (int row = 0; row < model->rowCount(); ++row) {
            const auto rowTick = model->exactTickForRow(row);
            if (rowTick && *rowTick == tick)
                ++count;
        }
        return count;
    };
    std::vector<int> victimRows;
    std::vector<uint64_t> victimTicks;
    for (int row = 0; row < model->rowCount() && int(victimRows.size()) < 2; ++row) {
        const auto tick = model->exactTickForRow(row);
        if (!tick || !model->rawEventIndexForRow(row).has_value() || row == protectedRow ||
            *tick == protectedNote->note.tick || *tick == protectedEndTick ||
            countRowsWithTick(*tick) != 1)
            continue;
        victimRows.push_back(row);
        victimTicks.push_back(*tick);
    }
    QCOMPARE(int(victimRows.size()), 2);
    // Select All ran earlier and every document refresh preserves valid row
    // positions, so drop whatever selection survived before staging the two
    // victims — otherwise Delete would remove every selected raw event.
    controller->selectRow(-1, Qt::NoModifier);
    selectionkey::settle();
    QVERIFY2(focusInput(), "the event list input did not take focus for Delete");
    controller->selectRow(victimRows.front(), Qt::NoModifier);
    controller->selectRow(victimRows.back(), Qt::ControlModifier);
    selectionkey::settle();
    QVERIFY2(controller->selectedRows().contains(victimRows.front()) &&
                 controller->selectedRows().contains(victimRows.back()),
             "the two victim rows were not both selected");
    view.selectionModel().setNoteSelection({protectedNote->id});

    const int rowsBeforeDelete = model->rowCount();
    const int totalBeforeDelete = totalEvents(document);
    QTest::keyClick(quickWindow, Qt::Key_Delete);
    selectionkey::settle();
    QCOMPARE(model->rowCount(), rowsBeforeDelete - 2);
    QCOMPARE(totalEvents(document), totalBeforeDelete - 2);
    int victimRowsRemaining = 0;
    for (int row = 0; row < model->rowCount(); ++row) {
        const auto tick = model->exactTickForRow(row);
        if (tick && std::find(victimTicks.begin(), victimTicks.end(), *tick) != victimTicks.end())
            ++victimRowsRemaining;
    }
    QCOMPARE(victimRowsRemaining, 0);
    const std::optional<DocNote> survivor = selectionkey::noteById(document, protectedNote->id);
    QVERIFY2(survivor.has_value() && survivor->tick == protectedNote->note.tick &&
                 survivor->key == protectedNote->note.key && !survivor->unterminated(),
             "event-list Delete mutated the note-selection target instead of its rows");

    view.setEventListVisible(false);
    selectionkey::settle();
}
