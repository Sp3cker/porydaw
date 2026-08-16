#include "audioengine.h"
#include "audio/trackactivitylevel.h"

#include <QFile>

#include <algorithm>

#include "miniaudio.h"

#ifdef __linux__
#include <dlfcn.h>

namespace {

// Install a no-op error handler into libasound to suppress the wall of
// "cannot find card '0'" messages ALSA prints on WSL and other systems
// without hardware audio. Uses dlopen so we don't link libasound explicitly.
void alsaErrorNoop(const char *, int, const char *, int, const char *, ...) {}

void suppressAlsaErrors()
{
    void *lib = dlopen("libasound.so.2", RTLD_LAZY);
    if (!lib)
        return;
    typedef void (*ErrFn)(const char *, int, const char *, int, const char *, ...);
    typedef void (*SetFn)(ErrFn);
    SetFn setfn;
    *reinterpret_cast<void **>(&setfn) = dlsym(lib, "snd_lib_error_set_handler");
    if (setfn)
        setfn(alsaErrorNoop);
    // Leave the handle open so the handler stays installed when miniaudio
    // later opens libasound itself (same shared library instance).
}

bool runningUnderWsl()
{
    QFile osrelease(QStringLiteral("/proc/sys/kernel/osrelease"));
    if (!osrelease.open(QIODevice::ReadOnly))
        return false;
    return osrelease.readAll().toLower().contains("microsoft");
}

} // namespace
#endif

namespace {
// Silence to render after the last event before auto-stopping (no loop).
constexpr double kTailSeconds = 3.0;

void publishMaximum(std::atomic<uint32_t> &pending, TrackActivityLevel level)
{
    auto observed = pending.load(std::memory_order_relaxed);
    for (;;) {
        const auto desired = packedActivity(maxLevel(unpackedActivity(observed), level));
        if (desired == observed ||
            pending.compare_exchange_weak(observed, desired, std::memory_order_relaxed))
            return;
    }
}
} // namespace

AudioEngine::AudioEngine() = default;

AudioEngine::~AudioEngine()
{
    shutdown();
}

bool AudioEngine::init(QString *error)
{
#ifdef __linux__
    suppressAlsaErrors();
    // Try PulseAudio before ALSA so WSLg's PulseAudio server is found
    // without probing (nonexistent) ALSA hardware.
    ma_backend linuxBackends[] = {ma_backend_pulseaudio, ma_backend_alsa};
    m_context = new ma_context;
    m_hasContext = (ma_context_init(linuxBackends, 2, nullptr, m_context) == MA_SUCCESS);
    if (!m_hasContext) {
        delete m_context;
        m_context = nullptr;
    }
#endif

    m_device = new ma_device;
    ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
    cfg.playback.format = ma_format_f32;
    cfg.playback.channels = 2;
    cfg.sampleRate = 0; // use the device's native rate
    cfg.dataCallback = &AudioEngine::dataCallback;
    cfg.pUserData = this;
    // Buffering: PORYDAW_AUDIO_PERIOD_MS overrides when set. Under WSL,
    // default to 30 ms periods — WSLg's PulseAudio rides the RDP transport,
    // which underruns at miniaudio's 10 ms low-latency default and is heard
    // as constant crackling.
    bool havePeriodMs = false;
    int periodMs = qEnvironmentVariableIntValue("PORYDAW_AUDIO_PERIOD_MS", &havePeriodMs);
#ifdef __linux__
    if ((!havePeriodMs || periodMs <= 0) && runningUnderWsl()) {
        periodMs = 30;
        havePeriodMs = true;
    }
#endif
    if (havePeriodMs && periodMs > 0)
        cfg.periodSizeInMilliseconds = uint32_t(std::clamp(periodMs, 1, 500));

    if (ma_device_init(m_hasContext ? m_context : nullptr, &cfg, m_device) != MA_SUCCESS) {
        if (error)
            *error = QStringLiteral("Failed to initialize the audio output device.");
        delete m_device;
        m_device = nullptr;
        return false;
    }
    m_sampleRate = double(m_device->sampleRate);
    m_outputGainRampSamples =
        std::max<uint32_t>(1, uint32_t(m_sampleRate * kOutputGainRampSeconds));
    m_cutFadeSettleSamples = std::max<uint32_t>(1, uint32_t(m_sampleRate * kCutFadeSettleSeconds));
    resetOutputCut();
    const int targetOutputVolume = m_targetOutputVolume.load();
    m_outputGainTargetVolume = targetOutputVolume;
    m_outputGainTarget = float(targetOutputVolume) / 100.0f;
    m_appliedOutputGain = m_outputGainTarget;
    m_outputGainStep = 0.0f;
    m_outputGainRampRemaining = 0;
    // When every real backend fails (headless CI, WSL without libpulse),
    // miniaudio's default context falls back to its null device: playback
    // runs but is silent. Record which backend won so the UI can warn.
    m_backendName = QString::fromUtf8(ma_get_backend_name(m_device->pContext->backend));
    m_isNullBackend = (m_device->pContext->backend == ma_backend_null);
    m_periodFrames = int(m_device->playback.internalPeriodSizeInFrames);
    m_periodCount = int(m_device->playback.internalPeriods);

    m_bufCapacity = 8192;
    m_bufL = std::make_unique<float[]>(m_bufCapacity);
    m_bufR = std::make_unique<float[]>(m_bufCapacity);
    m_pvL = std::make_unique<float[]>(m_bufCapacity);
    m_pvR = std::make_unique<float[]>(m_bufCapacity);

    m_engine = std::make_unique<M4AEngine>();
    m4a_engine_init(m_engine.get(), float(m_sampleRate));
    m_previewEngine = std::make_unique<M4AEngine>();
    m4a_engine_init(m_previewEngine.get(), float(m_sampleRate));

    if (ma_device_start(m_device) != MA_SUCCESS) {
        if (error)
            *error = QStringLiteral("Failed to start the audio output device.");
        ma_device_uninit(m_device);
        delete m_device;
        m_device = nullptr;
        return false;
    }
    m_deviceStarted = true;
    return true;
}

