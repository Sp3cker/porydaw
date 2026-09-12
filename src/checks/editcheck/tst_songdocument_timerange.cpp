#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include <array>

#include "checks/editcheck/tst_songdocument_support.h"
#include "core/miditimeline.h"

namespace {

SmfFile timeRangeFile()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back({{}, 200});
    smf.tracks.push_back({{songdocument_test::channel(0xC0, 0, 1, 0)}, 200});
    smf.tracks.push_back({{songdocument_test::channel(0xC1, 0, 2, 0)}, 200});
    return smf;
}

SongDocument::TimeScope trackZero()
{
    SongDocument::TimeScope scope;
    scope.tracks = {0};
    return scope;
}

} // namespace

void EditCheckTest::timeRangeNoOps()
{
    auto fixture = songdocument_test::makeDocument(timeRangeFile(), QStringLiteral("time-noops"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    const QByteArray bytes = document.smf().write();
    const auto tempos = document.tempoPoints();
    const int undoCount = document.undoStack()->count();
    SongDocument::TimeScope empty;
    QVERIFY(!document.removeTimeRange({20, 20}, empty));
    QVERIFY(!document.insertBlankTime({20, 10}, empty));
    QVERIFY(!document.duplicateTimeRange({20, 10}, empty));
    SongDocument::TimeScope invalid;
    invalid.tracks = {99};
    QVERIFY(!document.removeTimeRange({20, 30}, invalid));
    QVERIFY(!document.insertBlankTime({20, 30}, invalid));
    QVERIFY(!document.duplicateTimeRange({20, 30}, invalid));
    QCOMPARE(document.smf().write(), bytes);
    QVERIFY(document.tempoPoints() == tempos);
    QCOMPARE(document.undoStack()->count(), undoCount);
}

void EditCheckTest::timeRangeInsertScopeAndSplit()
{
    auto fixture = songdocument_test::makeDocument(timeRangeFile(), QStringLiteral("time-insert"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    const SongDocument::TimeScope trackScope = trackZero();
    document.addNote(0, 35, 60, 10, 90);
    document.addNote(0, 60, 61, 5, 80);
    DocNote later;
    QVERIFY(document.findNote(0, 60, 61, &later));
    const NoteId laterId = later.noteId;
    const QByteArray before = document.smf().write();
    const int undoCount = document.undoStack()->count();
    QVERIFY(document.insertBlankTime({40, 45}, trackScope));
    DocNote left;
    DocNote right;
    QVERIFY(document.findNote(0, 35, 60, &left));
    QCOMPARE(left.duration, uint32_t(5));
    QVERIFY(document.findNote(0, 45, 60, &right));
    QCOMPARE(right.duration, uint32_t(5));
    QVERIFY(document.findNote(0, 65, 61, &later));
    QCOMPARE(later.noteId, laterId);
    QCOMPARE(document.undoStack()->count(), undoCount + 1);
    const QByteArray after = document.smf().write();
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), before);
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), after);

    auto laneFixture =
        songdocument_test::makeDocument(timeRangeFile(), QStringLiteral("time-lanes"));
    QVERIFY(laneFixture);
    SongDocument &lane = laneFixture->document;
    lane.addLanePoint(0, 7, 300, 10);
    lane.addLanePoint(0, 10, 300, 20);
    lane.addLanePoint(1, 7, 300, 30);
    SongDocument::TimeScope laneScope;
    laneScope.lanes = {{0, 7}};
    const uint64_t selectedEnd = lane.smf().tracks[1].endTick;
    const uint64_t untouchedEnd = lane.smf().tracks[2].endTick;
    const QByteArray laneBefore = lane.smf().write();
    QVERIFY(lane.insertBlankTime({300, 320}, laneScope));
    DocLanePoint point;
    QVERIFY(lane.findLanePoint(0, 7, 320, &point));
    QCOMPARE(point.value, 10);
    QVERIFY(lane.findLanePoint(0, 10, 300, &point));
    QCOMPARE(point.value, 20);
    QVERIFY(lane.findLanePoint(1, 7, 300, &point));
    QCOMPARE(point.value, 30);
    QCOMPARE(lane.smf().tracks[1].endTick, selectedEnd + 20);
    QCOMPARE(lane.smf().tracks[2].endTick, untouchedEnd);
    const QByteArray laneAfter = lane.smf().write();
    lane.undoStack()->undo();
    QCOMPARE(lane.smf().write(), laneBefore);
    lane.undoStack()->redo();
    QCOMPARE(lane.smf().write(), laneAfter);

    auto trackFixture =
        songdocument_test::makeDocument(timeRangeFile(), QStringLiteral("time-track-scope"));
    QVERIFY(trackFixture);
    SongDocument &track = trackFixture->document;
    track.addNote(0, 400, 62, 5, 90);
    track.addNote(1, 400, 63, 5, 90);
    track.addLanePoint(0, 7, 400, 40);
    track.addLanePoint(1, 7, 400, 50);
    const uint64_t trackEnd = track.smf().tracks[1].endTick;
    const uint64_t otherEnd = track.smf().tracks[2].endTick;
    const QByteArray trackBefore = track.smf().write();
    QVERIFY(track.insertBlankTime({400, 420}, trackScope));
    DocNote shifted;
    DocNote untouched;
    QVERIFY(track.findNote(0, 420, 62, &shifted));
    QVERIFY(track.findNote(1, 400, 63, &untouched));
    QCOMPARE(track.smf().tracks[1].endTick, trackEnd + 20);
    QCOMPARE(track.smf().tracks[2].endTick, otherEnd);
    const QByteArray trackAfter = track.smf().write();
    track.undoStack()->undo();
    QCOMPARE(track.smf().write(), trackBefore);
    track.undoStack()->redo();
    QCOMPARE(track.smf().write(), trackAfter);
}

