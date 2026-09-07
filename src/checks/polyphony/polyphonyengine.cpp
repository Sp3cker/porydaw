#include "checks/polyphony/tst_polyphonycheck.h"

#include <QByteArray>
#include <QtTest>

#include <algorithm>
#include <array>
#include <cmath>
#include <span>

#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/timelineplayer.h"

extern "C" {
#include "m4a_engine.h"
}

namespace {

constexpr uint32_t kDivision = 24;
constexpr double kSampleRate = 48000.0;
constexpr uint64_t kSamplesPerTick = 1000;
constexpr uint64_t kHoldOnTick = 24;
constexpr uint64_t kHoldOffTick = 216;
constexpr uint64_t kStealTick = 96;
constexpr uint64_t kDropTick = 120;
constexpr uint64_t kStealOffTick = 144;
constexpr uint64_t kTailCutTick = 148;
constexpr uint8_t kHoldKey = 62;
constexpr uint8_t kStealKey = 60;
constexpr uint8_t kDropKey = 64;
constexpr uint8_t kTailKey = 65;
constexpr uint32_t kRenderChunk = 500;
constexpr uint64_t kRenderSamples = 220000;
constexpr uint64_t kGateModeTick = 24;
constexpr uint64_t kGateOffTick = 96;
constexpr uint64_t kGateRenderTicks = 49;
constexpr uint8_t kGateKey = 60;

SmfEvent channelEvent(uint64_t tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    SmfEvent event;
    event.tick = tick;
    event.status = status;
    event.data0 = data0;
    event.data1 = data1;
    return event;
}

SmfEvent tempoEvent()
{
    SmfEvent event;
    event.tick = 0;
    event.status = 0xFF;
    event.metaType = 0x51;
    event.blob = QByteArray("\x07\xA1\x20", 3);
    return event;
}

SmfFile overflowSong()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = kDivision;
    smf.tracks.resize(5);
    smf.tracks[0].events.push_back(tempoEvent());
    smf.tracks[0].endTick = 384;

    struct NoteSpec {
        uint64_t on;
        uint64_t off;
        uint8_t key;
    };
    const std::array<NoteSpec, 4> notes = {{{kStealTick, kStealOffTick, kStealKey},
                                            {kHoldOnTick, kHoldOffTick, kHoldKey},
                                            {kDropTick, 200, kDropKey},
                                            {kTailCutTick, kHoldOffTick, kTailKey}}};
    for (int track = 0; track < 4; ++track) {
        SmfTrack &target = smf.tracks[track + 1];
        target.events = {channelEvent(0, 0xC0, 0, 0),
                         channelEvent(notes[track].on, 0x90, notes[track].key, 100),
                         channelEvent(notes[track].off, 0x80, notes[track].key, 0)};
        target.endTick = 384;
    }
    return smf;
}

struct TestVoicegroup {
    std::array<int8_t, 65> sample{};
    WaveData wave{};
    std::array<ToneData, 128> voices{};

    TestVoicegroup()
    {
        for (int index = 0; index < 64; ++index)
            sample[index] = index < 32 ? 100 : -100;
        sample[64] = sample[63];
        wave.status = 0xC000;
        wave.freq = 8363u * 1024u;
        wave.size = 64;
        wave.data = sample.data();
        for (ToneData &voice : voices) {
            voice.type = VOICE_DIRECTSOUND;
            voice.key = 60;
            voice.wav = &wave;
            voice.attack = 255;
            voice.sustain = 255;
            voice.release = 165;
        }
    }
};

class EngineFixture final
{
  public:
    EngineFixture()
    {
        m4a_engine_init(&engine, float(kSampleRate));
        m4a_engine_set_voicegroup(&engine, voicegroup.voices.data());
        engine.maxPcmChannels = 1;
    }

    ~EngineFixture() { m4a_engine_destroy(&engine); }

    EngineFixture(const EngineFixture &) = delete;
    EngineFixture &operator=(const EngineFixture &) = delete;

    M4AEngine engine{};
    TestVoicegroup voicegroup;
};

struct RenderResult {
    float maxBeforeSteal = 0.0f;
    float maxAfterSteal = 0.0f;
    bool shadowOnAfterSteal = false;
};

