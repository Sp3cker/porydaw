#include "tst_swiftcore.h"

#include "core_check.h"

#include <QByteArray>
#include <QFile>
#include <QStringList>
#include <QtTest/QTest>

#include <algorithm>
#include <array>
#include <bit>
#include <cstdint>
#include <limits>
#include <memory>
#include <optional>
#include <span>
#include <utility>
#include <vector>

#include "checks/playback/sustainvoicegroup.h"
#include "core/m4asemantics.h"
#include "core/mid2agbtables.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/timedefaults.h"
#include "core/timelineplayer.h"
#include "core/tracklimits.h"
#include "core/velocitymodel.h"
#include "project/songregistry.h"

namespace {

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

QByteArray midiBytes(uint16_t format, uint16_t division, const std::vector<QByteArray> &tracks)
{
    QByteArray bytes("MThd");
    appendU32(bytes, 6);
    appendU16(bytes, format);
    appendU16(bytes, uint16_t(tracks.size()));
    appendU16(bytes, division);
    for (const QByteArray &track : tracks) {
        bytes.append("MTrk");
        appendU32(bytes, uint32_t(track.size()));
        bytes.append(track);
    }
    return bytes;
}

QByteArray format0Bytes(const QByteArray &track)
{
    return midiBytes(0, 24, {track});
}

QString cppSummary(const SmfFile &file)
{
    QStringList parts{
        QStringLiteral("division=%1").arg(file.division),
        QStringLiteral("chunks=%1").arg(file.tracks.size()),
        QStringLiteral("was0=%1").arg(file.wasFormat0 ? 1 : 0),
    };
    for (size_t index = 0; index < file.tracks.size(); ++index) {
        const SmfTrack &track = file.tracks[index];
        parts.append(
            QStringLiteral("chunk%1=%2,%3").arg(index).arg(track.endTick).arg(track.events.size()));
    }
    const SmfEngineTrackMapping mapping = mapSmfEngineTracks(file);
    parts.append(
        QStringLiteral("map=%1,%2").arg(mapping.usedTrackCount).arg(mapping.droppedTracks));
    for (int index = 0; index < mapping.usedTrackCount; ++index) {
        parts.append(QStringLiteral("slot%1=%2,%3")
                         .arg(index)
                         .arg(mapping.tracks[size_t(index)].smfTrack)
                         .arg(mapping.tracks[size_t(index)].channel));
    }
    return parts.join(QLatin1Char(';'));
}

struct SwiftCodecResult {
    bool valid = false;
    QByteArray encoded;
    bool wasFormat0 = false;
    QString summary;
    QString error;
};

SwiftCodecResult swiftCodec(const QByteArray &bytes)
{
    SwiftCodecResult result;
    uint8_t wasFormat0 = 0;
    size_t summarySize = 0;
    size_t errorSize = 0;
    const auto *input = reinterpret_cast<const uint8_t *>(bytes.constData());
    const int64_t encodedSize =
        pdc_codec_roundtrip(input, size_t(bytes.size()), nullptr, 0, &wasFormat0, nullptr, 0,
                            &summarySize, nullptr, 0, &errorSize);
    result.wasFormat0 = wasFormat0 != 0;
    if (encodedSize < 0) {
        QByteArray error(int(errorSize), Qt::Uninitialized);
        pdc_codec_roundtrip(input, size_t(bytes.size()), nullptr, 0, &wasFormat0, nullptr, 0,
                            &summarySize, error.data(), size_t(error.size()), &errorSize);
        result.error = QString::fromUtf8(error);
        return result;
    }

    result.valid = true;
    result.encoded.resize(int(encodedSize));
    QByteArray summary(int(summarySize), Qt::Uninitialized);
    const int64_t secondSize = pdc_codec_roundtrip(
        input, size_t(bytes.size()), reinterpret_cast<uint8_t *>(result.encoded.data()),
        size_t(result.encoded.size()), &wasFormat0, summary.data(), size_t(summary.size()),
        &summarySize, nullptr, 0, &errorSize);
    if (secondSize != encodedSize) {
        result.valid = false;
        result.error = QStringLiteral("sizing call returned %1, copy call returned %2")
                           .arg(encodedSize)
                           .arg(secondSize);
        return result;
    }
    result.wasFormat0 = wasFormat0 != 0;
    result.summary = QString::fromUtf8(summary);
    return result;
}

void compareCodecCase(const QString &name, const QByteArray &bytes, bool expectedValid)
{
    SmfFile cpp;
    QString cppError;
    const bool cppValid = SmfFile::read(bytes, &cpp, &cppError);
    const SwiftCodecResult swift = swiftCodec(bytes);
    const QString verdict = QStringLiteral("cppId=%1: expected=%2 C++=%3 (%4) Swift=%5 (%6)")
                                .arg(name)
                                .arg(expectedValid)
                                .arg(cppValid)
                                .arg(cppError)
                                .arg(swift.valid)
                                .arg(swift.error);
    QVERIFY2(cppValid == expectedValid, qPrintable(verdict));
    QVERIFY2(swift.valid == cppValid, qPrintable(verdict));
    if (!cppValid)
        return;

    const QByteArray cppEncoded = cpp.write();
    const QString bytesFailure = QStringLiteral("cppId=%1: canonical bytes differ; C++=%2 Swift=%3")
                                     .arg(name, QString::fromLatin1(cppEncoded.toHex()),
                                          QString::fromLatin1(swift.encoded.toHex()));
    QVERIFY2(swift.encoded == cppEncoded, qPrintable(bytesFailure));
    const QString summary = cppSummary(cpp);
    const QString summaryFailure = QStringLiteral("cppId=%1: summaries differ; C++=%2 Swift=%3")
                                       .arg(name, summary, swift.summary);
    QVERIFY2(swift.summary == summary, qPrintable(summaryFailure));
    const QString formatFailure = QStringLiteral("cppId=%1: wasFormat0 differs; C++=%2 Swift=%3")
                                      .arg(name)
                                      .arg(cpp.wasFormat0)
                                      .arg(swift.wasFormat0);
    QVERIFY2(swift.wasFormat0 == cpp.wasFormat0, qPrintable(formatFailure));
}

QString swiftText(uint32_t operation, int64_t a = 0, int64_t b = 0)
{
    const int64_t count = pdc_semantic_text(operation, a, b, nullptr, 0);
    QByteArray bytes(int(count), Qt::Uninitialized);
    const int64_t copied = pdc_semantic_text(operation, a, b, bytes.data(), size_t(bytes.size()));
    if (copied != count)
        return QStringLiteral("<adapter-size-error:%1/%2>").arg(count).arg(copied);
    return QString::fromUtf8(bytes);
}

QString semanticCppId(const QString &caseKey)
{
    if (caseKey.startsWith(QLatin1String("velocity-kind-"))) {
        const bool resolution = caseKey.contains(QLatin1String("-is-psg")) ||
                                caseKey.contains(QLatin1String("-compatible-")) ||
                                caseKey.endsWith(QLatin1String("-name"));
        return QStringLiteral("velocity-model/VelocityModelTest::%1/%2")
            .arg(resolution ? QStringLiteral("resolvesVoiceKinds")
                            : QStringLiteral("levelsCanonicalizeAndMove"),
                 caseKey);
    }
    if (caseKey.startsWith(QLatin1String("voice-type-")))
        return QStringLiteral("vgcheck/VoicegroupSourceTest::displayNamesAreStable/%1")
            .arg(caseKey);
    if (caseKey.startsWith(QLatin1String("effective-")) ||
        caseKey.startsWith(QLatin1String("duration-"))) {
        return QStringLiteral("no-row/core/mid2agbtables.cpp/%1").arg(caseKey);
    }
    if (caseKey.startsWith(QLatin1String("controller-")) ||
        caseKey.startsWith(QLatin1String("tempo-")) ||
        caseKey.startsWith(QLatin1String("shift-")) ||
        caseKey.startsWith(QLatin1String("tick-from-double-"))) {
        return QStringLiteral("no-row/core/timedefaults.h/%1").arg(caseKey);
    }
    if (caseKey.startsWith(QLatin1String("track-"))) {
        return QStringLiteral("no-row/core/tracklimits.h/%1").arg(caseKey);
    }
    if (caseKey.startsWith(QLatin1String("note-id-"))) {
        return QStringLiteral("noteidcheck/NoteIdentityCheckTest::"
                              "identityDoesNotAffectEqualityOrSerialization/%1")
            .arg(caseKey);
    }
    return QStringLiteral("no-row/core/m4asemantics.cpp/%1").arg(caseKey);
}

void expectValue(const QString &name, int64_t cpp, int64_t swift)
{
    const QString failure =
        QStringLiteral("cppId=%1: C++=%2 Swift=%3").arg(semanticCppId(name)).arg(cpp).arg(swift);
    QVERIFY2(swift == cpp, qPrintable(failure));
}

void expectText(const QString &name, const QString &cpp, const QString &swift)
{
    const QString failure =
        QStringLiteral("cppId=%1: C++='%2' Swift='%3'").arg(semanticCppId(name), cpp, swift);
    QVERIFY2(swift == cpp, qPrintable(failure));
}

ToneData tone(uint8_t type)
{
    ToneData result{};
    result.type = type;
    return result;
}

VelocityMap cppVelocityMap(int kind)
{
    switch (kind) {
    case 0:
        return VelocityMap::resolve(nullptr, std::nullopt);
    case 1: {
        const ToneData data = tone(VOICE_CRY);
        return VelocityMap::resolve(&data, 60);
    }
    case 2: {
        const ToneData data = tone(VOICE_KEYSPLIT);
        return VelocityMap::resolve(&data, std::nullopt);
    }
    case 3: {
        const ToneData data = tone(VOICE_DIRECTSOUND);
        return VelocityMap::resolve(&data, 60);
    }
    case 4: {
        const ToneData data = tone(VOICE_SQUARE_1);
        return VelocityMap::resolve(&data, 60);
    }
    case 5: {
        const ToneData data = tone(VOICE_SQUARE_2);
        return VelocityMap::resolve(&data, 60);
    }
    case 6: {
        const ToneData data = tone(VOICE_PROGRAMMABLE_WAVE);
        return VelocityMap::resolve(&data, 60);
    }
    default: {
        const ToneData data = tone(VOICE_NOISE);
        return VelocityMap::resolve(&data, 60);
    }
    }
}

constexpr double kPlaybackSampleRate = 48000.0;
constexpr uint32_t kPlaybackDivision = 24;
constexpr uint64_t kPlaybackSamplesPerTick = 1000;

constexpr const char *kExactSamplesId =
    "smfcheck/MidiSmfTest::tempoConversionSchedulesExactSamples";
constexpr const char *kMappingId =
    "smfcheck/MidiSmfTest::engineTrackMappingAgreesAcrossProjections/"
    "document-and-timeline assertions";
constexpr const char *kIdentitiesId =
    "noteidcheck/NoteIdentityCheckTest::timelineTransportsOnlyStampedNoteIds";
constexpr const char *kLoopPointsId = "loopcheck/LoopTest::synthesizedLoopSongHasExactLoopPoints";
constexpr const char *kLoopRenderId =
    "loopcheck/LoopTest::loopWrapMatchesHardwareGoto[rows=pass-1-tied-note-sounds,"
    "pass-2-gate-carry-holds-across-wrap,gate-carry-releases-at-written-duration,"
    "pass-2-tied-note-stacks,pass-3-tied-note-stacks,"
    "loop-boundary-notes-play-without-looping]";
constexpr const char *kPrimeId =
    "primecheck/PrimeTest::{unprimedTrackAuditionIsSilent,"
    "primeVoicesApplyTrackPrograms[rows=chase-applied-voice-not-overridden,"
    "later-voice-primed-at-load,voiceless-track-never-primed],"
    "primedTrackAuditionIsAudible,midSongChaseSuppliesAllPrograms}";
constexpr const char *kControllerDefaultsId = "no-row/core/timedefaults.h exhaustive functions";
constexpr const char *kReplacementId =
    "transportcheck/TransportTest::{timelineHandoffOwnership,seekPublishesWithoutBlocking,"
    "stopCancelsPendingSeek,updateTimelineCarriesPendingSeek,"
    "liveTimelineReplacementDoesNotBlock,rebuildKeepsSoundingCgbSongNote,"
    "rebuildKeepsCgbNotePreview}";

QString playbackFailure(const char *cppId, const QString &detail)
{
    return QStringLiteral("cppId=%1: %2").arg(QString::fromLatin1(cppId), detail);
}

SmfEvent playbackChannelEvent(Tick tick, uint8_t status, uint8_t data0, uint8_t data1 = 0,
                              NoteId noteId = {})
{
    SmfEvent event;
    event.tick = tick;
    event.status = status;
    event.data0 = data0;
    event.data1 = data1;
    event.noteId = noteId;
    return event;
}

SmfEvent playbackMetaEvent(Tick tick, uint8_t type, const QByteArray &data)
{
    SmfEvent event;
    event.tick = tick;
    event.status = 0xFF;
    event.metaType = type;
    event.blob = data;
    return event;
}

QString writePlaybackFixture(const QString &path, const SmfFile &file, const char *cppId)
{
    QFile output(path);
    if (!output.open(QIODevice::WriteOnly))
        return playbackFailure(cppId, QStringLiteral("cannot create fixture %1").arg(path));
    const QByteArray bytes = file.write();
    if (output.write(bytes) != bytes.size())
        return playbackFailure(cppId, QStringLiteral("cannot write fixture %1").arg(path));
    return {};
}

SmfFile projectionSong()
{
    SmfFile file;
    file.format = 1;
    file.division = 37;
    file.tracks.resize(20);
    file.tracks[0].events = {
        playbackMetaEvent(0, 0x51, QByteArray("\x07\xA1\x21", 3)),
        playbackMetaEvent(7, 0x51, QByteArray("\x06\x1A\x83", 3)),
        playbackMetaEvent(19, 0x51, QByteArray("\x09\x27\xC7", 3)),
        playbackMetaEvent(23, 0x01, QByteArray("[")),
        playbackMetaEvent(61, 0x01, QByteArray("]")),
    };
    file.tracks[0].endTick = 80;
    file.tracks[1].events = {playbackMetaEvent(0, 0x03, QByteArray("metadata"))};
    file.tracks[1].endTick = 80;
    for (int track = 0; track < 18; ++track) {
        SmfTrack &chunk = file.tracks[size_t(track + 2)];
        const uint8_t channel = uint8_t(track & 0x0F);
        chunk.events = {
            playbackChannelEvent(Tick(track), uint8_t(0xC0 | channel), uint8_t(track)),
            playbackChannelEvent(Tick(11 + track), uint8_t(0x90 | channel), uint8_t(48 + track), 96,
                                 NoteId{uint64_t(track + 1)}),
            playbackChannelEvent(Tick(31 + track), uint8_t(0x80 | channel), uint8_t(48 + track)),
        };
        chunk.endTick = 80;
    }
    return file;
}

SmfFile loopSong()
{
    constexpr Tick loopStart = 96;
    constexpr Tick loopEnd = 288;
    SmfFile file;
    file.format = 1;
    file.division = kPlaybackDivision;
    file.tracks.resize(2);
    file.tracks[0].events = {
        playbackMetaEvent(0, 0x51, QByteArray("\x07\xA1\x20", 3)),
        playbackMetaEvent(loopStart, 0x01, QByteArray("[")),
        playbackMetaEvent(loopEnd, 0x01, QByteArray("]")),
    };
    file.tracks[0].endTick = 384;
    SmfTrack &notes = file.tracks[1];
    notes.events.push_back(playbackChannelEvent(0, 0xC0, 0));
    const auto addNote = [&notes](Tick on, Tick off, uint8_t key) {
        notes.events.push_back(playbackChannelEvent(on, 0x90, key, 100));
        notes.events.push_back(playbackChannelEvent(off, 0x80, key));
    };
    addNote(96, 120, 60);
    addNote(192, 312, 67);
    addNote(240, 300, 65);
    addNote(264, 288, 62);
    addNote(288, 312, 64);
    std::stable_sort(
        notes.events.begin(), notes.events.end(),
        [](const SmfEvent &left, const SmfEvent &right) { return left.tick < right.tick; });
    notes.endTick = 384;
    return file;
}

SmfFile primeSong()
{
    SmfFile file;
    file.format = 1;
    file.division = kPlaybackDivision;
    file.tracks.resize(4);
    file.tracks[0].events = {
        playbackMetaEvent(0, 0x51, QByteArray("\x07\xA1\x20", 3)),
    };
    file.tracks[0].endTick = 192;
    file.tracks[1].events = {
        playbackChannelEvent(0, 0xC0, 5),
        playbackChannelEvent(0, 0x90, 60, 100),
        playbackChannelEvent(24, 0x80, 60),
        playbackChannelEvent(96, 0xC0, 9),
    };
    file.tracks[1].endTick = 192;
    file.tracks[2].events = {
        playbackChannelEvent(48, 0xC1, 7),
        playbackChannelEvent(48, 0x91, 62, 100),
        playbackChannelEvent(72, 0x81, 62),
    };
    file.tracks[2].endTick = 192;
    file.tracks[3].events = {
        playbackChannelEvent(0, 0x92, 64, 100),
        playbackChannelEvent(24, 0x82, 64),
    };
    file.tracks[3].endTick = 192;
    return file;
}

SmfFile controllerSong(std::optional<std::pair<uint8_t, uint8_t>> controller, Tick tick)
{
    SmfFile file;
    file.format = 1;
    file.division = kPlaybackDivision;
    file.tracks.resize(2);
    file.tracks[0].events = {
        playbackMetaEvent(0, 0x51, QByteArray("\x07\xA1\x20", 3)),
    };
    file.tracks[0].endTick = 48;
    file.tracks[1].events = {playbackChannelEvent(0, 0xC0, 0)};
    if (controller) {
        file.tracks[1].events.push_back(
            playbackChannelEvent(tick, 0xB0, controller->first, controller->second));
    }
    file.tracks[1].endTick = 48;
    return file;
}

SmfFile replacementSong(bool replacement)
{
    SmfFile file;
    file.format = 1;
    file.division = kPlaybackDivision;
    file.tracks.resize(2);
    file.tracks[0].events = {
        playbackMetaEvent(0, 0x51, QByteArray("\x07\xA1\x20", 3)),
    };
    file.tracks[0].endTick = 48;
    file.tracks[1].events = {
        playbackChannelEvent(0, 0xC0, 0),
        playbackChannelEvent(0, 0x90, 60, 100),
        playbackChannelEvent(24, 0x80, 60),
    };
    if (replacement) {
        file.tracks[1].events.push_back(playbackChannelEvent(8, 0x90, 67, 100));
        file.tracks[1].events.push_back(playbackChannelEvent(14, 0x80, 67));
        std::stable_sort(
            file.tracks[1].events.begin(), file.tracks[1].events.end(),
            [](const SmfEvent &left, const SmfEvent &right) { return left.tick < right.tick; });
    }
    file.tracks[1].endTick = 48;
    return file;
}

struct PlaybackEngineFixture {
    checks::SustainVoicegroup bank;
    M4AEngine engine{};
    bool initialized = false;

