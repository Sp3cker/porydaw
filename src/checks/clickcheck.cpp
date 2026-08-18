#include <QString>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <span>
#include <vector>

#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/timelineplayer.h"

extern "C" {
#include "m4a_engine.h"
}

// --clickcheck: transport transitions into silence (pause, stop, and
// starting playback over a ringing audition) must not step the output
// waveform. A transport cut used to call m4a_engine_all_sound_off() the
// instant the transition fired, while the engine's last rendered sample
// could still be at full volume: dropping a sounding channel from one sample
// to the next is a discontinuity — an audible click on every pause. The
// interface now fades the output to zero over a few milliseconds, cuts both
// engines at the exact zero sample, applies the pending transport, then
// ramps back (AudioEngine's cut-fade in process()).

// Self-contained (no project, no audio device): synthesizes a loud sustained
// note, drives the engine exactly as AudioEngine::process does — chunked
// TimelinePlayer renders while the applied transport is Playing,
// m4a_engine_process(idle) while not, transport requests begin a fade but
// apply only at fade zero — and asserts the sample-to-sample steps around
// each transition stay near the signal's own natural step size.

namespace {

constexpr uint32_t kDivision = 24;
constexpr double kSampleRate = 48000.0;
constexpr uint64_t kSamplesPerTick = 1000; // 24 tpqn, 120 BPM -> 1000 samples/tick
constexpr uint32_t kChunk = 512;           // AudioEngine's m_bufCapacity analog
constexpr double kCutFadeSeconds = 0.01;   // matches AudioEngine::kOutputGainRampSeconds
constexpr uint32_t kRampSamples = uint32_t(kSampleRate * kCutFadeSeconds);
// After the engine cut, the driver's output queue still holds up to one full
// DMA buffer (2 VBlank periods) of already-mixed audio. The fade stays at zero
// through that transit so queued pre-cut audio cannot be amplified when the
// return ramp starts. The same ordering is used for every transport target.
constexpr uint32_t kCutFadeSettleSamples = 1607; // ceil(2 * 48000 / 59.7275)
constexpr uint32_t kTimedRingSize = 64;
constexpr int kTimedMaxActive = 24;
// Transport states, mirrored from AudioEngine's Transport enum.
constexpr int kStopped = 0;
constexpr int kPaused = 1;
constexpr int kPlaying = 2;

SmfEvent channelEvent(uint64_t tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    SmfEvent ev;
    ev.tick = tick;
    ev.status = status;
    ev.data0 = data0;
    ev.data1 = data1;
    return ev;
}

SmfEvent metaEvent(uint64_t tick, uint8_t metaType, const QByteArray &blob)
{
    SmfEvent ev;
    ev.tick = tick;
    ev.status = 0xFF;
    ev.metaType = metaType;
    ev.blob = blob;
    return ev;
}

// One sustained note, no note-off: while playing, the channel holds at full
// level until the transport transition cuts it.
SmfFile buildSustainSong()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = kDivision;
    smf.tracks.resize(2);

    SmfTrack &conductor = smf.tracks[0];
    conductor.events.push_back(metaEvent(0, 0x51, QByteArray("\x07\xA1\x20", 3))); // 120 BPM
    conductor.endTick = 96;

    SmfTrack &notes = smf.tracks[1];
    notes.events.push_back(channelEvent(0, 0xC0, 0, 0));    // program 0
    notes.events.push_back(channelEvent(0, 0x90, 60, 100)); // sustain, no off
    notes.endTick = 96;

    return smf;
}

// In-memory voicegroup like loopcheck's: one looped PCM voice. `square`
// produces the loopcheck square (per-sample waveform edges — the natural
// step floor of the signal); the default constant sample produces a DC tone
// whose rendered output has zero natural steps, so ANY step at a transition
// is the bug under test, with no waveform edges to confuse the measurement.
struct TestVoicegroup {
    int8_t sample[65];
    WaveData wave;
    ToneData voices[128];

