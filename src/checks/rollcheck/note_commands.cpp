#include "checks/rollcheck/tst_pianoroll.h"

#include "checks/quickpopupguard.h"
#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"
#include "core/smf.h"
#include "core/songdocument.h"

#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QEvent>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest>

#include <algorithm>
#include <optional>
#include <vector>

using namespace checks::rollcheck;

namespace {

struct NoteMenuSession {
    songview::QuickPopupSession *session = nullptr;
    songview::QuickMenuModel *model = nullptr;
    QString diagnostic = QStringLiteral("the note menu did not open");
};

NoteMenuSession openNoteMenu(PianoRollFixture &check, const Cell &cell)
{
    NoteMenuSession menu;
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    checks::events::sendMouse(roll, QEvent::MouseButtonPress, cell.center, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease, cell.center, Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    const QPointer<songview::QuickPopupSession> live(quick_popup::popupSession(view));
    if (!QTest::qWaitFor([&live] {
            return live && live->isOpen() && quick_popup::menuPanel(*live) &&
                   quick_popup::menuModel(*quick_popup::menuPanel(*live)) != nullptr;
        })) {
        menu.diagnostic = QStringLiteral("the note right-click did not open the note menu");
        return menu;
    }
    menu.session = live;
    menu.model = quick_popup::menuModel(*quick_popup::menuPanel(*live));
    menu.diagnostic.clear();
    return menu;
}

int noteRow(songview::QuickMenuModel &model, songview::pianoroll_detail::NoteMenuAction action)
{
    return model.rowForId(int(action));
}

void sendCommandKey(songview::TimelineInputItem &roll, int key)
{
    sendKeyStroke(roll, key, Qt::ControlModifier, false);
}

int freeKeyAt(SongDocument &doc, int track, Tick tick)
{
    int key = 12;
    while (key < 128) {
        DocNote existing;
        if (!doc.findNote(track, tick, uint8_t(key), &existing))
            break;
        ++key;
    }
    return key;
}

void unwindTo(SongDocument &doc, int undo, const QByteArray &before)
{
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

// Snap-aligned seeds may start mid-grid-cell; align before growing to three cells.
std::optional<DocNote> gridAlignedThreeCells(PianoRollFixture &check, const ResizeFixture &seed,
                                             QString *diagnostic)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const int track = check.track();
    const Cell &d = seed.cell;
    DocNote source;
    if (!doc.findNote(track, d.tick, uint8_t(d.key), &source)) {
        *diagnostic = QStringLiteral("the grid-aligned split seed was not found");
        return std::nullopt;
    }
    const Tick grid = view.grid().gridTicksAt(d.tick);
    if (source.duration != grid) {
        *diagnostic = QStringLiteral("the split seed is not one visible grid cell");
        return std::nullopt;
    }
    const songview::Grid::Segment segment = view.grid().segmentAt(d.tick);
    const Tick start =
        Tick(uint64_t(segment.start) + (uint64_t(d.tick) - segment.start) / grid * grid);
    if (start != d.tick && (doc.moveNotes({source}, int64_t(start) - int64_t(d.tick), 0),
                            !doc.findNote(track, start, uint8_t(d.key), &source))) {
        *diagnostic = QStringLiteral("the split seed did not move onto a grid line");
        return std::nullopt;
    }
    doc.resizeNotes({source}, int64_t(3 * grid) - int64_t(source.duration));
    if (!doc.findNote(track, start, uint8_t(d.key), &source) || source.duration != 3 * grid) {
        *diagnostic = QStringLiteral("the split seed did not grow to three grid cells");
        return std::nullopt;
    }
    return source;
}

} // namespace

void PianoRollTest::keyboardDuplicateNotes()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const Cell &d = seed->cell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote source;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &source),
             "duplicate-notes seed note was not found");
    view.selectionModel().setNoteSelection({source.noteId});
    const int duplicateUndoIndex = doc.undoStack()->index();
    sendCommandKey(roll, Qt::Key_D);
    DocNote copy;
    QVERIFY2(doc.undoStack()->index() == duplicateUndoIndex + 1 &&
                 doc.findNote(track, source.tick + source.duration, uint8_t(d.key), &copy) &&
                 copy.duration == source.duration,
             "Ctrl+D did not duplicate the selected note one span later in one undo step");
    const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
    QVERIFY2(selection.size() == 1 && selection.front() == copy.noteId,
             "Ctrl+D did not reselect the duplicated copy");
    QVERIFY2(!view.selectionModel().timeSelection().active(),
             "note duplication leaked into the time selection");
    unwindTo(doc, undo, before);
}

