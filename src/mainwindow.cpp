#include "mainwindow.h"

#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDir>
#include <QDockWidget>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QFontMetrics>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QPainter>
#include <QPlainTextEdit>
#include <QPointer>
#include <QProgressDialog>
#include <QPushButton>
#include <QRegularExpressionValidator>
#include <QSettings>
#include <QSpinBox>
#include <QStatusBar>
#include <QStyle>
#include <QTabBar>
#include <QTabWidget>
#include <QTextEdit>
#include <QTimer>
#include <QUndoGroup>

#include <QChildEvent>
#include <QCloseEvent>
#include <QKeyEvent>
#include <QKeySequence>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <dwmapi.h>
#include <windows.h>
#endif

#include <algorithm>
#include <cmath>
#include <cstring>
#include <utility>

#include "audio/sampleimport.h"
#include "audio/sf2reader.h"
#include "audio/wavexport.h"
#include "core/miditimeline.h"
#include "porydaw_scale.h"
#include "project/samplereg.h"
#include "project/sidecar.h"
#include "project/songregistry.h"
#include "project/voicegroupeditcommand.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/newsongwizard.h"
#include "ui/polyphonypanel.h"
#include "ui/sampleeditordialog.h"
#include "ui/settingsdialog.h"
#include "ui/sf2zonepicker.h"
#include "ui/songlistpanel.h"
#include "ui/songview.h"
#include "ui/theme/themecontroller.h"
#include "ui/theme/themedialog.h"
#include "ui/theme/themeruntime.h"
#include "ui/transportbar.h"
#include "ui/typography.h"
#include "ui/viewsidecar.h"
#include "ui/voicegroupbrowser.h"

namespace {
constexpr int kIdleUiIntervalMs = 500;
constexpr int kPlaybackUiIntervalMs = 100;

const QString kLastOpenSongsKey = QStringLiteral("lastOpenSongs");
const QString kLastSongLabelKey = QStringLiteral("lastSongLabel");
const QString kVelocityColorsKey = QStringLiteral("velocityNoteColors");
const QString kNoteNamesKey = QStringLiteral("noteNames");
const QString kSystemFontKey = QStringLiteral("systemFont");
const QString kFollowPlayheadKey = QStringLiteral("followPlayhead");
const QString kOutputVolumeKey = QStringLiteral("outputVolume");
const QString kResonanceSuppressionKey = QStringLiteral("dsp/resonanceSuppression");
const QString kDrawerVelocityVisibleKey = QStringLiteral("editorDrawer/velocityVisible");
const QString kDrawerVelocityHeightKey = QStringLiteral("editorDrawer/velocityHeight");
const QString kDrawerAutomationVisibleKey = QStringLiteral("editorDrawer/automationVisible");
const QString kDrawerAutomationHeightKey = QStringLiteral("editorDrawer/automationHeight");
const QString kDrawerActivePageKey = QStringLiteral("editorDrawer/activePage");

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

std::optional<int> loadDrawerHeight(const QSettings &settings, const QString &key)
{
    if (!settings.contains(key))
        return std::nullopt;
    bool ok = false;
    const int height = settings.value(key).toInt(&ok);
    return ok && height > 0 ? std::optional<int>(height) : std::nullopt;
}

EditorDrawerState loadEditorDrawerState(const QSettings &settings)
{
    EditorDrawerState state;
    state.velocity.visible =
        settings.value(kDrawerVelocityVisibleKey, state.velocity.visible).toBool();
    state.velocity.height = loadDrawerHeight(settings, kDrawerVelocityHeightKey);
    state.automation.visible =
        settings.value(kDrawerAutomationVisibleKey, state.automation.visible).toBool();
    state.automation.height = loadDrawerHeight(settings, kDrawerAutomationHeightKey);
    if (settings.value(kDrawerActivePageKey).toString() == QLatin1String("velocity"))
        state.activePage = EditorDrawerPage::Velocity;
    return state;
}

void saveEditorDrawerState(QSettings &settings, const EditorDrawerState &state)
{
    settings.setValue(kDrawerVelocityVisibleKey, state.velocity.visible);
    settings.setValue(kDrawerAutomationVisibleKey, state.automation.visible);
    if (state.velocity.height)
        settings.setValue(kDrawerVelocityHeightKey, *state.velocity.height);
    else
        settings.remove(kDrawerVelocityHeightKey);
    if (state.automation.height)
        settings.setValue(kDrawerAutomationHeightKey, *state.automation.height);
    else
        settings.remove(kDrawerAutomationHeightKey);
    settings.setValue(kDrawerActivePageKey, state.activePage == EditorDrawerPage::Velocity
                                                ? QLatin1String("velocity")
                                                : QLatin1String("automations"));
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

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent)
    , m_projectIo(std::make_unique<ProjectIo>(this))
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
    m_editorDrawerState = loadEditorDrawerState(*m_themeSettings);
    updateWindowFrameTheme();
    m_themeDialog = std::make_unique<themes::ThemeDialog>(*m_themeController, this);
    buildUi();

    QSettings settings;
    restoreGeometry(settings.value(QStringLiteral("windowGeometry")).toByteArray());
    restoreState(settings.value(QStringLiteral("windowState")).toByteArray());
    m_songList->restoreFilters(settings.value(QStringLiteral("songFilterText")).toString(),
                               settings.value(QStringLiteral("songFilterSort")).toInt(),
                               settings.value(QStringLiteral("songFilterCategory")).toString());

