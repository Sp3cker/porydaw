#pragma once

#include <QMainWindow>

#include <cstdint>
#include <memory>
#include <optional>

#include "audio/audioengine.h"
#include "project/projectworkspace.h"
#include "project/voicegroupsource.h"
#include "ui/editorviewstate.h"
#include "ui/settingsdialog.h"
#include "ui/workspaceui.h"

class QAction;
class QCloseEvent;
class QDockWidget;
class QEvent;
class FastLabel;
class QLabel;
class QSettings;
class QTimer;
class QWidget;
class MidiTimeline;
class PolyphonyPanel;
class SongTab;

namespace themes {
class ThemeController;
class ThemeDialog;
} // namespace themes

namespace songview {
class EditActions;
} // namespace songview

class OnboardingTest;
class WorkspaceSessionTest;
class WorkspaceTabsTest;
class WorkspaceTimelineSelfTest;
class WorkspaceTransportSelfTest;
class WorkspaceEditorCodecSelfTest;

namespace checks {
class VoicegroupSaveTest;
class PolyphonyGateTest;
namespace host {
class HostIntegrationTest;
} // namespace host
namespace mainwindowrouting {
class MainWindowRoutingFixture;
class MainWindowRoutingInputTest;
class MainWindowRoutingStateTest;
class MainWindowRoutingLifecycleTest;
class MainWindowRoutingNativeTest;
} // namespace mainwindowrouting
} // namespace checks

// The application shell and audio root. MainWindow is the composition root
// that owns WorkspaceUi, ProjectWorkspace, and the AudioEngine, plus the
// menus and window chrome around them. ProjectWorkspace's three publication
// streams connect straight to WorkspaceUi's three apply slots, and
// WorkspaceUi's semantic requests connect straight to ProjectWorkspace's
// slots — MainWindow adds no relay. Its own audio duty is the selected
// SongTab: it reads that tab directly, binds the engine from the tab's
// timeline/settings/lease, and retains the selected VoicegroupLease the
// engine borrows. Project policy — tabs, dialogs, placement, persistence —
// lives in WorkspaceUi; the worker and its scheduling live behind
// ProjectWorkspace.
class MainWindow : public QMainWindow
{
    Q_OBJECT

    // Qt Test classes own focused private-access seams; each exercises the
    // production flows directly instead of dedicated check entry points.
    friend class OnboardingTest;
    friend class WorkspaceSessionTest;
    friend class WorkspaceTabsTest;
    friend class WorkspaceTimelineSelfTest;
    friend class WorkspaceTransportSelfTest;
    friend class WorkspaceEditorCodecSelfTest;
    friend class checks::VoicegroupSaveTest;
    friend class checks::PolyphonyGateTest;
    friend class checks::host::HostIntegrationTest;
    friend class checks::mainwindowrouting::MainWindowRoutingFixture;
    friend class checks::mainwindowrouting::MainWindowRoutingInputTest;
    friend class checks::mainwindowrouting::MainWindowRoutingStateTest;
    friend class checks::mainwindowrouting::MainWindowRoutingLifecycleTest;
    friend class checks::mainwindowrouting::MainWindowRoutingNativeTest;

  public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow() override;

  signals:
    // Observable completion boundary for editor-view persistence: emitted
    // once per semantic hub change, after the store mutation.
    void editorViewStatePersisted(const EditorViewState &state);

  protected:
    void closeEvent(QCloseEvent *event) override;
    void changeEvent(QEvent *event) override;

  private slots:
    void saveSong();
    void exportWav();
    void openSettings(bool songFirst = false);
    void uiTick();

  private:
    void buildUi(const EditorViewState &initialEditorViewState);
    void updateWindowFrameTheme();

    // ---- Selected-tab audio handoff ----
    // A new selection stops the outgoing tab's playback, unloads the engine
    // for a null/not-ready selection before the retained lease is released,
    // and otherwise binds the engine from the tab and retains its lease.
    void onSelectedTabChanged(SongTab *tab);
    // The selected tab reached its terminal VoicegroupBound: bind.
    void onSelectedTabReady(SongTab *tab);
    // The selected tab's document, bank, or registration state changed:
    // refresh the chrome that reads the loaded state.
    void onSelectedSongStateChanged();
    // Full (re)bind of a ready selected tab.
    void applySelectedAudio();
    // Diff-based engine refresh: publishes a rebuilt timeline (hot), swaps a
    // replaced bank (cold), and re-applies song settings only when each
    // actually changed.
    void refreshSelectedAudio();
    // Pushes the tab's timeline/track-name/voice-name context into the
    // Polyphony dock (null clears it).
    void updatePolyPanelContext(SongTab *tab);
    // The tab's cfg (volume/reverb) merged with the global engine knobs —
    // everything AudioEngine::updateSettings applies.
    SongSettings songSettingsFor(const SongTab &tab) const;

