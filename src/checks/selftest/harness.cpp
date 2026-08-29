#include "harness.h"

#include "checks/support/asyncwait.h"
#include "mainwindow.h"

#include <cmath>

#include <QApplication>

#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/workspaceui.h"

namespace checks {
namespace {

const char *scenarioName(SelfTestScenario scenario)
{
    switch (scenario) {
    case SelfTestScenario::Timeline:
        return "selftest-timeline";
    case SelfTestScenario::Voicegroup:
        return "selftest-voicegroup";
    case SelfTestScenario::Transport:
        return "selftest-transport";
    case SelfTestScenario::Workspace:
        return "selftest-workspace";
    }
    return "selftest";
}

} // namespace

SelfTestHarness::SelfTestHarness(MainWindow &window) : m_window(window)
{
    m_window.m_persistSession = false;
}

int SelfTestHarness::run(MainWindow &window, SelfTestScenario scenario, const QString &projectRoot,
                         const QString &songLabel)
{
    auto harness = SelfTestHarness{window};
    if (!harness.openSong(projectRoot, songLabel)) {
        qWarning("%s: FAIL", scenarioName(scenario));
        return 1;
    }
    auto succeeded = false;
    switch (scenario) {
    case SelfTestScenario::Timeline:
        succeeded = harness.runTimelineScenario();
        break;
    case SelfTestScenario::Voicegroup:
        succeeded = harness.runVoicegroupScenario();
        break;
    case SelfTestScenario::Transport:
        succeeded = harness.runTransportScenario();
        break;
    case SelfTestScenario::Workspace:
        succeeded = harness.runWorkspaceScenario();
        break;
    }
    if (succeeded)
        qInfo("%s: PASS", scenarioName(scenario));
    else
        qWarning("%s: FAIL", scenarioName(scenario));
    return succeeded ? 0 : 1;
}

bool SelfTestHarness::openSong(const QString &projectRoot, const QString &songLabel)
{
    if (!m_window.m_audioOk) {
        qWarning("selftest: audio initialization failed");
        return false;
    }
    if (!m_window.m_audio.usingNullBackend() ||
        m_window.m_audio.backendName() != QStringLiteral("Null")) {
        qWarning("selftest: expected Null audio backend, got '%s'",
                 qUtf8Printable(m_window.m_audio.backendName()));
        return false;
    }
    qInfo("selftest: backend=%s rate=%d period=%dx%d frames",
          qUtf8Printable(m_window.m_audio.backendName()), int(m_window.m_audio.sampleRate()),
          m_window.m_audio.periodCount(), m_window.m_audio.periodSizeFrames());
    m_window.m_workspace->requestProjectOpenAt(projectRoot);
    if (async_wait::waitUntil([] { return true; },
                              [this] {
                                  const ProjectOpenState state =
                                      m_window.m_workspace->projectState().state;
                                  return state == ProjectOpenState::Ready ||
                                         state == ProjectOpenState::Failed;
                              }) != async_wait::Result::Ready ||
        m_window.m_workspace->projectState().state != ProjectOpenState::Ready) {
        qWarning("selftest: project failed to open");
        return false;
    }
    const ProjectSnapshot &project = m_window.m_workspace->projectState().snapshot;
    m_projectRoot = project.root();
    const auto &songs = project.songs();
    const auto target =
        std::find_if(songs.cbegin(), songs.cend(),
                     [&songLabel](const SongInfo &song) { return song.label == songLabel; });
    if (target == songs.cend() || !target->isPlayable()) {
        qWarning("selftest: song '%s' not found or has no MIDI source", qUtf8Printable(songLabel));
        return false;
    }
    m_songInfo = *target;
    const auto songName = SongName::create(m_songInfo.label);
    if (!songName) {
        qWarning("selftest: invalid song label '%s'", qUtf8Printable(m_songInfo.label));
        return false;
    }
    m_window.m_workspace->requestSongOpen(*songName);
    m_tab = m_window.m_workspace->songTabFor(*songName);
    const auto loadWait =
        async_wait::waitUntil([this] { return tabIsLive(); }, [this] { return m_tab->isReady(); });
    if (loadWait != async_wait::Result::Ready) {
        const char *reason = loadWait == async_wait::Result::Destroyed
                                 ? "tab destroyed before async load completed"
                                 : "timed out waiting for SongTab::isReady()";
        qWarning("selftest: %s for '%s'", reason, qUtf8Printable(m_songInfo.label));
        return false;
    }
    if (!m_window.m_audio.songLoaded()) {
        qWarning("selftest: song failed to load into the audio engine");
        return false;
    }
    m_view = &m_tab->view();
    qInfo("selftest: loaded %s (%zu events, %d tracks)", qUtf8Printable(m_songInfo.label),
          m_window.m_audio.timeline()->events.size(), m_window.m_audio.timeline()->usedTrackCount);
    QApplication::processEvents();
    return true;
}

bool SelfTestHarness::beginObservedPlayback(uint64_t samplePosition)
{
    if (!tabIsLive() || !m_window.m_audio.songLoaded())
        return false;
    m_window.stopPlayback();
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this] {
                                  return m_window.m_audio.transport() == Transport::Stopped &&
                                         m_window.m_audio.playheadSamples() == 0;
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest: transport did not stop before playback setup");
        return false;
    }
    const auto tick =
        uint64_t(std::llround(m_window.m_audio.timeline()->tickForSample(samplePosition)));
    m_view->commitEditCursor(tick);
    const uint64_t before = m_window.m_audio.playheadSamples();
    m_window.startPlayback();
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this, before] {
                                  return m_window.m_audio.transport() == Transport::Playing &&
                                         m_window.m_audio.playheadSamples() > before;
                              },
                              3000) != async_wait::Result::Ready) {
        qWarning("selftest: callback did not advance playback");
        return false;
    }
    return true;
}

bool SelfTestHarness::closeCleanly()
{
    if (!tabIsLive())
        return true;
    if (m_window.m_workspace->selectedSongDirty()) {
        qWarning("selftest: song still dirty before closing its tab");
        return false;
    }
    m_window.stopPlayback();
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this] {
                                  return m_window.m_audio.transport() == Transport::Stopped &&
                                         m_window.m_audio.playheadSamples() == 0;
                              },
                              2000) != async_wait::Result::Ready)
        return false;
    const SongName closingSong = m_tab->name();
    m_window.m_workspace->requestCloseSelectedTab();
    if (async_wait::waitUntil(
            [] { return true; },
            [this, &closingSong] { return !m_window.m_workspace->songTabFor(closingSong); },
            2000) != async_wait::Result::Ready) {
        qWarning("selftest: clean tab did not close");
        return false;
    }
    m_tab = nullptr;
    m_view = nullptr;
    return m_window.m_workspace->openTabCount() == 0;
}

bool SelfTestHarness::tabIsLive() const
{
    return m_tab && m_window.m_workspace->songTabFor(m_tab->name()) == m_tab;
}

} // namespace checks
