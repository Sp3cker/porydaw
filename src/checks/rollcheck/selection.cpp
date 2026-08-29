#include "checks/rollcheck/rollcheck.h"

#include <QApplication>
#include <QEvent>
#include <QFontMetrics>
#include <QImage>
#include <QObject>
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
        const qreal previewDpr = roll->devicePixelRatioF();
        const QRectF previewNoteBox = rows.noteBox(rows.noteRect(
            view.displayX(double(noteA.tick), pianoKeyboardWidth, previewDpr),
            view.displayX(double(noteA.tick + noteA.duration), pianoKeyboardWidth, previewDpr),
            noteA.key));
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, sweepStart, Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, a.center + QPoint(4, 4), Qt::NoButton,
                                  Qt::RightButton, Qt::NoModifier);
        const QImage previewImage = check.captureQuickFramebuffer();
        const qreal previewRasterDpr = previewImage.devicePixelRatio();
        const int previewCenterX = qRound(previewNoteBox.center().x() * previewRasterDpr);
        const int previewBottomY = qRound(previewNoteBox.bottom() * previewRasterDpr) - 1;
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
            const QImage readoutOn = check.captureQuickFramebuffer();
            view.setNoteNameMode(false);
            const QImage readoutOff = check.captureQuickFramebuffer();
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
    // the hover mark pinned to the note's row. Crossing the drag threshold
    // preserves a selected group when the grabbed note is already selected;
    // otherwise it re-anchors the selection to the grabbed note. Without a
    // preceding drag, Ctrl+click keeps its selection-toggle meaning
    // (deferred to release), and a vertical jitter under the drag threshold
    // is still that click: it toggles, changes no velocity, and pushes no
    // undo command.
    {
        const auto sameNoteFields = [](const DocNote &x, const DocNote &y) {
            return x.noteId == y.noteId && x.engineTrack == y.engineTrack &&
                   x.smfTrack == y.smfTrack && x.onIndex == y.onIndex && x.endIndex == y.endIndex &&
                   x.tick == y.tick && x.duration == y.duration && x.key == y.key &&
                   x.velocity == y.velocity && x.channel == y.channel;
        };
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
        const NoteId bId = bMod.noteId;
        if (view.selectionModel().noteSelection() != std::vector<NoteId>{bId})
            fail("modifier velocity drag did not leave only its anchor selected");
        if (doc.undoStack()->count() != preCount + 1)
            fail("modifier velocity drag did not push exactly one command");

        // Clicks keep their ordinary meaning: a Ctrl+click toggles, deferred
        // to release, and the release never crosses the drag threshold.
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center, Qt::LeftButton,
                                  Qt::NoButton, Qt::ControlModifier);
        if (view.selectionModel().noteSelection() != std::vector<NoteId>{})
            fail("Ctrl+click after a velocity drag did not keep its toggle meaning");
        // A vertical jitter under the drag threshold is still that click:
        // it toggles, changes no velocity, and pushes no undo command.
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, b.center + QPoint(0, 2), Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center + QPoint(0, 2),
                                  Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
        if (view.selectionModel().noteSelection() != std::vector<NoteId>{bId})
            fail("a sub-threshold Ctrl-jitter did not act as the toggle click");
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &bMod) || bMod.velocity != 78)
            fail("a sub-threshold Ctrl-jitter changed the velocity");
        if (doc.undoStack()->count() != preCount + 1)
            fail("a Ctrl-click or jitter pushed an undo command");

        // At the platform threshold the deferred press becomes a velocity drag.
        const int velocityDragDistance = QApplication::startDragDistance();
        const int thresholdCount = doc.undoStack()->count();
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
        if (view.selectionModel().noteSelection() != std::vector<NoteId>{bId})
            fail("the threshold velocity drag did not leave only its anchor selected");
        if (doc.undoStack()->count() != thresholdCount + 1)
            fail("the threshold velocity drag did not push exactly one command");

        // With the chord still held, a different note under the cursor is
        // edited the same way: the new crossing re-anchors the selection to
        // the grabbed note alone and touches nothing else.
        DocNote aBefore;
        if (!doc.findNote(track, a.tick, uint8_t(a.key), &aBefore))
            fail("note A went missing before the chord-held velocity drag");
        const NoteId aId = aBefore.noteId;
        const int heldCount = doc.undoStack()->count();
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, a.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, a.center + QPoint(0, 15), Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, a.center + QPoint(0, 15),
                                  Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
        DocNote aAfter, bAfterDrag;
        if (view.selectionModel().noteSelection() != std::vector<NoteId>{aId})
            fail("the chord-held drag on another note kept the prior note selected");
        if (!doc.findNote(track, a.tick, uint8_t(a.key), &aAfter) ||
            int(aAfter.velocity) != int(aBefore.velocity) - 15)
            fail("the chord-held velocity drag did not adjust the grabbed note");
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &bAfterDrag) ||
            !sameNoteFields(bAfterDrag, bMod))
            fail("the chord-held velocity drag also adjusted the prior note");
        if (doc.undoStack()->count() != heldCount + 1)
            fail("the chord-held velocity drag did not push exactly one command");

        // Decisive regression: the anchor sits inside a multi-note selection.
        // A chord velocity drag must preserve the selection and apply the
        // same delta to every selected note from its own original velocity.
        view.selectionModel().setNoteSelection({aId, bId});
        DocNote aGrouped, bGrouped;
        if (!doc.findNote(track, a.tick, uint8_t(a.key), &aGrouped) ||
            !doc.findNote(track, b.tick, uint8_t(b.key), &bGrouped))
            fail("notes A/B went missing before the grouped velocity drag");
        const int groupCount = doc.undoStack()->count();
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, a.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, a.center + QPoint(0, 15), Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, a.center + QPoint(0, 15),
                                  Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
        DocNote aAdjusted, bAdjusted;
        if (view.selectionModel().noteSelection() != std::vector<NoteId>({aId, bId}))
            fail("a grouped velocity drag did not preserve the selected notes");
        if (!doc.findNote(track, a.tick, uint8_t(a.key), &aAdjusted) ||
            int(aAdjusted.velocity) != int(aGrouped.velocity) - 15)
            fail("the grouped velocity drag did not adjust its anchor");
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &bAdjusted) ||
            int(bAdjusted.velocity) != int(bGrouped.velocity) - 15)
            fail("the grouped velocity drag did not adjust the other selected note");
        if (doc.undoStack()->count() != groupCount + 1)
            fail("the grouped velocity drag did not push exactly one command");

        // Repeating the drag on the same selected anchor keeps the group and
        // applies the opposite delta to both notes.
        const int repeatCount = doc.undoStack()->count();
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, a.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, a.center - QPoint(0, 15), Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, a.center - QPoint(0, 15),
                                  Qt::LeftButton, Qt::NoButton, Qt::ControlModifier);
        DocNote aRepeated, bRepeated;
        if (view.selectionModel().noteSelection() != std::vector<NoteId>({aId, bId}))
            fail("repeating a grouped velocity drag did not preserve the selected notes");
        if (!doc.findNote(track, a.tick, uint8_t(a.key), &aRepeated) ||
            !sameNoteFields(aRepeated, aGrouped))
            fail("repeating the grouped velocity drag did not restore its anchor");
        if (!doc.findNote(track, b.tick, uint8_t(b.key), &bRepeated) ||
            !sameNoteFields(bRepeated, bGrouped))
            fail("repeating the grouped velocity drag did not restore the other selected note");
        if (doc.undoStack()->count() != repeatCount + 1)
            fail("the repeated grouped velocity drag did not push exactly one command");

        doc.undoStack()->undo();
        doc.undoStack()->undo();
        doc.undoStack()->undo();
        doc.undoStack()->undo();
        doc.undoStack()->undo(); // restore both fixture velocities for later checks
        view.selectionModel().clearNoteSelection();
    }

    // Ordinary-mode move release: with Scale Fold forced off, a plain body
    // press (well clear of the edge resize grips) on a wide note drags the
    // document's own note, not just a visual preview. The release must
    // commit the same NoteId at the target position, vacate the old one,
    // and leave exactly that id selected — and the still-selected note must
    // answer a standard arrow nudge without being reselected. A release
    // that only reverts the preview, or strands the next arrow, fails here.
    {
        const SongView::ViewState viewBefore = view.viewState();
        const bool foldBefore = view.scaleFold();
        view.setScaleFold(false);
        const Cell cell = check.findFreeCell();
        if (cell.key < 0) {
            fail("no free grid cell for the non-Scale move");
            view.setScaleFold(foldBefore);
            return ScenarioContinuation::Stop;
        }
        const uint64_t snap = view.snapTicksAt(cell.tick);
        const qreal cellPx =
            view.contentX(double(cell.tick + snap)) - view.contentX(double(cell.tick));
        uint64_t widthTicks = snap * 4;
        while (pianoKeyboardWidth + view.contentX(double(cell.tick + widthTicks)) >
                   roll->width() - 4 &&
               widthTicks > snap * 2)
            widthTicks -= snap;
        if (check.isOccupied(cell.tick, widthTicks, cell.key)) {
            fail("no free span for the non-Scale move");
            view.setScaleFold(foldBefore);
            return ScenarioContinuation::Stop;
        }
        const int undoBase = doc.undoStack()->index();
        doc.addNote(track, cell.tick, uint8_t(cell.key), uint32_t(widthTicks), 93);
        QCoreApplication::processEvents(); // the view model must see the note before the press
        if (doc.undoStack()->index() != undoBase + 1)
            fail("the wide non-Scale probe add did not push exactly one command");
        DocNote probe;
        if (!doc.findNote(track, cell.tick, uint8_t(cell.key), &probe))
            fail("the wide non-Scale probe note did not commit");
        const NoteId moveId = probe.noteId;
        // Press the body center: whole snap cells of width keep the point
        // clear of the edge grips on both sides.
        const int bodyX = qRound((view.contentX(double(cell.tick)) +
                                  view.contentX(double(cell.tick + widthTicks))) /
                                 2.0) +
                          pianoKeyboardWidth;
        const QPoint body(bodyX, rows.centerY(cell.key));
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, body, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        if (view.selectionModel().noteSelection() != std::vector<NoteId>{moveId})
            fail("the body press did not grab the note as the whole selection");
        // Drag exactly two snap cells right: the move preview snaps the
        // grabbed offset to the press tick's grid, so the destination is
        // deterministic, and two cells clear any drag threshold.
        const QPoint target(body + QPoint(qRound(cellPx * 2.0), 0));
        checks::events::sendMouse(*roll, QEvent::MouseMove, target, Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
        if (doc.undoStack()->index() != undoBase + 1)
            fail("the move preview mutated the document before release");
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, target, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        DocNote moved;
        if (!doc.findNote(moveId, &moved) || moved.tick != cell.tick + 2 * snap ||
            moved.key != cell.key || moved.duration != widthTicks)
            fail("the non-Scale move release did not commit the same NoteId at its target");
        DocNote stranded;
        if (doc.findNote(track, cell.tick, uint8_t(cell.key), &stranded))
            fail("the non-Scale move release left a note at the old position");
        if (view.selectionModel().noteSelection() != std::vector<NoteId>{moveId})
            fail("the non-Scale move release did not leave exactly the moved note selected");
        if (doc.undoStack()->index() != undoBase + 2)
            fail("the non-Scale move release did not push exactly one command");
        // Without reselecting, the standard arrow must move the same
        // still-selected NoteId: a release that strands the gesture would
        // leave the note here.
        sendKeyStroke(*roll, Qt::Key_Right, Qt::NoModifier, false);
        DocNote nudged;
        if (!doc.findNote(moveId, &nudged) || nudged.tick != cell.tick + 3 * snap ||
            nudged.key != cell.key)
            fail("the post-release Right nudge did not move the same NoteId");
        if (view.selectionModel().noteSelection() != std::vector<NoteId>{moveId})
            fail("the Right nudge did not keep the moved note selected");
        if (doc.undoStack()->index() != undoBase + 3)
            fail("the Right nudge did not push exactly one command");
        while (doc.undoStack()->index() > undoBase && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
        view.selectionModel().clearNoteSelection();
        view.setScaleFold(foldBefore);
        view.applyViewState(viewBefore); // the nudge's keep-in-sight scroll must not leak
        (void)view.grab();               // consume the restoration repaint before later probes
        QCoreApplication::processEvents();
    }

    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
