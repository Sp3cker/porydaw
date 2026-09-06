#include "checks/midi/tst_midismf.h"

#include <QByteArray>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QtTest>

#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

#include "core/smf.h"
#include "core/songdocument.h"

extern "C" {
#include "m4a_engine.h"
}

namespace {

void appendU32(QByteArray &out, uint32_t value)
{
    out.append(char(value >> 24));
    out.append(char(value >> 16));
    out.append(char(value >> 8));
    out.append(char(value));
}

void appendU16(QByteArray &out, uint16_t value)
{
    out.append(char(value >> 8));
    out.append(char(value));
}

QByteArray format0Bytes(const QByteArray &trackBody)
{
    auto bytes = QByteArray{"MThd"};
    appendU32(bytes, 6);
    appendU16(bytes, 0);
    appendU16(bytes, 1);
    appendU16(bytes, 24);
    bytes.append("MTrk");
    appendU32(bytes, uint32_t(trackBody.size()));
    bytes.append(trackBody);
    return bytes;
}

SmfEvent channelEvent(uint64_t tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    auto event = SmfEvent{};
    event.tick = tick;
    event.status = status;
    event.data0 = data0;
    event.data1 = data1;
    return event;
}

QString fixturePath(const char *relativePath)
{
    return QStringLiteral(":/checks/test_midis/smf/") + QString::fromLatin1(relativePath);
}

bool sameSmf(const SmfFile &left, const SmfFile &right)
{
    if (left.format != right.format || left.division != right.division ||
        left.tracks.size() != right.tracks.size()) {
        return false;
    }
    for (size_t index = 0; index < left.tracks.size(); ++index) {
        if (left.tracks[index].endTick != right.tracks[index].endTick ||
            left.tracks[index].events != right.tracks[index].events) {
            return false;
        }
    }
    return true;
}

bool semanticReparseMatches(const SmfFile &smf, QString &error)
{
    error.clear();
    auto reread = SmfFile{};
    if (!SmfFile::read(smf.write(), &reread, &error))
        return false;
    if (!sameSmf(smf, reread)) {
        error = QStringLiteral("semantic write/re-read mismatch");
        return false;
    }
    return true;
}

bool loadDocumentFromSmf(const SmfFile &smf, const QString &path, SongDocument &document,
                         QString &error)
{
    auto song = SongInfo{};
    song.label = QFileInfo(path).baseName();
    song.midPath = path;
    song.hasMid = true;
    return smf.writeFile(path, &error) && document.load(song, &error);
}

int engineTrackForChunk(const SongDocument &document, int chunk)
{
    for (int track = 0; track < document.engineTrackCount(); ++track) {
        if (document.smfTrackFor(track) == chunk)
            return track;
    }
    return -1;
}

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

void MidiSmfTest::validFormat0ParsingAndCoercion()
{
    const auto body = QByteArray::fromHex("00903c4010803c4000c07f00ff2f00");
    auto smf = SmfFile{};
    auto error = QString{};

    QVERIFY2(SmfFile::read(format0Bytes(body), &smf, &error), qPrintable(error));
    QCOMPARE(int(smf.format), 1);
    QVERIFY(smf.wasFormat0);
}

void MidiSmfTest::highDataBytesKeepStreamAlignment()
{
    const auto body = QByteArray::fromHex("00c08000903c4000b00780000a4000ff2f00");
    auto smf = SmfFile{};
    auto error = QString{};

    QVERIFY2(SmfFile::read(format0Bytes(body), &smf, &error), qPrintable(error));
    QVERIFY2(smf.tracks.size() == 2,
             "format-0 conversion did not create conductor and channel tracks");
    const auto &events = smf.tracks[1].events;
    QVERIFY2(events.size() == 4, "high-data-byte stream changed event count");

    QCOMPARE(int(events[0].status), 0xC0);
    QCOMPARE(int(events[0].data0), 0x80);
    QCOMPARE(int(events[0].data1), 0);
    QCOMPARE(int(events[1].status), 0x90);
    QCOMPARE(int(events[1].data0), 0x3C);
    QCOMPARE(int(events[1].data1), 0x40);
    QCOMPARE(int(events[2].status), 0xB0);
    QCOMPARE(int(events[2].data0), 0x07);
    QCOMPARE(int(events[2].data1), 0x80);
    QCOMPARE(int(events[3].status), 0xB0);
    QCOMPARE(int(events[3].data0), 0x0A);
    QCOMPARE(int(events[3].data1), 0x40);
}

void MidiSmfTest::opaqueSysExAndMetaEventsRoundTrip()
{
    auto smf = SmfFile{};
    auto error = QString{};
    constexpr auto kFixture = "valid/opaque_sysex.mid";

    QVERIFY2(SmfFile::readFile(fixturePath(kFixture), &smf, &error), qPrintable(error));
    QCOMPARE(int(smf.format), 1);
    QCOMPARE(int(smf.division), 48);
    QVERIFY2(smf.tracks.size() == 2, "opaque SysEx fixture must have two tracks");

    const auto &conductor = smf.tracks[0];
    const auto &notes = smf.tracks[1];
    QCOMPARE(qulonglong(conductor.endTick), qulonglong(0));
    QVERIFY2(conductor.events.size() == 4, "opaque SysEx conductor event count changed");
    QCOMPARE(qulonglong(notes.endTick), qulonglong(24));
    QVERIFY2(notes.events.size() == 2, "opaque SysEx note event count changed");

    QCOMPARE(int(conductor.events[1].status), 0xF0);
    QCOMPARE(conductor.events[1].blob, QByteArray::fromHex("7e7f0903f7"));
    QCOMPARE(int(conductor.events[2].status), 0xFF);
    QCOMPARE(int(conductor.events[2].metaType), 0x7F);
    QCOMPARE(conductor.events[2].blob, QByteArray::fromHex("deadbeef"));
    QCOMPARE(int(conductor.events[3].status), 0xF7);
    QCOMPARE(conductor.events[3].blob, QByteArray::fromHex("4312f7"));

    QCOMPARE(qulonglong(notes.events[0].tick), qulonglong(0));
    QCOMPARE(int(notes.events[0].status), 0x90);
    QCOMPARE(int(notes.events[0].data0), 0x3C);
    QCOMPARE(int(notes.events[0].data1), 0x40);
    QCOMPARE(qulonglong(notes.events[1].tick), qulonglong(24));
    QCOMPARE(int(notes.events[1].status), 0x90);
    QCOMPARE(int(notes.events[1].data0), 0x3C);
    QCOMPARE(int(notes.events[1].data1), 0);

    QVERIFY2(semanticReparseMatches(smf, error), qPrintable(error));
}

void MidiSmfTest::vlqRunningStatusResetsAcrossMeta()
{
    auto smf = SmfFile{};
    auto error = QString{};
    constexpr auto kFixture = "valid/vlq_running_status.mid";

    QVERIFY2(SmfFile::readFile(fixturePath(kFixture), &smf, &error), qPrintable(error));
    QCOMPARE(int(smf.format), 1);
    QCOMPARE(int(smf.division), 96);
    QVERIFY2(smf.tracks.size() == 2, "VLQ fixture must have two tracks");

    const auto &track = smf.tracks[1];
    QCOMPARE(qulonglong(track.endTick), qulonglong(24835));
    QVERIFY2(track.events.size() == 12, "VLQ/running-status event count changed");

    QCOMPARE(qulonglong(track.events[0].tick), qulonglong(0));
    QCOMPARE(int(track.events[0].status), 0xB0);
    QCOMPARE(int(track.events[0].data0), 0x65);
    QCOMPARE(int(track.events[0].data1), 0);
    QCOMPARE(qulonglong(track.events[1].tick), qulonglong(0));
    QCOMPARE(int(track.events[1].status), 0xB0);
    QCOMPARE(int(track.events[1].data0), 0x64);
    QCOMPARE(int(track.events[1].data1), 1);
    QCOMPARE(qulonglong(track.events[2].tick), qulonglong(0));
    QCOMPARE(int(track.events[2].status), 0xB0);
    QCOMPARE(int(track.events[2].data0), 0x06);
    QCOMPARE(int(track.events[2].data1), 2);
    QCOMPARE(qulonglong(track.events[3].tick), qulonglong(0));
    QCOMPARE(int(track.events[3].status), 0xB0);
    QCOMPARE(int(track.events[3].data0), 0x26);
    QCOMPARE(int(track.events[3].data1), 0);
    QCOMPARE(qulonglong(track.events[4].tick), qulonglong(24611));
    QCOMPARE(int(track.events[4].status), 0xC0);
    QCOMPARE(int(track.events[4].data0), 5);
    QCOMPARE(int(track.events[4].data1), 0);
    QCOMPARE(qulonglong(track.events[5].tick), qulonglong(24611));
    QCOMPARE(int(track.events[5].status), 0xC0);
    QCOMPARE(int(track.events[5].data0), 6);
    QCOMPARE(int(track.events[5].data1), 0);
    QCOMPARE(qulonglong(track.events[6].tick), qulonglong(24611));
    QCOMPARE(int(track.events[6].status), 0xFF);
    QCOMPARE(int(track.events[6].metaType), 1);
    QCOMPARE(track.events[6].blob, QByteArray("X"));
    QCOMPARE(qulonglong(track.events[7].tick), qulonglong(24611));
    QCOMPARE(int(track.events[7].status), 0xC0);
    QCOMPARE(int(track.events[7].data0), 7);
    QCOMPARE(int(track.events[7].data1), 0);
    QCOMPARE(qulonglong(track.events[8].tick), qulonglong(24739));
    QCOMPARE(int(track.events[8].status), 0x90);
    QCOMPARE(int(track.events[8].data0), 0x3C);
    QCOMPARE(int(track.events[8].data1), 0x64);
    QCOMPARE(qulonglong(track.events[9].tick), qulonglong(24739));
    QCOMPARE(int(track.events[9].status), 0x90);
    QCOMPARE(int(track.events[9].data0), 0x3E);
    QCOMPARE(int(track.events[9].data1), 0x50);
    QCOMPARE(qulonglong(track.events[10].tick), qulonglong(24835));
    QCOMPARE(int(track.events[10].status), 0x80);
    QCOMPARE(int(track.events[10].data0), 0x3C);
    QCOMPARE(int(track.events[10].data1), 0);
    QCOMPARE(qulonglong(track.events[11].tick), qulonglong(24835));
    QCOMPARE(int(track.events[11].status), 0x80);
    QCOMPARE(int(track.events[11].data0), 0x3E);
    QCOMPARE(int(track.events[11].data1), 0);

    QVERIFY2(semanticReparseMatches(smf, error), qPrintable(error));
}

void MidiSmfTest::duplicateEndOfTrackCanonicalizes()
{
    auto smf = SmfFile{};
    auto error = QString{};
    constexpr auto kFixture = "malformed/duplicate_eot.mid";

    QVERIFY2(SmfFile::readFile(fixturePath(kFixture), &smf, &error), qPrintable(error));
    QCOMPARE(int(smf.format), 1);
    QCOMPARE(int(smf.division), 24);
    QVERIFY2(smf.tracks.size() == 1, "duplicate-EOT fixture must have one track");
    QVERIFY(smf.tracks[0].events.empty());
    QCOMPARE(qulonglong(smf.tracks[0].endTick), qulonglong(0));

    const auto canonical =
        QByteArray::fromHex("4d546864000000060001000100184d54726b0000000400ff2f00");
    QCOMPARE(smf.write(), canonical);
    QVERIFY2(semanticReparseMatches(smf, error), qPrintable(error));
}

void MidiSmfTest::automationBurstPreservesEveryChannelEvent()
{
    auto smf = SmfFile{};
    auto error = QString{};
    constexpr auto kFixture = "stress/automation_burst.mid";
    constexpr int kGroupCount = 64;
    constexpr size_t kEventsPerGroup = 3;
    constexpr size_t kAutomationEventCount = size_t(kGroupCount) * kEventsPerGroup;
    constexpr size_t kEventTrackEventCount = 1 + kAutomationEventCount + 2;
    constexpr uint64_t kEndTick = 352;

    QVERIFY2(SmfFile::readFile(fixturePath(kFixture), &smf, &error), qPrintable(error));
    QCOMPARE(int(smf.format), 1);
    QCOMPARE(int(smf.division), 96);
    QVERIFY2(smf.tracks.size() == 3, "automation fixture must have conductor plus two channels");

    const auto &conductor = smf.tracks[0];
    QVERIFY2(conductor.events.size() == 2, "automation conductor event count changed");
    QCOMPARE(qulonglong(conductor.endTick), qulonglong(kEndTick));
    QCOMPARE(qulonglong(conductor.events[0].tick), qulonglong(0));
    QCOMPARE(int(conductor.events[0].status), 0xFF);
    QCOMPARE(int(conductor.events[0].metaType), 0x51);
    QCOMPARE(qulonglong(conductor.events[1].tick), qulonglong(0));
    QCOMPARE(int(conductor.events[1].status), 0xFF);
    QCOMPARE(int(conductor.events[1].metaType), 0x58);

    for (int channel = 0; channel < 2; ++channel) {
        const auto &track = smf.tracks[size_t(channel + 1)];
        QVERIFY2(track.events.size() == kEventTrackEventCount,
                 "automation channel event count changed");
        QCOMPARE(qulonglong(track.endTick), qulonglong(kEndTick));
        QCOMPARE(qulonglong(track.events[0].tick), qulonglong(0));
        QCOMPARE(int(track.events[0].status), 0xC0 + channel);
        QCOMPARE(int(track.events[0].data0), channel == 0 ? 5 : 40);
        QCOMPARE(int(track.events[0].data1), 0);

        for (int group = 0; group < kGroupCount; ++group) {
            const size_t base = 1 + size_t(group) * kEventsPerGroup;
            const uint8_t ccStatus = uint8_t(0xB0 + channel);
            const uint8_t bendStatus = uint8_t(0xE0 + channel);
            const uint8_t firstController = uint8_t(channel == 0 ? 7 : 1);
            const uint8_t firstValue = uint8_t(channel == 0 ? 20 + group : (3 * group) & 0x7F);
            const uint8_t secondController = uint8_t(channel == 0 ? 11 : 10);
            const uint8_t secondValue = uint8_t(channel == 0 ? 0x7F - group : 40 + group);
            const uint8_t bendLsb = uint8_t(channel == 0 ? group : (5 * group) & 0x7F);
            const uint8_t bendMsb = uint8_t(channel == 0 ? (2 * group) & 0x7F : (7 * group) & 0x7F);
            const uint64_t tick = uint64_t(4 * group);

            const auto &firstCc = track.events[base];
            QCOMPARE(qulonglong(firstCc.tick), qulonglong(tick));
            QCOMPARE(int(firstCc.status), int(ccStatus));
            QCOMPARE(int(firstCc.data0), int(firstController));
            QCOMPARE(int(firstCc.data1), int(firstValue));

            const auto &secondCc = track.events[base + 1];
            QCOMPARE(qulonglong(secondCc.tick), qulonglong(tick));
            QCOMPARE(int(secondCc.status), int(ccStatus));
            QCOMPARE(int(secondCc.data0), int(secondController));
            QCOMPARE(int(secondCc.data1), int(secondValue));

            const auto &bend = track.events[base + 2];
            QCOMPARE(qulonglong(bend.tick), qulonglong(tick));
            QCOMPARE(int(bend.status), int(bendStatus));
            QCOMPARE(int(bend.data0), int(bendLsb));
            QCOMPARE(int(bend.data1), int(bendMsb));
        }

        const size_t noteOn = 1 + kAutomationEventCount;
        const uint8_t note = uint8_t(channel == 0 ? 0x3C : 0x43);
        QCOMPARE(qulonglong(track.events[noteOn].tick), qulonglong(256));
        QCOMPARE(int(track.events[noteOn].status), 0x90 + channel);
        QCOMPARE(int(track.events[noteOn].data0), int(note));
        QCOMPARE(int(track.events[noteOn].data1), 0x50);
        QCOMPARE(qulonglong(track.events[noteOn + 1].tick), qulonglong(kEndTick));
        QCOMPARE(int(track.events[noteOn + 1].status), 0x80 + channel);
        QCOMPARE(int(track.events[noteOn + 1].data0), int(note));
        QCOMPARE(int(track.events[noteOn + 1].data1), 0);
    }

    QVERIFY2(semanticReparseMatches(smf, error), qPrintable(error));
}

void MidiSmfTest::noteLifecyclePreservesSameTickOrdering()
{
    auto smf = SmfFile{};
    auto error = QString{};
    constexpr auto kFixture = "valid/note_lifecycle.mid";

    QVERIFY2(SmfFile::readFile(fixturePath(kFixture), &smf, &error), qPrintable(error));
    QCOMPARE(int(smf.format), 1);
    QCOMPARE(int(smf.division), 24);
    QVERIFY2(smf.tracks.size() == 2, "note-lifecycle fixture must have two tracks");
    const auto &track = smf.tracks[1];
    QCOMPARE(qulonglong(track.endTick), qulonglong(120));
    QVERIFY2(track.events.size() == 10, "note-lifecycle event count changed");

    QCOMPARE(qulonglong(track.events[2].tick), qulonglong(0));
    QCOMPARE(int(track.events[2].status), 0x90);
    QCOMPARE(int(track.events[2].data0), 0x3C);
    QCOMPARE(int(track.events[2].data1), 0x64);
    QCOMPARE(qulonglong(track.events[3].tick), qulonglong(24));
    QCOMPARE(int(track.events[3].status), 0x90);
    QCOMPARE(int(track.events[3].data0), 0x3C);
    QCOMPARE(int(track.events[3].data1), 0);
    QCOMPARE(qulonglong(track.events[4].tick), qulonglong(24));
    QCOMPARE(int(track.events[4].status), 0x90);
    QCOMPARE(int(track.events[4].data0), 0x3C);
    QCOMPARE(int(track.events[4].data1), 0x6E);
    QCOMPARE(qulonglong(track.events[6].tick), qulonglong(72));
    QCOMPARE(int(track.events[6].status), 0x90);
    QCOMPARE(int(track.events[6].data0), 0x3E);
    QCOMPARE(int(track.events[6].data1), 0x50);
    QCOMPARE(qulonglong(track.events[7].tick), qulonglong(72));
    QCOMPARE(int(track.events[7].status), 0x80);
    QCOMPARE(int(track.events[7].data0), 0x3E);
    QCOMPARE(int(track.events[7].data1), 0);
    QCOMPARE(qulonglong(track.events[8].tick), qulonglong(96));
    QCOMPARE(int(track.events[8].status), 0x90);
    QCOMPARE(int(track.events[8].data0), 0x40);
    QCOMPARE(int(track.events[8].data1), 0x60);
    QCOMPARE(qulonglong(track.events[9].tick), qulonglong(120));
    QCOMPARE(int(track.events[9].status), 0x80);
    QCOMPARE(int(track.events[9].data0), 0x40);
    QCOMPARE(int(track.events[9].data1), 0);

    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "could not create note-lifecycle fixture directory");
    auto document = SongDocument{};
    QVERIFY2(loadDocumentFromSmf(smf, scratch.filePath(QStringLiteral("note-lifecycle.mid")),
                                 document, error),
             qPrintable(error));
    const int engineTrack = engineTrackForChunk(document, 1);
    QVERIFY2(engineTrack >= 0, "note-lifecycle chunk has no engine track");
    const std::vector<DocNote> notes = document.notesForTrack(engineTrack);
    QVERIFY2(notes.size() == 4, "note-lifecycle pairing count changed");

