#pragma once

#include "audio/auditionslots.h"
#include "audio/resonance_suppressor.h"
#include "audio/timeline_handoff.h"
#include "audio/trackactivitylevel.h"
#include "core/miditimeline.h"
#include "core/timelineplayer.h"
#include "project/voicegroupsource.h"
#include <QString>
#include <algorithm>
#include <array>
#include <atomic>
#include <cstdint>
#include <memory>
#include <utility>
#include <vector>

extern "C" {
#include "m4a_engine.h"
#include "voicegroup_loader.h"
}

static_assert(kMaxTracks == MAX_TRACKS, "track count mismatch");

struct ma_device;
struct ma_context;

struct SongSettings {
    M4APcmMixerMode pcmMixer = M4A_PCM_MIXER_IPATIX;
    uint8_t songVolume = 127;    // mid2agb -V (0-127)
    uint8_t reverb = 0;          // mid2agb -R (0-127)
    uint8_t maxPcmChannels = 5;  // pokeemerald m4aSoundInit default
    float pcmMixRate = 13379.0f; // GBA-accurate DirectSound mix rate
    bool analogFilter = false;   // GBA analog output low-pass (SPEC §7)
};

enum class Transport : int {
    Stopped = 0,
    Paused = 1,
    Playing = 2,
};

// Owns the audio output device (miniaudio), the poryaaaa M4AEngine instance,
// and the sequencer that walks a MidiTimeline on the audio thread.
//
// Thread model, split hot/cold:
//  - Cold operations (loadSong/unloadSong/shutdown) stop the device first, so
//    the audio thread is not running while engine/timeline/voicegroup pointers
//    are swapped. Call from the UI thread only.
//  - Hot operations (transport, mute/solo, loop) are single-writer atomics set
//    by the UI thread; the audio thread applies transitions at callback
//    boundaries (sending note-offs for newly muted tracks, etc.).
//  - Telemetry (playhead, active channels) is written by the audio thread into
//    atomics; polyphony-overflow counters are read directly from the engine
//    struct, which its header documents as safe for lock-free monitoring.
class AudioEngine
{
  public:
    AudioEngine();
    ~AudioEngine();

    AudioEngine(const AudioEngine &) = delete;
    AudioEngine &operator=(const AudioEngine &) = delete;

    bool init(QString *error);
    void shutdown();
    double sampleRate() const { return m_sampleRate; }
    // Which miniaudio backend the device landed on ("PulseAudio", "ALSA",
    // "Null", ...). The null device keeps the sequencer running with no
    // sound — either forced for integration checks or selected as a fallback,
    // and a trap for real users, so the UI must surface it.
    QString backendName() const { return m_backendName; }
    bool usingNullBackend() const { return m_isNullBackend; }
    bool nullBackendForced() const { return m_forcedNullBackend; }
    // The device's resolved buffering (per-period frames × period count),
    // for diagnostics: underruns on slow transports (WSLg's RDP audio)
    // show up as crackling, and the first support question is "how big are
    // the periods really?".
    int periodSizeFrames() const { return m_periodFrames; }
    int periodCount() const { return m_periodCount; }

    // Cold: swaps song data with the device stopped. Takes shared ownership
    // of the timeline; the bank stays leased by the active song session.
    void loadSong(std::shared_ptr<const MidiTimeline> timeline, const VoicegroupLease &voicegroup,
                  const SongSettings &settings);
    void unloadSong();

    // Publishes the latest rebuilt timeline for the next audio callback.
    // Ownership handoff and deferred reclamation stay inside TimelineHandoff;
    // this call never waits for the callback.
    void updateTimeline(std::shared_ptr<const MidiTimeline> timeline);
    // Hot: requests a jump at the next audio callback. Releases sounding
    // notes and chases controller state at the landing position. Works in
    // any transport state; playing from Stopped starts wherever the last
    // seek (or the stop-time reset to 0) left the playhead. Takes effect
    // within one audio period — read the target back, not playheadSamples(),
    // when acting immediately after.
    void seek(uint64_t samplePos);
    // Cold: re-applies song settings (master volume, reverb) to the engine.
    void updateSettings(const SongSettings &settings);
    // Cold: swaps the voicegroup (borrowed, like loadSong's); cuts all
    // sound. The old bank may be released once this returns.
    void updateVoicegroup(const VoicegroupLease &voicegroup);

