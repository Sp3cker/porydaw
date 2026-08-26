#include "ui/workspaceui.h"

#include <QAction>
#include <QDockWidget>
#include <QLabel>
#include <QMainWindow>
#include <QMenu>
#include <QSignalBlocker>
#include <QStyle>
#include <QTabBar>
#include <QTabWidget>

#include <algorithm>
#include <utility>

#include "songsession.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songlistpanel.h"
#include "ui/songview.h"
#include "ui/transportbar.h"

WorkspaceUi::WorkspaceUi(QMainWindow &host) : QObject(&host), m_host(host)
{
    buildUi();
}

SongView &WorkspaceUi::attachSession(SongSession &session, const QString &title,
                                     const QString &toolTip, const ViewSidecar::Snapshot &viewState,
                                     ActivationPolicy activationPolicy)
{
    if (findView(session))
        qFatal("WorkspaceUi::attachSession: session is already attached");

    QSignalBlocker blocker(m_tabs);
    SongView *const previousView =
        m_tabs->currentWidget() ? qobject_cast<SongView *>(m_tabs->currentWidget()) : nullptr;

    auto *view = new SongView(m_tabs);
    view->setVelocityColorMode(m_velocityColorMode);
    view->setNoteNameMode(m_noteNameMode);
    view->setFollowPlayhead(m_followPlayhead);
    view->setSong(session.timeline.get(), session.voicegroup);
    view->setDocument(&session.doc);
    view->applyViewState(viewState.view);
    view->applyEditorViewState(viewState.editor);
    view->applyEditorDrawerState(m_editorDrawerState);
    m_pages.push_back(Page{&session, view});

    const int index = m_tabs->addTab(view, title);
    m_tabs->setTabToolTip(index, toolTip);
    if (activationPolicy == ActivationPolicy::Activate)
        m_tabs->setCurrentWidget(view);
    else if (previousView)
        m_tabs->setCurrentWidget(previousView);
    else
        m_tabs->setCurrentIndex(-1);

    blocker.unblock();
    publishActiveSessionIfChanged();
    return *view;
}

void WorkspaceUi::detachSession(SongSession &session)
{
    const auto page =
        std::find_if(m_pages.begin(), m_pages.end(),
                     [&session](const Page &candidate) { return candidate.session == &session; });
    if (page == m_pages.end())
        return;

    QSignalBlocker blocker(m_tabs);
    SongView *const view = page->view;
    view->setDocument(nullptr);
    view->setSong(nullptr, nullptr);
    m_pages.erase(page);

    const int index = m_tabs->indexOf(view);
    Q_ASSERT(index >= 0);
    if (index < 0)
        qFatal("WorkspaceUi::detachSession: attached view is not in tabs");
    m_tabs->removeTab(index);
    delete view;

    blocker.unblock();
    publishActiveSessionIfChanged();
}

void WorkspaceUi::detachAllSessions()
{
    QSignalBlocker blocker(m_tabs);
    std::vector<Page> pages = std::move(m_pages);
    m_pages.clear();
    for (const Page &page : pages) {
        page.view->setDocument(nullptr);
        page.view->setSong(nullptr, nullptr);
    }
    while (m_tabs->count() > 0) {
        QWidget *const page = m_tabs->widget(0);
        m_tabs->removeTab(0);
        delete page;
    }

    blocker.unblock();
    publishActiveSessionIfChanged();
}

void WorkspaceUi::activateSession(SongSession *session)
{
    SongView *view = nullptr;
    if (session) {
        view = findView(*session);
        if (!view)
            qFatal("WorkspaceUi::activateSession: session is not attached");
    }

    QSignalBlocker blocker(m_tabs);
    if (view)
        m_tabs->setCurrentWidget(view);
    else
        m_tabs->setCurrentIndex(-1);
    blocker.unblock();
    publishActiveSessionIfChanged();
}

void WorkspaceUi::requestCloseSession(SongSession &session)
{
    if (!isSessionAttached(session))
        qFatal("WorkspaceUi::requestCloseSession: session is not attached");
    emit closeSessionRequested(&session);
}

SongSession *WorkspaceUi::activeSession() const noexcept
{
    return findSessionForWidget(m_tabs->currentWidget());
}

