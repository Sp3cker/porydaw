#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QApplication>
#include <QDialogButtonBox>
#include <QLineEdit>
#include <QPushButton>
#include <QTreeWidget>
#include <QtTest>
#include <cmath>
#include <cstring>
#include <vector>

#include "audio/sampledoc.h"
#include "audio/sampleimport.h"
#include "audio/sf2reader.h"
#include "ui/sf2zonepicker.h"

namespace {
constexpr double kPi = 3.14159265358979323846;
struct SoundFontFixture {
    std::vector<qint16> pool;
    QByteArray bytes;
    QByteArray romOnlyBytes;
};

SoundFontFixture makeSoundFontFixture()
{
    SoundFontFixture fixture;
    fixture.pool.reserve(600);
    for (int i = 0; i < 400; ++i)
        fixture.pool.push_back(
            qint16(std::lround(16383.0 * std::sin(2.0 * kPi * 441.0 * i / 22050.0))));
    for (int i = 0; i < 200; ++i)
        fixture.pool.push_back(qint16(i * 100 - 10000));

    QByteArray poolBytes;
    for (const qint16 sample : fixture.pool)
        putU16(&poolBytes, quint16(sample));

    const auto makeChunk = [](const char *id, const QByteArray &body) {
        QByteArray chunk(id, 4);
        putU32(&chunk, quint32(body.size()));
        chunk += body;
        if (body.size() & 1)
            chunk += '\0';
        return chunk;
    };
    const auto makeList = [&makeChunk](const char *type, const QByteArray &subchunks) {
        return makeChunk("LIST", QByteArray(type, 4) + subchunks);
    };
    const auto appendName20 = [](QByteArray *out, const char *name) {
        char buffer[20] = {};
        std::strncpy(buffer, name, 19);
        out->append(buffer, 20);
    };
    const auto appendSampleHeader = [&appendName20](QByteArray *out, const char *name,
                                                    quint32 start, quint32 end, quint32 loopStart,
                                                    quint32 loopEndExclusive, quint32 rate,
                                                    quint8 pitch, qint8 correction, quint16 type) {
        appendName20(out, name);
        putU32(out, start);
        putU32(out, end);
        putU32(out, loopStart);
        putU32(out, loopEndExclusive);
        putU32(out, rate);
        out->append(char(pitch)).append(char(correction));
        putU16(out, 0);
        putU16(out, type);
    };
    const auto buildFont = [&appendName20, &makeChunk, &makeList,
                            &poolBytes](const QByteArray &sampleHeaders) {
        QByteArray presetHeaders;
        appendName20(&presetHeaders, "TestPreset");
        putU16(&presetHeaders, 0);
        putU16(&presetHeaders, 0);
        putU16(&presetHeaders, 0);
        putU32(&presetHeaders, 0);
        putU32(&presetHeaders, 0);
        putU32(&presetHeaders, 0);
        appendName20(&presetHeaders, "EOP");
        putU16(&presetHeaders, 0);
        putU16(&presetHeaders, 0);
        putU16(&presetHeaders, 1);
        putU32(&presetHeaders, 0);
        putU32(&presetHeaders, 0);
        putU32(&presetHeaders, 0);

        QByteArray presetBags;
        putU16(&presetBags, 0);
        putU16(&presetBags, 0);
        putU16(&presetBags, 1);
        putU16(&presetBags, 0);
        QByteArray presetGenerators;
        putU16(&presetGenerators, 41);
        putU16(&presetGenerators, 0);
        putU16(&presetGenerators, 0);
        putU16(&presetGenerators, 0);

        QByteArray instruments;
        appendName20(&instruments, "TestInst");
        putU16(&instruments, 0);
        appendName20(&instruments, "EOI");
        putU16(&instruments, 1);
        QByteArray instrumentBags;
        putU16(&instrumentBags, 0);
        putU16(&instrumentBags, 0);
        putU16(&instrumentBags, 1);
        putU16(&instrumentBags, 0);
        QByteArray instrumentGenerators;
        putU16(&instrumentGenerators, 53);
        putU16(&instrumentGenerators, 0);
        putU16(&instrumentGenerators, 0);
        putU16(&instrumentGenerators, 0);

        QByteArray version;
        putU16(&version, 2);
        putU16(&version, 1);
        QByteArray body("sfbk", 4);
        body += makeList("INFO", makeChunk("ifil", version) +
                                     makeChunk("INAM", QByteArray("samplecheck\0", 12)));
        body += makeList("sdta", makeChunk("smpl", poolBytes));
        body += makeList(
            "pdta", makeChunk("phdr", presetHeaders) + makeChunk("pbag", presetBags) +
                        makeChunk("pmod", QByteArray(10, '\0')) +
                        makeChunk("pgen", presetGenerators) + makeChunk("inst", instruments) +
                        makeChunk("ibag", instrumentBags) +
                        makeChunk("imod", QByteArray(10, '\0')) +
                        makeChunk("igen", instrumentGenerators) + makeChunk("shdr", sampleHeaders));
        QByteArray font("RIFF", 4);
        putU32(&font, quint32(body.size()));
        return font + body;
    };

    QByteArray headers;
    appendSampleHeader(&headers, "Test Tone", 0, 400, 100, 300, 22050, 69, -20, 1);
    appendSampleHeader(&headers, "PadL", 400, 600, 400, 400, 32000, 60, 50, 4);
    appendSampleHeader(&headers, "RomTone", 0, 400, 0, 0, 22050, 60, 0, 0x8001);
    appendSampleHeader(&headers, "Unpitched", 400, 600, 0, 0, 22050, 255, 0, 1);
    appendSampleHeader(&headers, "EOS", 0, 0, 0, 0, 0, 0, 0, 0);
    fixture.bytes = buildFont(headers);

    QByteArray romOnlyHeaders;
    appendSampleHeader(&romOnlyHeaders, "RomTone", 0, 400, 0, 0, 22050, 60, 0, 0x8001);
    appendSampleHeader(&romOnlyHeaders, "EOS", 0, 0, 0, 0, 0, 0, 0, 0);
    fixture.romOnlyBytes = buildFont(romOnlyHeaders);
    return fixture;
}
} // namespace

