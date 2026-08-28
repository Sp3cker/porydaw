#include "checks/rollcheck/rollcheck.h"

#include <QApplication>
#include <QEvent>
#include <QFontMetrics>
#include <QImage>
#include <QObject>
#include <QPixmap>
#include <QPoint>
#include <QRectF>
#include <QWidget>
#include <algorithm>
#include <utility>
#include <vector>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/typography.h"

namespace checks::rollcheck {

ScenarioContinuation runSelectionGestureScenarios(Harness &check,
                                                  const PencilVelocityFixture &fixture)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    QWidget *roll = &check.roll();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const SnappedRows rows{view, *roll};
    const Cell &a = fixture.a;
    const Cell &b = fixture.b;
    const DocNote &noteA = fixture.noteA;
    const DocNote &noteB = fixture.noteB;
    auto fail = [&](const char *what) { check.fail(what); };
    // Band-sweep audition: notes audition (self-releasing, duration in
    // samples) as the right-drag rubber band first covers them, release
    // early when the band leaves them (velocity-0 emission), re-audition on
    // re-entry, all release at the drag's end, and no undo commands.
    {
        std::vector<int> onKeys, offKeys;
        quint32 minDur = UINT32_MAX;
        auto conn = QObject::connect(&view, &SongView::auditionNoteTimed, &view,
                                     [&](int, int key, int velocity, quint32 dur) {
                                         if (velocity > 0) {
                                             onKeys.push_back(key);
                                             minDur = std::min(minDur, dur);
                                         } else {
                                             offKeys.push_back(key);
                                         }
                                     });
        const int preBandCount = doc.undoStack()->count();
        const QPoint sweepStart(pianoKeyboardWidth + 1, 0);
        const QPoint sweepEnd(std::max(a.center.x(), b.center.x()) + 4,
                              std::max(a.center.y(), b.center.y()) + 4);
        view.selectionModel().clearNoteSelection();
        // The band is provisional until release, but covered notes should
        // use the same selection ring as the velocity drawer's live preview.
        const QRectF previewNoteBox = rows.noteBox(rows.noteRect(
            pianoKeyboardWidth + qRound(view.contentX(double(noteA.tick))),
            pianoKeyboardWidth + qRound(view.contentX(double(noteA.tick + noteA.duration))),
            noteA.key));

        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, sweepStart, Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, a.center + QPoint(4, 4), Qt::NoButton,
                                  Qt::RightButton, Qt::NoModifier);
        const QPixmap previewPixmap = roll->grab();
        const QImage previewImage = previewPixmap.toImage();
        const qreal previewDpr = previewPixmap.devicePixelRatio();
        const int previewCenterX = qRound(previewNoteBox.center().x() * previewDpr);
        const int previewBottomY = qRound(previewNoteBox.bottom() * previewDpr) - 1;
        if (!isSelectionRingColor(previewImage.pixel(previewCenterX, previewBottomY)))
            fail("band-dragged note did not show a provisional selection ring");
        if (!view.selectionModel().noteSelection().empty())
            fail("band drag committed selection before release");

