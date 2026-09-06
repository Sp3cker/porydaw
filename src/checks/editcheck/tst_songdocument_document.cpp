#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include <cstddef>
#include <vector>

#include "checks/editcheck/tst_songdocument_support.h"
#include "core/miditimeline.h"
#include "core/tracklimits.h"

namespace {

SmfFile twoTrackFile()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back(songdocument_test::conductor());
    SmfTrack first;
    first.events = {
        songdocument_test::channel(0xC0, 0, 1, 0), songdocument_test::channel(0x90, 0, 60, 100),
        songdocument_test::channel(0x90, 0, 60, 90), songdocument_test::channel(0x80, 12, 60, 0),
        songdocument_test::channel(0x80, 24, 60, 0)};
    first.endTick = 48;
    smf.tracks.push_back(first);
    smf.tracks.push_back({{songdocument_test::channel(0xC1, 0, 2, 0)}, 48});
    return smf;
}

} // namespace

void EditCheckTest::documentLoadPublication()
{
    songdocument_test::SyntheticDocument fixture;
    std::vector<QString> order;
    std::vector<TrackRemap> remaps;
    std::vector<uint64_t> revisions;
    QObject::connect(&fixture.document, &SongDocument::tracksRemapped,
                     [&fixture, &order, &remaps, &revisions](TrackRemap remap) {
                         order.push_back(QStringLiteral("remap"));
                         remaps.push_back(std::move(remap));
                         revisions.push_back(fixture.document.revision());
                     });
    QObject::connect(&fixture.document, &SongDocument::documentChanged,
                     [&fixture, &order, &revisions] {
                         order.push_back(QStringLiteral("changed"));
                         revisions.push_back(fixture.document.revision());
                     });
    QVERIFY2(fixture.stage(twoTrackFile(), QStringLiteral("publication")),
             qPrintable(fixture.error));
    QCOMPARE(fixture.document.revision(), uint64_t(1));
    QVERIFY((order == std::vector<QString>{QStringLiteral("remap"), QStringLiteral("changed")}));
    QVERIFY((revisions == std::vector<uint64_t>{1, 1}));
    QCOMPARE(remaps.size(), size_t(1));
    QVERIFY(remaps.front().smfTrackMap.empty());
    QVERIFY(remaps.front().engineTrackMap.empty());
    QCOMPARE(remaps.front().newSmfTrackCount, 3);
    QCOMPARE(remaps.front().newEngineTrackCount, 2);
}

void EditCheckTest::documentTempoEmpty()
{
    songdocument_test::SyntheticDocument fixture;
    QVERIFY2(fixture.stage(twoTrackFile(), QStringLiteral("tempo-empty")),
             qPrintable(fixture.error));
    SongDocument &document = fixture.document;
    QVERIFY(document.tempoPoints().empty());
    const auto timeline = document.buildTimeline(48000.0);
    QVERIFY(timeline);
    QCOMPARE(timeline->tempoMap.size(), size_t(1));
    QCOMPARE(timeline->tempoMap.front().tick, uint64_t(0));
    QCOMPARE(timeline->tempoMap.front().bpm, 120.0);
    const TempoPoint point = songdocument_test::tempo(24, 150);
    document.applyTempoEdit({{}, {point}});
    document.applyTempoEdit({{point}, {}});
    QVERIFY(document.tempoPoints().empty());
    document.undoStack()->undo();
    QVERIFY((document.tempoPoints() == std::vector<TempoPoint>{point}));
    document.undoStack()->redo();
    QVERIFY(document.tempoPoints().empty());
    QString error;
    SmfFile saved;
    QVERIFY2(document.save(&error), qPrintable(error));
    QVERIFY2(SmfFile::readFile(fixture.song.midPath, &saved, &error), qPrintable(error));
    for (const SmfTrack &track : saved.tracks)
        for (const SmfEvent &event : track.events)
            QVERIFY(!isTempoMeta(event));
}

