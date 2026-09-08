#include "checks/rollcheck/tst_pianoroll.h"

#include "checks/quickpopupguard.h"
#include "checks/rollcheck/headerchecksupport.h"
#include "checks/rollcheck/rollcheck.h"

#include <QByteArray>
#include <QColor>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QKeyEvent>
#include <QPoint>
#include <QPointer>
#include <QRectF>
#include <QScopeGuard>
#include <QtTest>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

using namespace checks::rollcheck;

void PianoRollTest::keyboardTranspose()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const SnappedRows rows{view, roll};
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const QPoint center(
        qRound(view.camera().displayX(double(d.tick) + 0.5 * double(snapCell), 0.0, rows.dpr())),
        rows.centerY(d.key));
    click(roll, center);
    sendKeyStroke(roll, Qt::Key_Up, Qt::NoModifier, false);
    DocNote note;
    QVERIFY2(doc.findNote(check.track(), d.tick, uint8_t(d.key + 1), &note),
             "Up did not transpose up a semitone");
    sendKeyStroke(roll, Qt::Key_Down, Qt::ShiftModifier, false);
    QVERIFY2(doc.findNote(check.track(), d.tick, uint8_t(d.key - 11), &note),
             "Shift+Down did not transpose down an octave");
    sendKeyStroke(roll, Qt::Key_Right, Qt::NoModifier, false);
    QVERIFY2(doc.findNote(check.track(), d.tick + snapCell, uint8_t(d.key - 11), &note),
             "Right did not nudge one snap cell right");
    doc.moveNotes({note}, int64_t(snapCell / 2), 0);
    view.selectionModel().setNoteSelection({note.noteId});
    sendKeyStroke(roll, Qt::Key_Left, Qt::NoModifier, false);
    QVERIFY2(doc.findNote(check.track(), d.tick + snapCell, uint8_t(d.key - 11), &note),
             "Left did not snap the off-grid note back to the grid");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::keyboardKeepVisible()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    constexpr uint64_t kNoteTicks = 12; // resize fixture's two six-tick cells
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote transposed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &transposed),
             "keyboard keep-visible seed note was not found");
    doc.moveNotes({transposed}, int64_t(snapCell), -11);
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 11), &transposed),
             "keyboard keep-visible seed did not reach the expected post-transpose state");
    view.selectionModel().setNoteSelection({transposed.noteId});

    const int keyNow = d.key - 11;
    const int currentRow = view.pitchProjection().rowForPitch(keyNow);
    const int upRow = view.pitchProjection().rowForPitch(keyNow + 1);
    QVERIFY2(currentRow != songview::PitchProjection::cHiddenRow &&
                 upRow != songview::PitchProjection::cHiddenRow,
             "keyboard keep-visible pitches are not in the current projection");
    view.selectionModel().setNoteSelection({transposed.noteId});
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason),
             "Quick roll input could not be focused before keyboard keep-visible");
    QTRY_VERIFY(roll.hasActiveFocus());
    const qreal rowDpr = roll.devicePixelRatio();
    view.scrollRollBy((currentRow + 2) * view.camera().keyHeight() - view.camera().scrollY());
    QVERIFY2(view.pitchProjection().rowBottom(currentRow, view.camera().keyHeight(),
                                              view.camera().scrollY(), rowDpr) <= 0.0,
             "could not park the note's projected row above the viewport");
    sendKeyStroke(roll, Qt::Key_Up, Qt::NoModifier, false);
    DocNote movedUp;
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(keyNow + 1), &movedUp),
             "Up was not delivered to the selected keep-visible note");
    QCOMPARE(movedUp.duration, uint32_t(kNoteTicks));
    const qreal displayedUpTop = view.pitchProjection().rowTop(upRow, view.camera().keyHeight(),
                                                               view.camera().scrollY(), rowDpr);
    QVERIFY2(std::abs(displayedUpTop) <= 1e-9,
             "Up above the viewport did not scroll the projected row flush to the top");
    sendKeyStroke(roll, Qt::Key_Down, Qt::NoModifier, false);

    uint64_t nStart = d.tick + snapCell;
    const qreal dpr = roll.devicePixelRatio();
    const qreal physicalPixel = dpr > 0.0 ? 1.0 / dpr : 1.0;
    view.scrollByPx(view.camera().contentX(double(nStart + kNoteTicks)) + 40);
    QVERIFY2(view.camera().displayX(double(nStart + kNoteTicks), 0.0, dpr) < 0.0,
             "could not park the full note past the left edge");
    sendKeyStroke(roll, Qt::Key_Right, Qt::NoModifier, false);
    nStart += snapCell;
    QCOMPARE(view.camera().displayX(double(nStart), 0.0, dpr), 0.0);
    const qreal vw = std::max<qreal>(50, roll.width());
    const qreal cellPx =
        view.camera().contentX(double(nStart + snapCell)) - view.camera().contentX(double(nStart));
    const int rides = (vw - view.camera().contentX(double(nStart + kNoteTicks))) / cellPx + 2;
    for (int i = 0; i < rides; ++i)
        sendKeyStroke(roll, Qt::Key_Right, Qt::NoModifier, false);
    nStart += uint64_t(rides) * snapCell;
    QVERIFY2(doc.findNote(track, nStart, uint8_t(keyNow), &transposed),
             "Right did not nudge the selected note to the expected tick");
    QCOMPARE(view.camera().displayX(double(nStart + kNoteTicks), 0.0, dpr), vw - physicalPixel);
    for (int i = 0; i < rides + 1; ++i)
        sendKeyStroke(roll, Qt::Key_Left, Qt::NoModifier, false);
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 11), &transposed) &&
                 transposed.duration == kNoteTicks,
             "the ride right and back did not return the full note home");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

namespace {

// Every non-duration field a resize must preserve.
bool sameButDuration(const DocNote &before, const DocNote &after)
{
    return before.noteId == after.noteId && before.engineTrack == after.engineTrack &&
           before.smfTrack == after.smfTrack && before.tick == after.tick &&
           before.key == after.key && before.velocity == after.velocity &&
           before.channel == after.channel;
}

void undoToFixture(SongDocument &doc, const QByteArray &bytes, int baseIndex)
{
    while (doc.undoStack()->index() > baseIndex && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), bytes);
}

void expectConsumedNoCommand(SongDocument &doc, const QByteArray &bytes, int baseIndex,
                             int baseCount)
{
    QCOMPARE(doc.undoStack()->index(), baseIndex);
    QCOMPARE(doc.undoStack()->count(), baseCount);
    QCOMPARE(doc.smf().write(), bytes);
}

// One production Shift+Arrow keystroke into the roll's Quick input item.
// The shared Timeline policy accepts a recognized command exactly once —
// including a consumed no-op — and ignores unclaimed keys, so the press's
// acceptance bit is asserted on every delivery; sendKeyStroke() hides it.
void pressResizeKey(songview::TimelineInputItem &roll, bool longer)
{
    const int key = longer ? Qt::Key_Right : Qt::Key_Left;
    QKeyEvent press(QEvent::KeyPress, key, Qt::ShiftModifier, QString(), false, 1);
    QCoreApplication::sendEvent(&roll, &press);
    const bool accepted = press.isAccepted();
    QKeyEvent release(QEvent::KeyRelease, key, Qt::ShiftModifier, QString(), false, 1);
    QCoreApplication::sendEvent(&roll, &release);
    QVERIFY2(accepted, longer ? "the Shift+Right lengthen press was not accepted"
                              : "the Shift+Left shorten press was not accepted");
}