    QCOMPARE(qulonglong(notes[0].onIndex), qulonglong(2));
    QCOMPARE(qulonglong(notes[0].endIndex), qulonglong(3));
    QCOMPARE(quint32(notes[0].duration), quint32(24));
    QCOMPARE(int(notes[0].key), 0x3C);
    QCOMPARE(int(notes[0].velocity), 0x64);
    QCOMPARE(int(notes[0].channel), 0);
    QCOMPARE(qulonglong(notes[1].onIndex), qulonglong(4));
    QCOMPARE(qulonglong(notes[1].endIndex), qulonglong(5));
    QCOMPARE(quint32(notes[1].duration), quint32(24));
    QCOMPARE(int(notes[1].key), 0x3C);
    QCOMPARE(int(notes[1].velocity), 0x6E);
    QCOMPARE(int(notes[1].channel), 0);
    QCOMPARE(qulonglong(notes[2].onIndex), qulonglong(6));
    QCOMPARE(qulonglong(notes[2].endIndex), qulonglong(7));
    QCOMPARE(quint32(notes[2].duration), quint32(0));
    QCOMPARE(int(notes[2].key), 0x3E);
    QCOMPARE(int(notes[2].velocity), 0x50);
    QCOMPARE(int(notes[2].channel), 0);
    QCOMPARE(qulonglong(notes[3].onIndex), qulonglong(8));
    QCOMPARE(qulonglong(notes[3].endIndex), qulonglong(9));
    QCOMPARE(quint32(notes[3].duration), quint32(24));
    QCOMPARE(int(notes[3].key), 0x40);
    QCOMPARE(int(notes[3].velocity), 0x60);
    QCOMPARE(int(notes[3].channel), 0);