void EditCheckTest::documentVelocityAtomic()
{
    songdocument_test::SyntheticDocument fixture;
    std::vector<QString> order;
    std::vector<TrackRemap> remaps;
    QObject::connect(&fixture.document, &SongDocument::tracksRemapped,
                     [&order, &remaps](TrackRemap remap) {
                         order.push_back(QStringLiteral("remap"));
                         remaps.push_back(std::move(remap));
                     });
    QObject::connect(&fixture.document, &SongDocument::documentChanged,
                     [&order] { order.push_back(QStringLiteral("changed")); });
    QVERIFY2(fixture.stage(twoTrackFile(), QStringLiteral("velocity")), qPrintable(fixture.error));
    SongDocument &document = fixture.document;
    const auto notes = document.notesForTrack(0);
    QCOMPARE(notes.size(), size_t(2));
    QVERIFY(notes[0].noteId.isAssigned());
    QVERIFY(notes[1].noteId.isAssigned());
    QVERIFY(notes[0].noteId != notes[1].noteId);
    order.clear();
    remaps.clear();
    const uint64_t before = document.revision();
    const int undoCount = document.undoStack()->count();
    const auto result = document.setNotesVelocities(
        before, {{notes[0].noteId, 0}, {notes[1].noteId, 200}, {notes[0].noteId, 99}});
    QVERIFY(result);
    QCOMPARE(*result, before + 1);
    QCOMPARE(document.revision(), before + 1);
    QCOMPARE(document.undoStack()->count(), undoCount + 1);
    DocNote first;
    DocNote second;
    QVERIFY(document.findNote(notes[0].noteId, &first));
    QVERIFY(document.findNote(notes[1].noteId, &second));
    QCOMPARE(first.velocity, uint8_t(99));
    QCOMPARE(second.velocity, uint8_t(127));
    QVERIFY((order == std::vector<QString>{QStringLiteral("changed")}));
    QVERIFY(remaps.empty());
    const uint64_t changed = document.revision();
    order.clear();
    document.undoStack()->undo();
    QCOMPARE(document.revision(), changed + 1);
    QVERIFY(document.findNote(notes[0].noteId, &first));
    QVERIFY(document.findNote(notes[1].noteId, &second));
    QCOMPARE(first.velocity, uint8_t(100));
    QCOMPARE(second.velocity, uint8_t(90));
    QVERIFY((order == std::vector<QString>{QStringLiteral("changed")}));
    const uint64_t undone = document.revision();
    order.clear();
    document.undoStack()->redo();
    QCOMPARE(document.revision(), undone + 1);
    QVERIFY(document.findNote(notes[0].noteId, &first));
    QCOMPARE(first.velocity, uint8_t(99));
    const uint64_t lowerBefore = document.revision();
    const int lowerUndo = document.undoStack()->count();
    order.clear();
    const auto lower = document.setNotesVelocities(lowerBefore, {{first.noteId, 0}});
    QVERIFY(lower);
    QCOMPARE(*lower, lowerBefore + 1);
    QCOMPARE(document.revision(), lowerBefore + 1);
    QCOMPARE(document.undoStack()->count(), lowerUndo + 1);
    QVERIFY(document.findNote(first.noteId, &first));
    QCOMPARE(first.velocity, uint8_t(1));
    QVERIFY((order == std::vector<QString>{QStringLiteral("changed")}));
}

void EditCheckTest::documentVelocityRejects()
{
    songdocument_test::SyntheticDocument fixture;
    int changedCount = 0;
    QObject::connect(&fixture.document, &SongDocument::documentChanged,
                     [&changedCount] { ++changedCount; });
    QVERIFY2(fixture.stage(twoTrackFile(), QStringLiteral("velocity-rejects")),
             qPrintable(fixture.error));
    SongDocument &document = fixture.document;
    const auto notes = document.notesForTrack(0);
    const QByteArray bytes = document.smf().write();
    const uint64_t revision = document.revision();
    const int undoCount = document.undoStack()->count();
    changedCount = 0;
    QVERIFY(!document.setNotesVelocities(revision - 1, {{notes[0].noteId, 42}}));
    QVERIFY(
        !document.setNotesVelocities(revision - 1, {{notes[0].noteId, 42}, {notes[1].noteId, 77}}));
    QVERIFY(!document.setNotesVelocities(revision, {{notes[0].noteId, 42}, {NoteId{}, 77}}));
    const auto result =
        document.setNotesVelocities(revision, {{notes[0].noteId, 100}, {notes[1].noteId, 90}});
    QVERIFY(result);
    QCOMPARE(*result, revision);
    QCOMPARE(document.smf().write(), bytes);
    QCOMPARE(document.revision(), revision);
    QCOMPARE(document.undoStack()->count(), undoCount);
    QCOMPARE(changedCount, 0);
}

