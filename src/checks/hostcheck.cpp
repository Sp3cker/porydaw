#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "project/decompproject.h"
#include "ui/editordrawer/automationarea.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"

#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QFileInfo>
#include <QImage>
#include <QKeyEvent>
#include <QMenu>
#include <QMouseEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QTemporaryDir>
#include <QTimer>
#include <QWidget>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

namespace {

SmfEvent noteEvent(uint8_t status, uint64_t tick, uint8_t key, uint8_t velocity)
{
    SmfEvent event;
    event.status = status;
    event.tick = tick;
    event.data0 = key;
    event.data1 = velocity;
    return event;
}

void sendMouse(QWidget &widget, QEvent::Type type, const QPointF &position, Qt::MouseButton button,
               Qt::MouseButtons buttons = Qt::NoButton)
{
    QMouseEvent event(type, position, QPointF(widget.mapToGlobal(position.toPoint())), button,
                      buttons, Qt::NoModifier);
    QApplication::sendEvent(&widget, &event);
}

void sendKey(QWidget &widget, Qt::Key key)
{
    QKeyEvent event(QEvent::KeyPress, key, Qt::NoModifier);
    QApplication::sendEvent(&widget, &event);
}

uint64_t drawerContextTick(double tick)
{
    return static_cast<uint64_t>(std::floor(std::max(0.0, tick) + 0.5));
}

EditorDrawer *editorDrawer(SongView &view)
{
    for (QWidget *widget : view.findChildren<QWidget *>()) {
        if (auto *drawer = dynamic_cast<EditorDrawer *>(widget))
            return drawer;
    }
    return nullptr;
}

VelocityArea *velocityArea(SongView &view)
{
    auto *drawer = editorDrawer(view);
    return drawer ? drawer->velocityArea() : nullptr;
}

AutomationArea *automationArea(SongView &view)
{
    auto *drawer = editorDrawer(view);
    auto *page = drawer ? drawer->automationPage() : nullptr;
    return page ? page->area() : nullptr;
}

songview::PlayheadOverlay *playheadOverlay(SongView &view)
{
    for (QWidget *widget : view.findChildren<QWidget *>()) {
        if (auto *overlay = dynamic_cast<songview::PlayheadOverlay *>(widget))
            return overlay;
    }
    return nullptr;
}

QPointF nodePosition(const SongView &view, const VelocityArea &area, const MidiTimeline &timeline,
                     const DocNote &note)
{
    const double x = double(area.plotOrigin()) +
                     double(note.tick) * view.pxPerBeat() / double(timeline.ticksPerBeat) -
                     view.viewState().scrollPx;
    return {x, area.axis().velocityToY(note.velocity)};
}

} // namespace