// Highest piano key whose occupancy window is clear for the probe ticks
// after tick; nullopt when every key is taken. The one free-key scan —
// stageNote and the raw-event seeds below all share it.
std::optional<int> findFreeKey(PianoRollFixture &check, uint64_t tick, uint64_t probe)
{
    for (int key = 115; key >= 24; --key) {
        if (!check.isOccupied(tick, probe, key, true))
            return key;
    }
    return std::nullopt;
}

// Seeds one note at an exact tick on a visibly free key. The occupancy probe
// is capped so the one-cell resizes below cannot run into a neighbor the
// scan did not see.
std::optional<DocNote> stageNote(PianoRollFixture &check, uint64_t tick, uint32_t duration)
{
    const uint64_t probe = std::clamp<uint64_t>(duration, 24, 48);
    const std::optional<int> key = findFreeKey(check, tick, probe);
    if (!key.has_value())
        return std::nullopt;
    check.document().addNote(check.track(), tick, uint8_t(*key), duration, 100);
    DocNote note;
    if (check.document().findNote(check.track(), tick, uint8_t(*key), &note) &&
        note.duration == duration)
        return note;
    return std::nullopt;
}

// Seeds a note whose start and end sit on an absolute cell boundary of the
// given lattice, probing candidate cells near the fixture's working region.
std::optional<DocNote> stageLatticeNote(PianoRollFixture &check, uint64_t lattice,
                                        uint32_t duration, uint64_t nearTick)
{
    const uint64_t first = std::max<uint64_t>(lattice, (nearTick / lattice) * lattice);
    for (uint64_t tick = first; tick < first + 4 * lattice; tick += lattice) {
        if (auto note = stageNote(check, tick, duration))
            return note;
    }
    return std::nullopt;
}

} // namespace