    QString audioError;
    m_audioOk = m_audio.init(&audioError);
    if (!m_audioOk) {
        QMessageBox::warning(this, tr("Audio Error"),
                             tr("%1\n\nPlayback will be unavailable.").arg(audioError));
    } else if (m_audio.usingNullBackend()) {
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
    updateTimeLabel();
    updatePolyStatus();

    updateTransportActions();
}

MainWindow::~MainWindow()
{
    // The sessions delete their views below; the tab widget notices the
    // pages vanishing and would fire currentChanged into handlers that walk
    // the half-destroyed session list.
    if (m_tabs)
        disconnect(m_tabs, nullptr, this, nullptr);
    if (m_uiTimer)
        m_uiTimer->stop();
    if (m_playheadTimer)
        m_playheadTimer->stop();
    // Invalidate every session callback before the GUI-owned sessions are
    // destroyed; ProjectIo drops cancelled completions during shutdown.
    for (const auto &session : m_sessions) {
        if (session->pendingMidiRequest != 0)
            m_projectIo->cancel(session->pendingMidiRequest);
        if (session->pendingVgRequest != 0)
            m_projectIo->cancel(session->pendingVgRequest);
        if (session->pendingVgProbeRequest != 0)
            m_projectIo->cancel(session->pendingVgProbeRequest);
        if (session->pendingVgSaveRequest != 0)
            m_projectIo->cancel(session->pendingVgSaveRequest);
        if (session->pendingPreviewRequest != 0)
            m_projectIo->cancel(session->pendingPreviewRequest);
        if (session->pendingSaveRequest != 0)
            m_projectIo->cancel(session->pendingSaveRequest);
        if (session->pendingSidecarRequest != 0)
            m_projectIo->cancel(session->pendingSidecarRequest);
    }
    for (const auto requestId :
         {m_pendingCatalogRequest, m_pendingSampleSetRequest, m_pendingSampleProbeRequest,
          m_pendingSampleProjectRequest, m_pendingSampleCommitRequest,
          m_pendingRegistrationPlanRequest, m_pendingRegistrationRequest,
          m_pendingDeletionPlanRequest, m_pendingDeletionRequest, m_pendingProjectRefreshRequest,
          m_pendingCreateSongRequest, m_pendingCreateVoicegroupRequest}) {
        if (requestId != 0)
            m_projectIo->cancel(requestId);
    }
    // Stop the audio thread before the sessions free the timeline and
    // voicegroup it borrows.
    m_audio.shutdown();
    voicegroup_free_samples(m_sampleSet);
}

void MainWindow::buildUi()
{
    // Every user-facing action registers with the keymap so its shortcut is
    // rebindable; the registry owns defaults and re-applies user changes.
    auto &keys = keymap::Registry::instance();

    // Menu
    QMenu *fileMenu = menuBar()->addMenu(tr("&File"));
    QAction *openAction =
        fileMenu->addAction(tr("&Open Project..."), this, &MainWindow::openProject);
    keys.attach(QStringLiteral("file.open_project"), openAction);
    m_newSongAction = fileMenu->addAction(tr("&New Song..."), this, &MainWindow::newSong);
    keys.attach(QStringLiteral("file.new_song"), m_newSongAction);
    m_newSongAction->setEnabled(false);
    m_importAction = fileMenu->addAction(tr("&Import MIDI..."), this, &MainWindow::importMidi);
    keys.attach(QStringLiteral("file.import_midi"), m_importAction);
    m_importAction->setEnabled(false);
    m_saveAction = fileMenu->addAction(tr("&Save Song"), this, &MainWindow::saveSong);
    keys.attach(QStringLiteral("file.save_song"), m_saveAction);
    m_saveAction->setEnabled(false);
    m_registerAction =
        fileMenu->addAction(tr("Re&gister Song"), this, &MainWindow::registerLoadedSong);
    keys.attach(QStringLiteral("file.register_song"), m_registerAction);
    m_registerAction->setEnabled(false);
    m_closeTabAction = fileMenu->addAction(tr("&Close Tab"), this, [this] {
        if (m_tabs->currentIndex() >= 0)
            closeTab(m_tabs->currentIndex());
    });
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
    m_undoGroup = new QUndoGroup(this);
    QAction *undoAction = m_undoGroup->createUndoAction(this, tr("&Undo"));
    keys.attach(QStringLiteral("edit.undo"), undoAction);
    editMenu->addAction(undoAction);
    QAction *redoAction = m_undoGroup->createRedoAction(this, tr("&Redo"));
    keys.attach(QStringLiteral("edit.redo"), redoAction);
    editMenu->addAction(redoAction);
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
        if (m_active)
            m_active->view->copySelection();
    });
    editMenu->addAction(m_copyAction);
    m_copyAction->setEnabled(false);
    editMenu->addSeparator();
    QAction *preferencesAction = editMenu->addAction(tr("Prefere&nces..."), this, [this] {
        openSettings(m_active ? SettingsDialog::Tab::Song : SettingsDialog::Tab::Engine);
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
    connect(m_eventListAction, &QAction::toggled, this, [this](bool on) {
        if (m_active)
            m_active->view->setEventListVisible(on);
    });

    viewMenu->addSeparator();
    m_automationDrawerAction = viewMenu->addAction(tr("Automation Lanes"));
    m_automationDrawerAction->setObjectName(QStringLiteral("automationDrawerWindowAction"));
    m_automationDrawerAction->setShortcut(QKeySequence(Qt::Key_A));
    m_automationDrawerAction->setShortcutContext(Qt::WindowShortcut);
    m_automationDrawerAction->setToolTip(tr("Show or hide automation lanes (A)"));
    m_automationDrawerAction->setEnabled(false);
    connect(m_automationDrawerAction, &QAction::triggered, this,
            [this] { toggleDrawerPage(/*automation=*/true); });
    m_velocityDrawerAction = viewMenu->addAction(tr("Velocity Lane"));
    m_velocityDrawerAction->setObjectName(QStringLiteral("velocityDrawerWindowAction"));
    m_velocityDrawerAction->setShortcut(QKeySequence(Qt::Key_V));
    m_velocityDrawerAction->setShortcutContext(Qt::WindowShortcut);
    m_velocityDrawerAction->setToolTip(tr("Show or hide note velocities (V)"));
    m_velocityDrawerAction->setEnabled(false);
    connect(m_velocityDrawerAction, &QAction::triggered, this,
            [this] { toggleDrawerPage(/*automation=*/false); });

    // Tools menu: project-level utilities that aren't song-scoped.
    QMenu *toolsMenu = menuBar()->addMenu(tr("&Tools"));
    m_importSampleAction =
        toolsMenu->addAction(tr("Import &Sample..."), this, &MainWindow::importSample);
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

    // Transport toolbar. The bar owns its presentation; this window keeps
    // session and audio orchestration behind the emitted user intents.
    m_transportBar = new TransportBar(this);
    {
        QSettings settings;
        m_transportBar->setFollowPlayhead(settings.value(kFollowPlayheadKey, true).toBool());
        m_audio.setOutputVolume(settings.value(kOutputVolumeKey, 100).toInt());
        m_transportBar->setOutputVolume(m_audio.outputVolume());
        const bool resonanceSuppression = settings.value(kResonanceSuppressionKey, false).toBool();
        m_audio.setResonanceSuppression(resonanceSuppression);
        m_transportBar->resonanceAction()->setChecked(resonanceSuppression);
    }
    addToolBar(m_transportBar);
    // Space is window-scoped so play/pause works regardless of focus.
    addAction(m_transportBar->playPauseAction());
    connect(m_transportBar, &TransportBar::goToStartRequested, this, [this] {
        if (m_active)
            m_active->view->goToStart();
    });
    connect(m_transportBar, &TransportBar::playRequested, this, [this] { startPlayback(); });
    connect(m_transportBar, &TransportBar::playPauseRequested, this, [this] {
        if (m_audio.transport() == Transport::Playing)
            pausePlayback();
        else
            startPlayback(/*fromEditCursor=*/true);
    });
    connect(m_transportBar, &TransportBar::pauseRequested, this, [this] { pausePlayback(); });
    connect(m_transportBar, &TransportBar::stopRequested, this, [this] { stopPlayback(); });
    connect(m_transportBar, &TransportBar::loopEnabledChanged, this,
            [this](bool enabled) { m_audio.setLoopEnabled(enabled); });
    connect(m_transportBar, &TransportBar::followPlayheadChanged, this, [this](bool enabled) {
        QSettings settings;
        settings.setValue(kFollowPlayheadKey, enabled);
        for (int i = 0; i < m_tabs->count(); i++) {
            if (SongSession *session = sessionForWidget(m_tabs->widget(i)))
                session->view->setFollowPlayhead(enabled);
        }
    });
    connect(m_transportBar, &TransportBar::resonanceSuppressionChanged, this, [this](bool enabled) {
        QSettings settings;
        settings.setValue(kResonanceSuppressionKey, enabled);
        m_audio.setResonanceSuppression(enabled);
    });
    connect(m_transportBar, &TransportBar::outputVolumeChanged, this, [this](int value) {
        m_audio.setOutputVolume(value);
        QSettings settings;
        settings.setValue(kOutputVolumeKey, m_audio.outputVolume());
    });
    connect(m_transportBar, &TransportBar::masterVolumeChanged, this, [this](int value) {
        if (!m_active || m_active->doc.cfg().masterVolume == value)
            return;
        SongCfg cfg = m_active->doc.cfg();
        cfg.masterVolume = value;
        m_active->doc.setCfg(cfg);
    });
    connect(m_transportBar, &TransportBar::scaleRootChanged, this, [this](int root) {
        if (m_active)
            m_active->view->setScaleRoot(root);
    });
    connect(m_transportBar, &TransportBar::scaleIdChanged, this,
            [this](porydaw_scale::ScaleId scale) {
                if (m_active)
                    m_active->view->setScaleId(scale);
            });
    connect(m_transportBar, &TransportBar::scaleHighlightChanged, this, [this](bool enabled) {
        if (m_active)
            m_active->view->setScaleHighlight(enabled);
    });
    connect(m_transportBar, &TransportBar::scaleFoldChanged, this, [this](bool enabled) {
        if (m_active)
            m_active->view->setScaleFold(enabled);
    });

    // Dock titles and the tab strip share this metric-derived outer height so
    // neither clips when the platform font or small-icon metric changes.
    const auto chromeHeight =
        layout::chromeRowHeight(font(), style()->pixelMetric(QStyle::PM_SmallIconSize));
    const auto installDockTitle = [chromeHeight](QDockWidget *target) {
        auto *title = new QLabel(target->windowTitle(), target);
        title->setAlignment(Qt::AlignLeft | Qt::AlignVCenter);
        title->setContentsMargins(::layout::space(::layout::Space::Two), 0,
                                  ::layout::space(::layout::Space::Two), 0);
        title->setFixedHeight(chromeHeight);
        title->setAttribute(Qt::WA_TransparentForMouseEvents);
        QObject::connect(target, &QDockWidget::windowTitleChanged, title, &QLabel::setText);
        target->setTitleBarWidget(title);
    };

    // Song browser dock
    auto *dock = new QDockWidget(tr("Songs"), this);
    dock->setObjectName(QStringLiteral("songsDock"));
    dock->setFeatures(QDockWidget::DockWidgetMovable);
    installDockTitle(dock);
    m_songList = new SongListPanel(dock);
    connect(m_songList, &SongListPanel::songActivated, this, &MainWindow::songActivated);
    connect(m_songList, &SongListPanel::songOpenInNewTabRequested, this,
            &MainWindow::songOpenInNewTab);
    connect(m_songList, &SongListPanel::songRegisterRequested, this, &MainWindow::registerSongById);
    connect(m_songList, &SongListPanel::songDeleteRequested, this, &MainWindow::deleteSongById);
    dock->setWidget(m_songList);
    addDockWidget(Qt::LeftDockWidgetArea, dock);

    auto *findAction = new QAction(tr("Find Song"), this);
    keys.attach(QStringLiteral("songs.find"), findAction);
    connect(findAction, &QAction::triggered, this, [this] { m_songList->focusSearch(); });
    addAction(findAction);

    // Voicegroup browser dock (SPEC §6.1): the active tab's instruments,
    // click-and-hold to audition through the preview engine instance, with
    // an editor panel for the selected voice.
    m_vgDock = new QDockWidget(tr("Voicegroup"), this);
    m_vgDock->setObjectName(QStringLiteral("voicegroupDock"));
    m_vgDock->setFeatures(QDockWidget::DockWidgetMovable);
    installDockTitle(m_vgDock);
    m_vgBrowser = new VoicegroupBrowser(m_vgDock);
    connect(m_vgBrowser, &VoicegroupBrowser::auditionVoice, this,
            [this](int voice, int key, int velocity) {
                if (m_audioOk)
                    m_audio.previewVoice(uint8_t(voice), uint8_t(key), uint8_t(velocity));
            });
    connect(m_vgBrowser, &VoicegroupBrowser::voiceEditRequested, this,
            &MainWindow::onVoiceEditRequested);
    connect(m_vgBrowser, &VoicegroupBrowser::newVoicegroupRequested, this,
            &MainWindow::newVoicegroup);
    connect(m_vgBrowser, &VoicegroupBrowser::newSampleRequested, this,
            &MainWindow::importSampleForSlot);
    connect(m_vgBrowser, &VoicegroupBrowser::editSampleRequested, this,
            &MainWindow::editSampleForSlot);
    // The sample picker: loop badges and browse audition both read the
    // committed sample data the engine would play, loaded lazily in one
    // batch per catalog generation.
    m_vgBrowser->setSampleInfoProvider([this](const QString &symbol) {
        SamplePickInfo info;
        const WaveData *wd = sampleWaveFor(symbol);
        if (!wd || !wd->data || wd->size == 0)
            return info;
        info.known = true;
        info.looped = (wd->status & 0x4000) != 0;
        info.rateHz = int(wd->freq / 1024);
        info.seconds = info.rateHz > 0 ? double(wd->size) / info.rateHz : 0.0;
        return info;
    });
    connect(
        m_vgBrowser, &VoicegroupBrowser::sampleAuditionRequested, this,
        [this](const QString &symbol, VgAuditionKind kind, const AuditionSlots::Adsr &adsr) {
            if (!m_audioOk)
                return;
            if (kind == VgAuditionKind::Keysplit) {
                auditionKeysplit(symbol);
                return;
            }
            if (kind == VgAuditionKind::Wave) {
                ensureSampleSet();
                const uint32_t *pw = m_progWaves.value(symbol, nullptr);
                if (pw)
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
    connect(m_vgBrowser, &VoicegroupBrowser::sampleAuditionStopRequested, this, [this] {
        if (m_audioOk)
            m_audio.auditionSampleOff();
    });
    // The dock's voicegroup selector: same undoable cfg edit as Song
    // Settings; onDocumentChanged does the actual swap (and, on a
    // not-found arg, keeps the old voicegroup with a status message).
    connect(m_vgBrowser, &VoicegroupBrowser::voicegroupChangeRequested, this,
            [this](const QString &arg) {
                if (!m_active)
                    return;
                SongCfg cfg = m_active->doc.cfg();
                // "_dummy" IS the empty arg's meaning; don't write it out.
                if (arg == cfg.voicegroupArg ||
                    (cfg.voicegroupArg.isEmpty() && arg == QLatin1String("_dummy")))
                    return;
                cfg.voicegroupArg = arg;
                m_active->doc.setCfg(cfg);
            });
    m_vgDock->setWidget(m_vgBrowser);
    addDockWidget(Qt::LeftDockWidgetArea, m_vgDock);

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
                // commitEditCursor's editCursorMoved connect already seeks
                // the engine while playing/paused; when stopped, playback
                // starts from the edit cursor. revealNote selects the losing
                // track and the lost note itself.
                if (!m_active)
                    return;
                m_active->view->revealNote(track, uint8_t(midiKey), tick);
                m_active->view->commitEditCursor(tick);
                m_active->view->ensureTickVisible(tick);
            });
    m_polyDock->setWidget(m_polyPanel);
    addDockWidget(Qt::RightDockWidgetArea, m_polyDock);
    m_polyDock->hide();
    QAction *polyDockAction = m_polyDock->toggleViewAction();
    polyDockAction->setText(tr("&Polyphony Debugger"));
    polyDockAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+P")));
    viewMenu->addAction(polyDockAction);

    // App-wide appearance preferences, set off by a separator from the
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
    connect(m_velocityColorsAction, &QAction::toggled, this, [this](bool on) {
        QSettings settings;
        settings.setValue(kVelocityColorsKey, on);
        for (int i = 0; i < m_tabs->count(); i++) {
            if (SongSession *s = sessionForWidget(m_tabs->widget(i)))
                s->view->setVelocityColorMode(on);
        }
    });

    m_noteNamesAction = viewMenu->addAction(tr("Show Note &Names"));
    m_noteNamesAction->setCheckable(true);
    keys.attach(QStringLiteral("view.note_names"), m_noteNamesAction);
    {
        QSettings settings;
        m_noteNamesAction->setChecked(settings.value(kNoteNamesKey, false).toBool());
    }
    connect(m_noteNamesAction, &QAction::toggled, this, [this](bool on) {
        QSettings settings;
        settings.setValue(kNoteNamesKey, on);
        for (int i = 0; i < m_tabs->count(); i++) {
            if (SongSession *s = sessionForWidget(m_tabs->widget(i)))
                s->view->setNoteNameMode(on);
        }
    });

    // The transport bar's follow toggle, findable here too: an app-wide
    // persisted preference like the rest of this group.
    viewMenu->addAction(m_transportBar->followPlayheadAction());

    // Song tabs: each open song lives in its own tab with its own view,
    // document, and undo stack.
    m_tabs = new QTabWidget(this);
    m_tabs->setFocusPolicy(Qt::NoFocus);
    m_tabs->setTabsClosable(true);
    m_tabs->setMovable(true);
    m_tabs->setDocumentMode(true);
    m_tabs->tabBar()->setFixedHeight(chromeHeight);
    m_tabs->tabBar()->setFocusPolicy(Qt::NoFocus);
    connect(m_tabs, &QTabWidget::currentChanged, this, &MainWindow::tabChanged);
    connect(m_tabs, &QTabWidget::tabCloseRequested, this, &MainWindow::closeTab);
    connect(m_tabs->tabBar(), &QTabBar::tabMoved, this, [this](int, int) { persistOpenTabs(); });
    setCentralWidget(m_tabs);

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
    m_songList->setFocus();
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

SongSession *MainWindow::sessionForWidget(QWidget *widget) const
{
    for (const auto &session : m_sessions) {
        if (session->view == widget)
            return session.get();
    }
    return nullptr;
}

SongSession *MainWindow::sessionForLabel(const QString &label) const
{
    for (const auto &session : m_sessions) {
        QString sessionLabel;
        if (session->midiBound) {
            sessionLabel = session->doc.label();
        } else {
            const int index = m_tabs->indexOf(session->view);
            sessionLabel = index >= 0 ? m_tabs->tabText(index) : QString();
            if (sessionLabel.endsWith(QLatin1Char('*')))
                sessionLabel.chop(1);
        }
        if (sessionLabel == label)
            return session.get();
    }
    return nullptr;
}

SongSession *MainWindow::createSession()
{
    auto owned = std::make_unique<SongSession>();
    SongSession *s = owned.get();
    s->view = new SongView;
    s->view->setSong(nullptr, nullptr);
    s->view->setDocument(nullptr);
    s->view->setEnabled(false);
    s->view->setVelocityColorMode(m_velocityColorsAction->isChecked());
    s->view->setNoteNameMode(m_noteNamesAction->isChecked());
    s->view->setFollowPlayhead(m_transportBar->followPlayhead());
    s->view->applyEditorDrawerState(m_editorDrawerState);
    connect(s->view, &SongView::editorDrawerStateChanged, this,
            [this](const EditorDrawerState &state) { setEditorDrawerState(state); });
    connect(s->view, &SongView::muteMaskChanged, this, [this, s](uint32_t mask) {
        if (s == m_active)
            m_audio.setMuteMask(mask);
    });
    connect(s->view, &SongView::soloMaskChanged, this, [this, s](uint32_t mask) {
        if (s == m_active)
            m_audio.setSoloMask(mask);
    });
    connect(s->view, &SongView::auditionNote, this, [this, s](int track, int key, int velocity) {
        if (s == m_active && m_audioOk && m_audio.songLoaded())
            m_audio.previewNote(uint8_t(track), uint8_t(key), uint8_t(velocity));
    });
    connect(s->view, &SongView::auditionNoteTimed, this,
            [this, s](int track, int key, int velocity, quint32 durationSamples) {
                if (s == m_active && m_audioOk && m_audio.songLoaded())
                    m_audio.previewNoteTimed(uint8_t(track), uint8_t(key), uint8_t(velocity),
                                             durationSamples);
            });
    connect(s->view, &SongView::auditionVoice, this, [this, s](int voice, int key, int velocity) {
        if (s == m_active && m_audioOk)
            m_audio.previewVoice(uint8_t(voice), uint8_t(key), uint8_t(velocity));
    });
    connect(s->view, &SongView::statusMessage, this, [this, s](const QString &text) {
        if (s == m_active)
            statusBar()->showMessage(text, 6000);
    });
    connect(s->view, &SongView::playPauseFromRequested, this, [this, s](uint64_t tick) {
        if (s != m_active)
            return;
        if (m_audio.transport() == Transport::Playing) {
            m_transportBar->playPauseAction()->trigger();
            s->view->commitEditCursor(tick);
            return;
        }
        s->view->commitEditCursor(tick);
        m_transportBar->playPauseAction()->trigger();
    });
    // Jump-from-context voice navigation (header voice line, event list):
    // raise the dock and select the slot. No keyboard focus moves — Space
    // and the roll's shortcuts keep working.
    connect(s->view, &SongView::revealVoiceRequested, this, [this, s](int program) {
        if (s != m_active)
            return;
        m_vgDock->show();
        m_vgDock->raise();
        m_vgBrowser->revealSlot(program);
    });
    // A sidecar restore (applyViewState) can flip the view under the menu.
    connect(s->view, &SongView::eventListVisibilityChanged, this, [this, s](bool on) {
        if (s == m_active) {
            QSignalBlocker blocker(m_eventListAction);
            m_eventListAction->setChecked(on);
            updateDrawerActions();
        }
    });
    const auto syncScale = [this, s] { syncScaleControls(s); };
    connect(s->view, &SongView::scaleHighlightChanged, this, syncScale);
    connect(s->view, &SongView::scaleFoldChanged, this, syncScale);
    connect(s->view, &SongView::scaleRootChanged, this, syncScale);
    connect(s->view, &SongView::scaleIdChanged, this, syncScale);
    // Moving the edit cursor while playing (or paused) seeks playback there,
    // chasing controller state to the landing position.
    connect(s->view, &SongView::editCursorMoved, this, [this, s](uint64_t tick) {
        if (s == m_active && m_audioOk && m_audio.songLoaded() &&
            m_audio.transport() != Transport::Stopped) {
            const uint64_t targetSample = m_audio.timeline()->sampleForTick(tick);
            m_audio.seek(targetSample);
            // The seek lands within one audio period; show its target now
            // rather than the stale engine playhead (while playing, the
            // playhead timer takes over from the next real position).
            s->view->setPlayheadSample(targetSample, m_audio.transport() == Transport::Playing);
        }
    });
    connect(&s->doc, &SongDocument::documentChanged, this, [this, s] { onDocumentChanged(*s); });
    connect(s->doc.undoStack(), &QUndoStack::cleanChanged, this, [this, s](bool) {
        updateTabTitle(*s);
        if (s == m_active)
            updateWindowTitle();
    });
    m_undoGroup->addStack(s->doc.undoStack());
    m_sessions.push_back(std::move(owned));
    return s;
}

void MainWindow::destroySession(SongSession *session)
{
    if (!session)
        return;
    if (session->pendingMidiRequest != 0) {
        m_projectIo->cancel(session->pendingMidiRequest);
        session->pendingMidiRequest = 0;
    }
    if (session->pendingVgRequest != 0) {
        m_projectIo->cancel(session->pendingVgRequest);
        session->pendingVgRequest = 0;
    }
    if (session->pendingVgProbeRequest != 0) {
        m_projectIo->cancel(session->pendingVgProbeRequest);
        session->pendingVgProbeRequest = 0;
    }
    if (session->pendingVgSaveRequest != 0) {
        m_projectIo->cancel(session->pendingVgSaveRequest);
        session->pendingVgSaveRequest = 0;
    }
    if (session->pendingPreviewRequest != 0) {
        m_projectIo->cancel(session->pendingPreviewRequest);
        session->pendingPreviewRequest = 0;
    }
    if (session->pendingSaveRequest != 0) {
        m_projectIo->cancel(session->pendingSaveRequest);
        session->pendingSaveRequest = 0;
    }
    if (session->pendingSidecarRequest != 0) {
        m_projectIo->cancel(session->pendingSidecarRequest);
        session->pendingSidecarRequest = 0;
    }
    const int index = m_tabs->indexOf(session->view);
    if (index >= 0)
        m_tabs->removeTab(index); // fires currentChanged → activateSession
    // Removing the current tab re-activated a neighbor (rebinding the audio
    // engine) through currentChanged; this only fires if that didn't happen.
    if (m_active == session)
        activateSession(nullptr);
    std::erase_if(m_sessions, [session](const std::unique_ptr<SongSession> &candidate) {
        return candidate.get() == session;
    });
}
void MainWindow::promptToSaveAllSessions(SessionContinuation continuation)
{
    auto sessions = std::make_shared<std::vector<SongSession *>>();
    sessions->reserve(m_sessions.size());
    for (const auto &session : m_sessions)
        sessions->push_back(session.get());
    auto completion = std::make_shared<SessionContinuation>(std::move(continuation));
    auto next = std::make_shared<std::function<void(size_t)>>();
    const std::weak_ptr<std::function<void(size_t)>> weakNext = next;
    *next = [this, sessions, completion, weakNext](size_t index) {
        const auto isLive = [this](SongSession *candidate) {
            return candidate && std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                                            [candidate](const std::unique_ptr<SongSession> &owned) {
                                                return owned.get() == candidate;
                                            });
        };
        if (index >= sessions->size()) {
            if (*completion)
                (*completion)(true);
            return;
        }
        SongSession *session = sessions->at(index);
        if (!isLive(session)) {
            if (*completion)
                (*completion)(false);
            return;
        }
        maybeSaveSession(*session, [this, sessions, completion, weakNext, session, index,
                                    isLive](bool succeeded) {
            if (!succeeded || !isLive(session)) {
                if (*completion)
                    (*completion)(false);
                return;
            }
            if (const auto next = weakNext.lock())
                (*next)(index + 1);
        });
    };
    (*next)(0);
}

void MainWindow::teardownSessions()
{
    m_tearingDown = true;
    // One engine/dock detach up front; the guarded currentChanged handler
    // then lets the tabs vanish without rebinding each doomed neighbor.
    activateSession(nullptr, /*force=*/true);
    while (!m_sessions.empty())
        destroySession(m_sessions.back().get());
    m_tearingDown = false;
}

void MainWindow::activateSession(SongSession *session, bool force)
{
    if (session == m_active && !force)
        return;
    const SongSession *previous = m_active;
    // Switching tabs stops playback in the tab being left.
    if (m_audioOk)
        m_audio.stop();
    m_active = session;
    const bool ready = session && session->isInteractive();
    m_undoGroup->setActiveStack(ready ? session->doc.undoStack() : nullptr);
    syncMasterVolumeControl();
    syncScaleControls(session);

    m_saveAction->setEnabled(ready);
    m_exportWavAction->setEnabled(ready);
    m_settingsAction->setEnabled(ready);
    m_closeTabAction->setEnabled(session != nullptr);
    m_eventListAction->setEnabled(ready);
    m_copyAction->setEnabled(ready);
    {
        // Reflect the incoming tab's roll/event-list state without the
        // checkbox driving a redundant toggle.
        QSignalBlocker blocker(m_eventListAction);
        m_eventListAction->setChecked(ready && session->view->eventListVisible());
    }
    updateDrawerActions();

    if (!session) {
        if (m_audioOk)
            m_audio.unloadSong();
        m_polyPanel->clearSession();
        m_vgBrowser->setVoicegroup(nullptr);
        m_vgBrowser->setLoading(false);
        updateVgDockTitle();
        m_registerAction->setEnabled(false);
        m_transportBar->setSongName(QString());
        updateTimeLabel();
        updatePolyStatus();
        m_songList->setCurrentSong(-1);
        updateWindowTitle();
        updateTransportActions();
        persistOpenTabs();
        synchronizePlayhead();
        return;
    }

    if (!ready) {
        if (m_audioOk)
            m_audio.unloadSong();
        m_polyPanel->clearSession();
        if (session->vgBound && session->voicegroup)
            updateVoicegroupBrowser();
        else {
            m_vgBrowser->setVoicegroup(nullptr);
            m_vgBrowser->setLoading(true);
        }
        updateVgDockTitle();
        m_registerAction->setEnabled(false);
        const int index = m_tabs->indexOf(session->view);
        const QString label = index >= 0 ? m_tabs->tabText(index) : QString();
        m_transportBar->setSongName(label);
        m_songList->setCurrentSong(session->songId);
        updateWindowTitle();
        updateTransportActions();
        persistOpenTabs();
        synchronizePlayhead();
        return;
    }

    // Only on a genuine switch: while re-binding the same session (force),
    // the engine may still borrow this session's voicegroup, which the
    // refresh would free.
    if (session != previous)
        maybeRefreshVoicegroup(*session);
    if (m_audioOk)
        attachEngine(*session);
    session->view->setEnabled(true);
    synchronizePlayhead();
    updateVoicegroupBrowser();
    updatePolyPanelContext(session);
    updateTimeLabel();
    updatePolyStatus();

    // Register Song stays available while ANY registration file lacks (or
    // mis-states) the song's line — not only for unregistered strays. A song
    // registered before porydaw wrote charmap.txt entries reads as registered
    // from the song table, but still needs a re-register to backfill.
    bool complete = true;
    if (session->songId >= 0 && session->songId < m_project.songs().size())
        complete = m_project.songs().at(session->songId).registrationGaps.isEmpty();
    m_registerAction->setEnabled(!complete);
    m_transportBar->setSongName(session->doc.label());
    m_songList->setCurrentSong(session->songId);
    updateWindowTitle();
    updateTransportActions();
    session->view->focusActiveSurface();
    persistOpenTabs();
}

void MainWindow::attachEngine(SongSession &session)
{
    m_audio.loadSong(session.timeline, session.voicegroup, songSettingsFor(session));
    // loadSong resets the engine's masks; the view remembers the tab's.
    m_audio.setMuteMask(session.view->muteMask());
    m_audio.setSoloMask(session.view->soloMask());
}

void MainWindow::updatePolyPanelContext(SongSession *session)
{
    if (!session || !session->isInteractive()) {
        m_polyPanel->clearSession();
        return;
    }
    m_polyPanel->setTimeline(session->timeline.get());
    QStringList trackNames;
    for (int t = 0; t < MAX_TRACKS; t++)
        trackNames.append(session->doc.trackName(t));
    m_polyPanel->setTrackNames(trackNames);
    // Copied out so a voicegroup swap can't leave the panel with a dangling
    // pointer.
    QStringList voiceNames;
    if (session->voicegroup) {
        for (int v = 0; v < VOICEGROUP_SIZE; v++)
            voiceNames.append(QString::fromLatin1(session->voicegroup->voiceNames[v]));
    }
    m_polyPanel->setVoiceNames(voiceNames);
}

void MainWindow::maybeRefreshVoicegroup(SongSession &session)
{
    if (!session.midiBound || !session.vgBound || !session.vgSource || session.vgSource->dirty())
        return;
    // Metadata and the possible reload are both worker operations. The
    // cached stamp remains authoritative until the probe completes.
    queueVoicegroupProbe(session);
}

void MainWindow::refreshSessionsAfterVgSave(const QString &filePath, SongSession *except)
{
    for (const auto &owned : m_sessions) {
        SongSession *session = owned.get();
        if (session == except || !session->midiBound || !session->vgBound || !session->vgSource ||
            session->vgSource->filePath() != filePath || session->vgSource->dirty())
            continue;
        const int keepSlot = session == m_active ? m_vgBrowser->currentSlot() : 0;
        queueVoicegroupLoad(*session, session->doc.cfg(), keepSlot);
    }
}

void MainWindow::persistOpenTabs()
{
    // Never persist mid-teardown: during a project switch the settings
    // already point at the NEW project, and the dying tabs' labels would
    // be recorded against it if a crash landed in this window.
    if (m_tearingDown || !m_persistSession || !m_project.isOpen())
        return;
    QSettings settings;
    QStringList labels;
    for (int i = 0; i < m_tabs->count(); i++) {
        if (!sessionForWidget(m_tabs->widget(i)))
            continue;
        QString label = m_tabs->tabText(i);
        if (label.endsWith(QLatin1Char('*')))
            label.chop(1);
        if (!label.isEmpty())
            labels << label;
    }
    if (labels.isEmpty()) {
        settings.remove(kLastOpenSongsKey);
        settings.remove(kLastSongLabelKey);
        return;
    }
    QString activeLabel = labels.first();
    if (m_active) {
        const int index = m_tabs->indexOf(m_active->view);
        if (index >= 0) {
            activeLabel = m_tabs->tabText(index);
            if (activeLabel.endsWith(QLatin1Char('*')))
                activeLabel.chop(1);
        }
    }
    settings.setValue(kLastOpenSongsKey, labels);
    settings.setValue(kLastSongLabelKey, activeLabel);
}

void MainWindow::refreshSessionSongIds()
{
    for (const auto &session : m_sessions) {
        QString label;
        const int index = m_tabs->indexOf(session->view);
        if (index >= 0)
            label = m_tabs->tabText(index);
        if (label.endsWith(QLatin1Char('*')))
            label.chop(1);
        session->songId = -1;
        for (const SongInfo &song : m_project.songs()) {
            if (song.label == label) {
                session->songId = song.id;
                break;
            }
        }
    }
    if (m_active)
        m_songList->setCurrentSong(m_active->songId);
}

void MainWindow::updateTabTitle(SongSession &session)
{
    if (!session.midiBound)
        return;
    const int index = m_tabs->indexOf(session.view);
    if (index < 0)
        return;
    m_tabs->setTabText(index, session.isDirty() ? session.doc.label() + QLatin1Char('*')
                                                : session.doc.label());
}

void MainWindow::toggleDrawerPage(bool automation)
{
    if (!m_active || !m_active->isInteractive() || m_active->view->eventListVisible())
        return;
    SongView *view = m_active->view;
    const EditorDrawerPage page =
        automation ? EditorDrawerPage::Automations : EditorDrawerPage::Velocity;
    const bool hiding = view->drawerSectionVisible(page);
    view->toggleDrawerSection(page);
    statusBar()->showMessage(automation ? (hiding ? QStringLiteral("Automation lanes hidden")
                                                  : QStringLiteral("Automation lanes shown"))
                                        : (hiding ? QStringLiteral("Velocity lane hidden")
                                                  : QStringLiteral("Velocity lane shown")),
                             6000);
}

void MainWindow::setEditorDrawerState(const EditorDrawerState &state)
{
    if (m_editorDrawerState == state)
        return;
    m_editorDrawerState = state;
    saveEditorDrawerState(*m_themeSettings, state);
    for (const auto &session : m_sessions)
        session->view->applyEditorDrawerState(state);
}

void MainWindow::updateDrawerActions()
{
    const bool enabled =
        m_active && m_active->isInteractive() && !m_active->view->eventListVisible();
    m_automationDrawerAction->setEnabled(enabled);
    m_velocityDrawerAction->setEnabled(enabled);
}

void MainWindow::tabChanged(int index)
{
    if (m_tearingDown || m_restoringSession)
        return;
    SongSession *session = index >= 0 ? sessionForWidget(m_tabs->widget(index)) : nullptr;
    activateSession(session);
    syncScaleControls(session);
}

void MainWindow::closeTab(int index)
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted)
        return;
    SongSession *session = sessionForWidget(m_tabs->widget(index));
    if (!session)
        return;
    maybeSaveSession(*session, [this, session](bool succeeded) {
        if (!succeeded)
            return;
        const bool live = std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                                      [session](const std::unique_ptr<SongSession> &candidate) {
                                          return candidate.get() == session;
                                      });
        if (!live)
            return;
        saveViewState(*session);
        destroySession(session);
        persistOpenTabs();
    });
}