    explicit TestVoicegroup(bool square)
    {
        for (int i = 0; i < 64; i++)
            sample[i] = square ? (i < 32 ? 100 : -100) : 100;
        sample[64] = sample[63]; // loader's guard byte
        std::memset(&wave, 0, sizeof(wave));
        wave.status = 0xC000; // looped
        wave.freq = 8363u * 1024u;
        wave.loopStart = 0;
        wave.size = 64;
        wave.data = sample;
        std::memset(voices, 0, sizeof(voices));
        for (ToneData &v : voices) {
            v.type = VOICE_DIRECTSOUND;
            v.key = 60;
            v.wav = &wave;
            v.attack = 255;  // instant
            v.decay = 0;     // straight to sustain
            v.sustain = 255; // hold until note-off
            v.release = 165; // ~0.2 s fade (never reached in these scenarios)
        }
    }
};

// The normal transport cut's output fade: ramp the final gain to 0, fire the
// deferred engine cut at the zero sample, then ramp back to 1. AudioEngine's
// full-gain song-start exception is covered directly by transportcheck.
struct CutFader {
    bool active = false;
    bool rising = false;
    float gain = 1.0f;
    float step = 0.0f;
    uint32_t remaining = 0;
    uint32_t hold = 0;        // zero-gain settle samples after the cut
    uint32_t holdSamples = 0; // measured post-cut engine drain + margin

    void begin()
    {
        active = true;
        rising = false;
        gain = std::clamp(gain, 0.0f, 1.0f);
        remaining = std::max<uint32_t>(1, kRampSamples);
        step = gain / float(remaining);
        hold = 0;
        holdSamples = kCutFadeSettleSamples;
    }

    void reset()
    {
        active = false;
        rising = false;
        gain = 1.0f;
        step = 0.0f;
        remaining = 0;
        hold = 0;
    }

    // Advance one output sample; returns true on the exact sample where the
    // deferred engine cut must fire (gain just reached zero).
    bool advance()
    {
        if (!active)
            return false;
        if (hold > 0) {
            // Settle at exactly zero while the engine drains its output
            // queue. The fade-up runs at full length after the hold.
            --hold;
            gain = 0.0f;
            return false;
        }
        if (remaining > 0) {
            --remaining;
            if (rising)
                gain = std::min(1.0f, gain + step);
            else
                gain = std::max(0.0f, gain - step);
            if (!rising && remaining == 0) {
                gain = 0.0f;
                rising = true;
                remaining = kRampSamples;
                step = 1.0f / float(std::max<uint32_t>(1, remaining));
                hold = holdSamples; // cut fires here, at gain == 0
                return true;
            }
        } else {
            active = false;
            gain = 1.0f;
        }
        return false;
    }
};

struct Driver {
    M4AEngine engine;
    M4AEngine previewEngine;
    TestVoicegroup vg;
    std::unique_ptr<MidiTimeline> tl;
    TimelinePlayer player;
    int appliedTransport = kStopped;
    int requestedTransport = kStopped;
    int pendingTransport = kStopped;
    CutFader fader;
    float bufL[kChunk] = {};
    float bufR[kChunk] = {};
    float pvL[kChunk] = {};
    float pvR[kChunk] = {};
    std::vector<float> outL, outR;
    std::vector<float> gains;
    std::vector<float> rawL;
    std::vector<float> rawR;
    struct TimedPreview {
        uint8_t track;
        uint8_t key;
        uint8_t velocity;
        uint32_t durationSamples;
    };
    struct ActiveTimed {
        uint8_t track;
        uint8_t key;
        int64_t remaining;
    };
    TimedPreview timedRing[kTimedRingSize] = {};
    uint32_t timedWrite = 0;
    uint32_t timedRead = 0;
    ActiveTimed timedActive[kTimedMaxActive] = {};
    int timedActiveCount = 0;

    Driver(bool square, const MidiTimeline *timeline) : vg(square)
    {
        m4a_engine_init(&engine, float(kSampleRate));
        m4a_engine_set_voicegroup(&engine, vg.voices);
        m4a_engine_init(&previewEngine, float(kSampleRate));
        m4a_engine_set_voicegroup(&previewEngine, vg.voices);
        if (timeline)
            tl = std::make_unique<MidiTimeline>(*timeline);
        player.reset();
    }

    ~Driver()
    {
        m4a_engine_destroy(&engine);
        m4a_engine_destroy(&previewEngine);
    }

