#include "checks/rollcheck/rollcheck.h"

#include <QApplication>
#include <QColor>
#include <QEvent>
#include <QImage>
#include <QPixmap>
#include <QPoint>
#include <QRectF>
#include <QTimer>
#include <QWidget>
#include <algorithm>
#include <cmath>
#include <vector>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"

#include "ui/songview/otherstrip.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelinequickview.h"
namespace checks::rollcheck {

ScenarioContinuation runKeyboardAndTimelineScenarios(Harness &check, const ResizeFixture &fixture)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    QWidget *roll = &check.roll();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const SnappedRows rows{view, *roll};
    const Cell &d = fixture.cell;
    const uint64_t snapCell = fixture.snapCell;
    const int rowY = rows.centerY(d.key);
    const int undoBaseline = doc.undoStack()->index();
    auto fail = [&](const char *what) { check.fail(what); };
    // Keyboard transpose/nudge on note D (clicking it selects it):
    // Up is a semitone, Shift+Down an octave, and Right
    // moves one snap cell from an on-grid start.
    const QPoint dCenter(
        pianoKeyboardWidth + view.contentX(double(d.tick) + 0.5 * double(snapCell)), rowY);
    click(*roll, dCenter);
    sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false);
    DocNote transposed;
    if (!doc.findNote(track, d.tick, uint8_t(d.key + 1), &transposed))
        fail("Up did not transpose up a semitone");
    sendKeyStroke(*roll, Qt::Key_Down, Qt::ShiftModifier, false);
    if (!doc.findNote(track, d.tick, uint8_t(d.key - 11), &transposed))
        fail("Shift+Down did not transpose down an octave");
    sendKeyStroke(*roll, Qt::Key_Right, Qt::NoModifier, false);
    if (!doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 11), &transposed))
        fail("Right did not nudge one snap cell right");
    // An off-grid selection nudges onto the grid line, not by a whole
    // cell: push the note half a snap cell right behind the view's back
    // (reselecting — the selection keys on the start tick, which moved),
    // and Left must bring it back to the line it left.
    doc.moveNotes({transposed}, int64_t(snapCell / 2), 0);
    view.selectionModel().setNoteSelection({transposed.noteId});
    sendKeyStroke(*roll, Qt::Key_Left, Qt::NoModifier, false);
    if (!doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 11), &transposed))
        fail("Left did not snap the off-grid note back to the grid");

    // Keyboard moves keep the notes in view, scrolling just enough rather
    // than re-anchoring. Vertical: park the note's row above the viewport,
    // and Up must land it flush at the top edge.
    const int keyNow = d.key - 11;
    view.scrollRollBy((129 - keyNow) * view.keyHeight() - view.scrollY());
    if ((128 - keyNow) * view.keyHeight() - view.scrollY() > 1e-9)
        fail("could not park the note's row above the viewport");
    sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false);
    if (std::abs(view.scrollY() - (126 - keyNow) * view.keyHeight()) > 1e-9)
        fail("Up above the viewport did not scroll the row flush to the top");
    sendKeyStroke(*roll, Qt::Key_Down, Qt::NoModifier, false); // undo the extra semitone

    // Horizontal: park the note past the left edge; nudging right must
    // bring its start flush to the left edge (minimal scroll, not the
    // paste jump). Then ride it right across the viewport: once the end
    // crosses the right edge, it must stay flush there.
    uint64_t nStart = d.tick + snapCell;
    const qreal dpr = roll->devicePixelRatioF();
    const qreal physicalPixel = dpr > 0.0 ? 1.0 / dpr : 1.0;
    view.scrollByPx(view.contentX(double(nStart + snapCell)) + 40);
    if (view.displayX(double(nStart + snapCell), 0.0, dpr) >= 0.0)
        fail("could not park the note past the left edge");
    sendKeyStroke(*roll, Qt::Key_Right, Qt::NoModifier, false);
    nStart += snapCell;
    if (view.displayX(double(nStart), 0.0, dpr) != 0.0)
        fail("Right off-screen-left did not scroll the start flush to the "
             "left edge");
    const qreal vw = std::max(50, roll->width() - pianoKeyboardWidth);
    const qreal cellPx = view.contentX(double(nStart + snapCell)) - view.contentX(double(nStart));
    const int rides = (vw - view.contentX(double(nStart + snapCell))) / cellPx + 2;
    for (int i = 0; i < rides; i++)
        sendKeyStroke(*roll, Qt::Key_Right, Qt::NoModifier, false);
    nStart += uint64_t(rides) * snapCell;
    if (view.displayX(double(nStart + snapCell), 0.0, dpr) != vw - physicalPixel)
        fail("riding the nudge right did not keep the note's end at the right edge");
    // Ride back home so the time-selection checks below find the note
    // where they expect it; every press so far merges into one command.
    for (int i = 0; i < rides + 1; i++)
        sendKeyStroke(*roll, Qt::Key_Left, Qt::NoModifier, false);
    if (!doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 11), &transposed))
        fail("the ride right and back did not return the note home");

    // Consecutive keyboard presses on the same notes merge into one undo
    // command; mark a save point so the time-selection presses below get
    // their own commands (merges never cross the stack's clean index).
    doc.undoStack()->setClean();
    {
        const songview::TimelineBand rulerBand = view.timelineBands().front();
        QWidget *ruler = &rulerBand.widget;
        const qreal rulerDpr = ruler->devicePixelRatioF();
        const uint64_t startTick = d.tick + snapCell;
        const uint64_t endTick = d.tick + 2 * snapCell;
        const QPoint start(
            qRound(view.displayX(double(startTick), rulerBand.timelineOrigin, rulerDpr)),
            ruler->height() - 2);
        const QPoint end(qRound(view.displayX(double(endTick), rulerBand.timelineOrigin, rulerDpr)),
                         ruler->height() - 2);

        view.selectionModel().clearTimeSelection();
        view.selectionModel().applyTrackScopeAdjustment(
            track, 0xffffu, songview::EditorSelectionModel::TrackScopeAction::Plain);
        if (doc.engineTrackCount() > 1) {
            const int priorSecondary = track == 0 ? 1 : 0;
            view.selectionModel().applyTrackScopeAdjustment(
                priorSecondary, 0xffffu, songview::EditorSelectionModel::TrackScopeAction::Toggle);
        }
        // Modifier changes after the press do not change this plain sweep.
        checks::events::sendMouse(*ruler, QEvent::MouseButtonPress, start, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*ruler, QEvent::MouseMove, end, Qt::NoButton, Qt::LeftButton,
                                  Qt::ControlModifier);
        checks::events::sendMouse(*ruler, QEvent::MouseButtonRelease, end, Qt::LeftButton,
                                  Qt::NoButton, Qt::ControlModifier);
        if (!view.selectionModel().timeSelection().active() ||
            view.selectionModel().timeSelection().startTick != startTick ||
            view.selectionModel().timeSelection().endTick != endTick ||
            view.selectionModel().storedTrackScope() != (uint32_t{1} << track))
            fail("plain ruler drag did not create a primary-only time selection");

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
        QWidget *secondaryHeader =
            scopedGhost ? view.findChild<QWidget *>(
                              QStringLiteral("trackHeaderRow%1").arg(scopedGhost->track))
                        : nullptr;
        const QImage plainHeader = secondaryHeader ? secondaryHeader->grab().toImage() : QImage{};
        // Ctrl is captured at press even though it is absent from move/release.
        checks::events::sendMouse(*ruler, QEvent::MouseButtonPress, start, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*ruler, QEvent::MouseMove, end, Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
        checks::events::sendMouse(*ruler, QEvent::MouseButtonRelease, end, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        if (view.selectionModel().timeSelection().startTick != startTick ||
            view.selectionModel().timeSelection().endTick != endTick ||
            view.selectionModel().storedTrackScope() != expectedScope)
            fail("modified ruler drag did not derive the overlapping note-track scope");
        if (!scopedGhost) {
            fail("modified ruler drag fixture has no overlapping secondary-track note");
        } else {
            const SongView::ViewState priorViewState = view.viewState();
            SongView::ViewState ghostViewState = priorViewState;
            ghostViewState.scrollY =
                std::max(0.0, (127.5 - double(scopedGhost->key)) * ghostViewState.keyHeight -
                                  roll->height() / 2.0);
            view.applyViewState(ghostViewState);
            const SnappedRows ghostRows{view, *roll};
            const QRectF ghostBox = ghostRows.noteBox(ghostRows.noteRect(
                view.displayX(double(scopedGhost->startTick), pianoKeyboardWidth, ghostRows.dpr()),
                view.displayX(double(scopedGhost->endTick), pianoKeyboardWidth, ghostRows.dpr()),
                scopedGhost->key));
            const QRectF visibleGhostBox = ghostBox.intersected(
                QRectF(pianoKeyboardWidth, 0.0, qreal(roll->width() - pianoKeyboardWidth),
                       qreal(roll->height())));
            const QImage scopedImage = check.captureQuickFramebuffer();
            if (visibleGhostBox.isEmpty()) {
                fail("time-scoped ghost note is outside the horizontal viewport");
            } else {
                const qreal scopedDpr = scopedImage.devicePixelRatio();
                const int centerX = qRound(visibleGhostBox.center().x() * scopedDpr);
                const int bottomY = qRound(visibleGhostBox.bottom() * scopedDpr) - 1;
                if (!isSelectionRingColor(scopedImage.pixel(centerX, bottomY)))
                    fail("time-scoped ghost note did not render its selection ring");
            }
            view.applyViewState(priorViewState);
            auto *pianoRoll = static_cast<songview::PianoRoll *>(roll);
            auto *otherStrip = static_cast<songview::OtherStrip *>(
                view.findChild<QWidget *>(QStringLiteral("otherEventsStrip")));
            if (!otherStrip)
                fail("could not find the other-events strip");
            const songview::TimelineBand stripBand = view.timelineBands().back();
            const StripItem *trackEvent = nullptr;
            for (const StripItem &item : view.model().strip) {
                if (item.track >= 0) {
                    trackEvent = &item;
                    break;
                }
            }
            if (!trackEvent)
                fail("timeline fixture has no track-colored other-events marker");
            const double originalScroll = view.viewState().scrollPx;
            if (otherStrip && trackEvent) {
                const qreal visibleContentX =
                    std::max<qreal>(1.0, (otherStrip->width() - stripBand.timelineOrigin) / 3.0);
                view.setEditorHorizontalScroll(
                    originalScroll + view.contentX(double(trackEvent->tick)) - visibleContentX);
                QCoreApplication::processEvents();
            }
            const QImage beforeStripImage =
                otherStrip ? check.captureQuickBand(*otherStrip) : QImage{};
            auto movedSelection = view.selectionModel().timeSelection();
            ++movedSelection.endTick;
            view.selectionModel().setTimeSelection(movedSelection);
            QCoreApplication::processEvents();
            const QImage partialSelectionImage = check.captureQuickFramebuffer();
            const QImage afterStripImage =
                otherStrip ? check.captureQuickBand(*otherStrip) : QImage{};
            if (beforeStripImage.isNull() || afterStripImage.isNull() ||
                beforeStripImage != afterStripImage) {
                fail("moving a time selection changed the other-events strip pixels");
            }
            if (trackEvent && !afterStripImage.isNull()) {
                const qreal stripDpr = afterStripImage.devicePixelRatioF();
                const int markerX = qRound(
                    view.displayX(double(trackEvent->tick), stripBand.timelineOrigin, stripDpr) *
                    stripDpr);
                const int plotLeft = qRound(stripBand.timelineOrigin * stripDpr);
                const int markerY = afterStripImage.height() / 2;
                const QRgb expected = SongView::trackColor(trackEvent->track).rgba();
                bool foundMarker = false;
                for (int y = markerY - 2; y <= markerY + 2 && !foundMarker; ++y) {
                    for (int x = markerX - 2; x <= markerX + 2; ++x) {
                        if (x >= plotLeft && y >= 0 && x < afterStripImage.width() &&
                            y < afterStripImage.height() &&
                            afterStripImage.pixel(x, y) == expected) {
                            foundMarker = true;
                            break;
                        }
                    }
                }
                if (markerX < plotLeft || markerX >= afterStripImage.width())
                    fail("track-colored other-events marker was not positioned in the plot");
                else if (!foundMarker)
                    fail("other-events strip did not render a visible track-colored diamond");
            }
            pianoRoll->requestQuickUpdate(songview::PianoRollQuickDirty::All);
            QCoreApplication::processEvents();
            if (partialSelectionImage != check.captureQuickFramebuffer())
                fail("partial time-selection repaint differed from a full repaint");
            view.setEditorHorizontalScroll(originalScroll);
            QCoreApplication::processEvents();
            view.selectionModel().setTimeSelection(
                {startTick, endTick, songview::EditorSelectionModel::TimeSelection::Tracks});
            QCoreApplication::processEvents();
            const QImage selectedHeader =
                secondaryHeader ? secondaryHeader->grab().toImage() : QImage{};
            if (plainHeader.isNull() || selectedHeader.isNull() || plainHeader == selectedHeader)
                fail("time-scoped secondary header did not render its selection indicator");
        }
        const QPoint outsideSelection(
            qRound(view.displayX(double(endTick + snapCell), rulerBand.timelineOrigin, rulerDpr)),
            ruler->height() - 2);
        checks::events::sendMouse(*ruler, QEvent::MouseButtonPress, outsideSelection,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*ruler, QEvent::MouseButtonRelease, outsideSelection,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        if (!view.selectionModel().timeSelection().active())
            fail("left-clicking the timeline ruler outside the time selection cleared it");

        view.selectionModel().clearTimeSelection();
        checks::events::sendMouse(*ruler, QEvent::MouseButtonPress, start, Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*ruler, QEvent::MouseMove, end, Qt::NoButton, Qt::RightButton,
                                  Qt::NoModifier);
        if (view.selectionModel().timeSelection().active())
            fail("right-dragging the timeline ruler still created a time selection");
        QTimer::singleShot(0, [] {
            if (QWidget *menu = QApplication::activePopupWidget()) {
                menu->close();
            } else if (QWidget *menu = QApplication::activeModalWidget()) {
                menu->close();
            }
        });
        checks::events::sendMouse(*ruler, QEvent::MouseButtonRelease, end, Qt::RightButton,
                                  Qt::NoButton, Qt::NoModifier);
    }

    // The same shortcuts on a time selection (no notes selected): the band
    // over the note's cell transposes every covered note of the scoped
    // tracks, and a nudge moves the contents with the band following.
    songview::EditorSelectionModel::TimeSelection band;
    band.startTick = d.tick + snapCell;
    band.endTick = d.tick + 2 * snapCell;
    view.selectionModel().setTimeSelection(band);
    {
        const QRectF selectedByTimeBox = rows.noteBox(
            rows.noteRect(view.displayX(double(transposed.tick), pianoKeyboardWidth, rows.dpr()),
                          view.displayX(double(transposed.tick + transposed.duration),
                                        pianoKeyboardWidth, rows.dpr()),
                          transposed.key));
        const QImage selectedByTimeImage = check.captureQuickFramebuffer();
        const qreal selectedByTimeDpr = selectedByTimeImage.devicePixelRatio();
        const int centerX = qRound(selectedByTimeBox.center().x() * selectedByTimeDpr);
        const int bottomY = qRound(selectedByTimeBox.bottom() * selectedByTimeDpr) - 1;
        if (!isSelectionRingColor(selectedByTimeImage.pixel(centerX, bottomY)))
            fail("time-selected note did not show the normal selection ring");
        if (!view.selectionModel().noteSelection().empty())
            fail("time-selected note leaked into the explicit note selection");
    }
    {
        const uint64_t emptyTick = band.startTick + (band.endTick - band.startTick) / 2;
        int emptyKey = -1;
        for (int key = 0; key < 128 && emptyKey < 0; ++key) {
            const int y = rows.centerY(key);
            if (y < 0 || y >= roll->height())
                continue;
            const bool occupied =
                std::any_of(view.model().notes.cbegin(), view.model().notes.cend(),
                            [track, key, emptyTick](const ViewNote &note) {
                                return note.track == track && note.key == key &&
                                       note.startTick <= emptyTick && emptyTick < note.endTick;
                            });
            if (!occupied)
                emptyKey = key;
        }
        if (emptyKey < 0) {
            fail("could not find empty roll space inside the time selection");
        } else {
            const QPoint emptyInside(
                qRound(view.displayX(double(emptyTick), pianoKeyboardWidth, rows.dpr())),
                rows.centerY(emptyKey));
            click(*roll, emptyInside);
            if (view.selectionModel().timeSelection().active())
                fail("left-clicking empty space inside the time selection did not clear it");
            view.selectionModel().setTimeSelection(band);
        }
    }
    sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false);
    if (!doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 10), &transposed))
        fail("time-selection Up did not transpose the covered note");
    sendKeyStroke(*roll, Qt::Key_Right, Qt::NoModifier, false);
    if (!doc.findNote(track, d.tick + 2 * snapCell, uint8_t(d.key - 10), &transposed))
        fail("time-selection Right did not nudge the covered note");
    if (view.selectionModel().timeSelection().startTick != d.tick + 2 * snapCell)
        fail("time-selection band did not follow the nudge");

    // Duplicate Time uses the active range as its source, advances the band
    // and edit cursor to the newly-created copy, and repeats from that copy.
    {
        const songview::EditorSelectionModel::TimeSelection duplicateSource =
            view.selectionModel().timeSelection();
        const uint64_t duplicateSpan = duplicateSource.endTick - duplicateSource.startTick;
        const int duplicateUndoIndex = doc.undoStack()->index();
        const uint8_t duplicateKey = transposed.key;
        const auto hasNoteAt = [&](uint64_t tick) {
            DocNote note;
            return doc.findNote(track, tick, duplicateKey, &note);
        };
        sendKeyStroke(*roll, Qt::Key_D, Qt::ControlModifier, false);
        const uint64_t firstStart = duplicateSource.endTick;
        const uint64_t firstEnd = firstStart + duplicateSpan;
        const songview::EditorSelectionModel::TimeSelection firstSelection =
            view.selectionModel().timeSelection();
        if (doc.undoStack()->index() != duplicateUndoIndex + 1 || !firstSelection.active() ||
            firstSelection.startTick != firstStart || firstSelection.endTick != firstEnd ||
            view.editCursorTick() != firstEnd || !hasNoteAt(firstStart)) {
            fail("Ctrl+D did not duplicate once and advance the time selection");
        }
        const qreal duplicateDpr = roll->devicePixelRatioF();
        const qreal duplicateViewport = std::max(50, roll->width() - pianoKeyboardWidth);
        if (view.displayX(double(firstStart), 0.0, duplicateDpr) < 0.0 ||
            view.displayX(double(firstEnd), 0.0, duplicateDpr) > duplicateViewport) {
            fail("first duplicated range was not made visible");
        }
        sendKeyStroke(*roll, Qt::Key_D, Qt::ControlModifier, false);
        const uint64_t secondStart = firstEnd;
        const uint64_t secondEnd = secondStart + duplicateSpan;
        const songview::EditorSelectionModel::TimeSelection secondSelection =
            view.selectionModel().timeSelection();
        if (doc.undoStack()->index() != duplicateUndoIndex + 2 || !secondSelection.active() ||
            secondSelection.startTick != secondStart || secondSelection.endTick != secondEnd ||
            view.editCursorTick() != secondEnd || !hasNoteAt(secondStart)) {
            fail("repeating Ctrl+D did not duplicate the newest copy");
        }
        while (doc.undoStack()->index() > duplicateUndoIndex && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
        view.selectionModel().clearTimeSelection();
    }

    // Insert Blank Time keeps a track-scoped band and cursor while leaving a
    // note on an unselected track untouched.
    const uint64_t insertStart = d.tick + 2 * snapCell;
    const uint64_t insertEnd = insertStart + snapCell;
    if (doc.engineTrackCount() >= 2) {
        const int fixtureUndoIndex = doc.undoStack()->index();
        const int otherTrack = track == 0 ? 1 : 0;
        int otherKey = 12;
        while (otherKey < 128) {
            DocNote existing;
            if (!doc.findNote(otherTrack, insertStart, uint8_t(otherKey), &existing))
                break;
            otherKey++;
        }
        if (otherKey >= 128) {
            fail("could not reserve an unselected-track insert fixture");
        } else {
            const uint8_t otherPitch = uint8_t(otherKey);
            doc.addNote(otherTrack, insertStart, otherPitch, uint32_t(snapCell), 91);
            DocNote otherBefore;
            if (!doc.findNote(otherTrack, insertStart, otherPitch, &otherBefore)) {
                fail("could not create the unselected-track insert fixture");
            } else {
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
                    otherAfter.tick == otherBefore.tick &&
                    otherAfter.duration == otherBefore.duration &&
                    otherAfter.key == otherBefore.key &&
                    otherAfter.velocity == otherBefore.velocity;
                const bool selectedShifted =
                    doc.findNote(track, insertEnd, transposed.key, &selectedAfter);
                const songview::EditorSelectionModel::TimeSelection insertedSelection =
                    view.selectionModel().timeSelection();
                if (doc.undoStack()->index() != insertUndoIndex + 1 || !otherStable ||
                    !selectedShifted || !insertedSelection.active() ||
                    insertedSelection.startTick != insertStart ||
                    insertedSelection.endTick != insertEnd ||
                    insertedSelection.scope !=
                        songview::EditorSelectionModel::TimeSelection::Tracks ||
                    view.editCursorTick() != insertStart) {
                    fail("Insert Blank Time changed scope, cursor, or an unselected track");
                }
                doc.undoStack()->undo();
                view.selectionModel().clearTimeSelection();
            }
        }
        while (doc.undoStack()->index() > fixtureUndoIndex && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
    }

    // A lane-scoped insertion shifts only the selected lane; notes on the
    // same track stay fixed, proving the resolver does not widen lane scope.
    {
        const int fixtureUndoIndex = doc.undoStack()->index();
        const uint8_t laneCc = 7;
        const uint64_t lanePointTick = insertStart + snapCell / 2;
        doc.addLanePoint(track, laneCc, lanePointTick, 80);
        DocLanePoint laneBefore;
        DocNote laneNoteBefore;
        if (!doc.findLanePoint(track, laneCc, lanePointTick, &laneBefore) ||
            !doc.findNote(track, insertStart, transposed.key, &laneNoteBefore)) {
            fail("could not create the lane-scoped insert fixture");
        } else {
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
            const bool noteStable =
                doc.findNote(track, insertStart, transposed.key, &laneNoteAfter) &&
                laneNoteAfter.tick == laneNoteBefore.tick &&
                laneNoteAfter.duration == laneNoteBefore.duration &&
                laneNoteAfter.key == laneNoteBefore.key &&
                laneNoteAfter.velocity == laneNoteBefore.velocity;
            const songview::EditorSelectionModel::TimeSelection insertedSelection =
                view.selectionModel().timeSelection();
            if (doc.undoStack()->index() != insertUndoIndex + 1 || !laneShifted || !noteStable ||
                !insertedSelection.active() ||
                insertedSelection.scope != songview::EditorSelectionModel::TimeSelection::Lanes ||
                insertedSelection.lanes != laneSelection.lanes ||
                insertedSelection.startTick != insertStart ||
                insertedSelection.endTick != insertEnd || view.editCursorTick() != insertStart) {
                fail("lane-scoped Insert Blank Time widened its scope or moved the band");
            }
            doc.undoStack()->undo();
            view.selectionModel().clearTimeSelection();
        }
        while (doc.undoStack()->index() > fixtureUndoIndex && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
    }

    if (doc.undoStack()->index() != undoBaseline + 5)
        fail("gesture pass pushed an unexpected number of undo commands");
    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
