#include "mainwindow.h"

#include <QApplication>
#include <QComboBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDir>
#include <QDockWidget>
#include <QDoubleSpinBox>
#include <QFileDialog>
#include <QFileInfo>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QKeySequence>
#include <QLabel>
#include <QLineEdit>
#include <QMenuBar>
#include <QMessageBox>
#include <QPlainTextEdit>
#include <QPointer>
#include <QProgressDialog>
#include <QSettings>
#include <QSignalBlocker>
#include <QSpinBox>
#include <QStatusBar>
#include <QTextEdit>
#include <QTimer>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <dwmapi.h>
#include <windows.h>
#endif

#include <utility>

#include "audio/wavexport.h"
#include "core/miditimeline.h"
#include "porydaw_scale.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/polyphonypanel.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/theme/themecontroller.h"
#include "ui/theme/themedialog.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

namespace {
constexpr int kIdleUiIntervalMs = 500;
constexpr int kPlaybackUiIntervalMs = 100;

const QString kVelocityColorsKey = QStringLiteral("velocityNoteColors");
const QString kNoteNamesKey = QStringLiteral("noteNames");
const QString kSystemFontKey = QStringLiteral("systemFont");
const QString kFollowPlayheadKey = QStringLiteral("followPlayhead");
const QString kOutputVolumeKey = QStringLiteral("outputVolume");
const QString kResonanceSuppressionKey = QStringLiteral("dsp/resonanceSuppression");

void resetInheritedWidgetFonts()
{
    QList<QPointer<QWidget>> widgets;
    widgets.reserve(QApplication::allWidgets().size());
    for (auto *widget : QApplication::allWidgets())
        widgets.append(widget);

    for (const auto &widget : widgets) {
        if (widget && widget->font().resolveMask() == 0)
            widget->setFont(QFont());
    }
}

// SongSettings carries no equality; exact equality of applied inputs is the
// intent (every field is re-derived from the same sources).
bool sameSongSettings(const SongSettings &a, const SongSettings &b)
{
    return a.pcmMixer == b.pcmMixer && a.songVolume == b.songVolume && a.reverb == b.reverb &&
           a.maxPcmChannels == b.maxPcmChannels && a.pcmMixRate == b.pcmMixRate &&
           a.analogFilter == b.analogFilter;
}

// Symbol -> index into the sample set's parallel arrays (the set was loaded
// from the catalog lists in this order), or -1.
int sampleSetIndex(const QStringList &symbols, int limit, const QString &symbol)
{
    const int index = symbols.indexOf(symbol);
    return index >= 0 && index < limit ? index : -1;
}

#ifdef Q_OS_WIN
// These names and values come from the current Windows SDK. The bundled
// MinGW header stops at DWMWA_PASSIVE_UPDATE_MODE, so keep the compatibility
// values strongly typed until its dwmapi.h catches up. Both attributes exist
// since Windows 11; on Windows 10 DwmSetWindowAttribute rejects them and the
// stock title bar stays, which is the intended graceful fallback.
enum class DwmWindowAttribute : DWORD {
    CaptionColor = 35, // DWMWA_CAPTION_COLOR
    TextColor = 36,    // DWMWA_TEXT_COLOR
};
#endif

} // namespace

MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent)
{
    setWindowTitle(QStringLiteral("porydaw"));
    resize(::layout::fontPx(92), ::layout::fontPx(57));
    m_engineSettings = EngineSettings::load();
    m_themeSettings = std::make_unique<QSettings>();
    m_themeController = std::make_unique<themes::ThemeController>(*qApp, *m_themeSettings);
    // Before restore(): the theme apply installs the Body font, so the
    // system-font preference must already be in force for the first paint.
    typography::setUseSystemFont(m_themeSettings->value(kSystemFontKey, false).toBool());
    m_themeController->restore();
    const EditorViewState initialEditorViewState = loadEditorViewState(*m_themeSettings);
    updateWindowFrameTheme();
    m_themeDialog = std::make_unique<themes::ThemeDialog>(*m_themeController, this);
    buildUi(initialEditorViewState);

    QSettings settings;
    restoreGeometry(settings.value(QStringLiteral("windowGeometry")).toByteArray());
    restoreState(settings.value(QStringLiteral("windowState")).toByteArray());
    m_workspace->restoreSongFilters(
        {settings.value(QStringLiteral("songFilterText")).toString(),
         settings.value(QStringLiteral("songFilterSort")).toInt(),
         settings.value(QStringLiteral("songFilterCategory")).toString()});

    // Composition order: WorkspaceUi first (the shell and its startup
    // placeholder tabs), then the engine, then the worker seam — whose
    // constructor queues the saved recipe's open for the next event-loop
    // turn, after everything below is wired.
    QString audioError;
    m_audioOk = m_audio.init(&audioError);
    if (!m_audioOk) {
        QMessageBox::warning(this, tr("Audio Error"),
                             tr("%1\n\nPlayback will be unavailable.").arg(audioError));
    } else if (m_audio.usingNullBackend() && !m_audio.nullBackendForced()) {
        // Non-modal: harnesses construct MainWindow offscreen and must not
        // block on a dialog (CI runs without a real audio server).
        auto *box = new QMessageBox(QMessageBox::Warning, tr("No Audio Output"),
                                    tr("No working audio backend was found, so playback will be "
                                       "silent.\n\nOn WSL this usually means the Linux distro is "
                                       "missing the PulseAudio client library (sudo apt install "
                                       "libpulse0) or WSLg is out of date (run \"wsl --update\" "
                                       "from Windows, then restart WSL)."),
                                    QMessageBox::Ok, this);
        box->setAttribute(Qt::WA_DeleteOnClose);
        box->show();
    }
    statusBar()->showMessage(
        !m_audioOk ? tr("No audio device.")
        : m_audio.usingNullBackend()
            ? tr("No audio output: silent null device.")
            : tr("Audio ready (%1 Hz, %2). Open a decomp project to get started.")
                  .arg(int(m_audio.sampleRate()))
                  .arg(m_audio.backendName()));
    // Tabs build their timeline projections at the engine's resolved rate.
    m_workspace->setAudioSampleRate(m_audio.sampleRate());
    m_workspace->setSampleAuditionEngine(m_audioOk ? &m_audio : nullptr);

    m_projectWorkspace = std::make_unique<ProjectWorkspace>();
    // Direct publication wiring — no relays. WorkspaceUi's apply slots are
    // connected before MainWindow's own publication reactions so chrome
    // updates observe the applied state, not the pre-apply one.
    connect(m_projectWorkspace.get(), &ProjectWorkspace::projectStatePublished, m_workspace.get(),
            &WorkspaceUi::applyProjectState);
    connect(m_projectWorkspace.get(), &ProjectWorkspace::projectEventPublished, m_workspace.get(),
            &WorkspaceUi::applyProjectEvent);
    connect(m_projectWorkspace.get(), &ProjectWorkspace::songUpdatePublished, m_workspace.get(),
            &WorkspaceUi::applySongUpdate);
    connect(m_projectWorkspace.get(), &ProjectWorkspace::projectStatePublished, this,
            [this](const ProjectState &) {
                updateWindowTitle();
                updateChrome();
            });
    // Semantic requests: straight into ProjectWorkspace's slots.
    connect(m_workspace.get(), &WorkspaceUi::projectOpenRequested, m_projectWorkspace.get(),
            &ProjectWorkspace::openProject);
    connect(m_workspace.get(), &WorkspaceUi::projectOperationRequested, m_projectWorkspace.get(),
            &ProjectWorkspace::submit);

    m_uiTimer = new QTimer(this);
    m_playheadTimer = new QTimer(this);

    m_uiTimer->setInterval(kIdleUiIntervalMs);
    connect(m_uiTimer, &QTimer::timeout, this, &MainWindow::uiTick);
    m_uiTimer->start();
    m_playheadTimer->setTimerType(Qt::PreciseTimer);
    // 60hz is 16.6 ms; Qt can tick faster than this, making the playhead move
    // faster than 60hz and wasting time.
    m_playheadTimer->setInterval(17);
    connect(m_playheadTimer, &QTimer::timeout, this, &MainWindow::synchronizePlayhead);
    // The workspace published its construction-time selection (the startup
    // placeholder tab) before these connections existed; adopt it now so
    // the later songTabReady publication binds the engine for it.
    onSelectedTabChanged(m_workspace->selectedSongTab());
    updateTimeLabel();
    updatePolyStatus();

    updateChrome();
    updateTransportActions();
    syncMasterVolumeControl();
    syncScaleControls();
    updateWindowTitle();
}