namespace samplecheck {

void SampleProcessingTest::soundFontExtraction()
{
    const SoundFontFixture fixture = makeSoundFontFixture();
    QString error;
    QVERIFY2(sf2Magic(fixture.bytes), "sf2 magic sniffs");
    Sf2File font;
    QVERIFY2(readSf2Bytes(fixture.bytes, QStringLiteral("f/test.sf2"), &font, &error),
             "sf2 fixture reads");
    QCOMPARE(font.zones.size(), 3);
    const Sf2Zone &tone = font.zones[0];
    QVERIFY2(tone.name == QStringLiteral("Test Tone") &&
                 tone.instrument == QStringLiteral("TestInst") &&
                 tone.preset == QStringLiteral("TestPreset"),
             "grouping labels resolve through the pdta index arrays");
    QVERIFY2(font.zones[1].name == QStringLiteral("PadL") && font.zones[1].stereoPair() &&
                 font.zones[1].instrument.isEmpty(),
             "left-linked zone flags as a stereo pair, ungrouped");

    ImportedSample z0;
    QVERIFY2(extractSf2Zone(font, 0, &z0, &error), "zone 0 extracts");
    QVERIFY2(z0.sourceKind == ImportedSample::Sf2 && z0.sourceChannels == 1 &&
                 z0.sourceBits == 16 && !z0.gbaReady && z0.warnings.isEmpty(),
             "zone 0 structure");
    QVERIFY2(z0.frameCount() == 400 && z0.playLength == 400 && z0.sampleRate == 22050.0,
             "zone 0 pool segment bounds");
    QVERIFY2(z0.hasPitchMetadata && z0.baseKey == 68 && std::abs(z0.fracSemitone - 0.8) < 1e-9,
             "negative pitchCorrection renormalizes below the unity key");
    QVERIFY2(z0.hasLoop && z0.loopStart == 100 && z0.loopEndIncl == 299,
             "sf2 exclusive loop end converts to inclusive");
    QVERIFY2(z0.suggestedName == QStringLiteral("test_tone"),
             "zone name sanitizes into the suggested name");
    for (int i = 0; i < 400; ++i)
        QCOMPARE(z0.buffer[size_t(i)], float(double(fixture.pool[size_t(i)]) / 32768.0));

    ImportedSample z1;
    QVERIFY2(extractSf2Zone(font, 1, &z1, &error), "zone 1 extracts");
    QVERIFY2(!z1.warnings.isEmpty(), "stereo-pair extraction reports its one-channel conversion");
    QVERIFY2(z1.frameCount() == 200 && !z1.hasLoop && z1.hasPitchMetadata && z1.baseKey == 60 &&
                 std::abs(z1.fracSemitone - 0.5) < 1e-9 &&
                 z1.buffer[0] == float(double(fixture.pool[400]) / 32768.0),
             "positive pitchCorrection becomes the semitone fraction");

    ImportedSample z2;
    QVERIFY2(extractSf2Zone(font, 2, &z2, &error), "zone 2 extracts");
    QVERIFY2(!z2.hasPitchMetadata && z2.baseKey == 60,
             "unpitched (255) zone defers to pitch detection");

    SampleDocument doc(z0);
    doc.setParams(SampleDocument::defaultParams(z0));
    const ProcessedSample &out = doc.processed();
    QVERIFY2(!out.s8.isEmpty() && out.size == quint32(out.s8.size()) && out.freq > 0 && out.looped,
             "sf2 zone renders through the pipeline");
}

void SampleProcessingTest::soundFontRefusals_data()
{
    QTest::addColumn<QByteArray>("bytes");
    QTest::addColumn<bool>("singleStream");

    const SoundFontFixture fixture = makeSoundFontFixture();
    QTest::newRow("single-stream-front-door") << fixture.bytes << true;
    QTest::newRow("truncated-container") << fixture.bytes.left(200) << false;
    QTest::newRow("rom-only-font") << fixture.romOnlyBytes << false;
}

void SampleProcessingTest::soundFontRefusals()
{
    QFETCH(QByteArray, bytes);
    QFETCH(bool, singleStream);
    QString error;
    ImportedSample imported;
    Sf2File font;
    const bool accepted =
        singleStream ? importAudioBytes(bytes, QStringLiteral("f/test.sf2"), &imported, &error)
                     : readSf2Bytes(bytes, QStringLiteral("f/test.sf2"), &font, &error);
    QVERIFY2(!accepted, "invalid SoundFont input is refused");
    QVERIFY2(!error.isEmpty(), "rejected input reports a refusal");
}

void SampleProcessingTest::soundFontPicker()
{
    const SoundFontFixture fixture = makeSoundFontFixture();
    QString error;
    Sf2File font;
    QVERIFY2(readSf2Bytes(fixture.bytes, QStringLiteral("f/test.sf2"), &font, &error),
             "sf2 fixture reads");

    Sf2ZonePicker picker(font);
    picker.resize(720, 480);
    picker.show();
    QApplication::processEvents();
    auto *tree = picker.findChild<QTreeWidget *>(QStringLiteral("sf2ZoneTree"));
    auto *searchEdit = picker.findChild<QLineEdit *>(QStringLiteral("sf2SearchEdit"));
    auto *buttons = picker.findChild<QDialogButtonBox *>(QStringLiteral("sf2ButtonBox"));
    QVERIFY2(tree && searchEdit && buttons, "picker widgets found");
    QPushButton *ok = buttons->button(QDialogButtonBox::Ok);
    QVERIFY2(ok, "picker has an accept button");
    QCOMPARE(tree->topLevelItemCount(), 2);
    QTreeWidgetItem *firstGroup = tree->topLevelItem(0);
    QTreeWidgetItem *secondGroup = tree->topLevelItem(1);
    QVERIFY2(firstGroup && firstGroup->childCount() == 1,
             "instrument/preset zones form one picker group");
    QVERIFY2(secondGroup && secondGroup->childCount() == 2,
             "unreferenced zones fall under (no instrument)");
    QVERIFY2(!ok->isEnabled() && picker.selectedZone() == -1,
             "nothing picked until a zone row is chosen");
    tree->setCurrentItem(firstGroup->child(0));
    QVERIFY2(picker.selectedZone() == 0 && ok->isEnabled(), "selecting a zone row arms OK");
    tree->setCurrentItem(firstGroup);
    QVERIFY2(picker.selectedZone() == -1 && !ok->isEnabled(), "group rows are not pickable");
    searchEdit->setText(QStringLiteral("pad"));
    QCOMPARE(tree->topLevelItemCount(), 1);
    QCOMPARE(tree->topLevelItem(0)->childCount(), 1);
    tree->setCurrentItem(tree->topLevelItem(0)->child(0));
    QCOMPARE(picker.selectedZone(), 1);
    searchEdit->clear();
    QCOMPARE(tree->topLevelItemCount(), 2);
    tree->setCurrentItem(tree->topLevelItem(0)->child(0));
    ok->click();
    QVERIFY2(picker.result() == QDialog::Accepted && picker.selectedZone() == 0,
             "OK accepts with the picked zone");
}

} // namespace samplecheck