    bool sounding(uint8_t midiKey) const
    {
        for (int i = 0; i < TOTAL_PCM_CHANNELS; i++) {
            const M4APCMChannel &ch = engine.pcmChannels[i];
            if ((ch.status & CHN_ON) && ch.midiKey == midiKey)
                return true;
        }
        return false;
    }

    bool sustaining(uint8_t midiKey) const
    {
        for (int i = 0; i < TOTAL_PCM_CHANNELS; i++) {
            const M4APCMChannel &ch = engine.pcmChannels[i];
            if ((ch.status & CHN_ON) && !(ch.status & CHN_STOP) && ch.midiKey == midiKey)
                return true;
        }
        return false;
    }

    void queueTimedPreview(uint8_t track, uint8_t key, uint8_t velocity, uint32_t durationSamples)
    {
        if (velocity > 0 && durationSamples == 0)
            return;
        if (timedWrite - timedRead >= kTimedRingSize)
            return;
        timedRing[timedWrite % kTimedRingSize] = {track, key, velocity, durationSamples};
        ++timedWrite;
    }

    void clearTimedPreviews()
    {
        timedRead = timedWrite;
        timedActiveCount = 0;
    }

    void applyTimedPreviews(uint32_t frameCount)
    {
        // A command published after a cut starts remains queued until the
        // deferred cut has completed.
        if (fader.active)
            return;

        const uint32_t w = timedWrite;
        uint32_t r = timedRead;
        for (; r != w; ++r) {
            const TimedPreview cmd = timedRing[r % kTimedRingSize];
            if (cmd.velocity == 0) {
                for (int i = 0; i < timedActiveCount; ++i) {
                    if (timedActive[i].track == cmd.track && timedActive[i].key == cmd.key) {
                        m4a_engine_note_off(&engine, cmd.track, cmd.key);
                        timedActive[i] = timedActive[--timedActiveCount];
                        break;
                    }
                }
                continue;
            }

            int slot = -1;
            for (int i = 0; i < timedActiveCount; ++i) {
                if (timedActive[i].track == cmd.track && timedActive[i].key == cmd.key) {
                    slot = i;
                    break;
                }
            }
            if (slot < 0 && timedActiveCount < kTimedMaxActive)
                slot = timedActiveCount++;
            else if (slot < 0) {
                slot = 0;
                for (int i = 1; i < timedActiveCount; ++i) {
                    if (timedActive[i].remaining < timedActive[slot].remaining)
                        slot = i;
                }
                m4a_engine_note_off(&engine, timedActive[slot].track, timedActive[slot].key);
            } else {
                m4a_engine_note_off(&engine, timedActive[slot].track, timedActive[slot].key);
            }

            engine.polyEventClock = M4A_POLY_TICK_NONE;
            engine.auditionNote = true;
            m4a_engine_note_on(&engine, cmd.track, cmd.key, cmd.velocity);
            timedActive[slot] = {cmd.track, cmd.key, int64_t(cmd.durationSamples)};
        }
        timedRead = r;

        for (int i = 0; i < timedActiveCount;) {
            timedActive[i].remaining -= frameCount;
            if (timedActive[i].remaining <= 0) {
                m4a_engine_note_off(&engine, timedActive[i].track, timedActive[i].key);
                timedActive[i] = timedActive[--timedActiveCount];
            } else {
                ++i;
            }
        }
    }

    void finishOutputCut()
    {
        pendingTransport = requestedTransport;
        m4a_engine_all_sound_off(&engine);
        m4a_engine_all_sound_off(&previewEngine);
        timedActiveCount = 0;

        const int prior = appliedTransport;
        switch (pendingTransport) {
        case kStopped:
            player.reset();
            break;
        case kPaused:
            break;
        case kPlaying:
            if (prior == kStopped)
                m4a_engine_reset_poly_stats(&engine);
            break;
        }
        appliedTransport = pendingTransport;
    }

    void beginOutputCut(int transport)
    {
        if (fader.active) {
            if (!fader.rising)
                pendingTransport = transport;
            return;
        }
        clearTimedPreviews();
        pendingTransport = transport;
        fader.begin();
    }