RenderResult renderSong(M4AEngine &engine, const MidiTimeline &timeline)
{
    TimelinePlayer player;
    player.reset();
    RenderResult result;
    std::array<float, kRenderChunk> left{};
    std::array<float, kRenderChunk> right{};
    const uint64_t stealSample = kStealTick * kSamplesPerTick;
    uint64_t rendered = 0;
    while (rendered < kRenderSamples) {
        player.render(&engine, &timeline, std::span(left), std::span(right), false, 0);
        float peak = 0.0f;
        for (uint32_t index = 0; index < kRenderChunk; ++index)
            peak = std::max({peak, std::fabs(left[index]), std::fabs(right[index])});
        if (rendered + kRenderChunk <= stealSample)
            result.maxBeforeSteal = std::max(result.maxBeforeSteal, peak);
        else
            result.maxAfterSteal = std::max(result.maxAfterSteal, peak);
        rendered += kRenderChunk;
        if (rendered == stealSample + 4000) {
            for (int channel = MAX_PCM_CHANNELS; channel < TOTAL_PCM_CHANNELS; ++channel) {
                if ((engine.pcmChannels[channel].status & CHN_ON) != 0)
                    result.shadowOnAfterSteal = true;
            }
        }
    }
    return result;
}

std::unique_ptr<MidiTimeline> timeline()
{
    return MidiTimeline::build(overflowSong(), kSampleRate);
}

} // namespace

