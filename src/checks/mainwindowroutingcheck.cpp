#include <algorithm>
#include <cstdint>
#include <optional>
#include <vector>

#include "core/miditimeline.h"
#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QKeySequence>
#include <QMouseEvent>
#include <QPixmap>
#include <QScrollArea>
#include <QScrollBar>
#include <QSettings>
#include <QStatusBar>
#include <QTabWidget>
#include <QTemporaryDir>
#include <QUndoStack>
#include <QWidget>
#include <cstdio>

#include "core/smf.h"
#include "mainwindow.h"
#include "project/sidecar.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/viewsidecar.h"

namespace {

QByteArray fileContents(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
}

template <class T>
T *descendant(QWidget &owner)
{
    for (QWidget *widget : owner.findChildren<QWidget *>()) {
        if (auto *typed = dynamic_cast<T *>(widget))
            return typed;
    }
    return nullptr;
}

void sendUnmodifiedKey(QWidget &window, Qt::Key key)
{
    QKeyEvent press(QEvent::KeyPress, key, Qt::NoModifier);
    QApplication::sendEvent(&window, &press);
    QKeyEvent release(QEvent::KeyRelease, key, Qt::NoModifier);
    QApplication::sendEvent(&window, &release);
}

void sendMouse(QWidget &widget, QEvent::Type type, const QPointF &position, Qt::MouseButton button,
               Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
    QMouseEvent event(type, position, QPointF(widget.mapToGlobal(position.toPoint())), button,
                      buttons, modifiers);
    QApplication::sendEvent(&widget, &event);
}

QPointF velocityNodePosition(const SongView &view, const VelocityArea &area,
                             const MidiTimeline &timeline, const DocNote &note)
{
    const double x = double(area.plotOrigin()) +
                     double(note.tick) * view.pxPerBeat() / double(timeline.ticksPerBeat) -
                     view.viewState().scrollPx;
    return {x, area.axis().velocityToY(note.velocity)};
}

} // namespace