    // The poryaaaa compatibility seam (see VoicegroupLease): feeds the
    // lease's legacy mutable borrow to a poryaaaa engine, which only reads
    // it. Used by the load/update paths here and by the offline WAV
    // exporter, which runs its own engine instance.
    static void bindEngineVoicegroup(M4AEngine *engine, const VoicegroupLease &bank);

    // Hot: audition a single note outside the timeline (piano-key click,
    // note-draw preview). velocity 0 releases. A new preview releases the
    // previous one, so at most one preview note sounds at a time.
    void previewNote(uint8_t track, uint8_t key, uint8_t velocity);

    // Hot: audition a note for a fixed length (band-sweep chord preview).
    // Unlike previewNote, timed previews stack polyphonically; the audio
    // thread sends each note-off itself once the duration elapses. velocity
    // 0 releases that track+key's preview early instead (durationSamples
    // ignored).
    void previewNoteTimed(uint8_t track, uint8_t key, uint8_t velocity, uint32_t durationSamples);

    // Hot: audition a voicegroup entry by program number (SPEC §6.1 voicegroup
    // browser). Runs on a second engine instance (SPEC §3) so the program
    // change never disturbs playback track state. velocity 0 releases.
    void previewVoice(uint8_t voice, uint8_t key, uint8_t velocity);

    // Hot: Sample Editor in-memory sample audition (PLAN.md §4). Plays the
    // rendered s8 bytes through the audition engine instance on a dedicated
    // track, so an unregistered sample is heard with the engine's real
    // fetch/loop/envelope math. A new publish releases the previous
    // audition. Returns false when every slot is still busy (the caller
    // coalesces — retry on the next re-render).
    bool auditionSample(const QByteArray &s8, uint32_t freq, uint32_t loopStart, bool looped,
                        uint8_t key, const AuditionSlots::Adsr &adsr, uint8_t toneKey = 60)
    {
        return m_audition.publishNote(s8, freq, loopStart, looped, key, adsr, toneKey);
    }
    // CGB programmable-wave audition (16 packed bytes; CGB-range adsr).
    bool auditionWave(const QByteArray &wave16, uint8_t key, const AuditionSlots::Adsr &adsr)
    {
        return m_audition.publishWave(wave16, key, adsr);
    }
    void auditionSampleOff() { m_audition.publishOff(); }

    bool songLoaded() const { return m_timelineHandoff.active() != nullptr; }

    // Borrowed snapshots for immediate GUI-thread reads. The engine retains
    // replaced timelines until the audio callback finishes with them.
    const MidiTimeline *timeline() const { return m_timelineHandoff.active(); }
    const LoadedVoiceGroup *voicegroup() const { return m_voicegroup; }

    // Hot transport controls.
    void play();
    void pause();
    void stop();
    Transport transport() const { return static_cast<Transport>(m_transport.load()); }
    void setLoopEnabled(bool enabled) { m_loopEnabled.store(enabled); }
    bool loopEnabled() const { return m_loopEnabled.load(); }
    void setMuteMask(uint32_t mask) { m_muteMask.store(mask); }
    void setSoloMask(uint32_t mask) { m_soloMask.store(mask); }

    void setOutputVolume(int percent) { m_targetOutputVolume.store(std::clamp(percent, 0, 100)); }
    int outputVolume() const { return m_targetOutputVolume.load(); }
    void setResonanceSuppression(bool on) { m_resonance.setEnabled(on); }
    bool resonanceSuppression() const { return m_resonance.enabled(); }

    // Hot: polyphony-overflow debug mode — mutes normal playback and plays
    // only the sounds lost to the polyphony limit (SPEC §6.1 Polyphony dock).
    // Applied at the callback boundary against the live engine field, so it
    // re-asserts itself after loadSong reinitializes the engine: the mode is
    // session-sticky (survives play/stop and song switches) but never
    // persisted.
    void setPolyDebugInvert(bool on) { m_polyInvert.store(on); }
    bool polyDebugInvert() const { return m_polyInvert.load(); }
    // Hot: zero the overflow counters and event ring at the next callback
    // boundary (a GUI-thread reset would race the audio thread's writes).
    void resetPolyStats() { m_polyResetCmd.fetch_add(1); }

    // Telemetry.
    uint64_t playheadSamples() const { return m_playhead.load(); }
    int activePcmChannels() const { return m_activePcm.load(); }
    int activeCgbChannels() const { return m_activeCgb.load(); }
    TrackActivityLevels consumeTrackActivityLevels();