    void applyTransportRequest()
    {
        if (fader.active) {
            if (!fader.rising)
                pendingTransport = requestedTransport;
            return;
        }
        if (requestedTransport != appliedTransport)
            beginOutputCut(requestedTransport);
    }

    void renderChunk(uint32_t n)
    {
        n = std::min<uint32_t>(n, kChunk);
        applyTransportRequest();
        applyTimedPreviews(n);
        const bool playing = appliedTransport == kPlaying && tl != nullptr;
        if (playing)
            player.render(&engine, tl.get(), std::span(bufL).first(n), std::span(bufR).first(n),
                          false, 0);
        else
            m4a_engine_process(&engine, bufL, bufR, int(n));
        m4a_engine_process(&previewEngine, pvL, pvR, int(n));
        for (uint32_t i = 0; i < n; i++) {
            if (fader.advance()) {
                finishOutputCut();
                // This chunk was rendered before the cut: samples from here
                // onward are stale pre-cut audio in both engines.
                for (uint32_t j = i; j < n; j++) {
                    bufL[j] = 0.0f;
                    bufR[j] = 0.0f;
                    pvL[j] = 0.0f;
                    pvR[j] = 0.0f;
                }
            }
            const float mixedL = bufL[i] + pvL[i];
            const float mixedR = bufR[i] + pvR[i];
            outL.push_back(mixedL * fader.gain);
            outR.push_back(mixedR * fader.gain);
            gains.push_back(fader.gain);
            rawL.push_back(mixedL);
            rawR.push_back(mixedR);
        }
    }

    void unloadSong()
    {
        m4a_engine_all_sound_off(&engine);
        m4a_engine_all_sound_off(&previewEngine);
        clearTimedPreviews();
        fader.reset();
        tl.reset();
        player.reset();
        appliedTransport = kStopped;
        requestedTransport = kStopped;
        pendingTransport = kStopped;
    }

    void loadSong(const MidiTimeline *timeline)
    {
        unloadSong();
        if (timeline)
            tl = std::make_unique<MidiTimeline>(*timeline);
    }

    void render(uint64_t samples)
    {
        while (samples > 0) {
            const uint32_t n = uint32_t(std::min<uint64_t>(samples, kChunk));
            renderChunk(n);
            samples -= n;
        }
    }

    // Mirrors AudioEngine::applyTransportTransition and its deferred
    // cut-fade. hardCut retains the pre-fade negative-control interface.
    void transitionTo(int transport, bool hardCut)
    {
        requestedTransport = transport;
        if (hardCut) {
            const int prior = appliedTransport;
            m4a_engine_all_sound_off(&engine);
            m4a_engine_all_sound_off(&previewEngine);
            clearTimedPreviews();
            fader.reset();
            pendingTransport = transport;
            if (transport == kStopped)
                player.reset();
            else if (transport == kPlaying && prior == kStopped)
                m4a_engine_reset_poly_stats(&engine);
            appliedTransport = transport;
            return;
        }
        applyTransportRequest();
    }
};

double maxAbsIn(const std::vector<float> &x, size_t from, size_t to)
{
    to = std::min(to, x.size());
    double m = 0.0;
    for (size_t i = from; i < to; i++)
        m = std::max(m, double(std::fabs(x[i])));
    return m;
}

// Largest sample-to-sample step in [from, to).
double maxStepIn(const std::vector<float> &x, size_t from, size_t to)
{
    to = std::min(to, x.size());
    double m = 0.0;
    for (size_t i = std::max<size_t>(from, 1); i < to; i++)
        m = std::max(m, double(std::fabs(x[i] - x[i - 1])));
    return m;
}

// A transition cut lands at `at`. The sustain window right before it proves
// the signal level (amp) and its natural per-sample step floor (square-wave
// edges; ~0 for the DC tone). The transition window covers the fade-down,
// the deferred cut, and the fade-back: a hard cut steps by roughly the full
// signal amplitude in one sample; the fade keeps every step at or below the
// natural floor, plus ~1/ramp of the amplitude per sample.