    QVERIFY2(semanticReparseMatches(smf, error), qPrintable(error));
}

void MidiSmfTest::complexInterleavedNotesPairExactly()
{
    auto smf = SmfFile{};
    smf.format = 1;
    smf.division = 24;
    smf.tracks.resize(2);
    smf.tracks[0].endTick = 40;
    auto &track = smf.tracks[1];
    track.events.push_back(channelEvent(0, 0x90, 60, 100));
    track.events.push_back(channelEvent(0, 0x90, 62, 80));
    track.events.push_back(channelEvent(0, 0x91, 60, 70));
    track.events.push_back(channelEvent(5, 0x90, 62, 0));
    track.events.push_back(channelEvent(7, 0x81, 60, 0));
    track.events.push_back(channelEvent(10, 0x90, 60, 90));
    track.events.push_back(channelEvent(20, 0x80, 60, 0));
    track.events.push_back(channelEvent(30, 0x90, 64, 50));
    track.events.push_back(channelEvent(31, 0x90, 0x83, 60));
    track.events.push_back(channelEvent(33, 0x80, 0x03, 0));
    track.events.push_back(channelEvent(39, 0x80, 0x83, 0));
    track.endTick = 40;

    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "could not create interleaved-pairing fixture directory");
    auto document = SongDocument{};
    auto error = QString{};
    QVERIFY2(loadDocumentFromSmf(smf, scratch.filePath(QStringLiteral("interleaved-pairing.mid")),
                                 document, error),
             qPrintable(error));
    const int engineTrack = engineTrackForChunk(document, 1);
    QVERIFY2(engineTrack >= 0, "interleaved pairing chunk has no engine track");
    const std::vector<DocNote> notes = document.notesForTrack(engineTrack);
    QVERIFY2(notes.size() == 5, "interleaved note pairing count changed");

    QCOMPARE(qulonglong(notes[0].onIndex), qulonglong(0));
    QCOMPARE(qulonglong(notes[0].endIndex), qulonglong(6));
    QCOMPARE(quint32(notes[0].duration), quint32(20));
    QCOMPARE(int(notes[0].key), 60);
    QCOMPARE(int(notes[0].velocity), 100);
    QCOMPARE(int(notes[0].channel), 0);
    QCOMPARE(qulonglong(notes[1].onIndex), qulonglong(1));
    QCOMPARE(qulonglong(notes[1].endIndex), qulonglong(3));
    QCOMPARE(quint32(notes[1].duration), quint32(5));
    QCOMPARE(int(notes[1].key), 62);
    QCOMPARE(int(notes[1].velocity), 80);
    QCOMPARE(int(notes[1].channel), 0);
    QCOMPARE(qulonglong(notes[2].onIndex), qulonglong(5));
    QCOMPARE(qulonglong(notes[2].endIndex), qulonglong(6));
    QCOMPARE(quint32(notes[2].duration), quint32(10));
    QCOMPARE(int(notes[2].key), 60);
    QCOMPARE(int(notes[2].velocity), 90);
    QCOMPARE(int(notes[2].channel), 0);
    QCOMPARE(qulonglong(notes[3].onIndex), qulonglong(7));
    QVERIFY(notes[3].unterminated());
    QCOMPARE(quint32(notes[3].duration), quint32(0));
    QCOMPARE(int(notes[3].key), 64);
    QCOMPARE(int(notes[3].velocity), 50);
    QCOMPARE(int(notes[3].channel), 0);
    QCOMPARE(qulonglong(notes[4].onIndex), qulonglong(8));
    QCOMPARE(qulonglong(notes[4].endIndex), qulonglong(10));
    QCOMPARE(quint32(notes[4].duration), quint32(8));
    QCOMPARE(int(notes[4].key), 0x83);
    QCOMPARE(int(notes[4].velocity), 60);
    QCOMPARE(int(notes[4].channel), 0);
}

