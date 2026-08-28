#pragma once

#include <QHash>
#include <QList>
#include <QObject>
#include <QPair>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVector>

#include <cstdint>
#include <memory>
#include <optional>
#include <vector>

#include "porydaw_scale.h"
#include "project/projectidentity.h"
#include "project/projectworkspace.h"
#include "ui/editorviewstate.h"
#include "ui/viewsidecar.h"
#include "ui/voicegroupbrowser.h"
#include "ui/voicegroupviewcache.h"

class QAction;
class QDockWidget;
class QMainWindow;
class QMenu;
class QMessageBox;
class QTabWidget;
class QWidget;
class NewSongWizard;
class SongListPanel;
class SongTab;
class SongView;
class TransportBar;

namespace keymap {
class Registry;
}

namespace checks {
class VoicegroupBrowserDriver;
}

// The workspace controller: owns every open SongTab, their selection,
// lifetime, and order; the Songs dock, VoicegroupBrowser dock, and
// TransportBar chrome; the private VoicegroupViewCache shared-bank
// coordinator; the transient closed-loading tombstones; and the project
// operation/dialog policy (open/save/reload, new song, register, delete,
// samples, previews, and the voicegroup picker).
//
// ProjectWorkspace is owned and wired by MainWindow: this class emits
// semantic requests (projectOpenRequested / projectOperationRequested) and
// consumes the three publication streams through the apply* slots below. It
// never includes ProjectIo, never owns AudioEngine, and never performs
// project file I/O — the QSettings startup read of the saved workspace
// recipe is the one deliberate exception.
class WorkspaceUi final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(WorkspaceUi)

  public:
    enum class PlaybackState {
        Unavailable,
        Stopped,
        Paused,
        Playing,
    };

    struct SongFilters {
        QString search;
        int sortIndex = 0;
        QString categoryPrefix;
    };

    struct ChromeObservation {
        bool transportVisible = false;
        bool songsVisible = false;
        bool voicegroupsVisible = false;
        qsizetype listedSongCount = 0;
        qsizetype listedVoiceCount = 0;
    };

    explicit WorkspaceUi(QMainWindow &host);
    ~WorkspaceUi() override;

    // ---- Selected tab (MainWindow reads it directly for audio handoff) ----

    SongTab *selectedSongTab() const noexcept { return m_selectedTab; }
    qsizetype openTabCount() const noexcept { return qsizetype(m_tabPages.size()); }
    std::vector<SongTab *> tabsInDisplayOrder() const;
    // The unique live tab carrying this song, or nullptr.
    SongTab *songTabFor(const SongName &name) const noexcept;

    // ---- Standing project state and policy gates ----

    const ProjectState &projectState() const noexcept { return m_state; }
    // Open Project action policy: disabled while Loading, while the user's
    // open request is in flight, while any tab lacks its terminal song
    // payload, or while any workspace-submitted work remains in flight.
    bool openProjectEnabled() const noexcept;
    // The single bank gate: false while a shared-bank transition is pending.
    // Gates picker edits, history mutation, undo, and redo.
    bool bankActionsEnabled() const noexcept { return m_cache.bankActionsEnabled(); }
    // True when the selected tab's document or its shared bank has unsaved
    // changes and no save is in flight for it.
    bool selectedSongDirty() const noexcept;

    // The saved workspace recipe read once at shell construction. The named
    // placeholder tabs it describes are already created; ProjectWorkspace
    // reads the same keys independently and queues the startup open.
    const SavedWorkspaceRecipe &startupRecipe() const noexcept { return m_startRecipe; }

    // ---- MainWindow entry points (menu/toolbar actions) ----

    // Open Project action: the directory dialog plus the interactive switch
    // policy (dirty prompts, in-flight gates) end in projectOpenRequested.
    void requestProjectOpen();
    // Non-dialog open seams (explicit-restoration flows and check harnesses;
    // no dialog of their own). Both run the same interactive switch policy —
    // dirty prompts and in-flight gates — before their request is emitted.
    // Requests switching to an explicit project root.
    void requestProjectOpenAt(const QString &root);
    // Opens (or focuses) an explicit song through the browser placement
    // policy; a no-op when the name is absent from the project snapshot.
    void requestSongOpen(const SongName &name, bool newTab = false);
    void selectSongTab(SongTab *tab);
    // Reload Project action: re-reads the open project's data in place.
    void requestProjectReload();
    // Save action for the selected tab: one semantic SaveSongInput.
    void saveSelectedSong();
    // Register action for the selected tab: plan request plus confirmation.
    void registerSelectedSong();
    void deleteSelectedSong();
    void requestCloseSelectedTab();
    // Undo/redo for the selected tab: document entries cross synchronously;
    // shared-bank entries route through VoicegroupViewCache and the worker.
    void requestUndo();
    void requestRedo();
    void runNewSongWizard();
    void runMidiImport();
    void importSample();
    void runCreateVoicegroupFlow();
    void toggleDrawerPage(EditorDrawerPage page);
    void setSelectedTabEventListVisible(bool visible);
    // Queues a cosmetic SaveSidecarInput for every open tab (shutdown).
    void persistSessionViews();
    // Submits CleanupPreviewInput (shutdown / project switch).
    void cleanupPreview();
    // The save-all prompt chain: every dirty tab is offered a save (each
    // focused as it asks); completion(false) means the user cancelled.
    // Shared by the interactive project switch and the application-close
    // chain; saves answered before a Cancel have already queued.
    void promptSaveAll(const std::function<void(bool)> &continuation);

    // ---- MainWindow-pushed audio state ----

    // Copied engine sample rate for tab timeline projections; applies to the
    // open tabs and to every tab created afterwards.
    void setAudioSampleRate(double sampleRate);
    // The audition sample set for engine auditions; empty until loaded.
    SampleSetLease sampleSet() const noexcept { return m_sampleSet; }

    // ---- Chrome (preserved surface) ----

    void restoreSongFilters(const SongFilters &filters);
    SongFilters songFilters() const;
    void focusSongSearch();
    void focusSongList();
    bool isSongListed(const QString &label) const;
    qsizetype listedSongCount() const noexcept;
    void bindFindSongShortcut(keymap::Registry &registry);

    void setTransportPlaybackState(PlaybackState state);
    void setTransportSongAvailable(bool available);
    void setTransportTimeText(const QString &text);
    void setTransportMasterVolume(int volume, bool enabled);
    void setTransportOutputVolume(int volume);
    void setTransportScaleState(int root, porydaw_scale::ScaleId scale, bool highlight, bool fold);
    void setTransportResonanceSuppression(bool enabled);
    void triggerPlayPause();
    void addFollowPlayheadActionTo(QMenu &menu);

    void showVoicegroupPanel();
    void setVelocityColorMode(bool enabled);
    void setNoteNameMode(bool enabled);
    void setFollowPlayhead(bool enabled);
    void setEditorDrawerState(const EditorDrawerState &state);

    ChromeObservation observeChrome() const;

  public slots:
    // The three direct publication streams; MainWindow connects
    // ProjectWorkspace's signals straight to these.
    void applyProjectState(ProjectState state);
    void applyProjectEvent(ProjectEvent event);
    void applySongUpdate(SongUpdate update);

  signals:
    // Semantic requests: MainWindow connects these to ProjectWorkspace's
    // slots without relaying payloads.
    void projectOpenRequested(OpenProjectInput input);
    void projectOperationRequested(ProjectOperation operation);

    // Selection and selected-tab state for MainWindow's audio handoff,
    // window title, and action enablement. Re-read the tab; no aggregate
    // crosses the seam.
    void selectedSongTabChanged(SongTab *tab);
    // A tab reached its terminal VoicegroupBound; MainWindow rebinds the
    // engine when it is the selected one.
    void songTabReady(SongTab *tab);
    // The selected tab's document, bank, or registration state changed.
    void selectedSongStateChanged();
    // The global bank gate flipped (a shared-bank transition began/ended).
    void bankActionsChanged(bool enabled);
    void openProjectEnabledChanged(bool enabled);
    void statusMessageRequested(const QString &message, int timeout = 0);
    void sessionsReordered();

    void goToStartRequested();
    void playRequested();
    void playPauseRequested();
    void pauseRequested();
    void stopRequested();
    void loopEnabledChanged(bool enabled);
    void followPlayheadChanged(bool enabled);
    void resonanceSuppressionChanged(bool enabled);
    void masterVolumeChanged(int value);
    void outputVolumeChanged(int value);
    void scaleRootChanged(int root);
    void scaleIdChanged(porydaw_scale::ScaleId scale);
    void scaleHighlightChanged(bool enabled);
    void scaleFoldChanged(bool enabled);

    void selectedTabMuteMaskChanged(uint32_t mask);
    void selectedTabSoloMaskChanged(uint32_t mask);
    void selectedTabEventListChanged(bool visible);
    void editorDrawerStateEdited(const EditorDrawerState &state);
    void editCursorSeekRequested(uint64_t tick);
    void playPauseFromRequested(uint64_t tick);

    // Audition intents are copied values; MainWindow owns every engine call.
    void auditionNoteRequested(uint8_t track, uint8_t key, uint8_t velocity);
    void auditionNoteTimedRequested(uint8_t track, uint8_t key, uint8_t velocity,
                                    uint32_t durationSamples);
    void auditionVoiceRequested(uint8_t voice, uint8_t key, uint8_t velocity);
    void sampleAuditionRequested(const QString &symbol, VgAuditionKind kind,
                                 const AuditionSlots::Adsr &adsr);
    void sampleAuditionStopRequested();

  private:
    friend class checks::VoicegroupBrowserDriver;

    // ---- Tab lifecycle and placement (workspaceui_tabs.cpp) ----
    static SongTab *tabForWidget(const QWidget *widget) noexcept;
    SongTab *createTab(SongName name, const QString &title, bool activate);
    SongTab *createLoadTab(const SongName &name, bool activate);
    void openSongFromList(int songId, bool newTab);
    void destroyAllTabs();
    void removeTab(SongTab *tab);
    void selectTab(SongTab *tab);
    void publishSelectedIfChanged();
    void refreshTabTitle(SongTab *tab);
    void persistTabs();
    void maybeSaveTab(SongTab *tab, const std::function<void(bool)> &continuation);
    // Gates: pending bank origin, in-flight save, dirty prompt; then close.
    void requestCloseTab(SongTab *tab);
    void closeTabNow(SongTab *tab);
    void submitSaveForTab(SongTab *tab, const std::function<void(bool)> &continuation);
    bool bankDirty(const SongTab &tab) const noexcept;
    const LoadedBankView *bankViewFor(const SongTab &tab) const noexcept;
    // The exhaustive SongUpdate payload dispatch, one overload per stage.
    void applyStagedUpdate(const SongName &name, MidiStage &stage);
    void applyStagedUpdate(const SongName &name, SidecarStage &stage);
    void applyStagedUpdate(const SongName &name, VoicegroupBound &bound);
    void applyStagedUpdate(const SongName &name, SongSaved &saved);
    void applyStagedUpdate(const SongName &name, SongFailed &failed);
    void handleSongFailed(const SongName &name, SongFailed failed);
    void onTabEdited(SongTab *tab);
    void startVoicegroupRebind(SongTab &tab);
    void applySampleRateToTabs();

    // ---- Project state and events (workspaceui_project.cpp) ----
    void reconcileSnapshot();
    void beginProjectSwitch(const QString &dir);
    void teardownStartupPlaceholders();
    void clearStartupSongKeys();
    void updateOpenGate();
    void consumeDialogOperation();
    const SongInfo *listedSongAt(int songId) const;
    void runRegisterFlow(const SongInfo &song);
    void applyBankView(LoadedBankView view);
    void confirmRegistration(const RegistrationPlanResult &result);
    void runDeleteFlow(const SongInfo &song);
    void confirmDeletion(const DeletionPlanResult &result);
    void handleSongCreated(const SongCreated &created);
    void submitCreateSong(NewSongWizard &wizard);

    // ---- Voicegroup bank coordinator and picker (workspaceui_voicegroup.cpp) ----
    void beginBankTransition(PendingBankTransition transition, const VoicegroupEditInput &draft);
    void submitPickerEdit(int slot, const VgVoice &voice);
    void rebuildVoicegroupPresentation();
    void syncVoicegroupLoading();
    void updateVoicegroupDockTitle();
    void resolveBankApplied(const VoicegroupEditApplied &outcome);
    void resolveBankConflict(const VoicegroupEditConflict &outcome);
    void resolveBankHardError(const VoicegroupMutationFailed &failure);
    void routeHistoryRequest(bool undo);
    QString mintSynthSymbol(const VgSynthDesc &desc);
    // Loop badge / detail metadata for the picker's sample rows, resolved
    // from the published catalog's DirectSound list against the audition
    // sample set's parallel waves (the SampleSetLease seam).
    SamplePickInfo samplePickInfoFor(const QString &symbol) const;
    void dropSavedPendingSynths(const SongTab &tab);
    QList<QPair<QString, VgSynthDesc>> pendingSynthDefsFor(const LoadedBankView &view) const;

    // ---- Sample, song-creation, and dialog workflows (workspaceui_samples.cpp) ----
    void ensureSampleSet();
    void runImportFlow(std::optional<int> slot);
    void continueImportFlow(const SampleFormatProbe &probe);
    void runEditSampleFlow(int slot);
    void continueEditSampleFlow(const SampleRead &read);
    void handleSampleCommitted(const SampleCommitted &committed);
    bool validateNewSampleName(const QString &name, QString *error) const;

    // ---- Shared wiring helpers (workspaceui.cpp) ----
    void buildUi();
    void wireTab(SongTab *tab);
    void wireBrowser();
    void persistViewSidecar(SongTab *tab);
    void showStatus(const QString &message, int timeout = 5000);
    const SongInfo *songInfoFor(const SongName &name) const;
    bool projectBusy() const noexcept;

    QMainWindow &m_host;
    TransportBar *m_transport = nullptr;
    SongListPanel *m_songList = nullptr;
    QDockWidget *m_songsDock = nullptr;
    VoicegroupBrowser *m_voicegroupBrowser = nullptr;
    QDockWidget *m_voicegroupDock = nullptr;
    QTabWidget *m_tabs = nullptr;
    QAction *m_findSongAction = nullptr;

    std::vector<std::unique_ptr<SongTab>> m_tabPages;
    SongTab *m_selectedTab = nullptr;

    ProjectState m_state;
    SavedWorkspaceRecipe m_startRecipe;
    VoicegroupViewCache m_cache;
    QSet<SongName> m_tombstones;          // closed while their load was in flight
    QSet<SongName> m_inFlightLoads;       // submitted Open/ReloadSongInput
    QSet<SongName> m_inFlightSaves;       // submitted SaveSongInput
    QSet<SongName> m_closeAfterSave;      // close the tab when its save lands
    QSet<SongName> m_rebindSkip;          // cfg-driven reload: skip Midi/Sidecar stages
    QHash<SongName, QString> m_boundArgs; // per-tab -G arg at VoicegroupBound
    QSet<SongName> m_startupPlaceholders; // recipe tabs awaiting their terminal payload
    int m_dialogOps = 0;                  // keyed dialog operations in flight

    QString m_pendingOpenDir; // user open awaiting its prompts
    std::optional<int> m_pendingImportSlot;
    QString m_pendingEditSampleName;
    int m_pendingEditSampleSlot = -1;
    QString m_pendingCreatedLabel;
    bool m_pendingCreatedNewVoicegroup = false;
    QString m_pendingDeleteSong;
    QString m_pendingVoicegroupArg; // new-voicegroup assignment to the selected song

    QHash<QString, VgSynthDesc> m_pendingSynths; // minted-but-unsaved synth definitions
    SampleSetLease m_sampleSet;
    std::optional<LoadedBankView> m_bankView; // stable presentation copy the picker borrows
    QPointer<QMessageBox> m_registerConfirmation;
    QPointer<QMessageBox> m_deleteConfirmation;

    double m_audioSampleRate = 0.0;
    bool m_openRequested = false;      // this class submitted an open
    bool m_awaitingStartupOpen = true; // startup placeholders await the first terminal
    bool m_openGatePublished = true;
    bool m_tearingDown = false;
    bool m_velocityColorMode = false;
    bool m_noteNameMode = false;
    bool m_followPlayhead = true;
    EditorDrawerState m_editorDrawerState;
};
