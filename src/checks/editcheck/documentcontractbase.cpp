#include <QTemporaryDir>

#include <utility>
#include <vector>

#include <algorithm>
#include <cstddef>
#include <cstdio>

#include "core/miditimeline.h"

#include "checks/editcheck/documentcontractfixtures.h"
#include "checks/editcheck/support.h"

namespace editcheck {
int documentPublicationTempoVelocityRemapFailures()
{
    using documentcontract::channel;
    using documentcontract::meta;
    auto failures = 0;
    const auto fail = [&failures](const char *what) {
        std::fprintf(stderr, "editcheck: FAIL document-contracts: %s\n", what);
        failures++;
    };
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back(documentcontract::conductor());
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

    // Document-state identity: saved state is an adopted identity, so an
    // edit dirties, undoing onto the saved state cleans, and undoing past
    // an adopted saved state dirties again until redo returns to it.
    if (ok) {
        doc.didSave(doc.captureSaveSnapshot(), true);
        expect(!doc.isDirty(), "matching save adoption did not clean the document");
        const auto saved = doc.captureSaveSnapshot();
        doc.applyTempoEdit({{}, {tempoPoint(96, 140)}});
        expect(doc.isDirty(), "an edit after adoption did not dirty the document");
        expect(!(doc.captureSaveSnapshot().documentState == saved.documentState),
               "an edit did not move the captured document state");
        doc.undoStack()->undo();
        expect(!doc.isDirty(), "undoing to the saved state left the document dirty");
        doc.undoStack()->redo();
        expect(doc.isDirty(), "redoing off the saved state left the document clean");
        doc.didSave(doc.captureSaveSnapshot(), true);
        doc.undoStack()->undo();
        expect(doc.isDirty(), "undoing past the adopted saved state stayed clean");
        doc.undoStack()->redo();
        expect(!doc.isDirty(), "redoing to the adopted saved state stayed dirty");
    }
    return failures;
}

} // namespace editcheck