    // ---- Canonical edit actions ----
    // The one retarget seam for the production set, called only at
    // selected-tab and readiness changes. A change of target unbinds before
    // the fresh bind — the narrowed borrow contract allows no live handover —
    // and a null or unready view leaves every action disabled through the
    // set's own refresh. All other state updates ride the set's target
    // observations.
    void rebindEditActions(SongTab *tab);

    // ---- Browse auditions (engine-owned; values resolved per call) ----
    // Browse-audition a keysplit instrument: play whatever sub-voice the
    // audition key (middle C) resolves to, with that sub-voice's own envelope
    // — the same resolution the engine does per note (resolve_voice).
    void auditionKeysplit(const QString &symbol);

    // The one editor-view persistence sink: each hub change writes the
    // complete state through *m_themeSettings. No in-memory mirror exists.
    void persistEditorViewState(const EditorViewState &state);

    // ---- Chrome ----
    // One recomputation of every menu action's enablement from the workspace,
    // project state, and the selected tab.
    void updateChrome();
    void updateWindowTitle();
    void updateTransportActions();
    void syncMasterVolumeControl();
    void syncScaleControls();
    void synchronizePlayhead();
    void updateTimeLabel();
    void updatePolyStatus();
    // ---- Transport ----
    // Starts (or resumes) playback; from Stopped, seeks to the edit cursor
    // first so playback begins there. fromEditCursor forces that seek even
    // out of Paused — the Space binding (Reaper-style restart), while the
    // Play button resumes from the pause point.
    void startPlayback(bool fromEditCursor = false);
    void pausePlayback();
    void stopPlayback();
    QString formatTime(uint64_t samples) const;
    bool selectedSongRegistrationPending() const;

    // The fixed composition root (see the check contracts). WorkspaceUi and
    // the engine outlive ProjectWorkspace, whose worker borrows nothing from
    // them; the selected binding pins the engine's borrowed bank.
    std::unique_ptr<WorkspaceUi> m_workspace;
    std::unique_ptr<ProjectWorkspace> m_projectWorkspace;
    AudioEngine m_audio;
    SongTab *m_selectedTab = nullptr;
    VoicegroupLease m_selectedVoicegroup;

    // The selected-tab audio as last handed to the engine — the diff input
    // for the focused update paths. The engine's own getters lag hot
    // publishes (TimelineHandoff flips active() only at the callback), so
    // MainWindow keeps this one record.
    const MidiTimeline *m_appliedTimeline = nullptr;
    std::optional<SongSettings> m_appliedSettings;

    bool m_audioOk = false;
    // False during harness runs so they don't overwrite the window-chrome
    // QSettings (geometry, state, song filters). Tab/session persistence is
    // WorkspaceUi's and always runs; harnesses redirect QSettings instead.
    bool m_persistSession = true;
    bool m_closeInProgress = false;
    bool m_closeAccepted = false;
    EngineSettings m_engineSettings;

    std::unique_ptr<QSettings> m_themeSettings;
    std::unique_ptr<themes::ThemeController> m_themeController;
    std::unique_ptr<themes::ThemeDialog> m_themeDialog;
    // The one production canonical edit action set (songview::EditActions).
    // The Edit menu borrows its QActions for presentation, and the four
    // song-command pointers below are borrowed views of the same objects —
    // never owning duplicates or separate handlers.
    std::unique_ptr<songview::EditActions> m_editActions;
    // Borrowed presentation pointers into m_editActions (Window-class
    // commands), assigned once next to the menu composition.
    QAction *m_openProjectAction = nullptr;
    QAction *m_newSongAction = nullptr;
    QAction *m_importAction = nullptr;
    QAction *m_importSampleAction = nullptr;
    QAction *m_registerAction = nullptr;
    QAction *m_closeTabAction = nullptr;
    QAction *m_saveAction = nullptr;
    QAction *m_undoAction = nullptr;
    QAction *m_redoAction = nullptr;
    QAction *m_exportWavAction = nullptr;
    QAction *m_copyAction = nullptr;
    QAction *m_soloAction = nullptr;
    QAction *m_insertTimeAction = nullptr;
    QAction *m_deleteTimeAction = nullptr;
    QAction *m_settingsAction = nullptr;
    QAction *m_eventListAction = nullptr;
    QAction *m_automationDrawerAction = nullptr;
    QAction *m_velocityDrawerAction = nullptr;
    QAction *m_voiceChangesDrawerAction = nullptr;
    QAction *m_velocityColorsAction = nullptr;
    QAction *m_noteNamesAction = nullptr;
    QDockWidget *m_polyDock = nullptr;
    PolyphonyPanel *m_polyPanel = nullptr;
    QWidget *m_polyMeter = nullptr;
    FastLabel *m_pcmValueLabel = nullptr;
    FastLabel *m_cgbValueLabel = nullptr;
    QLabel *m_polyLostSeparator = nullptr;
    QLabel *m_polyLostCaption = nullptr;
    QLabel *m_polyLostLabel = nullptr;
    QTimer *m_uiTimer = nullptr;
    QTimer *m_playheadTimer = nullptr;
};