bool MainWindow::runMainWindowRoutingCheck(const QString &projectRoot, const QString &songA,
                                           const QString &songB)
{
    if (!m_audioOk) {
        std::fprintf(stderr, "mainwindow-routing: no audio device available\n");
        return false;
    }
    if (!openProjectDir(projectRoot, /*interactive=*/false)) {
        std::fprintf(stderr, "mainwindow-routing: project failed to open\n");
        return false;
    }

    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "mainwindow-routing: FAIL: %s\n", message);
            ++failures;
        }
    };

    resize(960, 640);
    show();
    QCoreApplication::processEvents();
    loadSongByLabel(songA);
    SongSession *tabA = m_active;
    loadSongByLabel(songB, /*newTab=*/true);
    SongSession *tabB = m_active;
    if (!tabA || !tabB || tabA == tabB || m_tabs->count() != 2) {
        std::fprintf(stderr, "mainwindow-routing: songs did not open in two tabs\n");
        return false;
    }

    check(m_automationDrawerAction->shortcut() == QKeySequence(Qt::Key_A) &&
              m_automationDrawerAction->shortcutContext() == Qt::WindowShortcut &&
              m_automationDrawerAction->toolTip() ==
                  QStringLiteral("Show or hide automation lanes (A)"),
          "automation route is not the required WindowShortcut action");
    check(m_velocityDrawerAction->shortcut() == QKeySequence(Qt::Key_V) &&
              m_velocityDrawerAction->shortcutContext() == Qt::WindowShortcut &&
              m_velocityDrawerAction->toolTip() ==
                  QStringLiteral("Show or hide note velocities (V)"),
          "velocity route is not the required WindowShortcut action");
    check(tabA->view->drawerSectionVisible(EditorDrawerPage::Velocity) &&
              !tabA->view->drawerSectionVisible(EditorDrawerPage::Automations) &&
              tabA->view->drawerActivePage() == EditorDrawerPage::Velocity &&
              tabA->view->drawerSectionHeight(EditorDrawerPage::Velocity) == 173 &&
              tabB->view->editorViewState().drawerState() ==
                  tabA->view->editorViewState().drawerState(),
          "new tabs did not restore application-wide drawer settings");

    tabA->view->setDrawerSectionVisible(EditorDrawerPage::Automations, false);
    tabA->view->setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    check(!tabB->view->hasVisibleDrawerSection(),
          "drawer visibility did not propagate to the other open tab");

    tabB->view->focusContent();
    sendUnmodifiedKey(*this, Qt::Key_A);
    check(tabB->view->drawerSectionVisible(EditorDrawerPage::Automations) &&
              tabB->view->drawerActivePage() == EditorDrawerPage::Automations &&
              tabA->view->drawerSectionVisible(EditorDrawerPage::Automations) &&
              tabA->view->drawerActivePage() == EditorDrawerPage::Automations &&
              statusBar()->currentMessage() == QStringLiteral("Automation lanes shown"),
          "automation route did not update application-wide drawer chrome");
    sendUnmodifiedKey(*this, Qt::Key_A);
    check(!tabB->view->drawerSectionVisible(EditorDrawerPage::Automations) &&
              !tabA->view->drawerSectionVisible(EditorDrawerPage::Automations) &&
              statusBar()->currentMessage() == QStringLiteral("Automation lanes hidden"),
          "automation route did not globally close the drawer");
    sendUnmodifiedKey(*this, Qt::Key_V);
    QCoreApplication::processEvents();
    check(tabB->view->drawerSectionVisible(EditorDrawerPage::Velocity) &&
              tabB->view->drawerActivePage() == EditorDrawerPage::Velocity &&
              tabA->view->drawerSectionVisible(EditorDrawerPage::Velocity) &&
              tabA->view->drawerActivePage() == EditorDrawerPage::Velocity &&
              statusBar()->currentMessage() == QStringLiteral("Velocity lane shown"),
          "velocity route did not update application-wide drawer chrome");
    sendUnmodifiedKey(*this, Qt::Key_V);
    QCoreApplication::processEvents();
    QWidget *focusAfterClose = QApplication::focusWidget();
    check(focusAfterClose &&
              (focusAfterClose == tabB->view || tabB->view->isAncestorOf(focusAfterClose)),
          "closing a focus-owned drawer did not return focus to active content");

    auto *automationSurface = descendant<AutomationCanvas>(*tabB->view);
    auto *velocitySurface = descendant<VelocityArea>(*tabB->view);
    check(automationSurface && velocitySurface,
          "drawer shortcut focus check could not find both editor surfaces");
    if (automationSurface && velocitySurface) {
        tabB->view->setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        tabB->view->setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        tabB->view->setDrawerActivePage(EditorDrawerPage::Velocity);
        velocitySurface->setFocus(Qt::MouseFocusReason);
        QCoreApplication::processEvents();
        check(QApplication::focusWidget() == velocitySurface,
              "velocity surface did not accept focus for the drawer shortcut check");
        sendUnmodifiedKey(*velocitySurface, Qt::Key_V);
        QCoreApplication::processEvents();
        check(!tabB->view->drawerSectionVisible(EditorDrawerPage::Velocity) &&
                  tabB->view->drawerSectionVisible(EditorDrawerPage::Automations) &&
                  QApplication::focusWidget() == automationSurface,
              "closing focused velocity did not focus the remaining automation drawer");
        if (QWidget *focus = QApplication::focusWidget())
            sendUnmodifiedKey(*focus, Qt::Key_A);
        QCoreApplication::processEvents();
        QWidget *focusAfterFocusedClose = QApplication::focusWidget();
        check(!tabB->view->hasVisibleDrawerSection() && focusAfterFocusedClose &&
                  (focusAfterFocusedClose == tabB->view ||
                   tabB->view->isAncestorOf(focusAfterFocusedClose)),
              "closing focused automation did not return focus to active content");
    }

    tabB->view->setDrawerActivePage(EditorDrawerPage::Velocity);
    tabB->view->setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
    const int retainedHeight = tabB->view->drawerSectionHeight(EditorDrawerPage::Velocity);
    tabB->view->setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    check(tabB->view->drawerActivePage() == EditorDrawerPage::Velocity &&
              tabB->view->drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight &&
              tabA->view->drawerActivePage() == EditorDrawerPage::Velocity &&
              tabA->view->drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight,
          "drawer hide did not retain globally shared page and height");
    m_tabs->setCurrentWidget(tabA->view);
    m_tabs->setCurrentWidget(tabB->view);
    QCoreApplication::processEvents();
    QWidget *focusAfterTabSwitch = QApplication::focusWidget();
    check(
        focusAfterTabSwitch &&
            (focusAfterTabSwitch == tabB->view || tabB->view->isAncestorOf(focusAfterTabSwitch)) &&
            focusAfterTabSwitch->focusPolicy() != Qt::NoFocus,
        "tab switch did not request active content focus");
    check(m_active == tabB && tabB->view->drawerActivePage() == EditorDrawerPage::Velocity &&
              tabB->view->drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight &&
              tabA->view->drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight,
          "application-wide drawer state did not survive a tab switch");

    tabB->view->setEventListVisible(true);
    QCoreApplication::processEvents();
    const bool blockedVelocityVisible =
        tabB->view->drawerSectionVisible(EditorDrawerPage::Velocity);
    const EditorDrawerPage blockedPage = tabB->view->drawerActivePage();
    const QString blockedStatus = statusBar()->currentMessage();
    check(!m_automationDrawerAction->isEnabled() && !m_velocityDrawerAction->isEnabled(),
          "event-list mode did not disable drawer routes");
    sendUnmodifiedKey(*this, Qt::Key_V);
    check(tabB->view->drawerSectionVisible(EditorDrawerPage::Velocity) == blockedVelocityVisible &&
              tabB->view->drawerActivePage() == blockedPage &&
              statusBar()->currentMessage() == blockedStatus,
          "event-list mode let a drawer route change or announce");
    tabB->view->setEventListVisible(false);
    QCoreApplication::processEvents();
    check(m_automationDrawerAction->isEnabled() && m_velocityDrawerAction->isEnabled(),
          "leaving event-list mode did not re-enable drawer routes");

    const EditorAutomationRowId persistedLane{EditorAutomationRowKind::ControlChange, 0, 74};
    EditorViewState drawerCosmetics = tabB->view->editorViewState();
    drawerCosmetics.laneHeight = 53;
    drawerCosmetics.laneHeights[persistedLane] = 61;
    drawerCosmetics.laneRanges[persistedLane] = 100;
    drawerCosmetics.emptyLanes.insert(persistedLane);
    tabB->view->applyEditorViewState(drawerCosmetics);
    const auto sameLaneState = [](const EditorViewState &first, const EditorViewState &second) {
        return first.laneHeight == second.laneHeight && first.laneHeights == second.laneHeights &&
               first.laneRanges == second.laneRanges && first.emptyLanes == second.emptyLanes &&
               first.hiddenLanes() == second.hiddenLanes();
    };

    const QByteArray sidecarBefore = fileContents(ViewSidecar::pathFor(projectRoot, songB));
    const QByteArray midiBefore = tabB->doc.smf().write();
    const uint64_t revisionBefore = tabB->doc.revision();
    const int undoBefore = tabB->doc.undoStack()->count();
    tabB->view->setDrawerActivePage(EditorDrawerPage::Velocity);
    tabB->view->setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    tabB->view->setDrawerSectionHeight(EditorDrawerPage::Velocity, retainedHeight);
    QCoreApplication::processEvents();
    const EditorViewState expectedCosmetics = tabB->view->editorViewState();
    check(tabB->doc.smf().write() == midiBefore && tabB->doc.revision() == revisionBefore &&
              tabB->doc.undoStack()->count() == undoBefore &&
              fileContents(ViewSidecar::pathFor(projectRoot, songB)) == sidecarBefore,
          "view-only drawer state changed MIDI, Undo, or persisted outside a boundary");

    QSettings drawerSettings;
    check(drawerSettings.value(QStringLiteral("editorDrawer/velocityVisible")).toBool() &&
              !drawerSettings.value(QStringLiteral("editorDrawer/automationVisible")).toBool() &&
              drawerSettings.value(QStringLiteral("editorDrawer/velocityHeight")).toInt() ==
                  retainedHeight &&
              drawerSettings.value(QStringLiteral("editorDrawer/activePage")).toString() ==
                  QStringLiteral("velocity"),
          "drawer chrome was not written to application settings");

    closeTab(m_tabs->indexOf(tabB->view));
    ViewSidecar::Snapshot savedSnapshot;
    check(ViewSidecar::load(projectRoot, songB, &savedSnapshot) && savedSnapshot.view.valid &&
              savedSnapshot.editor.drawerState() == EditorDrawerState{} &&
              sameLaneState(savedSnapshot.editor, expectedCosmetics),
          "tab close did not persist only song-specific lane state");
    loadSongByLabel(songB, true);
    SongSession *reopened = sessionForLabel(songB);
    check(reopened && reopened->view->drawerSectionVisible(EditorDrawerPage::Velocity) &&
              reopened->view->drawerActivePage() == EditorDrawerPage::Velocity &&
              reopened->view->drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight &&
              reopened->view->editorViewState().drawerState() == m_editorDrawerState &&
              sameLaneState(reopened->view->editorViewState(), expectedCosmetics),
          "reopened song did not combine global drawer chrome with its lane state");
    if (reopened) {
        int documentChangedCount = 0;
        QObject::connect(&reopened->doc, &SongDocument::documentChanged,
                         [&documentChangedCount] { ++documentChangedCount; });
        const SongCfg expectedCfg = reopened->doc.cfg();
        const auto expectedEventCount =
            reopened->timeline ? reopened->timeline->events.size() : size_t{0};
        const auto expectedLengthSamples =
            reopened->timeline ? reopened->timeline->lengthSamples : uint64_t{0};
        const int beforeLoad = documentChangedCount;
        loadSongByLabel(songB);
        check(documentChangedCount == beforeLoad && m_active == reopened &&
                  reopened->doc.label() == songB &&
                  reopened->doc.cfg().voicegroupArg == expectedCfg.voicegroupArg &&
                  reopened->doc.cfg().masterVolume == expectedCfg.masterVolume &&
                  reopened->doc.cfg().reverb == expectedCfg.reverb &&
                  reopened->appliedVoicegroupArg == expectedCfg.voicegroupArg &&
                  reopened->appliedVolume == expectedCfg.masterVolume &&
                  reopened->appliedReverb == expectedCfg.reverb && reopened->timeline &&
                  reopened->timeline->events.size() == expectedEventCount &&
                  reopened->timeline->lengthSamples == expectedLengthSamples &&
                  reopened->voicegroup && m_audio.songLoaded() &&
                  m_audio.timeline() == reopened->timeline.get() &&
                  m_audio.voicegroup() == reopened->voicegroup,
              "in-place song load published a document edit or lost its final session/audio state");
        const int beforeEdit = documentChangedCount;
        SongCfg editedCfg = reopened->doc.cfg();
        editedCfg.priority++;
        reopened->doc.setCfg(editedCfg);
        check(documentChangedCount == beforeEdit + 1,
              "genuine document edit did not emit documentChanged");
        reopened->doc.undoStack()->undo();
        check(documentChangedCount == beforeEdit + 2 &&
                  reopened->doc.cfg().priority == expectedCfg.priority,
              "undo after genuine document edit did not emit documentChanged or restore config");
    }

    hide();
    std::printf("mainwindow-routing: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0;
}

