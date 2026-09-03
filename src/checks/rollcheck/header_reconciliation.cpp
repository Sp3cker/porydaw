#include "checks/rollcheck/rollcheck.h"

#include <QAbstractItemModel>
#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QMenu>
#include <QTimer>
#include <algorithm>
#include <optional>

#include "checks/rollcheck/headerchecksupport.h"
#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"

namespace checks::rollcheck {
using headercheck::addTrackRow;
using headercheck::model;
using headercheck::ModelChanges;
using headercheck::recordsMatchTimeline;
using headercheck::rowForTrack;
using headercheck::titlePoint;

ScenarioContinuation runHeaderReconciliationScenarios(Harness &check, const SongInfo &song)
{
    auto fail = [&](const char *what) { check.fail(what); };
    SongView &view = check.view();
    auto *headers = model(view);
    auto *input = headercheck::input(view);
    const int originalTrack = view.selectionModel().primaryTrack();
    if (!headers || !input) {
        fail("Quick track-header model or input was not found");
    } else {
        int menuTrack = -1;
        int menuRow = -1;
        for (int row = 0; row < headers->rowCount(); ++row) {
            const QModelIndex index = headers->index(row, 0);
            if (headers->data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool())
                continue;
            const int track = headers->data(index, songview::TrackHeaderModel::TrackRole).toInt();
            if (track != originalTrack) {
                menuTrack = track;
                menuRow = row;
                break;
            }
        }
        if (menuRow < 0) {
            fail("context-menu fixture lacks a secondary track header");
        } else {
            bool menuOpened = false;
            QTimer::singleShot(0, [&menuOpened] {
                if (auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget())) {
                    menuOpened = menu->actions().size() == 5;
                    menu->close();
                }
            });
            const QPointF position = titlePoint(*headers, *input, menuRow);
            checks::events::sendMouse(*input, QEvent::MouseButtonPress, position, Qt::RightButton,
                                      Qt::RightButton, Qt::NoModifier);
            checks::events::sendMouse(*input, QEvent::MouseButtonRelease, position, Qt::RightButton,
                                      Qt::NoButton, Qt::NoModifier);
            if (!menuOpened || view.selectionModel().primaryTrack() != menuTrack)
                fail("right press did not select its track and open the context menu");
            view.selectTrack(originalTrack);
        }
    }