    PlaybackEngineFixture()
    {
        initialized = m4a_engine_init(&engine, float(kPlaybackSampleRate));
        if (initialized)
            m4a_engine_set_voicegroup(&engine, bank.voices);
    }

    ~PlaybackEngineFixture()
    {
        if (initialized)
            m4a_engine_destroy(&engine);
    }

    PlaybackEngineFixture(const PlaybackEngineFixture &) = delete;
    PlaybackEngineFixture &operator=(const PlaybackEngineFixture &) = delete;
};

QString loadCppTimeline(const QString &path, std::unique_ptr<MidiTimeline> *timeline,
                        const char *cppId)
{
    QString error;
    *timeline = MidiTimeline::load(path, kPlaybackSampleRate, &error);
    if (!*timeline)
        return playbackFailure(cppId, QStringLiteral("C++ timeline load failed: %1").arg(error));
    return {};
}

QString compareProjection(const QString &path, const char *cppId)
{
    std::unique_ptr<MidiTimeline> cpp;
    if (const QString failure = loadCppTimeline(path, &cpp, cppId); !failure.isEmpty())
        return failure;

    std::array<char, 512> error{};
    PdPlaybackData swiftData{};
    const QByteArray encodedPath = QFile::encodeName(path);
    const int64_t count =
        pdc_playback_project_file(encodedPath.constData(), kPlaybackSampleRate, false, false,
                                  nullptr, 0, &swiftData, error.data(), error.size());
    if (count < 0) {
        return playbackFailure(
            cppId,
            QStringLiteral("Swift projection failed: %1").arg(QString::fromUtf8(error.data())));
    }
    std::vector<PdPlaybackEvent> swiftEvents(static_cast<size_t>(count));
    const int64_t copied = pdc_playback_project_file(
        encodedPath.constData(), kPlaybackSampleRate, false, false, swiftEvents.data(),
        swiftEvents.size(), &swiftData, error.data(), error.size());
    if (copied != count) {
        return playbackFailure(
            cppId, QStringLiteral("projection sizing=%1 copy=%2").arg(count).arg(copied));
    }
    if (swiftEvents.size() != cpp->events.size()) {
        return playbackFailure(cppId, QStringLiteral("event count C++=%1 Swift=%2")
                                          .arg(cpp->events.size())
                                          .arg(swiftEvents.size()));
    }
    if (swiftData.tempoPointCount != cpp->tempoMap.size() ||
        swiftData.sampleRate != cpp->sampleRate || swiftData.lengthSamples != cpp->lengthSamples ||
        swiftData.loopStartSample != cpp->loopStartSample ||
        swiftData.loopEndSample != cpp->loopEndSample ||
        swiftData.ticksPerBeat != cpp->ticksPerBeat || swiftData.lengthTicks != cpp->lengthTicks ||
        swiftData.loopStartTick != cpp->loopStartTick ||
        swiftData.loopEndTick != cpp->loopEndTick ||
        swiftData.usedTrackCount != uint32_t(cpp->usedTrackCount) ||
        swiftData.droppedTracks != uint32_t(cpp->droppedTracks) || swiftData.exactGate ||
        swiftData.extendedClocks) {
        return playbackFailure(cppId, QStringLiteral("timeline scalar projection differs"));
    }

    for (size_t index = 0; index < cpp->events.size(); ++index) {
        const TimelineEvent &left = cpp->events[index];
        const PdPlaybackEvent &right = swiftEvents[index];
        const uint64_t cppNoteId = std::bit_cast<uint64_t>(left.noteId);
        if (right.sample != left.samplePos || right.tick != left.tick || right.type != left.type ||
            right.track != left.track || right.data0 != left.data0 || right.data1 != left.data1 ||
            right.noteID != cppNoteId) {
            return playbackFailure(cppId,
                                   QStringLiteral("event %1 differs: C++=(%2,%3,%4,%5,%6,%7,%8) "
                                                  "Swift=(%9,%10,%11,%12,%13,%14,%15)")
                                       .arg(index)
                                       .arg(left.samplePos)
                                       .arg(left.tick)
                                       .arg(left.type)
                                       .arg(left.track)
                                       .arg(left.data0)
                                       .arg(left.data1)
                                       .arg(cppNoteId)
                                       .arg(right.sample)
                                       .arg(right.tick)
                                       .arg(right.type)
                                       .arg(right.track)
                                       .arg(right.data0)
                                       .arg(right.data1)
                                       .arg(right.noteID));
        }
    }
    return {};
}

QString compareDecodedNoteIds(const QString &path)
{
    std::unique_ptr<MidiTimeline> cpp;
    if (const QString failure = loadCppTimeline(path, &cpp, kIdentitiesId); !failure.isEmpty())
        return failure;
    std::array<char, 512> error{};
    const QByteArray encodedPath = QFile::encodeName(path);
    const int64_t count =
        pdc_playback_project_file(encodedPath.constData(), kPlaybackSampleRate, false, false,
                                  nullptr, 0, nullptr, error.data(), error.size());
    if (count < 0)
        return playbackFailure(kIdentitiesId, QString::fromUtf8(error.data()));
    std::vector<PdPlaybackEvent> events(static_cast<size_t>(count));
    const int64_t copied = pdc_playback_project_file(encodedPath.constData(), kPlaybackSampleRate,
                                                     false, false, events.data(), events.size(),
                                                     nullptr, error.data(), error.size());
    if (copied != count || events.size() != cpp->events.size())
        return playbackFailure(kIdentitiesId, QStringLiteral("identity projection size differs"));
    size_t noteOns = 0;
    for (size_t index = 0; index < events.size(); ++index) {
        const uint64_t expected = std::bit_cast<uint64_t>(cpp->events[index].noteId);
        if (cpp->events[index].type == 0x9) {
            ++noteOns;
            if (expected != 0) {
                return playbackFailure(
                    kIdentitiesId,
                    QStringLiteral("decoded fixture unexpectedly retained serialized NoteID"));
            }
        }
        if (events[index].noteID != expected) {
            return playbackFailure(kIdentitiesId, QStringLiteral("event %1 NoteID C++=%2 Swift=%3")
                                                      .arg(index)
                                                      .arg(expected)
                                                      .arg(events[index].noteID));
        }
    }
    if (noteOns == 0)
        return playbackFailure(kIdentitiesId, QStringLiteral("identity fixture has no note-ons"));
    return {};
}

bool rendersAudibly(M4AEngine *engine)
{
    constexpr size_t chunkFrames = 512;
    constexpr size_t maximumFrames = 4096;
    std::array<float, chunkFrames> left{};
    std::array<float, chunkFrames> right{};
    for (size_t rendered = 0; rendered < maximumFrames; rendered += chunkFrames) {
        m4a_engine_process(engine, left.data(), right.data(), int(chunkFrames));
        for (size_t frame = 0; frame < chunkFrames; ++frame) {
            if (left[frame] != 0.0f || right[frame] != 0.0f)
                return true;
        }
    }
    return false;
}

QString prepareSwift(const QString &path, bool native, M4AEngine *engine, uint64_t position,
                     bool chase, bool prime, const char *cppId)
{
    std::array<char, 512> error{};
    const QByteArray encodedPath = QFile::encodeName(path);
    const bool prepared =
        native
            ? pdc_playback_prepare_file_native(encodedPath.constData(), kPlaybackSampleRate, engine,
                                               position, chase, prime, error.data(), error.size())
            : pdc_playback_prepare_file(encodedPath.constData(), kPlaybackSampleRate, false, false,
                                        engine, position, chase, prime, error.data(), error.size());
    if (!prepared) {
        return playbackFailure(
            cppId, QStringLiteral("Swift prepare failed: %1").arg(QString::fromUtf8(error.data())));
    }
    return {};
}

int controllerField(const M4ATrack &track, uint8_t controller)
{
    switch (controller) {
    case CoreTimeDefaults::kCcModulation:
        return track.mod;
    case CoreTimeDefaults::kCcPortamento:
        return track.portamentoDuration;
    case CoreTimeDefaults::kCcVolume:
        return track.rawVolume;
    case CoreTimeDefaults::kCcPan:
        return track.pan;
    case CoreTimeDefaults::kCcBendRange:
        return track.bendRange;
    case CoreTimeDefaults::kCcLfoSpeed:
        return track.lfoSpeed;
    case CoreTimeDefaults::kCcModType:
        return track.modT;
    case CoreTimeDefaults::kCcPwmCycle:
        return track.pwmPattern;
    case CoreTimeDefaults::kCcFineTune:
        return track.tune;
    case CoreTimeDefaults::kCcPwmWidth:
        return track.pwmSpeed;
    case CoreTimeDefaults::kCcLfoDelay:
        return track.lfoDelay;
    default:
        return std::numeric_limits<int>::min();
    }
}

int expectedControllerField(uint8_t controller, uint8_t value)
{
    if (controller == CoreTimeDefaults::kCcPan || controller == CoreTimeDefaults::kCcFineTune) {
        return int(value) - 64;
    }
    return value;
}

QString comparePcm(const std::vector<float> &cppLeft, const std::vector<float> &cppRight,
                   const std::vector<float> &swiftLeft, const std::vector<float> &swiftRight,
                   const char *cppId)
{
    if (cppLeft.size() != swiftLeft.size() || cppRight.size() != swiftRight.size())
        return playbackFailure(cppId, QStringLiteral("PCM buffer sizes differ"));
    for (size_t frame = 0; frame < cppLeft.size(); ++frame) {
        if (std::bit_cast<uint32_t>(cppLeft[frame]) != std::bit_cast<uint32_t>(swiftLeft[frame]) ||
            std::bit_cast<uint32_t>(cppRight[frame]) !=
                std::bit_cast<uint32_t>(swiftRight[frame])) {
            return playbackFailure(cppId,
                                   QStringLiteral("PCM frame %1 differs: C++=(%2,%3) Swift=(%4,%5)")
                                       .arg(frame)
                                       .arg(cppLeft[frame], 0, 'g', 9)
                                       .arg(cppRight[frame], 0, 'g', 9)
                                       .arg(swiftLeft[frame], 0, 'g', 9)
                                       .arg(swiftRight[frame], 0, 'g', 9));
        }
    }
    return {};
}

} // namespace