void MidiSmfTest::unterminatedNotePairingStaysLinear()
{
    constexpr int kNoteOns = 300000;
    auto smf = SmfFile{};
    smf.format = 1;
    smf.division = 24;
    smf.tracks.resize(2);
    smf.tracks[0].endTick = kNoteOns;
    auto &track = smf.tracks[1];
    track.events.reserve(kNoteOns);
    for (int index = 0; index < kNoteOns; ++index)
        track.events.push_back(channelEvent(uint64_t(index), 0x90, 60, 100));
    track.endTick = kNoteOns;

    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "could not create pairing stress fixture directory");
    auto document = SongDocument{};
    auto error = QString{};
    QVERIFY2(loadDocumentFromSmf(smf, scratch.filePath(QStringLiteral("unterminated-notes.mid")),
                                 document, error),
             qPrintable(error));
    const int engineTrack = engineTrackForChunk(document, 1);
    QVERIFY2(engineTrack >= 0, "unterminated-note chunk has no engine track");

    auto timer = QElapsedTimer{};
    timer.start();
    const std::vector<DocNote> notes = document.notesForTrack(engineTrack);
    const qint64 milliseconds = timer.elapsed();
    QVERIFY2(notes.size() == size_t(kNoteOns), "unterminated note pairing count changed");
    QVERIFY(notes.front().unterminated());
    QVERIFY(notes.back().unterminated());
    QVERIFY2(milliseconds <= 10000,
             qPrintable(QStringLiteral("pairing %1 unterminated note-ons took %2 ms")
                            .arg(kNoteOns)
                            .arg(milliseconds)));
}

void MidiSmfTest::programChangesRejectOutOfRangeValues()
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

void MidiSmfTest::noteOnsRejectOutOfRangeKeys()
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

int runSmfCheck(const QStringList &qtArguments)
{
    auto test = MidiSmfTest{};
    auto arguments = QStringList{QStringLiteral("smfcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
