#include <cstdint>
#include <cstdio>
#include <span>
#include <vector>

#include "core/xcmd.h"

namespace {

using xcmd::Event;
using xcmd::PointWrite;
using xcmd::Projection;
using xcmd::Relocation;

Event ev(uint64_t index, uint64_t tick, uint8_t stream, uint8_t controller, uint8_t value,
         uint8_t channel = 0)
{
    Event event;
    event.index = index;
    event.tick = tick;
    event.stream = stream;
    event.controller = controller;
    event.value = value;
    event.channel = channel;
    return event;
}

template <typename... Events>
std::vector<Event> makeEvents(Events... events)
{
    return std::vector<Event>{static_cast<Event>(events)...};
}

Projection project(const std::vector<Event> &events)
{
    return xcmd::projectEvents(std::span<const Event>(events));
}

// ---------------------------------------------------------------------------
// Projection
// ---------------------------------------------------------------------------

int checkProjection()
{
    int failures = 0;
    const auto fail = [&failures](const char *message) {
        std::fprintf(stderr, "xcmdcheck: FAIL: %s\n", message);
        ++failures;
    };

    // One shared selector serves two one-byte completions: two known points
    // at their terminal ticks, and every protocol event consumed.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 2, 0, xcmd::kPayloadController, 34),
                                       ev(2, 3, 0, xcmd::kPayloadController, 35));
        const Projection result = project(events);
        if (result.points.size() != 2 || result.points[0].lane != xcmd::kEchoVolumeLane ||
            result.points[0].value != 34 || result.points[0].tick != 2 ||
            result.points[0].index != 1 || result.points[1].value != 35 ||
            result.points[1].tick != 3 || result.points[1].index != 2 ||
            result.consumed != std::vector<uint64_t>({0, 1, 2}))
            fail("shared-selector projection did not expose both points and consumed indices");
    }

    // An unknown selector epoch (0x01, multi-byte) is one opaque block: no
    // points, but the whole epoch is consumed protocol traffic.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x01),
                                       ev(1, 2, 0, xcmd::kPayloadController, 1),
                                       ev(2, 3, 0, xcmd::kPayloadController, 2));
        const Projection result = project(events);
        if (!result.points.empty() || result.consumed != std::vector<uint64_t>({0, 1, 2}))
            fail("unknown-selector epoch did not stay opaque with consumed bytes");
    }

    // A known selector with no payload at all is a dangling epoch: no point,
    // selector still consumed.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08));
        const Projection result = project(events);
        if (!result.points.empty() || result.consumed != std::vector<uint64_t>({0}))
            fail("payload-less selector epoch did not project as opaque");
    }

    // Leading stray payloads (before any selector) are their own opaque
    // block: no point, consumed bytes.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kPayloadController, 99),
                                       ev(1, 2, 0, xcmd::kSelectorController, 0x09),
                                       ev(2, 3, 0, xcmd::kPayloadController, 17));
        const Projection result = project(events);
        if (result.points.size() != 1 || result.points[0].value != 17 ||
            result.consumed != std::vector<uint64_t>({0, 1, 2}))
            fail("leading stray payload run was not kept opaque");
    }

    // Per-stream separation: traffic on different streams projects as
    // separate points, never merged into one epoch.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 2, 0, xcmd::kPayloadController, 34),
                                       ev(2, 1, 1, xcmd::kSelectorController, 0x09),
                                       ev(3, 2, 1, xcmd::kPayloadController, 17));
        const Projection result = project(events);
        if (result.points.size() != 2 || result.points[0].stream != 0 ||
            result.points[0].lane != xcmd::kEchoVolumeLane || result.points[1].stream != 1 ||
            result.points[1].lane != xcmd::kEchoLengthLane || result.points[1].value != 17)
            fail("streams did not project independently");
    }
    // Consumed identities are a sorted, de-duplicated protocol index set,
    // independent of the caller's raw-index order.
    {
        const auto events = makeEvents(ev(9, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(2, 2, 0, xcmd::kPayloadController, 34),
                                       ev(7, 3, 0, xcmd::kAlternatePayloadController, 35));
        const Projection result = project(events);
        if (result.consumed != std::vector<uint64_t>({2, 7, 9}))
            fail("protocol consumption was not a sorted raw-index set");
    }

    return failures;
}

