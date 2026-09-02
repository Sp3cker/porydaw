#include <QAction>
#include <QApplication>
#include <QClipboard>
#include <QCloseEvent>
#include <QCoreApplication>
#include <QDialog>
#include <QDir>
#include <QElapsedTimer>
#include <QEvent>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QKeyEvent>
#include <QKeySequence>
#include <QLineEdit>
#include <QList>
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
#include <QTabBar>
#include <QTimer>
#include <QUndoStack>
#include <QWidget>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <functional>
#include <limits>
#include <map>
#include <memory>
#include <optional>
#include <vector>

#include "checks/clipcheck_support.h"
#include "checks/support/asyncwait.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "mainwindow.h"
#include "project/projectidentity.h"
#include "project/sidecar.h"
#include "ui/dragspinbox.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songtab.h"
#include "ui/songview/clipmime.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
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
                     double(note.tick) * view.camera().pxPerBeat() / double(timeline.ticksPerBeat) -
                     view.camera().scrollX();
    return {x, area.axis().velocityToY(note.velocity)};
}

// Awaits a tab's terminal payload while it stays open; readiness is the one
// observable that MidiStage and the terminal VoicegroupBound both landed.
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

// The native-smoke entry gate: on real Cocoa the window server makes the
// process frontmost asynchronously after show() (external LaunchServices
// activation), so repeatedly request activation while pumping events until
// the window is genuinely active instead of racing the first keyboard
// scenario. Offscreen platforms are active immediately.
bool waitForNativeActivation(QWidget &window)
{
    return checks::async_wait::waitUntil([] { return true; },
                                         [&window] {
                                             window.activateWindow();
                                             window.raise();
                                             return window.isActiveWindow();
                                         },
                                         5000) == checks::async_wait::Result::Ready;
}

// A byte snapshot of every file under the project's .porydaw directory.
// Boundary checks require listing and byte identity: nothing under the
// directory may appear, vanish, or change across close, reload, switch,
// and quit.
std::map<QString, QByteArray> porydawSnapshot(const QString &projectRoot)
{
    std::map<QString, QByteArray> snapshot;
    const std::function<void(const QString &, const QString &)> visit =
        [&snapshot, &visit](const QString &dir, const QString &prefix) {
            const QDir entries(dir);
            for (const QFileInfo &entry :
                 entries.entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot)) {
                const QString relative = prefix.isEmpty()
                                             ? entry.fileName()
                                             : prefix + QLatin1Char('/') + entry.fileName();
                if (entry.isDir())
                    visit(entry.absoluteFilePath(), relative);
                else
                    snapshot.emplace(relative, fileContents(entry.absoluteFilePath()));
            }
        };
    const QString root = Sidecar::dirPath(projectRoot);
    if (QDir(root).exists())
        visit(root, QString());
    return snapshot;
}

// The canonical fresh ViewState is the default-constructed value (the
// Geometry defaults) with both scroll axes at resetScrollPosition()'s home;
// asserting the identity of a second reset pins the scroll defaults too.
bool freshViewStateAtCanonicalDefaults(SongView &view, const MidiTimeline &timeline)
{
    const SongView::ViewState defaults;
    const SongView::ViewState landed = view.viewState();
    if (!landed.valid || !qFuzzyCompare(landed.pxPerBeat, defaults.pxPerBeat) ||
        !qFuzzyCompare(landed.keyHeight, defaults.keyHeight) || landed.editCursorTick != 0 ||
        landed.gridMinDenom != 0 || landed.gridTriplet || landed.eventList)
        return false;
    int firstUsedTrack = 0;
    for (int track = 0; track < 16; ++track) {
        if (timeline.tracks[track].used) {
            firstUsedTrack = track;
            break;
        }
    }
    if (landed.selectedTrack != firstUsedTrack)
        return false;
    view.resetScrollPosition();
    const SongView::ViewState reset = view.viewState();
    return landed.scrollPx == reset.scrollPx && landed.scrollY == reset.scrollY;
}

// Row A: a fresh bind keeps the complete global editor projection and lands
// the canonical fresh ViewState defaults; readiness waits for the terminal
// VoicegroupBound.
template <class Check>
void checkFreshBind(const WorkspaceUi &workspace, const SongName &name,
                    const VoicegroupId *probeIdentity, const EditorViewState &globalState,
                    Check &&check)
{
    const auto &songs = workspace.projectState().snapshot.songs();
    const auto song = std::find_if(songs.cbegin(), songs.cend(), [&name](const SongInfo &info) {
        return info.label == name.value();
    });
    auto smf = SmfFile{};
    QString smfError;
    const bool readable = song != songs.cend() && SmfFile::readFile(song->midPath, &smf, &smfError);
    check(readable, "fresh-bind probe could not read the song's MIDI");
    check(probeIdentity != nullptr, "fresh-bind probe has no terminal voicegroup identity");
    if (!readable || !probeIdentity)
        return;
    const int budget = workspace.projectState().snapshot.trackBudgetFor(*song);
    SongTab probe(name);
    probe.view().applyEditorViewState(globalState); // what createTab does for a future tab
    check(!probe.isReady() && probe.view().isEnabled(),
          "the fresh tab did not start not ready with its presentation enabled");
    probe.applyMidiStage(*song, smf, budget);
    check(!probe.isReady() && probe.view().timeline() != nullptr &&
              probe.view().document() == &probe.document(),
          "MidiStage alone did not swap the binding while withholding readiness");
    check(probe.view().isEnabled(),
          "MidiStage disabled the SongView presentation while readiness was withheld");
    check(probe.view().editorViewState() == globalState,
          "the fresh bind did not keep every complete global editor field");
    check(freshViewStateAtCanonicalDefaults(probe.view(), *probe.view().timeline()),
          "the fresh bind did not establish every canonical view default");
    probe.applyVoicegroupBound(*probeIdentity);
    check(probe.isReady() && probe.view().isEnabled(),
          "readiness did not wait for the terminal VoicegroupBound");
}

// Field equality over the complete transient ViewState: capture and
// reapplication are value-exact, so retention compares values.
bool sameViewState(const SongView::ViewState &a, const SongView::ViewState &b)
{
    return a.valid == b.valid && a.pxPerBeat == b.pxPerBeat && a.keyHeight == b.keyHeight &&
           a.scrollPx == b.scrollPx && a.scrollY == b.scrollY &&
           a.selectedTrack == b.selectedTrack && a.editCursorTick == b.editCursorTick &&
           a.gridMinDenom == b.gridMinDenom && a.gridTriplet == b.gridTriplet &&
           a.eventList == b.eventList;
}

// A probe tab reaches readiness with a bank bound, seeds a distinctive
// transient state, then walks the staged full reload: readiness drops at
// the ReloadSongInput dispatch - before the replacement MidiStage - while
// the old timeline lease, voicegroup identity and lease, ruler camera, and
// complete ViewState stay live; MidiStage swaps the binding and restores
// the captured state while readiness is still withheld; the terminal
// VoicegroupBound restores readiness. readinessChanged must fire exactly
// once per derived transition.
template <class Check>
void checkStagedFullReload(const WorkspaceUi &workspace, const SongName &name,
                           const VoicegroupId *identity, Check &&check)
{
    const auto &songs = workspace.projectState().snapshot.songs();
    const auto song = std::find_if(songs.cbegin(), songs.cend(), [&name](const SongInfo &info) {
        return info.label == name.value();
    });
    auto initialStage = SmfFile{};
    auto replacementStage = SmfFile{};
    QString smfError;
    const bool readable = song != songs.cend() &&
                          SmfFile::readFile(song->midPath, &initialStage, &smfError) &&
                          SmfFile::readFile(song->midPath, &replacementStage, &smfError);
    check(readable, "staged-reload probe could not read the song's MIDI");
    check(identity != nullptr, "staged-reload probe has no bound voicegroup identity");
    if (!readable || !identity)
        return;
    const int budget = workspace.projectState().snapshot.trackBudgetFor(*song);
    // Declared before the probe so the borrowed bank outlives the view's
    // borrow.
    LoadedVoiceGroup probeBank{};
    SongTab probe(name);
    probe.applyMidiStage(*song, std::move(initialStage), budget);
    probe.applyBankView(LoadedBankView{*identity, borrowVoicegroupLease(&probeBank), QString()});
    probe.applyVoicegroupBound(*identity);
    check(probe.isReady() && probe.timeline() && probe.voicegroupLease().get() == &probeBank,
          "the staged-reload probe did not reach readiness with its bank bound");
    const MidiTimeline *const boundTimeline = probe.timeline().get();
    const VoicegroupId boundIdentity = *probe.voicegroupId();

    // A distinctive transient state makes the captured-state restoration
    // distinguishable from a reset to the canonical fresh defaults.
    const SongView::ViewState canonical = probe.view().viewState();
    SongView::ViewState distinctive;
    distinctive.valid = true;
    distinctive.pxPerBeat = canonical.pxPerBeat * 2.0;
    distinctive.keyHeight = canonical.keyHeight * 1.5;
    int alternateTrack = -1;
    for (int track = 0; track < 16 && alternateTrack < 0; ++track) {
        if (probe.timeline()->tracks[track].used && track != canonical.selectedTrack)
            alternateTrack = track;
    }
    if (alternateTrack >= 0)
        distinctive.selectedTrack = alternateTrack;
    distinctive.editCursorTick = probe.timeline()->ticksPerBeat * 4;
    distinctive.gridMinDenom = 16;
    distinctive.gridTriplet = true;
    probe.view().applyViewState(distinctive);
    const SongView::ViewState captured = probe.view().viewState();
    check(captured.pxPerBeat == distinctive.pxPerBeat &&
              captured.keyHeight == distinctive.keyHeight &&
              captured.editCursorTick == distinctive.editCursorTick &&
              captured.gridMinDenom == 16 && captured.gridTriplet &&
              (alternateTrack < 0 || captured.selectedTrack == alternateTrack),
          "the staged-reload seed did not land a distinctive transient state");

    const auto readinessChanges = std::make_shared<int>(0);
    const QMetaObject::Connection readinessSpy = QObject::connect(
        &probe, &SongTab::readinessChanged, [readinessChanges] { ++*readinessChanges; });

    // Dispatch: readiness drops here, before the replacement MidiStage,
    // while everything loaded stays exactly as it was.
    probe.beginMidiReload();
    check(!probe.isReady(), "the full reload stayed ready after its ReloadSongInput dispatch");
    check(probe.timeline().get() == boundTimeline,
          "the full reload dropped the old timeline lease before the replacement stage");
    check(sameViewState(probe.view().viewState(), captured),
          "the reload dispatch disturbed the retained ruler camera or complete view state");
    check(probe.view().isEnabled(),
          "the reload dispatch disabled the SongView presentation while readiness was withheld");
    check(probe.voicegroupId() && *probe.voicegroupId() == boundIdentity &&
              probe.voicegroupLease().get() == &probeBank,
          "the reload dispatch disturbed the old voicegroup identity or lease");
    check(*readinessChanges == 1,
          "the reload dispatch did not report exactly one readiness change");

    // Replacement stage: the binding swaps and the captured state is
    // restored while readiness stays withheld for the terminal stage.
    probe.applyMidiStage(*song, std::move(replacementStage), budget);
    check(!probe.isReady(), "the replacement MidiStage alone restored readiness");
    check(probe.timeline().get() != boundTimeline,
          "the replacement MidiStage did not swap the retained binding");
    check(sameViewState(probe.view().viewState(), captured),
          "the replacement MidiStage did not restore the captured view state");
    check(*readinessChanges == 1,
          "the replacement MidiStage reported a readiness change it did not derive");

    // Terminal stage.
    probe.applyVoicegroupBound(boundIdentity);
    check(probe.isReady() && probe.view().isEnabled(),
          "the staged reload did not restore readiness at the terminal VoicegroupBound");
    check(sameViewState(probe.view().viewState(), captured),
          "the terminal VoicegroupBound disturbed the restored view state");
    check(*readinessChanges == 2,
          "the staged reload did not report exactly one readiness change per transition");
}