void MainWindow::openProject()
{
    QSettings settings;
    const QString startDir =
        settings.value(QStringLiteral("lastProjectDir"), QDir::homePath()).toString();
    const QString dir =
        QFileDialog::getExistingDirectory(this, tr("Open Decomp Project"), startDir);
    if (dir.isEmpty())
        return;
    openProjectDir(dir);
}

void MainWindow::restoreSession()
{
    QSettings settings;
    const QString dir = settings.value(QStringLiteral("lastProjectDir")).toString();
    if (dir.isEmpty())
        return;
    // Read before openProjectDir clears them for the fresh project.
    QStringList labels = settings.value(kLastOpenSongsKey).toStringList();
    const QString activeLabel = settings.value(kLastSongLabelKey).toString();
    if (labels.isEmpty() && !activeLabel.isEmpty())
        labels << activeLabel; // session recorded before tabs existed
    openProjectDir(dir, /*interactive=*/false,
                   [this, labels = std::move(labels), activeLabel](bool succeeded) {
                       if (!succeeded)
                           return;
                       // Load the tabs without activating each in turn — the
                       // per-activation work (engine rebind, voicegroup-dock
                       // rebuild, tab persistence) would run N times with all
                       // but the last discarded. One activation at the end,
                       // for the remembered active tab.
                       m_restoringSession = true;
                       for (const QString &label : labels)
                           loadSongByLabel(label, /*newTab=*/true);
                       m_restoringSession = false;
                       SongSession *toActivate = sessionForLabel(activeLabel);
                       if (!toActivate && m_tabs->count() > 0)
                           toActivate = sessionForWidget(m_tabs->currentWidget());
                       if (toActivate) {
                           m_tabs->setCurrentWidget(toActivate->view);
                           if (m_active != toActivate)
                               activateSession(toActivate);
                       }
                   });
}

void MainWindow::cancelDisposableProjectRequests()
{
    const auto cancel = [this](uint64_t &requestId) {
        if (requestId == 0)
            return;
        m_projectIo->cancel(requestId);
        requestId = 0;
    };
    cancel(m_pendingCatalogRequest);
    m_vgCatalog.loading = false;
    cancel(m_pendingSampleSetRequest);
    cancel(m_pendingSampleProbeRequest);
    cancel(m_pendingSampleProjectRequest);
    cancel(m_pendingRegistrationPlanRequest);
    cancel(m_pendingDeletionPlanRequest);
    cancel(m_pendingProjectRefreshRequest);
}

bool MainWindow::projectMutationInProgress() const
{
    return m_pendingSampleCommitRequest != 0 || m_pendingRegistrationRequest != 0 ||
           m_pendingDeletionRequest != 0 || m_pendingCreateSongRequest != 0 ||
           m_pendingCreateVoicegroupRequest != 0;
}

void MainWindow::openProjectDir(const QString &dir, bool interactive,
                                ProjectOpenContinuation continuation)
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted) {
        if (continuation)
            continuation(false);
        return;
    }
    if (projectMutationInProgress()) {
        statusBar()->showMessage(
            tr("A project change is still in progress; finish it before switching projects."),
            5000);
        if (continuation)
            continuation(false);
        return;
    }
    m_projectSwitchInProgress = true;
    if (m_registerSongConfirmation) {
        QMessageBox *box = m_registerSongConfirmation.data();
        m_registerSongConfirmation = nullptr;
        box->close();
    }
    if (m_deleteSongConfirmation) {
        QMessageBox *box = m_deleteSongConfirmation.data();
        m_deleteSongConfirmation = nullptr;
        box->close();
    }
    QElapsedTimer timer;
    timer.start();

    // Every prompt before the project (or any tab) changes: a Cancel
    // aborts the switch, though Saves answered before it have already
    // queued or written — standard save-all behavior, not a transaction.
    promptToSaveAllSessions([this, dir, interactive, continuation = std::move(continuation),
                             timer](bool saved) mutable {
        if (!saved) {
            m_projectSwitchInProgress = false;
            if (continuation)
                continuation(false);
            return;
        }
        if (m_closeInProgress || m_closeAccepted || projectMutationInProgress()) {
            m_projectSwitchInProgress = false;
            if (projectMutationInProgress())
                statusBar()->showMessage(
                    tr("A project change is still in progress; finish it before switching "
                       "projects."),
                    5000);
            if (continuation)
                continuation(false);
            return;
        }
        cancelDisposableProjectRequests();
        for (const auto &session : m_sessions)
            saveViewState(*session); // against the old project root
        cleanupVgPreview();

        m_projectIo->openProject(dir, [this, dir, interactive,
                                       continuation = std::move(continuation),
                                       timer](ProjectOpenResult result) mutable {
            m_projectSwitchInProgress = false;
            if (!result.succeeded()) {
                if (interactive)
                    QMessageBox::warning(this, tr("Open Project"), result.error);
                else
                    statusBar()->showMessage(
                        tr("Couldn't reopen last project %1: %2").arg(dir, result.error));
                if (continuation)
                    continuation(false);
                return;
            }
            m_project.replaceWith(result.snapshot);
            QSettings settings;
            settings.setValue(QStringLiteral("lastProjectDir"), dir);
            // The new project starts with no tabs; loadSong re-records them.
            settings.remove(kLastSongLabelKey);
            settings.remove(kLastOpenSongsKey);

            // Sessions were prompted above; closing them now needs no questions.
            teardownSessions();
            invalidateVgCatalog();
            m_pendingSynths.clear(); // unsaved synth definitions die with the project

            m_newSongAction->setEnabled(true);
            m_importAction->setEnabled(true);
            m_importSampleAction->setEnabled(true);
            updateWindowTitle();
            populateSongList();
            m_songList->setCurrentSong(-1);

            int playable = 0;
            for (const SongInfo &song : m_project.songs()) {
                if (song.isPlayable())
                    playable++;
            }
            statusBar()->showMessage(tr("Opened %1 — %2 songs, %3 with MIDI sources (%4 ms)")
                                         .arg(QDir(dir).dirName())
                                         .arg(m_project.songs().size())
                                         .arg(playable)
                                         .arg(timer.elapsed()));
            updateTransportActions();
            if (continuation)
                continuation(true);
        });
    });
}

void MainWindow::populateSongList()
{
    m_songList->setSongs(m_project.songs());
}

void MainWindow::songActivated(int songId)
{
    if (songId < 0 || songId >= m_project.songs().size())
        return;
    loadSong(m_project.songs().at(songId));
}

void MainWindow::songOpenInNewTab(int songId)
{
    if (songId < 0 || songId >= m_project.songs().size())
        return;
    loadSong(m_project.songs().at(songId), /*newTab=*/true);
}

void MainWindow::queueVoicegroupLoad(SongSession &session, const SongCfg &cfg, int keepSlot,
                                     std::function<void(bool)> completion)
{
    if (session.pendingVgRequest != 0) {
        m_projectIo->cancel(session.pendingVgRequest);
        session.pendingVgRequest = 0;
    }
    if (session.pendingVgProbeRequest != 0) {
        m_projectIo->cancel(session.pendingVgProbeRequest);
        session.pendingVgProbeRequest = 0;
    }
    // A fresh on-disk load supersedes any preview of the old source. Without
    // this cancellation, a late preview result can replace the newly loaded
    // voicegroup after a cfg switch or a sibling-save refresh.
    if (session.pendingPreviewRequest != 0) {
        m_projectIo->cancel(session.pendingPreviewRequest);
        session.pendingPreviewRequest = 0;
    }
    SongSession *const sessionPtr = &session;
    const auto isLive = [this, sessionPtr] {
        return std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                           [sessionPtr](const std::unique_ptr<SongSession> &candidate) {
                               return candidate.get() == sessionPtr;
                           });
    };
    const auto restoreBrowser = [this, sessionPtr] {
        if (sessionPtr == m_active) {
            m_vgBrowser->setLoading(false);
            updateVoicegroupBrowser();
        }
    };
    const bool sourceWasClean = !session.vgSource || !session.vgSource->dirty();
    const QString root = m_project.root();
    const QString label = session.doc.label();
    const QString tried = DecompProject::voicegroupCandidates(cfg).join(QStringLiteral(", "));
    if (&session == m_active)
        m_vgBrowser->setLoading(true);
    session.pendingVgRequest = m_projectIo->loadVoicegroup(
        root, cfg,
        [this, sessionPtr, cfg, keepSlot, root, label, tried, sourceWasClean, restoreBrowser,
         completion = std::move(completion), isLive](VoicegroupLoadResult result) mutable {
            if (!isLive()) {
                if (result.voicegroup)
                    voicegroup_free(result.voicegroup);
                return;
            }
            if (result.requestId != sessionPtr->pendingVgRequest) {
                if (result.voicegroup)
                    voicegroup_free(result.voicegroup);
                return;
            }
            sessionPtr->pendingVgRequest = 0;
            if (m_project.root() != root) {
                if (result.voicegroup)
                    voicegroup_free(result.voicegroup);
                restoreBrowser();
                if (completion)
                    completion(false);
                return;
            }
            if (!result.succeeded() || !result.source) {
                if (result.voicegroup)
                    voicegroup_free(result.voicegroup);
                statusBar()->showMessage(
                    tr("Could not load the voicegroup for %1 (tried: %2).").arg(label, tried),
                    8000);
                restoreBrowser();
                if (completion)
                    completion(false);
                return;
            }
            if (sessionPtr->midiBound && sessionPtr->doc.cfg().voicegroupArg != cfg.voicegroupArg) {
                voicegroup_free(result.voicegroup);
                restoreBrowser();
                if (completion)
                    completion(false);
                return;
            }
            if (sourceWasClean && sessionPtr->vgSource && sessionPtr->vgSource->dirty()) {
                voicegroup_free(result.voicegroup);
                restoreBrowser();
                if (completion)
                    completion(false);
                return;
            }
            sessionPtr->vgSource = std::move(result.source);
            sessionPtr->vgFileTime = result.fileTime;
            sessionPtr->vgBound = true;
            sessionPtr->appliedVoicegroupArg = cfg.voicegroupArg;
            swapVoicegroup(*sessionPtr, result.voicegroup, keepSlot);
            result.voicegroup = nullptr;
            restoreBrowser();
            if (completion)
                completion(true);
        });
}

