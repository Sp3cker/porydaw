#include "ui/workspaceui.h"

#include <QAction>
#include <QDockWidget>
#include <QLabel>
#include <QMainWindow>
#include <QMenu>
#include <QSettings>
#include <QSignalBlocker>
#include <QStyle>
#include <QTabBar>
#include <QTabWidget>

#include <algorithm>

#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songlistpanel.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/transportbar.h"

namespace {

const QString kLastProjectDirKey = QStringLiteral("lastProjectDir");
const QString kLastOpenSongsKey = QStringLiteral("lastOpenSongs");
const QString kLastSongLabelKey = QStringLiteral("lastSongLabel");

} // namespace

WorkspaceUi::WorkspaceUi(QMainWindow &host) : QObject(&host), m_host(host)
{
    buildUi();

    // The one QSettings read this class performs: the saved workspace recipe
    // for the startup placeholder tabs. ProjectWorkspace reads the same keys
    // independently and queues the startup open.
    QSettings settings;
    m_startRecipe = normalizeSavedRecipe(settings.value(kLastProjectDirKey).toString(),
                                         settings.value(kLastOpenSongsKey).toStringList(),
                                         settings.value(kLastSongLabelKey).toString());
    if (!m_startRecipe.projectPath.isEmpty()) {
        for (const SongName &name : m_startRecipe.orderedSongs) {
            SongTab *tab = createTab(name, name.value(), /*activate=*/false);
            m_startupPlaceholders.insert(tab->name());
        }
        SongTab *toSelect = m_startRecipe.selected ? songTabFor(*m_startRecipe.selected) : nullptr;
        if (!toSelect && !m_tabPages.empty())
            toSelect = m_tabPages.front().get();
        if (toSelect)
            selectTab(toSelect);
    } else {
        m_awaitingStartupOpen = false;
    }
    updateOpenGate();
}

WorkspaceUi::~WorkspaceUi()
{
    // The browser borrows the presentation copy; detach it before the
    // member dies.
    m_voicegroupBrowser->setSource(nullptr, {}, {}, {}, {});
    m_tabs->blockSignals(true);
    m_tabPages.clear();
    m_selectedTab = nullptr;
}

