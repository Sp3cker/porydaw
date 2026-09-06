#include <QTest>
#include <cstdint>
#include <vector>

#include "checks/playback/tst_xcmd.h"

namespace checks {

// Byte-exact relocation of a whole unknown selector epoch keeps each
// member's own tick and channel. Repeating an identical operation is
// accepted; removals sort/deduplicate and equal-tick emissions stay in
// source order.
void XcmdTest::wholeOpaqueRelocationIsByteExact()
{
    const auto events = makeEvents(
        ev(9, 1, 0, xcmd::kSelectorController, 0x01), ev(2, 2, 0, xcmd::kPayloadController, 1),
        ev(7, 3, 0, xcmd::kPayloadController, 2), ev(3, 4, 0, xcmd::kPayloadController, 3),
        ev(4, 5, 0, xcmd::kPayloadController, 4));
    const std::vector<xcmd::Relocation> moves = {
        xcmd::Relocation{9, 30, 4}, xcmd::Relocation{2, 10, 5}, xcmd::Relocation{2, 10, 5},
        xcmd::Relocation{7, 10, 6}, xcmd::Relocation{3, 20, 7}, xcmd::Relocation{4, 20, 8},
    };
    const auto patch = xcmd::reconcileRaw(events, {}, moves, {});
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({2, 3, 4, 7, 9}) &&
                 patch->inserts.size() == 5 && patch->inserts[0].sourceIndex == 2 &&
                 patch->inserts[0].tick == 10 && patch->inserts[0].channel == 5 &&
                 patch->inserts[1].sourceIndex == 7 && patch->inserts[1].tick == 10 &&
                 patch->inserts[1].channel == 6 && patch->inserts[2].sourceIndex == 3 &&
                 patch->inserts[2].tick == 20 && patch->inserts[2].channel == 7 &&
                 patch->inserts[3].sourceIndex == 4 && patch->inserts[3].tick == 20 &&
                 patch->inserts[3].channel == 8 && patch->inserts[4].sourceIndex == 9 &&
                 patch->inserts[4].tick == 30 && patch->inserts[4].channel == 4,
             "whole opaque relocation did not preserve sorted byte-exact emissions");
}

// Moving or copying only part of an unknown epoch is a split: rejected.
// Mixing remove and move within one epoch is rejected too.
void XcmdTest::partialOpaqueOperationsRejected()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x01),
                                   ev(1, 2, 0, xcmd::kPayloadController, 1),
                                   ev(2, 3, 0, xcmd::kPayloadController, 2));
    const std::vector<xcmd::Relocation> partialMoves = {xcmd::Relocation{1, 20, 0}};
    QVERIFY2(!xcmd::reconcileRaw(events, {}, partialMoves, {}),
             "partial opaque relocation was not rejected");
    const std::vector<xcmd::Relocation> partialCopies = {xcmd::Relocation{1, 20, 0}};
    QVERIFY2(!xcmd::reconcileRaw(events, {}, {}, partialCopies),
             "partial opaque copy was not rejected");
    const std::vector<uint64_t> mixedRemovals = {0};
    const std::vector<xcmd::Relocation> mixedMoves = {xcmd::Relocation{1, 20, 0},
                                                      xcmd::Relocation{2, 21, 0}};
    QVERIFY2(!xcmd::reconcileRaw(events, mixedRemovals, mixedMoves, {}),
             "mixed remove/move within one opaque epoch was not rejected");
}

// A duplicate byte operation must retain its exact kind and destination:
// conflicting destinations and mixed operations on one byte reject.
void XcmdTest::conflictingDuplicateRawOpsRejected()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                   ev(1, 2, 0, xcmd::kPayloadController, 34));
    const std::vector<xcmd::Relocation> conflicting = {xcmd::Relocation{1, 20, 0},
                                                       xcmd::Relocation{1, 21, 0}};
    QVERIFY2(!xcmd::reconcileRaw(events, {}, conflicting, {}),
             "conflicting duplicate raw destinations were accepted");
    const std::vector<uint64_t> removals = {1};
    const std::vector<xcmd::Relocation> moves = {xcmd::Relocation{1, 20, 0}};
    QVERIFY2(!xcmd::reconcileRaw(events, removals, moves, {}),
             "mixed raw operations on one byte were accepted");
}