void MainWindow::queueVoicegroupProbe(SongSession &session)
{
    if (session.pendingVgProbeRequest != 0 || session.pendingVgRequest != 0)
        return;
    SongSession *const sessionPtr = &session;
    const auto isLive = [this, sessionPtr] {
        return std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                           [sessionPtr](const std::unique_ptr<SongSession> &candidate) {
                               return candidate.get() == sessionPtr;
                           });
    };
    const QString root = m_project.root();
    const SongCfg cfg = session.doc.cfg();
    session.pendingVgProbeRequest = m_projectIo->probeVoicegroup(
        root, cfg, [this, sessionPtr, cfg, root, isLive](VoicegroupProbeResult result) mutable {
            if (!isLive())
                return;
            if (result.requestId != sessionPtr->pendingVgProbeRequest)
                return;
            sessionPtr->pendingVgProbeRequest = 0;
            // A probe is only a hint for a clean session. If the project,
            // cfg, or source changed while it was queued, do not let its
            // stale answer overwrite a newer GUI edit.
            if (m_project.root() != root || !result.succeeded() || !sessionPtr->vgSource ||
                sessionPtr->vgSource->dirty() ||
                (sessionPtr->midiBound && sessionPtr->doc.cfg().voicegroupArg != cfg.voicegroupArg))
                return;
            if (result.filePath == sessionPtr->vgSource->filePath() &&
                result.fileTime == sessionPtr->vgFileTime)
                return;
            const int keepSlot = sessionPtr == m_active ? m_vgBrowser->currentSlot() : 0;
            queueVoicegroupLoad(*sessionPtr, cfg, keepSlot);
        });
}

void MainWindow::loadSong(const SongInfo &song, bool newTab)
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted)
        return;
    if (!m_audioOk)
        return;
    // Already open somewhere? Focus that tab: two documents over one .mid
    // would fight over the file on save. Except the song already in the
    // CURRENT tab — re-activating it falls through to an in-place reload
    // from disk (the pre-tabs behavior, and the only reload path for an
    // externally changed .mid).
    if (SongSession *open = sessionForLabel(song.label)) {
        if (newTab || open != m_active) {
            m_tabs->setCurrentWidget(open->view);
            return;
        }
    }

    const bool created = newTab || !m_active;
    auto sessionState = std::make_shared<SongSession *>(created ? nullptr : m_active);
    const auto beginLoad = [this, song, created, sessionState]() {
        cleanupVgPreview();
        SongSession *session = *sessionState;
        if (!session) {
            session = createSession();
            *sessionState = session;
        }
        session->songId = song.id;
        session->doc.setTrackBudget(m_project.trackBudgetFor(song));
        session->view->setDocument(nullptr);
        session->view->setSong(nullptr, nullptr);
        if (session == m_active) {
            m_vgBrowser->setVoicegroup(nullptr);
            if (m_audioOk)
                m_audio.unloadSong();
        }
        if (session->pendingMidiRequest != 0) {
            m_projectIo->cancel(session->pendingMidiRequest);
            session->pendingMidiRequest = 0;
        }
        if (session->pendingVgRequest != 0) {
            m_projectIo->cancel(session->pendingVgRequest);
            session->pendingVgRequest = 0;
        }
        if (session->pendingVgProbeRequest != 0) {
            m_projectIo->cancel(session->pendingVgProbeRequest);
            session->pendingVgProbeRequest = 0;
        }
        if (session->pendingSidecarRequest != 0) {
            m_projectIo->cancel(session->pendingSidecarRequest);
            session->pendingSidecarRequest = 0;
        }
        if (session->voicegroup)
            voicegroup_free(session->voicegroup);
        session->voicegroup = nullptr;
        session->vgSource.reset();
        session->timeline.reset();
        session->midiBound = false;
        session->vgBound = false;
        session->sidecarBound = false;
        session->vgFileTime = QDateTime();
        session->appliedVoicegroupArg = song.cfg.voicegroupArg;
        session->appliedVolume = song.cfg.masterVolume;
        session->appliedReverb = song.cfg.reverb;
        session->view->setEnabled(false);

        if (created) {
            const int index = m_tabs->addTab(session->view, song.label);
            m_tabs->setTabText(index, song.label);
            m_tabs->setTabToolTip(index, song.midPath);
            if (!m_restoringSession) {
                // The first tab activates inside addTab; later ones here.
                m_tabs->setCurrentIndex(index);
                if (m_active != session)
                    activateSession(session);
            }
        } else {
            const int index = m_tabs->indexOf(session->view);
            m_tabs->setTabText(index, song.label);
            m_tabs->setTabToolTip(index, song.midPath);
            activateSession(session, /*force=*/true);
        }
        if (session == m_active)
            m_vgBrowser->setLoading(true);

        const auto isLive = [this, session] {
            return std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                               [session](const std::unique_ptr<SongSession> &candidate) {
                                   return candidate.get() == session;
                               });
        };
        const auto fail = [this, session](const QString &error) {
            const bool live = std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                                          [session](const std::unique_ptr<SongSession> &candidate) {
                                              return candidate.get() == session;
                                          });
            if (!live)
                return;
            if (session->pendingMidiRequest != 0) {
                m_projectIo->cancel(session->pendingMidiRequest);
                session->pendingMidiRequest = 0;
            }
            if (session->pendingVgRequest != 0) {
                m_projectIo->cancel(session->pendingVgRequest);
                session->pendingVgRequest = 0;
            }
            if (session->pendingSidecarRequest != 0) {
                m_projectIo->cancel(session->pendingSidecarRequest);
                session->pendingSidecarRequest = 0;
            }
            destroySession(session);
            QMessageBox::warning(this, tr("Load Song"), error);
        };
        const auto finish = [this, session, isLive] {
            if (!isLive())
                return;
            if (!session->isInteractive()) {
                if (session == m_active) {
                    if (session->voicegroup)
                        updateVoicegroupBrowser();
                    else
                        m_vgBrowser->setLoading(true);
                    updateTransportActions();
                    updateDrawerActions();
                    updateWindowTitle();
                }
                return;
            }
            session->view->setEnabled(true);
            if (session == m_active)
                activateSession(session, /*force=*/true);
            else
                updateTabTitle(*session);
        };
        const QString root = m_project.root();
        const QString tried =
            DecompProject::voicegroupCandidates(song.cfg).join(QStringLiteral(", "));
        session->pendingMidiRequest = m_projectIo->loadSongFile(
            song, [this, session, song, root, isLive, fail, finish](SongFileResult result) mutable {
                if (!isLive())
                    return;
                if (result.requestId != session->pendingMidiRequest)
                    return;
                session->pendingMidiRequest = 0;
                if (!result.succeeded()) {
                    fail(result.error);
                    return;
                }
                QString error;
                if (!session->doc.adoptSmf(std::move(result.smf), song, &error)) {
                    fail(error);
                    return;
                }
                session->timeline = session->doc.buildTimeline(m_audio.sampleRate());
                session->view->setSong(session->timeline.get(), session->voicegroup);
                session->view->setDocument(&session->doc);
                session->appliedVoicegroupArg = song.cfg.voicegroupArg;
                session->appliedVolume = song.cfg.masterVolume;
                session->appliedReverb = song.cfg.reverb;
                session->midiBound = true;
                session->sidecarBound = false;
                session->pendingSidecarRequest = m_projectIo->readSidecar(
                    SidecarLoadRequest{root, song.label},
                    [this, session, isLive, finish](SidecarLoadResult sidecar) mutable {
                        if (!isLive())
                            return;
                        if (sidecar.requestId != session->pendingSidecarRequest)
                            return;
                        session->pendingSidecarRequest = 0;
                        if (sidecar.loaded) {
                            session->view->applyViewState(sidecar.snapshot.view);
                            sidecar.snapshot.editor.setDrawerState(m_editorDrawerState);
                            session->view->applyEditorViewState(sidecar.snapshot.editor);
                        }
                        session->view->applyEditorDrawerState(m_editorDrawerState);
                        session->sidecarBound = true;
                        finish();
                    });
                updateTabTitle(*session);
                finish();
            });
        session->pendingVgRequest = m_projectIo->loadVoicegroup(
            root, song.cfg,
            [this, session, song, tried, isLive, fail,
             finish](VoicegroupLoadResult result) mutable {
                if (!isLive()) {
                    if (result.voicegroup)
                        voicegroup_free(result.voicegroup);
                    return;
                }
                if (result.requestId != session->pendingVgRequest) {
                    if (result.voicegroup)
                        voicegroup_free(result.voicegroup);
                    return;
                }
                session->pendingVgRequest = 0;
                if (!result.succeeded()) {
                    if (result.voicegroup)
                        voicegroup_free(result.voicegroup);
                    fail(tr("Could not load the voicegroup for %1 (tried: %2).")
                             .arg(song.label, tried));
                    return;
                }
                session->view->setVoicegroup(nullptr);
                session->voicegroup = result.voicegroup;
                result.voicegroup = nullptr;
                session->vgSource = std::move(result.source);
                session->vgFileTime = result.fileTime;
                session->vgBound = true;
                session->view->setVoicegroup(session->voicegroup);
                if (session == m_active)
                    updateVoicegroupBrowser();
                finish();
            });
        statusBar()->showMessage(tr("Loading %1...").arg(song.label));
        updateWindowTitle();
        updateTransportActions();
    };

    SongSession *session = *sessionState;
    if (!session) {
        beginLoad();
        return;
    }
    maybeSaveSession(*session, [this, sessionState, beginLoad](bool succeeded) {
        if (!succeeded)
            return;
        SongSession *session = *sessionState;
        const bool live =
            session && std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                                   [session](const std::unique_ptr<SongSession> &candidate) {
                                       return candidate.get() == session;
                                   });
        if (!live)
            return;
        saveViewState(*session);
        beginLoad();
    });
}

void MainWindow::onDocumentChanged(SongSession &session)
{
    if (!m_audioOk || !session.isInteractive())
        return;
    const bool active = &session == m_active;

    const SongCfg &cfg = session.doc.cfg();
    if (cfg.voicegroupArg != session.appliedVoicegroupArg) {
        // The -G switch (or its undo/redo) reloads through the project
        // worker. Existing undo commands are replayed only after its detached
        // source lands on the GUI thread.
        cleanupVgPreview();
        if (session.pendingPreviewRequest != 0) {
            m_projectIo->cancel(session.pendingPreviewRequest);
            session.pendingPreviewRequest = 0;
        }
        if (session.pendingVgProbeRequest != 0) {
            m_projectIo->cancel(session.pendingVgProbeRequest);
            session.pendingVgProbeRequest = 0;
        }
        SongSession *const sessionPtr = &session;
        queueVoicegroupLoad(session, cfg, active ? m_vgBrowser->currentSlot() : 0,
                            [this, sessionPtr, active](bool succeeded) {
                                if (!succeeded)
                                    return;
                                reapplyVoicegroupEditsToReopenedSource(*sessionPtr);
                                if (sessionPtr->vgSource && sessionPtr->vgSource->dirty())
                                    reloadVoicegroupPreview(
                                        *sessionPtr, active ? m_vgBrowser->currentSlot() : 0);
                                if (active)
                                    updateVoicegroupBrowser();
                            });
    }
    if (cfg.masterVolume != session.appliedVolume || cfg.reverb != session.appliedReverb) {
        if (active && m_audio.songLoaded())
            m_audio.updateSettings(songSettingsFor(session));
        session.appliedVolume = cfg.masterVolume;
        session.appliedReverb = cfg.reverb;
    }

    auto timeline = std::shared_ptr<MidiTimeline>(session.doc.buildTimeline(m_audio.sampleRate()));
    if (active && m_audio.songLoaded())
        m_audio.updateTimeline(timeline);
    session.view->updateSong(timeline.get());
    session.timeline = std::move(timeline);
    updateTabTitle(session);
    if (active) {
        // The timeline was rebuilt, track names may have changed, and the
        // voicegroup may have been swapped above.
        updatePolyPanelContext(&session);
        updateWindowTitle();
        // Keep the dock's voicegroup selector on the cfg even when no swap
        // ran (the arg's voicegroup wasn't found, or its change was undone).
        m_vgBrowser->setCurrentVoicegroupArg(cfg.voicegroupArg.isEmpty() ? QStringLiteral("_dummy")
                                                                         : cfg.voicegroupArg);
        // Program changes may have been added/removed; refresh the dock's
        // used-voice marks (no-op when the set is unchanged).
        m_vgBrowser->setUsedVoices(session.view->usedVoices());
        // Cfg may have changed from any source (Song Settings, undo/redo);
        // the toolbar spinbox mirrors it.
        syncMasterVolumeControl();
    }
}

void MainWindow::saveSong()
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted)
        return;
    if (m_active && m_active->isInteractive())
        saveSession(*m_active);
}