SwiftCoreTest::SwiftCoreTest(QString fixtureRoot) : m_fixtureRoot(std::move(fixtureRoot)) {}

void SwiftCoreTest::midiCodec()
{
    struct FixtureCase {
        const char *cppId;
        const char *relativePath;
    };
    const std::array<FixtureCase, 5> fixtures = {{
        {"smfcheck/MidiSmfTest::opaqueSysExAndMetaEventsRoundTrip",
         "test_midis/smf/valid/opaque_sysex.mid"},
        {"smfcheck/MidiSmfTest::vlqRunningStatusResetsAcrossMeta",
         "test_midis/smf/valid/vlq_running_status.mid"},
        {"smfcheck/MidiSmfTest::noteLifecyclePreservesSameTickOrdering",
         "test_midis/smf/valid/note_lifecycle.mid"},
        {"smfcheck/MidiSmfTest::duplicateEndOfTrackCanonicalizes",
         "test_midis/smf/malformed/duplicate_eot.mid"},
        {"smfcheck/MidiSmfTest::automationBurstPreservesEveryChannelEvent",
         "test_midis/smf/stress/automation_burst.mid"},
    }};

    const std::array<const char *, 14> projectSongs = {{
        "sound/songs/midi/mus_caught.mid",
        "sound/songs/midi/mus_dummy.mid",
        "sound/songs/midi/mus_gsc_route38.mid",
        "sound/songs/midi/mus_gym.mid",
        "sound/songs/midi/mus_littleroot_test.mid",
        "sound/songs/midi/mus_oldale.mid",
        "sound/songs/midi/mus_petalburg.mid",
        "sound/songs/midi/mus_route101.mid",
        "sound/songs/midi/mus_route102.mid",
        "sound/songs/midi/mus_surf.mid",
        "sound/songs/midi/mus_victory_wild.mid",
        "sound/songs/midi/se_fanfare_1trk.mid",
        "sound/songs/midi/se_pc_login.mid",
        "sound/songs/midi/se_use_item.mid",
    }};
    for (const char *relativePath : projectSongs) {
        const QString path = m_fixtureRoot + QLatin1Char('/') + QString::fromLatin1(relativePath);
        QFile file(path);
        const QString cppId = QStringLiteral("no-row/core/smf.cpp/normal-project-song/%1")
                                  .arg(QString::fromLatin1(relativePath));
        QVERIFY2(file.open(QIODevice::ReadOnly),
                 qPrintable(QStringLiteral("cppId=%1: missing fixture %2").arg(cppId, path)));
        compareCodecCase(cppId, file.readAll(), true);
    }
    for (const FixtureCase &fixture : fixtures) {
        const QString path =
            m_fixtureRoot + QLatin1Char('/') + QString::fromLatin1(fixture.relativePath);
        QFile file(path);
        QVERIFY2(file.open(QIODevice::ReadOnly),
                 qPrintable(QStringLiteral("cppId=%1: missing fixture %2")
                                .arg(QString::fromLatin1(fixture.cppId), path)));
        compareCodecCase(QString::fromLatin1(fixture.cppId), file.readAll(), true);
    }

    compareCodecCase(QStringLiteral("smfcheck/MidiSmfTest::validFormat0ParsingAndCoercion"),
                     format0Bytes(QByteArray::fromHex("00903c4010803c4000c07f00ff2f00")), true);
    compareCodecCase(QStringLiteral("smfcheck/MidiSmfTest::highDataBytesKeepStreamAlignment"),
                     format0Bytes(QByteArray::fromHex("00c08000903c4000b00780000a4000ff2f00")),
                     true);
    compareCodecCase(
        QStringLiteral(
            "smfcheck/MidiSmfTest::noteLifecyclePreservesSameTickOrdering/velocity-zero"),
        format0Bytes(QByteArray::fromHex("00903c0000ff2f00")), true);
    compareCodecCase(
        QStringLiteral("smfcheck/MidiSmfTest::opaqueSysExAndMetaEventsRoundTrip/synthetic"),
        midiBytes(1, 48,
                  {QByteArray::fromHex("00ff7f04deadbeef00f0057e7f0903f700f7034312f700ff2f00")}),
        true);
    compareCodecCase(
        QStringLiteral("editcheck/EditCheckTest::formatZeroCoercion/channel-prefix-routing"),
        format0Bytes(QByteArray::fromHex(
            "00ff510307a12000ff0304536f6e6700ff20010400ff03044c65616400ff0403477472"
            "00913c6400944064009743640cff06015b00ff20010700ff03013a00813c0000844000"
            "008743000cff06015d00ff20010900ff0307416d6269656e740cff2f00")),
        true);
    compareCodecCase(
        QStringLiteral("smf.cpp::mapSmfEngineTracks/explicit-no-row/metadata-only-chunk"),
        midiBytes(1, 24, {QByteArray::fromHex("00ff03044e616d6518ff2f00")}), true);
    compareCodecCase(
        QStringLiteral("smfcheck/MidiSmfTest::duplicateEndOfTrackCanonicalizes/trailing-data"),
        midiBytes(1, 24, {QByteArray::fromHex("0a903c4014ff2f0000903e40")}), true);
    compareCodecCase(
        QStringLiteral("smfcheck/MidiSmfTest::noteLifecyclePreservesSameTickOrdering/synthetic"),
        midiBytes(1, 24, {QByteArray::fromHex("00903c4000803c4000903e0000ff2f00")}), true);

    std::vector<QByteArray> mappingTracks{QByteArray::fromHex("00ff510307a12000ff2f00"),
                                          QByteArray::fromHex("00ff03044d65746100ff2f00")};
    for (int track = 0; track < 18; ++track) {
        QByteArray body = QByteArray::fromHex("00c00000ff2f00");
        body[1] = char(0xC0 | (track & 0x0F));
        mappingTracks.push_back(body);
    }
    compareCodecCase(
        QStringLiteral("smfcheck/MidiSmfTest::engineTrackMappingAgreesAcrossProjections/"
                       "SmfEngineTrackMapping"),
        midiBytes(1, 24, mappingTracks), true);

    compareCodecCase(QStringLiteral("smf.cpp::SmfFile::read/explicit-no-row/truncated-header"),
                     QByteArray("MThd\0\0", 6), false);
    compareCodecCase(QStringLiteral("smf.cpp::parseTrack/explicit-no-row/truncated-event"),
                     midiBytes(1, 24, {QByteArray::fromHex("00903c")}), false);
    compareCodecCase(QStringLiteral("smf.cpp::SmfFile::read/explicit-no-row/division-zero"),
                     midiBytes(1, 0, {QByteArray::fromHex("00ff2f00")}), false);
    compareCodecCase(QStringLiteral("smf.cpp::SmfFile::read/explicit-no-row/division-smpte"),
                     midiBytes(1, 0xE728, {QByteArray::fromHex("00ff2f00")}), false);
    compareCodecCase(
        QStringLiteral("smfcheck/MidiSmfTest::vlqRunningStatusResetsAcrossMeta/invalid-carry"),
        format0Bytes(QByteArray::fromHex("00903c4000ff010158003e4000ff2f00")), false);
    compareCodecCase(
        QStringLiteral("smf.cpp::parseTrack/explicit-no-row/running-status-after-sysex"),
        format0Bytes(QByteArray::fromHex("00903c4000f001f7003e4000ff2f00")), false);

    QByteArray overlong;
    for (int index = 0; index < 17; ++index)
        overlong.append(QByteArray::fromHex("ffffff7f903c40"));
    overlong.append(QByteArray::fromHex("00ff2f00"));
    compareCodecCase(QStringLiteral("smfcheck/MidiSmfTest::overlongTickFailsParsing"),
                     format0Bytes(overlong), false);

    const QByteArray cppBlank = SongRegistry::blankSong().write();
    const int64_t blankSize = pdc_blank_song(nullptr, 0);
    QVERIFY2(blankSize >= 0, "cppId=project/SongRegistry::blankSong: Swift factory failed");
    QByteArray swiftBlank(int(blankSize), Qt::Uninitialized);
    const int64_t blankCopySize =
        pdc_blank_song(reinterpret_cast<uint8_t *>(swiftBlank.data()), size_t(swiftBlank.size()));
    QVERIFY2(blankCopySize == blankSize,
             qPrintable(QStringLiteral("cppId=project/SongRegistry::blankSong: sizing=%1 copy=%2")
                            .arg(blankSize)
                            .arg(blankCopySize)));
    const QString blankFailure =
        QStringLiteral("cppId=project/SongRegistry::blankSong: C++=%1 Swift=%2")
            .arg(QString::fromLatin1(cppBlank.toHex()), QString::fromLatin1(swiftBlank.toHex()));
    QVERIFY2(swiftBlank == cppBlank, qPrintable(blankFailure));
    compareCodecCase(QStringLiteral("project/SongRegistry::blankSong/reparse"), swiftBlank, true);
}