// Whole-epoch copy duplicates every byte and keeps the source; mixing move
// and copy in one opaque epoch is rejected.
void XcmdTest::wholeOpaqueCopyDuplicatesBytes()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x01),
                                   ev(1, 2, 0, xcmd::kPayloadController, 1),
                                   ev(2, 3, 0, xcmd::kPayloadController, 2));
    const std::vector<xcmd::Relocation> copies = {
        xcmd::Relocation{0, 20, 0}, xcmd::Relocation{1, 21, 0}, xcmd::Relocation{2, 22, 0}};
    const auto patch = xcmd::reconcileRaw(events, {}, {}, copies);
    QVERIFY2(patch && patch->removeEvents.empty() && patch->inserts.size() == 3 &&
                 patch->inserts[0].sourceIndex == 0 && patch->inserts[0].tick == 20 &&
                 patch->inserts[1].sourceIndex == 1 && patch->inserts[1].tick == 21 &&
                 patch->inserts[2].sourceIndex == 2 && patch->inserts[2].tick == 22,
             "whole opaque copy did not duplicate every byte");
    const std::vector<xcmd::Relocation> mixedMoves = {xcmd::Relocation{0, 20, 0},
                                                      xcmd::Relocation{1, 21, 0}};
    const std::vector<xcmd::Relocation> mixedCopies = {xcmd::Relocation{2, 22, 0}};
    QVERIFY2(!xcmd::reconcileRaw(events, {}, mixedMoves, mixedCopies),
             "mixed move/copy in one opaque epoch was not rejected");
}

// A whole-unknown-epoch removal: selector and payloads leave together.
// Removing only payload bytes rejects.
void XcmdTest::wholeEpochRemovalLeavesNothingBehind()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x01),
                                   ev(1, 2, 0, xcmd::kPayloadController, 1),
                                   ev(2, 3, 0, xcmd::kPayloadController, 2));
    const std::vector<uint64_t> payloadOnly = {1, 2};
    QVERIFY2(!xcmd::reconcileRaw(events, payloadOnly, {}, {}),
             "removing only payload bytes of an opaque epoch was accepted");
    const std::vector<uint64_t> wholeEpoch = {0, 1, 2};
    const auto patch = xcmd::reconcileRaw(events, wholeEpoch, {}, {});
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({0, 1, 2}) &&
                 patch->inserts.empty(),
             "whole-epoch removal left bytes behind");
}

// Stray-run operations must be whole-block too: partial relocation
// rejects, whole relocation is byte-exact.
void XcmdTest::wholeStrayRunRelocationIsByteExact()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kPayloadController, 9),
                                   ev(1, 2, 0, xcmd::kPayloadController, 10));
    const std::vector<xcmd::Relocation> partialMoves = {xcmd::Relocation{0, 20, 3}};
    QVERIFY2(!xcmd::reconcileRaw(events, {}, partialMoves, {}),
             "partial stray-run relocation was not rejected");
    const std::vector<xcmd::Relocation> wholeMoves = {xcmd::Relocation{0, 20, 3},
                                                      xcmd::Relocation{1, 21, 3}};
    const auto patch = xcmd::reconcileRaw(events, {}, wholeMoves, {});
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({0, 1}) &&
                 patch->inserts.size() == 2 && patch->inserts[0].sourceIndex == 0 &&
                 patch->inserts[1].sourceIndex == 1,
             "whole stray-run relocation was not byte-exact");
}

// Moving one point of a shared known epoch rebuilds the epoch: the survivor
// becomes its own explicit pair, the moved point lands as a pair at the
// destination, and every original byte leaves.
void XcmdTest::knownPointMoveRebuildsEpoch()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                   ev(1, 2, 0, xcmd::kPayloadController, 34),
                                   ev(2, 3, 0, xcmd::kPayloadController, 35));
    const std::vector<xcmd::Relocation> moves = {xcmd::Relocation{1, 20, 0}};
    const auto patch = xcmd::reconcileRaw(events, {}, moves, {});
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({0, 1, 2}) &&
                 patch->inserts.size() == 4 && patch->inserts[0].tick == 3 &&
                 patch->inserts[0].value == 0x08 && patch->inserts[1].value == 35 &&
                 patch->inserts[2].tick == 20 && patch->inserts[2].value == 0x08 &&
                 patch->inserts[3].value == 34,
             "known-point move did not rebuild the epoch canonically");
}

