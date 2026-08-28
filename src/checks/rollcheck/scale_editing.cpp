#include "checks/rollcheck/rollcheck.h"

#include <QCoreApplication>
#include <QEvent>
#include <QObject>
#include <QPoint>
#include <QWidget>
#include <algorithm>
#include <cmath>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "porydaw_scale.h"
#include "ui/songview.h"

namespace checks::rollcheck {

ScenarioContinuation runScaleEditingScenarios(Harness &check)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    QWidget *roll = &check.roll();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const int pianoRollDefaultKeyHeight = check.pianoRollDefaultKeyHeight();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const auto projHidden = songview::PitchProjection::cHiddenRow;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const auto foldCenterY = [&](int pitch) -> int {
        const int row = view.pitchProjection().rowForPitch(pitch);
        if (row == songview::PitchProjection::cHiddenRow)
            return -1;
        const qreal dpr = roll->devicePixelRatioF();
        const qreal top = std::round((double(row) * view.keyHeight() - view.scrollY()) * dpr) / dpr;
        const qreal bottom =
            std::round((double(row + 1) * view.keyHeight() - view.scrollY()) * dpr) / dpr;
        return int(std::floor((top + bottom) / 2.0));
    };
    const int undoBaseline = doc.undoStack()->index();
    auto fail = [&](const char *what) { check.fail(what); };
    // Block D — Fold editing (Wave 7): diatonic degree nudges, chromatic
    // fallbacks, exception-row rules, and atomic out-of-range rejection.
    {
        const auto &proj = view.pitchProjection();
        const uint64_t tBase =
            uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
        const uint32_t dur = uint32_t(doc.ticksPerClock());
        const auto noteIdAt = [&](uint64_t tick, uint8_t key) {
            DocNote note;
            return doc.findNote(scaleTrack, tick, key, &note) ? note.noteId : NoteId{};
        };

        view.setScaleHighlight(false);
        view.setScaleFold(false);
        view.setScaleRoot(0);
        view.setScaleId(scaleMajor);

        // D1. Fold Up moves one scale degree (C60 -> D62).
        {
            const int cmd0 = doc.undoStack()->index();
            doc.addNote(scaleTrack, tBase, 60, dur, 100);
            view.selectionModel().setNoteSelection({noteIdAt(tBase, 60)});
            view.setScaleHighlight(false);
            view.setScaleFold(true);
            sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false);
            DocNote moved;
            if (!doc.findNote(scaleTrack, tBase, 62, &moved))
                fail("Fold Up did not move C up one scale degree to D");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
            view.selectionModel().clearNoteSelection();
        }

        // D2. Fold Shift+Up moves a chromatic octave (C60 -> 72).
        {
            const int cmd0 = doc.undoStack()->index();
            doc.addNote(scaleTrack, tBase, 60, dur, 100);
            view.selectionModel().setNoteSelection({noteIdAt(tBase, 60)});
            view.setScaleHighlight(false);
            view.setScaleFold(true);
            sendKeyStroke(*roll, Qt::Key_Up, Qt::ShiftModifier, false);
            DocNote moved;
            if (!doc.findNote(scaleTrack, tBase, 72, &moved))
                fail("Fold Shift+Up did not move C up an octave");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
            view.selectionModel().clearNoteSelection();
        }