void PianoRollTest::keyboardDuplicatePrefersTimeSelection()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const Cell &d = seed->cell;
    const Tick snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote source;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &source),
             "duplicate-precedence seed note was not found");
    view.selectionModel().setNoteSelection({source.noteId});
    view.selectionModel().setTimeSelection(
        {d.tick, d.tick + snapCell, songview::EditorSelectionModel::TimeSelection::Tracks});
    const int duplicateUndoIndex = doc.undoStack()->index();
    sendCommandKey(roll, Qt::Key_D);
    const songview::EditorSelectionModel::TimeSelection advanced =
        view.selectionModel().timeSelection();
    DocNote copy;
    QVERIFY2(doc.undoStack()->index() == duplicateUndoIndex + 1 && advanced.active() &&
                 advanced.startTick == d.tick + snapCell &&
                 advanced.endTick == d.tick + 2 * snapCell &&
                 doc.findNote(track, d.tick + snapCell, uint8_t(d.key), &copy) &&
                 view.editCursorTick() == d.tick + 2 * snapCell,
             "Ctrl+D with both selections did not run the time-range arm");
    unwindTo(doc, undo, before);
}

void PianoRollTest::keyboardSplitNotesGrid()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const uint8_t key = uint8_t(seed->cell.key);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    QString seedDiagnostic;
    const std::optional<DocNote> alignedSeed = gridAlignedThreeCells(check, *seed, &seedDiagnostic);
    QVERIFY2(alignedSeed.has_value(), qUtf8Printable(seedDiagnostic));
    const DocNote &source = *alignedSeed;
    const Tick start = source.tick;
    const Tick grid = view.grid().gridTicksAt(start);
    view.selectionModel().setNoteSelection({source.noteId});
    const int splitUndoIndex = doc.undoStack()->index();
    sendCommandKey(roll, Qt::Key_E);
    DocNote piece;
    QVERIFY2(doc.undoStack()->index() == splitUndoIndex + 1 &&
                 doc.findNote(track, start, key, &piece) && piece.duration == grid &&
                 doc.findNote(track, start + grid, key, &piece) && piece.duration == grid &&
                 doc.findNote(track, start + 2 * grid, key, &piece) && piece.duration == grid,
             "Ctrl+E did not split the selected note into grid pieces in one undo step");
    const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
    QVERIFY2(selection.size() == 3, "Ctrl+E did not reselect every split piece");
    for (NoteId id : selection) {
        QVERIFY2(doc.findNote(id, &piece) && piece.tick >= start && piece.tick < start + 3 * grid,
                 "the split selection contains a note outside the fragments");
    }
    unwindTo(doc, undo, before);
}

void PianoRollTest::keyboardSplitAtEditCursor()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const Cell &d = seed->cell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote source;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &source),
             "split-cursor seed note was not found");
    const Tick cursorTick = d.tick + source.duration / 2;
    view.setEditCursorTick(cursorTick);
    const int splitUndoIndex = doc.undoStack()->index();
    sendCommandKey(roll, Qt::Key_E);
    DocNote piece;
    QVERIFY2(doc.undoStack()->index() == splitUndoIndex + 1 &&
                 doc.findNote(track, d.tick, uint8_t(d.key), &piece) &&
                 piece.duration == cursorTick - d.tick &&
                 doc.findNote(track, cursorTick, uint8_t(d.key), &piece) &&
                 piece.duration == uint32_t(source.duration - (cursorTick - d.tick)),
             "Ctrl+E did not split the unselected note at the edit cursor in one undo step");
    unwindTo(doc, undo, before);
}