// ---------------------------------------------------------------------------
// Canonical lane rewrites
// ---------------------------------------------------------------------------

int checkRewrites()
{
    int failures = 0;
    const auto fail = [&failures](const char *message) {
        std::fprintf(stderr, "xcmdcheck: FAIL: %s\n", message);
        ++failures;
    };

    // Add on an empty track: canonical selector support + payload, both on
    // the requested channel.
    {
        const std::vector<PointWrite> writes = {{5, xcmd::kEchoVolumeLane, 40, 0, 7}};
        const auto patch = xcmd::rewritePoints({}, {}, writes);
        if (!patch || !patch->removeEvents.empty() || patch->inserts.size() != 2 ||
            patch->inserts[0].tick != 5 ||
            patch->inserts[0].controller != xcmd::kSelectorController ||
            patch->inserts[0].value != 0x08 || patch->inserts[0].channel != 7 ||
            patch->inserts[1].controller != xcmd::kPayloadController ||
            patch->inserts[1].value != 40)
            fail("add did not emit canonical selector+payload");
    }

    // Add under already-active matching state still emits a full explicit
    // pair: no selector reuse ever.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 2, 0, xcmd::kPayloadController, 34));
        const std::vector<PointWrite> writes = {{5, xcmd::kEchoVolumeLane, 40, 0, 7}};
        const auto patch = xcmd::rewritePoints(events, {}, writes);
        if (!patch || patch->inserts.size() != 2 ||
            patch->inserts[0].controller != xcmd::kSelectorController ||
            patch->inserts[0].value != 0x08 ||
            patch->inserts[1].controller != xcmd::kPayloadController ||
            !patch->removeEvents.empty())
            fail("write did not emit a self-contained pair under active state");
    }

    // Replace the point on a tick: its whole epoch is rebuilt; the survivor
    // set is empty so only the write's canonical pair lands.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 2, 0, xcmd::kPayloadController, 34));
        const std::vector<PointWrite> writes = {{2, xcmd::kEchoVolumeLane, 40, 0, 7}};
        const auto patch = xcmd::rewritePoints(events, {}, writes);
        if (!patch || patch->removeEvents != std::vector<uint64_t>({0, 1}) ||
            patch->inserts.size() != 2 || patch->inserts[0].value != 0x08 ||
            patch->inserts[1].value != 40)
            fail("replace did not rebuild the epoch with an explicit pair");
    }

    // Delete one of two points sharing a selector: the epoch is rebuilt and
    // the survivor is re-emitted as its own explicit pair (no shared
    // selector output).
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 2, 0, xcmd::kPayloadController, 34),
                                       ev(2, 3, 0, xcmd::kPayloadController, 35));
        const Projection projection = project(events);
        const std::vector<uint64_t> removeIdentities = {projection.points[0].index};
        const auto patch = xcmd::rewritePoints(events, removeIdentities, {});
        if (!patch || patch->removeEvents != std::vector<uint64_t>({0, 1, 2}) ||
            patch->inserts.size() != 2 || patch->inserts[0].tick != 3 ||
            patch->inserts[0].value != 0x08 || patch->inserts[1].value != 35)
            fail("deleting one shared point did not rebuild the survivor as a pair");
    }

    // Delete the last point of an epoch: the whole epoch leaves, nothing
    // is inserted.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 2, 0, xcmd::kPayloadController, 34));
        const Projection projection = project(events);
        const std::vector<uint64_t> removeIdentities = {projection.points[0].index};
        const auto patch = xcmd::rewritePoints(events, removeIdentities, {});
        if (!patch || patch->removeEvents != std::vector<uint64_t>({0, 1}) ||
            !patch->inserts.empty())
            fail("deleting the last point left the dead epoch behind");
    }

    // A write inside a known epoch's span (between two shared points of a
    // different lane) rebuilds that epoch: survivor pairs replace it, and
    // the write lands as its own explicit pair. No selector restoration.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 2, 0, xcmd::kPayloadController, 34),
                                       ev(2, 10, 0, xcmd::kSelectorController, 0x09),
                                       ev(3, 13, 0, xcmd::kPayloadController, 17));
        const std::vector<PointWrite> writes = {{12, xcmd::kEchoVolumeLane, 40, 0, 0}};
        const auto patch = xcmd::rewritePoints(events, {}, writes);
        // 0x09 epoch [10,13] is affected: events 2,3 leave; survivor point@13
        // re-emitted as its own pair; write pair@12.
        if (!patch || patch->removeEvents != std::vector<uint64_t>({2, 3}) ||
            patch->inserts.size() != 4 || patch->inserts[0].tick != 12 ||
            patch->inserts[0].value != 0x08 || patch->inserts[1].value != 40 ||
            patch->inserts[2].tick != 13 || patch->inserts[2].value != 0x09 ||
            patch->inserts[3].value != 17)
            fail("in-span write did not rebuild the epoch canonically");
    }

    // Values clamp to the descriptor range.
    {
        const std::vector<PointWrite> writes = {{5, xcmd::kEchoLengthLane, 200, 0, 0}};
        const auto patch = xcmd::rewritePoints({}, {}, writes);
        if (!patch || patch->inserts[1].value != 127)
            fail("lane write did not clamp to the descriptor maximum");
    }

    // Unknown lane rejects; duplicate writes collapse to the later one.
    {
        const std::vector<PointWrite> unknownLane = {{5, 0x77, 40, 0, 0}};
        if (xcmd::rewritePoints({}, {}, unknownLane))
            fail("write on an unknown lane was not rejected");
        const std::vector<PointWrite> duplicates = {{5, xcmd::kEchoVolumeLane, 40, 0, 0},
                                                    {5, xcmd::kEchoVolumeLane, 55, 0, 0}};
        const auto patch = xcmd::rewritePoints({}, {}, duplicates);
        if (!patch || patch->inserts.size() != 2 || patch->inserts[1].value != 55)
            fail("duplicate same-slot write did not collapse to the later value");
    }
    // Same-tick canonical pairs retain active-write order after the stable
    // tick sort, rather than interleaving selectors and payloads by lane.
    {
        const std::vector<PointWrite> writes = {
            {5, xcmd::kEchoVolumeLane, 40, 0, 4},
            {5, xcmd::kEchoLengthLane, 55, 0, 5},
        };
        const auto patch = xcmd::rewritePoints({}, {}, writes);
        if (!patch || patch->inserts.size() != 4 || patch->inserts[0].value != 0x08 ||
            patch->inserts[0].channel != 4 || patch->inserts[1].value != 40 ||
            patch->inserts[1].channel != 4 || patch->inserts[2].value != 0x09 ||
            patch->inserts[2].channel != 5 || patch->inserts[3].value != 55 ||
            patch->inserts[3].channel != 5)
            fail("same-tick writes did not retain canonical pair order");
    }

    return failures;
}