int runHostAdapterCheck(const QString &scratchProject, const QString &songLabel)
{
    int failures = 0;
    const auto check = [&failures, &songLabel](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "host-adapter: FAIL %s: %s\n", qUtf8Printable(songLabel), message);
            ++failures;
        }
    };

    check(QFileInfo(scratchProject).isDir(), "scratch project does not exist");
    check(!songLabel.isEmpty(), "song label is empty");
    if (failures)
        return 1;

    DecompProject fixtureProject;
    QString fixtureError;
    check(fixtureProject.open(scratchProject, &fixtureError), "fixture project should load");
    const SongInfo *fixtureSong = nullptr;
    if (fixtureProject.isOpen()) {
        for (const SongInfo &song : fixtureProject.songs()) {
            if (song.label == songLabel && song.isPlayable()) {
                fixtureSong = &song;
                break;
            }
        }
    }
    check(fixtureSong != nullptr, "fixture song label should resolve to a playable song");
    SongDocument fixtureDocument;
    std::unique_ptr<MidiTimeline> fixtureTimeline;
    std::optional<DocNote> fixtureNote;
    if (fixtureSong) {
        check(fixtureDocument.load(*fixtureSong, &fixtureError),
              "fixture song should load through SongDocument");
        fixtureTimeline = fixtureDocument.buildTimeline(44100.0);
        check(fixtureTimeline != nullptr, "fixture song should build a timeline");
        if (fixtureTimeline) {
            for (int track = 0; track < fixtureTimeline->usedTrackCount; ++track) {
                const std::vector<DocNote> notes = fixtureDocument.notesForTrack(track);
                if (!notes.empty()) {
                    fixtureNote = notes.front();
                    break;
                }
            }
            bool timelineHasFixtureNote = false;
            if (fixtureNote) {
                timelineHasFixtureNote =
                    std::any_of(fixtureTimeline->events.cbegin(), fixtureTimeline->events.cend(),
                                [noteId = fixtureNote->noteId](const TimelineEvent &event) {
                                    return event.type == 0x9 && event.noteId == noteId;
                                });
            }
            check(!fixtureTimeline->events.empty() && fixtureNote.has_value() &&
                      timelineHasFixtureNote,
                  "fixture song should contain timeline and note data");
        }
    }
    if (fixtureTimeline && fixtureNote) {
        SongView fixtureView;
        fixtureView.resize(720, 520);
        fixtureView.setDocument(&fixtureDocument);
        fixtureView.setSong(fixtureTimeline.get(), nullptr);
        fixtureView.show();
        QCoreApplication::processEvents();
        fixtureView.selectTrack(fixtureNote->engineTrack);
        const std::vector<NoteId> fixtureSelection{fixtureNote->noteId};
        fixtureView.selectionModel().setNoteSelection(fixtureSelection);
        fixtureView.setEditCursorTick(fixtureNote->tick);
        fixtureView.setDrawerActivePage(EditorDrawerPage::Velocity);
        fixtureView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        QCoreApplication::processEvents();
        auto *fixtureDrawer = fixtureView.editorDrawer();
        auto *fixtureArea = velocityArea(fixtureView);
        check(fixtureDocument.label() == songLabel &&
                  fixtureView.timeline() == fixtureTimeline.get() && fixtureDrawer &&
                  fixtureDrawer->isVisible() && fixtureArea &&
                  fixtureView.selectionModel().primaryTrack() == fixtureNote->engineTrack &&
                  fixtureView.selectionModel().noteSelection() == fixtureSelection &&
                  fixtureArea->axis().markerCount() == 1 &&
                  fixtureArea->axis().markers()[0].velocity == fixtureNote->velocity,
              "adapter should attach supplied fixture note data to the hosted velocity page");
        fixtureView.hide();
    }
    if (failures)
        return 1;

    QTemporaryDir temporary;
    QString error;
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack primary;
    primary.events = {
        noteEvent(0xC0, 0, 0, 0),  noteEvent(0x90, 12, 60, 20), noteEvent(0x90, 12, 60, 70),
        noteEvent(0xC0, 24, 1, 0), noteEvent(0x80, 36, 60, 0),  noteEvent(0x80, 36, 60, 0),
    };
    primary.endTick = 36;
    SmfTrack secondary;
    secondary.events = {
        noteEvent(0x91, 12, 67, 80),
        noteEvent(0x81, 36, 67, 0),
    };
    secondary.endTick = 36;
    smf.tracks = {primary, secondary};

    const QString midiPath = temporary.path() + QStringLiteral("/host-adapter.mid");
    SongInfo song;
    song.label = QStringLiteral("host-adapter");
    song.midPath = midiPath;
    song.hasMid = true;
    SongDocument document;
    check(temporary.isValid() && smf.writeFile(midiPath, &error) && document.load(song, &error),
          "synthetic fixture should load");
    std::unique_ptr<MidiTimeline> timeline = document.buildTimeline(44100.0);
    check(timeline != nullptr, "synthetic fixture should build a timeline");
    if (failures)
        return 1;

    LoadedVoiceGroup voicegroup{};
    voicegroup.voices[0].type = VOICE_SQUARE_1;
    voicegroup.voices[1].type = VOICE_NOISE;
    SongView view;
    view.resize(720, 520);
    view.setDocument(&document);
    view.setSong(timeline.get(), &voicegroup);
    view.show();
    QCoreApplication::processEvents();

    auto *area = velocityArea(view);
    auto *overlay = playheadOverlay(view);
    check(area != nullptr, "host should construct the velocity page");
    check(overlay != nullptr, "host should construct the playhead overlay");
    if (!area || !overlay)
        return 1;

    EditorViewState editorState;
    editorState.velocity = {true, 180};
    editorState.automation.visible = false;
    editorState.activePage = EditorDrawerPage::Velocity;
    editorState.laneHeight = 42;
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, 0, 74};
    editorState.emptyLanes.insert(lane);
    editorState.laneRanges.emplace(lane, 96);
    view.applyEditorViewState(editorState);
    QCoreApplication::processEvents();
    check(view.editorViewState() == editorState &&
              view.drawerActivePage() == EditorDrawerPage::Velocity &&
              view.drawerSectionVisible(EditorDrawerPage::Velocity),
          "editor view state should attach without becoming document state");
    const uint64_t revisionBeforeViewCapture = document.revision();
    const int undoBeforeViewCapture = document.undoStack()->count();
    const SongView::ViewState capturedView = view.viewState();
    const EditorViewState capturedEditor = view.editorViewState();
    check(capturedView.valid && capturedEditor.emptyLanes.size() == 1 &&
              capturedEditor.emptyLanes.count(lane) == 1 &&
              document.revision() == revisionBeforeViewCapture &&
              document.undoStack()->count() == undoBeforeViewCapture,
          "detached view-state capture should not save document state");
    check(drawerContextTick(-1.0) == 0 && drawerContextTick(0.49) == 0 &&
              drawerContextTick(0.5) == 1 && drawerContextTick(0.51) == 1,
          "drawer tick should use the neutral shared conversion");

    auto *drawer = editorDrawer(view);
    check(drawer && drawer->isVisible(), "drawer should remain visible above other events");
    auto *otherStrip = view.findChild<QWidget *>(QStringLiteral("otherEventsStrip"));
    auto *sections =
        drawer ? drawer->findChild<QWidget *>(QStringLiteral("drawerSections")) : nullptr;
    auto *velocityHandle =
        drawer ? drawer->findChild<QWidget *>(QStringLiteral("velocityResizeHandle")) : nullptr;
    auto *automationHandle =
        drawer ? drawer->findChild<QWidget *>(QStringLiteral("automationResizeHandle")) : nullptr;
    auto *velocityToggle =
        drawer ? drawer->findChild<QWidget *>(QStringLiteral("velocityDrawerToggle")) : nullptr;
    auto *automationToggle =
        drawer ? drawer->findChild<QWidget *>(QStringLiteral("automationDrawerToggle")) : nullptr;
    auto *automationBar =
        drawer ? drawer->findChild<QWidget *>(QStringLiteral("automationDrawerBar")) : nullptr;
    check(otherStrip && otherStrip->isVisible(), "other events strip should remain visible");
    check(sections && velocityHandle && automationHandle && velocityToggle && automationToggle &&
              automationBar,
          "drawer should create independent section chrome");
    if (drawer && otherStrip && sections && velocityHandle && automationHandle && velocityToggle &&
        automationToggle && automationBar) {
        const QRect drawerBounds(drawer->mapTo(&view, QPoint()), drawer->size());
        const QRect toggleGroup = automationToggle->geometry().united(velocityToggle->geometry());
        const int pianoKeysCenter = area->geometry().x() + area->plotOrigin() / 2;
        check(drawerBounds.bottom() < otherStrip->geometry().top(),
              "drawer should stack above the other events strip");
        check(sections->geometry() == drawer->rect() && !velocityHandle->isHidden() &&
                  automationHandle->isHidden() && area->isVisible() &&
                  drawer->automationPage()->isHidden() && !automationBar->isHidden() &&
                  velocityHandle->geometry().bottom() + 1 == area->geometry().top() &&
                  area->geometry().bottom() + 1 == automationBar->geometry().top() &&
                  automationBar->geometry().contains(automationToggle->geometry()) &&
                  automationBar->geometry().contains(velocityToggle->geometry()) &&
                  velocityToggle->x() == automationToggle->x() + automationToggle->width() +
                                             layout::space(layout::Space::One) &&
                  std::abs(toggleGroup.center().x() - pianoKeysCenter) <= 1,
              "drawer section chrome should center its toggles beneath the piano keys");
    }
    if (otherStrip) {
        const QImage stripWithoutLoopMarkers = otherStrip->grab().toImage();
        document.setLoopTick(false, 6);
        document.setLoopTick(true, 18);
        std::unique_ptr<MidiTimeline> loopTimeline = document.buildTimeline(44100.0);
        check(loopTimeline && loopTimeline->loopStartTick == 6 && loopTimeline->loopEndTick == 18,
              "fixture loop markers should reach the timeline");
        if (loopTimeline) {
            view.updateSong(loopTimeline.get());
            timeline = std::move(loopTimeline);
            QCoreApplication::processEvents();
            check(otherStrip->grab().toImage() == stripWithoutLoopMarkers,
                  "loop markers should not appear in the Other Events strip");
        }
    }
    view.setDrawerActivePage(EditorDrawerPage::Automations);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    QCoreApplication::processEvents();
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    auto *automation = automationArea(view);
    check(automation != nullptr, "host should construct the automation page");
    if (automation) {
        const int selectedTrack = view.selectionModel().primaryTrack();
        view.setTrackSolo(selectedTrack, false);
        sendKey(*area, Qt::Key_S);
        check(view.trackSoloed(selectedTrack),
              "S from the velocity drawer did not solo the selected track");
        view.setTrackSolo(selectedTrack, false);

        view.selectionModel().clearNoteSelection();
        view.setEditCursorTick(0);
        QCoreApplication::processEvents();
        check(QString::fromLatin1(area->axis().map().voiceName()) == QStringLiteral("Square 1"),
              "velocity map should resolve the edit-cursor voice while stopped");

        view.setPlayheadSample(timeline->sampleForTick(24), true);
        QCoreApplication::processEvents();
        check(QString::fromLatin1(area->axis().map().voiceName()) == QStringLiteral("Noise"),
              "visible velocity page should immediately resolve the playback voice");
        const auto warmVelocity = area->diagnostics();
        for (int tick = 25; tick < 27; ++tick)
            view.setPlayheadSample(timeline->sampleForTick(uint64_t(tick)), true);
        QCoreApplication::processEvents();
        check(area->diagnostics().contentBuildCount == warmVelocity.contentBuildCount &&
                  area->diagnostics().playheadPresentationCount ==
                      warmVelocity.playheadPresentationCount + 2,
              "steady same-context playback should not rebuild visible velocity content");

        view.setPlayheadSample(timeline->sampleForTick(26), false);
        QCoreApplication::processEvents();
        check(QString::fromLatin1(area->axis().map().voiceName()) == QStringLiteral("Square 1"),
              "stopping should return visible velocity map to the edit cursor");
        view.setPlayheadSample(timeline->sampleForTick(12), true);
        QCoreApplication::processEvents();
        const auto velocityBeforeCrossing = area->diagnostics();
        view.setPlayheadSample(timeline->sampleForTick(24), true);
        QCoreApplication::processEvents();
        check(QString::fromLatin1(area->axis().map().voiceName()) == QStringLiteral("Noise") &&
                  area->diagnostics().contentBuildCount >
                      velocityBeforeCrossing.contentBuildCount &&
                  area->diagnostics().playheadPresentationCount ==
                      velocityBeforeCrossing.playheadPresentationCount + 1,
              "visible velocity map should refresh and present once across a voice change");

        view.setPlayheadSample(timeline->sampleForTick(24), false);
        view.setDrawerActivePage(EditorDrawerPage::Automations);
        QCoreApplication::processEvents();
        const QImage editCursorContext = automation->grab().toImage();
        view.setPlayheadSample(timeline->sampleForTick(24), true);
        QCoreApplication::processEvents();
        const QImage playbackContext = automation->grab().toImage();
        check(playbackContext != editCursorContext,
              "visible automation page should immediately resolve the playback voice");
        const auto warmAutomation = automation->diagnostics();
        for (int tick = 25; tick < 27; ++tick)
            view.setPlayheadSample(timeline->sampleForTick(uint64_t(tick)), true);
        QCoreApplication::processEvents();
        check(automation->diagnostics() == warmAutomation,
              "steady same-context playback should not rebuild visible automation content");

        view.setPlayheadSample(timeline->sampleForTick(26), false);
        QCoreApplication::processEvents();
        check(automation->grab().toImage() == editCursorContext,
              "stopping should return visible automation context to the edit cursor");
        view.setPlayheadSample(timeline->sampleForTick(12), true);
        QCoreApplication::processEvents();
        const QImage squarePlaybackContext = automation->grab().toImage();
        const auto automationBeforeCrossing = automation->diagnostics();
        view.setPlayheadSample(timeline->sampleForTick(24), true);
        QCoreApplication::processEvents();
        check(automation->grab().toImage() != squarePlaybackContext &&
                  automation->diagnostics().contentInvalidationCount >
                      automationBeforeCrossing.contentInvalidationCount,
              "visible automation context should refresh when playback crosses a voice change");
        view.setPlayheadSample(timeline->sampleForTick(24), false);
        QCoreApplication::processEvents();
        const QPointF menuStart(layout::fontPx(17.5 + 13.0 / 3.0) + 4.0, 4.0);
        const QPointF menuEnd = menuStart + QPointF(48.0, 0.0);
        const QPointF menuPoint = (menuStart + menuEnd) / 2.0;
        sendMouse(*automation, QEvent::MouseButtonPress, menuStart, Qt::RightButton,
                  Qt::RightButton);
        sendMouse(*automation, QEvent::MouseMove, menuEnd, Qt::NoButton, Qt::RightButton);
        sendMouse(*automation, QEvent::MouseButtonRelease, menuEnd, Qt::RightButton);
        sendMouse(*automation, QEvent::MouseButtonPress, menuPoint, Qt::RightButton,
                  Qt::RightButton);
        QTimer::singleShot(0, [] {
            if (auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget()))
                menu->close();
        });
        sendMouse(*automation, QEvent::MouseButtonRelease, menuPoint, Qt::RightButton);
        const songview::TimeSelection &menuSelection = view.selectionModel().timeSelection();
        check(menuSelection.active() && menuSelection.scope == songview::TimeSelection::Lanes &&
                  menuSelection.lanes.size() == 1 && menuSelection.lanes.front().first == -1 &&
                  menuSelection.lanes.front().second == DOC_CC_TEMPO,
              "automation range menu should delegate its lane scope to the host");
        view.selectionModel().clearTimeSelection();
    }

    check(document.moveTrack(0, 1), "fixture track move should succeed");
    const EditorAutomationRowId movedLane{EditorAutomationRowKind::ControlChange, 1, 74};
    check(view.editorViewState().emptyLanes.count(movedLane) == 1,
          "track remap should reach hosted cosmetics before document refresh");
    std::unique_ptr<MidiTimeline> remappedTimeline = document.buildTimeline(44100.0);
    view.updateSong(remappedTimeline.get());
    timeline = std::move(remappedTimeline);

    std::vector<DocNote> notes = document.notesForTrack(view.selectionModel().primaryTrack());
    check(notes.size() == 2, "remapped selected track should retain duplicate-note identities");
    if (notes.size() != 2)
        return 1;

    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 200);
    view.selectionModel().setNoteSelection({notes[0].noteId, notes[1].noteId});
    view.setEditCursorTick(1);
    QCoreApplication::processEvents();

    const QPointF firstNode = nodePosition(view, *area, *timeline, notes[0]);
    const std::vector<NoteId> selected = view.selectionModel().noteSelection();
    std::vector<NoteVelocity> unchangedVelocities;
    unchangedVelocities.reserve(notes.size());
    for (const DocNote &note : notes)
        unchangedVelocities.push_back({note.noteId, note.velocity});
    const uint64_t revisionBeforeNoChange = document.revision();
    const int undoBeforeNoChange = document.undoStack()->count();
    const bool beganNoChange = view.beginVelocityGesture(notes);
    const bool updatedNoChange = view.updateVelocityGesture(unchangedVelocities);
    const auto committedNoChange = view.commitVelocityGesture();
    const std::vector<DocNote> notesAfterNoChange =
        document.notesForTrack(view.selectionModel().primaryTrack());
    check(beganNoChange && !updatedNoChange &&
              committedNoChange == SongView::VelocityCommitResult::Unchanged &&
              !view.previewVelocity(notes[0].noteId) && !view.previewVelocity(notes[1].noteId) &&
              document.revision() == revisionBeforeNoChange &&
              document.undoStack()->count() == undoBeforeNoChange &&
              notesAfterNoChange.size() == notes.size() &&
              notesAfterNoChange[0].velocity == notes[0].velocity &&
              notesAfterNoChange[1].velocity == notes[1].velocity &&
              view.selectionModel().noteSelection() == selected,
          "host no-op gesture should preserve preview, revision, MIDI, Undo, and selection");
    const int undoBeforeChange = document.undoStack()->count();
    const uint64_t revisionBeforeChange = document.revision();
    sendMouse(*area, QEvent::MouseButtonPress, firstNode, Qt::LeftButton, Qt::LeftButton);
    sendMouse(*area, QEvent::MouseMove, firstNode + QPointF(0.0, -double(area->height())),
              Qt::NoButton, Qt::LeftButton);
    const auto heldFirstPreview = view.previewVelocity(notes[0].noteId);
    const auto heldSecondPreview = view.previewVelocity(notes[1].noteId);
    DocNote heldFirst;
    DocNote heldSecond;
    check(document.findNote(notes[0].noteId, &heldFirst) &&
              document.findNote(notes[1].noteId, &heldSecond) &&
              heldFirst.velocity == notes[0].velocity && heldSecond.velocity == notes[1].velocity &&
              heldFirstPreview && heldSecondPreview && *heldFirstPreview != notes[0].velocity &&
              *heldSecondPreview != notes[1].velocity &&
              document.revision() == revisionBeforeChange &&
              document.undoStack()->count() == undoBeforeChange,
          "velocity host moves must update preview without changing document history");
    sendMouse(*area, QEvent::MouseButtonRelease, firstNode + QPointF(0.0, -double(area->height())),
              Qt::LeftButton);
    DocNote committedFirst;
    DocNote committedSecond;
    check(document.revision() == revisionBeforeChange + 1 &&
              document.undoStack()->count() == undoBeforeChange + 1 &&
              document.findNote(notes[0].noteId, &committedFirst) &&
              document.findNote(notes[1].noteId, &committedSecond) && heldFirstPreview &&
              heldSecondPreview && committedFirst.velocity == *heldFirstPreview &&
              committedSecond.velocity == *heldSecondPreview &&
              !view.previewVelocity(notes[0].noteId) && !view.previewVelocity(notes[1].noteId) &&
              view.selectionModel().noteSelection() == selected,
          "velocity host release should commit one exact batch, clear preview, and preserve "
          "selection");

    document.undoStack()->undo();
    check(view.selectionModel().noteSelection() == selected &&
              document.undoStack()->count() == undoBeforeChange + 1,
          "undo should preserve shared selection while retaining the exact velocity history entry");
    document.undoStack()->redo();

    notes = document.notesForTrack(view.selectionModel().primaryTrack());
    view.selectionModel().setNoteSelection({notes[0].noteId, notes[1].noteId});
    view.setEditCursorTick(2);
    QCoreApplication::processEvents();
    const QPointF unchangedNode = nodePosition(view, *area, *timeline, notes[0]);
    const uint64_t revisionBeforeNoOp = document.revision();
    const int undoBeforeNoOp = document.undoStack()->count();
    sendMouse(*area, QEvent::MouseButtonPress, unchangedNode, Qt::LeftButton, Qt::LeftButton);
    sendMouse(*area, QEvent::MouseButtonRelease, unchangedNode, Qt::LeftButton);
    check(document.revision() == revisionBeforeNoOp &&
              document.undoStack()->count() == undoBeforeNoOp &&
              view.selectionModel().noteSelection().size() == 1 &&
              std::find(selected.cbegin(), selected.cend(),
                        view.selectionModel().noteSelection().front()) != selected.cend(),
          "unchanged stacked-node click should leave history untouched and collapse selection");

    notes = document.notesForTrack(view.selectionModel().primaryTrack());
    view.selectionModel().setNoteSelection(selected);
    view.setEditCursorTick(3);
    QCoreApplication::processEvents();
    const QPointF staleNode = nodePosition(view, *area, *timeline, notes[0]);
    sendMouse(*area, QEvent::MouseButtonPress, staleNode, Qt::LeftButton, Qt::LeftButton);
    const uint64_t revisionBeforeExternalChange = document.revision();
    const int secondVelocity = notes[1].velocity == 127 ? 1 : 127;
    document.blockSignals(true);
    document.setNotesVelocity({notes[1]}, uint8_t(secondVelocity));
    document.blockSignals(false);
    sendMouse(*area, QEvent::MouseMove, staleNode + QPointF(0.0, -double(area->height())),
              Qt::NoButton, Qt::LeftButton);
    sendMouse(*area, QEvent::MouseButtonRelease, staleNode + QPointF(0.0, -double(area->height())),
              Qt::LeftButton);
    const std::vector<DocNote> staleNotes =
        document.notesForTrack(view.selectionModel().primaryTrack());
    check(document.revision() == revisionBeforeExternalChange + 1 && staleNotes.size() == 2 &&
              staleNotes[1].velocity == secondVelocity && !view.previewVelocity(notes[0].noteId) &&
              !view.previewVelocity(notes[1].noteId) &&
              view.selectionModel().noteSelection() == selected,
          "stale velocity batch should apply none of its frozen request, clear preview, and cancel "
          "its gesture");

    std::unique_ptr<MidiTimeline> staleTimeline = document.buildTimeline(44100.0);
    view.updateSong(staleTimeline.get());
    timeline = std::move(staleTimeline);
    notes = document.notesForTrack(view.selectionModel().primaryTrack());
    view.selectionModel().setNoteSelection({notes[0].noteId});
    view.setEditCursorTick(4);
    QCoreApplication::processEvents();
    const QPointF lifecycleNode = nodePosition(view, *area, *timeline, notes[0]);
    const auto cancelGesture = [&](const QPointF &node, auto cancel, bool clearsSelection,
                                   const char *message) {
        const uint64_t revision = document.revision();
        const int undo = document.undoStack()->count();
        DocNote pressedNote;
        const std::vector<NoteId> selectionBeforeGesture = view.selectionModel().noteSelection();
        const bool pressedNoteResolved =
            !selectionBeforeGesture.empty() &&
            document.findNote(selectionBeforeGesture.front(), &pressedNote);
        const QPointF dragPosition =
            node + QPointF(0.0, pressedNoteResolved && pressedNote.velocity == 127 ? 40.0 : -40.0);
        sendMouse(*area, QEvent::MouseButtonPress, node, Qt::LeftButton, Qt::LeftButton);
        sendMouse(*area, QEvent::MouseMove, dragPosition, Qt::NoButton, Qt::LeftButton);
        const std::vector<NoteId> gestureSelection = view.selectionModel().noteSelection();
        const std::vector<NoteId> expectedSelection =
            clearsSelection ? std::vector<NoteId>{} : gestureSelection;
        bool previewStaged = !gestureSelection.empty();
        bool previewChanged = false;
        for (const NoteId id : gestureSelection) {
            DocNote liveNote;
            const auto preview = view.previewVelocity(id);
            const bool noteResolved = document.findNote(id, &liveNote);
            previewStaged = previewStaged && preview.has_value() && noteResolved;
            if (preview && noteResolved && *preview != liveNote.velocity)
                previewChanged = true;
        }
        check(previewStaged && previewChanged && document.revision() == revision &&
                  document.undoStack()->count() == undo,
              "velocity cancellation should begin with changed staged previews and unchanged "
              "history");
        cancel();
        sendMouse(*area, QEvent::MouseButtonRelease, dragPosition, Qt::LeftButton);
        bool previewCleared = true;
        for (const NoteId id : gestureSelection)
            previewCleared = previewCleared && !view.previewVelocity(id);
        check(document.revision() == revision && document.undoStack()->count() == undo &&
                  previewCleared && view.selectionModel().noteSelection() == expectedSelection,
              message);
    };
    cancelGesture(
        lifecycleNode, [&] { view.setDrawerActivePage(EditorDrawerPage::Automations); }, false,
        "drawer page switch should terminate the visible page gesture");
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setEditCursorTick(5);
    QCoreApplication::processEvents();
    cancelGesture(
        lifecycleNode,
        [&] {
            QKeyEvent escape(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
            QApplication::sendEvent(&view, &escape);
        },
        false, "Escape should terminate the visible page gesture through the host lifecycle");
    cancelGesture(
        lifecycleNode, [&] { view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false); },
        false, "drawer close should terminate the visible page gesture");
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    cancelGesture(
        lifecycleNode,
        [&] {
            QEvent ungrab(QEvent::UngrabMouse);
            QApplication::sendEvent(&view, &ungrab);
        },
        false, "mouse-grab loss should terminate the visible page gesture");
    cancelGesture(
        lifecycleNode,
        [&] {
            QEvent deactivate(QEvent::WindowDeactivate);
            QApplication::sendEvent(&view, &deactivate);
        },
        false, "window deactivation should terminate the visible page gesture");
    LoadedVoiceGroup replacementVoicegroup{};
    QPointF replacementNode = nodePosition(view, *area, *timeline, notes[0]);
    cancelGesture(
        replacementNode, [&] { view.setVoicegroup(&replacementVoicegroup); }, false,
        "voice replacement should terminate the visible page gesture");
    view.setVoicegroup(nullptr);
    replacementNode = nodePosition(view, *area, *timeline, notes[0]);
    cancelGesture(
        replacementNode, [&] { view.setSong(timeline.get(), nullptr); }, true,
        "song replacement should terminate the visible page gesture");
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.selectTrack(1);
    notes = document.notesForTrack(view.selectionModel().primaryTrack());
    view.selectionModel().setNoteSelection({notes[0].noteId});
    view.setEditCursorTick(7);
    QCoreApplication::processEvents();

    const QPointF documentNode = nodePosition(view, *area, *timeline, notes[0]);
    const uint64_t revisionBeforeDocumentReplacement = document.revision();
    const int undoBeforeDocumentReplacement = document.undoStack()->count();
    const std::vector<NoteId> selectionBeforeDocumentReplacement =
        view.selectionModel().noteSelection();
    sendMouse(*area, QEvent::MouseButtonPress, documentNode, Qt::LeftButton, Qt::LeftButton);
    sendMouse(*area, QEvent::MouseMove, documentNode + QPointF(0.0, -40.0), Qt::NoButton,
              Qt::LeftButton);
    const auto documentReplacementPreview = view.previewVelocity(notes[0].noteId);
    check(selectionBeforeDocumentReplacement.size() == 1 && documentReplacementPreview &&
              document.revision() == revisionBeforeDocumentReplacement &&
              document.undoStack()->count() == undoBeforeDocumentReplacement,
          "document replacement should begin with a staged preview and unchanged history");
    view.setDocument(nullptr);
    sendMouse(*area, QEvent::MouseButtonRelease, documentNode + QPointF(0.0, -40.0),
              Qt::LeftButton);
    check(document.revision() == revisionBeforeDocumentReplacement,
          "document replacement should not change document revision");
    check(document.undoStack()->count() == undoBeforeDocumentReplacement,
          "document replacement should not change document history");
    check(!view.previewVelocity(notes[0].noteId),
          "document replacement should clear the visible velocity preview");
    check(view.selectionModel().noteSelection().empty(),
          "document replacement should clear the note selection");
    view.setDocument(&document);
    view.selectionModel().setNoteSelection({notes[0].noteId});
    view.setEditCursorTick(8);
    QCoreApplication::processEvents();

    const int replacementVelocity = notes[0].velocity == 127 ? 1 : 127;
    const int undoBeforeMutation = document.undoStack()->count();
    const uint64_t revisionBeforeMutation = document.revision();
    const std::vector<NoteId> selectionBeforeMutation = view.selectionModel().noteSelection();
    sendMouse(*area, QEvent::MouseButtonPress, documentNode, Qt::LeftButton, Qt::LeftButton);
    sendMouse(*area, QEvent::MouseMove, documentNode + QPointF(0.0, -40.0), Qt::NoButton,
              Qt::LeftButton);
    const auto mutationPreview = view.previewVelocity(notes[0].noteId);
    check(mutationPreview && document.revision() == revisionBeforeMutation &&
              document.undoStack()->count() == undoBeforeMutation,
          "document mutation should begin with a staged preview and unchanged history");
    document.setNotesVelocity({notes[0]}, uint8_t(replacementVelocity));
    sendMouse(*area, QEvent::MouseButtonRelease, documentNode + QPointF(0.0, -40.0),
              Qt::LeftButton);
    check(document.revision() == revisionBeforeMutation + 1 &&
              document.undoStack()->count() == undoBeforeMutation + 1 &&
              !view.previewVelocity(notes[0].noteId) &&
              view.selectionModel().noteSelection() == selectionBeforeMutation,
          "document mutation should cancel the visible preview without applying its staged batch");

    DocNote undoNote = notes[0];
    check(document.findNote(notes[0].noteId, &undoNote),
          "Undo cancellation fixture should resolve its current note");
    const QPointF undoNode = nodePosition(view, *area, *timeline, undoNote);
    const uint64_t revisionBeforeUndo = document.revision();
    const int undoBeforeUndo = document.undoStack()->count();
    const std::vector<NoteId> selectionBeforeUndo = view.selectionModel().noteSelection();
    sendMouse(*area, QEvent::MouseButtonPress, undoNode, Qt::LeftButton, Qt::LeftButton);
    sendMouse(*area, QEvent::MouseMove, undoNode + QPointF(0.0, -40.0), Qt::NoButton,
              Qt::LeftButton);
    const auto undoPreview = view.previewVelocity(notes[0].noteId);
    check(undoPreview && document.revision() == revisionBeforeUndo &&
              document.undoStack()->count() == undoBeforeUndo,
          "Undo cancellation should begin with a staged preview and unchanged history");
    document.undoStack()->undo();
    sendMouse(*area, QEvent::MouseButtonRelease, undoNode + QPointF(0.0, -40.0), Qt::LeftButton);
    check(document.revision() == revisionBeforeUndo + 1 &&
              document.undoStack()->count() == undoBeforeUndo &&
              !view.previewVelocity(notes[0].noteId) &&
              view.selectionModel().noteSelection() == selectionBeforeUndo,
          "Undo should terminate the visible page gesture");

    DocNote redoNote = notes[0];
    check(document.findNote(notes[0].noteId, &redoNote),
          "Redo cancellation fixture should resolve its current note");
    const QPointF redoNode = nodePosition(view, *area, *timeline, redoNote);
    const uint64_t revisionBeforeRedo = document.revision();
    const int undoBeforeRedo = document.undoStack()->count();
    const std::vector<NoteId> selectionBeforeRedo = view.selectionModel().noteSelection();
    sendMouse(*area, QEvent::MouseButtonPress, redoNode, Qt::LeftButton, Qt::LeftButton);
    sendMouse(*area, QEvent::MouseMove, redoNode + QPointF(0.0, -40.0), Qt::NoButton,
              Qt::LeftButton);
    const auto redoPreview = view.previewVelocity(notes[0].noteId);
    check(redoPreview && document.revision() == revisionBeforeRedo &&
              document.undoStack()->count() == undoBeforeRedo,
          "Redo cancellation should begin with a staged preview and unchanged history");
    document.undoStack()->redo();
    sendMouse(*area, QEvent::MouseButtonRelease, redoNode + QPointF(0.0, -40.0), Qt::LeftButton);
    check(document.revision() == revisionBeforeRedo + 1 &&
              document.undoStack()->count() == undoBeforeRedo &&
              !view.previewVelocity(notes[0].noteId) &&
              view.selectionModel().noteSelection() == selectionBeforeRedo,
          "Redo should terminate the visible page gesture");

    DocNote reloadNote = notes[0];
    check(document.findNote(notes[0].noteId, &reloadNote),
          "reload cancellation fixture should resolve its current note");
    const QPointF reloadNode = nodePosition(view, *area, *timeline, reloadNote);
    const uint64_t revisionBeforeReload = document.revision();
    const int undoBeforeReload = document.undoStack()->count();
    sendMouse(*area, QEvent::MouseButtonPress, reloadNode, Qt::LeftButton, Qt::LeftButton);
    sendMouse(*area, QEvent::MouseMove, reloadNode + QPointF(0.0, -40.0), Qt::NoButton,
              Qt::LeftButton);
    const auto reloadPreview = view.previewVelocity(notes[0].noteId);
    check(reloadPreview && document.revision() == revisionBeforeReload &&
              document.undoStack()->count() == undoBeforeReload,
          "reload cancellation should begin with a staged preview and unchanged history");
    const bool reloaded = document.load(song, &error);
    sendMouse(*area, QEvent::MouseButtonRelease, reloadNode + QPointF(0.0, -40.0), Qt::LeftButton);
    check(reloaded && !view.previewVelocity(notes[0].noteId),
          "reload should terminate the visible page gesture");
    std::unique_ptr<MidiTimeline> reloadedTimeline = document.buildTimeline(44100.0);
    view.updateSong(reloadedTimeline.get());
    timeline = std::move(reloadedTimeline);

    view.hide();
    return failures == 0 ? 0 : 1;
}