MainWindow::~MainWindow()
{
    if (m_uiTimer)
        m_uiTimer->stop();
    if (m_playheadTimer)
        m_playheadTimer->stop();
    // Stop the audio thread first: the engine borrows the retained bank
    // until shutdown() returns.
    m_audio.shutdown();
    // Then release the retained lease, before the tabs and the shared-bank
    // view cache release theirs.
    m_selectedVoicegroup = {};
    // Tab leases and the view cache die with the workspace...
    m_workspace.reset();
    // ...and the worker joins last: no GUI lease outlives Project I/O.
    m_projectWorkspace.reset();
}

void MainWindow::buildUi(const EditorViewState &initialEditorViewState)
{
    // Every user-facing action registers with the keymap so its shortcut is
    // rebindable; the registry owns defaults and re-applies user changes.
    auto &keys = keymap::Registry::instance();

    // Menu
    QMenu *fileMenu = menuBar()->addMenu(tr("&File"));
    m_openProjectAction = fileMenu->addAction(tr("&Open Project..."), this,
                                              [this] { m_workspace->requestProjectOpen(); });
    keys.attach(QStringLiteral("file.open_project"), m_openProjectAction);
    m_newSongAction =
        fileMenu->addAction(tr("&New Song..."), this, [this] { m_workspace->runNewSongWizard(); });
    keys.attach(QStringLiteral("file.new_song"), m_newSongAction);
    m_newSongAction->setEnabled(false);
    m_importAction =
        fileMenu->addAction(tr("&Import MIDI..."), this, [this] { m_workspace->runMidiImport(); });
    keys.attach(QStringLiteral("file.import_midi"), m_importAction);
    m_importAction->setEnabled(false);
    m_saveAction = fileMenu->addAction(tr("&Save Song"), this, &MainWindow::saveSong);
    keys.attach(QStringLiteral("file.save_song"), m_saveAction);
    m_saveAction->setEnabled(false);
    m_registerAction = fileMenu->addAction(tr("Re&gister Song"), this,
                                           [this] { m_workspace->registerSelectedSong(); });
    keys.attach(QStringLiteral("file.register_song"), m_registerAction);
    m_registerAction->setEnabled(false);
    m_closeTabAction = fileMenu->addAction(tr("&Close Tab"), this,
                                           [this] { m_workspace->requestCloseSelectedTab(); });
    keys.attach(QStringLiteral("file.close_tab"), m_closeTabAction);
    m_closeTabAction->setEnabled(false);
    fileMenu->addSeparator();
    m_exportWavAction = fileMenu->addAction(tr("Export &WAV..."), this, &MainWindow::exportWav);
    keys.attach(QStringLiteral("file.export_wav"), m_exportWavAction);
    m_exportWavAction->setEnabled(false);
    fileMenu->addSeparator();
    QAction *quitAction = fileMenu->addAction(tr("&Quit"), this, &QWidget::close);
    keys.attach(QStringLiteral("file.quit"), quitAction);

    QMenu *editMenu = menuBar()->addMenu(tr("&Edit"));
    m_undoAction = editMenu->addAction(tr("&Undo"), this, [this] { m_workspace->requestUndo(); });
    keys.attach(QStringLiteral("edit.undo"), m_undoAction);
    m_undoAction->setEnabled(false);
    m_redoAction = editMenu->addAction(tr("&Redo"), this, [this] { m_workspace->requestRedo(); });
    keys.attach(QStringLiteral("edit.redo"), m_redoAction);
    m_redoAction->setEnabled(false);
    editMenu->addSeparator();
    m_copyAction = new QAction(tr("&Copy"), this);
    m_copyAction->setObjectName(QStringLiteral("copyWindowAction"));
    m_copyAction->setShortcutContext(Qt::WindowShortcut);
    keys.attach(QStringLiteral("roll.copy"), m_copyAction);
    connect(m_copyAction, &QAction::triggered, this, [this] {
        if (auto *lineEdit = qobject_cast<QLineEdit *>(QApplication::focusWidget())) {
            lineEdit->copy();
            return;
        }
        if (auto *plainTextEdit = qobject_cast<QPlainTextEdit *>(QApplication::focusWidget())) {
            plainTextEdit->copy();
            return;
        }
        if (auto *textEdit = qobject_cast<QTextEdit *>(QApplication::focusWidget())) {
            textEdit->copy();
            return;
        }
        if (m_selectedTab)
            m_selectedTab->view().copySelection();
    });
    editMenu->addAction(m_copyAction);
    m_copyAction->setEnabled(false);
    m_insertTimeAction = new QAction(tr("Insert &Time..."), this);
    connect(m_insertTimeAction, &QAction::triggered, this, [this] {
        if (m_selectedTab)
            m_selectedTab->view().insertTimeAtPlaybackCursor();
    });
    m_insertTimeAction->setObjectName(QStringLiteral("insertTimeWindowAction"));
    m_insertTimeAction->setShortcutContext(Qt::WindowShortcut);
    keys.attach(QStringLiteral("edit.insert_time"), m_insertTimeAction);
    editMenu->addAction(m_insertTimeAction);
    m_insertTimeAction->setEnabled(false);
    editMenu->addSeparator();
    QAction *preferencesAction = editMenu->addAction(tr("Prefere&nces..."), this, [this] {
        openSettings(m_selectedTab ? SettingsDialog::Tab::Song : SettingsDialog::Tab::Engine);
    });
    preferencesAction->setMenuRole(QAction::PreferencesRole);
    keys.attach(QStringLiteral("edit.preferences"), preferencesAction);

    m_settingsAction =
        editMenu->addAction(tr("Song Se&ttings..."), this, &MainWindow::openSongSettings);
    keys.attach(QStringLiteral("edit.song_settings"), m_settingsAction);
    m_settingsAction->setEnabled(false);
    // Global GBA-accuracy knobs (SPEC §7); not song-scoped, so always enabled.
    QAction *engineSettingsAction =
        editMenu->addAction(tr("&Engine Settings..."), this, &MainWindow::openEngineSettings);
    keys.attach(QStringLiteral("edit.engine_settings"), engineSettingsAction);
    QAction *shortcutsAction =
        editMenu->addAction(tr("&Keyboard Shortcuts..."), this, &MainWindow::openKeyboardShortcuts);
    keys.attach(QStringLiteral("edit.keyboard_shortcuts"), shortcutsAction);
    auto *viewMenu = menuBar()->addMenu(tr("&View"));
    // View menu: piano roll vs raw MIDI event list, per tab.
    m_eventListAction = viewMenu->addAction(tr("MIDI &Event List"));
    m_eventListAction->setCheckable(true);
    keys.attach(QStringLiteral("view.event_list"), m_eventListAction);
    m_eventListAction->setEnabled(false);
    connect(m_eventListAction, &QAction::toggled, this,
            [this](bool on) { m_workspace->setSelectedTabEventListVisible(on); });

    m_automationDrawerAction = viewMenu->addAction(tr("Automation Lanes"));
    m_automationDrawerAction->setObjectName(QStringLiteral("automationDrawerWindowAction"));
    m_automationDrawerAction->setShortcut(QKeySequence(Qt::Key_A));
    m_automationDrawerAction->setShortcutContext(Qt::WindowShortcut);
    m_automationDrawerAction->setToolTip(tr("Show or hide automation lanes (A)"));
    m_automationDrawerAction->setEnabled(false);
    connect(m_automationDrawerAction, &QAction::triggered, this,
            [this] { m_workspace->toggleDrawerPage(EditorDrawerPage::Automations); });
    m_velocityDrawerAction = viewMenu->addAction(tr("Velocity Lane"));
    m_velocityDrawerAction->setObjectName(QStringLiteral("velocityDrawerWindowAction"));
    m_velocityDrawerAction->setShortcut(QKeySequence(Qt::Key_V));
    m_velocityDrawerAction->setShortcutContext(Qt::WindowShortcut);
    m_velocityDrawerAction->setToolTip(tr("Show or hide note velocities (V)"));
    m_velocityDrawerAction->setEnabled(false);
    connect(m_velocityDrawerAction, &QAction::triggered, this,
            [this] { m_workspace->toggleDrawerPage(EditorDrawerPage::Velocity); });
    m_voiceChangesDrawerAction = viewMenu->addAction(tr("Voice &Changes"));
    m_voiceChangesDrawerAction->setObjectName(QStringLiteral("voiceChangesDrawerWindowAction"));
    m_voiceChangesDrawerAction->setShortcut(QKeySequence(Qt::Key_P));
    m_voiceChangesDrawerAction->setShortcutContext(Qt::WindowShortcut);
    m_voiceChangesDrawerAction->setToolTip(tr("Show or hide voice changes (P)"));
    m_voiceChangesDrawerAction->setEnabled(false);
    connect(m_voiceChangesDrawerAction, &QAction::triggered, this,
            [this] { m_workspace->toggleDrawerPage(EditorDrawerPage::VoiceChanges); });

    // Tools menu: project-level utilities that aren't song-scoped.
    QMenu *toolsMenu = menuBar()->addMenu(tr("&Tools"));
    m_importSampleAction = toolsMenu->addAction(tr("Import &Sample..."), this,
                                                [this] { m_workspace->importSample(); });
    keys.attach(QStringLiteral("tools.import_sample"), m_importSampleAction);
    m_importSampleAction->setEnabled(false);

    QMenu *helpMenu = menuBar()->addMenu(tr("&Help"));
    QAction *aboutAction = helpMenu->addAction(tr("&About porydaw"), this, [this] {
        QMessageBox::about(this, tr("About porydaw"),
                           tr("<h3>porydaw %1</h3>"
                              "<p>A music editor for the Pokémon generation 3 "
                              "decompilation projects "
                              "(<a href=\"https://github.com/pret/pokeruby\">pokeruby</a>, "
                              "<a href=\"https://github.com/pret/pokeemerald\">pokeemerald</a>, "
                              "and <a href=\"https://github.com/pret/pokefirered\">"
                              "pokefirered</a>).</p>"
                              "<p>In Porydaw, load your decomp project directory to load "
                              "the music-related project data. Then, play, edit, and "
                              "create music. It sounds just like it does in-game. When "
                              "saving, Porydaw writes and creates the necessary files "
                              "directly into the decomp project. It also supports "
                              "importing MIDI files, making it easy to whip up songs and "
                              "voicegroups for brand new songs.</p>"
                              "<p>Porydaw is designed for both music beginners and power "
                              "users who are familiar with DAW programs. If you've used "
                              "Sappy or Anvil Studio for your musical needs in the past, "
                              "then Porydaw is for you! If you're a power user who loves "
                              "your existing DAW (FL Studio, Reaper, etc.), give Porydaw "
                              "a try&mdash;but if you can't be pulled away, the "
                              "<a href=\"https://github.com/huderlem/poryaaaa\">poryaaaa "
                              "CLAP plugin</a> helps serve that power-user workflow.</p>"
                              "<p>Running on Qt %2.</p>"
                              "<p><a href=\"https://github.com/huderlem/porydaw\">"
                              "github.com/huderlem/porydaw</a></p>")
                               .arg(QStringLiteral(PORYDAW_VERSION), QLatin1String(qVersion())));
    });
    // Qt recognizes the "About" text and relocates this into the application
    // menu on macOS.
    aboutAction->setMenuRole(QAction::AboutRole);
    keys.attach(QStringLiteral("help.about"), aboutAction);

    // Constructor injection: the loaded global editor state seeds the hub
    // before any tab exists; no startup write or hub transaction happens.
    m_workspace = std::make_unique<WorkspaceUi>(*this, initialEditorViewState);

    {
        QSettings settings;
        m_workspace->setFollowPlayhead(settings.value(kFollowPlayheadKey, true).toBool());
        m_audio.setOutputVolume(settings.value(kOutputVolumeKey, 100).toInt());
        m_workspace->setTransportOutputVolume(m_audio.outputVolume());
        const bool resonanceSuppression = settings.value(kResonanceSuppressionKey, false).toBool();
        m_audio.setResonanceSuppression(resonanceSuppression);
        m_workspace->setTransportResonanceSuppression(resonanceSuppression);
    }
    m_workspace->bindFindSongShortcut(keys);

    // WorkspaceUi → MainWindow: transport intents, chrome state, and the
    // selected-tab stream that drives the audio handoff.
    connect(m_workspace.get(), &WorkspaceUi::selectedSongTabChanged, this,
            &MainWindow::onSelectedTabChanged);
    connect(m_workspace.get(), &WorkspaceUi::songTabReady, this, &MainWindow::onSelectedTabReady);
    connect(m_workspace.get(), &WorkspaceUi::selectedSongTimelineChanged, this,
            [this] { refreshSelectedAudio(); });
    connect(m_workspace.get(), &WorkspaceUi::selectedSongStateChanged, this,
            &MainWindow::onSelectedSongStateChanged);
    connect(m_workspace.get(), &WorkspaceUi::bankActionsChanged, this,
            [this](bool) { updateChrome(); });
    connect(m_workspace.get(), &WorkspaceUi::openProjectEnabledChanged, this,
            [this](bool enabled) { m_openProjectAction->setEnabled(enabled); });
    connect(m_workspace.get(), &WorkspaceUi::statusMessageRequested, this,
            [this](const QString &message, int timeout) {
                statusBar()->showMessage(message, timeout);
            });
    connect(m_workspace.get(), &WorkspaceUi::goToStartRequested, this, [this] {
        if (m_selectedTab)
            m_selectedTab->view().goToStart();
    });
    connect(m_workspace.get(), &WorkspaceUi::playRequested, this, [this] { startPlayback(); });
    connect(m_workspace.get(), &WorkspaceUi::playPauseRequested, this, [this] {
        if (m_audio.transport() == Transport::Playing)
            pausePlayback();
        else
            startPlayback(/*fromEditCursor=*/true);
    });
    connect(m_workspace.get(), &WorkspaceUi::pauseRequested, this, [this] { pausePlayback(); });
    connect(m_workspace.get(), &WorkspaceUi::stopRequested, this, [this] { stopPlayback(); });
    connect(m_workspace.get(), &WorkspaceUi::loopEnabledChanged, this,
            [this](bool enabled) { m_audio.setLoopEnabled(enabled); });
    connect(m_workspace.get(), &WorkspaceUi::followPlayheadChanged, this, [this](bool enabled) {
        QSettings settings;
        settings.setValue(kFollowPlayheadKey, enabled);
    });
    connect(m_workspace.get(), &WorkspaceUi::resonanceSuppressionChanged, this,
            [this](bool enabled) {
                QSettings settings;
                settings.setValue(kResonanceSuppressionKey, enabled);
                m_audio.setResonanceSuppression(enabled);
            });
    connect(m_workspace.get(), &WorkspaceUi::outputVolumeChanged, this, [this](int value) {
        m_audio.setOutputVolume(value);
        QSettings settings;
        settings.setValue(kOutputVolumeKey, m_audio.outputVolume());
    });
    connect(m_workspace.get(), &WorkspaceUi::masterVolumeChanged, this, [this](int value) {
        if (!m_selectedTab || !m_selectedTab->isReady() ||
            m_selectedTab->document().cfg().masterVolume == value)
            return;
        SongCfg cfg = m_selectedTab->document().cfg();
        cfg.masterVolume = value;
        m_selectedTab->document().setCfg(cfg);
    });
    connect(m_workspace.get(), &WorkspaceUi::scaleRootChanged, this, [this](int root) {
        if (m_selectedTab)
            m_selectedTab->view().setScaleRoot(root);
    });
    connect(m_workspace.get(), &WorkspaceUi::scaleIdChanged, this,
            [this](porydaw_scale::ScaleId scale) {
                if (m_selectedTab)
                    m_selectedTab->view().setScaleId(scale);
            });
    connect(m_workspace.get(), &WorkspaceUi::scaleHighlightChanged, this, [this](bool enabled) {
        if (m_selectedTab)
            m_selectedTab->view().setScaleHighlight(enabled);
    });
    connect(m_workspace.get(), &WorkspaceUi::scaleFoldChanged, this, [this](bool enabled) {
        if (m_selectedTab)
            m_selectedTab->view().setScaleFold(enabled);
    });
    connect(m_workspace.get(), &WorkspaceUi::selectedTabMuteMaskChanged, this,
            [this](uint32_t mask) { m_audio.setMuteMask(mask); });
    connect(m_workspace.get(), &WorkspaceUi::selectedTabSoloMaskChanged, this,
            [this](uint32_t mask) { m_audio.setSoloMask(mask); });
    connect(m_workspace.get(), &WorkspaceUi::selectedTabEventListChanged, this, [this](bool) {
        const QSignalBlocker blocker(m_eventListAction);
        m_eventListAction->setChecked(m_selectedTab && m_selectedTab->view().eventListVisible());
        updateChrome();
    });
    connect(m_workspace.get(), &WorkspaceUi::editorViewStateChanged, this,
            &MainWindow::persistEditorViewState);
    connect(m_workspace.get(), &WorkspaceUi::editCursorSeekRequested, this, [this](uint64_t tick) {
        if (!m_audioOk || !m_audio.songLoaded() || m_audio.transport() == Transport::Stopped)
            return;
        const uint64_t target = m_audio.timeline()->sampleForTick(tick);
        m_audio.seek(target);
        if (m_selectedTab)
            m_selectedTab->view().setPlayheadSample(target,
                                                    m_audio.transport() == Transport::Playing);
    });
    connect(m_workspace.get(), &WorkspaceUi::playPauseFromRequested, this, [this](uint64_t tick) {
        if (!m_selectedTab)
            return;
        if (m_audioOk && m_audio.transport() == Transport::Playing) {
            m_workspace->triggerPlayPause();
            m_selectedTab->view().commitEditCursor(tick);
            return;
        }
        m_selectedTab->view().commitEditCursor(tick);
        m_workspace->triggerPlayPause();
    });

    // Audition intents are copied values; every engine call stays here.
    connect(m_workspace.get(), &WorkspaceUi::auditionNoteRequested, this,
            [this](uint8_t track, uint8_t key, uint8_t velocity) {
                if (m_audioOk && m_audio.songLoaded())
                    m_audio.previewNote(track, key, velocity);
            });
    connect(m_workspace.get(), &WorkspaceUi::auditionNoteTimedRequested, this,
            [this](uint8_t track, uint8_t key, uint8_t velocity, uint32_t durationSamples) {
                if (m_audioOk && m_audio.songLoaded())
                    m_audio.previewNoteTimed(track, key, velocity, durationSamples);
            });
    connect(m_workspace.get(), &WorkspaceUi::auditionVoiceRequested, this,
            [this](uint8_t voice, uint8_t key, uint8_t velocity) {
                if (m_audioOk)
                    m_audio.previewVoice(voice, key, velocity);
            });
    connect(
        m_workspace.get(), &WorkspaceUi::sampleAuditionRequested, this,
        [this](const QString &symbol, VgAuditionKind kind, const AuditionSlots::Adsr &adsr) {
            if (!m_audioOk)
                return;
            if (kind == VgAuditionKind::Keysplit) {
                auditionKeysplit(symbol);
                return;
            }
            if (kind == VgAuditionKind::Wave) {
                if (const uint32_t *pw = progWaveFor(symbol))
                    m_audio.auditionWave(
                        QByteArray::fromRawData(reinterpret_cast<const char *>(pw), 16), 60, adsr);
                return;
            }
            const WaveData *wd = sampleWaveFor(symbol);
            if (!wd || !wd->data || wd->size == 0)
                return;
            m_audio.auditionSample(
                QByteArray::fromRawData(reinterpret_cast<const char *>(wd->data), int(wd->size)),
                wd->freq, wd->loopStart, (wd->status & 0x4000) != 0, 60, adsr);
        });
    connect(m_workspace.get(), &WorkspaceUi::sampleAuditionStopRequested, this, [this] {
        if (m_audioOk)
            m_audio.auditionSampleOff();
    });

    // Polyphony overflow debugger dock (SPEC §6.1): hidden by default (it's
    // a diagnostic tool); closable, with a View-menu toggle. The saved
    // window state restores visibility/placement on later runs.
    m_polyDock = new QDockWidget(tr("Polyphony"), this);
    m_polyDock->setObjectName(QStringLiteral("polyphonyDock"));
    m_polyDock->setFeatures(QDockWidget::DockWidgetMovable | QDockWidget::DockWidgetClosable);
    m_polyPanel = new PolyphonyPanel(m_polyDock);
    // Solo-overflow only inverts the audio while the dock is on screen: with
    // the checkbox out of sight there is nothing to explain the weird
    // playback, so hiding the dock suspends the mode and re-showing it
    // (checkbox still checked) resumes it.
    const auto applyPolyInvert = [this] {
        if (m_audioOk)
            m_audio.setPolyDebugInvert(m_polyPanel->invertChecked() && m_polyDock->isVisible());
    };
    connect(m_polyPanel, &PolyphonyPanel::invertToggled, this, applyPolyInvert);
    connect(m_polyDock, &QDockWidget::visibilityChanged, this, applyPolyInvert);
    connect(m_polyPanel, &PolyphonyPanel::resetRequested, this, [this] {
        if (m_audioOk)
            m_audio.resetPolyStats();
    });
    connect(m_polyPanel, &PolyphonyPanel::jumpToEvent, this,
            [this](uint64_t tick, int track, int midiKey) {
                // editCursorMoved's seek (above) already follows the cursor
                // while playing/paused; when stopped, playback starts from
                // the edit cursor. revealNote selects the losing track and
                // the lost note itself.
                if (!m_selectedTab)
                    return;
                SongView &view = m_selectedTab->view();
                view.revealNote(track, uint8_t(midiKey), tick);
                view.commitEditCursor(tick);
                view.ensureTickVisible(tick);
            });
    m_polyDock->setWidget(m_polyPanel);
    addDockWidget(Qt::RightDockWidgetArea, m_polyDock);
    m_polyDock->hide();
    QAction *polyDockAction = m_polyDock->toggleViewAction();
    polyDockAction->setText(tr("&Polyphony Debugger"));
    polyDockAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+P")));
    viewMenu->addAction(polyDockAction);

    // App-wide appearance preferences, set off a separator from the
    // per-song view state above: the theme, the typeface, and the
    // velocity-hue note fills all persist in QSettings and apply to every
    // open tab at once.
    viewMenu->addSeparator();
    QAction *themeAction = viewMenu->addAction(tr("&Theme..."), this, [this] {
        m_themeDialog->show();
        m_themeDialog->raise();
        m_themeDialog->activateWindow();
    });
    keys.attach(QStringLiteral("view.theme"), themeAction);

    // The typeface: the bundled Atkinson Hyperlegible scale, or the platform
    // font other Qt applications use.
    QAction *systemFontAction = viewMenu->addAction(tr("Use System &Font"));
    systemFontAction->setCheckable(true);
    keys.attach(QStringLiteral("view.system_font"), systemFontAction);
    {
        QSettings settings;
        systemFontAction->setChecked(settings.value(kSystemFontKey, false).toBool());
    }
    connect(systemFontAction, &QAction::toggled, this, [this](bool on) {
        QSettings settings;
        settings.setValue(kSystemFontKey, on);
        typography::setUseSystemFont(on);
        if (const auto body = typography::bodyFont()) {
            QApplication::setFont(*body);
            // QStyleSheetStyle caches the resolved application font on
            // already-polished widgets, even when their font resolve mask is
            // empty. Reassert inheritance before reapplying the theme
            // stylesheet so derived fonts resolve from the new Body.
            resetInheritedWidgetFonts();
        }
        // Reapply the committed theme to repolish stylesheet-derived fonts.
        m_themeController->discardPreview();
    });

    m_velocityColorsAction = viewMenu->addAction(tr("Color Notes by &Velocity"));
    m_velocityColorsAction->setCheckable(true);
    keys.attach(QStringLiteral("view.velocity_colors"), m_velocityColorsAction);
    {
        QSettings settings;
        m_velocityColorsAction->setChecked(settings.value(kVelocityColorsKey, false).toBool());
    }
    m_workspace->setVelocityColorMode(m_velocityColorsAction->isChecked());
    connect(m_velocityColorsAction, &QAction::toggled, this, [this](bool on) {
        QSettings settings;
        settings.setValue(kVelocityColorsKey, on);
        m_workspace->setVelocityColorMode(on);
    });

    m_noteNamesAction = viewMenu->addAction(tr("Show Note &Names"));
    m_noteNamesAction->setCheckable(true);
    keys.attach(QStringLiteral("view.note_names"), m_noteNamesAction);
    {
        QSettings settings;
        m_noteNamesAction->setChecked(settings.value(kNoteNamesKey, false).toBool());
    }
    m_workspace->setNoteNameMode(m_noteNamesAction->isChecked());
    connect(m_noteNamesAction, &QAction::toggled, this, [this](bool on) {
        QSettings settings;
        settings.setValue(kNoteNamesKey, on);
        m_workspace->setNoteNameMode(on);
    });

    // The transport bar's follow toggle, findable here too: an app-wide
    // persisted preference like the rest of this group.
    m_workspace->addFollowPlayheadActionTo(*viewMenu);

    // Status bar: polyphony meter
    m_polyMeter = new QWidget(this);
    auto *polyLayout = new QHBoxLayout(m_polyMeter);
    polyLayout->setContentsMargins(0, 0, 0, 0);
    polyLayout->setSpacing(::layout::space(::layout::Space::Half));
    const auto fieldInset = ::layout::space(::layout::Space::Half);
    auto *pcmCaption = new QLabel(tr("PCM"), m_polyMeter);
    m_pcmValueLabel = new QLabel(m_polyMeter);
    m_pcmValueLabel->setObjectName(QStringLiteral("polyphonyPcmValue"));
    m_pcmValueLabel->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
    m_pcmValueLabel->setAttribute(Qt::WA_StyledBackground);
    m_pcmValueLabel->setContentsMargins(fieldInset, 0, fieldInset, 0);
    auto *separator = new QLabel(QStringLiteral("·"), m_polyMeter);
    auto *cgbCaption = new QLabel(tr("CGB"), m_polyMeter);
    m_cgbValueLabel = new QLabel(m_polyMeter);
    m_cgbValueLabel->setObjectName(QStringLiteral("polyphonyCgbValue"));
    m_cgbValueLabel->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
    m_cgbValueLabel->setAttribute(Qt::WA_StyledBackground);
    m_cgbValueLabel->setContentsMargins(fieldInset, 0, fieldInset, 0);
    m_polyLostSeparator = new QLabel(QStringLiteral("·"), m_polyMeter);
    m_polyLostLabel = new QLabel(m_polyMeter);
    m_polyLostLabel->setObjectName(QStringLiteral("polyphonyLostValue"));
    m_polyLostLabel->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
    m_polyLostLabel->setAttribute(Qt::WA_StyledBackground);
    m_polyLostLabel->setContentsMargins(fieldInset, 0, fieldInset, 0);
    m_polyLostCaption = new QLabel(tr("notes lost"), m_polyMeter);
    m_polyLostCaption->setObjectName(QStringLiteral("polyphonyLostCaption"));
    m_polyLostSeparator->hide();
    m_polyLostLabel->hide();
    m_polyLostCaption->hide();
    polyLayout->addWidget(pcmCaption);
    polyLayout->addWidget(m_pcmValueLabel);
    polyLayout->addWidget(separator);
    polyLayout->addWidget(cgbCaption);
    polyLayout->addWidget(m_cgbValueLabel);
    polyLayout->addWidget(m_polyLostSeparator);
    polyLayout->addWidget(m_polyLostLabel);
    polyLayout->addWidget(m_polyLostCaption);
    statusBar()->addPermanentWidget(m_polyMeter);
    m_polyMeter->hide();
    const auto valueFont = typography::bodyMono(font());
    m_pcmValueLabel->setFixedWidth(
        QFontMetrics(valueFont).horizontalAdvance(QStringLiteral("15/15")) + 2 * fieldInset);
    m_cgbValueLabel->setFixedWidth(
        QFontMetrics(valueFont).horizontalAdvance(QStringLiteral("4/4")) + 2 * fieldInset);

    // Initial focus goes to the song list (via the panel's focus proxy), not
    // its filter box — first in tab order, which otherwise wins on show and
    // swallowed the first keystrokes into the search field.
    m_workspace->focusSongList();
}