// A bank-only voicegroup rebind moves just the bank binding: no load event
// is dispatched, so readiness never drops, the retained view state is never
// disturbed, and no readiness change is reported.
template <class Check>
void checkBankOnlyRebind(const WorkspaceUi &workspace, const SongName &name,
                         const VoicegroupId *identity, Check &&check)
{
    const auto &songs = workspace.projectState().snapshot.songs();
    const auto song = std::find_if(songs.cbegin(), songs.cend(), [&name](const SongInfo &info) {
        return info.label == name.value();
    });
    auto stage = SmfFile{};
    QString smfError;
    const bool readable =
        song != songs.cend() && SmfFile::readFile(song->midPath, &stage, &smfError);
    check(readable, "rebind probe could not read the song's MIDI");
    check(identity != nullptr, "rebind probe has no bound voicegroup identity");
    if (!readable || !identity)
        return;
    const int budget = workspace.projectState().snapshot.trackBudgetFor(*song);
    // Declared before the probe so the borrowed banks outlive the view's
    // borrow.
    LoadedVoiceGroup initialBank{};
    LoadedVoiceGroup replacementBank{};
    SongTab probe(name);
    probe.applyMidiStage(*song, std::move(stage), budget);
    probe.applyVoicegroupBound(*identity);
    probe.applyBankView(LoadedBankView{*identity, borrowVoicegroupLease(&initialBank), QString()});
    check(probe.isReady() && probe.voicegroupLease().get() == &initialBank,
          "the rebind probe did not reach readiness with its bank bound");
    const MidiTimeline *const boundTimeline = probe.timeline().get();
    const SongView::ViewState before = probe.view().viewState();
    const auto readinessChanges = std::make_shared<int>(0);
    const QMetaObject::Connection readinessSpy = QObject::connect(
        &probe, &SongTab::readinessChanged, [readinessChanges] { ++*readinessChanges; });

    // The refresh re-delivers the bank view and re-binds the same identity:
    // a bank replacement, not a load.
    probe.applyBankView(
        LoadedBankView{*identity, borrowVoicegroupLease(&replacementBank), QString()});
    probe.applyVoicegroupBound(*identity);
    check(probe.isReady() && probe.timeline().get() == boundTimeline,
          "the bank-only rebind entered the full MIDI loading state");
    check(probe.voicegroupLease().get() == &replacementBank,
          "the bank-only rebind did not move the bank binding");
    check(sameViewState(probe.view().viewState(), before),
          "the bank-only rebind disturbed the retained view state");
    check(*readinessChanges == 0, "the bank-only rebind reported a readiness change");
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
    if (QApplication::platformName() == QLatin1String("cocoa") && !waitForNativeActivation(*this)) {
        std::fprintf(stderr, "mainwindow-routing: native activation failed: the main window never "
                             "became active after show\n");
        return false;
    }
    m_workspace->requestSongOpen(*nameA);
    SongTab *const tabA = m_workspace->songTabFor(*nameA);
    m_workspace->requestSongOpen(*nameB, /*newTab=*/true);
    SongTab *const tabB = m_workspace->selectedSongTab();
    if (!tabA || !tabB || tabA == tabB || m_workspace->openTabCount() != 2) {
        std::fprintf(stderr, "mainwindow-routing: songs did not open in two tabs\n");
        return false;
    }
    // Fresh tabs start not ready and stay that way until both load stages
    // land; presentation stays enabled because input gating reads readiness.
    check(!tabA->isReady() && !tabB->isReady() && tabA->view().isEnabled() &&
              tabB->view().isEnabled(),
          "fresh tabs did not start not ready with their SongView presentation enabled");
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
    QAction *insertTimeAction = findChild<QAction *>(QStringLiteral("insertTimeWindowAction"));
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
    check(insertTimeAction && insertTimeAction == m_insertTimeAction &&
              insertTimeAction->parent() == this,
          "Insert Time action is missing or is not owned by MainWindow");
    check(editMenu && editMenu->actions().contains(insertTimeAction),
          "Insert Time action is not a member of the Edit menu");
    check(insertTimeAction &&
              insertTimeAction->shortcuts() == keys.bindings(QStringLiteral("edit.insert_time")) &&
              insertTimeAction->shortcutContext() == Qt::WindowShortcut,
          "Insert Time action does not carry its global window shortcut");
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
    m_workspace->selectSongTab(tabA);
    QCoreApplication::processEvents();
    m_workspace->selectSongTab(tabB);
    QCoreApplication::processEvents();
    tabBView.setPlayheadSample(tabB->timeline()->sampleForTick(auditionTick), false);
    QCoreApplication::processEvents();
    auto *const overlay = descendant<songview::PlayheadOverlay>(tabBView);
    auto *const quick = descendant<songview::TimelineQuickView>(tabBView);
    const auto quickChildren =
        quick ? quick->findChildren<QWidget *>(QString{}, Qt::FindDirectChildrenOnly)
              : QList<QWidget *>{};
    QWidget *const quickContainer = quickChildren.size() == 1 ? quickChildren.front() : nullptr;
    check(overlay && overlay->focusPolicy() == Qt::NoFocus,
          "native playhead overlay did not enforce its no-focus contract");
    check(quickContainer && quickContainer->focusPolicy() == Qt::NoFocus,
          "TimelineQuickView native container did not enforce its no-focus contract");
    auto *const focusTarget = QApplication::focusWidget();
    check(focusTarget && (focusTarget == &tabBView || tabBView.isAncestorOf(focusTarget)),
          "tab switch/playhead update did not restore active-surface focus");
    check(focusTarget != overlay, "tab switch/playhead update focused the native playhead overlay");
    check(focusTarget != quickContainer || tabBView.focusedTimelineBand().has_value(),
          "TimelineQuickView native container was focused without an active Quick input band");

    if (copyAction && tabBNote) {
        auto copyTriggerCount = 0;
        const QMetaObject::Connection triggerSpy = connect(
            copyAction, &QAction::triggered, this, [&copyTriggerCount] { ++copyTriggerCount; });
        activateWindow();
        raise();
        QCoreApplication::processEvents();
        tabBView.focusActiveSurface();
        QCoreApplication::processEvents();
        if (currentCopyBindings.isEmpty()) {
            check(false, "native Copy action has no shortcut to exercise");
        } else {
            auto *target = QApplication::focusWidget();
            if (!target || !(target == &tabBView || tabBView.isAncestorOf(target))) {
                check(false,
                      "Copy shortcut check did not focus a widget inside the active tab surface");
            } else {
                const auto combination = currentCopyBindings.front()[0];
                QKeyEvent press(QEvent::KeyPress, combination.key(),
                                combination.keyboardModifiers());
                QKeyEvent release(QEvent::KeyRelease, combination.key(),
                                  combination.keyboardModifiers());
                QApplication::sendEvent(target, &press);
                QApplication::sendEvent(target, &release);
            }
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
    check(m_voiceChangesDrawerAction->objectName() ==
                  QStringLiteral("voiceChangesDrawerWindowAction") &&
              m_voiceChangesDrawerAction->shortcut() == QKeySequence(Qt::Key_P) &&
              m_voiceChangesDrawerAction->shortcutContext() == Qt::WindowShortcut &&
              m_voiceChangesDrawerAction->text() == QStringLiteral("Voice &Changes") &&
              m_voiceChangesDrawerAction->toolTip() ==
                  QStringLiteral("Show or hide voice changes (P)"),
          "voice changes route is not the required WindowShortcut P action");
    check(tabAView.drawerSectionVisible(EditorDrawerPage::Velocity),
          "new tab did not restore velocity visibility");
    check(!tabAView.drawerSectionVisible(EditorDrawerPage::Automations),
          "new tab did not restore automation visibility");
    check(!tabAView.drawerSectionVisible(EditorDrawerPage::VoiceChanges),
          "new tab did not restore voice-changes visibility");
    check(tabAView.drawerActivePage() == EditorDrawerPage::Velocity,
          "new tab did not restore the active drawer page");
    check(tabAView.drawerSectionHeight(EditorDrawerPage::Velocity) == 173,
          "new tab did not restore the velocity drawer height");
    check(tabBView.editorViewState().drawerState() == tabAView.editorViewState().drawerState(),
          "new tabs did not share application-wide drawer settings");

    tabAView.setDrawerSectionVisible(EditorDrawerPage::Automations, false);
    tabAView.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    tabAView.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    check(!tabBView.hasVisibleDrawerSection(),
          "drawer visibility did not propagate to the other open tab");

    tabBView.focusContent();
    QCoreApplication::processEvents();
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
    // The P route toggles the voice changes page as application-wide chrome
    // with its own announcement, like the A and V routes.
    sendKeyStroke(*this, Qt::Key_P, Qt::NoModifier, false);
    QCoreApplication::processEvents();
    check(tabBView.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              tabBView.drawerActivePage() == EditorDrawerPage::VoiceChanges &&
              tabAView.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              tabAView.drawerActivePage() == EditorDrawerPage::VoiceChanges &&
              statusBar()->currentMessage() == QStringLiteral("Voice changes shown"),
          "voice changes route did not update application-wide drawer chrome");
    sendKeyStroke(*this, Qt::Key_P, Qt::NoModifier, false);
    QCoreApplication::processEvents();
    check(!tabBView.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              !tabAView.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              statusBar()->currentMessage() == QStringLiteral("Voice changes hidden"),
          "voice changes route did not globally close its page");

    EditorDrawer *const focusDrawer = tabBView.editorDrawer();
    AutomationPage *const focusAutomationPage =
        focusDrawer ? focusDrawer->automationPage() : nullptr;
    auto *automationSurface = focusAutomationPage ? focusAutomationPage->canvas() : nullptr;
    auto *velocitySurface = focusDrawer ? focusDrawer->velocityArea() : nullptr;
    auto *voiceSurface = focusDrawer ? focusDrawer->voiceChangeArea() : nullptr;
    check(automationSurface && velocitySurface && voiceSurface,
          "drawer shortcut focus check could not find all three editor surfaces");
    if (automationSurface && velocitySurface && voiceSurface) {
        tabBView.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        tabBView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        tabBView.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
        tabBView.setDrawerActivePage(EditorDrawerPage::Velocity);
        tabBView.focusTimelineBand(songview::TimelineBand::VoiceChanges, Qt::MouseFocusReason);
        // Quick delivers activation asynchronously: let one event turn run
        // before reading the live active-focus band.
        QCoreApplication::processEvents();
        check(tabBView.focusedTimelineBand() == songview::TimelineBand::VoiceChanges,
              "voice changes input did not take drawer focus through the SongView bridge");
        // Hiding the focused first page walks the visual order to velocity.
        // The voice surface is no longer a widget, so sendEvent keystrokes
        // cannot enter the widget shortcut map; fire the same QAction the
        // window shortcut routes to.
        m_voiceChangesDrawerAction->trigger();
        QCoreApplication::processEvents();
        check(!tabBView.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
                  tabBView.drawerSectionVisible(EditorDrawerPage::Velocity) &&
                  tabBView.focusedTimelineBand() == songview::TimelineBand::Velocity,
              "closing focused voice changes did not focus the velocity drawer");
        tabBView.focusTimelineBand(songview::TimelineBand::Velocity, Qt::MouseFocusReason);
        QCoreApplication::processEvents();
        // The velocity surface is no longer a widget, so sendEvent keystrokes
        // cannot enter the widget shortcut map; fire the same QAction the
        // window shortcut routes to.
        m_velocityDrawerAction->trigger();
        QCoreApplication::processEvents();
        check(!tabBView.drawerSectionVisible(EditorDrawerPage::Velocity) &&
                  tabBView.drawerSectionVisible(EditorDrawerPage::Automations) &&
                  tabBView.focusedTimelineBand() == songview::TimelineBand::Automation,
              "closing focused velocity did not focus the remaining automation drawer");
        if (QWidget *focus = QApplication::focusWidget()) {
            sendKeyStroke(*focus, Qt::Key_A, Qt::NoModifier, false);
        }
        QCoreApplication::processEvents();
        QWidget *focusAfterFocusedClose = QApplication::focusWidget();
        check(!tabBView.hasVisibleDrawerSection() &&
                  tabBView.focusedTimelineBand() == songview::TimelineBand::Roll &&
                  focusAfterFocusedClose &&
                  (focusAfterFocusedClose == &tabBView ||
                   tabBView.isAncestorOf(focusAfterFocusedClose)),
              "closing focused automation did not return focus to active content");
    }

    tabBView.setDrawerActivePage(EditorDrawerPage::Velocity);
    tabBView.setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
    tabBView.setDrawerSectionHeight(EditorDrawerPage::VoiceChanges, 97);
    const int retainedHeight = tabBView.drawerSectionHeight(EditorDrawerPage::Velocity);
    const int retainedVoiceHeight = tabBView.drawerSectionHeight(EditorDrawerPage::VoiceChanges);
    tabBView.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    tabBView.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    check(tabBView.drawerActivePage() == EditorDrawerPage::Velocity &&
              tabBView.drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight &&
              tabBView.drawerSectionHeight(EditorDrawerPage::VoiceChanges) == retainedVoiceHeight &&
              tabAView.drawerActivePage() == EditorDrawerPage::Velocity &&
              tabAView.drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight &&
              tabAView.drawerSectionHeight(EditorDrawerPage::VoiceChanges) == retainedVoiceHeight,
          "drawer hide did not retain globally shared page and height");
    m_workspace->selectSongTab(tabA);
    m_workspace->selectSongTab(tabB);
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QWidget *focusAfterTabSwitch = QApplication::focusWidget();
    check(focusAfterTabSwitch &&
              (focusAfterTabSwitch == &tabBView || tabBView.isAncestorOf(focusAfterTabSwitch)) &&
              tabBView.focusedTimelineBand() == songview::TimelineBand::Roll,
          "tab switch did not request active content focus");
    check(m_workspace->selectedSongTab() == tabB &&
              tabBView.drawerActivePage() == EditorDrawerPage::Velocity &&
              tabBView.drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight &&
              tabAView.drawerSectionHeight(EditorDrawerPage::Velocity) == retainedHeight,
          "application-wide drawer state did not survive a tab switch");

    tabBView.setEventListVisible(true);
    QCoreApplication::processEvents();
    const bool blockedVelocityVisible = tabBView.drawerSectionVisible(EditorDrawerPage::Velocity);
    const bool blockedVoiceVisible = tabBView.drawerSectionVisible(EditorDrawerPage::VoiceChanges);
    const EditorDrawerPage blockedPage = tabBView.drawerActivePage();
    const QString blockedStatus = statusBar()->currentMessage();
    check(!m_automationDrawerAction->isEnabled() && !m_velocityDrawerAction->isEnabled() &&
              !m_voiceChangesDrawerAction->isEnabled(),
          "event-list mode did not disable drawer routes");
    sendKeyStroke(*this, Qt::Key_V, Qt::NoModifier, false);
    sendKeyStroke(*this, Qt::Key_P, Qt::NoModifier, false);
    check(tabBView.drawerSectionVisible(EditorDrawerPage::Velocity) == blockedVelocityVisible &&
              tabBView.drawerSectionVisible(EditorDrawerPage::VoiceChanges) ==
                  blockedVoiceVisible &&
              tabBView.drawerActivePage() == blockedPage &&
              statusBar()->currentMessage() == blockedStatus,
          "event-list mode let a drawer route change or announce");
    tabBView.setEventListVisible(false);
    QCoreApplication::processEvents();
    check(m_automationDrawerAction->isEnabled() && m_velocityDrawerAction->isEnabled() &&
              m_voiceChangesDrawerAction->isEnabled(),
          "leaving event-list mode did not re-enable drawer routes");

    // ---- All-tab origin (row D): the non-selected tab is a first-class
    // origin. The public WorkspaceUi hub fans the complete state out before
    // MainWindow reports the persistence completion.
    WorkspaceUi *const rowDWorkspace = findChild<WorkspaceUi *>();
    check(rowDWorkspace != nullptr, "row-D could not discover WorkspaceUi through MainWindow");
    if (!rowDWorkspace) {
        hide();
        return false;
    }
    const EditorAutomationRowId lane0{EditorAutomationRowKind::ControlChange, 0, 74};
    const EditorAutomationRowId hiddenFirst{EditorAutomationRowKind::ControlChange, 1, 7};
    const EditorAutomationRowId hiddenSecond{EditorAutomationRowKind::ControlChange, 0, 80};
    const EditorAutomationRowId tempoRow{EditorAutomationRowKind::Tempo, 0, 0};
    const int laneHeightFloor = layout::fontPx(7.0 / 3.0);
    const int laneHeightCeiling = layout::fontPx(32.0 / 3.0);
    EditorViewState completeSeed;
    completeSeed.velocity = {true, 173};
    completeSeed.automation = {true, 44};
    completeSeed.voiceChanges = {true, 55};
    completeSeed.activePage = EditorDrawerPage::Automations;
    completeSeed.laneHeight = (laneHeightFloor + laneHeightCeiling) / 2;
    completeSeed.laneHeights = {{lane0, laneHeightFloor + 3}, {hiddenFirst, laneHeightFloor + 5}};
    completeSeed.laneRanges = {{lane0, 90}, {tempoRow, 100}};
    completeSeed.emptyLanes.insert(lane0);
    completeSeed.hideLane(hiddenFirst);
    completeSeed.hideLane(hiddenSecond);

    rowDWorkspace->selectSongTab(tabA);
    QCoreApplication::processEvents();
    struct RowDTrace {
        std::vector<QString> events;
        std::optional<EditorViewState> lastPersistedState;
        int originA = 0;
        int originB = 0;
        int hub = 0;
        int persisted = 0;
        int projectionOriginBaseline = 0;
        bool hubCompleteAtEmission = false;
        bool projectionQuietAtEmission = false;
    };
    const auto rowDTrace = std::make_shared<RowDTrace>();
    SongView *const tabAPointer = &tabAView;
    SongView *const tabBPointer = &tabBView;
    const QMetaObject::Connection originBSpy =
        connect(tabBPointer, &SongView::editorViewStateChanged, this,
                [rowDTrace](const EditorViewState &) { ++rowDTrace->originB; });
    const QMetaObject::Connection originASpy =
        connect(tabAPointer, &SongView::editorViewStateChanged, this,
                [rowDTrace](const EditorViewState &) { ++rowDTrace->originA; });
    const QMetaObject::Connection hubSpy =
        connect(rowDWorkspace, &WorkspaceUi::editorViewStateChanged, this,
                [rowDTrace, tabAPointer, tabBPointer](const EditorViewState &state) {
                    ++rowDTrace->hub;
                    rowDTrace->events.emplace_back(QStringLiteral("hub"));
                    rowDTrace->hubCompleteAtEmission = tabAPointer->editorViewState() == state &&
                                                       tabBPointer->editorViewState() == state;
                    rowDTrace->projectionQuietAtEmission =
                        rowDTrace->originA == rowDTrace->projectionOriginBaseline;
                });
    const QMetaObject::Connection persistedSpy = connect(
        this, &MainWindow::editorViewStatePersisted, this,
        [rowDTrace](const EditorViewState &state) {
            ++rowDTrace->persisted;
            rowDTrace->lastPersistedState = state;
            rowDTrace->events.emplace_back(QStringLiteral("persisted"));
        },
        Qt::QueuedConnection);
    const auto expectPublished = [&](const char *message, auto &&change) {
        const int originB = rowDTrace->originB;
        const int originA = rowDTrace->originA;
        const int hub = rowDTrace->hub;
        const int persisted = rowDTrace->persisted;
        const auto traceStart = rowDTrace->events.size();
        rowDTrace->projectionOriginBaseline = originA;
        rowDTrace->hubCompleteAtEmission = false;
        rowDTrace->projectionQuietAtEmission = false;
        // The SongView call below is the semantic origin. Its observer is
        // already armed; this marker makes the public signal order explicit
        // despite the WorkspaceUi connection being older than this observer.
        rowDTrace->events.emplace_back(QStringLiteral("origin"));
        change();
        QCoreApplication::processEvents();
        check(rowDTrace->originB == originB + 1 && rowDTrace->originA == originA &&
                  rowDTrace->hub == hub + 1 && rowDTrace->persisted == persisted + 1,
              message);
        const bool ordered = rowDTrace->events.size() == traceStart + 3 &&
                             rowDTrace->events[traceStart] == QStringLiteral("origin") &&
                             rowDTrace->events[traceStart + 1] == QStringLiteral("hub") &&
                             rowDTrace->events[traceStart + 2] == QStringLiteral("persisted");
        check(ordered && rowDTrace->hubCompleteAtEmission && rowDTrace->projectionQuietAtEmission &&
                  rowDTrace->lastPersistedState.has_value() &&
                  *rowDTrace->lastPersistedState == tabBView.editorViewState(),
              "row-D publication was not hub-then-persisted with a silent projection");
    };
    expectPublished("one non-selected origin commit did not emit exactly one origin, hub, "
                    "and persistence completion",
                    [&] { tabBView.setEditorViewState(completeSeed); });
    check(tabAView.editorViewState() == completeSeed && tabBView.editorViewState() == completeSeed,
          "the origin commit did not fan the complete state out to every open tab");
    check(tabBView.editorViewState().hiddenLanes().size() == 2 &&
              tabBView.editorViewState().hiddenLanes().front() == hiddenFirst &&
              tabBView.editorViewState().hiddenLanes().back() == hiddenSecond,
          "the complete state lost its ordered hidden lanes");
    QSettings persisted;
    check(loadEditorViewState(persisted) == completeSeed,
          "the complete state was not persisted through the public codec");

    expectPublished("a lane-range mutation on the non-selected tab did not publish exactly once",
                    [&] { tabBView.setLaneDisplayRange(0, 74, 80); });
    check(tabAView.editorViewState().laneRanges.at(lane0) == 80 &&
              tabBView.editorViewState().laneRanges.at(lane0) == 80,
          "the lane-range mutation did not fan out to both tabs");

    const int unchangedOriginB = rowDTrace->originB;
    const int unchangedOriginA = rowDTrace->originA;
    const int unchangedHub = rowDTrace->hub;
    const int unchangedPersisted = rowDTrace->persisted;
    const auto unchangedTrace = rowDTrace->events.size();
    tabBView.setLaneDisplayRange(0, 74, 80); // unchanged value
    tabBView.addEmptyLane(0, 74);            // already an empty lane
    tabBView.removeEmptyLane(3, 99);         // already absent
    QCoreApplication::processEvents();
    check(rowDTrace->originB == unchangedOriginB && rowDTrace->originA == unchangedOriginA &&
              rowDTrace->hub == unchangedHub && rowDTrace->persisted == unchangedPersisted &&
              rowDTrace->events.size() == unchangedTrace,
          "an editor-unchanged lane mutation published");

    const int engineTracks = tabB->document().engineTrackCount();
    check(engineTracks >= 2, "remap fixture lacks two engine tracks");
    if (engineTracks >= 2) {
        const int remapSource = 1;
        const int remapTarget = remapSource == engineTracks - 1 ? 0 : engineTracks - 1;
        const QByteArray midiBeforeRemap = tabB->document().smf().write();
        const EditorViewState preRemap = tabBView.editorViewState();
        bool moved = false;
        expectPublished(
            "a lane-identity remap on the non-selected tab did not publish exactly once",
            [&] { moved = tabB->document().moveTrack(remapSource, remapTarget); });
        const EditorViewState remapped = tabBView.editorViewState();
        check(moved, "the lane-identity remap was rejected unexpectedly");
        check(remapped != completeSeed && !remapped.isLaneHidden(hiddenFirst) &&
                  remapped.hiddenLanes().size() == 2 &&
                  remapped.hiddenLanes().front().controller == 7 &&
                  remapped.hiddenLanes().front().track != 1 &&
                  remapped.hiddenLanes().back().controller == 80 &&
                  remapped.laneRanges.at(tempoRow) == 100,
              "the remap did not re-identify hidden lanes or keep tempo rows fixed");
        check(tabAView.editorViewState() == remapped,
              "the remap did not fan out to the other open tab");
        QSettings persistedAfterRemap;
        check(loadEditorViewState(persistedAfterRemap) == remapped,
              "the remap was not persisted through the public codec");

        expectPublished("the remap undo did not publish exactly once",
                        [&] { tabB->document().undoStack()->undo(); });
        check(tabBView.editorViewState() == preRemap && tabAView.editorViewState() == preRemap &&
                  tabB->document().smf().write() == midiBeforeRemap && !tabB->document().isDirty(),
              "the remap undo did not restore the state and song exactly");

        // A remap that leaves every lane identity unchanged is suppressed by
        // the origin equality guard: no SongView, hub, or persistence signal.
        EditorViewState reducedSeed;
        reducedSeed.velocity = {true, 173};
        reducedSeed.automation = {true, 44};
        reducedSeed.voiceChanges = {true, 55};
        reducedSeed.activePage = EditorDrawerPage::Automations;
        expectPublished("the reduced state seed did not publish exactly once",
                        [&] { tabBView.setEditorViewState(reducedSeed); });
        const QByteArray midiBeforeQuietMove = tabB->document().smf().write();
        const int quietOriginB = rowDTrace->originB;
        const int quietOriginA = rowDTrace->originA;
        const int quietHub = rowDTrace->hub;
        const int quietPersisted = rowDTrace->persisted;
        const auto quietTrace = rowDTrace->events.size();
        const bool quietMoved = tabB->document().moveTrack(remapSource, remapTarget);
        QCoreApplication::processEvents();
        check(quietMoved && rowDTrace->originB == quietOriginB &&
                  rowDTrace->originA == quietOriginA && rowDTrace->hub == quietHub &&
                  rowDTrace->persisted == quietPersisted && rowDTrace->events.size() == quietTrace,
              "an editor-unchanged remap published");
        const int quietUndoOriginB = rowDTrace->originB;
        const int quietUndoOriginA = rowDTrace->originA;
        const int quietUndoHub = rowDTrace->hub;
        const int quietUndoPersisted = rowDTrace->persisted;
        const auto quietUndoTrace = rowDTrace->events.size();
        tabB->document().undoStack()->undo();
        QCoreApplication::processEvents();
        check(rowDTrace->originB == quietUndoOriginB && rowDTrace->originA == quietUndoOriginA &&
                  rowDTrace->hub == quietUndoHub && rowDTrace->persisted == quietUndoPersisted &&
                  rowDTrace->events.size() == quietUndoTrace &&
                  tabB->document().smf().write() == midiBeforeQuietMove &&
                  !tabB->document().isDirty(),
              "an editor-unchanged remap undo published or disturbed the song");
    }

    // A duplicate destination is rejected by the live SongDocument signal
    // seam. Arm state, project, settings, and signal snapshots before invoke.
    const EditorViewState rejectedA = tabAView.editorViewState();
    const EditorViewState rejectedB = tabBView.editorViewState();
    const QByteArray rejectedMidi = tabB->document().smf().write();
    const uint64_t rejectedRevision = tabB->document().revision();
    QSettings rejectedSettings;
    const EditorViewState rejectedPersisted = loadEditorViewState(rejectedSettings);
    const auto rejectedProject = porydawSnapshot(projectRoot);
    const int rejectedOriginB = rowDTrace->originB;
    const int rejectedOriginA = rowDTrace->originA;
    const int rejectedHub = rowDTrace->hub;
    const int rejectedPersistedCount = rowDTrace->persisted;
    const auto rejectedTrace = rowDTrace->events.size();
    TrackRemap rejectedRemap;
    rejectedRemap.engineTrackMap = {0, 0};
    rejectedRemap.newEngineTrackCount = 2;
    emit tabB->document().tracksRemapped(rejectedRemap);
    QCoreApplication::processEvents();
    check(
        tabAView.editorViewState() == rejectedA && tabBView.editorViewState() == rejectedB &&
            rowDTrace->originB == rejectedOriginB && rowDTrace->originA == rejectedOriginA &&
            rowDTrace->hub == rejectedHub && rowDTrace->persisted == rejectedPersistedCount &&
            rowDTrace->events.size() == rejectedTrace &&
            tabB->document().smf().write() == rejectedMidi &&
            tabB->document().revision() == rejectedRevision &&
            [&] {
                QSettings settingsAfterRejected;
                return loadEditorViewState(settingsAfterRejected) == rejectedPersisted;
            }() &&
            porydawSnapshot(projectRoot) == rejectedProject,
        "a rejected live remap changed state, persistence, or the project");

    // Keep the detached atomic EditorViewState contract pinned too.
    EditorViewState rejectionProbe = completeSeed;
    check(!rejectionProbe.remapEngineTracks({0, 0}) && rejectionProbe == completeSeed,
          "a rejected remap mutated state or reported success");

    // A view-only lane mutation persists immediately while the song, its
    // history, and the project directory stay untouched.
    const auto projectBoundary = porydawSnapshot(projectRoot);
    {
        const QByteArray midiBefore = tabB->document().smf().write();
        const uint64_t revisionBefore = tabB->document().revision();
        const int undoBefore = tabB->view().document()->undoStack()->count();
        expectPublished("an empty-lane mutation did not publish exactly once",
                        [&] { tabBView.addEmptyLane(2, 40); });
        check(tabAView.editorViewState() == tabBView.editorViewState() &&
                  tabBView.editorViewState() != completeSeed,
              "an empty-lane mutation did not fan out to both tabs");
        QSettings persisted;
        check(loadEditorViewState(persisted) == tabBView.editorViewState(),
              "the empty-lane change was not persisted outside a boundary");
        check(tabB->document().smf().write() == midiBefore &&
                  tabB->document().revision() == revisionBefore &&
                  tabB->view().document()->undoStack()->count() == undoBefore &&
                  porydawSnapshot(projectRoot) == projectBoundary,
              "view-only lane state changed MIDI, Undo, or the project directory");
        expectPublished("empty-lane removal did not publish exactly once",
                        [&] { tabBView.removeEmptyLane(2, 40); });
        check(tabBView.editorViewState().emptyLanes.count(
                  {EditorAutomationRowKind::ControlChange, 2, 40}) == 0,
              "empty-lane removal did not clear the lane");
    }
    expectPublished("the final complete state did not publish exactly once",
                    [&] { tabBView.setEditorViewState(completeSeed); });
    check(tabAView.editorViewState() == completeSeed && tabBView.editorViewState() == completeSeed,
          "the final complete state was not restored through one origin commit");
    QSettings persistedFinal;
    check(loadEditorViewState(persistedFinal) == completeSeed,
          "the restored complete state was not persisted through the public codec");
    disconnect(originBSpy);
    disconnect(originASpy);
    disconnect(hubSpy);
    disconnect(persistedSpy);

    // The row-D origin work deliberately left tabA selected. The remaining
    // action checks exercise the selected-tab route, so restore tabB and pin
    // the routing target before the Insert Time section runs.
    rowDWorkspace->selectSongTab(tabB);
    QCoreApplication::processEvents();
    check(rowDWorkspace->selectedSongTab() == tabB,
          "the selected-tab action checks did not start with tab B routed");

    if (insertTimeAction && tabBNote) {
        const DocNote source = *tabBNote;
        const SongView::GridSeg segment = tabBView.gridSegAt(source.tick);
        const QByteArray before = tabB->document().smf().write();
        const int undoIndex = tabB->document().undoStack()->index();
        const auto insertAndCheck = [&](bool playing, int bars, int beats, int fractions,
                                        uint64_t expectedSpan, const char *failure) {
            tabBView.setPlayheadSample(
                tabB->timeline()->sampleForTick(playing ? source.tick : uint64_t{0}), playing);
            if (!playing)
                tabBView.commitEditCursor(source.tick);
            QTimer::singleShot(0, [bars, beats, fractions] {
                auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
                auto *barsSpin =
                    dialog ? dialog->findChild<DragSpinBox *>(QStringLiteral("insertTimeBars"))
                           : nullptr;
                auto *beatsSpin =
                    dialog ? dialog->findChild<DragSpinBox *>(QStringLiteral("insertTimeBeats"))
                           : nullptr;
                auto *fractionsSpin = dialog ? dialog->findChild<DragSpinBox *>(
                                                   QStringLiteral("insertTimeBeatFractions"))
                                             : nullptr;
                if (!dialog || !barsSpin || !beatsSpin || !fractionsSpin) {
                    if (dialog)
                        dialog->reject();
                    return;
                }
                barsSpin->setValue(bars);
                beatsSpin->setValue(beats);
                fractionsSpin->setValue(fractions);
                dialog->accept();
            });
            insertTimeAction->trigger();
            DocNote shifted;
            check(tabB->document().undoStack()->index() == undoIndex + 1 &&
                      tabB->document().findNote(source.noteId, &shifted) &&
                      shifted.tick == source.tick + expectedSpan,
                  failure);
            tabB->document().undoStack()->undo();
            check(tabB->document().smf().write() == before,
                  "Insert Time undo did not restore the active song exactly");
        };
        insertAndCheck(false, 0, 2, 0, 2 * segment.beatTicks,
                       "Insert Time did not insert beats at the stopped edit cursor");
        insertAndCheck(true, 1, 0, 0, segment.beatTicks * segment.beatsPerBar,
                       "Insert Time did not insert a bar at the playback cursor");
        insertAndCheck(true, 0, 0, 2, (2 * segment.beatTicks + 3) / 4,
                       "Insert Time did not insert beat fractions at the playback cursor");
        tabBView.setPlayheadSample(0, false);
    }

    // ---- Close, reopen, and in-place reload (rows C and F) ----------------
    m_workspace->selectSongTab(tabB);
    m_workspace->requestCloseSelectedTab(); // tabB is selected and clean
    check(m_workspace->openTabCount() == 1 && m_workspace->songTabFor(*nameB) == nullptr,
          "tab close did not synchronously detach the clean session");
    check(porydawSnapshot(projectRoot) == projectBoundary,
          "tab close wrote view or editor data into the project");
    m_workspace->requestSongOpen(*nameB, /*newTab=*/true);
    QPointer<SongTab> reopened = m_workspace->songTabFor(*nameB);
    check(reopened != nullptr, "reopened song did not create its tab immediately");
    const bool reopenedReady = reopened && waitForTabReady(*m_workspace, reopened.data(),
                                                           "mainwindow-routing reopened song B");
    QPointer<SongView> reopenedView = reopened ? &reopened->view() : nullptr;
    check(reopenedReady && reopened && m_workspace->songTabFor(*nameB) == reopened.data() &&
              reopenedView,
          "reopened song did not become ready");
    // A future tab projects the complete global state; its camera is canonical.
    check(reopenedView && reopenedView->editorViewState() == completeSeed &&
              tabAView.editorViewState() == completeSeed,
          "the future tab did not project the complete global editor state");
    check(reopenedView && reopened->timeline() &&
              freshViewStateAtCanonicalDefaults(*reopenedView, *reopened->timeline()),
          "reopen after close did not establish every canonical fresh view default");
    check(porydawSnapshot(projectRoot) == projectBoundary,
          "reopen wrote view or editor data into the project");

    // A ready reload preserves all nine transient fields that are live when
    // the reload starts and swaps the binding; reapplying state while disabled
    // must produce no event-list visibility traffic.
    if (reopenedReady && reopened && reopenedView) {
        m_workspace->selectSongTab(reopened.data());
        const SongView::ViewState before = reopenedView->viewState();
        const MidiTimeline *const reopenedTimeline = reopened->timeline().get();
        auto alternateTrack = std::optional<int>{};
        if (reopenedTimeline) {
            for (int track = 0; track < 16; ++track) {
                if (reopenedTimeline->tracks[track].used && track != before.selectedTrack) {
                    alternateTrack = track;
                    break;
                }
            }
        }
        check(alternateTrack.has_value(),
              "reopen fixture lacks a used engine track distinct from the canonical selection");
        if (!alternateTrack)
            return false;
        SongView::ViewState distinctive;
        distinctive.valid = true;
        distinctive.pxPerBeat = before.pxPerBeat * 2.0;
        distinctive.keyHeight = before.keyHeight * 1.5;
        // The native Quick root can change available canvas dimensions. Seed
        // each camera axis beyond its range so applyViewState captures the
        // actual reachable endpoint rather than assuming a fixed viewport.
        distinctive.scrollPx = std::numeric_limits<double>::max();
        distinctive.scrollY = std::numeric_limits<double>::max();
        distinctive.selectedTrack = *alternateTrack;
        distinctive.editCursorTick =
            before.editCursorTick == 0 ? reopenedView->timeline()->ticksPerBeat : 0;
        distinctive.gridMinDenom = 16;
        distinctive.gridTriplet = true;
        distinctive.eventList = true;
        reopenedView->applyViewState(distinctive);
        SongView::ViewState seeded = reopenedView->viewState();
        if (seeded.scrollPx == before.scrollPx || seeded.scrollY == before.scrollY) {
            if (seeded.scrollPx == before.scrollPx)
                distinctive.scrollPx = 0.0;
            if (seeded.scrollY == before.scrollY)
                distinctive.scrollY = 0.0;
            reopenedView->applyViewState(distinctive);
            seeded = reopenedView->viewState();
        }
        distinctive = seeded;
        const bool cursorSeedLanded = reopenedView->timeline()->lengthTicks == 0
                                          ? seeded.editCursorTick == 0
                                          : seeded.editCursorTick != before.editCursorTick;
        check(seeded.pxPerBeat != before.pxPerBeat && seeded.keyHeight != before.keyHeight &&
                  seeded.scrollPx != before.scrollPx && seeded.scrollY != before.scrollY &&
                  seeded.selectedTrack == *alternateTrack &&
                  seeded.selectedTrack != before.selectedTrack &&
                  seeded.editCursorTick == distinctive.editCursorTick && cursorSeedLanded &&
                  seeded.gridMinDenom == distinctive.gridMinDenom &&
                  seeded.gridMinDenom != before.gridMinDenom &&
                  seeded.gridTriplet == distinctive.gridTriplet &&
                  seeded.gridTriplet != before.gridTriplet &&
                  seeded.eventList == distinctive.eventList && seeded.eventList != before.eventList,
              "the reload seed did not land every reachable transient field");
        QTabBar *const reloadFocusTarget = findChild<QTabBar *>();
        check(reloadFocusTarget && reloadFocusTarget->isVisible() && reloadFocusTarget->isEnabled(),
              "reload focus tab bar is missing, hidden, or disabled");
        const Qt::FocusPolicy originalFocusPolicy =
            reloadFocusTarget ? reloadFocusTarget->focusPolicy() : Qt::NoFocus;
        if (reloadFocusTarget) {
            reloadFocusTarget->setFocusPolicy(Qt::StrongFocus);
            activateWindow();
            raise();
            QCoreApplication::processEvents();
            reloadFocusTarget->setFocus(Qt::OtherFocusReason);
            QCoreApplication::processEvents();
        }
        check(reloadFocusTarget && QApplication::focusWidget() == reloadFocusTarget,
              "reload focus tab bar did not own focus before the ready reload");
        // The workspace tab bar stays alive across the borrow-safe wait below.
        int eventListTraffic = 0;
        const QMetaObject::Connection eventListSpy =
            connect(reopenedView, &SongView::eventListVisibilityChanged, this,
                    [&eventListTraffic](bool) { ++eventListTraffic; });
        reopenedView->applyViewState(distinctive);
        QCoreApplication::processEvents();
        check(QApplication::focusWidget() == reloadFocusTarget,
              "reapplying the visible event-list state moved focus from the workspace tab bar");
        const MidiTimeline *timelineBeforeReload = reopened->timeline().get();
        const SongView::ViewState baseline = reopenedView->viewState();
        check(baseline.valid && baseline.pxPerBeat == distinctive.pxPerBeat &&
                  baseline.keyHeight == distinctive.keyHeight &&
                  baseline.scrollPx == distinctive.scrollPx &&
                  baseline.scrollY == distinctive.scrollY &&
                  baseline.selectedTrack != before.selectedTrack &&
                  baseline.selectedTrack == *alternateTrack &&
                  baseline.selectedTrack == distinctive.selectedTrack &&
                  baseline.editCursorTick == distinctive.editCursorTick &&
                  baseline.gridMinDenom == distinctive.gridMinDenom &&
                  baseline.gridTriplet == distinctive.gridTriplet &&
                  baseline.eventList == distinctive.eventList,
              "the post-reseed reload baseline did not retain all distinctive transient fields");
        const SongName reopenedName = reopened->name();
        m_workspace->requestSongOpen(reopenedName); // the in-place reload
        // The reload drops readiness synchronously at the ReloadSongInput
        // dispatch, before any replacement MidiStage can arrive, and keeps
        // the old binding until that stage lands.
        check(reopened && !reopened->isReady() &&
                  reopened->timeline().get() == timelineBeforeReload,
              "the in-place reload did not become not ready at its dispatch while retaining "
              "the old binding");
        // The shared helper returns at readiness alone; await the swap as
        // well, and require the retained complete state across every
        // not-ready turn of the staged reload.
        bool stagedStateDropped = false;
        const auto reloadLive = [this, reopened, reopenedView, reopenedName] {
            return reopened && reopenedView &&
                   m_workspace->songTabFor(reopenedName) == reopened.data() &&
                   &reopened->view() == reopenedView.data();
        };
        const auto reloadSwapped = [reopened, reopenedView, timelineBeforeReload, baseline,
                                    &stagedStateDropped] {
            if (reopened && reopenedView && reopened->isReady())
                return reopened->timeline().get() != timelineBeforeReload;
            // The retained complete state must survive every not-ready turn:
            // the live state before the replacement stage, the restored
            // capture after it.
            const bool targetsGone = reopened.isNull() || reopenedView.isNull();
            const bool stateIntact =
                targetsGone || sameViewState(reopenedView->viewState(), baseline);
            if (stateIntact)
                return false;
            stagedStateDropped = true;
            return false;
        };
        const auto reloadResult = checks::async_wait::waitUntil(reloadLive, reloadSwapped);
        disconnect(eventListSpy); // the lambda captures a block-local by reference
        check(!stagedStateDropped,
              "the staged reload dropped the retained complete view state while readiness was "
              "withheld");
        if (reloadResult == checks::async_wait::Result::Destroyed)
            std::fprintf(stderr, "song-load wait failed: mainwindow-routing reloaded song B tab "
                                 "was destroyed before its terminal payload\n");
        else if (reloadResult == checks::async_wait::Result::TimedOut)
            std::fprintf(stderr, "song-load wait failed: mainwindow-routing reloaded song B timed "
                                 "out before its terminal payload\n");
        const bool reloadedReady = reloadResult == checks::async_wait::Result::Ready;
        const bool reloadTabLive = reopened && reopenedView &&
                                   m_workspace->songTabFor(reopenedName) == reopened.data() &&
                                   &reopened->view() == reopenedView.data();
        if (!reloadedReady || !reloadTabLive) {
            check(false, "the ready reload did not retain the same live tab and view");
            if (reloadFocusTarget)
                reloadFocusTarget->setFocusPolicy(originalFocusPolicy);
            return false;
        }
        check(reloadedReady && reopened->timeline().get() != timelineBeforeReload,
              "the ready reload did not swap the binding and return to readiness");
        const SongView::ViewState after = reopenedView->viewState();
        check(after.valid, "the ready reload did not produce a valid view state");
        check(after.pxPerBeat == baseline.pxPerBeat, "the ready reload did not preserve pxPerBeat");
        check(after.keyHeight == baseline.keyHeight, "the ready reload did not preserve keyHeight");
        check(after.scrollPx == baseline.scrollPx, "the ready reload did not preserve scrollPx");
        check(after.scrollY == baseline.scrollY, "the ready reload did not preserve scrollY");
        check(after.selectedTrack == baseline.selectedTrack,
              "the ready reload did not preserve selectedTrack");
        check(after.editCursorTick == baseline.editCursorTick,
              "the ready reload did not preserve editCursorTick");
        check(after.gridMinDenom == baseline.gridMinDenom,
              "the ready reload did not preserve gridMinDenom");
        check(after.gridTriplet == baseline.gridTriplet,
              "the ready reload did not preserve gridTriplet");
        check(after.eventList == baseline.eventList, "the ready reload did not preserve eventList");
        check(eventListTraffic == 0, "the ready reload produced intermediate event-list traffic");
        check(reloadedReady && QApplication::focusWidget() == reloadFocusTarget,
              "the ready reload moved focus away from the unrelated workspace tab bar");
        if (reloadFocusTarget)
            reloadFocusTarget->setFocusPolicy(originalFocusPolicy);
    }
    check(porydawSnapshot(projectRoot) == projectBoundary,
          "the ready reload wrote view or editor data into the project");

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
        // warning; dismiss it while awaiting the Failed publication. The
        // dismissal is queued into a Qt-owned event-loop turn because
        // closing the box reentrantly from this poll callback races the
        // native Cocoa modal dispatch and tears the live dialog down
        // mid-sendEvent. The property flag keeps one dismissal queued per
        // live box.
        const auto failed = [&] {
            if (QPointer<QMessageBox> box =
                    qobject_cast<QMessageBox *>(QApplication::activeModalWidget());
                box && !box->property("dismissalQueued").toBool()) {
                box->setProperty("dismissalQueued", true);
                QTimer::singleShot(0, box, [box] { box->reject(); });
            }
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
    checkFreshBind(*m_workspace, *nameB, reopened ? reopened->voicegroupId() : nullptr,
                   tabAView.editorViewState(), check);
    checkStagedFullReload(*m_workspace, *nameB, reopened ? reopened->voicegroupId() : nullptr,
                          check);
    checkBankOnlyRebind(*m_workspace, *nameB, reopened ? reopened->voicegroupId() : nullptr, check);

    // ---- Project switch and quit leave the project untouched (row F) ------
    m_workspace->requestProjectOpenAt(projectRoot);
    check(waitForProjectReady(*m_workspace), "project switch failed");
    check(m_workspace->openTabCount() == 0, "project switch did not close its tabs");
    check(porydawSnapshot(projectRoot) == projectBoundary,
          "project switch wrote view or editor data into the project");
    m_workspace->requestSongOpen(*nameA);
    SongTab *postSwitch = m_workspace->songTabFor(*nameA);
    const bool postSwitchReady =
        postSwitch && waitForTabReady(*m_workspace, postSwitch, "mainwindow-routing post-switch");
    check(postSwitchReady && postSwitch && postSwitch->view().editorViewState() == completeSeed,
          "the global editor state did not survive the project switch into a future tab");
    check(porydawSnapshot(projectRoot) == projectBoundary,
          "the post-switch reopen wrote view or editor data into the project");

    QCloseEvent closeEvent;
    QApplication::sendEvent(this, &closeEvent);
    check(closeEvent.isAccepted() && m_closeAccepted,
          "clean application close did not accept its first close request");
    close();
    QElapsedTimer closeDeadline;
    closeDeadline.start();
    while (!m_closeAccepted && closeDeadline.elapsed() < 30000)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    check(m_closeAccepted, "application close boundary was rejected");
    check(porydawSnapshot(projectRoot) == projectBoundary,
          "application quit wrote view or editor data into the project");
    QSettings settingsAfterQuit;
    check(loadEditorViewState(settingsAfterQuit) == completeSeed,
          "application quit rewrote the global editor state");

    hide();
    std::printf("mainwindow-routing: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0;
}

int runMainWindowRoutingCheck(const QString &projectRoot, const QString &songA,
                              const QString &songB)
{
    // Seed the complete global editor view state through the public codec;
    // the harness owns no settings key literals.
    EditorViewState seed;
    seed.velocity = {true, 173};
    seed.automation = {false, std::nullopt};
    seed.voiceChanges = {false, std::nullopt};
    seed.activePage = EditorDrawerPage::Velocity;
    {
        QSettings settings;
        saveEditorViewState(settings, seed);
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
            auto *drawer = view.editorDrawer();
            AutomationPage *const hostAutomationPage = drawer ? drawer->automationPage() : nullptr;
            auto *automation = hostAutomationPage ? hostAutomationPage->canvas() : nullptr;
            auto *velocity = drawer ? drawer->velocityArea() : nullptr;
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
                    AutomationPage *const automationPage = drawer->automationPage();
                    QWidget *const automationViewport =
                        automationPage ? automationPage->scrollViewport() : nullptr;
                    QString automationCaptureError;
                    const QImage automationBefore =
                        automationViewport ? checks::support::captureQuickBand(
                                                 view, *automationViewport, &automationCaptureError)
                                           : QImage{};
                    check(!automationBefore.isNull(),
                          qPrintable(QStringLiteral("automation Quick viewport capture failed: %1")
                                         .arg(automationCaptureError)));
                    const auto velocityBefore = velocity->diagnostics();
                    for (uint64_t tick = firstTick + 1; tick <= finalTick; ++tick)
                        view.setPlayheadSample(session->timeline()->sampleForTick(tick), true);
                    QCoreApplication::processEvents();
                    check(uint64_t(view.playheadTick() + 0.5) == finalTick,
                          "SongView playhead did not reach the final tick");
                    check(velocity->diagnostics().playheadPresentationCount ==
                              velocityBefore.playheadPresentationCount + 120,
                          "velocity page did not receive all distinct playhead samples");
                    QString automationAfterError;
                    const QImage automationAfter =
                        automationViewport ? checks::support::captureQuickBand(
                                                 view, *automationViewport, &automationAfterError)
                                           : QImage{};
                    check(!automationAfter.isNull(),
                          qPrintable(QStringLiteral("automation Quick viewport capture failed: %1")
                                         .arg(automationAfterError)));
                    check(automationAfter == automationBefore &&
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
                AutomationPage *const automationThemePage = drawer->automationPage();
                QWidget *const automationThemeViewport =
                    automationThemePage ? automationThemePage->scrollViewport() : nullptr;
                QString themeBeforeError;
                const QImage automationThemeBefore =
                    automationThemeViewport ? checks::support::captureQuickBand(
                                                  view, *automationThemeViewport, &themeBeforeError)
                                            : QImage{};
                auto *themeQuickCanvas = view.findChild<songview::TimelineQuickView *>(
                    QStringLiteral("timelineQuickCanvas"));
                auto *automationThemeInput =
                    themeQuickCanvas && themeQuickCanvas->rootObject()
                        ? themeQuickCanvas->rootObject()->findChild<songview::TimelineInputItem *>(
                              QStringLiteral("timelineAutomationInput"))
                        : nullptr;
                check(automationThemeInput != nullptr,
                      "automation theme check requires the Quick automation input item");
                if (automationThemeInput)
                    automationThemeInput->notifyHostAppearanceChanged();
                QCoreApplication::processEvents();
                QString themeAfterError;
                const QImage automationThemeAfter =
                    automationThemeViewport ? checks::support::captureQuickBand(
                                                  view, *automationThemeViewport, &themeAfterError)
                                            : QImage{};
                check(themeBeforeError.isEmpty() && !automationThemeBefore.isNull() &&
                          themeAfterError.isEmpty() && !automationThemeAfter.isNull() &&
                          automationThemeAfter == automationThemeBefore,
                      qPrintable(QStringLiteral("theme change did not preserve the automation "
                                                "Quick viewport: before=%1 after=%2")
                                     .arg(themeBeforeError, themeAfterError)));
                view.setDrawerActivePage(EditorDrawerPage::Velocity);

                if (noteTrack >= 0) {
                    view.addEmptyLane(noteTrack, 74);
                    EditorViewState automationCosmetics = view.editorViewState();
                    automationCosmetics.laneHeight = layout::fontPx(4.0);
                    view.applyEditorViewState(automationCosmetics);
                    document->addLanePoint(noteTrack, 74, 0, 64);
                    view.setDrawerActivePage(EditorDrawerPage::Automations);
                    QCoreApplication::processEvents();
                    AutomationPage *const automationPage = drawer->automationPage();
                    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange,
                                                     uint8_t(noteTrack), 74};
                    const auto laneRow =
                        std::find_if(automation->rows().begin(), automation->rows().end(),
                                     [&lane](const AutomationRow &row) { return row.id == lane; });
                    check(laneRow != automation->rows().end(),
                          "automation lifecycle lane is unavailable");
                    if (laneRow != automation->rows().end()) {
                        view.setEditorHorizontalScroll(0.0);
                        QCoreApplication::processEvents();
                        const EditorViewState lifecycleViewState = view.editorViewState();
                        const int rowIndex =
                            int(std::distance(automation->rows().begin(), laneRow));
                        const int rowHeight = layout::fontPx(4.0);
                        const qreal rowY = qreal(rowIndex * rowHeight + rowHeight / 2);
                        const QPointF automationPoint(layout::fontPx(17.5 + 13.0 / 3.0), rowY);
                        auto *quickCanvas = view.findChild<songview::TimelineQuickView *>(
                            QStringLiteral("timelineQuickCanvas"));
                        auto *automationInput =
                            quickCanvas && quickCanvas->rootObject()
                                ? quickCanvas->rootObject()
                                      ->findChild<songview::TimelineInputItem *>(
                                          QStringLiteral("timelineAutomationInput"))
                                : nullptr;
                        auto *velocityInput = quickCanvas && quickCanvas->rootObject()
                                                  ? quickCanvas->rootObject()
                                                        ->findChild<songview::TimelineInputItem *>(
                                                            QStringLiteral("timelineVelocityInput"))
                                                  : nullptr;
                        check(automationInput != nullptr,
                              "Quick canvas must expose timelineAutomationInput");
                        check(velocityInput != nullptr,
                              "Quick canvas must expose timelineVelocityInput");
                        QScrollArea *const automationLifecycleScroll =
                            automationPage ? automationPage->findChild<QScrollArea *>(
                                                 QStringLiteral("automationScroll"))
                                           : nullptr;
                        QScrollBar *const automationScrollbar =
                            automationLifecycleScroll
                                ? automationLifecycleScroll->verticalScrollBar()
                                : nullptr;
                        // Automation input positions are viewport coordinates; convert
                        // content positions through the live scrollbar offset.
                        const auto automationViewportPoint = [&](const QPointF &contentPoint) {
                            return QPointF(
                                contentPoint.x(),
                                contentPoint.y() -
                                    qreal(automationScrollbar ? automationScrollbar->value() : 0));
                        };
                        const auto identityPoint = [](const QPointF &point) { return point; };
                        const auto beginAutomation = [&](Qt::MouseButton button,
                                                         Qt::KeyboardModifiers modifiers,
                                                         qreal xOffset) {
                            view.setDrawerActivePage(EditorDrawerPage::Automations);
                            view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
                            if (automationScrollbar) {
                                automationScrollbar->setValue(
                                    qBound(0, int(rowY) - automationScrollbar->pageStep() / 2,
                                           automationScrollbar->maximum()));
                            }
                            if (automationInput) {
                                checks::events::sendMouse(
                                    *automationInput, QEvent::MouseButtonPress,
                                    automationViewportPoint(automationPoint +
                                                            QPointF(xOffset, 0.0)),
                                    button, Qt::MouseButtons(button), modifiers);
                                checks::events::sendMouse(
                                    *automationInput, QEvent::MouseMove,
                                    automationViewportPoint(automationPoint +
                                                            QPointF(xOffset + 32.0, 12.0)),
                                    Qt::NoButton, Qt::MouseButtons(button), modifiers);
                            }
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
                            if (velocityInput) {
                                checks::events::sendMouse(*velocityInput, QEvent::MouseButtonPress,
                                                          position, button,
                                                          Qt::MouseButtons(button), Qt::NoModifier);
                                checks::events::sendMouse(*velocityInput, QEvent::MouseMove,
                                                          position + QPointF(32.0, -24.0),
                                                          Qt::NoButton, Qt::MouseButtons(button),
                                                          Qt::NoModifier);
                            }
                        };
                        const auto verifyTermination = [&](auto &surface, Qt::MouseButton button,
                                                           const QPointF &release,
                                                           const auto &toViewport, auto begin) {
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
                                                          toViewport(release), button, Qt::NoButton,
                                                          Qt::NoModifier);
                                QCoreApplication::processEvents();
                                const bool previewCleared = std::none_of(
                                    selection.begin(), selection.end(),
                                    [thisView = &view](const NoteId id) {
                                        return thisView->previewVelocity(id).has_value();
                                    });
                                const bool notGrabbed = [](const auto &item) {
                                    if constexpr (std::is_base_of_v<QWidget,
                                                                    std::decay_t<decltype(item)>>) {
                                        return QWidget::mouseGrabber() != &item;
                                    } else {
                                        const QQuickWindow *itemWindow = item.window();
                                        return !itemWindow ||
                                               itemWindow->mouseGrabberItem() != &item;
                                    }
                                }(surface);
                                check(interactionStarted && interactionTerminated &&
                                          document->smf().write() == midi &&
                                          document->revision() == revision &&
                                          document->undoStack()->count() == undo &&
                                          previewCleared &&
                                          view.selectionModel().noteSelection() ==
                                              expectedSelection &&
                                          notGrabbed &&
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
                            *automationInput, Qt::LeftButton, automationPoint + QPointF(32, 12),
                            automationViewportPoint,
                            [&] { beginAutomation(Qt::LeftButton, Qt::NoModifier, 0.0); });
                        verifyTermination(
                            *automationInput, Qt::LeftButton, automationPoint + QPointF(112, 12),
                            automationViewportPoint,
                            [&] { beginAutomation(Qt::LeftButton, Qt::NoModifier, 80.0); });
                        verifyTermination(
                            *automationInput, Qt::LeftButton, automationPoint + QPointF(192, 12),
                            automationViewportPoint,
                            [&] { beginAutomation(Qt::LeftButton, Qt::ShiftModifier, 160.0); });
                        verifyTermination(
                            *automationInput, Qt::RightButton, automationPoint + QPointF(272, 12),
                            automationViewportPoint,
                            [&] { beginAutomation(Qt::RightButton, Qt::NoModifier, 240.0); });

                        const auto live = document->notesForTrack(noteTrack);
                        const QPointF velocityPoint =
                            velocityNodePosition(view, *velocity, *session->timeline(), live[0]);
                        const QPointF velocityPaintPoint(
                            std::max(double(velocity->plotOrigin() + 1), velocityPoint.x() - 32.0),
                            8.0);
                        if (velocityInput) {
                            verifyTermination(*velocityInput, Qt::LeftButton,
                                              velocityPoint + QPointF(32, -24), identityPoint, [&] {
                                                  beginVelocity(Qt::LeftButton, velocityPoint);
                                              });
                            verifyTermination(
                                *velocityInput, Qt::LeftButton,
                                velocityPaintPoint + QPointF(32.0, -24.0), identityPoint,
                                [&] { beginVelocity(Qt::LeftButton, velocityPaintPoint); });
                            verifyTermination(*velocityInput, Qt::RightButton,
                                              velocityPoint + QPointF(32, -24), identityPoint, [&] {
                                                  beginVelocity(Qt::RightButton, velocityPoint);
                                              });
                        }
                        const auto startVelocityRelative = [&] {
                            beginVelocity(Qt::LeftButton, velocityPoint);
                        };
                        const auto releaseVelocityRelative = [&] {
                            if (velocityInput) {
                                checks::events::sendMouse(
                                    *velocityInput, QEvent::MouseButtonRelease,
                                    velocityPoint + QPointF(32, -24), Qt::LeftButton, Qt::NoButton,
                                    Qt::NoModifier);
                                QCoreApplication::processEvents();
                            }
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
        SongView &songBView = songBTab->view();
        // One non-selected-tab origin commit, matching native smoke row D:
        // the sibling tab holds the selection while the hub fans the
        // complete state out synchronously and the codec persists it once;
        // the project directory stays untouched.
        EditorViewState replacementFixture = songBView.editorViewState();
        replacementFixture.laneHeight = layout::fontPx(4.0);
        replacementFixture.laneHeights.emplace(replacementLane, layout::fontPx(4.0));
        replacementFixture.laneRanges.emplace(replacementLane, 100);
        replacementFixture.emptyLanes.emplace(replacementLane);
        window.m_workspace->selectSongTab(songATab);
        QCoreApplication::processEvents();
        check(window.m_workspace->selectedSongTab() == songATab,
              "host integration did not select the sibling tab before the "
              "non-selected lane-state origin");
        songBView.setEditorViewState(replacementFixture);
        QCoreApplication::processEvents();
        const EditorViewState replacementState = songBView.editorViewState();
        check(songATab->view().editorViewState() == replacementState &&
                  loadEditorViewState(QSettings{}) == replacementState,
              "the lane-state origin commit did not fan out and persist once");
        const QString replacementMidiPath = songBTab->document().midPath();
        const QByteArray replacementMidi = fileContents(replacementMidiPath);
        const auto projectBoundary = porydawSnapshot(scratchProject);
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
        check(replacementReady && replacement &&
                  window.m_workspace->selectedSongTab() == replacement &&
                  replacement->document().label() == songA &&
                  replacement->view().editorViewState() == replacementState &&
                  fileContents(replacementMidiPath) == replacementMidi &&
                  porydawSnapshot(scratchProject) == projectBoundary,
              "song replacement lost the global lane state or touched the project");
        if (replacement) {
            SongView &replacementView = replacement->view();
            const EditorViewState projectSwitchState = replacementView.editorViewState();
            const QString projectSwitchMidiPath = replacement->document().midPath();
            const QByteArray projectSwitchMidi = fileContents(projectSwitchMidiPath);
            window.m_workspace->requestProjectOpenAt(scratchProject);
            check(waitForProjectReady(*window.m_workspace) &&
                      window.m_workspace->openTabCount() == 0,
                  "project switch failed");
            check(porydawSnapshot(scratchProject) == projectBoundary &&
                      loadEditorViewState(QSettings{}) == projectSwitchState,
                  "project switch wrote into the project or lost the global editor state");

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
                check(closingView.editorViewState() == projectSwitchState,
                      "the post-switch tab did not project the global editor state");
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
                QByteArray midiBeforeCloseB;
                QString closeMidiPathB;
                QByteArray closeMidiB;
                int undoBeforeCloseB = -1;
                if (closingBReady && closingB) {
                    SongView &closingBView = closingB->view();
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
                check(
                    closing->document().smf().write() == midiBeforeClose &&
                        fileContents(closeMidiPath) == closeMidi &&
                        closingView.document()->undoStack()->count() == undoBeforeClose &&
                        (!closingBReady ||
                         (closingB && closingB->document().smf().write() == midiBeforeCloseB &&
                          fileContents(closeMidiPathB) == closeMidiB &&
                          closingB->view().document()->undoStack()->count() == undoBeforeCloseB)) &&
                        porydawSnapshot(scratchProject) == projectBoundary &&
                        loadEditorViewState(QSettings{}) == projectSwitchState,
                    "multi-tab application close rewrote songs, the project, or the global "
                    "editor state");
            }
        }
    }
    window.hide();
    std::printf("host-integration: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0 ? 0 : 1;
}
