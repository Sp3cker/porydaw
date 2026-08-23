#include "core/xcmd.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <unordered_map>
#include <utility>

// ---------------------------------------------------------------------------
// Deep module. All protocol parsing, epoch segmentation, and identity
// validation live in this TU. Decode model: one selector event (CC 0x1E)
// opens an epoch; payload events (CC 0x1D/0x1F) follow it. Selectors 0x08
// and 0x09 are known and yield one logical point per payload byte; any
// other selector epoch, a payload-less selector epoch, and payload events
// before the first selector are opaque blocks preserved byte-for-byte.
// Edits never share or restore selector state: every emitted point is an
// explicit selector+payload pair, so no final-stream projection is needed.
// ---------------------------------------------------------------------------

namespace xcmd {
namespace {

enum class SelectorBlockKind : uint8_t {
    KnownEpoch,  // selector 0x08/0x09 with payload bytes: one point per byte
    OpaqueEpoch, // any other selector epoch (or a payload-less known selector)
    StrayRun,    // payload bytes before any selector
};

struct SelectorBlock {
    SelectorBlockKind kind = SelectorBlockKind::OpaqueEpoch;
    uint8_t stream = 0;
    uint8_t selector = 0;              // epoch selector value
    size_t selectorEvent = SIZE_MAX;   // ordinal of the selector event, if any
    std::vector<size_t> payloadEvents; // event ordinals in scan order
    uint64_t firstTick = UINT64_MAX;   // occupied tick span
    uint64_t lastTick = 0;
};

struct ProtocolEvent {
    const Event *source = nullptr; // caller's event (identity/bytes)
    uint64_t tick = 0;
    uint8_t stream = 0;
    uint8_t value = 0;
    uint8_t channel = 0;
    size_t block = SIZE_MAX; // block ordinal
    bool isSelector = false;
};

struct ParsedEvents {
    std::vector<ProtocolEvent> events;            // protocol events, input order
    std::vector<SelectorBlock> blocks;            // per stream, epoch order
    std::unordered_map<uint64_t, size_t> indexOf; // event index -> event ordinal
};

ParsedEvents parseEvents(std::span<const Event> events) noexcept
{
    ParsedEvents parsed;
    // One open block per stream: the protocol is entirely per-stream state.
    std::array<size_t, 256> open{};
    open.fill(SIZE_MAX);
    for (const Event &event : events) {
        if (event.controller != kSelectorController && event.controller != kPayloadController &&
            event.controller != kAlternatePayloadController)
            continue;
        const size_t stream = size_t(event.stream);
        size_t block = open[stream];
        if (event.controller == kSelectorController) {
            block = parsed.blocks.size();
            SelectorBlock newBlock;
            newBlock.kind = SelectorBlockKind::OpaqueEpoch;
            newBlock.stream = event.stream;
            newBlock.selector = event.value;
            newBlock.firstTick = newBlock.lastTick = event.tick;
            parsed.blocks.push_back(std::move(newBlock));
            open[stream] = block;
        } else if (block == SIZE_MAX) {
            block = parsed.blocks.size();
            SelectorBlock newBlock;
            newBlock.kind = SelectorBlockKind::StrayRun;
            newBlock.stream = event.stream;
            newBlock.firstTick = newBlock.lastTick = event.tick;
            parsed.blocks.push_back(std::move(newBlock));
            open[stream] = block;
        }
        const size_t eventIndex = parsed.events.size();
        ProtocolEvent protocolEvent;
        protocolEvent.source = &event;
        protocolEvent.tick = event.tick;
        protocolEvent.stream = event.stream;
        protocolEvent.value = event.value;
        protocolEvent.channel = event.channel;
        protocolEvent.block = block;
        protocolEvent.isSelector = event.controller == kSelectorController;
        parsed.events.push_back(std::move(protocolEvent));
        parsed.indexOf.emplace(event.index, eventIndex);
        SelectorBlock &blockRef = parsed.blocks[block];
        if (protocolEvent.isSelector) {
            blockRef.selectorEvent = eventIndex;
        } else {
            blockRef.payloadEvents.push_back(eventIndex);
            blockRef.firstTick = std::min(blockRef.firstTick, event.tick);
            blockRef.lastTick = std::max(blockRef.lastTick, event.tick);
        }
    }
    // A known-selector epoch with at least one payload byte yields points.
    for (SelectorBlock &block : parsed.blocks)
        if (block.selectorEvent != SIZE_MAX && !block.payloadEvents.empty() &&
            descriptorForSelector(block.selector))
            block.kind = SelectorBlockKind::KnownEpoch;
    return parsed;
}

constexpr bool isKnownLaneBlock(const SelectorBlock &block) noexcept
{
    return block.kind == SelectorBlockKind::KnownEpoch;
}

Projection toProjection(const ParsedEvents &parsed) noexcept
{
    Projection projection;
    for (const SelectorBlock &block : parsed.blocks) {
        if (!isKnownLaneBlock(block))
            continue;
        for (const size_t eventIndex : block.payloadEvents) {
            const ProtocolEvent &protocolEvent = parsed.events[eventIndex];
            Point point;
            point.lane = descriptorForSelector(block.selector)->laneController;
            point.tick = protocolEvent.tick;
            point.value = protocolEvent.value;
            point.index = protocolEvent.source->index;
            point.stream = protocolEvent.stream;
            point.channel = protocolEvent.channel;
            projection.points.push_back(point);
        }
    }
    projection.consumed.reserve(parsed.events.size());
    for (const ProtocolEvent &protocolEvent : parsed.events)
        projection.consumed.push_back(protocolEvent.source->index);
    std::sort(projection.consumed.begin(), projection.consumed.end());
    projection.consumed.erase(std::unique(projection.consumed.begin(), projection.consumed.end()),
                              projection.consumed.end());
    return projection;
}

// Ascending, deduplicated removal set for membership tests.
struct RemoveSet {
    std::vector<uint64_t> indices;