void MainWindow::updateWindowFrameTheme()
{
#ifdef Q_OS_WIN
    const auto caption = themes::color(themes::Role::toolbar_background);
    const auto text = themes::color(themes::Role::toolbar_text);
    const COLORREF captionColor = RGB(caption.red(), caption.green(), caption.blue());
    const COLORREF textColor = RGB(text.red(), text.green(), text.blue());
    const HWND hwnd = reinterpret_cast<HWND>(winId());
    const auto setColor = [hwnd](DwmWindowAttribute attribute, const COLORREF &color) {
        DwmSetWindowAttribute(hwnd, static_cast<DWORD>(attribute), &color, sizeof(color));
    };
    setColor(DwmWindowAttribute::CaptionColor, captionColor);
    setColor(DwmWindowAttribute::TextColor, textColor);
#endif
}

void MainWindow::changeEvent(QEvent *event)
{
    QMainWindow::changeEvent(event);
    if (event->type() == QEvent::ApplicationPaletteChange || event->type() == QEvent::StyleChange) {
        updateWindowFrameTheme();
    }
}

// ---- Selected-tab audio handoff ---------------------------------------------

void MainWindow::onSelectedTabChanged(SongTab *tab)
{
    // Switching tabs stops playback in the tab being left.
    if (m_audioOk)
        m_audio.stop();
    m_selectedTab = tab;

    {
        // Reflect the incoming tab's roll/event-list state without the
        // checkbox driving a redundant toggle.
        const QSignalBlocker blocker(m_eventListAction);
        m_eventListAction->setChecked(tab && tab->isReady() && tab->view().eventListVisible());
    }

    if (!tab || !tab->isReady() || !tab->voicegroupLease()) {
        // Null or still-loading selection: unload the engine before the
        // retained lease is released — the engine borrows that bank until
        // unloadSong returns, and a tab awaiting VoicegroupBound has no
        // bank to bind yet.
        if (m_audioOk)
            m_audio.unloadSong();
        m_selectedVoicegroup = {};
        m_appliedTimeline = nullptr;
        m_appliedSettings.reset();
        m_polyPanel->clearSession();
        updateTimeLabel();
        updatePolyStatus();
        syncScaleControls();
        updateWindowTitle();
        updateChrome();
        updateTransportActions();
        synchronizePlayhead();
        return;
    }

    onSelectedTabReady(tab);
    // A native QQuickView completes its tab-activation handoff after
    // QTabWidget emits currentChanged. Restore content focus on the next
    // turn, after that non-focusable overlay has settled.
    const QPointer<SongTab> focusTab(tab);
    QTimer::singleShot(0, this, [this, focusTab] {
        if (focusTab && focusTab == m_selectedTab && focusTab->isReady())
            focusTab->view().focusActiveSurface();
    });
}