void SwiftCoreTest::musicalSemantics()
{
    for (int cc = 0; cc <= 127; ++cc) {
        const M4aCcInfo info = m4aClassifyCc(uint8_t(cc));
        expectValue(QStringLiteral("cc-%1-class").arg(cc), int(info.eventClass),
                    pdc_semantic_value(PDC_CC_EVENT_CLASS, cc, 0, 0, 0));
        expectValue(QStringLiteral("cc-%1-lane").arg(cc), int(info.lane),
                    pdc_semantic_value(PDC_CC_LANE, cc, 0, 0, 0));
        expectValue(QStringLiteral("cc-%1-export").arg(cc), int(m4aExportSupport(uint8_t(cc))),
                    pdc_semantic_value(PDC_CC_EXPORT_SUPPORT, cc, 0, 0, 0));
        expectText(QStringLiteral("cc-%1-name").arg(cc), QString::fromLatin1(info.name),
                   swiftText(PDC_CC_NAME, cc));
        expectText(QStringLiteral("cc-%1-display").arg(cc), QString::fromLatin1(info.display),
                   swiftText(PDC_CC_DISPLAY, cc));
        for (int value = 0; value <= 127; ++value) {
            expectText(QStringLiteral("cc-%1-value-%2").arg(cc).arg(value),
                       m4aFormatCcValue(uint8_t(cc), uint8_t(value)),
                       swiftText(PDC_FORMAT_CC_VALUE, cc, value));
            expectText(QStringLiteral("cc-%1-label-%2").arg(cc).arg(value),
                       m4aAdvancedCcLabel(uint8_t(cc), uint8_t(value)),
                       swiftText(PDC_ADVANCED_CC_LABEL, cc, value));
        }
    }

    for (int lane = int(M4aLane::Mod); lane <= int(M4aLane::Tempo); ++lane) {
        expectText(QStringLiteral("lane-%1-name").arg(lane), m4aLaneName(M4aLane(lane)),
                   swiftText(PDC_LANE_NAME, lane));
    }
    for (const int selector : {0x08, 0x09}) {
        expectValue(QStringLiteral("xcmd-%1-lane").arg(selector),
                    int(m4aLaneForXcmdSelector(uint8_t(selector))),
                    pdc_semantic_value(PDC_XCMD_LANE, selector, 0, 0, 0));
    }
    for (int bend = -8192; bend <= 8191; ++bend) {
        expectText(QStringLiteral("bend-%1").arg(bend), m4aFormatBend(bend),
                   swiftText(PDC_FORMAT_BEND, bend));
    }
    for (int type = 0; type <= 255; ++type) {
        expectText(QStringLiteral("voice-type-%1").arg(type), m4aVoiceTypeName(uint8_t(type)),
                   swiftText(PDC_VOICE_TYPE_NAME, type));
    }
    for (int key = 0; key <= 127; ++key) {
        expectText(QStringLiteral("key-%1").arg(key), midiKeyName(key),
                   swiftText(PDC_MIDI_KEY_NAME, key));
    }
    for (int numerator = 1; numerator <= 16; ++numerator) {
        for (int power = 0; power <= 10; ++power) {
            expectText(QStringLiteral("time-signature-%1-%2").arg(numerator).arg(power),
                       midiTimeSigLabel(numerator, power),
                       swiftText(PDC_TIME_SIGNATURE_LABEL, numerator, power));
        }
    }

    for (int velocity = -2; velocity <= 130; ++velocity) {
        expectValue(QStringLiteral("effective-velocity-%1").arg(velocity),
                    mid2agbEffectiveVelocity(velocity),
                    pdc_semantic_value(PDC_EFFECTIVE_VELOCITY, velocity, 0, 0, 0));
    }
    for (const uint32_t division : {0U, 24U, 48U, 96U, 480U}) {
        for (int duration = -2; duration <= 200; ++duration) {
            for (const bool extended : {false, true}) {
                for (const bool exact : {false, true}) {
                    const QString name = QStringLiteral("duration-%1-%2-%3-%4")
                                             .arg(duration)
                                             .arg(division)
                                             .arg(extended)
                                             .arg(exact);
                    expectValue(name, mid2agbEffectiveDuration(duration, division, extended, exact),
                                pdc_semantic_value(PDC_EFFECTIVE_DURATION, duration, division,
                                                   extended, exact));
                }
            }
        }
    }

    for (int kind = 0; kind < 8; ++kind) {
        const VelocityMap map = cppVelocityMap(kind);
        expectValue(QStringLiteral("velocity-kind-%1-is-psg").arg(kind), map.isPsg(),
                    pdc_semantic_value(PDC_VELOCITY_IS_PSG, kind, 0, 0, 0));
        expectValue(QStringLiteral("velocity-kind-%1-count").arg(kind), int64_t(map.levelCount()),
                    pdc_semantic_value(PDC_VELOCITY_LEVEL_COUNT, kind, 0, 0, 0));
        expectText(QStringLiteral("velocity-kind-%1-name").arg(kind),
                   QString::fromLatin1(map.voiceName()), swiftText(PDC_VELOCITY_VOICE_NAME, kind));
        for (int other = 0; other < 8; ++other) {
            expectValue(QStringLiteral("velocity-kind-%1-compatible-%2").arg(kind).arg(other),
                        map.compatibleWith(cppVelocityMap(other)),
                        pdc_semantic_value(PDC_VELOCITY_COMPATIBLE, kind, other, 0, 0));
        }
        for (int level = -2; level <= 18; ++level) {
            const VelocityLevelRange range = map.levelRange(level);
            const int packedRange = (int(range.first) << 8) | int(range.last);
            expectValue(QStringLiteral("velocity-kind-%1-range-%2").arg(kind).arg(level),
                        packedRange,
                        pdc_semantic_value(PDC_VELOCITY_LEVEL_RANGE, kind, level, 0, 0));
            expectValue(QStringLiteral("velocity-kind-%1-representative-%2").arg(kind).arg(level),
                        map.representative(level),
                        pdc_semantic_value(PDC_VELOCITY_REPRESENTATIVE, kind, level, 0, 0));
        }
        for (int velocity = -2; velocity <= 130; ++velocity) {
            const std::optional<size_t> level = map.levelOf(velocity);
            expectValue(QStringLiteral("velocity-kind-%1-level-of-%2").arg(kind).arg(velocity),
                        level ? int64_t(*level) : -1,
                        pdc_semantic_value(PDC_VELOCITY_LEVEL_OF, kind, velocity, 0, 0));
            expectValue(QStringLiteral("velocity-kind-%1-canonical-%2").arg(kind).arg(velocity),
                        map.canonicalize(velocity),
                        pdc_semantic_value(PDC_VELOCITY_CANONICALIZE, kind, velocity, 0, 0));
        }
        for (const int origin : {0, 1, 8, 9, 60, 64, 65, 80, 95, 112, 127, 128}) {
            for (int delta = -3; delta <= 3; ++delta) {
                expectValue(
                    QStringLiteral("velocity-kind-%1-move-%2-%3").arg(kind).arg(origin).arg(delta),
                    map.moveLevels(uint8_t(origin), delta),
                    pdc_semantic_value(PDC_VELOCITY_MOVE_LEVELS, kind, origin, delta, 0));
            }
        }
    }

    for (int cc = 0; cc <= 255; ++cc) {
        const auto domain = CoreTimeDefaults::laneDomain(uint8_t(cc));
        expectValue(QStringLiteral("controller-%1-default").arg(cc),
                    CoreTimeDefaults::controllerDefault(uint8_t(cc)),
                    pdc_semantic_value(PDC_CONTROLLER_DEFAULT, cc, 0, 0, 0));
        expectValue(QStringLiteral("controller-%1-min").arg(cc), domain.minimum,
                    pdc_semantic_value(PDC_LANE_MINIMUM, cc, 0, 0, 0));
        expectValue(QStringLiteral("controller-%1-max").arg(cc), domain.maximum,
                    pdc_semantic_value(PDC_LANE_MAXIMUM, cc, 0, 0, 0));
        expectValue(QStringLiteral("controller-%1-centered").arg(cc), domain.centered,
                    pdc_semantic_value(PDC_LANE_CENTERED, cc, 0, 0, 0));
        expectValue(QStringLiteral("controller-%1-zoomable").arg(cc), domain.zoomable,
                    pdc_semantic_value(PDC_LANE_ZOOMABLE, cc, 0, 0, 0));
        expectValue(QStringLiteral("controller-%1-engine-default").arg(cc),
                    CoreTimeDefaults::hasEngineDefaultNode(uint8_t(cc)),
                    pdc_semantic_value(PDC_HAS_ENGINE_DEFAULT, cc, 0, 0, 0));
    }
    for (int bpm = -10; bpm <= 300; ++bpm) {
        expectValue(QStringLiteral("tempo-bpm-%1").arg(bpm),
                    CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm),
                    pdc_semantic_value(PDC_TEMPO_USPQN_FOR_BPM, bpm, 0, 0, 0));
    }
    for (const uint32_t uspqn : {0U, 1U, 235294U, 500000U, 3000000U, UINT32_MAX}) {
        const double bpm = CoreTimeDefaults::tempoBpm(uspqn);
        expectValue(QStringLiteral("tempo-value-%1").arg(uspqn), std::bit_cast<int64_t>(bpm),
                    pdc_semantic_value(PDC_TEMPO_BPM_BITS, uspqn, 0, 0, 0));
        expectValue(QStringLiteral("tempo-clamp-%1").arg(uspqn),
                    CoreTimeDefaults::clampTempoUspqn(uspqn),
                    pdc_semantic_value(PDC_CLAMP_TEMPO_USPQN, uspqn, 0, 0, 0));
    }

    const std::array<Tick, 4> ticks = {0, 1, CoreTimeDefaults::kMaxTick, CoreTimeDefaults::kNoTick};
    const std::array<int64_t, 7> deltas = {std::numeric_limits<int64_t>::min(),
                                           -1,
                                           0,
                                           1,
                                           int64_t(CoreTimeDefaults::kMaxTick),
                                           int64_t(CoreTimeDefaults::kNoTick),
                                           std::numeric_limits<int64_t>::max()};
    for (const Tick tick : ticks) {
        for (const int64_t delta : deltas) {
            expectValue(QStringLiteral("shift-%1-%2").arg(tick).arg(delta),
                        CoreTimeDefaults::shiftTickClamped(tick, delta),
                        pdc_semantic_value(PDC_SHIFT_TICK, tick, delta, 0, 0));
        }
    }
    for (const double value :
         {std::numeric_limits<double>::quiet_NaN(), -std::numeric_limits<double>::infinity(), -1.0,
          0.0, 0.5, 1.9, double(CoreTimeDefaults::kMaxTick), double(CoreTimeDefaults::kNoTick),
          std::numeric_limits<double>::infinity()}) {
        const int64_t bits = std::bit_cast<int64_t>(value);
        expectValue(QStringLiteral("tick-from-double-%1").arg(bits),
                    CoreTimeDefaults::tickFromDouble(value),
                    pdc_semantic_value(PDC_TICK_FROM_DOUBLE_BITS, bits, 0, 0, 0));
    }
    expectValue(QStringLiteral("track-capacity"), track_limits::kHardwareCapacity,
                pdc_semantic_value(PDC_TRACK_CAPACITY, 0, 0, 0, 0));

    expectValue(QStringLiteral("note-id-0-assigned"), NoteId().isAssigned(),
                pdc_semantic_value(PDC_NOTE_ID_IS_ASSIGNED, 0, 0, 0, 0));
    expectValue(QStringLiteral("note-id-42-assigned"), NoteId(42).isAssigned(),
                pdc_semantic_value(PDC_NOTE_ID_IS_ASSIGNED, 42, 0, 0, 0));
    SmfEvent plain;
    plain.tick = 12;
    plain.status = 0x90;
    plain.data0 = 60;
    plain.data1 = 100;
    SmfEvent stamped = plain;
    stamped.noteId = NoteId(42);
    SmfTrack plainTrack;
    plainTrack.events = {plain};
    plainTrack.endTick = 24;
    SmfFile plainFile;
    plainFile.division = 24;
    plainFile.tracks = {plainTrack};
    SmfTrack stampedTrack;
    stampedTrack.events = {stamped};
    stampedTrack.endTick = 24;
    SmfFile stampedFile;
    stampedFile.division = 24;
    stampedFile.tracks = {stampedTrack};
    const bool identityDoesNotAffectStorage =
        plain == stamped && plainFile.write() == stampedFile.write();
    expectValue(QStringLiteral("note-id-storage"), identityDoesNotAffectStorage,
                pdc_semantic_value(PDC_NOTE_ID_DOES_NOT_AFFECT_STORAGE, 0, 0, 0, 0));
}

