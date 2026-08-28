#include <QAction>
#include <QApplication>
#include <QClipboard>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QEvent>
#include <QEventLoop>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QKeySequence>
#include <QLineEdit>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QMouseEvent>
#include <QPixmap>
#include <QPointer>
#include <QScrollArea>
#include <QScrollBar>
#include <QSettings>
#include <QStatusBar>
#include <QTimer>
#include <QUndoStack>
#include <QWidget>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <optional>
#include <vector>

#include "checks/clipcheck_support.h"
#include "checks/support/asyncwait.h"
#include "checks/support/eventsynth.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "mainwindow.h"
#include "project/projectidentity.h"
#include "project/sidecar.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songtab.h"
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
QJsonObject readJsonObject(const QString &path)
{
    const QJsonDocument document = QJsonDocument::fromJson(fileContents(path));
    return document.isObject() ? document.object() : QJsonObject{};
}

bool writeJsonObject(const QString &path, const QJsonObject &object)
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    return file.write(QJsonDocument(object).toJson()) >= 0;
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

// Awaits a tab's terminal payload while it stays open; readiness is the one
// observable that MidiStage, SidecarStage, and VoicegroupBound all landed.
bool waitForTabReady(const WorkspaceUi &workspace, SongTab *tab, const char *what)
{
    const auto isLive = [&workspace, tab] {
        return tab && workspace.songTabFor(tab->name()) == tab;
    };
    if (!isLive()) {
        std::fprintf(stderr,
                     "song-load wait failed: %s tab was destroyed before its terminal payload\n",
                     what);
        return false;
    }
    if (tab->isReady())
        return true;
    const auto result = checks::async_wait::waitUntil(isLive, [tab] { return tab->isReady(); });
    if (result == checks::async_wait::Result::Destroyed || !isLive()) {
        std::fprintf(stderr,
                     "song-load wait failed: %s tab was destroyed before its terminal payload\n",
                     what);
        return false;
    }
    if (result == checks::async_wait::Result::TimedOut) {
        std::fprintf(stderr, "song-load wait failed: %s timed out before its terminal payload\n",
                     what);
        return false;
    }
    return true;
}

// Awaits the workspace's Ready publication (the request itself returns while
// the open is still in flight).
bool waitForProjectReady(const WorkspaceUi &workspace)
{
    return checks::async_wait::waitUntil(
               [] { return true; },
               [&workspace] { return workspace.projectState().state == ProjectOpenState::Ready; },
               30000, 1) == checks::async_wait::Result::Ready;
}

} // namespace