void EditCheckTest::timeRangeUnterminated()
{
    auto fixture =
        songdocument_test::makeDocument(timeRangeFile(), QStringLiteral("time-unterminated"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    const SongDocument::TimeScope scope = trackZero();
    const int smfTrack = document.smfTrackFor(0);
    QVERIFY(smfTrack >= 0);
    document.insertRawEvent(smfTrack, songdocument_test::channel(0x90, 220, 68, 77));
    DocNote unterminated;
    QVERIFY(document.findNote(0, 220, 68, &unterminated));
    QVERIFY(unterminated.unterminated());
    const NoteId leftId = unterminated.noteId;
    const QByteArray before = document.smf().write();
    QVERIFY(document.insertBlankTime({240, 250}, scope));
    DocNote left;
    DocNote right;
    QVERIFY(document.findNote(0, 220, 68, &left));
    QVERIFY(!left.unterminated());
    QCOMPARE(left.duration, uint32_t(20));
    QCOMPARE(left.noteId, leftId);
    QVERIFY(document.findNote(0, 250, 68, &right));
    QVERIFY(right.unterminated());
    QVERIFY(right.noteId != left.noteId);
    bool sourceOn = false;
    bool generatedOff = false;
    bool resumedOn = false;
    for (const SmfEvent &event : document.smf().tracks[size_t(smfTrack)].events) {
        sourceOn |=
            event.tick == 220 && event.status == 0x90 && event.data0 == 68 && event.data1 == 77;
        generatedOff |=
            event.tick == 240 && event.status == 0x80 && event.data0 == 68 && event.data1 == 0;
        resumedOn |=
            event.tick == 250 && event.status == 0x90 && event.data0 == 68 && event.data1 == 77;
    }
    QVERIFY(sourceOn);
    QVERIFY(generatedOff);
    QVERIFY(resumedOn);
    const QByteArray after = document.smf().write();
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), before);
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), after);
}