void MainWindow::onSelectedTabReady(SongTab *tab)
{
    if (tab != m_selectedTab)
        return;
    // The selected tab's terminal VoicegroupBound just landed (or the
    // selection moved to an already-ready tab): bind the engine, then
    // refresh the chrome that reads loaded state.
    applySelectedAudio();
    updatePolyPanelContext(tab);
    syncMasterVolumeControl();
    syncScaleControls();
    updateTimeLabel();
    updatePolyStatus();
    synchronizePlayhead();
    updateWindowTitle();
    updateChrome();
    updateTransportActions();
}

void MainWindow::onSelectedSongStateChanged()
{
    refreshSelectedAudio();
    updateWindowTitle();
    updateChrome();
    syncMasterVolumeControl();
    updateTransportActions();
}

void MainWindow::applySelectedAudio()
{
    SongTab *const tab = m_selectedTab;
    Q_ASSERT(tab && tab->isReady() && tab->voicegroupLease());
    if (!tab || !tab->isReady() || !tab->voicegroupLease())
        return;
    // Cold bind: the engine shares the tab's timeline and borrows the bank
    // for exactly as long as the retained lease below keeps it alive.
    const VoicegroupLease lease = tab->voicegroupLease();
    const SongSettings settings = songSettingsFor(*tab);
    m_audio.loadSong(tab->timeline(), lease, settings);
    m_selectedVoicegroup = lease;
    m_appliedTimeline = tab->timeline().get();
    m_appliedSettings = settings;
    // loadSong resets the engine's masks; the tab's view remembers them.
    m_audio.setMuteMask(tab->view().muteMask());
    m_audio.setSoloMask(tab->view().soloMask());
}

