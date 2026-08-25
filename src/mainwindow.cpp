#include "mainwindow.h"

#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDebug>
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
#include <QSignalBlocker>
#include <QSpinBox>
#include <QStatusBar>
#include <QStyle>
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
#include "ui/songview.h"
#include "ui/theme/themecontroller.h"
#include "ui/theme/themedialog.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"
#include "ui/viewsidecar.h"

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
    m_editorDrawerState = loadEditorDrawerState(*m_themeSettings);
    updateWindowFrameTheme();
    m_themeDialog = std::make_unique<themes::ThemeDialog>(*m_themeController, this);
    buildUi();

    QSettings settings;
    restoreGeometry(settings.value(QStringLiteral("windowGeometry")).toByteArray());
    restoreState(settings.value(QStringLiteral("windowState")).toByteArray());
    m_workspace->restoreSongFilters(
        {settings.value(QStringLiteral("songFilterText")).toString(),
         settings.value(QStringLiteral("songFilterSort")).toInt(),
         settings.value(QStringLiteral("songFilterCategory")).toString()});

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
    // Detach pages before session resources vanish; WorkspaceUi owns their
    // lifecycle and can otherwise emit activation signals while doing so.
    if (m_workspace) {
        disconnect(m_workspace.get(), nullptr, this, nullptr);
        m_workspace->detachAllSessions();
    }
    if (m_uiTimer)
        m_uiTimer->stop();
    if (m_playheadTimer)
        m_playheadTimer->stop();
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
        if (m_active)
            closeSession(*m_active);
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
            m_workspace->viewFor(*m_active).copySelection();
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
            m_workspace->viewFor(*m_active).setEventListVisible(on);
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

    m_workspace = std::make_unique<WorkspaceUi>(*this);
    m_workspace->setEditorDrawerState(m_editorDrawerState);

    {
        QSettings settings;
        m_workspace->setFollowPlayhead(settings.value(kFollowPlayheadKey, true).toBool());
        m_audio.setOutputVolume(settings.value(kOutputVolumeKey, 100).toInt());
        m_workspace->setTransportOutputVolume(m_audio.outputVolume());
        const bool resonanceSuppression = settings.value(kResonanceSuppressionKey, false).toBool();
        m_audio.setResonanceSuppression(resonanceSuppression);
        m_workspace->setTransportResonanceSuppression(resonanceSuppression);
    }
    connect(m_workspace.get(), &WorkspaceUi::goToStartRequested, this, [this] {
        if (m_active)
            m_workspace->viewFor(*m_active).goToStart();
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
        if (!m_active || m_active->doc.cfg().masterVolume == value)
            return;
        SongCfg cfg = m_active->doc.cfg();
        cfg.masterVolume = value;
        m_active->doc.setCfg(cfg);
    });
    connect(m_workspace.get(), &WorkspaceUi::scaleRootChanged, this, [this](int root) {
        if (m_active)
            m_workspace->viewFor(*m_active).setScaleRoot(root);
    });
    connect(m_workspace.get(), &WorkspaceUi::scaleIdChanged, this,
            [this](porydaw_scale::ScaleId scale) {
                if (m_active)
                    m_workspace->viewFor(*m_active).setScaleId(scale);
            });
    connect(m_workspace.get(), &WorkspaceUi::scaleHighlightChanged, this, [this](bool enabled) {
        if (m_active)
            m_workspace->viewFor(*m_active).setScaleHighlight(enabled);
    });
    connect(m_workspace.get(), &WorkspaceUi::scaleFoldChanged, this, [this](bool enabled) {
        if (m_active)
            m_workspace->viewFor(*m_active).setScaleFold(enabled);
    });

    connect(m_workspace.get(), &WorkspaceUi::songActivated, this, &MainWindow::songActivated);
    connect(m_workspace.get(), &WorkspaceUi::songOpenInNewTabRequested, this,
            &MainWindow::songOpenInNewTab);
    connect(m_workspace.get(), &WorkspaceUi::songRegisterRequested, this,
            &MainWindow::registerSongById);
    connect(m_workspace.get(), &WorkspaceUi::songDeleteRequested, this,
            &MainWindow::deleteSongById);
    m_workspace->bindFindSongShortcut(keys);

    connect(m_workspace.get(), &WorkspaceUi::auditionVoiceRequested, this,
            [this](int voice, int key, int velocity) {
                if (m_audioOk)
                    m_audio.previewVoice(uint8_t(voice), uint8_t(key), uint8_t(velocity));
            });
    connect(m_workspace.get(), &WorkspaceUi::voiceEditRequested, this,
            &MainWindow::onVoiceEditRequested);
    connect(m_workspace.get(), &WorkspaceUi::newVoicegroupRequested, this,
            &MainWindow::newVoicegroup);
    connect(m_workspace.get(), &WorkspaceUi::newSampleRequested, this,
            &MainWindow::importSampleForSlot);
    connect(m_workspace.get(), &WorkspaceUi::editSampleRequested, this,
            &MainWindow::editSampleForSlot);
    m_workspace->setVoicegroupSampleInfoProvider([this](const QString &symbol) {
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
        m_workspace.get(), &WorkspaceUi::sampleAuditionRequested, this,
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
    connect(m_workspace.get(), &WorkspaceUi::sampleAuditionStopRequested, this, [this] {
        if (m_audioOk)
            m_audio.auditionSampleOff();
    });
    connect(m_workspace.get(), &WorkspaceUi::voicegroupChangeRequested, this,
            [this](const QString &arg) {
                if (!m_active)
                    return;
                SongCfg cfg = m_active->doc.cfg();
                if (arg == cfg.voicegroupArg ||
                    (cfg.voicegroupArg.isEmpty() && arg == QLatin1String("_dummy"))) {
                    return;
                }
                cfg.voicegroupArg = arg;
                m_active->doc.setCfg(cfg);
            });

    connect(m_workspace.get(), &WorkspaceUi::activeSessionChanged, this,
            [this](SongSession *session) {
                if (m_tearingDown || m_restoringSession)
                    return;
                activateSession(session);
                syncScaleControls(session);
            });
    connect(m_workspace.get(), &WorkspaceUi::closeSessionRequested, this,
            [this](SongSession *session) {
                Q_ASSERT(session);
                if (!session)
                    qFatal("MainWindow: workspace requested a null session close");
                closeSession(*session);
            });
    connect(m_workspace.get(), &WorkspaceUi::sessionsReordered, this,
            [this] { persistOpenTabs(); });
    connect(m_workspace.get(), &WorkspaceUi::followPlayheadChanged, this, [this](bool enabled) {
        QSettings settings;
        settings.setValue(kFollowPlayheadKey, enabled);
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
                // commitEditCursor's editCursorMoved connect already seeks
                // the engine while playing/paused; when stopped, playback
                // starts from the edit cursor. revealNote selects the losing
                // track and the lost note itself.
                if (!m_active)
                    return;
                SongView &view = m_workspace->viewFor(*m_active);
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

SongSession *MainWindow::sessionForLabel(const QString &label) const
{
    for (const auto &session : m_sessions) {
        if (session->doc.label() == label)
            return session.get();
    }
    return nullptr;
}
SongSession *MainWindow::createSession()
{
    auto owned = std::make_unique<SongSession>();
    SongSession *s = owned.get();

    connect(&s->doc, &SongDocument::documentChanged, this, [this, s] { onDocumentChanged(*s); });
    connect(s->doc.undoStack(), &QUndoStack::cleanChanged, this, [this, s](bool) {
        if (!m_workspace->isSessionAttached(*s))
            return;
        updateTabTitle(*s);
        if (s == m_active)
            updateWindowTitle();
    });
    m_undoGroup->addStack(s->doc.undoStack());
    m_sessions.push_back(std::move(owned));
    return s;
}

void MainWindow::wireSongView(SongSession &session, SongView &view)
{
    SongSession *const sourceSession = &session;
    connect(&view, &SongView::auditionNote, this,
            [this, sourceSession](int track, int key, int velocity) {
                if (sourceSession == m_active && m_audioOk && m_audio.songLoaded())
                    m_audio.previewNote(uint8_t(track), uint8_t(key), uint8_t(velocity));
            });
    connect(&view, &SongView::auditionNoteTimed, this,
            [this, sourceSession](int track, int key, int velocity, quint32 durationSamples) {
                if (sourceSession == m_active && m_audioOk && m_audio.songLoaded()) {
                    m_audio.previewNoteTimed(uint8_t(track), uint8_t(key), uint8_t(velocity),
                                             durationSamples);
                }
            });
    connect(&view, &SongView::auditionVoice, this,
            [this, sourceSession](int voice, int key, int velocity) {
                if (sourceSession == m_active && m_audioOk)
                    m_audio.previewVoice(uint8_t(voice), uint8_t(key), uint8_t(velocity));
            });
    connect(&view, &SongView::statusMessage, this, [this, sourceSession](const QString &message) {
        if (sourceSession == m_active)
            statusBar()->showMessage(message, 6000);
    });
    connect(&view, &SongView::editCursorMoved, this, [this, sourceSession](uint64_t tick) {
        if (sourceSession != m_active || !m_audioOk || !m_audio.songLoaded() ||
            m_audio.transport() == Transport::Stopped) {
            return;
        }
        const uint64_t targetSample = m_audio.timeline()->sampleForTick(tick);
        m_audio.seek(targetSample);
        m_workspace->viewFor(*sourceSession)
            .setPlayheadSample(targetSample, m_audio.transport() == Transport::Playing);
    });
    connect(&view, &SongView::playPauseFromRequested, this, [this, sourceSession](uint64_t tick) {
        if (sourceSession != m_active)
            return;
        if (m_audio.transport() == Transport::Playing) {
            m_workspace->triggerPlayPause();
            m_workspace->viewFor(*sourceSession).commitEditCursor(tick);
            return;
        }
        m_workspace->viewFor(*sourceSession).commitEditCursor(tick);
        m_workspace->triggerPlayPause();
    });
    connect(&view, &SongView::revealVoiceRequested, this, [this, sourceSession](int program) {
        if (sourceSession != m_active)
            return;
        m_workspace->showVoicegroupPanel();
        m_workspace->revealVoicegroupSlot(program);
    });
    connect(&view, &SongView::eventListVisibilityChanged, this,
            [this, sourceSession](bool visible) {
                if (sourceSession != m_active)
                    return;
                const QSignalBlocker blocker(m_eventListAction);
                m_eventListAction->setChecked(visible);
                updateDrawerActions();
            });
    connect(&view, &SongView::editorDrawerStateChanged, this,
            [this](const EditorDrawerState &state) { setEditorDrawerState(state); });
    connect(&view, &SongView::muteMaskChanged, this, [this, sourceSession](uint32_t mask) {
        if (sourceSession == m_active)
            m_audio.setMuteMask(mask);
    });
    connect(&view, &SongView::soloMaskChanged, this, [this, sourceSession](uint32_t mask) {
        if (sourceSession == m_active)
            m_audio.setSoloMask(mask);
    });
    const auto syncScaleState = [this, sourceSession] {
        if (sourceSession == m_active)
            syncScaleControls(sourceSession);
    };
    connect(&view, &SongView::scaleHighlightChanged, this, syncScaleState);
    connect(&view, &SongView::scaleFoldChanged, this, syncScaleState);
    connect(&view, &SongView::scaleRootChanged, this, syncScaleState);
    connect(&view, &SongView::scaleIdChanged, this, syncScaleState);
}

void MainWindow::closeSession(SongSession &session)
{
    if (!maybeSaveSession(session))
        return;
    saveViewState(session);
    destroySession(&session);
    persistOpenTabs();
}

void MainWindow::destroySession(SongSession *session)
{
    m_workspace->detachSession(*session);
    // Detaching the current tab may activate a neighbor through WorkspaceUi;
    // clear the engine only when no such activation occurred.
    if (m_active == session)
        activateSession(nullptr);
    std::erase_if(m_sessions, [session](const std::unique_ptr<SongSession> &candidate) {
        return candidate.get() == session;
    });
}

bool MainWindow::promptToSaveAllSessions()
{
    for (const auto &session : m_sessions) {
        if (!maybeSaveSession(*session))
            return false;
    }
    return true;
}

void MainWindow::teardownSessions()
{
    m_tearingDown = true;
    // One engine/dock detach up front; WorkspaceUi then deletes every page
    // without rebinding the doomed sessions.
    activateSession(nullptr, /*force=*/true);
    m_workspace->detachAllSessions();
    m_sessions.clear();
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
    m_workspace->activateSession(session);
    m_undoGroup->setActiveStack(session ? session->doc.undoStack() : nullptr);
    syncMasterVolumeControl();
    syncScaleControls(session);

    const bool loaded = session != nullptr;
    m_saveAction->setEnabled(loaded);
    m_exportWavAction->setEnabled(loaded);
    m_settingsAction->setEnabled(loaded);
    m_closeTabAction->setEnabled(loaded);
    m_eventListAction->setEnabled(loaded);
    m_copyAction->setEnabled(loaded);
    {
        // Reflect the incoming tab's roll/event-list state without the
        // checkbox driving a redundant toggle.
        QSignalBlocker blocker(m_eventListAction);
        const bool eventListVisible = session && m_workspace->viewFor(*session).eventListVisible();
        m_eventListAction->setChecked(eventListVisible);
    }
    updateDrawerActions();

    if (!session) {
        if (m_audioOk)
            m_audio.unloadSong();
        m_polyPanel->clearSession();
        m_workspace->clearVoicegroupPresentation();
        updateVgDockTitle();
        m_registerAction->setEnabled(false);
        m_workspace->setTransportSongName(QString());
        updateTimeLabel();
        updatePolyStatus();
        m_workspace->setCurrentSong(-1);
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
    if (m_audioOk && session->timeline && session->voicegroup)
        attachEngine(*session);
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
    m_workspace->setTransportSongName(session->doc.label());
    m_workspace->setCurrentSong(session->songId);
    updateWindowTitle();
    updateTransportActions();
    m_workspace->viewFor(*session).focusActiveSurface();
    persistOpenTabs();
}

void MainWindow::attachEngine(SongSession &session)
{
    m_audio.loadSong(session.timeline, session.voicegroup, songSettingsFor(session));
    // loadSong resets the engine's masks; the view remembers the tab's.
    SongView &view = m_workspace->viewFor(session);
    m_audio.setMuteMask(view.muteMask());
    m_audio.setSoloMask(view.soloMask());
}

void MainWindow::updatePolyPanelContext(SongSession *session)
{
    if (!session) {
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
    // Another tab may have saved this session's voicegroup since it was
    // opened; a clean session silently follows the disk. A dirty one keeps
    // its unsaved edits — last save wins, as with any two-editor overlap.
    if (!session.vgSource || session.vgSource->dirty())
        return;
    const QDateTime onDisk = QFileInfo(session.vgSource->filePath()).lastModified();
    if (!onDisk.isValid() || onDisk == session.vgFileTime)
        return;
    QString tried;
    LoadedVoiceGroup *vg = loadVoicegroupFor(session.doc.cfg(), &tried);
    if (!vg)
        return; // keep the previous sound
    SongView &view = m_workspace->viewFor(session);
    view.setVoicegroup(nullptr);
    if (session.voicegroup)
        voicegroup_free(session.voicegroup);
    session.voicegroup = vg;
    view.setVoicegroup(vg);
    // Fresh parse of the saved file (also re-records its mtime).
    openVoicegroupSource(session, session.doc.cfg());
}

void MainWindow::refreshSessionsAfterVgSave(const QString &filePath, SongSession *except)
{
    for (const auto &owned : m_sessions) {
        SongSession *session = owned.get();
        if (session == except || !session->vgSource || session->vgSource->filePath() != filePath)
            continue;
        if (session->vgSource->dirty())
            continue; // unsaved edits stay; last save wins, as documented
        QString tried;
        LoadedVoiceGroup *vg = loadVoicegroupFor(session->doc.cfg(), &tried);
        if (!vg)
            continue; // keep the previous sound
        const int keepSlot = session == m_active ? m_workspace->currentVoicegroupSlot() : 0;
        swapVoicegroup(*session, vg, keepSlot);
        // Fresh parse of the saved file (also re-records its mtime), then
        // re-point the browser at it — swapVoicegroup bound the old one.
        openVoicegroupSource(*session, session->doc.cfg());
        if (session == m_active)
            updateVoicegroupBrowser();
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
    for (SongSession *session : m_workspace->sessionsInDisplayOrder())
        labels << session->doc.label();
    if (labels.isEmpty()) {
        settings.remove(kLastOpenSongsKey);
        settings.remove(kLastSongLabelKey);
        return;
    }
    settings.setValue(kLastOpenSongsKey, labels);
    settings.setValue(kLastSongLabelKey, m_active ? m_active->doc.label() : labels.first());
}

void MainWindow::refreshSessionSongIds()
{
    for (const auto &session : m_sessions) {
        session->songId = -1;
        for (const SongInfo &song : m_project.songs()) {
            if (song.label == session->doc.label()) {
                session->songId = song.id;
                break;
            }
        }
    }
    if (m_active)
        m_workspace->setCurrentSong(m_active->songId);
}

void MainWindow::updateTabTitle(SongSession &session)
{
    m_workspace->setSessionTitle(session, session.doc.label(), session.isDirty(),
                                 session.doc.midPath());
}

void MainWindow::toggleDrawerPage(bool automation)
{
    if (!m_active)
        return;
    SongView &view = m_workspace->viewFor(*m_active);
    if (view.eventListVisible())
        return;
    const EditorDrawerPage page =
        automation ? EditorDrawerPage::Automations : EditorDrawerPage::Velocity;
    const bool hiding = view.drawerSectionVisible(page);
    view.toggleDrawerSection(page);
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
    m_workspace->setEditorDrawerState(state);
}

void MainWindow::updateDrawerActions()
{
    const bool enabled = m_active && !m_workspace->viewFor(*m_active).eventListVisible();
    m_automationDrawerAction->setEnabled(enabled);
    m_velocityDrawerAction->setEnabled(enabled);
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
    if (dir.isEmpty() || !QDir(dir).exists())
        return;
    // Read before openProjectDir clears them for the fresh project.
    QStringList labels = settings.value(kLastOpenSongsKey).toStringList();
    const QString activeLabel = settings.value(kLastSongLabelKey).toString();
    if (labels.isEmpty() && !activeLabel.isEmpty())
        labels << activeLabel; // session recorded before tabs existed
    if (!openProjectDir(dir, /*interactive=*/false))
        return;
    // Load the tabs without activating each in turn — the per-activation
    // work (engine rebind, voicegroup-dock rebuild, tab persistence) would
    // run N times with all but the last discarded. One activation at the
    // end, for the remembered active tab.
    m_restoringSession = true;
    for (const QString &label : labels)
        loadSongByLabel(label, /*newTab=*/true);
    m_restoringSession = false;
    SongSession *toActivate = sessionForLabel(activeLabel);
    if (!toActivate) {
        const auto sessions = m_workspace->sessionsInDisplayOrder();
        if (!sessions.empty())
            toActivate = sessions.front();
    }
    if (toActivate)
        activateSession(toActivate);
}

bool MainWindow::openProjectDir(const QString &dir, bool interactive)
{
    QElapsedTimer timer;
    timer.start();

    // Every prompt before the project (or any tab) changes: a Cancel
    // aborts the switch, though Saves answered before it have already
    // written — standard save-all behavior, not a transaction.
    if (!promptToSaveAllSessions())
        return false;
    for (const auto &session : m_sessions)
        saveViewState(*session); // against the old project root
    cleanupVgPreview();

    QString error;
    if (!m_project.open(dir, &error)) {
        if (interactive)
            QMessageBox::warning(this, tr("Open Project"), error);
        else
            statusBar()->showMessage(tr("Couldn't reopen last project %1: %2").arg(dir, error));
        return false;
    }
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
    m_workspace->setCurrentSong(-1);

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
    return true;
}

void MainWindow::populateSongList()
{
    m_workspace->setSongs(m_project.songs());
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

LoadedVoiceGroup *MainWindow::loadVoicegroupFor(const SongCfg &cfg, QString *tried)
{
    const QStringList candidates = DecompProject::voicegroupCandidates(cfg);
    if (tried)
        *tried = candidates.join(QStringLiteral(", "));
    const QByteArray rootUtf8 = m_project.root().toLocal8Bit();
    for (const QString &name : candidates) {
        LoadedVoiceGroup *vg =
            voicegroup_load(rootUtf8.constData(), name.toLocal8Bit().constData(), nullptr);
        if (vg)
            return vg;
    }
    return nullptr;
}

void MainWindow::loadSong(const SongInfo &song, bool newTab)
{
    if (!m_audioOk)
        return;
    // Already open somewhere? Focus that tab: two documents over one .mid
    // would fight over the file on save. Except the song already in the
    // CURRENT tab — re-activating it falls through to an in-place reload
    // from disk (the pre-tabs behavior, and the only reload path for a
    // .mid changed externally).
    if (SongSession *open = sessionForLabel(song.label)) {
        if (newTab || open != m_active) {
            activateSession(open);
            return;
        }
    }

    const bool created = newTab || !m_active;
    SongSession *session = created ? nullptr : m_active;
    if (session) {
        if (!maybeSaveSession(*session))
            return;
        saveViewState(*session); // the outgoing song's, while its view is up
    }
    cleanupVgPreview();

    QApplication::setOverrideCursor(Qt::WaitCursor);
    QElapsedTimer timer;
    timer.start();

    QString tried;
    LoadedVoiceGroup *vg = loadVoicegroupFor(song.cfg, &tried);
    if (!vg) {
        QApplication::restoreOverrideCursor();
        QMessageBox::warning(
            this, tr("Load Song"),
            tr("Could not load the voicegroup for %1 (tried: %2).").arg(song.label, tried));
        return;
    }

    if (!session)
        session = createSession();
    session->doc.setTrackBudget(m_project.trackBudgetFor(song));
    QString error;
    if (!session->doc.load(song, &error)) {
        voicegroup_free(vg);
        if (created)
            destroySession(session);
        QApplication::restoreOverrideCursor();
        QMessageBox::warning(this, tr("Load Song"), error);
        return;
    }

    auto timeline = session->doc.buildTimeline(m_audio.sampleRate());

    // An attached in-place reload must release every borrow before its old
    // model state is freed. A new session has no page yet.
    SongView *view = nullptr;
    if (!created) {
        view = &m_workspace->viewFor(*session);
        view->setDocument(nullptr);
        view->setSong(nullptr, nullptr);
    }
    if (session == m_active) {
        m_workspace->setVoicegroup(nullptr);
        m_audio.unloadSong();
    }
    if (session->voicegroup)
        voicegroup_free(session->voicegroup);
    session->voicegroup = vg;
    session->timeline = std::move(timeline);
    openVoicegroupSource(*session, song.cfg);
    session->songId = song.id;
    session->appliedVoicegroupArg = song.cfg.voicegroupArg;
    session->appliedVolume = song.cfg.masterVolume;
    session->appliedReverb = song.cfg.reverb;
    ViewSidecar::Snapshot viewSnapshot;
    const bool hasViewSnapshot = ViewSidecar::load(m_project.root(), song.label, &viewSnapshot);

    if (created) {
        view = &m_workspace->attachSession(*session, song.label, song.midPath, viewSnapshot,
                                           m_restoringSession
                                               ? WorkspaceUi::ActivationPolicy::PreserveCurrent
                                               : WorkspaceUi::ActivationPolicy::Activate);
        wireSongView(*session, *view);
    } else {
        view->setSong(session->timeline.get(), session->voicegroup);
        view->setDocument(&session->doc);
        if (hasViewSnapshot)
            m_workspace->applySessionViewState(*session, viewSnapshot);
    }
    updateTabTitle(*session);

    if (!created && !m_restoringSession)
        activateSession(session, /*force=*/true);

    const MidiTimeline *tl = session->timeline.get();
    QString loopNote = tl->hasLoop() ? tr(", loops") : tr(", no loop markers");
    QString dropNote;
    if (tl->droppedTracks > 0)
        dropNote = tr(", %1 tracks beyond 16 ignored").arg(tl->droppedTracks);
    statusBar()->showMessage(tr("Loaded %1 in %2 ms — %3 events%4%5")
                                 .arg(song.label)
                                 .arg(timer.elapsed())
                                 .arg(tl->events.size())
                                 .arg(loopNote, dropNote));

    QApplication::restoreOverrideCursor();
    updateTransportActions();
}

void MainWindow::onDocumentChanged(SongSession &session)
{
    if (!m_workspace->isSessionAttached(session))
        return;
    if (!m_audioOk)
        return;
    const bool active = &session == m_active;

    const SongCfg &cfg = session.doc.cfg();
    if (cfg.voicegroupArg != session.appliedVoicegroupArg) {
        // The -G switch (or its undo/redo) swaps the voicegroup. Unsaved
        // voice edits need no prompt: they live in the undo history and are
        // reapplied whenever their voicegroup source is reopened.
        cleanupVgPreview();
        QString tried;
        if (LoadedVoiceGroup *vg = loadVoicegroupFor(cfg, &tried)) {
            SongView &view = m_workspace->viewFor(session);
            view.setVoicegroup(nullptr);
            if (active) {
                m_workspace->setVoicegroup(nullptr);
                m_audio.updateVoicegroup(vg);
            }
            if (session.voicegroup)
                voicegroup_free(session.voicegroup);
            session.voicegroup = vg;
            openVoicegroupSource(session, cfg);
            if (session.vgSource)
                reapplyVoicegroupEditsToReopenedSource(*session.doc.undoStack(), session.vgSource);
            view.setVoicegroup(session.voicegroup);
            if (active)
                updateVoicegroupBrowser();
            session.appliedVoicegroupArg = cfg.voicegroupArg;
            // Replayed edits aren't in the disk file just loaded; audition
            // them through the preview shadow like any unsaved edit.
            if (session.vgSource && session.vgSource->dirty()) {
                reloadVoicegroupPreview(session, active ? m_workspace->currentVoicegroupSlot() : 0);
            }
        } else {
            statusBar()->showMessage(
                tr("Voicegroup not found (tried: %1) — keeping the previous one until save.")
                    .arg(tried),
                8000);
        }
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
    m_workspace->viewFor(session).updateSong(timeline.get());
    session.timeline = std::move(timeline);
    updateTabTitle(session);
    if (active) {
        // The timeline was rebuilt, track names may have changed, and the
        // voicegroup may have been swapped above.
        updatePolyPanelContext(&session);
        updateWindowTitle();
        // Keep the dock's voicegroup selector on the cfg even when no swap
        // ran (the arg's voicegroup wasn't found, or its change was undone).
        m_workspace->setCurrentVoicegroupArg(cfg.voicegroupArg.isEmpty() ? QStringLiteral("_dummy")
                                                                         : cfg.voicegroupArg);
        // Program changes may have been added/removed; refresh the dock's
        // used-voice marks (no-op when the set is unchanged).
        m_workspace->setVoicegroupUsedVoices(m_workspace->viewFor(session).usedVoices());
        // the toolbar spinbox mirrors it.
        syncMasterVolumeControl();
    }
}

void MainWindow::saveSong()
{
    if (m_active)
        saveSession(*m_active);
}

bool MainWindow::saveSession(SongSession &session)
{
    if (session.doc.midPath().isEmpty())
        return false;

    // The voicegroup first: the document save below marks the undo stack
    // clean, and a failed voicegroup write must leave the session dirty so
    // the user can retry.
    const bool vgWasDirty = session.vgSource && session.vgSource->dirty();
    if (vgWasDirty) {
        QString error;
        // Golden Sun synth definitions this voicegroup references that only
        // exist in memory (minted by param edits) must land on disk first —
        // the saved file's symbols have to resolve. Only what the SAVED
        // state references is written; abandoned tweaks never persist.
        QList<QPair<QString, VgSynthDesc>> newDefs;
        for (int slot = 0; slot < VOICEGROUP_SIZE; slot++) {
            const VgVoice *v = session.vgSource->voiceAt(slot);
            if (!v)
                continue;
            const auto it = m_pendingSynths.constFind(v->symbol);
            if (it == m_pendingSynths.constEnd())
                continue;
            const QPair<QString, VgSynthDesc> def{it.key(), it.value()};
            if (!newDefs.contains(def))
                newDefs.append(def);
        }
        if (!newDefs.isEmpty()) {
            if (!VoicegroupSource::writeSynthDefinitions(m_project.root(), newDefs, &error)) {
                QMessageBox::warning(this, tr("Save Voicegroup"), error);
                return false;
            }
            // The definitions are on disk now whatever the voicegroup save
            // below does; the catalog must rescan or a failed save would
            // leave them invisible to lookups, dedupe, and the dropdown.
            invalidateVgCatalog();
        }
        if (!session.vgSource->save(&error)) {
            QMessageBox::warning(this, tr("Save Voicegroup"), error);
            return false;
        }
        // Written definitions graduate from pending to on-disk only once the
        // voicegroup save landed: a failed save keeps them pending so synth
        // lookups still resolve them (the writer skips value-equal defs, so
        // the retry save stays a no-op for them).
        for (const auto &def : newDefs)
            m_pendingSynths.remove(def.first);
        cleanupVgPreview();
        // Invalidate before the reload below repopulates the browser: the
        // rebuilt catalog must include any synth definitions written above.
        invalidateVgCatalog();
        // Reload from the project: verifies the saved file parses and
        // replaces any preview-loaded state.
        const int slot = &session == m_active ? m_workspace->currentVoicegroupSlot() : 0;
        QString tried;
        if (LoadedVoiceGroup *vg = loadVoicegroupFor(session.doc.cfg(), &tried))
            swapVoicegroup(session, vg, slot);
        updateVgDockTitle();
        // Only a real write may refresh the stamp: recording the mtime on a
        // doc-only save would silently absorb another tab's voicegroup save
        // and defeat the staleness reload for good.
        session.vgFileTime = QFileInfo(session.vgSource->filePath()).lastModified();
        // Sibling tabs on this voicegroup can't wait for their next
        // activation: the ACTIVE tab never gets one, and a stale parse
        // there would revert this save on its own next voicegroup write.
        refreshSessionsAfterVgSave(session.vgSource->filePath(), &session);
    }

    QString error;
    if (!session.doc.save(&error)) {
        QMessageBox::warning(this, tr("Save Song"), error);
        return false;
    }
    if (session.songId >= 0)
        m_project.setSongCfg(session.songId, session.doc.cfg());
    statusBar()->showMessage(
        vgWasDirty ? tr("Saved %1 and %2").arg(session.doc.midPath(), session.vgSource->filePath())
                   : tr("Saved %1").arg(session.doc.midPath()),
        5000);
    updateTabTitle(session);
    if (&session == m_active)
        updateWindowTitle();
    return true;
}

void MainWindow::exportWav()
{
    SongSession *session = m_active;
    if (!session || !m_audio.songLoaded())
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
    if (m_active)
        song = SongTarget{m_active->doc.cfg(), m_active->doc.label()};
    const QStringList vgArgs = vgCatalog().groupArgs;
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
        if (m_active) {
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
    if (!m_project.isOpen())
        return;
    NewSongWizard wizard(&m_project, vgCatalog().groupArgs, this);
    if (wizard.exec() != QDialog::Accepted)
        return;
    finishCreateSong(wizard.songFile(), wizard.label(), wizard.constant(), wizard.player(),
                     wizard.cfg(), wizard.newVoicegroupName());
}

void MainWindow::importMidi()
{
    if (!m_project.isOpen())
        return;
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
    NewSongWizard wizard(&m_project, std::move(smf), path, vgCatalog().groupArgs, this);
    if (wizard.exec() != QDialog::Accepted)
        return;
    finishCreateSong(wizard.songFile(), wizard.label(), wizard.constant(), wizard.player(),
                     wizard.cfg(), wizard.newVoicegroupName());
}

void MainWindow::importSample()
{
    importSampleForSlot(-1);
}

void MainWindow::importSampleForSlot(int slot)
{
    if (!m_project.isOpen())
        return;
    // Refuse before the file dialog: a legacy-aif or unwired project can't
    // take samples no matter which file is picked.
    const SampleFormatProbe probe = SampleRegistrar::probeSampleFormat(m_project.root());
    if (!probe.ok()) {
        QMessageBox::warning(this, tr("Import Sample"), probe.refusal);
        return;
    }
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

    const QString root = m_project.root();
    const QStringList symbols = vgCatalog().directSound;
    // Browser-initiated: audition with the destination voice's envelope
    // when that slot already holds a DirectSound-family voice.
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
        [root, symbols](const QString &name, QString *validationError) {
            return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
        },
        m_audioOk ? &m_audio : nullptr, hasDestAdsr ? &destAdsr : nullptr, this);
    if (dialog.exec() != QDialog::Accepted)
        return;

    // Write-through commit (not undoable, like song registration): the
    // rendered .wav (FORMATS.md §1) plus its direct_sound_data.inc block.
    if (!SampleRegistrar::registerSample(root, dialog.sampleName(), dialog.wavBytes(), &error)) {
        QMessageBox::warning(this, tr("Import Sample"), error);
        return;
    }
    // Provenance sidecar (PLAN.md §3): source identity + the edit params, so
    // "Edit sample…" reopens from the hi-res source. Auxiliary — a failed
    // write never fails the commit that just landed.
    SampleSidecar sidecar;
    sidecar.sourcePath = QFileInfo(path).absoluteFilePath();
    sidecar.sourceSha256 = SampleRegistrar::sourceHashHex(sourceBytes);
    sidecar.leftOnly = leftOnly;
    sidecar.sf2Zone = sf2Zone;
    sidecar.params = dialog.document()->params();
    QString sidecarError;
    if (!SampleRegistrar::writeSampleSidecar(root, dialog.sampleName(), sidecar, &sidecarError))
        statusBar()->showMessage(
            tr("Sample imported, but saving its edit history failed: %1").arg(sidecarError), 8000);
    invalidateVgCatalog();
    updateVoicegroupBrowser();

    // Browser-initiated: point the requesting slot's voice at the new sample
    // via the session undo stack — the file creation above is write-through,
    // but the voice assignment stays undoable (PLAN.md §3).
    if (slot >= 0 && m_active && m_active->vgSource) {
        // A DirectSound-family slot keeps its voice and only swaps the
        // sample: the dialog auditioned with that voice's envelope, so
        // replacing its ADSR (or key/pan/macro variant) would commit
        // something other than what was heard.
        const VgVoice *dest = m_active->vgSource->voiceAt(slot);
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
                vgDefaultAdsr(vgCatalog().typicalAdsr, voice.macro,
                              QStringLiteral("DirectSoundWaveData_") + dialog.sampleName());
            voice.attack = adsr.attack;
            voice.decay = adsr.decay;
            voice.sustain = adsr.sustain;
            voice.release = adsr.release;
        }
        voice.symbol = QStringLiteral("DirectSoundWaveData_") + dialog.sampleName();
        onVoiceEditRequested(slot, voice, true);
        m_workspace->revealVoicegroupSlot(slot);
    }
    statusBar()->showMessage(tr("Imported %1 — DirectSoundWaveData_%1 is now available to "
                                "voicegroups")
                                 .arg(dialog.sampleName()),
                             8000);
}

void MainWindow::editSampleForSlot(int slot)
{
    if (!m_project.isOpen() || !m_active || !m_active->vgSource)
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
    const SampleFormatProbe probe = SampleRegistrar::probeSampleFormat(root);
    if (!probe.ok()) {
        QMessageBox::warning(this, tr("Edit Sample"), probe.refusal);
        return;
    }
    const QString wavPath = probe.samplesDir + QStringLiteral("/%1.wav").arg(name);
    if (!QFile::exists(wavPath)) {
        QMessageBox::warning(this, tr("Edit Sample"),
                             tr("%1.wav does not exist in sound/direct_sound_samples — only "
                                "samples with a .wav source can be edited here.")
                                 .arg(name));
        return;
    }

    // Provenance: reopen from the sidecar's hi-res source while it still
    // checks out; otherwise the committed 8-bit .wav (the project is
    // canonical without the sidecar — still crop/loop-editable).
    ImportedSample sample;
    SampleSidecar sidecar;
    bool fromSource = false; // decoding the original hi-res source
    bool haveParams = false; // sidecar params apply to that source
    QString error;
    if (SampleRegistrar::readSampleSidecar(root, name, &sidecar)) {
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
    if (!fromSource) {
        QFile wavFile(wavPath);
        if (!wavFile.open(QIODevice::ReadOnly) ||
            !importAudioBytes(wavFile.readAll(), wavPath, &sample, &error)) {
            QMessageBox::warning(this, tr("Edit Sample"), tr("%1: %2").arg(wavPath, error));
            return;
        }
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

    // Write-through commit: overwrite the .wav in place; the registration
    // block already exists and stays untouched.
    if (!SampleRegistrar::updateSample(root, name, dialog.wavBytes(), &error)) {
        QMessageBox::warning(this, tr("Edit Sample"), error);
        return;
    }
    if (fromSource) {
        sidecar.params = dialog.document()->params();
        QString sidecarError;
        if (!SampleRegistrar::writeSampleSidecar(root, name, sidecar, &sidecarError))
            statusBar()->showMessage(
                tr("Sample saved, but saving its edit history failed: %1").arg(sidecarError), 8000);
    } else {
        // The session came from the committed bytes, which were just
        // replaced — a stale sidecar would misdescribe them on the next
        // reopen (the committed .wav is its own provenance now).
        SampleRegistrar::removeSampleSidecar(root, name);
    }
    invalidateVgCatalog();
    updateVoicegroupBrowser();
    // The loaded voicegroup decoded the old .wav at load time; reload so the
    // edit is audible without reopening the song.
    if (m_active && m_active->vgSource)
        reloadVoicegroupPreview(*m_active, slot);
    statusBar()->showMessage(tr("Saved %1 — the ROM's .bin recompiles on the next build").arg(name),
                             8000);
}

void MainWindow::finishCreateSong(const SmfFile &smf, const QString &label, const QString &constant,
                                  const QString &player, const SongCfg &cfg,
                                  const QString &newVoicegroup)
{
    QString error;
    // The voicegroup first: the song's -G already points at it, so nothing
    // else may be written if it can't exist. Starts as the dummy template —
    // the user configures it in the Voicegroup dock.
    if (!newVoicegroup.isEmpty()) {
        if (!VoicegroupSource::createVoicegroup(m_project.root(), newVoicegroup, QString(),
                                                QString(), &error) ||
            !VoicegroupSource::appendIncludeLine(m_project.root(), newVoicegroup, &error)) {
            QMessageBox::warning(this, tr("New Song"), error);
            return;
        }
    }

    const QString midiDir = m_project.root() + QStringLiteral("/sound/songs/midi");
    if (!smf.writeFile(midiDir + QStringLiteral("/%1.mid").arg(label), &error) ||
        !SongRegistry::writeSongFlags(midiDir, label, SongRegistry::mergeCfgFlags(cfg), &error)) {
        QMessageBox::warning(this, tr("New Song"), error);
        return;
    }
    int songId = -1;
    if (!SongRegistry::registerSong(m_project.root(), label, constant, player, &error, &songId)) {
        // Keep the chosen constant/player so Register Song can retry later;
        // the song shows a badge in the browser until then.
        SongRegistry::saveRegistrationMeta(m_project.root(), label, constant, player);
        QMessageBox::warning(this, tr("New Song"),
                             tr("Wrote %1/%2.mid, but registering it failed: %3\n"
                                "Use File → Register Song to retry.")
                                 .arg(midiDir, label, error));
    } else {
        SongRegistry::clearRegistrationMeta(m_project.root(), label);
        QString message =
            tr("Created and registered %1 as %2 (song ID %3)").arg(label, constant).arg(songId);
        if (!newVoicegroup.isEmpty())
            message += tr(" — configure its new voicegroup in the Voicegroup dock");
        statusBar()->showMessage(message, 8000);
    }

    reloadProject();
    // The fresh song opens in its own tab, next to whatever is being worked
    // on.
    loadSongByLabel(label, /*newTab=*/true);
}

void MainWindow::registerLoadedSong()
{
    if (m_active && m_active->songId >= 0 && m_active->songId < m_project.songs().size())
        registerSongById(m_active->songId);
}

void MainWindow::registerSongById(int songId)
{
    if (songId < 0 || songId >= m_project.songs().size())
        return;
    const SongInfo song = m_project.songs().at(songId);
    const QString constant =
        song.constant.isEmpty() ? SongRegistry::constantForLabel(song.label) : song.constant;
    const QString player = song.player.isEmpty() ? QStringLiteral("MUSIC_PLAYER_BGM") : song.player;
    QString error;
    int newId = -1;
    if (!SongRegistry::registerSong(m_project.root(), song.label, constant, player, &error,
                                    &newId)) {
        QMessageBox::warning(this, tr("Register Song"), error);
        return;
    }
    SongRegistry::clearRegistrationMeta(m_project.root(), song.label);
    statusBar()->showMessage(
        tr("Registered %1 as %2 (song ID %3)").arg(song.label, constant).arg(newId), 8000);
    // The open tab keeps its document; only the registry-derived state
    // (badge, song ids) needs refreshing. Ids may shift in the reload, so
    // the action refresh matches by label.
    reloadProject();
    if (m_active && m_active->doc.label() == song.label)
        m_registerAction->setEnabled(false);
}

void MainWindow::deleteSongById(int songId)
{
    if (songId < 0 || songId >= m_project.songs().size())
        return;
    const SongInfo song = m_project.songs().at(songId);
    const QString constant =
        song.constant.isEmpty() ? SongRegistry::constantForLabel(song.label) : song.constant;
    const RemovalPlan plan = SongRegistry::makeRemovalPlan(m_project.root(), song.label, constant);
    if (plan.tableIndex == 0) {
        QMessageBox::warning(this, tr("Delete Song"),
                             tr("%1 is the first song_table.inc entry (song ID 0), the engine's "
                                "fallback song — it cannot be deleted.")
                                 .arg(song.label));
        return;
    }
    const QString vgName =
        SongRegistry::deletableVoicegroup(m_project.root(), m_project.songs(), song.label);

    QMessageBox box(this);
    box.setWindowTitle(tr("Delete Song"));
    box.setIcon(QMessageBox::Warning);
    box.setText(tr("Delete %1?").arg(song.label));
    QStringList details;
    details << tr("• Its .mid moves to .porydaw/trash/ (recoverable)");
    QStringList files;
    if (plan.tableIndex >= 0)
        files << QStringLiteral("song_table.inc");
    if (plan.inSongsH)
        files << QStringLiteral("songs.h");
    if (plan.inLdScript)
        files << QStringLiteral("ld_script.ld");
    if (plan.inCharmap)
        files << QStringLiteral("charmap.txt");
    if (plan.inDebugMenu)
        files << QStringLiteral("src/debug.c");
    if (song.hasCfg)
        files << QStringLiteral("midi.cfg / songs.mk");
    if (!files.isEmpty())
        details << tr("• Its lines are removed from %1").arg(files.join(QStringLiteral(", ")));
    if (plan.tableIndex > 0 && !plan.lastEntry)
        details << tr("• Its song_table.inc entry becomes a reusable free slot, "
                      "so no other song's ID changes");
    box.setInformativeText(details.join(QLatin1Char('\n')));
    QCheckBox *vgBox = nullptr;
    if (!vgName.isEmpty()) {
        vgBox = new QCheckBox(tr("Also delete voicegroup %1 (used only by this song)")
                                  .arg(SongRegistry::voicegroupDisplayName(song.cfg.voicegroupArg)),
                              &box);
        vgBox->setChecked(true);
        box.setCheckBox(vgBox);
    }
    QPushButton *del = box.addButton(tr("Delete"), QMessageBox::DestructiveRole);
    box.addButton(QMessageBox::Cancel);
    box.setDefaultButton(QMessageBox::Cancel);
    box.exec();
    if (box.clickedButton() != del)
        return;

    QString error;
    if (!performSongDeletion(song, vgBox && vgBox->isChecked() ? vgName : QString(), &error)) {
        QMessageBox::warning(this, tr("Delete Song"), error);
        return;
    }
    statusBar()->showMessage(
        tr("Deleted %1 — its .mid is recoverable from .porydaw/trash/").arg(song.label), 8000);
}

bool MainWindow::performSongDeletion(const SongInfo &song, const QString &deleteVoicegroupName,
                                     QString *error)
{
    const QString root = m_project.root();
    const QString constant =
        song.constant.isEmpty() ? SongRegistry::constantForLabel(song.label) : song.constant;
    // Re-checked here so the harness path can't slip past the dialog's guard.
    const RemovalPlan plan = SongRegistry::makeRemovalPlan(root, song.label, constant);
    if (plan.tableIndex == 0) {
        if (error)
            *error = tr("%1 is the engine's fallback song (song ID 0) and cannot "
                        "be deleted.")
                         .arg(song.label);
        return false;
    }

    // The song's tab goes first: unsaved edits belong to the song being
    // deleted, and closing re-binds (or unloads) the audio engine before the
    // files disappear underneath it.
    if (SongSession *session = sessionForLabel(song.label)) {
        destroySession(session);
        persistOpenTabs();
    }

    QStringList problems;
    QString err;
    const QString midiDir = root + QStringLiteral("/sound/songs/midi");
    const QString midPath = midiDir + QStringLiteral("/%1.mid").arg(song.label);
    if (QFile::exists(midPath)) {
        Sidecar::ensureDir(root, QStringLiteral("trash"));
        QString target = root + QStringLiteral("/.porydaw/trash/%1.mid").arg(song.label);
        for (int n = 2; QFile::exists(target); n++)
            target = root + QStringLiteral("/.porydaw/trash/%1-%2.mid").arg(song.label).arg(n);
        if (!QFile::rename(midPath, target))
            problems << tr("Could not move %1 to %2").arg(midPath, target);
    }
    // mid2agb's generated assembly, stale once the .mid is gone.
    QFile::remove(midiDir + QStringLiteral("/%1.s").arg(song.label));

    if (!SongRegistry::removeSongFlags(midiDir, song.label, &err))
        problems << err;
    if (!SongRegistry::unregisterSong(root, song.label, constant, &err))
        problems << err;
    SongRegistry::removeSongSidecar(root, song.label);
    if (!deleteVoicegroupName.isEmpty() &&
        !VoicegroupSource::deleteVoicegroup(root, deleteVoicegroupName, &err))
        problems << err;

    reloadProject(); // also rebuilds the browser and drops the vg catalog
    if (!problems.isEmpty()) {
        if (error)
            *error = problems.join(QLatin1Char('\n'));
        return false;
    }
    return true;
}

void MainWindow::reloadProject()
{
    QString error;
    if (!m_project.reload(&error)) {
        QMessageBox::warning(this, tr("Reload Project"), error);
        return;
    }
    populateSongList();
    refreshSessionSongIds();
    invalidateVgCatalog();
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
    if (!session || !session->voicegroup) {
        m_workspace->clearVoicegroupPresentation();
        updateVgDockTitle();
        return;
    }

    const VgCatalog &catalog = vgCatalog();
    WorkspaceUi::VoicegroupPresentation presentation;
    presentation.voicegroup = session->voicegroup;
    presentation.source = session->vgSource.get();
    presentation.currentArg = session->doc.cfg().voicegroupArg.isEmpty()
                                  ? QStringLiteral("_dummy")
                                  : session->doc.cfg().voicegroupArg;
    presentation.choices = catalog.groupArgs;
    presentation.sampleSymbols = catalog.directSound;
    presentation.waveSymbols = catalog.progWave;
    presentation.keysplits = catalog.keysplits;
    presentation.drumkits = catalog.drumkits;
    presentation.adsrDefaults = catalog.typicalAdsr;
    presentation.synths = catalog.synths;
    presentation.pendingSynths = m_pendingSynths;
    presentation.usedVoices = m_workspace->viewFor(*session).usedVoices();
    presentation.mintSynth = [this](const VgSynthDesc &desc) -> QString {
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
        // Param-named; a hand-written symbol with the same name but
        // different bytes (or a plain sample) forces a suffix.
        symbol = vgSynthSymbolName(desc);
        const QString base = symbol;
        for (int i = 2; synths.find(symbol) || vgCatalog().directSound.contains(symbol); i++)
            symbol = base + QStringLiteral("_%1").arg(i);
        m_pendingSynths.insert(symbol, desc);
        return symbol;
    };
    m_workspace->setVoicegroupPresentation(std::move(presentation));
    updateVgDockTitle();
}

const MainWindow::VgCatalog &MainWindow::vgCatalog()
{
    if (!m_vgCatalog.valid) {
        const QString root = m_project.root();
        // One read of each voicegroup file and of the sound data files; the
        // per-dataset accessors would redo the same full scan per call.
        const VgCatalogScan scan = VoicegroupSource::catalogScan(root);
        m_vgCatalog.groupArgs = scan.groupArgs;
        m_vgCatalog.keysplits = scan.keysplits;
        m_vgCatalog.drumkits = scan.drumkits;
        m_vgCatalog.typicalAdsr = scan.typicalAdsr;
        const VgDirectSoundScan sound = VoicegroupSource::directSoundCatalog(root);
        m_vgCatalog.directSound = sound.directSound;
        m_vgCatalog.synths = sound.synths;
        m_vgCatalog.progWave = VoicegroupSource::progWaveSymbols(root);
        m_vgCatalog.valid = true;
    }
    return m_vgCatalog;
}

void MainWindow::invalidateVgCatalog()
{
    m_vgCatalog.valid = false;
    // The loaded instrument batch is derived from the catalog's symbol
    // lists; audition is safe across the free because AuditionSlots copies
    // the bytes into its own slot at publish time.
    m_sampleWaves.clear();
    m_progWaves.clear();
    m_keysplits.clear();
    voicegroup_free_samples(m_sampleSet);
    m_sampleSet = nullptr;
}

void MainWindow::ensureSampleSet()
{
    if (m_sampleSet || !m_project.isOpen())
        return;
    const VgCatalog &catalog = vgCatalog();
    QList<QByteArray> storage;
    const auto utf8 = [&storage](const QString &s) {
        storage.append(s.toUtf8());
        return storage.last().constData();
    };
    std::vector<const char *> samples, waves, keysplits, tables;
    for (const QString &s : catalog.directSound)
        samples.push_back(utf8(s));
    for (const QString &s : catalog.progWave)
        waves.push_back(utf8(s));
    for (const auto &pair : catalog.keysplits) {
        keysplits.push_back(utf8(pair.first));
        tables.push_back(utf8(pair.second));
    }
    m_sampleSet =
        voicegroup_load_samples(m_project.root().toLocal8Bit().constData(), samples.data(),
                                int(samples.size()), waves.data(), int(waves.size()),
                                keysplits.data(), tables.data(), int(keysplits.size()), nullptr);
    if (!m_sampleSet)
        return;
    for (int i = 0; i < catalog.directSound.size() && i < m_sampleSet->count; i++) {
        if (m_sampleSet->waves[i])
            m_sampleWaves.insert(catalog.directSound.at(i), m_sampleSet->waves[i]);
    }
    for (int i = 0; i < catalog.progWave.size() && i < m_sampleSet->progWaveCount; i++) {
        if (m_sampleSet->progWaves[i])
            m_progWaves.insert(catalog.progWave.at(i), m_sampleSet->progWaves[i]);
    }
    for (int i = 0; i < catalog.keysplits.size() && i < m_sampleSet->keysplitCount; i++) {
        const LoadedKeysplit &ks = m_sampleSet->keysplits[i];
        if (ks.subGroup && ks.table)
            m_keysplits.insert(catalog.keysplits.at(i).first, ks);
    }
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

void MainWindow::openVoicegroupSource(SongSession &session, const SongCfg &cfg)
{
    auto candidate = std::make_unique<VoicegroupSource>();
    QString error;
    if (!candidate->open(m_project.root(), cfg.voicegroupArg, &error)) {
        // VoicegroupBrowser keeps a non-owning source pointer. Release that
        // borrow before clear destroys the active session's source; the
        // caller's existing presentation update then leaves it bound to null.
        if (&session == m_active)
            m_workspace->clearVoicegroupSource();
        session.vgSource.clear();
        session.vgFileTime = QDateTime();
        statusBar()->showMessage(tr("Voicegroup editing unavailable: %1").arg(error), 8000);
        return;
    }

    const QDateTime fileTime = QFileInfo(candidate->filePath()).lastModified();
    // Do not invalidate the browser's persistent raw borrow while replacing
    // the holder's source. Callers rebind it after any requested replay.
    if (&session == m_active)
        m_workspace->clearVoicegroupSource();
    session.vgSource.replace(std::move(candidate));
    session.vgFileTime = fileTime;
}

void MainWindow::onVoiceEditRequested(int slot, const VgVoice &voice, bool structural)
{
    SongSession *session = m_active;
    if (!session || !session->vgSource)
        return;
    auto applied = [this, session](VoicegroupSource &, int slot, bool structural) {
        onVoiceEdited(*session, slot, structural);
        if (!structural && session == m_active)
            m_workspace->refreshVoicegroupSlot(slot);
        updateTabTitle(*session);
        if (session == m_active)
            updateWindowTitle();
    };
    auto command =
        makeUndoableVoicegroupEdit(session->vgSource, slot, voice, structural, std::move(applied));
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
        ToneData *tone = nullptr;
        if (session.voicegroup && slot >= 0 && slot < VOICEGROUP_SIZE)
            tone = &session.voicegroup->voices[slot];
        session.vgSource->applyScalarsToToneData(slot, tone);
        // Synth param edits are scalar pokes too: the descriptor bytes are
        // patched straight into the loaded tone (pending definitions have
        // nothing on disk to reload from). The poke can rename the voice
        // (param-named symbols), which track headers display — repaint.
        if (applyPendingSynthTones(session, session.voicegroup))
            m_workspace->viewFor(session).update();
        // Playing tracks hold a copy of their instrument; refresh so the
        // edit is heard from the next note without a pause/play cycle.
        if (&session == m_active && m_audioOk)
            m_audio.refreshVoices();
    }
    updateVgDockTitle();
    updateTabTitle(session);
}

void MainWindow::reloadVoicegroupPreview(SongSession &session, int keepSlot)
{
    const QString previewDir = m_project.root() + QStringLiteral("/.porydaw/vgpreview");
    QDir().mkpath(previewDir);
    {
        QFile out(previewDir + QLatin1Char('/') + session.vgSource->loadName() +
                  QStringLiteral(".inc"));
        if (!out.open(QIODevice::WriteOnly)) {
            statusBar()->showMessage(tr("Cannot write voicegroup preview file."), 8000);
            return;
        }
        out.write(session.vgSource->renderPreview());
    }
    // The config's voicegroup paths are searched before the project's own
    // (voicegroup_loader.c discovery), so the preview file shadows the real
    // one while samples and keysplits still resolve from the project.
    VoicegroupLoaderConfig config;
    std::memset(&config, 0, sizeof(config));
    std::strncpy(config.voicegroupPaths[0], ".porydaw/vgpreview", VG_MAX_PATH_LEN - 1);
    config.voicegroupPathCount = 1;
    LoadedVoiceGroup *vg =
        voicegroup_load(m_project.root().toLocal8Bit().constData(),
                        session.vgSource->loadName().toLocal8Bit().constData(), &config);
    if (!vg) {
        statusBar()->showMessage(
            tr("Edited voicegroup failed to load — keeping the previous sound."), 8000);
        return;
    }
    swapVoicegroup(session, vg, keepSlot);
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
    SongView &view = m_workspace->viewFor(session);
    view.setVoicegroup(nullptr);
    if (&session == m_active) {
        m_workspace->setVoicegroup(nullptr);
        if (m_audioOk)
            m_audio.updateVoicegroup(vg);
    }
    if (session.voicegroup)
        voicegroup_free(session.voicegroup);
    session.voicegroup = vg;
    view.setVoicegroup(vg);
    if (&session == m_active) {
        updateVoicegroupBrowser();
        m_workspace->selectVoicegroupSlot(keepSlot);
    }
}

void MainWindow::cleanupVgPreview()
{
    if (!m_project.isOpen())
        return;
    QDir(m_project.root() + QStringLiteral("/.porydaw/vgpreview")).removeRecursively();
}

void MainWindow::updateVgDockTitle()
{
    const bool dirty = m_active && m_active->vgSource && m_active->vgSource->dirty();
    m_workspace->setVoicegroupDirty(dirty);
}

void MainWindow::newVoicegroup()
{
    if (!m_project.isOpen())
        return;
    if (!QDir(m_project.root() + QStringLiteral("/sound/voicegroups")).exists()) {
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
    form->addRow(buttons);
    if (dialog.exec() != QDialog::Accepted)
        return;

    const QString name = nameEdit->text().trimmed();
    if (name.isEmpty())
        return;
    if (vgCatalog().groupArgs.contains(QStringLiteral("_") + name)) {
        QMessageBox::warning(this, tr("New Voicegroup"),
                             tr("A voicegroup named %1 already exists.").arg(name));
        return;
    }

    const QString copyFrom = sourceCombo->currentData().toString();
    const QString sectionLabel =
        (!copyFrom.isEmpty() && activeSource && copyFrom == activeSource->filePath())
            ? activeSource->sectionLabel()
            : QString();
    QString error;
    if (!VoicegroupSource::createVoicegroup(m_project.root(), name, copyFrom, sectionLabel,
                                            &error) ||
        !VoicegroupSource::appendIncludeLine(m_project.root(), name, &error)) {
        QMessageBox::warning(this, tr("New Voicegroup"), error);
        return;
    }
    invalidateVgCatalog();
    updateVoicegroupBrowser(); // the selector's choices now include it
    if (m_active) {
        // Assign it to the current song right away — the same undoable cfg
        // edit the selector makes; onDocumentChanged performs the swap.
        SongCfg cfg = m_active->doc.cfg();
        cfg.voicegroupArg = QStringLiteral("_") + name;
        m_active->doc.setCfg(cfg);
        statusBar()->showMessage(tr("Created sound/voicegroups/%1.inc and assigned it to %2 "
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
}

bool MainWindow::maybeSaveSession(SongSession &session)
{
    // Voicegroup edits count as the song's unsaved changes: to the user the
    // song and its voicegroup are one document (a normally-clean undo stack
    // can still leave the voicegroup dirty when a save was refused mid-way).
    if (!session.isDirty())
        return true;
    const bool vgDirty = session.vgSource && session.vgSource->dirty();
    // Show the tab being asked about: Save/Discard for edits the user
    // can't see is a data-loss trap.
    if (&session != m_active)
        activateSession(&session);
    const auto choice = QMessageBox::question(
        this, tr("Unsaved Changes"),
        vgDirty ? tr("%1 has unsaved changes (including voicegroup edits). Save them?")
                      .arg(session.doc.label())
                : tr("%1 has unsaved changes. Save them?").arg(session.doc.label()),
        QMessageBox::Save | QMessageBox::Discard | QMessageBox::Cancel, QMessageBox::Save);
    if (choice == QMessageBox::Cancel)
        return false;
    if (choice == QMessageBox::Save)
        return saveSession(session);
    return true;
}

void MainWindow::saveViewState(SongSession &session)
{
    if (session.doc.label().isEmpty())
        return;
    ViewSidecar::save(m_project.root(), session.doc.label(),
                      m_workspace->sessionViewState(session));
}

void MainWindow::updateWindowTitle()
{
    const QString project = m_project.isOpen() ? QDir(m_project.root()).dirName() : QString();
    if (m_active) {
        setWindowTitle(QStringLiteral("%1[*] — %2 — porydaw").arg(m_active->doc.label(), project));
        setWindowModified(m_active->isDirty());
    } else {
        setWindowTitle(project.isEmpty() ? QStringLiteral("porydaw")
                                         : QStringLiteral("%1 — porydaw").arg(project));
        setWindowModified(false);
    }
}

void MainWindow::closeEvent(QCloseEvent *event)
{
    // Every dirty tab gets its prompt; a Cancel keeps the window open
    // (Saves answered before it have already written, as with any
    // save-all).
    if (!promptToSaveAllSessions()) {
        event->ignore();
        return;
    }
    for (const auto &session : m_sessions)
        saveViewState(*session);
    cleanupVgPreview();
    if (m_persistSession) {
        QSettings settings;
        settings.setValue(QStringLiteral("windowGeometry"), saveGeometry());
        settings.setValue(QStringLiteral("windowState"), saveState());
        const WorkspaceUi::SongFilters filters = m_workspace->songFilters();
        settings.setValue(QStringLiteral("songFilterText"), filters.search);
        settings.setValue(QStringLiteral("songFilterSort"), filters.sortIndex);
        settings.setValue(QStringLiteral("songFilterCategory"), filters.categoryPrefix);
    }
    event->accept();
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
    m_workspace->setTransportTimeText(text);
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
    const bool songLoaded = m_audioOk && m_active && m_audio.songLoaded();
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
    SongView &view = m_workspace->viewFor(*m_active);
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

void MainWindow::startPlayback(bool fromEditCursor)
{
    if (!m_audioOk || !m_active || !m_audio.songLoaded())
        return;
    const bool seekToCursor = fromEditCursor || m_audio.transport() == Transport::Stopped;
    uint64_t target = 0;
    if (seekToCursor) {
        const SongView &view = m_workspace->viewFor(*m_active);
        target = m_audio.timeline()->sampleForTick(view.editCursorTick());
        m_audio.seek(target);
    }
    m_audio.play();
    updateTransportActions();
    synchronizePlayhead();
    // The seek lands within one audio period; show its target now rather
    // than the stale engine playhead synchronizePlayhead just read.
    if (seekToCursor)
        m_workspace->viewFor(*m_active).setPlayheadSample(target, true);
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
    const bool loaded = m_audioOk && m_audio.songLoaded();
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
    m_workspace->setTransportSessionAvailable(m_active != nullptr);
}

void MainWindow::syncMasterVolumeControl()
{
    const bool loaded = m_active != nullptr;
    m_workspace->setTransportMasterVolume(
        loaded ? m_active->doc.cfg().masterVolume : SongCfg().masterVolume, loaded);
}

void MainWindow::syncScaleControls(SongSession *session)
{
    if (session != m_active)
        return;
    if (session) {
        const SongView &view = m_workspace->viewFor(*session);
        m_workspace->setTransportScaleState(view.scaleRoot(), view.scaleId(), view.scaleHighlight(),
                                            view.scaleFold());
    } else {
        m_workspace->setTransportScaleState(0, porydaw_scale::displayOrder()[0], false, false);
    }
}

QString MainWindow::formatTime(uint64_t samples) const
{
    const double seconds = double(samples) / m_audio.sampleRate();
    const int mins = int(seconds) / 60;
    const int secs = int(seconds) % 60;
    const int tenths = int(seconds * 10) % 10;
    return QStringLiteral("%1:%2.%3").arg(mins).arg(secs, 2, 10, QLatin1Char('0')).arg(tenths);
}