void EditCheckTest::timeRangeDuplicateClippingAndOrder()
{
    auto fixture =
        songdocument_test::makeDocument(timeRangeFile(), QStringLiteral("time-clipping"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    const SongDocument::TimeScope scope = trackZero();
    constexpr Tick start = 600;
    document.addNote(0, start + 10, 64, 10, 90);
    document.addNote(0, start - 5, 65, 15, 80);
    document.addNote(0, start + 10, 66, 20, 70);
    document.addNote(0, start - 5, 67, 30, 60);
    DocNote contained;
    DocNote leftCross;
    DocNote rightCross;
    DocNote bothCross;
    QVERIFY(document.findNote(0, start + 10, 64, &contained));
    QVERIFY(document.findNote(0, start - 5, 65, &leftCross));
    QVERIFY(document.findNote(0, start + 10, 66, &rightCross));
    QVERIFY(document.findNote(0, start - 5, 67, &bothCross));
    const std::array<NoteId, 4> original = {contained.noteId, leftCross.noteId, rightCross.noteId,
                                            bothCross.noteId};
    const QByteArray before = document.smf().write();
    QVERIFY(document.duplicateTimeRange({start, start + 20}, scope));
    DocNote copiedContained;
    DocNote copiedLeft;
    DocNote copiedRight;
    DocNote copiedBoth;
    QVERIFY(document.findNote(0, start + 30, 64, &copiedContained));
    QCOMPARE(copiedContained.duration, uint32_t(10));
    QVERIFY(document.findNote(0, start + 20, 65, &copiedLeft));
    QCOMPARE(copiedLeft.duration, uint32_t(10));
    QVERIFY(document.findNote(0, start + 30, 66, &copiedRight));
    QCOMPARE(copiedRight.duration, uint32_t(10));
    QVERIFY(document.findNote(0, start + 20, 67, &copiedBoth));
    QCOMPARE(copiedBoth.duration, uint32_t(20));
    const std::array<NoteId, 4> copies = {copiedContained.noteId, copiedLeft.noteId,
                                          copiedRight.noteId, copiedBoth.noteId};
    for (size_t i = 0; i < copies.size(); ++i) {
        for (const NoteId id : original)
            QVERIFY(copies[i] != id);
        for (size_t j = i + 1; j < copies.size(); ++j)
            QVERIFY(copies[i] != copies[j]);
    }
    const QByteArray after = document.smf().write();
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), before);
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), after);
    const int smfTrack = document.smfTrackFor(0);
    document.insertRawEvent(smfTrack, songdocument_test::channel(0x80, 700, 72, 0));
    document.insertRawEvent(smfTrack, songdocument_test::channel(0x90, 700, 72, 55));
    QVERIFY(document.duplicateTimeRange({700, 720}, scope));
    QVERIFY(songdocument_test::noteEndsBeforeOnsAt(document, 0, 720));
    document.insertRawEvent(smfTrack, songdocument_test::channel(0x80, 800, 73, 0));
    document.insertRawEvent(smfTrack, songdocument_test::channel(0x90, 800, 73, 66));
    QVERIFY(document.insertBlankTime({800, 820}, scope));
    QVERIFY(songdocument_test::noteEndsBeforeOnsAt(document, 0, 820));
}