void MainWindow::saveSession(SongSession &session, SessionContinuation continuation)
{
    const auto complete = [&continuation](bool succeeded) {
        if (continuation)
            continuation(succeeded);
    };
    if (!session.isInteractive() || session.doc.midPath().isEmpty()) {
        complete(false);
        return;
    }
    if (session.pendingSaveRequest != 0 || session.pendingVgSaveRequest != 0) {
        complete(false);
        return;
    }
    if (!session.isDirty()) {
        complete(true);
        return;
    }

    const bool vgWasDirty = session.vgSource && session.vgSource->dirty();
    const auto sessionPtr = &session;
    const auto completionPtr = std::make_shared<SessionContinuation>(std::move(continuation));
    auto startMidiSave = std::make_shared<std::function<void()>>();
    *startMidiSave = [this, sessionPtr, completionPtr, vgWasDirty]() mutable {
        const QString savedVgPath =
            vgWasDirty && sessionPtr->vgSource ? sessionPtr->vgSource->filePath() : QString();
        auto completion = std::move(*completionPtr);
        SongSaveSnapshot snapshot = sessionPtr->doc.captureSaveSnapshot();
        SongSaveSnapshot landed;
        landed.midPath = snapshot.midPath;
        landed.label = snapshot.label;
        landed.cfg = snapshot.cfg;
        landed.flagsNeeded = snapshot.flagsNeeded;
        landed.revision = snapshot.revision;
        landed.saveStateToken = snapshot.saveStateToken;
        const auto isLive = [this, sessionPtr] {
            return std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                               [sessionPtr](const std::unique_ptr<SongSession> &candidate) {
                                   return candidate.get() == sessionPtr;
                               });
        };
        if (sessionPtr == m_active)
            m_saveAction->setEnabled(false);
        sessionPtr->pendingSaveRequest = m_projectIo->saveSong(
            std::move(snapshot),
            [this, sessionPtr, completion = std::move(completion), isLive,
             landed = std::move(landed), vgWasDirty, savedVgPath](SaveSongResult result) mutable {
                if (!isLive()) {
                    if (completion)
                        completion(false);
                    return;
                }
                if (result.requestId != sessionPtr->pendingSaveRequest)
                    return;
                sessionPtr->pendingSaveRequest = 0;
                if (sessionPtr == m_active)
                    m_saveAction->setEnabled(true);
                if (!result.succeeded()) {
                    QMessageBox::warning(this, tr("Save Song"), result.error);
                    if (completion)
                        completion(false);
                    return;
                }
                sessionPtr->doc.didSave(landed, result.flagsWritten);
                if (sessionPtr->songId >= 0)
                    m_project.setSongCfg(sessionPtr->songId, landed.cfg);
                statusBar()->showMessage(
                    vgWasDirty ? tr("Saved %1 and %2").arg(landed.midPath, savedVgPath)
                               : tr("Saved %1").arg(landed.midPath),
                    5000);
                updateTabTitle(*sessionPtr);
                if (sessionPtr == m_active)
                    updateWindowTitle();
                if (completion)
                    completion(!sessionPtr->isDirty());
            });
    };

    if (!vgWasDirty) {
        (*startMidiSave)();
        return;
    }

    QList<QPair<QString, VgSynthDesc>> newDefs;
    for (int slot = 0; slot < VOICEGROUP_SIZE; slot++) {
        const VgVoice *voice = session.vgSource->voiceAt(slot);
        if (!voice)
            continue;
        const auto it = m_pendingSynths.constFind(voice->symbol);
        if (it == m_pendingSynths.constEnd())
            continue;
        const QPair<QString, VgSynthDesc> definition{it.key(), it.value()};
        if (!newDefs.contains(definition))
            newDefs.append(definition);
    }
    const QByteArray sourceBytes = session.vgSource->sourceBytes();
    const auto sourcePath = session.vgSource->filePath();
    const SongCfg cfg = session.doc.cfg();
    const int keepSlot = &session == m_active ? m_vgBrowser->currentSlot() : 0;
    cleanupVgPreview();
    VoicegroupSaveRequest request;
    request.projectRoot = m_project.root();
    request.filePath = sourcePath;
    request.sourceBytes = sourceBytes;
    request.synthDefinitions = newDefs;
    session.pendingVgSaveRequest = m_projectIo->saveVoicegroup(
        std::move(request),
        [this, sessionPtr, completionPtr, sourceBytes, sourcePath, cfg, keepSlot, newDefs,
         startMidiSave](VoicegroupSaveResult result) mutable {
            if (!std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                             [sessionPtr](const std::unique_ptr<SongSession> &candidate) {
                                 return candidate.get() == sessionPtr;
                             })) {
                if (*completionPtr)
                    (*completionPtr)(false);
                *completionPtr = {};
                return;
            }
            if (result.requestId != sessionPtr->pendingVgSaveRequest)
                return;
            sessionPtr->pendingVgSaveRequest = 0;
            if (!result.succeeded()) {
                if (result.synthOk)
                    invalidateVgCatalog();
                QMessageBox::warning(this, tr("Save Voicegroup"), result.error);
                if (*completionPtr)
                    (*completionPtr)(false);
                *completionPtr = {};
                return;
            }
            const bool current = sessionPtr->vgSource && sessionPtr->vgSource->didSave(sourceBytes);
            if (current) {
                for (const auto &definition : newDefs)
                    m_pendingSynths.remove(definition.first);
            }
            invalidateVgCatalog();
            cleanupVgPreview();
            sessionPtr->vgFileTime = result.fileTime;
            refreshSessionsAfterVgSave(sourcePath, sessionPtr);
            if (!current) {
                (*startMidiSave)();
                return;
            }
            queueVoicegroupLoad(*sessionPtr, cfg, keepSlot,
                                [startMidiSave, completionPtr](bool succeeded) {
                                    if (succeeded) {
                                        if (*startMidiSave)
                                            (*startMidiSave)();
                                    } else if (*completionPtr) {
                                        auto completion = std::move(*completionPtr);
                                        *completionPtr = {};
                                        completion(false);
                                    }
                                });
        });
}

void MainWindow::exportWav()
{
    SongSession *session = m_active;
    if (!session || !session->isInteractive() || !m_audio.songLoaded())
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
            .value(QStringLiteral("lastWavExportDir"), QFileInfo(session->doc.midPath()).path())
            .toString();
    const QString path = QFileDialog::getSaveFileName(
        this, tr("Export WAV"), startDir + QLatin1Char('/') + session->doc.label() + ".wav",
        tr("WAV files (*.wav)"));
    if (path.isEmpty())
        return;
    appSettings.setValue(QStringLiteral("lastWavExportDir"), QFileInfo(path).path());

    stopPlayback();

    QProgressDialog progress(tr("Rendering %1...").arg(session->doc.label()), tr("Cancel"), 0, 1000,
                             this);
    progress.setWindowModality(Qt::WindowModal);
    progress.setMinimumDuration(0);

    // The render reads the same voicegroup the audio engine borrows (the
    // engine only reads it too), against a fresh timeline at the export
    // rate — so unsaved document and voice edits export as heard.
    auto timeline = session->doc.buildTimeline(double(opts.sampleRate));
    QString error;
    const bool ok = ::exportWav(
        path, *timeline, session->voicegroup, songSettingsFor(*session), opts,
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
    if (m_active && m_active->isInteractive())
        song = SongTarget{m_active->doc.cfg(), m_active->doc.label()};
    const auto &catalog = vgCatalog();
    if (!catalog.valid) {
        statusBar()->showMessage(tr("Loading voicegroup catalog…"), 5000);
        return;
    }
    const QStringList vgArgs = catalog.groupArgs;
    SettingsDialog dialog(m_engineSettings, song, vgArgs, initialTab, this);
    const auto apply = [this, &dialog] {
        const EngineSettings newEngine = dialog.engineSettings();
        if (newEngine.pcmMixer != m_engineSettings.pcmMixer ||
            newEngine.maxPcmChannels != m_engineSettings.maxPcmChannels ||
            newEngine.pcmMixRate != m_engineSettings.pcmMixRate ||
            newEngine.analogFilter != m_engineSettings.analogFilter) {
            m_engineSettings = newEngine;
            m_engineSettings.save();
            if (m_audioOk && m_active && m_audio.songLoaded())
                m_audio.updateSettings(songSettingsFor(*m_active));
        }
        if (m_active && m_active->isInteractive()) {
            const auto songCfg = dialog.songCfg();
            if (songCfg)
                m_active->doc.setCfg(*songCfg);
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

SongSettings MainWindow::songSettingsFor(const SongSession &session) const
{
    const SongCfg &cfg = session.doc.cfg();
    SongSettings settings;
    settings.songVolume = uint8_t(cfg.masterVolume);
    settings.reverb = uint8_t(cfg.reverb >= 0 ? cfg.reverb : SongCfg::kDefaultReverb);
    settings.pcmMixer = m_engineSettings.pcmMixer;
    settings.maxPcmChannels = uint8_t(m_engineSettings.maxPcmChannels);
    settings.pcmMixRate = m_engineSettings.pcmMixRate;
    settings.analogFilter = m_engineSettings.analogFilter;
    return settings;
}

void MainWindow::newSong()
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted || !m_project.isOpen() ||
        projectMutationInProgress())
        return;
    const QString projectRoot = m_project.root();
    const auto &catalog = vgCatalog();
    if (!catalog.valid) {
        statusBar()->showMessage(tr("Loading voicegroup catalog…"), 5000);
        return;
    }
    NewSongWizard::ProjectData data{m_project.songs(), m_project.players(), catalog.groupArgs,
                                    catalog.perFileVoicegroups};
    NewSongWizard wizard(std::move(data), this);
    if (wizard.exec() != QDialog::Accepted)
        return;
    finishCreateSong(wizard.songFile(), wizard.label(), wizard.constant(), wizard.player(),
                     wizard.cfg(), wizard.newVoicegroupName(), projectRoot);
}

void MainWindow::importMidi()
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted || !m_project.isOpen() ||
        projectMutationInProgress())
        return;
    const QString projectRoot = m_project.root();
    QSettings settings;
    const QString startDir =
        settings.value(QStringLiteral("lastImportDir"), QDir::homePath()).toString();
    const QString path = QFileDialog::getOpenFileName(this, tr("Import MIDI"), startDir,
                                                      tr("MIDI files (*.mid *.midi)"));
    if (path.isEmpty())
        return;
    settings.setValue(QStringLiteral("lastImportDir"), QFileInfo(path).path());

    SmfFile smf;
    QString error;
    if (!SmfFile::readFile(path, &smf, &error)) {
        QMessageBox::warning(this, tr("Import MIDI"), error);
        return;
    }
    const auto &catalog = vgCatalog();
    if (!catalog.valid) {
        statusBar()->showMessage(tr("Loading voicegroup catalog…"), 5000);
        return;
    }
    NewSongWizard::ProjectData data{m_project.songs(), m_project.players(), catalog.groupArgs,
                                    catalog.perFileVoicegroups};
    NewSongWizard wizard(std::move(data), std::move(smf), path, this);
    if (wizard.exec() != QDialog::Accepted)
        return;
    finishCreateSong(wizard.songFile(), wizard.label(), wizard.constant(), wizard.player(),
                     wizard.cfg(), wizard.newVoicegroupName(), projectRoot);
}

void MainWindow::importSample()
{
    importSampleForSlot(-1);
}

void MainWindow::importSampleForSlot(int slot)
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted || !m_project.isOpen() ||
        m_pendingSampleProbeRequest != 0)
        return;
    const QString root = m_project.root();
    m_pendingSampleProbeRequest =
        m_projectIo->probeSamples(root, [this, root, slot](SampleProbeResult result) mutable {
            if (result.requestId != m_pendingSampleProbeRequest)
                return;
            m_pendingSampleProbeRequest = 0;
            if (m_project.root() != root)
                return;
            if (!result.succeeded()) {
                QMessageBox::warning(this, tr("Import Sample"), result.error);
                return;
            }
            continueImportSampleForSlot(slot, root, result.probe);
        });
}

void MainWindow::continueImportSampleForSlot(int slot, QString projectRoot,
                                             const SampleFormatProbe &probe)
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted || !m_project.isOpen() ||
        m_project.root() != projectRoot)
        return;
    const QString root = std::move(projectRoot);
    Q_UNUSED(probe);
    QSettings settings;
    const QString startDir =
        settings.value(QStringLiteral("lastSampleDir"), QDir::homePath()).toString();
    const QString path = QFileDialog::getOpenFileName(
        this, tr("Import Sample"), startDir,
        tr("Audio files (*.wav *.aif *.aiff *.mp3 *.flac *.ogg *.sf2);;"
           "All files (*)"));
    if (path.isEmpty())
        return;
    settings.setValue(QStringLiteral("lastSampleDir"), QFileInfo(path).path());

    QFile sourceFile(path);
    if (!sourceFile.open(QIODevice::ReadOnly)) {
        QMessageBox::warning(this, tr("Import Sample"), tr("Cannot read %1.").arg(path));
        return;
    }
    const QByteArray sourceBytes = sourceFile.readAll();
    sourceFile.close();

    ImportedSample sample;
    QString error;
    // Decode choices beyond the source bytes, recorded in the provenance
    // sidecar so "Edit sample…" can re-decode identically.
    bool leftOnly = false;
    int sf2Zone = -1;
    if (sf2Magic(sourceBytes)) {
        // SoundFonts hold many samples: pick a zone first (FORMATS.md §5);
        // the chosen zone then rides the ordinary editor pipeline.
        Sf2File font;
        if (!readSf2Bytes(sourceBytes, path, &font, &error)) {
            QMessageBox::warning(this, tr("Import Sample"),
                                 tr("%1: %2").arg(QFileInfo(path).fileName(), error));
            return;
        }
        Sf2ZonePicker picker(font, this);
        if (picker.exec() != QDialog::Accepted)
            return;
        if (!extractSf2Zone(font, picker.selectedZone(), &sample, &error)) {
            QMessageBox::warning(this, tr("Import Sample"),
                                 tr("%1: %2").arg(QFileInfo(path).fileName(), error));
            return;
        }
        sf2Zone = picker.selectedZone();
    } else {
        if (!importAudioBytes(sourceBytes, path, &sample, &error)) {
            QMessageBox::warning(this, tr("Import Sample"),
                                 tr("%1: %2").arg(QFileInfo(path).fileName(), error));
            return;
        }
        if (sample.phaseCancelStereo &&
            QMessageBox::question(this, tr("Import Sample"),
                                  tr("The left and right channels of %1 are "
                                     "phase-cancelling — the mono mix may sound hollow.\n\n"
                                     "Import the left channel only instead?")
                                      .arg(QFileInfo(path).fileName())) == QMessageBox::Yes) {
            if (!importAudioBytes(sourceBytes, path, &sample, &error, true)) {
                QMessageBox::warning(this, tr("Import Sample"),
                                     tr("%1: %2").arg(QFileInfo(path).fileName(), error));
                return;
            }
            leftOnly = true;
        }
    }

    const auto &catalog = vgCatalog();
    if (!catalog.valid) {
        statusBar()->showMessage(tr("Loading voicegroup catalog…"), 5000);
        return;
    }
    const QStringList symbols = catalog.directSound;
    AuditionSlots::Adsr destAdsr;
    bool hasDestAdsr = false;
    if (slot >= 0 && m_active && m_active->vgSource) {
        const VgVoice *dest = m_active->vgSource->voiceAt(slot);
        if (dest && !vgMacroIsCgb(dest->macro)) {
            destAdsr = {uint8_t(dest->attack), uint8_t(dest->decay), uint8_t(dest->sustain),
                        uint8_t(dest->release)};
            hasDestAdsr = true;
        }
    }
    SampleEditorDialog dialog(
        std::move(sample),
        [symbols](const QString &name, QString *validationError) {
            const auto valid = QRegularExpression(QStringLiteral("^[a-z0-9_]+$")).match(name);
            if (name.isEmpty() || !valid.hasMatch()) {
                if (validationError)
                    *validationError = QStringLiteral("use lowercase letters, digits, and '_'.");
                return false;
            }
            if (symbols.contains(QStringLiteral("DirectSoundWaveData_") + name)) {
                if (validationError)
                    *validationError = QStringLiteral("a sample with that name already exists.");
                return false;
            }
            return true;
        },
        m_audioOk ? &m_audio : nullptr, hasDestAdsr ? &destAdsr : nullptr, this);
    if (dialog.exec() != QDialog::Accepted)
        return;
    const QString committedName = dialog.sampleName();
    const QByteArray committedWav = dialog.wavBytes();
    SampleSidecar sidecar;
    sidecar.sourcePath = QFileInfo(path).absoluteFilePath();
    sidecar.sourceSha256 = SampleRegistrar::sourceHashHex(sourceBytes);
    sidecar.leftOnly = leftOnly;
    sidecar.sf2Zone = sf2Zone;
    sidecar.params = dialog.document()->params();
    const VgAdsrDefaults defaults = catalog.typicalAdsr;
    SongSession *const requestedSession = m_active;
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted ||
        m_project.root() != root || projectMutationInProgress())
        return;
    SampleCommitRequest request;
    request.projectRoot = root;
    request.name = committedName;
    request.wavBytes = committedWav;
    request.sidecar = sidecar;
    m_pendingSampleCommitRequest = m_projectIo->commitSample(
        std::move(request),
        [this, root, slot, committedName, defaults, requestedSession](SampleCommitResult result) {
            if (result.requestId != m_pendingSampleCommitRequest)
                return;
            m_pendingSampleCommitRequest = 0;
            if (m_project.root() != root || m_projectSwitchInProgress || m_closeInProgress ||
                m_closeAccepted)
                return;
            if (!result.succeeded()) {
                QMessageBox::warning(this, tr("Import Sample"), result.error);
                return;
            }
            if (!result.sidecarSaved && !result.sidecarError.isEmpty())
                statusBar()->showMessage(
                    tr("Sample imported, but saving its edit history failed: %1")
                        .arg(result.sidecarError),
                    8000);
            invalidateVgCatalog();
            updateVoicegroupBrowser();
            if (slot >= 0 && requestedSession && requestedSession == m_active &&
                requestedSession->vgSource) {
                const VgVoice *dest = requestedSession->vgSource->voiceAt(slot);
                const bool keepDest = dest && (dest->macro == VgMacro::DirectSound ||
                                               dest->macro == VgMacro::DirectSoundNoResample ||
                                               dest->macro == VgMacro::DirectSoundAlt);
                VgVoice voice;
                if (keepDest) {
                    voice = *dest;
                } else {
                    voice.macro = VgMacro::DirectSound;
                    voice.key = 60;
                    voice.pan = 0;
                    const VgAdsr adsr =
                        vgDefaultAdsr(defaults, voice.macro,
                                      QStringLiteral("DirectSoundWaveData_") + committedName);
                    voice.attack = adsr.attack;
                    voice.decay = adsr.decay;
                    voice.sustain = adsr.sustain;
                    voice.release = adsr.release;
                }
                voice.symbol = QStringLiteral("DirectSoundWaveData_") + committedName;
                onVoiceEditRequested(slot, voice, true);
                m_vgBrowser->revealSlot(slot);
            }
            statusBar()->showMessage(
                tr("Imported %1 — DirectSoundWaveData_%1 is now available to voicegroups")
                    .arg(committedName),
                8000);
        });
}

