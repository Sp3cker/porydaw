#include <QElapsedTimer>
#include <QFile>
#include <QString>
#include <QTemporaryDir>
#include <algorithm>
#include <array>
#include <cstdio>
#include <iterator>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "core/tracklimits.h"
#include "project/decompproject.h"

// --editcheck <projectRoot>: M2 undo-integrity check. For every song with a
// MIDI source, performs a scripted pass over every edit-operation type, then
// verifies that undoing everything restores the SMF byte-for-byte, that redo
// reproduces the edited state deterministically, and that event ticks stay
// sorted after each mutation. Complements --roundtrip (which proves the
// unedited writer) by proving the editing layer can always get back to that
// pristine state.

namespace {

bool tracksSorted(const SmfFile &smf)
{
    for (const SmfTrack &track : smf.tracks) {
        for (size_t i = 1; i < track.events.size(); i++) {
            if (track.events[i].tick < track.events[i - 1].tick)
                return false;
        }
    }
    return true;
}

TempoPoint tempoPoint(uint64_t tick, uint32_t bpm)
{
    return {tick, 60'000'000U / bpm};
}

bool containsTempoPoint(const SongDocument &doc, const TempoPoint &point)
{
    for (const TempoPoint &candidate : doc.tempoPoints()) {
        if (candidate == point)
            return true;
    }
    return false;
}

int documentContractFailures()
{
    auto failures = 0;
    const auto fail = [&failures](const char *what) {
        std::fprintf(stderr, "editcheck: FAIL document-contracts: %s\n", what);
        failures++;
    };
    const auto channel = [](uint8_t status, uint64_t tick, uint8_t data0, uint8_t data1) {
        SmfEvent event;
        event.tick = tick;
        event.status = status;
        event.data0 = data0;
        event.data1 = data1;
        return event;
    };
    const auto meta = [](uint8_t type, uint64_t tick, const QByteArray &blob) {
        SmfEvent event;
        event.tick = tick;
        event.status = 0xFF;
        event.metaType = type;
        event.blob = blob;
        return event;
    };
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack conductor;
    SmfEvent text;
    text.status = 0xFF;
    text.metaType = 0x01;
    text.blob = QByteArrayLiteral("contract fixture");
    conductor.events.push_back(text);
    conductor.endTick = 48;
    smf.tracks.push_back(conductor);
    SmfTrack first;
    first.events.push_back(channel(0xC0, 0, 1, 0));
    first.events.push_back(channel(0x90, 0, 60, 100));
    first.events.push_back(channel(0x90, 0, 60, 90));
    first.events.push_back(channel(0x80, 12, 60, 0));
    first.events.push_back(channel(0x80, 24, 60, 0));
    first.endTick = 48;
    smf.tracks.push_back(first);
    SmfTrack second;
    second.events.push_back(channel(0xC1, 0, 2, 0));
    second.endTick = 48;
    smf.tracks.push_back(second);

    QTemporaryDir temporary;
    const QString midPath = temporary.path() + QStringLiteral("/contracts.mid");
    QString error;
    SongInfo info;
    info.label = QStringLiteral("contracts");
    info.midPath = midPath;
    info.hasMid = true;
    SongDocument doc;
    std::vector<QString> order;
    std::vector<TrackRemap> remaps;
    std::vector<uint64_t> loadRevisions;
    QObject::connect(&doc, &SongDocument::tracksRemapped,
                     [&doc, &order, &remaps, &loadRevisions](TrackRemap remap) {
                         order.push_back(QStringLiteral("remap"));
                         remaps.push_back(std::move(remap));
                         loadRevisions.push_back(doc.revision());
                     });
    QObject::connect(&doc, &SongDocument::documentChanged, [&doc, &order, &loadRevisions] {
        order.push_back(QStringLiteral("changed"));
        loadRevisions.push_back(doc.revision());
    });
    auto ok = temporary.isValid() && smf.writeFile(midPath, &error) && doc.load(info, &error);
    if (!ok) {
        fail("could not write/load the synthetic file");
        return failures;
    }
    if (doc.revision() != 1 || loadRevisions != std::vector<uint64_t>{1, 1} ||
        order != std::vector<QString>{QStringLiteral("remap"), QStringLiteral("changed")} ||
        remaps.size() != 1 || !remaps.front().smfTrackMap.empty() ||
        !remaps.front().engineTrackMap.empty() || remaps.front().newSmfTrackCount != 3 ||
        remaps.front().newEngineTrackCount != 2) {
        fail("load did not publish a complete replacement at its new revision");
        return failures;
    }

    const auto clearSignals = [&order, &remaps] {
        order.clear();
        remaps.clear();
    };
    const auto expect = [&](bool condition, const char *what) {
        if (!condition) {
            fail(what);
            ok = false;
        }
    };
    const auto expectRemap = [&](const char *what, const std::vector<int> &smfMap,
                                 const std::vector<int> &engineMap, int newSmfCount,
                                 int newEngineCount) {
        expect(remaps.size() == 1 && remaps.front().smfTrackMap == smfMap &&
                   remaps.front().engineTrackMap == engineMap &&
                   remaps.front().newSmfTrackCount == newSmfCount &&
                   remaps.front().newEngineTrackCount == newEngineCount &&
                   order ==
                       std::vector<QString>{QStringLiteral("remap"), QStringLiteral("changed")},
               what);
    };
    expect(doc.tempoPoints().empty(), "tempo-free file grew a synthetic tempo point");
    if (ok) {
        const auto timeline = doc.buildTimeline(48000.0);
        expect(timeline && timeline->tempoMap.size() == 1 && timeline->tempoMap.front().tick == 0 &&
                   timeline->tempoMap.front().bpm == 120.0,
               "tempo-free file did not use the implicit 120 BPM playback default");
    }
    if (ok) {
        const TempoPoint point = tempoPoint(24, 150);
        doc.applyTempoEdit({{}, {point}});
        doc.applyTempoEdit({{point}, {}});
        expect(doc.tempoPoints().empty(), "removing the last tempo point reseeded the document");
        doc.undoStack()->undo();
        expect(doc.tempoPoints() == std::vector<TempoPoint>{point},
               "tempo-point removal undo did not restore the point");
        doc.undoStack()->redo();
        expect(doc.tempoPoints().empty(),
               "tempo-point removal redo did not restore the empty document");
    }
    if (ok) {
        SmfFile saved;
        const bool savedFile = doc.save(&error) && SmfFile::readFile(midPath, &saved, &error);
        auto savedTempoCount = 0;
        if (savedFile) {
            for (const SmfTrack &track : saved.tracks) {
                savedTempoCount +=
                    int(std::count_if(track.events.cbegin(), track.events.cend(),
                                      [](const SmfEvent &event) { return isTempoMeta(event); }));
            }
        }
        expect(savedFile && savedTempoCount == 0,
               "saving an empty tempo list emitted an FF 51 event");
    }
    doc.undoStack()->clear();
    clearSignals();

    const auto notes = doc.notesForTrack(0);
    expect(notes.size() == 2 && notes[0].noteId.isAssigned() && notes[1].noteId.isAssigned() &&
               notes[0].noteId != notes[1].noteId,
           "duplicate note-ons did not receive distinct identities");
    if (ok) {
        DocNote byId, bySecondId;
        expect(doc.findNote(notes[0].noteId, &byId) && doc.findNote(notes[1].noteId, &bySecondId) &&
                   byId.onIndex == notes[0].onIndex && bySecondId.noteId == notes[1].noteId,
               "identity lookup did not resolve exact duplicate notes");
    }
    if (ok) {
        clearSignals();
        const uint64_t before = doc.revision();
        const int undoCount = doc.undoStack()->count();
        const auto result = doc.setNotesVelocities(
            before, {{notes[0].noteId, 0}, {notes[1].noteId, 200}, {notes[0].noteId, 99}});
        DocNote firstNow, secondNow;
        expect(result && *result == before + 1 && doc.revision() == before + 1 &&
                   doc.undoStack()->count() == undoCount + 1 &&
                   doc.findNote(notes[0].noteId, &firstNow) &&
                   doc.findNote(notes[1].noteId, &secondNow) && firstNow.velocity == 99 &&
                   secondNow.velocity == 127 &&
                   order == std::vector<QString>{QStringLiteral("changed")},
               "velocity batch did not last-write, clamp, and commit atomically");
        expect(doc.findNote(notes[0].noteId, &firstNow) && firstNow.noteId == notes[0].noteId &&
                   firstNow.velocity == 99,
               "successful batch did not preserve its NoteId");
        const uint64_t changedRevision = doc.revision();
        clearSignals();
        doc.undoStack()->undo();
        expect(doc.revision() == changedRevision + 1 && doc.findNote(notes[0].noteId, &firstNow) &&
                   doc.findNote(notes[1].noteId, &secondNow) && firstNow.velocity == 100 &&
                   secondNow.velocity == 90 &&
                   order == std::vector<QString>{QStringLiteral("changed")},
               "velocity batch undo did not restore exact values");
        const uint64_t undoneRevision = doc.revision();
        clearSignals();
        doc.undoStack()->redo();
        expect(doc.revision() == undoneRevision + 1 && doc.findNote(notes[0].noteId, &firstNow) &&
                   doc.findNote(notes[1].noteId, &secondNow) && firstNow.velocity == 99 &&
                   secondNow.velocity == 127 &&
                   order == std::vector<QString>{QStringLiteral("changed")},
               "velocity batch redo did not preserve duplicate identities");
        DocNote lower;
        expect(doc.findNote(notes[0].noteId, &lower),
               "velocity batch fixture did not resolve the lower-clamp note");
        if (ok) {
            clearSignals();
            const uint64_t lowerBefore = doc.revision();
            const int lowerUndoCount = doc.undoStack()->count();
            const auto lowerResult = doc.setNotesVelocities(lowerBefore, {{lower.noteId, 0}});
            expect(lowerResult && *lowerResult == lowerBefore + 1 &&
                       doc.revision() == lowerBefore + 1 &&
                       doc.undoStack()->count() == lowerUndoCount + 1 &&
                       doc.findNote(notes[0].noteId, &firstNow) && firstNow.velocity == 1 &&
                       order == std::vector<QString>{QStringLiteral("changed")},
                   "velocity batch did not clamp an independently edited note to one");
            clearSignals();
            const uint64_t lowerAppliedRevision = doc.revision();
            doc.undoStack()->undo();
            expect(doc.revision() == lowerAppliedRevision + 1 &&
                       doc.undoStack()->count() == lowerUndoCount + 1 &&
                       doc.findNote(notes[0].noteId, &firstNow) && firstNow.velocity == 99 &&
                       order == std::vector<QString>{QStringLiteral("changed")},
                   "lower-clamped velocity batch undo did not restore the exact value");
        }
    }
    if (ok) {
        DocNote current;
        doc.findNote(notes[0].noteId, &current);
        const QByteArray unchanged = doc.smf().write();
        const uint64_t before = doc.revision();
        const int undoCount = doc.undoStack()->count();
        clearSignals();
        const auto staleResult = doc.setNotesVelocities(before - 1, {{current.noteId, 42}});
        expect(!staleResult && doc.smf().write() == unchanged && doc.revision() == before &&
                   doc.undoStack()->count() == undoCount && order.empty(),
               "stale expected revision did not reject a current velocity NoteId");
        const auto staleBatchResult =
            doc.setNotesVelocities(before - 1, {{current.noteId, 42}, {notes[1].noteId, 77}});
        expect(!staleBatchResult && doc.smf().write() == unchanged && doc.revision() == before &&
                   doc.undoStack()->count() == undoCount && order.empty(),
               "stale velocity batch was not rejected atomically");
        const NoteId invalidId;
        const auto invalidBatchResult =
            doc.setNotesVelocities(before, {{current.noteId, 42}, {invalidId, 77}});
        expect(!invalidBatchResult && doc.smf().write() == unchanged && doc.revision() == before &&
                   doc.undoStack()->count() == undoCount && order.empty(),
               "invalid velocity NoteId partially mutated the batch");
        DocNote secondCurrent;
        doc.findNote(notes[1].noteId, &secondCurrent);
        const auto noOpResult =
            doc.setNotesVelocities(before, {{current.noteId, current.velocity},
                                            {secondCurrent.noteId, secondCurrent.velocity}});
        expect(noOpResult && *noOpResult == before && doc.smf().write() == unchanged &&
                   doc.revision() == before && doc.undoStack()->count() == undoCount &&
                   order.empty(),
               "no-op velocity batch changed document state");
    }
    if (ok) {
        const auto source = doc.notesForTrack(0);
        clearSignals();
        const int copy = doc.duplicateTrack(0);
        expect(copy >= 0, "track duplication rejected a duplicable source");
        if (copy >= 0) {
            const auto copied = doc.notesForTrack(copy);
            bool matches = copied.size() == source.size();
            for (size_t i = 0; matches && i < copied.size(); i++) {
                matches = copied[i].tick == source[i].tick && copied[i].key == source[i].key &&
                          copied[i].duration == source[i].duration &&
                          copied[i].velocity == source[i].velocity;
                for (size_t j = 0; matches && j < source.size(); j++)
                    matches = copied[i].noteId != source[j].noteId;
                for (size_t j = 0; matches && j < i; j++)
                    matches = copied[i].noteId != copied[j].noteId;
            }
            expect(matches, "track duplication did not preserve notes with fresh identities");
            const auto copiedIds = copied;
            doc.undoStack()->undo();
            doc.undoStack()->redo();
            const auto redone = doc.notesForTrack(copy);
            bool idsPreserved = redone.size() == copiedIds.size();
            for (size_t i = 0; idsPreserved && i < redone.size(); i++)
                idsPreserved = redone[i].noteId == copiedIds[i].noteId;
            expect(idsPreserved, "track duplication redo did not preserve minted identities");
            doc.undoStack()->undo();
        }
    }

    if (ok) {
        clearSignals();
        const uint64_t before = doc.revision();
        expect(doc.moveTrack(0, 1) && doc.revision() == before + 1,
               "track move did not increment revision exactly once");
        expectRemap("track move remap/order was incomplete", {0, 2, 1}, {1, 0}, 3, 2);
        clearSignals();
        doc.undoStack()->undo();
        expectRemap("track move undo remap was incomplete", {0, 2, 1}, {1, 0}, 3, 2);
        clearSignals();
        doc.undoStack()->redo();
        expectRemap("track move redo remap was incomplete", {0, 2, 1}, {1, 0}, 3, 2);
    }
    if (ok) {
        clearSignals();
        const int added = doc.addTrack(3);
        expect(added == 2, "track insertion did not produce its new engine slot");
        expectRemap("track insertion remap/order was incomplete", {0, 1, 2}, {0, 1}, 4, 3);
        clearSignals();
        doc.undoStack()->undo();
        expectRemap("track insertion undo remap was incomplete", {0, 1, 2, -1}, {0, 1, -1}, 3, 2);
        clearSignals();
        doc.undoStack()->redo();
        expectRemap("track insertion redo remap was incomplete", {0, 1, 2}, {0, 1}, 4, 3);
        clearSignals();
        doc.deleteTrack(added);
        expectRemap("track deletion remap did not mark deleted owners", {0, 1, 2, -1}, {0, 1, -1},
                    3, 2);
        clearSignals();
        doc.undoStack()->undo();
        expectRemap("track deletion undo remap was incomplete", {0, 1, 2}, {0, 1}, 4, 3);
        clearSignals();
        doc.undoStack()->redo();
        expectRemap("track deletion redo remap was incomplete", {0, 1, 2, -1}, {0, 1, -1}, 3, 2);
    }
    if (ok) {
        clearSignals();
        const int copy = doc.duplicateTrack(0);
        expect(copy == 2, "track duplication did not create its engine slot");
        expectRemap("track duplication remap/order was incomplete", {0, 1, 2}, {0, 1}, 4, 3);
        clearSignals();
        doc.undoStack()->undo();
        expectRemap("track duplication undo remap was incomplete", {0, 1, 2, -1}, {0, 1, -1}, 3, 2);
        clearSignals();
        doc.undoStack()->redo();
        expectRemap("track duplication redo remap was incomplete", {0, 1, 2}, {0, 1}, 4, 3);
    }
    if (ok) {
        SmfEvent metadata;
        metadata.tick = 12;
        metadata.status = 0xFF;
        metadata.metaType = 0x01;
        metadata.blob = QByteArrayLiteral("metadata");
        clearSignals();
        doc.insertRawEvent(0, metadata);
        expect(remaps.empty() && order == std::vector<QString>{QStringLiteral("changed")},
               "identity raw-metadata edit published a remap");
        clearSignals();
        doc.undoStack()->undo();
        expect(remaps.empty() && order == std::vector<QString>{QStringLiteral("changed")},
               "identity raw-metadata undo published a remap");
        clearSignals();
        const uint64_t before = doc.revision();
        expect(!doc.moveTrack(0, 0) && doc.revision() == before && order.empty(),
               "track move no-op changed state");
    }
    if (ok) {
        SmfEvent program = channel(0xC2, 0, 4, 0);
        clearSignals();
        doc.insertRawEvent(0, program);
        expectRemap("metadata-to-engine remap was incomplete", {0, 1, 2, 3}, {1, 2, 3}, 4, 4);
        clearSignals();
        doc.undoStack()->undo();
        expectRemap("metadata-to-engine undo remap was incomplete", {0, 1, 2, 3}, {-1, 0, 1, 2}, 4,
                    3);
        clearSignals();
        doc.undoStack()->redo();
        expectRemap("metadata-to-engine redo remap was incomplete", {0, 1, 2, 3}, {1, 2, 3}, 4, 4);
        size_t programIndex = SIZE_MAX;
        for (size_t index = 0; index < doc.smf().tracks[0].events.size(); index++) {
            const SmfEvent &event = doc.smf().tracks[0].events[index];
            if (event.isChannel() && event.typeNibble() == 0xC && event.channel() == 2)
                programIndex = index;
        }
        if (programIndex == SIZE_MAX) {
            fail("metadata-to-engine fixture lost its inserted program");
            return failures;
        }
        clearSignals();
        doc.deleteRawEvents(0, {programIndex});
        expectRemap("engine-to-metadata remap was incomplete", {0, 1, 2, 3}, {-1, 0, 1, 2}, 4, 3);
        clearSignals();
        doc.undoStack()->undo();
        expectRemap("engine-to-metadata undo remap was incomplete", {0, 1, 2, 3}, {1, 2, 3}, 4, 4);
        clearSignals();
        doc.undoStack()->redo();
        expectRemap("engine-to-metadata redo remap was incomplete", {0, 1, 2, 3}, {-1, 0, 1, 2}, 4,
                    3);
    }
    if (ok) {
        SmfFile collision;
        collision.format = 1;
        collision.division = 24;
        collision.tracks.push_back(conductor);
        SmfEvent metadata;
        metadata.status = 0xFF;
        metadata.metaType = 0x03;
        metadata.blob = QByteArrayLiteral("owned channel");
        SmfTrack sourceTrack;
        sourceTrack.events.push_back(metadata);
        sourceTrack.events.push_back(channel(0xC1, 0, 7, 0));
        sourceTrack.events.push_back(channel(0x91, 0, 60, 100));
        sourceTrack.events.push_back(channel(0x90, 24, 60, 90));
        sourceTrack.events.push_back(channel(0x81, 24, 60, 0));
        sourceTrack.events.push_back(channel(0x80, 48, 60, 0));
        sourceTrack.endTick = 48;
        collision.tracks.push_back(sourceTrack);
        for (int channelNumber = 2; channelNumber < 16; channelNumber++) {
            SmfTrack track;
            track.events.push_back(
                channel(uint8_t(0xC0 | channelNumber), 0, uint8_t(channelNumber), 0));
            track.endTick = 48;
            collision.tracks.push_back(std::move(track));
        }
        const QString collisionPath = temporary.path() + QStringLiteral("/channel-collision.mid");
        SongInfo collisionInfo = info;
        collisionInfo.label = QStringLiteral("channel collision");
        collisionInfo.midPath = collisionPath;
        SongDocument collisionDoc;
        std::vector<TrackRemap> collisionRemaps;
        QObject::connect(
            &collisionDoc, &SongDocument::tracksRemapped,
            [&collisionRemaps](TrackRemap remap) { collisionRemaps.push_back(std::move(remap)); });
        const bool collisionLoaded =
            collision.writeFile(collisionPath, &error) && collisionDoc.load(collisionInfo, &error);
        expect(collisionLoaded, "could not load the channel-collision fixture");
        if (!collisionLoaded)
            return failures;
        const auto source = collisionDoc.notesForTrack(0);
        DocNote hidden, visible;
        const SmfEvent &foreignNote = collisionDoc.smf().tracks[1].events[3];
        expect(collisionDoc.channelFor(0) == 1 && source.size() == 1 && source.front().tick == 0 &&
                   source.front().key == 60 && source.front().duration == 24 &&
                   source.front().velocity == 100 && source.front().noteId.isAssigned() &&
                   foreignNote.noteId.isAssigned() && foreignNote.noteId != source.front().noteId &&
                   collisionDoc.findNote(source.front().noteId, &visible) &&
                   visible.noteId == source.front().noteId &&
                   !collisionDoc.findNote(foreignNote.noteId, &hidden),
               "note projection mishandled a colliding unowned NoteId");
        collisionRemaps.clear();
        const int copy = collisionDoc.duplicateTrack(0);
        const auto copied = collisionDoc.notesForTrack(copy);
        const int copiedSmfTrack = collisionDoc.smfTrackFor(copy);
        bool visibleMatch = source.size() == copied.size();
        for (size_t index = 0; visibleMatch && index < source.size(); index++) {
            visibleMatch = copied[index].tick == source[index].tick &&
                           copied[index].key == source[index].key &&
                           copied[index].duration == source[index].duration &&
                           copied[index].velocity == source[index].velocity &&
                           copied[index].noteId.isAssigned() &&
                           copied[index].noteId != source[index].noteId;
        }
        bool completeRemap = collisionRemaps.size() == 1 &&
                             collisionRemaps.front().smfTrackMap.size() == 16 &&
                             collisionRemaps.front().engineTrackMap.size() == 15 &&
                             collisionRemaps.front().newSmfTrackCount == 17 &&
                             collisionRemaps.front().newEngineTrackCount == 16;
        for (int index = 0; completeRemap && index < 16; index++)
            completeRemap = collisionRemaps.front().smfTrackMap[index] == index;
        for (int index = 0; completeRemap && index < 15; index++)
            completeRemap = collisionRemaps.front().engineTrackMap[index] == index;
        bool copiedEvents = false;
        if (copiedSmfTrack >= 0) {
            const auto &copiedTrack = collisionDoc.smf().tracks[size_t(copiedSmfTrack)];
            copiedEvents = copiedTrack.endTick == sourceTrack.endTick &&
                           copiedTrack.events.size() == 3 &&
                           copiedTrack.events[0] == channel(0xC0, 0, 7, 0) &&
                           copiedTrack.events[1] == channel(0x90, 0, 60, 100) &&
                           copiedTrack.events[2] == channel(0x80, 24, 60, 0);
        }
        expect(copy >= 0 && collisionDoc.channelFor(copy) == 0 && visibleMatch && copiedEvents &&
                   completeRemap,
               "track duplication did not isolate the owned channel");
        expect(collisionDoc.engineTrackCount() == track_limits::kHardwareCapacity &&
                   !collisionDoc.canAddTrack() && collisionDoc.duplicateTrack(0) < 0,
               "track creation did not stop at the 16-track engine capacity");
        if (copy >= 0 && !copied.empty() && !source.empty()) {
            const NoteId copiedId = copied.front().noteId;
            collisionDoc.undoStack()->undo();
            collisionDoc.undoStack()->redo();
            DocNote redone;
            expect(collisionDoc.findNote(copiedId, &redone) && redone.tick == source.front().tick &&
                       redone.key == source.front().key &&
                       redone.duration == source.front().duration &&
                       redone.velocity == source.front().velocity,
                   "channel-isolated duplicate redo did not preserve its identity");
        }
    }
    if (ok) {
        SmfFile globals;
        globals.format = 1;
        globals.division = 24;
        const SmfEvent localName = meta(0x03, 0, QByteArrayLiteral("lead"));
        SmfTrack globalSource;
        globalSource.events.push_back(localName);
        globalSource.events.push_back(meta(0x51, 0, QByteArrayLiteral("\x07\xa1\x20")));
        globalSource.events.push_back(meta(0x58, 0, QByteArrayLiteral("\x04\x02\x18\x08")));
        globalSource.events.push_back(channel(0xC0, 0, 6, 0));
        globalSource.events.push_back(channel(0x90, 0, 60, 100));
        globalSource.events.push_back(meta(0x01, 4, QByteArrayLiteral("global annotation")));
        globalSource.events.push_back(meta(0x06, 12, QByteArrayLiteral("[")));
        globalSource.events.push_back(meta(0x06, 16, QByteArrayLiteral(":")));
        globalSource.events.push_back(channel(0x80, 24, 60, 0));
        globalSource.endTick = 48;
        globals.tracks.push_back(globalSource);
        SmfTrack backing;
        backing.events.push_back(channel(0xC1, 0, 7, 0));
        backing.endTick = 48;
        globals.tracks.push_back(backing);
        const QString globalsPath = temporary.path() + QStringLiteral("/duplicate-globals.mid");
        SongInfo globalsInfo = info;
        globalsInfo.label = QStringLiteral("duplicate globals");
        globalsInfo.midPath = globalsPath;
        SongDocument globalsDoc;
        const bool globalsLoaded =
            globals.writeFile(globalsPath, &error) && globalsDoc.load(globalsInfo, &error);
        expect(globalsLoaded, "could not load the duplicate-global fixture");
        if (!globalsLoaded)
            return failures;
        const auto activeGlobalsAreOriginal = [&globalsDoc] {
            const auto &tempoPoints = globalsDoc.tempoPoints();
            const auto signatures = globalsDoc.timeSigs();
            int tempoEvents = 0;
            int signatureEvents = 0;
            int starts = 0;
            int labels = 0;
            for (const SmfTrack &track : globalsDoc.smf().tracks) {
                for (const SmfEvent &event : track.events) {
                    if (!event.isMeta())
                        continue;
                    if (isTempoMeta(event))
                        tempoEvents++;
                    if (event.metaType == 0x58 && event.blob.size() >= 2)
                        signatureEvents++;
                    if (event.metaType == 0x06 && event.blob == QByteArrayLiteral("["))
                        starts++;
                    if (event.metaType == 0x06 && event.blob == QByteArrayLiteral(":"))
                        labels++;
                }
            }
            return tempoPoints == std::vector<TempoPoint>{tempoPoint(0, 120)} &&
                   signatures.size() == 1 && signatures.front().tick == 0 &&
                   signatures.front().numerator == 4 && signatures.front().denomPow2 == 2 &&
                   globalsDoc.loopTick(false) == 12 && globalsDoc.loopTick(true) == UINT64_MAX &&
                   tempoEvents == 0 && signatureEvents == 1 && starts == 1 && labels == 1;
        };
        expect(activeGlobalsAreOriginal(),
               "duplicate-global fixture did not load canonical globals");
        const int copy = globalsDoc.duplicateTrack(0);
        bool copiedOnlyOwned = copy >= 0 && globalsDoc.channelFor(copy) == 2;
        if (copiedOnlyOwned) {
            const SmfTrack &copiedTrack = globalsDoc.smf().tracks[globalsDoc.smfTrackFor(copy)];
            copiedOnlyOwned = copiedTrack.endTick == globalSource.endTick &&
                              copiedTrack.events.size() == 3 &&
                              copiedTrack.events[0] == channel(0xC2, 0, 6, 0) &&
                              copiedTrack.events[1] == channel(0x92, 0, 60, 100) &&
                              copiedTrack.events[2] == channel(0x82, 24, 60, 0);
        }
        expect(copiedOnlyOwned && activeGlobalsAreOriginal(),
               "track duplication copied sequencer-global metadata");
        if (copy >= 0) {
            const bool moved = globalsDoc.moveTrack(copy, 0);
            expect(moved && activeGlobalsAreOriginal(),
                   "moving a duplicate activated copied global metadata");
            if (moved) {
                globalsDoc.deleteTrack(0);
                expect(activeGlobalsAreOriginal(),
                       "deleting a moved duplicate changed sequencer-global metadata");
                globalsDoc.undoStack()->undo();
                expect(activeGlobalsAreOriginal(),
                       "undoing duplicate deletion changed sequencer-global metadata");
                globalsDoc.undoStack()->undo();
                expect(activeGlobalsAreOriginal(),
                       "undoing duplicate move changed sequencer-global metadata");
                globalsDoc.undoStack()->undo();
                expect(activeGlobalsAreOriginal(),
                       "undoing track duplication changed sequencer-global metadata");
                globalsDoc.undoStack()->redo();
                expect(activeGlobalsAreOriginal(),
                       "redoing track duplication changed sequencer-global metadata");
                globalsDoc.undoStack()->redo();
                expect(activeGlobalsAreOriginal(),
                       "redoing duplicate move changed sequencer-global metadata");
                globalsDoc.undoStack()->redo();
                expect(activeGlobalsAreOriginal(),
                       "redoing duplicate deletion changed sequencer-global metadata");
            }
        }
    }
    if (ok) {
        SmfFile collisions;
        collisions.format = 1;
        collisions.division = 24;
        SmfTrack collisionTrack;
        collisionTrack.events.push_back(channel(0xC0, 0, 1, 0));
        collisionTrack.events.push_back(channel(0x90, 0, 60, 100)); // A
        collisionTrack.events.push_back(channel(0x90, 0, 61, 100)); // B
        collisionTrack.endTick = 8;
        collisions.tracks.push_back(collisionTrack);
        const QString collisionsPath = temporary.path() + QStringLiteral("/move-collisions.mid");
        SongInfo collisionsInfo = info;
        collisionsInfo.label = QStringLiteral("move collisions");
        collisionsInfo.midPath = collisionsPath;
        SongDocument collisionsDoc;
        const bool collisionsLoaded = collisions.writeFile(collisionsPath, &error) &&
                                      collisionsDoc.load(collisionsInfo, &error);
        expect(collisionsLoaded, "could not load the move-collision fixture");
        if (!collisionsLoaded)
            return failures;
        DocNote a, b;
        const bool collisionsResolved =
            collisionsDoc.findNote(0, 0, 60, &a) && collisionsDoc.findNote(0, 0, 61, &b);
        const bool collisionsReady = collisionsResolved && a.unterminated() && b.unterminated() &&
                                     a.velocity == b.velocity && a.noteId.isAssigned() &&
                                     b.noteId.isAssigned() && a.noteId != b.noteId;
        expect(collisionsReady, "move-collision fixture did not assign distinct identities");
        if (collisionsReady) {
            const NoteId aId = a.noteId;
            const NoteId bId = b.noteId;
            const auto hasCollisionState = [&collisionsDoc, aId, bId](uint8_t aKey, uint8_t bKey) {
                DocNote aNow, bNow;
                return collisionsDoc.findNote(aId, &aNow) && collisionsDoc.findNote(bId, &bNow) &&
                       aNow.noteId == aId && bNow.noteId == bId && aNow.key == aKey &&
                       bNow.key == bKey;
            };
            const int countBefore = collisionsDoc.undoStack()->count();
            const uint64_t beforeFirstMove = collisionsDoc.revision();
            collisionsDoc.moveNotes({a}, 0, 1, true);
            expect(collisionsDoc.undoStack()->count() == countBefore + 1 &&
                       collisionsDoc.revision() == beforeFirstMove + 1 && hasCollisionState(61, 61),
                   "first move-collision transpose did not preserve A's identity");
            DocNote bAfterA;
            const bool bResolvedById = collisionsDoc.findNote(bId, &bAfterA);
            expect(bResolvedById && bAfterA.noteId == bId && bAfterA.key == 61,
                   "move-collision fixture did not re-resolve B by identity");
            if (bResolvedById) {
                const uint64_t beforeSecondMove = collisionsDoc.revision();
                collisionsDoc.moveNotes({bAfterA}, 0, -1, true);
                expect(collisionsDoc.undoStack()->count() == countBefore + 2 &&
                           collisionsDoc.revision() == beforeSecondMove + 1 &&
                           hasCollisionState(61, 60),
                       "crossing mergeable moves merged distinct note identities");
                const uint64_t beforeUndo = collisionsDoc.revision();
                collisionsDoc.undoStack()->undo();
                expect(collisionsDoc.revision() == beforeUndo + 1 && hasCollisionState(61, 61),
                       "crossing move undo did not preserve exact identities and revision");
                const uint64_t beforeSecondUndo = collisionsDoc.revision();
                collisionsDoc.undoStack()->undo();
                expect(collisionsDoc.revision() == beforeSecondUndo + 1 &&
                           hasCollisionState(60, 61),
                       "first crossing move undo did not restore exact identities and revision");
                const uint64_t beforeRedo = collisionsDoc.revision();
                collisionsDoc.undoStack()->redo();
                expect(collisionsDoc.revision() == beforeRedo + 1 && hasCollisionState(61, 61),
                       "first crossing move redo did not preserve exact identities and revision");
                const uint64_t beforeSecondRedo = collisionsDoc.revision();
                collisionsDoc.undoStack()->redo();
                expect(collisionsDoc.revision() == beforeSecondRedo + 1 &&
                           hasCollisionState(61, 60),
                       "crossing move redo did not preserve exact identities and revision");
            }
        }
    }
    if (ok) {
        SmfFile moves;
        moves.format = 1;
        moves.division = 24;
        SmfTrack moveTrack;
        moveTrack.events.push_back(channel(0xC0, 0, 1, 0));
        moveTrack.events.push_back(channel(0x90, 0, 70, 100)); // S
        moveTrack.events.push_back(channel(0x90, 0, 69, 100)); // M
        moveTrack.events.push_back(channel(0x80, 2, 69, 0));
        moveTrack.events.push_back(channel(0x80, 4, 70, 0));
        moveTrack.endTick = 8;
        moves.tracks.push_back(moveTrack);
        const QString movesPath = temporary.path() + QStringLiteral("/merge-publication.mid");
        SongInfo movesInfo = info;
        movesInfo.label = QStringLiteral("merge publication");
        movesInfo.midPath = movesPath;
        SongDocument movesDoc;
        const bool movesLoaded =
            moves.writeFile(movesPath, &error) && movesDoc.load(movesInfo, &error);
        expect(movesLoaded, "could not load the merged-move fixture");
        if (!movesLoaded)
            return failures;
        std::vector<QString> moveOrder;
        std::vector<TrackRemap> moveRemaps;
        QObject::connect(&movesDoc, &SongDocument::tracksRemapped,
                         [&moveOrder, &moveRemaps](TrackRemap remap) {
                             moveOrder.push_back(QStringLiteral("remap"));
                             moveRemaps.push_back(std::move(remap));
                         });
        QObject::connect(&movesDoc, &SongDocument::documentChanged,
                         [&moveOrder] { moveOrder.push_back(QStringLiteral("changed")); });
        const auto clearMoveSignals = [&moveOrder, &moveRemaps] {
            moveOrder.clear();
            moveRemaps.clear();
        };
        const auto expectOneMovePublication = [&](uint64_t before, const char *what) {
            expect(movesDoc.revision() == before + 1 && moveRemaps.empty() &&
                       moveOrder == std::vector<QString>{QStringLiteral("changed")},
                   what);
        };
        const int countBefore = movesDoc.undoStack()->count();
        const QByteArray reversalBaseline = movesDoc.smf().write();
        DocNote moved, survivor;
        if (!movesDoc.findNote(0, 0, 69, &moved)) {
            fail("merged-move fixture did not resolve the moved note");
            ok = false;
        }
        if (ok) {
            clearMoveSignals();
            const uint64_t before = movesDoc.revision();
            movesDoc.moveNotes({moved}, 0, 1, true);
            expect(movesDoc.undoStack()->count() == countBefore + 1,
                   "initial reversal mergeable move did not retain an undo entry");
            expectOneMovePublication(
                before, "initial reversal mergeable move did not publish exactly once");
            if (!movesDoc.findNote(0, 0, 70, &moved)) {
                fail("initial reversal mergeable move did not resolve its output");
                ok = false;
            }
        }
        if (ok) {
            clearMoveSignals();
            const uint64_t before = movesDoc.revision();
            movesDoc.moveNotes({moved}, 0, -1, true);
            expectOneMovePublication(
                before, "inverse net-zero mergeable move did not publish exactly once");
            expect(
                movesDoc.undoStack()->count() == countBefore && !movesDoc.undoStack()->canUndo() &&
                    !movesDoc.undoStack()->canRedo() && movesDoc.smf().write() == reversalBaseline,
                "net-zero merged move retained an undo entry or did not restore its original MIDI");
            clearMoveSignals();
            const uint64_t afterInverse = movesDoc.revision();
            movesDoc.undoStack()->undo();
            movesDoc.undoStack()->redo();
            expect(movesDoc.smf().write() == reversalBaseline &&
                       movesDoc.revision() == afterInverse && moveRemaps.empty() &&
                       moveOrder.empty(),
                   "undo or redo after a net-zero merged move mutated the document");
        }
        if (ok && !movesDoc.findNote(0, 0, 69, &moved)) {
            fail("net-zero merged move did not restore its original note");
            ok = false;
        }
        if (ok) {
            clearMoveSignals();
            const uint64_t before = movesDoc.revision();
            movesDoc.moveNotes({moved}, 0, 1, true);
            expectOneMovePublication(before, "initial mergeable move did not publish exactly once");
            expect(movesDoc.findNote(0, 0, 70, &moved) && movesDoc.findNote(0, 2, 70, &survivor) &&
                       survivor.duration == 2,
                   "initial mergeable move did not create its overlap state");
        }
        if (ok) {
            clearMoveSignals();
            const uint64_t before = movesDoc.revision();
            movesDoc.moveNotes({moved}, 0, 1, true);
            expect(movesDoc.undoStack()->count() == countBefore + 1,
                   "second mergeable move did not merge");
            expectOneMovePublication(
                before, "second mergeable move published its provisional overlap state");
            expect(movesDoc.findNote(0, 0, 71, &moved) && movesDoc.findNote(0, 0, 70, &survivor) &&
                       survivor.duration == 4,
                   "second mergeable move did not publish its final combined state");
        }
        if (ok) {
            clearMoveSignals();
            const uint64_t before = movesDoc.revision();
            movesDoc.moveNotes({moved}, 0, 1, true);
            expect(movesDoc.undoStack()->count() == countBefore + 1,
                   "later mergeable move did not merge");
            expectOneMovePublication(
                before, "later mergeable move published its provisional overlap state");
            expect(movesDoc.findNote(0, 0, 72, &moved) && movesDoc.findNote(0, 0, 70, &survivor) &&
                       survivor.duration == 4,
                   "later mergeable move did not publish its final combined state");
        }
        if (ok) {
            clearMoveSignals();
            const uint64_t before = movesDoc.revision();
            movesDoc.undoStack()->undo();
            expectOneMovePublication(before, "merged move undo did not publish exactly once");
            expect(movesDoc.findNote(0, 0, 69, &moved) && movesDoc.findNote(0, 0, 70, &survivor) &&
                       survivor.duration == 4,
                   "merged move undo did not restore its start");
        }
        if (ok) {
            clearMoveSignals();
            const uint64_t before = movesDoc.revision();
            movesDoc.undoStack()->redo();
            expectOneMovePublication(before, "merged move redo did not publish exactly once");
            expect(movesDoc.findNote(0, 0, 72, &moved),
                   "merged move redo did not restore its final state");
        }
        if (ok) {
            clearMoveSignals();
            const uint64_t before = movesDoc.revision();
            movesDoc.moveNotes({moved}, 0, 1);
            expectOneMovePublication(before, "ordinary move did not publish exactly once");
            clearMoveSignals();
            const uint64_t undoBefore = movesDoc.revision();
            movesDoc.undoStack()->undo();
            expectOneMovePublication(undoBefore, "ordinary move undo did not publish exactly once");
            clearMoveSignals();
            const uint64_t redoBefore = movesDoc.revision();
            movesDoc.undoStack()->redo();
            expectOneMovePublication(redoBefore, "ordinary move redo did not publish exactly once");
        }
    }
    return failures;
}

int timeRangeContractFailures()
{
    int failures = 0;
    const auto fail = [&failures](const char *what) {
        std::fprintf(stderr, "editcheck: FAIL time-range-contracts: %s\n", what);
        failures++;
    };
    const auto channel = [](uint8_t status, uint64_t tick, uint8_t data0, uint8_t data1) {
        SmfEvent event;
        event.tick = tick;
        event.status = status;
        event.data0 = data0;
        event.data1 = data1;
        return event;
    };
    const auto meta = [](uint8_t type, uint64_t tick, const QByteArray &blob) {
        SmfEvent event;
        event.tick = tick;
        event.status = 0xFF;
        event.metaType = type;
        event.blob = blob;
        return event;
    };
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back({{}, 200});
    smf.tracks.push_back({{channel(0xC0, 0, 1, 0)}, 200});
    smf.tracks.push_back({{channel(0xC1, 0, 2, 0)}, 200});
    QTemporaryDir temporary;
    QString error;
    SongInfo info;
    info.label = QStringLiteral("time-range-contracts");
    info.midPath = temporary.path() + QStringLiteral("/time-range.mid");
    info.hasMid = true;
    SongDocument doc;
    if (!temporary.isValid() || !smf.writeFile(info.midPath, &error) || !doc.load(info, &error)) {
        fail("could not write/load the time-range fixture");
        return failures;
    }
    const auto expect = [&fail](bool condition, const char *what) {
        if (!condition)
            fail(what);
    };
    const auto noteEndsBeforeOnsAt = [&doc](int engineTrack, uint64_t tick) {
        const int smfTrack = doc.smfTrackFor(engineTrack);
        if (smfTrack < 0)
            return true;
        bool sawNoteOn = false;
        for (const SmfEvent &event : doc.smf().tracks[size_t(smfTrack)].events) {
            if (event.tick != tick || !event.isChannel())
                continue;
            if (event.isNoteOn())
                sawNoteOn = true;
            else if (event.isNoteEnd() && sawNoteOn)
                return false;
        }
        return true;
    };
    const auto checkNoOp =
        [&doc, &fail](const SongDocument::TimeRange &range, const SongDocument::TimeScope &scope,
                      bool (SongDocument::*operation)(const SongDocument::TimeRange &,
                                                      const SongDocument::TimeScope &),
                      const char *what) {
            const QByteArray before = doc.smf().write();
            const auto beforeTempo = doc.tempoPoints();
            const int undoCount = doc.undoStack()->count();
            if ((doc.*operation)(range, scope) || doc.smf().write() != before ||
                doc.tempoPoints() != beforeTempo || doc.undoStack()->count() != undoCount)
                fail(what);
        };
    SongDocument::TimeScope emptyScope;
    checkNoOp({20, 20}, emptyScope, &SongDocument::removeTimeRange,
              "empty remove range/scope was not a no-op");
    checkNoOp({20, 10}, emptyScope, &SongDocument::insertBlankTime,
              "backward insert range/scope was not a no-op");
    checkNoOp({20, 10}, emptyScope, &SongDocument::duplicateTimeRange,
              "backward duplicate range/scope was not a no-op");
    SongDocument::TimeScope invalidScope;
    invalidScope.tracks = {99};
    checkNoOp({20, 30}, invalidScope, &SongDocument::removeTimeRange,
              "invalid remove scope was not a no-op");
    checkNoOp({20, 30}, invalidScope, &SongDocument::insertBlankTime,
              "invalid insert scope was not a no-op");
    checkNoOp({20, 30}, invalidScope, &SongDocument::duplicateTimeRange,
              "invalid duplicate scope was not a no-op");

    const auto checkRoundTrip =
        [&doc, &fail](const SongDocument::TimeRange &range, const SongDocument::TimeScope &scope,
                      bool (SongDocument::*operation)(const SongDocument::TimeRange &,
                                                      const SongDocument::TimeScope &),
                      const char *what) {
            const QByteArray before = doc.smf().write();
            const auto beforeTempo = doc.tempoPoints();
            const int undoCount = doc.undoStack()->count();
            if (!(doc.*operation)(range, scope)) {
                fail(what);
                return false;
            }
            const QByteArray after = doc.smf().write();
            const auto afterTempo = doc.tempoPoints();
            if (doc.undoStack()->count() != undoCount + 1) {
                fail("time edit pushed more than one undo command");
                return false;
            }
            doc.undoStack()->undo();
            if (doc.smf().write() != before) {
                fail("time edit undo did not restore exact SMF bytes");
                return false;
            }
            if (doc.tempoPoints() != beforeTempo) {
                fail("time edit undo did not restore tempo points");
                return false;
            }
            doc.undoStack()->redo();
            if (doc.smf().write() != after || doc.tempoPoints() != afterTempo) {
                fail("time edit redo did not restore exact document state");
                return false;
            }
            return true;
        };

    SongDocument::TimeScope trackScope;
    trackScope.tracks = {0};
    doc.addNote(0, 35, 60, 10, 90);
    doc.addNote(0, 60, 61, 5, 80);
    DocNote crossing, later;
    expect(doc.findNote(0, 35, 60, &crossing) && doc.findNote(0, 60, 61, &later),
           "insert fixture notes were not created");
    const NoteId laterId = later.noteId;
    if (checkRoundTrip({40, 45}, trackScope, &SongDocument::insertBlankTime,
                       "blank insertion did not commit")) {
        DocNote left, right, shifted;
        expect(doc.findNote(0, 35, 60, &left) && left.duration == 5 &&
                   doc.findNote(0, 45, 60, &right) && right.duration == 5 &&
                   doc.findNote(0, 65, 61, &shifted) && shifted.noteId == laterId,
               "blank insertion did not split the crossing note and shift the later note");
    }

    doc.addLanePoint(0, 7, 300, 10);
    doc.addLanePoint(0, 10, 300, 20);
    doc.addLanePoint(1, 7, 300, 30);
    SongDocument::TimeScope laneScope;
    laneScope.lanes = {{0, 7}};
    const uint64_t laneEndBefore = doc.smf().tracks[1].endTick;
    if (checkRoundTrip({300, 320}, laneScope, &SongDocument::insertBlankTime,
                       "lane-only blank insertion did not commit")) {
        DocLanePoint point;
        expect(doc.findLanePoint(0, 7, 320, &point) && point.value == 10 &&
                   doc.findLanePoint(0, 10, 300, &point) && point.value == 20 &&
                   doc.findLanePoint(1, 7, 300, &point) && point.value == 30 &&
                   doc.smf().tracks[1].endTick == laneEndBefore + 20,
               "lane-only insertion leaked into another lane or track or missed EOT");
    }
    doc.addNote(0, 400, 62, 5, 90);
    doc.addNote(1, 400, 63, 5, 90);
    doc.addLanePoint(0, 7, 400, 40);
    doc.addLanePoint(1, 7, 400, 50);
    const uint64_t selectedEndBefore = doc.smf().tracks[1].endTick;
    const uint64_t untouchedEndBefore = doc.smf().tracks[2].endTick;
    if (checkRoundTrip({400, 420}, trackScope, &SongDocument::insertBlankTime,
                       "track blank insertion did not commit")) {
        DocNote shiftedTrack, untouchedTrack;
        expect(doc.findNote(0, 420, 62, &shiftedTrack) &&
                   doc.findNote(1, 400, 63, &untouchedTrack) &&
                   doc.smf().tracks[1].endTick == selectedEndBefore + 20 &&
                   doc.smf().tracks[2].endTick == untouchedEndBefore,
               "track insertion did not isolate the named engine track");
    }
    if (!doc.load(info, &error)) {
        fail("could not reload for the unterminated-note fixture");
        return failures;
    }
    const int noteSmfTrack = doc.smfTrackFor(0);
    doc.insertRawEvent(noteSmfTrack, channel(0x90, 220, 68, 77));
    DocNote unterminated;
    expect(doc.findNote(0, 220, 68, &unterminated) && unterminated.unterminated(),
           "unterminated-note fixture was not created");
    const NoteId leftNoteId = unterminated.noteId;
    if (checkRoundTrip({240, 250}, trackScope, &SongDocument::insertBlankTime,
                       "unterminated blank insertion did not commit")) {
        DocNote left, right;
        bool leftBytesPreserved = false;
        bool rightBytesPreserved = false;
        bool matchingOff = false;
        for (const SmfEvent &event : doc.smf().tracks[size_t(noteSmfTrack)].events) {
            if (event.tick == 220 && event.status == 0x90 && event.data0 == 68 && event.data1 == 77)
                leftBytesPreserved = true;
            if (event.tick == 240 && event.status == 0x80 && event.data0 == 68 && event.data1 == 0)
                matchingOff = true;
            if (event.tick == 250 && event.status == 0x90 && event.data0 == 68 && event.data1 == 77)
                rightBytesPreserved = true;
        }
        expect(doc.findNote(0, 220, 68, &left) && !left.unterminated() && left.duration == 20 &&
                   doc.findNote(0, 250, 68, &right) && right.unterminated() &&
                   left.noteId == leftNoteId && right.noteId != left.noteId && leftBytesPreserved &&
                   matchingOff && rightBytesPreserved,
               "unterminated note was not silenced and resumed with a fresh raw note-on");
    }

    const uint64_t duplicateStart = 600;
    doc.addNote(0, duplicateStart + 10, 64, 10, 90); // contained, ends at e
    doc.addNote(0, duplicateStart - 5, 65, 15, 80);  // crosses s only
    doc.addNote(0, duplicateStart + 10, 66, 20, 70); // crosses e only
    doc.addNote(0, duplicateStart - 5, 67, 30, 60);  // crosses both
    DocNote contained, leftCrossing, rightCrossing, bothCrossing;
    expect(doc.findNote(0, duplicateStart + 10, 64, &contained) &&
               doc.findNote(0, duplicateStart - 5, 65, &leftCrossing) &&
               doc.findNote(0, duplicateStart + 10, 66, &rightCrossing) &&
               doc.findNote(0, duplicateStart - 5, 67, &bothCrossing),
           "duplicate boundary fixture notes were not created");
    const std::array<NoteId, 4> originalIds = {contained.noteId, leftCrossing.noteId,
                                               rightCrossing.noteId, bothCrossing.noteId};
    if (checkRoundTrip({duplicateStart, duplicateStart + 20}, trackScope,
                       &SongDocument::duplicateTimeRange, "time-range duplicate did not commit")) {
        DocNote copyContained, copyLeft, copyRight, copyBoth;
        expect(doc.findNote(0, duplicateStart + 30, 64, &copyContained) &&
                   copyContained.duration == 10 &&
                   doc.findNote(0, duplicateStart + 20, 65, &copyLeft) && copyLeft.duration == 10 &&
                   doc.findNote(0, duplicateStart + 30, 66, &copyRight) &&
                   copyRight.duration == 10 &&
                   doc.findNote(0, duplicateStart + 20, 67, &copyBoth) && copyBoth.duration == 20,
               "duplicate did not clip contained and boundary-crossing notes");
        const std::array<NoteId, 4> copiedIds = {copyContained.noteId, copyLeft.noteId,
                                                 copyRight.noteId, copyBoth.noteId};
        for (size_t i = 0; i < copiedIds.size(); i++) {
            for (size_t j = i + 1; j < copiedIds.size(); j++)
                expect(copiedIds[i] != copiedIds[j], "duplicated note-ons shared a NoteId");
            for (const NoteId id : originalIds)
                expect(copiedIds[i] != id, "duplicated note-on preserved an original NoteId");
        }
    }
    if (!doc.load(info, &error)) {
        fail("could not reload for canonical time-edit ordering");
        return failures;
    }
    const int canonicalTrack = doc.smfTrackFor(0);
    doc.insertRawEvent(canonicalTrack, channel(0x80, 700, 72, 0));
    doc.insertRawEvent(canonicalTrack, channel(0x90, 700, 72, 55));
    if (checkRoundTrip({700, 720}, trackScope, &SongDocument::duplicateTimeRange,
                       "canonical duplicate did not commit"))
        expect(noteEndsBeforeOnsAt(0, 720),
               "duplicate did not canonicalize same-tick note-end before note-on");
    doc.insertRawEvent(canonicalTrack, channel(0x80, 800, 73, 0));
    doc.insertRawEvent(canonicalTrack, channel(0x90, 800, 73, 66));
    if (checkRoundTrip({800, 820}, trackScope, &SongDocument::insertBlankTime,
                       "canonical split did not commit"))
        expect(noteEndsBeforeOnsAt(0, 820),
               "split did not canonicalize same-tick note-end before note-on");

    if (!doc.load(info, &error)) {
        fail("could not reload the clean time-range fixture");
        return failures;
    }
    const int orphanTrack = doc.smfTrackFor(0);
    doc.addNote(0, 40, 60, 10, 90);
    doc.insertRawEvent(orphanTrack, channel(0x90, 90, 61, 11));
    doc.insertRawEvent(orphanTrack, channel(0x80, 120, 66, 13));
    doc.insertRawEvent(orphanTrack, channel(0x90, 110, 62, 22));
    doc.insertRawEvent(orphanTrack, channel(0x80, 130, 63, 12));
    doc.insertRawEvent(orphanTrack, channel(0x90, 130, 64, 33));
    doc.insertRawEvent(orphanTrack, channel(0x90, 140, 65, 44));
    if (checkRoundTrip({100, 130}, trackScope, &SongDocument::removeTimeRange,
                       "orphan-note remove did not commit")) {
        bool beforeBytes = false;
        bool removedBytes = false;
        bool endBytes = false;
        bool removedEnd = false;
        bool endOnBytes = false;
        bool afterBytes = false;
        for (const SmfEvent &event : doc.smf().tracks[size_t(orphanTrack)].events) {
            if (event.tick == 90 && event.status == 0x90 && event.data0 == 61 && event.data1 == 11)
                beforeBytes = true;
            if (event.tick == 110 && event.status == 0x90 && event.data0 == 62 && event.data1 == 22)
                removedBytes = true;
            if (event.status == 0x80 && event.data0 == 66 && event.data1 == 13)
                removedEnd = true;
            if (event.tick == 100 && event.status == 0x80 && event.data0 == 63 && event.data1 == 12)
                endBytes = true;
            if (event.tick == 100 && event.status == 0x90 && event.data0 == 64 && event.data1 == 33)
                endOnBytes = true;
            if (event.tick == 110 && event.status == 0x90 && event.data0 == 65 && event.data1 == 44)
                afterBytes = true;
        }
        DocNote paired;
        expect(beforeBytes && !removedBytes && endBytes && endOnBytes && afterBytes &&
                   !removedEnd && noteEndsBeforeOnsAt(0, 100) && doc.findNote(0, 40, 60, &paired) &&
                   !paired.unterminated() && paired.duration == 10,
               "orphan note events did not close half-open without double-handling paired notes");
    }
    if (!doc.load(info, &error)) {
        fail("could not reload after orphan-note remove");
        return failures;
    }

    const uint64_t seamStart = 1000;
    doc.addLanePoint(0, 7, seamStart - 20, 33);
    doc.addLanePoint(0, 7, seamStart + 10, 44);
    if (checkRoundTrip({seamStart, seamStart + 40}, laneScope, &SongDocument::duplicateTimeRange,
                       "automation seam duplicate did not commit")) {
        DocLanePoint point;
        expect(doc.findLanePoint(0, 7, seamStart + 40, &point) && point.value == 33 &&
                   doc.findLanePoint(0, 7, seamStart + 50, &point) && point.value == 44,
               "automation duplicate did not preserve the effective seam value");
    }
    if (!doc.load(info, &error)) {
        fail("could not reload before implicit-default checks");
        return failures;
    }
    struct DefaultCase {
        uint8_t cc;
        int sourceValue;
        int expected;
    };
    const DefaultCase defaults[] = {
        {0x01, 11, 0}, {0x05, 12, 0}, {0x07, 80, 127}, {0x0A, 81, 64},        {0x14, 3, 2},
        {0x15, 4, 22}, {0x17, 5, 0},  {0x19, 6, 0},    {DOC_CC_BEND, 500, 0},
    };
    for (size_t remaining = std::size(defaults); remaining > 0; --remaining) {
        const size_t i = remaining - 1;
        const uint64_t start = 1100 + i * 40;
        doc.addLanePoint(0, defaults[i].cc, start + 10, defaults[i].sourceValue);
        SongDocument::TimeScope defaultLane;
        defaultLane.lanes = {{0, defaults[i].cc}};
        if (checkRoundTrip({start, start + 20}, defaultLane, &SongDocument::duplicateTimeRange,
                           "implicit automation default duplicate did not commit")) {
            DocLanePoint point;
            expect(doc.findLanePoint(0, defaults[i].cc, start + 20, &point) &&
                       point.value == defaults[i].expected,
                   "duplicate did not use the shared implicit automation default");
        }
    }
    const uint64_t tempoStart = 1500;
    SongDocument::TimeScope tempoScope;
    tempoScope.tempo = true;
    doc.applyTempoEdit({{tempoPoint(0, 120)}, {tempoPoint(tempoStart + 10, 150)}});
    if (checkRoundTrip({tempoStart, tempoStart + 20}, tempoScope, &SongDocument::duplicateTimeRange,
                       "tempo default duplicate did not commit")) {
        expect(containsTempoPoint(doc, tempoPoint(tempoStart + 20, 120)) &&
                   containsTempoPoint(doc, tempoPoint(tempoStart + 30, 150)),
               "tempo duplicate did not use the 120 BPM default");
    }
    auto timeline = doc.buildTimeline(44100.0);
    expect(timeline && !timeline->tempoMap.empty() && timeline->tempoMap.front().bpm == 120.0,
           "timeline tempo map did not retain the 120 BPM implicit default");
    doc.addLanePoint(0, DOC_CC_VOICE, 1610, 12);
    SongDocument::TimeScope voiceScope;
    voiceScope.lanes = {{0, DOC_CC_VOICE}};
    if (checkRoundTrip({1600, 1620}, voiceScope, &SongDocument::duplicateTimeRange,
                       "voice duplicate did not commit")) {
        DocLanePoint voice;
        expect(doc.findLanePoint(0, DOC_CC_VOICE, 1620, &voice) && voice.value == 1 &&
                   doc.findLanePoint(0, DOC_CC_VOICE, 1630, &voice) && voice.value == 12,
               "voice duplicate did not preserve the authored program state");
    }

    const uint64_t downstreamStart = 1700;
    doc.addLanePoint(0, 7, downstreamStart, 11);
    doc.addLanePoint(0, 7, downstreamStart + 20, 99);
    if (checkRoundTrip({downstreamStart, downstreamStart + 20}, laneScope,
                       &SongDocument::duplicateTimeRange,
                       "downstream boundary duplicate did not commit")) {
        DocLanePoint point;
        expect(doc.findLanePoint(0, 7, downstreamStart + 20, &point) && point.value == 11 &&
                   doc.findLanePoint(0, 7, downstreamStart + 40, &point) && point.value == 99,
               "event at duplicate end was copied instead of shifted downstream");
    }
    if (!doc.load(info, &error)) {
        fail("could not reload before whole-song duplicate");
        return failures;
    }

    doc.addNote(0, 1900, 70, 5, 50);
    const uint64_t globalStart = 1800;
    doc.setTimeSig(globalStart + 10, 3, 2);
    doc.applyTempoEdit({{}, {tempoPoint(globalStart + 10, 180)}});
    doc.insertRawEvent(0, meta(0x01, globalStart + 15, QByteArrayLiteral("global")));
    SongDocument::TimeScope wholeSong;
    wholeSong.wholeSong = true;
    if (checkRoundTrip({globalStart, globalStart + 20}, wholeSong,
                       &SongDocument::duplicateTimeRange, "whole-song duplicate did not commit")) {
        bool copiedMeta = false;
        for (const SmfEvent &event : doc.smf().tracks[0].events) {
            if (event.tick == globalStart + 35 && event.isMeta() && event.metaType == 0x01 &&
                event.blob == QByteArrayLiteral("global"))
                copiedMeta = true;
        }
        bool copiedSig = false;
        for (const DocTimeSig &sig : doc.timeSigs()) {
            if (sig.tick == globalStart + 30 && sig.numerator == 3)
                copiedSig = true;
        }
        DocNote shiftedNote;
        const int noteTrack = doc.smfTrackFor(0);
        expect(copiedMeta && copiedSig &&
                   containsTempoPoint(doc, tempoPoint(globalStart + 20, 120)) &&
                   containsTempoPoint(doc, tempoPoint(globalStart + 30, 180)) &&
                   doc.findNote(0, 1920, 70, &shiftedNote) && noteTrack >= 0 &&
                   doc.smf().tracks[size_t(noteTrack)].endTick >=
                       shiftedNote.tick + shiftedNote.duration,
               "whole-song duplicate mishandled globals or track ends");
    }
    return failures;
}

} // namespace