void EditCheckTest::timeRangeSignatureAndOrphans()
{
    auto fixture =
        songdocument_test::makeDocument(timeRangeFile(), QStringLiteral("time-signature"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    constexpr Tick seam = 960;
    const Tick bar = 3 * Tick(document.smf().division);
    document.setTimeSig(0, 4, 2);
    document.setTimeSig(seam, 3, 2);
    SongDocument::TimeScope whole;
    whole.wholeSong = true;
    const QByteArray before = document.smf().write();
    QVERIFY(document.insertBlankTime({seam, seam + bar}, whole));
    bool start = false;
    bool end = false;
    for (const DocTimeSig &signature : document.timeSigs())
        if (signature.numerator == 3 && signature.denomPow2 == 2) {
            start |= signature.tick == seam;
            end |= signature.tick == seam + bar;
        }
    QVERIFY(start);
    QVERIFY(end);
    const QByteArray after = document.smf().write();
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), before);
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), after);
    auto orphanFixture =
        songdocument_test::makeDocument(timeRangeFile(), QStringLiteral("time-orphans"));
    QVERIFY(orphanFixture);
    SongDocument &orphan = orphanFixture->document;
    const int smfTrack = orphan.smfTrackFor(0);
    const SongDocument::TimeScope scope = trackZero();
    orphan.addNote(0, 40, 60, 10, 90);
    orphan.insertRawEvent(smfTrack, songdocument_test::channel(0x90, 90, 61, 11));
    orphan.insertRawEvent(smfTrack, songdocument_test::channel(0x80, 120, 66, 13));
    orphan.insertRawEvent(smfTrack, songdocument_test::channel(0x90, 110, 62, 22));
    orphan.insertRawEvent(smfTrack, songdocument_test::channel(0x80, 130, 63, 12));
    orphan.insertRawEvent(smfTrack, songdocument_test::channel(0x90, 130, 64, 33));
    orphan.insertRawEvent(smfTrack, songdocument_test::channel(0x90, 140, 65, 44));
    const QByteArray orphanBefore = orphan.smf().write();
    QVERIFY(orphan.removeTimeRange({100, 130}, scope));
    bool beforeOn = false;
    bool removedOn = false;
    bool removedOff = false;
    bool pinnedOff = false;
    bool endOn = false;
    bool shiftedOn = false;
    for (const SmfEvent &event : orphan.smf().tracks[size_t(smfTrack)].events) {
        beforeOn |=
            event.tick == 90 && event.status == 0x90 && event.data0 == 61 && event.data1 == 11;
        removedOn |=
            event.tick == 110 && event.status == 0x90 && event.data0 == 62 && event.data1 == 22;
        removedOff |= event.status == 0x80 && event.data0 == 66 && event.data1 == 13;
        pinnedOff |=
            event.tick == 100 && event.status == 0x80 && event.data0 == 63 && event.data1 == 12;
        endOn |=
            event.tick == 100 && event.status == 0x90 && event.data0 == 64 && event.data1 == 33;
        shiftedOn |=
            event.tick == 110 && event.status == 0x90 && event.data0 == 65 && event.data1 == 44;
    }
    DocNote paired;
    QVERIFY(beforeOn);
    QVERIFY(!removedOn);
    QVERIFY(!removedOff);
    QVERIFY(pinnedOff);
    QVERIFY(endOn);
    QVERIFY(shiftedOn);
    QVERIFY(songdocument_test::noteEndsBeforeOnsAt(orphan, 0, 100));
    QVERIFY(orphan.findNote(0, 40, 60, &paired));
    QVERIFY(!paired.unterminated());
    QCOMPARE(paired.duration, uint32_t(10));
    const QByteArray orphanAfter = orphan.smf().write();
    orphan.undoStack()->undo();
    QCOMPARE(orphan.smf().write(), orphanBefore);
    orphan.undoStack()->redo();
    QCOMPARE(orphan.smf().write(), orphanAfter);
}