    M4APcmMixerMode pcmMixerMode() const { return m_settings.pcmMixer; }
    int maxPcmChannels() const { return m_settings.maxPcmChannels; }
    float pcmMixRate() const { return m_settings.pcmMixRate; }
    bool analogFilter() const { return m_settings.analogFilter; }
    uint64_t polyLostTotal() const; // dropped + stolen, all tracks (no tail cuts)

    // GUI-thread copy of the engine's polyphony-overflow state (the engine
    // header documents these fields as safe for lock-free monitor reads).
    // If more than M4A_POLY_EVENT_CAPACITY events land between two polls the
    // oldest ring rows may be torn or stale — benign for a debug display;
    // eventTotal is always exact.
    struct PolyChannel {
        bool on = false;
        bool releasing = false; // CHN_STOP | CHN_IEC: fading out
        uint8_t track = 0;
        uint8_t midiKey = 0;
    };
    struct PolySnapshot {
        uint8_t maxPcmChannels = 0;
        bool invert = false;
        // Second half of each array is the shadow pool (lost sounds).
        PolyChannel pcm[TOTAL_PCM_CHANNELS];
        PolyChannel cgb[TOTAL_CGB_CHANNELS];
        uint32_t drop[MAX_TRACKS] = {};
        uint32_t steal[MAX_TRACKS] = {};
        uint32_t tailCut[MAX_TRACKS] = {};
        uint32_t eventTotal = 0;
        M4APolyEvent events[M4A_POLY_EVENT_CAPACITY] = {};
    };
    void polySnapshot(PolySnapshot *out) const;

  private:
    friend int runTransportCheck();
    static void dataCallback(ma_device *device, void *output, const void *input,
                             uint32_t frameCount);
    void process(float *interleavedOut, uint32_t frameCount);
    void applyPendingSeek();
    void applyTimelineAdoption(const MidiTimeline *timeline);
    void applyTransportTransition();
    // Transport cut-fade: the requested state is normally applied at the
    // exact zero-gain sample. A start at song position zero is deferred until
    // the settle hold ends so its first note begins at full output gain.
    void beginOutputCut(int transport);
    // Cold: clears interrupted transport cut-fade state while the device is
    // stopped. Scalar-only; safe for cold init/load/unload boundaries.
    void resetOutputCut();
    void finishOutputCut();
    void applyMuteTransition();
    void applyPreviewNote();
    void applyTimedPreviews(uint32_t frameCount);
    void clearTimedPreviews();
    void applyPreviewVoice();
    void applyPolyDebug();
    void resetPreviewEngine();
    uint32_t effectiveMuteMask() const;
    void clearTrackActivityLevels();

    // Device / engine (audio thread reads; cold ops swap while stopped)
    ma_context *m_context = nullptr;
    bool m_hasContext = false;
    ma_device *m_device = nullptr;
    bool m_deviceStarted = false;
    double m_sampleRate = 0.0;
    QString m_backendName;
    bool m_isNullBackend = false;
    bool m_forcedNullBackend = false;
    int m_periodFrames = 0;
    int m_periodCount = 0;
    std::unique_ptr<M4AEngine> m_engine;
    TimelineHandoff m_timelineHandoff;
    LoadedVoiceGroup *m_voicegroup = nullptr; // borrowed from the session's lease; not owned
    SongSettings m_settings;
    // Audition instance: voice previews and sample auditions, mixed on top
    // of the main engine.
    std::unique_ptr<M4AEngine> m_previewEngine;
    // Sample Editor audition slots (PLAN.md §4), played on the audition
    // instance's track 1 (previewVoice owns track 0).
    static constexpr int kAuditionTrack = 1;
    AuditionSlots m_audition;