int checkTransition(const char *what, const Driver &d, size_t at)
{
    int failures = 0;
    const double amp =
        std::max(maxAbsIn(d.outL, at - 2048, at - 512), maxAbsIn(d.outR, at - 2048, at - 512));
    const double naturalStep =
        std::max(maxStepIn(d.outL, at - 2048, at - 512), maxStepIn(d.outR, at - 2048, at - 512));
    const size_t winEnd = std::min(at + 2560, d.outL.size());
    const double step =
        std::max(maxStepIn(d.outL, at - 512, winEnd), maxStepIn(d.outR, at - 512, winEnd));
    const double allowed = std::max(0.02 * amp, 1.5 * naturalStep + 0.001);
    if (amp < 0.01) {
        std::fprintf(stderr, "clickcheck: FAIL: %s: sustain amplitude %.4f too low to measure\n",
                     what, amp);
        failures++;
    } else if (step > allowed) {
        std::fprintf(stderr,
                     "clickcheck: FAIL: %s: output stepped %.4f in one sample at the "
                     "transition (sustain %.4f, natural step %.5f, allowed %.6f)\n",
                     what, step, amp, naturalStep, allowed);
        failures++;
    }
    return failures;
}

// Mirrors AudioEngine::process's transport order: a transition into Playing
// first (while still rendering the applied transport), 1 s of loud sustain,
// then the Paused transition, then idle processing while the fade runs out.
int scenarioPause(bool hardCut, bool square, const MidiTimeline &tl)
{
    Driver d(square, &tl);
    d.transitionTo(kPlaying, hardCut);
    d.render(48000);
    const size_t at = d.outL.size();
    d.transitionTo(kPaused, hardCut);
    const size_t steadyStart = at + 3 * size_t(kRampSamples) + size_t(kCutFadeSettleSamples);
    const size_t steadySamples = size_t(3.0 * kSampleRate);
    if (hardCut)
        d.render(3 * kRampSamples + 2048);
    else
        d.render(steadyStart - at + steadySamples);
    int failures = checkTransition(square ? "square pause" : "DC pause", d, at);
    // Pause must fall silent: after the cut (well inside the tail window)
    // nothing but silence remains.
    const double tail = std::max(maxAbsIn(d.outL, at + 2 * kRampSamples, d.outL.size()),
                                 maxAbsIn(d.outR, at + 2 * kRampSamples, d.outR.size()));
    if (tail > 0.01) {
        std::fprintf(stderr,
                     "clickcheck: FAIL: %s: pause did not fall silent "
                     "(tail level %.4f)\n",
                     square ? "square pause" : "DC pause", tail);
        failures++;
    }
    if (!hardCut) {
        constexpr double kSteadyAmplitudeLimit = 1e-5;
        constexpr double kSteadyStepLimit = 1e-5;
        const size_t steadyEnd = std::min(steadyStart + steadySamples, d.outL.size());
        double steadyAmplitude = 0.0;
        double steadyStep = 0.0;
        size_t steadyAmplitudeAt = steadyStart;
        size_t steadyStepAt = steadyStart;
        std::vector<size_t> evidence;
        evidence.reserve(8);
        bool wasEvidence = false;
        for (size_t i = steadyStart; i < steadyEnd; ++i) {
            const double level = std::max(std::fabs(d.outL[i]), std::fabs(d.outR[i]));
            if (level > steadyAmplitude) {
                steadyAmplitude = level;
                steadyAmplitudeAt = i;
            }
            double step = 0.0;
            if (i > steadyStart)
                step = std::max(std::fabs(d.outL[i] - d.outL[i - 1]),
                                std::fabs(d.outR[i] - d.outR[i - 1]));
            if (step > steadyStep) {
                steadyStep = step;
                steadyStepAt = i;
            }
            const bool isEvidence = level > kSteadyAmplitudeLimit || step > kSteadyStepLimit;
            if (isEvidence && !wasEvidence && evidence.size() < 8)
                evidence.push_back(i);
            wasEvidence = isEvidence;
        }
        if (steadyAmplitude > kSteadyAmplitudeLimit || steadyStep > kSteadyStepLimit) {
            std::fprintf(stderr,
                         "clickcheck: FAIL: %s: steady Paused tail was not silent "
                         "(max abs %.8g at sample %zu, max step %.8g at sample %zu; "
                         "limits %.1e/%.1e)\n",
                         square ? "square pause" : "DC pause", steadyAmplitude, steadyAmplitudeAt,
                         steadyStep, steadyStepAt, kSteadyAmplitudeLimit, kSteadyStepLimit);
            if (!evidence.empty()) {
                std::fprintf(stderr, "clickcheck: steady Paused evidence:");
                for (size_t i = 0; i < evidence.size(); ++i) {
                    const size_t interval = i == 0 ? 0 : evidence[i] - evidence[i - 1];
                    std::fprintf(stderr, " %zu(+%zu)", evidence[i], interval);
                }
                std::fprintf(stderr, "\n");
            }
            failures++;
        }
    }
    return failures;
}