void EditCheckTest::timeRangeAutomationSeamsAndDefaults()
{
    auto fixture =
        songdocument_test::makeDocument(timeRangeFile(), QStringLiteral("time-automation"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    constexpr Tick seam = 1000;
    SongDocument::TimeScope laneScope;
    laneScope.lanes = {{0, 7}};
    document.addLanePoint(0, 7, seam - 20, 33);
    document.addLanePoint(0, 7, seam + 10, 44);
    const QByteArray seamBefore = document.smf().write();
    const int seamUndoCount = document.undoStack()->count();
    QVERIFY(document.duplicateTimeRange({seam, seam + 40}, laneScope));
    DocLanePoint point;
    QVERIFY(document.findLanePoint(0, 7, seam + 40, &point));
    QCOMPARE(point.value, 33);
    QVERIFY(document.findLanePoint(0, 7, seam + 50, &point));
    QCOMPARE(point.value, 44);
    QCOMPARE(document.undoStack()->count(), seamUndoCount + 1);
    const QByteArray seamAfter = document.smf().write();
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), seamBefore);
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), seamAfter);

    auto defaultsFixture =
        songdocument_test::makeDocument(timeRangeFile(), QStringLiteral("time-defaults"));
    QVERIFY(defaultsFixture);
    SongDocument &defaultsDocument = defaultsFixture->document;
    struct DefaultCase {
        uint8_t cc;
        int source;
        int expected;
    };
    constexpr std::array<DefaultCase, 9> defaults = {DefaultCase{0x01, 11, 0},
                                                     {0x05, 12, 0},
                                                     {0x07, 80, 127},
                                                     {0x0A, 81, 64},
                                                     {0x14, 3, 2},
                                                     {0x15, 4, 22},
                                                     {0x17, 5, 0},
                                                     {0x19, 6, 0},
                                                     {DOC_CC_BEND, 500, 0}};
    for (size_t remaining = defaults.size(); remaining > 0; --remaining) {
        const size_t index = remaining - 1;
        const Tick start = 1100 + index * 40U;
        defaultsDocument.addLanePoint(0, defaults[index].cc, start + 10, defaults[index].source);
        const QByteArray before = defaultsDocument.smf().write();
        const int undoCount = defaultsDocument.undoStack()->count();
        SongDocument::TimeScope lane;
        lane.lanes = {{0, defaults[index].cc}};
        QVERIFY(defaultsDocument.duplicateTimeRange({start, start + 20}, lane));
        QVERIFY(defaultsDocument.findLanePoint(0, defaults[index].cc, start + 20, &point));
        QCOMPARE(point.value, defaults[index].expected);
        QCOMPARE(defaultsDocument.undoStack()->count(), undoCount + 1);
        const QByteArray after = defaultsDocument.smf().write();
        defaultsDocument.undoStack()->undo();
        QCOMPARE(defaultsDocument.smf().write(), before);
        defaultsDocument.undoStack()->redo();
        QCOMPARE(defaultsDocument.smf().write(), after);
    }
    SongDocument::TimeScope tempoScope;
    tempoScope.tempo = true;
    defaultsDocument.applyTempoEdit(
        {{songdocument_test::tempo(0, 120)}, {songdocument_test::tempo(1510, 150)}});
    const QByteArray tempoBytesBefore = defaultsDocument.smf().write();
    const auto temposBefore = defaultsDocument.tempoPoints();
    const int tempoUndoCount = defaultsDocument.undoStack()->count();
    QVERIFY(defaultsDocument.duplicateTimeRange({1500, 1520}, tempoScope));
    QVERIFY(
        songdocument_test::containsTempo(defaultsDocument, songdocument_test::tempo(1520, 120)));
    QVERIFY(
        songdocument_test::containsTempo(defaultsDocument, songdocument_test::tempo(1530, 150)));
    const auto timeline = defaultsDocument.buildTimeline(44100.0);
    QVERIFY(timeline);
    QVERIFY(!timeline->tempoMap.empty());
    QCOMPARE(timeline->tempoMap.front().bpm, 120.0);
    QCOMPARE(defaultsDocument.undoStack()->count(), tempoUndoCount + 1);
    const QByteArray tempoBytesAfter = defaultsDocument.smf().write();
    const auto temposAfter = defaultsDocument.tempoPoints();
    defaultsDocument.undoStack()->undo();
    QCOMPARE(defaultsDocument.smf().write(), tempoBytesBefore);
    QVERIFY(defaultsDocument.tempoPoints() == temposBefore);
    defaultsDocument.undoStack()->redo();
    QCOMPARE(defaultsDocument.smf().write(), tempoBytesAfter);
    QVERIFY(defaultsDocument.tempoPoints() == temposAfter);
    defaultsDocument.addLanePoint(0, DOC_CC_VOICE, 1610, 12);
    const QByteArray voiceBefore = defaultsDocument.smf().write();
    const int voiceUndoCount = defaultsDocument.undoStack()->count();
    SongDocument::TimeScope voiceScope;
    voiceScope.lanes = {{0, DOC_CC_VOICE}};
    QVERIFY(defaultsDocument.duplicateTimeRange({1600, 1620}, voiceScope));
    QVERIFY(defaultsDocument.findLanePoint(0, DOC_CC_VOICE, 1620, &point));
    QCOMPARE(point.value, 1);
    QVERIFY(defaultsDocument.findLanePoint(0, DOC_CC_VOICE, 1630, &point));
    QCOMPARE(point.value, 12);
    QCOMPARE(defaultsDocument.undoStack()->count(), voiceUndoCount + 1);
    const QByteArray voiceAfter = defaultsDocument.smf().write();
    defaultsDocument.undoStack()->undo();
    QCOMPARE(defaultsDocument.smf().write(), voiceBefore);
    defaultsDocument.undoStack()->redo();
    QCOMPARE(defaultsDocument.smf().write(), voiceAfter);
    constexpr uint64_t downstream = 1700;
    defaultsDocument.addLanePoint(0, 7, downstream, 11);
    defaultsDocument.addLanePoint(0, 7, downstream + 20, 99);
    const QByteArray downstreamBefore = defaultsDocument.smf().write();
    const int downstreamUndoCount = defaultsDocument.undoStack()->count();
    QVERIFY(defaultsDocument.duplicateTimeRange({downstream, downstream + 20}, laneScope));
    QVERIFY(defaultsDocument.findLanePoint(0, 7, downstream + 20, &point));
    QCOMPARE(point.value, 11);
    QVERIFY(defaultsDocument.findLanePoint(0, 7, downstream + 40, &point));
    QCOMPARE(point.value, 99);
    QCOMPARE(defaultsDocument.undoStack()->count(), downstreamUndoCount + 1);
    const QByteArray downstreamAfter = defaultsDocument.smf().write();
    defaultsDocument.undoStack()->undo();
    QCOMPARE(defaultsDocument.smf().write(), downstreamBefore);
    defaultsDocument.undoStack()->redo();
    QCOMPARE(defaultsDocument.smf().write(), downstreamAfter);
}