bool WorkspaceUi::isSessionAttached(const SongSession &session) const noexcept
{
    return findView(session) != nullptr;
}

SongView &WorkspaceUi::viewFor(const SongSession &session)
{
    SongView *const view = findView(session);
    Q_ASSERT_X(view, "WorkspaceUi::viewFor", "session is not attached");
    if (!view)
        qFatal("WorkspaceUi::viewFor: session is not attached");
    return *view;
}

const SongView &WorkspaceUi::viewFor(const SongSession &session) const
{
    const SongView *const view = findView(session);
    Q_ASSERT_X(view, "WorkspaceUi::viewFor", "session is not attached");
    if (!view)
        qFatal("WorkspaceUi::viewFor: session is not attached");
    return *view;
}

qsizetype WorkspaceUi::openSessionCount() const noexcept
{
    return qsizetype(m_pages.size());
}

std::vector<SongSession *> WorkspaceUi::sessionsInDisplayOrder() const
{
    std::vector<SongSession *> sessions;
    sessions.reserve(size_t(m_tabs->count()));
    for (int index = 0; index < m_tabs->count(); ++index) {
        SongSession *const session = findSessionForWidget(m_tabs->widget(index));
        Q_ASSERT(session);
        if (!session)
            qFatal("WorkspaceUi: tab does not map to a session");
        sessions.push_back(session);
    }
    return sessions;
}

QString WorkspaceUi::sessionTitle(const SongSession &session) const
{
    const SongView &view = viewFor(session);
    const int index = m_tabs->indexOf(&view);
    Q_ASSERT(index >= 0);
    if (index < 0)
        qFatal("WorkspaceUi::sessionTitle: attached view is not in tabs");
    return m_tabs->tabText(index);
}

void WorkspaceUi::setSessionTitle(const SongSession &session, const QString &title, bool dirty,
                                  const QString &toolTip)
{
    SongView &view = viewFor(session);
    const int index = m_tabs->indexOf(&view);
    Q_ASSERT(index >= 0);
    if (index < 0)
        qFatal("WorkspaceUi::setSessionTitle: attached view is not in tabs");
    m_tabs->setTabText(index, dirty ? title + QLatin1Char('*') : title);
    m_tabs->setTabToolTip(index, toolTip);
}

ViewSidecar::Snapshot WorkspaceUi::sessionViewState(const SongSession &session) const
{
    const SongView &view = viewFor(session);
    return {view.viewState(), view.editorViewState()};
}

void WorkspaceUi::applySessionViewState(SongSession &session,
                                        const ViewSidecar::Snapshot &viewState)
{
    SongView &view = viewFor(session);
    view.applyViewState(viewState.view);
    view.applyEditorViewState(viewState.editor);
    view.applyEditorDrawerState(m_editorDrawerState);
}

void WorkspaceUi::setSongs(const QVector<SongInfo> &songs)
{
    m_songs = songs;
    m_songList->setSongs(songs);
}

void WorkspaceUi::setCurrentSong(int songId)
{
    m_songList->setCurrentSong(songId);
}

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
    return std::any_of(m_songs.cbegin(), m_songs.cend(), [&label](const SongInfo &song) {
        return song.label == label && song.isPlayable();
    });
}

qsizetype WorkspaceUi::listedSongCount() const noexcept
{
    return std::count_if(m_songs.cbegin(), m_songs.cend(),
                         [](const SongInfo &song) { return song.isPlayable(); });
}

void WorkspaceUi::bindFindSongShortcut(keymap::Registry &registry)
{
    registry.attach(QStringLiteral("songs.find"), m_findSongAction);
}

void WorkspaceUi::setTransportPlaybackState(PlaybackState state)
{
    TransportBar::PlaybackState transportState = TransportBar::PlaybackState::Unavailable;
    switch (state) {
    case PlaybackState::Unavailable:
        transportState = TransportBar::PlaybackState::Unavailable;
        break;
    case PlaybackState::Stopped:
        transportState = TransportBar::PlaybackState::Stopped;
        break;
    case PlaybackState::Paused:
        transportState = TransportBar::PlaybackState::Paused;
        break;
    case PlaybackState::Playing:
        transportState = TransportBar::PlaybackState::Playing;
        break;
    }
    m_transport->setPlaybackState(transportState);
}