void PianoRollTest::keyboardSplitNoop()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const Cell &d = seed->cell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.selectionModel().clearNoteSelection();
    // Park the edit cursor past the seeded note's end so no note straddles it.
    view.setEditCursorTick(d.tick + 2 * d.dur);
    sendCommandKey(roll, Qt::Key_E);
    QCOMPARE(doc.undoStack()->index(), undo);
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::keyboardJoinNotes()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const Cell &d = seed->cell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote first;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &first), "join seed note was not found");
    const Tick secondTick = d.tick + 2 * first.duration;
    doc.addNotes(track, {{secondTick, uint8_t(d.key), first.duration, first.velocity}});
    DocNote second;
    QVERIFY2(doc.findNote(track, secondTick, uint8_t(d.key), &second),
             "the second join note did not land");
    view.selectionModel().setNoteSelection({first.noteId, second.noteId});
    const int joinUndoIndex = doc.undoStack()->index();
    sendCommandKey(roll, Qt::Key_J);
    DocNote joined;
    QVERIFY2(doc.undoStack()->index() == joinUndoIndex + 1 &&
                 doc.findNote(track, d.tick, uint8_t(d.key), &joined) &&
                 joined.duration == uint32_t(secondTick - d.tick) + first.duration,
             "Ctrl+J did not join the selected notes into one span in one undo step");
    QVERIFY2(!doc.findNote(track, secondTick, uint8_t(d.key), &joined),
             "Ctrl+J left the second note behind");
    const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
    QVERIFY2(selection.size() == 1 && selection.front() == joined.noteId,
             "Ctrl+J did not reselect the joined note");
    unwindTo(doc, undo, before);
}

// Joining one pitch must preserve other selected groups' identities and open ends.
void PianoRollTest::keyboardJoinMixedSpread()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const Cell &d = seed->cell;
    const Tick grid = uint32_t(d.dur);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();

    DocNote first;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &first),
             "the mixed-join seed note was not found");
    const Tick pairEndTick = d.tick + 2 * grid;
    doc.addNotes(track, {{pairEndTick, uint8_t(d.key), grid, 44}});
    DocNote second;
    QVERIFY2(doc.findNote(track, pairEndTick, uint8_t(d.key), &second),
             "the mixed-join pair partner did not land");

    const Tick singletonTick = d.tick + grid;
    const uint8_t singletonKey = uint8_t(d.key == 24 ? 25 : 24);
    doc.addNote(track, singletonTick, singletonKey, grid, 55);
    DocNote singleton;
    QVERIFY2(doc.findNote(track, singletonTick, singletonKey, &singleton),
             "the mixed-join singleton did not land");

    // A raw note-on detects accidental end synthesis when rebuilding skipped groups.
    const Tick openTick = d.tick + 8 * grid;
    const int openKeyInt = freeKeyAt(doc, track, openTick);
    QVERIFY2(openKeyInt < 128, "no free pitch for the unterminated join group");
    const uint8_t openKey = uint8_t(openKeyInt);
    const uint8_t openChannel = doc.channelFor(track);
    SmfEvent openOn;
    openOn.tick = openTick;
    openOn.status = uint8_t(0x90 | openChannel);
    openOn.data0 = openKey;
    openOn.data1 = 66;
    doc.insertRawEvent(doc.smfTrackFor(track), openOn);
    DocNote open;
    QVERIFY2(doc.findNote(track, openTick, openKey, &open) && open.unterminated(),
             "the unterminated join group did not land");

    view.selectionModel().setNoteSelection(
        {first.noteId, second.noteId, singleton.noteId, open.noteId});
    const int joinUndoIndex = doc.undoStack()->index();
    sendCommandKey(roll, Qt::Key_J);

    DocNote joined;
    QVERIFY2(doc.undoStack()->index() == joinUndoIndex + 1 &&
                 doc.findNote(track, d.tick, uint8_t(d.key), &joined) &&
                 joined.duration == 3 * grid && joined.velocity == first.velocity,
             "Ctrl+J did not join the same-key pair into one span with the first velocity");
    QVERIFY2(!doc.findNote(track, pairEndTick, uint8_t(d.key), &joined),
             "Ctrl+J left the pair partner behind");
    DocNote singletonAfter;
    QVERIFY2(doc.findNote(track, singletonTick, singletonKey, &singletonAfter) &&
                 singletonAfter.noteId == singleton.noteId &&
                 singletonAfter.duration == singleton.duration &&
                 singletonAfter.velocity == singleton.velocity,
             "Ctrl+J changed the different-key singleton or lost its identity");
    DocNote openAfter;
    QVERIFY2(doc.findNote(track, openTick, openKey, &openAfter) && openAfter.unterminated(),
             "Ctrl+J synthesized a note end for the unterminated singleton");
    const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
    QVERIFY2(selection.size() == 3 &&
                 std::find(selection.begin(), selection.end(), joined.noteId) != selection.end(),
             "Ctrl+J did not reselect the joined and surviving notes");

    unwindTo(doc, undo, before);
}

