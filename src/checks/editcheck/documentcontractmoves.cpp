#include <QTemporaryDir>

#include <utility>
#include <vector>

#include <cstdio>

#include "checks/editcheck/documentcontractfixtures.h"
#include "checks/editcheck/support.h"

namespace editcheck {
int documentMoveIdentityFailures()
{
    using documentcontract::channel;
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
    return failures;
}

int documentMovePublicationFailures()
{
    using documentcontract::channel;
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

} // namespace editcheck