void MainWindow::refreshSelectedAudio()
{
    SongTab *const tab = m_selectedTab;
    if (!m_audioOk || !tab || !tab->isReady() || !tab->voicegroupLease())
        return;

    const VoicegroupLease lease = tab->voicegroupLease();
    const bool bankChanged = lease.get() != m_selectedVoicegroup.get();
    if (bankChanged) {
        // Cold swap: cuts all sound. The engine drops the old borrow before
        // the assignment releases the retained lease.
        m_audio.updateVoicegroup(lease);
        m_selectedVoicegroup = lease;
    }
    const bool timelineChanged = tab->timeline().get() != m_appliedTimeline;
    if (timelineChanged) {
        // Hot: publishes the rebuilt timeline for the next audio callback.
        m_audio.updateTimeline(tab->timeline());
        m_appliedTimeline = tab->timeline().get();
    }
    const SongSettings settings = songSettingsFor(*tab);
    if (!m_appliedSettings || !sameSongSettings(*m_appliedSettings, settings)) {
        m_audio.updateSettings(settings);
        m_appliedSettings = settings;
    }
    if (bankChanged || timelineChanged)
        updatePolyPanelContext(tab); // track and voice names follow the bank
}

void MainWindow::updatePolyPanelContext(SongTab *tab)
{
    if (!tab || !tab->isReady()) {
        m_polyPanel->clearSession();
        return;
    }
    m_polyPanel->setTimeline(tab->timeline().get());
    QStringList trackNames;
    for (int t = 0; t < MAX_TRACKS; t++)
        trackNames.append(tab->document().trackName(t));
    m_polyPanel->setTrackNames(trackNames);
    // Copied out so a bank swap can't leave the panel reading a bank that is
    // being replaced.
    QStringList voiceNames;
    if (const VoicegroupLease lease = tab->voicegroupLease()) {
        for (int v = 0; v < VOICEGROUP_SIZE; v++)
            voiceNames.append(QString::fromLatin1(lease->voiceNames[v]));
    }
    m_polyPanel->setVoiceNames(voiceNames);
}