void AudioEngine::shutdown()
{
    if (m_device) {
        ma_device_uninit(m_device); // stops the audio thread
        delete m_device;
        m_device = nullptr;
        m_deviceStarted = false;
    }
    resetOutputCut();
    if (m_engine) {
        m4a_engine_destroy(m_engine.get());
        m_engine.reset();
    }
    if (m_previewEngine) {
        m4a_engine_destroy(m_previewEngine.get());
        m_previewEngine.reset();
    }
    m_audition.reset();
    m_timeline = nullptr;
    m_voicegroup = nullptr;
    m_activePcm.store(0);
    m_activeCgb.store(0);
    clearTrackActivityLevels();
    if (m_context) {
        if (m_hasContext)
            ma_context_uninit(m_context);
        delete m_context;
        m_context = nullptr;
        m_hasContext = false;
    }
}

void AudioEngine::loadSong(const MidiTimeline *timeline, LoadedVoiceGroup *voicegroup,
                           const SongSettings &settings)
{
    // Cold swap: the audio thread must not be running while pointers change.
    if (m_deviceStarted)
        ma_device_stop(m_device);
    resetOutputCut();
    m_pendingSeek.store(kNoPendingSeek, std::memory_order_release);

    m_timeline = timeline;
    m_voicegroup = voicegroup;
    m_settings = settings;

    // Fresh engine state for the new song (safe here: device is stopped, and
    // init/set_pcm_mix_rate may allocate).
    m4a_engine_destroy(m_engine.get());
    m4a_engine_init(m_engine.get(), float(m_sampleRate));
    m4a_engine_set_voicegroup(m_engine.get(), m_voicegroup ? m_voicegroup->voices : nullptr);
    m4a_engine_set_song_volume(m_engine.get(), m_settings.songVolume);
    m4a_reverb_set_amount(&m_engine->reverb, m_settings.reverb);
    m_engine->maxPcmChannels = m_settings.maxPcmChannels;
    m_engine->analogFilter = m_settings.analogFilter;
    m4a_engine_set_pcm_mix_rate(m_engine.get(), m_settings.pcmMixRate);
    // Latch the song's initial controller state and prime each track's voice
    // so auditioned notes (previewNote) sound as they would in the song
    // before playback has ever dispatched the track's events. Playback
    // re-dispatches the real events, so this changes nothing it plays.
    if (m_timeline) {
        TimelinePlayer::chase(m_engine.get(), m_timeline, 0);
        TimelinePlayer::primeVoices(m_engine.get(), m_timeline, 0);
    }
    resetPreviewEngine();
    clearTimedPreviews();

    m_transport.store(static_cast<int>(Transport::Stopped));
    m_appliedTransport = static_cast<int>(Transport::Stopped);
    m_muteMask.store(0);
    m_soloMask.store(0);
    m_appliedMute = 0;
    m_player.reset();
    m_playhead.store(0);
    m_activePcm.store(0);
    m_activeCgb.store(0);
    clearTrackActivityLevels();
    if (m_deviceStarted)
        ma_device_start(m_device);
}

