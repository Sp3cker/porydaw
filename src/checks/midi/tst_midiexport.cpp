#include "checks/midi/tst_midiexport.h"

#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QtTest>

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <utility>

#include "audio/wavexport.h"
#include "checks/support/songfixture.h"
#include "core/songdocument.h"
#include "project/decompproject.h"
#include "project/voicegroupsource.h"

extern "C" {
#include "voicegroup_loader.h"
}

namespace {

struct ExportFixture {
    std::unique_ptr<checks::LoadedSong> song;
    VoicegroupLease voicegroup;
    std::unique_ptr<MidiTimeline> timeline;
    SongSettings settings;
    WavExportOptions options;
};

uint32_t littleEndianU32(const QByteArray &bytes, qsizetype offset)
{
    return uint32_t(uint8_t(bytes[offset])) | uint32_t(uint8_t(bytes[offset + 1])) << 8 |
           uint32_t(uint8_t(bytes[offset + 2])) << 16 | uint32_t(uint8_t(bytes[offset + 3])) << 24;
}

uint16_t littleEndianU16(const QByteArray &bytes, qsizetype offset)
{
    return uint16_t(uint8_t(bytes[offset])) | uint16_t(uint8_t(bytes[offset + 1])) << 8;
}

int16_t sampleAt(const QByteArray &bytes, uint64_t index)
{
    const qsizetype offset = 44 + static_cast<qsizetype>(index * 2);
    return static_cast<int16_t>(littleEndianU16(bytes, offset));
}

bool readFile(const QString &path, QByteArray &bytes, QString &error)
{
    auto file = QFile{path};
    if (!file.open(QIODevice::ReadOnly)) {
        error = QStringLiteral("cannot read %1: %2").arg(path, file.errorString());
        return false;
    }
    bytes = file.readAll();
    return true;
}

std::unique_ptr<ExportFixture> loadExportFixture(const QString &projectRoot,
                                                 const QString &songLabel, QString &error)
{
    auto fixture = std::make_unique<ExportFixture>();
    fixture->song = checks::LoadedSong::load(projectRoot, songLabel, error);
    if (!fixture->song)
        return nullptr;

    const SongInfo song = fixture->song->songInfo();
    const QByteArray rootUtf8 = projectRoot.toLocal8Bit();
    auto *rawVoicegroup = static_cast<LoadedVoiceGroup *>(nullptr);
    for (const QString &candidate : DecompProject::voicegroupCandidates(song)) {
        const QByteArray candidateUtf8 = candidate.toLocal8Bit();
        rawVoicegroup = voicegroup_load(rootUtf8.constData(), candidateUtf8.constData(), nullptr);
        if (rawVoicegroup)
            break;
    }
    if (!rawVoicegroup) {
        error = QStringLiteral("voicegroup not found for %1").arg(songLabel);
        return nullptr;
    }
    fixture->voicegroup = wrapVoicegroupLease(rawVoicegroup);

    SongDocument &document = fixture->song->document();
    fixture->settings.songVolume = static_cast<uint8_t>(document.cfg().masterVolume);
    fixture->settings.reverb =
        static_cast<uint8_t>(document.cfg().reverb > 0 ? document.cfg().reverb : 0);
    fixture->options.sampleRate = 44100;
    fixture->options.loopCount = 1;
    fixture->options.fadeoutSeconds = 1.0;
    fixture->options.tailSeconds = 1.0;
    fixture->timeline = document.buildTimeline(double(fixture->options.sampleRate));
    if (!fixture->timeline) {
        error = QStringLiteral("could not build MIDI timeline for %1").arg(songLabel);
        return nullptr;
    }
    error.clear();
    return fixture;
}

uint64_t expectedTotalSamples(const MidiTimeline &timeline, const WavExportOptions &options)
{
    if (timeline.hasLoop()) {
        const uint64_t loopDuration = timeline.loopEndSample - timeline.loopStartSample;
        return timeline.loopStartSample + loopDuration + uint64_t(options.sampleRate);
    }
    return timeline.lengthSamples + uint64_t(options.sampleRate);
}

} // namespace

MidiExportTest::MidiExportTest(QString projectRoot, QString songLabel)
    : m_projectRoot(std::move(projectRoot))
    , m_songLabel(std::move(songLabel))
{}

void MidiExportTest::initTestCase()
{
    QVERIFY2(
        QFileInfo{m_projectRoot}.isDir(),
        qPrintable(
            QStringLiteral("exportcheck project root is not a directory: %1").arg(m_projectRoot)));
    QVERIFY2(!m_songLabel.isEmpty(), "exportcheck requires a song label");
}

void MidiExportTest::durationCalculationMatchesRenderParity()
{
    auto error = QString{};
    const auto fixture = loadExportFixture(m_projectRoot, m_songLabel, error);
    QVERIFY2(fixture, qPrintable(error));

    const WavExportTotals totals = wavExportTotals(*fixture->timeline, fixture->options);
    QCOMPARE(qulonglong(totals.totalSamples),
             qulonglong(expectedTotalSamples(*fixture->timeline, fixture->options)));
}