SongSettings MainWindow::songSettingsFor(const SongTab &tab) const
{
    const SongCfg &cfg = tab.document().cfg();
    SongSettings settings;
    settings.songVolume = uint8_t(cfg.masterVolume);
    settings.reverb = uint8_t(cfg.reverb >= 0 ? cfg.reverb : SongCfg::kDefaultReverb);
    settings.pcmMixer = m_engineSettings.pcmMixer;
    settings.maxPcmChannels = uint8_t(m_engineSettings.maxPcmChannels);
    settings.pcmMixRate = m_engineSettings.pcmMixRate;
    settings.analogFilter = m_engineSettings.analogFilter;
    return settings;
}

// ---- Browse auditions ---------------------------------------------------------

const WaveData *MainWindow::sampleWaveFor(const QString &symbol) const
{
    const SampleSetLease &set = m_workspace->sampleSet();
    if (!set)
        return nullptr;
    const int index =
        sampleSetIndex(m_workspace->projectState().catalog.directSound, set->count, symbol);
    return index < 0 ? nullptr : set->waves[index];
}

const uint32_t *MainWindow::progWaveFor(const QString &symbol) const
{
    const SampleSetLease &set = m_workspace->sampleSet();
    if (!set)
        return nullptr;
    const int index =
        sampleSetIndex(m_workspace->projectState().catalog.progWave, set->progWaveCount, symbol);
    return index < 0 ? nullptr : set->progWaves[index];
}

const LoadedKeysplit *MainWindow::keysplitFor(const QString &symbol) const
{
    const SampleSetLease &set = m_workspace->sampleSet();
    if (!set)
        return nullptr;
    const auto &pairs = m_workspace->projectState().catalog.keysplits;
    for (int i = 0; i < pairs.size() && i < set->keysplitCount; i++) {
        if (pairs.at(i).first == symbol && set->keysplits[i].subGroup && set->keysplits[i].table)
            return &set->keysplits[i];
    }
    return nullptr;
}

void MainWindow::auditionKeysplit(const QString &symbol)
{
    const LoadedKeysplit *const keysplit = keysplitFor(symbol);
    if (!keysplit)
        return;
    const uint8_t idx = keysplit->table[60];
    if (idx >= VOICEGROUP_SIZE)
        return; // old-style overflow index: nothing loaded to play
    const ToneData &sub = keysplit->subGroup[idx];
    if (sub.type & (VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL))
        return; // nested split: the engine refuses these too
    const AuditionSlots::Adsr adsr{sub.attack, sub.decay, sub.sustain, sub.release};
    const int cgbType = sub.type & 0x07;
    if (cgbType == 0 && sub.wav && sub.wav->data && sub.wav->size > 0) {
        m_audio.auditionSample(
            QByteArray::fromRawData(reinterpret_cast<const char *>(sub.wav->data),
                                    int(sub.wav->size)),
            sub.wav->freq, sub.wav->loopStart, (sub.wav->status & 0x4000) != 0, 60, adsr, sub.key);
    } else if (cgbType == VOICE_PROGRAMMABLE_WAVE && sub.wavePointer) {
        m_audio.auditionWave(
            QByteArray::fromRawData(reinterpret_cast<const char *>(sub.wavePointer), 16), 60, adsr);
    }
    // Square/noise sub-voices: rare, and their audition would need CGB
    // square plumbing — silently skipped.
}

// ---- Chrome -----------------------------------------------------------------

void MainWindow::persistEditorViewState(const EditorViewState &state)
{
    // The hub has already fanned the change out to every tab; MainWindow
    // only writes the store — once per semantic change, no mirror.
    // editorViewStatePersisted is a harness-only completion boundary, used
    // to prove sink cardinality/order; production consumers must observe
    // the WorkspaceUi hub signal, not this persistence completion.
    saveEditorViewState(*m_themeSettings, state);
    emit editorViewStatePersisted(state);
}

void MainWindow::updateChrome()
{
    const bool projectOpen = m_workspace->projectState().snapshot.isOpen();
    SongTab *const tab = m_selectedTab;
    const bool ready = tab && tab->isReady();

    m_openProjectAction->setEnabled(m_workspace->openProjectEnabled());
    m_newSongAction->setEnabled(projectOpen);
    m_importAction->setEnabled(projectOpen);
    m_importSampleAction->setEnabled(projectOpen);
    m_saveAction->setEnabled(ready);
    m_exportWavAction->setEnabled(ready && m_audioOk && m_audio.songLoaded());
    m_settingsAction->setEnabled(ready);
    m_copyAction->setEnabled(ready);
    m_insertTimeAction->setEnabled(ready);
    m_registerAction->setEnabled(ready && selectedSongRegistrationPending());
    m_closeTabAction->setEnabled(m_workspace->openTabCount() > 0);
    m_eventListAction->setEnabled(ready);
    m_undoAction->setEnabled(ready && m_workspace->bankActionsEnabled() &&
                             tab->history().canUndo());
    m_redoAction->setEnabled(ready && m_workspace->bankActionsEnabled() &&
                             tab->history().canRedo());
    const bool drawerAvailable = ready && !tab->view().eventListVisible();
    m_automationDrawerAction->setEnabled(drawerAvailable);
    m_velocityDrawerAction->setEnabled(drawerAvailable);
    m_voiceChangesDrawerAction->setEnabled(drawerAvailable);
}

bool MainWindow::selectedSongRegistrationPending() const
{
    if (!m_selectedTab || !m_selectedTab->isReady())
        return false;
    const QString &label = m_selectedTab->name().value();
    for (const SongInfo &song : m_workspace->projectState().snapshot.songs()) {
        if (song.label == label)
            return !song.registrationGaps.isEmpty();
    }
    return false;
}

void MainWindow::updateWindowTitle()
{
    const auto &snapshot = m_workspace->projectState().snapshot;
    const QString project = snapshot.isOpen() ? QDir(snapshot.root()).dirName() : QString();

    if (m_selectedTab) {
        setWindowTitle(
            QStringLiteral("%1[*] — %2 — porydaw").arg(m_selectedTab->name().value(), project));
        setWindowModified(m_selectedTab->isReady() && m_selectedTab->document().isDirty());
    } else {
        setWindowTitle(project.isEmpty() ? QStringLiteral("porydaw")
                                         : QStringLiteral("%1 — porydaw").arg(project));
        setWindowModified(false);
    }
}