    // Hot control state (UI writes, audio thread reads)
    std::atomic<int> m_transport{static_cast<int>(Transport::Stopped)};
    std::atomic<bool> m_loopEnabled{true};
    std::atomic<uint32_t> m_muteMask{0};
    std::atomic<uint32_t> m_soloMask{0};
    std::atomic<int> m_targetOutputVolume{100};
    // Avoid stop/start stalls: publish the latest seek for the audio callback.
    static constexpr uint64_t kNoPendingSeek = UINT64_MAX;
    std::atomic<uint64_t> m_pendingSeek{kNoPendingSeek};
    // Preview-note command: generation<<24 | track<<16 | key<<8 | velocity.
    // The generation counter makes every request distinct so repeated notes
    // are seen by the audio thread.
    std::atomic<uint32_t> m_previewCmd{0};
    uint8_t m_previewGen = 0; // UI thread only
    // Timed-preview commands (band-sweep chord audition): a fixed SPSC ring.
    // The UI thread produces at m_timedWrite; the audio thread consumes at
    // m_timedRead, starting each note and releasing it when its duration
    // elapses. A full ring drops the preview, which is harmless.
    struct TimedPreview {
        uint8_t track;
        uint8_t key;
        uint8_t velocity;
        uint32_t durationSamples;
    };
    static constexpr uint32_t kTimedRingSize = 64;
    static constexpr int kTimedMaxActive = 24;
    TimedPreview m_timedRing[kTimedRingSize];
    std::atomic<uint32_t> m_timedWrite{0}; // UI thread increments
    std::atomic<uint32_t> m_timedRead{0};  // audio thread increments
    // Voice-preview command: generation<<32 | voice<<16 | key<<8 | velocity.
    std::atomic<uint64_t> m_previewVoiceCmd{0};
    uint8_t m_previewVoiceGen = 0; // UI thread only
    // Polyphony-overflow debug: desired invert state + reset command.
    std::atomic<bool> m_polyInvert{false};
    std::atomic<uint32_t> m_polyResetCmd{0};

    // Telemetry (audio thread writes, UI reads)
    std::atomic<uint64_t> m_playhead{0};
    std::atomic<int> m_activePcm{0};
    std::atomic<int> m_activeCgb{0};
    std::array<std::atomic<uint32_t>, kMaxTracks> m_pendingTrackActivityLevels{};
    static_assert(std::atomic<uint32_t>::is_always_lock_free);

    // Audio-thread-only output gain state. The control thread publishes only
    // m_targetOutputVolume above.
    static constexpr double kOutputGainRampSeconds = 0.01;
    uint32_t m_outputGainRampSamples = 1;
    int m_outputGainTargetVolume = 100;
    float m_outputGainTarget = 1.0f;
    float m_appliedOutputGain = 1.0f;
    float m_outputGainStep = 0.0f;
    uint32_t m_outputGainRampRemaining = 0;

    // Audio-thread-only transport cut-fade state (see beginOutputCut).
    // The settle hold covers all already-rendered pre-cut audio: the current
    // device render block, the driver's two-VBlank DMA buffer, and poryaaaa's
    // fixed hardware-frontend queue. The fade remains at zero through them.
    static constexpr double kDriverQueueSettleSeconds = 2.0 / 59.7275;
    static constexpr uint32_t kFrontendQueueFrames = 1536;
    uint32_t m_cutFadeSettleSamples = 1;
    bool m_cutFadeActive = false;
    bool m_cutFadeRising = false;
    int m_cutFadeTargetTransport = static_cast<int>(Transport::Stopped);
    float m_cutFadeGain = 1.0f;
    float m_cutFadeStep = 0.0f;
    uint32_t m_cutFadeRemaining = 0;
    uint32_t m_cutFadeHold = 0;

    // Audio-thread-only sequencer state
    int m_appliedTransport = static_cast<int>(Transport::Stopped);
    uint32_t m_appliedMute = 0;
    uint32_t m_appliedPreview = 0;
    int m_previewTrack = -1; // sounding preview note, -1 when none
    int m_previewKey = -1;
    // Sounding timed previews, counting down to their note-offs.
    struct ActiveTimed {
        uint8_t track;
        uint8_t key;
        int64_t remaining; // samples until note-off
    };
    ActiveTimed m_timedActive[kTimedMaxActive];
    int m_timedActiveCount = 0;
    uint64_t m_appliedPreviewVoice = 0;
    int m_previewVoiceKey = -1; // sounding voice-preview note, -1 when none
    uint32_t m_appliedPolyReset = 0;
    TimelinePlayer m_player;

    // Scratch deinterleave buffers (allocated in init)
    std::unique_ptr<float[]> m_bufL;
    std::unique_ptr<float[]> m_bufR;
    std::unique_ptr<float[]> m_pvL; // voice-preview engine mix
    std::unique_ptr<float[]> m_pvR;
    ResonanceSuppressor m_resonance;

    uint32_t m_bufCapacity = 0;
};
