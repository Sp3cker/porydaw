#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/automationarea.h"
#include "ui/automationpage.h"
#include "ui/editordrawer.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/velocityarea.h"

#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QFileInfo>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QScrollArea>
#include <QMenu>
#include <QScrollBar>
#include <QTemporaryDir>
#include <QTabBar>
#include <QWidget>
#include <QTimer>
#include <QImage>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>
#include <optional>
#include <vector>
#include <utility>

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
    QMouseEvent event(type, position, button, buttons, Qt::NoModifier);
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
    const double x = double(area.plotOrigin()) + double(note.tick) * view.pxPerBeat()
        / double(timeline.ticksPerBeat) - view.viewState().scrollPx;
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

    QTemporaryDir temporary;
    QString error;
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack primary;
    primary.events = {
        noteEvent(0xC0, 0, 0, 0),
        noteEvent(0x90, 12, 60, 20),
        noteEvent(0x90, 12, 60, 70),
        noteEvent(0xC0, 24, 1, 0),
        noteEvent(0x80, 36, 60, 0),
        noteEvent(0x80, 36, 60, 0),
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

    EditorViewState sidecar;
    sidecar.drawerVisible = true;
    sidecar.drawerPage = EditorDrawerPage::Velocity;
    sidecar.drawerHeight = 180;
    sidecar.laneHeight = 42;
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, 0, 74};
    sidecar.emptyLanes.insert(lane);
    sidecar.laneRanges.emplace(lane, 96);
    view.applyEditorViewState(sidecar);
    QCoreApplication::processEvents();
    check(view.editorViewState() == sidecar && view.drawerPage() == EditorDrawerPage::Velocity
              && view.drawerVisible(),
          "drawer sidecar state should attach without becoming document state");
    const uint64_t revisionBeforeSidecarCapture = document.revision();
    const int undoBeforeSidecarCapture = document.undoStack()->count();
    const SongView::ViewState capturedView = view.viewState();
    const EditorViewState capturedEditor = view.editorViewState();
    check(capturedView.valid && capturedEditor.emptyLanes.size() == 1
              && capturedEditor.emptyLanes.count(lane) == 1
              && document.revision() == revisionBeforeSidecarCapture
              && document.undoStack()->count() == undoBeforeSidecarCapture,
          "detached view-state capture should preserve the sidecar without saving document state");
    check(drawerContextTick(-1.0) == 0
              && drawerContextTick(0.49) == 0
              && drawerContextTick(0.5) == 1
              && drawerContextTick(0.51) == 1,
          "drawer tick should use the neutral shared conversion");

    auto *drawer = editorDrawer(view);
    check(drawer && drawer->isVisible(), "drawer should remain visible above other events");
    auto *otherStrip = view.findChild<QWidget *>(QStringLiteral("otherEventsStrip"));
    auto *tabs = drawer ? drawer->findChild<QTabBar *>(QStringLiteral("editorDrawerTabs")) : nullptr;
    auto *pages = drawer ? drawer->findChild<QWidget *>(QStringLiteral("editorDrawerPages")) : nullptr;
    auto *handle = drawer ? drawer->findChild<QWidget *>(QStringLiteral("editorDrawerResizeHandle"))
                          : nullptr;
    check(otherStrip && otherStrip->isVisible(), "other events strip should remain visible");
    check(tabs && pages && handle, "drawer should create tabs, a top resize handle, and a page stack");
    if (drawer && otherStrip && tabs && pages && handle) {
        const QRect drawerBounds(drawer->mapTo(&view, QPoint()), drawer->size());
        const QRect handleBounds(handle->mapTo(drawer, QPoint()), handle->size());
        const QRect tabsBounds(tabs->mapTo(drawer, QPoint()), tabs->size());
        const QRect pagesBounds(pages->mapTo(drawer, QPoint()), pages->size());
        check(drawerBounds.bottom() < otherStrip->geometry().top(),
              "drawer should stack above the other events strip");
        check(tabs->count() == 2 && tabs->tabText(0) == QStringLiteral("Automations")
                  && tabs->tabText(1) == QStringLiteral("Velocity")
                  && tabs->tabToolTip(0) == QStringLiteral("Show or hide automation lanes (A)")
                  && tabs->tabToolTip(1) == QStringLiteral("Show or hide note velocities (V)")
                  && tabsBounds.left() == 0
                  && tabsBounds.top() == 0
                  && tabsBounds.width() == layout::editorGeometry().trackHeaderWidth
                  && handleBounds.left() == 0
                  && handleBounds.top() == tabsBounds.bottom() + 1
                  && handleBounds.width() == drawer->width()
                  && handleBounds.bottom() + 1 == pagesBounds.top(),
              "drawer tabs should attach to the page stack");
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
    view.setDrawerPage(EditorDrawerPage::Automations);
    QCoreApplication::processEvents();
    view.setDrawerPage(EditorDrawerPage::Velocity);
    auto *automation = automationArea(view);
    check(automation != nullptr, "host should construct the automation page");
    if (automation) {
        const int selectedTrack = view.selectedTrack();
        view.setTrackSolo(selectedTrack, false);
        sendKey(*area, Qt::Key_S);
        check(view.trackSoloed(selectedTrack),
              "S from the velocity drawer did not solo the selected track");
        view.setTrackSolo(selectedTrack, false);

        view.clearSelection();
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
        check(area->diagnostics().contentBuildCount == warmVelocity.contentBuildCount
                  && area->diagnostics().playheadPresentationCount
                         == warmVelocity.playheadPresentationCount + 2,
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
        check(QString::fromLatin1(area->axis().map().voiceName()) == QStringLiteral("Noise")
                  && area->diagnostics().contentBuildCount
                         > velocityBeforeCrossing.contentBuildCount,
              "visible velocity map should refresh when playback crosses a voice change");

        view.setPlayheadSample(timeline->sampleForTick(24), false);
        view.setDrawerPage(EditorDrawerPage::Automations);
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
        check(automation->grab().toImage() != squarePlaybackContext
                  && automation->diagnostics().contentInvalidationCount
                         > automationBeforeCrossing.contentInvalidationCount,
              "visible automation context should refresh when playback crosses a voice change");
        view.setPlayheadSample(timeline->sampleForTick(24), false);
        QCoreApplication::processEvents();
        const QPointF menuStart(layout::editorGeometry().plotOrigin + 4.0, 4.0);
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
        const SongView::TimeSelection &menuSelection = view.timeSelection();
        check(menuSelection.active() && menuSelection.scope == SongView::TimeSelection::Lanes
                  && menuSelection.lanes.size() == 1 && menuSelection.lanes.front().first == -1
                  && menuSelection.lanes.front().second == DOC_CC_TEMPO,
              "automation range menu should delegate its lane scope to the host");
        view.clearTimeSelection();
    }

    check(document.moveTrack(0, 1), "fixture track move should succeed");
    const EditorAutomationRowId movedLane{EditorAutomationRowKind::ControlChange, 1, 74};
    check(view.editorViewState().emptyLanes.count(movedLane) == 1,
          "track remap should reach hosted cosmetics before document refresh");
    std::unique_ptr<MidiTimeline> remappedTimeline = document.buildTimeline(44100.0);
    view.updateSong(remappedTimeline.get());
    timeline = std::move(remappedTimeline);

    std::vector<DocNote> notes = document.notesForTrack(view.selectedTrack());
    check(notes.size() == 2, "remapped selected track should retain duplicate-note identities");
    if (notes.size() != 2)
        return 1;

    view.setDrawerPage(EditorDrawerPage::Velocity);
    view.setDrawerVisible(true);
    view.setDrawerHeight(200);
    view.setSelection({notes[0].noteId, notes[1].noteId});
    view.setEditCursorTick(1);
    QCoreApplication::processEvents();

    const QPointF firstNode = nodePosition(view, *area, *timeline, notes[0]);
    const std::vector<NoteId> selected = view.selection();
    std::vector<NoteVelocity> unchangedVelocities;
    unchangedVelocities.reserve(notes.size());
    for (const DocNote &note : notes)
        unchangedVelocities.push_back({note.noteId, note.velocity});
    const uint64_t revisionBeforeNoChange = document.revision();
    const int undoBeforeNoChange = document.undoStack()->count();
    const std::optional<uint64_t> noChange =
        view.applyVelocityMutation(revisionBeforeNoChange, unchangedVelocities);
    const std::vector<DocNote> notesAfterNoChange = document.notesForTrack(view.selectedTrack());
    check(noChange && *noChange == revisionBeforeNoChange
              && document.revision() == revisionBeforeNoChange
              && document.undoStack()->count() == undoBeforeNoChange
              && notesAfterNoChange.size() == notes.size()
              && notesAfterNoChange[0].velocity == notes[0].velocity
              && notesAfterNoChange[1].velocity == notes[1].velocity && view.selection() == selected,
          "host NoChange result should preserve revision, MIDI, Undo, and NoteId selection");
    const int undoBeforeChange = document.undoStack()->count();
    const uint64_t revisionBeforeChange = document.revision();
    sendMouse(*area, QEvent::MouseButtonPress, firstNode, Qt::LeftButton, Qt::LeftButton);
    sendMouse(*area, QEvent::MouseMove, firstNode + QPointF(0.0, -double(area->height())),
              Qt::NoButton, Qt::LeftButton);
    sendMouse(*area, QEvent::MouseButtonRelease,
              firstNode + QPointF(0.0, -double(area->height())), Qt::LeftButton);
    check(document.revision() == revisionBeforeChange + 1
              && document.undoStack()->count() == undoBeforeChange + 1
              && view.selection() == selected,
          "velocity host should commit one exact revisioned batch and preserve NoteId selection");

    document.undoStack()->undo();
    check(view.selection() == selected && document.undoStack()->count() == undoBeforeChange + 1,
          "undo should preserve shared selection while retaining the exact velocity history entry");
    document.undoStack()->redo();

    notes = document.notesForTrack(view.selectedTrack());
    view.setSelection({notes[0].noteId, notes[1].noteId});
    view.setEditCursorTick(2);
    QCoreApplication::processEvents();
    const QPointF unchangedNode = nodePosition(view, *area, *timeline, notes[0]);
    const uint64_t revisionBeforeNoOp = document.revision();
    const int undoBeforeNoOp = document.undoStack()->count();
    sendMouse(*area, QEvent::MouseButtonPress, unchangedNode, Qt::LeftButton, Qt::LeftButton);
    sendMouse(*area, QEvent::MouseButtonRelease, unchangedNode, Qt::LeftButton);
    check(document.revision() == revisionBeforeNoOp && document.undoStack()->count() == undoBeforeNoOp
              && view.selection() == selected,
          "unchanged velocity gesture should leave revision, MIDI, Undo, and selection untouched");

    notes = document.notesForTrack(view.selectedTrack());
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
    sendMouse(*area, QEvent::MouseButtonRelease,
              staleNode + QPointF(0.0, -double(area->height())), Qt::LeftButton);
    const std::vector<DocNote> staleNotes = document.notesForTrack(view.selectedTrack());
    check(document.revision() == revisionBeforeExternalChange + 1 && staleNotes.size() == 2
              && staleNotes[1].velocity == secondVelocity && view.selection() == selected,
          "stale velocity batch should apply none of its frozen request and cancel its gesture");

    std::unique_ptr<MidiTimeline> staleTimeline = document.buildTimeline(44100.0);
    view.updateSong(staleTimeline.get());
    timeline = std::move(staleTimeline);
    notes = document.notesForTrack(view.selectedTrack());
    view.setSelection({notes[0].noteId});
    view.setEditCursorTick(4);
    QCoreApplication::processEvents();
    const QPointF lifecycleNode = nodePosition(view, *area, *timeline, notes[0]);
    const uint64_t revisionBeforeLifecycle = document.revision();
    sendMouse(*area, QEvent::MouseButtonPress, lifecycleNode, Qt::LeftButton, Qt::LeftButton);
    view.setDrawerPage(EditorDrawerPage::Automations);
    sendMouse(*area, QEvent::MouseButtonRelease, lifecycleNode + QPointF(0.0, -40.0), Qt::LeftButton);
    check(document.revision() == revisionBeforeLifecycle,
          "drawer page switch should terminate the visible page gesture");

    view.setDrawerPage(EditorDrawerPage::Velocity);
    view.setEditCursorTick(5);
    QCoreApplication::processEvents();
    sendMouse(*area, QEvent::MouseButtonPress, lifecycleNode, Qt::LeftButton, Qt::LeftButton);
    QKeyEvent escape(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
    QApplication::sendEvent(&view, &escape);
    sendMouse(*area, QEvent::MouseButtonRelease, lifecycleNode + QPointF(0.0, -40.0), Qt::LeftButton);
    check(document.revision() == revisionBeforeLifecycle,
          "Escape should terminate the visible page gesture through the host lifecycle");

    const auto cancelGesture = [&](auto cancel, const char *message) {
        const uint64_t revision = document.revision();
        sendMouse(*area, QEvent::MouseButtonPress, lifecycleNode, Qt::LeftButton, Qt::LeftButton);
        cancel();
        sendMouse(*area, QEvent::MouseButtonRelease, lifecycleNode + QPointF(0.0, -40.0),
                  Qt::LeftButton);
        check(document.revision() == revision, message);
    };
    cancelGesture([&] { view.setDrawerVisible(false); },
                  "drawer close should terminate the visible page gesture");
    view.setDrawerVisible(true);
    view.setDrawerPage(EditorDrawerPage::Velocity);
    cancelGesture(
        [&] {
            QEvent ungrab(QEvent::UngrabMouse);
            QApplication::sendEvent(&view, &ungrab);
        },
        "mouse-grab loss should terminate the visible page gesture");
    cancelGesture(
        [&] {
            QEvent deactivate(QEvent::WindowDeactivate);
            QApplication::sendEvent(&view, &deactivate);
        },
        "window deactivation should terminate the visible page gesture");

    cancelGesture([&] { view.selectTrack(0); },
                  "selected-track replacement should terminate the visible page gesture");
    view.selectTrack(1);
    notes = document.notesForTrack(view.selectedTrack());
    view.setSelection({notes[0].noteId});
    view.setEditCursorTick(6);
    QCoreApplication::processEvents();

    LoadedVoiceGroup replacementVoicegroup{};
    const QPointF replacementNode = nodePosition(view, *area, *timeline, notes[0]);
    const auto cancelReplacementGesture = [&](auto cancel, const char *message) {
        const uint64_t revision = document.revision();
        sendMouse(*area, QEvent::MouseButtonPress, replacementNode, Qt::LeftButton, Qt::LeftButton);
        cancel();
        sendMouse(*area, QEvent::MouseButtonRelease, replacementNode + QPointF(0.0, -40.0),
                  Qt::LeftButton);
        check(document.revision() == revision, message);
    };
    cancelReplacementGesture([&] { view.setVoicegroup(&replacementVoicegroup); },
                             "voice replacement should terminate the visible page gesture");
    view.setVoicegroup(nullptr);
    cancelReplacementGesture([&] { view.setSong(timeline.get(), nullptr); },
                             "song replacement should terminate the visible page gesture");
    view.selectTrack(1);
    notes = document.notesForTrack(view.selectedTrack());
    view.setSelection({notes[0].noteId});
    view.setEditCursorTick(7);
    QCoreApplication::processEvents();

    const QPointF documentNode = nodePosition(view, *area, *timeline, notes[0]);
    const uint64_t revisionBeforeDocumentReplacement = document.revision();
    sendMouse(*area, QEvent::MouseButtonPress, documentNode, Qt::LeftButton, Qt::LeftButton);
    view.setDocument(nullptr);
    sendMouse(*area, QEvent::MouseButtonRelease, documentNode + QPointF(0.0, -40.0),
              Qt::LeftButton);
    check(document.revision() == revisionBeforeDocumentReplacement,
          "document replacement should terminate the visible page gesture");
    view.setDocument(&document);
    view.setSelection({notes[0].noteId});
    view.setEditCursorTick(8);
    QCoreApplication::processEvents();

    const int replacementVelocity = notes[0].velocity == 127 ? 1 : 127;
    const uint64_t revisionBeforeMutation = document.revision();
    sendMouse(*area, QEvent::MouseButtonPress, documentNode, Qt::LeftButton, Qt::LeftButton);
    document.setNotesVelocity({notes[0]}, uint8_t(replacementVelocity));
    sendMouse(*area, QEvent::MouseButtonRelease, documentNode + QPointF(0.0, -40.0),
              Qt::LeftButton);
    check(document.revision() == revisionBeforeMutation + 1,
          "document mutation should terminate the visible page gesture");

    const uint64_t revisionBeforeUndo = document.revision();
    sendMouse(*area, QEvent::MouseButtonPress, documentNode, Qt::LeftButton, Qt::LeftButton);
    document.undoStack()->undo();
    sendMouse(*area, QEvent::MouseButtonRelease, documentNode + QPointF(0.0, -40.0),
              Qt::LeftButton);
    check(document.revision() == revisionBeforeUndo + 1,
          "Undo should terminate the visible page gesture");
    const uint64_t revisionBeforeRedo = document.revision();
    sendMouse(*area, QEvent::MouseButtonPress, documentNode, Qt::LeftButton, Qt::LeftButton);
    document.undoStack()->redo();
    sendMouse(*area, QEvent::MouseButtonRelease, documentNode + QPointF(0.0, -40.0),
              Qt::LeftButton);
    check(document.revision() == revisionBeforeRedo + 1,
          "Redo should terminate the visible page gesture");

    sendMouse(*area, QEvent::MouseButtonPress, documentNode, Qt::LeftButton, Qt::LeftButton);
    const bool reloaded = document.load(song, &error);
    sendMouse(*area, QEvent::MouseButtonRelease, documentNode + QPointF(0.0, -40.0),
              Qt::LeftButton);
    check(reloaded, "reload should terminate the visible page gesture");
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
    check(state.drawerVisible && state.drawerPage == EditorDrawerPage::Automations
              && state.drawerHeight == 0 && state.laneHeight == 0
              && state.laneHeights.empty() && state.laneRanges.empty()
              && state.emptyLanes.empty() && state.hiddenLanes().empty(),
          "new songs default to an open Automations drawer with cosmetic lane state");
    const auto controllerRow =
        EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 2, 1};
    auto changedState = state;
    changedState.drawerVisible = false;
    changedState.drawerPage = EditorDrawerPage::Velocity;
    changedState.drawerHeight = 144;
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
    check(temporary.isValid() && smf.writeFile(song.midPath, &error)
              && document.load(song, &error),
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
    check(drawer && automation && velocity,
          "SongView must own both concrete drawer pages");
    if (!drawer || !automation || !velocity)
        return 1;

    view.applyEditorViewState(changedState);
    check(view.editorViewState() == changedState
              && view.drawerPage() == EditorDrawerPage::Velocity
              && !view.drawerVisible(),
          "typed drawer state should attach through SongView without document mutation");
    view.setDrawerPage(EditorDrawerPage::Velocity);
    view.setDrawerVisible(true);
    view.setDrawerHeight(280);
    view.show();
    QCoreApplication::processEvents();

    view.setEditorHorizontalScroll(96.0);
    view.setEditorTimeZoom(1.75 * layout::editorGeometry().editorDefaultPixelsPerBeat);
    view.setFollowScrollPaused(true);
    view.focusContent();
    view.announce(QStringLiteral("editor-state"));
    view.showEditorNoteStatus(EditorPageNoteStatus{60, 64, 64, 24, 12});
    view.showEditorNoteStatus(std::nullopt);
    view.requestEditorUndo();
    view.requestEditorRedo();
    const auto runtime = view.viewState();
    check(runtime.valid && runtime.scrollPx == 96.0
              && runtime.pxPerBeat == 1.75 * layout::editorGeometry().editorDefaultPixelsPerBeat,
          "SongView editor endpoints should update runtime camera state");
    const auto grid = view.gridState(12, false);
    const auto voice = view.voiceContext(12);
    check(grid.gridTicks > 0 && grid.snapTicks > 0
              && voice.voice == &voicegroup.voices[0] && voice.voiceSlot == 0,
          "SongView should resolve grid and voice state at concrete page ticks");

    auto live = EditorPageLiveState{};
    live.documentRevision = document.revision();
    live.timeZoom = 48.0;
    live.horizontalScroll = 0.0;
    live.editCursorTick = 12;
    live.trackColor = QColor{10, 20, 30};
    live.playback = {12.0, true};
    automation->refreshLiveState(live);
    velocity->refreshLiveState(live);
    check(!automation->area()->rows().empty()
              && velocity->axis().mode() == VelocityAxis::Mode::Intrinsic,
          "concrete pages should refresh live state through their SongView owner");

    const auto notes = document.notesForTrack(0);
    check(notes.size() == 1, "concrete fixture should retain its note identity");
    if (notes.empty())
        return 1;
    view.setSelection({notes.front().noteId});
    const std::vector<NoteVelocity> velocities{{notes.front().noteId, 96}};
    const uint64_t revision = document.revision();
    check(!view.applyVelocityMutation(revision + 1, velocities).has_value(),
          "stale velocity revision must be rejected by the concrete SongView endpoint");
    const auto accepted = view.applyVelocityMutation(revision, velocities);
    check(accepted.has_value() && *accepted == revision + 1,
          "matching velocity revision must commit through SongView");
    view.updateSong(timeline.get());

    if (!notes.empty()) {
        view.setSelection({notes.front().noteId});
        live.documentRevision = document.revision();
        live.playback.playing = false;
        velocity->refreshLiveState(live);
        const QPointF node(
            velocity->plotOrigin()
                + double(notes.front().tick) * live.timeZoom / double(timeline->ticksPerBeat),
            velocity->axis().velocityToY(notes.front().velocity));
        const uint64_t beforePageSwitch = document.revision();
        sendMouse(*velocity, QEvent::MouseButtonPress, node, Qt::LeftButton, Qt::LeftButton);
        sendMouse(*velocity, QEvent::MouseMove, node + QPointF(0.0, -40.0),
                  Qt::NoButton, Qt::LeftButton);
        view.setDrawerPage(EditorDrawerPage::Automations);
        sendMouse(*velocity, QEvent::MouseButtonRelease,
                  node + QPointF(0.0, -40.0), Qt::LeftButton);
        check(document.revision() == beforePageSwitch,
              "drawer page replacement must cancel the concrete velocity gesture first");

        view.setDrawerPage(EditorDrawerPage::Velocity);
        velocity->refreshLiveState(live);
        const uint64_t beforeDocumentSwap = document.revision();
        sendMouse(*velocity, QEvent::MouseButtonPress, node, Qt::LeftButton, Qt::LeftButton);
        view.setDocument(nullptr);
        sendMouse(*velocity, QEvent::MouseButtonRelease,
                  node + QPointF(0.0, -40.0), Qt::LeftButton);
        check(document.revision() == beforeDocumentSwap,
              "document replacement must cancel the concrete velocity gesture first");
        view.setDocument(&document);
        view.updateSong(timeline.get());
    }

    const auto cosmeticsBeforeChange = view.editorViewState();
    automation->documentChanged();
    velocity->documentChanged();
    check(view.editorViewState() == cosmeticsBeforeChange,
          "document refresh must preserve concrete drawer cosmetics");
    view.cancelVisiblePageInteraction();
    view.hide();
    return failures == 0 ? 0 : 1;
}