void AudioEngine::updateTimeline(const MidiTimeline *timeline)
{
    if (!m_timeline || !timeline)
        return;
    if (m_deviceStarted)
        ma_device_stop(m_device);
    resetOutputCut();
    // A seek published but not yet applied by the audio thread must survive
    // the rebuild — dropping it would silently ignore an edit-cursor move
    // that raced this edit. The device is stopped, so the exchange can't
    // race applyPendingSeek.
    const uint64_t pending = m_pendingSeek.exchange(kNoPendingSeek, std::memory_order_acq_rel);
    const uint64_t pos = pending != kNoPendingSeek ? pending : m_player.position();
    m_timeline = timeline;
    m_player.seek(pos, m_timeline);
    m_playhead.store(pos);
    // Release sounding notes: their note-offs may have moved or vanished in
    // the rebuilt timeline. Envelopes fade naturally, so brief edits during
    // playback don't hard-cut the audio.
    for (int track = 0; track < MAX_TRACKS; track++)
        m4a_engine_all_notes_off(m_engine.get(), track);
    clearTimedPreviews();
    // Re-latch controller state from the rebuilt timeline: the edit may have
    // deleted or moved the events behind the engine's current bend/CC values
    // (e.g. clearing a lane), which would otherwise stay latched until stop.
    TimelinePlayer::chase(m_engine.get(), m_timeline, pos);
    TimelinePlayer::primeVoices(m_engine.get(), m_timeline, pos);

    if (m_deviceStarted)
        ma_device_start(m_device);
}

void AudioEngine::seek(uint64_t samplePos)
{
    if (!m_timeline)
        return;
    m_pendingSeek.store(samplePos, std::memory_order_release);
}

void AudioEngine::applyPendingSeek()
{
    const uint64_t samplePos = m_pendingSeek.exchange(kNoPendingSeek, std::memory_order_acq_rel);
    if (samplePos == kNoPendingSeek || !m_timeline)
        return;

    for (int track = 0; track < MAX_TRACKS; track++)
        m4a_engine_all_notes_off(m_engine.get(), track);
    clearTimedPreviews();
    m_player.seek(samplePos, m_timeline);
    TimelinePlayer::chase(m_engine.get(), m_timeline, samplePos);
    TimelinePlayer::primeVoices(m_engine.get(), m_timeline, samplePos);
    m_playhead.store(samplePos);
}

void AudioEngine::updateSettings(const SongSettings &settings)
{
    if (m_deviceStarted)
        ma_device_stop(m_device);
    resetOutputCut();
    const bool mixRateChanged = settings.pcmMixRate != m_settings.pcmMixRate;
    m_settings = settings;
    m4a_engine_set_song_volume(m_engine.get(), m_settings.songVolume);
    m4a_reverb_set_amount(&m_engine->reverb, m_settings.reverb);
    m_engine->maxPcmChannels = m_settings.maxPcmChannels;
    m_engine->analogFilter = m_settings.analogFilter;
    if (mixRateChanged)
        m4a_engine_set_pcm_mix_rate(m_engine.get(), m_settings.pcmMixRate);
    resetPreviewEngine();
    if (m_deviceStarted)
        ma_device_start(m_device);
}

void AudioEngine::updateVoicegroup(LoadedVoiceGroup *voicegroup)
{
    if (m_deviceStarted)
        ma_device_stop(m_device);
    resetOutputCut();
    m4a_engine_all_sound_off(m_engine.get());
    clearTimedPreviews();
    m_voicegroup = voicegroup;
    m4a_engine_set_voicegroup(m_engine.get(), m_voicegroup ? m_voicegroup->voices : nullptr);
    // Re-latch program changes: the tracks' instrument state still points
    // into the old voices array until the chase reapplies it.
    if (m_timeline) {
        TimelinePlayer::chase(m_engine.get(), m_timeline, m_playhead.load());
        TimelinePlayer::primeVoices(m_engine.get(), m_timeline, m_playhead.load());
    }
    resetPreviewEngine();
    if (m_deviceStarted)
        ma_device_start(m_device);
}

ToneData *AudioEngine::previewVoices() const
{
    return m_voicegroup ? m_voicegroup->voices : nullptr;
}

// Rebuilds the audition instance to match the main engine's settings and
// voicegroup. Cold: callers have stopped the device.
void AudioEngine::resetPreviewEngine()
{
    if (!m_previewEngine)
        return;
    m4a_engine_destroy(m_previewEngine.get());
    m4a_engine_init(m_previewEngine.get(), float(m_sampleRate));
    m4a_engine_set_voicegroup(m_previewEngine.get(), previewVoices());
    m4a_engine_set_song_volume(m_previewEngine.get(), m_settings.songVolume);
    m4a_reverb_set_amount(&m_previewEngine->reverb, m_settings.reverb);
    m_previewEngine->maxPcmChannels = m_settings.maxPcmChannels;
    m_previewEngine->analogFilter = m_settings.analogFilter;
    m4a_engine_set_pcm_mix_rate(m_previewEngine.get(), m_settings.pcmMixRate);
    m_previewVoiceKey = -1;
    // The reinit destroyed every channel, so all audition slots retire.
    m_audition.reset();
}