int scenarioStop(bool hardCut, const MidiTimeline &tl)
{
    Driver d(false, &tl);
    d.transitionTo(kPlaying, hardCut);
    d.render(48000);
    const size_t at = d.outL.size();
    d.transitionTo(kStopped, hardCut);
    d.render(3 * kRampSamples + 2048);
    int failures = checkTransition("DC stop", d, at);
    const double tail = std::max(maxAbsIn(d.outL, at + 2 * kRampSamples, d.outL.size()),
                                 maxAbsIn(d.outR, at + 2 * kRampSamples, d.outR.size()));
    if (tail > 0.01) {
        std::fprintf(stderr,
                     "clickcheck: FAIL: DC stop did not fall silent "
                     "(tail level %.4f)\n",
                     tail);
        failures++;
    }
    return failures;
}

int scenarioPlayStopsAudition(bool hardCut, const MidiTimeline &tl)
{
    Driver d(false, &tl);
    // A live audition rings from outside the timeline (piano-key click,
    // note preview). The transport cut uses the public all-sound-off API for
    // the complete engine, so the sequenced note starts only after zero.
    m4a_engine_program_change(&d.engine, 0, 0);
    d.engine.auditionNote = true;
    m4a_engine_note_on(&d.engine, 0, 62, 100);
    d.engine.auditionNote = false;
    d.render(24000); // audition rings for 0.5 s
    const size_t at = d.outL.size();
    d.transitionTo(kPlaying, hardCut);
    d.render(3 * kRampSamples + 4096);
    int failures = checkTransition("DC play-over-audition", d, at);
    // The ringing audition must be cut (not left sounding under playback).
    if (d.sounding(62)) {
        std::fprintf(stderr, "clickcheck: FAIL: play did not halt the ringing audition\n");
        failures++;
    }
    return failures;
}

int scenarioPlayingStartsFirstNote(const MidiTimeline &tl)
{
    Driver d(false, &tl);
    d.transitionTo(kPlaying, false);
    d.render(3 * kRampSamples + kCutFadeSettleSamples + 2 * kChunk);

    int failures = 0;
    const size_t onset = kRampSamples + kCutFadeSettleSamples;
    const double level =
        std::max(maxAbsIn(d.outL, onset, d.outL.size()), maxAbsIn(d.outR, onset, d.outR.size()));
    if (level < 0.01) {
        std::fprintf(stderr,
                     "clickcheck: FAIL: Playing transition cut the first sequenced note "
                     "(level %.4f)\n",
                     level);
        failures++;
    }
    if (!d.sustaining(60)) {
        std::fprintf(stderr,
                     "clickcheck: FAIL: first sequenced note did not sustain after Playing\n");
        failures++;
    }
    if (d.appliedTransport != kPlaying || d.fader.active || d.fader.gain < 0.99f) {
        std::fprintf(stderr,
                     "clickcheck: FAIL: Playing transition left stale transport/fade state\n");
        failures++;
    }
    return failures;
}