void WorkspaceUi::buildUi()
{
    m_transport = new TransportBar(&m_host);
    m_host.addToolBar(m_transport);
    m_host.addAction(m_transport->playPauseAction());
    connect(m_transport, &TransportBar::goToStartRequested, this, &WorkspaceUi::goToStartRequested);
    connect(m_transport, &TransportBar::playRequested, this, &WorkspaceUi::playRequested);
    connect(m_transport, &TransportBar::playPauseRequested, this, &WorkspaceUi::playPauseRequested);
    connect(m_transport, &TransportBar::pauseRequested, this, &WorkspaceUi::pauseRequested);
    connect(m_transport, &TransportBar::stopRequested, this, &WorkspaceUi::stopRequested);
    connect(m_transport, &TransportBar::loopEnabledChanged, this, &WorkspaceUi::loopEnabledChanged);
    connect(m_transport, &TransportBar::resonanceSuppressionChanged, this,
            &WorkspaceUi::resonanceSuppressionChanged);
    connect(m_transport, &TransportBar::masterVolumeChanged, this,
            &WorkspaceUi::masterVolumeChanged);
    connect(m_transport, &TransportBar::outputVolumeChanged, this,
            &WorkspaceUi::outputVolumeChanged);
    connect(m_transport, &TransportBar::scaleRootChanged, this, &WorkspaceUi::scaleRootChanged);
    connect(m_transport, &TransportBar::scaleIdChanged, this, &WorkspaceUi::scaleIdChanged);
    connect(m_transport, &TransportBar::scaleHighlightChanged, this,
            &WorkspaceUi::scaleHighlightChanged);
    connect(m_transport, &TransportBar::scaleFoldChanged, this, &WorkspaceUi::scaleFoldChanged);
    connect(m_transport, &TransportBar::followPlayheadChanged, this, [this](bool enabled) {
        setFollowPlayhead(enabled);
        emit followPlayheadChanged(enabled);
    });
    setFollowPlayhead(m_followPlayhead);

    const auto chromeHeight = ::layout::chromeRowHeight(
        m_host.font(), m_host.style()->pixelMetric(QStyle::PM_SmallIconSize));
    const auto installDockTitle = [chromeHeight](QDockWidget *dock) {
        auto *title = new QLabel(dock->windowTitle(), dock);
        title->setAlignment(Qt::AlignLeft | Qt::AlignVCenter);
        title->setContentsMargins(::layout::space(::layout::Space::Two), 0,
                                  ::layout::space(::layout::Space::Two), 0);
        title->setFixedHeight(chromeHeight);
        title->setAttribute(Qt::WA_TransparentForMouseEvents);
        QObject::connect(dock, &QDockWidget::windowTitleChanged, title, &QLabel::setText);
        dock->setTitleBarWidget(title);
    };

    m_songsDock = new QDockWidget(tr("Songs"), &m_host);
    m_songsDock->setObjectName(QStringLiteral("songsDock"));
    m_songsDock->setFeatures(QDockWidget::DockWidgetMovable);
    installDockTitle(m_songsDock);
    m_songList = new SongListPanel(m_songsDock);
    m_songsDock->setWidget(m_songList);
    m_host.addDockWidget(Qt::LeftDockWidgetArea, m_songsDock);

    connect(m_songList, &SongListPanel::songActivated, this,
            [this](int songId) { openSongFromList(songId, /*newTab=*/false); });
    connect(m_songList, &SongListPanel::songOpenInNewTabRequested, this,
            [this](int songId) { openSongFromList(songId, /*newTab=*/true); });
    connect(m_songList, &SongListPanel::songRegisterRequested, this, [this](int songId) {
        if (const SongInfo *song = listedSongAt(songId))
            runRegisterFlow(*song);
    });
    connect(m_songList, &SongListPanel::songDeleteRequested, this, [this](int songId) {
        if (const SongInfo *song = listedSongAt(songId))
            runDeleteFlow(*song);
    });

    m_findSongAction = new QAction(tr("Find Song"), &m_host);
    connect(m_findSongAction, &QAction::triggered, this, &WorkspaceUi::focusSongSearch);
    m_host.addAction(m_findSongAction);

    m_voicegroupDock = new QDockWidget(tr("Voicegroup"), &m_host);
    m_voicegroupDock->setObjectName(QStringLiteral("voicegroupDock"));
    m_voicegroupDock->setFeatures(QDockWidget::DockWidgetMovable);
    installDockTitle(m_voicegroupDock);
    m_voicegroupBrowser = new VoicegroupBrowser(m_voicegroupDock);
    m_voicegroupDock->setWidget(m_voicegroupBrowser);
    m_host.addDockWidget(Qt::LeftDockWidgetArea, m_voicegroupDock);
    wireBrowser();

    m_tabs = new QTabWidget(&m_host);
    m_tabs->setFocusPolicy(Qt::NoFocus);
    m_tabs->setTabsClosable(true);
    m_tabs->setMovable(true);
    m_tabs->setDocumentMode(true);
    m_tabs->tabBar()->setFixedHeight(chromeHeight);
    m_tabs->tabBar()->setFocusPolicy(Qt::NoFocus);
    connect(m_tabs, &QTabWidget::currentChanged, this, [this](int) { publishSelectedIfChanged(); });
    connect(m_tabs, &QTabWidget::tabCloseRequested, this,
            [this](int index) { requestCloseTab(tabForWidget(m_tabs->widget(index))); });
    connect(m_tabs->tabBar(), &QTabBar::tabMoved, this, [this](int, int) {
        emit sessionsReordered();
        persistTabs();
    });
    m_host.setCentralWidget(m_tabs);
}

