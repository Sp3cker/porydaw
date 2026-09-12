#include "checks/audio/clickrig.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace checks {
namespace {

constexpr uint32_t kDivision = 24;

SmfEvent channelEvent(Tick tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    SmfEvent ev;
    ev.tick = tick;
    ev.status = status;
    ev.data0 = data0;
    ev.data1 = data1;
    return ev;
}

SmfEvent metaEvent(Tick tick, uint8_t metaType, const QByteArray &blob)
{
    SmfEvent ev;
    ev.tick = tick;
    ev.status = 0xFF;
    ev.metaType = metaType;
    ev.blob = blob;
    return ev;
}

} // namespace

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

ClickVoicegroup::ClickVoicegroup(bool square)
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
    std::memset(&vg, 0, sizeof(vg));
    for (ToneData &v : vg.voices) {
        v.type = VOICE_DIRECTSOUND;
        v.key = 60;
        v.wav = &wave;
        v.attack = 255;  // instant
        v.decay = 0;     // straight to sustain
        v.sustain = 255; // hold until note-off
        v.release = 165; // ~0.2 s fade (never reached in these scenarios)
    }
}

double maxAbsIn(const std::vector<float> &x, std::size_t from, std::size_t to)
{
    to = std::min(to, x.size());
    double m = 0.0;
    for (std::size_t i = from; i < to; i++)
        m = std::max(m, double(std::fabs(x[i])));
    return m;
}

double maxStepIn(const std::vector<float> &x, std::size_t from, std::size_t to)
{
    to = std::min(to, x.size());
    double m = 0.0;
    for (std::size_t i = std::max<std::size_t>(from, 1); i < to; i++)
        m = std::max(m, double(std::fabs(x[i] - x[i - 1])));
    return m;
}

TransitionProbe measureTransition(const std::vector<float> &outL, const std::vector<float> &outR,
                                  std::size_t at)
{
    TransitionProbe probe;
    probe.amp = std::max(maxAbsIn(outL, at - 2048, at - 512), maxAbsIn(outR, at - 2048, at - 512));
    probe.naturalStep =
        std::max(maxStepIn(outL, at - 2048, at - 512), maxStepIn(outR, at - 2048, at - 512));
    const std::size_t winEnd = std::min(at + 2560, outL.size());
    probe.step = std::max(maxStepIn(outL, at - 512, winEnd), maxStepIn(outR, at - 512, winEnd));
    probe.allowed = std::max(0.02 * probe.amp, 1.5 * probe.naturalStep + 0.001);
    return probe;
}

SteadySilence scanSteadySilence(const std::vector<float> &outL, const std::vector<float> &outR,
                                std::size_t from, std::size_t to)
{
    SteadySilence steady;
    steady.absAt = from;
    steady.stepAt = from;
    steady.evidence.reserve(8);
    bool wasEvidence = false;
    to = std::min(to, outL.size());
    for (std::size_t i = from; i < to; ++i) {
        const double level = std::max(std::fabs(double(outL[i])), std::fabs(double(outR[i])));
        if (level > steady.maxAbs) {
            steady.maxAbs = level;
            steady.absAt = i;
        }
        double step = 0.0;
        if (i > from)
            step = std::max(std::fabs(double(outL[i]) - double(outL[i - 1])),
                            std::fabs(double(outR[i]) - double(outR[i - 1])));
        if (step > steady.maxStep) {
            steady.maxStep = step;
            steady.stepAt = i;
        }
        const bool isEvidence = level > kOutputLsb || step > kOutputLsb;
        if (isEvidence && !wasEvidence && steady.evidence.size() < 8)
            steady.evidence.push_back(i);
        wasEvidence = isEvidence;
    }
    return steady;
}

} // namespace checks