void AudioEngine::previewNote(uint8_t track, uint8_t key, uint8_t velocity)
{
    m_previewGen++;
    m_previewCmd.store((uint32_t(m_previewGen) << 24) | (uint32_t(track & 0x0F) << 16) |
                       (uint32_t(key & 0x7F) << 8) | velocity);
}

void AudioEngine::previewNoteTimed(uint8_t track, uint8_t key, uint8_t velocity,
                                   uint32_t durationSamples)
{
    if (velocity > 0 && durationSamples == 0)
        return;
    const uint32_t w = m_timedWrite.load(std::memory_order_relaxed);
    if (w - m_timedRead.load(std::memory_order_acquire) >= kTimedRingSize)
        return;
    m_timedRing[w % kTimedRingSize] = {uint8_t(track & 0x0F), uint8_t(key & 0x7F), velocity,
                                       durationSamples};
    m_timedWrite.store(w + 1, std::memory_order_release);
}

void AudioEngine::previewVoice(uint8_t voice, uint8_t key, uint8_t velocity)
{
    m_previewVoiceGen++;
    m_previewVoiceCmd.store((uint64_t(m_previewVoiceGen) << 32) | (uint64_t(voice & 0x7F) << 16) |
                            (uint64_t(key & 0x7F) << 8) | velocity);
}

void AudioEngine::unloadSong()
{
    if (m_deviceStarted)
        ma_device_stop(m_device);
    resetOutputCut();
    // Hard-cut sounding channels while the device is parked. Both transport
    // fields are assigned below, so the callback's Playing→Stopped transition
    // never fires and no transport cut-fade would ever run — leaving mid-note
    // channels CHN_ON (with no note-offs coming after the player reset) still
    // reading WaveData owned by the voicegroup the caller frees right after
    // this returns. loadSong is exempt only because its engine reinit zeroes
    // the channels.
    m4a_engine_all_sound_off(m_engine.get());
    m_pendingSeek.store(kNoPendingSeek, std::memory_order_release);
    m_timeline = nullptr;
    m_voicegroup = nullptr;
    m4a_engine_set_voicegroup(m_engine.get(), nullptr);
    resetPreviewEngine();
    clearTimedPreviews();
    m_transport.store(static_cast<int>(Transport::Stopped));
    m_appliedTransport = static_cast<int>(Transport::Stopped);
    m_player.reset();
    m_playhead.store(0);
    m_activePcm.store(0);
    m_activeCgb.store(0);
    clearTrackActivityLevels();

    if (m_deviceStarted)
        ma_device_start(m_device);
}

void AudioEngine::play()
{
    if (songLoaded())
        m_transport.store(static_cast<int>(Transport::Playing));
}

void AudioEngine::pause()
{
    if (transport() == Transport::Playing)
        m_transport.store(static_cast<int>(Transport::Paused));
}

void AudioEngine::stop()
{
    // Cancel before publishing the transport change: once the callback can
    // see Stopped, no stale seek may survive to move the rewound playhead.
    m_pendingSeek.store(kNoPendingSeek, std::memory_order_release);
    m_transport.store(static_cast<int>(Transport::Stopped));
}

uint64_t AudioEngine::polyLostTotal() const
{
    // The engine header documents these counters as safe for lock-free
    // monitor reads from the GUI thread.
    if (!m_engine)
        return 0;
    // Tail cuts are deliberately excluded: a shortened release is barely
    // audible, and folding it in makes the transport-bar count alarmingly
    // large. The Polyphony dock still shows tail cuts in their own column.
    uint64_t total = 0;
    for (int t = 0; t < MAX_TRACKS; t++) {
        total += m_engine->polyDropCount[t];
        total += m_engine->polyStealCount[t];
    }
    return total;
}

TrackActivityLevels AudioEngine::consumeTrackActivityLevels()
{
    TrackActivityLevels levels{};
    for (std::size_t track = 0; track < kMaxTracks; track++) {
        levels[track] = unpackedActivity(
            m_pendingTrackActivityLevels[track].exchange(0, std::memory_order_relaxed));
    }
    return levels;
}

void AudioEngine::clearTrackActivityLevels()
{
    for (auto &level : m_pendingTrackActivityLevels)
        level.store(0, std::memory_order_relaxed);
}