        // D3. Off Up stays chromatic (C60 -> 61).
        {
            const int cmd0 = doc.undoStack()->index();
            doc.addNote(scaleTrack, tBase, 60, dur, 100);
            view.selectionModel().setNoteSelection({noteIdAt(tBase, 60)});
            view.setScaleHighlight(false);
            view.setScaleFold(false);
            sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false);
            DocNote moved;
            if (!doc.findNote(scaleTrack, tBase, 61, &moved))
                fail("Off Up did not move C up a semitone");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
            view.selectionModel().clearNoteSelection();
        }

        // D4. Multi-note selection maps to distinct degrees (60,61 -> 62,64).
        {
            const int cmd0 = doc.undoStack()->index();
            doc.addNote(scaleTrack, tBase, 60, dur, 100);
            doc.addNote(scaleTrack, tBase, 61, dur, 100);
            view.selectionModel().setNoteSelection({noteIdAt(tBase, 60), noteIdAt(tBase, 61)});
            view.setScaleHighlight(false);
            view.setScaleFold(true);
            sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false);
            DocNote moved;
            const bool okA = doc.findNote(scaleTrack, tBase, 62, &moved);
            const bool okB = doc.findNote(scaleTrack, tBase, 64, &moved);
            if (!okA || !okB)
                fail("Fold Up did not map selected notes to distinct degrees");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
            view.selectionModel().clearNoteSelection();
        }

        // D5. Repeated source pitch: two C60 notes both go to D62.
        {
            const int cmd0 = doc.undoStack()->index();
            const uint64_t tA = tBase, tB = tBase + uint64_t(doc.ticksPerClock());
            doc.addNote(scaleTrack, tA, 60, dur, 100);
            doc.addNote(scaleTrack, tB, 60, dur, 100);
            view.selectionModel().setNoteSelection({noteIdAt(tA, 60), noteIdAt(tB, 60)});
            view.setScaleHighlight(false);
            view.setScaleFold(true);
            sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false);
            DocNote moved;
            const bool okA = doc.findNote(scaleTrack, tA, 62, &moved);
            const bool okB = doc.findNote(scaleTrack, tB, 62, &moved);
            if (!okA || !okB)
                fail("Repeated Fold source pitch did not share the destination");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
            view.selectionModel().clearNoteSelection();
        }

        // D6. Off-scale source entry (exception) nudges to the first scale
        // pitch above (61 -> 62).
        {
            const int cmd0 = doc.undoStack()->index();
            doc.addNote(scaleTrack, tBase, 61, dur, 100);
            view.selectionModel().setNoteSelection({noteIdAt(tBase, 61)});
            view.setScaleHighlight(false);
            view.setScaleFold(true);
            sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false);
            DocNote moved;
            if (!doc.findNote(scaleTrack, tBase, 62, &moved))
                fail("Fold Up did not move an off-scale exception to the next degree");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
            view.selectionModel().clearNoteSelection();
        }

        // D7. Fold rejects drawing into an off-scale exception row.
        {
            const int cmd0 = doc.undoStack()->index();
            doc.addNote(scaleTrack, tBase, 61, dur, 100);
            view.setScaleHighlight(false);
            view.setScaleFold(true);
            const int r61 = proj.rowForPitch(61);
            SongView::ViewState d7 = view.viewState();
            d7.valid = true;
            d7.keyHeight = pianoRollDefaultKeyHeight;
            d7.scrollY = double(
                std::max(0, r61 * pianoRollDefaultKeyHeight - 4 * pianoRollDefaultKeyHeight));
            view.applyViewState(d7);
            (void)view.grab();
            QCoreApplication::processEvents();
            const size_t before = doc.notesForTrack(scaleTrack).size();
            drawNote(*roll, QPoint(pianoKeyboardWidth + 40, foldCenterY(61)));
            QCoreApplication::processEvents();
            if (doc.notesForTrack(scaleTrack).size() != before)
                fail("Fold accepted a draw into an off-scale exception row");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
            view.selectionModel().clearNoteSelection();
        }

        // D8. The exception row's piano key still auditions its pitch.
        {
            const int cmd0 = doc.undoStack()->index();
            doc.addNote(scaleTrack, tBase, 61, dur, 100);
            view.setScaleHighlight(false);
            view.setScaleFold(true);
            const int r61 = proj.rowForPitch(61);
            SongView::ViewState d8 = view.viewState();
            d8.valid = true;
            d8.keyHeight = pianoRollDefaultKeyHeight;
            d8.scrollY = double(
                std::max(0, r61 * pianoRollDefaultKeyHeight - 4 * pianoRollDefaultKeyHeight));
            view.applyViewState(d8);
            (void)view.grab();
            QCoreApplication::processEvents();
            int audKey = -1;
            auto conn = QObject::connect(&view, &SongView::auditionNote, &view,
                                         [&](int, int key, int velocity) {
                                             if (velocity > 0)
                                                 audKey = key;
                                         });
            checks::events::sendMouse(*roll, QEvent::MouseButtonPress,
                                      QPoint(pianoKeyboardWidth / 2, foldCenterY(61)),
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            QObject::disconnect(conn);
            if (audKey != 61)
                fail("Fold exception-row piano key did not audition pitch 61");
            checks::events::sendMouse(*roll, QEvent::MouseButtonRelease,
                                      QPoint(pianoKeyboardWidth / 2, foldCenterY(61)),
                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
        }

        // D9+D12. A vertical pointer drag previews and commits the fold
        // degree; the layout only rebuilds once the gesture commits. The
        // source pitch is an off-scale exception NOT present anywhere in the
        // track: adding it adds exactly one fold row, and committing the
        // drag away collapses it — deterministic regardless of the song.
        {
            const int cmd0 = doc.undoStack()->index();
            view.setScaleHighlight(false);
            view.setScaleFold(true);
            view.setScaleRoot(0);
            view.setScaleId(scaleMajor);
            (void)view.grab();
            QCoreApplication::processEvents();
            bool occ[128] = {};
            for (const DocNote &dn : doc.notesForTrack(scaleTrack))
                occ[dn.key] = true;
            // The lowest off-scale (non-diatonic) pitch the track never uses.
            int src = -1, dst = -1;
            for (int k = 48; k < 96; k++) {
                if (porydaw_scale::isScalePitch(scaleMajor, 0, k) || occ[k])
                    continue;
                src = k;
                dst = porydaw_scale::nextScalePitch(scaleMajor, 0, k, 1);
                break;
            }
            if (src < 0 || dst < 0 || dst == src)
                fail("Fold drag could not pick a free off-scale pitch");
            // Occupied-only Fold needs a visible scale row for the pointer
            // target. Add a distant support note when the track does not
            // already use that destination pitch.
            if (!occ[dst])
                doc.addNote(scaleTrack,
                            uint64_t(check.timeline().lengthTicks) + doc.ticksPerClock() * 32,
                            uint8_t(dst), doc.ticksPerClock(), 100);
            const int rowsBeforeSource = proj.visibleRowCount();
            doc.addNote(scaleTrack, tBase, uint8_t(src), uint32_t(doc.ticksPerClock()) * 4, 100);
            QCoreApplication::processEvents();
            const int rowsWithNote = proj.visibleRowCount();
            if (rowsWithNote != rowsBeforeSource + 1)
                fail("Fold drag did not gain the occupied off-scale row");
            view.ensureTickVisible(tBase);
            const int rSrc = proj.rowForPitch(src);
            SongView::ViewState d9 = view.viewState();
            d9.valid = true;
            d9.keyHeight = pianoRollDefaultKeyHeight;
            d9.scrollY = double(
                std::max(0, rSrc * pianoRollDefaultKeyHeight - 4 * pianoRollDefaultKeyHeight));
            view.applyViewState(d9);
            (void)view.grab();
            QCoreApplication::processEvents();
            // Press the note center for a Move drag: horizontally the center
            // avoids the 3px edge-grip zones on this 5px-wide, 4-tick note.
            const int x = int((view.contentX(double(tBase)) +
                               view.contentX(double(tBase) + doc.ticksPerClock() * 4)) /
                                  2.0 +
                              pianoKeyboardWidth);
            const QPoint press(x, foldCenterY(src));
            int dragAud = -1;
            auto dconn = QObject::connect(&view, &SongView::auditionNote, &view,
                                          [&](int, int key, int velocity) {
                                              if (velocity > 0)
                                                  dragAud = key;
                                          });
            checks::events::sendMouse(*roll, QEvent::MouseButtonPress, press, Qt::LeftButton,
                                      Qt::LeftButton, Qt::NoModifier);
            if (view.selectionModel().noteSelection().size() != 1)
                fail("Fold drag press did not grab the off-scale note");
            if (proj.visibleRowCount() != rowsWithNote)
                fail("Fold rebuilt its layout during a pointer drag");
            const int rDst = proj.rowForPitch(dst);
            if (rDst == projHidden)
                fail("Fold drag target row is hidden");
            const QPoint target(x, foldCenterY(dst));
            checks::events::sendMouse(*roll, QEvent::MouseMove, target, Qt::NoButton,
                                      Qt::LeftButton, Qt::NoModifier);
            if (proj.visibleRowCount() != rowsWithNote)
                fail("Fold rebuilt its layout mid-drag");
            checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, target, Qt::LeftButton,
                                      Qt::NoButton, Qt::NoModifier);
            QObject::disconnect(dconn);
            QCoreApplication::processEvents();
            DocNote moved;
            if (!doc.findNote(scaleTrack, tBase, uint8_t(dst), &moved))
                fail("Fold drag did not commit the note to its scale degree");
            if (proj.visibleRowCount() != rowsBeforeSource)
                fail("Fold did not rebuild its occupied rows after the drag commit");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
            view.selectionModel().clearNoteSelection();
        }

        // D10. A horizontal-only move preserves an off-scale exception pitch.
        {
            const int cmd0 = doc.undoStack()->index();
            doc.addNote(scaleTrack, tBase, 61, dur, 100);
            view.setScaleHighlight(false);
            view.setScaleFold(true);
            DocNote n;
            if (doc.findNote(scaleTrack, tBase, 61, &n)) {
                const uint64_t next = tBase + uint64_t(doc.ticksPerClock()) * 4;
                doc.moveNotes({n}, int64_t(next) - int64_t(tBase), 0, /*mergeable=*/true);
                DocNote moved;
                if (!doc.findNote(scaleTrack, next, 61, &moved))
                    fail("Fold horizontal move changed the exception pitch");
            }
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
            view.selectionModel().clearNoteSelection();
        }

        // D11. Out-of-range diatonic nudge is atomic: no move, no command.
        {
            const int cmd0 = doc.undoStack()->index();
            doc.addNote(scaleTrack, tBase, 127, dur, 100); // B = top C-major pitch
            view.selectionModel().setNoteSelection({noteIdAt(tBase, 127)});
            view.setScaleHighlight(false);
            view.setScaleFold(true);
            const int cmdsBefore = doc.undoStack()->count();
            sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false); // out of range
            if (doc.undoStack()->count() != cmdsBefore)
                fail("Fold out-of-range nudge pushed an undo command");
            DocNote still;
            if (!doc.findNote(scaleTrack, tBase, 127, &still))
                fail("Fold out-of-range nudge moved the top pitch");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
            view.selectionModel().clearNoteSelection();
        }

        view.setScaleHighlight(false);
        view.setScaleFold(false);
        view.setScaleRoot(0);
        view.setScaleId(scaleMajor);
    }

    if (doc.undoStack()->index() != undoBaseline)
        fail("gesture pass pushed an unexpected number of undo commands");
    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