int runHostSeamsCheck()
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *what) {
        if (!condition) {
            std::fprintf(stderr, "host-seams: FAIL: %s\n", what);
            ++failures;
        }
    };

    auto state = EditorViewState{};
    check(!state.velocity.visible && !state.velocity.height && state.automation.visible &&
              !state.automation.height && state.activePage == EditorDrawerPage::Automations &&
              state.laneHeight == 0 && state.laneHeights.empty() && state.laneRanges.empty() &&
              state.emptyLanes.empty() && state.hiddenLanes().empty(),
          "new songs default to an open Automations drawer with cosmetic lane state");
    const auto controllerRow = EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 2, 1};
    auto changedState = state;
    changedState.velocity = {false, 144};
    changedState.automation = {true, 96};
    changedState.activePage = EditorDrawerPage::Velocity;
    changedState.laneHeight = 96;
    changedState.laneHeights.emplace(controllerRow, 112);
    changedState.laneRanges.emplace(controllerRow, 91);
    changedState.emptyLanes.emplace(controllerRow);
    changedState.hideLane(controllerRow);
    check(changedState != state, "typed cosmetic lane state compares by value");

    QTemporaryDir temporary;
    QString error;
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events = {
        noteEvent(0xC0, 0, 0, 0),
        noteEvent(0x90, 12, 60, 64),
        noteEvent(0x80, 36, 60, 0),
        noteEvent(0xB0, 24000, 1, 0),
    };
    track.endTick = 24000;
    smf.tracks.push_back(track);
    SongInfo song;
    song.label = QStringLiteral("editor-state");
    song.midPath = temporary.path() + QStringLiteral("/editor-state.mid");
    song.hasMid = true;
    SongDocument document;
    check(temporary.isValid() && smf.writeFile(song.midPath, &error) && document.load(song, &error),
          "concrete editor fixture should load");
    auto timeline = document.buildTimeline(44100.0);
    check(timeline != nullptr, "concrete editor fixture should build a timeline");
    if (!timeline)
        return 1;

    LoadedVoiceGroup voicegroup{};
    voicegroup.voices[0].type = VOICE_SQUARE_1;
    SongView view;
    view.resize(900, 600);
    view.setDocument(&document);
    view.setSong(timeline.get(), &voicegroup);
    auto *drawer = view.editorDrawer();
    auto *automation = drawer ? drawer->automationPage() : nullptr;
    auto *velocity = drawer ? drawer->velocityArea() : nullptr;
    check(drawer && automation && velocity, "SongView must own both concrete drawer pages");
    if (!drawer || !automation || !velocity)
        return 1;

    view.applyEditorViewState(changedState);
    check(view.editorViewState() == changedState &&
              view.drawerActivePage() == EditorDrawerPage::Velocity &&
              !view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              view.drawerSectionVisible(EditorDrawerPage::Automations),
          "typed drawer state should attach through SongView without document mutation");
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 280);
    view.show();
    QCoreApplication::processEvents();

    view.setEditorHorizontalScroll(96.0);
    view.setEditorTimeZoom(1.75 * layout::fontPx(8.0 / 3.0));
    view.setFollowScrollPaused(true);
    view.focusContent();
    view.announce(QStringLiteral("editor-state"));
    view.showDrawerPageNoteStatus(DrawerPageNoteStatus{60, 64, 64, 24, 12});
    view.showDrawerPageNoteStatus(std::nullopt);
    view.requestDrawerPageUndo();
    view.requestDrawerPageRedo();
    const auto runtime = view.viewState();
    check(runtime.valid && runtime.scrollPx == 96.0 &&
              runtime.pxPerBeat == 1.75 * layout::fontPx(8.0 / 3.0),
          "SongView editor endpoints should update runtime camera state");
    const auto grid = view.gridState(12, false);
    const auto voice = view.voiceContext(12);
    check(grid.gridTicks > 0 && grid.snapTicks > 0 && voice.voice == &voicegroup.voices[0] &&
              voice.voiceSlot == 0,
          "SongView should resolve grid and voice state at concrete page ticks");

    auto live = DrawerPageLiveState{};
    live.documentRevision = document.revision();
    live.timeZoom = 48.0;
    live.horizontalScroll = 0.0;
    live.editCursorTick = 12;
    live.trackColor = QColor{10, 20, 30};
    live.playback = {12.0, true};
    automation->refreshLiveState(live);
    velocity->refreshLiveState(live);
    check(!automation->area()->rows().empty() &&
              velocity->axis().mode() == VelocityAxis::Mode::Intrinsic,
          "concrete pages should refresh live state through their SongView owner");

    const auto notes = document.notesForTrack(0);
    check(notes.size() == 1, "concrete fixture should retain its note identity");
    if (notes.empty())
        return 1;
    view.selectionModel().setNoteSelection({notes.front().noteId});
    const std::vector<NoteVelocity> velocities{{notes.front().noteId, 96}};
    const uint64_t revisionBeforeStale = document.revision();
    const int undoBeforeStale = document.undoStack()->count();
    const bool beganStale = view.beginVelocityGesture(notes);
    const bool updatedStale = view.updateVelocityGesture(velocities);
    check(beganStale && updatedStale && view.previewVelocity(notes.front().noteId) &&
              *view.previewVelocity(notes.front().noteId) == 96 &&
              document.revision() == revisionBeforeStale &&
              document.undoStack()->count() == undoBeforeStale,
          "concrete SongView should expose a deferred velocity preview");
    document.blockSignals(true);
    document.setNotesVelocity({notes.front()}, 95);
    document.blockSignals(false);
    const auto staleCommitted = view.commitVelocityGesture();
    DocNote staleNote;
    check(staleCommitted == SongView::VelocityCommitResult::Rejected &&
              document.revision() == revisionBeforeStale + 1 &&
              document.undoStack()->count() == undoBeforeStale + 1 &&
              document.findNote(notes.front().noteId, &staleNote) && staleNote.velocity == 95 &&
              !view.previewVelocity(notes.front().noteId),
          "stale SongView velocity gesture should be rejected atomically and clear its preview");

    const uint64_t revisionBeforeAccepted = document.revision();
    const int undoBeforeAccepted = document.undoStack()->count();
    const bool beganAccepted = view.beginVelocityGesture(document.notesForTrack(0));
    const bool updatedAccepted = view.updateVelocityGesture(velocities);
    const auto accepted = view.commitVelocityGesture();
    DocNote acceptedNote = notes.front();
    check(beganAccepted && updatedAccepted &&
              accepted == SongView::VelocityCommitResult::Committed &&
              document.revision() == revisionBeforeAccepted + 1 &&
              document.undoStack()->count() == undoBeforeAccepted + 1 &&
              document.findNote(notes.front().noteId, &acceptedNote) &&
              acceptedNote.velocity == 96 && !view.previewVelocity(notes.front().noteId),
          "matching SongView velocity gesture should commit exactly once and clear its preview");

    if (!notes.empty()) {
        view.selectionModel().setNoteSelection({notes.front().noteId});
        live.documentRevision = document.revision();
        live.playback.playing = false;
        velocity->refreshLiveState(live);
        const QPointF node(velocity->plotOrigin() + double(acceptedNote.tick) * live.timeZoom /
                                                        double(timeline->ticksPerBeat),
                           velocity->axis().velocityToY(acceptedNote.velocity));
        const uint64_t beforePageSwitch = document.revision();
        const int undoBeforePageSwitch = document.undoStack()->count();
        const std::vector<NoteId> selectionBeforePageSwitch = view.selectionModel().noteSelection();
        sendMouse(*velocity, QEvent::MouseButtonPress, node, Qt::LeftButton, Qt::LeftButton);
        sendMouse(*velocity, QEvent::MouseMove, node + QPointF(0.0, -40.0), Qt::NoButton,
                  Qt::LeftButton);
        const auto pageSwitchPreview = view.previewVelocity(notes.front().noteId);
        check(pageSwitchPreview && document.revision() == beforePageSwitch &&
                  document.undoStack()->count() == undoBeforePageSwitch,
              "drawer page replacement should begin with a staged preview and unchanged history");
        view.setDrawerActivePage(EditorDrawerPage::Automations);
        sendMouse(*velocity, QEvent::MouseButtonRelease, node + QPointF(0.0, -40.0),
                  Qt::LeftButton);
        check(document.revision() == beforePageSwitch &&
                  document.undoStack()->count() == undoBeforePageSwitch &&
                  !view.previewVelocity(notes.front().noteId) &&
                  view.selectionModel().noteSelection() == selectionBeforePageSwitch,
              "drawer page replacement must cancel the concrete velocity preview first");

        view.setDrawerActivePage(EditorDrawerPage::Velocity);
        velocity->refreshLiveState(live);
        const uint64_t beforeDocumentSwap = document.revision();
        const int undoBeforeDocumentSwap = document.undoStack()->count();
        const std::vector<NoteId> selectionBeforeDocumentSwap =
            view.selectionModel().noteSelection();
        sendMouse(*velocity, QEvent::MouseButtonPress, node, Qt::LeftButton, Qt::LeftButton);
        sendMouse(*velocity, QEvent::MouseMove, node + QPointF(0.0, -40.0), Qt::NoButton,
                  Qt::LeftButton);
        const auto documentSwapPreview = view.previewVelocity(notes.front().noteId);
        check(!selectionBeforeDocumentSwap.empty() && documentSwapPreview &&
                  document.revision() == beforeDocumentSwap &&
                  document.undoStack()->count() == undoBeforeDocumentSwap,
              "document replacement should begin with a staged preview and unchanged history");
        view.setDocument(nullptr);
        sendMouse(*velocity, QEvent::MouseButtonRelease, node + QPointF(0.0, -40.0),
                  Qt::LeftButton);
        check(document.revision() == beforeDocumentSwap &&
                  document.undoStack()->count() == undoBeforeDocumentSwap &&
                  !view.previewVelocity(notes.front().noteId) &&
                  view.selectionModel().noteSelection().empty(),
              "document replacement must cancel the concrete velocity preview first");
        view.setDocument(&document);
        view.updateSong(timeline.get());
    }

    const auto cosmeticsBeforeChange = view.editorViewState();
    automation->documentChanged();
    velocity->documentChanged();
    check(view.editorViewState() == cosmeticsBeforeChange,
          "document refresh must preserve concrete drawer cosmetics");
    view.cancelActiveInteractions();
    view.hide();
    return failures == 0 ? 0 : 1;
}
