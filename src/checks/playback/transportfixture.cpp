#include "checks/playback/transportfixture.h"

#include <QByteArray>
#include <cstring>

namespace checks {

SmfEvent channelEvent(uint64_t tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    SmfEvent ev;
    ev.tick = tick;
    ev.status = status;
    ev.data0 = data0;
    ev.data1 = data1;
    return ev;
}

namespace {

constexpr uint32_t kDivision = 24;

// 64 looped square samples; the caller owns the guard byte past the end.
void fillLoopedSquare(int8_t *sample, WaveData *wave)
{
    for (int i = 0; i < 64; i++)
        sample[i] = i < 32 ? 100 : -100;
    sample[64] = sample[63];
    std::memset(wave, 0, sizeof(*wave));
    wave->status = 0xC000; // looped
    wave->freq = 8363u * 1024u;
    wave->loopStart = 0;
    wave->size = 64;
    wave->data = sample;
}

} // namespace

SmfFile buildSilentSong()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = kDivision;
    smf.tracks.resize(3);

    SmfTrack &conductor = smf.tracks[0];
    SmfEvent tempo;
    tempo.tick = 0;
    tempo.status = 0xFF;
    tempo.metaType = 0x51;
    tempo.blob = QByteArray("\x07\xA1\x20", 3); // 120 BPM
    conductor.events.push_back(tempo);
    conductor.endTick = 4800;

    SmfTrack &t0 = smf.tracks[1];
    t0.events.push_back(channelEvent(0, 0xC0, 0, 0));
    t0.events.push_back(channelEvent(4800, 0xB0, 7, 100)); // 100 s at 120 BPM
    t0.endTick = 4800;

    SmfTrack &t1 = smf.tracks[2];
    t1.events.push_back(channelEvent(0, 0xC1, 1, 0));
    t1.endTick = 4800;

    return smf;
}

SmfFile buildNoteSong(uint8_t program)
{
    SmfFile smf;
    smf.format = 1;
    smf.division = kDivision;
    smf.tracks.resize(2);

    SmfTrack &conductor = smf.tracks[0];
    SmfEvent tempo;
    tempo.tick = 0;
    tempo.status = 0xFF;
    tempo.metaType = 0x51;
    tempo.blob = QByteArray("\x07\xA1\x20", 3); // 120 BPM
    conductor.events.push_back(tempo);
    conductor.endTick = 4800;

    SmfTrack &t0 = smf.tracks[1];
    t0.events.push_back(channelEvent(0, 0xC0, program, 0));
    t0.events.push_back(channelEvent(0, 0x90, 60, 127));
    t0.events.push_back(channelEvent(4800, 0x80, 60, 0));
    t0.endTick = 4800;

    return smf;
}

AuditionVoicegroup::AuditionVoicegroup()
{
    fillLoopedSquare(sample, &wave);
    std::memset(&vg, 0, sizeof(vg));
    for (ToneData &v : vg.voices) {
        v.type = VOICE_DIRECTSOUND;
        v.key = 60;
        v.wav = &wave;
        v.attack = 255; // instant
        v.decay = 0;    // straight to sustain
        v.sustain = 255;
        v.release = 254; // slow: (env * 254) >> 8 per frame, ~12 s ring
    }
    auto &square = vg.voices[2];
    square.type = VOICE_SQUARE_2;
    square.key = 60;
    square.wavePointer = reinterpret_cast<uint32_t *>(uintptr_t{2});
    square.attack = 7;
    square.decay = 0;
    square.sustain = 15;
    square.release = 7;
}

HeapVoicegroup::HeapVoicegroup()
{
    sample = new int8_t[65];
    wave = new WaveData();
    fillLoopedSquare(sample, wave);
    vg = new LoadedVoiceGroup();
    std::memset(vg, 0, sizeof(*vg));
    for (ToneData &v : vg->voices) {
        v.type = VOICE_DIRECTSOUND;
        v.key = 60;
        v.wav = wave;
        v.attack = 255;
        v.decay = 0;
        v.sustain = 255;
        v.release = 254;
    }
}

HeapVoicegroup::~HeapVoicegroup()
{
    freeAll();
}

void HeapVoicegroup::freeAll()
{
    delete vg;
    delete wave;
    delete[] sample;
    vg = nullptr;
    wave = nullptr;
    sample = nullptr;
}

} // namespace checks