int runEditCheck(const QString &projectRoot)
{
    DecompProject project;
    QString error;
    if (!project.open(projectRoot, &error)) {
        std::fprintf(stderr, "editcheck: %s\n", qUtf8Printable(error));
        return 1;
    }

    QElapsedTimer timer;
    timer.start();

    int checked = 0, failures = 0;
    for (const SongInfo &song : project.songs()) {
        if (!song.isPlayable())
            continue;

        SongDocument doc;
        if (!doc.load(song, &error)) {
            std::fprintf(stderr, "editcheck: FAIL %s: %s\n", qUtf8Printable(song.label),
                         qUtf8Printable(error));
            failures++;
            continue;
        }
        const QByteArray baseline = doc.smf().write();

        // Pick a track that has notes to edit on.
        int track = -1;
        for (int t = 0; t < doc.engineTrackCount(); t++) {
            if (!doc.notesForTrack(t).empty()) {
                track = t;
                break;
            }
        }

        auto fail = [&](const char *what) {
            std::fprintf(stderr, "editcheck: FAIL %s: %s\n", qUtf8Printable(song.label), what);
            failures++;
        };

        const uint32_t step = doc.ticksPerClock();
        // Edit far past the end of the song so scripted notes and lane points
        // can't collide with (or re-pair against) the song's real content.
        uint64_t base = 0;
        for (const SmfTrack &tr : doc.smf().tracks)
            base = std::max(base, tr.endTick);
        base += step * 100;
        bool ok = true;
        auto mutateAndCheck = [&](const char *what) {
            if (ok && !tracksSorted(doc.smf())) {
                fail(what);
                ok = false;
            }
        };

        if (track >= 0) {
            // Note ops: add, move, resize, re-velocity, delete.
            doc.addNote(track, base, 60, step * 4, 100);
            mutateAndCheck("events unsorted after addNote");
            DocNote note;
            if (ok && !doc.findNote(track, base, 60, &note)) {
                fail("added note not found");
                ok = false;
            }
            if (ok) {
                doc.moveNotes({note}, int64_t(step) * 8, 3);
                mutateAndCheck("events unsorted after moveNotes");
            }
            if (ok && !doc.findNote(track, base + step * 8, 63, &note)) {
                fail("moved note not found");
                ok = false;
            }
            if (ok) {
                doc.resizeNotes({note}, int64_t(step) * 2);
                mutateAndCheck("events unsorted after resizeNotes");
                if (!doc.findNote(track, base + step * 8, 63, &note) || note.duration != step * 6) {
                    fail("resize produced wrong duration");
                    ok = false;
                }
            }
            if (ok) {
                // Left resize: the note-on moves, the note-off stays pinned.
                doc.resizeNotesLeft({note}, -int64_t(step) * 2);
                mutateAndCheck("events unsorted after resizeNotesLeft");
                if (!doc.findNote(track, base + step * 6, 63, &note) || note.duration != step * 8) {
                    fail("left resize produced wrong start/duration");
                    ok = false;
                }
            }
            if (ok) {
                // Dragging the note-on past the note-off clamps to 1 tick left.
                doc.resizeNotesLeft({note}, int64_t(step) * 100);
                mutateAndCheck("events unsorted after clamped resizeNotesLeft");
                if (!doc.findNote(track, base + step * 14 - 1, 63, &note) || note.duration != 1) {
                    fail("left resize not clamped at the note-off");
                    ok = false;
                } else {
                    doc.resizeNotesLeft({note}, -int64_t(step) * 8 + 1);
                    if (!doc.findNote(track, base + step * 6, 63, &note) ||
                        note.duration != step * 8) {
                        fail("left resize could not restore the note");
                        ok = false;
                    }
                }
            }
            if (ok) {
                doc.setNotesVelocity({note}, 88);
                if (!doc.findNote(track, base + step * 6, 63, &note) || note.velocity != 88) {
                    fail("velocity edit not applied");
                    ok = false;
                }
            }
            if (ok) {
                doc.nudgeNotesVelocity({note}, -30);
                if (!doc.findNote(track, base + step * 6, 63, &note) || note.velocity != 58) {
                    fail("velocity nudge not applied");
                    ok = false;
                }
            }
            if (ok) {
                doc.nudgeNotesVelocity({note}, 200); // must clamp to 127
                if (!doc.findNote(track, base + step * 6, 63, &note) || note.velocity != 127) {
                    fail("velocity nudge not clamped");
                    ok = false;
                }
            }
            if (ok)
                doc.deleteNotes({note});

            // Batch add (clipboard paste): both notes in one undoable command.
            if (ok) {
                doc.addNotes(track, {{base + step * 20, 64, step * 2, 96},
                                     {base + step * 22, 67, step * 2, 96}});
                mutateAndCheck("events unsorted after addNotes");
                DocNote a, b;
                if (!doc.findNote(track, base + step * 20, 64, &a) ||
                    !doc.findNote(track, base + step * 22, 67, &b)) {
                    fail("batch-added notes not found");
                    ok = false;
                } else {
                    doc.undoStack()->undo();
                    if (doc.findNote(track, base + step * 20, 64, &a) ||
                        doc.findNote(track, base + step * 22, 67, &b)) {
                        fail("addNotes was not a single undo command");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
            }

            // Abutting same-pitch notes, written right-to-left: the left
            // note's end lands at the right note's on tick, and must be
            // ordered before it — pairing (here and in mid2agb) gives every
            // note-on the first same-key end after it, so an end placed
            // after a same-tick note-on makes the left note swallow the
            // right one and orphans the real end when the pair is deleted.
            if (ok) {
                const uint64_t seam = base + step * 72;
                doc.addNote(track, seam, 60, step * 2, 100);
                doc.addNote(track, seam - step * 2, 60, step * 2, 100);
                mutateAndCheck("events unsorted after abutting addNote");
                DocNote leftNote, rightNote;
                if (!doc.findNote(track, seam - step * 2, 60, &leftNote) ||
                    !doc.findNote(track, seam, 60, &rightNote) || leftNote.duration != step * 2 ||
                    rightNote.duration != step * 2 || leftNote.endIndex == rightNote.endIndex) {
                    fail("abutting notes mis-paired (note end after same-tick note-on)");
                    ok = false;
                } else {
                    doc.deleteNotes({leftNote, rightNote});
                    bool leftover = false;
                    for (const SmfEvent &ev : doc.smf().tracks[size_t(leftNote.smfTrack)].events) {
                        leftover |= ev.tick >= seam - step * 2 && ev.isChannel() &&
                                    (ev.isNoteOn() || ev.isNoteEnd());
                    }
                    if (leftover) {
                        fail("deleting abutting notes left a note event behind");
                        ok = false;
                    }
                }
            }

            // Range edit: a multi-track/multi-lane batch of removals and
            // insertions must land as ONE undoable command.
            if (ok) {
                doc.addNotes(track, {{base + step * 30, 60, step * 2, 90},
                                     {base + step * 32, 62, step * 2, 90}});
                doc.addLanePoint(track, 7, base + step * 30, 80);
                doc.applyTempoEdit({{}, {tempoPoint(base + step * 31, 140)}});
                SongDocument::RangeEdit edit;
                for (const DocNote &n : doc.notesForTrack(track)) {
                    if (n.tick >= base + step * 30 && n.tick < base + step * 34)
                        edit.removeNotes.push_back(n);
                }
                for (const DocLanePoint &p : doc.lanePoints(track, 7)) {
                    if (p.tick == base + step * 30)
                        edit.removePoints.push_back(p);
                }
                for (const TempoPoint &point : doc.tempoPoints()) {
                    if (point.tick == base + step * 31)
                        edit.removeTempo.push_back(point);
                }
                edit.addNotes.push_back({track, {{base + step * 40, 65, step * 2, 90}}});
                edit.addPoints.push_back({track, 7, {{base + step * 40, 70}}});
                edit.addTempo.push_back(tempoPoint(base + step * 41, 155));
                doc.applyRangeEdit(QStringLiteral("range edit"), edit);
                mutateAndCheck("events unsorted after applyRangeEdit");
                DocNote n;
                DocLanePoint p;
                if (doc.findNote(track, base + step * 30, 60, &n) ||
                    doc.findNote(track, base + step * 32, 62, &n) ||
                    !doc.findNote(track, base + step * 40, 65, &n) ||
                    !doc.findLanePoint(track, 7, base + step * 40, &p) || p.value != 70 ||
                    !containsTempoPoint(doc, tempoPoint(base + step * 41, 155))) {
                    fail("range edit produced wrong content");
                    ok = false;
                } else {
                    doc.undoStack()->undo();
                    if (!doc.findNote(track, base + step * 30, 60, &n) ||
                        doc.findNote(track, base + step * 40, 65, &n)) {
                        fail("applyRangeEdit was not a single undo command");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
            }

            // Range move (time-selection nudge): notes plus CC and tempo
            // points shift together by a tick delta as ONE undoable command,
            // with values intact (events move as raw bytes).
            if (ok) {
                doc.addNotes(track, {{base + step * 80, 60, step * 2, 90},
                                     {base + step * 82, 64, step * 2, 90}});
                doc.addLanePoint(track, 7, base + step * 80, 45);
                doc.applyTempoEdit({{}, {tempoPoint(base + step * 81, 140)}});
                std::vector<DocNote> moveNotes;
                for (const DocNote &n : doc.notesForTrack(track)) {
                    if (n.tick >= base + step * 80 && n.tick < base + step * 84)
                        moveNotes.push_back(n);
                }
                std::vector<DocLanePoint> movePoints;
                for (const DocLanePoint &p : doc.lanePoints(track, 7)) {
                    if (p.tick == base + step * 80)
                        movePoints.push_back(p);
                }
                std::vector<TempoPoint> moveTempo;
                for (const TempoPoint &point : doc.tempoPoints()) {
                    if (point.tick == base + step * 81)
                        moveTempo.push_back(point);
                }
                doc.moveRange(moveNotes, movePoints, step * 3, moveTempo);
                mutateAndCheck("events unsorted after moveRange");
                DocNote n;
                DocLanePoint p;
                if (doc.findNote(track, base + step * 80, 60, &n) ||
                    !doc.findNote(track, base + step * 83, 60, &n) || n.duration != step * 2 ||
                    !doc.findNote(track, base + step * 85, 64, &n) ||
                    !doc.findLanePoint(track, 7, base + step * 83, &p) || p.value != 45 ||
                    !containsTempoPoint(doc, tempoPoint(base + step * 84, 140))) {
                    fail("range move produced wrong content");
                    ok = false;
                }
                if (ok) {
                    doc.moveRange(moveNotes, movePoints, 0, moveTempo); // no-op guard
                    doc.undoStack()->undo();
                    if (!doc.findNote(track, base + step * 80, 60, &n) ||
                        doc.findNote(track, base + step * 83, 60, &n) ||
                        !doc.findLanePoint(track, 7, base + step * 80, &p) ||
                        !containsTempoPoint(doc, tempoPoint(base + step * 81, 140))) {
                        fail("moveRange was not a single undo command");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
            }

            // Bulk lane-point move: several automation points shift by
            // independent tick/value deltas as ONE undoable command.
            if (ok) {
                doc.addLanePoint(track, 7, base + step * 90, 20);
                doc.addLanePoint(track, 7, base + step * 91, 40);
                doc.addLanePoint(track, 7, base + step * 92, 60);
                std::vector<SongDocument::LanePointMove> moves;
                for (const DocLanePoint &p : doc.lanePoints(track, 7)) {
                    if (p.tick == base + step * 90)
                        moves.push_back({track, 7, p, base + step * 93, 25});
                    else if (p.tick == base + step * 91)
                        moves.push_back({track, 7, p, base + step * 94, 45});
                }
                const int undoBefore = doc.undoStack()->count();
                doc.moveLanePoints(moves);
                mutateAndCheck("events unsorted after moveLanePoints");
                DocLanePoint p;
                if (doc.findLanePoint(track, 7, base + step * 90, &p) ||
                    doc.findLanePoint(track, 7, base + step * 91, &p) ||
                    !doc.findLanePoint(track, 7, base + step * 93, &p) || p.value != 25 ||
                    !doc.findLanePoint(track, 7, base + step * 94, &p) || p.value != 45 ||
                    !doc.findLanePoint(track, 7, base + step * 92, &p) || p.value != 60 ||
                    doc.undoStack()->count() != undoBefore + 1) {
                    fail("moveLanePoints produced wrong content or undo count");
                    ok = false;
                } else {
                    doc.undoStack()->undo();
                    if (!doc.findLanePoint(track, 7, base + step * 90, &p) || p.value != 20 ||
                        !doc.findLanePoint(track, 7, base + step * 91, &p) || p.value != 40 ||
                        doc.findLanePoint(track, 7, base + step * 93, &p)) {
                        fail("moveLanePoints was not a single undo command");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                    if (ok) {
                        doc.addLanePoint(track, 7, base + step * 95, 70);
                        doc.addLanePoint(track, 7, base + step * 96, 80);
                        DocLanePoint first, second;
                        if (!doc.findLanePoint(track, 7, base + step * 95, &first) ||
                            !doc.findLanePoint(track, 7, base + step * 96, &second)) {
                            fail("converging move fixture was not created");
                            ok = false;
                        } else {
                            const uint64_t destination = base + step * 97;
                            const int convergeUndoBefore = doc.undoStack()->count();
                            doc.moveLanePoints({{track, 7, first, destination, 71},
                                                {track, 7, second, destination, 72}});
                            mutateAndCheck("events unsorted after converging moveLanePoints");
                            int destinationCount = 0;
                            int destinationValue = -1;
                            for (const DocLanePoint &point : doc.lanePoints(track, 7)) {
                                if (point.tick == destination) {
                                    destinationCount++;
                                    destinationValue = point.value;
                                }
                            }
                            if (doc.findLanePoint(track, 7, base + step * 95, &p) ||
                                doc.findLanePoint(track, 7, base + step * 96, &p) ||
                                destinationCount != 1 || destinationValue != 72 ||
                                doc.undoStack()->count() != convergeUndoBefore + 1) {
                                fail("converging move was not last-input-wins");
                                ok = false;
                            } else {
                                doc.undoStack()->undo();
                                if (!doc.findLanePoint(track, 7, base + step * 95, &p) ||
                                    p.value != 70 ||
                                    !doc.findLanePoint(track, 7, base + step * 96, &p) ||
                                    p.value != 80 || doc.findLanePoint(track, 7, destination, &p)) {
                                    fail("converging move undo did not restore both points");
                                    ok = false;
                                } else {
                                    doc.undoStack()->redo();
                                }
                            }
                        }
                    }
                }
            }

            // Same-key overlap resolution: a written note landing on another
            // note's span trims it (head or tail kept) or removes it when
            // fully covered, in the same undo command — the pairing rule
            // (first same-key end after the on) cannot represent an overlap,
            // which used to silently re-pair the stationary note's end onto
            // the edited note's.
            if (ok) {
                doc.addNote(track, base + step * 90, 71, step * 4, 100); // S 90..94
                doc.addNote(track, base + step * 88, 70, step * 4, 100); // M 88..92
                DocNote m, s;
                // Tail kept: M transposed up onto S's head.
                if (!doc.findNote(track, base + step * 88, 70, &m)) {
                    fail("overlap-scenario notes not found");
                    ok = false;
                } else {
                    doc.moveNotes({m}, 0, 1);
                    mutateAndCheck("events unsorted after overlap transpose");
                    if (!doc.findNote(track, base + step * 88, 71, &m) || m.duration != step * 4 ||
                        !doc.findNote(track, base + step * 92, 71, &s) || s.duration != step * 2) {
                        fail("transpose onto a note's head did not keep its tail");
                        ok = false;
                    }
                }
                // Fully covered: M resized right across all of S removes it.
                if (ok) {
                    doc.resizeNotes({m}, step * 4); // M 88..96 covers S 92..94
                    mutateAndCheck("events unsorted after overlap resize");
                    if (!doc.findNote(track, base + step * 88, 71, &m) || m.duration != step * 8 ||
                        doc.findNote(track, base + step * 92, 71, &s)) {
                        fail("resize across a covered note did not remove it");
                        ok = false;
                    }
                }
                // Head kept: a note drawn over M's tail trims M back, and one
                // undo reverts the trim together with the add.
                if (ok) {
                    doc.addNote(track, base + step * 94, 71, step * 4, 100);
                    mutateAndCheck("events unsorted after overlapping addNote");
                    if (!doc.findNote(track, base + step * 88, 71, &m) || m.duration != step * 6 ||
                        !doc.findNote(track, base + step * 94, 71, &s) || s.duration != step * 4) {
                        fail("overlapping add did not trim the covered tail");
                        ok = false;
                    }
                }
                if (ok) {
                    doc.undoStack()->undo();
                    if (!doc.findNote(track, base + step * 88, 71, &m) || m.duration != step * 8 ||
                        doc.findNote(track, base + step * 94, 71, &s)) {
                        fail("overlap trim was not part of the edit's own undo");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
            }

            // Mergeable moves (keyboard transpose/nudge): consecutive
            // mergeable moveNotes of the same notes collapse into ONE undo
            // command that re-lands from the gesture's start — a neighbor
            // trimmed by a merely-passed-through overlap comes back — and
            // the merge stops at the stack's clean index (a save between
            // presses keeps its own command).
            if (ok) {
                doc.addNote(track, base + step * 100, 70, step * 4, 100); // S
                doc.addNote(track, base + step * 100, 69, step * 2, 100); // M
                const int countBefore = doc.undoStack()->count();
                DocNote m, s;
                if (!doc.findNote(track, base + step * 100, 69, &m)) {
                    fail("merge-scenario notes not found");
                    ok = false;
                }
                if (ok) {
                    doc.moveNotes({m}, 0, 1, true); // M onto S: S trimmed
                    if (!doc.findNote(track, base + step * 102, 70, &s) || s.duration != step * 2) {
                        fail("mergeable transpose did not trim the overlap");
                        ok = false;
                    }
                }
                if (ok) {
                    doc.findNote(track, base + step * 100, 70, &m); // re-resolve
                    doc.moveNotes({m}, 0, 1, true);                 // past S: merged, +2 total
                    if (doc.undoStack()->count() != countBefore + 1) {
                        fail("consecutive mergeable moves did not merge");
                        ok = false;
                    } else if (!doc.findNote(track, base + step * 100, 71, &m) ||
                               m.duration != step * 2 ||
                               !doc.findNote(track, base + step * 100, 70, &s) ||
                               s.duration != step * 4) {
                        fail("merged transpose did not restore the trimmed note");
                        ok = false;
                    }
                }
                if (ok) {
                    doc.undoStack()->undo();
                    if (!doc.findNote(track, base + step * 100, 69, &m) ||
                        !doc.findNote(track, base + step * 100, 70, &s) || s.duration != step * 4) {
                        fail("merged move undo did not restore the gesture start");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
                if (ok) {
                    doc.findNote(track, base + step * 100, 71, &m);
                    doc.undoStack()->setClean();
                    doc.moveNotes({m}, 0, 1, true);
                    if (doc.undoStack()->count() != countBefore + 2) {
                        fail("mergeable move merged across the clean index");
                        ok = false;
                    }
                }
            }

            // Batch pitch moves (moveNotesToPitches): Wave 2's per-note
            // destination transposes. Two notes of different keys move by
            // different amounts in ONE undo command; identities survive at
            // the destinations (findNote resolves them, durations and
            // velocities intact), one undo restores the pre-gesture MIDI
            // bytes and one redo re-lands the destinations. Mergeable
            // nudges collapse exactly like moveNotes: repeated consecutive
            // presses stay one undo gesture (the count grows by exactly one
            // in total) and one undo returns to the gesture start; an
            // inverse press (up then down) nets to the gesture start with
            // no extra undo entry. A collision with an unselected note trims
            // it exactly like the moveNotes overlap scenarios above, with
            // the trim part of the move's own undo command. A rejected
            // resolver (destKey outside 0-127, or mismatched list sizes)
            // returns false without pushing: no command, unchanged SMF.
            if (ok) {
                const uint64_t tA = base + step * 110;
                doc.addNote(track, tA, 115, step * 4, 100);            // A 115 -> 118 (+3)
                doc.addNote(track, tA + step * 20, 117, step * 2, 90); // B 117 -> 114 (-3)
                mutateAndCheck("events unsorted after batch-pitch adds");
                const int countBefore = doc.undoStack()->count();
                const QByteArray preMove = doc.smf().write();
                DocNote a, b;
                if (!doc.findNote(track, tA, 115, &a) ||
                    !doc.findNote(track, tA + step * 20, 117, &b)) {
                    fail("batch-pitch scenario notes not found");
                    ok = false;
                }
                // One command moves different pitches by different amounts.
                if (ok) {
                    if (!doc.moveNotesToPitches({a, b}, {uint8_t(118), uint8_t(114)}, 0)) {
                        fail("moveNotesToPitches rejected a valid batch move");
                        ok = false;
                    }
                    mutateAndCheck("events unsorted after moveNotesToPitches");
                    if (ok && doc.undoStack()->count() != countBefore + 1) {
                        fail("moveNotesToPitches was not a single undo command");
                        ok = false;
                    }
                    if (ok &&
                        (!doc.findNote(track, tA, 118, &a) || a.duration != step * 4 ||
                         a.velocity != 100 || doc.findNote(track, tA, 115, &a) ||
                         !doc.findNote(track, tA + step * 20, 114, &b) || b.duration != step * 2 ||
                         b.velocity != 90 || doc.findNote(track, tA + step * 20, 117, &b))) {
                        fail("batch pitch move did not land both destinations");
                        ok = false;
                    }
                }
                // Undo restores the original bytes and identities; redo
                // reproduces the destinations. (QUndoStack::count never
                // shrinks on undo, so the restore is proven by bytes and
                // resolved note identities, not by a count comparison.)
                if (ok) {
                    const QByteArray moved = doc.smf().write();
                    doc.undoStack()->undo();
                    if (doc.smf().write() != preMove) {
                        fail("moveNotesToPitches undo did not restore the original bytes");
                        ok = false;
                    } else if (!doc.findNote(track, tA, 115, &a) || a.duration != step * 4 ||
                               a.velocity != 100 || !doc.findNote(track, tA + step * 20, 117, &b) ||
                               b.duration != step * 2 || b.velocity != 90) {
                        fail("moveNotesToPitches undo did not restore bytes and identities");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                        if (ok && (doc.smf().write() != moved ||
                                   !doc.findNote(track, tA, 118, &a) || a.duration != step * 4 ||
                                   !doc.findNote(track, tA + step * 20, 114, &b) ||
                                   b.duration != step * 2)) {
                            fail("moveNotesToPitches redo did not reproduce the destinations");
                            ok = false;
                        }
                    }
                }
                // Repeated mergeable nudges stay ONE undo gesture: the count
                // grows by exactly one in total, and one undo returns the
                // notes to the gesture start.
                if (ok) {
                    const int countBefore = doc.undoStack()->count();
                    const QByteArray atStart = doc.smf().write();
                    if (!doc.findNote(track, tA, 118, &a) ||
                        !doc.findNote(track, tA + step * 20, 114, &b)) {
                        fail("merge-nudge notes not found");
                        ok = false;
                    }
                    if (ok) {
                        doc.moveNotesToPitches({a, b}, {uint8_t(119), uint8_t(115)}, 0, true);
                        if (!doc.findNote(track, tA, 119, &a) ||
                            !doc.findNote(track, tA + step * 20, 115, &b)) {
                            fail("first mergeable nudge did not land");
                            ok = false;
                        }
                    }
                    if (ok) {
                        doc.moveNotesToPitches({a, b}, {uint8_t(120), uint8_t(116)}, 0, true);
                        mutateAndCheck("events unsorted after merged pitch nudge");
                        if (doc.undoStack()->count() != countBefore + 1) {
                            fail("mergeable pitch nudges did not stay one undo gesture");
                            ok = false;
                        } else if (!doc.findNote(track, tA, 120, &a) ||
                                   !doc.findNote(track, tA + step * 20, 116, &b)) {
                            fail("merged pitch nudges did not reach the final pitch");
                            ok = false;
                        }
                    }
                    if (ok) {
                        doc.undoStack()->undo();
                        if (!doc.findNote(track, tA, 118, &a) ||
                            !doc.findNote(track, tA + step * 20, 114, &b) ||
                            doc.smf().write() != atStart) {
                            fail("one undo did not return to the nudge gesture start");
                            ok = false;
                        }
                    }
                }
                // Inverse merge: up then down collapses (no extra undo
                // entry) and one undo returns to the pre-gesture bytes. A
                // clean index marks the gesture boundary — without it Qt
                // merges the new press into the previous (undone) mergeable
                // command, exactly like MoveNotesCommand.
                if (ok) {
                    doc.undoStack()->setClean();
                    const QByteArray atStart = doc.smf().write();
                    if (!doc.findNote(track, tA, 118, &a) ||
                        !doc.findNote(track, tA + step * 20, 114, &b)) {
                        fail("inverse-nudge notes not found");
                        ok = false;
                    }
                    // Up nudge reuses the undone command's redo slot (its
                    // count is already counted); capture the post-push index
                    // as the gesture baseline.
                    if (ok) {
                        doc.moveNotesToPitches({a, b}, {uint8_t(119), uint8_t(115)}, 0, true);
                        if (!doc.findNote(track, tA, 119, &a) ||
                            !doc.findNote(track, tA + step * 20, 115, &b)) {
                            fail("up-nudge of the inverse gesture did not land");
                            ok = false;
                        }
                    }
                    // The down nudge must merge into the up nudge — it adds
                    // no command on top (the index is unchanged) — and net
                    // to the gesture start.
                    if (ok) {
                        const int afterUpIndex = doc.undoStack()->index();
                        doc.moveNotesToPitches({a, b}, {uint8_t(118), uint8_t(114)}, 0, true);
                        if (doc.undoStack()->index() != afterUpIndex) {
                            fail("inverse mergeable nudge did not collapse");
                            ok = false;
                        } else if (!doc.findNote(track, tA, 118, &a) ||
                                   !doc.findNote(track, tA + step * 20, 114, &b)) {
                            fail("collapsed inverse nudge did not net to the gesture start");
                            ok = false;
                        }
                    }
                    if (ok) {
                        doc.undoStack()->undo();
                        if (doc.smf().write() != atStart) {
                            fail("inverse-gesture undo did not return to the pre-gesture bytes");
                            ok = false;
                        }
                    }
                }
                // Collisions with unselected notes: a written note landing
                // on another note's span trims it (tail kept) or removes it
                // when fully covered, exactly like the moveNotes overlap
                // scenarios above, with the trim part of the move's own undo
                // command.
                if (ok) {
                    doc.addNote(track, base + step * 140, 119, step * 4, 100); // S 140..144
                    doc.addNote(track, base + step * 138, 118, step * 4, 100); // M 138..142
                    mutateAndCheck("events unsorted after collision adds");
                    DocNote m6, s6;
                    if (!doc.findNote(track, base + step * 138, 118, &m6) ||
                        !doc.findNote(track, base + step * 140, 119, &s6)) {
                        fail("collision-scenario notes not found");
                        ok = false;
                    }
                    // Tail kept: M pitch-moved up onto S's head.
                    if (ok) {
                        doc.moveNotesToPitches({m6}, {uint8_t(119)}, 0);
                        mutateAndCheck("events unsorted after pitch-move collision");
                        if (!doc.findNote(track, base + step * 138, 119, &m6) ||
                            m6.duration != step * 4 ||
                            !doc.findNote(track, base + step * 142, 119, &s6) ||
                            s6.duration != step * 2 ||
                            doc.findNote(track, base + step * 138, 118, &m6) ||
                            doc.findNote(track, base + step * 140, 119, &s6)) {
                            fail("pitch move onto a note's head did not keep its tail");
                            ok = false;
                        }
                    }
                    // One undo reverts the move together with its trim: both
                    // notes are back at their original keys and durations.
                    if (ok) {
                        doc.undoStack()->undo();
                        if (!doc.findNote(track, base + step * 138, 118, &m6) ||
                            m6.duration != step * 4 ||
                            !doc.findNote(track, base + step * 140, 119, &s6) ||
                            s6.duration != step * 4) {
                            fail("pitch-move trim was not part of the move's own undo");
                            ok = false;
                        } else {
                            doc.undoStack()->redo();
                        }
                    }
                    // Fully covered: M pitch-moved forward across all of S
                    // removes it.
                    if (ok) {
                        if (!doc.findNote(track, base + step * 138, 119, &m6)) {
                            fail("collision redo did not restore the moved note");
                            ok = false;
                        } else {
                            doc.moveNotesToPitches({m6}, {uint8_t(119)}, step * 2);
                            mutateAndCheck("events unsorted after pitch-move full cover");
                            if (!doc.findNote(track, base + step * 140, 119, &m6) ||
                                m6.duration != step * 4 ||
                                doc.findNote(track, base + step * 142, 119, &s6)) {
                                fail("pitch move across a covered note did not remove it");
                                ok = false;
                            }
                        }
                    }
                }
                // Rejected resolvers: a destKey outside 0-127 or mismatched
                // notes/dests sizes return false with no revision pushed and
                // no undo entry — the count is unchanged and the SMF stays
                // byte-identical.
                if (ok) {
                    const int countBefore = doc.undoStack()->count();
                    const QByteArray before = doc.smf().write();
                    DocNote x, y;
                    if (!doc.findNote(track, tA, 118, &x) ||
                        !doc.findNote(track, tA + step * 20, 114, &y)) {
                        fail("reject-scenario notes not found");
                        ok = false;
                    }
                    if (ok && doc.moveNotesToPitches({x}, {uint8_t(130)}, 0)) {
                        fail("moveNotesToPitches did not reject a dest above 127");
                        ok = false;
                    }
                    if (ok && doc.undoStack()->count() != countBefore) {
                        fail("rejected move above 127 pushed an undo command");
                        ok = false;
                    }
                    if (ok && doc.moveNotesToPitches({x}, {}, 0)) {
                        fail("moveNotesToPitches did not reject mismatched sizes");
                        ok = false;
                    }
                    if (ok && doc.moveNotesToPitches({}, {uint8_t(118)}, 0)) {
                        fail("moveNotesToPitches did not reject empty notes");
                        ok = false;
                    }
                    if (ok && doc.undoStack()->count() != countBefore) {
                        fail("rejected move pushed an undo command");
                        ok = false;
                    }
                    if (ok && (doc.smf().write() != before || !doc.findNote(track, tA, 118, &x) ||
                               !doc.findNote(track, tA + step * 20, 114, &y))) {
                        fail("rejected move changed the SMF");
                        ok = false;
                    }
                }
            }

            // Remove time range: in-range content vanishes,
            // later events shift left by the span, and the last in-range
            // automation point survives at the seam. ONE undoable command.
            if (ok) {
                doc.addNotes(track, {{base + step * 50, 60, step, 90},
                                     {base + step * 52, 62, step, 90},
                                     {base + step * 56, 64, step, 90}});
                doc.addLanePoint(track, 7, base + step * 51, 30);
                doc.addLanePoint(track, 7, base + step * 52, 40);
                SongDocument::TimeScope scope;
                scope.tracks = {track};
                if (!doc.removeTimeRange({base + step * 51, base + step * 54}, scope)) {
                    fail("removeTimeRange reported nothing to do");
                    ok = false;
                }
                mutateAndCheck("events unsorted after removeTimeRange");
                DocNote n;
                DocLanePoint p;
                if (ok && (!doc.findNote(track, base + step * 50, 60, &n) ||
                           doc.findNote(track, base + step * 52, 62, &n) ||
                           !doc.findNote(track, base + step * 53, 64, &n) ||
                           !doc.findLanePoint(track, 7, base + step * 51, &p) || p.value != 40)) {
                    fail("removeTimeRange produced wrong content");
                    ok = false;
                }
                if (ok) {
                    doc.undoStack()->undo();
                    if (!doc.findNote(track, base + step * 56, 64, &n) ||
                        !doc.findLanePoint(track, 7, base + step * 52, &p) || p.value != 40) {
                        fail("removeTimeRange was not a single undo command");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
            }

            // Whole-song remove: the globals travel too — a time signature
            // and a tempo change inside the range survive at the seam, later
            // notes shift, loop markers before the range stay put, and the
            // end-of-track ticks close the gap so the song gets shorter.
            if (ok) {
                const auto maxEnd = [&doc] {
                    uint64_t end = 0;
                    for (const SmfTrack &tr : doc.smf().tracks)
                        end = std::max(end, tr.endTick);
                    return end;
                };
                doc.setTimeSig(base + step * 62, 3, 2);
                doc.applyTempoEdit({{}, {tempoPoint(base + step * 63, 150)}});
                doc.addNotes(track, {{base + step * 66, 65, step, 90}});
                const uint64_t endBefore = maxEnd();
                const uint64_t loopStartBefore = doc.loopTick(false);
                SongDocument::TimeScope scope;
                scope.wholeSong = true;
                if (!doc.removeTimeRange({base + step * 61, base + step * 65}, scope)) {
                    fail("whole-song removeTimeRange reported nothing to do");
                    ok = false;
                }
                mutateAndCheck("events unsorted after whole-song removeTimeRange");
                DocNote n;
                bool sigAtSeam = false;
                for (const DocTimeSig &sig : doc.timeSigs()) {
                    if (sig.tick == base + step * 61 && sig.numerator == 3)
                        sigAtSeam = true;
                }
                if (ok &&
                    (!sigAtSeam || !containsTempoPoint(doc, tempoPoint(base + step * 61, 150)) ||
                     !doc.findNote(track, base + step * 62, 65, &n) ||
                     maxEnd() != endBefore - step * 4 || doc.loopTick(false) != loopStartBefore)) {
                    fail("whole-song removeTimeRange produced wrong content");
                    ok = false;
                }
                if (ok) {
                    doc.undoStack()->undo();
                    if (!doc.findNote(track, base + step * 66, 65, &n) || maxEnd() != endBefore) {
                        fail("whole-song removeTimeRange was not a single undo command");
                        ok = false;
                    } else {
                        doc.undoStack()->redo();
                    }
                }
            }

            // Voice ops: add, value-only modify (must not reorder within the
            // tick), move to a new tick, delete.
            if (ok) {
                doc.addLanePoint(track, DOC_CC_VOICE, base + step, 5);
                mutateAndCheck("events unsorted after voice add");
                DocLanePoint vc;
                if (!doc.findLanePoint(track, DOC_CC_VOICE, base + step, &vc) || vc.value != 5) {
                    fail("voice change not found after add");
                    ok = false;
                } else {
                    doc.moveLanePoints({{track, DOC_CC_VOICE, vc, vc.tick, 9}});
                    if (!doc.findLanePoint(track, DOC_CC_VOICE, base + step, &vc) ||
                        vc.value != 9) {
                        fail("voice value edit not applied");
                        ok = false;
                    } else {
                        doc.moveLanePoints({{track, DOC_CC_VOICE, vc, base + step * 6, 9}});
                        mutateAndCheck("events unsorted after voice move");
                        if (!doc.findLanePoint(track, DOC_CC_VOICE, base + step * 6, &vc)) {
                            fail("voice change not found after move");
                            ok = false;
                        } else {
                            doc.deleteLanePoints(track, DOC_CC_VOICE, {vc});
                        }
                    }
                }
            }

            // Automation ops on the volume lane and pitch bend, plus tempo.
            if (ok) {
                doc.addLanePoint(track, 7, base + step * 2, 100);
                doc.addLanePoint(track, DOC_CC_BEND, base + step * 3, -1024);
                const TempoPoint tempo = tempoPoint(base + step * 4, 150);
                doc.applyTempoEdit({{}, {tempo}});
                mutateAndCheck("events unsorted after addLanePoint");
                DocLanePoint pt;
                if (!doc.findLanePoint(track, 7, base + step * 2, &pt) || pt.value != 100) {
                    fail("lane point not found after add");
                    ok = false;
                } else {
                    doc.moveLanePoints({{track, 7, pt, base + step * 5, 90}});
                    mutateAndCheck("events unsorted after moveLanePoints");
                    if (!doc.findLanePoint(track, 7, base + step * 5, &pt) || pt.value != 90) {
                        fail("lane point not found after move");
                        ok = false;
                    } else {
                        std::vector<DocLanePoint> doomed{pt};
                        DocLanePoint bendPt;
                        if (doc.findLanePoint(track, DOC_CC_BEND, base + step * 3, &bendPt))
                            doc.deleteLanePoints(track, DOC_CC_BEND, {bendPt});
                        doc.applyTempoEdit({{tempo}, {}});
                        // Re-resolve: the deletes above shifted indices.
                        if (doc.findLanePoint(track, 7, base + step * 5, &pt))
                            doc.deleteLanePoints(track, 7, {pt});
                    }
                }
            }
        }

        // Track ops: create a track (seeded with its voice), edit on it,
        // delete it again.
        if (ok && doc.canAddTrack()) {
            const int newTrack = doc.addTrack(7);
            if (newTrack < 0) {
                fail("addTrack returned no track with canAddTrack true");
                ok = false;
            } else {
                mutateAndCheck("events unsorted after addTrack");
                const auto seed = doc.lanePoints(newTrack, DOC_CC_VOICE);
                if (ok && (seed.empty() || seed.front().tick != 0 || seed.front().value != 7)) {
                    fail("new track missing its seed voice");
                    ok = false;
                }
                DocNote note;
                if (ok) {
                    doc.addNote(newTrack, base, 72, step * 4, 100);
                    if (!doc.findNote(newTrack, base, 72, &note)) {
                        fail("note on new track not found");
                        ok = false;
                    }
                }
                if (ok) {
                    doc.deleteTrack(newTrack);
                    mutateAndCheck("events unsorted after deleteTrack");
                    if (doc.findNote(newTrack, base, 72, &note)) {
                        fail("deleted track still has its note");
                        ok = false;
                    }
                }
            }
        }

        // Duplicating a song track: the copy lands on a fresh engine slot
        // carrying the same notes as the source.
        if (ok && track >= 0 && doc.canAddTrack()) {
            const auto srcNotes = doc.notesForTrack(track);
            const int copy = doc.duplicateTrack(track);
            mutateAndCheck("events unsorted after duplicateTrack");
            if (copy < 0) {
                fail("duplicateTrack returned no track with canAddTrack true");
                ok = false;
            } else if (copy == track) {
                fail("duplicateTrack returned the source track");
                ok = false;
            } else if (ok) {
                const auto copyNotes = doc.notesForTrack(copy);
                bool same = copyNotes.size() == srcNotes.size();
                for (size_t i = 0; same && i < copyNotes.size(); i++) {
                    same = copyNotes[i].tick == srcNotes[i].tick &&
                           copyNotes[i].key == srcNotes[i].key &&
                           copyNotes[i].duration == srcNotes[i].duration &&
                           copyNotes[i].velocity == srcNotes[i].velocity;
                }
                if (!same) {
                    fail("duplicated track's notes differ from the source");
                    ok = false;
                } else {
                    doc.deleteTrack(copy);
                    mutateAndCheck("events unsorted after deleting the duplicate");
                }
            }
        }

        // Reordering tracks: the chunks move with their events and channel
        // bytes untouched, while typed Tempo and chunk-0 time signatures and
        // loop markers remain global.
        if (ok && doc.engineTrackCount() >= 2 && track >= 0) {
            doc.applyTempoEdit({{}, {tempoPoint(base + step * 110, 145)}});
            doc.setTimeSig(base + step * 112, 5, 2);
            const uint64_t loopStartBefore = doc.loopTick(false);
            const uint64_t loopEndBefore = doc.loopTick(true);
            const auto srcNotes = doc.notesForTrack(0);
            const uint8_t srcChannel = doc.channelFor(0);
            const int last = doc.engineTrackCount() - 1;
            const int countBefore = doc.undoStack()->count();
            doc.moveTrack(0, 0); // no-op guard
            if (doc.undoStack()->count() != countBefore) {
                fail("moveTrack onto itself pushed a command");
                ok = false;
            }
            auto seqChunkHas = [&doc](uint8_t metaType, uint64_t tick) {
                for (const SmfEvent &ev : doc.smf().tracks[0].events) {
                    if (ev.isMeta() && ev.metaType == metaType && ev.tick == tick)
                        return true;
                }
                return false;
            };
            auto notesMatch = [&doc](int engineTrack, const std::vector<DocNote> &want) {
                const auto got = doc.notesForTrack(engineTrack);
                if (got.size() != want.size())
                    return false;
                for (size_t i = 0; i < got.size(); i++) {
                    if (got[i].tick != want[i].tick || got[i].key != want[i].key ||
                        got[i].duration != want[i].duration || got[i].velocity != want[i].velocity)
                        return false;
                }
                return true;
            };
            if (ok) {
                doc.moveTrack(0, last);
                mutateAndCheck("events unsorted after moveTrack");
            }
            if (ok && doc.undoStack()->count() != countBefore + 1) {
                fail("moveTrack was not a single undo command");
                ok = false;
            }
            if (ok && (!notesMatch(last, srcNotes) || doc.channelFor(last) != srcChannel)) {
                fail("moved track's notes or channel changed");
                ok = false;
            }
            if (ok && (!containsTempoPoint(doc, tempoPoint(base + step * 110, 145)) ||
                       !seqChunkHas(0x58, base + step * 112))) {
                fail("global tempo or sequence metadata changed across the move");
                ok = false;
            }
            if (ok &&
                (doc.loopTick(false) != loopStartBefore || doc.loopTick(true) != loopEndBefore)) {
                fail("moveTrack lost the loop markers");
                ok = false;
            }
            if (ok) {
                doc.undoStack()->undo();
                if (!notesMatch(0, srcNotes)) {
                    fail("moveTrack undo did not restore the track order");
                    ok = false;
                } else {
                    doc.undoStack()->redo();
                }
            }
            if (ok) {
                doc.moveTrack(last, 0); // and back again
                mutateAndCheck("events unsorted after moveTrack back");
                if (!notesMatch(0, srcNotes) ||
                    !containsTempoPoint(doc, tempoPoint(base + step * 110, 145)) ||
                    !seqChunkHas(0x58, base + step * 112)) {
                    fail("moving the track back did not restore its slot");
                    ok = false;
                }
            }
        }

        // Reordering must not confuse chunk-0 metas that only LOOK like loop
        // markers: a first-0x03 name of "[" is the track's name and travels
        // with its chunk (findLoopMarkerEvent skips it; imported files can
        // carry such names even though renameTrack refuses them), while the
        // combined "][" marker mid2agb reads stays with chunk 0.
        if (ok && doc.engineTrackCount() >= 2 && doc.smfTrackFor(0) == 0) {
            const int last = doc.engineTrackCount() - 1;
            const int indexBefore = doc.undoStack()->index();
            const uint64_t loopStartBefore = doc.loopTick(false);
            const uint64_t loopEndBefore = doc.loopTick(true);
            doc.renameTrack(0, QString()); // the "[" below must be the first 0x03
            SmfEvent name;
            name.tick = 0;
            name.status = 0xFF;
            name.metaType = 0x03;
            name.blob = QByteArrayLiteral("[");
            doc.insertRawEvent(0, name);
            SmfEvent marker;
            marker.tick = base;
            marker.status = 0xFF;
            marker.metaType = 0x06;
            marker.blob = QByteArrayLiteral("][");
            doc.insertRawEvent(0, marker);
            doc.moveTrack(0, last);
            mutateAndCheck("events unsorted after marker-name moveTrack");
            if (ok && doc.trackName(last) != QStringLiteral("[")) {
                fail("a '['-named track lost its name in the move");
                ok = false;
            }
            if (ok &&
                (doc.loopTick(false) != loopStartBefore || doc.loopTick(true) != loopEndBefore)) {
                fail("a '[' track name was misread as a loop marker");
                ok = false;
            }
            bool combinedStayed = false;
            for (const SmfEvent &ev : doc.smf().tracks[0].events) {
                if (ev.isMeta() && ev.metaType == 0x06 && ev.blob == "][")
                    combinedStayed = true;
            }
            if (ok && !combinedStayed) {
                fail("the '][' marker left chunk 0 in the move");
                ok = false;
            }
            while (doc.undoStack()->index() > indexBefore)
                doc.undoStack()->undo();
            mutateAndCheck("events unsorted after marker-name undo");
        }

        // Deleting an original track must not lose the loop markers, even
        // when they live in the removed chunk (they get rescued into the seq
        // chunk). Undone right away so the loop/cfg script below still runs
        // against the full song.
        if (ok && track >= 0) {
            const uint64_t loopStartBefore = doc.loopTick(false);
            const uint64_t loopEndBefore = doc.loopTick(true);
            doc.deleteTrack(track);
            mutateAndCheck("events unsorted after deleteTrack of a song track");
            if (ok &&
                (doc.loopTick(false) != loopStartBefore || doc.loopTick(true) != loopEndBefore)) {
                fail("deleteTrack lost the loop markers");
                ok = false;
            }
            doc.undoStack()->undo();
        }

        // Track rename: set, no-op guard (trimmed match pushes nothing),
        // clear, and undo back through the chunk's Track Name meta (0x03).
        if (ok && track >= 0) {
            auto chunkNameCount = [&doc, track] {
                const int smfTrack = doc.smfTrackFor(track);
                int count = 0;
                SmfChannelPrefix prefix;
                for (const SmfEvent &event : doc.smf().tracks[smfTrack].events) {
                    prefix.observe(event);
                    if (event.isMeta() && event.metaType == 0x03 && prefix.channel < 0)
                        count++;
                }
                return count;
            };
            doc.renameTrack(track, QStringLiteral("editcheck name"));
            mutateAndCheck("events unsorted after renameTrack");
            if (ok && (doc.trackName(track) != QStringLiteral("editcheck name") ||
                       chunkNameCount() != 1)) {
                fail("rename did not produce one authoritative track name");
                ok = false;
            }
            // The header paints from the playable projection, not the raw
            // SMF — the authoritative meta must land where MidiTimeline's
            // reader finds it.
            if (ok) {
                const auto timeline = doc.buildTimeline(48000.0);
                if (!timeline || timeline->tracks[track].name != QStringLiteral("editcheck name")) {
                    fail("renamed track not visible in the timeline projection");
                    ok = false;
                }
            }
            if (ok) {
                const int count = doc.undoStack()->count();
                doc.renameTrack(track, QStringLiteral("  editcheck name  "));
                if (doc.undoStack()->count() != count) {
                    fail("no-op rename pushed an undo command");
                    ok = false;
                }
            }
            if (ok) {
                // mid2agb reads any text meta whose whole text is a marker
                // as a loop/label command; those names must be refused.
                const int count = doc.undoStack()->count();
                doc.renameTrack(track, QStringLiteral("["));
                doc.renameTrack(track, QStringLiteral(" ][ "));
                if (doc.undoStack()->count() != count ||
                    doc.trackName(track) != QStringLiteral("editcheck name")) {
                    fail("loop-marker name was not refused");
                    ok = false;
                }
            }
            if (ok) {
                doc.renameTrack(track, QString());
                if (!doc.trackName(track).isEmpty() || chunkNameCount() != 0) {
                    fail("empty rename did not clear all track names");
                    ok = false;
                }
            }
            if (ok) {
                doc.undoStack()->undo();
                if (doc.trackName(track) != QStringLiteral("editcheck name")) {
                    fail("rename undo did not restore the name");
                    ok = false;
                } else {
                    doc.undoStack()->redo();
                }
            }
        }

        // Time signatures: create, modify in place, move, delete.
        if (ok) {
            auto findSig = [&doc](uint64_t tick, DocTimeSig *out) {
                for (const DocTimeSig &sig : doc.timeSigs()) {
                    if (sig.tick == tick) {
                        *out = sig;
                        return true;
                    }
                }
                return false;
            };
            const size_t sigsBefore = doc.timeSigs().size();
            doc.setTimeSig(base, 3, 3); // 3/8
            mutateAndCheck("events unsorted after setTimeSig");
            DocTimeSig sig;
            if (ok && (!findSig(base, &sig) || sig.numerator != 3 || sig.denomPow2 != 3)) {
                fail("time signature not found after set");
                ok = false;
            }
            if (ok) {
                doc.setTimeSig(base, 7, 2); // 7/4, replacing in place
                if (!findSig(base, &sig) || sig.numerator != 7 || sig.denomPow2 != 2 ||
                    doc.timeSigs().size() != sigsBefore + 1) {
                    fail("time signature edit did not replace in place");
                    ok = false;
                }
            }
            if (ok) {
                doc.moveTimeSig(base, base + step * 4);
                mutateAndCheck("events unsorted after moveTimeSig");
                if (findSig(base, &sig) || !findSig(base + step * 4, &sig) || sig.numerator != 7) {
                    fail("time signature not moved");
                    ok = false;
                }
            }
            if (ok) {
                doc.deleteTimeSig(base + step * 4);
                if (findSig(base + step * 4, &sig)) {
                    fail("time signature not deleted");
                    ok = false;
                }
            }
        }

        // Loop markers: move an existing one / create where absent, and cfg.
        const uint64_t loopStart = doc.loopTick(false);
        doc.setLoopTick(false, loopStart == UINT64_MAX ? 0 : int64_t(loopStart + step));
        mutateAndCheck("events unsorted after setLoopTick");
        SongCfg cfg = doc.cfg();
        cfg.masterVolume = cfg.masterVolume == 80 ? 90 : 80;
        doc.setCfg(cfg);

        // Undo everything: the document must be byte-identical to the load.
        while (doc.undoStack()->canUndo())
            doc.undoStack()->undo();
        if (doc.smf().write() != baseline)
            fail("undo-all did not restore the original bytes");
        else if (doc.cfg().masterVolume != song.cfg.masterVolume)
            fail("undo-all did not restore song settings");
        else {
            // Redo everything, then undo again: redo must be deterministic.
            while (doc.undoStack()->canRedo())
                doc.undoStack()->redo();
            const QByteArray redone = doc.smf().write();
            while (doc.undoStack()->canUndo())
                doc.undoStack()->undo();
            if (doc.smf().write() != baseline)
                fail("undo after redo did not restore the original bytes");
            else if (redone == baseline && track >= 0)
                fail("redo-all produced no change (edits were lost)");
        }

        checked++;
    }

    // Format 0 is coerced to format 1 at load (convertToFormat1): the
    // single chunk splits into a conductor chunk 0 carrying every
    // non-channel meta, then one chunk per used channel in ascending
    // channel order — the order mid2agb emits agb tracks for a format-0
    // file, so the build output is unchanged (--roundtrip proves that end
    // to end). Channel-Prefix names (0x20 + 0x03) become ordinary chunk
    // names. Synthetic file — decomp projects are format 1 in practice.
    {
        auto fail0 = [&](const char *what) {
            std::fprintf(stderr, "editcheck: FAIL format0-convert: %s\n", what);
            failures++;
        };
        SmfFile smf;
        smf.format = 0;
        smf.division = 24;
        SmfTrack tr;
        auto chEvent = [](uint8_t status, uint64_t tick, uint8_t d0, uint8_t d1) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = status;
            ev.data0 = d0;
            ev.data1 = d1;
            return ev;
        };
        auto meta = [](uint64_t tick, uint8_t type, QByteArray blob) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = 0xFF;
            ev.metaType = type;
            ev.blob = std::move(blob);
            return ev;
        };
        // Global metas, a prefixed per-channel name, and notes on the
        // non-contiguous channels 1, 4, 7 (so slot order = channel order is
        // visible). The unprefixed 0x03 precedes the prefix — after a
        // channel prefix, names are scoped until the next channel event.
        // Three preservation cases ride along: a prefixed non-name text
        // meta (0x04 "Gtr" → travels to channel 4's chunk), a prefixed
        // MARKER-text 0x03 (":" → stays in the conductor chunk with a
        // prefix, where mid2agb reads markers), and a prefixed name on the
        // silent channel 9 ("Ambient" → a name-only chunk rather than
        // silent data loss).
        tr.events.push_back(meta(0, 0x51, QByteArray("\x07\xA1\x20", 3))); // 120 BPM
        tr.events.push_back(meta(0, 0x03, QByteArrayLiteral("Song")));
        tr.events.push_back(meta(0, 0x20, QByteArray(1, char(4))));
        tr.events.push_back(meta(0, 0x03, QByteArrayLiteral("Lead")));
        tr.events.push_back(meta(0, 0x04, QByteArrayLiteral("Gtr")));
        tr.events.push_back(chEvent(0x91, 0, 60, 100));
        tr.events.push_back(chEvent(0x94, 0, 64, 100));
        tr.events.push_back(chEvent(0x97, 0, 67, 100));
        tr.events.push_back(meta(12, 0x06, QByteArrayLiteral("[")));
        tr.events.push_back(meta(12, 0x20, QByteArray(1, char(7))));
        tr.events.push_back(meta(12, 0x03, QByteArrayLiteral(":")));
        tr.events.push_back(chEvent(0x81, 24, 60, 0));
        tr.events.push_back(chEvent(0x84, 24, 64, 0));
        tr.events.push_back(chEvent(0x87, 24, 67, 0));
        tr.events.push_back(meta(36, 0x06, QByteArrayLiteral("]")));
        tr.events.push_back(meta(36, 0x20, QByteArray(1, char(9))));
        tr.events.push_back(meta(36, 0x03, QByteArrayLiteral("Ambient")));
        tr.endTick = 48;
        smf.tracks.push_back(tr);
        const QByteArray originalBytes = smf.write();

        QTemporaryDir tmp;
        const QString midPath = tmp.path() + QStringLiteral("/format0.mid");
        QString werror;
        SongInfo info;
        info.label = QStringLiteral("format0");
        info.midPath = midPath;
        info.hasMid = true;
        SongDocument doc;
        bool ok = tmp.isValid() && smf.writeFile(midPath, &werror) && doc.load(info, &werror);
        if (!ok)
            fail0("could not write/load the synthetic format-0 file");
        if (ok && (doc.smf().format != 1 || !doc.smf().wasFormat0 || doc.smf().tracks.size() != 5 ||
                   doc.engineTrackCount() != 3)) {
            fail0("load did not split into conductor + one chunk per channel");
            ok = false;
        }
        if (ok && (doc.channelFor(0) != 1 || doc.channelFor(1) != 4 || doc.channelFor(2) != 7 ||
                   doc.smfTrackFor(0) != 1)) {
            fail0("converted chunks not in ascending channel order");
            ok = false;
        }
        if (ok) {
            const auto note = [&doc](int track) {
                const auto notes = doc.notesForTrack(track);
                return notes.size() == 1 && notes[0].duration == 24 ? int(notes[0].key) : -1;
            };
            if (note(0) != 60 || note(1) != 64 || note(2) != 67) {
                fail0("notes did not land on their channel's chunk");
                ok = false;
            }
        }
        if (ok && (doc.trackName(1) != QStringLiteral("Lead") || !doc.trackName(0).isEmpty() ||
                   !doc.trackName(2).isEmpty())) {
            fail0("the prefixed name did not become its channel chunk's name");
            ok = false;
        }
        if (ok) {
            auto hasMeta = [](const SmfTrack &track, uint8_t type, const char *text) {
                for (const SmfEvent &ev : track.events)
                    if (ev.isMeta() && ev.metaType == type && ev.blob == text)
                        return true;
                return false;
            };
            const auto &chunks = doc.smf().tracks;
            // Chunk layout: 0 conductor, 1..3 channels 1/4/7, 4 the
            // name-only channel-9 chunk.
            if (!hasMeta(chunks[2], 0x04, "Gtr")) {
                fail0("prefixed instrument-name meta did not travel to its channel chunk");
                ok = false;
            }
            if (ok && (!hasMeta(chunks[0], 0x03, ":") || hasMeta(chunks[3], 0x03, ":"))) {
                fail0("prefixed marker-text meta did not stay in the conductor chunk");
                ok = false;
            }
            if (ok) {
                // ...and it kept a prefix, so no reader mistakes it for the
                // conductor's name.
                bool prefixedMarker = false;
                const auto &evs = chunks[0].events;
                for (size_t i = 1; i < evs.size(); i++) {
                    if (evs[i].isMeta() && evs[i].metaType == 0x03 && evs[i].blob == ":" &&
                        evs[i - 1].isMeta() && evs[i - 1].metaType == 0x20)
                        prefixedMarker = true;
                }
                if (!prefixedMarker) {
                    fail0("the conductor's marker-text meta lost its prefix");
                    ok = false;
                }
            }
            if (ok && !hasMeta(chunks[4], 0x03, "Ambient")) {
                fail0("prefixed name on a silent channel was lost (no name-only chunk)");
                ok = false;
            }
            if (ok) {
                for (const SmfEvent &ev : chunks[4].events) {
                    if (ev.isChannel()) {
                        fail0("the name-only chunk grew channel events");
                        ok = false;
                    }
                }
            }
        }
        if (ok) {
            // Prefixes are rewritten into chunk structure everywhere except
            // the conductor's re-prefixed marker pair (the ":" case above).
            for (size_t t = 0; t < doc.smf().tracks.size(); t++) {
                const SmfTrack &track = doc.smf().tracks[t];
                for (const SmfEvent &ev : track.events) {
                    if (t > 0 && ev.isMeta() && ev.metaType == 0x20) {
                        fail0("a Channel Prefix meta survived in a channel chunk");
                        ok = false;
                    }
                }
                if (track.endTick != 48) {
                    fail0("a converted chunk lost the end-of-track tick");
                    ok = false;
                }
            }
            for (const SmfEvent &ev : doc.smf().tracks[0].events) {
                if (ev.isChannel()) {
                    fail0("a channel event landed in the conductor chunk");
                    ok = false;
                }
            }
        }
        if (ok && (doc.loopTick(false) != 12 || doc.loopTick(true) != 36 ||
                   doc.tempoPoints() != std::vector<TempoPoint>{tempoPoint(0, 120)})) {
            fail0("seq globals did not stay readable in chunk 0");
            ok = false;
        }
        if (ok) {
            const auto timeline = doc.buildTimeline(48000.0);
            if (!timeline || timeline->usedTrackCount != 3 ||
                timeline->tracks[1].name != QStringLiteral("Lead") ||
                timeline->loopStartTick != 12) {
                fail0("conversion not reflected in the timeline projection");
                ok = false;
            }
        }
        if (ok && !tracksSorted(doc.smf())) {
            fail0("events unsorted after conversion");
            ok = false;
        }
        const QByteArray convertedLive = ok ? doc.smf().write() : QByteArray();
        QByteArray convertedSerialized;
        if (ok) {
            SmfFile saved;
            if (!doc.save(&werror) || !SmfFile::readFile(midPath, &saved, &werror)) {
                fail0("save did not persist the converted SMF");
                ok = false;
            } else {
                convertedSerialized = saved.write();
                bool tempoValid = true;
                std::vector<TempoPoint> savedTempo;
                bool tempoFirst = true;
                bool tempoOutsideSeq = false;
                for (size_t track = 0; track < saved.tracks.size(); track++) {
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
                        if (track != 0)
                            tempoOutsideSeq = true;
                        if (nonTempoAtTick)
                            tempoFirst = false;
                        if (event.blob.size() != 3) {
                            tempoValid = false;
                            continue;
                        }
                        const auto *bytes =
                            reinterpret_cast<const uint8_t *>(event.blob.constData());
                        savedTempo.push_back({event.tick, (uint32_t(bytes[0]) << 16) |
                                                              (uint32_t(bytes[1]) << 8) |
                                                              bytes[2]});
                    }
                }
                auto nonTempoSaved = saved;
                for (SmfTrack &track : nonTempoSaved.tracks) {
                    std::vector<SmfEvent> events;
                    events.reserve(track.events.size());
                    for (const SmfEvent &event : track.events)
                        if (!isTempoMeta(event))
                            events.push_back(event);
                    track.events = std::move(events);
                }
                const auto hasLiveTempo = [&doc] {
                    for (const SmfTrack &track : doc.smf().tracks)
                        for (const SmfEvent &event : track.events)
                            if (isTempoMeta(event))
                                return true;
                    return false;
                };
                if (nonTempoSaved.write() != convertedLive) {
                    fail0("save changed the converted non-tempo structure");
                    ok = false;
                } else if (tempoOutsideSeq || !tempoFirst || !tempoValid ||
                           savedTempo != doc.tempoPoints()) {
                    fail0("save did not serialize typed tempo points tempo-first in chunk 0");
                    ok = false;
                } else if (hasLiveTempo()) {
                    fail0("save leaked tempo metas into the live SMF");
                    ok = false;
                }
            }
        }
        if (ok) {
            // SmfFile::read is the conversion choke point: raw re-reading
            // the original bytes yields the serialized converted form,
            // including its FF51 tempo event. Converting that already
            // converted form is a no-op (fixed point).
            SmfFile redo;
            QString rerror;
            if (!SmfFile::read(originalBytes, &redo, &rerror)) {
                fail0("could not re-read the original bytes");
                ok = false;
            } else {
                if (!redo.wasFormat0 || redo.write() != convertedSerialized) {
                    fail0("read() did not coerce deterministically");
                    ok = false;
                }
                convertToFormat1(&redo);
                if (ok && redo.write() != convertedSerialized) {
                    fail0("conversion of a converted file is not a no-op");
                    ok = false;
                }
            }
        }
        if (ok) {
            // The editing layer runs on the converted shape: undo-all
            // restores the tempo-free converted baseline, not the format-0 bytes.
            doc.renameTrack(0, QStringLiteral("Bass"));
            doc.moveTrack(0, 2);
            if (doc.trackName(2) != QStringLiteral("Bass")) {
                fail0("edits after conversion did not behave as format 1");
                ok = false;
            }
            while (doc.undoStack()->canUndo())
                doc.undoStack()->undo();
            if (ok && doc.smf().write() != convertedLive)
                fail0("undo-all did not restore the converted baseline");
        }
    }

    // A PREFIXED 0x03 carrying marker text has no name position (a chunk's
    // name is its first unprefixed 0x03), so every classifier
    // (MidiTimeline::build, findLoopMarkerEvent, trackNameLoc) reads it as
    // a marker — mid2agb's rule: a foreign format-1 file whose chunk opens
    // with a prefixed 0x03 "[" has a loop the playback timeline, the loop
    // UI, and the compiled ROM all agree on, and renaming the track edits
    // the real name meta, never the marker.
    {
        auto failM = [&](const char *what) {
            std::fprintf(stderr, "editcheck: FAIL marker-vs-name: %s\n", what);
            failures++;
        };
        auto chEvent = [](uint8_t status, uint64_t tick, uint8_t d0, uint8_t d1) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = status;
            ev.data0 = d0;
            ev.data1 = d1;
            return ev;
        };
        auto meta = [](uint64_t tick, uint8_t type, QByteArray blob) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = 0xFF;
            ev.metaType = type;
            ev.blob = std::move(blob);
            return ev;
        };
        SmfFile smf;
        smf.format = 1;
        smf.division = 24;
        SmfTrack tr;
        tr.events.push_back(meta(0, 0x20, QByteArray(1, char(0))));
        tr.events.push_back(meta(0, 0x03, QByteArrayLiteral("[")));
        tr.events.push_back(chEvent(0x90, 0, 60, 100)); // clears the prefix
        tr.events.push_back(meta(0, 0x03, QByteArrayLiteral("Real")));
        tr.events.push_back(chEvent(0x80, 24, 60, 0));
        tr.endTick = 24;
        smf.tracks.push_back(tr);

        QTemporaryDir tmp;
        const QString midPath = tmp.path() + QStringLiteral("/marker.mid");
        QString werror;
        SongInfo info;
        info.label = QStringLiteral("marker");
        info.midPath = midPath;
        info.hasMid = true;
        SongDocument doc;
        bool ok = tmp.isValid() && smf.writeFile(midPath, &werror) && doc.load(info, &werror);
        if (!ok)
            failM("could not write/load the synthetic file");
        if (ok && doc.trackName(0) != QStringLiteral("Real")) {
            failM("marker-text 0x03 was mistaken for the track name");
            ok = false;
        }
        if (ok && doc.loopTick(false) != 0) {
            failM("the loop UI did not see the prefixed marker");
            ok = false;
        }
        if (ok) {
            const auto timeline = doc.buildTimeline(48000.0);
            if (!timeline || timeline->loopStartTick != 0) {
                failM("playback did not see the prefixed marker (build/UI disagree)");
                ok = false;
            }
        }
        if (ok) {
            doc.renameTrack(0, QStringLiteral("Renamed"));
            if (doc.trackName(0) != QStringLiteral("Renamed") || doc.loopTick(false) != 0) {
                failM("rename clobbered the loop marker instead of the name");
            }
        }
    }

    // Same-tick duplicate setters (a foreign file's repeated channel-init
    // block): the loader preserves them — sanitizing is the import wizard's
    // job — but every editing surface resolves the run LAST-wins, matching
    // playback, and writing onto an occupied tick replaces what sits there
    // instead of stacking another duplicate. Undo restores the duplicates.
    {
        auto failD = [&](const char *what) {
            std::fprintf(stderr, "editcheck: FAIL same-tick-dup: %s\n", what);
            failures++;
        };
        auto chEvent = [](uint8_t status, uint64_t tick, uint8_t d0, uint8_t d1) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = status;
            ev.data0 = d0;
            ev.data1 = d1;
            return ev;
        };
        auto meta = [](uint64_t tick, uint8_t type, QByteArray blob) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = 0xFF;
            ev.metaType = type;
            ev.blob = std::move(blob);
            return ev;
        };
        const auto tempoMeta = [&meta](uint64_t tick, uint32_t microsecondsPerQuarterNote) {
            QByteArray blob(3, '\0');
            blob[0] = char((microsecondsPerQuarterNote >> 16) & 0xFF);
            blob[1] = char((microsecondsPerQuarterNote >> 8) & 0xFF);
            blob[2] = char(microsecondsPerQuarterNote & 0xFF);
            return meta(tick, 0x51, std::move(blob));
        };
        const TempoPoint slowTempo = tempoPoint(24, 20);
        const TempoPoint inRangeTempo = tempoPoint(48, 150);
        const TempoPoint fastTempo = tempoPoint(72, 255);
        const TempoPoint exactTempo{96, 375'001};
        const std::vector<TempoPoint> expectedTempo{slowTempo, inRangeTempo, fastTempo, exactTempo};
        SmfFile smf;
        smf.format = 1;
        smf.division = 24;
        SmfTrack conductor;
        conductor.events.push_back(meta(0, 0x01, QByteArrayLiteral("conductor")));
        conductor.events.push_back(tempoMeta(24, 6'000'000)); // 10 BPM, clamps to 20
        conductor.events.push_back(tempoMeta(48, tempoPoint(48, 120).microsecondsPerQuarterNote));
        conductor.events.push_back(tempoMeta(48, inRangeTempo.microsecondsPerQuarterNote));
        conductor.events.push_back(meta(48, 0x01, QByteArrayLiteral("shared tick")));
        conductor.events.push_back(tempoMeta(72, 200'000)); // 300 BPM, clamps to 255
        conductor.events.push_back(tempoMeta(96, exactTempo.microsecondsPerQuarterNote));
        conductor.endTick = 120;
        smf.tracks.push_back(conductor);
        SmfTrack ch0;
        ch0.events.push_back(chEvent(0xC0, 0, 5, 0));
        ch0.events.push_back(chEvent(0xB0, 0, 7, 100));
        ch0.events.push_back(chEvent(0xC0, 0, 9, 0));
        ch0.events.push_back(chEvent(0xB0, 0, 7, 80));
        ch0.events.push_back(chEvent(0x90, 0, 60, 100));
        ch0.events.push_back(meta(48, 0x51, QByteArray("\x09\x27\xC0", 3)));
        ch0.events.push_back(chEvent(0x80, 96, 60, 0));
        ch0.endTick = 96;
        smf.tracks.push_back(ch0);

        QTemporaryDir tmp;
        const QString midPath = tmp.path() + QStringLiteral("/dups.mid");
        QString werror;
        SongInfo info;
        info.label = QStringLiteral("dups");
        info.midPath = midPath;
        info.hasMid = true;
        SongDocument doc;
        bool ok = tmp.isValid() && smf.writeFile(midPath, &werror) && doc.load(info, &werror);
        if (!ok)
            failD("could not write/load the synthetic file");
        int changedSignals = 0;
        QObject::connect(&doc, &SongDocument::documentChanged,
                         [&changedSignals] { changedSignals++; });
        const QByteArray baseline = ok ? doc.smf().write() : QByteArray();
        const auto hasLiveTempoMeta = [&doc] {
            for (const SmfTrack &track : doc.smf().tracks) {
                for (const SmfEvent &event : track.events) {
                    if (isTempoMeta(event))
                        return true;
                }
            }
            return false;
        };
        const auto ccPointsAt = [&doc](uint8_t cc, uint64_t tick) {
            std::vector<DocLanePoint> at;
            for (const DocLanePoint &pt : doc.lanePoints(0, cc)) {
                if (pt.tick == tick)
                    at.push_back(pt);
            }
            return at;
        };
        if (ok && (doc.lanePoints(0, DOC_CC_VOICE).size() != 2 || ccPointsAt(7, 0).size() != 2)) {
            failD("the loader no longer preserves same-tick duplicates");
            ok = false;
        }
        DocLanePoint pt;
        if (ok && (!doc.findLanePoint(0, 7, 0, &pt) || pt.value != 80)) {
            failD("findLanePoint did not return the last CC at the tick");
            ok = false;
        }
        if (ok && (!doc.findLanePoint(0, DOC_CC_VOICE, 0, &pt) || pt.value != 9)) {
            failD("findLanePoint did not return the last program at the tick");
            ok = false;
        }
        if (ok && doc.tempoPoints() != expectedTempo) {
            failD("tempo load did not clamp bounds or preserve exact later tempo points");
            ok = false;
        }
        if (ok && hasLiveTempoMeta()) {
            failD("tempo load retained a live raw FF 51 event");
            ok = false;
        }
        if (ok) {
            const auto timeline = doc.buildTimeline(48000.0);
            if (!timeline || timeline->tempoMap.size() != 5 || timeline->tempoMap[0].tick != 0 ||
                timeline->tempoMap[0].bpm != 120.0 ||
                timeline->tempoMap[1].tick != slowTempo.tick ||
                timeline->tempoMap[2].tick != inRangeTempo.tick ||
                timeline->tempoMap[3].tick != fastTempo.tick ||
                timeline->tempoMap[4].tick != exactTempo.tick) {
                failD("timeline did not use the typed tempo points");
                ok = false;
            }
        }
        if (ok) {
            const QByteArray liveBytes = doc.smf().write();
            SmfFile expected = doc.smf();
            auto &expectedEvents = expected.tracks.front().events;
            expectedEvents.insert(
                expectedEvents.begin() + 1,
                {tempoMeta(slowTempo.tick, slowTempo.microsecondsPerQuarterNote),
                 tempoMeta(inRangeTempo.tick, inRangeTempo.microsecondsPerQuarterNote)});
            expectedEvents.insert(
                expectedEvents.begin() + 4,
                {tempoMeta(fastTempo.tick, fastTempo.microsecondsPerQuarterNote),
                 tempoMeta(exactTempo.tick, exactTempo.microsecondsPerQuarterNote)});
            QFile savedFile(midPath);
            const bool saved = doc.save(&werror);
            const bool readSaved = saved && savedFile.open(QIODevice::ReadOnly);
            const QByteArray savedBytes = readSaved ? savedFile.readAll() : QByteArray();
            if (!saved || !readSaved || savedBytes != expected.write() ||
                doc.smf().write() != liveBytes) {
                failD("save did not serialize tempo first without restoring live FF 51 events");
                ok = false;
            }
        }
        if (ok) {
            // Resubmitting the audible value still removes its same-tick
            // shadow, so this remains a real, exactly undoable edit.
            doc.findLanePoint(0, 7, 0, &pt);
            const QByteArray before = doc.smf().write();
            const uint64_t beforeRevision = doc.revision();
            const int beforeUndoCount = doc.undoStack()->count();
            const int beforeUndoIndex = doc.undoStack()->index();
            changedSignals = 0;
            doc.moveLanePoints({{0, 7, pt, pt.tick, pt.value}});
            const auto after = ccPointsAt(7, 0);
            if (after.size() != 1 || after[0].value != 80 || doc.revision() != beforeRevision + 1 ||
                doc.undoStack()->count() != beforeUndoCount + 1 ||
                doc.undoStack()->index() != beforeUndoIndex + 1 || changedSignals != 1) {
                failD("an exact duplicate resubmission did not canonicalize as one edit");
                ok = false;
            }
            const uint64_t canonicalRevision = doc.revision();
            changedSignals = 0;
            doc.undoStack()->undo();
            const auto restored = ccPointsAt(7, 0);
            if (ok &&
                (restored.size() != 2 || restored[0].value != 100 || restored[1].value != 80 ||
                 doc.smf().write() != before || doc.revision() != canonicalRevision + 1 ||
                 doc.undoStack()->count() != beforeUndoCount + 1 ||
                 doc.undoStack()->index() != beforeUndoIndex || changedSignals != 1)) {
                failD("undo did not exactly restore the shadowed duplicate");
                ok = false;
            }
        }
        if (ok) {
            // addLanePoint replaces the whole run on its tick.
            doc.addLanePoint(0, 7, 0, 70);
            if (ccPointsAt(7, 0).size() != 1) {
                failD("addLanePoint stacked another duplicate on the tick");
                ok = false;
            }
            doc.undoStack()->undo();
        }
        if (ok) {
            doc.addLanePoint(0, 7, 48, 55);
            if (!doc.findLanePoint(0, 7, 48, &pt) || ccPointsAt(7, 48).size() != 1) {
                failD("controller no-op fixture did not create one point");
                ok = false;
            } else {
                const QByteArray before = doc.smf().write();
                const uint64_t beforeRevision = doc.revision();
                const int beforeUndoCount = doc.undoStack()->count();
                const int beforeUndoIndex = doc.undoStack()->index();
                changedSignals = 0;
                doc.moveLanePoints({{0, 7, pt, pt.tick, pt.value}});
                if (doc.smf().write() != before || doc.revision() != beforeRevision ||
                    doc.undoStack()->count() != beforeUndoCount ||
                    doc.undoStack()->index() != beforeUndoIndex || changedSignals != 0) {
                    failD("an unchanged controller point mutated the document");
                    ok = false;
                }
            }
            if (ok) {
                // A cross-tick move landing on an occupied tick replaces the
                // run there too.
                doc.moveLanePoints({{0, 7, pt, 0, 55}});
                if (ccPointsAt(7, 0).size() != 1 || !ccPointsAt(7, 48).empty()) {
                    failD("a cross-tick move did not replace the destination run");
                    ok = false;
                }
            }
        }
        if (ok) {
            const TempoPoint noOpTempo = tempoPoint(48, 120);
            doc.applyTempoEdit({{}, {noOpTempo}});
            if (!containsTempoPoint(doc, noOpTempo) || hasLiveTempoMeta()) {
                failD("tempo edit did not keep live SMF free of FF 51 events");
                ok = false;
            } else {
                const QByteArray before = doc.smf().write();
                const auto beforeTempo = doc.tempoPoints();
                const uint64_t beforeRevision = doc.revision();
                const int beforeUndoCount = doc.undoStack()->count();
                const int beforeUndoIndex = doc.undoStack()->index();
                changedSignals = 0;
                doc.applyTempoEdit({{}, {noOpTempo}});
                if (doc.smf().write() != before || doc.tempoPoints() != beforeTempo ||
                    doc.revision() != beforeRevision ||
                    doc.undoStack()->count() != beforeUndoCount ||
                    doc.undoStack()->index() != beforeUndoIndex || changedSignals != 0) {
                    failD("an unchanged global tempo point mutated the document");
                    ok = false;
                }
            }
            if (ok) {
                doc.undoStack()->undo();
                if (!containsTempoPoint(doc, tempoPoint(48, 150)) || hasLiveTempoMeta()) {
                    failD("tempo undo did not keep live SMF free of FF 51 events");
                    ok = false;
                } else {
                    doc.undoStack()->redo();
                }
            }
        }
        if (ok) {
            while (doc.undoStack()->canUndo())
                doc.undoStack()->undo();
            if (doc.smf().write() != baseline)
                failD("undo-all did not restore the duplicated file byte-for-byte");
        }
    }
    failures += documentContractFailures();
    failures += timeRangeContractFailures();

    std::printf("editcheck: %d songs in %lld ms\n", checked, (long long)timer.elapsed());
    std::printf("editcheck: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