void AudioEngine::polySnapshot(PolySnapshot *out) const
{
    *out = PolySnapshot{};
    if (!m_engine)
        return;
    const M4AEngine *engine = m_engine.get();
    out->maxPcmChannels = engine->maxPcmChannels;
    out->invert = engine->polyDebugInvert;
    // Total first, then the ring: an event published after this line shows up
    // next poll instead of tearing this one's newest row.
    out->eventTotal = engine->polyEventTotal;
    for (int i = 0; i < M4A_POLY_EVENT_CAPACITY; i++)
        out->events[i] = engine->polyEvents[i];
    for (int t = 0; t < MAX_TRACKS; t++) {
        out->drop[t] = engine->polyDropCount[t];
        out->steal[t] = engine->polyStealCount[t];
        out->tailCut[t] = engine->polyTailCutCount[t];
    }
    for (int i = 0; i < TOTAL_PCM_CHANNELS; i++) {
        const M4APCMChannel &ch = engine->pcmChannels[i];
        out->pcm[i] = {(ch.status & CHN_ON) != 0, (ch.status & (CHN_STOP | CHN_IEC)) != 0,
                       uint8_t(ch.trackIndex), uint8_t(ch.midiKey)};
    }
    for (int i = 0; i < TOTAL_CGB_CHANNELS; i++) {
        const M4ACGBChannel &ch = engine->cgbChannels[i];
        out->cgb[i] = {(ch.status & CHN_ON) != 0, (ch.status & (CHN_STOP | CHN_IEC)) != 0,
                       uint8_t(ch.trackIndex), uint8_t(ch.midiKey)};
    }
}

void AudioEngine::dataCallback(ma_device *device, void *output, const void *, uint32_t frameCount)
{
    auto *self = static_cast<AudioEngine *>(device->pUserData);
    self->process(static_cast<float *>(output), frameCount);
}

uint32_t AudioEngine::effectiveMuteMask() const
{
    const uint32_t mute = m_muteMask.load();
    const uint32_t solo = m_soloMask.load();
    // Tracks beyond the music player's budget are silent in-game
    // (MPlayStart never starts them); solo cannot bring them back.
    return ((solo ? (mute | ~solo) : mute) | trackBudgetMuteMask(m_settings.trackBudget)) & 0xFFFF;
}

void AudioEngine::applyTransportTransition()
{
    const int requested = m_transport.load();
    if (m_cutFadeActive) {
        // The applied transport remains unchanged until the zero sample. A
        // request change during fade-down only retargets that pending cut;
        // unchanged requests must not restart the ramp every callback.
        if (!m_cutFadeRising)
            m_cutFadeTargetTransport = requested;
        return;
    }
    if (requested == m_appliedTransport)
        return;
    beginOutputCut(requested);
}

// Cold: clears interrupted transport cut-fade state while the device is
// stopped. This only resets scalar state; it does not allocate or lock.
void AudioEngine::resetOutputCut()
{
    m_cutFadeActive = false;
    m_cutFadeRising = false;
    m_cutFadeTargetTransport = m_appliedTransport;
    m_cutFadeGain = 1.0f;
    m_cutFadeStep = 0.0f;
    m_cutFadeRemaining = 0;
    m_cutFadeHold = 0;
}

// Audio-thread: starts a transport cut-fade. The output gain ramps from its
// current value down to 0, both engines are cut at zero, and the pending
// transport is applied before the settle hold and return ramp.
void AudioEngine::beginOutputCut(int transport)
{
    if (m_cutFadeActive) {
        if (!m_cutFadeRising)
            m_cutFadeTargetTransport = transport;
        return;
    }

    // Drop all main-engine preview bookkeeping before the deferred cut. A
    // timed preview note-off must not reach a sequenced note started under
    // this transition's fade on the same track and key.
    m_timedActiveCount = 0;
    m_timedRead.store(m_timedWrite.load(std::memory_order_acquire), std::memory_order_release);
    m_previewTrack = -1;
    m_previewKey = -1;

    m_cutFadeActive = true;
    m_cutFadeRising = false;
    m_cutFadeTargetTransport = transport;
    m_cutFadeGain = std::clamp(m_cutFadeGain, 0.0f, 1.0f);
    m_cutFadeRemaining = std::max<uint32_t>(1, m_outputGainRampSamples);
    m_cutFadeStep = m_cutFadeGain / float(m_cutFadeRemaining);
    m_cutFadeHold = 0;
}