void WorkspaceUi::wireBrowser()
{
    connect(m_voicegroupBrowser, &VoicegroupBrowser::auditionVoice, this,
            &WorkspaceUi::auditionVoiceRequested);
    connect(m_voicegroupBrowser, &VoicegroupBrowser::sampleAuditionRequested, this,
            [this](const QString &symbol, VgAuditionKind kind, const AuditionSlots::Adsr &adsr) {
                // Browse auditions lazily load the shared sample set (loop
                // badges, waves, and keysplit tables) before the engine call.
                ensureSampleSet();
                emit sampleAuditionRequested(symbol, kind, adsr);
            });
    connect(m_voicegroupBrowser, &VoicegroupBrowser::sampleAuditionStopRequested, this,
            &WorkspaceUi::sampleAuditionStopRequested);
    connect(m_voicegroupBrowser, &VoicegroupBrowser::voiceEditRequested, this,
            [this](int slot, const VgVoice &voice, bool) { submitPickerEdit(slot, voice); });
    connect(m_voicegroupBrowser, &VoicegroupBrowser::newVoicegroupRequested, this,
            &WorkspaceUi::runCreateVoicegroupFlow);
    connect(m_voicegroupBrowser, &VoicegroupBrowser::newSampleRequested, this,
            [this](int slot) { runImportFlow(slot); });
    connect(m_voicegroupBrowser, &VoicegroupBrowser::editSampleRequested, this,
            [this](int slot) { runEditSampleFlow(slot); });
    connect(m_voicegroupBrowser, &VoicegroupBrowser::voicegroupChangeRequested, this,
            [this](const QString &arg) {
                SongTab *const tab = m_selectedTab;
                if (!tab || !tab->isReady())
                    return;
                const SongCfg cfg = tab->document().cfg();
                if (arg == cfg.voicegroupArg ||
                    (cfg.voicegroupArg.isEmpty() && arg == QLatin1String("_dummy")))
                    return;
                SongCfg changed = cfg;
                changed.voicegroupArg = arg;
                tab->document().setCfg(changed);
            });
}

void WorkspaceUi::wireTab(SongTab *tab)
{
    connect(tab, &SongTab::edited, this, [this, tab] { onTabEdited(tab); });
    connect(tab, &SongTab::timelineChanged, this, [this, tab] {
        if (tab == m_selectedTab)
            emit selectedSongTimelineChanged();
    });

    SongView &view = tab->view();
    connect(&view, &SongView::auditionNote, this, [this, tab](int track, int key, int velocity) {
        if (tab == m_selectedTab)
            emit auditionNoteRequested(uint8_t(track), uint8_t(key), uint8_t(velocity));
    });
    connect(&view, &SongView::auditionNoteTimed, this,
            [this, tab](int track, int key, int velocity, quint32 durationSamples) {
                if (tab == m_selectedTab)
                    emit auditionNoteTimedRequested(uint8_t(track), uint8_t(key), uint8_t(velocity),
                                                    durationSamples);
            });
    connect(&view, &SongView::auditionVoice, this, [this, tab](int voice, int key, int velocity) {
        if (tab == m_selectedTab)
            emit auditionVoiceRequested(uint8_t(voice), uint8_t(key), uint8_t(velocity));
    });
    connect(&view, &SongView::editCursorMoved, this, [this, tab](uint64_t tick) {
        if (tab == m_selectedTab)
            emit editCursorSeekRequested(tick);
    });
    connect(&view, &SongView::playPauseFromRequested, this, [this, tab](uint64_t tick) {
        if (tab == m_selectedTab)
            emit playPauseFromRequested(tick);
    });
    connect(&view, &SongView::revealVoiceRequested, this, [this](int program) {
        showVoicegroupPanel();
        m_voicegroupBrowser->revealSlot(program);
    });
    connect(&view, &SongView::eventListVisibilityChanged, this, [this, tab](bool visible) {
        if (tab == m_selectedTab)
            emit selectedTabEventListChanged(visible);
    });
    connect(&view, &SongView::editorDrawerStateChanged, this,
            [this](const EditorDrawerState &state) { setEditorDrawerState(state); });
    connect(&view, &SongView::muteMaskChanged, this, [this, tab](uint32_t mask) {
        if (tab == m_selectedTab)
            emit selectedTabMuteMaskChanged(mask);
    });
    connect(&view, &SongView::soloMaskChanged, this, [this, tab](uint32_t mask) {
        if (tab == m_selectedTab)
            emit selectedTabSoloMaskChanged(mask);
    });
    connect(&view, &SongView::scaleHighlightChanged, this,
            [this] { emit selectedSongStateChanged(); });
    connect(&view, &SongView::scaleFoldChanged, this, [this] { emit selectedSongStateChanged(); });
    connect(&view, &SongView::scaleRootChanged, this, [this] { emit selectedSongStateChanged(); });
    connect(&view, &SongView::scaleIdChanged, this, [this] { emit selectedSongStateChanged(); });
}

