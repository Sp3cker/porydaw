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

namespace checks {
class SelfTestHarness;
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

    friend int runHostIntegrationCheck(const QString &scratchProject, const QString &songA,
                                       const QString &songB, const QString &screenshotPath);
    friend class checks::SelfTestHarness;

  public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow() override;

    // Unified song+voicegroup undo/save check (--vgsavecheck; vgsavecheck.cpp).
    // Writes into the project: run against a scratch copy, with QSettings
    // already redirected by the caller. A non-empty screenshotPath saves the
    // sample picker's open popup for visual review.
    bool runVgSaveCheck(const QString &projectRoot, const QString &songLabel,
                        const QString &screenshotPath = QString());

    // Multi-tab check (--tabcheck; tabcheck.cpp): per-tab documents and undo
    // stacks, playback stopping on tab switches, tab close/replace, and
    // multi-tab session persistence. QSettings must be redirected.
    bool runTabCheck(const QString &projectRoot, const QString &songA, const QString &songB);

    // Assert restored tab persistence through the WorkspaceUi session seam
    // (--tabcheck; tabcheck.cpp).
    bool checkTabRestore(const QString &songA, const QString &songB);

    // Focused MainWindow-to-SongView drawer routing check
    // (--check-mainwindow-routing; mainwindowroutingcheck.cpp).
    bool runMainWindowRoutingCheck(const QString &projectRoot, const QString &songA,
                                   const QString &songB);

    // Register Song action wiring (part of --onboardcheck; onboardcheck.cpp):
    // a partially registered song keeps the action enabled, and running it
    // heals the registration. Writes into the project: scratch copy only,
    // QSettings must be redirected. Failures count into onboardcheck's total.
    bool runRegisterActionCheck(const QString &projectRoot, const QString &label);

    // Delete Song action wiring (part of --onboardcheck; onboardcheck.cpp):
    // deleting an open song closes its tab, drops it from the model and the
    // browser, and moves its .mid to .porydaw/trash/. Writes into the
    // project: scratch copy only, QSettings must be redirected. Failures
    // count into onboardcheck's total.
    bool runDeleteActionCheck(const QString &projectRoot, const QString &label);

    // Solo-overflow visibility gate (--polycheck stage C; polycheck.cpp):
    // the engine inverts only while the invert checkbox is checked AND the
    // Polyphony dock is visible. No project needed; QSettings must be
    // redirected.
    bool runPolyGateCheck();

    // Reopens the last session's project and open song tabs, if they still
    // exist. Called after show() on interactive launches only, so the
    // harnesses never inherit (or overwrite) the user's session.
    void restoreSession();

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
    void openSettings(SettingsDialog::Tab initialTab = SettingsDialog::Tab::Engine);
    void openSongSettings();
    void openEngineSettings();
    void openKeyboardShortcuts();
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

    // ---- Browse auditions (engine-owned; values resolved per call) ----
    const WaveData *sampleWaveFor(const QString &symbol) const;
    const uint32_t *progWaveFor(const QString &symbol) const;
    const LoadedKeysplit *keysplitFor(const QString &symbol) const;
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
    QAction *m_insertTimeAction = nullptr;
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
    QLabel *m_pcmValueLabel = nullptr;
    QLabel *m_cgbValueLabel = nullptr;
    QLabel *m_polyLostSeparator = nullptr;
    QLabel *m_polyLostCaption = nullptr;
    QLabel *m_polyLostLabel = nullptr;
    QTimer *m_uiTimer = nullptr;
    QTimer *m_playheadTimer = nullptr;
    // Last values applied to the status widgets (uiTick runs at 2 Hz idle,
    // 10 Hz during playback; unchanged values skip the label writes).
    struct PolyStatusSnapshot {
        bool loaded = false;
        int activePcm = 0;
        int maxPcm = 0;
        int activeCgb = 0;
        uint64_t lostTotal = 0;

        bool operator==(const PolyStatusSnapshot &) const = default;
    };
    std::optional<PolyStatusSnapshot> m_lastPolyStatus;
};
