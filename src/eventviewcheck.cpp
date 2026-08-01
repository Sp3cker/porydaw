#include <QAbstractItemModel>
#include <QComboBox>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QMetaObject>
#include <QFontInfo>
#include <QImage>
#include <QItemSelectionModel>
#include <QKeyEvent>
#include <QMenu>
#include <QMimeData>
#include <QScrollBar>
#include <QSettings>
#include <QString>
#include <QStringList>
#include <QStyleOptionViewItem>
#include <QTableView>
#include <QTemporaryDir>
#include <algorithm>
#include <cstdio>
#include <memory>

#include "core/songdocument.h"
#include "project/decompproject.h"
#include "ui/eventlistview.h"
#include "ui/songview.h"
#include "ui/typography.h"

// --eventviewcheck <projectRoot>: MIDI event list check. Model pass over
// every song with a MIDI source: the raw-event API (insert, same-tick
// modify, tick-moving modify, delete, end-of-track move with its clamp)
// keeps event ticks sorted and undoes back to the original bytes. UI pass
// on the first song: the event list swaps in for the roll, mirrors the
// chunk's events plus an end-of-track row, routes cell edits into the
// document (queued), filters, round-trips through view state, tints the
// row under the playhead (end-of-track row past the end), commits the
// edit cursor when a row is focused — but never on programmatic restores —
// and inserts a copy of a row at its own tick (the context menu's insert;
// the end-of-track row is not copyable). Deleting a multi-row selection
// clears the highlight instead of restoring it onto the surviving rows;
// a single-row delete keeps its current row so Delete can be spammed.
// The app-wide Follow Playhead toggle stops the running scrollTo while
// the tint keeps tracking.

