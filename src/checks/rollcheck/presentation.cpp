#include "checks/rollcheck/rollcheck.h"

#include <QAbstractItemModel>
#include <QColor>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QMetaObject>
#include <QObject>
#include <QPointF>
#include <QTimer>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <optional>
#include <vector>

#include "checks/rollcheck/headerchecksupport.h"
#include "checks/rollcheckplayhead.h"
#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"
#include "ui/songview/voicepicker.h"

namespace {

class VoicePickerAccepter final : public QObject
{
  public:
    bool opened = false;

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() != QEvent::Show)
            return false;
        auto *dialog = dynamic_cast<songview::VoicePickerDialog *>(watched);
        if (!dialog)
            return false;
        opened = true;
        QTimer::singleShot(0, dialog, [dialog] { dialog->accept(); });
        return false;
    }
};

} // namespace

namespace checks::rollcheck {

using headercheck::addTrackRow;
using headercheck::captureBand;
using headercheck::click;
using headercheck::includesRole;
using headercheck::input;
using headercheck::model;
using headercheck::ModelChange;
using headercheck::recordsMatchTimeline;
using headercheck::renameInput;
using headercheck::rowForTrack;
using headercheck::rowPoint;
using headercheck::titlePoint;
using headercheck::voicePoint;

ScenarioContinuation runHeaderAndPresentationScenarios(Harness &check,
                                                       const PencilVelocityFixture &fixture,
                                                       const QString &screenshotPath)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem *roll = &check.rollInput();
    songview::TimelineInputItem *rollGutter = &check.rollGutterInput();
    const int track = check.track();
    const SnappedRows rows{view, *roll};
    const Cell &a = fixture.a;
    const qreal vw = std::max<qreal>(50, roll->width());
    const int undoBaseline = doc.undoStack()->index();
    auto fail = [&](const char *what) { check.fail(what); };
    auto *headers = model(view);
    auto *headerInputItem = input(view);
    if (!headers || !headerInputItem) {
        fail("Quick track-header model or input was not found");
        return ScenarioContinuation::Continue;
    }
    if (!recordsMatchTimeline(*headers, check.timeline(), doc.canAddTrack()))
        fail("Quick header records did not match the current timeline");
    // Playhead follow-scroll pauses while a mouse gesture is live: with a
    // middle-button pan held in the roll (or the automation lanes), a playing
    // playhead far past the right edge must not move the view; releasing the
    // button lets the next playhead tick scroll again.
    auto *automationQuick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *lanes = automationQuick && automationQuick->rootObject()
                      ? automationQuick->rootObject()->findChild<songview::TimelineInputItem *>(
                            QStringLiteral("timelineAutomationInput"))
                      : nullptr;
    if (!lanes)
        fail("automation input item not found");
    // Roll and automation lanes are both Quick input items with attached
    // non-widget interactions; both run the same middle-drag pan probe
    // against their own input surface.
    const auto panFollowProbe = [&](auto &panned) {
        const int home = view.camera().contentX(0.0);
        const uint64_t farTick = uint64_t(std::max(0.0, view.camera().tickAtContentX(vw * 2)));
        const QPointF mid(panned.width() / 2.0, panned.height() / 2.0);
        checks::events::sendMouse(panned, QEvent::MouseButtonPress, mid, Qt::MiddleButton,
                                  Qt::MiddleButton, Qt::NoModifier);
        view.setPlayheadSample(check.timeline().sampleForTick(farTick), true);
        if (view.camera().contentX(0.0) != home)
            fail("playhead follow-scroll moved the view during a pan gesture");
        checks::events::sendMouse(panned, QEvent::MouseButtonRelease, mid, Qt::MiddleButton,
                                  Qt::NoButton, Qt::NoModifier);
        view.setPlayheadSample(check.timeline().sampleForTick(farTick), true);
        if (view.camera().contentX(0.0) == home)
            fail("playhead follow-scroll did not resume after the pan ended");
        view.setPlayheadSample(0, false);
        view.scrollByPx(view.camera().contentX(0.0) - home); // back where it started
    };
    panFollowProbe(*roll);
    if (lanes)
        panFollowProbe(*lanes);