void EditCheckTest::documentDuplicateIdentities()
{
    songdocument_test::SyntheticDocument fixture;
    QVERIFY2(fixture.stage(twoTrackFile(), QStringLiteral("duplicate-identities")),
             qPrintable(fixture.error));
    SongDocument &document = fixture.document;
    const auto source = document.notesForTrack(0);
    const int copy = document.duplicateTrack(0);
    QVERIFY(copy >= 0);
    const auto copied = document.notesForTrack(copy);
    QCOMPARE(copied.size(), source.size());
    for (size_t index = 0; index < copied.size(); ++index) {
        QCOMPARE(copied[index].tick, source[index].tick);
        QCOMPARE(copied[index].key, source[index].key);
        QCOMPARE(copied[index].duration, source[index].duration);
        QCOMPARE(copied[index].velocity, source[index].velocity);
        for (const DocNote &original : source)
            QVERIFY(copied[index].noteId != original.noteId);
    }
    const auto minted = copied;
    document.undoStack()->undo();
    document.undoStack()->redo();
    const auto redone = document.notesForTrack(copy);
    QCOMPARE(redone.size(), minted.size());
    for (size_t index = 0; index < redone.size(); ++index)
        QCOMPARE(redone[index].noteId, minted[index].noteId);
}

void EditCheckTest::documentRemapsAndRaw()
{
    songdocument_test::SyntheticDocument fixture;
    std::vector<QString> order;
    std::vector<TrackRemap> remaps;
    QObject::connect(&fixture.document, &SongDocument::tracksRemapped,
                     [&order, &remaps](TrackRemap remap) {
                         order.push_back(QStringLiteral("remap"));
                         remaps.push_back(std::move(remap));
                     });
    QObject::connect(&fixture.document, &SongDocument::documentChanged,
                     [&order] { order.push_back(QStringLiteral("changed")); });
    QVERIFY2(fixture.stage(twoTrackFile(), QStringLiteral("remaps")), qPrintable(fixture.error));
    SongDocument &document = fixture.document;
    const auto expectRemap = [&order, &remaps](const std::vector<int> &smf,
                                               const std::vector<int> &engine, int smfCount,
                                               int engineCount) {
        return remaps.size() == 1 && remaps.front().smfTrackMap == smf &&
               remaps.front().engineTrackMap == engine &&
               remaps.front().newSmfTrackCount == smfCount &&
               remaps.front().newEngineTrackCount == engineCount &&
               order == std::vector<QString>{QStringLiteral("remap"), QStringLiteral("changed")};
    };
    order.clear();
    remaps.clear();
    QVERIFY(document.moveTrack(0, 1));
    QVERIFY(expectRemap({0, 2, 1}, {1, 0}, 3, 2));
    order.clear();
    remaps.clear();
    document.undoStack()->undo();
    QVERIFY(expectRemap({0, 2, 1}, {1, 0}, 3, 2));
    order.clear();
    remaps.clear();
    document.undoStack()->redo();
    QVERIFY(expectRemap({0, 2, 1}, {1, 0}, 3, 2));
    order.clear();
    remaps.clear();
    QCOMPARE(document.addTrack(3), 2);
    QVERIFY(expectRemap({0, 1, 2}, {0, 1}, 4, 3));
    order.clear();
    remaps.clear();
    document.undoStack()->undo();
    QVERIFY(expectRemap({0, 1, 2, -1}, {0, 1, -1}, 3, 2));
    order.clear();
    remaps.clear();
    document.undoStack()->redo();
    QVERIFY(expectRemap({0, 1, 2}, {0, 1}, 4, 3));
    order.clear();
    remaps.clear();
    document.deleteTrack(2);
    QVERIFY(expectRemap({0, 1, 2, -1}, {0, 1, -1}, 3, 2));
    order.clear();
    remaps.clear();
    document.undoStack()->undo();
    QVERIFY(expectRemap({0, 1, 2}, {0, 1}, 4, 3));
    order.clear();
    remaps.clear();
    document.undoStack()->redo();
    QVERIFY(expectRemap({0, 1, 2, -1}, {0, 1, -1}, 3, 2));
    order.clear();
    remaps.clear();
    QCOMPARE(document.duplicateTrack(0), 2);
    QVERIFY(expectRemap({0, 1, 2}, {0, 1}, 4, 3));
    order.clear();
    remaps.clear();
    document.undoStack()->undo();
    QVERIFY(expectRemap({0, 1, 2, -1}, {0, 1, -1}, 3, 2));
    order.clear();
    remaps.clear();
    document.undoStack()->redo();
    QVERIFY(expectRemap({0, 1, 2}, {0, 1}, 4, 3));
    order.clear();
    remaps.clear();
    document.insertRawEvent(0, songdocument_test::meta(0x01, 12, QByteArrayLiteral("metadata")));
    QVERIFY((order == std::vector<QString>{QStringLiteral("changed")}));
    QVERIFY(remaps.empty());
    order.clear();
    remaps.clear();
    document.insertRawEvent(0, songdocument_test::channel(0xC2, 0, 4, 0));
    QVERIFY(expectRemap({0, 1, 2, 3}, {1, 2, 3}, 4, 4));
    order.clear();
    remaps.clear();
    document.undoStack()->undo();
    QVERIFY(expectRemap({0, 1, 2, 3}, {-1, 0, 1, 2}, 4, 3));
    order.clear();
    remaps.clear();
    document.undoStack()->redo();
    QVERIFY(expectRemap({0, 1, 2, 3}, {1, 2, 3}, 4, 4));
    size_t programIndex = SIZE_MAX;
    for (size_t index = 0; index < document.smf().tracks[0].events.size(); ++index) {
        const SmfEvent &event = document.smf().tracks[0].events[index];
        if (event.isChannel() && event.typeNibble() == 0xC && event.channel() == 2)
            programIndex = index;
    }
    QVERIFY(programIndex != SIZE_MAX);
    order.clear();
    remaps.clear();
    document.deleteRawEvents(0, {programIndex});
    QVERIFY(expectRemap({0, 1, 2, 3}, {-1, 0, 1, 2}, 4, 3));
    order.clear();
    remaps.clear();
    document.undoStack()->undo();
    QVERIFY(expectRemap({0, 1, 2, 3}, {1, 2, 3}, 4, 4));
    order.clear();
    remaps.clear();
    document.undoStack()->redo();
    QVERIFY(expectRemap({0, 1, 2, 3}, {-1, 0, 1, 2}, 4, 3));
    order.clear();
    const uint64_t revision = document.revision();
    QVERIFY(!document.moveTrack(0, 0));
    QCOMPARE(document.revision(), revision);
    QVERIFY(order.empty());
}