namespace checks {

void PolyphonyGateTest::overflowCountersAndRing()
{
    const std::unique_ptr<MidiTimeline> songTimeline = timeline();
    QVERIFY(songTimeline);
    QCOMPARE(songTimeline->usedTrackCount, 4);
    EngineFixture fixture;
    renderSong(fixture.engine, *songTimeline);

    QCOMPARE(fixture.engine.polyEventTotal, uint32_t(3));
    QCOMPARE(fixture.engine.polyStealCount[1], uint32_t(1));
    QCOMPARE(fixture.engine.polyDropCount[2], uint32_t(1));
    QCOMPARE(fixture.engine.polyTailCutCount[0], uint32_t(1));
    uint64_t totalCounters = 0;
    for (int track = 0; track < MAX_TRACKS; ++track) {
        totalCounters += fixture.engine.polyDropCount[track] +
                         fixture.engine.polyStealCount[track] +
                         fixture.engine.polyTailCutCount[track];
    }
    QCOMPARE(totalCounters, uint64_t(3));
    struct ExpectedEvent {
        uint8_t type;
        uint8_t track;
        uint8_t key;
        uint8_t byTrack;
        uint32_t tick;
    };
    const std::array<ExpectedEvent, 3> expected = {{
        {M4A_POLY_STOLEN, 1, kHoldKey, 0, uint32_t(kStealTick)},
        {M4A_POLY_DROPPED, 2, kDropKey, 2, uint32_t(kDropTick)},
        {M4A_POLY_TAIL_CUT, 0, kStealKey, 3, uint32_t(kTailCutTick)},
    }};
    for (std::size_t index = 0; index < expected.size(); ++index) {
        const M4APolyEvent &event = fixture.engine.polyEvents[index];
        QCOMPARE(event.type, expected[index].type);
        QCOMPARE(event.trackIndex, expected[index].track);
        QCOMPARE(event.midiKey, expected[index].key);
        QCOMPARE(event.byTrack, expected[index].byTrack);
        QCOMPARE(event.tick, expected[index].tick);
    }
}

void PolyphonyGateTest::liveSentinelTick()
{
    EngineFixture fixture;
    m4a_engine_program_change(&fixture.engine, 0, 0);
    m4a_engine_program_change(&fixture.engine, 1, 0);
    m4a_engine_note_on(&fixture.engine, 1, 60, 100);
    m4a_engine_note_on(&fixture.engine, 0, 67, 100);

    QCOMPARE(fixture.engine.polyEventTotal, uint32_t(1));
    QCOMPARE(fixture.engine.polyEvents[0].tick, uint32_t(M4A_POLY_TICK_NONE));
}

void PolyphonyGateTest::normalPlaybackKeepsShadowPoolOff()
{
    const std::unique_ptr<MidiTimeline> songTimeline = timeline();
    QVERIFY(songTimeline);
    EngineFixture fixture;
    const RenderResult result = renderSong(fixture.engine, *songTimeline);

    QVERIFY2(result.maxBeforeSteal > 1e-4f, qPrintable(QString::number(result.maxBeforeSteal)));
    QVERIFY2(result.maxAfterSteal > 1e-4f, qPrintable(QString::number(result.maxAfterSteal)));
    QVERIFY(!result.shadowOnAfterSteal);
}

void PolyphonyGateTest::invertSilencesUntilOverflowAndClearsShadow()
{
    const std::unique_ptr<MidiTimeline> songTimeline = timeline();
    QVERIFY(songTimeline);
    EngineFixture fixture;
    m4a_engine_set_poly_debug_invert(&fixture.engine, true);
    // Sequenced dispatch must clear a preview note struck before playback begins.
    fixture.engine.auditionNote = true;
    const RenderResult result = renderSong(fixture.engine, *songTimeline);
    QVERIFY2(result.maxBeforeSteal < 1e-6f, qPrintable(QString::number(result.maxBeforeSteal)));
    QVERIFY2(result.maxAfterSteal > 1e-4f, qPrintable(QString::number(result.maxAfterSteal)));
    QVERIFY(result.shadowOnAfterSteal);
    m4a_engine_set_poly_debug_invert(&fixture.engine, false);
    for (int channel = MAX_PCM_CHANNELS; channel < TOTAL_PCM_CHANNELS; ++channel)
        QCOMPARE(fixture.engine.pcmChannels[channel].status, uint8_t(0));
}

void PolyphonyGateTest::auditionRemainsAudibleWithInvert()
{
    EngineFixture fixture;
    m4a_engine_set_poly_debug_invert(&fixture.engine, true);
    m4a_engine_program_change(&fixture.engine, 0, 0);
    fixture.engine.polyEventClock = M4A_POLY_TICK_NONE;
    fixture.engine.auditionNote = true;
    m4a_engine_note_on(&fixture.engine, 0, 60, 100);
    std::array<float, kRenderChunk> left{};
    std::array<float, kRenderChunk> right{};
    float peak = 0.0f;
    for (int chunk = 0; chunk < 8; ++chunk) {
        m4a_engine_process(&fixture.engine, left.data(), right.data(), kRenderChunk);
        for (uint32_t index = 0; index < kRenderChunk; ++index)
            peak = std::max({peak, std::fabs(left[index]), std::fabs(right[index])});
    }
    QVERIFY2(peak > 1e-4f, qPrintable(QString::number(peak)));
}

void PolyphonyGateTest::channelModeLeavesCompiledGateIntact_data()
{
    QTest::addColumn<int>("controller");

    QTest::newRow("allNotesOff") << 0x7B;
    QTest::newRow("allSoundOff") << 0x78;
}

void PolyphonyGateTest::channelModeLeavesCompiledGateIntact()
{
    QFETCH(int, controller);

    SmfFile smf;
    smf.format = 1;
    smf.division = kDivision;
    smf.tracks.resize(2);
    smf.tracks[0].events.push_back(tempoEvent());
    SmfTrack &track = smf.tracks[1];
    track.events = {channelEvent(0, 0xC0, 0, 0), channelEvent(0, 0x90, kGateKey, 100),
                    channelEvent(kGateModeTick, 0xB0, uint8_t(controller), 0),
                    channelEvent(kGateOffTick, 0x80, kGateKey, 0)};
    const std::unique_ptr<MidiTimeline> songTimeline = MidiTimeline::build(smf, kSampleRate);
    QVERIFY(songTimeline);

    EngineFixture fixture;
    TimelinePlayer player;
    player.reset();
    std::array<float, kRenderChunk> left{};
    std::array<float, kRenderChunk> right{};
    for (uint64_t rendered = 0; rendered < kGateRenderTicks * kSamplesPerTick;
         rendered += kRenderChunk)
        player.render(&fixture.engine, songTimeline.get(), std::span(left), std::span(right), false,
                      0);

    float peak = 0.0f;
    for (uint32_t index = 0; index < kRenderChunk; ++index)
        peak = std::max({peak, std::fabs(left[index]), std::fabs(right[index])});
    QVERIFY2(peak > 0.01f, qPrintable(QString::number(peak)));
}

} // namespace checks