void WorkspaceUi::setTransportSessionAvailable(bool available)
{
    m_transport->setSessionAvailable(available);
}

void WorkspaceUi::setTransportSongName(const QString &name)
{
    m_transport->setSongName(name);
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

void WorkspaceUi::setVoicegroupPresentation(VoicegroupPresentation &&presentation)
{
    m_voicegroupBrowser->setVoicegroup(presentation.voicegroup);
    m_voicegroupBrowser->setUsedVoices(presentation.usedVoices);
    m_voicegroupBrowser->setVoicegroupChoices(presentation.choices);
    m_voicegroupBrowser->setCurrentVoicegroupArg(presentation.currentArg);
    m_voicegroupBrowser->setSource(
        presentation.source, presentation.sampleSymbols, presentation.waveSymbols,
        presentation.keysplits, presentation.drumkits, presentation.adsrDefaults,
        presentation.synths, presentation.pendingSynths, std::move(presentation.mintSynth));
    m_hasVoicegroup = presentation.voicegroup != nullptr;
}

void WorkspaceUi::clearVoicegroupPresentation()
{
    m_voicegroupBrowser->setSource(nullptr, {}, {}, {}, {});
    m_voicegroupBrowser->setVoicegroup(nullptr);
    m_voicegroupBrowser->setUsedVoices({});
    m_hasVoicegroup = false;
}

void WorkspaceUi::setVoicegroupLoading(bool loading)
{
    m_voicegroupBrowser->setLoading(loading);
}

void WorkspaceUi::clearVoicegroupSource()
{
    m_voicegroupBrowser->setSource(nullptr, {}, {}, {}, {});
}

void WorkspaceUi::setVoicegroup(const LoadedVoiceGroup *voicegroup)
{
    m_voicegroupBrowser->setVoicegroup(voicegroup);
    m_hasVoicegroup = voicegroup != nullptr;
}
void WorkspaceUi::setVoicegroupDirty(bool dirty)
{
    m_voicegroupDock->setWindowTitle(dirty ? tr("Voicegroup*") : tr("Voicegroup"));
}

void WorkspaceUi::setVoicegroupUsedVoices(const QSet<int> &usedVoices)
{
    m_voicegroupBrowser->setUsedVoices(usedVoices);
}

void WorkspaceUi::setCurrentVoicegroupArg(const QString &arg)
{
    m_voicegroupBrowser->setCurrentVoicegroupArg(arg);
}

void WorkspaceUi::setVoicegroupSampleInfoProvider(
    std::function<SamplePickInfo(const QString &)> provider)
{
    m_voicegroupBrowser->setSampleInfoProvider(std::move(provider));
}

int WorkspaceUi::currentVoicegroupSlot() const
{
    return m_voicegroupBrowser->currentSlot();
}

void WorkspaceUi::selectVoicegroupSlot(int slot)
{
    m_voicegroupBrowser->selectSlot(slot);
}

void WorkspaceUi::revealVoicegroupSlot(int slot)
{
    m_voicegroupBrowser->revealSlot(slot);
}

void WorkspaceUi::refreshVoicegroupSlot(int slot)
{
    m_voicegroupBrowser->voiceChanged(slot);
}

void WorkspaceUi::showVoicegroupPanel()
{
    m_voicegroupDock->show();
    m_voicegroupDock->raise();
}

void WorkspaceUi::setVelocityColorMode(bool enabled)
{
    m_velocityColorMode = enabled;
    for (const Page &page : m_pages)
        page.view->setVelocityColorMode(enabled);
}

void WorkspaceUi::setNoteNameMode(bool enabled)
{
    m_noteNameMode = enabled;
    for (const Page &page : m_pages)
        page.view->setNoteNameMode(enabled);
}

void WorkspaceUi::setFollowPlayhead(bool enabled)
{
    m_followPlayhead = enabled;
    {
        const QSignalBlocker blocker(m_transport->followPlayheadAction());
        m_transport->setFollowPlayhead(enabled);
    }
    for (const Page &page : m_pages)
        page.view->setFollowPlayhead(enabled);
}

void WorkspaceUi::setEditorDrawerState(const EditorDrawerState &state)
{
    m_editorDrawerState = state;
    for (const Page &page : m_pages)
        page.view->applyEditorDrawerState(state);
}

WorkspaceUi::ChromeObservation WorkspaceUi::observeChrome() const
{
    return {
        .transportVisible = m_transport->isVisible(),
        .songsVisible = m_songsDock->isVisible(),
        .voicegroupsVisible = m_voicegroupDock->isVisible(),
        .listedSongCount = listedSongCount(),
        .listedVoiceCount = m_hasVoicegroup ? VOICEGROUP_SIZE : 0,
    };
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

    connect(m_songList, &SongListPanel::songActivated, this, &WorkspaceUi::songActivated);
    connect(m_songList, &SongListPanel::songOpenInNewTabRequested, this,
            &WorkspaceUi::songOpenInNewTabRequested);
    connect(m_songList, &SongListPanel::songRegisterRequested, this,
            &WorkspaceUi::songRegisterRequested);
    connect(m_songList, &SongListPanel::songDeleteRequested, this,
            &WorkspaceUi::songDeleteRequested);

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

    connect(m_voicegroupBrowser, &VoicegroupBrowser::auditionVoice, this,
            &WorkspaceUi::auditionVoiceRequested);
    connect(m_voicegroupBrowser, &VoicegroupBrowser::sampleAuditionRequested, this,
            &WorkspaceUi::sampleAuditionRequested);
    connect(m_voicegroupBrowser, &VoicegroupBrowser::sampleAuditionStopRequested, this,
            &WorkspaceUi::sampleAuditionStopRequested);
    connect(m_voicegroupBrowser, &VoicegroupBrowser::voiceEditRequested, this,
            &WorkspaceUi::voiceEditRequested);
    connect(m_voicegroupBrowser, &VoicegroupBrowser::newVoicegroupRequested, this,
            &WorkspaceUi::newVoicegroupRequested);
    connect(m_voicegroupBrowser, &VoicegroupBrowser::newSampleRequested, this,
            &WorkspaceUi::newSampleRequested);
    connect(m_voicegroupBrowser, &VoicegroupBrowser::editSampleRequested, this,
            &WorkspaceUi::editSampleRequested);
    connect(m_voicegroupBrowser, &VoicegroupBrowser::voicegroupChangeRequested, this,
            &WorkspaceUi::voicegroupChangeRequested);

    m_tabs = new QTabWidget(&m_host);
    m_tabs->setFocusPolicy(Qt::NoFocus);
    m_tabs->setTabsClosable(true);
    m_tabs->setMovable(true);
    m_tabs->setDocumentMode(true);
    m_tabs->tabBar()->setFixedHeight(chromeHeight);
    m_tabs->tabBar()->setFocusPolicy(Qt::NoFocus);
    connect(m_tabs, &QTabWidget::currentChanged, this,
            [this](int) { publishActiveSessionIfChanged(); });
    connect(m_tabs, &QTabWidget::tabCloseRequested, this, [this](int index) {
        SongSession *const session = findSessionForWidget(m_tabs->widget(index));
        Q_ASSERT(session);
        if (!session)
            qFatal("WorkspaceUi: close request does not map to a session");
        requestCloseSession(*session);
    });
    connect(m_tabs->tabBar(), &QTabBar::tabMoved, this,
            [this](int, int) { emit sessionsReordered(); });
    m_host.setCentralWidget(m_tabs);
}

SongView *WorkspaceUi::findView(const SongSession &session) const noexcept
{
    const auto page =
        std::find_if(m_pages.cbegin(), m_pages.cend(),
                     [&session](const Page &candidate) { return candidate.session == &session; });
    return page == m_pages.cend() ? nullptr : page->view;
}

SongSession *WorkspaceUi::findSessionForWidget(const QWidget *widget) const noexcept
{
    const auto page =
        std::find_if(m_pages.cbegin(), m_pages.cend(),
                     [widget](const Page &candidate) { return candidate.view == widget; });
    return page == m_pages.cend() ? nullptr : page->session;
}

void WorkspaceUi::publishActiveSessionIfChanged()
{
    SongSession *const session = activeSession();
    if (session == m_publishedActiveSession)
        return;
    m_publishedActiveSession = session;
    emit activeSessionChanged(session);
}