// Audio-thread: the exact zero-gain engine cut and deferred transport apply.
void AudioEngine::finishOutputCut()
{
    m_cutFadeTargetTransport = m_transport.load();
    m4a_engine_all_sound_off(m_engine.get());
    m4a_engine_all_sound_off(m_previewEngine.get());
    m_timedActiveCount = 0;
    m_previewTrack = -1;
    m_previewKey = -1;
    m_previewVoiceKey = -1;
    m_audition.reset();

    const int prior = m_appliedTransport;
    const int target = m_cutFadeTargetTransport;
    switch (static_cast<Transport>(target)) {
    case Transport::Stopped:
        m_player.reset();
        break;
    case Transport::Paused:
        break;
    case Transport::Playing:
        // Preserve the cursor for every non-Stopped transition. Starting
        // from Stopped only clears the accumulated overflow diagnostics.
        if (prior == static_cast<int>(Transport::Stopped))
            m4a_engine_reset_poly_stats(m_engine.get());
        break;
    }
    m_appliedTransport = target;
}

void AudioEngine::applyMuteTransition()
{
    const uint32_t em = effectiveMuteMask();
    if (em == m_appliedMute)
        return;
    const uint32_t newlyMuted = em & ~m_appliedMute;
    for (int track = 0; track < MAX_TRACKS; track++) {
        if ((newlyMuted >> track) & 1)
            m4a_engine_all_notes_off(m_engine.get(), track);
    }
    m_appliedMute = em;
}

void AudioEngine::applyPreviewNote()
{
    const uint32_t cmd = m_previewCmd.load();
    if (cmd == m_appliedPreview)
        return;
    m_appliedPreview = cmd;

    // A new preview releases the previous one so previews never stack.
    if (m_previewKey >= 0) {
        m4a_engine_note_off(m_engine.get(), m_previewTrack, uint8_t(m_previewKey));
        m_previewTrack = -1;
        m_previewKey = -1;
    }
    const uint8_t track = (cmd >> 16) & 0x0F;
    const uint8_t key = (cmd >> 8) & 0x7F;
    const uint8_t velocity = cmd & 0xFF;
    if (velocity > 0) {
        // Live note: no timeline position for any overflow event it causes,
        // and it stays audible in the solo-overflow invert mode.
        m_engine->polyEventClock = M4A_POLY_TICK_NONE;
        m_engine->auditionNote = true;
        m4a_engine_note_on(m_engine.get(), track, key, velocity);
        m_previewTrack = track;
        m_previewKey = key;
    }
}

void AudioEngine::applyTimedPreviews(uint32_t frameCount)
{
    // Do not start or expire timed previews while a transport cut is in
    // flight. Commands published after beginOutputCut stay queued for the
    // first callback after the deferred cut has completed.
    if (m_cutFadeActive)
        return;

    const uint32_t w = m_timedWrite.load(std::memory_order_acquire);
    uint32_t r = m_timedRead.load(std::memory_order_relaxed);
    // Auditions are live notes: no timeline position for overflow events,
    // and they stay audible in the solo-overflow invert mode.
    if (r != w) {
        m_engine->polyEventClock = M4A_POLY_TICK_NONE;
        m_engine->auditionNote = true;
    }
    for (; r != w; r++) {
        const TimedPreview cmd = m_timedRing[r % kTimedRingSize];
        if (cmd.velocity == 0) {
            // Early release: the band no longer covers the note.
            for (int i = 0; i < m_timedActiveCount; i++) {
                if (m_timedActive[i].track == cmd.track && m_timedActive[i].key == cmd.key) {
                    m4a_engine_note_off(m_engine.get(), cmd.track, cmd.key);
                    m_timedActive[i] = m_timedActive[--m_timedActiveCount];
                    break;
                }
            }
            continue;
        }
        // Retrigger a still-sounding key (note-off first — the engine stops
        // channels by track+key, so duplicates must never stack) and reuse
        // its slot; otherwise take a free slot, or steal the preview closest
        // to its own note-off.
        int slot = -1;
        for (int i = 0; i < m_timedActiveCount; i++) {
            if (m_timedActive[i].track == cmd.track && m_timedActive[i].key == cmd.key) {
                slot = i;
                break;
            }
        }
        if (slot < 0 && m_timedActiveCount < kTimedMaxActive) {
            slot = m_timedActiveCount++;
        } else {
            if (slot < 0) {
                slot = 0;
                for (int i = 1; i < m_timedActiveCount; i++) {
                    if (m_timedActive[i].remaining < m_timedActive[slot].remaining)
                        slot = i;
                }
            }
            m4a_engine_note_off(m_engine.get(), m_timedActive[slot].track, m_timedActive[slot].key);
        }
        m4a_engine_note_on(m_engine.get(), cmd.track, cmd.key, cmd.velocity);
        m_timedActive[slot] = {cmd.track, cmd.key, int64_t(cmd.durationSamples)};
    }
    m_timedRead.store(r, std::memory_order_release);

    // Count down and release. Expiry lands at callback granularity, which is
    // plenty for an audition.
    for (int i = 0; i < m_timedActiveCount;) {
        m_timedActive[i].remaining -= frameCount;
        if (m_timedActive[i].remaining <= 0) {
            m4a_engine_note_off(m_engine.get(), m_timedActive[i].track, m_timedActive[i].key);
            m_timedActive[i] = m_timedActive[--m_timedActiveCount];
        } else {
            i++;
        }
    }
}

