#include "harness.h"

#include "checks/support/asyncwait.h"
#include "mainwindow.h"

#include <algorithm>
#include <cmath>

#include <QElapsedTimer>

#include "ui/songtab.h"
#include "ui/songview.h"

namespace checks {

bool SelfTestHarness::runTransportScenario()
{
    const auto waitForSettledPause = [this] {
        auto stable = QElapsedTimer{};
        auto lastSample = m_window.m_audio.playheadSamples();
        stable.start();
        return async_wait::waitUntil([this] { return tabIsLive(); },
                                     [this, &stable, &lastSample] {
                                         const uint64_t sample = m_window.m_audio.playheadSamples();
                                         if (sample != lastSample) {
                                             lastSample = sample;
                                             stable.restart();
                                         }
                                         return m_window.m_audio.transport() == Transport::Paused &&
                                                stable.elapsed() >= 100;
                                     },
                                     2000);
    };
    const SongSettings originalSettings = m_window.songSettingsFor(*m_tab);
    auto tweaked = originalSettings;
    tweaked.pcmMixer =
        tweaked.pcmMixer == M4A_PCM_MIXER_IPATIX ? M4A_PCM_MIXER_SAPPY : M4A_PCM_MIXER_IPATIX;
    tweaked.maxPcmChannels = 8;
    tweaked.pcmMixRate = 21024.0f;
    tweaked.analogFilter = !tweaked.analogFilter;
    if (!beginObservedPlayback())
        return false;
    const uint64_t beforeSettings = m_window.m_audio.playheadSamples();
    m_window.m_audio.updateSettings(tweaked);
    const auto settingsWait = async_wait::waitUntil(
        [this] { return tabIsLive(); },
        [this, &tweaked, beforeSettings] {
            return m_window.m_audio.pcmMixerMode() == tweaked.pcmMixer &&
                   m_window.m_audio.maxPcmChannels() == tweaked.maxPcmChannels &&
                   m_window.m_audio.transport() == Transport::Playing &&
                   m_window.m_audio.playheadSamples() > beforeSettings;
        },
        2000);
    const auto observedMixer = m_window.m_audio.pcmMixerMode();
    const int observedMaxPcm = m_window.m_audio.maxPcmChannels();
    const auto observedTransport = m_window.m_audio.transport();
    const uint64_t observedPlayhead = m_window.m_audio.playheadSamples();
    m_window.m_audio.updateSettings(originalSettings);
    if (settingsWait != async_wait::Result::Ready) {
        qWarning("selftest-transport: settings replacement FAILED "
                 "(mixer %d, maxPcm %d, transport %d, playhead %llu -> %llu)",
                 int(observedMixer), observedMaxPcm, int(observedTransport),
                 static_cast<unsigned long long>(beforeSettings),
                 static_cast<unsigned long long>(observedPlayhead));
        return false;
    }
    qInfo("selftest-transport: settings replacement while playing OK");
    if (!beginObservedPlayback())
        return false;
    m_window.pausePlayback();
    if (waitForSettledPause() != async_wait::Result::Ready) {
        qWarning("selftest-transport: transport did not pause");
        return false;
    }
    m_window.synchronizePlayhead();
    const uint64_t pausedSample = m_window.m_audio.playheadSamples();
    const double pausedViewTick = m_view->playheadTick();
    const double pausedEngineTick = m_window.m_audio.timeline()->tickForSample(pausedSample);
    constexpr double kPausedPlayheadToleranceTicks = 0.25;
    if (std::abs(pausedViewTick - pausedEngineTick) > kPausedPlayheadToleranceTicks) {
        qWarning("selftest-transport: paused playhead reconciliation FAILED "
                 "(view %.3f ticks, engine %.3f ticks at %llu samples)",
                 pausedViewTick, pausedEngineTick, static_cast<unsigned long long>(pausedSample));
        return false;
    }
    const MidiTimeline *const timeline = m_window.m_audio.timeline();
    const uint64_t maxTick = timeline->lengthTicks > 0 ? timeline->lengthTicks - 1 : 9600;
    const uint64_t pausedTargetTick =
        pausedViewTick >= 960.0 ? uint64_t(pausedViewTick - 480.0)
                                : std::min<uint64_t>(uint64_t(pausedViewTick + 960.0), maxTick);
    m_view->commitEditCursor(pausedTargetTick);
    const double immediateViewTick = m_view->playheadTick();
    if (std::abs(immediateViewTick - double(pausedTargetTick)) > kPausedPlayheadToleranceTicks) {
        qWarning("selftest-transport: paused edit-cursor visible playhead FAILED "
                 "(target %llu ticks, view %.3f ticks)",
                 static_cast<unsigned long long>(pausedTargetTick), immediateViewTick);
        return false;
    }
    const uint64_t pausedTargetSample = timeline->sampleForTick(pausedTargetTick);
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this, pausedTargetSample] {
                                  return m_window.m_audio.playheadSamples() == pausedTargetSample;
                              },
                              2000) != async_wait::Result::Ready) {
        const double engineTick =
            m_window.m_audio.timeline()->tickForSample(m_window.m_audio.playheadSamples());
        qWarning("selftest-transport: paused edit-cursor engine seek FAILED "
                 "(target %llu ticks, engine %.3f ticks)",
                 static_cast<unsigned long long>(pausedTargetTick), engineTick);
        return false;
    }
    qInfo("selftest-transport: paused edit-cursor seek OK");
    const uint64_t beforeResume = m_window.m_audio.playheadSamples();
    m_window.startPlayback();
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this, beforeResume] {
                                  return m_window.m_audio.transport() == Transport::Playing &&
                                         m_window.m_audio.playheadSamples() > beforeResume;
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest-transport: playback did not resume after paused seek");
        return false;
    }
    const bool originalLoopEnabled = m_window.m_audio.loopEnabled();
    m_window.m_audio.setLoopEnabled(false);
    if (!beginObservedPlayback()) {
        m_window.m_audio.setLoopEnabled(originalLoopEnabled);
        return false;
    }
    const uint64_t seekTick =
        std::min<uint64_t>(timeline->lengthTicks / 2, uint64_t(timeline->ticksPerBeat) * 16);
    const uint64_t seekSample = timeline->sampleForTick(seekTick);
    m_view->commitEditCursor(seekTick);
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this, seekSample] {
                                  return m_window.m_audio.transport() == Transport::Playing &&
                                         m_window.m_audio.playheadSamples() >= seekSample;
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest-transport: edit-cursor seek while playing FAILED");
        m_window.m_audio.setLoopEnabled(originalLoopEnabled);
        return false;
    }
    const uint64_t afterSeek = m_window.m_audio.playheadSamples();
    m_window.stopPlayback();
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this] { return m_window.m_audio.transport() == Transport::Stopped; },
                              2000) != async_wait::Result::Ready) {
        m_window.m_audio.setLoopEnabled(originalLoopEnabled);
        return false;
    }
    m_window.startPlayback();
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this, seekSample] {
                                  return m_window.m_audio.transport() == Transport::Playing &&
                                         m_window.m_audio.playheadSamples() >=
                                             seekSample +
                                                 uint64_t(m_window.m_audio.sampleRate() * 0.25);
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest-transport: play-from-cursor out of Stopped FAILED");
        m_window.m_audio.setLoopEnabled(originalLoopEnabled);
        return false;
    }
    const uint64_t afterRestart = m_window.m_audio.playheadSamples();
    m_window.pausePlayback();
    if (waitForSettledPause() != async_wait::Result::Ready) {
        m_window.m_audio.setLoopEnabled(originalLoopEnabled);
        return false;
    }
    const uint64_t pausedAt = m_window.m_audio.playheadSamples();
    m_window.startPlayback(/*fromEditCursor=*/true);
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this, seekSample, pausedAt] {
                                  const uint64_t playhead = m_window.m_audio.playheadSamples();
                                  return m_window.m_audio.transport() == Transport::Playing &&
                                         playhead >= seekSample && playhead < pausedAt;
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest-transport: Space-from-pause FAILED (cursor %.2fs, paused %.2fs, "
                 "playhead %.2fs)",
                 double(seekSample) / m_window.m_audio.sampleRate(),
                 double(pausedAt) / m_window.m_audio.sampleRate(),
                 double(m_window.m_audio.playheadSamples()) / m_window.m_audio.sampleRate());
        m_window.m_audio.setLoopEnabled(originalLoopEnabled);
        return false;
    }
    qInfo("selftest-transport: seek + stopped restart + Space-from-pause OK "
          "(seek %.2fs, first %.2fs, restart %.2fs)",
          double(seekSample) / m_window.m_audio.sampleRate(),
          double(afterSeek) / m_window.m_audio.sampleRate(),
          double(afterRestart) / m_window.m_audio.sampleRate());
    m_window.m_audio.setLoopEnabled(originalLoopEnabled);
    return closeCleanly();
}

} // namespace checks
