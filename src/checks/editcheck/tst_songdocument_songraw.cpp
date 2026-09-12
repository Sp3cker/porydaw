#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include <algorithm>

#include "checks/editcheck/tst_songdocument_support.h"

namespace {

// The chunk raw-event contracts run against: engine track 0's chunk if
// the song owns one, else the first non-empty chunk.
int rawChunk(const SongDocument &document)
{
    const int mapped = document.smfTrackFor(0);
    if (mapped >= 0)
        return mapped;
    for (size_t index = 0; index < document.smf().tracks.size(); ++index) {
        if (!document.smf().tracks[index].events.empty())
            return int(index);
    }
    return document.smf().tracks.empty() ? -1 : 0;
}

long long eventIndex(const SmfTrack &track, const SmfEvent &event)
{
    const auto found = std::find(track.events.begin(), track.events.end(), event);
    return found == track.events.end() ? -1 : found - track.events.begin();
}

size_t eventCount(const SmfTrack &track, const SmfEvent &event)
{
    return std::count(track.events.begin(), track.events.end(), event);
}

} // namespace

void EditCheckTest::rawEventMutate_data()
{
    addSongRows(SongCapability::Playable);
}

void EditCheckTest::rawEventMutate()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no playable song for raw-event mutation");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int chunk = rawChunk(document);
    QVERIFY2(chunk >= 0, "loaded song has no SMF chunk");
    const QByteArray baseline = document.smf().write();
    QUndoStack *const undo = document.undoStack();
    const int entryIndex = undo->index();

    SmfTrack &track = const_cast<SmfTrack &>(document.smf().tracks[size_t(chunk)]);
    uint8_t channel = 0;
    for (const SmfEvent &candidate : track.events) {
        if (candidate.isChannel()) {
            channel = candidate.channel();
            break;
        }
    }
    const uint64_t base = songdocument_test::distantBase(document) + 100;
    const size_t before = track.events.size();
    SmfEvent event = songdocument_test::channel(uint8_t(0xB0 | channel), base, 7, 64);
    document.insertRawEvent(chunk, event);
    QCOMPARE(track.events.size(), before + 1);
    QCOMPARE(eventCount(track, event), size_t(1));
    QCOMPARE(track.endTick, base);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));

    const long long sameTickIndex = eventIndex(track, event);
    QVERIFY(sameTickIndex >= 0);
    event.data1 = 99;
    document.modifyRawEvent(chunk, size_t(sameTickIndex), event);
    QCOMPARE(eventIndex(track, event), sameTickIndex);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));

    const long long movingIndex = eventIndex(track, event);
    QVERIFY(movingIndex >= 0);
    event.tick = 0;
    const size_t countBeforeMove = eventCount(track, event);
    document.modifyRawEvent(chunk, size_t(movingIndex), event);
    QCOMPARE(eventCount(track, event), countBeforeMove + 1);
    QCOMPARE(track.events.size(), before + 1);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));

    const long long deleteIndex = eventIndex(track, event);
    QVERIFY(deleteIndex >= 0);
    document.deleteRawEvents(chunk, {size_t(deleteIndex)});
    QCOMPARE(track.events.size(), before);

    document.setTrackEndTick(chunk, base + 500);
    QCOMPARE(track.endTick, base + 500);
    const Tick lastTick = track.events.empty() ? Tick(0) : track.events.back().tick;
    document.setTrackEndTick(chunk, 0);
    QCOMPARE(track.endTick, lastTick);

    while (undo->index() > entryIndex)
        undo->undo();
    QCOMPARE(document.smf().write(), baseline);
}

void EditCheckTest::rawEventReorder_data()
{
    addSongRows(SongCapability::Playable);
}

void EditCheckTest::rawEventReorder()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no playable song for raw-event reordering");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int chunk = rawChunk(document);
    QVERIFY2(chunk >= 0, "loaded song has no SMF chunk");
    const QByteArray baseline = document.smf().write();
    QUndoStack *const undo = document.undoStack();
    const int entryIndex = undo->index();

    SmfTrack &track = const_cast<SmfTrack &>(document.smf().tracks[size_t(chunk)]);
    uint8_t channel = 0;
    for (const SmfEvent &candidate : track.events) {
        if (candidate.isChannel()) {
            channel = candidate.channel();
            break;
        }
    }
    const uint64_t group = songdocument_test::distantBase(document) + 1100;
    const SmfEvent first = songdocument_test::channel(uint8_t(0xB0 | channel), group, 7, 1);
    const SmfEvent second = songdocument_test::channel(uint8_t(0xB0 | channel), group, 10, 2);
    const SmfEvent noteOn = songdocument_test::channel(uint8_t(0x90 | channel), group, 60, 100);
    document.insertRawEvent(chunk, first);
    document.insertRawEvent(chunk, second);
    document.insertRawEvent(chunk, noteOn);
    const long long firstIndex = eventIndex(track, first);
    const long long secondIndex = eventIndex(track, second);
    const long long noteIndex = eventIndex(track, noteOn);
    QVERIFY(firstIndex >= 0);
    QCOMPARE(secondIndex, firstIndex + 1);
    QCOMPARE(noteIndex, firstIndex + 2);

    size_t lower = 0;
    size_t upper = 0;
    QVERIFY(document.rawEventMoveBounds(chunk, size_t(firstIndex), &lower, &upper));
    QCOMPARE(lower, size_t(firstIndex));
    QCOMPARE(upper, size_t(secondIndex));
    QVERIFY(document.rawEventMoveBounds(chunk, size_t(noteIndex), &lower, &upper));
    QCOMPARE(lower, size_t(noteIndex));
    QCOMPARE(upper, size_t(noteIndex));

    document.moveRawEvent(chunk, size_t(firstIndex), size_t(secondIndex));
    QCOMPARE(eventIndex(track, second), firstIndex);
    QCOMPARE(eventIndex(track, first), secondIndex);
    QVERIFY(songdocument_test::tracksSorted(document.smf()));
    const int undoCount = undo->count();
    document.moveRawEvent(chunk, size_t(secondIndex), size_t(noteIndex));
    document.moveRawEvent(chunk, size_t(firstIndex), 0);
    QCOMPARE(undo->count(), undoCount);
    QCOMPARE(eventIndex(track, first), secondIndex);
    QCOMPARE(eventIndex(track, second), firstIndex);

    undo->undo();
    QCOMPARE(eventIndex(track, first), firstIndex);
    QCOMPARE(eventIndex(track, second), secondIndex);
    undo->redo();
    QCOMPARE(eventIndex(track, first), secondIndex);
    QCOMPARE(eventIndex(track, second), firstIndex);
    const QByteArray edited = document.smf().write();
    while (undo->index() > entryIndex)
        undo->undo();
    QCOMPARE(document.smf().write(), baseline);
    while (undo->canRedo())
        undo->redo();
    QCOMPARE(document.smf().write(), edited);
}