void EditCheckTest::timeRangeWholeSong()
{
    auto fixture =
        songdocument_test::makeDocument(timeRangeFile(), QStringLiteral("time-whole-song"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    constexpr Tick start = 1800;
    document.addNote(0, 1900, 70, 5, 50);
    document.setTimeSig(start + 10, 3, 2);
    document.applyTempoEdit({{}, {songdocument_test::tempo(start + 10, 180)}});
    document.insertRawEvent(0,
                            songdocument_test::meta(0x01, start + 15, QByteArrayLiteral("global")));
    SongDocument::TimeScope wholeSong;
    wholeSong.wholeSong = true;
    const QByteArray before = document.smf().write();
    QVERIFY(document.duplicateTimeRange({start, start + 20}, wholeSong));
    bool copiedMeta = false;
    bool copiedSignature = false;
    for (const SmfEvent &event : document.smf().tracks.front().events)
        copiedMeta |= event.tick == start + 35 && event.isMeta() && event.metaType == 0x01 &&
                      event.blob == QByteArrayLiteral("global");
    for (const DocTimeSig &signature : document.timeSigs())
        copiedSignature |= signature.tick == start + 30 && signature.numerator == 3;
    DocNote shifted;
    QVERIFY(copiedMeta);
    QVERIFY(copiedSignature);
    QVERIFY(songdocument_test::containsTempo(document, songdocument_test::tempo(start + 20, 120)));
    QVERIFY(songdocument_test::containsTempo(document, songdocument_test::tempo(start + 30, 180)));
    QVERIFY(document.findNote(0, 1920, 70, &shifted));
    const int smfTrack = document.smfTrackFor(0);
    QVERIFY(smfTrack >= 0);
    QVERIFY(document.smf().tracks[size_t(smfTrack)].endTick >= shifted.tick + shifted.duration);
    const QByteArray after = document.smf().write();
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), before);
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), after);
}

void EditCheckTest::timeRangeInsertBlankOverflow()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back(SmfTrack{{}, 48});
    smf.tracks.push_back(SmfTrack{{songdocument_test::channel(0xC0, 0, 1, 0)}, 48});
    auto fixture =
        songdocument_test::makeDocument(std::move(smf), QStringLiteral("time-blank-overflow"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    const int smfTrack = document.smfTrackFor(0);
    QVERIFY(smfTrack >= 0);
    // SMF VLQ is 28-bit, so kMaxTick cannot round-trip as EOT through makeDocument.
    document.insertRawEvent(smfTrack,
                            songdocument_test::channel(0xB0, CoreTimeDefaults::kMaxTick, 7, 0));
    const QByteArray bytes = document.smf().write();
    const int undoCount = document.undoStack()->count();
    QVERIFY(!document.insertBlankTime({0, 1}, trackZero()));
    QCOMPARE(document.smf().write(), bytes);
    QCOMPARE(document.undoStack()->count(), undoCount);
}