int scenarioRapidRetarget(const MidiTimeline &tl)
{
    Driver d(false, &tl);
    d.transitionTo(kPlaying, false);
    d.render(kRampSamples / 2);
    d.transitionTo(kPaused, false);
    d.transitionTo(kPlaying, false);
    if (!d.fader.active || d.pendingTransport != kPlaying) {
        std::fprintf(stderr,
                     "clickcheck: FAIL: rapid retarget did not keep the newest pending state\n");
        return 1;
    }

    d.render(3 * kRampSamples + kCutFadeSettleSamples + 2 * kChunk);
    int failures = 0;
    if (d.appliedTransport != kPlaying || d.fader.active || d.fader.gain < 0.99f) {
        std::fprintf(stderr, "clickcheck: FAIL: rapid retarget left stale transport/fade state\n");
        failures++;
    }
    if (!d.sustaining(60)) {
        std::fprintf(stderr, "clickcheck: FAIL: rapid retarget lost the sequenced note\n");
        failures++;
    }
    return failures;
}

int scenarioTimedPreviewPlayingCut(const MidiTimeline &tl)
{
    Driver d(false, &tl);
    // One active preview and one queued preview share the song note's
    // track/key. Neither may leave a timed note-off behind the Playing cut.
    d.queueTimedPreview(0, 60, 100, 4 * kChunk);
    d.render(kChunk);
    d.queueTimedPreview(0, 60, 100, 2 * kChunk + 1);
    d.transitionTo(kPlaying, false);

    int failures = 0;
    if (d.timedActiveCount != 0 || d.timedRead != d.timedWrite) {
        std::fprintf(stderr,
                     "clickcheck: FAIL: Playing cut did not drop active/queued timed previews\n");
        failures++;
    }

    // The old bookkeeping race expires the queued preview during this fade,
    // after the sequencer has started its note. The note must still sustain.
    d.render(4 * kChunk);
    if (!d.sustaining(60)) {
        std::fprintf(stderr,
                     "clickcheck: FAIL: timed preview note-off stopped the Playing song note\n");
        failures++;
    }

    // A command published after the cut boundary remains deterministic: it
    // waits for the deferred cut, then starts normally.
    d.queueTimedPreview(0, 61, 100, 8 * kChunk);
    d.render(3 * kRampSamples + kCutFadeSettleSamples + kChunk);
    if (!d.sustaining(60) || !d.sustaining(61)) {
        std::fprintf(stderr, "clickcheck: FAIL: later timed preview was not deferred cleanly\n");
        failures++;
    }
    return failures;
}

int scenarioReloadAfterInterruptedFade(const MidiTimeline &tl)
{
    Driver d(false, &tl);
    d.transitionTo(kPlaying, false);
    d.render(48000);
    d.transitionTo(kPaused, false);
    d.render(kRampSamples / 2); // interrupt the fade at a partial gain

    d.unloadSong();
    d.loadSong(&tl);
    d.transitionTo(kPlaying, false);
    const size_t at = d.outL.size();
    d.render(3 * kRampSamples + kCutFadeSettleSamples + kChunk);

    int failures = 0;
    if (at >= d.gains.size() || d.gains[at] < 0.9f) {
        std::fprintf(stderr,
                     "clickcheck: FAIL: load after interrupted fade reused stale cut gain\n");
        failures++;
    }
    if (!d.sustaining(60)) {
        std::fprintf(stderr,
                     "clickcheck: FAIL: loaded song did not sustain after interrupted fade\n");
        failures++;
    }
    return failures;
}

} // namespace

int runClickCheck(bool hardCut)
{
    const SmfFile smf = buildSustainSong();
    const auto timeline = MidiTimeline::build(smf, kSampleRate);
    if (!timeline) {
        std::fprintf(stderr, "clickcheck: synthesized song failed to build\n");
        return 1;
    }

    int failures = 0;
    failures += scenarioPause(hardCut, false, *timeline);
    failures += scenarioPause(hardCut, true, *timeline);
    failures += scenarioStop(hardCut, *timeline);
    failures += scenarioPlayStopsAudition(hardCut, *timeline);
    if (!hardCut) {
        failures += scenarioPlayingStartsFirstNote(*timeline);
        failures += scenarioRapidRetarget(*timeline);
        failures += scenarioTimedPreviewPlayingCut(*timeline);
        failures += scenarioReloadAfterInterruptedFade(*timeline);
    }

    std::printf("clickcheck: %s (%s interface)\n", failures == 0 ? "PASS" : "FAIL",
                hardCut ? "pre-fade hard cut" : "faded cut");
    return failures == 0 ? 0 : 1;
}