// Cold: drop queued and sounding timed previews. Callers have already cut or
// released the engine's sound (or destroyed the engine), so no note-offs are
// owed; stale entries would otherwise cut a later playback note that lands on
// the same track and key.
void AudioEngine::clearTimedPreviews()
{
    m_timedRead.store(m_timedWrite.load());
    m_timedActiveCount = 0;
}

void AudioEngine::applyPreviewVoice()
{
    const uint64_t cmd = m_previewVoiceCmd.load();
    if (cmd == m_appliedPreviewVoice)
        return;
    m_appliedPreviewVoice = cmd;

    M4AEngine *engine = m_previewEngine.get();
    if (m_previewVoiceKey >= 0) {
        m4a_engine_note_off(engine, 0, uint8_t(m_previewVoiceKey));
        m_previewVoiceKey = -1;
    }
    const uint8_t voice = (cmd >> 16) & 0x7F;
    const uint8_t key = (cmd >> 8) & 0x7F;
    const uint8_t velocity = cmd & 0xFF;
    if (velocity > 0 && previewVoices() != nullptr) {
        m4a_engine_program_change(engine, 0, voice);
        m4a_engine_note_on(engine, 0, key, velocity);
        m_previewVoiceKey = key;
    }
}

void AudioEngine::applyPolyDebug()
{
    // Compared against the live engine field, not an applied-state shadow:
    // loadSong's engine reinit clears polyDebugInvert, and this re-asserts
    // the desired mode on the next callback (session-sticky semantics).
    const bool invert = m_polyInvert.load();
    if (invert != m_engine->polyDebugInvert)
        m4a_engine_set_poly_debug_invert(m_engine.get(), invert);

    const uint32_t resetGen = m_polyResetCmd.load();
    if (resetGen != m_appliedPolyReset) {
        m_appliedPolyReset = resetGen;
        m4a_engine_reset_poly_stats(m_engine.get());
    }
}

