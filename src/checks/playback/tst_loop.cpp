#include "checks/playback/tst_loop.h"
#include <QByteArray>

#include <QTest>
#include <QVariant>
#include <algorithm>
#include <cstring>
#include <span>

#include "checks/playback/sustainvoicegroup.h"
#include "core/miditimeline.h"
#include "core/smf.h"

extern "C" {
#include "m4a_engine.h"
}

namespace checks {
namespace {

// 24 ticks per quarter, 4/4, 120 BPM: one tick is 500000/24 us, which at
// 48kHz is exactly 1000 samples — probe positions below rely on this.
constexpr uint32_t kDivision = 24;
constexpr double kSampleRate = 48000.0;
constexpr uint64_t kSamplesPerTick = 1000;

constexpr uint64_t kLoopStartTick = 96; // measure 2
constexpr uint64_t kLoopEndTick = 288;  // downbeat of measure 4
constexpr uint8_t kBodyKey = 60;        // ticks 96-120, plays every pass
constexpr uint8_t kEndsAtKey = 62;      // ticks 264-288, off exactly at loop end
constexpr uint8_t kSpansKey = 65;       // ticks 240-300, crosses the loop end (60
                                        // clocks: direct note -> gate-carry)
constexpr uint8_t kBoundaryKey = 64;    // ticks 288-312, the reported stuck note
constexpr uint8_t kTieKey = 67;         // ticks 192-312, crosses the loop end (120
                                        // clocks: TIE + EOT -> held forever)

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

// A looping song exercising every note/loop-boundary relationship: a normal
// body note, a note ending exactly at the loop end, short and long notes
// spanning the loop end, and a note starting exactly at the loop end (the
// downbeat of the next measure).
SmfFile buildLoopSong()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = kDivision;
    smf.tracks.resize(2);

    SmfTrack &conductor = smf.tracks[0];
    conductor.events.push_back(metaEvent(0, 0x51, QByteArray("\x07\xA1\x20", 3)));
    conductor.events.push_back(metaEvent(kLoopStartTick, 0x01, QByteArray("[")));
    conductor.events.push_back(metaEvent(kLoopEndTick, 0x01, QByteArray("]")));
    conductor.endTick = 384;

    SmfTrack &notes = smf.tracks[1];
    auto note = [&notes](uint64_t on, uint64_t off, uint8_t key) {
        notes.events.push_back(channelEvent(on, 0x90, key, 100));
        notes.events.push_back(channelEvent(off, 0x80, key, 0));
    };
    notes.events.push_back(channelEvent(0, 0xC0, 0, 0));
    note(96, 120, kBodyKey);
    note(192, 312, kTieKey);
    note(240, 300, kSpansKey);
    note(264, 288, kEndsAtKey);
    note(288, 312, kBoundaryKey);
    std::sort(notes.events.begin(), notes.events.end(),
              [](const SmfEvent &a, const SmfEvent &b) { return a.tick < b.tick; });
    notes.endTick = 384;

    return smf;
}

// Keys of PCM channels that are keyed on (started and not yet released).
std::vector<uint8_t> keyedOnKeys(const M4AEngine &engine)
{
    std::vector<uint8_t> keys;
    for (int i = 0; i < TOTAL_PCM_CHANNELS; i++) {
        const M4APCMChannel &ch = engine.pcmChannels[i];
        if ((ch.status & CHN_ON) && !(ch.status & CHN_STOP))
            keys.push_back(ch.midiKey);
    }
    std::sort(keys.begin(), keys.end());
    return keys;
}

std::vector<uint8_t> keySet(const QVariantList &keys)
{
    std::vector<uint8_t> result;
    result.reserve(keys.size());
    for (const QVariant &key : keys)
        result.push_back(uint8_t(key.toInt()));
    return result;
}

} // namespace

LoopTest::LoopTest() = default;

LoopTest::~LoopTest() = default;

void LoopTest::init()
{
    auto timeline = MidiTimeline::build(buildLoopSong(), kSampleRate);
    QVERIFY2(timeline, "synthesized song built wrong");
    // Fail the row fast with the shape message when the markers break,
    // instead of letting every row fail with confusing key mismatches.
    QVERIFY2(timeline->hasLoop() && timeline->loopStartSample == kLoopStartTick * kSamplesPerTick &&
                 timeline->loopEndSample == kLoopEndTick * kSamplesPerTick,
             "synthesized song has wrong loop points");
    m_timeline = std::move(timeline);
    // The bank is borrowed raw, so it must outlive the engine; declare and
    // destroy it in the opposite order.
    m_bank = std::make_unique<SustainVoicegroup>();
    m_engine = std::make_unique<M4AEngine>();
    m4a_engine_init(m_engine.get(), float(kSampleRate));
    m4a_engine_set_voicegroup(m_engine.get(), m_bank->voices);
    m_player.reset();
    m_rendered = 0;
}

