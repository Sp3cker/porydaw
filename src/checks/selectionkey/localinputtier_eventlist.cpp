// Selection keyboard routing, protected-local-input tier: the event list. The
// QTableView keeps row-local navigation, Select All, and the registered Alt
// reorder binding, Copy with event-list focus fires exactly once through its
// one window owner, and Delete removes exactly the selected raw-event rows
// while a note selected in the song — but not in the table — survives
// untouched (plan 11). The destructive Delete runs last in the case.

#include "checks/selectionkey/tst_localinputtier.h"

#include "ui/eventtablemodel.h"

#include <QApplication>
#include <QItemSelectionModel>
#include <QTableView>

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
    // The pitch-bend overlay self-activated on top of the shell; the window
    // Copy owner below only fires while the shell is the active window again.
    activateShellForCommands();
    view.setEventListVisible(true);
    selectionkey::settle();
    auto *const table = view.findChild<QTableView *>(QStringLiteral("eventListTable"));
    QVERIFY2(table && table->isVisible(), "the event list table is unavailable");
    auto *const model = dynamic_cast<eventlist::EventTableModel *>(table->model());
    QVERIFY2(model != nullptr, "the event list model is missing");
    const int rows = model->rowCount();
    QVERIFY2(rows >= 4, "the event-list fixture has too few rows");
    const int copyBefore = m_counts.copy;

    // Row navigation stays table-local.
    table->setFocus(Qt::OtherFocusReason);
    selectionkey::settle();
    table->setCurrentIndex(model->index(0, 0));
    selectionkey::settle();
    QTest::keyClick(table, Qt::Key_Down);
    selectionkey::settle();
    QCOMPARE(table->currentIndex().row(), 1);
    QTest::keyClick(table, Qt::Key_Up);
    selectionkey::settle();
    QCOMPARE(table->currentIndex().row(), 0);

    // Select All stays local to the table rows.
    QTest::keyClick(table, Qt::Key_A, Qt::ControlModifier);
    selectionkey::settle();
    QCOMPARE(table->selectionModel()->selectedRows().count(), rows);

    // The registered reorder binding swaps adjacent rows without changing the
    // event set.
    const auto moveUp = selectionkey::firstBinding(QStringLiteral("eventlist.move_up"));
    QVERIFY2(moveUp.has_value(), "eventlist.move_up has no single binding");
    const int totalBefore = totalEvents(document);
    const QString row0Before = rowSummary(model, 0);
    const QString row1Before = rowSummary(model, 1);
    table->setCurrentIndex(model->index(1, 0));
    selectionkey::settle();
    QTest::keyClick(table, moveUp->key(), moveUp->keyboardModifiers());
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
    QTest::keyClick(table, copy->key(), copy->keyboardModifiers());
    selectionkey::settle();
    QCOMPARE(m_counts.copy, copyBefore + 1);

    // Delete removes the selected rows; a note that is selected in the song
    // but whose row is not selected must survive untouched.
    const std::optional<NoteRef> protectedNote = addNote(kTrack, kProtectedTick, 60, 48);
    QVERIFY2(protectedNote.has_value(),
             "the reserved tick-6720 protected note could not be inserted and resolved");
    selectionkey::settle();
    const uint64_t protectedEndTick = protectedNote->note.tick + protectedNote->note.duration;
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
    // Victims need a table-unique tick so the post-delete scan cannot be
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
    // Select All ran earlier and every document refresh restores multi-row
    // selections (EventListView::refresh re-selects captured rows after each
    // model reset), so drop whatever selection survived before staging the
    // two victims — otherwise Delete would remove every selected raw event.
    table->selectionModel()->clearSelection();
    selectionkey::settle();
    QItemSelection selection;
    for (const int row : victimRows)
        selection.select(model->index(row, 0), model->index(row, model->columnCount() - 1));
    table->selectionModel()->select(selection,
                                    QItemSelectionModel::Select | QItemSelectionModel::Rows);
    selectionkey::settle();
    view.selectionModel().setNoteSelection({protectedNote->id});

    const int rowsBeforeDelete = model->rowCount();
    const int totalBeforeDelete = totalEvents(document);
    QTest::keyClick(table, Qt::Key_Delete);
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