void MainWindow::editSampleForSlot(int slot)
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted || !m_project.isOpen() ||
        !m_active || !m_active->vgSource || m_pendingSampleProjectRequest != 0)
        return;
    const QString prefix = QStringLiteral("DirectSoundWaveData_");
    const VgVoice *voice = m_active->vgSource->voiceAt(slot);
    if (!voice || !voice->symbol.startsWith(prefix)) {
        QMessageBox::warning(this, tr("Edit Sample"),
                             tr("This voice does not reference a DirectSound sample."));
        return;
    }
    const QString name = voice->symbol.mid(prefix.size());
    const QString root = m_project.root();
    m_pendingSampleProjectRequest = m_projectIo->readProjectSample(
        root, name, [this, root, name, slot](SampleProjectResult result) mutable {
            if (result.requestId != m_pendingSampleProjectRequest)
                return;
            m_pendingSampleProjectRequest = 0;
            if (m_project.root() != root)
                return;
            if (!result.succeeded()) {
                QMessageBox::warning(this, tr("Edit Sample"), result.error);
                return;
            }
            continueEditSampleForSlot(slot, name, root, std::move(result));
        });
}

void MainWindow::continueEditSampleForSlot(int slot, QString name, QString projectRoot,
                                           SampleProjectResult result)
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted || !m_project.isOpen() ||
        m_project.root() != projectRoot)
        return;
    const QString root = std::move(projectRoot);
    const VgVoice *voice =
        m_active && m_active->vgSource ? m_active->vgSource->voiceAt(slot) : nullptr;
    if (!voice)
        return;
    const QString wavPath = result.wavPath;
    const SampleSidecar loadedSidecar = result.sidecar;
    SampleSidecar sidecar = loadedSidecar;

    // Provenance: reopen from the sidecar's hi-res source while it still
    // checks out; otherwise the committed 8-bit .wav (the project is
    // canonical without the sidecar — still crop/loop-editable).
    ImportedSample sample;
    bool fromSource = false; // decoding the original hi-res source
    bool haveParams = false; // sidecar params apply to that source
    QString error;
    if (result.sidecarLoaded) {
        const auto decodeSource = [&](const QByteArray &bytes, ImportedSample *out, QString *err) {
            if (sidecar.sf2Zone >= 0) {
                Sf2File font;
                return readSf2Bytes(bytes, sidecar.sourcePath, &font, err) &&
                       extractSf2Zone(font, sidecar.sf2Zone, out, err);
            }
            return importAudioBytes(bytes, sidecar.sourcePath, out, err, sidecar.leftOnly);
        };
        QFile sourceFile(sidecar.sourcePath);
        QByteArray sourceBytes;
        if (sourceFile.open(QIODevice::ReadOnly))
            sourceBytes = sourceFile.readAll();
        if (sourceBytes.isEmpty()) {
            QMessageBox::information(this, tr("Edit Sample"),
                                     tr("The original source (%1) is no longer readable; editing "
                                        "the committed 8-bit sample instead.")
                                         .arg(sidecar.sourcePath));
        } else if (SampleRegistrar::sourceHashHex(sourceBytes) != sidecar.sourceSha256) {
            const QMessageBox::StandardButton pick =
                QMessageBox::question(this, tr("Edit Sample"),
                                      tr("%1 has changed since this sample was created, so the "
                                         "saved edit settings no longer apply to it.\n\n"
                                         "Re-import the changed file with fresh settings? "
                                         "(\"No\" edits the committed 8-bit sample instead.)")
                                          .arg(sidecar.sourcePath),
                                      QMessageBox::Yes | QMessageBox::No | QMessageBox::Cancel);
            if (pick == QMessageBox::Cancel)
                return;
            if (pick == QMessageBox::Yes) {
                if (!decodeSource(sourceBytes, &sample, &error)) {
                    QMessageBox::warning(this, tr("Edit Sample"),
                                         tr("%1: %2").arg(sidecar.sourcePath, error));
                    return;
                }
                sidecar.sourceSha256 = SampleRegistrar::sourceHashHex(sourceBytes);
                fromSource = true;
            }
        } else if (decodeSource(sourceBytes, &sample, &error)) {
            fromSource = true;
            haveParams = true;
        } else {
            QMessageBox::information(this, tr("Edit Sample"),
                                     tr("The original source (%1) no longer decodes (%2); editing "
                                        "the committed 8-bit sample instead.")
                                         .arg(sidecar.sourcePath, error));
        }
    }
    if (!fromSource && !importAudioBytes(result.wavBytes, wavPath, &sample, &error)) {
        QMessageBox::warning(this, tr("Edit Sample"), tr("%1: %2").arg(wavPath, error));
        return;
    }

    AuditionSlots::Adsr destAdsr;
    bool hasDestAdsr = false;
    if (!vgMacroIsCgb(voice->macro)) {
        destAdsr = {uint8_t(voice->attack), uint8_t(voice->decay), uint8_t(voice->sustain),
                    uint8_t(voice->release)};
        hasDestAdsr = true;
    }
    SampleEditorDialog dialog(
        std::move(sample),
        [name](const QString &candidate, QString *validationError) {
            if (candidate == name)
                return true;
            if (validationError)
                *validationError = tr("the sample keeps its registered name (%1).").arg(name);
            return false;
        },
        m_audioOk ? &m_audio : nullptr, hasDestAdsr ? &destAdsr : nullptr, this);
    dialog.setEditTarget(name);
    if (haveParams)
        dialog.applyParamsExternal(sidecar.params);
    if (dialog.exec() != QDialog::Accepted)
        return;

    const QByteArray committedWav = dialog.wavBytes();
    if (fromSource)
        sidecar.params = dialog.document()->params();
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted ||
        m_project.root() != root || projectMutationInProgress())
        return;
    SampleCommitRequest request;
    request.projectRoot = root;
    request.name = name;
    request.wavBytes = committedWav;
    if (fromSource)
        request.sidecar = sidecar;
    else
        request.removeSidecar = true;
    SongSession *const requestedSession = m_active;
    m_pendingSampleCommitRequest = m_projectIo->commitSample(
        std::move(request),
        [this, root, name, slot, requestedSession](SampleCommitResult result) mutable {
            if (result.requestId != m_pendingSampleCommitRequest)
                return;
            m_pendingSampleCommitRequest = 0;
            if (m_project.root() != root || m_projectSwitchInProgress || m_closeInProgress ||
                m_closeAccepted)
                return;
            if (!result.succeeded()) {
                QMessageBox::warning(this, tr("Edit Sample"), result.error);
                return;
            }
            if (!result.sidecarSaved && !result.sidecarError.isEmpty())
                statusBar()->showMessage(tr("Sample saved, but saving its edit history failed: %1")
                                             .arg(result.sidecarError),
                                         8000);
            invalidateVgCatalog();
            updateVoicegroupBrowser();
            if (requestedSession && requestedSession == m_active && requestedSession->vgSource)
                reloadVoicegroupPreview(*requestedSession, slot);
            statusBar()->showMessage(
                tr("Saved %1 — the ROM's .bin recompiles on the next build").arg(name), 8000);
        });
}

void MainWindow::finishCreateSong(SmfFile smf, const QString &label, const QString &constant,
                                  const QString &player, const SongCfg &cfg,
                                  const QString &newVoicegroup, const QString &projectRoot)
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted || !m_project.isOpen() ||
        m_project.root() != projectRoot || projectMutationInProgress())
        return;
    CreateSongRequest request;
    const QString root = m_project.root();
    request.projectRoot = root;
    request.label = label;
    request.constant = constant;
    request.player = player;
    request.cfg = cfg;
    request.newVoicegroup = newVoicegroup;
    request.smf = std::move(smf);
    m_pendingCreateSongRequest = m_projectIo->createSong(
        std::move(request), [this, root, label, newVoicegroup](CreateSongResult result) mutable {
            if (result.requestId != m_pendingCreateSongRequest)
                return;
            m_pendingCreateSongRequest = 0;
            if (m_project.root() != root || m_projectSwitchInProgress || m_closeInProgress ||
                m_closeAccepted)
                return;
            if (!result.succeeded()) {
                const QString midiDir = root + QStringLiteral("/sound/songs/midi");
                if (!result.voicegroupOk) {
                    QMessageBox::warning(this, tr("New Song"), result.error);
                } else if (!result.midiOk || !result.flagsOk) {
                    QMessageBox::warning(this, tr("New Song"), result.error);
                } else {
                    QMessageBox::warning(this, tr("New Song"),
                                         tr("Wrote %1/%2.mid, but registering it failed: %3\n"
                                            "Use File → Register Song to retry.")
                                             .arg(midiDir, label, result.error));
                }
            } else {
                QString message = tr("Created and registered %1 as %2 (song ID %3)")
                                      .arg(label)
                                      .arg(result.songId);
                if (!newVoicegroup.isEmpty())
                    message += tr(" — configure its new voicegroup in the Voicegroup dock");
                statusBar()->showMessage(message, 8000);
            }
            reloadProject([this, label](bool refreshed) {
                if (refreshed)
                    loadSongByLabel(label, /*newTab=*/true);
            });
        });
}

void MainWindow::registerLoadedSong()
{
    if (m_active && m_active->songId >= 0 && m_active->songId < m_project.songs().size())
        registerSongById(m_active->songId);
}

void MainWindow::registerSongById(int songId)
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted ||
        projectMutationInProgress() || songId < 0 || songId >= m_project.songs().size() ||
        m_registerSongConfirmation || m_pendingRegistrationPlanRequest != 0 ||
        m_pendingRegistrationRequest != 0)
        return;
    const SongInfo song = m_project.songs().at(songId);
    const QString constant =
        song.constant.isEmpty() ? SongRegistry::constantForLabel(song.label) : song.constant;
    const QString player = song.player.isEmpty() ? QStringLiteral("MUSIC_PLAYER_BGM") : song.player;
    const QString root = m_project.root();
    RegistrationPlanRequest request{root, song.label, constant, player};
    m_pendingRegistrationPlanRequest = m_projectIo->registrationPlan(
        std::move(request),
        [this, root, song, constant, player](RegistrationPlanResult result) mutable {
            if (result.requestId != m_pendingRegistrationPlanRequest)
                return;
            m_pendingRegistrationPlanRequest = 0;
            if (m_project.root() != root || m_projectSwitchInProgress || m_closeInProgress ||
                m_closeAccepted || projectMutationInProgress())
                return;
            if (!result.succeeded()) {
                QMessageBox::warning(this, tr("Register Song"), result.error);
                return;
            }
            auto *box = new QMessageBox(QMessageBox::Question, tr("Register Song"),
                                        tr("Register %1 as %2?").arg(song.label, constant),
                                        QMessageBox::NoButton, this);
            box->setAttribute(Qt::WA_DeleteOnClose);
            QStringList files;
            if (!result.status.inSongTable)
                files << QStringLiteral("song_table.inc");
            if (!result.status.inSongsH)
                files << QStringLiteral("songs.h");
            if (result.status.ldApplicable && !result.status.inLdScript)
                files << QStringLiteral("ld_script.ld");
            if (result.status.charmapApplicable && !result.status.inCharmap)
                files << QStringLiteral("charmap.txt");
            if (result.status.debugApplicable && !result.status.inDebugMenu)
                files << QStringLiteral("src/debug.c");
            if (!files.isEmpty())
                box->setInformativeText(tr("The following registration files need updates: %1")
                                            .arg(files.join(QStringLiteral(", "))));
            box->addButton(tr("Register"), QMessageBox::AcceptRole);
            box->addButton(QMessageBox::Cancel);
            m_registerSongConfirmation = box;
            connect(box, &QMessageBox::finished, this,
                    [this, box, root, song, constant, player](int) mutable {
                        if (m_registerSongConfirmation != box)
                            return;
                        auto *clicked = box->clickedButton();
                        const bool accepted =
                            clicked && box->buttonRole(clicked) == QMessageBox::AcceptRole;
                        m_registerSongConfirmation = nullptr;
                        if (!accepted || m_project.root() != root || m_projectSwitchInProgress ||
                            m_closeInProgress || m_closeAccepted || projectMutationInProgress())
                            return;
                        RegisterSongRequest request{root, song.label, constant, player};
                        m_pendingRegistrationRequest = m_projectIo->registerSong(
                            std::move(request),
                            [this, root, song, constant](RegisterSongResult result) mutable {
                                if (result.requestId != m_pendingRegistrationRequest)
                                    return;
                                m_pendingRegistrationRequest = 0;
                                if (m_project.root() != root || m_projectSwitchInProgress ||
                                    m_closeInProgress || m_closeAccepted)
                                    return;
                                if (!result.succeeded()) {
                                    QMessageBox::warning(this, tr("Register Song"), result.error);
                                    return;
                                }
                                statusBar()->showMessage(tr("Registered %1 as %2 (song ID %3)")
                                                             .arg(song.label, constant)
                                                             .arg(result.songId),
                                                         8000);
                                reloadProject([this, label = song.label](bool refreshed) {
                                    if (refreshed && m_active && m_active->doc.label() == label)
                                        activateSession(m_active, /*force=*/true);
                                });
                            });
                    });
            connect(box, &QObject::destroyed, this, [this, box] {
                if (m_registerSongConfirmation == box)
                    m_registerSongConfirmation = nullptr;
            });
            box->setWindowModality(Qt::WindowModal);
            box->show();
        });
}

void MainWindow::deleteSongById(int songId)
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted ||
        projectMutationInProgress() || songId < 0 || songId >= m_project.songs().size() ||
        m_deleteSongConfirmation || m_pendingDeletionPlanRequest != 0 ||
        m_pendingDeletionRequest != 0)
        return;
    const SongInfo song = m_project.songs().at(songId);
    const QString constant =
        song.constant.isEmpty() ? SongRegistry::constantForLabel(song.label) : song.constant;
    const QString root = m_project.root();
    DeletionPlanRequest request{root, song.label, constant, m_project.songs()};
    m_pendingDeletionPlanRequest = m_projectIo->deletionPlan(
        std::move(request), [this, root, song, constant](DeletionPlanResult result) mutable {
            if (result.requestId != m_pendingDeletionPlanRequest)
                return;
            m_pendingDeletionPlanRequest = 0;
            if (m_project.root() != root || m_projectSwitchInProgress || m_closeInProgress ||
                m_closeAccepted || projectMutationInProgress())
                return;
            if (result.plan.tableIndex == 0) {
                QMessageBox::warning(
                    this, tr("Delete Song"),
                    tr("%1 is the first song_table.inc entry (song ID 0), the engine's fallback "
                       "song — it cannot be deleted.")
                        .arg(song.label));
                return;
            }
            auto *box =
                new QMessageBox(QMessageBox::Warning, tr("Delete Song"),
                                tr("Delete %1?").arg(song.label), QMessageBox::NoButton, this);
            box->setAttribute(Qt::WA_DeleteOnClose);
            m_deleteSongConfirmation = box;
            QStringList details;
            details << tr("• Its .mid moves to .porydaw/trash/ (recoverable)");
            QStringList files;
            if (result.plan.tableIndex >= 0)
                files << QStringLiteral("song_table.inc");
            if (result.plan.inSongsH)
                files << QStringLiteral("songs.h");
            if (result.plan.inLdScript)
                files << QStringLiteral("ld_script.ld");
            if (result.plan.inCharmap)
                files << QStringLiteral("charmap.txt");
            if (result.plan.inDebugMenu)
                files << QStringLiteral("src/debug.c");
            if (song.hasCfg)
                files << QStringLiteral("midi.cfg / songs.mk");
            if (!files.isEmpty())
                details
                    << tr("• Its lines are removed from %1").arg(files.join(QStringLiteral(", ")));
            if (result.plan.tableIndex > 0 && !result.plan.lastEntry)
                details << tr("• Its song_table.inc entry becomes a reusable free slot, so no "
                              "other song's ID changes");
            box->setInformativeText(details.join(QLatin1Char('\n')));
            QCheckBox *vgBox = nullptr;
            if (!result.deletableVoicegroupName.isEmpty()) {
                vgBox = new QCheckBox(
                    tr("Also delete voicegroup %1 (used only by this song)")
                        .arg(SongRegistry::voicegroupDisplayName(song.cfg.voicegroupArg)),
                    box);
                vgBox->setChecked(true);
                box->setCheckBox(vgBox);
            }
            auto *deleteButton = box->addButton(tr("Delete"), QMessageBox::DestructiveRole);
            connect(
                box, &QDialog::finished, this,
                [this, box, root, song, result, deleteButton, vgBox](int) mutable {
                    if (m_deleteSongConfirmation != box)
                        return;
                    const bool accepted = box->clickedButton() == deleteButton;
                    m_deleteSongConfirmation = nullptr;
                    if (!accepted || m_project.root() != root || m_projectSwitchInProgress ||
                        m_closeInProgress || m_closeAccepted || projectMutationInProgress())
                        return;
                    const QString deleteName =
                        vgBox && vgBox->isChecked() ? result.deletableVoicegroupName : QString();
                    performSongDeletion(
                        song, deleteName,
                        [this, label = song.label](bool succeeded, QString error) {
                            if (!succeeded && !error.isEmpty())
                                QMessageBox::warning(this, tr("Delete Song"), error);
                            else if (succeeded)
                                statusBar()->showMessage(tr("Deleted %1 — its .mid is recoverable "
                                                            "from .porydaw/trash/")
                                                             .arg(label),
                                                         8000);
                        });
                });
            connect(box, &QObject::destroyed, this, [this, box] {
                if (m_deleteSongConfirmation == box)
                    m_deleteSongConfirmation = nullptr;
            });
            box->open();
        });
}

