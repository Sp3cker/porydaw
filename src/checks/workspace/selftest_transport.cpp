#include "checks/workspace/tst_workspacesessions.h"

#include <QtTest>

#include <QElapsedTimer>
#include <QSettings>

#include <algorithm>
#include <cmath>

#include "core/miditimeline.h"
#include "mainwindow.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/workspaceui.h"

namespace {

class SettingsRestore final
{
  public:
    SettingsRestore(AudioEngine &engine, SongSettings settings)
        : m_engine(engine)
        , m_settings(std::move(settings))
    {}
    ~SettingsRestore() { m_engine.updateSettings(m_settings); }

  private:
    AudioEngine &m_engine;
    SongSettings m_settings;
};

class LoopRestore final
{
  public:
    explicit LoopRestore(AudioEngine &engine) : m_engine(engine), m_enabled(engine.loopEnabled()) {}
    ~LoopRestore() { m_engine.setLoopEnabled(m_enabled); }

  private:
    AudioEngine &m_engine;
    bool m_enabled;
};

} // namespace

WorkspaceTransportSelfTest::WorkspaceTransportSelfTest(QString projectRoot, QString songLabel)
    : m_songLabel(std::move(songLabel))
    , m_project(std::move(projectRoot))
{}

void WorkspaceTransportSelfTest::init()
{
    QSettings settings;
    settings.clear();
    settings.sync();
    QString error;
    QVERIFY2(m_project.reset(error), qPrintable(error));
}

void WorkspaceTransportSelfTest::cleanup()
{
    QSettings settings;
    settings.clear();
    settings.sync();
}

SongTab *WorkspaceTransportSelfTest::openNull(MainWindow &window, SongView *&view)
{
    window.m_persistSession = false;
    if (!window.m_audioOk || !window.m_audio.usingNullBackend() ||
        window.m_audio.backendName() != QStringLiteral("Null"))
        return nullptr;
    auto *workspace = window.m_workspace.get();
    workspace->requestProjectOpenAt(m_project.root());
    if (!workspace_test::waitForProject(*workspace))
        return nullptr;
    const std::optional<SongName> name = workspace_test::songName(m_songLabel);
    if (!name)
        return nullptr;
    SongTab *tab = workspace_test::openReady(*workspace, *name);
    if (!tab || !window.m_audio.songLoaded())
        return nullptr;
    view = &tab->view();
    return tab;
}

bool WorkspaceTransportSelfTest::startObserved(MainWindow &window, SongTab &tab, SongView &view,
                                               uint64_t samplePosition)
{
    window.stopPlayback();
    if (checks::async_wait::waitUntil(
            [&window, &tab] { return window.m_workspace->songTabFor(tab.name()) == &tab; },
            [&window] {
                return window.m_audio.transport() == Transport::Stopped &&
                       window.m_audio.playheadSamples() == 0;
            },
            2000) != checks::async_wait::Result::Ready)
        return false;
    view.commitEditCursor(
        uint64_t(std::llround(window.m_audio.timeline()->tickForSample(samplePosition))));
    const uint64_t before = window.m_audio.playheadSamples();
    window.startPlayback();
    return checks::async_wait::waitUntil(
               [&window, &tab] { return window.m_workspace->songTabFor(tab.name()) == &tab; },
               [&window, before] {
                   return window.m_audio.transport() == Transport::Playing &&
                          window.m_audio.playheadSamples() > before;
               },
               3000) == checks::async_wait::Result::Ready;
}

