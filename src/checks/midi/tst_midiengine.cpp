#include "checks/midi/tst_midiengine.h"
#include "checks/fwd.hpp"

#include <QtTest>

#include <array>
#include <cstdint>

extern "C" {
#include "m4a_engine.h"
}

namespace {

class EngineFixture final
{
  public:
    EngineFixture() { m4a_engine_init(&m_engine, 48000.0F); }
    ~EngineFixture() { m4a_engine_destroy(&m_engine); }

    M4AEngine &engine() noexcept { return m_engine; }

    EngineFixture(const EngineFixture &) = delete;
    EngineFixture &operator=(const EngineFixture &) = delete;

  private:
    M4AEngine m_engine = {};
};

void installKeysplitVoicegroup(M4AEngine &engine, std::array<ToneData, 128> &voices,
                               std::array<ToneData, 128> &sub, std::array<uint8_t, 128> &splitTable)
{
    voices[5].type = VOICE_KEYSPLIT;
    voices[5].subGroup = sub.data();
    voices[5].keySplitTable = splitTable.data();
    m4a_engine_set_voicegroup(&engine, voices.data());
}

} // namespace

namespace checks {

void MidiEngineBoundsTest::programChangesRejectOutOfRangeValues()
{
    auto voices = std::array<ToneData, 128>{};
    auto sub = std::array<ToneData, 128>{};
    auto splitTable = std::array<uint8_t, 128>{};
    auto fixture = EngineFixture{};
    installKeysplitVoicegroup(fixture.engine(), voices, sub, splitTable);

    m4a_engine_program_change(&fixture.engine(), 0, 5);
    QCOMPARE(int(fixture.engine().tracks[0].currentProgram), 5);
    m4a_engine_program_change(&fixture.engine(), 0, 128);
    m4a_engine_program_change(&fixture.engine(), 0, 255);
    QCOMPARE(int(fixture.engine().tracks[0].currentProgram), 5);
}

void MidiEngineBoundsTest::noteOnsRejectOutOfRangeKeys()
{
    auto voices = std::array<ToneData, 128>{};
    auto sub = std::array<ToneData, 128>{};
    auto splitTable = std::array<uint8_t, 128>{};
    auto fixture = EngineFixture{};
    installKeysplitVoicegroup(fixture.engine(), voices, sub, splitTable);
    m4a_engine_program_change(&fixture.engine(), 0, 5);

    m4a_engine_note_on(&fixture.engine(), 0, 128, 100);
    m4a_engine_note_on(&fixture.engine(), 0, 255, 100);
    m4a_engine_note_off(&fixture.engine(), 0, 255);
    for (int channel = 0; channel < TOTAL_PCM_CHANNELS; ++channel)
        QVERIFY((fixture.engine().pcmChannels[channel].status & CHN_ON) == 0);
}

} // namespace checks

int runMidiEngineCheck(const QStringList &qtArguments)
{
    checks::MidiEngineBoundsTest test;
    QStringList arguments{QStringLiteral("midienginecheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