void MainWindow::performSongDeletion(const SongInfo &song, const QString &deleteVoicegroupName,
                                     DeletionContinuation continuation)
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted) {
        if (continuation)
            continuation(false, {});
        return;
    }
    const QString root = m_project.root();
    const QString constant =
        song.constant.isEmpty() ? SongRegistry::constantForLabel(song.label) : song.constant;
    if (m_pendingDeletionRequest != 0) {
        if (continuation)
            continuation(false, tr("A song deletion is already in progress."));
        return;
    }
    if (projectMutationInProgress()) {
        if (continuation)
            continuation(false, {});
        return;
    }
    if (SongSession *session = sessionForLabel(song.label)) {
        destroySession(session);
        persistOpenTabs();
    }
    DeleteSongRequest request{root, song.label, constant, deleteVoicegroupName};
    m_pendingDeletionRequest = m_projectIo->deleteSong(
        std::move(request),
        [this, root, continuation = std::move(continuation)](DeleteSongResult result) mutable {
            if (result.requestId != m_pendingDeletionRequest)
                return;
            m_pendingDeletionRequest = 0;
            if (m_project.root() != root || m_projectSwitchInProgress || m_closeInProgress ||
                m_closeAccepted) {
                if (continuation)
                    continuation(false, {});
                return;
            }
            const QString workerError = result.error;
            reloadProject(
                [continuation = std::move(continuation), workerError](bool refreshed) mutable {
                    if (!continuation)
                        return;
                    if (!refreshed)
                        continuation(false, workerError.isEmpty()
                                                ? QStringLiteral("Project refresh failed.")
                                                : workerError);
                    else
                        continuation(workerError.isEmpty(), workerError);
                });
        });
}

void MainWindow::reloadProject(ProjectOpenContinuation continuation)
{
    if (!m_project.isOpen() || m_projectSwitchInProgress) {
        if (continuation)
            continuation(false);
        return;
    }
    if (m_pendingProjectRefreshRequest != 0) {
        m_projectIo->cancel(m_pendingProjectRefreshRequest);
        m_pendingProjectRefreshRequest = 0;
    }
    const QString root = m_project.root();
    m_pendingProjectRefreshRequest = m_projectIo->openProject(
        root,
        [this, root, continuation = std::move(continuation)](ProjectOpenResult result) mutable {
            if (m_pendingProjectRefreshRequest == 0)
                return;
            m_pendingProjectRefreshRequest = 0;
            if (m_project.root() != root)
                return;
            if (!result.succeeded()) {
                QMessageBox::warning(this, tr("Reload Project"), result.error);
                if (continuation)
                    continuation(false);
                return;
            }
            m_project.replaceWith(result.snapshot);
            populateSongList();
            refreshSessionSongIds();
            invalidateVgCatalog();
            if (continuation)
                continuation(true);
        });
}

void MainWindow::loadSongByLabel(const QString &label, bool newTab)
{
    for (const SongInfo &song : m_project.songs()) {
        if (song.label == label && song.isPlayable()) {
            loadSong(song, newTab);
            return;
        }
    }
}

void MainWindow::updateVoicegroupBrowser()
{
    SongSession *session = m_active;
    if (!session) {
        m_vgBrowser->setVoicegroup(nullptr);
        m_vgBrowser->setLoading(false);
        updateVgDockTitle();
        return;
    }
    if (!session->voicegroup) {
        m_vgBrowser->setVoicegroup(nullptr);
        m_vgBrowser->setLoading(true);
        updateVgDockTitle();
        return;
    }
    const bool ready = session->isInteractive();
    const QString arg =
        (session->midiBound ? session->doc.cfg().voicegroupArg : session->appliedVoicegroupArg)
                .isEmpty()
            ? QStringLiteral("_dummy")
            : (session->midiBound ? session->doc.cfg().voicegroupArg
                                  : session->appliedVoicegroupArg);
    if (!ready)
        m_vgBrowser->setLoading(true);
    m_vgBrowser->setVoicegroup(session->voicegroup);
    if (session->midiBound)
        m_vgBrowser->setUsedVoices(session->view->usedVoices());
    else
        m_vgBrowser->setUsedVoices({});
    const VgCatalog &catalog = vgCatalog();
    if (!catalog.valid) {
        m_vgBrowser->setVoicegroupChoices({});
        m_vgBrowser->setCurrentVoicegroupArg(arg);
        m_vgBrowser->setSource(session->vgSource.get(), {}, {}, {}, {});
        m_vgBrowser->setLoading(true);
        updateVgDockTitle();
        return;
    }
    m_vgBrowser->setVoicegroupChoices(catalog.groupArgs);
    m_vgBrowser->setCurrentVoicegroupArg(arg);
    m_vgBrowser->setSource(
        session->vgSource.get(), catalog.directSound, catalog.progWave, catalog.keysplits,
        catalog.drumkits, catalog.typicalAdsr, catalog.synths, m_pendingSynths,
        [this](const VgSynthDesc &desc) -> QString {
            // Mint a pending symbol for the descriptor — nothing is written;
            // the definition reaches disk when a voicegroup referencing it
            // saves. Value-equal definitions (on disk or pending) are reused.
            const VgSynthCatalog &synths = vgCatalog().synths;
            QString symbol = synths.symbolFor(desc);
            if (!symbol.isEmpty())
                return symbol;
            for (auto it = m_pendingSynths.constBegin(); it != m_pendingSynths.constEnd(); ++it) {
                if (it.value() == desc)
                    return it.key();
            }
            if (!synths.creatable()) {
                statusBar()->showMessage(tr("Cannot create synth instrument: this project doesn't "
                                            "define the set_synth_* macros (Golden Sun synths need "
                                            "ipatix's improved mixer)."),
                                         8000);
                return QString();
            }
            symbol = vgSynthSymbolName(desc);
            const QString base = symbol;
            for (int i = 2; synths.find(symbol) || vgCatalog().directSound.contains(symbol); i++)
                symbol = base + QStringLiteral("_%1").arg(i);
            m_pendingSynths.insert(symbol, desc);
            return symbol;
        });
    if (ready)
        m_vgBrowser->setLoading(false);
    updateVgDockTitle();
}

const MainWindow::VgCatalog &MainWindow::vgCatalog()
{
    if (!m_vgCatalog.valid && !m_vgCatalog.loading && m_project.isOpen())
        queueCatalogRefresh();
    return m_vgCatalog;
}

void MainWindow::queueCatalogRefresh()
{
    if (m_pendingCatalogRequest != 0 || !m_project.isOpen())
        return;
    const QString root = m_project.root();
    m_vgCatalog.loading = true;
    m_pendingCatalogRequest =
        m_projectIo->refreshVgCatalog(root, [this, root](CatalogResult result) mutable {
            if (result.requestId != m_pendingCatalogRequest)
                return;
            m_pendingCatalogRequest = 0;
            if (m_project.root() != root) {
                m_vgCatalog.loading = false;
                return;
            }
            m_vgCatalog.loading = false;
            if (!result.succeeded()) {
                statusBar()->showMessage(
                    tr("Voicegroup catalog is unavailable: %1").arg(result.error), 8000);
                return;
            }
            m_vgCatalog.groupArgs = result.catalog.groupArgs;
            m_vgCatalog.keysplits = result.catalog.keysplits;
            m_vgCatalog.drumkits = result.catalog.drumkits;
            m_vgCatalog.typicalAdsr = result.catalog.typicalAdsr;
            m_vgCatalog.directSound = result.directSound.directSound;
            m_vgCatalog.synths = result.directSound.synths;
            m_vgCatalog.progWave = result.progWave;
            m_vgCatalog.perFileVoicegroups = result.perFileVoicegroups;
            m_vgCatalog.valid = true;
            updateVoicegroupBrowser();
        });
}

void MainWindow::invalidateVgCatalog()
{
    if (m_pendingCatalogRequest != 0) {
        m_projectIo->cancel(m_pendingCatalogRequest);
        m_pendingCatalogRequest = 0;
    }
    if (m_pendingSampleSetRequest != 0) {
        m_projectIo->cancel(m_pendingSampleSetRequest);
        m_pendingSampleSetRequest = 0;
    }
    m_vgCatalog.valid = false;
    m_vgCatalog.loading = false;
    m_vgCatalog.perFileVoicegroups = false;
    m_sampleWaves.clear();
    m_progWaves.clear();
    m_keysplits.clear();
    voicegroup_free_samples(m_sampleSet);
    m_sampleSet = nullptr;
}

void MainWindow::ensureSampleSet()
{
    if (m_sampleSet || m_pendingSampleSetRequest != 0 || !m_project.isOpen())
        return;
    const VgCatalog &catalog = vgCatalog();
    if (!catalog.valid)
        return;
    const QStringList sampleSymbols = catalog.directSound;
    const QStringList waveSymbols = catalog.progWave;
    const QList<QPair<QString, QString>> keysplitSymbols = catalog.keysplits;
    SampleSetRequest request;
    request.projectRoot = m_project.root();
    request.samples = sampleSymbols;
    request.waves = waveSymbols;
    request.keysplits = keysplitSymbols;
    const QString root = request.projectRoot;
    m_pendingSampleSetRequest = m_projectIo->loadSampleSet(
        std::move(request),
        [this, root, sampleSymbols, waveSymbols, keysplitSymbols](SampleSetResult result) mutable {
            if (result.requestId != m_pendingSampleSetRequest) {
                if (result.sampleSet)
                    voicegroup_free_samples(result.sampleSet);
                return;
            }
            m_pendingSampleSetRequest = 0;
            if (m_project.root() != root || !m_vgCatalog.valid ||
                m_vgCatalog.directSound != sampleSymbols || m_vgCatalog.progWave != waveSymbols ||
                m_vgCatalog.keysplits != keysplitSymbols) {
                if (result.sampleSet)
                    voicegroup_free_samples(result.sampleSet);
                return;
            }
            if (!result.succeeded()) {
                if (result.sampleSet)
                    voicegroup_free_samples(result.sampleSet);
                return;
            }
            m_sampleSet = result.sampleSet;
            result.sampleSet = nullptr;
            m_sampleWaves.clear();
            m_progWaves.clear();
            m_keysplits.clear();
            for (int i = 0; i < sampleSymbols.size() && i < m_sampleSet->count; i++) {
                if (m_sampleSet->waves[i])
                    m_sampleWaves.insert(sampleSymbols.at(i), m_sampleSet->waves[i]);
            }
            for (int i = 0; i < waveSymbols.size() && i < m_sampleSet->progWaveCount; i++) {
                if (m_sampleSet->progWaves[i])
                    m_progWaves.insert(waveSymbols.at(i), m_sampleSet->progWaves[i]);
            }
            for (int i = 0; i < keysplitSymbols.size() && i < m_sampleSet->keysplitCount; i++) {
                const LoadedKeysplit &keysplits = m_sampleSet->keysplits[i];
                if (keysplits.subGroup && keysplits.table)
                    m_keysplits.insert(keysplitSymbols.at(i).first, keysplits);
            }
            if (m_active)
                m_vgBrowser->setVoicegroup(m_active->voicegroup);
        });
}

const WaveData *MainWindow::sampleWaveFor(const QString &symbol)
{
    ensureSampleSet();
    return m_sampleWaves.value(symbol, nullptr);
}

// Browse-audition a keysplit instrument: play whatever sub-voice the
// audition key (middle C) resolves to, with that sub-voice's own envelope —
// the same resolution the engine does per note (resolve_voice).
void MainWindow::auditionKeysplit(const QString &symbol)
{
    ensureSampleSet();
    const auto it = m_keysplits.constFind(symbol);
    if (it == m_keysplits.constEnd())
        return;
    const uint8_t idx = it->table[60];
    if (idx >= VOICEGROUP_SIZE)
        return; // old-style overflow index: nothing loaded to play
    const ToneData &sub = it->subGroup[idx];
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

void MainWindow::onVoiceEditRequested(int slot, const VgVoice &voice, bool structural)
{
    SongSession *session = m_active;
    if (!session || !session->isInteractive())
        return;
    auto applied = [this](SongSession &session, int slot, bool structural) {
        onVoiceEdited(session, slot, structural);
        // The source edit is synchronous; preview/audio replacement is not.
        // Reflect both scalar and structural edits immediately while retaining
        // the existing disabled editor during an async load.
        if (&session == m_active)
            m_vgBrowser->voiceChanged(slot);
        updateTabTitle(session);
        if (&session == m_active)
            updateWindowTitle();
    };
    auto command =
        makeUndoableVoicegroupEdit(*session, slot, voice, structural, std::move(applied));
    if (command)
        session->doc.undoStack()->push(command.release());
}

void MainWindow::onVoiceEdited(SongSession &session, int slot, bool structural)
{
    if (!session.vgSource)
        return;
    if (structural) {
        reloadVoicegroupPreview(session, slot);
    } else {
        // A scalar undo can land while a structural preview is still being
        // decoded. Cancel that preview and render the current source again;
        // otherwise its older bytes can replace the scalar edit on arrival.
        const bool previewPending = session.pendingPreviewRequest != 0;
        if (previewPending) {
            m_projectIo->cancel(session.pendingPreviewRequest);
            session.pendingPreviewRequest = 0;
        }
        ToneData *tone = nullptr;
        if (session.voicegroup && slot >= 0 && slot < VOICEGROUP_SIZE)
            tone = &session.voicegroup->voices[slot];
        session.vgSource->applyScalarsToToneData(slot, tone);
        // Synth param edits are scalar pokes too: the descriptor bytes are
        // patched straight into the loaded tone (pending definitions have
        // nothing on disk to reload from). The poke can rename the voice
        // (param-named symbols), which track headers display — repaint.
        if (applyPendingSynthTones(session, session.voicegroup))
            session.view->update();
        // Playing tracks hold a copy of their instrument; refresh so the
        // edit is heard from the next note without a pause/play cycle.
        if (&session == m_active && m_audioOk)
            m_audio.refreshVoices();
        if (previewPending)
            reloadVoicegroupPreview(session, &session == m_active ? m_vgBrowser->currentSlot() : 0);
    }
    updateVgDockTitle();
    updateTabTitle(session);
}

void MainWindow::reloadVoicegroupPreview(SongSession &session, int keepSlot)
{
    if (!session.vgSource)
        return;
    if (session.pendingPreviewRequest != 0) {
        m_projectIo->cancel(session.pendingPreviewRequest);
        session.pendingPreviewRequest = 0;
    }
    SongSession *const sessionPtr = &session;
    const QString root = m_project.root();
    const QString loadName = session.vgSource->loadName();
    const QByteArray sourceBytes = session.vgSource->renderPreview();
    const auto isLive = [this, sessionPtr] {
        return std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                           [sessionPtr](const std::unique_ptr<SongSession> &candidate) {
                               return candidate.get() == sessionPtr;
                           });
    };
    PreviewRequest request;
    request.projectRoot = root;
    request.loadName = loadName;
    request.sourceBytes = sourceBytes;
    session.pendingPreviewRequest = m_projectIo->preview(
        std::move(request), [this, sessionPtr, keepSlot, root, loadName, sourceBytes,
                             isLive](PreviewResult result) mutable {
            if (!isLive()) {
                if (result.voicegroup)
                    voicegroup_free(result.voicegroup);
                return;
            }
            if (result.requestId != sessionPtr->pendingPreviewRequest) {
                if (result.voicegroup)
                    voicegroup_free(result.voicegroup);
                return;
            }
            sessionPtr->pendingPreviewRequest = 0;
            // A matching request id is not enough: scalar edits and
            // undo/redo can change the source while the worker decodes.
            if (m_project.root() != root || !sessionPtr->vgSource ||
                sessionPtr->vgSource->loadName() != loadName ||
                sessionPtr->vgSource->renderPreview() != sourceBytes) {
                if (result.voicegroup)
                    voicegroup_free(result.voicegroup);
                return;
            }
            if (!result.succeeded()) {
                if (result.voicegroup)
                    voicegroup_free(result.voicegroup);
                statusBar()->showMessage(
                    tr("Edited voicegroup failed to load — keeping the previous sound."), 8000);
                return;
            }
            swapVoicegroup(*sessionPtr, result.voicegroup, keepSlot);
            result.voicegroup = nullptr;
        });
}

const VgSynthDesc *MainWindow::synthDescForSymbol(const QString &symbol)
{
    const auto pending = m_pendingSynths.constFind(symbol);
    if (pending != m_pendingSynths.constEnd())
        return &pending.value();
    return vgCatalog().synths.find(symbol);
}