void LoopTest::cleanup()
{
    if (m_engine)
        m4a_engine_destroy(m_engine.get());
    m_engine.reset();
    m_bank.reset();
    m_timeline.reset();
    m_rendered = 0;
}

void LoopTest::synthesizedLoopSongHasExactLoopPoints()
{
    QVERIFY2(m_timeline->hasLoop(), "synthesized song has no loop");
    QCOMPARE(m_timeline->loopStartSample, kLoopStartTick * kSamplesPerTick);
    QCOMPARE(m_timeline->loopEndSample, kLoopEndTick * kSamplesPerTick);
}

std::vector<uint8_t> LoopTest::renderAndProbe(uint64_t samplePos, bool looping)
{
    constexpr uint32_t kChunk = 512;
    float bufL[kChunk], bufR[kChunk];
    while (m_rendered < samplePos) {
        const auto n = uint32_t(std::min<uint64_t>(kChunk, samplePos - m_rendered));
        m_player.render(m_engine.get(), m_timeline.get(), std::span(bufL).first(n),
                        std::span(bufR).first(n), looping, 0);
        m_rendered += n;
    }
    return keyedOnKeys(*m_engine);
}

void LoopTest::loopWrapMatchesHardwareGoto_data()
{
    QTest::addColumn<uint64_t>("samplePos");
    QTest::addColumn<bool>("looping");
    QTest::addColumn<QVariantList>("expectedKeys");

    const uint64_t loopLen = (kLoopEndTick - kLoopStartTick) * kSamplesPerTick;
    // The quiet-zone probes sit after the body note's release and before the
    // short spanning note starts, where only the tied note may sound — one
    // held instance per completed pass. The short spanning note (ticks
    // 240-300) gate-carries across the wrap at tick 288 and releases at its
    // full written duration — global sample 300000 — so it is still keyed at
    // 298000 and gone by 310000.
    QTest::newRow("pass-1-tied-note-sounds") << uint64_t(200000) << true << QVariantList{kTieKey};
    QTest::newRow("pass-2-gate-carry-holds-across-wrap")
        << uint64_t(298000) << true << QVariantList{kBodyKey, kSpansKey, kTieKey};
    QTest::newRow("gate-carry-releases-at-written-duration")
        << uint64_t(310000) << true << QVariantList{kBodyKey, kTieKey};
    QTest::newRow("pass-2-tied-note-stacks")
        << uint64_t(200000 + loopLen) << true << QVariantList{kTieKey, kTieKey};
    QTest::newRow("pass-3-tied-note-stacks")
        << uint64_t(200000 + 2 * loopLen) << true << QVariantList{kTieKey, kTieKey, kTieKey};
    // Not looping: playback runs straight through, so the note at the loop
    // end and both notes spanning it sound normally.
    QTest::newRow("loop-boundary-notes-play-without-looping")
        << uint64_t(298000) << false << QVariantList{kBoundaryKey, kSpansKey, kTieKey};
}

void LoopTest::loopWrapMatchesHardwareGoto()
{
    QFETCH(uint64_t, samplePos);
    QFETCH(bool, looping);
    QFETCH(QVariantList, expectedKeys);

    const auto keys = renderAndProbe(samplePos, looping);
    const auto expected = keySet(expectedKeys);
    if (keys != expected) {
        QString actualKeys;
        for (uint8_t k : keys)
            actualKeys += QStringLiteral(" %1").arg(k);
        QString expectedText;
        for (uint8_t k : expected)
            expectedText += QStringLiteral(" %1").arg(k);
        QFAIL(qPrintable(QStringLiteral("keyed-on notes at t=%1 (looping=%2): [%3 ], expected "
                                        "[%4 ]")
                             .arg(samplePos)
                             .arg(looping)
                             .arg(actualKeys, expectedText)));
    }
}

} // namespace checks

int runLoopCheck(const QStringList &qtArguments)
{
    checks::LoopTest test;
    QStringList arguments{QStringLiteral("loopcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