void EditCheckTest::documentSavedIdentity()
{
    songdocument_test::SyntheticDocument fixture;
    QVERIFY2(fixture.stage(twoTrackFile(), QStringLiteral("saved")), qPrintable(fixture.error));
    SongDocument &document = fixture.document;
    document.didSave(document.captureSaveSnapshot(), true);
    QVERIFY(!document.isDirty());
    const SongSaveSnapshot saved = document.captureSaveSnapshot();
    document.applyTempoEdit({{}, {songdocument_test::tempo(96, 140)}});
    QVERIFY(document.isDirty());
    QVERIFY(document.captureSaveSnapshot().documentState != saved.documentState);
    document.undoStack()->undo();
    QVERIFY(!document.isDirty());
    document.undoStack()->redo();
    QVERIFY(document.isDirty());
    document.didSave(document.captureSaveSnapshot(), true);
    document.undoStack()->undo();
    QVERIFY(document.isDirty());
    document.undoStack()->redo();
    QVERIFY(!document.isDirty());
}

void EditCheckTest::documentDuplicationOwnership()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack source;
    smf.tracks.push_back(songdocument_test::conductor());
    source.events = {songdocument_test::meta(0x03, 0, QByteArrayLiteral("owned channel")),
                     songdocument_test::channel(0xC1, 0, 7, 0),
                     songdocument_test::channel(0x91, 0, 60, 100),
                     songdocument_test::channel(0x90, 24, 60, 90),
                     songdocument_test::channel(0x81, 24, 60, 0),
                     songdocument_test::channel(0x80, 48, 60, 0)};
    source.endTick = 48;
    smf.tracks.push_back(source);
    for (int channel = 2; channel < track_limits::kHardwareCapacity; ++channel)
        smf.tracks.push_back(
            {{songdocument_test::channel(uint8_t(0xC0 | channel), 0, uint8_t(channel), 0)}, 48});
    auto fixture = songdocument_test::makeDocument(std::move(smf), QStringLiteral("ownership"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    std::vector<TrackRemap> remaps;
    QObject::connect(&document, &SongDocument::tracksRemapped,
                     [&remaps](TrackRemap remap) { remaps.push_back(std::move(remap)); });
    const auto notes = document.notesForTrack(0);
    const SmfEvent &foreign = document.smf().tracks[1].events[3];
    DocNote visible;
    DocNote hidden;
    QCOMPARE(document.channelFor(0), uint8_t(1));
    QCOMPARE(notes.size(), size_t(1));
    QCOMPARE(notes.front().tick, uint64_t(0));
    QCOMPARE(notes.front().key, uint8_t(60));
    QCOMPARE(notes.front().duration, uint32_t(24));
    QCOMPARE(notes.front().velocity, uint8_t(100));
    QVERIFY(notes.front().noteId.isAssigned());
    QVERIFY(foreign.noteId.isAssigned());
    QVERIFY(foreign.noteId != notes.front().noteId);
    QVERIFY(document.findNote(notes.front().noteId, &visible));
    QVERIFY(!document.findNote(foreign.noteId, &hidden));
    const int copy = document.duplicateTrack(0);
    QVERIFY(copy >= 0);
    QCOMPARE(document.channelFor(copy), uint8_t(0));
    const auto copied = document.notesForTrack(copy);
    QCOMPARE(copied.size(), size_t(1));
    QCOMPARE(copied.front().tick, notes.front().tick);
    QCOMPARE(copied.front().key, notes.front().key);
    QCOMPARE(copied.front().duration, notes.front().duration);
    QCOMPARE(copied.front().velocity, notes.front().velocity);
    QVERIFY(copied.front().noteId != notes.front().noteId);
    QCOMPARE(remaps.size(), size_t(1));
    QCOMPARE(remaps.front().smfTrackMap.size(), size_t(16));
    QCOMPARE(remaps.front().engineTrackMap.size(), size_t(15));
    QCOMPARE(remaps.front().newSmfTrackCount, 17);
    QCOMPARE(remaps.front().newEngineTrackCount, 16);
    for (int index = 0; index < 16; ++index)
        QCOMPARE(remaps.front().smfTrackMap[size_t(index)], index);
    for (int index = 0; index < 15; ++index)
        QCOMPARE(remaps.front().engineTrackMap[size_t(index)], index);
    const auto &events = document.smf().tracks[size_t(document.smfTrackFor(copy))].events;
    QCOMPARE(events.size(), size_t(3));
    QCOMPARE(events[0], songdocument_test::channel(0xC0, 0, 7, 0));
    QCOMPARE(events[1], songdocument_test::channel(0x90, 0, 60, 100));
    QCOMPARE(events[2], songdocument_test::channel(0x80, 24, 60, 0));
    QCOMPARE(document.engineTrackCount(), track_limits::kHardwareCapacity);
    QVERIFY(!document.canAddTrack());
    QCOMPARE(document.duplicateTrack(0), -1);
    const NoteId copiedId = copied.front().noteId;
    document.undoStack()->undo();
    document.undoStack()->redo();
    DocNote redone;
    QVERIFY(document.findNote(copiedId, &redone));
    QCOMPARE(redone.tick, notes.front().tick);
}

void EditCheckTest::documentGlobalMetadata()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack source;
    source.events = {songdocument_test::meta(0x03, 0, QByteArrayLiteral("lead")),
                     songdocument_test::meta(0x51, 0, QByteArray::fromHex("07A120")),
                     songdocument_test::meta(0x58, 0, QByteArray::fromHex("04021808")),
                     songdocument_test::channel(0xC0, 0, 6, 0),
                     songdocument_test::channel(0x90, 0, 60, 100),
                     songdocument_test::meta(0x01, 4, QByteArrayLiteral("global annotation")),
                     songdocument_test::meta(0x06, 12, QByteArrayLiteral("[")),
                     songdocument_test::meta(0x06, 16, QByteArrayLiteral(":")),
                     songdocument_test::channel(0x80, 24, 60, 0)};
    source.endTick = 48;
    smf.tracks.push_back(source);
    smf.tracks.push_back({{songdocument_test::channel(0xC1, 0, 7, 0)}, 48});
    auto fixture = songdocument_test::makeDocument(std::move(smf), QStringLiteral("globals"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    const auto globalsOriginal = [&document] {
        int tempos = 0, signatures = 0, starts = 0, labels = 0;
        for (const SmfTrack &track : document.smf().tracks)
            for (const SmfEvent &event : track.events)
                if (event.isMeta()) {
                    tempos += isTempoMeta(event);
                    signatures += event.metaType == 0x58 && event.blob.size() >= 2;
                    starts += event.metaType == 0x06 && event.blob == QByteArrayLiteral("[");
                    labels += event.metaType == 0x06 && event.blob == QByteArrayLiteral(":");
                }
        const auto sigs = document.timeSigs();
        return document.tempoPoints() ==
                   std::vector<TempoPoint>{songdocument_test::tempo(0, 120)} &&
               sigs.size() == 1 && sigs.front().tick == 0 && sigs.front().numerator == 4 &&
               sigs.front().denomPow2 == 2 && document.loopTick(false) == 12 &&
               document.loopTick(true) == UINT64_MAX && tempos == 0 && signatures == 1 &&
               starts == 1 && labels == 1;
    };
    QVERIFY(globalsOriginal());
    const int copy = document.duplicateTrack(0);
    QVERIFY(copy >= 0);
    QCOMPARE(document.channelFor(copy), uint8_t(2));
    const auto &events = document.smf().tracks[size_t(document.smfTrackFor(copy))].events;
    QCOMPARE(events.size(), size_t(3));
    QCOMPARE(events[0], songdocument_test::channel(0xC2, 0, 6, 0));
    QCOMPARE(events[1], songdocument_test::channel(0x92, 0, 60, 100));
    QCOMPARE(events[2], songdocument_test::channel(0x82, 24, 60, 0));
    QVERIFY(globalsOriginal());
    QVERIFY(document.moveTrack(copy, 0));
    QVERIFY(globalsOriginal());
    document.deleteTrack(0);
    QVERIFY(globalsOriginal());
    for (int i = 0; i < 3; ++i) {
        document.undoStack()->undo();
        QVERIFY(globalsOriginal());
    }
    for (int i = 0; i < 3; ++i) {
        document.undoStack()->redo();
        QVERIFY(globalsOriginal());
    }
}

void EditCheckTest::documentCrossingIdentities()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back(
        {{songdocument_test::channel(0xC0, 0, 1, 0), songdocument_test::channel(0x90, 0, 60, 100),
          songdocument_test::channel(0x90, 0, 61, 100)},
         8});
    auto fixture = songdocument_test::makeDocument(std::move(smf), QStringLiteral("crossing"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    DocNote first;
    DocNote second;
    QVERIFY(document.findNote(0, 0, 60, &first));
    QVERIFY(document.findNote(0, 0, 61, &second));
    QVERIFY(first.unterminated());
    QVERIFY(second.unterminated());
    const NoteId firstId = first.noteId, secondId = second.noteId;
    const int before = document.undoStack()->count();
    const uint64_t initial = document.revision();
    document.moveNotes({first}, 0, 1, true);
    QCOMPARE(document.undoStack()->count(), before + 1);
    QCOMPARE(document.revision(), initial + 1);
    QVERIFY(document.findNote(firstId, &first));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(first.key, uint8_t(61));
    QCOMPARE(second.key, uint8_t(61));
    const uint64_t secondRevision = document.revision();
    document.moveNotes({second}, 0, -1, true);
    QCOMPARE(document.undoStack()->count(), before + 2);
    QCOMPARE(document.revision(), secondRevision + 1);
    QVERIFY(document.findNote(firstId, &first));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(first.key, uint8_t(61));
    QCOMPARE(second.key, uint8_t(60));
    const uint64_t undo = document.revision();
    document.undoStack()->undo();
    QCOMPARE(document.revision(), undo + 1);
    QVERIFY(document.findNote(firstId, &first));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(first.key, uint8_t(61));
    QCOMPARE(second.key, uint8_t(61));
    const uint64_t secondUndo = document.revision();
    document.undoStack()->undo();
    QCOMPARE(document.revision(), secondUndo + 1);
    QVERIFY(document.findNote(firstId, &first));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(first.key, uint8_t(60));
    QCOMPARE(second.key, uint8_t(61));
    const uint64_t redo = document.revision();
    document.undoStack()->redo();
    QCOMPARE(document.revision(), redo + 1);
    const uint64_t secondRedo = document.revision();
    document.undoStack()->redo();
    QCOMPARE(document.revision(), secondRedo + 1);
    QVERIFY(document.findNote(firstId, &first));
    QVERIFY(document.findNote(secondId, &second));
    QCOMPARE(first.key, uint8_t(61));
    QCOMPARE(second.key, uint8_t(60));
}

void EditCheckTest::documentPublicationNetZero()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back(
        {{songdocument_test::channel(0xC0, 0, 1, 0), songdocument_test::channel(0x90, 0, 70, 100),
          songdocument_test::channel(0x90, 0, 69, 100), songdocument_test::channel(0x80, 2, 69, 0),
          songdocument_test::channel(0x80, 4, 70, 0)},
         8});
    auto fixture =
        songdocument_test::makeDocument(std::move(smf), QStringLiteral("publication-net-zero"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    int changeCount = 0;
    std::vector<TrackRemap> remaps;
    QObject::connect(&document, &SongDocument::documentChanged, [&changeCount] { ++changeCount; });
    QObject::connect(&document, &SongDocument::tracksRemapped,
                     [&remaps](TrackRemap remap) { remaps.push_back(std::move(remap)); });
    DocNote moving;
    QVERIFY(document.findNote(0, 0, 69, &moving));
    const int before = document.undoStack()->count();
    const QByteArray baseline = document.smf().write();
    const uint64_t initial = document.revision();
    document.moveNotes({moving}, 0, 1, true);
    QCOMPARE(document.undoStack()->count(), before + 1);
    QCOMPARE(document.revision(), initial + 1);
    QCOMPARE(changeCount, 1);
    QVERIFY(remaps.empty());
    QVERIFY(document.findNote(0, 0, 70, &moving));
    const uint64_t inverse = document.revision();
    document.moveNotes({moving}, 0, -1, true);
    QCOMPARE(document.revision(), inverse + 1);
    QCOMPARE(changeCount, 2);
    QCOMPARE(document.undoStack()->count(), before);
    QVERIFY(!document.undoStack()->canUndo());
    QVERIFY(!document.undoStack()->canRedo());
    QCOMPARE(document.smf().write(), baseline);
    const uint64_t frozenRevision = document.revision();
    const int frozenChanges = changeCount;
    document.undoStack()->undo();
    document.undoStack()->redo();
    QCOMPARE(document.smf().write(), baseline);
    QCOMPARE(document.revision(), frozenRevision);
    QCOMPARE(changeCount, frozenChanges);
    QVERIFY(remaps.empty());
}

void EditCheckTest::documentMergedOverlapPublication()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back(
        {{songdocument_test::channel(0xC0, 0, 1, 0), songdocument_test::channel(0x90, 0, 70, 100),
          songdocument_test::channel(0x90, 0, 69, 100), songdocument_test::channel(0x80, 2, 69, 0),
          songdocument_test::channel(0x80, 4, 70, 0)},
         8});
    auto fixture = songdocument_test::makeDocument(std::move(smf),
                                                   QStringLiteral("merged-overlap-publication"));
    QVERIFY(fixture);
    SongDocument &document = fixture->document;
    std::vector<QString> order;
    std::vector<TrackRemap> remaps;
    QObject::connect(&document, &SongDocument::tracksRemapped, [&order, &remaps](TrackRemap remap) {
        order.push_back(QStringLiteral("remap"));
        remaps.push_back(std::move(remap));
    });
    QObject::connect(&document, &SongDocument::documentChanged,
                     [&order] { order.push_back(QStringLiteral("changed")); });
    const int countBefore = document.undoStack()->count();
    DocNote moved;
    DocNote survivor;
    QVERIFY(document.findNote(0, 0, 69, &moved));

    order.clear();
    remaps.clear();
    uint64_t before = document.revision();
    document.moveNotes({moved}, 0, 1, true);
    QCOMPARE(document.undoStack()->count(), countBefore + 1);
    QCOMPARE(document.revision(), before + 1);
    QVERIFY(remaps.empty());
    QVERIFY((order == std::vector<QString>{QStringLiteral("changed")}));
    QVERIFY(document.findNote(0, 0, 70, &moved));
    QVERIFY(document.findNote(0, 2, 70, &survivor));
    QCOMPARE(survivor.duration, uint32_t(2));

    order.clear();
    remaps.clear();
    before = document.revision();
    document.moveNotes({moved}, 0, 1, true);
    QCOMPARE(document.undoStack()->count(), countBefore + 1);
    QCOMPARE(document.revision(), before + 1);
    QVERIFY(remaps.empty());
    QVERIFY((order == std::vector<QString>{QStringLiteral("changed")}));
    QVERIFY(document.findNote(0, 0, 71, &moved));
    QVERIFY(document.findNote(0, 0, 70, &survivor));
    QCOMPARE(survivor.duration, uint32_t(4));

    order.clear();
    remaps.clear();
    before = document.revision();
    document.moveNotes({moved}, 0, 1, true);
    QCOMPARE(document.undoStack()->count(), countBefore + 1);
    QCOMPARE(document.revision(), before + 1);
    QVERIFY(remaps.empty());
    QVERIFY((order == std::vector<QString>{QStringLiteral("changed")}));
    QVERIFY(document.findNote(0, 0, 72, &moved));
    QVERIFY(document.findNote(0, 0, 70, &survivor));
    QCOMPARE(survivor.duration, uint32_t(4));

    order.clear();
    remaps.clear();
    before = document.revision();
    document.undoStack()->undo();
    QCOMPARE(document.revision(), before + 1);
    QVERIFY(remaps.empty());
    QVERIFY((order == std::vector<QString>{QStringLiteral("changed")}));
    QVERIFY(document.findNote(0, 0, 69, &moved));
    QVERIFY(document.findNote(0, 0, 70, &survivor));
    QCOMPARE(survivor.duration, uint32_t(4));

    order.clear();
    remaps.clear();
    before = document.revision();
    document.undoStack()->redo();
    QCOMPARE(document.revision(), before + 1);
    QVERIFY(remaps.empty());
    QVERIFY((order == std::vector<QString>{QStringLiteral("changed")}));
    QVERIFY(document.findNote(0, 0, 72, &moved));

    order.clear();
    remaps.clear();
    before = document.revision();
    document.moveNotes({moved}, 0, 1);
    QCOMPARE(document.revision(), before + 1);
    QVERIFY(remaps.empty());
    QVERIFY((order == std::vector<QString>{QStringLiteral("changed")}));

    order.clear();
    remaps.clear();
    before = document.revision();
    document.undoStack()->undo();
    QCOMPARE(document.revision(), before + 1);
    QVERIFY(remaps.empty());
    QVERIFY((order == std::vector<QString>{QStringLiteral("changed")}));

    order.clear();
    remaps.clear();
    before = document.revision();
    document.undoStack()->redo();
    QCOMPARE(document.revision(), before + 1);
    QVERIFY(remaps.empty());
    QVERIFY((order == std::vector<QString>{QStringLiteral("changed")}));
}