// Semantic Lengthen/Shorten Note coverage (plan 6.2). Every press travels
// the production route — a Shift+Arrow QKeyEvent into the focused roll
// Quick input item, through the shared Timeline policy and its guarded
// SongView seam — so route acceptance and document semantics are pinned
// together. Each scenario closes by undoing back to a byte-identical
// fixture state.
void PianoRollTest::keyboardResize()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    const uint64_t kCell = seed->snapCell; // the fixture's canonical cell
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    // The presses below land on the roll's focused Quick input item, so the
    // shared policy resolves them exactly as a real keystroke would.
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason),
             "Quick roll input could not be focused before keyboard resize");
    QTRY_VERIFY(roll.hasActiveFocus());
    const int track = check.track();
    const uint64_t base = seed->cell.tick; // on the six-tick lattice
    DocNote seedNote;
    QVERIFY2(doc.findNote(track, base, uint8_t(seed->cell.key), &seedNote) &&
                 seedNote.duration == 2 * kCell,
             "the resize seed note was not found");

    // Aligned end: lengthen advances one cell, shorten returns it (6.2.1).
    {
        view.selectionModel().setNoteSelection({seedNote.noteId});
        const QByteArray bytes = doc.smf().write();
        const int baseIndex = doc.undoStack()->index();
        pressResizeKey(roll, true);
        DocNote note;
        QVERIFY2(doc.findNote(track, base, uint8_t(seed->cell.key), &note) &&
                     note.duration == 3 * kCell,
                 "lengthening an aligned end did not advance exactly one cell");
        pressResizeKey(roll, false);
        QVERIFY2(doc.findNote(track, base, uint8_t(seed->cell.key), &note) &&
                     note.duration == 2 * kCell,
                 "shortening the aligned end did not return it one cell");
        undoToFixture(doc, bytes, baseIndex);
    }

    // Identity and selection: the start and every non-duration field stay
    // put and the selected NoteIds stay selected in both directions (6.2.5).
    {
        const DocNote before = seedNote;
        view.selectionModel().setNoteSelection({before.noteId});
        const QByteArray bytes = doc.smf().write();
        const int baseIndex = doc.undoStack()->index();
        pressResizeKey(roll, true);
        DocNote note;
        QVERIFY2(doc.findNote(before.noteId, &note) && note.duration == 3 * kCell &&
                     sameButDuration(before, note) &&
                     view.selectionModel().noteSelection() == std::vector<NoteId>{before.noteId},
                 "lengthening changed more than the duration or dropped the selection");
        pressResizeKey(roll, false);
        QVERIFY2(doc.findNote(before.noteId, &note) && note.duration == 2 * kCell &&
                     sameButDuration(before, note) &&
                     view.selectionModel().noteSelection() == std::vector<NoteId>{before.noteId},
                 "shortening changed more than the duration or dropped the selection");
        undoToFixture(doc, bytes, baseIndex);
    }

    // Off-grid ends: each direction reaches the adjacent grid boundary, not
    // a fixed raw cell (6.2.2). The lengthen seed starts three ticks past a
    // boundary and ends one tick past the next, so a boundary step is +5
    // (raw cell +6); the shorten seed ends three ticks past a boundary, so a
    // boundary step is -3 (raw cell -6).
    {
        const std::optional<DocNote> offEnd = stageNote(check, base + kCell / 2, 4);
        const std::optional<DocNote> offShort = stageNote(check, base + 2 * kCell + 3, 12);
        QVERIFY2(offEnd.has_value() && offShort.has_value(), "no free keys for the off-grid seeds");
        view.selectionModel().setNoteSelection({offEnd->noteId});
        const QByteArray bytes = doc.smf().write();
        const int baseIndex = doc.undoStack()->index();
        pressResizeKey(roll, true);
        DocNote note;
        QVERIFY2(doc.findNote(offEnd->noteId, &note) && note.duration == 9,
                 "lengthening an off-grid end did not reach the next boundary");
        view.selectionModel().setNoteSelection({offShort->noteId});
        pressResizeKey(roll, false);
        QVERIFY2(doc.findNote(offShort->noteId, &note) && note.duration == 9,
                 "shortening an off-grid end did not reach the previous boundary");
        undoToFixture(doc, bytes, baseIndex);
    }

    // One-tick floor: shortening a one-tick note is a consumed no-op — no
    // mutation, no history entry, selection kept (6.2.3). Document inserts
    // floor duration to one tick, so a terminated note cannot be staged
    // shorter; this one-tick boundary is the smallest reachable shortening
    // case, and the clamp must never turn shortening into growth here.
    // Lengthening from the floor reaches the next live boundary: the floor
    // seed starts on the lattice with a one-tick duration, so the adjacent
    // boundary is exactly one live cell past its start, not three cells.
    {
        const std::optional<DocNote> floorNote = stageNote(check, base + 2 * kCell, 1);
        QVERIFY2(floorNote.has_value(), "no free key for the floor seed");
        view.selectionModel().setNoteSelection({floorNote->noteId});
        const QByteArray bytes = doc.smf().write();
        const int baseIndex = doc.undoStack()->index();
        const int baseCount = doc.undoStack()->count();
        pressResizeKey(roll, false);
        DocNote note;
        QVERIFY2(doc.findNote(floorNote->noteId, &note) && note.duration == 1 &&
                     view.selectionModel().noteSelection() ==
                         std::vector<NoteId>{floorNote->noteId},
                 "shortening a one-tick note mutated the document or selection");
        expectConsumedNoCommand(doc, bytes, baseIndex, baseCount);
        pressResizeKey(roll, true);
        // The live 1/16 cell, not the assumed constant: snapTicks determines
        // the actual step at this division.
        const uint64_t floorCell = view.grid().snapTicksAt(floorNote->tick);
        const uint64_t floorBoundary = view.grid().nextEditingTick(
            floorNote->tick + floorNote->duration, std::numeric_limits<uint64_t>::max());
        QVERIFY2(floorCell > 0 && floorBoundary > floorNote->tick &&
                     floorBoundary - floorNote->tick <= std::numeric_limits<uint32_t>::max(),
                 "the live grid offered no reachable lengthen boundary for the floor seed");
        QVERIFY2(doc.findNote(floorNote->noteId, &note) &&
                     note.duration == floorBoundary - floorNote->tick,
                 "lengthening the floor note did not reach the next boundary");
        undoToFixture(doc, bytes, baseIndex);
    }

    // Mixed selection: one shared delta from the furthest end (6.2.4). The
    // peers end at different alignments — a on the lattice, b three ticks
    // past it — and the shortest note clamps the second shorten to -2.
    {
        const std::optional<DocNote> a = stageNote(check, base + 4 * kCell, uint32_t(2 * kCell));
        const std::optional<DocNote> b = stageNote(check, base + 4 * kCell, 3);
        QVERIFY2(a.has_value() && b.has_value(), "no free keys for the mixed seeds");
        view.selectionModel().setNoteSelection({a->noteId, b->noteId});
        const QByteArray bytes = doc.smf().write();
        const int baseIndex = doc.undoStack()->index();
        pressResizeKey(roll, true);
        DocNote aNote;
        DocNote bNote;
        QVERIFY2(doc.findNote(a->noteId, &aNote) && aNote.duration == 3 * kCell &&
                     doc.findNote(b->noteId, &bNote) && bNote.duration == 9,
                 "lengthening did not move both mixed notes by the same boundary delta");
        pressResizeKey(roll, false);
        QVERIFY2(doc.findNote(a->noteId, &aNote) && aNote.duration == 2 * kCell &&
                     doc.findNote(b->noteId, &bNote) && bNote.duration == 3,
                 "shortening did not return both mixed notes by the same boundary delta");
        pressResizeKey(roll, false);
        QVERIFY2(doc.findNote(a->noteId, &aNote) && aNote.duration == 2 * kCell - 2 &&
                     doc.findNote(b->noteId, &bNote) && bNote.duration == 1,
                 "the shortest mixed note did not clamp the shared shortening delta");
        undoToFixture(doc, bytes, baseIndex);
    }

    // Live grid: the step is read from the grid selected at call time
    // (6.2.6); keyboard narrow/widen routing is covered by the grid suites.
    {
        const std::optional<DocNote> eighth =
            stageLatticeNote(check, 2 * kCell, uint32_t(2 * kCell), base);
        QVERIFY2(eighth.has_value(), "no free 1/8-lattice cell for the live-grid seed");
        const SongView::ViewState gridScenarioView = view.viewState();
        const auto restoreGrid =
            qScopeGuard([&view, gridScenarioView] { view.applyViewState(gridScenarioView); });
        view.setGridSelection(songview::GridSelection::musical(8));
        QCOMPARE(view.gridSelection(), songview::GridSelection::musical(8));
        view.selectionModel().setNoteSelection({eighth->noteId});
        const QByteArray bytes = doc.smf().write();
        const int baseIndex = doc.undoStack()->index();
        pressResizeKey(roll, true);
        DocNote note;
        QVERIFY2(doc.findNote(eighth->noteId, &note) && note.duration == 4 * kCell,
                 "the live 1/8 grid selection did not drive the lengthen step");
        undoToFixture(doc, bytes, baseIndex);
    }

    // Clock terminal: one ticksPerClock boundary on the absolute clock
    // lattice (6.2.7).
    {
        const uint32_t clockCell = doc.ticksPerClock();
        const std::optional<DocNote> clocked = stageLatticeNote(check, clockCell, clockCell, base);
        QVERIFY2(clocked.has_value(), "no free clock-lattice cell for the Clock seed");
        const SongView::ViewState gridScenarioView = view.viewState();
        const auto restoreGrid =
            qScopeGuard([&view, gridScenarioView] { view.applyViewState(gridScenarioView); });
        view.setGridSelection(songview::GridSelection::clock());
        QCOMPARE(view.gridSelection(), songview::GridSelection::clock());
        view.selectionModel().setNoteSelection({clocked->noteId});
        const QByteArray bytes = doc.smf().write();
        const int baseIndex = doc.undoStack()->index();
        pressResizeKey(roll, true);
        DocNote note;
        QVERIFY2(doc.findNote(clocked->noteId, &note) && note.duration == 2 * uint64_t(clockCell),
                 "the Clock grid did not lengthen by exactly one ticksPerClock boundary");
        undoToFixture(doc, bytes, baseIndex);
    }

    // Signature boundary: the first press lands exactly on the signature
    // boundary, the next press continues on the new segment's lattice
    // (6.2.8). The boundary sits on the live lattice inside the working
    // region with room for a note ending one tick before it: ticksPerClock
    // is 1 at this division, so ticksPerClock()*4 cannot stage the
    // thirteen-before/thirteen-after arithmetic the durations assert.
    {
        const QByteArray preSigBytes = doc.smf().write();
        const int preSigIndex = doc.undoStack()->index();
        const uint64_t signatureTick = base + 4 * kCell;
        doc.setTimeSig(signatureTick, 3, 2);
        QCoreApplication::processEvents(); // the timeline rebuilds the 3/4 segment
        const std::optional<DocNote> boundaryNote = stageNote(check, signatureTick - 13, 12);
        QVERIFY2(boundaryNote.has_value(), "no free key for the signature-boundary seed");
        view.selectionModel().setNoteSelection({boundaryNote->noteId});
        const QByteArray bytes = doc.smf().write();
        const int baseIndex = doc.undoStack()->index();
        pressResizeKey(roll, true);
        DocNote note;
        QVERIFY2(doc.findNote(boundaryNote->noteId, &note) && note.duration == 13,
                 "the first press did not land exactly on the signature boundary");
        pressResizeKey(roll, true);
        QVERIFY2(doc.findNote(boundaryNote->noteId, &note) && note.duration == 19,
                 "the next press did not follow the new segment's lattice");
        undoToFixture(doc, bytes, baseIndex);
        // setTimeSig and the boundary staging each pushed their own command
        // after the pre-signature snapshot; remove both so later scenarios
        // run under the opening 4/4 lattice again.
        while (doc.undoStack()->index() > preSigIndex && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
        QCoreApplication::processEvents(); // the timeline drops the undone 3/4 segment
        QCOMPARE(doc.smf().write(), preSigBytes);
    }

    // Active time selection: the command is a terminal no-op (6.2.9). The
    // selection model keeps the two selections exclusive in both directions:
    // staging a time selection clears the note selection, and
    // re-establishing a note selection clears the time selection — so the
    // band is re-armed last and the no-op probe runs with notes empty.
    {
        view.selectionModel().setNoteSelection({seedNote.noteId});
        songview::EditorSelectionModel::TimeSelection band;
        band.startTick = base;
        band.endTick = base + 4 * kCell;
        band.scope = songview::EditorSelectionModel::TimeSelection::Tracks;
        view.selectionModel().setTimeSelection(band);
        QVERIFY2(view.selectionModel().timeSelection().active() &&
                     view.selectionModel().noteSelection().empty(),
                 "staging a time selection did not clear the note selection");
        view.selectionModel().setNoteSelection({seedNote.noteId});
        QVERIFY2(view.selectionModel().noteSelection() == std::vector<NoteId>{seedNote.noteId} &&
                     !view.selectionModel().timeSelection().active(),
                 "re-establishing the note selection did not clear the time selection");
        view.selectionModel().setTimeSelection(band);
        QVERIFY2(view.selectionModel().timeSelection().active() &&
                     view.selectionModel().noteSelection().empty(),
                 "re-arming the time selection did not clear the note selection");
        const QByteArray bytes = doc.smf().write();
        const int baseIndex = doc.undoStack()->index();
        const int baseCount = doc.undoStack()->count();
        pressResizeKey(roll, true);
        pressResizeKey(roll, false);
        DocNote note;
        QVERIFY2(doc.findNote(seedNote.noteId, &note) && note.duration == 2 * kCell,
                 "the time-selected note was resized anyway");
        const songview::EditorSelectionModel::TimeSelection after =
            view.selectionModel().timeSelection();
        QVERIFY2(after.active() && after.startTick == band.startTick &&
                     after.endTick == band.endTick,
                 "the consumed resize command disturbed the time selection");
        expectConsumedNoCommand(doc, bytes, baseIndex, baseCount);
        view.selectionModel().clearTimeSelection();
        undoToFixture(doc, bytes, baseIndex);
    }

    // Unterminated selected note: the whole command is a consumed no-op and
    // the terminated peer stays byte-identical (6.2.10). The orphan note-on
    // is staged through the raw event seam — inserts floor duration to one
    // tick, so no staged note could fake an unterminated one.
    {
        const uint64_t orphanTick = base + 8 * kCell;
        const std::optional<int> orphanKey = findFreeKey(check, orphanTick, 24);
        QVERIFY2(orphanKey.has_value(), "no free key for the unterminated seed");
        SmfEvent orphanOn;
        orphanOn.tick = orphanTick;
        orphanOn.status = uint8_t(0x90 | (doc.channelFor(track) & 0x0F));
        orphanOn.data0 = uint8_t(*orphanKey);
        orphanOn.data1 = 100;
        doc.insertRawEvent(doc.smfTrackFor(track), orphanOn);
        DocNote orphan;
        QVERIFY2(doc.findNote(track, orphanTick, uint8_t(*orphanKey), &orphan) &&
                     orphan.unterminated(),
                 "the staged orphan note-on did not stay unterminated");
        view.selectionModel().setNoteSelection({seedNote.noteId, orphan.noteId});
        const QByteArray bytes = doc.smf().write();
        const int baseIndex = doc.undoStack()->index();
        const int baseCount = doc.undoStack()->count();
        pressResizeKey(roll, true);
        pressResizeKey(roll, false);
        DocNote seedAfter;
        DocNote orphanAfter;
        const std::vector<NoteId> &kept = view.selectionModel().noteSelection();
        const auto keeps = [&kept](NoteId id) {
            return std::find(kept.cbegin(), kept.cend(), id) != kept.cend();
        };
        QVERIFY2(doc.findNote(seedNote.noteId, &seedAfter) && seedAfter.duration == 2 * kCell &&
                     doc.findNote(orphan.noteId, &orphanAfter) && orphanAfter.unterminated() &&
                     kept.size() == 2 && keeps(seedNote.noteId) && keeps(orphan.noteId),
                 "an unterminated selected note did not consume the whole command");
        expectConsumedNoCommand(doc, bytes, baseIndex, baseCount);
    }
    // Terminated zero-duration selected note: shortening is a consumed
    // no-op and the whole selection stays byte-identical (thermoPhaseTwo
    // B2). The zero note is staged through the raw event seam — addNote
    // floors duration to one tick, so no staged note could fake a zero —
    // as a same-tick note-on/off pair. Canonical placement pins a
    // same-tick note-end ahead of its note-on, so the inserts land
    // [off, on]; two same-tick modifyRawEvent edits keep vector position
    // and flip the bytes to the file-faithful [on, off] order the
    // lifecycle fixture preserves (note_lifecycle.mid tick 72). Without
    // the non-positive shortening clamp this Shift+Left press would
    // lengthen the selection by one tick (1 - minDuration with a zero
    // shortest note); with it the shared delta is exactly zero.
    {
        const uint64_t zeroTick = base + 10 * kCell;
        const std::optional<int> zeroKey = findFreeKey(check, zeroTick, 24);
        QVERIFY2(zeroKey.has_value(), "no free key for the zero-duration seed");
        const uint8_t channel = doc.channelFor(track);
        SmfEvent zeroOn;
        zeroOn.tick = zeroTick;
        zeroOn.status = uint8_t(0x90 | (channel & 0x0F));
        zeroOn.data0 = uint8_t(*zeroKey);
        zeroOn.data1 = 100;
        SmfEvent zeroOff;
        zeroOff.tick = zeroTick;
        zeroOff.status = uint8_t(0x80 | (channel & 0x0F));
        zeroOff.data0 = uint8_t(*zeroKey);
        zeroOff.data1 = 0;
        const int smfTrack = doc.smfTrackFor(track);
        doc.insertRawEvent(smfTrack, zeroOn);
        doc.insertRawEvent(smfTrack, zeroOff);
        std::optional<size_t> offIndex;
        std::optional<size_t> onIndex;
        for (size_t i = 0; i < doc.smf().tracks[size_t(smfTrack)].events.size(); ++i) {
            const SmfEvent &event = doc.smf().tracks[size_t(smfTrack)].events[i];
            if (event.tick != zeroTick || event.data0 != uint8_t(*zeroKey))
                continue;
            if (event.status == zeroOff.status && event.data1 == 0)
                offIndex = i;
            else if (event.status == zeroOn.status && event.data1 == 100)
                onIndex = i;
        }
        QVERIFY2(offIndex.has_value() && onIndex.has_value(),
                 "the staged zero-duration pair was not found");
        doc.modifyRawEvent(smfTrack, *offIndex, zeroOn);
        doc.modifyRawEvent(smfTrack, *onIndex, zeroOff);
        DocNote zero;
        QVERIFY2(doc.findNote(track, zeroTick, uint8_t(*zeroKey), &zero) && !zero.unterminated() &&
                     zero.duration == 0,
                 "the staged same-tick pair did not stay terminated duration0");
        view.selectionModel().setNoteSelection({seedNote.noteId, zero.noteId});
        const QByteArray bytes = doc.smf().write();
        const int baseIndex = doc.undoStack()->index();
        const int baseCount = doc.undoStack()->count();
        pressResizeKey(roll, false);
        DocNote seedAfter;
        DocNote zeroAfter;
        const std::vector<NoteId> &kept = view.selectionModel().noteSelection();
        const auto keeps = [&kept](NoteId id) {
            return std::find(kept.cbegin(), kept.cend(), id) != kept.cend();
        };
        QVERIFY2(doc.findNote(seedNote.noteId, &seedAfter) && seedAfter.duration == 2 * kCell &&
                     sameButDuration(seedNote, seedAfter) &&
                     doc.findNote(zero.noteId, &zeroAfter) && !zeroAfter.unterminated() &&
                     zeroAfter.duration == 0 && sameButDuration(zero, zeroAfter) &&
                     kept.size() == 2 && keeps(seedNote.noteId) && keeps(zero.noteId),
                 "shortening a selection with a terminated zero-duration note was not a no-op");
        expectConsumedNoCommand(doc, bytes, baseIndex, baseCount);
    }

    // uint32 duration ceiling: a lengthen that would push a terminated
    // note's duration past 32 bits is consumed without touching the
    // document or history (regression for the resize-boundary guard). The
    // staged note exists only in memory; the SMF delta encoding would
    // truncate it, and every comparison here is an in-memory write snapshot,
    // so the staging stays faithful.
    {
        const std::optional<DocNote> ceiling =
            stageNote(check, base + 6 * kCell, std::numeric_limits<uint32_t>::max());
        QVERIFY2(ceiling.has_value(), "no free key for the duration-ceiling seed");
        view.selectionModel().setNoteSelection({ceiling->noteId});
        const QByteArray bytes = doc.smf().write();
        const int baseIndex = doc.undoStack()->index();
        const int baseCount = doc.undoStack()->count();
        pressResizeKey(roll, true);
        DocNote note;
        QVERIFY2(doc.findNote(ceiling->noteId, &note) &&
                     note.duration == std::numeric_limits<uint32_t>::max() &&
                     view.selectionModel().noteSelection() == std::vector<NoteId>{ceiling->noteId},
                 "lengthening past the uint32 duration ceiling was not rejected");
        expectConsumedNoCommand(doc, bytes, baseIndex, baseCount);
    }
}