// Copying one point of a known epoch keeps the copy as an explicit pair at
// its own tick and adds the destination pair — six canonical inserts, every
// sourceIndex still SIZE_MAX.
void XcmdTest::knownPointCopyRebuildsBothCanonically()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                   ev(1, 2, 0, xcmd::kPayloadController, 34),
                                   ev(2, 3, 0, xcmd::kPayloadController, 35));
    const std::vector<xcmd::Relocation> copies = {xcmd::Relocation{1, 20, 0}};
    const auto patch = xcmd::reconcileRaw(events, {}, {}, copies);
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({0, 1, 2}) &&
                 patch->inserts.size() == 6 && patch->inserts[0].value == 0x08 &&
                 patch->inserts[1].value == 34 && patch->inserts[2].value == 0x08 &&
                 patch->inserts[3].value == 35 && patch->inserts[4].value == 0x08 &&
                 patch->inserts[5].value == 34 && patch->inserts[0].sourceIndex == SIZE_MAX &&
                 patch->inserts[1].sourceIndex == SIZE_MAX &&
                 patch->inserts[2].sourceIndex == SIZE_MAX &&
                 patch->inserts[3].sourceIndex == SIZE_MAX &&
                 patch->inserts[4].sourceIndex == SIZE_MAX &&
                 patch->inserts[5].sourceIndex == SIZE_MAX,
             "known-point copy did not rebuild both copies canonically");
}

// Mixed per-point operations inside one known epoch are fine: each point
// rebuilds independently (remove one, move the other).
void XcmdTest::mixedKnownEpochOpsRebuildPointByPoint()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                   ev(1, 2, 0, xcmd::kPayloadController, 34),
                                   ev(2, 3, 0, xcmd::kPayloadController, 35));
    const std::vector<uint64_t> removals = {2};
    const std::vector<xcmd::Relocation> moves = {xcmd::Relocation{1, 20, 0}};
    const auto patch = xcmd::reconcileRaw(events, removals, moves, {});
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({0, 1, 2}) &&
                 patch->inserts.size() == 2 && patch->inserts[0].tick == 20 &&
                 patch->inserts[0].value == 0x08 && patch->inserts[1].value == 34,
             "mixed remove/move within a known epoch was not rebuilt point-by-point");
}

// Removing a known point through raw ops kills the epoch only via the same
// unified rule: survivor rebuilt, dead epoch gone.
void XcmdTest::rawRemovalOfLonePointKillsEpoch()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                   ev(1, 2, 0, xcmd::kPayloadController, 34));
    const std::vector<uint64_t> removals = {1};
    const auto patch = xcmd::reconcileRaw(events, removals, {}, {});
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({0, 1}) &&
                 patch->inserts.empty(),
             "raw removal of a lone point left the epoch behind");
}

// Stale/unknown identities and destinations inside another epoch's span are
// rejected.
void XcmdTest::staleAndCrossEpochRawDestinationsRejected()
{
    const auto events = makeEvents(
        ev(0, 1, 0, xcmd::kSelectorController, 0x08), ev(1, 2, 0, xcmd::kPayloadController, 34),
        ev(2, 3, 0, xcmd::kSelectorController, 0x03), ev(3, 4, 0, xcmd::kPayloadController, 9));
    const std::vector<xcmd::Relocation> staleMoves = {xcmd::Relocation{7, 20, 0}};
    QVERIFY2(!xcmd::reconcileRaw(events, {}, staleMoves, {}),
             "raw move of a stale identity was not rejected");
    const std::vector<xcmd::Relocation> selectorIntoOtherMoves = {xcmd::Relocation{0, 3, 0}};
    QVERIFY2(!xcmd::reconcileRaw(events, {}, selectorIntoOtherMoves, {}),
             "selector glue move inside another epoch's span was not rejected");
    const std::vector<xcmd::Relocation> intoOtherMoves = {
        xcmd::Relocation{1, 3, 0}}; // lands in the opaque epoch's span
    QVERIFY2(!xcmd::reconcileRaw(events, {}, intoOtherMoves, {}),
             "raw move inside another epoch's span was not rejected");
}