int runMainWindowRoutingCheck(const QString &projectRoot, const QString &songA,
                              const QString &songB)
{
    QTemporaryDir settingsDir;
    if (!settingsDir.isValid()) {
        std::fprintf(stderr, "mainwindow-routing: no temporary settings directory\n");
        return 1;
    }
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, settingsDir.path());
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDir.path());
    {
        QSettings settings;
        settings.setValue(QStringLiteral("editorDrawer/velocityVisible"), true);
        settings.setValue(QStringLiteral("editorDrawer/velocityHeight"), 173);
        settings.setValue(QStringLiteral("editorDrawer/automationVisible"), false);
        settings.setValue(QStringLiteral("editorDrawer/activePage"), QStringLiteral("velocity"));
    }

    MainWindow window;
    return window.runMainWindowRoutingCheck(projectRoot, songA, songB) ? 0 : 1;
}

int runHostIntegrationCheck(const QString &scratchProject, const QString &songA,
                            const QString &songB, const QString &screenshotPath)
{
    QTemporaryDir settingsDir;
    if (!settingsDir.isValid()) {
        std::fprintf(stderr, "host-integration: no temporary settings directory\n");
        return 1;
    }
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, settingsDir.path());
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDir.path());

    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "host-integration: FAIL %s\n", message);
            ++failures;
        }
    };
    MainWindow window;
    check(window.m_audioOk, "no audio device available");
    check(window.openProjectDir(scratchProject, /*interactive=*/false), "project failed to open");
    if (failures) {
        window.hide();
        return 1;
    }
    window.resize(960, 680);
    window.show();
    QCoreApplication::processEvents();
    window.loadSongByLabel(songA);
    window.loadSongByLabel(songB, /*newTab=*/true);
    SongSession *session = window.m_active;
    SongView *view = session ? session->view : nullptr;
    SongDocument *document = view ? view->document() : nullptr;
    check(view && document && session->timeline,
          "MainWindow flow did not leave an attached SongView and timeline");
    if (view && document && session->timeline) {
        auto noteTrack = -1;
        auto notes = std::vector<DocNote>{};
        for (auto track = 0; track < int(document->smf().tracks.size()); ++track) {
            const auto candidate = document->notesForTrack(track);
            if (candidate.size() >= 2) {
                noteTrack = track;
                notes = candidate;
                break;
            }
        }
        check(noteTrack >= 0, "active song has no two-note velocity adapter fixture");
        if (noteTrack >= 0) {
            view->selectTrack(noteTrack);
            const std::vector<NoteId> selection{notes[0].noteId, notes[1].noteId};
            view->selectionModel().setNoteSelection(selection);
        }

        view->setDrawerActivePage(EditorDrawerPage::Velocity);
        view->setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        view->setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
        view->setDocument(nullptr);
        view->setDocument(document);
        view->setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
        view->setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        QCoreApplication::processEvents();
        auto *automation = descendant<AutomationCanvas>(*view);
        auto *velocity = descendant<VelocityArea>(*view);
        auto *drawer = descendant<EditorDrawer>(*view);
        check(automation && velocity && drawer,
              "host flow did not expose drawer and page diagnostics");
        if (automation && velocity && drawer) {
            view->setDrawerActivePage(EditorDrawerPage::Velocity);
            view->setFollowPlayhead(false);
            auto firstTick = uint64_t{0};
            auto finalTick = uint64_t{0};
            auto foundSteadySamples = false;
            for (uint64_t candidate = 0; candidate < 4096 && !foundSteadySamples; ++candidate) {
                const DrawerPageVoiceContext context = view->voiceContext(candidate);
                uint64_t previousSample = 0;
                auto steady = true;
                for (uint64_t offset = 0; offset <= 120; ++offset) {
                    const DrawerPageVoiceContext next = view->voiceContext(candidate + offset);
                    const uint64_t sample = session->timeline->sampleForTick(candidate + offset);
                    if (next.voice != context.voice || next.voiceSlot != context.voiceSlot ||
                        (offset > 0 && sample <= previousSample)) {
                        steady = false;
                        break;
                    }
                    previousSample = sample;
                }
                if (steady) {
                    firstTick = candidate;
                    finalTick = candidate + 120;
                    foundSteadySamples = true;
                }
            }
            check(foundSteadySamples, "timeline has no steady 120-sample playhead span");
            if (foundSteadySamples) {
                view->setPlayheadSample(session->timeline->sampleForTick(firstTick), true);
                QCoreApplication::processEvents();
                const auto automationBefore = automation->diagnostics();
                const auto velocityBefore = velocity->diagnostics();
                for (uint64_t tick = firstTick + 1; tick <= finalTick; ++tick)
                    view->setPlayheadSample(session->timeline->sampleForTick(tick), true);
                QCoreApplication::processEvents();
                check(uint64_t(view->playheadTick() + 0.5) == finalTick,
                      "SongView playhead did not reach the final tick");
                check(velocity->diagnostics().playheadPresentationCount ==
                          velocityBefore.playheadPresentationCount + 120,
                      "velocity page did not receive all distinct playhead samples");
                check(automation->diagnostics() == automationBefore &&
                          velocity->diagnostics().contentBuildCount ==
                              velocityBefore.contentBuildCount,
                      "steady SongView playhead ticks rebuilt hosted page content");
            }

            const auto editBefore = velocity->diagnostics();
            const auto liveNotes =
                noteTrack >= 0 ? document->notesForTrack(noteTrack) : std::vector<DocNote>{};
            if (!liveNotes.empty()) {
                const DocNote editNote = liveNotes.front();
                const uint8_t editedVelocity = editNote.velocity == 127 ? 1 : editNote.velocity + 1;
                const std::vector<NoteVelocity> edit{{editNote.noteId, editedVelocity}};
                const uint64_t editRevision = document->revision();
                const int editUndo = document->undoStack()->index();
                const bool beganEdit = view->beginVelocityGesture(liveNotes);
                const bool updatedEdit = view->updateVelocityGesture(edit);
                const auto editPreview = view->previewVelocity(editNote.noteId);
                check(beganEdit && updatedEdit && editPreview && *editPreview == editedVelocity &&
                          document->revision() == editRevision &&
                          document->undoStack()->index() == editUndo,
                      "document edit should stage velocity preview without mutating history");
                const auto commit = view->commitVelocityGesture();
                QCoreApplication::processEvents();
                const auto committedNotes = document->notesForTrack(noteTrack);
                const auto committedNote = std::find_if(
                    committedNotes.begin(), committedNotes.end(),
                    [&editNote](const DocNote &note) { return note.noteId == editNote.noteId; });
                check(commit == SongView::VelocityCommitResult::Committed &&
                          committedNote != committedNotes.end() &&
                          committedNote->velocity == editedVelocity &&
                          document->revision() == editRevision + 1 &&
                          document->undoStack()->index() == editUndo + 1 &&
                          !view->previewVelocity(editNote.noteId) &&
                          velocity->diagnostics().contentBuildCount > editBefore.contentBuildCount,
                      "document edit did not commit its exact velocity once or invalidate affected "
                      "velocity content");
                document->undoStack()->undo();
            } else {
                check(false, "velocity edit invalidation fixture is unavailable");
            }
            const auto selectionBefore = velocity->diagnostics();
            view->selectionModel().clearNoteSelection();
            QCoreApplication::processEvents();
            check(velocity->diagnostics().contentBuildCount > selectionBefore.contentBuildCount,
                  "selection change did not invalidate affected velocity content");
            const auto zoomBefore = velocity->diagnostics();
            view->zoomAroundContentX(1.1, qreal(view->width()) / 2.0);
            QCoreApplication::processEvents();
            check(velocity->diagnostics().contentBuildCount > zoomBefore.contentBuildCount,
                  "zoom did not invalidate affected velocity content");
            view->setDrawerActivePage(EditorDrawerPage::Automations);
            QCoreApplication::processEvents();
            const auto automationThemeBefore = automation->diagnostics();
            QEvent automationThemeChange(QEvent::PaletteChange);
            QApplication::sendEvent(automation, &automationThemeChange);
            QCoreApplication::processEvents();
            check(automation->diagnostics().contentInvalidationCount >
                      automationThemeBefore.contentInvalidationCount,
                  "theme change did not invalidate affected automation content");
            view->setDrawerActivePage(EditorDrawerPage::Velocity);

            if (noteTrack >= 0) {
                view->addEmptyLane(noteTrack, 74);
                EditorViewState automationCosmetics = view->editorViewState();
                automationCosmetics.laneHeight = layout::fontPx(4.0);
                view->applyEditorViewState(automationCosmetics);
                document->addLanePoint(noteTrack, 74, 0, 64);
                view->setDrawerActivePage(EditorDrawerPage::Automations);
                QCoreApplication::processEvents();
                const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange,
                                                 uint8_t(noteTrack), 74};
                const auto laneRow =
                    std::find_if(automation->rows().begin(), automation->rows().end(),
                                 [&lane](const AutomationRow &row) { return row.id == lane; });
                check(laneRow != automation->rows().end(),
                      "automation lifecycle lane is unavailable");
                if (laneRow != automation->rows().end()) {
                    const EditorViewState lifecycleViewState = view->editorViewState();
                    const int rowIndex = int(std::distance(automation->rows().begin(), laneRow));
                    const int rowHeight = layout::fontPx(4.0);
                    const qreal rowY = qreal(rowIndex * rowHeight + rowHeight / 2);
                    const QPointF automationPoint(layout::fontPx(17.5 + 13.0 / 3.0), rowY);
                    const auto beginAutomation = [&](Qt::MouseButton button,
                                                     Qt::KeyboardModifiers modifiers,
                                                     qreal xOffset) {
                        view->setDrawerActivePage(EditorDrawerPage::Automations);
                        view->setDrawerSectionVisible(EditorDrawerPage::Automations, true);
                        sendMouse(*automation, QEvent::MouseButtonPress,
                                  automationPoint + QPointF(xOffset, 0.0), button,
                                  Qt::MouseButtons(button), modifiers);
                        sendMouse(*automation, QEvent::MouseMove,
                                  automationPoint + QPointF(xOffset + 32.0, 12.0), Qt::NoButton,
                                  Qt::MouseButtons(button), modifiers);
                    };
                    const auto beginVelocity = [&](Qt::MouseButton button,
                                                   const QPointF &position) {
                        view->setDrawerActivePage(EditorDrawerPage::Velocity);
                        view->setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
                        view->selectTrack(noteTrack);
                        const auto live = document->notesForTrack(noteTrack);
                        view->selectionModel().setNoteSelection({live[0].noteId, live[1].noteId});
                        QCoreApplication::processEvents();
                        sendMouse(*velocity, QEvent::MouseButtonPress, position, button,
                                  Qt::MouseButtons(button));
                        sendMouse(*velocity, QEvent::MouseMove, position + QPointF(32.0, -24.0),
                                  Qt::NoButton, Qt::MouseButtons(button));
                    };
                    const auto verifyTermination = [&](QWidget &surface, Qt::MouseButton button,
                                                       const QPointF &release, auto begin) {
                        const auto exercise = [&](const char *route, auto cancel,
                                                  bool clearsSelection) {
                            const QByteArray midi = document->smf().write();
                            const uint64_t revision = document->revision();
                            const int undo = document->undoStack()->count();
                            check(!view->userGestureActive(),
                                  "lifecycle check must begin without an active gesture");
                            begin();
                            const bool interactionStarted = view->userGestureActive();
                            const std::vector<NoteId> selection =
                                view->selectionModel().noteSelection();
                            const std::vector<NoteId> expectedSelection =
                                clearsSelection ? std::vector<NoteId>{} : selection;
                            cancel();
                            const bool interactionTerminated = !view->userGestureActive();
                            sendMouse(surface, QEvent::MouseButtonRelease, release, button,
                                      Qt::NoButton);
                            QCoreApplication::processEvents();
                            const bool previewCleared =
                                std::none_of(selection.begin(), selection.end(),
                                             [thisView = view](const NoteId id) {
                                                 return thisView->previewVelocity(id).has_value();
                                             });
                            check(interactionStarted && interactionTerminated &&
                                      document->smf().write() == midi &&
                                      document->revision() == revision &&
                                      document->undoStack()->count() == undo && previewCleared &&
                                      view->selectionModel().noteSelection() == expectedSelection &&
                                      QWidget::mouseGrabber() != &surface &&
                                      surface.cursor().shape() != Qt::ClosedHandCursor,
                                  route);
                            view->setSong(session->timeline.get(), session->voicegroup);
                            view->setDocument(document);
                            view->setVoicegroup(session->voicegroup);
                            view->applyEditorViewState(lifecycleViewState);
                            view->setDrawerSectionVisible(EditorDrawerPage::Automations, true);
                            view->selectTrack(noteTrack);
                            view->selectionModel().setNoteSelection(selection);
                        };
                        exercise(
                            "page switch did not terminate the live gesture",
                            [&] {
                                view->setDrawerActivePage(view->drawerActivePage() ==
                                                                  EditorDrawerPage::Velocity
                                                              ? EditorDrawerPage::Automations
                                                              : EditorDrawerPage::Velocity);
                            },
                            false);
                        exercise(
                            "drawer hide did not terminate the live gesture",
                            [&] { view->setDrawerSectionVisible(view->drawerActivePage(), false); },
                            false);
                        exercise(
                            "selected-track replacement did not terminate the live gesture",
                            [&] { view->selectTrack(noteTrack == 0 ? 1 : 0); }, true);
                        exercise(
                            "song replacement did not terminate the live gesture",
                            [&] { view->setSong(nullptr, nullptr); }, true);
                        exercise(
                            "document replacement did not terminate the live gesture",
                            [&] { view->setDocument(nullptr); }, true);
                        LoadedVoiceGroup replacementVoicegroup{};
                        exercise(
                            "voice replacement did not terminate the live gesture",
                            [&] { view->setVoicegroup(&replacementVoicegroup); }, false);
                        exercise(
                            "mouse-grab loss did not terminate the live gesture",
                            [&] {
                                QEvent event(QEvent::UngrabMouse);
                                QApplication::sendEvent(view, &event);
                            },
                            false);
                        exercise(
                            "window deactivation did not terminate the live gesture",
                            [&] {
                                QEvent event(QEvent::WindowDeactivate);
                                QApplication::sendEvent(view, &event);
                            },
                            false);
                        exercise(
                            "Escape did not terminate the live gesture",
                            [&] {
                                QKeyEvent event(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
                                QApplication::sendEvent(view, &event);
                            },
                            false);
                    };
                    verifyTermination(
                        *automation, Qt::LeftButton, automationPoint + QPointF(32, 12),
                        [&] { beginAutomation(Qt::LeftButton, Qt::NoModifier, 0.0); });
                    verifyTermination(
                        *automation, Qt::LeftButton, automationPoint + QPointF(112, 12),
                        [&] { beginAutomation(Qt::LeftButton, Qt::NoModifier, 80.0); });
                    verifyTermination(
                        *automation, Qt::LeftButton, automationPoint + QPointF(192, 12),
                        [&] { beginAutomation(Qt::LeftButton, Qt::ShiftModifier, 160.0); });
                    verifyTermination(
                        *automation, Qt::RightButton, automationPoint + QPointF(272, 12),
                        [&] { beginAutomation(Qt::RightButton, Qt::NoModifier, 240.0); });

                    const auto live = document->notesForTrack(noteTrack);
                    const QPointF velocityPoint =
                        velocityNodePosition(*view, *velocity, *session->timeline, live[0]);
                    verifyTermination(*velocity, Qt::LeftButton, velocityPoint + QPointF(32, -24),
                                      [&] { beginVelocity(Qt::LeftButton, velocityPoint); });
                    verifyTermination(
                        *velocity, Qt::LeftButton,
                        QPointF(velocity->plotOrigin() + velocity->plotWidth() - 4, 8), [&] {
                            beginVelocity(
                                Qt::LeftButton,
                                QPointF(velocity->plotOrigin() + velocity->plotWidth() - 36, 8));
                        });
                    verifyTermination(*velocity, Qt::RightButton, velocityPoint + QPointF(32, -24),
                                      [&] { beginVelocity(Qt::RightButton, velocityPoint); });
                    const auto startVelocityRelative = [&] {
                        beginVelocity(Qt::LeftButton, velocityPoint);
                    };
                    const auto releaseVelocityRelative = [&] {
                        sendMouse(*velocity, QEvent::MouseButtonRelease,
                                  velocityPoint + QPointF(32, -24), Qt::LeftButton, Qt::NoButton);
                        QCoreApplication::processEvents();
                    };
                    const std::vector<NoteId> selectionBeforeMutation =
                        view->selectionModel().noteSelection();
                    const DocNote mutationNote = document->notesForTrack(noteTrack).front();
                    const uint64_t mutationRevision = document->revision();
                    const int mutationUndo = document->undoStack()->index();
                    startVelocityRelative();
                    document->setNotesVelocity({mutationNote}, mutationNote.velocity == 127
                                                                   ? 1
                                                                   : mutationNote.velocity + 1);
                    releaseVelocityRelative();
                    check(document->revision() == mutationRevision + 1 &&
                              document->undoStack()->index() == mutationUndo + 1 &&
                              !view->previewVelocity(mutationNote.noteId) &&
                              view->selectionModel().noteSelection() == selectionBeforeMutation,
                          "document mutation did not terminate and clear the staged velocity "
                          "preview");
                    document->undoStack()->undo();

                    const int undoIndex = document->undoStack()->index();
                    startVelocityRelative();
                    document->undoStack()->undo();
                    check(document->undoStack()->index() == undoIndex - 1 &&
                              !view->previewVelocity(mutationNote.noteId) &&
                              view->selectionModel().noteSelection() == selectionBeforeMutation,
                          "Undo did not terminate and clear the staged velocity preview");
                    document->undoStack()->redo();
                    document->undoStack()->undo();
                    const int redoIndex = document->undoStack()->index();
                    startVelocityRelative();
                    document->undoStack()->redo();
                    releaseVelocityRelative();
                    check(document->undoStack()->index() == redoIndex + 1 &&
                              !view->previewVelocity(mutationNote.noteId) &&
                              view->selectionModel().noteSelection() == selectionBeforeMutation,
                          "Redo did not terminate and clear the staged velocity preview");

                    const SongInfo *reloadSong = nullptr;
                    for (const SongInfo &song : window.m_project.songs()) {
                        if (song.label == document->label()) {
                            reloadSong = &song;
                            break;
                        }
                    }
                    QString reloadError;
                    startVelocityRelative();
                    view->setDocument(nullptr);
                    const bool reloaded = reloadSong && document->load(*reloadSong, &reloadError);
                    releaseVelocityRelative();
                    if (reloaded) {
                        session->timeline = document->buildTimeline(window.m_audio.sampleRate());
                        window.attachEngine(*session);
                        view->setSong(session->timeline.get(), session->voicegroup);
                        view->setDocument(document);
                    }
                    check(reloaded && !view->previewVelocity(mutationNote.noteId) &&
                              view->selectionModel().noteSelection().empty(),
                          "reload did not terminate and clear the staged velocity preview");
                }
                document->undoStack()->undo();
            }
        }
        if (!screenshotPath.isEmpty())
            check(window.grab().save(screenshotPath), "could not save host integration screenshot");
    }

    SongSession *songASession = window.sessionForLabel(songA);
    SongSession *songBSession = window.m_active;
    check(songASession && songBSession && songASession != songBSession,
          "host integration did not retain distinct sessions for persistence boundaries");
    if (songASession && songBSession && songASession != songBSession) {
        const EditorAutomationRowId replacementLane{EditorAutomationRowKind::ControlChange, 0, 74};
        const auto sameLaneState = [](const EditorViewState &first, const EditorViewState &second) {
            return first.laneHeight == second.laneHeight &&
                   first.laneHeights == second.laneHeights &&
                   first.laneRanges == second.laneRanges && first.emptyLanes == second.emptyLanes &&
                   first.hiddenLanes() == second.hiddenLanes();
        };
        EditorViewState replacementFixture = songBSession->view->editorViewState();
        replacementFixture.laneHeight = 53;
        replacementFixture.laneHeights.emplace(replacementLane, 61);
        replacementFixture.laneRanges.emplace(replacementLane, 100);
        replacementFixture.emptyLanes.emplace(replacementLane);
        songBSession->view->applyEditorViewState(replacementFixture);
        QCoreApplication::processEvents();
        const EditorViewState replacementState = songBSession->view->editorViewState();
        const QString replacementMidiPath = songBSession->doc.midPath();
        const QByteArray replacementMidi = fileContents(replacementMidiPath);
        window.closeTab(window.m_tabs->indexOf(songASession->view));
        window.loadSongByLabel(songA);
        ViewSidecar::Snapshot replacedSnapshot;
        check(window.m_active && window.m_active->doc.label() == songA &&
                  ViewSidecar::load(scratchProject, songB, &replacedSnapshot) &&
                  sameLaneState(replacedSnapshot.editor, replacementState) &&
                  fileContents(replacementMidiPath) == replacementMidi,
              "song replacement did not save the outgoing lane view state");

        SongSession *replacement = window.m_active;
        if (replacement) {
            replacement->view->setDrawerActivePage(EditorDrawerPage::Velocity);
            replacement->view->setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
            replacement->view->setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
            const EditorViewState projectSwitchState = replacement->view->editorViewState();
            const QString projectSwitchMidiPath = replacement->doc.midPath();
            const QByteArray projectSwitchMidi = fileContents(projectSwitchMidiPath);
            check(window.openProjectDir(scratchProject, false), "project switch failed");
            ViewSidecar::Snapshot projectSwitchSnapshot;
            check(window.m_sessions.empty() &&
                      ViewSidecar::load(scratchProject, songA, &projectSwitchSnapshot) &&
                      sameLaneState(projectSwitchSnapshot.editor, projectSwitchState) &&
                      fileContents(projectSwitchMidiPath) == projectSwitchMidi,
                  "project switch did not save song-specific lane view state");

            window.loadSongByLabel(songA);
            SongSession *closing = window.m_active;
            check(closing, "project switch did not permit a fresh attached session");
            if (closing) {
                closing->view->setDrawerActivePage(EditorDrawerPage::Velocity);
                closing->view->setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
                closing->view->setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
                const EditorViewState closeState = closing->view->editorViewState();
                const QByteArray midiBeforeClose = closing->doc.smf().write();
                const QString closeMidiPath = closing->doc.midPath();
                const QByteArray closeMidi = fileContents(closeMidiPath);
                const int undoBeforeClose = closing->doc.undoStack()->count();
                check(window.close(), "application close boundary was rejected");
                ViewSidecar::Snapshot closeSnapshot;
                check(closing->doc.smf().write() == midiBeforeClose &&
                          fileContents(closeMidiPath) == closeMidi &&
                          closing->doc.undoStack()->count() == undoBeforeClose &&
                          ViewSidecar::load(scratchProject, songA, &closeSnapshot) &&
                          sameLaneState(closeSnapshot.editor, closeState),
                      "application close changed MIDI or failed to save lane view state");
            }
        }
    }
    window.hide();
    std::printf("host-integration: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0 ? 0 : 1;
}