    // Header records reconcile by engine index. Unchanged and non-structural
    // updates retain the model structure; track insertion/removal is the one
    // reset boundary. The optional add record remains last.
    {
        SongDocument reconcileDoc;
        QString reconcileError;
        if (!reconcileDoc.load(song, &reconcileError)) {
            fail("could not load header reconciliation fixture");
        } else {
            auto current = reconcileDoc.buildTimeline(48000.0);
            SongView reconcileView;
            reconcileView.resize(800, 480);
            reconcileView.setSong(current.get(), nullptr);
            reconcileView.setDocument(&reconcileDoc);
            (void)reconcileView.grab(); // realizes the attached Quick input

            auto *reconcileHeaders = model(reconcileView);
            if (!reconcileHeaders) {
                fail("header reconciliation fixture lacks TrackHeaderModel");
            } else {
                ModelChanges changes;
                QObject::connect(reconcileHeaders, &QAbstractItemModel::modelReset, &reconcileView,
                                 [&changes] { ++changes.resets; });
                QObject::connect(
                    reconcileHeaders, &QAbstractItemModel::dataChanged, &reconcileView,
                    [&changes](const QModelIndex &topLeft, const QModelIndex &bottomRight,
                               const QList<int> &roles) {
                        changes.data.push_back({topLeft.row(), bottomRight.row(), roles});
                    });

                int firstUsed = -1;
                int lastUsed = -1;
                for (int track = 0; track < 16; ++track) {
                    if (!current->tracks[track].used)
                        continue;
                    if (firstUsed < 0)
                        firstUsed = track;
                    lastUsed = track;
                }
                const std::optional<int> addBefore = addTrackRow(*reconcileHeaders);
                if (firstUsed < 0 || firstUsed == lastUsed ||
                    !rowForTrack(*reconcileHeaders, firstUsed) ||
                    !rowForTrack(*reconcileHeaders, lastUsed) || !addBefore ||
                    *addBefore != reconcileHeaders->rowCount() - 1) {
                    fail("header reconciliation fixture lacks ordered records and a last add "
                         "record");
                } else {
                    // Identical content retains the model structure and its ordered domain records.
                    changes.clear();
                    reconcileView.setSong(current.get(), nullptr);
                    if (changes.resets != 0 ||
                        !recordsMatchTimeline(*reconcileHeaders, *current,
                                              reconcileDoc.canAddTrack()) ||
                        addTrackRow(*reconcileHeaders) != addBefore) {
                        fail("unchanged song reset or reordered TrackHeaderModel records");
                    }

                    // A mask-only update changes a bounded row, publishes its mute role, and
                    // never resets the model. Notification batching is deliberately flexible.
                    reconcileView.setTrackMute(firstUsed, false);
                    changes.clear();
                    reconcileView.setTrackMute(firstUsed, true);
                    const std::optional<int> mutedRow = rowForTrack(*reconcileHeaders, firstUsed);
                    const bool boundedMuteChange =
                        changes.resets == 0 && mutedRow && !changes.data.empty() &&
                        std::all_of(changes.data.cbegin(), changes.data.cend(),
                                    [mutedRow](const headercheck::ModelChange &change) {
                                        return change.firstRow == *mutedRow &&
                                               change.lastRow == *mutedRow;
                                    }) &&
                        headercheck::includesRole(changes.data, *mutedRow,
                                                  songview::TrackHeaderModel::MuteCheckedRole) &&
                        reconcileHeaders
                            ->data(reconcileHeaders->index(*mutedRow, 0),
                                   songview::TrackHeaderModel::MuteCheckedRole)
                            .toBool();
                    if (!boundedMuteChange)
                        fail("mask-only header update was not bounded mute-role coverage");

                    // Contract lock: identity replacement uses one model reset, rather than
                    // insert/remove notifications, so QML discards stale record identity.
                    reconcileDoc.deleteTrack(lastUsed);
                    auto replacement = reconcileDoc.buildTimeline(48000.0);
                    if (replacement->tracks[lastUsed].used ||
                        !replacement->tracks[firstUsed].used) {
                        fail("replacement fixture did not drop exactly the last used slot");
                    } else {
                        changes.clear();
                        reconcileView.setSong(replacement.get(), nullptr);
                        if (changes.resets != 1 ||
                            !recordsMatchTimeline(*reconcileHeaders, *replacement,
                                                  reconcileDoc.canAddTrack()) ||
                            rowForTrack(*reconcileHeaders, lastUsed)) {
                            fail("structural header replacement did not reset to the replacement "
                                 "records");
                        }

                        reconcileDoc.undoStack()->undo();
                        current = reconcileDoc.buildTimeline(48000.0);
                        changes.clear();
                        reconcileView.setSong(current.get(), nullptr);
                        const std::optional<int> restoredAdd = addTrackRow(*reconcileHeaders);
                        if (changes.resets != 1 ||
                            !recordsMatchTimeline(*reconcileHeaders, *current,
                                                  reconcileDoc.canAddTrack()) ||
                            !rowForTrack(*reconcileHeaders, lastUsed) || !restoredAdd ||
                            *restoredAdd != reconcileHeaders->rowCount() - 1) {
                            fail("re-added track did not restore ordered model records and last "
                                 "add row");
                        }

                        // A replacement while rename is open cancels the transient model state
                        // without committing the draft.
                        reconcileView.renameTrack(firstUsed);
                        if (reconcileHeaders->renamingTrack() != firstUsed) {
                            fail("rename state did not open on a live TrackHeaderModel record");
                        } else {
                            reconcileHeaders->setRenameDraft(QStringLiteral("zzz"));
                            changes.clear();
                            reconcileView.setSong(replacement.get(), nullptr);
                            QCoreApplication::processEvents();
                            if (changes.resets != 1 || reconcileHeaders->renamingTrack() != -1) {
                                fail(
                                    "song replacement did not cancel the open header rename state");
                            }
                            if (reconcileDoc.trackName(firstUsed) == QStringLiteral("zzz"))
                                fail("cancelled rename committed across song replacement");
                        }
                    }
                }
            }
        }
    }

    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