    void add(uint64_t index) { indices.push_back(index); }
    void seal()
    {
        std::sort(indices.begin(), indices.end());
        indices.erase(std::unique(indices.begin(), indices.end()), indices.end());
    }
    bool contains(uint64_t index) const noexcept
    {
        return std::binary_search(indices.begin(), indices.end(), index);
    }
};

} // namespace

// ---------------------------------------------------------------------------
// Public projection: completed known points plus consumed raw indices.
// ---------------------------------------------------------------------------

Projection projectEvents(std::span<const Event> events) noexcept
{
    return toProjection(parseEvents(events));
}

// ---------------------------------------------------------------------------
// Logical lane rewrite.
//
// Removes are Point::index identities; writes land canonically as
// selector+payload at their ticks. Any epoch that owns a removed point or
// that a write lands inside is rebuilt: its selector byte and payload bytes
// are removed and its surviving points are re-emitted as explicit
// selector+payload pairs at their own ticks, so no selector sharing or
// restoration survives an edit. The rewrite is rejected (nullopt) without
// mutation when a write would fall inside an opaque epoch's occupied tick
// span (its bytes would be re-rolled) or when any identity or lane is
// unknown.
// ---------------------------------------------------------------------------

std::optional<Patch> rewritePoints(std::span<const Event> events,
                                   std::span<const uint64_t> removeIdentities,
                                   std::span<const PointWrite> writes) noexcept
{
    const ParsedEvents parsed = parseEvents(events);

    // Removes must name payload bytes of known epochs; unknown or opaque
    // identities reject rather than silently no-op.
    std::vector<char> touched(parsed.blocks.size(), 0);
    for (const uint64_t identity : removeIdentities) {
        const auto found = parsed.indexOf.find(identity);
        if (found == parsed.indexOf.end())
            return std::nullopt;
        const ProtocolEvent &protocolEvent = parsed.events[found->second];
        if (protocolEvent.isSelector || !isKnownLaneBlock(parsed.blocks[protocolEvent.block]))
            return std::nullopt;
        touched[protocolEvent.block] = 1;
    }

    // Writes must name known lanes; a write repeating the same (stream,
    // tick, lane) replaces the earlier one (later write wins).
    std::vector<const PointWrite *> activeWrites;
    activeWrites.reserve(writes.size());
    for (const PointWrite &write : writes) {
        if (!descriptorForLane(write.lane))
            return std::nullopt;
        bool duplicate = false;
        for (size_t i = 0; i < activeWrites.size(); ++i) {
            const PointWrite *existing = activeWrites[i];
            if (existing->stream == write.stream && existing->tick == write.tick &&
                existing->lane == write.lane) {
                activeWrites[i] = &write; // later write wins
                duplicate = true;
                break;
            }
        }
        if (!duplicate)
            activeWrites.push_back(&write);
    }

    // A write inside an unknown epoch's occupied tick span would re-roll
    // its surviving bytes; a write inside a known epoch's span makes that
    // epoch the affected span (rebuilt below).
    for (size_t blockIndex = 0; blockIndex < parsed.blocks.size(); ++blockIndex) {
        const SelectorBlock &block = parsed.blocks[blockIndex];
        for (const PointWrite *write : activeWrites) {
            if (write->stream != block.stream || write->tick < block.firstTick ||
                write->tick > block.lastTick)
                continue;
            if (isKnownLaneBlock(block))
                touched[blockIndex] = 1;
            else
                return std::nullopt;
        }
    }

    Patch patch;
    // The whole affected epoch leaves: selector byte plus every payload.
    RemoveSet removed;
    for (const SelectorBlock &block : parsed.blocks) {
        if (!touched[&block - parsed.blocks.data()])
            continue;
        if (block.selectorEvent != SIZE_MAX)
            removed.add(parsed.events[block.selectorEvent].source->index);
        for (const size_t eventIndex : block.payloadEvents)
            removed.add(parsed.events[eventIndex].source->index);
    }
    removed.seal();
    patch.removeEvents.assign(removed.indices.begin(), removed.indices.end());

    // Removed point identities, for the rebuild pass below.
    RemoveSet removedIds;
    for (const uint64_t identity : removeIdentities)
        removedIds.add(identity);
    removedIds.seal();

    std::vector<Emission> inserts;
    for (const SelectorBlock &block : parsed.blocks) {
        const size_t blockIndex = size_t(&block - parsed.blocks.data());
        if (!touched[blockIndex] || !isKnownLaneBlock(block))
            continue;
        for (const size_t eventIndex : block.payloadEvents) {
            const ProtocolEvent &protocolEvent = parsed.events[eventIndex];
            if (removedIds.contains(protocolEvent.source->index))
                continue; // the rewrite removed this point: no re-emission
            bool replaced = false;
            for (const PointWrite *write : activeWrites) {
                if (write->stream == protocolEvent.stream && write->tick == protocolEvent.tick &&
                    descriptorForLane(write->lane)->selector == block.selector) {
                    replaced = true;
                    break;
                }
            }
            if (replaced)
                continue;
            // Explicit pair: selector support plus its payload byte.
            inserts.push_back({protocolEvent.tick, kSelectorController, block.selector, SIZE_MAX,
                               protocolEvent.channel});
            inserts.push_back({protocolEvent.tick, kPayloadController, uint8_t(protocolEvent.value),
                               SIZE_MAX, protocolEvent.channel});
        }
    }
    for (const PointWrite *write : activeWrites) {
        const Descriptor *descriptor = descriptorForLane(write->lane);
        const uint8_t clamped = uint8_t(std::clamp(int(write->value), int(descriptor->minimumValue),
                                                   int(descriptor->maximumValue)));
        inserts.push_back(
            {write->tick, kSelectorController, descriptor->selector, SIZE_MAX, write->channel});
        inserts.push_back({write->tick, kPayloadController, clamped, SIZE_MAX, write->channel});
    }
    std::stable_sort(inserts.begin(), inserts.end(),
                     [](const Emission &a, const Emission &b) { return a.tick < b.tick; });
    patch.inserts = std::move(inserts);
    return patch;
}

// ---------------------------------------------------------------------------
// Raw reconciliation.
//
// Plain removals plus source-indexed relocations and copies. A known
// point's move/copy is rebuilt canonically (an explicit selector+payload
// pair at the destination); an opaque epoch can only be removed, moved, or
// copied as a whole block with one operation, byte-exact through
// Emission::sourceIndex. A destination inside the occupied span of an epoch
// whose bytes survive the rewrite is rejected (spans this edit vacates are
// fair game), as is any unknown identity, partial block operation, or
// mixed operation within one opaque epoch.
// ---------------------------------------------------------------------------

std::optional<Patch> reconcileRaw(std::span<const Event> events, std::span<const uint64_t> removals,
                                  std::span<const Relocation> moves,
                                  std::span<const Relocation> copies) noexcept
{
    const ParsedEvents parsed = parseEvents(events);

    enum class OpKind : uint8_t { Remove, Move, Copy };
    struct Op {
        OpKind kind = OpKind::Remove;
        const Relocation *relocation = nullptr;
    };
    std::unordered_map<size_t, Op> opByEvent;
    const auto record = [&](uint64_t index, OpKind kind, const Relocation *relocation) -> bool {
        const auto found = parsed.indexOf.find(index);
        if (found == parsed.indexOf.end())
            return false; // unknown/stale identity
        const size_t eventIndex = found->second;
        const auto existing = opByEvent.find(eventIndex);
        if (existing != opByEvent.end()) {
            if (existing->second.kind != kind)
                return false; // mixed operations on one byte
            if (relocation && existing->second.relocation) {
                // A repeat of the same relocation is tolerated; a different
                // destination for the same source is a conflict.
                return existing->second.relocation->tick == relocation->tick &&
                       existing->second.relocation->channel == relocation->channel;
            }
            return relocation == nullptr && existing->second.relocation == nullptr;
        }
        opByEvent.emplace(eventIndex, Op{kind, relocation});
        return true;
    };
    for (const uint64_t index : removals)
        if (!record(index, OpKind::Remove, nullptr))
            return std::nullopt;
    for (const Relocation &move : moves)
        if (!record(move.index, OpKind::Move, &move))
            return std::nullopt;
    for (const Relocation &copy : copies)
        if (!record(copy.index, OpKind::Copy, &copy))
            return std::nullopt;

    // Block-level coherence: one operation type per epoch. A known epoch's
    // selector byte is protocol glue; raw time edits may address it, but the
    // logical payload operations determine the rebuilt epoch.
    struct BlockOp {
        OpKind kind = OpKind::Remove;
        size_t count = 0;
        size_t memberCount = 0;
        bool mixed = false;
    };
    std::vector<BlockOp> blockOps(parsed.blocks.size());
    for (size_t blockIndex = 0; blockIndex < parsed.blocks.size(); ++blockIndex) {
        const SelectorBlock &block = parsed.blocks[blockIndex];
        blockOps[blockIndex].memberCount =
            block.payloadEvents.size() + (block.selectorEvent != SIZE_MAX);
    }
    for (const auto &[eventIndex, op] : opByEvent) {
        const ProtocolEvent &protocolEvent = parsed.events[eventIndex];
        const SelectorBlock &block = parsed.blocks[protocolEvent.block];
        if (isKnownLaneBlock(block) && protocolEvent.isSelector)
            continue;
        BlockOp &blockOp = blockOps[protocolEvent.block];
        ++blockOp.count;
        if (blockOp.count == 1)
            blockOp.kind = op.kind;
        else if (blockOp.kind != op.kind)
            blockOp.mixed = true;
    }
    for (size_t blockIndex = 0; blockIndex < parsed.blocks.size(); ++blockIndex) {
        const BlockOp &blockOp = blockOps[blockIndex];
        if (blockOp.count == 0)
            continue;
        // Whole-block coherence applies to opaque epochs: a raw edit may
        // remove, move, or copy one only when every member shares the same
        // operation. Known epochs are rebuilt point-by-point, so each point
        // independently removes/moves/copies.
        if (isKnownLaneBlock(parsed.blocks[blockIndex]))
            continue;
        if (blockOp.mixed)
            return std::nullopt; // mixed remove/move/copy in one opaque epoch
        if (blockOp.count != blockOp.memberCount)
            return std::nullopt; // partial opaque block is a split
    }

    // A re-insertion landing inside another epoch's occupied span on the
    // same stream would change what that epoch's surviving bytes decode as.
    // Blocks this edit fully removes or fully relocates vacate their spans,
    // so they are not hazards; only blocks with bytes still in place after
    // the edit reject destinations inside their span.
    const auto survivesInPlace = [&](size_t blockIndex) -> bool {
        const SelectorBlock &block = parsed.blocks[blockIndex];
        const BlockOp &blockOp = blockOps[blockIndex];
        if (blockOp.count == 0)
            return true; // untouched: original bytes remain
        if (!isKnownLaneBlock(block))
            return blockOp.kind == OpKind::Copy; // copy keeps the source;
                                                 // remove/move take it away
        // Known epoch: every original byte leaves and the epoch is rebuilt.
        // Only points that stay in place (untouched survivors and copy
        // sources) leave bytes at the span.
        for (const size_t eventIndex : block.payloadEvents) {
            const auto found = opByEvent.find(eventIndex);
            const bool stays = found == opByEvent.end() || found->second.kind == OpKind::Copy;
            if (stays)
                return true;
        }
        return false;
    };
    for (const auto &[eventIndex, op] : opByEvent) {
        if (op.kind == OpKind::Remove)
            continue;
        const ProtocolEvent &protocolEvent = parsed.events[eventIndex];
        for (size_t blockIndex = 0; blockIndex < parsed.blocks.size(); ++blockIndex) {
            if (blockIndex == protocolEvent.block)
                continue; // the event's own epoch is rebuilt, not re-rolled
            const SelectorBlock &block = parsed.blocks[blockIndex];
            if (block.stream != protocolEvent.stream || !survivesInPlace(blockIndex) ||
                block.firstTick > op.relocation->tick || op.relocation->tick > block.lastTick)
                continue;
            return std::nullopt;
        }
    }

    Patch patch;
    RemoveSet removed;
    std::vector<Emission> inserts;
    for (size_t blockIndex = 0; blockIndex < parsed.blocks.size(); ++blockIndex) {
        const SelectorBlock &block = parsed.blocks[blockIndex];
        const BlockOp &blockOp = blockOps[blockIndex];
        if (blockOp.count == 0)
            continue;
        if (isKnownLaneBlock(block)) {
            // The epoch's own bytes all leave; every point is rebuilt as an
            // explicit pair (survivors in place, moved/copied at their
            // destinations).
            if (block.selectorEvent != SIZE_MAX)
                removed.add(parsed.events[block.selectorEvent].source->index);
            for (const size_t eventIndex : block.payloadEvents)
                removed.add(parsed.events[eventIndex].source->index);
            for (const size_t eventIndex : block.payloadEvents) {
                const ProtocolEvent &protocolEvent = parsed.events[eventIndex];
                const auto foundOp = opByEvent.find(eventIndex);
                const bool isRemove =
                    foundOp != opByEvent.end() && foundOp->second.kind == OpKind::Remove;
                const bool isMove =
                    foundOp != opByEvent.end() && foundOp->second.kind == OpKind::Move;
                const bool isCopy =
                    foundOp != opByEvent.end() && foundOp->second.kind == OpKind::Copy;
                if (isRemove)
                    continue;
                if (!isMove) { // survivor or copy source stays in place
                    inserts.push_back({protocolEvent.tick, kSelectorController, block.selector,
                                       SIZE_MAX, protocolEvent.channel});
                    inserts.push_back({protocolEvent.tick, kPayloadController,
                                       uint8_t(protocolEvent.value), SIZE_MAX,
                                       protocolEvent.channel});
                }
                if (isMove || isCopy) { // explicit pair at the destination
                    inserts.push_back({foundOp->second.relocation->tick, kSelectorController,
                                       block.selector, SIZE_MAX,
                                       foundOp->second.relocation->channel});
                    inserts.push_back({foundOp->second.relocation->tick, kPayloadController,
                                       uint8_t(protocolEvent.value), SIZE_MAX,
                                       foundOp->second.relocation->channel});
                }
            }
        } else {
            // Opaque epoch: whole-block byte-exact removal or re-insertion
            // of every member through sourceIndex. Copy keeps the source;
            // Remove and Move take it.
            if (blockOp.kind != OpKind::Copy) {
                if (block.selectorEvent != SIZE_MAX)
                    removed.add(parsed.events[block.selectorEvent].source->index);
                for (const size_t eventIndex : block.payloadEvents)
                    removed.add(parsed.events[eventIndex].source->index);
                if (blockOp.kind == OpKind::Remove)
                    continue;
            }
            const auto emitMember = [&](size_t eventIndex) {
                const Relocation &relocation = *opByEvent.at(eventIndex).relocation;
                inserts.push_back({relocation.tick, 0, 0, parsed.events[eventIndex].source->index,
                                   relocation.channel});
            };
            if (block.selectorEvent != SIZE_MAX)
                emitMember(block.selectorEvent);
            for (const size_t eventIndex : block.payloadEvents)
                emitMember(eventIndex);
        }
    }
    removed.seal();
    patch.removeEvents.assign(removed.indices.begin(), removed.indices.end());
    std::stable_sort(inserts.begin(), inserts.end(),
                     [](const Emission &a, const Emission &b) { return a.tick < b.tick; });
    patch.inserts = std::move(inserts);
    return patch;
}

} // namespace xcmd