bool MainWindow::runMainWindowRoutingCheck(const QString &projectRoot, const QString &songA,
                                           const QString &songB)
{
    if (!m_audioOk) {
        std::fprintf(stderr, "mainwindow-routing: no audio device available\n");
        return false;
    }
    const std::optional<SongName> nameA = SongName::create(songA);
    const std::optional<SongName> nameB = SongName::create(songB);
    if (!nameA || !nameB) {
        std::fprintf(stderr, "mainwindow-routing: song labels were rejected as identities\n");
        return false;
    }
    m_workspace->requestProjectOpenAt(projectRoot);
    if (!waitForProjectReady(*m_workspace)) {
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
    m_workspace->requestSongOpen(*nameA);
    SongTab *const tabA = m_workspace->songTabFor(*nameA);
    m_workspace->requestSongOpen(*nameB, /*newTab=*/true);
    SongTab *const tabB = m_workspace->selectedSongTab();
    if (!tabA || !tabB || tabA == tabB || m_workspace->openTabCount() != 2) {
        std::fprintf(stderr, "mainwindow-routing: songs did not open in two tabs\n");
        return false;
    }
    if (!waitForTabReady(*m_workspace, tabA, "mainwindow-routing song A") ||
        !waitForTabReady(*m_workspace, tabB, "mainwindow-routing song B")) {
        hide();
        return false;
    }
    SongView &tabAView = tabA->view();
    SongView &tabBView = tabB->view();
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
    tabATimeSelection.endTick = tabA->timeline()->ticksPerBeat;
    tabAView.selectionModel().setTimeSelection(tabATimeSelection);
    auto tabBNote = std::optional<DocNote>{};
    for (int track = 0; track < tabB->document().engineTrackCount() && !tabBNote; ++track) {
        const auto notes = tabB->document().notesForTrack(track);
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
            noteCopy && noteCopy->ticksPerBeat == tabB->timeline()->ticksPerBeat &&
            noteCopy->clip.span == 0 && noteCopy->clip.tracks.size() == 1 &&
            noteCopy->clip.tracks.front().notes.size() == 1 &&
            noteCopy->clip.tracks.front().notes.front().key == tabBNote->key &&
            noteCopy->clip.tracks.front().notes.front().velocity == tabBNote->velocity;
        check(copiedSelectedNote, "Copy action did not route to the active tab's selected note");
        m_workspace->selectSongTab(tabA);
        QCoreApplication::processEvents();
        copyAction->trigger();
        const auto timeCopy = clipcheck_support::checkClipboardClip();
        check(timeCopy && timeCopy->ticksPerBeat == tabA->timeline()->ticksPerBeat &&
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
        m_workspace->selectSongTab(tabB);
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
    m_workspace->selectSongTab(tabA);
    m_workspace->selectSongTab(tabB);
    QCoreApplication::processEvents();
    QWidget *focusAfterTabSwitch = QApplication::focusWidget();
    check(focusAfterTabSwitch &&
              (focusAfterTabSwitch == &tabBView || tabBView.isAncestorOf(focusAfterTabSwitch)) &&
              focusAfterTabSwitch->focusPolicy() != Qt::NoFocus,
          "tab switch did not request active content focus");
    check(m_workspace->selectedSongTab() == tabB &&
              tabBView.drawerActivePage() == EditorDrawerPage::Velocity &&
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

    const QString sidecarPath = ViewSidecar::pathFor(projectRoot, songB);
    check(Sidecar::ensureDir(projectRoot),
          "could not create sidecar directory for persistence test");
    QJsonObject seededSidecar = readJsonObject(sidecarPath);
    seededSidecar.insert(QStringLiteral("registration"),
                         QJsonObject{{QStringLiteral("pending"), true}});
    check(writeJsonObject(sidecarPath, seededSidecar),
          "could not seed an unrelated sidecar key for persistence test");
    const QByteArray sidecarBefore = fileContents(sidecarPath);
    const QByteArray midiBefore = tabB->document().smf().write();
    const uint64_t revisionBefore = tabB->document().revision();
    const int undoBefore = tabB->view().document()->undoStack()->count();
    tabBView.setDrawerActivePage(EditorDrawerPage::Velocity);
    tabBView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    tabBView.setDrawerSectionHeight(EditorDrawerPage::Velocity, retainedHeight);
    QCoreApplication::processEvents();
    const EditorViewState expectedCosmetics = tabBView.editorViewState();
    check(tabB->document().smf().write() == midiBefore &&
              tabB->document().revision() == revisionBefore &&
              tabB->view().document()->undoStack()->count() == undoBefore &&
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
    m_workspace->requestCloseSelectedTab(); // tabB is selected and clean
    check(m_workspace->openTabCount() == 1 && m_workspace->songTabFor(*nameB) == nullptr,
          "tab close did not synchronously detach the clean session");
    // The replacement's sidecar read is queued after the close's sidecar write
    // on ProjectIo, so waiting for readiness is the write barrier.
    m_workspace->requestSongOpen(*nameB, /*newTab=*/true);
    SongTab *reopened = m_workspace->songTabFor(*nameB);
    check(reopened != nullptr, "reopened song did not create its tab immediately");
    const bool reopenedReady =
        reopened && waitForTabReady(*m_workspace, reopened, "mainwindow-routing reopened song B");
    SongView *reopenedView = reopened ? &reopened->view() : nullptr;
    ViewSidecar::Snapshot savedSnapshot;
    const bool savedSnapshotLoaded = ViewSidecar::load(projectRoot, songB, &savedSnapshot);
    const QJsonObject savedSidecar = readJsonObject(sidecarPath);
    check(reopenedReady && savedSnapshotLoaded && savedSnapshot.view.valid &&
              savedSnapshot.editor.drawerState() == EditorDrawerState{} &&
              sameLaneState(savedSnapshot.editor, expectedCosmetics) &&
              savedSidecar.value(QStringLiteral("registration"))
                  .toObject()
                  .value(QStringLiteral("pending"))
                  .toBool(),
          "tab close did not flush song-specific state or preserve unrelated sidecar keys");
    check(reopenedReady && reopened && m_workspace->songTabFor(*nameB) == reopened &&
              reopenedView && reopenedView->drawerSectionVisible(EditorDrawerPage::Velocity) &&
              reopenedView->drawerActivePage() == EditorDrawerPage::Velocity &&
              reopenedView->drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight &&
              reopenedView->editorViewState().drawerState() == m_editorDrawerState &&
              sameLaneState(reopenedView->editorViewState(), expectedCosmetics),
          "reopened tab did not restore sidecar lanes with application drawer chrome");
    // 12. A failed project open must not tear down an old tab whose
    // asynchronous reload is already queued. FIFO ordering also leaves the
    // reload to finish after the failed open.
    SongTab *const oldTab = m_workspace->selectedSongTab();
    const qsizetype oldTabCount = m_workspace->openTabCount();
    const QString oldLabel = oldTab ? oldTab->document().label() : QString();
    const bool oldTabOk = oldTab && !oldTab->document().isDirty();
    check(oldTabOk, "failed-open precondition did not leave a clean old tab");
    if (oldTabOk) {
        // Re-activating the selected tab's own song queues the in-place
        // reload whose staged updates must survive the failed open.
        m_workspace->requestSongOpen(*nameB);
        const QString invalidRoot =
            projectRoot + QStringLiteral("/mainwindow-routing-invalid-project");
        m_workspace->requestProjectOpenAt(invalidRoot);
        // The interactive open policy reports the failure with a modal
        // warning; dismiss it while awaiting the Failed publication.
        const auto failed = [&] {
            if (auto *box = qobject_cast<QMessageBox *>(QApplication::activeModalWidget()))
                box->close();
            return m_workspace->projectState().state == ProjectOpenState::Failed;
        };
        const auto openResult =
            checks::async_wait::waitUntil([] { return true; }, failed, 30000, 1);
        check(openResult == checks::async_wait::Result::Ready &&
                  m_workspace->projectState().state == ProjectOpenState::Failed,
              "invalid project open unexpectedly succeeded or did not fail");
        const bool oldLive = oldTab && m_workspace->selectedSongTab() == oldTab &&
                             m_workspace->openTabCount() == oldTabCount &&
                             m_workspace->projectState().snapshot.root() == projectRoot;
        check(oldLive, "failed project open destroyed or switched away from the old tab");
        if (oldLive) {
            const bool oldReady = waitForTabReady(*m_workspace, oldTab, "failed-open old tab");
            check(oldReady && oldTab->document().label() == oldLabel && oldTab->view().isEnabled(),
                  "old tab did not remain interactive after failed project open");
        }
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
    const std::optional<SongName> nameA = SongName::create(songA);
    const std::optional<SongName> nameB = SongName::create(songB);
    check(nameA && nameB, "fixture song labels were rejected as identities");
    if (nameA && nameB) {
        window.m_workspace->requestProjectOpenAt(scratchProject);
        check(waitForProjectReady(*window.m_workspace), "project failed to open");
    }
    if (failures) {
        window.hide();
        return 1;
    }
    window.resize(960, 680);
    window.show();
    QCoreApplication::processEvents();
    window.m_workspace->requestSongOpen(*nameA);
    SongTab *initialA = window.m_workspace->songTabFor(*nameA);
    window.m_workspace->requestSongOpen(*nameB, /*newTab=*/true);
    SongTab *session = window.m_workspace->selectedSongTab();
    check(initialA && session && session != initialA,
          "MainWindow flow did not create two distinct song tabs immediately");
    const bool initialAReady =
        initialA && waitForTabReady(*window.m_workspace, initialA, "host-integration song A");
    check(initialAReady,
          "song A timed out or its tab was destroyed before MIDI and voicegroup binding");
    const bool sessionReady =
        session && session != initialA &&
        waitForTabReady(*window.m_workspace, session, "host-integration song B");
    check(sessionReady, "MainWindow flow did not leave an attached ready tab and timeline");
    if (sessionReady) {
        SongView &view = session->view();
        SongDocument *document = view.document();
        check(document, "MainWindow flow did not leave an attached ready tab and timeline");
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
                            session->timeline()->sampleForTick(candidate + offset);
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
                    view.setPlayheadSample(session->timeline()->sampleForTick(firstTick), true);
                    QCoreApplication::processEvents();
                    const auto automationBefore = automation->diagnostics();
                    const auto velocityBefore = velocity->diagnostics();
                    for (uint64_t tick = firstTick + 1; tick <= finalTick; ++tick)
                        view.setPlayheadSample(session->timeline()->sampleForTick(tick), true);
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
                                view.setSong(session->timeline().get(),
                                             session->voicegroupLease().get());
                                view.setDocument(document);
                                view.setVoicegroup(session->voicegroupLease().get());
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
                            velocityNodePosition(view, *velocity, *session->timeline(), live[0]);
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

                        // Re-activating the selected tab's own song is the
                        // production in-place reload: its staged Midi
                        // replacement must terminate the live gesture and
                        // clear the staged preview.
                        document->undoStack()->undo(); // the reload needs a clean tab
                        startVelocityRelative();
                        const SongName reloadName = session->name();
                        window.m_workspace->requestSongOpen(reloadName);
                        const auto reloadLanded = [&] {
                            const SongTab *const liveTab =
                                window.m_workspace->songTabFor(reloadName);
                            return liveTab == session && session->isReady() &&
                                   document->undoStack()->count() == 0;
                        };
                        const bool reloaded =
                            checks::async_wait::waitUntil([] { return true; }, reloadLanded, 15000,
                                                          1) == checks::async_wait::Result::Ready;
                        const bool tabLive = window.m_workspace->songTabFor(reloadName) == session;
                        if (tabLive)
                            releaseVelocityRelative();
                        const bool gestureCleared = tabLive &&
                                                    !view.previewVelocity(mutationNote.noteId) &&
                                                    view.selectionModel().noteSelection().empty();
                        check(reloaded && gestureCleared,
                              "reload did not terminate and clear the staged velocity preview");
                    }
                }
            }
            if (!screenshotPath.isEmpty())
                check(window.grab().save(screenshotPath),
                      "could not save host integration screenshot");
        }
    }

    SongTab *const songATab = window.m_workspace->songTabFor(*nameA);
    SongTab *const songBTab = window.m_workspace->selectedSongTab();
    check(songATab && songBTab && songATab != songBTab,
          "host integration did not retain distinct tabs for persistence boundaries");
    if (songATab && songBTab && songATab != songBTab) {
        const EditorAutomationRowId replacementLane{EditorAutomationRowKind::ControlChange, 0, 74};
        const auto sameLaneState = [](const EditorViewState &first, const EditorViewState &second) {
            return first.laneHeight == second.laneHeight &&
                   first.laneHeights == second.laneHeights &&
                   first.laneRanges == second.laneRanges && first.emptyLanes == second.emptyLanes &&
                   first.hiddenLanes() == second.hiddenLanes();
        };
        SongView &songBView = songBTab->view();
        EditorViewState replacementFixture = songBView.editorViewState();
        replacementFixture.laneHeight = 53;
        replacementFixture.laneHeights.emplace(replacementLane, 61);
        replacementFixture.laneRanges.emplace(replacementLane, 100);
        replacementFixture.emptyLanes.emplace(replacementLane);
        songBView.applyEditorViewState(replacementFixture);
        QCoreApplication::processEvents();
        const EditorViewState replacementState = songBView.editorViewState();
        const QString replacementMidiPath = songBTab->document().midPath();
        const QByteArray replacementMidi = fileContents(replacementMidiPath);
        window.m_workspace->selectSongTab(songATab);
        window.m_workspace->requestCloseSelectedTab(); // songATab is selected and clean
        window.m_workspace->requestSongOpen(*nameA);
        SongTab *replacement = window.m_workspace->selectedSongTab();
        check(replacement != nullptr, "song replacement did not create its tab immediately");
        const bool replacementReady =
            replacement &&
            waitForTabReady(*window.m_workspace, replacement, "host-integration replacement");
        check(replacementReady,
              "song replacement timed out or its tab was destroyed before MIDI and voicegroup "
              "binding");
        if (!replacementReady)
            replacement = nullptr;
        ViewSidecar::Snapshot replacedSnapshot;
        check(replacementReady && replacement &&
                  window.m_workspace->selectedSongTab() == replacement &&
                  replacement->document().label() == songA &&
                  ViewSidecar::load(scratchProject, songB, &replacedSnapshot) &&
                  sameLaneState(replacedSnapshot.editor, replacementState) &&
                  fileContents(replacementMidiPath) == replacementMidi,
              "song replacement did not save the outgoing lane view state");
        if (replacement) {
            SongView &replacementView = replacement->view();
            replacementView.setDrawerActivePage(EditorDrawerPage::Velocity);
            replacementView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
            replacementView.setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
            const EditorViewState projectSwitchState = replacementView.editorViewState();
            const QString projectSwitchMidiPath = replacement->document().midPath();
            const QByteArray projectSwitchMidi = fileContents(projectSwitchMidiPath);
            window.m_workspace->requestProjectOpenAt(scratchProject);
            check(waitForProjectReady(*window.m_workspace) &&
                      window.m_workspace->openTabCount() == 0,
                  "project switch failed");
            ViewSidecar::Snapshot projectSwitchSnapshot;
            check(ViewSidecar::load(scratchProject, songA, &projectSwitchSnapshot) &&
                      sameLaneState(projectSwitchSnapshot.editor, projectSwitchState) &&
                      fileContents(projectSwitchMidiPath) == projectSwitchMidi,
                  "project switch did not save song-specific lane view state");

            window.m_workspace->requestSongOpen(*nameA);
            SongTab *closing = window.m_workspace->selectedSongTab();
            check(closing, "project switch did not permit a fresh attached tab");
            const bool closingReady = closing && waitForTabReady(*window.m_workspace, closing,
                                                                 "host-integration project switch");
            check(closingReady,
                  "project switch song timed out or its tab was destroyed before MIDI and "
                  "voicegroup binding");
            if (!closingReady)
                closing = nullptr;
            if (closing) {
                SongView &closingView = closing->view();
                closingView.setDrawerActivePage(EditorDrawerPage::Velocity);
                closingView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
                closingView.setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
                const EditorViewState closeState = closingView.editorViewState();
                const QByteArray midiBeforeClose = closing->document().smf().write();
                const QString closeMidiPath = closing->document().midPath();
                const QByteArray closeMidi = fileContents(closeMidiPath);
                const int undoBeforeClose = closingView.document()->undoStack()->count();

                window.m_workspace->requestSongOpen(*nameB, /*newTab=*/true);
                SongTab *closingB = window.m_workspace->selectedSongTab();
                check(closingB && closingB != closing,
                      "multi-tab shutdown did not create a second tab");
                const bool closingBReady = closingB && closingB != closing &&
                                           waitForTabReady(*window.m_workspace, closingB,
                                                           "host-integration multi-tab shutdown");
                check(closingBReady,
                      "multi-tab shutdown song timed out before MIDI and voicegroup binding");
                EditorViewState closeBState;
                QByteArray midiBeforeCloseB;
                QString closeMidiPathB;
                QByteArray closeMidiB;
                int undoBeforeCloseB = -1;
                if (closingBReady && closingB) {
                    SongView &closingBView = closingB->view();
                    closingBView.setDrawerActivePage(EditorDrawerPage::Velocity);
                    closingBView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
                    closingBView.setDrawerSectionHeight(EditorDrawerPage::Velocity, 191);
                    closeBState = closingBView.editorViewState();
                    midiBeforeCloseB = closingB->document().smf().write();
                    closeMidiPathB = closingB->document().midPath();
                    closeMidiB = fileContents(closeMidiPathB);
                    undoBeforeCloseB = closingBView.document()->undoStack()->count();
                }

                window.close();
                QElapsedTimer closeDeadline;
                closeDeadline.start();
                while (!window.m_closeAccepted && closeDeadline.elapsed() < 30000)
                    QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
                check(window.m_closeAccepted, "application close boundary was rejected");
                ViewSidecar::Snapshot closeSnapshot;
                ViewSidecar::Snapshot closeSnapshotB;
                check(closing->document().smf().write() == midiBeforeClose &&
                          fileContents(closeMidiPath) == closeMidi &&
                          closingView.document()->undoStack()->count() == undoBeforeClose &&
                          ViewSidecar::load(scratchProject, songA, &closeSnapshot) &&
                          sameLaneState(closeSnapshot.editor, closeState) &&
                          (!closingBReady ||
                           (closingB && closingB->document().smf().write() == midiBeforeCloseB &&
                            fileContents(closeMidiPathB) == closeMidiB &&
                            closingB->view().document()->undoStack()->count() == undoBeforeCloseB &&
                            ViewSidecar::load(scratchProject, songB, &closeSnapshotB) &&
                            sameLaneState(closeSnapshotB.editor, closeBState))),
                      "multi-tab application close did not flush all song view states");
            }
        }
    }
    window.hide();
    std::printf("host-integration: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0 ? 0 : 1;
}