// Both split arms share one undo; only selected-source fragments inherit selection.
void PianoRollTest::keyboardSplitSelectedPlusCursorStraddler()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const Cell &d = seed->cell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();

    QString seedDiagnostic;
    const std::optional<DocNote> alignedSeed = gridAlignedThreeCells(check, *seed, &seedDiagnostic);
    QVERIFY2(alignedSeed.has_value(), qUtf8Printable(seedDiagnostic));
    const DocNote &source = *alignedSeed;
    const Tick start = source.tick;
    const Tick grid = view.grid().gridTicksAt(start);
    const Tick straddlerTick = start + 12 * grid;
    const uint8_t straddlerKey = uint8_t(d.key == 24 ? 25 : 24);
    doc.addNote(track, straddlerTick, straddlerKey, uint32_t(2 * grid), 90);
    DocNote straddler;
    QVERIFY2(doc.findNote(track, straddlerTick, straddlerKey, &straddler),
             "the cursor straddler did not land");

    const Tick bystanderTick = straddlerTick + 5 * grid;
    const uint8_t bystanderKey = uint8_t(d.key == 30 ? 31 : 30);
    doc.addNote(track, bystanderTick, bystanderKey, grid, 82);
    DocNote bystander;
    QVERIFY2(doc.findNote(track, bystanderTick, bystanderKey, &bystander),
             "the untouched bystander note did not land");

    const Tick cursorTick = straddlerTick + grid;
    view.setEditCursorTick(cursorTick);
    view.selectionModel().setNoteSelection({source.noteId, bystander.noteId});

    const int splitUndoIndex = doc.undoStack()->index();
    sendCommandKey(roll, Qt::Key_E);

    DocNote piece;
    QVERIFY2(doc.undoStack()->index() == splitUndoIndex + 1,
             "Ctrl+E did not land as exactly one undo step");
    for (int offset = 0; offset < 3; ++offset) {
        QVERIFY2(doc.findNote(track, start + offset * grid, uint8_t(d.key), &piece) &&
                     piece.duration == grid,
                 "Ctrl+E did not split the selected source along its grid lines");
    }
    QVERIFY2(doc.findNote(track, straddlerTick, straddlerKey, &piece) && piece.duration == grid,
             "Ctrl+E did not keep the straddler's left half in place");
    QVERIFY2(doc.findNote(track, cursorTick, straddlerKey, &piece) && piece.duration == grid,
             "Ctrl+E did not split the straddler at the edit cursor");
    const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
    QVERIFY2(selection.size() == 4 &&
                 std::find(selection.begin(), selection.end(), bystander.noteId) != selection.end(),
             "Ctrl+E did not keep exactly the source fragments plus the bystander selected");
    for (NoteId id : selection) {
        if (id == bystander.noteId)
            continue;
        QVERIFY2(doc.findNote(id, &piece) && piece.key == uint8_t(d.key) && piece.tick >= start &&
                     piece.tick < start + 3 * grid,
                 "the combined-split selection contains a note outside the source fragments");
    }
    DocNote untouched;
    QVERIFY2(doc.findNote(track, bystanderTick, bystanderKey, &untouched) &&
                 untouched.noteId == bystander.noteId && untouched.duration == grid &&
                 untouched.velocity == 82,
             "Ctrl+E disturbed the also-selected bystander note");
    unwindTo(doc, undo, before);
}