void SwiftCoreTest::playback()
{
    QString failure;

    const QString projectFixture =
        m_fixtureRoot + QStringLiteral("/sound/songs/midi/mus_route101.mid");
    failure = compareProjection(projectFixture, kExactSamplesId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));

    const QString projectionPath = m_fixtureRoot + QStringLiteral("/swiftcore-projection.mid");
    failure = writePlaybackFixture(projectionPath, projectionSong(), kExactSamplesId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    failure = compareProjection(projectionPath, kExactSamplesId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    failure = compareProjection(projectionPath, kMappingId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    failure = compareDecodedNoteIds(projectionPath);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));

    const QString loopPath = m_fixtureRoot + QStringLiteral("/swiftcore-loop.mid");
    failure = writePlaybackFixture(loopPath, loopSong(), kLoopPointsId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    failure = compareProjection(loopPath, kLoopPointsId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    std::unique_ptr<MidiTimeline> loopTimeline;
    failure = loadCppTimeline(loopPath, &loopTimeline, kLoopRenderId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    const bool cppLoopPoints = loopTimeline->hasLoop() &&
                               loopTimeline->loopStartSample == 96 * kPlaybackSamplesPerTick &&
                               loopTimeline->loopEndSample == 288 * kPlaybackSamplesPerTick;
    QVERIFY2(cppLoopPoints,
             qPrintable(playbackFailure(kLoopPointsId,
                                        QStringLiteral("C++ loop fixture has wrong loop points"))));

    constexpr size_t loopFrames = 310000;
    PlaybackEngineFixture cppLoopEngine;
    PlaybackEngineFixture swiftLoopEngine;
    QVERIFY2(cppLoopEngine.initialized && swiftLoopEngine.initialized,
             qPrintable(playbackFailure(kLoopRenderId, QStringLiteral("engine init failed"))));
    std::vector<float> cppLoopLeft(loopFrames);
    std::vector<float> cppLoopRight(loopFrames);
    std::vector<float> swiftLoopLeft(loopFrames);
    std::vector<float> swiftLoopRight(loopFrames);
    TimelinePlayer loopPlayer;
    loopPlayer.render(&cppLoopEngine.engine, loopTimeline.get(), std::span(cppLoopLeft),
                      std::span(cppLoopRight), true, 0);
    std::array<char, 512> renderError{};
    const QByteArray loopEncodedPath = QFile::encodeName(loopPath);
    const bool swiftLoopRendered = pdc_playback_render_files(
        loopEncodedPath.constData(), nullptr, kPlaybackSampleRate, false, false,
        &swiftLoopEngine.engine, swiftLoopLeft.data(), swiftLoopRight.data(), loopFrames, 0, true,
        0, false, false, renderError.data(), renderError.size());
    QVERIFY2(swiftLoopRendered,
             qPrintable(
                 playbackFailure(kLoopRenderId, QStringLiteral("Swift loop render failed: %1")
                                                    .arg(QString::fromUtf8(renderError.data())))));
    failure = comparePcm(cppLoopLeft, cppLoopRight, swiftLoopLeft, swiftLoopRight, kLoopRenderId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));

    const QString primePath = m_fixtureRoot + QStringLiteral("/swiftcore-prime.mid");
    failure = writePlaybackFixture(primePath, primeSong(), kPrimeId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    std::unique_ptr<MidiTimeline> primeTimeline;
    failure = loadCppTimeline(primePath, &primeTimeline, kPrimeId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));

    PlaybackEngineFixture cppUnprimed;
    PlaybackEngineFixture swiftUnprimed;
    QVERIFY2(cppUnprimed.initialized && swiftUnprimed.initialized,
             qPrintable(playbackFailure(kPrimeId, QStringLiteral("unprimed engine init failed"))));
    TimelinePlayer::chase(&cppUnprimed.engine, primeTimeline.get(), 0);
    failure = prepareSwift(primePath, false, &swiftUnprimed.engine, 0, true, false, kPrimeId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    m4a_engine_note_on(&cppUnprimed.engine, 1, 60, 127);
    m4a_engine_note_on(&swiftUnprimed.engine, 1, 60, 127);
    const bool cppUnprimedAudible = rendersAudibly(&cppUnprimed.engine);
    const bool swiftUnprimedAudible = rendersAudibly(&swiftUnprimed.engine);
    QVERIFY2(
        !cppUnprimedAudible && swiftUnprimedAudible == cppUnprimedAudible,
        qPrintable(playbackFailure(kPrimeId, QStringLiteral("unprimed audition C++=%1 Swift=%2")
                                                 .arg(cppUnprimedAudible)
                                                 .arg(swiftUnprimedAudible))));

    PlaybackEngineFixture cppPrimed;
    PlaybackEngineFixture swiftPrimed;
    QVERIFY2(cppPrimed.initialized && swiftPrimed.initialized,
             qPrintable(playbackFailure(kPrimeId, QStringLiteral("primed engine init failed"))));
    TimelinePlayer::chase(&cppPrimed.engine, primeTimeline.get(), 0);
    TimelinePlayer::primeVoices(&cppPrimed.engine, primeTimeline.get(), 0);
    failure = prepareSwift(primePath, false, &swiftPrimed.engine, 0, true, true, kPrimeId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    for (int track = 0; track < 3; ++track) {
        const M4ATrack &cppTrack = cppPrimed.engine.tracks[track];
        const M4ATrack &swiftTrack = swiftPrimed.engine.tracks[track];
        const bool sameProgram = cppTrack.currentProgram == swiftTrack.currentProgram;
        const bool sameVoicePresence =
            (cppTrack.currentVoice.wav != nullptr) == (swiftTrack.currentVoice.wav != nullptr);
        QVERIFY2(sameProgram && sameVoicePresence,
                 qPrintable(playbackFailure(
                     kPrimeId, QStringLiteral("primed track %1 differs: C++ program=%2 voice=%3; "
                                              "Swift program=%4 voice=%5")
                                   .arg(track)
                                   .arg(cppTrack.currentProgram)
                                   .arg(cppTrack.currentVoice.wav != nullptr)
                                   .arg(swiftTrack.currentProgram)
                                   .arg(swiftTrack.currentVoice.wav != nullptr))));
    }
    m4a_engine_note_on(&cppPrimed.engine, 1, 60, 127);
    m4a_engine_note_on(&swiftPrimed.engine, 1, 60, 127);
    const bool cppPrimedAudible = rendersAudibly(&cppPrimed.engine);
    const bool swiftPrimedAudible = rendersAudibly(&swiftPrimed.engine);
    QVERIFY2(cppPrimedAudible && swiftPrimedAudible == cppPrimedAudible,
             qPrintable(playbackFailure(kPrimeId, QStringLiteral("primed audition C++=%1 Swift=%2")
                                                      .arg(cppPrimedAudible)
                                                      .arg(swiftPrimedAudible))));

    PlaybackEngineFixture cppMidSong;
    PlaybackEngineFixture swiftMidSong;
    QVERIFY2(cppMidSong.initialized && swiftMidSong.initialized,
             qPrintable(playbackFailure(kPrimeId, QStringLiteral("mid-song engine init failed"))));
    constexpr uint64_t midSongPosition = 100 * kPlaybackSamplesPerTick;
    TimelinePlayer::chase(&cppMidSong.engine, primeTimeline.get(), midSongPosition);
    TimelinePlayer::primeVoices(&cppMidSong.engine, primeTimeline.get(), midSongPosition);
    failure =
        prepareSwift(primePath, false, &swiftMidSong.engine, midSongPosition, true, true, kPrimeId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    for (int track = 0; track < 2; ++track) {
        const M4ATrack &cppTrack = cppMidSong.engine.tracks[track];
        const M4ATrack &swiftTrack = swiftMidSong.engine.tracks[track];
        QVERIFY2(cppTrack.currentProgram == swiftTrack.currentProgram &&
                     (cppTrack.currentVoice.wav != nullptr) ==
                         (swiftTrack.currentVoice.wav != nullptr),
                 qPrintable(playbackFailure(
                     kPrimeId, QStringLiteral("mid-song track %1 differs: C++ program=%2 voice=%3; "
                                              "Swift program=%4 voice=%5")
                                   .arg(track)
                                   .arg(cppTrack.currentProgram)
                                   .arg(cppTrack.currentVoice.wav != nullptr)
                                   .arg(swiftTrack.currentProgram)
                                   .arg(swiftTrack.currentVoice.wav != nullptr))));
    }

    const QString controllerDefaultPath =
        m_fixtureRoot + QStringLiteral("/swiftcore-controller-default.mid");
    failure = writePlaybackFixture(controllerDefaultPath, controllerSong(std::nullopt, 0),
                                   kControllerDefaultsId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    for (const CoreTimeDefaults::ControllerDefault &controller :
         CoreTimeDefaults::kControllerDefaults) {
        uint8_t nonDefault = controller.cc == CoreTimeDefaults::kCcPwmCycle
                                 ? 1
                                 : (controller.value == 127 ? 91 : uint8_t(controller.value + 17));
        if (nonDefault == controller.value)
            nonDefault = uint8_t(controller.value ^ 1);
        uint8_t overrideValue = controller.cc == CoreTimeDefaults::kCcPwmCycle
                                    ? 2
                                    : (controller.value == 0 ? 73 : uint8_t(controller.value - 1));
        if (overrideValue == nonDefault)
            overrideValue = uint8_t((overrideValue + 11) & 0x7F);
        const QString prefix =
            m_fixtureRoot + QStringLiteral("/swiftcore-controller-%1-").arg(controller.cc);
        const QString nonDefaultPath = prefix + QStringLiteral("nondefault.mid");
        const QString overridePath = prefix + QStringLiteral("override.mid");
        failure = writePlaybackFixture(nonDefaultPath,
                                       controllerSong(std::pair(controller.cc, nonDefault), 0),
                                       kControllerDefaultsId);
        QVERIFY2(failure.isEmpty(), qPrintable(failure));
        failure = writePlaybackFixture(overridePath,
                                       controllerSong(std::pair(controller.cc, overrideValue), 12),
                                       kControllerDefaultsId);
        QVERIFY2(failure.isEmpty(), qPrintable(failure));

        for (bool native : {false, true}) {
            PlaybackEngineFixture engine;
            QVERIFY2(engine.initialized,
                     qPrintable(playbackFailure(kControllerDefaultsId,
                                                QStringLiteral("controller engine init failed"))));
            m4a_engine_set_portamento_enabled(&engine.engine, true);
            m4a_engine_set_pwm_enabled(&engine.engine, true);
            failure = prepareSwift(nonDefaultPath, native, &engine.engine, kPlaybackSamplesPerTick,
                                   true, false, kControllerDefaultsId);
            QVERIFY2(failure.isEmpty(), qPrintable(failure));
            const int applied = controllerField(engine.engine.tracks[0], controller.cc);
            const int expectedApplied = expectedControllerField(controller.cc, nonDefault);
            QVERIFY2(applied == expectedApplied,
                     qPrintable(playbackFailure(
                         kControllerDefaultsId,
                         QStringLiteral("%1 path CC %2 non-default expected=%3 actual=%4")
                             .arg(native ? QStringLiteral("native") : QStringLiteral("Swift"))
                             .arg(controller.cc)
                             .arg(expectedApplied)
                             .arg(applied))));

            failure = prepareSwift(controllerDefaultPath, native, &engine.engine,
                                   kPlaybackSamplesPerTick, true, false, kControllerDefaultsId);
            QVERIFY2(failure.isEmpty(), qPrintable(failure));
            const int restored = controllerField(engine.engine.tracks[0], controller.cc);
            const int expectedDefault = expectedControllerField(controller.cc, controller.value);
            QVERIFY2(restored == expectedDefault,
                     qPrintable(playbackFailure(
                         kControllerDefaultsId,
                         QStringLiteral("%1 path CC %2 default expected=%3 actual=%4")
                             .arg(native ? QStringLiteral("native") : QStringLiteral("Swift"))
                             .arg(controller.cc)
                             .arg(expectedDefault)
                             .arg(restored))));

            failure =
                prepareSwift(overridePath, native, &engine.engine, 13 * kPlaybackSamplesPerTick,
                             true, false, kControllerDefaultsId);
            QVERIFY2(failure.isEmpty(), qPrintable(failure));
            const int overridden = controllerField(engine.engine.tracks[0], controller.cc);
            const int expectedOverride = expectedControllerField(controller.cc, overrideValue);
            QVERIFY2(overridden == expectedOverride,
                     qPrintable(playbackFailure(
                         kControllerDefaultsId,
                         QStringLiteral("%1 path CC %2 pre-seek expected=%3 actual=%4")
                             .arg(native ? QStringLiteral("native") : QStringLiteral("Swift"))
                             .arg(controller.cc)
                             .arg(expectedOverride)
                             .arg(overridden))));
        }
    }

    const QString originalPath = m_fixtureRoot + QStringLiteral("/swiftcore-replace-original.mid");
    const QString replacementPath =
        m_fixtureRoot + QStringLiteral("/swiftcore-replace-updated.mid");
    failure = writePlaybackFixture(originalPath, replacementSong(false), kReplacementId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    failure = writePlaybackFixture(replacementPath, replacementSong(true), kReplacementId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    std::unique_ptr<MidiTimeline> originalTimeline;
    std::unique_ptr<MidiTimeline> replacementTimeline;
    failure = loadCppTimeline(originalPath, &originalTimeline, kReplacementId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
    failure = loadCppTimeline(replacementPath, &replacementTimeline, kReplacementId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));

    constexpr size_t replacementFrames = 16000;
    constexpr size_t replacementAt = 5000;
    PlaybackEngineFixture cppReplacementEngine;
    PlaybackEngineFixture swiftReplacementEngine;
    QVERIFY2(cppReplacementEngine.initialized && swiftReplacementEngine.initialized,
             qPrintable(playbackFailure(kReplacementId, QStringLiteral("engine init failed"))));
    std::vector<float> cppReplacementLeft(replacementFrames);
    std::vector<float> cppReplacementRight(replacementFrames);
    std::vector<float> swiftReplacementLeft(replacementFrames);
    std::vector<float> swiftReplacementRight(replacementFrames);
    TimelinePlayer replacementPlayer;
    replacementPlayer.render(&cppReplacementEngine.engine, originalTimeline.get(),
                             std::span(cppReplacementLeft).first(replacementAt),
                             std::span(cppReplacementRight).first(replacementAt), false, 0);
    replacementPlayer.replaceTimeline(replacementPlayer.position(), replacementTimeline.get());
    replacementPlayer.render(&cppReplacementEngine.engine, replacementTimeline.get(),
                             std::span(cppReplacementLeft).subspan(replacementAt),
                             std::span(cppReplacementRight).subspan(replacementAt), false, 0);
    renderError.fill(0);
    const QByteArray originalEncodedPath = QFile::encodeName(originalPath);
    const QByteArray replacementEncodedPath = QFile::encodeName(replacementPath);
    const bool swiftReplacementRendered = pdc_playback_render_files(
        originalEncodedPath.constData(), replacementEncodedPath.constData(), kPlaybackSampleRate,
        false, false, &swiftReplacementEngine.engine, swiftReplacementLeft.data(),
        swiftReplacementRight.data(), replacementFrames, replacementAt, false, 0, false, false,
        renderError.data(), renderError.size());
    QVERIFY2(swiftReplacementRendered,
             qPrintable(playbackFailure(kReplacementId,
                                        QStringLiteral("Swift replacement render failed: %1")
                                            .arg(QString::fromUtf8(renderError.data())))));
    failure = comparePcm(cppReplacementLeft, cppReplacementRight, swiftReplacementLeft,
                         swiftReplacementRight, kReplacementId);
    QVERIFY2(failure.isEmpty(), qPrintable(failure));
}

int runSwiftCoreCheck(const QString &fixtureRoot, const QStringList &qtArguments)
{
    SwiftCoreTest test(fixtureRoot);
    QStringList arguments{QStringLiteral("swiftcore")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