namespace {

bool trackSorted(const SmfTrack &track)
{
    for (size_t i = 1; i < track.events.size(); i++) {
        if (track.events[i].tick < track.events[i - 1].tick)
            return false;
    }
    return true;
}

// The chunk the check edits: the first engine track's, else the first chunk
// holding any event. -1 when the file is empty.
int pickChunk(const SongDocument &doc)
{
    const int mapped = doc.smfTrackFor(0);
    if (mapped >= 0)
        return mapped;
    for (size_t t = 0; t < doc.smf().tracks.size(); t++) {
        if (!doc.smf().tracks[t].events.empty())
            return int(t);
    }
    return doc.smf().tracks.empty() ? -1 : 0;
}

size_t countMatching(const SmfTrack &track, const SmfEvent &target)
{
    return size_t(std::count(track.events.begin(), track.events.end(), target));
}

long long indexOf(const SmfTrack &track, const SmfEvent &target)
{
    const auto it = std::find(track.events.begin(), track.events.end(), target);
    return it == track.events.end() ? -1 : (long long)(it - track.events.begin());
}

int runUiPass(const SongInfo &song, const QString &screenshotPath)
{
    QString error;
    SongDocument doc;
    if (!doc.load(song, &error)) {
        std::fprintf(stderr, "eventviewcheck: FAIL ui %s: %s\n", qUtf8Printable(song.label),
                     qUtf8Printable(error));
        return 1;
    }
    auto tl = doc.buildTimeline(48000.0);

    SongView view;
    view.resize(1280, 800);
    view.setSong(tl.get(), nullptr);
    view.setDocument(&doc);

    int failures = 0;
    auto fail = [&](const char *what) {
        std::fprintf(stderr, "eventviewcheck: FAIL ui %s: %s\n", qUtf8Printable(song.label), what);
        failures++;
    };

    if (view.eventListVisible())
        fail("event list visible before the toggle");
    view.setEventListVisible(true);
    if (!view.eventListVisible())
        fail("event list not visible after the toggle");

    auto *table = view.findChild<QTableView *>(QStringLiteral("eventListTable"));
    auto *chunkCombo = view.findChild<QComboBox *>(QStringLiteral("eventListChunk"));
    auto *filterMenu = view.findChild<QMenu *>(QStringLiteral("eventListFilterMenu"));
    if (!table || !chunkCombo || !filterMenu) {
        fail("event list widgets not found");
        return failures;
    }
    QAbstractItemModel *model = table->model();
    const int chunk = chunkCombo->currentData().toInt();
    if (chunk < 0 || chunk >= int(doc.smf().tracks.size())) {
        fail("no chunk selected");
        return failures;
    }
    const int selectedChunk = doc.smfTrackFor(view.selectedTrack());
    if (selectedChunk >= 0 && selectedChunk != chunk)
        fail("chunk combo does not follow the selected track");

    if (model->rowCount() != int(doc.smf().tracks[chunk].events.size()) + 1)
        fail("row count != chunk events + end-of-track row");
    const QModelIndex eotIdx = model->index(model->rowCount() - 1, 0);
    if (model->data(eotIdx, Qt::EditRole).toULongLong() != doc.smf().tracks[chunk].endTick)
        fail("end-of-track row shows the wrong tick");

    const auto monoFamily = QFontInfo(typography::bodyMono(table->font())).family();
    constexpr int numericColumns[] = {0, 2, 3, 4};
    for (const auto column : numericColumns) {
        const auto cellFont = model->data(model->index(0, column), Qt::FontRole).value<QFont>();
        if (QFontInfo(cellFont).family() != monoFamily)
            fail("a numeric event cell does not use the monospace face");
        if (cellFont.letterSpacingType() != QFont::AbsoluteSpacing ||
            cellFont.letterSpacing() != -0.5)
            fail("a numeric event cell does not use tightened spacing");
        QStyleOptionViewItem editorOption;
        editorOption.initFrom(table);
        auto editor = std::unique_ptr<QWidget>(
            table->itemDelegate()->createEditor(table, editorOption, model->index(0, column)));
        if (!editor || QFontInfo(editor->font()).family() != monoFamily ||
            editor->font().letterSpacingType() != QFont::AbsoluteSpacing ||
            editor->font().letterSpacing() != -0.5)
            fail("a numeric event editor does not match its column font");
    }

    // Cell edit: bump the first event's tick. The mutation is queued (must
    // not reset the model inside the delegate's commit), so pump the loop.
    if (!doc.smf().tracks[chunk].events.empty()) {
        const qulonglong newTick = qulonglong(doc.smf().tracks[chunk].events[0].tick + 3);
        if (!model->setData(model->index(0, 0), newTick, Qt::EditRole))
            fail("tick cell rejected the edit");
        QCoreApplication::processEvents();
        if (!doc.undoStack()->canUndo())
            fail("tick edit never reached the document");
        if (!trackSorted(doc.smf().tracks[chunk]))
            fail("events unsorted after the tick edit");
        if (model->rowCount() != int(doc.smf().tracks[chunk].events.size()) + 1)
            fail("table did not refresh after the tick edit");
        doc.undoStack()->undo();
        if (model->rowCount() != int(doc.smf().tracks[chunk].events.size()) + 1)
            fail("table did not refresh after undo");

        // 64-bit ticks must not squeeze through an int anywhere in the edit
        // path (the event moves past everything, so it lands last).
        const qulonglong bigTick = 3000000000ULL; // > INT_MAX
        model->setData(model->index(0, 0), bigTick, Qt::EditRole);
        QCoreApplication::processEvents();
        const auto &evs = doc.smf().tracks[chunk].events;
        if (evs.empty() || evs.back().tick != bigTick)
            fail("a >INT_MAX tick edit did not land exactly");
        doc.undoStack()->undo();
    }

    // Filter checkboxes: any combination of categories can be shown. Check
    // Meta alone, then Meta + Notes together (the multi-select the old
    // exclusive combo couldn't express), then restore all.
    const auto setChecks = [filterMenu](const QStringList &names) {
        const QList<QAction *> actions = filterMenu->actions();
        for (QAction *action : actions)
            action->setChecked(names.contains(action->text()));
    };
    const auto &filterEvents = doc.smf().tracks[chunk].events;
    const size_t metas = size_t(std::count_if(filterEvents.begin(), filterEvents.end(),
                                              [](const SmfEvent &ev) { return ev.isMeta(); }));
    const size_t notes =
        size_t(std::count_if(filterEvents.begin(), filterEvents.end(), [](const SmfEvent &ev) {
            return ev.isChannel() && (ev.typeNibble() == 0x8 || ev.typeNibble() == 0x9);
        }));
    setChecks({QStringLiteral("Meta")});
    if (model->rowCount() != int(metas) + 1)
        fail("meta filter shows the wrong row count");
    setChecks({QStringLiteral("Meta"), QStringLiteral("Notes")});
    if (model->rowCount() != int(metas + notes) + 1)
        fail("meta+notes filter shows the wrong row count");
    setChecks({}); // nothing checked hides every event
    if (model->rowCount() != 1)
        fail("empty filter still shows events");
    const QList<QAction *> filterActions = filterMenu->actions();
    for (QAction *action : filterActions)
        action->setChecked(true);
    if (model->rowCount() != int(filterEvents.size()) + 1)
        fail("all-checked filter does not show every event");

    // A complete TrackRemap reaches the list before documentChanged. The
    // visible SMF owner follows a move and survives changes to another
    // owner; when its own chunk goes away, undo/redo must leave it
    // unselected instead of treating the restored chunk as its old anchor.
    int anchorEngine = -1;
    for (int engine = 0; engine < doc.engineTrackCount(); engine++) {
        if (doc.smfTrackFor(engine) == chunk) {
            anchorEngine = engine;
            break;
        }
    }
    if (anchorEngine >= 0) {
        QStringList notifications;
        QObject notificationObserver;
        QObject::connect(&doc, &SongDocument::tracksRemapped, &notificationObserver,
                         [&notifications](TrackRemap) { notifications.append(QStringLiteral("remap")); });
        QObject::connect(&doc, &SongDocument::documentChanged, &notificationObserver,
                         [&notifications] { notifications.append(QStringLiteral("changed")); });
        const auto expectNotifications = [&](bool remapped, const char *what) {
            const QStringList expected =
                remapped ? QStringList{QStringLiteral("remap"), QStringLiteral("changed")}
                         : QStringList{QStringLiteral("changed")};
            if (notifications != expected)
                fail(what);
        };
        const auto expectAnchor = [&](int expectedChunk, const char *what) {
            if (expectedChunk < 0) {
                if (chunkCombo->currentIndex() >= 0 || model->rowCount() != 0)
                    fail(what);
                return;
            }
            if (chunkCombo->currentIndex() < 0 || chunkCombo->currentData().toInt() != expectedChunk ||
                expectedChunk >= int(doc.smf().tracks.size())) {
                fail(what);
                return;
            }
            if (model->rowCount() != int(doc.smf().tracks[expectedChunk].events.size()) + 1)
                fail(what);
        };
        const int anchorChunk = doc.smfTrackFor(anchorEngine);

        if (doc.engineTrackCount() >= 2) {
            const int target =
                anchorEngine == doc.engineTrackCount() - 1 ? 0 : doc.engineTrackCount() - 1;
            notifications.clear();
            view.moveTrack(anchorEngine, target);
            expectNotifications(true, "track move did not notify remap before documentChanged");
            const int movedChunk = doc.smfTrackFor(target);
            expectAnchor(movedChunk, "chunk combo did not follow the moved track");

            notifications.clear();
            doc.undoStack()->undo();
            expectNotifications(true, "undoing a track move did not notify in order");
            expectAnchor(anchorChunk, "undoing the move did not re-anchor the chunk combo");

            notifications.clear();
            doc.undoStack()->redo();
            expectNotifications(true, "redoing a track move did not notify in order");
            expectAnchor(movedChunk, "redoing the move did not re-anchor the chunk combo");

            notifications.clear();
            doc.undoStack()->undo();
            expectNotifications(true, "restoring a moved track did not notify in order");
            expectAnchor(anchorChunk, "restoring a moved track lost the chunk anchor");
        }

        QString renamed = QStringLiteral("eventviewcheck remap");
        if (doc.trackName(anchorEngine) == renamed)
            renamed += QStringLiteral(" 2");
        notifications.clear();
        doc.renameTrack(anchorEngine, renamed);
        expectNotifications(false, "metadata-only edit emitted a track remap");
        expectAnchor(anchorChunk, "metadata-only edit changed the chunk anchor");
        notifications.clear();
        doc.undoStack()->undo();
        expectNotifications(false, "undoing metadata-only edit emitted a track remap");
        expectAnchor(anchorChunk, "undoing metadata-only edit changed the chunk anchor");
        notifications.clear();
        doc.undoStack()->redo();
        expectNotifications(false, "redoing metadata-only edit emitted a track remap");
        expectAnchor(anchorChunk, "redoing metadata-only edit changed the chunk anchor");
        notifications.clear();
        doc.undoStack()->undo();
        expectNotifications(false, "restoring metadata-only edit emitted a track remap");
        expectAnchor(anchorChunk, "restoring metadata-only edit changed the chunk anchor");

        int metadataChunk = -1;
        for (int candidate = 0; candidate < int(doc.smf().tracks.size()); candidate++) {
            bool hasEngine = false;
            for (int engine = 0; engine < doc.engineTrackCount(); engine++) {
                if (doc.smfTrackFor(engine) == candidate) {
                    hasEngine = true;
                    break;
                }
            }
            if (!hasEngine) {
                metadataChunk = candidate;
                break;
            }
        }
        int freeChannel = -1;
        for (int candidate = 0; candidate < 16 && freeChannel < 0; candidate++) {
            bool used = false;
            for (int engine = 0; engine < doc.engineTrackCount(); engine++) {
                if (doc.channelFor(engine) == candidate) {
                    used = true;
                    break;
                }
            }
            if (!used)
                freeChannel = candidate;
        }
        if (metadataChunk >= 0 && freeChannel >= 0) {
            const int metadataComboIndex = chunkCombo->findData(metadataChunk);
            if (metadataComboIndex < 0) {
                fail("metadata chunk is absent from the chunk combo");
            } else {
                // This chunk has no roll owner, so activate it through the
                // list itself. Its index survives the edit, but its owner
                // label changes only when EventListView consumes the remap.
                chunkCombo->setCurrentIndex(metadataComboIndex);
                if (!QMetaObject::invokeMethod(chunkCombo, "activated", Qt::DirectConnection,
                                               Q_ARG(int, metadataComboIndex))) {
                    fail("could not select the metadata chunk in the event list");
                }
                const auto engineForMetadataChunk = [&] {
                    for (int engine = 0; engine < doc.engineTrackCount(); engine++) {
                        if (doc.smfTrackFor(engine) == metadataChunk)
                            return engine;
                    }
                    return -1;
                };
                const auto expectTransitionState =
                    [&](int expectedEngineCount, int expectedOwner, bool expectProgram,
                        const char *what) {
                        if (doc.engineTrackCount() != expectedEngineCount ||
                            engineForMetadataChunk() != expectedOwner) {
                            fail(what);
                            return;
                        }
                        expectAnchor(metadataChunk, what);
                        const QString expectedLabel =
                            expectedOwner >= 0
                                ? QStringLiteral("Chunk %1 — Track %2")
                                      .arg(metadataChunk)
                                      .arg(expectedOwner + 1)
                                : QStringLiteral("Chunk %1 (tempo/meta)").arg(metadataChunk);
                        if (chunkCombo->currentText() != expectedLabel) {
                            fail(what);
                            return;
                        }
                        bool programShown = false;
                        for (int row = 0; row + 1 < model->rowCount(); row++) {
                            if (model->data(model->index(row, 1), Qt::DisplayRole).toString() ==
                                    QStringLiteral("Program change") &&
                                model->data(model->index(row, 2), Qt::DisplayRole).toInt() ==
                                    freeChannel + 1) {
                                programShown = true;
                                break;
                            }
                        }
                        if (programShown != expectProgram)
                            fail(what);
                    };
                const int engineCount = doc.engineTrackCount();
                expectTransitionState(engineCount, -1, false,
                                      "metadata chunk was not the active list source");
                SmfEvent program;
                program.status = uint8_t(0xc0 | freeChannel);
                program.data0 = 0;
                notifications.clear();
                doc.insertRawEvent(metadataChunk, program);
                expectNotifications(true,
                                    "engine-track transition did not notify remap before documentChanged");
                const int programOwner = engineForMetadataChunk();
                if (programOwner < 0) {
                    fail("program event did not create an engine owner");
                } else {
                    expectTransitionState(engineCount + 1, programOwner, true,
                                          "engine-track transition left stale list owner state");
                }
                notifications.clear();
                doc.undoStack()->undo();
                expectNotifications(true, "undoing engine-track transition did not notify in order");
                expectTransitionState(engineCount, -1, false,
                                      "undoing engine-track transition left stale list owner state");
                notifications.clear();
                doc.undoStack()->redo();
                expectNotifications(true, "redoing engine-track transition did not notify in order");
                if (programOwner >= 0) {
                    expectTransitionState(engineCount + 1, programOwner, true,
                                          "redoing engine-track transition left stale list owner state");
                }
                notifications.clear();
                doc.undoStack()->undo();
                expectNotifications(true, "restoring engine-track transition did not notify in order");
                expectTransitionState(engineCount, -1, false,
                                      "restoring engine-track transition left stale list owner state");
                const int anchorComboIndex = chunkCombo->findData(anchorChunk);
                if (anchorComboIndex < 0) {
                    fail("original chunk is absent from the chunk combo");
                } else {
                    chunkCombo->setCurrentIndex(anchorComboIndex);
                    if (!QMetaObject::invokeMethod(chunkCombo, "activated", Qt::DirectConnection,
                                                   Q_ARG(int, anchorComboIndex))) {
                        fail("could not restore the original chunk in the event list");
                    }
                    expectAnchor(anchorChunk, "could not restore the original chunk anchor");
                }
            }
        }

        if (doc.canAddTrack()) {
            notifications.clear();
            const int addedEngine = doc.addTrack(0);
            if (addedEngine < 0) {
                fail("addTrack was available but did not add a track");
            } else {
                const int addedChunk = doc.smfTrackFor(addedEngine);
                expectNotifications(true, "track insertion did not notify remap before documentChanged");
                expectAnchor(anchorChunk, "track insertion changed the existing chunk anchor");
                view.selectTrack(addedEngine);
                expectAnchor(addedChunk, "could not anchor the inserted chunk");

                notifications.clear();
                doc.undoStack()->undo();
                expectNotifications(true, "undoing track insertion did not notify in order");
                expectAnchor(-1, "undoing track insertion kept a deleted chunk anchor");
                notifications.clear();
                doc.undoStack()->redo();
                expectNotifications(true, "redoing track insertion did not notify in order");
                expectAnchor(-1, "redoing track insertion selected the inserted chunk");
                view.selectTrack(anchorEngine);
                view.selectTrack(addedEngine);
                expectAnchor(addedChunk, "could not reselect the inserted chunk");

                notifications.clear();
                doc.deleteTrack(addedEngine);
                expectNotifications(true, "track deletion did not notify remap before documentChanged");
                expectAnchor(-1, "track deletion kept a deleted chunk anchor");
                notifications.clear();
                doc.undoStack()->undo();
                expectNotifications(true, "undoing track deletion did not notify in order");
                expectAnchor(-1, "undoing track deletion selected the restored chunk");
                notifications.clear();
                doc.undoStack()->redo();
                expectNotifications(true, "redoing track deletion did not notify in order");
                expectAnchor(-1, "redoing track deletion selected the deleted chunk");

                notifications.clear();
                doc.undoStack()->undo();
                expectNotifications(true, "restoring deleted track did not notify in order");
                expectAnchor(-1, "restoring deleted track selected an inserted chunk");
                notifications.clear();
                doc.undoStack()->undo();
                expectNotifications(true, "removing inserted track did not notify in order");
                expectAnchor(-1, "removing inserted track selected another chunk");
                view.selectTrack(anchorEngine);
                expectAnchor(anchorChunk, "could not restore the original chunk anchor");
            }
        }

        if (doc.canAddTrack()) {
            notifications.clear();
            const int copyEngine = doc.duplicateTrack(anchorEngine);
            if (copyEngine < 0) {
                fail("duplicateTrack was available but did not duplicate a track");
            } else {
                expectNotifications(true, "track duplication did not notify remap before documentChanged");
                expectAnchor(anchorChunk, "track duplication changed the source chunk anchor");
                notifications.clear();
                doc.undoStack()->undo();
                expectNotifications(true, "undoing track duplication did not notify in order");
                expectAnchor(anchorChunk, "undoing track duplication changed the source chunk anchor");
                notifications.clear();
                doc.undoStack()->redo();
                expectNotifications(true, "redoing track duplication did not notify in order");
                expectAnchor(anchorChunk, "redoing track duplication changed the source chunk anchor");
                notifications.clear();
                doc.undoStack()->undo();
                expectNotifications(true, "restoring duplicated track did not notify in order");
                expectAnchor(anchorChunk, "restoring duplicated track changed the source chunk anchor");
            }
        }
    }

    // Playhead marker: exactly the row the play cursor last passed carries a
    // background tint (the last of a same-tick run), the end-of-track row
    // once the playhead passes the end. Row focus commits the edit cursor at
    // the row's tick, but programmatic restores after document edits do not.
    auto *events = view.findChild<EventListView *>();
    uint64_t markerTick = 0; // left on-screen for the screenshot
    if (!events) {
        fail("EventListView child not found");
    } else if (!doc.smf().tracks[chunk].events.empty()) {
        const auto tinted = [&](int row) {
            return model->data(model->index(row, 0), Qt::BackgroundRole).isValid();
        };
        {
            // A raw playhead push has no focused-row preference. Clear any
            // current row left by the remap exercise before checking it.
            table->selectionModel()->clearCurrentIndex();
            events->setPlayheadTick(-1.0, false);
            const auto &track = doc.smf().tracks[chunk];
            const auto &evs = track.events;
            const auto expectedRowForTick = [&evs, &track, model](uint64_t tick) {
                if (tick >= track.endTick)
                    return model->rowCount() - 1;
                const auto it = std::upper_bound(
                    evs.begin(), evs.end(), tick,
                    [](uint64_t tick, const SmfEvent &event) { return tick < event.tick; });
                return int(it - evs.begin()) - 1;
            };
            // Prefer an ordinary event row. When every event coincides with
            // EOT, rowForTick intentionally selects the EOT row instead.
            int markerEvent = -1;
            for (int i = 0; i < int(evs.size()); i++) {
                if (evs[i].tick < track.endTick)
                    markerEvent = i;
            }
            markerTick = markerEvent >= 0 ? evs[markerEvent].tick : track.endTick;
            const int expect = expectedRowForTick(markerTick);
            const int eotRow = model->rowCount() - 1;
            events->setPlayheadTick(double(markerTick), false);
            if (expect < 0 || !tinted(expect))
                fail("playhead row not tinted");
            if ((expect > 0 && tinted(expect - 1)) ||
                (expect + 1 < model->rowCount() && tinted(expect + 1)))
                fail("playhead tint on the wrong row");
            // If the raw marker is EOT, move off it first to keep a stale-tint
            // assertion without falsely treating an EOT event as ordinary.
            if (expect == eotRow) {
                events->setPlayheadTick(-1.0, false);
                if (tinted(eotRow))
                    fail("stale playhead tint after the playhead moved");
            }
            events->setPlayheadTick(double(track.endTick) + 10.0, false);
            if (!tinted(eotRow))
                fail("end-of-track row not tinted past the end");
            if (expect != eotRow && tinted(expect))
                fail("stale playhead tint after the playhead moved");
            // The SongView wiring pushes ticks through setPlayheadSample.
            // Move its sample position first: returning zero to an already
            // zero-position view must not be the only state transition.
            int zeroRun = 0;
            while (zeroRun < int(evs.size()) && evs[zeroRun].tick == 0)
                zeroRun++;
            if (zeroRun > 0)
                view.setPlayheadSample(tl->sampleForTick(track.endTick + 1), false);
            view.setPlayheadSample(0, false);
            const int zeroRow = expectedRowForTick(0);
            if (zeroRun > 0 && (zeroRow < 0 || !tinted(zeroRow)))
                fail("setPlayheadSample did not tint the tick-zero row");
        }
        {
            const auto &evs = doc.smf().tracks[chunk].events;
            table->setCurrentIndex(model->index(int(evs.size()) - 1, 0));
            if (view.editCursorTick() != evs.back().tick)
                fail("row focus did not move the edit cursor");
            table->setCurrentIndex(model->index(model->rowCount() - 1, 0));
            if (view.editCursorTick() != doc.smf().tracks[chunk].endTick)
                fail("end-of-track focus did not move the edit cursor");
        }
        {
            // Focusing one row of a same-tick run tints exactly that row —
            // not the run's last sibling — and survives the engine pushing
            // the tick back a hair low (the committed tick round-trips
            // tick→sample→tick). A current row at a different tick gets no
            // such preference.
            int runFirst = -1;
            bool madeRun = false;
            {
                const auto &evs = doc.smf().tracks[chunk].events;
                for (size_t i = 0; i + 1 < evs.size(); i++) {
                    if (evs[i].tick == evs[i + 1].tick) {
                        runFirst = int(i);
                        break;
                    }
                }
            }
            if (runFirst < 0) { // no natural run: twin row 0 to make one
                events->insertCopyOfRow(0);
                runFirst = 0;
                madeRun = true;
            }
            const auto &evs = doc.smf().tracks[chunk].events;
            const double runTick = double(evs[runFirst].tick);
            int runLast = runFirst;
            while (runLast + 1 < int(evs.size()) && evs[runLast + 1].tick == evs[runFirst].tick)
                runLast++;
            // Make the raw push below a state transition even when this run
            // is at tick zero, then focus the intended sibling before it.
            events->setPlayheadTick(-1.0, false);
            table->setCurrentIndex(model->index(runFirst, 0));
            events->setPlayheadTick(runTick, false);
            if (!tinted(runFirst))
                fail("focused row of a same-tick run not tinted");
            if (tinted(runLast))
                fail("same-tick sibling tinted instead of the focused row");
            if (runTick > 0) {
                events->setPlayheadTick(runTick - 0.001, false);
                if (!tinted(runFirst))
                    fail("sample-rounded playhead tick lost the focused row");
            }
            // Focusing a sibling moves the tint without a new playhead push
            // (the cursor tick doesn't change, so nothing re-seeks).
            table->setCurrentIndex(model->index(runLast, 0));
            if (!tinted(runLast) || tinted(runFirst))
                fail("re-focus inside the run did not move the tint");
            // A current row at another tick gets no preference: the run's
            // last row keeps the "most recently fired" tint.
            int other = -1;
            for (int i = 0; i < int(evs.size()); i++) {
                if (evs[i].tick != evs[runFirst].tick) {
                    other = i;
                    break;
                }
            }
            if (other >= 0) {
                table->setCurrentIndex(model->index(other, 0));
                events->setPlayheadTick(runTick, false);
                if (!tinted(runLast))
                    fail("off-tick current row stole the playhead tint");
                if (tinted(other))
                    fail("playhead tint followed an off-tick current row");
            }
            if (madeRun)
                doc.undoStack()->undo();
        }
        {
            // A document edit reloads the table and restores the current row
            // programmatically; that must not commit the edit cursor.
            const uint64_t cursorBefore = view.editCursorTick();
            SmfEvent probe;
            probe.tick = doc.smf().tracks[chunk].endTick + 50;
            probe.status = 0xB0;
            probe.data0 = 7;
            probe.data1 = 64;
            doc.insertRawEvent(chunk, probe);
            if (view.editCursorTick() != cursorBefore)
                fail("document refresh moved the edit cursor");
            doc.undoStack()->undo();
            if (view.editCursorTick() != cursorBefore)
                fail("undo refresh moved the edit cursor");
        }
        {
            // Context-menu insert: a copy of the clicked row at its own
            // tick, placed by the document (still sorted), undoable.
            const SmfEvent src = doc.smf().tracks[chunk].events[0];
            const size_t had = countMatching(doc.smf().tracks[chunk], src);
            events->insertCopyOfRow(0);
            if (countMatching(doc.smf().tracks[chunk], src) != had + 1)
                fail("insertCopyOfRow did not add a twin of the source row");
            if (!trackSorted(doc.smf().tracks[chunk]))
                fail("insertCopyOfRow broke tick order");
            if (model->rowCount() != int(doc.smf().tracks[chunk].events.size()) + 1)
                fail("table did not refresh after insertCopyOfRow");
            doc.undoStack()->undo();
            if (countMatching(doc.smf().tracks[chunk], src) != had)
                fail("undo did not remove the copied event");
            // The end-of-track row is not a copyable event; a no-op.
            const size_t total = doc.smf().tracks[chunk].events.size();
            events->insertCopyOfRow(model->rowCount() - 1);
            if (doc.smf().tracks[chunk].events.size() != total)
                fail("insertCopyOfRow on the end-of-track row mutated the chunk");
        }
        {
            // Same-tick reorder. A fresh tick group past the end — CC 7,
            // CC 10, note-on — swaps its CC pair by a model drop (the drag's
            // engine) and swaps it back with the Alt+Up nudge through the
            // table's event filter; illegal gaps (past the note-on, another
            // tick) are refused before any mutation.
            const int chunk2 = chunkCombo->currentData().toInt();
            const uint64_t group = doc.smf().tracks[chunk2].endTick + 100;
            SmfEvent ccA;
            ccA.tick = group;
            ccA.status = 0xB0;
            ccA.data0 = 7;
            ccA.data1 = 1;
            SmfEvent ccB = ccA;
            ccB.data0 = 10;
            ccB.data1 = 2;
            SmfEvent on;
            on.tick = group;
            on.status = 0x90;
            on.data0 = 60;
            on.data1 = 90;
            doc.insertRawEvent(chunk2, ccA);
            doc.insertRawEvent(chunk2, ccB);
            doc.insertRawEvent(chunk2, on);
            const long long iA = indexOf(doc.smf().tracks[chunk2], ccA);
            const long long iB = indexOf(doc.smf().tracks[chunk2], ccB);
            const long long iN = indexOf(doc.smf().tracks[chunk2], on);
            if (iA < 0 || iB != iA + 1 || iN != iA + 2) {
                fail("ui reorder scaffold not in canonical order");
            } else {
                // Unfiltered, display rows == event indices.
                const std::unique_ptr<QMimeData> mime(model->mimeData({model->index(int(iA), 0)}));
                if (!mime) {
                    fail("row drag produced no mime data");
                } else {
                    if (!model->canDropMimeData(mime.get(), Qt::MoveAction, int(iN), 0,
                                                QModelIndex()))
                        fail("legal same-tick drop refused");
                    if (model->canDropMimeData(mime.get(), Qt::MoveAction, int(iN) + 1, 0,
                                               QModelIndex()))
                        fail("drop past a same-tick note-on accepted");
                    if (model->canDropMimeData(mime.get(), Qt::MoveAction, 0, 0, QModelIndex()))
                        fail("cross-tick drop accepted");
                    if (!model->dropMimeData(mime.get(), Qt::MoveAction, int(iN), 0, QModelIndex()))
                        fail("legal same-tick drop not performed");
                    QCoreApplication::processEvents(); // queued reorder + refresh
                    const auto &evs = doc.smf().tracks[chunk2];
                    if (indexOf(evs, ccB) != iA || indexOf(evs, ccA) != iB)
                        fail("drop did not swap the same-tick CC pair");
                    if (table->currentIndex().row() != int(iB))
                        fail("selection did not follow the dropped event");
                }
                // Nudge the pair back: current row is the dropped CC, one
                // Alt+Up returns it ahead of its sibling.
                table->setCurrentIndex(model->index(int(iB), 0));
                QKeyEvent press(QEvent::KeyPress, Qt::Key_Up, Qt::AltModifier);
                QCoreApplication::sendEvent(table, &press);
                const auto &evs = doc.smf().tracks[chunk2];
                if (indexOf(evs, ccA) != iA || indexOf(evs, ccB) != iB)
                    fail("Alt+Up nudge did not restore the pair's order");
                if (table->currentIndex().row() != int(iA))
                    fail("selection did not follow the nudged event");
                // At the top of its legal range: a further nudge is a no-op.
                const int undoCount = doc.undoStack()->count();
                QKeyEvent again(QEvent::KeyPress, Qt::Key_Up, Qt::AltModifier);
                QCoreApplication::sendEvent(table, &again);
                if (doc.undoStack()->count() != undoCount)
                    fail("a blocked nudge pushed an undo entry");
            }
            // Leave the song as found: two reorders + three inserts.
            for (int i = 0; i < 5 && doc.undoStack()->canUndo(); i++)
                doc.undoStack()->undo();
        }
        {
            // Deleting a multi-row selection clears the highlight: the
            // refresh's by-position restore must not repaint the deleted
            // rows' selection onto the surviving rows.
            const int chunk2 = chunkCombo->currentData().toInt();
            const uint64_t group = doc.smf().tracks[chunk2].endTick + 100;
            SmfEvent ccA;
            ccA.tick = group;
            ccA.status = 0xB0;
            ccA.data0 = 7;
            ccA.data1 = 11;
            SmfEvent ccB = ccA;
            ccB.data0 = 10;
            ccB.data1 = 22;
            doc.insertRawEvent(chunk2, ccA);
            doc.insertRawEvent(chunk2, ccB);
            const long long iA = indexOf(doc.smf().tracks[chunk2], ccA);
            const long long iB = indexOf(doc.smf().tracks[chunk2], ccB);
            if (iA < 0 || iB < 0) {
                fail("multi-delete scaffold not inserted");
            } else {
                // Unfiltered, display rows == event indices.
                QItemSelection sel;
                sel.select(model->index(int(iA), 0),
                           model->index(int(iA), model->columnCount() - 1));
                sel.select(model->index(int(iB), 0),
                           model->index(int(iB), model->columnCount() - 1));
                // Current first: setCurrentIndex issues its own
                // ClearAndSelect and would collapse the pair to one row.
                table->setCurrentIndex(model->index(int(iB), 0));
                table->selectionModel()->select(sel, QItemSelectionModel::ClearAndSelect);
                QKeyEvent del(QEvent::KeyPress, Qt::Key_Delete, Qt::NoModifier);
                QCoreApplication::sendEvent(table, &del);
                const auto &evs = doc.smf().tracks[chunk2];
                if (countMatching(evs, ccA) != 0 || countMatching(evs, ccB) != 0)
                    fail("Delete key did not remove the selected rows");
                if (table->selectionModel()->hasSelection())
                    fail("multi-row delete left the selection painted");
                if (table->currentIndex().isValid())
                    fail("multi-row delete left a stale current row");
                // Single-row delete keeps a current row (the refresh lands
                // it on the next event) so repeated Delete presses mow
                // through the list.
                doc.insertRawEvent(chunk2, ccA);
                const long long iSolo = indexOf(doc.smf().tracks[chunk2], ccA);
                if (iSolo < 0) {
                    fail("single-delete scaffold not inserted");
                } else {
                    table->setCurrentIndex(model->index(int(iSolo), 0));
                    QKeyEvent del2(QEvent::KeyPress, Qt::Key_Delete, Qt::NoModifier);
                    QCoreApplication::sendEvent(table, &del2);
                    if (countMatching(doc.smf().tracks[chunk2], ccA) != 0)
                        fail("single-row Delete did not remove the row");
                    if (!table->currentIndex().isValid())
                        fail("single-row delete lost the current row");
                }
            }
            // Leave the song as found: two deletes + three inserts.
            for (int i = 0; i < 5 && doc.undoStack()->canUndo(); i++)
                doc.undoStack()->undo();
        }
        {
            // The app-wide Follow Playhead toggle: off, the playing row
            // keeps its tint but the running scrollTo stops — the table
            // stays where the user scrolled it. grab() first so the table
            // has real geometry; a short song (the first song is often a
            // sound effect) gets padded with undoable row copies until the
            // table actually overflows its viewport.
            (void)view.grab();
            auto *vbar = table->verticalScrollBar();
            int padded = 0;
            while (vbar->maximum() <= 0 && padded < 200) {
                for (int i = 0; i < 25 && padded < 200; i++, padded++)
                    events->insertCopyOfRow(0);
                (void)view.grab();
            }
            if (vbar->maximum() <= 0) {
                fail("event table has no scroll range for the follow check");
            } else {
                const double pastEnd = double(doc.smf().tracks[chunk].endTick) + 10.0;
                events->setPlayheadTick(0.0, false); // park the play row high
                vbar->setValue(0);
                events->setPlayheadTick(pastEnd, true);
                if (vbar->value() == 0)
                    fail("follow-on playback did not scroll the event table");
                events->setPlayheadTick(0.0, false);
                vbar->setValue(0);
                events->setFollowPlayhead(false);
                events->setPlayheadTick(pastEnd, true);
                if (vbar->value() != 0)
                    fail("follow-off playback scrolled the event table");
                if (!tinted(model->rowCount() - 1))
                    fail("follow-off playback lost the playhead tint");
                events->setFollowPlayhead(true);
            }
            // Leave the song as found.
            for (int i = 0; i < padded && doc.undoStack()->canUndo(); i++)
                doc.undoStack()->undo();
        }
        // For the screenshot: playing, so the follow-scroll brings the
        // tinted row into view (also exercises the scrollTo path).
        events->setPlayheadTick(double(markerTick), true);
    }

    const QImage image = view.grab().toImage();
    if (image.isNull())
        fail("offscreen render produced no image");
    if (!screenshotPath.isEmpty()) {
        image.save(screenshotPath);
        std::printf("eventviewcheck: wrote %s\n", qUtf8Printable(screenshotPath));
    }

    // View-state round trip carries the mode both ways.
    SongView::ViewState state = view.viewState();
    if (!state.eventList)
        fail("viewState does not record the event list mode");
    state.eventList = false;
    view.applyViewState(state);
    if (view.eventListVisible())
        fail("applyViewState did not restore the roll");

    view.setDocument(nullptr);
    view.setSong(nullptr, nullptr);
    return failures;
}

} // namespace