bool MainWindow::applyPendingSynthTones(SongSession &session, LoadedVoiceGroup *vg)
{
    if (!session.vgSource || !vg)
        return false;
    bool changed = false;
    for (int slot = 0; slot < VOICEGROUP_SIZE; slot++) {
        const VgVoice *v = session.vgSource->voiceAt(slot);
        if (!v || (v->macro != VgMacro::DirectSound && v->macro != VgMacro::DirectSoundNoResample &&
                   v->macro != VgMacro::DirectSoundAlt))
            continue;
        const VgSynthDesc *desc = synthDescForSymbol(v->symbol);
        if (!desc)
            continue;
        // A synth param edit rides the scalar path, so the reload that would
        // rebuild voiceNames never runs — sync the slot's name here or track
        // labels and the browser tree keep showing the pre-edit symbol.
        const QByteArray name = v->symbol.toUtf8();
        if (qstrncmp(vg->voiceNames[slot], name.constData(), VG_VOICE_NAME_LEN - 1) != 0) {
            std::strncpy(vg->voiceNames[slot], name.constData(), VG_VOICE_NAME_LEN - 1);
            vg->voiceNames[slot][VG_VOICE_NAME_LEN - 1] = '\0';
            changed = true;
        }
        ToneData &td = vg->voices[slot];
        // Already sounding these bytes (the loader resolved an on-disk
        // definition, or an earlier patch)? Leave the tone alone.
        if (td.wav && td.wav->size == 0 && td.wav->data) {
            const auto *d = reinterpret_cast<const uint8_t *>(td.wav->data);
            const VgSynthDesc current{d[1] > 2 ? 2 : d[1], d[2], d[3], d[4], d[5]};
            if (current == *desc)
                continue;
        }
        // Never mutate a loader-owned WaveData (shared across voices via its
        // cache): point the tone at a session-owned descriptor instead.
        // Re-patching an installed buffer pokes its bytes in place, which the
        // engine reads every tick — live tweaks sound without a reload.
        std::unique_ptr<SynthToneBuf> &tone = session.synthTones[slot];
        if (!tone) {
            tone = std::make_unique<SynthToneBuf>();
            std::memset(tone.get(), 0, sizeof(SynthToneBuf));
            tone->wd.status = 0x4000;   // loop flag, as the synth header sets
            tone->wd.freq = 0x01058920; // 64-sample period lands on middle C
            tone->wd.size = 0;          // size 0 = synth descriptor
            tone->wd.data = reinterpret_cast<int8_t *>(tone->bytes);
        }
        tone->bytes[0] = 0x80;
        tone->bytes[1] = uint8_t(desc->waveform);
        tone->bytes[2] = uint8_t(desc->baseDuty);
        tone->bytes[3] = uint8_t(desc->dutyStep);
        tone->bytes[4] = uint8_t(desc->modDepth);
        tone->bytes[5] = uint8_t(desc->phase);
        td.wav = &tone->wd;
        changed = true;
    }
    return changed;
}

void MainWindow::swapVoicegroup(SongSession &session, LoadedVoiceGroup *vg, int keepSlot)
{
    // Pending synth definitions aren't on disk, so a fresh load can't have
    // resolved them; patch before anything (views, engine) sees the group.
    applyPendingSynthTones(session, vg);
    session.view->setVoicegroup(nullptr);
    if (&session == m_active) {
        m_vgBrowser->setVoicegroup(nullptr);
        if (m_audioOk)
            m_audio.updateVoicegroup(vg);
    }
    if (session.voicegroup)
        voicegroup_free(session.voicegroup);
    session.voicegroup = vg;
    session.view->setVoicegroup(vg);
    if (&session == m_active) {
        updateVoicegroupBrowser();
        m_vgBrowser->selectSlot(keepSlot);
    }
}

void MainWindow::cleanupVgPreview(std::function<void()> completion)
{
    if (!m_project.isOpen()) {
        if (completion)
            completion();
        return;
    }
    // ProjectIo is FIFO: this request runs after all sidecar writes queued
    // before it, so its completion is the teardown barrier.
    m_projectIo->cleanupPreview(m_project.root(),
                                [completion = std::move(completion)](PreviewCleanupResult) mutable {
                                    if (completion)
                                        completion();
                                });
}

void MainWindow::updateVgDockTitle()
{
    const bool dirty = m_active && m_active->vgSource && m_active->vgSource->dirty();
    m_vgDock->setWindowTitle(dirty ? tr("Voicegroup*") : tr("Voicegroup"));
}

void MainWindow::newVoicegroup()
{
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted || !m_project.isOpen() ||
        projectMutationInProgress())
        return;
    const QString root = m_project.root();
    const VgCatalog &catalog = vgCatalog();
    if (!catalog.valid) {
        statusBar()->showMessage(tr("Loading voicegroup catalog…"), 5000);
        return;
    }
    if (!catalog.perFileVoicegroups) {
        QMessageBox::information(this, tr("New Voicegroup"),
                                 tr("This project keeps all voicegroups in one file; creating new "
                                    "per-file voicegroups isn't supported for that layout."));
        return;
    }
    VoicegroupSource *activeSource = m_active ? m_active->vgSource.get() : nullptr;
    QDialog dialog(this);
    dialog.setWindowTitle(tr("New Voicegroup"));
    auto *form = new QFormLayout(&dialog);
    auto *nameEdit = new QLineEdit(&dialog);
    nameEdit->setValidator(new QRegularExpressionValidator(
        QRegularExpression(QStringLiteral("[A-Za-z][A-Za-z0-9_]*")), nameEdit));
    form->addRow(tr("Name"), nameEdit);
    auto *sourceCombo = new QComboBox(&dialog);
    if (activeSource)
        sourceCombo->addItem(tr("Copy of %1").arg(QFileInfo(activeSource->filePath()).fileName()),
                             activeSource->filePath());
    sourceCombo->addItem(tr("Empty (dummy template)"), QString());
    form->addRow(tr("Start from"), sourceCombo);
    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    if (dialog.exec() != QDialog::Accepted)
        return;
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted || !m_project.isOpen() ||
        m_project.root() != root || projectMutationInProgress())
        return;
    const QString name = nameEdit->text().trimmed();
    if (name.isEmpty())
        return;
    if (catalog.groupArgs.contains(QStringLiteral("_") + name)) {
        QMessageBox::warning(this, tr("New Voicegroup"),
                             tr("A voicegroup named %1 already exists.").arg(name));
        return;
    }
    const QString copyFrom = sourceCombo->currentData().toString();
    const QString sectionLabel =
        (!copyFrom.isEmpty() && activeSource && copyFrom == activeSource->filePath())
            ? activeSource->sectionLabel()
            : QString();
    if (m_projectSwitchInProgress || m_closeInProgress || m_closeAccepted ||
        m_project.root() != root || projectMutationInProgress())
        return;
    CreateVoicegroupRequest request{root, name, copyFrom, sectionLabel};
    m_pendingCreateVoicegroupRequest = m_projectIo->createVoicegroup(
        std::move(request), [this, root, name](CreateVoicegroupResult result) mutable {
            if (result.requestId != m_pendingCreateVoicegroupRequest)
                return;
            m_pendingCreateVoicegroupRequest = 0;
            if (m_project.root() != root || m_projectSwitchInProgress || m_closeInProgress ||
                m_closeAccepted)
                return;
            if (!result.succeeded()) {
                QMessageBox::warning(this, tr("New Voicegroup"), result.error);
                return;
            }
            invalidateVgCatalog();
            updateVoicegroupBrowser();
            if (m_active) {
                SongCfg cfg = m_active->doc.cfg();
                cfg.voicegroupArg = QStringLiteral("_") + name;
                m_active->doc.setCfg(cfg);
                statusBar()->showMessage(
                    tr("Created sound/voicegroups/%1.inc and assigned it to %2 "
                       "(voicegroup_%1).")
                        .arg(name, m_active->doc.label()),
                    10000);
            } else {
                statusBar()->showMessage(
                    tr("Created sound/voicegroups/%1.inc — assign it with the voicegroup "
                       "selector above the instrument list (voicegroup_%1).")
                        .arg(name),
                    10000);
            }
        });
}

void MainWindow::maybeSaveSession(SongSession &session, SessionContinuation continuation)
{
    const auto complete = [&continuation](bool succeeded) {
        if (continuation)
            continuation(succeeded);
    };
    if (!session.midiBound || !session.vgBound) {
        complete(true);
        return;
    }
    if (session.pendingSaveRequest != 0 || session.pendingVgSaveRequest != 0) {
        complete(false);
        return;
    }
    // song and its voicegroup are one document (a normally-clean undo stack
    // can still leave the voicegroup dirty when a save was refused mid-way).
    if (!session.isDirty()) {
        complete(true);
        return;
    }
    const bool vgDirty = session.vgSource && session.vgSource->dirty();
    // Show the tab being asked about: Save/Discard for edits the user
    // can't see is a data-loss trap.
    if (&session != m_active && m_tabs->indexOf(session.view) >= 0)
        m_tabs->setCurrentWidget(session.view);
    const auto choice = QMessageBox::question(
        this, tr("Unsaved Changes"),
        vgDirty ? tr("%1 has unsaved changes (including voicegroup edits). Save them?")
                      .arg(session.doc.label())
                : tr("%1 has unsaved changes. Save them?").arg(session.doc.label()),
        QMessageBox::Save | QMessageBox::Discard | QMessageBox::Cancel, QMessageBox::Save);
    if (choice == QMessageBox::Cancel) {
        complete(false);
        return;
    }
    if (choice == QMessageBox::Save) {
        SongSession *sessionPtr = &session;
        saveSession(session, [this, sessionPtr,
                              continuation = std::move(continuation)](bool succeeded) mutable {
            const bool live =
                std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                            [sessionPtr](const std::unique_ptr<SongSession> &candidate) {
                                return candidate.get() == sessionPtr;
                            });
            if (continuation)
                continuation(live && succeeded && !sessionPtr->isDirty());
        });
        return;
    }
    complete(true);
}

void MainWindow::saveViewState(SongSession &session)
{
    if (!session.midiBound || session.doc.label().isEmpty())
        return;
    SidecarSaveRequest request;
    request.projectRoot = m_project.root();
    request.songLabel = session.doc.label();
    request.snapshot = {session.view->viewState(), session.view->editorViewState()};
    // Cosmetic and best-effort: the captured value is queued before the
    // session or project can be torn down, and no live view crosses threads.
    m_projectIo->writeSidecar(std::move(request), {});
}

void MainWindow::updateWindowTitle()
{
    const QString project = m_project.isOpen() ? QDir(m_project.root()).dirName() : QString();

    if (m_active) {
        QString label;
        if (m_active->midiBound) {
            label = m_active->doc.label();
        } else {
            const int index = m_tabs->indexOf(m_active->view);
            label = index >= 0 ? m_tabs->tabText(index) : QString();
            if (label.endsWith(QLatin1Char('*')))
                label.chop(1);
        }
        setWindowTitle(QStringLiteral("%1[*] — %2 — porydaw").arg(label, project));
        setWindowModified(m_active->isInteractive() && m_active->isDirty());
    } else {
        setWindowTitle(project.isEmpty() ? QStringLiteral("porydaw")
                                         : QStringLiteral("%1 — porydaw").arg(project));
        setWindowModified(false);
    }
}

void MainWindow::closeEvent(QCloseEvent *event)
{
    if (m_projectSwitchInProgress) {
        event->ignore();
        return;
    }
    if (m_closeAccepted) {
        event->accept();
        return;
    }
    event->ignore();
    if (m_closeInProgress)
        return;
    m_closeInProgress = true;
    // Every dirty tab gets its prompt; a Cancel keeps the window open.
    // Saves answered before it have already queued or written, as with any
    // save-all.
    promptToSaveAllSessions([this](bool succeeded) {
        if (!succeeded) {
            m_closeInProgress = false;
            return;
        }
        for (const auto &session : m_sessions)
            saveViewState(*session);
        if (m_persistSession) {
            QSettings settings;
            settings.setValue(QStringLiteral("windowGeometry"), saveGeometry());
            settings.setValue(QStringLiteral("windowState"), saveState());
            settings.setValue(QStringLiteral("songFilterText"), m_songList->searchText());
            settings.setValue(QStringLiteral("songFilterSort"), m_songList->sortIndex());
            settings.setValue(QStringLiteral("songFilterCategory"), m_songList->categoryPrefix());
        }
        cleanupVgPreview([this] {
            m_closeAccepted = true;
            m_closeInProgress = false;
            close();
        });
    });
}

// QLabel::setText repaints even for identical text, so both status
// updaters compare against the last applied value and only touch the
// widgets on change. Nothing else writes these labels, so the caches
// cannot go stale.
void MainWindow::updateTimeLabel()
{
    const bool loaded = m_audioOk && m_active && m_audio.songLoaded();
    const QString text =
        loaded ? QStringLiteral("%1 / %2").arg(formatTime(m_audio.playheadSamples()),
                                               formatTime(m_audio.timeline()->lengthSamples))
               : QStringLiteral("--:--.- / --:--.-");
    m_transportBar->setTimeText(text);
}

void MainWindow::updatePolyStatus()
{
    PolyStatusSnapshot status;
    status.loaded = m_audioOk && m_active && m_audio.songLoaded();
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

void MainWindow::uiTick()
{
    updateTimeLabel();
    updatePolyStatus();

    if (m_audioOk && m_active && m_audio.songLoaded() && m_polyDock->isVisible()) {
        AudioEngine::PolySnapshot snap;
        m_audio.polySnapshot(&snap);
        m_polyPanel->updateSnapshot(snap);
    }
    // Safety net for transport transitions no handler observed (the engine
    // stopping on its own while the playhead timer is idle): cheap no-op
    // setEnabled calls at the status cadence.
    updateTransportActions();
}

void MainWindow::synchronizePlayhead()
{
    const bool songLoaded =
        m_audioOk && m_active && m_active->isInteractive() && m_audio.songLoaded();
    const bool playing = songLoaded && m_audio.transport() == Transport::Playing;
    const int uiInterval = playing ? kPlaybackUiIntervalMs : kIdleUiIntervalMs;
    if (m_uiTimer->interval() != uiInterval)
        m_uiTimer->setInterval(uiInterval);

    if (!songLoaded) {
        // This also runs synchronously from activateSession(nullptr).
        m_playheadTimer->stop();
        return;
    }

    const bool playheadTimerWasActive = m_playheadTimer->isActive();
    const float activityElapsed = float(m_playheadTimer->interval()) / 1000.0f;
    const auto trackActivityLevels = m_audio.consumeTrackActivityLevels();
    const bool activityAnimating =
        m_active->view->advanceTrackActivity(trackActivityLevels, activityElapsed, playing);
    m_active->view->setPlayheadSample(m_audio.playheadSamples(), playing);
    if (activityAnimating) {
        if (!m_playheadTimer->isActive())
            m_playheadTimer->start();
    } else {
        m_playheadTimer->stop();
        if (playheadTimerWasActive)
            updateTransportActions();
    }
}

void MainWindow::startPlayback(bool fromEditCursor)
{
    if (!m_audioOk || !m_active || !m_active->isInteractive() || !m_audio.songLoaded())
        return;
    const bool seekToCursor = fromEditCursor || m_audio.transport() == Transport::Stopped;
    uint64_t target = 0;
    if (seekToCursor) {
        target = m_audio.timeline()->sampleForTick(m_active->view->editCursorTick());
        m_audio.seek(target);
    }
    m_audio.play();
    updateTransportActions();
    synchronizePlayhead();
    // The seek lands within one audio period; show its target now rather
    // than the stale engine playhead synchronizePlayhead just read.
    if (seekToCursor)
        m_active->view->setPlayheadSample(target, true);
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

void MainWindow::updateTransportActions()
{
    const bool loaded = m_audioOk && m_active && m_active->isInteractive() && m_audio.songLoaded();
    auto state = TransportBar::PlaybackState::Unavailable;
    if (loaded) {
        switch (m_audio.transport()) {
        case Transport::Stopped:
            state = TransportBar::PlaybackState::Stopped;
            break;
        case Transport::Paused:
            state = TransportBar::PlaybackState::Paused;
            break;
        case Transport::Playing:
            state = TransportBar::PlaybackState::Playing;
            break;
        }
    }
    m_transportBar->setPlaybackState(state);
    m_transportBar->setSessionAvailable(loaded);
}

void MainWindow::syncMasterVolumeControl()
{
    const bool loaded = m_active && m_active->isInteractive();
    m_transportBar->setMasterVolume(
        loaded ? m_active->doc.cfg().masterVolume : SongCfg().masterVolume, loaded);
}

void MainWindow::syncScaleControls(SongSession *session)
{
    if (session != m_active)
        return;
    SongView *view = session ? session->view : nullptr;
    m_transportBar->setScaleState(view ? view->scaleRoot() : 0,
                                  view ? view->scaleId() : porydaw_scale::displayOrder()[0],
                                  view && view->scaleHighlight(), view && view->scaleFold());
}

QString MainWindow::formatTime(uint64_t samples) const
{
    const double seconds = double(samples) / m_audio.sampleRate();
    const int mins = int(seconds) / 60;
    const int secs = int(seconds) % 60;
    const int tenths = int(seconds * 10) % 10;
    return QStringLiteral("%1:%2.%3").arg(mins).arg(secs, 2, 10, QLatin1Char('0')).arg(tenths);
}