    // A stopped playhead uses retained Quick chrome. Moving it must preserve
    // timeline scene-layer revisions instead of rebuilding their contents.
    for (const QString &error : timelineChromeCheckFailures(view, check.timeline()))
        fail(qUtf8Printable(error));

    // Inline rename is model-owned and rendered by the named Quick text
    // input. Commit and cancellation must traverse that focused input's
    // Return/Escape handlers, including the loop-marker name guard.
    {
        const auto renameIsOpen = [&] {
            QCoreApplication::processEvents();
            QObject *const field = renameInput(view);
            return headers->renamingTrack() == track && field &&
                   field->property("visible").toBool() && field->property("activeFocus").toBool();
        };
        const auto typeDraft = [&](QObject &field, const QString &draft) {
            headers->setRenameDraft(draft);
            QCoreApplication::processEvents();
            if (field.property("text").toString() != draft)
                fail("Quick rename input did not receive the model draft");
        };

        view.renameTrack(track);
        if (!renameIsOpen()) {
            fail("Quick rename input did not open");
        } else {
            QObject *const field = renameInput(view);
            typeDraft(*field, QStringLiteral("Rolled"));
            sendKeyStroke(*field, Qt::Key_Return, Qt::NoModifier, false);
            QCoreApplication::processEvents(); // the queued document commit
            if (doc.trackName(track) != QStringLiteral("Rolled"))
                fail("Quick Return did not commit the inline rename");
        }

        view.renameTrack(track);
        if (!renameIsOpen()) {
            fail("Quick rename input did not reopen");
        } else {
            QObject *const field = renameInput(view);
            typeDraft(*field, QStringLiteral("Discarded"));
            sendKeyStroke(*field, Qt::Key_Escape, Qt::NoModifier, false);
            QCoreApplication::processEvents();
            if (doc.trackName(track) != QStringLiteral("Rolled") ||
                headers->renamingTrack() != -1) {
                fail("Quick Escape did not discard the inline rename draft");
            }
        }

        view.renameTrack(track);
        if (!renameIsOpen()) {
            fail("Quick rename input did not reopen for the loop-marker guard");
        } else {
            const int commands = doc.undoStack()->count();
            QObject *const field = renameInput(view);
            typeDraft(*field, QStringLiteral("["));
            sendKeyStroke(*field, Qt::Key_Return, Qt::NoModifier, false);
            QCoreApplication::processEvents();
            if (doc.trackName(track) != QStringLiteral("Rolled") ||
                doc.undoStack()->count() != commands) {
                fail("loop-marker name was not refused");
            }
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

        // Header presentation is now a model-to-Quick contract. A program
        // transition changes the subtitle role for just this record and the
        // retained header framebuffer, while selection changes its resolved
        // presentation roles and pixels through the Quick input surface.
        if (const std::optional<int> headerRow = rowForTrack(*headers, track)) {
            std::vector<ModelChange> changes;
            const QMetaObject::Connection changeConnection = QObject::connect(
                headers, &QAbstractItemModel::dataChanged, &view,
                [&changes](const QModelIndex &topLeft, const QModelIndex &bottomRight,
                           const QList<int> &roles) {
                    changes.push_back({topLeft.row(), bottomRight.row(), roles});
                });

            const QString beforeSubtitle =
                headers
                    ->data(headers->index(*headerRow, 0), songview::TrackHeaderModel::SubtitleRole)
                    .toString();
            const QImage beforeProgram = captureBand(check, view);
            changes.clear();
            view.setEditCursorTick(vcTick);
            QCoreApplication::processEvents();
            const QString afterSubtitle =
                headers
                    ->data(headers->index(*headerRow, 0), songview::TrackHeaderModel::SubtitleRole)
                    .toString();
            const QImage afterProgram = captureBand(check, view);
            if (!includesRole(changes, *headerRow, songview::TrackHeaderModel::SubtitleRole) ||
                beforeSubtitle == afterSubtitle) {
                fail("program change did not publish a changed header subtitle role");
            }
            if (beforeProgram.isNull() || afterProgram.isNull() ||
                beforeProgram.size() != afterProgram.size() || beforeProgram == afterProgram) {
                fail("program change did not alter the retained Quick header rendering");
            }

            view.setEditCursorTick(0);
            const int previousPrimary = view.selectionModel().primaryTrack();
            std::optional<int> otherTrack;
            for (int row = 0; row < headers->rowCount(); ++row) {
                const QModelIndex index = headers->index(row, 0);
                if (!headers->data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool() &&
                    headers->data(index, songview::TrackHeaderModel::TrackRole).toInt() != track) {
                    otherTrack =
                        headers->data(index, songview::TrackHeaderModel::TrackRole).toInt();
                    break;
                }
            }
            if (!otherTrack) {
                fail("selection rendering fixture lacks a second header record");
            } else {
                view.selectTrack(*otherTrack);
                QCoreApplication::processEvents();
                const QColor unselectedBase = headers
                                                  ->data(headers->index(*headerRow, 0),
                                                         songview::TrackHeaderModel::BaseColorRole)
                                                  .value<QColor>();
                const QImage beforeSelection = captureBand(check, view);
                click(*headerInputItem, titlePoint(*headers, *headerInputItem, *headerRow));
                QCoreApplication::processEvents();
                const QColor selectedBase = headers
                                                ->data(headers->index(*headerRow, 0),
                                                       songview::TrackHeaderModel::BaseColorRole)
                                                .value<QColor>();
                const QImage afterSelection = captureBand(check, view);
                if (view.selectionModel().primaryTrack() != track ||
                    selectedBase == unselectedBase) {
                    fail("Quick header input did not publish selected record presentation");
                }
                if (beforeSelection.isNull() || afterSelection.isNull() ||
                    beforeSelection == afterSelection) {
                    fail("track selection did not alter the retained Quick header rendering");
                }
            }
            view.selectTrack(previousPrimary);
            QCoreApplication::processEvents();
            QObject::disconnect(changeConnection);
        } else {
            fail("track header model record for presentation coverage was not found");
        }
    }

    // Jump-from-context is delivered through the one header Quick input.
    // The model owns hit testing for the voice line, title line, rename, and
    // drag suppression; no delegate has a separate pointer path.
    {
        if (const std::optional<int> headerRow = rowForTrack(*headers, track)) {
            int revealed = -1;
            int reveals = 0;
            const QMetaObject::Connection connection =
                QObject::connect(&view, &SongView::revealVoiceRequested, [&](int program) {
                    revealed = program;
                    ++reveals;
                });
            const int preCount = doc.undoStack()->count();
            const QPointF voice = voicePoint(*headers, *headerInputItem, *headerRow);
            click(*headerInputItem, voice);
            if (reveals != 1 || revealed != view.currentProgram(track))
                fail("voice-line Quick input did not request the track's program");
            click(*headerInputItem, titlePoint(*headers, *headerInputItem, *headerRow));
            if (reveals != 1)
                fail("a title-line click requested a voice reveal");

            // A drag beginning on the voice line becomes an adjacent no-op
            // reorder and must not reveal a voice on release.
            const QPointF adjacentDrop =
                rowPoint(*headers, *headerInputItem, *headerRow,
                         {headers->voiceLineRect().center().x(), headers->rowHeight() * 1.2});
            checks::events::sendMouse(*headerInputItem, QEvent::MouseButtonPress, voice,
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*headerInputItem, QEvent::MouseMove, adjacentDrop,
                                      Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*headerInputItem, QEvent::MouseButtonRelease, adjacentDrop,
                                      Qt::RightButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*headerInputItem, QEvent::MouseButtonRelease, adjacentDrop,
                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            QCoreApplication::processEvents();
            if (reveals != 1 || headers->reorderIndicatorVisible())
                fail("voice-line reorder drag leaked a reveal or reorder state");

            // Voice-line double-click opens the picker end-to-end in
            // rollcheckwindowing.cpp; this body double-click owns rename here.
            const QPointF title = titlePoint(*headers, *headerInputItem, *headerRow);
            checks::events::sendMouse(*headerInputItem, QEvent::MouseButtonDblClick, title,
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*headerInputItem, QEvent::MouseButtonRelease, title,
                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            QCoreApplication::processEvents();
            QObject *const renameField = renameInput(view);
            if (headers->renamingTrack() != track || !renameField ||
                !renameField->property("visible").toBool()) {
                fail("title-line double-click did not open the Quick rename input");
            } else {
                sendKeyStroke(*renameField, Qt::Key_Escape, Qt::NoModifier, false);
                QCoreApplication::processEvents();
            }
            if (doc.undoStack()->count() != preCount)
                fail("voice navigation touched the undo stack");
            QObject::disconnect(connection);
        } else {
            fail("track header model record for voice navigation was not found");
        }
    }

    // Exercise every header control through the real Quick input geometry,
    // rather than invoking a model action directly.
    {
        const std::optional<int> trackRow = rowForTrack(*headers, track);
        const std::optional<int> addRow = addTrackRow(*headers);
        if (!trackRow || !addRow || !doc.canAddTrack()) {
            fail("Quick header control records were unavailable");
        } else {
            const auto roleChecked = [&](int row, int role) {
                return headers->data(headers->index(row, 0), role).toBool();
            };
            const QPointF mute =
                rowPoint(*headers, *headerInputItem, *trackRow, headers->muteButtonRect().center());
            view.setTrackMute(track, false);
            click(*headerInputItem, mute);
            if (!view.trackMuted(track) ||
                !roleChecked(*trackRow, songview::TrackHeaderModel::MuteCheckedRole)) {
                fail("Quick mute-button pointer input did not toggle the track");
            }
            click(*headerInputItem, mute);
            if (view.trackMuted(track) ||
                roleChecked(*trackRow, songview::TrackHeaderModel::MuteCheckedRole)) {
                fail("second Quick mute-button pointer input did not clear the track");
            }

            const QPointF solo =
                rowPoint(*headers, *headerInputItem, *trackRow, headers->soloButtonRect().center());
            view.setTrackSolo(track, false);
            click(*headerInputItem, solo);
            if (!view.trackSoloed(track) ||
                !roleChecked(*trackRow, songview::TrackHeaderModel::SoloCheckedRole)) {
                fail("Quick solo-button pointer input did not toggle the track");
            }
            click(*headerInputItem, solo);
            if (view.trackSoloed(track) ||
                roleChecked(*trackRow, songview::TrackHeaderModel::SoloCheckedRole)) {
                fail("second Quick solo-button pointer input did not clear the track");
            }

            const int tracksBefore = doc.engineTrackCount();
            const int undoBefore = doc.undoStack()->index();
            // Complete the actual modal picker without looking up widget internals,
            // so the pointer route reaches the queued document mutation.
            VoicePickerAccepter pickerAccepter;
            QCoreApplication::instance()->installEventFilter(&pickerAccepter);
            click(*headerInputItem, titlePoint(*headers, *headerInputItem, *addRow));
            QCoreApplication::processEvents();
            QCoreApplication::processEvents();
            QCoreApplication::instance()->removeEventFilter(&pickerAccepter);
            if (!pickerAccepter.opened || doc.engineTrackCount() != tracksBefore + 1 ||
                doc.undoStack()->index() != undoBefore + 1 ||
                !recordsMatchTimeline(*headers, check.timeline(), doc.canAddTrack())) {
                fail("Quick add-track pointer input did not create a header track");
            }
            if (doc.undoStack()->index() != undoBefore)
                doc.undoStack()->setIndex(undoBefore);
            QCoreApplication::processEvents();
            if (doc.engineTrackCount() != tracksBefore || doc.undoStack()->index() != undoBefore ||
                !recordsMatchTimeline(*headers, check.timeline(), doc.canAddTrack())) {
                fail("undoing the Quick add-track pointer input did not restore the header");
            }
            view.selectTrack(track);
            QCoreApplication::processEvents();
        }
    }

    // Header drag reorder goes through the shared Quick input and must carry
    // notes, masks, and an open model-owned rename across the queued move.
    bool reordered = false;
    bool dragRenamed = false;
    if (doc.engineTrackCount() >= 2) {
        headers->setScrollY(0.0);
        const std::optional<int> sourceRow = rowForTrack(*headers, 0);
        const std::optional<int> targetRow = rowForTrack(*headers, 1);
        if (!sourceRow || !targetRow) {
            fail("track header model records for reorder were not found");
        } else {
            const auto firstNotes = doc.notesForTrack(0);
            view.setTrackMute(0, true);
            const QPointF start = titlePoint(*headers, *headerInputItem, *sourceRow);
            const QPointF drop =
                rowPoint(*headers, *headerInputItem, *targetRow,
                         {headers->voiceLineRect().center().x(), headers->rowHeight() * 3.0 / 4.0});

            // A non-left release cancels a live drag and clears the
            // Quick reorder marker without queuing a document change.
            const int preDragCount = doc.undoStack()->count();
            checks::events::sendMouse(*headerInputItem, QEvent::MouseButtonPress, start,
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*headerInputItem, QEvent::MouseMove, drop, Qt::NoButton,
                                      Qt::LeftButton, Qt::NoModifier);
            const QImage markerFrame = captureBand(check, view);
            if (!headers->reorderIndicatorVisible() || markerFrame.isNull())
                fail("Quick header drag did not expose a reorder marker");
            checks::events::sendMouse(*headerInputItem, QEvent::MouseButtonRelease, drop,
                                      Qt::RightButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*headerInputItem, QEvent::MouseButtonRelease, drop,
                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            QCoreApplication::processEvents();
            if (doc.undoStack()->count() != preDragCount || headers->reorderIndicatorVisible())
                fail("non-left release during a Quick header drag committed or leaked state");

            // Reorder commits an open draft before queueing the move.
            view.renameTrack(0);
            QCoreApplication::processEvents();
            QObject *const renameField = renameInput(view);
            if (headers->renamingTrack() != 0 || !renameField ||
                !renameField->property("visible").toBool()) {
                fail("Quick rename input did not open before header reorder");
            } else {
                headers->setRenameDraft(QStringLiteral("Dragged"));
                dragRenamed = true;
            }

            checks::events::sendMouse(*headerInputItem, QEvent::MouseButtonPress, start,
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*headerInputItem, QEvent::MouseMove, drop, Qt::NoButton,
                                      Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*headerInputItem, QEvent::MouseButtonRelease, drop,
                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            // The queued rename commit, then the queued moveTrack commit.
            QCoreApplication::processEvents();
            const auto movedNotes = doc.notesForTrack(1);
            bool same = movedNotes.size() == firstNotes.size();
            for (size_t i = 0; same && i < movedNotes.size(); ++i) {
                same = movedNotes[i].tick == firstNotes[i].tick &&
                       movedNotes[i].key == firstNotes[i].key;
            }
            if (!same) {
                fail("Quick header drag did not move the track's notes to slot 1");
            } else if (!view.trackMuted(1) || view.trackMuted(0)) {
                fail("Quick header drag did not move the mute flag with the track");
            } else {
                reordered = true;
                if (dragRenamed && doc.trackName(1) != QStringLiteral("Dragged"))
                    fail("the open rename draft was lost in the reorder");
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
            headers->setScrollY(0.0);
            const std::optional<int> sourceRow = rowForTrack(*headers, fromTrack);
            const int targetTrack = fixtureTracks[slot < 3 ? slot : 2];
            const std::optional<int> targetRow = rowForTrack(*headers, targetTrack);
            if (!sourceRow || !targetRow) {
                fail("track header model records for insertion-slot drag were not found");
                return false;
            }
            const QPointF start = titlePoint(*headers, *headerInputItem, *sourceRow);
            const QPointF drop =
                rowPoint(*headers, *headerInputItem, *targetRow,
                         {headers->voiceLineRect().center().x(),
                          headers->rowHeight() * (slot < 3 ? 1.0 / 4.0 : 3.0 / 4.0)});
            checks::events::sendMouse(*headerInputItem, QEvent::MouseButtonPress, start,
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*headerInputItem, QEvent::MouseMove, drop, Qt::NoButton,
                                      Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*headerInputItem, QEvent::MouseButtonRelease, drop,
                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
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
        uint64_t(std::ceil(std::max(0.0, view.camera().tickAtContentX(roll->width() / 2))));
    view.setPlayheadSample(check.timeline().sampleForTick(screenshotTick), false);
    // Park the cursor on a snapped piano-key row so the shot shows the hover
    // mark and name chip through the physical gutter input.
    const int hoverKey = rows.keyAt(rollGutter->height() / 3.0);
    checks::events::sendMouse(*rollGutter, QEvent::MouseMove, QPointF(4.0, rows.centerY(hoverKey)),
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

    // Keyboard mute/solo changes view masks and the matching model roles
    // without resetting the retained Quick header structure.
    {
        const int preCount = doc.undoStack()->count();
        int headerResets = 0;
        const QMetaObject::Connection resetConnection = QObject::connect(
            headers, &QAbstractItemModel::modelReset, &view, [&headerResets] { ++headerResets; });
        const auto roleChecked = [&](int track, int role) {
            const std::optional<int> row = rowForTrack(*headers, track);
            return row && headers->data(headers->index(*row, 0), role).toBool();
        };

        const int selectedTrack = view.selectionModel().primaryTrack();
        if (view.muteMask() != 0 || view.soloMask() != 0)
            fail("mute/solo masks not clean before the keyboard toggles");
        sendKeyStroke(*roll, Qt::Key_M, Qt::NoModifier, false);
        if (!view.trackMuted(selectedTrack))
            fail("M did not mute the selected track");
        if (!roleChecked(selectedTrack, songview::TrackHeaderModel::MuteCheckedRole))
            fail("keyboard mute did not publish the checked Quick header role");
        sendKeyStroke(*roll, Qt::Key_M, Qt::NoModifier, false);
        if (view.muteMask() != 0)
            fail("second M did not unmute the selected track");
        if (roleChecked(selectedTrack, songview::TrackHeaderModel::MuteCheckedRole))
            fail("keyboard unmute did not clear the checked Quick header role");
        sendKeyStroke(*roll, Qt::Key_S, Qt::NoModifier, false);
        if (!view.trackSoloed(selectedTrack) ||
            !roleChecked(selectedTrack, songview::TrackHeaderModel::SoloCheckedRole)) {
            fail("S did not publish the selected track's solo role");
        }
        sendKeyStroke(*roll, Qt::Key_S, Qt::NoModifier, false);
        if (view.soloMask() != 0 ||
            roleChecked(selectedTrack, songview::TrackHeaderModel::SoloCheckedRole)) {
            fail("second S did not clear the selected track's solo role");
        }

        // Multi-track scope + mixed state: with another track Ctrl-scoped
        // in and already muted, M mutes the rest (on wins), and the next M
        // clears the whole scope.
        const int other = selectedTrack == 0 ? 1 : 0;
        if (!rowForTrack(*headers, other)) {
            fail("Quick header record was missing for the scoped keyboard probe");
        } else {
            view.trackHeaderClicked(other, Qt::ControlModifier);
            view.setTrackMute(other, true);
            sendKeyStroke(*roll, Qt::Key_M, Qt::NoModifier, false);
            if (!view.trackMuted(selectedTrack) || !view.trackMuted(other) ||
                !roleChecked(selectedTrack, songview::TrackHeaderModel::MuteCheckedRole) ||
                !roleChecked(other, songview::TrackHeaderModel::MuteCheckedRole)) {
                fail("M over a mixed scope did not mute every scoped track");
            }
            sendKeyStroke(*roll, Qt::Key_M, Qt::NoModifier, false);
            if (view.muteMask() != 0)
                fail("second M did not unmute the whole scope");
            view.trackHeaderClicked(selectedTrack, Qt::NoModifier); // collapse scope
        }
        if (headerResets != 0)
            fail("keyboard mute/solo reset the TrackHeaderModel");
        if (doc.undoStack()->count() != preCount)
            fail("keyboard mute/solo touched the undo stack");
        QObject::disconnect(resetConnection);
    }

    if (doc.undoStack()->index() !=
        undoBaseline + 2 + (seededHeaderProgram ? 1 : 0) + (reordered ? (dragRenamed ? 2 : 1) : 0))
        fail("gesture pass pushed an unexpected number of undo commands");
    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