void MainWindow::updateTransportActions()
{
    const bool loaded =
        m_audioOk && m_selectedTab && m_selectedTab->isReady() && m_audio.songLoaded();
    auto state = WorkspaceUi::PlaybackState::Unavailable;
    if (loaded) {
        switch (m_audio.transport()) {
        case Transport::Stopped:
            state = WorkspaceUi::PlaybackState::Stopped;
            break;
        case Transport::Paused:
            state = WorkspaceUi::PlaybackState::Paused;
            break;
        case Transport::Playing:
            state = WorkspaceUi::PlaybackState::Playing;
            break;
        }
    }
    m_workspace->setTransportPlaybackState(state);
    m_workspace->setTransportSongAvailable(loaded);
}

void MainWindow::syncMasterVolumeControl()
{
    const bool loaded = m_selectedTab && m_selectedTab->isReady();
    m_workspace->setTransportMasterVolume(
        loaded ? m_selectedTab->document().cfg().masterVolume : SongCfg().masterVolume, loaded);
}

void MainWindow::syncScaleControls()
{
    if (m_selectedTab && m_selectedTab->isReady()) {
        const SongView &view = m_selectedTab->view();
        m_workspace->setTransportScaleState(view.scaleRoot(), view.scaleId(), view.scaleHighlight(),
                                            view.scaleFold());
    } else {
        m_workspace->setTransportScaleState(0, porydaw_scale::displayOrder()[0], false, false);
    }
}

void MainWindow::synchronizePlayhead()
{
    const bool songLoaded =
        m_audioOk && m_selectedTab && m_selectedTab->isReady() && m_audio.songLoaded();
    const bool playing = songLoaded && m_audio.transport() == Transport::Playing;
    const int uiInterval = playing ? kPlaybackUiIntervalMs : kIdleUiIntervalMs;
    if (m_uiTimer->interval() != uiInterval)
        m_uiTimer->setInterval(uiInterval);

    if (!songLoaded) {
        // This also runs synchronously from a null-selection handoff.
        m_playheadTimer->stop();
        return;
    }

    const bool playheadTimerWasActive = m_playheadTimer->isActive();
    const float activityElapsed = float(m_playheadTimer->interval()) / 1000.0f;
    const auto trackActivityLevels = m_audio.consumeTrackActivityLevels();
    SongView &view = m_selectedTab->view();
    const bool activityAnimating =
        view.advanceTrackActivity(trackActivityLevels, activityElapsed, playing);
    view.setPlayheadSample(m_audio.playheadSamples(), playing);
    if (activityAnimating) {
        if (!m_playheadTimer->isActive())
            m_playheadTimer->start();
    } else {
        m_playheadTimer->stop();
        if (playheadTimerWasActive)
            updateTransportActions();
    }
}

// QLabel::setText repaints even for identical text, so both status
// updaters compare against the last applied value and only touch the
// widgets on change. Nothing else writes these labels, so the caches
// cannot go stale.
void MainWindow::updateTimeLabel()
{
    const bool loaded = m_audioOk && m_selectedTab && m_audio.songLoaded();
    const QString text =
        loaded ? QStringLiteral("%1 / %2").arg(formatTime(m_audio.playheadSamples()),
                                               formatTime(m_audio.timeline()->lengthSamples))
               : QStringLiteral("--:--.- / --:--.-");
    m_workspace->setTransportTimeText(text);
}

void MainWindow::updatePolyStatus()
{
    PolyStatusSnapshot status;
    status.loaded = m_audioOk && m_selectedTab && m_audio.songLoaded();
    if (status.loaded) {
        status.activePcm = m_audio.activePcmChannels();
        status.maxPcm = m_audio.maxPcmChannels();
        status.activeCgb = m_audio.activeCgbChannels();
        status.lostTotal = m_audio.polyLostTotal();
    }
    if (m_lastPolyStatus && *m_lastPolyStatus == status)
        return;
    m_lastPolyStatus = status;

    if (!status.loaded) {
        m_pcmValueLabel->clear();
        m_cgbValueLabel->clear();
        m_polyLostLabel->clear();
        m_polyLostSeparator->hide();
        m_polyLostLabel->hide();
        m_polyLostCaption->hide();
        m_polyMeter->hide();
        return;
    }

    m_pcmValueLabel->setText(QStringLiteral("%1/%2").arg(status.activePcm).arg(status.maxPcm));
    m_cgbValueLabel->setText(QStringLiteral("%1/4").arg(status.activeCgb));
    const bool hasLost = status.lostTotal > 0;
    m_polyLostLabel->setText(hasLost ? QString::number(status.lostTotal) : QString());
    m_polyLostSeparator->setVisible(hasLost);
    m_polyLostLabel->setVisible(hasLost);
    m_polyLostCaption->setVisible(hasLost);
    m_polyMeter->show();
}

QString MainWindow::formatTime(uint64_t samples) const
{
    const double seconds = double(samples) / m_audio.sampleRate();
    const int mins = int(seconds) / 60;
    const int secs = int(seconds) % 60;
    const int tenths = int(seconds * 10) % 10;
    return QStringLiteral("%1:%2.%3").arg(mins).arg(secs, 2, 10, QLatin1Char('0')).arg(tenths);
}

// ---- Slots ------------------------------------------------------------------

void MainWindow::saveSong()
{
    m_workspace->saveSelectedSong();
}

void MainWindow::uiTick()
{
    updateTimeLabel();
    updatePolyStatus();

    if (m_audioOk && m_selectedTab && m_audio.songLoaded() && m_polyDock->isVisible()) {
        AudioEngine::PolySnapshot snap;
        m_audio.polySnapshot(&snap);
        m_polyPanel->updateSnapshot(snap);
    }
    // Safety net for transport transitions no handler observed (the engine
    // stopping on its own while the playhead timer is idle): cheap no-op
    // setEnabled calls at the status cadence.
    updateTransportActions();
}

// Starts (or resumes) playback; from Stopped, seeks to the edit cursor
// first so playback begins there. fromEditCursor forces that seek even
// out of Paused — the Space binding (Reaper-style restart), while the
// Play button resumes from the pause point.
void MainWindow::startPlayback(bool fromEditCursor)
{
    if (!m_audioOk || !m_selectedTab || !m_selectedTab->isReady() || !m_audio.songLoaded())
        return;
    const bool seekToCursor = fromEditCursor || m_audio.transport() == Transport::Stopped;
    uint64_t target = 0;
    if (seekToCursor) {
        target = m_audio.timeline()->sampleForTick(m_selectedTab->view().editCursorTick());
        m_audio.seek(target);
    }
    m_audio.play();
    updateTransportActions();
    synchronizePlayhead();
    // The seek lands within one audio period; show its target now rather
    // than the stale engine playhead synchronizePlayhead just read.
    if (seekToCursor)
        m_selectedTab->view().setPlayheadSample(target, true);
}

void MainWindow::pausePlayback()
{
    m_audio.pause();
    updateTransportActions();
    synchronizePlayhead();
}

void MainWindow::stopPlayback()
{
    m_audio.stop();
    updateTransportActions();
    synchronizePlayhead();
}