// Keyboard merge behavior (plan 6.3): rapid Shift+Arrow presses — one
// delivered as a production auto-repeat keystroke — form one undo entry;
// a net-zero gesture leaves no entry; a selection change separates the
// gestures instead of merging across targets.
void PianoRollTest::keyboardResizeUndoMerge()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    const uint64_t kCell = seed->snapCell; // the fixture's canonical cell
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason),
             "Quick roll input could not be focused before the keyboard resize merge");
    QTRY_VERIFY(roll.hasActiveFocus());
    const uint64_t base = seed->cell.tick;
    DocNote seedNote;
    QVERIFY2(doc.findNote(check.track(), base, uint8_t(seed->cell.key), &seedNote) &&
                 seedNote.duration == 2 * kCell,
             "the merge seed note was not found");
    // The peer joins before the merge baseline so only gesture presses move
    // the undo counts below; selecting it later separates the gestures.
    const std::optional<DocNote> peer = stageNote(check, base + 2 * kCell, uint32_t(2 * kCell));
    QVERIFY2(peer.has_value(), "no free key for the merge peer seed");

    view.selectionModel().setNoteSelection({seedNote.noteId});
    const QByteArray bytes = doc.smf().write();
    const int baseIndex = doc.undoStack()->index();
    const int baseCount = doc.undoStack()->count();

    // A two-Right/two-Left volley on one gesture lands net zero: every
    // press still steps exactly one cell boundary en route, and the merged
    // command turns obsolete and leaves no entry at all (6.3.5; the plan's
    // smoke step 2, proven natively on this fixture).
    DocNote note;
    pressResizeKey(roll, true);
    QVERIFY2(doc.findNote(seedNote.noteId, &note) && note.duration == 3 * kCell,
             "the first lengthen press did not advance one cell");
    pressResizeKey(roll, true);
    QVERIFY2(doc.findNote(seedNote.noteId, &note) && note.duration == 4 * kCell,
             "the second lengthen press did not advance one cell");
    pressResizeKey(roll, false);
    QVERIFY2(doc.findNote(seedNote.noteId, &note) && note.duration == 3 * kCell,
             "the first shorten press did not return one cell");
    pressResizeKey(roll, false);
    QVERIFY2(doc.findNote(seedNote.noteId, &note) && note.duration == 2 * kCell,
             "the net-zero gesture did not restore the seed duration");
    expectConsumedNoCommand(doc, bytes, baseIndex, baseCount);

    // Five lengthen presses — the middle one carrying the production
    // auto-repeat flag through sendKeyStroke — merge into one entry
    // (6.3.1-2).
    pressResizeKey(roll, true);
    pressResizeKey(roll, true);
    sendKeyStroke(roll, Qt::Key_Right, Qt::ShiftModifier, true);
    pressResizeKey(roll, true);
    pressResizeKey(roll, true);
    QVERIFY2(doc.findNote(seedNote.noteId, &note) && note.duration == 7 * kCell,
             "five lengthen presses did not land five cells");
    QCOMPARE(doc.undoStack()->count(), baseCount + 1);
    QCOMPARE(doc.undoStack()->index(), baseIndex + 1);

    // One undo restores the pre-sequence document (6.3.3) and redo restores
    // the merged final duration (6.3.4).
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), bytes);
    doc.undoStack()->redo();
    QVERIFY2(doc.findNote(seedNote.noteId, &note) && note.duration == 7 * kCell,
             "redo did not restore the merged final duration");

    // Selecting a different note separates the gestures: the peer's press
    // cannot merge into the seed's entry, and each gesture undoes alone
    // (6.3.6).
    view.selectionModel().setNoteSelection({peer->noteId});
    pressResizeKey(roll, true);
    QVERIFY2(doc.findNote(peer->noteId, &note) && note.duration == 3 * kCell,
             "the peer lengthen press did not land one cell");
    QCOMPARE(doc.undoStack()->count(), baseCount + 2);
    QCOMPARE(doc.undoStack()->index(), baseIndex + 2);
    doc.undoStack()->undo();
    QVERIFY2(doc.findNote(peer->noteId, &note) && note.duration == 2 * kCell,
             "the peer gesture did not undo alone");
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), bytes);
}

