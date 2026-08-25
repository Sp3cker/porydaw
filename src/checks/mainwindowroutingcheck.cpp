#include <QAction>
#include <QApplication>
#include <QClipboard>
#include <QCoreApplication>
#include <QEvent>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QKeySequence>
#include <QLineEdit>
#include <QMenu>
#include <QMenuBar>
#include <QMouseEvent>
#include <QPixmap>
#include <QScrollArea>
#include <QScrollBar>
#include <QSettings>
#include <QStatusBar>
#include <QUndoStack>
#include <QWidget>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <optional>
#include <vector>

#include "checks/clipcheck_support.h"
#include "checks/support/eventsynth.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "mainwindow.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/clipmime.h"
#include "ui/viewsidecar.h"
#include "ui/workspaceui.h"

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
    if (!tabA || !tabB || tabA == tabB || m_workspace->openSessionCount() != 2) {
        std::fprintf(stderr, "mainwindow-routing: songs did not open in two tabs\n");
        return false;
    }
    SongView &tabAView = m_workspace->viewFor(*tabA);
    SongView &tabBView = m_workspace->viewFor(*tabB);

    constexpr uint64_t auditionTick = 24;
    stopPlayback();
    tabBView.commitEditCursor(0);
    tabBView.requestPlayPauseFrom(auditionTick);
    check(m_audio.transport() == Transport::Playing && tabBView.editCursorTick() == auditionTick,
          "audition request did not start playback from its requested tick");
    tabBView.requestPlayPauseFrom(auditionTick);
    check(m_audio.transport() == Transport::Paused && tabBView.editCursorTick() == auditionTick &&
              uint64_t(tabBView.playheadTick() + 0.5) == auditionTick,
          "playing audition did not pause and return the playhead to its requested tick");
    stopPlayback();
    auto &keys = keymap::Registry::instance();
    QAction *copyAction = findChild<QAction *>(QStringLiteral("copyWindowAction"));
    QMenu *editMenu = nullptr;
    for (QAction *menuAction : menuBar()->actions()) {
        auto *menu = menuAction->menu();
        if (menu && QString(menu->title()).remove(QLatin1Char('&')) == QStringLiteral("Edit")) {
            editMenu = menu;
            break;
        }
    }
    const auto copyCommand = keys.command(QStringLiteral("roll.copy"));
    const auto standardCopyBindings = QKeySequence::keyBindings(QKeySequence::Copy);
    const bool hasStandardDefault =
        std::any_of(copyCommand.defaults.cbegin(), copyCommand.defaults.cend(),
                    [&standardCopyBindings](const QKeySequence &sequence) {
                        return standardCopyBindings.contains(sequence);
                    });
    check(copyAction && copyAction == m_copyAction && copyAction->parent() == this,
          "native Copy action is missing or is not owned by MainWindow");
    check(editMenu && editMenu->actions().contains(copyAction),
          "native Copy action is not a member of the Edit menu");
    check(hasStandardDefault && copyAction &&
              copyAction->shortcuts() == keys.bindings(QStringLiteral("roll.copy")),
          "native Copy action does not carry the standard/current roll.copy binding");
    check(copyAction && copyAction->shortcutContext() == Qt::WindowShortcut,
          "native Copy action is not a WindowShortcut");
    int liveCopyOwners = 0;
    const auto currentCopyBindings = keys.bindings(QStringLiteral("roll.copy"));
    for (QAction *action : findChildren<QAction *>()) {
        if (!action->isEnabled())
            continue;
        const bool ownsCopy = std::any_of(currentCopyBindings.cbegin(), currentCopyBindings.cend(),
                                          [action](const QKeySequence &sequence) {
                                              return action->shortcuts().contains(sequence);
                                          });
        if (ownsCopy)
            ++liveCopyOwners;
    }
    check(currentCopyBindings.isEmpty() || liveCopyOwners == 1,
          "more than one live QAction owns the Copy shortcut");

    songview::EditorSelectionModel::TimeSelection tabATimeSelection;
    tabATimeSelection.startTick = 0;
    tabATimeSelection.endTick = tabA->timeline->ticksPerBeat;
    tabAView.selectionModel().setTimeSelection(tabATimeSelection);
    auto tabBNote = std::optional<DocNote>{};
    for (int track = 0; track < tabB->doc.engineTrackCount() && !tabBNote; ++track) {
        const auto notes = tabB->doc.notesForTrack(track);
        if (!notes.empty()) {
            tabBView.selectTrack(track);
            tabBView.selectionModel().setNoteSelection({notes.front().noteId});
            tabBNote = notes.front();
        }
    }
    check(tabBNote.has_value(), "active-tab Copy check found no note in the second song");
    if (copyAction && tabBNote) {
        auto copyTriggerCount = 0;
        const QMetaObject::Connection triggerSpy = connect(
            copyAction, &QAction::triggered, this, [&copyTriggerCount] { ++copyTriggerCount; });
        tabBView.focusActiveSurface();
        QCoreApplication::processEvents();
        if (currentCopyBindings.isEmpty()) {
            check(false, "native Copy action has no shortcut to exercise");
        } else {
            const auto combination = currentCopyBindings.front()[0];
            auto *target = QApplication::focusWidget();
            QKeyEvent press(QEvent::KeyPress, combination.key(), combination.keyboardModifiers());
            QKeyEvent release(QEvent::KeyRelease, combination.key(),
                              combination.keyboardModifiers());
            QApplication::sendEvent(target, &press);
            QApplication::sendEvent(target, &release);
        }
        check(copyTriggerCount == 1,
              "Copy shortcut did not trigger the MainWindow Edit action exactly once");
        const auto noteCopy = clipcheck_support::checkClipboardClip();
        const bool copiedSelectedNote =
            noteCopy && noteCopy->ticksPerBeat == tabB->timeline->ticksPerBeat &&
            noteCopy->clip.span == 0 && noteCopy->clip.tracks.size() == 1 &&
            noteCopy->clip.tracks.front().notes.size() == 1 &&
            noteCopy->clip.tracks.front().notes.front().key == tabBNote->key &&
            noteCopy->clip.tracks.front().notes.front().velocity == tabBNote->velocity;
        check(copiedSelectedNote, "Copy action did not route to the active tab's selected note");
        m_workspace->activateSession(tabA);
        QCoreApplication::processEvents();
        copyAction->trigger();
        const auto timeCopy = clipcheck_support::checkClipboardClip();
        check(timeCopy && timeCopy->ticksPerBeat == tabA->timeline->ticksPerBeat &&
                  timeCopy->clip.span == tabATimeSelection.endTick,
              "Copy action did not route the active tab's time selection");
        auto textProbe = QLineEdit(this);
        textProbe.setText(QStringLiteral("native copy text probe"));
        textProbe.selectAll();
        textProbe.show();
        textProbe.setFocus();
        QCoreApplication::processEvents();
        copyAction->trigger();
        check(QApplication::clipboard()->text() == QStringLiteral("native copy text probe"),
              "Edit Copy action hijacked focused text-widget copy");
        disconnect(triggerSpy); // the lambda captures a block-local by reference
        m_workspace->activateSession(tabB);
        QCoreApplication::processEvents();
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
    check(tabAView.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              !tabAView.drawerSectionVisible(EditorDrawerPage::Automations) &&
              tabAView.drawerActivePage() == EditorDrawerPage::Velocity &&
              tabAView.drawerSectionHeight(EditorDrawerPage::Velocity) == 173 &&
              tabBView.editorViewState().drawerState() == tabAView.editorViewState().drawerState(),
          "new tabs did not restore application-wide drawer settings");

    tabAView.setDrawerSectionVisible(EditorDrawerPage::Automations, false);
    tabAView.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    check(!tabBView.hasVisibleDrawerSection(),
          "drawer visibility did not propagate to the other open tab");

    tabBView.focusContent();
    sendKeyStroke(*this, Qt::Key_A, Qt::NoModifier, false);
    check(tabBView.drawerSectionVisible(EditorDrawerPage::Automations) &&
              tabBView.drawerActivePage() == EditorDrawerPage::Automations &&
              tabAView.drawerSectionVisible(EditorDrawerPage::Automations) &&
              tabAView.drawerActivePage() == EditorDrawerPage::Automations &&
              statusBar()->currentMessage() == QStringLiteral("Automation lanes shown"),
          "automation route did not update application-wide drawer chrome");
    sendKeyStroke(*this, Qt::Key_A, Qt::NoModifier, false);
    check(!tabBView.drawerSectionVisible(EditorDrawerPage::Automations) &&
              !tabAView.drawerSectionVisible(EditorDrawerPage::Automations) &&
              statusBar()->currentMessage() == QStringLiteral("Automation lanes hidden"),
          "automation route did not globally close the drawer");
    sendKeyStroke(*this, Qt::Key_V, Qt::NoModifier, false);
    QCoreApplication::processEvents();
    check(tabBView.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              tabBView.drawerActivePage() == EditorDrawerPage::Velocity &&
              tabAView.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              tabAView.drawerActivePage() == EditorDrawerPage::Velocity &&
              statusBar()->currentMessage() == QStringLiteral("Velocity lane shown"),
          "velocity route did not update application-wide drawer chrome");
    sendKeyStroke(*this, Qt::Key_V, Qt::NoModifier, false);
    QCoreApplication::processEvents();
    QWidget *focusAfterClose = QApplication::focusWidget();
    check(focusAfterClose &&
              (focusAfterClose == &tabBView || tabBView.isAncestorOf(focusAfterClose)),
          "closing a focus-owned drawer did not return focus to active content");

    auto *automationSurface = descendant<AutomationCanvas>(tabBView);
    auto *velocitySurface = descendant<VelocityArea>(tabBView);
    check(automationSurface && velocitySurface,
          "drawer shortcut focus check could not find both editor surfaces");
    if (automationSurface && velocitySurface) {
        tabBView.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        tabBView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        tabBView.setDrawerActivePage(EditorDrawerPage::Velocity);
        velocitySurface->setFocus(Qt::MouseFocusReason);
        QCoreApplication::processEvents();
        check(QApplication::focusWidget() == velocitySurface,
              "velocity surface did not accept focus for the drawer shortcut check");
        sendKeyStroke(*velocitySurface, Qt::Key_V, Qt::NoModifier, false);
        QCoreApplication::processEvents();
        check(!tabBView.drawerSectionVisible(EditorDrawerPage::Velocity) &&
                  tabBView.drawerSectionVisible(EditorDrawerPage::Automations) &&
                  QApplication::focusWidget() == automationSurface,
              "closing focused velocity did not focus the remaining automation drawer");
        if (QWidget *focus = QApplication::focusWidget()) {
            sendKeyStroke(*focus, Qt::Key_A, Qt::NoModifier, false);
        }
        QCoreApplication::processEvents();
        QWidget *focusAfterFocusedClose = QApplication::focusWidget();
        check(!tabBView.hasVisibleDrawerSection() && focusAfterFocusedClose &&
                  (focusAfterFocusedClose == &tabBView ||
                   tabBView.isAncestorOf(focusAfterFocusedClose)),
              "closing focused automation did not return focus to active content");
    }

    tabBView.setDrawerActivePage(EditorDrawerPage::Velocity);
    tabBView.setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
    const int retainedHeight = tabBView.drawerSectionHeight(EditorDrawerPage::Velocity);
    tabBView.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    check(tabBView.drawerActivePage() == EditorDrawerPage::Velocity &&
              tabBView.drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight &&
              tabAView.drawerActivePage() == EditorDrawerPage::Velocity &&
              tabAView.drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight,
          "drawer hide did not retain globally shared page and height");
    m_workspace->activateSession(tabA);
    m_workspace->activateSession(tabB);
    QCoreApplication::processEvents();
    QWidget *focusAfterTabSwitch = QApplication::focusWidget();
    check(focusAfterTabSwitch &&
              (focusAfterTabSwitch == &tabBView || tabBView.isAncestorOf(focusAfterTabSwitch)) &&
              focusAfterTabSwitch->focusPolicy() != Qt::NoFocus,
          "tab switch did not request active content focus");
    check(m_active == tabB && tabBView.drawerActivePage() == EditorDrawerPage::Velocity &&
              tabBView.drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight &&
              tabAView.drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight,
          "application-wide drawer state did not survive a tab switch");

    tabBView.setEventListVisible(true);
    QCoreApplication::processEvents();
    const bool blockedVelocityVisible = tabBView.drawerSectionVisible(EditorDrawerPage::Velocity);
    const EditorDrawerPage blockedPage = tabBView.drawerActivePage();
    const QString blockedStatus = statusBar()->currentMessage();
    check(!m_automationDrawerAction->isEnabled() && !m_velocityDrawerAction->isEnabled(),
          "event-list mode did not disable drawer routes");
    sendKeyStroke(*this, Qt::Key_V, Qt::NoModifier, false);
    check(tabBView.drawerSectionVisible(EditorDrawerPage::Velocity) == blockedVelocityVisible &&
              tabBView.drawerActivePage() == blockedPage &&
              statusBar()->currentMessage() == blockedStatus,
          "event-list mode let a drawer route change or announce");
    tabBView.setEventListVisible(false);
    QCoreApplication::processEvents();
    check(m_automationDrawerAction->isEnabled() && m_velocityDrawerAction->isEnabled(),
          "leaving event-list mode did not re-enable drawer routes");

    const EditorAutomationRowId persistedLane{EditorAutomationRowKind::ControlChange, 0, 74};
    EditorViewState drawerCosmetics = tabBView.editorViewState();
    drawerCosmetics.laneHeight = 53;
    drawerCosmetics.laneHeights[persistedLane] = 61;
    drawerCosmetics.laneRanges[persistedLane] = 100;
    drawerCosmetics.emptyLanes.insert(persistedLane);
    tabBView.applyEditorViewState(drawerCosmetics);
    const auto sameLaneState = [](const EditorViewState &first, const EditorViewState &second) {
        return first.laneHeight == second.laneHeight && first.laneHeights == second.laneHeights &&
               first.laneRanges == second.laneRanges && first.emptyLanes == second.emptyLanes &&
               first.hiddenLanes() == second.hiddenLanes();
    };

    const QByteArray sidecarBefore = fileContents(ViewSidecar::pathFor(projectRoot, songB));
    const QByteArray midiBefore = tabB->doc.smf().write();
    const uint64_t revisionBefore = tabB->doc.revision();
    const int undoBefore = tabB->doc.undoStack()->count();
    tabBView.setDrawerActivePage(EditorDrawerPage::Velocity);
    tabBView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    tabBView.setDrawerSectionHeight(EditorDrawerPage::Velocity, retainedHeight);
    QCoreApplication::processEvents();
    const EditorViewState expectedCosmetics = tabBView.editorViewState();
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

    closeSession(*tabB);
    ViewSidecar::Snapshot savedSnapshot;
    check(ViewSidecar::load(projectRoot, songB, &savedSnapshot) && savedSnapshot.view.valid &&
              savedSnapshot.editor.drawerState() == EditorDrawerState{} &&
              sameLaneState(savedSnapshot.editor, expectedCosmetics),
          "tab close did not persist only song-specific lane state");
    loadSongByLabel(songB, true);
    SongSession *reopened = sessionForLabel(songB);
    if (reopened) {
        SongView &reopenedView = m_workspace->viewFor(*reopened);
        check(reopenedView.drawerSectionVisible(EditorDrawerPage::Velocity) &&
                  reopenedView.drawerActivePage() == EditorDrawerPage::Velocity &&
                  reopenedView.drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight &&
                  reopenedView.editorViewState().drawerState() == m_editorDrawerState &&
                  sameLaneState(reopenedView.editorViewState(), expectedCosmetics),
              "reopened song did not combine global drawer chrome with its lane state");
    } else {
        check(false, "reopened song did not combine global drawer chrome with its lane state");
    }

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
    const bool sessionReady = session && session->timeline;
    check(sessionReady, "MainWindow flow did not leave an attached SongView and timeline");
    if (sessionReady) {
        SongView &view = window.m_workspace->viewFor(*session);
        SongDocument *document = view.document();
        check(document, "MainWindow flow did not leave an attached SongView and timeline");
        if (document) {
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
                view.selectTrack(noteTrack);
                const std::vector<NoteId> selection{notes[0].noteId, notes[1].noteId};
                view.selectionModel().setNoteSelection(selection);
            }

            view.setDrawerActivePage(EditorDrawerPage::Velocity);
            view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
            view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
            view.setDocument(nullptr);
            view.setDocument(document);
            view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
            view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
            QCoreApplication::processEvents();
            auto *automation = descendant<AutomationCanvas>(view);
            auto *velocity = descendant<VelocityArea>(view);
            auto *drawer = descendant<EditorDrawer>(view);
            check(automation && velocity && drawer,
                  "host flow did not expose drawer and page diagnostics");
            if (automation && velocity && drawer) {
                view.setDrawerActivePage(EditorDrawerPage::Velocity);
                view.setFollowPlayhead(false);
                auto firstTick = uint64_t{0};
                auto finalTick = uint64_t{0};
                auto foundSteadySamples = false;
                for (uint64_t candidate = 0; candidate < 4096 && !foundSteadySamples; ++candidate) {
                    const DrawerPageVoiceContext context = view.voiceContext(candidate);
                    uint64_t previousSample = 0;
                    auto steady = true;
                    for (uint64_t offset = 0; offset <= 120; ++offset) {
                        const DrawerPageVoiceContext next = view.voiceContext(candidate + offset);
                        const uint64_t sample =
                            session->timeline->sampleForTick(candidate + offset);
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
                    view.setPlayheadSample(session->timeline->sampleForTick(firstTick), true);
                    QCoreApplication::processEvents();
                    const auto automationBefore = automation->diagnostics();
                    const auto velocityBefore = velocity->diagnostics();
                    for (uint64_t tick = firstTick + 1; tick <= finalTick; ++tick)
                        view.setPlayheadSample(session->timeline->sampleForTick(tick), true);
                    QCoreApplication::processEvents();
                    check(uint64_t(view.playheadTick() + 0.5) == finalTick,
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
                    const uint8_t editedVelocity =
                        editNote.velocity == 127 ? 1 : editNote.velocity + 1;
                    const std::vector<NoteVelocity> edit{{editNote.noteId, editedVelocity}};
                    const uint64_t editRevision = document->revision();
                    const int editUndo = document->undoStack()->index();
                    const bool beganEdit = view.beginVelocityGesture(liveNotes);
                    const bool updatedEdit = view.updateVelocityGesture(edit);
                    const auto editPreview = view.previewVelocity(editNote.noteId);
                    check(beganEdit && updatedEdit && editPreview &&
                              *editPreview == editedVelocity &&
                              document->revision() == editRevision &&
                              document->undoStack()->index() == editUndo,
                          "document edit should stage velocity preview without mutating history");
                    const auto commit = view.commitVelocityGesture();
                    QCoreApplication::processEvents();
                    const auto committedNotes = document->notesForTrack(noteTrack);
                    const auto committedNote =
                        std::find_if(committedNotes.begin(), committedNotes.end(),
                                     [&editNote](const DocNote &note) {
                                         return note.noteId == editNote.noteId;
                                     });
                    check(commit == SongView::VelocityCommitResult::Committed &&
                              committedNote != committedNotes.end() &&
                              committedNote->velocity == editedVelocity &&
                              document->revision() == editRevision + 1 &&
                              document->undoStack()->index() == editUndo + 1 &&
                              !view.previewVelocity(editNote.noteId) &&
                              velocity->diagnostics().contentBuildCount >
                                  editBefore.contentBuildCount,
                          "document edit did not commit its exact velocity once or invalidate "
                          "affected "
                          "velocity content");
                    document->undoStack()->undo();
                } else {
                    check(false, "velocity edit invalidation fixture is unavailable");
                }
                const auto selectionBefore = velocity->diagnostics();
                view.selectionModel().clearNoteSelection();
                QCoreApplication::processEvents();
                check(velocity->diagnostics().contentBuildCount > selectionBefore.contentBuildCount,
                      "selection change did not invalidate affected velocity content");
                const auto zoomBefore = velocity->diagnostics();
                view.zoomAroundContentX(1.1, qreal(view.width()) / 2.0);
                QCoreApplication::processEvents();
                check(velocity->diagnostics().contentBuildCount > zoomBefore.contentBuildCount,
                      "zoom did not invalidate affected velocity content");
                view.setDrawerActivePage(EditorDrawerPage::Automations);
                QCoreApplication::processEvents();
                const auto automationThemeBefore = automation->diagnostics();
                QEvent automationThemeChange(QEvent::PaletteChange);
                QApplication::sendEvent(automation, &automationThemeChange);
                QCoreApplication::processEvents();
                check(automation->diagnostics().contentInvalidationCount >
                          automationThemeBefore.contentInvalidationCount,
                      "theme change did not invalidate affected automation content");
                view.setDrawerActivePage(EditorDrawerPage::Velocity);

                if (noteTrack >= 0) {
                    view.addEmptyLane(noteTrack, 74);
                    EditorViewState automationCosmetics = view.editorViewState();
                    automationCosmetics.laneHeight = layout::fontPx(4.0);
                    view.applyEditorViewState(automationCosmetics);
                    document->addLanePoint(noteTrack, 74, 0, 64);
                    view.setDrawerActivePage(EditorDrawerPage::Automations);
                    QCoreApplication::processEvents();
                    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange,
                                                     uint8_t(noteTrack), 74};
                    const auto laneRow =
                        std::find_if(automation->rows().begin(), automation->rows().end(),
                                     [&lane](const AutomationRow &row) { return row.id == lane; });
                    check(laneRow != automation->rows().end(),
                          "automation lifecycle lane is unavailable");
                    if (laneRow != automation->rows().end()) {
                        const EditorViewState lifecycleViewState = view.editorViewState();
                        const int rowIndex =
                            int(std::distance(automation->rows().begin(), laneRow));
                        const int rowHeight = layout::fontPx(4.0);
                        const qreal rowY = qreal(rowIndex * rowHeight + rowHeight / 2);
                        const QPointF automationPoint(layout::fontPx(17.5 + 13.0 / 3.0), rowY);
                        const auto beginAutomation = [&](Qt::MouseButton button,
                                                         Qt::KeyboardModifiers modifiers,
                                                         qreal xOffset) {
                            view.setDrawerActivePage(EditorDrawerPage::Automations);
                            view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
                            checks::events::sendMouse(*automation, QEvent::MouseButtonPress,
                                                      automationPoint + QPointF(xOffset, 0.0),
                                                      button, Qt::MouseButtons(button), modifiers);
                            checks::events::sendMouse(
                                *automation, QEvent::MouseMove,
                                automationPoint + QPointF(xOffset + 32.0, 12.0), Qt::NoButton,
                                Qt::MouseButtons(button), modifiers);
                        };
                        const auto beginVelocity = [&](Qt::MouseButton button,
                                                       const QPointF &position) {
                            view.setDrawerActivePage(EditorDrawerPage::Velocity);
                            view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
                            view.selectTrack(noteTrack);
                            const auto live = document->notesForTrack(noteTrack);
                            view.selectionModel().setNoteSelection(
                                {live[0].noteId, live[1].noteId});
                            QCoreApplication::processEvents();
                            checks::events::sendMouse(*velocity, QEvent::MouseButtonPress, position,
                                                      button, Qt::MouseButtons(button),
                                                      Qt::NoModifier);
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
                                check(!view.userGestureActive(),
                                      "lifecycle check must begin without an active gesture");
                                begin();
                                const bool interactionStarted = view.userGestureActive();
                                const std::vector<NoteId> selection =
                                    view.selectionModel().noteSelection();
                                const std::vector<NoteId> expectedSelection =
                                    clearsSelection ? std::vector<NoteId>{} : selection;
                                cancel();
                                const bool interactionTerminated = !view.userGestureActive();
                                checks::events::sendMouse(surface, QEvent::MouseButtonRelease,
                                                          release, button, Qt::NoButton,
                                                          Qt::NoModifier);
                                QCoreApplication::processEvents();
                                const bool previewCleared = std::none_of(
                                    selection.begin(), selection.end(),
                                    [thisView = &view](const NoteId id) {
                                        return thisView->previewVelocity(id).has_value();
                                    });
                                check(interactionStarted && interactionTerminated &&
                                          document->smf().write() == midi &&
                                          document->revision() == revision &&
                                          document->undoStack()->count() == undo &&
                                          previewCleared &&
                                          view.selectionModel().noteSelection() ==
                                              expectedSelection &&
                                          QWidget::mouseGrabber() != &surface &&
                                          surface.cursor().shape() != Qt::ClosedHandCursor,
                                      route);
                                view.setSong(session->timeline.get(), session->voicegroup);
                                view.setDocument(document);
                                view.setVoicegroup(session->voicegroup);
                                view.applyEditorViewState(lifecycleViewState);
                                view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
                                view.selectTrack(noteTrack);
                                view.selectionModel().setNoteSelection(selection);
                            };
                            exercise(
                                "page switch did not terminate the live gesture",
                                [&] {
                                    view.setDrawerActivePage(view.drawerActivePage() ==
                                                                     EditorDrawerPage::Velocity
                                                                 ? EditorDrawerPage::Automations
                                                                 : EditorDrawerPage::Velocity);
                                },
                                false);
                            exercise(
                                "drawer hide did not terminate the live gesture",
                                [&] {
                                    view.setDrawerSectionVisible(view.drawerActivePage(), false);
                                },
                                false);
                            exercise(
                                "selected-track replacement did not terminate the live gesture",
                                [&] { view.selectTrack(noteTrack == 0 ? 1 : 0); }, true);
                            exercise(
                                "song replacement did not terminate the live gesture",
                                [&] { view.setSong(nullptr, nullptr); }, true);
                            exercise(
                                "document replacement did not terminate the live gesture",
                                [&] { view.setDocument(nullptr); }, true);
                            LoadedVoiceGroup replacementVoicegroup{};
                            exercise(
                                "voice replacement did not terminate the live gesture",
                                [&] { view.setVoicegroup(&replacementVoicegroup); }, false);
                            exercise(
                                "mouse-grab loss did not terminate the live gesture",
                                [&] {
                                    QEvent event(QEvent::UngrabMouse);
                                    QApplication::sendEvent(&view, &event);
                                },
                                false);
                            exercise(
                                "window deactivation did not terminate the live gesture",
                                [&] {
                                    QEvent event(QEvent::WindowDeactivate);
                                    QApplication::sendEvent(&view, &event);
                                },
                                false);
                            exercise(
                                "Escape did not terminate the live gesture",
                                [&] {
                                    checks::events::sendKey(view, QEvent::KeyPress, Qt::Key_Escape,
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
                            velocityNodePosition(view, *velocity, *session->timeline, live[0]);
                        verifyTermination(*velocity, Qt::LeftButton,
                                          velocityPoint + QPointF(32, -24),
                                          [&] { beginVelocity(Qt::LeftButton, velocityPoint); });
                        verifyTermination(
                            *velocity, Qt::LeftButton,
                            QPointF(velocity->plotOrigin() + velocity->plotWidth() - 4, 8), [&] {
                                beginVelocity(
                                    Qt::LeftButton,
                                    QPointF(velocity->plotOrigin() + velocity->plotWidth() - 36,
                                            8));
                            });
                        verifyTermination(*velocity, Qt::RightButton,
                                          velocityPoint + QPointF(32, -24),
                                          [&] { beginVelocity(Qt::RightButton, velocityPoint); });
                        const auto startVelocityRelative = [&] {
                            beginVelocity(Qt::LeftButton, velocityPoint);
                        };
                        const auto releaseVelocityRelative = [&] {
                            checks::events::sendMouse(*velocity, QEvent::MouseButtonRelease,
                                                      velocityPoint + QPointF(32, -24),
                                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
                            QCoreApplication::processEvents();
                        };
                        const std::vector<NoteId> selectionBeforeMutation =
                            view.selectionModel().noteSelection();
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
                                  !view.previewVelocity(mutationNote.noteId) &&
                                  view.selectionModel().noteSelection() == selectionBeforeMutation,
                              "document mutation did not terminate and clear the staged velocity "
                              "preview");
                        document->undoStack()->undo();

                        const int undoIndex = document->undoStack()->index();
                        startVelocityRelative();
                        document->undoStack()->undo();
                        check(document->undoStack()->index() == undoIndex - 1 &&
                                  !view.previewVelocity(mutationNote.noteId) &&
                                  view.selectionModel().noteSelection() == selectionBeforeMutation,
                              "Undo did not terminate and clear the staged velocity preview");
                        document->undoStack()->redo();
                        document->undoStack()->undo();
                        const int redoIndex = document->undoStack()->index();
                        startVelocityRelative();
                        document->undoStack()->redo();
                        releaseVelocityRelative();
                        check(document->undoStack()->index() == redoIndex + 1 &&
                                  !view.previewVelocity(mutationNote.noteId) &&
                                  view.selectionModel().noteSelection() == selectionBeforeMutation,
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
                        view.setDocument(nullptr);
                        const bool reloaded =
                            reloadSong && document->load(*reloadSong, &reloadError);
                        releaseVelocityRelative();
                        if (reloaded) {
                            session->timeline =
                                document->buildTimeline(window.m_audio.sampleRate());
                            window.attachEngine(*session);
                            view.setSong(session->timeline.get(), session->voicegroup);
                            view.setDocument(document);
                        }
                        check(reloaded && !view.previewVelocity(mutationNote.noteId) &&
                                  view.selectionModel().noteSelection().empty(),
                              "reload did not terminate and clear the staged velocity preview");
                    }
                    document->undoStack()->undo();
                }
            }
            if (!screenshotPath.isEmpty())
                check(window.grab().save(screenshotPath),
                      "could not save host integration screenshot");
        }
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
        SongView &songBView = window.m_workspace->viewFor(*songBSession);
        EditorViewState replacementFixture = songBView.editorViewState();
        replacementFixture.laneHeight = 53;
        replacementFixture.laneHeights.emplace(replacementLane, 61);
        replacementFixture.laneRanges.emplace(replacementLane, 100);
        replacementFixture.emptyLanes.emplace(replacementLane);
        songBView.applyEditorViewState(replacementFixture);
        QCoreApplication::processEvents();
        const EditorViewState replacementState = songBView.editorViewState();
        const QString replacementMidiPath = songBSession->doc.midPath();
        const QByteArray replacementMidi = fileContents(replacementMidiPath);
        window.closeSession(*songASession);
        window.loadSongByLabel(songA);
        ViewSidecar::Snapshot replacedSnapshot;
        check(window.m_active && window.m_active->doc.label() == songA &&
                  ViewSidecar::load(scratchProject, songB, &replacedSnapshot) &&
                  sameLaneState(replacedSnapshot.editor, replacementState) &&
                  fileContents(replacementMidiPath) == replacementMidi,
              "song replacement did not save the outgoing lane view state");

        SongSession *replacement = window.m_active;
        if (replacement) {
            SongView &replacementView = window.m_workspace->viewFor(*replacement);
            replacementView.setDrawerActivePage(EditorDrawerPage::Velocity);
            replacementView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
            replacementView.setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
            const EditorViewState projectSwitchState = replacementView.editorViewState();
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
                SongView &closingView = window.m_workspace->viewFor(*closing);
                closingView.setDrawerActivePage(EditorDrawerPage::Velocity);
                closingView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
                closingView.setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
                const EditorViewState closeState = closingView.editorViewState();
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