namespace {

EditorAutomationRowId controllerRow(int track, int controller)
{
    return {EditorAutomationRowKind::ControlChange, uint8_t(track), uint8_t(controller)};
}

QJsonObject laneJson(int track, int controller)
{
    QJsonObject lane;
    lane.insert(QStringLiteral("track"), track);
    lane.insert(QStringLiteral("cc"), controller);
    return lane;
}

bool writeJson(const QString &path, const QJsonObject &root)
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    return file.write(QJsonDocument(root).toJson()) >= 0;
}

QJsonObject readJson(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).object();
}

} // namespace

int runViewSidecarCheck(const QString &scratchProject, const QString &songLabel)
{
    auto failures = 0;
    const auto check = [&failures](bool condition, const char *what) {
        if (!condition) {
            std::fprintf(stderr, "sidecar: FAIL: %s\n", what);
            failures++;
        }
    };
    if (scratchProject.isEmpty() || songLabel.isEmpty()) {
        std::fprintf(stderr, "sidecar: scratch project and song label are required\n");
        return 1;
    }
    const QString label = QStringLiteral("sidecar-check-") + songLabel;
    const QString path = ViewSidecar::pathFor(scratchProject, label);
    check(Sidecar::ensureDir(scratchProject), "created sidecar directory");
    QJsonObject originalRoot;
    originalRoot.insert(QStringLiteral("registration"),
                        QJsonObject{{QStringLiteral("pending"), true}});
    QJsonObject originalView;
    originalView.insert(QStringLiteral("futureState"),
                        QJsonArray{QJsonObject{{QStringLiteral("version"), 2}}, 7});
    originalRoot.insert(QStringLiteral("view"), originalView);
    check(writeJson(path, originalRoot), "seeded unrelated root and view fields");

    ViewSidecar::Snapshot saved;
    saved.view.valid = true;
    saved.view.pxPerBeat = 48.0;
    saved.view.keyHeight = 12.0;
    saved.view.scrollPx = 21.5;
    saved.view.scrollY = 7.25;
    saved.view.selectedTrack = 2;
    saved.view.editCursorTick = 96;
    saved.view.gridMinDenom = 16;
    saved.view.gridTriplet = true;
    saved.view.eventList = true;
    saved.editor.velocity = {true, 180};
    saved.editor.automation = {false, 240};
    saved.editor.activePage = EditorDrawerPage::Velocity;
    saved.editor.laneHeight = 96;
    const EditorAutomationRowId volume = controllerRow(2, 7);
    const EditorAutomationRowId hidden = controllerRow(2, 20);
    const EditorAutomationRowId hiddenSecond = controllerRow(2, 21);
    saved.editor.laneHeights.emplace(volume, 112);
    saved.editor.laneRanges.emplace(volume, 91);
    saved.editor.emptyLanes.emplace(volume);
    saved.editor.hideLane(hidden);
    saved.editor.hideLane(hiddenSecond);
    const auto hasSavedLaneState = [&saved](const EditorViewState &editor) {
        return editor.laneHeight == saved.editor.laneHeight &&
               editor.laneHeights == saved.editor.laneHeights &&
               editor.laneRanges == saved.editor.laneRanges &&
               editor.emptyLanes == saved.editor.emptyLanes &&
               editor.hiddenLanes() == saved.editor.hiddenLanes();
    };
    check(ViewSidecar::save(scratchProject, label, saved), "saved detached snapshot");

    ViewSidecar::Snapshot loaded;
    loaded.view.valid = false;
    loaded.editor.hideLane(controllerRow(9, 1));
    check(ViewSidecar::load(scratchProject, label, &loaded), "loaded detached snapshot");
    check(loaded.view.valid && loaded.view.pxPerBeat == saved.view.pxPerBeat &&
              loaded.view.keyHeight == saved.view.keyHeight &&
              loaded.view.scrollPx == saved.view.scrollPx &&
              loaded.view.scrollY == saved.view.scrollY &&
              loaded.view.selectedTrack == saved.view.selectedTrack &&
              loaded.view.editCursorTick == saved.view.editCursorTick &&
              loaded.view.gridMinDenom == saved.view.gridMinDenom &&
              loaded.view.gridTriplet == saved.view.gridTriplet &&
              loaded.view.eventList == saved.view.eventList,
          "round trip restores the detached camera/grid snapshot");
    const EditorViewState defaultEditor;
    check(hasSavedLaneState(loaded.editor) && loaded.editor.velocity == defaultEditor.velocity &&
              loaded.editor.automation == defaultEditor.automation &&
              loaded.editor.activePage == defaultEditor.activePage,
          "round trip restores typed lane state without drawer chrome");
    check(!loaded.editor.isLaneHidden(controllerRow(9, 1)),
          "load replaces rather than merges a caller snapshot");
    const QJsonObject canonicalRoot = readJson(path);
    const QJsonObject canonicalView = canonicalRoot.value(QStringLiteral("view")).toObject();
    const QJsonObject canonicalEditor = canonicalRoot.value(QStringLiteral("editor")).toObject();
    check(canonicalRoot.value(QStringLiteral("registration")).toObject() ==
                  originalRoot.value(QStringLiteral("registration")).toObject() &&
              !canonicalView.contains(QStringLiteral("futureState")),
          "save preserves unrelated root fields and replaces the view schema");
    const auto hasDrawerChrome = [](const QJsonObject &object) {
        return object.contains(QStringLiteral("velocity")) ||
               object.contains(QStringLiteral("automation")) ||
               object.contains(QStringLiteral("activePage")) ||
               object.contains(QStringLiteral("drawerVisible")) ||
               object.contains(QStringLiteral("drawerPage")) ||
               object.contains(QStringLiteral("drawerHeight"));
    };
    check(!hasDrawerChrome(canonicalView) && !hasDrawerChrome(canonicalEditor) &&
              canonicalEditor.value(QStringLiteral("laneHeight")).toInt() == 96 &&
              canonicalEditor.value(QStringLiteral("laneHeights"))
                      .toObject()
                      .value(QStringLiteral("cc:2:7"))
                      .toInt() == 112 &&
              canonicalEditor.value(QStringLiteral("laneRanges"))
                      .toObject()
                      .value(QStringLiteral("cc:2:7"))
                      .toInt() == 91 &&
              canonicalEditor.value(QStringLiteral("emptyLanes")).toArray() ==
                  QJsonArray{laneJson(2, 7)} &&
              canonicalEditor.value(QStringLiteral("hiddenLanes")).toArray() ==
                  QJsonArray{laneJson(2, 20), laneJson(2, 21)},
          "editor JSON stores only ordered lane state");

    QJsonObject viewOnly;
    viewOnly.insert(QStringLiteral("pxPerBeat"), 48.0);
    const EditorAutomationRowId legacyHeightLane = controllerRow(3, 7);
    const EditorAutomationRowId legacyEmptyLane = controllerRow(3, 8);
    const EditorAutomationRowId legacyHiddenFirst = controllerRow(3, 9);
    const EditorAutomationRowId legacyHiddenSecond = controllerRow(3, 10);
    QJsonObject legacyView = viewOnly;
    legacyView.insert(QStringLiteral("laneHeight"), 64);
    legacyView.insert(QStringLiteral("laneHeights"), QJsonObject{{QStringLiteral("cc:3:7"), 72}});
    legacyView.insert(QStringLiteral("laneRanges"), QJsonObject{{QStringLiteral("cc:3:7"), 42}});
    legacyView.insert(QStringLiteral("emptyLanes"), QJsonArray{laneJson(3, 8)});
    legacyView.insert(QStringLiteral("hiddenLanes"), QJsonArray{laneJson(3, 9), laneJson(3, 10)});
    check(writeJson(path, QJsonObject{{QStringLiteral("view"), legacyView}}),
          "seeded legacy view lane state");
    ViewSidecar::Snapshot migrated;
    check(
        ViewSidecar::load(scratchProject, label, &migrated) && migrated.editor.laneHeight == 64 &&
            migrated.editor.laneHeights.size() == 1 &&
            migrated.editor.laneHeights.find(legacyHeightLane) !=
                migrated.editor.laneHeights.end() &&
            migrated.editor.laneHeights.at(legacyHeightLane) == 72 &&
            migrated.editor.laneRanges.size() == 1 &&
            migrated.editor.laneRanges.find(legacyHeightLane) != migrated.editor.laneRanges.end() &&
            migrated.editor.laneRanges.at(legacyHeightLane) == 42 &&
            migrated.editor.emptyLanes.size() == 1 &&
            migrated.editor.emptyLanes.find(legacyEmptyLane) != migrated.editor.emptyLanes.end() &&
            migrated.editor.hiddenLanes() ==
                std::vector<EditorAutomationRowId>{legacyHiddenFirst, legacyHiddenSecond},
        "legacy view lane state migrates in order");
    check(ViewSidecar::save(scratchProject, label, migrated), "saved migrated lane state");
    const QJsonObject migratedRoot = readJson(path);
    const QJsonObject migratedView = migratedRoot.value(QStringLiteral("view")).toObject();
    const QJsonObject migratedEditor = migratedRoot.value(QStringLiteral("editor")).toObject();
    check(!migratedView.contains(QStringLiteral("laneHeight")) &&
              !migratedView.contains(QStringLiteral("laneHeights")) &&
              !migratedView.contains(QStringLiteral("laneRanges")) &&
              !migratedView.contains(QStringLiteral("emptyLanes")) &&
              !migratedView.contains(QStringLiteral("hiddenLanes")) &&
              migratedEditor.contains(QStringLiteral("laneHeight")) &&
              migratedEditor.contains(QStringLiteral("laneHeights")) &&
              migratedEditor.contains(QStringLiteral("laneRanges")) &&
              migratedEditor.contains(QStringLiteral("emptyLanes")) &&
              migratedEditor.contains(QStringLiteral("hiddenLanes")),
          "saving migration writes lane state under editor");

    QJsonObject editorLaneState;
    editorLaneState.insert(QStringLiteral("laneHeight"), 96);
    editorLaneState.insert(QStringLiteral("laneHeights"),
                           QJsonObject{{QStringLiteral("cc:2:7"), 112}});
    editorLaneState.insert(QStringLiteral("laneRanges"),
                           QJsonObject{{QStringLiteral("cc:2:7"), 91}});
    editorLaneState.insert(QStringLiteral("emptyLanes"), QJsonArray{laneJson(2, 7)});
    editorLaneState.insert(QStringLiteral("hiddenLanes"),
                           QJsonArray{laneJson(2, 20), laneJson(2, 21)});
    check(writeJson(path, QJsonObject{{QStringLiteral("view"), legacyView},
                                      {QStringLiteral("editor"), editorLaneState}}),
          "seeded competing editor lane state");
    ViewSidecar::Snapshot editorPreferred;
    check(ViewSidecar::load(scratchProject, label, &editorPreferred) &&
              hasSavedLaneState(editorPreferred.editor),
          "editor lane fields take precedence over legacy view fields");

    check(writeJson(path, QJsonObject{{QStringLiteral("view"), viewOnly}}),
          "seeded view without canonical editor state");
    ViewSidecar::Snapshot defaults;
    check(ViewSidecar::load(scratchProject, label, &defaults) &&
              defaults.editor == EditorViewState{},
          "missing editor object uses editor defaults");

    check(writeJson(path, QJsonObject{{QStringLiteral("view"), viewOnly},
                                      {QStringLiteral("editor"), QStringLiteral("not-an-object")}}),
          "seeded malformed editor object");
    ViewSidecar::Snapshot malformedDefaults;
    check(ViewSidecar::load(scratchProject, label, &malformedDefaults) &&
              malformedDefaults.editor == EditorViewState{},
          "malformed editor object uses editor defaults");

    QJsonObject malformedRoot;
    QJsonObject malformedView;
    malformedView.insert(QStringLiteral("pxPerBeat"), true);
    malformedRoot.insert(QStringLiteral("view"), malformedView);
    QJsonObject malformedEditor;
    malformedEditor.insert(QStringLiteral("laneHeight"), QStringLiteral("96"));
    QJsonObject heights;
    heights.insert(QStringLiteral("cc:2:7"), 112);
    heights.insert(QStringLiteral("cc:2:128"), 64);
    heights.insert(QStringLiteral("cc:2:255"), 64);
    heights.insert(QStringLiteral("voice:01"), 64);
    heights.insert(QStringLiteral("tempo"), QStringLiteral("bad"));
    malformedEditor.insert(QStringLiteral("laneHeights"), heights);
    QJsonObject ranges;
    ranges.insert(QStringLiteral("cc:2:7"), 91);
    ranges.insert(QStringLiteral("cc:2:128"), 91);
    ranges.insert(QStringLiteral("cc:2:255"), 128);
    malformedEditor.insert(QStringLiteral("laneRanges"), ranges);
    QJsonArray emptyLanes;
    emptyLanes.append(laneJson(2, 7));
    emptyLanes.append(laneJson(2, 128));
    emptyLanes.append(
        QJsonObject{{QStringLiteral("track"), QStringLiteral("2")}, {QStringLiteral("cc"), 7}});
    malformedEditor.insert(QStringLiteral("emptyLanes"), emptyLanes);
    QJsonArray hiddenLanes;
    hiddenLanes.append(laneJson(2, 20));
    hiddenLanes.append(laneJson(2, 128));
    malformedEditor.insert(QStringLiteral("hiddenLanes"), hiddenLanes);
    malformedRoot.insert(QStringLiteral("editor"), malformedEditor);
    check(writeJson(path, malformedRoot), "seeded malformed known entries");
    ViewSidecar::Snapshot strict;
    check(ViewSidecar::load(scratchProject, label, &strict),
          "loads canonical objects with malformed entries");
    check(strict.view.pxPerBeat == SongView::ViewState{}.pxPerBeat && strict.editor.laneHeight == 0,
          "invalid known scalars fall back independently");
    check(strict.editor.laneHeights.size() == 2 &&
              strict.editor.laneHeights.find(volume) != strict.editor.laneHeights.end() &&
              strict.editor.laneHeights.find(controllerRow(2, 255)) !=
                  strict.editor.laneHeights.end() &&
              strict.editor.laneRanges.size() == 1 && strict.editor.laneRanges.at(volume) == 91,
          "row keys and range values use canonical strict validation");
    check(strict.editor.emptyLanes.size() == 1 &&
              strict.editor.emptyLanes.find(volume) != strict.editor.emptyLanes.end() &&
              strict.editor.hiddenLanes().size() == 1 && strict.editor.hiddenLanes()[0] == hidden,
          "lane arrays tolerate bad entries without retaining invalid lanes");

    const EditorAutomationRowId tempoRow{EditorAutomationRowKind::Tempo, 0, 0};
    QJsonObject voiceDiscardHeights;
    voiceDiscardHeights.insert(QStringLiteral("tempo"), 94);
    voiceDiscardHeights.insert(QStringLiteral("cc:2:7"), 112);
    voiceDiscardHeights.insert(QStringLiteral("voice:0"), 66);
    voiceDiscardHeights.insert(QStringLiteral("voice:2"), 70);
    QJsonObject voiceDiscardRanges;
    voiceDiscardRanges.insert(QStringLiteral("tempo"), 116);
    voiceDiscardRanges.insert(QStringLiteral("cc:2:7"), 91);
    voiceDiscardRanges.insert(QStringLiteral("voice:0"), 103);
    QJsonObject voiceDiscardEditor;
    voiceDiscardEditor.insert(QStringLiteral("laneHeight"), 96);
    voiceDiscardEditor.insert(QStringLiteral("laneHeights"), voiceDiscardHeights);
    voiceDiscardEditor.insert(QStringLiteral("laneRanges"), voiceDiscardRanges);
    check(writeJson(path, QJsonObject{{QStringLiteral("view"), QJsonObject{}},
                                      {QStringLiteral("editor"), voiceDiscardEditor}}),
          "seeded legacy voice sidecar entries");
    ViewSidecar::Snapshot voiceDiscarded;
    check(ViewSidecar::load(scratchProject, label, &voiceDiscarded),
          "loads sidecar with legacy voice keys");
    check(voiceDiscarded.editor.laneHeight == 96 && voiceDiscarded.editor.laneHeights.size() == 2 &&
              voiceDiscarded.editor.laneHeights.find(tempoRow) !=
                  voiceDiscarded.editor.laneHeights.end() &&
              voiceDiscarded.editor.laneHeights.at(tempoRow) == 94 &&
              voiceDiscarded.editor.laneHeights.at(volume) == 112 &&
              voiceDiscarded.editor.laneRanges.size() == 2 &&
              voiceDiscarded.editor.laneRanges.at(tempoRow) == 116 &&
              voiceDiscarded.editor.laneRanges.at(volume) == 91,
          "legacy voice sidecar entries are discarded while Tempo and CC survive");
    check(ViewSidecar::save(scratchProject, label, voiceDiscarded),
          "saves sidecar after discarding voice keys");
    const QByteArray rewrittenSidecar = fileContents(path);
    const QJsonObject rewrittenHeights = readJson(path)
                                             .value(QStringLiteral("editor"))
                                             .toObject()
                                             .value(QStringLiteral("laneHeights"))
                                             .toObject();
    const QJsonObject rewrittenRanges = readJson(path)
                                            .value(QStringLiteral("editor"))
                                            .toObject()
                                            .value(QStringLiteral("laneRanges"))
                                            .toObject();
    check(!QString::fromUtf8(rewrittenSidecar).contains(QLatin1String("voice:")) &&
              rewrittenHeights.contains(QStringLiteral("tempo")) &&
              rewrittenHeights.contains(QStringLiteral("cc:2:7")) &&
              rewrittenRanges.contains(QStringLiteral("tempo")) &&
              rewrittenRanges.contains(QStringLiteral("cc:2:7")),
          "reserialized sidecar contains no voice key");

    const int maximumRowHeight = layout::fontPx(32.0 / 3.0);
    QJsonObject oversizedHeights;
    oversizedHeights.insert(QStringLiteral("cc:2:7"), maximumRowHeight + 1);
    QJsonObject oversizedEditor;
    oversizedEditor.insert(QStringLiteral("laneHeight"), maximumRowHeight + 1);
    oversizedEditor.insert(QStringLiteral("laneHeights"), oversizedHeights);
    check(writeJson(path, QJsonObject{{QStringLiteral("view"), QJsonObject{}},
                                      {QStringLiteral("editor"), oversizedEditor}}),
          "seeded oversized row heights");
    ViewSidecar::Snapshot clamped;
    check(ViewSidecar::load(scratchProject, label, &clamped), "loads oversized row heights");
    const auto clampedHeight = clamped.editor.laneHeights.find(volume);
    check(clamped.editor.laneHeight == maximumRowHeight &&
              clampedHeight != clamped.editor.laneHeights.end() &&
              clampedHeight->second == maximumRowHeight,
          "oversized row heights restore at the resolved maximum");
    check(ViewSidecar::save(scratchProject, label, clamped), "saves clamped row heights");
    const QJsonObject clampedEditor = readJson(path).value(QStringLiteral("editor")).toObject();
    check(clampedEditor.value(QStringLiteral("laneHeight")).toInt() == maximumRowHeight &&
              clampedEditor.value(QStringLiteral("laneHeights"))
                      .toObject()
                      .value(QStringLiteral("cc:2:7"))
                      .toInt() == maximumRowHeight,
          "save retains canonical row heights");

    ViewSidecar::Snapshot unchanged;
    unchanged.view.valid = true;
    unchanged.editor.laneHeight = 64;
    check(writeJson(path, QJsonObject{{QStringLiteral("view"),
                                       QJsonValue(QStringLiteral("not-an-object"))}}),
          "seeded malformed view root");
    check(!ViewSidecar::load(scratchProject, label, &unchanged) && unchanged.view.valid &&
              unchanged.editor.laneHeight == 64,
          "malformed view leaves caller snapshot untouched");
    check(!ViewSidecar::load(scratchProject, label + QStringLiteral("-missing"), &unchanged),
          "missing sidecar fails silently");
    check(!ViewSidecar::save(scratchProject, QString(), saved), "empty song label fails silently");

    QFile::remove(path);
    std::fprintf(stdout, "sidecar: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