// ---- Chrome surface ---------------------------------------------------------

void WorkspaceUi::restoreSongFilters(const SongFilters &filters)
{
    m_songList->restoreFilters(filters.search, filters.sortIndex, filters.categoryPrefix);
}

WorkspaceUi::SongFilters WorkspaceUi::songFilters() const
{
    return {m_songList->searchText(), m_songList->sortIndex(), m_songList->categoryPrefix()};
}

void WorkspaceUi::focusSongSearch()
{
    m_songList->focusSearch();
}

void WorkspaceUi::focusSongList()
{
    m_songList->setFocus();
}

bool WorkspaceUi::isSongListed(const QString &label) const
{
    return std::any_of(
        m_state.snapshot.songs().cbegin(), m_state.snapshot.songs().cend(),
        [&label](const SongInfo &song) { return song.label == label && song.isPlayable(); });
}

qsizetype WorkspaceUi::listedSongCount() const noexcept
{
    return std::count_if(m_state.snapshot.songs().cbegin(), m_state.snapshot.songs().cend(),
                         [](const SongInfo &song) { return song.isPlayable(); });
}

void WorkspaceUi::bindFindSongShortcut(keymap::Registry &registry)
{
    registry.attach(QStringLiteral("songs.find"), m_findSongAction);
}

void WorkspaceUi::setTransportPlaybackState(PlaybackState state)
{
    const TransportBar::PlaybackState transportState = [state] {
        switch (state) {
        case PlaybackState::Unavailable:
            return TransportBar::PlaybackState::Unavailable;
        case PlaybackState::Stopped:
            return TransportBar::PlaybackState::Stopped;
        case PlaybackState::Paused:
            return TransportBar::PlaybackState::Paused;
        case PlaybackState::Playing:
            return TransportBar::PlaybackState::Playing;
        }
        return TransportBar::PlaybackState::Unavailable;
    }();
    m_transport->setPlaybackState(transportState);
}

void WorkspaceUi::setTransportSongAvailable(bool available)
{
    m_transport->setSessionAvailable(available);
}

void WorkspaceUi::setTransportTimeText(const QString &text)
{
    m_transport->setTimeText(text);
}

void WorkspaceUi::setTransportMasterVolume(int volume, bool enabled)
{
    m_transport->setMasterVolume(volume, enabled);
}

void WorkspaceUi::setTransportOutputVolume(int volume)
{
    m_transport->setOutputVolume(volume);
}

void WorkspaceUi::setTransportScaleState(int root, porydaw_scale::ScaleId scale, bool highlight,
                                         bool fold)
{
    m_transport->setScaleState(root, scale, highlight, fold);
}

void WorkspaceUi::setTransportResonanceSuppression(bool enabled)
{
    m_transport->resonanceAction()->setChecked(enabled);
}

void WorkspaceUi::triggerPlayPause()
{
    m_transport->playPauseAction()->trigger();
}

void WorkspaceUi::addFollowPlayheadActionTo(QMenu &menu)
{
    menu.addAction(m_transport->followPlayheadAction());
}

void WorkspaceUi::showVoicegroupPanel()
{
    m_voicegroupBrowser->show();
    m_voicegroupDock->show();
    m_voicegroupDock->raise();
}

void WorkspaceUi::setVelocityColorMode(bool enabled)
{
    m_velocityColorMode = enabled;
    for (const auto &tab : m_tabPages)
        tab->view().setVelocityColorMode(enabled);
}