void AudioEngine::process(float *interleavedOut, uint32_t frameCount)
{
    // Transition before pending seek: a Stop rewinds the player, so a seek
    // requested after stop() (play-from-cursor) must land on top of the
    // rewind, not under it.
    applyTransportTransition();
    applyPendingSeek();
    applyMuteTransition();
    applyPreviewNote();
    applyTimedPreviews(frameCount);
    applyPreviewVoice();
    m_audition.apply(m_previewEngine.get(), kAuditionTrack);
    applyPolyDebug();

    // Voice edits: tracks hold a ToneData copy taken at program change, so a
    // scalar edit isn't heard until the copies are refreshed.
    const uint32_t refreshGen = m_refreshVoicesCmd.load();
    if (refreshGen != m_appliedRefreshVoices) {
        m_appliedRefreshVoices = refreshGen;
        m4a_engine_refresh_voices(m_engine.get());
    }

    M4AEngine *engine = m_engine.get();
    uint32_t done = 0;
    const int targetOutputVolume = m_targetOutputVolume.load();
    if (targetOutputVolume != m_outputGainTargetVolume) {
        m_outputGainTargetVolume = targetOutputVolume;
        m_outputGainTarget = float(targetOutputVolume) / 100.0f;
        m_outputGainRampRemaining = m_outputGainRampSamples;
        m_outputGainStep =
            (m_outputGainTarget - m_appliedOutputGain) / float(m_outputGainRampSamples);
    }

    while (done < frameCount) {
        const uint32_t n = std::min(frameCount - done, m_bufCapacity);
        const MidiTimeline *tl = m_timeline;
        const bool playing =
            m_appliedTransport == static_cast<int>(Transport::Playing) && tl != nullptr;

        if (playing) {
            const bool looping = m_loopEnabled.load();
            m_player.render(engine, tl, m_bufL.get(), m_bufR.get(), n, looping, m_appliedMute);

            // Auto-stop a non-looping song after the tail rings out.
            if (!(looping && tl->hasLoop()) &&
                m_player.position() > tl->lengthSamples + uint64_t(kTailSeconds * m_sampleRate)) {
                m_transport.store(static_cast<int>(Transport::Stopped));
                applyTransportTransition();
            }
        } else {
            // Idle: keep processing so releases and reverb ring out.
            m4a_engine_process(engine, m_bufL.get(), m_bufR.get(), int(n));
        }

        // The audition instance is mixed on top so voice previews are heard
        // as they would sound in the song, without touching playback state.
        m4a_engine_process(m_previewEngine.get(), m_pvL.get(), m_pvR.get(), int(n));

        for (uint32_t i = 0; i < n; ++i) {
            if (m_outputGainRampRemaining > 0) {
                --m_outputGainRampRemaining;
                if (m_outputGainRampRemaining == 0)
                    m_appliedOutputGain = m_outputGainTarget;
                else
                    m_appliedOutputGain += m_outputGainStep;
            }
            // Transport cut-fade: ramp the final gain down, fire the deferred
            // engine cut at the zero sample (finishOutputCut), hold at 0
            // through the engine's output-queue drain, then ramp back to 1.
            if (m_cutFadeActive) {
                if (m_cutFadeHold > 0) {
                    --m_cutFadeHold;
                    m_cutFadeGain = 0.0f;
                } else if (m_cutFadeRemaining > 0) {
                    --m_cutFadeRemaining;
                    if (m_cutFadeRising)
                        m_cutFadeGain = std::min(1.0f, m_cutFadeGain + m_cutFadeStep);
                    else
                        m_cutFadeGain = std::max(0.0f, m_cutFadeGain - m_cutFadeStep);
                    if (!m_cutFadeRising && m_cutFadeRemaining == 0) {
                        m_cutFadeGain = 0.0f;
                        m_cutFadeRising = true;
                        m_cutFadeRemaining = m_outputGainRampSamples;
                        m_cutFadeStep = 1.0f / float(m_cutFadeRemaining);
                        m_cutFadeHold = m_cutFadeSettleSamples;
                        finishOutputCut();
                        // This chunk was rendered before the cut: the samples
                        // from here on are stale pre-cut audio. Drop them so
                        // the fade-up can only amplify real silence.
                        for (uint32_t j = i; j < n; ++j) {
                            m_bufL[j] = 0.0f;
                            m_bufR[j] = 0.0f;
                            m_pvL[j] = 0.0f;
                            m_pvR[j] = 0.0f;
                        }
                    }
                } else {
                    m_cutFadeActive = false;
                    m_cutFadeGain = 1.0f;
                }
            }
            const float outputGain = m_appliedOutputGain * m_cutFadeGain;
            interleavedOut[(done + i) * 2] = (m_bufL[i] + m_pvL[i]) * outputGain;
            interleavedOut[(done + i) * 2 + 1] = (m_bufR[i] + m_pvR[i]) * outputGain;
        }
        done += n;
    }

    m_playhead.store(m_player.position());

    TrackActivityLevels callbackActivity{};
    int pcm = 0;
    for (int i = 0; i < engine->maxPcmChannels; i++) {
        const auto &channel = engine->pcmChannels[i];
        if (!(channel.status & CHN_ON))
            continue;
        pcm++;
        const int track = channel.trackIndex;
        if (track >= 0 && track < static_cast<int>(kMaxTracks)) {
            // Preserve the original envelope scale; left/right channel volume
            // contributes only the balance ratio, not a second gain reduction.
            callbackActivity[track] = maxLevel(
                callbackActivity[track],
                pcmActivityLevel(channel.envelopeVolume, channel.leftVolume, channel.rightVolume));
        }
    }
    int cgb = 0;
    for (int i = 0; i < MAX_CGB_CHANNELS; i++) {
        const auto &channel = engine->cgbChannels[i];
        if (!(channel.status & CHN_ON))
            continue;
        cgb++;
        const int track = channel.trackIndex;
        if (track >= 0 && track < static_cast<int>(kMaxTracks)) {
            // CGB output routing is binary per side. Scale its 0..15 envelope
            // to the PCM meter range, then apply the same pan bits as the mixer.
            const auto envelope = uint8_t(std::min(channel.envelopeVolume, uint8_t{15}) * 17);
            callbackActivity[track] =
                maxLevel(callbackActivity[track], {channel.pan & 0xF0 ? envelope : uint8_t{0},
                                                   channel.pan & 0x0F ? envelope : uint8_t{0}});
        }
    }
    m_activePcm.store(pcm);
    m_activeCgb.store(cgb);
    for (std::size_t track = 0; track < kMaxTracks; track++)
        publishMaximum(m_pendingTrackActivityLevels[track], callbackActivity[track]);
}