// Known-epoch selectors are glue: raw editors may address them, but payload
// operations determine whether the epoch moves — a selector-only move is an
// empty patch, while a payload move inside its own rebuilt epoch works.
void XcmdTest::knownSelectorGlueIgnoredAndOwnEpochMoveRebuilt()
{
    const auto events = makeEvents(
        ev(0, 1, 0, xcmd::kSelectorController, 0x08), ev(1, 2, 0, xcmd::kPayloadController, 34),
        ev(2, 3, 0, xcmd::kSelectorController, 0x03), ev(3, 4, 0, xcmd::kPayloadController, 9));
    const std::vector<xcmd::Relocation> selectorMoves = {
        xcmd::Relocation{0, 20, 0}}; // a known epoch's selector
    const auto selectorPatch = xcmd::reconcileRaw(events, {}, selectorMoves, {});
    QVERIFY2(selectorPatch && selectorPatch->removeEvents.empty() && selectorPatch->inserts.empty(),
             "raw move of known-epoch selector glue was not ignored");
    const std::vector<xcmd::Relocation> ownEpochMoves = {
        xcmd::Relocation{1, 2, 0}}; // inside its own rebuilt epoch
    const auto patch = xcmd::reconcileRaw(events, {}, ownEpochMoves, {});
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({0, 1}) &&
                 patch->inserts.size() == 2,
             "raw move within its own epoch was not rebuilt");
}

// Whole-song cut shape: a removed epoch's span is vacated by the edit, so
// moving a later point onto it is accepted (not a re-role hazard).
void XcmdTest::cutVacatesSpanForLaterMove()
{
    const auto events = makeEvents(ev(0, 96, 0, xcmd::kSelectorController, 0x08),
                                   ev(1, 96, 0, xcmd::kPayloadController, 34),
                                   ev(2, 192, 0, xcmd::kSelectorController, 0x09),
                                   ev(3, 192, 0, xcmd::kPayloadController, 17));
    const std::vector<uint64_t> removals = {0, 1}; // cut [96,192): the volume pair leaves
    const std::vector<xcmd::Relocation> moves = {
        xcmd::Relocation{3, 96, 0}}; // the length point lands at 96
    const auto patch = xcmd::reconcileRaw(events, removals, moves, {});
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({0, 1, 2, 3}) &&
                 patch->inserts.size() == 2 && patch->inserts[0].tick == 96 &&
                 patch->inserts[0].value == 0x09 && patch->inserts[1].value == 17,
             "whole-song cut could not move onto a removed epoch's span");
}

// A fully relocated opaque epoch vacates its span: another group's move may
// land there.
void XcmdTest::relocatedEpochVacatesItsSpan()
{
    const auto events = makeEvents(
        ev(0, 1, 0, xcmd::kSelectorController, 0x03), ev(1, 2, 0, xcmd::kPayloadController, 9),
        ev(2, 3, 0, xcmd::kPayloadController, 10), ev(3, 5, 0, xcmd::kSelectorController, 0x08),
        ev(4, 5, 0, xcmd::kPayloadController, 34));
    const std::vector<xcmd::Relocation> moves = {
        xcmd::Relocation{0, 40, 0}, xcmd::Relocation{1, 41, 0}, xcmd::Relocation{2, 42, 0},
        xcmd::Relocation{4, 2, 0}};
    const auto patch = xcmd::reconcileRaw(events, {}, moves, {});
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({0, 1, 2, 3, 4}) &&
                 patch->inserts.size() == 5 && patch->inserts[0].tick == 2 &&
                 patch->inserts[0].value == 0x08 && patch->inserts[1].value == 34 &&
                 patch->inserts[2].sourceIndex == 0 && patch->inserts[2].tick == 40 &&
                 patch->inserts[3].sourceIndex == 1 && patch->inserts[4].sourceIndex == 2,
             "move onto a fully relocated opaque epoch's span was not accepted");
}

} // namespace checks