// ---------------------------------------------------------------------------
// Opaque preservation and rejection
// ---------------------------------------------------------------------------

int checkOpaqueTraffic()
{
    int failures = 0;
    const auto fail = [&failures](const char *message) {
        std::fprintf(stderr, "xcmdcheck: FAIL: %s\n", message);
        ++failures;
    };

    // A write past an unknown-selector epoch keeps the opaque bytes
    // entirely untouched (no removal, no re-role).
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x03),
                                       ev(1, 2, 0, xcmd::kPayloadController, 9),
                                       ev(2, 5, 0, xcmd::kSelectorController, 0x08),
                                       ev(3, 6, 0, xcmd::kPayloadController, 34));
        const std::vector<PointWrite> writes = {{8, xcmd::kEchoVolumeLane, 40, 0, 0}};
        const auto patch = xcmd::rewritePoints(events, {}, writes);
        if (!patch || !patch->removeEvents.empty() || patch->inserts.size() != 2 ||
            patch->inserts[0].tick != 8 || patch->inserts[1].tick != 8)
            fail("write after an opaque epoch touched the opaque traffic");
    }

    // A write at an opaque epoch's interior tick would re-roll surviving
    // bytes: rejected.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x03),
                                       ev(1, 2, 0, xcmd::kPayloadController, 9),
                                       ev(2, 3, 0, xcmd::kPayloadController, 10));
        std::vector<PointWrite> writes = {{2, xcmd::kEchoVolumeLane, 40, 0, 0}};
        if (xcmd::rewritePoints(events, {}, writes))
            fail("write inside an opaque epoch was not rejected");
        writes[0].tick = 1; // the opaque selector's own tick
        if (xcmd::rewritePoints(events, {}, writes))
            fail("write on an opaque epoch's first tick was not rejected");
    }

    // A write inside a leading stray run's occupied span is rejected too.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kPayloadController, 99),
                                       ev(1, 2, 0, xcmd::kPayloadController, 98));
        const std::vector<PointWrite> writes = {{1, xcmd::kEchoVolumeLane, 40, 0, 0}};
        if (xcmd::rewritePoints(events, {}, writes))
            fail("write inside a stray-run span was not rejected");
    }

    // Remove identities that are not known points reject: opaque member,
    // selector byte, and unknown index.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x03),
                                       ev(1, 2, 0, xcmd::kPayloadController, 9),
                                       ev(2, 3, 0, xcmd::kSelectorController, 0x08),
                                       ev(3, 4, 0, xcmd::kPayloadController, 34));
        const std::vector<uint64_t> opaqueMember = {1};
        if (xcmd::rewritePoints(events, opaqueMember, {}))
            fail("removing an opaque member was not rejected");
        const std::vector<uint64_t> selectorByte = {2};
        if (xcmd::rewritePoints(events, selectorByte, {}))
            fail("removing a known selector was not rejected");
        const std::vector<uint64_t> staleIdentity = {999};
        if (xcmd::rewritePoints(events, staleIdentity, {}))
            fail("removing a stale identity was not rejected");
    }

    return failures;
}

