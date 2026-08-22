#include <QTemporaryDir>

#include <utility>
#include <vector>

#include <cstdio>

#include "checks/editcheck/documentcontractfixtures.h"
#include "checks/editcheck/support.h"
#include "core/tracklimits.h"

namespace editcheck {
int documentTrackDuplicationOwnershipFailures()
{
    using documentcontract::channel;
    auto failures = 0;
    const auto fail = [&failures](const char *what) {
        std::fprintf(stderr, "editcheck: FAIL document-contracts: %s\n", what);
        failures++;
    };
    const SmfTrack conductor = documentcontract::conductor();
    QTemporaryDir temporary;
    QString error;
    SongInfo info;
    info.hasMid = true;
    auto ok = true;
    const auto expect = [&](bool condition, const char *what) {
        if (!condition) {
            fail(what);
            ok = false;
        }
    };
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
    return failures;
}

int documentTrackGlobalMetadataFailures()
{
    using documentcontract::channel;
    using documentcontract::meta;
    auto failures = 0;
    const auto fail = [&failures](const char *what) {
        std::fprintf(stderr, "editcheck: FAIL document-contracts: %s\n", what);
        failures++;
    };
    QTemporaryDir temporary;
    QString error;
    SongInfo info;
    info.hasMid = true;
    auto ok = true;
    const auto expect = [&](bool condition, const char *what) {
        if (!condition) {
            fail(what);
            ok = false;
        }
    };
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
    return failures;
}

} // namespace editcheck
