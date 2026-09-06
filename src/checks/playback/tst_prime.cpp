#include "checks/playback/tst_prime.h"
#include <QByteArray>

#include <QTest>
#include <cstring>

#include "checks/playback/sustainvoicegroup.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/timelineplayer.h"

extern "C" {
#include "m4a_engine.h"
}

namespace checks {
namespace {

// 24 ticks per quarter, 120 BPM at 48kHz: one tick is exactly 1000 samples.
constexpr uint32_t kDivision = 24;
constexpr double kSampleRate = 48000.0;
constexpr uint64_t kSamplesPerTick = 1000;

constexpr uint8_t kProgAtZero = 5; // engine track 0, tick 0
constexpr uint8_t kProgLater = 9;  // engine track 0, tick 96
constexpr uint8_t kProgTrack1 = 7; // engine track 1, tick 48 (its first)
constexpr uint64_t kLaterTick = 96;

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

// A song covering the three track shapes: a voice at tick 0 (replaced
// later), a first voice only at tick 48, and notes with no voice anywhere.
SmfFile buildPrimeSong()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = kDivision;
    smf.tracks.resize(4);

    SmfTrack &conductor = smf.tracks[0];
    conductor.events.push_back(metaEvent(0, 0x51, QByteArray("\x07\xA1\x20", 3)));
    conductor.endTick = 192;

    // Engine track 0: voice at tick 0, replaced later — chase must win over
    // priming.
    SmfTrack &t0 = smf.tracks[1];
    t0.events.push_back(channelEvent(0, 0xC0, kProgAtZero, 0));
    t0.events.push_back(channelEvent(0, 0x90, 60, 100));
    t0.events.push_back(channelEvent(24, 0x80, 60, 0));
    t0.events.push_back(channelEvent(kLaterTick, 0xC0, kProgLater, 0));
    t0.endTick = 192;

    // Engine track 1: first voice only at tick 48 — the priming case.
    SmfTrack &t1 = smf.tracks[2];
    t1.events.push_back(channelEvent(48, 0xC1, kProgTrack1, 0));
    t1.events.push_back(channelEvent(48, 0x91, 62, 100));
    t1.events.push_back(channelEvent(72, 0x81, 62, 0));
    t1.endTick = 192;

    // Engine track 2: notes but no voice anywhere — must stay untouched.
    SmfTrack &t2 = smf.tracks[3];
    t2.events.push_back(channelEvent(0, 0x92, 64, 100));
    t2.events.push_back(channelEvent(24, 0x82, 64, 0));
    t2.endTick = 192;

    return smf;
}

} // namespace

PrimeTest::PrimeTest() = default;

PrimeTest::~PrimeTest() = default;

void PrimeTest::init()
{
    auto timeline = MidiTimeline::build(buildPrimeSong(), kSampleRate);
    QVERIFY2(timeline && timeline->usedTrackCount == 3, "synthesized song built wrong");
    m_timeline = std::move(timeline);
    // The bank is borrowed raw, so it must outlive the engine.
    m_bank = std::make_unique<SustainVoicegroup>();
    m_engine = std::make_unique<M4AEngine>();
    m4a_engine_init(m_engine.get(), float(kSampleRate));
    m4a_engine_set_voicegroup(m_engine.get(), m_bank->voices);
}

void PrimeTest::cleanup()
{
    if (m_engine)
        m4a_engine_destroy(m_engine.get());
    m_engine.reset();
    m_bank.reset();
    m_timeline.reset();
}

bool PrimeTest::rendersAudibly()
{
    constexpr uint32_t kChunkFrames = 512;
    constexpr uint32_t kMaximumFrames = 4096;
    float bufL[kChunkFrames], bufR[kChunkFrames];
    for (uint32_t rendered = 0; rendered < kMaximumFrames; rendered += kChunkFrames) {
        m4a_engine_process(m_engine.get(), bufL, bufR, int(kChunkFrames));
        for (uint32_t i = 0; i < kChunkFrames; i++) {
            if (bufL[i] != 0.0f || bufR[i] != 0.0f)
                return true;
        }
    }
    return false;
}

void PrimeTest::unprimedTrackAuditionIsSilent()
{
    TimelinePlayer::chase(m_engine.get(), m_timeline.get(), 0);
    m4a_engine_note_on(m_engine.get(), 1, 60, 127);
    QVERIFY2(!rendersAudibly(),
             "unprimed track 1 audition was audible (control expectation changed?)");
}

void PrimeTest::primeVoicesApplyTrackPrograms_data()
{
    QTest::addColumn<int>("track");
    QTest::addColumn<int>("expectedProgram");
    QTest::addColumn<bool>("expectPrimed");

    QTest::newRow("chase-applied-voice-not-overridden") << 0 << int(kProgAtZero) << true;
    QTest::newRow("later-voice-primed-at-load") << 1 << int(kProgTrack1) << true;
    QTest::newRow("voiceless-track-never-primed") << 2 << -1 << false;
}

void PrimeTest::primeVoicesApplyTrackPrograms()
{
    QFETCH(int, track);
    QFETCH(int, expectedProgram);
    QFETCH(bool, expectPrimed);

    TimelinePlayer::chase(m_engine.get(), m_timeline.get(), 0);
    TimelinePlayer::primeVoices(m_engine.get(), m_timeline.get(), 0);

    const M4ATrack &t = m_engine->tracks[track];
    if (expectPrimed) {
        QCOMPARE(t.currentProgram, uint8_t(expectedProgram));
        QVERIFY2(t.currentVoice.wav != nullptr, "primed track has no wave");
    } else {
        QVERIFY2(t.currentVoice.wav == nullptr, "track with no voice event was primed anyway");
    }
}

void PrimeTest::primedTrackAuditionIsAudible()
{
    TimelinePlayer::chase(m_engine.get(), m_timeline.get(), 0);
    TimelinePlayer::primeVoices(m_engine.get(), m_timeline.get(), 0);
    m4a_engine_note_on(m_engine.get(), 1, 60, 127);
    QVERIFY2(rendersAudibly(), "primed track 1 audition was silent");
}

void PrimeTest::midSongChaseSuppliesAllPrograms()
{
    const uint64_t pos = (kLaterTick + 4) * kSamplesPerTick;
    TimelinePlayer::chase(m_engine.get(), m_timeline.get(), pos);
    TimelinePlayer::primeVoices(m_engine.get(), m_timeline.get(), pos);

    QCOMPARE(m_engine->tracks[0].currentProgram, kProgLater);
    QVERIFY2(m_engine->tracks[0].currentVoice.wav != nullptr,
             "mid-song chase left track 0 without a wave");
    QCOMPARE(m_engine->tracks[1].currentProgram, kProgTrack1);
    QVERIFY2(m_engine->tracks[1].currentVoice.wav != nullptr,
             "mid-song chase left track 1 without a wave");
}

} // namespace checks

int runPrimeCheck(const QStringList &qtArguments)
{
    checks::PrimeTest test;
    QStringList arguments{QStringLiteral("primecheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