int runEventViewCheck(const QString &projectRoot, const QString &screenshotSong,
                      const QString &screenshotPath)
{
    // The UI pass drives keymap-bound nudges (Alt+Up), so redirect QSettings
    // into a temp dir: the check must see the shipped defaults, not the
    // user's rebindings.
    QTemporaryDir settingsDir;
    if (settingsDir.isValid()) {
        QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, settingsDir.path());
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDir.path());
    }

    DecompProject project;
    QString error;
    if (!project.open(projectRoot, &error)) {
        std::fprintf(stderr, "eventviewcheck: %s\n", qUtf8Printable(error));
        return 1;
    }

    QElapsedTimer timer;
    timer.start();

    int checked = 0, failures = 0;
    bool uiChecked = false;
    for (const SongInfo &song : project.songs()) {
        if (!song.isPlayable())
            continue;

        SongDocument doc;
        if (!doc.load(song, &error)) {
            std::fprintf(stderr, "eventviewcheck: FAIL %s: %s\n", qUtf8Printable(song.label),
                         qUtf8Printable(error));
            failures++;
            continue;
        }
        const QByteArray baseline = doc.smf().write();
        const int chunk = pickChunk(doc);
        if (chunk < 0)
            continue;

        auto fail = [&](const char *what) {
            std::fprintf(stderr, "eventviewcheck: FAIL %s: %s\n", qUtf8Printable(song.label), what);
            failures++;
        };
        const auto &track = doc.smf().tracks[chunk];

        uint8_t channel = 0;
        for (const SmfEvent &ev : track.events) {
            if (ev.isChannel()) {
                channel = ev.channel();
                break;
            }
        }
        uint64_t base = 0;
        for (const SmfTrack &t : doc.smf().tracks)
            base = std::max(base, t.endTick);
        base += 100;

        const size_t before = track.events.size();
        bool ok = true;

        // Insert: appended past everything, and the EOT follows it out.
        SmfEvent ev;
        ev.tick = base;
        ev.status = uint8_t(0xB0 | channel);
        ev.data0 = 7;
        ev.data1 = 64;
        doc.insertRawEvent(chunk, ev);
        if (track.events.size() != before + 1 || !trackSorted(track) ||
            countMatching(track, ev) != 1 || track.endTick != base) {
            fail("insertRawEvent produced wrong content");
            ok = false;
        }

        // Same-tick modify: in place, no reorder.
        if (ok) {
            const long long idx = indexOf(track, ev);
            SmfEvent edited = ev;
            edited.data1 = 99;
            doc.modifyRawEvent(chunk, size_t(idx), edited);
            if (indexOf(track, edited) != idx || !trackSorted(track)) {
                fail("same-tick modifyRawEvent produced wrong content");
                ok = false;
            }
            ev = edited;
        }

        // Tick-moving modify: re-inserted at the new position, still sorted.
        if (ok) {
            const long long idx = indexOf(track, ev);
            SmfEvent moved = ev;
            moved.tick = 0;
            const size_t movedBefore = countMatching(track, moved);
            doc.modifyRawEvent(chunk, size_t(idx), moved);
            if (countMatching(track, moved) != movedBefore + 1 || !trackSorted(track) ||
                track.events.size() != before + 1) {
                fail("tick-moving modifyRawEvent produced wrong content");
                ok = false;
            }
            ev = moved;
        }

        // Delete brings the chunk back to its original event count.
        if (ok) {
            const size_t had = countMatching(track, ev);
            doc.deleteRawEvents(chunk, {size_t(indexOf(track, ev))});
            if (track.events.size() != before || countMatching(track, ev) != had - 1) {
                fail("deleteRawEvents produced wrong content");
                ok = false;
            }
        }

        // End-of-track moves freely forward but clamps at the last event.
        if (ok) {
            doc.setTrackEndTick(chunk, base + 500);
            if (track.endTick != base + 500) {
                fail("setTrackEndTick did not move the end");
                ok = false;
            }
            const uint64_t lastTick = track.events.empty() ? 0 : track.events.back().tick;
            doc.setTrackEndTick(chunk, 0);
            if (track.endTick != lastTick) {
                fail("setTrackEndTick not clamped at the last event");
                ok = false;
            }
        }

        // Reorder: a same-tick setup pair swaps by explicit position — the
        // one raw edit that picks position — while the clamp keeps setup
        // ahead of the group's note-on and refuses to leave the tick.
        if (ok) {
            const uint64_t group = base + 1000;
            SmfEvent ccA;
            ccA.tick = group;
            ccA.status = uint8_t(0xB0 | channel);
            ccA.data0 = 7;
            ccA.data1 = 1;
            SmfEvent ccB = ccA;
            ccB.data0 = 10;
            ccB.data1 = 2;
            SmfEvent on;
            on.tick = group;
            on.status = uint8_t(0x90 | channel);
            on.data0 = 60;
            on.data1 = 100;
            doc.insertRawEvent(chunk, ccA);
            doc.insertRawEvent(chunk, ccB);
            doc.insertRawEvent(chunk, on);
            const long long iA = indexOf(track, ccA);
            const long long iB = indexOf(track, ccB);
            const long long iN = indexOf(track, on);
            if (iA < 0 || iB != iA + 1 || iN != iA + 2) {
                fail("reorder scaffold not in canonical order");
                ok = false;
            }
            size_t first = 0, last = 0;
            if (ok) {
                // The CC roams its setup run, never past the note-on; the
                // note-on is pinned behind the whole run.
                if (!doc.rawEventMoveBounds(chunk, size_t(iA), &first, &last) ||
                    first != size_t(iA) || last != size_t(iB)) {
                    fail("rawEventMoveBounds wrong for a same-tick setup event");
                    ok = false;
                }
                if (!doc.rawEventMoveBounds(chunk, size_t(iN), &first, &last) ||
                    first != size_t(iN) || last != size_t(iN)) {
                    fail("rawEventMoveBounds lets a note-on cross its setup run");
                    ok = false;
                }
            }
            if (ok) {
                doc.moveRawEvent(chunk, size_t(iA), size_t(iB));
                if (indexOf(track, ccB) != iA || indexOf(track, ccA) != iB ||
                    indexOf(track, on) != iN || !trackSorted(track)) {
                    fail("moveRawEvent did not swap the same-tick pair");
                    ok = false;
                }
            }
            if (ok) {
                // Clamped moves that land on the current position are no-ops
                // and must not grow the undo stack: past the note-on (the
                // event already sits at its last legal slot) and across the
                // tick boundary toward index 0.
                const int undoCount = doc.undoStack()->count();
                doc.moveRawEvent(chunk, size_t(iB), size_t(iN));
                doc.moveRawEvent(chunk, size_t(iA), 0);
                if (doc.undoStack()->count() != undoCount || indexOf(track, ccA) != iB ||
                    indexOf(track, ccB) != iA) {
                    fail("a clamped no-op move mutated the chunk or undo stack");
                    ok = false;
                }
            }
            if (ok) {
                // Direct undo/redo of the move: the final undo-all cannot see
                // a broken MoveEvent revert, because the whole scaffold group
                // is erased by the insert undos either way.
                doc.undoStack()->undo();
                if (indexOf(track, ccA) != iA || indexOf(track, ccB) != iB) {
                    fail("undoing the reorder did not restore the order");
                    ok = false;
                }
                doc.undoStack()->redo();
                if (indexOf(track, ccA) != iB || indexOf(track, ccB) != iA) {
                    fail("redoing the reorder did not reapply the swap");
                    ok = false;
                }
            }
        }

        // Undo everything: byte-identical; redo deterministic. (Most of the
        // script is net-zero — insert, move, delete, EOT clamped back — so
        // the redone bytes are compared against the captured edited state,
        // not against "anything but the baseline". The reorder scaffold
        // above stays in, putting the swap itself under both comparisons.)
        const QByteArray edited = doc.smf().write();
        while (doc.undoStack()->canUndo())
            doc.undoStack()->undo();
        if (doc.smf().write() != baseline) {
            fail("undo-all did not restore the original bytes");
        } else {
            while (doc.undoStack()->canRedo())
                doc.undoStack()->redo();
            const QByteArray redone = doc.smf().write();
            while (doc.undoStack()->canUndo())
                doc.undoStack()->undo();
            if (doc.smf().write() != baseline)
                fail("undo after redo did not restore the original bytes");
            else if (redone != edited)
                fail("redo-all did not reproduce the edited state");
        }

        // The UI pass runs once — on the named screenshot song, else the
        // first playable song whose chunk has events (mus_dummy sorts
        // first and its empty chunk would silently skip every
        // event-dependent check).
        if (song.label == screenshotSong) {
            uiChecked = true;
            failures += runUiPass(song, screenshotPath);
        } else if (!uiChecked && screenshotSong.isEmpty() &&
                   !doc.smf().tracks[chunk].events.empty()) {
            uiChecked = true;
            failures += runUiPass(song, QString());
        }
        checked++;
    }

    std::printf("eventviewcheck: %d songs in %lld ms\n", checked, (long long)timer.elapsed());
    std::printf("eventviewcheck: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