void WorkspaceTransportSelfTest::settingsAndSeekKeepLiveTransport()
{
    MainWindow window;
    SongView *view = nullptr;
    SongTab *tab = openNull(window, view);
    QVERIFY(tab);
    QVERIFY(view);
    const SongSettings original = window.songSettingsFor(*tab);
    SettingsRestore restoreSettings(window.m_audio, original);
    Q_UNUSED(restoreSettings);
    SongSettings changed = original;
    changed.pcmMixer =
        changed.pcmMixer == M4A_PCM_MIXER_IPATIX ? M4A_PCM_MIXER_SAPPY : M4A_PCM_MIXER_IPATIX;
    changed.maxPcmChannels = 8;
    changed.pcmMixRate = 21024.0f;
    changed.analogFilter = !changed.analogFilter;
    QVERIFY(startObserved(window, *tab, *view));
    const uint64_t beforeSettings = window.m_audio.playheadSamples();
    window.m_audio.updateSettings(changed);
    QTRY_VERIFY(window.m_audio.pcmMixerMode() == changed.pcmMixer &&
                window.m_audio.maxPcmChannels() == changed.maxPcmChannels &&
                window.m_audio.pcmMixRate() == changed.pcmMixRate &&
                window.m_audio.analogFilter() == changed.analogFilter &&
                window.m_audio.transport() == Transport::Playing &&
                window.m_audio.playheadSamples() > beforeSettings);
    window.m_audio.updateSettings(original);

    QVERIFY(startObserved(window, *tab, *view));
    window.pausePlayback();
    QElapsedTimer stable;
    stable.start();
    uint64_t lastSample = window.m_audio.playheadSamples();
    QTRY_VERIFY([&] {
        const uint64_t sample = window.m_audio.playheadSamples();
        if (sample != lastSample) {
            lastSample = sample;
            stable.restart();
        }
        return window.m_audio.transport() == Transport::Paused && stable.elapsed() >= 100;
    }());
    window.synchronizePlayhead();
    constexpr double toleranceTicks = 0.25;
    const uint64_t pausedSample = window.m_audio.playheadSamples();
    const double pausedTick = window.m_audio.timeline()->tickForSample(pausedSample);
    QVERIFY(std::abs(view->playheadTick() - pausedTick) <= toleranceTicks);
    const MidiTimeline *const timeline = window.m_audio.timeline();
    const uint64_t maxTick = timeline->lengthTicks > 0 ? timeline->lengthTicks - 1 : 9600;
    const uint64_t target = view->playheadTick() >= 960.0
                                ? uint64_t(view->playheadTick() - 480.0)
                                : (std::min)(uint64_t(view->playheadTick() + 960.0), maxTick);
    view->commitEditCursor(target);
    QVERIFY(std::abs(view->playheadTick() - double(target)) <= toleranceTicks);
    QTRY_VERIFY(
        std::abs(window.m_audio.timeline()->tickForSample(window.m_audio.playheadSamples()) -
                 double(target)) <= toleranceTicks);

    const uint64_t beforeResume = window.m_audio.playheadSamples();
    window.startPlayback();
    QTRY_VERIFY(window.m_audio.transport() == Transport::Playing &&
                window.m_audio.playheadSamples() > beforeResume);

    LoopRestore restoreLoop(window.m_audio);
    Q_UNUSED(restoreLoop);
    window.m_audio.setLoopEnabled(false);
    QVERIFY(startObserved(window, *tab, *view));
    const uint64_t seekTick =
        (std::min)(uint64_t(timeline->lengthTicks) / 2, uint64_t(timeline->ticksPerBeat) * 16);
    const uint64_t seekSample = timeline->sampleForTick(seekTick);
    view->commitEditCursor(seekTick);
    QTRY_VERIFY(window.m_audio.transport() == Transport::Playing &&
                window.m_audio.playheadSamples() >= seekSample);
    window.stopPlayback();
    QTRY_COMPARE(window.m_audio.transport(), Transport::Stopped);
    window.startPlayback();
    QTRY_VERIFY(window.m_audio.transport() == Transport::Playing &&
                window.m_audio.playheadSamples() >=
                    seekSample + uint64_t(window.m_audio.sampleRate() * 0.25));
    window.pausePlayback();
    QTRY_COMPARE(window.m_audio.transport(), Transport::Paused);
    const uint64_t pausedAt = window.m_audio.playheadSamples();
    window.startPlayback(true);
    QTRY_VERIFY([&] {
        const uint64_t sample = window.m_audio.playheadSamples();
        return window.m_audio.transport() == Transport::Playing && sample >= seekSample &&
               sample < pausedAt;
    }());

    window.stopPlayback();
    QTRY_COMPARE(window.m_audio.transport(), Transport::Stopped);
    const SongName name = tab->name();
    window.m_workspace->requestCloseSelectedTab();
    QTRY_VERIFY(!window.m_workspace->songTabFor(name));
    QCOMPARE(window.m_workspace->openTabCount(), qsizetype(0));
}