void PianoRollTest::keyboardNoteCommandPopupActivation_data()
{
    QTest::addColumn<int>("action");

    QTest::newRow("duplicate") << int(songview::pianoroll_detail::NoteMenuAction::Duplicate);
    QTest::newRow("split") << int(songview::pianoroll_detail::NoteMenuAction::Split);
    QTest::newRow("join") << int(songview::pianoroll_detail::NoteMenuAction::Join);
}

void PianoRollTest::keyboardNoteCommandPopupActivation()
{
    QFETCH(int, action);
    const auto command = songview::pianoroll_detail::NoteMenuAction(action);

    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const int track = check.track();
    const Cell &d = seed->cell;
    const quick_popup::PromptGuard guard(view);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();

    QString seedDiagnostic;
    // Keep the playhead past the fixtures to isolate selected-note splitting.
    DocNote source;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &source),
             "the popup-activation seed note was not found");
    const Tick grid = view.grid().gridTicksAt(d.tick);
    const Tick secondTick = d.tick + 2 * grid;
    if (command == songview::pianoroll_detail::NoteMenuAction::Split) {
        const std::optional<DocNote> alignedSeed =
            gridAlignedThreeCells(check, *seed, &seedDiagnostic);
        QVERIFY2(alignedSeed.has_value(), qUtf8Printable(seedDiagnostic));
        source = *alignedSeed;
    } else if (command == songview::pianoroll_detail::NoteMenuAction::Join) {
        doc.addNotes(track, {{secondTick, uint8_t(d.key), grid, source.velocity}});
        DocNote partner;
        QVERIFY2(doc.findNote(track, secondTick, uint8_t(d.key), &partner),
                 "the popup-join partner did not land");
        view.selectionModel().setNoteSelection({source.noteId, partner.noteId});
    }
    if (command != songview::pianoroll_detail::NoteMenuAction::Join)
        view.selectionModel().setNoteSelection({source.noteId});
    view.setPlayheadSample(check.timeline().sampleForTick(d.tick + 6 * grid), true);

    const NoteMenuSession opened = openNoteMenu(check, d);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
    const int row = noteRow(*opened.model, command);
    QVERIFY2(row >= 0, "the note menu lost the command's typed row");
    const int commandUndoIndex = doc.undoStack()->index();
    QVERIFY2(quick_popup::clickMenuRow(*opened.session, row),
             "the command's note menu row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(opened.session && !opened.session->isOpen(),
             "the command's note menu activation left the menu open");

    DocNote observed;
    if (command == songview::pianoroll_detail::NoteMenuAction::Duplicate) {
        QVERIFY2(doc.findNote(track, d.tick + source.duration, uint8_t(d.key), &observed) &&
                     observed.duration == source.duration,
                 "the Duplicate row did not duplicate the selected note one span later");
        const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
        QVERIFY2(selection.size() == 1 && selection.front() == observed.noteId,
                 "the Duplicate row did not reselect the copy");
    } else if (command == songview::pianoroll_detail::NoteMenuAction::Split) {
        const Tick start = source.tick;
        for (int offset = 0; offset < 3; ++offset) {
            QVERIFY2(doc.findNote(track, start + offset * grid, uint8_t(d.key), &observed) &&
                         observed.duration == grid,
                     "the Split row did not split the note into grid pieces");
        }
        const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
        QVERIFY2(selection.size() == 3, "the Split row did not keep every piece selected");
    } else {
        QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &observed) &&
                     observed.duration == 3 * grid,
                 "the Join row did not join the same-key pair into one span");
        QVERIFY2(!doc.findNote(track, secondTick, uint8_t(d.key), &observed),
                 "the Join row left the second note behind");
        const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
        QVERIFY2(selection.size() == 1, "the Join row did not leave only the joined note selected");
    }
    QVERIFY2(doc.undoStack()->index() == commandUndoIndex + 1,
             "the popup activation did not land as exactly one undo step");

    unwindTo(doc, undo, before);
}
