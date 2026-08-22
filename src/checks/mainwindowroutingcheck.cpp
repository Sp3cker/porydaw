#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QFile>
#include <QPixmap>
#include <QScrollArea>
#include <QScrollBar>
#include <QSettings>
#include <QStatusBar>
#include <QTabWidget>
#include <QUndoStack>
#include <QWidget>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <optional>
#include <vector>

#include "checks/support/eventsynth.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "mainwindow.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/viewsidecar.h"

namespace {

void sendKeyStroke(QWidget &widget, Qt::Key key, Qt::KeyboardModifiers modifiers, bool autoRepeat)
{
    checks::events::sendKey(widget, QEvent::KeyPress, key, modifiers, QString(), autoRepeat, 1);
    checks::events::sendKey(widget, QEvent::KeyRelease, key, modifiers, QString(), autoRepeat, 1);
}

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
    constexpr uint64_t auditionTick = 24;
    stopPlayback();
    tabB->view->commitEditCursor(0);
    tabB->view->requestPlayPauseFrom(auditionTick);
    check(m_audio.transport() == Transport::Playing && tabB->view->editCursorTick() == auditionTick,
          "audition request did not start playback from its requested tick");
    tabB->view->requestPlayPauseFrom(auditionTick);
    check(m_audio.transport() == Transport::Paused &&
              tabB->view->editCursorTick() == auditionTick &&
              uint64_t(tabB->view->playheadTick() + 0.5) == auditionTick,
          "playing audition did not pause and return the playhead to its requested tick");
    stopPlayback();

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
    sendKeyStroke(*this, Qt::Key_A, Qt::NoModifier, false);
    check(tabB->view->drawerSectionVisible(EditorDrawerPage::Automations) &&
              tabB->view->drawerActivePage() == EditorDrawerPage::Automations &&
              tabA->view->drawerSectionVisible(EditorDrawerPage::Automations) &&
              tabA->view->drawerActivePage() == EditorDrawerPage::Automations &&
              statusBar()->currentMessage() == QStringLiteral("Automation lanes shown"),
          "automation route did not update application-wide drawer chrome");
    sendKeyStroke(*this, Qt::Key_A, Qt::NoModifier, false);
    check(!tabB->view->drawerSectionVisible(EditorDrawerPage::Automations) &&
              !tabA->view->drawerSectionVisible(EditorDrawerPage::Automations) &&
              statusBar()->currentMessage() == QStringLiteral("Automation lanes hidden"),
          "automation route did not globally close the drawer");
    sendKeyStroke(*this, Qt::Key_V, Qt::NoModifier, false);
    QCoreApplication::processEvents();
    check(tabB->view->drawerSectionVisible(EditorDrawerPage::Velocity) &&
              tabB->view->drawerActivePage() == EditorDrawerPage::Velocity &&
              tabA->view->drawerSectionVisible(EditorDrawerPage::Velocity) &&
              tabA->view->drawerActivePage() == EditorDrawerPage::Velocity &&
              statusBar()->currentMessage() == QStringLiteral("Velocity lane shown"),
          "velocity route did not update application-wide drawer chrome");
    sendKeyStroke(*this, Qt::Key_V, Qt::NoModifier, false);
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
        sendKeyStroke(*velocitySurface, Qt::Key_V, Qt::NoModifier, false);
        QCoreApplication::processEvents();
        check(!tabB->view->drawerSectionVisible(EditorDrawerPage::Velocity) &&
                  tabB->view->drawerSectionVisible(EditorDrawerPage::Automations) &&
                  QApplication::focusWidget() == automationSurface,
              "closing focused velocity did not focus the remaining automation drawer");
        if (QWidget *focus = QApplication::focusWidget()) {
            sendKeyStroke(*focus, Qt::Key_A, Qt::NoModifier, false);
        }
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
    sendKeyStroke(*this, Qt::Key_V, Qt::NoModifier, false);
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

    hide();
    std::printf("mainwindow-routing: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0;
}

int runMainWindowRoutingCheck(const QString &projectRoot, const QString &songA,
                              const QString &songB)
{
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
                        checks::events::sendMouse(*automation, QEvent::MouseButtonPress,
                                                  automationPoint + QPointF(xOffset, 0.0), button,
                                                  Qt::MouseButtons(button), modifiers);
                        checks::events::sendMouse(*automation, QEvent::MouseMove,
                                                  automationPoint + QPointF(xOffset + 32.0, 12.0),
                                                  Qt::NoButton, Qt::MouseButtons(button),
                                                  modifiers);
                    };
                    const auto beginVelocity = [&](Qt::MouseButton button,
                                                   const QPointF &position) {
                        view->setDrawerActivePage(EditorDrawerPage::Velocity);
                        view->setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
                        view->selectTrack(noteTrack);
                        const auto live = document->notesForTrack(noteTrack);
                        view->selectionModel().setNoteSelection({live[0].noteId, live[1].noteId});
                        QCoreApplication::processEvents();
                        checks::events::sendMouse(*velocity, QEvent::MouseButtonPress, position,
                                                  button, Qt::MouseButtons(button), Qt::NoModifier);
                        checks::events::sendMouse(*velocity, QEvent::MouseMove,
                                                  position + QPointF(32.0, -24.0), Qt::NoButton,
                                                  Qt::MouseButtons(button), Qt::NoModifier);
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
                            checks::events::sendMouse(surface, QEvent::MouseButtonRelease, release,
                                                      button, Qt::NoButton, Qt::NoModifier);
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
                                checks::events::sendKey(*view, QEvent::KeyPress, Qt::Key_Escape,
                                                        Qt::NoModifier, QString(), false, 1);
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
                        checks::events::sendMouse(*velocity, QEvent::MouseButtonRelease,
                                                  velocityPoint + QPointF(32, -24), Qt::LeftButton,
                                                  Qt::NoButton, Qt::NoModifier);
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