void PianoRollTest::timelineRulerScope()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const Cell &d = seed->cell;
    constexpr uint64_t kCellTicks = 6; // fixture's selected straight 1/16 at 24 PPQN
    const uint64_t startTick = d.tick + kCellTicks;
    const uint64_t endTick = d.tick + 2 * kCellTicks;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote transposed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &transposed),
             "timeline scope seed note was not found");
    doc.moveNotes({transposed}, int64_t(kCellTicks), -11);
    QVERIFY2(doc.findNote(track, d.tick + kCellTicks, uint8_t(d.key - 11), &transposed),
             "timeline scope seed did not reach the expected post-transpose state");
    QVERIFY2(doc.engineTrackCount() > 1,
             "timeline scope fixture needs an independent secondary track");
    const int secondaryTrack = track == 0 ? 1 : 0;
    doc.addNote(secondaryTrack, startTick, uint8_t(d.key), uint32_t(kCellTicks), 100);
    DocNote secondaryNote;
    QVERIFY2(doc.findNote(secondaryTrack, startTick, uint8_t(d.key), &secondaryNote) &&
                 secondaryNote.duration == kCellTicks,
             "timeline scope fixture could not seed its overlapping secondary-track note");

    auto *quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *rulerInput = quick && quick->rootObject()
                           ? quick->rootObject()->findChild<songview::TimelineInputItem *>(
                                 QStringLiteral("timelineRulerInput"))
                           : nullptr;
    const std::optional<songview::TimelineBandGeometry> rulerBand =
        view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    auto *headers = headercheck::model(view);
    QVERIFY2(headers, "could not find the Quick track-header model");
    QVERIFY2(headercheck::recordsMatchTimeline(*headers, check.timeline(), doc.canAddTrack()),
             "Quick header records did not match the current timeline");
    QVERIFY2(rulerInput && rulerBand, "could not find the time ruler");
    const qreal rulerDpr = rulerInput->devicePixelRatio();
    const QPointF start(view.camera().displayX(double(startTick), 0.0, rulerDpr),
                        rulerBand->rect.height() - 2.0);
    const QPointF end(view.camera().displayX(double(endTick), 0.0, rulerDpr),
                      rulerBand->rect.height() - 2.0);
    const QPointF activate = start + QPointF(qreal(QApplication::startDragDistance() + 2), 0.0);

    view.selectionModel().clearTimeSelection();
    view.selectionModel().applyTrackScopeAdjustment(
        track, 0xffffu, songview::EditorSelectionModel::TrackScopeAction::Plain);
    view.selectionModel().applyTrackScopeAdjustment(
        secondaryTrack, 0xffffu, songview::EditorSelectionModel::TrackScopeAction::Toggle);
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonPress, start, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseMove, activate, Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseMove, end, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonRelease, end, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    QVERIFY2(view.selectionModel().timeSelection().active() &&
                 view.selectionModel().timeSelection().startTick == startTick &&
                 view.selectionModel().timeSelection().endTick == endTick &&
                 view.selectionModel().storedTrackScope() == (uint32_t{1} << track),
             "plain ruler drag did not create a primary-only time selection");

    uint32_t expectedScope = uint32_t{1} << track;
    const ViewNote *scopedGhost = nullptr;
    for (const ViewNote &note : view.model().notes) {
        if (note.startTick >= endTick)
            break;
        if (startTick < note.endTick) {
            expectedScope |= uint32_t{1} << note.track;
            if (note.track != track && !scopedGhost)
                scopedGhost = &note;
        }
    }
    const std::optional<int> secondaryRecord =
        scopedGhost ? headercheck::rowForTrack(*headers, scopedGhost->track) : std::nullopt;
    const QColor plainOverlay = secondaryRecord
                                    ? headers
                                          ->data(headers->index(*secondaryRecord, 0),
                                                 songview::TrackHeaderModel::OverlayColorRole)
                                          .value<QColor>()
                                    : QColor{};
    const QImage plainHeaderFrame =
        secondaryRecord ? headercheck::captureBand(check, view) : QImage{};
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonPress, start, Qt::LeftButton,
                              Qt::LeftButton, Qt::ControlModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseMove, activate, Qt::NoButton,
                              Qt::LeftButton, Qt::ControlModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseMove, end, Qt::NoButton, Qt::LeftButton,
                              Qt::ControlModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonRelease, end, Qt::LeftButton,
                              Qt::NoButton, Qt::ControlModifier);
    QVERIFY2(view.selectionModel().timeSelection().startTick == startTick &&
                 view.selectionModel().timeSelection().endTick == endTick &&
                 view.selectionModel().storedTrackScope() == expectedScope,
             "modified ruler drag did not derive the overlapping note-track scope");
    QVERIFY2(scopedGhost, "modified ruler drag fixture has no overlapping secondary-track note");
    const SongView::ViewState priorViewState = view.viewState();
    SongView::ViewState ghostViewState = priorViewState;
    ghostViewState.scrollY = std::max(
        0.0, (127.5 - double(scopedGhost->key)) * ghostViewState.keyHeight - roll.height() / 2.0);
    view.applyViewState(ghostViewState);
    const SnappedRows ghostRows{view, roll};
    const QRectF ghostPlotBox = ghostRows.noteBox(ghostRows.noteRect(
        view.camera().displayX(double(scopedGhost->startTick), 0.0, ghostRows.dpr()),
        view.camera().displayX(double(scopedGhost->endTick), 0.0, ghostRows.dpr()),
        scopedGhost->key));
    const QRectF ghostBandBox = ghostPlotBox.translated(pianoKeyboardWidth, 0.0);
    const QRectF visibleGhostBox = ghostBandBox.intersected(
        QRectF(pianoKeyboardWidth, 0.0, qreal(roll.width()), qreal(roll.height())));
    const QImage scopedImage = check.captureQuickFramebuffer();
    QVERIFY2(!visibleGhostBox.isEmpty(),
             "time-scoped ghost note is outside the horizontal viewport");
    const qreal scopedDpr = scopedImage.devicePixelRatio();
    const int centerX = qRound(visibleGhostBox.center().x() * scopedDpr);
    const int bottomY = qRound(visibleGhostBox.bottom() * scopedDpr) - 1;
    QVERIFY2(isSelectionRingColor(scopedImage.pixel(centerX, bottomY)),
             "time-scoped ghost note did not render its selection ring");
    view.applyViewState(priorViewState);
    view.selectionModel().setTimeSelection(
        {startTick, endTick, songview::EditorSelectionModel::TimeSelection::Tracks});
    QCoreApplication::processEvents();
    QVERIFY2(secondaryRecord, "time-scoped secondary track has no TrackHeaderModel record");
    const QColor selectedOverlay = headers
                                       ->data(headers->index(*secondaryRecord, 0),
                                              songview::TrackHeaderModel::OverlayColorRole)
                                       .value<QColor>();
    QVERIFY2(plainOverlay != selectedOverlay,
             "time-scoped secondary header did not publish its selection role");
    const QImage selectedHeaderFrame = headercheck::captureBand(check, view);
    QVERIFY2(!plainHeaderFrame.isNull() && !selectedHeaderFrame.isNull(),
             "could not capture the time-scoped secondary header");
    if (plainHeaderFrame == selectedHeaderFrame) {
        QCoreApplication::processEvents();
        const QImage repaintedHeaderFrame = headercheck::captureBand(check, view);
        QVERIFY2(!repaintedHeaderFrame.isNull(),
                 "could not recapture the time-scoped secondary header");
        QVERIFY2(plainHeaderFrame != repaintedHeaderFrame,
                 "time-scoped secondary header did not render its selection indicator");
    }

    const QPointF outsideSelection(
        view.camera().displayX(double(endTick + kCellTicks), 0.0, rulerDpr),
        rulerBand->rect.height() - 2.0);
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonPress, outsideSelection,
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonRelease, outsideSelection,
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QVERIFY2(view.selectionModel().timeSelection().active(),
             "left-clicking the timeline ruler outside the time selection cleared it");
    view.selectionModel().clearTimeSelection();
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonPress, start, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseMove, end, Qt::NoButton, Qt::RightButton,
                              Qt::NoModifier);
    QVERIFY2(!view.selectionModel().timeSelection().active(),
             "right-dragging the timeline ruler still created a time selection");
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonRelease, end, Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    // The release publishes the shared ruler menu instead of a nested native
    // exec, so the test continues linearly; a real Escape key dismisses it.
    const QPointer<songview::QuickPopupSession> live(quick_popup::popupSession(view));
    QVERIFY2(QTest::qWaitFor(
                 [&live] { return live && live->isOpen() && quick_popup::menuPanel(*live); }),
             "releasing the right-drag did not open the shared ruler menu");
    QTest::keyClick(live->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(live && !live->isOpen(), "Escape did not dismiss the right-drag ruler menu");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::timelineOtherEventsStrip()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const std::optional<songview::TimelineBandGeometry> otherEvents =
        view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents);
    QVERIFY2(otherEvents, "could not find the canonical other-events band");
    const StripItem *trackEvent = nullptr;
    for (const StripItem &item : view.model().strip) {
        if (item.track >= 0) {
            trackEvent = &item;
            break;
        }
    }
    QVERIFY2(trackEvent, "timeline fixture has no track-colored other-events marker");
    view.selectionModel().setTimeSelection({d.tick + snapCell, d.tick + 2 * snapCell,
                                            songview::EditorSelectionModel::TimeSelection::Tracks});
    QCoreApplication::processEvents();
    const double originalScroll = view.camera().scrollX();
    const qreal visibleContentX = std::max<qreal>(1.0, otherEvents->plotRect.width() / 3.0);
    view.setEditorHorizontalScroll(
        originalScroll + view.camera().contentX(double(trackEvent->tick)) - visibleContentX);
    QCoreApplication::processEvents();
    const QImage beforeStripImage = check.captureQuickBand(otherEvents->rect);
    auto movedSelection = view.selectionModel().timeSelection();
    ++movedSelection.endTick;
    view.selectionModel().setTimeSelection(movedSelection);
    QCoreApplication::processEvents();
    const QImage afterStripImage = check.captureQuickBand(otherEvents->rect);
    QVERIFY2(!beforeStripImage.isNull() && !afterStripImage.isNull() &&
                 beforeStripImage == afterStripImage,
             "moving a time selection changed the other-events strip pixels");
    const qreal stripDpr = afterStripImage.devicePixelRatioF();
    const qreal plotOffset = otherEvents->plotRect.left() - otherEvents->rect.left();
    const int markerX = qRound(
        (plotOffset + view.camera().displayX(double(trackEvent->tick), 0.0, stripDpr)) * stripDpr);
    const int plotLeft = qRound(plotOffset * stripDpr);
    const int markerY = afterStripImage.height() / 2;
    const QRgb expected = SongView::trackColor(trackEvent->track).rgba();
    bool foundMarker = false;
    for (int y = markerY - 2; y <= markerY + 2 && !foundMarker; ++y) {
        for (int x = markerX - 2; x <= markerX + 2; ++x) {
            if (x >= plotLeft && y >= 0 && x < afterStripImage.width() &&
                y < afterStripImage.height() && afterStripImage.pixel(x, y) == expected) {
                foundMarker = true;
                break;
            }
        }
    }
    QVERIFY2(markerX >= plotLeft && markerX < afterStripImage.width(),
             "track-colored other-events marker was not positioned in the plot");
    QVERIFY2(foundMarker, "other-events strip did not render a visible track-colored diamond");
    view.setEditorHorizontalScroll(originalScroll);
    QCoreApplication::processEvents();
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::timelinePartialSelectionRepaint()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.selectionModel().setTimeSelection({d.tick + snapCell, d.tick + 2 * snapCell,
                                            songview::EditorSelectionModel::TimeSelection::Tracks});
    QCoreApplication::processEvents();
    auto movedSelection = view.selectionModel().timeSelection();
    ++movedSelection.endTick;
    view.selectionModel().setTimeSelection(movedSelection);
    QCoreApplication::processEvents();
    const QImage partialSelectionImage = check.captureQuickFramebuffer();
    check.roll().requestQuickUpdate(songview::PianoRollQuickDirty::All);
    QCoreApplication::processEvents();
    QCOMPARE(partialSelectionImage, check.captureQuickFramebuffer());
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::keyboardTimeSelectionShortcuts()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const SnappedRows rows{view, roll};
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote transposed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &transposed),
             "time shortcut seed note was not found");
    doc.moveNotes({transposed}, int64_t(snapCell), -11);
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 11), &transposed),
             "time shortcut seed did not reach the expected post-transpose state");

    songview::EditorSelectionModel::TimeSelection band;
    band.startTick = d.tick + snapCell;
    band.endTick = d.tick + 2 * snapCell;
    view.selectionModel().setTimeSelection(band);
    const QRectF selectedByTimeBox =
        rows.noteBox(
                rows.noteRect(view.camera().displayX(double(transposed.tick), 0.0, rows.dpr()),
                              view.camera().displayX(double(transposed.tick + transposed.duration),
                                                     0.0, rows.dpr()),
                              transposed.key))
            .translated(pianoKeyboardWidth, 0.0);
    const QImage selectedByTimeImage = check.captureQuickFramebuffer();
    const qreal selectedByTimeDpr = selectedByTimeImage.devicePixelRatio();
    const int centerX = qRound(selectedByTimeBox.center().x() * selectedByTimeDpr);
    const int bottomY = qRound(selectedByTimeBox.bottom() * selectedByTimeDpr) - 1;
    QVERIFY2(isSelectionRingColor(selectedByTimeImage.pixel(centerX, bottomY)),
             "time-selected note did not show the normal selection ring");
    QVERIFY2(view.selectionModel().noteSelection().empty(),
             "time-selected note leaked into the explicit note selection");
    const uint64_t emptyTick = band.startTick + (band.endTick - band.startTick) / 2;
    int emptyKey = -1;
    for (int key = 0; key < 128 && emptyKey < 0; ++key) {
        const int y = rows.centerY(key);
        if (y < 0 || y >= roll.height())
            continue;
        const bool occupied = std::any_of(view.model().notes.cbegin(), view.model().notes.cend(),
                                          [track, key, emptyTick](const ViewNote &note) {
                                              return note.track == track && note.key == key &&
                                                     note.startTick <= emptyTick &&
                                                     emptyTick < note.endTick;
                                          });
        if (!occupied)
            emptyKey = key;
    }
    QVERIFY2(emptyKey >= 0, "could not find empty roll space inside the time selection");
    const QPoint emptyInside(qRound(view.camera().displayX(double(emptyTick), 0.0, rows.dpr())),
                             rows.centerY(emptyKey));
    click(roll, emptyInside);
    QVERIFY2(!view.selectionModel().timeSelection().active(),
             "left-clicking empty space inside the time selection did not clear it");
    view.selectionModel().setTimeSelection(band);
    sendKeyStroke(roll, Qt::Key_Up, Qt::NoModifier, false);
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 10), &transposed),
             "time-selection Up did not transpose the covered note");
    sendKeyStroke(roll, Qt::Key_Right, Qt::NoModifier, false);
    QVERIFY2(doc.findNote(track, d.tick + 2 * snapCell, uint8_t(d.key - 10), &transposed),
             "time-selection Right did not nudge the covered note");
    QCOMPARE(view.selectionModel().timeSelection().startTick, d.tick + 2 * snapCell);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::timelineDuplicateTime()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote transposed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &transposed),
             "duplicate-time seed note was not found");
    doc.moveNotes({transposed}, int64_t(snapCell), -11);
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 11), &transposed),
             "duplicate-time seed did not reach the expected post-transpose state");
    view.selectionModel().setTimeSelection({d.tick + snapCell, d.tick + 2 * snapCell,
                                            songview::EditorSelectionModel::TimeSelection::Tracks});
    const songview::EditorSelectionModel::TimeSelection duplicateSource =
        view.selectionModel().timeSelection();
    const uint64_t duplicateSpan = duplicateSource.endTick - duplicateSource.startTick;
    const int duplicateUndoIndex = doc.undoStack()->index();
    const uint8_t duplicateKey = transposed.key;
    const auto hasNoteAt = [&](uint64_t tick) {
        DocNote note;
        return doc.findNote(track, tick, duplicateKey, &note);
    };
    sendKeyStroke(roll, Qt::Key_D, Qt::ControlModifier, false);
    const uint64_t firstStart = duplicateSource.endTick;
    const uint64_t firstEnd = firstStart + duplicateSpan;
    const songview::EditorSelectionModel::TimeSelection firstSelection =
        view.selectionModel().timeSelection();
    QVERIFY2(doc.undoStack()->index() == duplicateUndoIndex + 1 && firstSelection.active() &&
                 firstSelection.startTick == firstStart && firstSelection.endTick == firstEnd &&
                 view.editCursorTick() == firstEnd && hasNoteAt(firstStart),
             "Ctrl+D did not duplicate once and advance the time selection");
    const qreal duplicateDpr = roll.devicePixelRatio();
    const qreal duplicateViewport = std::max<qreal>(50, roll.width());
    QVERIFY2(view.camera().displayX(double(firstStart), 0.0, duplicateDpr) >= 0.0 &&
                 view.camera().displayX(double(firstEnd), 0.0, duplicateDpr) <= duplicateViewport,
             "first duplicated range was not made visible");
    sendKeyStroke(roll, Qt::Key_D, Qt::ControlModifier, false);
    const uint64_t secondStart = firstEnd;
    const uint64_t secondEnd = secondStart + duplicateSpan;
    const songview::EditorSelectionModel::TimeSelection secondSelection =
        view.selectionModel().timeSelection();
    QVERIFY2(doc.undoStack()->index() == duplicateUndoIndex + 2 && secondSelection.active() &&
                 secondSelection.startTick == secondStart && secondSelection.endTick == secondEnd &&
                 view.editCursorTick() == secondEnd && hasNoteAt(secondStart),
             "repeating Ctrl+D did not duplicate the newest copy");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::timelineInsertBlankTimeTracks()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const int track = check.track();
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote transposed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &transposed),
             "track insertion seed note was not found");
    doc.moveNotes({transposed}, int64_t(2 * snapCell), -10);
    QVERIFY2(doc.findNote(track, d.tick + 2 * snapCell, uint8_t(d.key - 10), &transposed),
             "track insertion seed did not reach the expected shortcut state");
    const uint64_t insertStart = d.tick + 2 * snapCell;
    const uint64_t insertEnd = insertStart + snapCell;
    if (doc.engineTrackCount() < 2) {
        while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
        QCOMPARE(doc.smf().write(), before);
        return;
    }
    const int otherTrack = track == 0 ? 1 : 0;
    int otherKey = 12;
    while (otherKey < 128) {
        DocNote existing;
        if (!doc.findNote(otherTrack, insertStart, uint8_t(otherKey), &existing))
            break;
        ++otherKey;
    }
    QVERIFY2(otherKey < 128, "could not reserve an unselected-track insert fixture");
    const uint8_t otherPitch = uint8_t(otherKey);
    doc.addNote(otherTrack, insertStart, otherPitch, uint32_t(snapCell), 91);
    DocNote otherBefore;
    QVERIFY2(doc.findNote(otherTrack, insertStart, otherPitch, &otherBefore),
             "could not create the unselected-track insert fixture");
    view.selectTrack(track);
    songview::EditorSelectionModel::TimeSelection trackSelection;
    trackSelection.startTick = insertStart;
    trackSelection.endTick = insertEnd;
    view.selectionModel().setTimeSelectionAndTrackScope(trackSelection, 1u << track);
    const int insertUndoIndex = doc.undoStack()->index();
    view.insertBlankTime();
    DocNote otherAfter;
    DocNote selectedAfter;
    const bool otherStable =
        doc.findNote(otherTrack, insertStart, otherPitch, &otherAfter) &&
        otherAfter.tick == otherBefore.tick && otherAfter.duration == otherBefore.duration &&
        otherAfter.key == otherBefore.key && otherAfter.velocity == otherBefore.velocity;
    const bool selectedShifted = doc.findNote(track, insertEnd, transposed.key, &selectedAfter);
    const songview::EditorSelectionModel::TimeSelection insertedSelection =
        view.selectionModel().timeSelection();
    QVERIFY2(doc.undoStack()->index() == insertUndoIndex + 1 && otherStable && selectedShifted &&
                 insertedSelection.active() && insertedSelection.startTick == insertStart &&
                 insertedSelection.endTick == insertEnd &&
                 insertedSelection.scope == songview::EditorSelectionModel::TimeSelection::Tracks &&
                 view.editCursorTick() == insertStart,
             "Insert Blank Time changed scope, cursor, or an unselected track");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::timelineInsertBlankTimeLanes()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const int track = check.track();
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote transposed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &transposed),
             "lane insertion seed note was not found");
    doc.moveNotes({transposed}, int64_t(2 * snapCell), -10);
    QVERIFY2(doc.findNote(track, d.tick + 2 * snapCell, uint8_t(d.key - 10), &transposed),
             "lane insertion seed did not reach the expected shortcut state");
    const uint64_t insertStart = d.tick + 2 * snapCell;
    const uint64_t insertEnd = insertStart + snapCell;
    const uint8_t laneCc = 7;
    const uint64_t lanePointTick = insertStart + snapCell / 2;
    doc.addLanePoint(track, laneCc, lanePointTick, 80);
    DocLanePoint laneBefore;
    DocNote laneNoteBefore;
    QVERIFY2(doc.findLanePoint(track, laneCc, lanePointTick, &laneBefore) &&
                 doc.findNote(track, insertStart, transposed.key, &laneNoteBefore),
             "could not create the lane-scoped insert fixture");
    songview::EditorSelectionModel::TimeSelection laneSelection;
    laneSelection.startTick = insertStart;
    laneSelection.endTick = insertEnd;
    laneSelection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    laneSelection.lanes = {{track, laneCc}};
    view.selectionModel().setTimeSelection(laneSelection);
    const int insertUndoIndex = doc.undoStack()->index();
    view.insertBlankTime();
    DocLanePoint shiftedLanePoint;
    DocNote laneNoteAfter;
    const bool laneShifted =
        doc.findLanePoint(track, laneCc, lanePointTick + snapCell, &shiftedLanePoint);
    const bool noteStable = doc.findNote(track, insertStart, transposed.key, &laneNoteAfter) &&
                            laneNoteAfter.tick == laneNoteBefore.tick &&
                            laneNoteAfter.duration == laneNoteBefore.duration &&
                            laneNoteAfter.key == laneNoteBefore.key &&
                            laneNoteAfter.velocity == laneNoteBefore.velocity;
    const songview::EditorSelectionModel::TimeSelection insertedSelection =
        view.selectionModel().timeSelection();
    QVERIFY2(doc.undoStack()->index() == insertUndoIndex + 1 && laneShifted && noteStable &&
                 insertedSelection.active() &&
                 insertedSelection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
                 insertedSelection.lanes == laneSelection.lanes &&
                 insertedSelection.startTick == insertStart &&
                 insertedSelection.endTick == insertEnd && view.editCursorTick() == insertStart,
             "lane-scoped Insert Blank Time widened its scope or moved the band");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}
