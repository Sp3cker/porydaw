#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include <algorithm>
#include <vector>

#include "checks/editcheck/tst_songdocument_support.h"
#include "core/miditimeline.h"
#include "core/xcmd.h"

namespace {

SmfFile formatZeroFile()
{
    SmfFile smf;
    smf.format = 0;
    smf.division = 24;
    SmfTrack track;
    track.events = {songdocument_test::meta(0x51, 0, QByteArray("\x07\xA1\x20", 3)),
                    songdocument_test::meta(0x03, 0, QByteArrayLiteral("Song")),
                    songdocument_test::meta(0x20, 0, QByteArray(1, char(4))),
                    songdocument_test::meta(0x03, 0, QByteArrayLiteral("Lead")),
                    songdocument_test::meta(0x04, 0, QByteArrayLiteral("Gtr")),
                    songdocument_test::channel(0x91, 0, 60, 100),
                    songdocument_test::channel(0x94, 0, 64, 100),
                    songdocument_test::channel(0x97, 0, 67, 100),
                    songdocument_test::meta(0x06, 12, QByteArrayLiteral("[")),
                    songdocument_test::meta(0x20, 12, QByteArray(1, char(7))),
                    songdocument_test::meta(0x03, 12, QByteArrayLiteral(":")),
                    songdocument_test::channel(0x81, 24, 60, 0),
                    songdocument_test::channel(0x84, 24, 64, 0),
                    songdocument_test::channel(0x87, 24, 67, 0),
                    songdocument_test::meta(0x06, 36, QByteArrayLiteral("]")),
                    songdocument_test::meta(0x20, 36, QByteArray(1, char(9))),
                    songdocument_test::meta(0x03, 36, QByteArrayLiteral("Ambient"))};
    track.endTick = 48;
    smf.tracks.push_back(track);
    return smf;
}

SmfEvent tempoMeta(uint64_t tick, uint32_t microseconds)
{
    QByteArray bytes(3, '\0');
    bytes[0] = char((microseconds >> 16) & 0xFF);
    bytes[1] = char((microseconds >> 8) & 0xFF);
    bytes[2] = char(microseconds & 0xFF);
    return songdocument_test::meta(0x51, tick, bytes);
}

SmfFile duplicateFile()
{
    const TempoPoint normal = songdocument_test::tempo(48, 150);
    const TempoPoint exact{96, 375'001};
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack conductor;
    conductor.events = {songdocument_test::meta(0x01, 0, QByteArrayLiteral("conductor")),
                        tempoMeta(24, 6'000'000),
                        tempoMeta(48, songdocument_test::tempo(48, 120).microsecondsPerQuarterNote),
                        tempoMeta(48, normal.microsecondsPerQuarterNote),
                        songdocument_test::meta(0x01, 48, QByteArrayLiteral("shared tick")),
                        tempoMeta(72, 200'000),
                        tempoMeta(96, exact.microsecondsPerQuarterNote)};
    conductor.endTick = 120;
    smf.tracks.push_back(conductor);
    SmfTrack channel;
    channel.events = {songdocument_test::channel(0xC0, 0, 5, 0),
                      songdocument_test::channel(0xB0, 0, 7, 100),
                      songdocument_test::channel(0xC0, 0, 9, 0),
                      songdocument_test::channel(0xB0, 0, 7, 80),
                      songdocument_test::channel(0x90, 0, 60, 100),
                      songdocument_test::meta(0x51, 48, QByteArray("\x09\x27\xC0", 3)),
                      songdocument_test::channel(0x80, 96, 60, 0)};
    channel.endTick = 96;
    smf.tracks.push_back(channel);
    return smf;
}

std::vector<DocLanePoint> pointsAt(const SongDocument &document, uint8_t cc, uint64_t tick)
{
    std::vector<DocLanePoint> result;
    for (const DocLanePoint &point : document.lanePoints(0, cc)) {
        if (point.tick == tick)
            result.push_back(point);
    }
    return result;
}

bool hasMeta(const SmfTrack &track, uint8_t type, const QByteArray &text)
{
    return std::ranges::any_of(track.events, [type, &text](const SmfEvent &event) {
        return event.isMeta() && event.metaType == type && event.blob == text;
    });
}

} // namespace

void EditCheckTest::xcmdSaveSnapshot()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events.push_back(songdocument_test::channel(0xC0, 0, 1, 0));
    track.endTick = 96;
    smf.tracks.push_back(track);
    auto fixture = songdocument_test::makeDocument(std::move(smf), QStringLiteral("xcmd"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    const int smfTrack = document.smfTrackFor(0);
    QVERIFY(smfTrack >= 0);
    const uint64_t base = 100;
    const uint8_t status = uint8_t(0xB0 | document.channelFor(0));
    document.insertRawEvent(
        smfTrack, songdocument_test::channel(status, base + 1, xcmd::kSelectorController, 0x08));
    document.insertRawEvent(
        smfTrack, songdocument_test::channel(status, base + 2, xcmd::kPayloadController, 34));
    document.insertRawEvent(
        smfTrack, songdocument_test::channel(status, base + 3, xcmd::kSelectorController, 0x09));
    const QByteArray liveBytes = document.smf().write();
    const int undoIndex = document.undoStack()->index();
    const bool dirty = document.isDirty();
    const SongSaveSnapshot snapshot = document.captureSaveSnapshot();
    QCOMPARE(document.smf().write(), liveBytes);
    QCOMPARE(document.undoStack()->index(), undoIndex);
    QCOMPARE(document.isDirty(), dirty);
    const SmfTrack &saved = snapshot.smf.tracks[size_t(smfTrack)];
    bool delayedSelector = false;
    bool danglingSelector = false;
    std::vector<SmfEvent> payload;
    for (const SmfEvent &event : saved.events) {
        if (event.tick == base + 1 && event.isChannel() && event.data0 == xcmd::kSelectorController)
            delayedSelector = true;
        if (event.tick == base + 2 && event.isChannel() &&
            (event.data0 == xcmd::kSelectorController || event.data0 == xcmd::kPayloadController))
            payload.push_back(event);
        if (event.tick == base + 3 && event.isChannel() && event.data0 == xcmd::kSelectorController)
            danglingSelector = true;
    }
    QVERIFY(!delayedSelector);
    QCOMPARE(payload.size(), size_t(2));
    QCOMPARE(payload[0].data0, uint8_t(xcmd::kSelectorController));
    QCOMPARE(payload[0].data1, uint8_t(0x08));
    QCOMPARE(payload[1].data0, uint8_t(xcmd::kPayloadController));
    QCOMPARE(payload[1].data1, uint8_t(34));
    QVERIFY(!danglingSelector);
}

void EditCheckTest::formatZeroCoercion()
{
    songdocument_test::SyntheticDocument fixture;
    QVERIFY2(fixture.stage(formatZeroFile(), QStringLiteral("format0-coercion")),
             qPrintable(fixture.error));
    const SongDocument &document = fixture.document;
    QCOMPARE(document.smf().format, uint16_t(1));
    QVERIFY(document.smf().wasFormat0);
    QCOMPARE(document.smf().tracks.size(), size_t(5));
    QCOMPARE(document.engineTrackCount(), 3);
    QCOMPARE(document.channelFor(0), uint8_t(1));
    QCOMPARE(document.channelFor(1), uint8_t(4));
    QCOMPARE(document.channelFor(2), uint8_t(7));
    QCOMPARE(document.smfTrackFor(0), 1);
    QCOMPARE(document.notesForTrack(0).front().key, uint8_t(60));
    QCOMPARE(document.notesForTrack(0).front().duration, uint32_t(24));
    QCOMPARE(document.notesForTrack(1).front().key, uint8_t(64));
    QCOMPARE(document.notesForTrack(2).front().key, uint8_t(67));
    QCOMPARE(document.trackName(1), QStringLiteral("Lead"));
    QVERIFY(document.trackName(0).isEmpty());
    QVERIFY(document.trackName(2).isEmpty());
    const auto &chunks = document.smf().tracks;
    QVERIFY(hasMeta(chunks[2], 0x04, QByteArrayLiteral("Gtr")));
    QVERIFY(hasMeta(chunks[0], 0x03, QByteArrayLiteral(":")));
    QVERIFY(!hasMeta(chunks[3], 0x03, QByteArrayLiteral(":")));
    QVERIFY(hasMeta(chunks[4], 0x03, QByteArrayLiteral("Ambient")));
    bool prefixedMarker = false;
    for (size_t index = 1; index < chunks[0].events.size(); ++index) {
        const SmfEvent &event = chunks[0].events[index];
        prefixedMarker |=
            event.isMeta() && event.metaType == 0x03 && event.blob == QByteArrayLiteral(":") &&
            chunks[0].events[index - 1].isMeta() && chunks[0].events[index - 1].metaType == 0x20;
    }
    QVERIFY(prefixedMarker);
    for (size_t index = 0; index < chunks.size(); ++index) {
        QCOMPARE(chunks[index].endTick, uint64_t(48));
        for (const SmfEvent &event : chunks[index].events)
            QVERIFY(index == 0 || !(event.isMeta() && event.metaType == 0x20));
    }
    for (const SmfEvent &event : chunks[0].events)
        QVERIFY(!event.isChannel());
}

void EditCheckTest::formatZeroGlobals()
{
    songdocument_test::SyntheticDocument fixture;
    QVERIFY2(fixture.stage(formatZeroFile(), QStringLiteral("format0-globals")),
             qPrintable(fixture.error));
    const SongDocument &document = fixture.document;
    QCOMPARE(document.loopTick(false), uint64_t(12));
    QCOMPARE(document.loopTick(true), uint64_t(36));
    QVERIFY((document.tempoPoints() == std::vector<TempoPoint>{songdocument_test::tempo(0, 120)}));
    const auto timeline = document.buildTimeline(48000.0);
    QVERIFY(timeline);
    QCOMPARE(timeline->usedTrackCount, 3);
    QCOMPARE(timeline->tracks[1].name, QStringLiteral("Lead"));
    QCOMPARE(timeline->loopStartTick, uint64_t(12));
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
}

void EditCheckTest::formatZeroSaveRoundTrip()
{
    const SmfFile source = formatZeroFile();
    const QByteArray original = source.write();
    songdocument_test::SyntheticDocument fixture;
    QVERIFY2(fixture.stage(source, QStringLiteral("format0-save")), qPrintable(fixture.error));
    SongDocument &document = fixture.document;
    const QByteArray convertedLive = document.smf().write();
    QString error;
    SmfFile saved;
    QVERIFY2(document.save(&error), qPrintable(error));
    QVERIFY2(SmfFile::readFile(fixture.song.midPath, &saved, &error), qPrintable(error));
    SmfFile expected = document.smf();
    const auto tempos = document.tempoPoints();
    QCOMPARE(tempos.size(), size_t(1));
    expected.tracks.front().events.insert(
        expected.tracks.front().events.begin(),
        tempoMeta(tempos.front().tick, tempos.front().microsecondsPerQuarterNote));
    QCOMPARE(saved.write(), expected.write());
    SmfFile nonTempoSaved = saved;
    for (SmfTrack &track : nonTempoSaved.tracks) {
        std::erase_if(track.events, [](const SmfEvent &event) { return isTempoMeta(event); });
    }
    QCOMPARE(nonTempoSaved.write(), convertedLive);
    bool tempoFirst = true;
    bool tempoOutsideConductor = false;
    std::vector<TempoPoint> savedTempos;
    for (size_t track = 0; track < saved.tracks.size(); ++track) {
        uint64_t tick = 0;
        bool haveTick = false;
        bool nonTempoAtTick = false;
        for (const SmfEvent &event : saved.tracks[track].events) {
            if (!haveTick || event.tick != tick) {
                tick = event.tick;
                haveTick = true;
                nonTempoAtTick = false;
            }
            if (!isTempoMeta(event)) {
                nonTempoAtTick = true;
                continue;
            }
            tempoOutsideConductor |= track != 0;
            tempoFirst &= !nonTempoAtTick;
            QVERIFY(event.blob.size() == 3);
            const auto *bytes = reinterpret_cast<const uint8_t *>(event.blob.constData());
            savedTempos.push_back(
                {event.tick, (uint32_t(bytes[0]) << 16) | (uint32_t(bytes[1]) << 8) | bytes[2]});
        }
    }
    QVERIFY(!tempoOutsideConductor);
    QVERIFY(tempoFirst);
    QVERIFY(savedTempos == tempos);
    QVERIFY(!songdocument_test::hasLiveTempo(document));
    SmfFile reloaded;
    QVERIFY2(SmfFile::read(original, &reloaded, &error), qPrintable(error));
    QVERIFY(reloaded.wasFormat0);
    QCOMPARE(reloaded.write(), saved.write());
    convertToFormat1(&reloaded);
    QCOMPARE(reloaded.write(), saved.write());
    document.renameTrack(0, QStringLiteral("Bass"));
    QVERIFY(document.moveTrack(0, 2));
    QCOMPARE(document.trackName(2), QStringLiteral("Bass"));
    while (document.undoStack()->canUndo())
        document.undoStack()->undo();
    QCOMPARE(document.smf().write(), convertedLive);
}

void EditCheckTest::markerVersusTrackName()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events = {songdocument_test::meta(0x20, 0, QByteArray(1, char(0))),
                    songdocument_test::meta(0x03, 0, QByteArrayLiteral("[")),
                    songdocument_test::channel(0x90, 0, 60, 100),
                    songdocument_test::meta(0x03, 0, QByteArrayLiteral("Real")),
                    songdocument_test::channel(0x80, 24, 60, 0)};
    track.endTick = 24;
    smf.tracks.push_back(track);
    auto fixture = songdocument_test::makeDocument(std::move(smf), QStringLiteral("marker"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    QCOMPARE(document.trackName(0), QStringLiteral("Real"));
    QCOMPARE(document.loopTick(false), uint64_t(0));
    const auto timeline = document.buildTimeline(48000.0);
    QVERIFY(timeline);
    QCOMPARE(timeline->loopStartTick, uint64_t(0));
    document.renameTrack(0, QStringLiteral("Renamed"));
    QCOMPARE(document.trackName(0), QStringLiteral("Renamed"));
    QCOMPARE(document.loopTick(false), uint64_t(0));
}

void EditCheckTest::duplicateLaneAndTempoLoad()
{
    auto fixture =
        songdocument_test::makeDocument(duplicateFile(), QStringLiteral("duplicates-load"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    const TempoPoint slow = songdocument_test::tempo(24, 20);
    const TempoPoint normal = songdocument_test::tempo(48, 150);
    const TempoPoint fast = songdocument_test::tempo(72, 255);
    const TempoPoint exact{96, 375'001};
    QCOMPARE(document.lanePoints(0, DOC_CC_VOICE).size(), size_t(2));
    QCOMPARE(pointsAt(document, 7, 0).size(), size_t(2));
    DocLanePoint point;
    QVERIFY(document.findLanePoint(0, 7, 0, &point));
    QCOMPARE(point.value, 80);
    QVERIFY(document.findLanePoint(0, DOC_CC_VOICE, 0, &point));
    QCOMPARE(point.value, 9);
    QVERIFY((document.tempoPoints() == std::vector<TempoPoint>{slow, normal, fast, exact}));
    QVERIFY(!songdocument_test::hasLiveTempo(document));
    const auto timeline = document.buildTimeline(48000.0);
    QVERIFY(timeline);
    QCOMPARE(timeline->tempoMap.size(), size_t(5));
    QCOMPARE(timeline->tempoMap.front().bpm, 120.0);
    const QByteArray liveBytes = document.smf().write();
    SmfFile expected = document.smf();
    auto &events = expected.tracks.front().events;
    events.insert(events.begin() + 1, {tempoMeta(slow.tick, slow.microsecondsPerQuarterNote),
                                       tempoMeta(normal.tick, normal.microsecondsPerQuarterNote)});
    events.insert(events.begin() + 4, {tempoMeta(fast.tick, fast.microsecondsPerQuarterNote),
                                       tempoMeta(exact.tick, exact.microsecondsPerQuarterNote)});
    QString error;
    QVERIFY2(document.save(&error), qPrintable(error));
    SmfFile saved;
    QVERIFY2(SmfFile::readFile(fixture->song.midPath, &saved, &error), qPrintable(error));
    QCOMPARE(saved.write(), expected.write());
    QCOMPARE(document.smf().write(), liveBytes);
    QVERIFY(!songdocument_test::hasLiveTempo(document));
}

void EditCheckTest::duplicateCanonicalization()
{
    auto fixture =
        songdocument_test::makeDocument(duplicateFile(), QStringLiteral("duplicates-canonical"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    const QByteArray baseline = document.smf().write();
    int changedCount = 0;
    QObject::connect(&document, &SongDocument::documentChanged,
                     [&changedCount] { ++changedCount; });
    DocLanePoint point;
    QVERIFY(document.findLanePoint(0, 7, 0, &point));
    const uint64_t revision = document.revision();
    const int undoCount = document.undoStack()->count();
    const int undoIndex = document.undoStack()->index();
    document.moveLanePoints({{0, 7, point, point.tick, point.value}});
    QCOMPARE(pointsAt(document, 7, 0).size(), size_t(1));
    QCOMPARE(document.revision(), revision + 1);
    QCOMPARE(document.undoStack()->count(), undoCount + 1);
    QCOMPARE(document.undoStack()->index(), undoIndex + 1);
    QCOMPARE(changedCount, 1);
    const uint64_t canonicalRevision = document.revision();
    changedCount = 0;
    document.undoStack()->undo();
    const auto restored = pointsAt(document, 7, 0);
    QCOMPARE(restored.size(), size_t(2));
    QCOMPARE(restored[0].value, 100);
    QCOMPARE(restored[1].value, 80);
    QCOMPARE(document.smf().write(), baseline);
    QCOMPARE(document.revision(), canonicalRevision + 1);
    QCOMPARE(document.undoStack()->count(), undoCount + 1);
    QCOMPARE(document.undoStack()->index(), undoIndex);
    QCOMPARE(changedCount, 1);
    document.addLanePoint(0, 7, 0, 70);
    QCOMPARE(pointsAt(document, 7, 0).size(), size_t(1));
}

void EditCheckTest::duplicateReplacementsAndNoOps()
{
    auto fixture =
        songdocument_test::makeDocument(duplicateFile(), QStringLiteral("duplicates-edits"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    const QByteArray baseline = document.smf().write();
    int changedCount = 0;
    QObject::connect(&document, &SongDocument::documentChanged,
                     [&changedCount] { ++changedCount; });
    document.addLanePoint(0, 7, 48, 55);
    DocLanePoint point;
    QVERIFY(document.findLanePoint(0, 7, 48, &point));
    QCOMPARE(pointsAt(document, 7, 48).size(), size_t(1));
    const QByteArray noOpBytes = document.smf().write();
    const uint64_t noOpRevision = document.revision();
    const int noOpUndoCount = document.undoStack()->count();
    const int noOpUndoIndex = document.undoStack()->index();
    changedCount = 0;
    document.moveLanePoints({{0, 7, point, point.tick, point.value}});
    QCOMPARE(document.smf().write(), noOpBytes);
    QCOMPARE(document.revision(), noOpRevision);
    QCOMPARE(document.undoStack()->count(), noOpUndoCount);
    QCOMPARE(document.undoStack()->index(), noOpUndoIndex);
    QCOMPARE(changedCount, 0);
    document.moveLanePoints({{0, 7, point, 0, 55}});
    QCOMPARE(pointsAt(document, 7, 0).size(), size_t(1));
    QVERIFY(pointsAt(document, 7, 48).empty());
    const TempoPoint noOpTempo = songdocument_test::tempo(48, 120);
    document.applyTempoEdit({{}, {noOpTempo}});
    QVERIFY(songdocument_test::containsTempo(document, noOpTempo));
    QVERIFY(!songdocument_test::hasLiveTempo(document));
    const QByteArray tempoBytes = document.smf().write();
    const auto tempoPoints = document.tempoPoints();
    const uint64_t tempoRevision = document.revision();
    const int tempoUndoCount = document.undoStack()->count();
    const int tempoUndoIndex = document.undoStack()->index();
    changedCount = 0;
    document.applyTempoEdit({{}, {noOpTempo}});
    QCOMPARE(document.smf().write(), tempoBytes);
    QVERIFY(document.tempoPoints() == tempoPoints);
    QCOMPARE(document.revision(), tempoRevision);
    QCOMPARE(document.undoStack()->count(), tempoUndoCount);
    QCOMPARE(document.undoStack()->index(), tempoUndoIndex);
    QCOMPARE(changedCount, 0);
    QVERIFY(!songdocument_test::hasLiveTempo(document));
    document.undoStack()->undo();
    QVERIFY(songdocument_test::containsTempo(document, songdocument_test::tempo(48, 150)));
    QVERIFY(!songdocument_test::hasLiveTempo(document));
    document.undoStack()->redo();
    while (document.undoStack()->canUndo())
        document.undoStack()->undo();
    QCOMPARE(document.smf().write(), baseline);
}