        if (std::find(onKeys.begin(), onKeys.end(), a.key) == onKeys.end())
            fail("sweeping the band over a note did not audition it");
        // Retreat to a band covering nothing: the departed notes' previews
        // must release now, not ring out their durations.
        checks::events::sendMouse(*roll, QEvent::MouseMove, sweepStart + QPoint(4, 4), Qt::NoButton,
                                  Qt::RightButton, Qt::NoModifier);
        if (std::find(offKeys.begin(), offKeys.end(), a.key) == offKeys.end())
            fail("shrinking the band did not release the departed note");
        checks::events::sendMouse(*roll, QEvent::MouseMove, sweepEnd, Qt::NoButton, Qt::RightButton,
                                  Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, sweepEnd, Qt::RightButton,
                                  Qt::NoButton, Qt::NoModifier);
        QObject::disconnect(conn);
        if (std::count(onKeys.begin(), onKeys.end(), a.key) < 2)
            fail("re-covering a note did not re-audition it");
        const std::vector<NoteId> &sel = view.selectionModel().noteSelection();
        if (sel.size() < 2 || std::find(sel.begin(), sel.end(), noteA.noteId) == sel.end() ||
            std::find(sel.begin(), sel.end(), noteB.noteId) == sel.end())
            fail("band release did not select the swept notes");
        // Every key that auditioned was eventually released (mid-drag or at
        // the drag's end).
        auto keySet = [](std::vector<int> keys) {
            std::sort(keys.begin(), keys.end());
            keys.erase(std::unique(keys.begin(), keys.end()), keys.end());
            return keys;
        };
        if (keySet(onKeys) != keySet(offKeys))
            fail("band sweep left auditioned keys unreleased");
        if (!onKeys.empty() && minDur == 0)
            fail("band sweep auditioned a zero-length note");
        if (doc.undoStack()->count() != preBandCount)
            fail("band sweep pushed an undo command");
        view.selectionModel().clearNoteSelection(); // the sections below manage their own
    }

    // Empty-space press audition: a plain left press sounds its row at the
    // latched velocity right away, glisses when the held cursor crosses
    // rows, and releases on mouse-up — while the release in place still
    // parks the edit cursor without touching the document. A press that
    // grows into a draw keeps the already-sounding key ringing instead of
    // re-attacking it.
    {
        const Cell e = check.findFreeCell();
        if (e.key < 0) {
            fail("no free grid cell for the press audition");
            return ScenarioContinuation::Stop;
        }
        std::vector<std::pair<int, int>> aud; // key, velocity
        auto conn =
            QObject::connect(&view, &SongView::auditionNote, &view,
                             [&](int, int key, int velocity) { aud.push_back({key, velocity}); });
        const int preCount = doc.undoStack()->count();
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, e.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        if (aud != std::vector<std::pair<int, int>>{{e.key, 93}})
            fail("empty-space press did not audition its row at the latched velocity");
        const QPoint gliss(e.center.x(), rows.centerY(e.key - 1));
        checks::events::sendMouse(*roll, QEvent::MouseMove, gliss, Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
        if (aud.empty() || aud.back() != std::make_pair(e.key - 1, 93))
            fail("holding the press across a row did not gliss the preview");
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, gliss, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        if (aud.empty() || aud.back().second != 0)
            fail("releasing the press did not release the preview");
        if (doc.undoStack()->count() != preCount)
            fail("a plain empty-space click edited the document");
        if (view.editCursorTick() !=
            view.snapTick(view.tickAtContentX(e.center.x() - pianoKeyboardWidth)))
            fail("the press audition broke the click's edit-cursor park");
        // Draw growth: press the still-free cell again and drag right past
        // the drag threshold; the press's preview must carry into the draw
        // with no second attack on the same key.
        aud.clear();
        const QPoint pull = e.center + QPoint(QApplication::startDragDistance() + 8, 0);
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, e.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, pull, Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, pull, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        QObject::disconnect(conn);
        if (std::count(aud.begin(), aud.end(), std::make_pair(e.key, 93)) != 1)
            fail("growing the press into a draw re-attacked the sounding key");
        DocNote drawn;
        if (!doc.findNote(track, e.tick, uint8_t(e.key), &drawn))
            fail("the press-grown draw did not commit its note");
    }

    // The pending draw note ignores note-name mode: nothing may cover the
    // note while it is being placed, so toggling note-name mode mid-gesture
    // must leave the preview pixel-identical. The probe uses rows too short
    // for the settled label font, so the comparison is sensitive only to the
    // draw preview itself.
    {
        const auto readoutPadding = layout::space(layout::Space::Half);
        auto readoutFont = typography::noteName(roll->font());
        readoutFont.setPixelSize(
            std::max(layout::singlePixel(), readoutFont.pixelSize() - 2 * layout::singlePixel()));
        const auto readoutMetrics = QFontMetrics(readoutFont);
        const SongView::ViewState viewBeforeReadout = view.viewState();
        SongView::ViewState readoutShortRows = viewBeforeReadout;
        // Short rows where the fixed face cannot fit, so no settled name
        // ever paints on the probed rows.
        readoutShortRows.keyHeight =
            double(readoutMetrics.ascent() + readoutMetrics.descent() + 2 * readoutPadding);
        view.applyViewState(readoutShortRows);
        view.setNoteNameMode(true);
        const Cell readoutCell = check.findFreeCell();
        if (readoutCell.key < 0) {
            fail("no free grid cell for the draw readout probe");
        } else {
            const int undoIndexBeforeReadout = doc.undoStack()->index();
            const QPoint readoutEnd =
                readoutCell.center + QPoint(QApplication::startDragDistance() + 8, 0);
            checks::events::sendMouse(*roll, QEvent::MouseButtonPress, readoutCell.center,
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*roll, QEvent::MouseMove, readoutEnd, Qt::NoButton,
                                      Qt::LeftButton, Qt::NoModifier);
            const QImage readoutOn = roll->grab().toImage();
            view.setNoteNameMode(false);
            const QImage readoutOff = roll->grab().toImage();
            view.setNoteNameMode(true);
            checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, readoutEnd, Qt::LeftButton,
                                      Qt::NoButton, Qt::NoModifier);
            if (readoutOn != readoutOff)
                fail("note-name mode changed the pending draw-note rendering");
            while (doc.undoStack()->index() > undoIndexBeforeReadout && doc.undoStack()->canUndo())
                doc.undoStack()->undo();
        }
        view.applyViewState(viewBeforeReadout);
    }

    // Drawing begins at a layout Space::One horizontal drag; a shorter
    // gesture remains a click, while one at the threshold creates a
    // one-snap-cell note.
    {
        const int drawStartDistance = layout::space(layout::Space::One);
        const qreal belowDrawStartDistance = std::max(0.0, double(drawStartDistance) - 0.5);
        const Cell f = check.findFreeCell();
        if (f.key < 0) {
            fail("no free grid cell for the minimum-distance draw");
            return ScenarioContinuation::Stop;
        }
        const QPointF belowDrawEnd = QPointF(f.center) + QPointF(belowDrawStartDistance, 0.0);
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, f.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, belowDrawEnd, Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, belowDrawEnd, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        DocNote tiny;
        if (doc.findNote(track, f.tick, uint8_t(f.key), &tiny))
            fail("a subthreshold horizontal drag drew a note");
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, f.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, f.center + QPoint(drawStartDistance, 0),
                                  Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease,
                                  f.center + QPoint(drawStartDistance, 0), Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        if (!doc.findNote(track, f.tick, uint8_t(f.key), &tiny))
            fail("a Space::One horizontal drag did not draw a note");
        else if (tiny.duration != view.snapTicksAt(f.tick))
            fail("the minimum-distance note is not one snap cell long");
    }

    // Modifier velocity gesture (Ableton-style): with the roll.velocity_drag
    // chord held (Ctrl by default), a vertical drag from anywhere on note B
    // adjusts its velocity — 1px = 1 step, 15px down lands 93 -> 78 — with
    // the hover mark pinned to the note's row. Keeping the chord held for a
    // velocity drag on the next note replaces the prior selection instead of
    // accumulating it. Without a preceding drag, Ctrl+click keeps its
    // selection-toggle meaning (deferred to release), and a vertical jitter
    // under the drag threshold is still that click: it toggles, changes no
    // velocity, and pushes no undo command.
    {
        click(*roll, b.center); // plain click: select B (velocity 93)
        const int preCount = doc.undoStack()->count();
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, b.center + QPoint(0, 15), Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        if (roll->property("hoverKey").toInt() != b.key)
            fail("modifier velocity drag did not pin the hover mark");
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center + QPoint(0, 15),
                                  Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
        DocNote bMod;
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &bMod) || bMod.velocity != 78)
            fail("modifier velocity drag did not land at 78");
        if (doc.undoStack()->count() != preCount + 1)
            fail("modifier velocity drag did not push exactly one command");

        // Clicks keep their ordinary meaning and do not spend the protection
        // intended for the next modifier velocity drag.
        const NoteId bId = bMod.noteId;
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center, Qt::LeftButton,
                                  Qt::NoButton, Qt::ControlModifier);
        if (std::find(view.selectionModel().noteSelection().begin(),
                      view.selectionModel().noteSelection().end(),
                      bId) != view.selectionModel().noteSelection().end())
            fail("Ctrl+click after a velocity drag did not keep its toggle meaning");
        click(*roll, b.center);
        if (view.selectionModel().noteSelection() != std::vector<NoteId>{bId})
            fail("plain click after a velocity drag did not restore the single-note selection");

        // The same uninterrupted modifier hold on another note is a request
        // to edit that note, not to grow a bulk selection and edit both.
        DocNote aCarryBefore;
        if (!doc.findNote(track, a.tick, uint8_t(a.key), &aCarryBefore))
            fail("note A went missing before the carried modifier velocity drag");
        const int carryCount = doc.undoStack()->count();
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, a.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, a.center + QPoint(0, 15), Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, a.center + QPoint(0, 15),
                                  Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
        DocNote aCarryAfter, bAfterCarry;
        const std::vector<NoteId> &carriedSelection = view.selectionModel().noteSelection();
        if (carriedSelection.size() != 1 || !(carriedSelection.front() == aCarryBefore.noteId))
            fail("a held modifier accumulated the note after a velocity drag");
        if (!doc.findNote(track, a.tick, uint8_t(a.key), &aCarryAfter) ||
            int(aCarryAfter.velocity) != int(aCarryBefore.velocity) - 15)
            fail("the carried modifier velocity drag did not adjust the next note");
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &bAfterCarry) ||
            bAfterCarry.velocity != bMod.velocity)
            fail("the carried modifier velocity drag also adjusted the prior note");
        if (doc.undoStack()->count() != carryCount + 1)
            fail("the carried modifier velocity drag did not push exactly one command");

        // Releasing the modifier ends the protection; a later Ctrl gesture
        // has the ordinary selection-toggle and bulk-selection behavior.
        checks::events::sendKey(*roll, QEvent::KeyRelease, Qt::Key_Control, Qt::NoModifier,
                                QString(), false, 1);
        click(*roll, b.center);
        const int postCarryCount = doc.undoStack()->count();

        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center, Qt::LeftButton,
                                  Qt::NoButton, Qt::ControlModifier);
        if (std::find(view.selectionModel().noteSelection().begin(),
                      view.selectionModel().noteSelection().end(),
                      bId) != view.selectionModel().noteSelection().end())
            fail("Ctrl+click did not toggle the note out of the selection");
        // A vertical jitter under the drag threshold is still that click:
        // it toggles, changes no velocity, and pushes no undo command.
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, b.center + QPoint(0, 2), Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center + QPoint(0, 2),
                                  Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
        if (view.selectionModel().noteSelection().size() != 1 ||
            !(view.selectionModel().noteSelection().front() == bId))
            fail("a sub-threshold Ctrl-jitter did not act as the toggle click");
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &bMod) || bMod.velocity != 78)
            fail("a sub-threshold Ctrl-jitter changed the velocity");
        if (doc.undoStack()->count() != postCarryCount)
            fail("a Ctrl-click or jitter pushed an undo command");

        // At the platform threshold the deferred press becomes a velocity drag.
        const int velocityDragDistance = QApplication::startDragDistance();
        const int gestureCount = doc.undoStack()->count();
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove,
                                  b.center + QPoint(0, velocityDragDistance), Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease,
                                  b.center + QPoint(0, velocityDragDistance), Qt::LeftButton,
                                  Qt::NoButton, Qt::ControlModifier);
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &bMod) ||
            bMod.velocity != 78 - velocityDragDistance)
            fail("a threshold Ctrl-drag did not start the velocity gesture");
        if (doc.undoStack()->count() != gestureCount + 1)
            fail("the threshold velocity drag did not push exactly one command");

        // Bulk-selection preservation, mirroring the Ctrl+edge grab: with
        // note A selected, a Ctrl+velocity drag on unselected note B joins
        // B to the selection instead of replacing it, and the nudge lands
        // on BOTH notes in one command.
        click(*roll, a.center); // selection = {A}
        DocNote aBefore, bBefore;
        if (!doc.findNote(track, a.tick, uint8_t(a.key), &aBefore) ||
            !doc.findNote(track, b.tick, uint8_t(b.key), &bBefore))
            fail("notes A/B went missing before the joined velocity drag");
        const int joinCount = doc.undoStack()->count();
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, b.center + QPoint(0, 15), Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center + QPoint(0, 15),
                                  Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
        const NoteId aId = aBefore.noteId;
        const std::vector<NoteId> &joined = view.selectionModel().noteSelection();
        if (joined.size() != 2 || std::find(joined.begin(), joined.end(), aId) == joined.end() ||
            std::find(joined.begin(), joined.end(), bId) == joined.end())
            fail("a Ctrl+velocity drag replaced the bulk selection");
        DocNote aAfter, bAfter;
        if (!doc.findNote(track, a.tick, uint8_t(a.key), &aAfter) ||
            aAfter.velocity != aBefore.velocity - 15)
            fail("the joined Ctrl+velocity drag did not nudge the other note");
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &bAfter) ||
            bAfter.velocity != bBefore.velocity - 15)
            fail("the joined Ctrl+velocity drag did not nudge the grabbed note");
        if (doc.undoStack()->count() != joinCount + 1)
            fail("the joined velocity drag did not push exactly one command");

        // Repeating the modifier drag on the same anchor keeps the deliberate
        // bulk selection; the carryover only suppresses adding another note.
        const int repeatedCount = doc.undoStack()->count();
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, b.center - QPoint(0, 15), Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center - QPoint(0, 15),
                                  Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
        const std::vector<NoteId> &repeatedSelection = view.selectionModel().noteSelection();
        DocNote aRepeated, bRepeated;
        if (repeatedSelection.size() != 2 ||
            std::find(repeatedSelection.begin(), repeatedSelection.end(), aId) ==
                repeatedSelection.end() ||
            std::find(repeatedSelection.begin(), repeatedSelection.end(), bId) ==
                repeatedSelection.end())
            fail("repeating a modifier velocity drag on its anchor collapsed the bulk selection");
        if (!doc.findNote(track, a.tick, uint8_t(a.key), &aRepeated) ||
            aRepeated.velocity != aAfter.velocity + 15 ||
            !doc.findNote(track, b.tick, uint8_t(b.key), &bRepeated) ||
            bRepeated.velocity != bAfter.velocity + 15)
            fail("repeating a modifier velocity drag did not nudge the whole selection");
        if (doc.undoStack()->count() != repeatedCount + 1)
            fail("the repeated velocity drag did not push exactly one command");

        // A different anchor replaces the prior selection even when that
        // anchor was already part of the bulk selection.
        const int switchCount = doc.undoStack()->count();
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, a.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, a.center + QPoint(0, 15), Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, a.center + QPoint(0, 15),
                                  Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
        DocNote aSwitched, bAfterSwitch;
        if (view.selectionModel().noteSelection() != std::vector<NoteId>{aId})
            fail("a carried modifier drag kept the prior note selected");
        if (!doc.findNote(track, a.tick, uint8_t(a.key), &aSwitched) ||
            aSwitched.velocity != aRepeated.velocity - 15)
            fail("the carried modifier drag did not adjust its selected anchor");
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &bAfterSwitch) ||
            bAfterSwitch.velocity != bRepeated.velocity)
            fail("the carried modifier drag adjusted the prior selected note");
        if (doc.undoStack()->count() != switchCount + 1)
            fail("the switched velocity drag did not push exactly one command");
        doc.undoStack()->undo();
        doc.undoStack()->undo();
        doc.undoStack()->undo(); // restore both velocities for later checks
        view.selectionModel().clearNoteSelection();
    }

    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