void WorkspaceUi::setNoteNameMode(bool enabled)
{
    m_noteNameMode = enabled;
    for (const auto &tab : m_tabPages)
        tab->view().setNoteNameMode(enabled);
}

void WorkspaceUi::setFollowPlayhead(bool enabled)
{
    m_followPlayhead = enabled;
    const QSignalBlocker blocker(m_transport);
    m_transport->setFollowPlayhead(enabled);
    for (const auto &tab : m_tabPages)
        tab->view().setFollowPlayhead(enabled);
}

void WorkspaceUi::setEditorDrawerState(const EditorDrawerState &state)
{
    m_editorDrawerState = state;
    for (const auto &tab : m_tabPages)
        tab->view().applyEditorDrawerState(state);
    emit editorDrawerStateEdited(state);
}

WorkspaceUi::ChromeObservation WorkspaceUi::observeChrome() const
{
    ChromeObservation observation;
    observation.transportVisible = m_transport->isVisible();
    observation.songsVisible = m_songsDock->isVisible();
    observation.voicegroupsVisible = m_voicegroupDock->isVisible();
    observation.listedSongCount = listedSongCount();
    observation.listedVoiceCount = m_selectedTab && m_selectedTab->voicegroupLease() ? 128 : 0;
    return observation;
}

// ---- Shared helpers ---------------------------------------------------------

void WorkspaceUi::showStatus(const QString &message, int timeout)
{
    emit statusMessageRequested(message, timeout);
}

bool WorkspaceUi::projectBusy() const noexcept
{
    return m_state.state == ProjectOpenState::Loading || m_openRequested;
}

const SongInfo *WorkspaceUi::songInfoFor(const SongName &name) const
{
    for (const SongInfo &song : m_state.snapshot.songs()) {
        if (song.label == name.value())
            return &song;
    }
    return nullptr;
}

void WorkspaceUi::persistViewSidecar(SongTab *tab)
{
    if (!tab || !tab->isReady())
        return;
    // Cosmetic and best-effort: the snapshot is captured before the tab or
    // project can be torn down; no live view crosses threads. The worker
    // writes it against the project root current when the command runs, so
    // a project switch submits these before its open (FIFO keeps order).
    emit projectOperationRequested(
        ProjectOperation{SaveSidecarInput{tab->name(), tab->captureViewSnapshot()}});
}

void WorkspaceUi::setAudioSampleRate(double sampleRate)
{
    if (m_audioSampleRate == sampleRate)
        return;
    m_audioSampleRate = sampleRate;
    applySampleRateToTabs();
}

void WorkspaceUi::toggleDrawerPage(EditorDrawerPage page)
{
    SongTab *const tab = m_selectedTab;
    if (!tab || !tab->isReady())
        return;
    SongView &view = tab->view();
    if (view.eventListVisible())
        return;
    const bool hiding = view.drawerSectionVisible(page);
    view.toggleDrawerSection(page);
    QString status;
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        status =
            hiding ? QStringLiteral("Voice changes hidden") : QStringLiteral("Voice changes shown");
        break;
    case EditorDrawerPage::Velocity:
        status =
            hiding ? QStringLiteral("Velocity lane hidden") : QStringLiteral("Velocity lane shown");
        break;
    case EditorDrawerPage::Automations:
        status = hiding ? QStringLiteral("Automation lanes hidden")
                        : QStringLiteral("Automation lanes shown");
        break;
    }
    showStatus(status, 6000);
}

void WorkspaceUi::setSelectedTabEventListVisible(bool visible)
{
    SongTab *const tab = m_selectedTab;
    if (!tab || !tab->isReady())
        return;
    tab->view().setEventListVisible(visible);
}

void WorkspaceUi::cleanupPreview()
{
    if (m_state.snapshot.isOpen())
        emit projectOperationRequested(ProjectOperation{CleanupPreviewInput{}});
}

void WorkspaceUi::persistSessionViews()
{
    for (const auto &tab : m_tabPages)
        persistViewSidecar(tab.get());
}