void MainWindow::exportWav()
{
    SongTab *const tab = m_selectedTab;
    if (!tab || !tab->isReady() || !m_audioOk || !m_audio.songLoaded())
        return;
    const bool hasLoop = m_audio.timeline()->hasLoop();

    // Options: loop count + fadeout for looping songs, ring-out tail
    // otherwise (SPEC §7 — poryaaaa_render parity), with a live duration
    // preview. The timeline is rebuilt per rate change only for that
    // preview math; the real render builds its own below.
    QDialog dialog(this);
    dialog.setWindowTitle(tr("Export WAV"));
    auto *form = new QFormLayout(&dialog);

    auto *rateBox = new QComboBox(&dialog);
    for (int rate : {32000, 44100, 48000})
        rateBox->addItem(tr("%1 Hz").arg(rate), rate);
    rateBox->setCurrentIndex(2);
    form->addRow(tr("Sample rate:"), rateBox);

    QSpinBox *loopCountBox = nullptr;
    QDoubleSpinBox *fadeoutBox = nullptr;
    QDoubleSpinBox *tailBox = nullptr;
    if (hasLoop) {
        loopCountBox = new QSpinBox(&dialog);
        loopCountBox->setRange(1, 99);
        loopCountBox->setValue(2);
        form->addRow(tr("Loop count:"), loopCountBox);
        fadeoutBox = new QDoubleSpinBox(&dialog);
        fadeoutBox->setRange(0.0, 60.0);
        fadeoutBox->setDecimals(1);
        fadeoutBox->setValue(5.0);
        fadeoutBox->setSuffix(tr(" s"));
        form->addRow(tr("Fadeout:"), fadeoutBox);
    } else {
        tailBox = new QDoubleSpinBox(&dialog);
        tailBox->setRange(0.0, 60.0);
        tailBox->setDecimals(1);
        tailBox->setValue(3.0);
        tailBox->setSuffix(tr(" s"));
        form->addRow(tr("Tail (no loop markers):"), tailBox);
    }

    auto *durationLabel = new QLabel(&dialog);
    form->addRow(tr("Duration:"), durationLabel);

    auto currentOptions = [&] {
        WavExportOptions opts;
        opts.sampleRate = rateBox->currentData().toInt();
        opts.resonanceSuppression = m_audio.resonanceSuppression();
        if (loopCountBox)
            opts.loopCount = loopCountBox->value();
        if (fadeoutBox)
            opts.fadeoutSeconds = fadeoutBox->value();
        if (tailBox)
            opts.tailSeconds = tailBox->value();
        return opts;
    };
    auto updateDuration = [&] {
        const WavExportOptions opts = currentOptions();
        // Loop/length sample positions scale exactly with the rate, so the
        // loaded timeline's positions can be rescaled for the preview
        // instead of rebuilding the timeline on every spin.
        const double scale = double(opts.sampleRate) / m_audio.timeline()->sampleRate;
        MidiTimeline scaled;
        scaled.lengthSamples = uint64_t(double(m_audio.timeline()->lengthSamples) * scale);
        if (hasLoop) {
            scaled.loopStartSample = uint64_t(double(m_audio.timeline()->loopStartSample) * scale);
            scaled.loopEndSample = uint64_t(double(m_audio.timeline()->loopEndSample) * scale);
        }
        const uint64_t total = wavExportTotals(scaled, opts).totalSamples;
        const int seconds = int(double(total) / opts.sampleRate + 0.5);
        durationLabel->setText(
            QStringLiteral("%1:%2").arg(seconds / 60).arg(seconds % 60, 2, 10, QLatin1Char('0')));
    };
    connect(rateBox, &QComboBox::currentIndexChanged, &dialog, updateDuration);
    if (loopCountBox)
        connect(loopCountBox, &QSpinBox::valueChanged, &dialog, updateDuration);
    if (fadeoutBox)
        connect(fadeoutBox, &QDoubleSpinBox::valueChanged, &dialog, updateDuration);
    if (tailBox)
        connect(tailBox, &QDoubleSpinBox::valueChanged, &dialog, updateDuration);
    updateDuration();

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    form->addRow(buttons);
    if (dialog.exec() != QDialog::Accepted)
        return;
    const WavExportOptions opts = currentOptions();

    QSettings appSettings;
    const QString startDir =
        appSettings
            .value(QStringLiteral("lastWavExportDir"), QFileInfo(tab->document().midPath()).path())
            .toString();
    const QString path = QFileDialog::getSaveFileName(
        this, tr("Export WAV"), startDir + QLatin1Char('/') + tab->document().label() + ".wav",
        tr("WAV files (*.wav)"));
    if (path.isEmpty())
        return;
    appSettings.setValue(QStringLiteral("lastWavExportDir"), QFileInfo(path).path());

    stopPlayback();

    QProgressDialog progress(tr("Rendering %1...").arg(tab->document().label()), tr("Cancel"), 0,
                             1000, this);
    progress.setWindowModality(Qt::WindowModal);
    progress.setMinimumDuration(0);

    // The render reads the same bank the audio engine borrows — the
    // retained selected lease — against a fresh timeline at the export
    // rate, so unsaved document and voice edits export as heard.
    auto timeline = tab->document().buildTimeline(double(opts.sampleRate));
    QString error;
    const bool ok = ::exportWav(
        path, *timeline, m_selectedVoicegroup, songSettingsFor(*tab), opts,
        [&](double fraction) {
            progress.setValue(int(fraction * 1000));
            return !progress.wasCanceled();
        },
        &error);
    progress.setValue(1000);
    if (!ok) {
        if (!error.isEmpty())
            QMessageBox::warning(this, tr("Export WAV"), error);
        else
            statusBar()->showMessage(tr("Export cancelled."), 5000);
        return;
    }
    const uint64_t total = wavExportTotals(*timeline, opts).totalSamples;
    statusBar()->showMessage(tr("Exported %1 (%2 @ %3 Hz)")
                                 .arg(path, QStringLiteral("%1:%2")
                                                .arg(int(total / uint64_t(opts.sampleRate)) / 60)
                                                .arg(int(total / uint64_t(opts.sampleRate)) % 60, 2,
                                                     10, QLatin1Char('0')))
                                 .arg(opts.sampleRate),
                             8000);
}

void MainWindow::openSettings(SettingsDialog::Tab initialTab)
{
    auto song = std::optional<SongTarget>();
    if (m_selectedTab && m_selectedTab->isReady())
        song = SongTarget{m_selectedTab->document().cfg(), m_selectedTab->document().label()};
    const QStringList vgArgs = m_workspace->projectState().catalog.groupArgs;
    SettingsDialog dialog(m_engineSettings, song, vgArgs, initialTab, this);
    const auto apply = [this, &dialog] {
        const EngineSettings newEngine = dialog.engineSettings();
        if (newEngine.pcmMixer != m_engineSettings.pcmMixer ||
            newEngine.maxPcmChannels != m_engineSettings.maxPcmChannels ||
            newEngine.pcmMixRate != m_engineSettings.pcmMixRate ||
            newEngine.analogFilter != m_engineSettings.analogFilter) {
            m_engineSettings = newEngine;
            m_engineSettings.save();
            if (m_audioOk && m_selectedTab && m_audio.songLoaded()) {
                const SongSettings settings = songSettingsFor(*m_selectedTab);
                m_audio.updateSettings(settings);
                m_appliedSettings = settings;
            }
        }
        if (m_selectedTab && m_selectedTab->isReady()) {
            if (const auto songCfg = dialog.songCfg())
                m_selectedTab->document().setCfg(*songCfg);
        }
    };
    connect(&dialog, &SettingsDialog::applyRequested, this, apply);
    if (dialog.exec() == QDialog::Accepted)
        apply();
}

void MainWindow::openSongSettings()
{
    openSettings(SettingsDialog::Tab::Song);
}

void MainWindow::openKeyboardShortcuts()
{
    openSettings(SettingsDialog::Tab::Keyboard);
}

void MainWindow::openEngineSettings()
{
    openSettings(SettingsDialog::Tab::Engine);
}

void MainWindow::closeEvent(QCloseEvent *event)
{
    if (m_closeAccepted) {
        event->accept();
        return;
    }
    event->ignore();
    if (m_closeInProgress)
        return;
    m_closeInProgress = true;
    // Every dirty tab gets its prompt; a Cancel keeps the window open.
    // Saves answered before it have already queued — standard save-all
    // behavior, not a transaction.
    m_workspace->promptSaveAll([this](bool succeeded) {
        if (!succeeded) {
            m_closeInProgress = false;
            return;
        }
        // Preview cleanup rides the worker's FIFO; the destructor's shutdown
        // order joins the worker after it.
        m_workspace->cleanupPreview();
        if (m_persistSession) {
            QSettings settings;
            settings.setValue(QStringLiteral("windowGeometry"), saveGeometry());
            settings.setValue(QStringLiteral("windowState"), saveState());
            const WorkspaceUi::SongFilters filters = m_workspace->songFilters();
            settings.setValue(QStringLiteral("songFilterText"), filters.search);
            settings.setValue(QStringLiteral("songFilterSort"), filters.sortIndex);
            settings.setValue(QStringLiteral("songFilterCategory"), filters.categoryPrefix);
        }
        m_closeAccepted = true;
        m_closeInProgress = false;
        close();
    });
}