// ---------------------------------------------------------------------------
// Raw reconciliation
// ---------------------------------------------------------------------------

int checkRawReconciliation()
{
    int failures = 0;
    const auto fail = [&failures](const char *message) {
        std::fprintf(stderr, "xcmdcheck: FAIL: %s\n", message);
        ++failures;
    };

    // Byte-exact relocation of a whole unknown selector epoch keeps each
    // member's own tick and channel. Repeating an identical operation is
    // accepted; removals sort/deduplicate and equal-tick emissions stay in
    // source order.
    {
        const auto events = makeEvents(
            ev(9, 1, 0, xcmd::kSelectorController, 0x01), ev(2, 2, 0, xcmd::kPayloadController, 1),
            ev(7, 3, 0, xcmd::kPayloadController, 2), ev(3, 4, 0, xcmd::kPayloadController, 3),
            ev(4, 5, 0, xcmd::kPayloadController, 4));
        const std::vector<Relocation> moves = {
            Relocation{9, 30, 4}, Relocation{2, 10, 5}, Relocation{2, 10, 5},
            Relocation{7, 10, 6}, Relocation{3, 20, 7}, Relocation{4, 20, 8},
        };
        const auto patch = xcmd::reconcileRaw(events, {}, moves, {});
        if (!patch || patch->removeEvents != std::vector<uint64_t>({2, 3, 4, 7, 9}) ||
            patch->inserts.size() != 5 || patch->inserts[0].sourceIndex != 2 ||
            patch->inserts[0].tick != 10 || patch->inserts[0].channel != 5 ||
            patch->inserts[1].sourceIndex != 7 || patch->inserts[1].tick != 10 ||
            patch->inserts[1].channel != 6 || patch->inserts[2].sourceIndex != 3 ||
            patch->inserts[2].tick != 20 || patch->inserts[2].channel != 7 ||
            patch->inserts[3].sourceIndex != 4 || patch->inserts[3].tick != 20 ||
            patch->inserts[3].channel != 8 || patch->inserts[4].sourceIndex != 9 ||
            patch->inserts[4].tick != 30 || patch->inserts[4].channel != 4)
            fail("whole opaque relocation did not preserve sorted byte-exact emissions");
    }

    // Moving only part of an unknown epoch is a split: rejected. Mixing
    // remove and move within one epoch is rejected too.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x01),
                                       ev(1, 2, 0, xcmd::kPayloadController, 1),
                                       ev(2, 3, 0, xcmd::kPayloadController, 2));
        const std::vector<Relocation> partialMoves = {Relocation{1, 20, 0}};
        if (xcmd::reconcileRaw(events, {}, partialMoves, {}))
            fail("partial opaque relocation was not rejected");
        const std::vector<Relocation> partialCopies = {Relocation{1, 20, 0}};
        if (xcmd::reconcileRaw(events, {}, {}, partialCopies))
            fail("partial opaque copy was not rejected");
        const std::vector<uint64_t> mixedRemovals = {0};
        const std::vector<Relocation> mixedMoves = {Relocation{1, 20, 0}, Relocation{2, 21, 0}};
        if (xcmd::reconcileRaw(events, mixedRemovals, mixedMoves, {}))
            fail("mixed remove/move within one opaque epoch was not rejected");
    }
    // A duplicate byte operation must retain its exact kind and destination.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 2, 0, xcmd::kPayloadController, 34));
        const std::vector<Relocation> conflicting = {Relocation{1, 20, 0}, Relocation{1, 21, 0}};
        if (xcmd::reconcileRaw(events, {}, conflicting, {}))
            fail("conflicting duplicate raw destinations were accepted");
        const std::vector<uint64_t> removals = {1};
        const std::vector<Relocation> moves = {Relocation{1, 20, 0}};
        if (xcmd::reconcileRaw(events, removals, moves, {}))
            fail("mixed raw operations on one byte were accepted");
    }

    // Whole-epoch copy duplicates every byte and keeps the source.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x01),
                                       ev(1, 2, 0, xcmd::kPayloadController, 1),
                                       ev(2, 3, 0, xcmd::kPayloadController, 2));
        const std::vector<Relocation> copies = {Relocation{0, 20, 0}, Relocation{1, 21, 0},
                                                Relocation{2, 22, 0}};
        const auto patch = xcmd::reconcileRaw(events, {}, {}, copies);
        if (!patch || !patch->removeEvents.empty() || patch->inserts.size() != 3 ||
            patch->inserts[0].sourceIndex != 0 || patch->inserts[0].tick != 20 ||
            patch->inserts[1].sourceIndex != 1 || patch->inserts[1].tick != 21 ||
            patch->inserts[2].sourceIndex != 2 || patch->inserts[2].tick != 22)
            fail("whole opaque copy did not duplicate every byte");
        const std::vector<Relocation> mixedMoves = {Relocation{0, 20, 0}, Relocation{1, 21, 0}};
        const std::vector<Relocation> mixedCopies = {Relocation{2, 22, 0}};
        if (xcmd::reconcileRaw(events, {}, mixedMoves, mixedCopies))
            fail("mixed move/copy in one opaque epoch was not rejected");
    }

    // A whole-unknown-epoch removal: selector and payloads leave together.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x01),
                                       ev(1, 2, 0, xcmd::kPayloadController, 1),
                                       ev(2, 3, 0, xcmd::kPayloadController, 2));
        const std::vector<uint64_t> payloadOnly = {1, 2};
        if (xcmd::reconcileRaw(events, payloadOnly, {}, {}))
            fail("removing only payload bytes of an opaque epoch was accepted");
        const std::vector<uint64_t> wholeEpoch = {0, 1, 2};
        const auto patch = xcmd::reconcileRaw(events, wholeEpoch, {}, {});
        if (!patch || patch->removeEvents != std::vector<uint64_t>({0, 1, 2}) ||
            !patch->inserts.empty())
            fail("whole-epoch removal left bytes behind");
    }

    // Stray-run operations must be whole-block too.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kPayloadController, 9),
                                       ev(1, 2, 0, xcmd::kPayloadController, 10));
        const std::vector<Relocation> partialMoves = {Relocation{0, 20, 3}};
        if (xcmd::reconcileRaw(events, {}, partialMoves, {}))
            fail("partial stray-run relocation was not rejected");
        const std::vector<Relocation> wholeMoves = {Relocation{0, 20, 3}, Relocation{1, 21, 3}};
        const auto patch = xcmd::reconcileRaw(events, {}, wholeMoves, {});
        if (!patch || patch->removeEvents != std::vector<uint64_t>({0, 1}) ||
            patch->inserts.size() != 2 || patch->inserts[0].sourceIndex != 0 ||
            patch->inserts[1].sourceIndex != 1)
            fail("whole stray-run relocation was not byte-exact");
    }

    // Moving one point of a shared known epoch rebuilds the epoch: the
    // survivor becomes its own explicit pair, the moved point lands as a
    // pair at the destination, and every original byte leaves.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 2, 0, xcmd::kPayloadController, 34),
                                       ev(2, 3, 0, xcmd::kPayloadController, 35));
        const std::vector<Relocation> moves = {Relocation{1, 20, 0}};
        const auto patch = xcmd::reconcileRaw(events, {}, moves, {});
        if (!patch || patch->removeEvents != std::vector<uint64_t>({0, 1, 2}) ||
            patch->inserts.size() != 4 || patch->inserts[0].tick != 3 ||
            patch->inserts[0].value != 0x08 || patch->inserts[1].value != 35 ||
            patch->inserts[2].tick != 20 || patch->inserts[2].value != 0x08 ||
            patch->inserts[3].value != 34)
            fail("known-point move did not rebuild the epoch canonically");
    }

    // Copying one point of a known epoch keeps the copy as an explicit pair
    // at its own tick and adds the destination pair.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 2, 0, xcmd::kPayloadController, 34),
                                       ev(2, 3, 0, xcmd::kPayloadController, 35));
        const std::vector<Relocation> copies = {Relocation{1, 20, 0}};
        const auto patch = xcmd::reconcileRaw(events, {}, {}, copies);
        if (!patch || patch->removeEvents != std::vector<uint64_t>({0, 1, 2}) ||
            patch->inserts.size() != 6 || patch->inserts[0].value != 0x08 ||
            patch->inserts[1].value != 34 || patch->inserts[2].value != 0x08 ||
            patch->inserts[3].value != 35 || patch->inserts[4].value != 0x08 ||
            patch->inserts[5].value != 34 || patch->inserts[0].sourceIndex != SIZE_MAX ||
            patch->inserts[1].sourceIndex != SIZE_MAX ||
            patch->inserts[2].sourceIndex != SIZE_MAX ||
            patch->inserts[3].sourceIndex != SIZE_MAX ||
            patch->inserts[4].sourceIndex != SIZE_MAX || patch->inserts[5].sourceIndex != SIZE_MAX)
            fail("known-point copy did not rebuild both copies canonically");
    }

    // Mixed per-point operations inside one known epoch are fine: each
    // point rebuilds independently (remove one, move the other).
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 2, 0, xcmd::kPayloadController, 34),
                                       ev(2, 3, 0, xcmd::kPayloadController, 35));
        const std::vector<uint64_t> removals = {2};
        const std::vector<Relocation> moves = {Relocation{1, 20, 0}};
        const auto patch = xcmd::reconcileRaw(events, removals, moves, {});
        if (!patch || patch->removeEvents != std::vector<uint64_t>({0, 1, 2}) ||
            patch->inserts.size() != 2 || patch->inserts[0].tick != 20 ||
            patch->inserts[0].value != 0x08 || patch->inserts[1].value != 34)
            fail("mixed remove/move within a known epoch was not rebuilt point-by-point");
    }

    // Removing a known point through raw ops kills the epoch only via the
    // same unified rule: survivor rebuilt, dead epoch gone.
    {
        const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 2, 0, xcmd::kPayloadController, 34));
        const std::vector<uint64_t> removals = {1};
        const auto patch = xcmd::reconcileRaw(events, removals, {}, {});
        if (!patch || patch->removeEvents != std::vector<uint64_t>({0, 1}) ||
            !patch->inserts.empty())
            fail("raw removal of a lone point left the epoch behind");
    }

    // Stale/unknown identities and destinations inside another epoch's
    // span are rejected. Known-epoch selectors are glue: raw editors may
    // address them, but payload operations determine whether the epoch moves.
    {
        const auto events = makeEvents(
            ev(0, 1, 0, xcmd::kSelectorController, 0x08), ev(1, 2, 0, xcmd::kPayloadController, 34),
            ev(2, 3, 0, xcmd::kSelectorController, 0x03), ev(3, 4, 0, xcmd::kPayloadController, 9));
        const std::vector<Relocation> staleMoves = {Relocation{7, 20, 0}};
        if (xcmd::reconcileRaw(events, {}, staleMoves, {}))
            fail("raw move of a stale identity was not rejected");
        const std::vector<Relocation> selectorMoves = {
            Relocation{0, 20, 0}}; // a known epoch's selector
        const auto selectorPatch = xcmd::reconcileRaw(events, {}, selectorMoves, {});
        if (!selectorPatch || !selectorPatch->removeEvents.empty() ||
            !selectorPatch->inserts.empty())
            fail("raw move of known-epoch selector glue was not ignored");
        const std::vector<Relocation> selectorIntoOtherMoves = {Relocation{0, 3, 0}};
        if (xcmd::reconcileRaw(events, {}, selectorIntoOtherMoves, {}))
            fail("selector glue move inside another epoch's span was not rejected");
        const std::vector<Relocation> intoOtherMoves = {
            Relocation{1, 3, 0}}; // lands in the opaque epoch's span
        if (xcmd::reconcileRaw(events, {}, intoOtherMoves, {}))
            fail("raw move inside another epoch's span was not rejected");
        const std::vector<Relocation> ownEpochMoves = {
            Relocation{1, 2, 0}}; // inside its own rebuilt epoch
        const auto patch = xcmd::reconcileRaw(events, {}, ownEpochMoves, {});
        if (!patch || patch->removeEvents != std::vector<uint64_t>({0, 1}) ||
            patch->inserts.size() != 2)
            fail("raw move within its own epoch was not rebuilt");
    }

    // Whole-song cut shape: a removed epoch's span is vacated by the edit,
    // so moving a later point onto it is accepted (not a re-role hazard).
    {
        const auto events = makeEvents(ev(0, 96, 0, xcmd::kSelectorController, 0x08),
                                       ev(1, 96, 0, xcmd::kPayloadController, 34),
                                       ev(2, 192, 0, xcmd::kSelectorController, 0x09),
                                       ev(3, 192, 0, xcmd::kPayloadController, 17));
        const std::vector<uint64_t> removals = {0, 1}; // cut [96,192): the volume pair leaves
        const std::vector<Relocation> moves = {
            Relocation{3, 96, 0}}; // the length point lands at 96
        const auto patch = xcmd::reconcileRaw(events, removals, moves, {});
        if (!patch || patch->removeEvents != std::vector<uint64_t>({0, 1, 2, 3}) ||
            patch->inserts.size() != 2 || patch->inserts[0].tick != 96 ||
            patch->inserts[0].value != 0x09 || patch->inserts[1].value != 17)
            fail("whole-song cut could not move onto a removed epoch's span");
    }

    // A fully relocated opaque epoch vacates its span: another group's
    // move may land there.
    {
        const auto events = makeEvents(
            ev(0, 1, 0, xcmd::kSelectorController, 0x03), ev(1, 2, 0, xcmd::kPayloadController, 9),
            ev(2, 3, 0, xcmd::kPayloadController, 10), ev(3, 5, 0, xcmd::kSelectorController, 0x08),
            ev(4, 5, 0, xcmd::kPayloadController, 34));
        const std::vector<Relocation> moves = {Relocation{0, 40, 0}, Relocation{1, 41, 0},
                                               Relocation{2, 42, 0}, Relocation{4, 2, 0}};
        const auto patch = xcmd::reconcileRaw(events, {}, moves, {});
        if (!patch || patch->removeEvents != std::vector<uint64_t>({0, 1, 2, 3, 4}) ||
            patch->inserts.size() != 5 || patch->inserts[0].tick != 2 ||
            patch->inserts[0].value != 0x08 || patch->inserts[1].value != 34 ||
            patch->inserts[2].sourceIndex != 0 || patch->inserts[2].tick != 40 ||
            patch->inserts[3].sourceIndex != 1 || patch->inserts[4].sourceIndex != 2)
            fail("move onto a fully relocated opaque epoch's span was not accepted");
    }

    return failures;
}

} // namespace

int runXcmdCheck()
{
    int failures = 0;
    failures += checkProjection();
    failures += checkRewrites();
    failures += checkOpaqueTraffic();
    failures += checkRawReconciliation();

    std::printf("xcmdcheck: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}