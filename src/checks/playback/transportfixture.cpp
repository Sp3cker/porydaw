#include "checks/playback/transportfixture.h"

#include <array>
#include <cstring>

namespace checks {

TransportMidiEvent channelEvent(uint32_t tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    return {
        .tick = tick,
        .status = status,
        .data0 = data0,
        .data1 = data1,
    };
}

namespace {

constexpr uint16_t kDivision = 24;

TransportMidiEvent tempoEvent()
{
    return {
        .tick = 0,
        .status = 0xFF,
        .data0 = 0x51,
        .payload = QByteArray("\x07\xA1\x20", 3),
    };
}

void appendU16(QByteArray &bytes, uint16_t value)
{
    bytes.append(char(value >> 8));
    bytes.append(char(value));
}

void appendU32(QByteArray &bytes, uint32_t value)
{
    bytes.append(char(value >> 24));
    bytes.append(char(value >> 16));
    bytes.append(char(value >> 8));
    bytes.append(char(value));
}

void appendVariableLength(QByteArray &bytes, uint32_t value)
{
    std::array<char, 5> encoded{};
    auto index = encoded.size() - 1;
    encoded[index] = char(value & 0x7F);
    while ((value >>= 7) != 0) {
        --index;
        encoded[index] = char((value & 0x7F) | 0x80);
    }
    bytes.append(encoded.data() + index, qsizetype(encoded.size() - index));
}

bool appendTrack(QByteArray &file, const TransportMidiTrack &track)
{
    QByteArray body;
    uint32_t previousTick = 0;
    for (const auto &event : track.events) {
        if (event.tick < previousTick)
            return false;
        appendVariableLength(body, event.tick - previousTick);
        previousTick = event.tick;
        body.append(char(event.status));
        body.append(char(event.data0));
        if (event.status == 0xFF) {
            appendVariableLength(body, uint32_t(event.payload.size()));
            body.append(event.payload);
        } else if ((event.status & 0xF0) != 0xC0 && (event.status & 0xF0) != 0xD0) {
            body.append(char(event.data1));
        }
    }
    if (track.endTick < previousTick)
        return false;
    appendVariableLength(body, track.endTick - previousTick);
    body.append("\xFF\x2F\x00", 3);

    file.append("MTrk", 4);
    appendU32(file, uint32_t(body.size()));
    file.append(body);
    return true;
}

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

QByteArray TransportMidiFile::encode() const
{
    QByteArray bytes;
    bytes.append("MThd", 4);
    appendU32(bytes, 6);
    appendU16(bytes, 1);
    appendU16(bytes, uint16_t(tracks.size()));
    appendU16(bytes, division);
    for (const auto &track : tracks) {
        if (!appendTrack(bytes, track))
            return {};
    }
    return bytes;
}

TransportMidiFile buildSilentSong()
{
    TransportMidiFile midi;
    midi.division = kDivision;
    midi.tracks.resize(3);

    TransportMidiTrack &conductor = midi.tracks[0];
    conductor.events.push_back(tempoEvent());
    conductor.endTick = 4800;

    TransportMidiTrack &t0 = midi.tracks[1];
    t0.events.push_back(channelEvent(0, 0xC0, 0, 0));
    t0.events.push_back(channelEvent(4800, 0xB0, 7, 100)); // 100 s at 120 BPM
    t0.endTick = 4800;

    TransportMidiTrack &t1 = midi.tracks[2];
    t1.events.push_back(channelEvent(0, 0xC1, 1, 0));
    t1.endTick = 4800;

    return midi;
}

TransportMidiFile buildNoteSong(uint8_t program)
{
    TransportMidiFile midi;
    midi.division = kDivision;
    midi.tracks.resize(2);

    TransportMidiTrack &conductor = midi.tracks[0];
    conductor.events.push_back(tempoEvent());
    conductor.endTick = 4800;

    TransportMidiTrack &t0 = midi.tracks[1];
    t0.events.push_back(channelEvent(0, 0xC0, program, 0));
    t0.events.push_back(channelEvent(0, 0x90, 60, 127));
    t0.events.push_back(channelEvent(4800, 0x80, 60, 0));
    t0.endTick = 4800;

    return midi;
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
