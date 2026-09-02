#include "checks/rollcheck/rollcheck.h"

#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QLineEdit>
#include <QMetaObject>
#include <QObject>
#include <QPaintEvent>
#include <QPoint>
#include <QRegion>
#include <QToolButton>
#include <QWidget>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

#include "checks/rollcheckplayhead.h"
#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/activity/trackactivityview.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"

namespace checks::rollcheck {

namespace {

class PaintRegionProbe final : public QObject
{
  public:
    void clear() { m_region = {}; }
    const QRegion &region() const { return m_region; }

  protected:
    bool eventFilter(QObject *, QEvent *event) override
    {
        if (event->type() == QEvent::Paint)
            m_region |= static_cast<QPaintEvent *>(event)->region();
        return false;
    }

  private:
    QRegion m_region;
};

} // namespace

ScenarioContinuation runHeaderAndPresentationScenarios(Harness &check,
                                                       const PencilVelocityFixture &fixture,
                                                       const QString &screenshotPath)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem *roll = &check.rollInput();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const SnappedRows rows{view, *roll};
    const Cell &a = fixture.a;
    const qreal vw = std::max<qreal>(50, roll->width() - pianoKeyboardWidth);
    const int undoBaseline = doc.undoStack()->index();
    auto fail = [&](const char *what) { check.fail(what); };
    // The suite-wide click() helper targets the roll's Quick input item, so
    // the widget-based header rows press/release through the synth directly.
    const auto clickWidget = [](QWidget &widget, QPoint position) {
        checks::events::sendMouse(widget, QEvent::MouseButtonPress, position, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(widget, QEvent::MouseButtonRelease, position, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
    };
    // Playhead follow-scroll pauses while a mouse gesture is live: with a
    // middle-button pan held in the roll (or the lanes), a playing playhead
    // far past the right edge must not move the view; releasing the button
    // lets the next playhead tick scroll again.
    auto *lanes = view.findChild<QWidget *>(QStringLiteral("automationCanvas"));
    if (!lanes)
        fail("automation area not found");
    // The roll is the Quick input item and the lanes stay a widget; both run
    // the same middle-drag pan probe against their own input surface.
    const auto panFollowProbe = [&](auto &panned) {
        const int home = view.contentX(0.0);
        const uint64_t farTick = uint64_t(std::max(0.0, view.tickAtContentX(vw * 2)));
        const QPointF mid(panned.width() / 2.0, panned.height() / 2.0);
        checks::events::sendMouse(panned, QEvent::MouseButtonPress, mid, Qt::MiddleButton,
                                  Qt::MiddleButton, Qt::NoModifier);
        view.setPlayheadSample(check.timeline().sampleForTick(farTick), true);
        if (view.contentX(0.0) != home)
            fail("playhead follow-scroll moved the view during a pan gesture");
        checks::events::sendMouse(panned, QEvent::MouseButtonRelease, mid, Qt::MiddleButton,
                                  Qt::NoButton, Qt::NoModifier);
        view.setPlayheadSample(check.timeline().sampleForTick(farTick), true);
        if (view.contentX(0.0) == home)
            fail("playhead follow-scroll did not resume after the pan ended");
        view.setPlayheadSample(0, false);
        view.scrollByPx(view.contentX(0.0) - home); // back where it started
    };
    panFollowProbe(*roll);
    if (lanes)
        panFollowProbe(*lanes);

    // A stopped playhead uses retained Quick chrome. Moving it must preserve
    // timeline scene-layer revisions instead of rebuilding their contents.
    for (const QString &error : timelineChromeCheckFailures(view, check.timeline()))
        fail(qUtf8Printable(error));

    // Inline track rename: renameTrack opens a line editor on the header
    // row; Return commits (queued past the panel rebuild), Escape discards,
    // and loop-marker names are refused. isHidden (not isVisible) because
    // the view is never shown offscreen.
    {
        view.renameTrack(track);
        auto *editor = view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
        if (!editor || editor->isHidden()) {
            fail("rename editor did not open");
        } else {
            editor->setText(QStringLiteral("Rolled"));
            sendKeyStroke(*editor, Qt::Key_Return, Qt::NoModifier, false);
            QCoreApplication::processEvents(); // the queued document commit
            if (doc.trackName(track) != QStringLiteral("Rolled"))
                fail("inline rename did not apply on Return");
        }
        view.renameTrack(track); // the rebuilt panel carries a fresh editor
        editor = view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
        if (!editor || editor->isHidden()) {
            fail("rename editor did not reopen after the rebuild");
        } else {
            editor->setText(QStringLiteral("Discarded"));
            sendKeyStroke(*editor, Qt::Key_Escape, Qt::NoModifier, false);
            QCoreApplication::processEvents();
            if (doc.trackName(track) != QStringLiteral("Rolled"))
                fail("Escape did not discard the rename");
        }
        view.renameTrack(track);
        editor = view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
        if (editor && !editor->isHidden()) {
            const int commands = doc.undoStack()->count();
            editor->setText(QStringLiteral("["));
            sendKeyStroke(*editor, Qt::Key_Return, Qt::NoModifier, false);
            QCoreApplication::processEvents();
            if (doc.trackName(track) != QStringLiteral("Rolled") ||
                doc.undoStack()->count() != commands)
                fail("loop-marker name was not refused");
        }
    }
    bool seededHeaderProgram = false;

    // The header voice line is live: currentProgram is the last program
    // change at or before the display position — the playhead while playing,
    // the edit cursor otherwise — falling back to the track's first program
    // (which is what primes the engine before any change).
    {
        view.setEditCursorTick(0);
        const int base = view.currentProgram(track);
        const int atStart = base < 0 ? 4 : base;
        const int changed = atStart == 5 ? 6 : 5;
        const uint64_t vcTick = a.tick + 4 * a.dur;
        // Seed an empty voice lane so crossing vcTick is always a real
        // program transition, not the first-program fallback everywhere.
        if (base < 0) {
            doc.addLanePoint(track, DOC_CC_VOICE, 0, atStart);
            seededHeaderProgram = true;
        }
        doc.addLanePoint(track, DOC_CC_VOICE, vcTick, changed);
        if (view.currentProgram(track) != atStart)
            fail("voice label at the start did not show the priming program");
        view.setEditCursorTick(vcTick);
        if (view.currentProgram(track) != changed)
            fail("voice label did not follow the edit cursor past the change");
        view.setEditCursorTick(0);
        view.setPlayheadSample(check.timeline().sampleForTick(vcTick), true);
        if (view.currentProgram(track) != changed)
            fail("voice label did not follow the playing playhead");
        view.setPlayheadSample(0, false); // stopped: back to the edit cursor
        if (view.currentProgram(track) != atStart)
            fail("voice label did not return to the edit cursor after stop");

        // Retained rows paint an opaque base. Program-only changes invalidate
        // both text lines as one region, leaving buttons and the separator
        // untouched. Selection styling invalidates the full visible row; the
        // panel-owned opaque activity column clips its covered gutter.
        (void)view.grab();
        auto *row = view.findChild<QWidget *>(QStringLiteral("trackHeaderRow%1").arg(track));
        if (!row) {
            fail("track header row for repaint coverage not found");
        } else {
            if (!row->testAttribute(Qt::WA_OpaquePaintEvent))
                fail("track header row did not report opaque painting");

            const int gutter = layout::space(layout::Space::One);
            const int singlePixel = layout::singlePixel();
            const int textWidth = row->width() - layout::fontPx(1.5) - 2 * gutter;
            const QRect textColumn(gutter, 0, textWidth, row->height() - singlePixel);
            PaintRegionProbe paintProbe;
            row->installEventFilter(&paintProbe);

            view.show();
            QCoreApplication::sendPostedEvents();
            QCoreApplication::processEvents();
            const QImage beforeProgram = row->grab().toImage();
            QCoreApplication::sendPostedEvents();
            QCoreApplication::processEvents();
            paintProbe.clear();

            view.setEditCursorTick(vcTick);
            QCoreApplication::sendPostedEvents();
            QCoreApplication::processEvents();
            const QRegion programPaint = paintProbe.region();
            if (programPaint.isEmpty())
                fail("program change did not repaint the track header row");
            else if (!programPaint.subtracted(QRegion(textColumn)).isEmpty())
                fail("program change repainted outside the combined text column");
            const QImage afterProgram = row->grab().toImage();

            if (beforeProgram.isNull() || afterProgram.isNull()) {
                fail("program change did not produce track header rasters");
            } else if (beforeProgram.size() != afterProgram.size()) {
                fail("program change altered the track header raster size");
            } else {
                const qreal dpr = beforeProgram.devicePixelRatio();
                bool changedOutsideText = false;
                for (int y = 0; y < beforeProgram.height() && !changedOutsideText; ++y) {
                    for (int x = 0; x < beforeProgram.width(); ++x) {
                        const QPoint logical(int(x / dpr), int(y / dpr));
                        if (!textColumn.contains(logical) &&
                            beforeProgram.pixel(x, y) != afterProgram.pixel(x, y)) {
                            changedOutsideText = true;
                            break;
                        }
                    }
                }
                if (changedOutsideText)
                    fail("program change altered pixels outside the combined text column");
            }

            view.setEditCursorTick(0);
            const int previousPrimary = view.selectionModel().primaryTrack();
            view.selectTrack(track == 15 ? 14 : track + 1);
            QCoreApplication::sendPostedEvents();
            QCoreApplication::processEvents();
            paintProbe.clear();
            clickWidget(*row, QPoint(textColumn.center().x(), singlePixel));
            QCoreApplication::sendPostedEvents();
            QCoreApplication::processEvents();
            const int obscuredGutter = view.findChild<TrackActivityView *>() ? gutter : 0;
            const QRect visibleRow = row->rect().adjusted(obscuredGutter, 0, 0, 0);
            if (paintProbe.region().boundingRect() != visibleRow)
                fail("track selection change did not repaint the full visible header row");
            view.selectTrack(previousPrimary);
            QCoreApplication::sendPostedEvents();
            QCoreApplication::processEvents();
            view.hide();
        }
    }

    // Jump-from-context: a completed plain click on a header row's voice
    // line emits revealVoiceRequested with the track's current program (the
    // main window raises the voicegroup dock and selects the slot). A click
    // on the name line stays silent, as does a press there that turns into
    // a reorder drag — and none of it is an edit, so the undo stack must
    // not move.
    {
        (void)view.grab(); // layout pass: rows need real geometry
        auto *row = view.findChild<QWidget *>(QStringLiteral("trackHeaderRow%1").arg(track));
        if (!row) {
            fail("track header row for the edited track not found");
        } else {
            int revealed = -1, reveals = 0;
            const QMetaObject::Connection conn =
                QObject::connect(&view, &SongView::revealVoiceRequested, [&](int program) {
                    revealed = program;
                    reveals++;
                });
            const int preCount = doc.undoStack()->count();
            const QPoint voicePos(row->width() / 2, 30); // the painted voice line
            clickWidget(*row, voicePos);
            if (reveals != 1 || revealed != view.currentProgram(track))
                fail("voice-line click did not request the track's program");
            clickWidget(*row, QPoint(row->width() / 2, 10)); // the name line
            if (reveals != 1)
                fail("a name-line click requested a voice reveal");
            // A press on the voice line that becomes a reorder drag must
            // not reveal on release (adjacent drop slot: no move commits).
            checks::events::sendMouse(*row, QEvent::MouseButtonPress, voicePos, Qt::LeftButton,
                                      Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*row, QEvent::MouseMove, voicePos + QPoint(0, 25),
                                      Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*row, QEvent::MouseButtonRelease, voicePos + QPoint(0, 25),
                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            QCoreApplication::processEvents();
            if (reveals != 1)
                fail("a reorder drag from the voice line requested a reveal");
            const QPoint namePos(row->width() / 2, 10);
            checks::events::sendMouse(*row, QEvent::MouseButtonDblClick, namePos, Qt::LeftButton,
                                      Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*row, QEvent::MouseButtonRelease, namePos, Qt::LeftButton,
                                      Qt::NoButton, Qt::NoModifier);
            auto *renameEditor = view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
            if (!renameEditor || renameEditor->isHidden())
                fail("name-line double-click no longer opens the rename editor");
            else
                sendKeyStroke(*renameEditor, Qt::Key_Escape, Qt::NoModifier, false);
            if (doc.undoStack()->count() != preCount)
                fail("voice navigation touched the undo stack");
            QObject::disconnect(conn);
        }
    }

    // Header-row drag reorder (format 1 with two or more tracks): press the
    // first row, drag past the second row's center, release — the first two
    // tracks swap slots, the notes and the mute flag following, as ONE undo
    // command (committed queued, so the event loop must spin). A non-left
    // release mid-drag cancels instead of dropping, a rename editor still
    // open at the drop gets its text committed rather than destroyed, and
    // undo/redo re-permute the mute flag along with the tracks.
    bool reordered = false;
    bool dragRenamed = false;
    if (doc.engineTrackCount() >= 2) {
        // The panel was rebuilt by the edits above; force a layout pass so
        // the rows have real positions for the drop-slot hit test.
        (void)view.grab();
        auto *row0 = view.findChild<QWidget *>(QStringLiteral("trackHeaderRow0"));
        auto *row1 = view.findChild<QWidget *>(QStringLiteral("trackHeaderRow1"));
        if (!row0 || !row1) {
            fail("track header rows not found");
        } else {
            const auto firstNotes = doc.notesForTrack(0);
            view.setTrackMute(0, true);
            // Press low in the row, clear of the rename editor overlaying
            // the name line.
            const QPoint start(row0->width() / 2, row0->height() * 3 / 4);
            // Past row 1's center in row-0 coordinates: rows are contiguous
            // and equal-height, so 1.6 row heights lands between row 1's
            // center (1.5) and its bottom.
            const QPoint drop(row0->width() / 2, row0->height() * 8 / 5);

            // A right-button release mid-drag cancels; the left release
            // that follows must not commit either.
            const int preDragCount = doc.undoStack()->count();
            checks::events::sendMouse(*row0, QEvent::MouseButtonPress, start, Qt::LeftButton,
                                      Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*row0, QEvent::MouseMove, drop, Qt::NoButton, Qt::LeftButton,
                                      Qt::NoModifier);
            checks::events::sendMouse(*row0, QEvent::MouseButtonRelease, drop, Qt::RightButton,
                                      Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*row0, QEvent::MouseButtonRelease, drop, Qt::LeftButton,
                                      Qt::NoButton, Qt::NoModifier);
            QCoreApplication::processEvents();
            if (doc.undoStack()->count() != preDragCount)
                fail("right-button release mid-drag committed the reorder");

            // An open rename editor rides along: the drop commits its text
            // Reaper-style (before the move, so it names the right track)
            // instead of silently discarding it with the rebuilt panel.
            view.renameTrack(0);
            auto *editor = view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
            if (editor && !editor->isHidden()) {
                editor->setText(QStringLiteral("Dragged"));
                dragRenamed = true;
            }

            checks::events::sendMouse(*row0, QEvent::MouseButtonPress, start, Qt::LeftButton,
                                      Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*row0, QEvent::MouseMove, drop, Qt::NoButton, Qt::LeftButton,
                                      Qt::NoModifier);
            checks::events::sendMouse(*row0, QEvent::MouseButtonRelease, drop, Qt::LeftButton,
                                      Qt::NoButton, Qt::NoModifier);
            // The queued rename commit, then the queued moveTrack commit.
            QCoreApplication::processEvents();
            const auto movedNotes = doc.notesForTrack(1);
            bool same = movedNotes.size() == firstNotes.size();
            for (size_t i = 0; same && i < movedNotes.size(); i++) {
                same = movedNotes[i].tick == firstNotes[i].tick &&
                       movedNotes[i].key == firstNotes[i].key;
            }
            if (!same) {
                fail("header drag did not move the track's notes to slot 1");
            } else if (!view.trackMuted(1) || view.trackMuted(0)) {
                fail("header drag did not move the mute flag with the track");
            } else {
                reordered = true;
                if (dragRenamed && doc.trackName(1) != QStringLiteral("Dragged"))
                    fail("the open rename editor's text was lost in the drop");
                // The complete TrackRemap re-addresses view state on undo
                // and redo too — the mute bit follows.
                doc.undoStack()->undo();
                if (!view.trackMuted(0) || view.trackMuted(1))
                    fail("undoing the move left the mute flag behind");
                doc.undoStack()->redo();
                if (!view.trackMuted(1) || view.trackMuted(0))
                    fail("redoing the move did not re-move the mute flag");
            }
            view.setTrackMute(1, false);
        }
    }
    // Three-row insertion-slot arithmetic: grow this two-track fixture with a
    // real duplicated track, then exercise both directions across two rows
    // plus the adjacent slot that must leave the row in place. Every probe
    // returns to the duplicate baseline; the final undo restores the original
    // two-track document and header state for the presentation checks below.
    const int twoTrackIndex = doc.undoStack()->index();
    const bool firstMute = view.trackMuted(0);
    const bool secondMute = view.trackMuted(1);
    const uint8_t firstChannel = doc.channelFor(0);
    const uint8_t secondChannel = doc.channelFor(1);
    const int duplicatedTrack = doc.duplicateTrack(1);
    if (duplicatedTrack < 0) {
        fail("could not create the third track for header reorder arithmetic");
    } else if (duplicatedTrack != 2 || doc.engineTrackCount() != 3 ||
               doc.undoStack()->index() != twoTrackIndex + 1) {
        fail("duplicating the header reorder fixture did not create one three-track edit");
    } else {
        QCoreApplication::processEvents();
        (void)view.grab(); // rebuild and lay out the added header row

        const int fixtureIndex = doc.undoStack()->index();
        const int fixtureTracks[] = {0, 1, duplicatedTrack};
        const uint8_t duplicateChannel = doc.channelFor(duplicatedTrack);
        const uint8_t trackIdentities[] = {firstChannel, secondChannel, duplicateChannel};
        const bool distinctIdentities = firstChannel != secondChannel &&
                                        firstChannel != duplicateChannel &&
                                        secondChannel != duplicateChannel;
        if (!distinctIdentities)
            fail("three-track header fixture channels are not distinct");
        const auto hasTrackOrder = [&](int first, int second, int third) {
            return distinctIdentities &&
                   doc.channelFor(fixtureTracks[0]) == trackIdentities[first] &&
                   doc.channelFor(fixtureTracks[1]) == trackIdentities[second] &&
                   doc.channelFor(fixtureTracks[2]) == trackIdentities[third];
        };
        auto dragToSlot = [&](int fromTrack, int slot) {
            (void)view.grab();
            auto *source =
                view.findChild<QWidget *>(QStringLiteral("trackHeaderRow%1").arg(fromTrack));
            const int targetRow = slot < 3 ? slot : 2;
            auto *target = view.findChild<QWidget *>(
                QStringLiteral("trackHeaderRow%1").arg(fixtureTracks[targetRow]));
            if (!source || !target) {
                fail("three-track header rows not found");
                return false;
            }
            const QPoint start(source->width() / 2, source->height() * 3 / 4);
            const QPoint targetPoint(target->width() / 2,
                                     target->height() * (slot < 3 ? 1 : 3) / 4);
            const QPoint drop = source->mapFromGlobal(target->mapToGlobal(targetPoint));
            checks::events::sendMouse(*source, QEvent::MouseButtonPress, start, Qt::LeftButton,
                                      Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*source, QEvent::MouseMove, drop, Qt::NoButton,
                                      Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*source, QEvent::MouseButtonRelease, drop, Qt::LeftButton,
                                      Qt::NoButton, Qt::NoModifier);
            QCoreApplication::processEvents();
            return true;
        };

        view.setTrackMute(fixtureTracks[0], false);
        view.setTrackMute(fixtureTracks[1], false);
        view.setTrackMute(duplicatedTrack, true);
        const int upwardIndex = doc.undoStack()->index();
        if (dragToSlot(duplicatedTrack, 0)) {
            const bool committed = doc.undoStack()->index() == upwardIndex + 1;
            if (!committed || !hasTrackOrder(2, 0, 1) || !view.trackMuted(fixtureTracks[0]) ||
                view.trackMuted(fixtureTracks[1]) || view.trackMuted(fixtureTracks[2])) {
                fail("upward header drag resolved to the wrong engine track");
            }
            if (doc.undoStack()->index() != upwardIndex)
                doc.undoStack()->setIndex(upwardIndex);
            if (doc.undoStack()->index() != upwardIndex || !hasTrackOrder(0, 1, 2) ||
                view.trackMuted(fixtureTracks[0]) || view.trackMuted(fixtureTracks[1]) ||
                !view.trackMuted(fixtureTracks[2])) {
                fail("undoing the upward header drag did not restore track identity");
            }
        }
        view.setTrackMute(duplicatedTrack, false);

        view.setTrackMute(fixtureTracks[0], true);
        const int downwardIndex = doc.undoStack()->index();
        if (dragToSlot(fixtureTracks[0], 3)) {
            const bool committed = doc.undoStack()->index() == downwardIndex + 1;
            if (!committed || !hasTrackOrder(1, 2, 0) || view.trackMuted(fixtureTracks[0]) ||
                view.trackMuted(fixtureTracks[1]) || !view.trackMuted(fixtureTracks[2])) {
                fail("downward header drag resolved to the wrong engine track");
            }
            if (doc.undoStack()->index() != downwardIndex)
                doc.undoStack()->setIndex(downwardIndex);
            if (doc.undoStack()->index() != downwardIndex || !hasTrackOrder(0, 1, 2) ||
                !view.trackMuted(fixtureTracks[0]) || view.trackMuted(fixtureTracks[1]) ||
                view.trackMuted(fixtureTracks[2])) {
                fail("undoing the downward header drag did not restore track identity");
            }
        }
        view.setTrackMute(fixtureTracks[0], false);

        view.setTrackMute(fixtureTracks[1], true);
        const int adjacentIndex = doc.undoStack()->index();
        if (dragToSlot(fixtureTracks[1], 2)) {
            const bool moved = doc.undoStack()->index() != adjacentIndex;
            if (moved || !hasTrackOrder(0, 1, 2) || view.trackMuted(fixtureTracks[0]) ||
                !view.trackMuted(fixtureTracks[1]) || view.trackMuted(fixtureTracks[2])) {
                fail("adjacent header insertion slot moved the track");
            }
            if (doc.undoStack()->index() != adjacentIndex)
                doc.undoStack()->setIndex(adjacentIndex);
        }
        view.setTrackMute(fixtureTracks[1], false);

        if (doc.undoStack()->index() != fixtureIndex)
            doc.undoStack()->setIndex(fixtureIndex);
    }
    if (doc.undoStack()->index() != twoTrackIndex)
        doc.undoStack()->setIndex(twoTrackIndex);
    QCoreApplication::processEvents();
    view.setTrackMute(0, firstMute);
    view.setTrackMute(1, secondMute);
    (void)view.grab(); // consume the two-track restoration rebuild
    if (doc.undoStack()->index() != twoTrackIndex || doc.engineTrackCount() != 2 ||
        doc.channelFor(0) != firstChannel || doc.channelFor(1) != secondChannel ||
        view.trackMuted(0) != firstMute || view.trackMuted(1) != secondMute ||
        view.document() != &doc) {
        fail("header reorder arithmetic did not restore the two-track fixture");
    }

    const auto screenshotTick =
        uint64_t(std::ceil(std::max(0.0, view.tickAtContentX(view.width() / 2))));
    view.setPlayheadSample(check.timeline().sampleForTick(screenshotTick), false);
    // Park the cursor mid-roll so the shot shows the hover mark + name chip.
    checks::events::sendMouse(*roll, QEvent::MouseMove,
                              QPointF(pianoKeyboardWidth + 60.0, roll->height() / 3.0),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    const QImage image = view.grab().toImage();
    if (image.isNull())
        fail("offscreen render produced no image");
    if (!screenshotPath.isEmpty()) {
        image.save(screenshotPath);
        std::printf("rollcheck: wrote %s\n", qUtf8Printable(screenshotPath));
    }

    // Polyphony-dock jump target: revealNote selects the losing track and
    // the lost note itself (the last note on (track, key) starting at or
    // before the event tick), without touching the undo stack.
    {
        const auto &notes = view.model().notes;
        if (notes.empty()) {
            fail("no notes in the view model for revealNote");
        } else {
            const ViewNote target = notes[notes.size() / 2];
            if (!view.revealNote(target.track, target.key, target.startTick))
                fail("revealNote did not find the note");
            if (view.selectionModel().primaryTrack() != int(target.track))
                fail("revealNote did not select the track");
            const auto &sel = view.selectionModel().noteSelection();
            if (sel.size() != 1 || !(sel[0] == target.noteId))
                fail("revealNote did not select the note");

            // A key the track never plays: no note found, but the track
            // selection sticks (the dock still switches context).
            bool used[128] = {};
            for (const ViewNote &note : notes) {
                if (note.track == target.track)
                    used[note.key] = true;
            }
            int freeKey = -1;
            for (int k = 0; k < 128 && freeKey < 0; k++) {
                if (!used[k])
                    freeKey = k;
            }
            if (freeKey >= 0) {
                if (view.revealNote(target.track, uint8_t(freeKey), target.startTick))
                    fail("revealNote found a note on an unused key");
                if (view.selectionModel().primaryTrack() != int(target.track))
                    fail("revealNote miss dropped the track selection");
            }
        }
    }

    // Keyboard mute/solo: bare M and S toggle the header buttons over the
    // multi-track scope — the selected track alone, or every Ctrl-scoped
    // row — with a mixed scope resolving toward on. View state only: the
    // undo stack must not move, and the header buttons follow the masks
    // without a panel rebuild.
    {
        const int preCount = doc.undoStack()->count();
        const int track = view.selectionModel().primaryTrack();
        if (view.muteMask() != 0 || view.soloMask() != 0)
            fail("mute/solo masks not clean before the keyboard toggles");
        sendKeyStroke(*roll, Qt::Key_M, Qt::NoModifier, false);
        if (!view.trackMuted(track))
            fail("M did not mute the selected track");
        auto *row = view.findChild<QWidget *>(QStringLiteral("trackHeaderRow%1").arg(track));
        auto *muteButton =
            row ? row->findChild<QToolButton *>(QStringLiteral("trackMuteButton")) : nullptr;
        if (!muteButton || !muteButton->isChecked())
            fail("keyboard mute did not check the header button");
        sendKeyStroke(*roll, Qt::Key_M, Qt::NoModifier, false);
        if (view.muteMask() != 0)
            fail("second M did not unmute the selected track");
        if (muteButton && muteButton->isChecked())
            fail("keyboard unmute did not uncheck the header button");
        sendKeyStroke(*roll, Qt::Key_S, Qt::NoModifier, false);
        if (!view.trackSoloed(track))
            fail("S did not solo the selected track");
        sendKeyStroke(*roll, Qt::Key_S, Qt::NoModifier, false);
        if (view.soloMask() != 0)
            fail("second S did not unsolo the selected track");

        // Multi-track scope + mixed state: with another track Ctrl-scoped
        // in and already muted, M mutes the rest (on wins), and the next M
        // clears the whole scope.
        const int other = track == 0 ? 1 : 0;
        if (view.findChild<QWidget *>(QStringLiteral("trackHeaderRow%1").arg(other))) {
            view.trackHeaderClicked(other, Qt::ControlModifier);
            view.setTrackMute(other, true);
            sendKeyStroke(*roll, Qt::Key_M, Qt::NoModifier, false);
            if (!view.trackMuted(track) || !view.trackMuted(other))
                fail("M over a mixed scope did not mute every scoped track");
            sendKeyStroke(*roll, Qt::Key_M, Qt::NoModifier, false);
            if (view.muteMask() != 0)
                fail("second M did not unmute the whole scope");
            view.trackHeaderClicked(track, Qt::NoModifier); // collapse scope
        }
        if (doc.undoStack()->count() != preCount)
            fail("keyboard mute/solo touched the undo stack");
    }

    if (doc.undoStack()->index() !=
        undoBaseline + 2 + (seededHeaderProgram ? 1 : 0) + (reordered ? (dragRenamed ? 2 : 1) : 0))
        fail("gesture pass pushed an unexpected number of undo commands");
    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