void MidiExportTest::offlineExportProducesValidRiffPcm()
{
    auto error = QString{};
    const auto fixture = loadExportFixture(m_projectRoot, m_songLabel, error);
    QVERIFY2(fixture, qPrintable(error));
    const WavExportTotals totals = wavExportTotals(*fixture->timeline, fixture->options);

    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "could not create WAV export scratch directory");
    const QString path = scratch.filePath(QStringLiteral("export.wav"));
    double lastFraction = -1.0;
    bool strictlyMonotonic = true;
    QVERIFY2(exportWav(
                 path, *fixture->timeline, fixture->voicegroup, fixture->settings, fixture->options,
                 [&](double fraction) {
                     strictlyMonotonic = strictlyMonotonic && fraction > lastFraction;
                     lastFraction = fraction;
                     return true;
                 },
                 &error),
             qPrintable(error));
    QVERIFY2(strictlyMonotonic && lastFraction == 1.0,
             "WAV export progress was not strictly monotonic through 1.0");

    auto wav = QByteArray{};
    QVERIFY2(readFile(path, wav, error), qPrintable(error));
    const uint64_t dataSize = totals.totalSamples * 4;
    QVERIFY2(uint64_t(wav.size()) == 44 + dataSize,
             "WAV byte count does not match the rendered frame count");
    QVERIFY(wav.size() >= 44);
    QCOMPARE(wav.left(4), QByteArray("RIFF"));
    QCOMPARE(wav.mid(8, 4), QByteArray("WAVE"));
    QCOMPARE(wav.mid(12, 4), QByteArray("fmt "));
    QCOMPARE(wav.mid(36, 4), QByteArray("data"));
    QCOMPARE(int(littleEndianU16(wav, 20)), 1);
    QCOMPARE(int(littleEndianU16(wav, 22)), 2);
    QCOMPARE(int(littleEndianU16(wav, 34)), 16);
    QCOMPARE(qulonglong(littleEndianU32(wav, 24)), qulonglong(fixture->options.sampleRate));
    QCOMPARE(qulonglong(littleEndianU32(wav, 40)), qulonglong(dataSize));

    int peak = 0;
    for (uint64_t sampleIndex = 0; sampleIndex < totals.totalSamples * 2; ++sampleIndex)
        peak = std::max(peak, std::abs(int(sampleAt(wav, sampleIndex))));
    QVERIFY2(peak >= 256, "offline WAV render is nearly silent");

    if (fixture->timeline->hasLoop()) {
        QVERIFY2(totals.totalSamples >= 16, "looping export is too short for tail verification");
        int tailPeak = 0;
        for (uint64_t sampleIndex = (totals.totalSamples - 16) * 2;
             sampleIndex < totals.totalSamples * 2; ++sampleIndex) {
            tailPeak = std::max(tailPeak, std::abs(int(sampleAt(wav, sampleIndex))));
        }
        QVERIFY2(tailPeak <= peak / 16, "looping WAV export did not fade to silence");
    }
}

void MidiExportTest::resonanceSuppressionChangesPcmWithoutChangingFrames()
{
    auto error = QString{};
    const auto fixture = loadExportFixture(m_projectRoot, m_songLabel, error);
    QVERIFY2(fixture, qPrintable(error));

    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "could not create resonance-export scratch directory");
    const QString baselinePath = scratch.filePath(QStringLiteral("baseline.wav"));
    const QString suppressedPath = scratch.filePath(QStringLiteral("suppressed.wav"));
    QVERIFY2(exportWav(baselinePath, *fixture->timeline, fixture->voicegroup, fixture->settings,
                       fixture->options, {}, &error),
             qPrintable(error));
    auto baseline = QByteArray{};
    QVERIFY2(readFile(baselinePath, baseline, error), qPrintable(error));

    fixture->options.resonanceSuppression = true;
    QVERIFY2(exportWav(suppressedPath, *fixture->timeline, fixture->voicegroup, fixture->settings,
                       fixture->options, {}, &error),
             qPrintable(error));
    auto suppressed = QByteArray{};
    QVERIFY2(readFile(suppressedPath, suppressed, error), qPrintable(error));
    QCOMPARE(suppressed.size(), baseline.size());
    QVERIFY2(suppressed != baseline, "resonance suppression did not alter exported PCM bytes");
}

void MidiExportTest::cancelledExportRemovesPartialFile()
{
    auto error = QString{};
    const auto fixture = loadExportFixture(m_projectRoot, m_songLabel, error);
    QVERIFY2(fixture, qPrintable(error));

    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "could not create cancellation-export scratch directory");
    const QString path = scratch.filePath(QStringLiteral("cancelled.wav"));
    fixture->options.resonanceSuppression = true;
    QVERIFY(!exportWav(
        path, *fixture->timeline, fixture->voicegroup, fixture->settings, fixture->options,
        [](double) { return false; }, &error));
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY2(!QFile::exists(path), "cancelled WAV export left a partial file");
}

int runExportCheck(const QString &projectRoot, const QString &songLabel,
                   const QStringList &qtArguments)
{
    auto test = MidiExportTest{projectRoot, songLabel};
    auto arguments = QStringList{QStringLiteral("exportcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
