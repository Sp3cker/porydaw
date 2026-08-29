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

struct NormalizedPointWrites {
    // Points into the caller's writes span. Entries stay in first-key order;
    // a duplicate key replaces the pointer at its original position.
    std::vector<const PointWrite *> active;
};

struct PointRewritePlan {
    // One entry per ParsedEvents::blocks element; 0 means untouched.
    std::vector<char> touchedBlocks;
    // Sorted and deduplicated before this plan is returned.
    RemoveSet removedPointIdentities;
    // Stores only pointers into rewritePoints' still-live writes span.
    NormalizedPointWrites writes;
};

enum class RawOperationKind : uint8_t {
    Remove,
    Move,
    Copy,
};

struct RawOperation {
    RawOperationKind kind = RawOperationKind::Remove;
    // Null only for Remove. Otherwise points into reconcileRaw's still-live
    // moves or copies span.
    const Relocation *relocation = nullptr;
};

struct RawOperations {
    // Key is a ParsedEvents::events ordinal, not Event::index.
    std::unordered_map<size_t, RawOperation> byEvent;
};

struct BlockOperation {
    // Meaningful only when affectedMemberCount is nonzero. Zero means the
    // block is untouched despite the default Remove value.
    RawOperationKind kind = RawOperationKind::Remove;
    size_t affectedMemberCount = 0;
    size_t memberCount = 0;
    bool mixed = false;
};

void appendCanonicalPoint(std::vector<Emission> &inserts, uint64_t tick, uint8_t selector,
                          uint8_t value, uint8_t channel) noexcept
{
    inserts.push_back({tick, kSelectorController, selector, SIZE_MAX, channel});
    inserts.push_back({tick, kPayloadController, value, SIZE_MAX, channel});
}

void appendVerbatimEvent(std::vector<Emission> &inserts, const ProtocolEvent &event,
                         const Relocation &relocation) noexcept
{
    inserts.push_back({relocation.tick, 0, 0, event.source->index, relocation.channel});
}

Patch finishPatch(RemoveSet removed, std::vector<Emission> inserts) noexcept
{
    removed.seal();
    Patch patch;
    patch.removeEvents = std::move(removed.indices);
    std::stable_sort(inserts.begin(), inserts.end(),
                     [](const Emission &a, const Emission &b) { return a.tick < b.tick; });
    patch.inserts = std::move(inserts);
    return patch;
}

bool samePointWriteSlot(const PointWrite &first, const PointWrite &second) noexcept
{
    return first.stream == second.stream && first.tick == second.tick && first.lane == second.lane;
}

bool isKnownPointPayload(const ParsedEvents &parsed, const ProtocolEvent &event) noexcept
{
    return !event.isSelector && isKnownLaneBlock(parsed.blocks[event.block]);
}

enum class PointWriteBlockRelation : char { Outside, Known, Opaque };

PointWriteBlockRelation pointWriteBlockRelation(const PointWrite &write,
                                                const SelectorBlock &block) noexcept
{
    if (write.stream != block.stream || write.tick < block.firstTick || write.tick > block.lastTick)
        return PointWriteBlockRelation::Outside;
    return isKnownLaneBlock(block) ? PointWriteBlockRelation::Known
                                   : PointWriteBlockRelation::Opaque;
}

std::optional<NormalizedPointWrites>
normalizePointWrites(std::span<const PointWrite> writes) noexcept
{
    NormalizedPointWrites normalized;
    normalized.active.reserve(writes.size());
    for (const PointWrite &write : writes) {
        if (!descriptorForLane(write.lane))
            return std::nullopt;
        bool duplicate = false;
        for (const PointWrite *&active : normalized.active) {
            if (!samePointWriteSlot(*active, write))
                continue;
            active = &write;
            duplicate = true;
            break;
        }
        if (!duplicate)
            normalized.active.push_back(&write);
    }
    return normalized;
}
std::optional<PointRewritePlan> planPointRewrite(const ParsedEvents &parsed,
                                                 std::span<const uint64_t> removeIdentities,
                                                 NormalizedPointWrites writes) noexcept
{
    PointRewritePlan plan;
    plan.touchedBlocks.assign(parsed.blocks.size(), 0);
    plan.writes = std::move(writes);
    for (const uint64_t identity : removeIdentities) {
        const auto found = parsed.indexOf.find(identity);
        if (found == parsed.indexOf.end())
            return std::nullopt;
        const ProtocolEvent &event = parsed.events[found->second];
        if (!isKnownPointPayload(parsed, event))
            return std::nullopt;
        plan.touchedBlocks[event.block] = 1;
        plan.removedPointIdentities.add(identity);
    }
    plan.removedPointIdentities.seal();
    for (size_t blockIndex = 0; blockIndex < parsed.blocks.size(); ++blockIndex) {
        const SelectorBlock &block = parsed.blocks[blockIndex];
        for (const PointWrite *write : plan.writes.active) {
            const auto relation = pointWriteBlockRelation(*write, block);
            if (relation == PointWriteBlockRelation::Opaque)
                return std::nullopt;
            plan.touchedBlocks[blockIndex] |= relation == PointWriteBlockRelation::Known;
        }
    }
    return plan;
}

void appendPointRewriteBlockRemoval(const ParsedEvents &parsed, const SelectorBlock &block,
                                    RemoveSet &removed) noexcept
{
    if (block.selectorEvent != SIZE_MAX)
        removed.add(parsed.events[block.selectorEvent].source->index);
    for (const size_t eventIndex : block.payloadEvents)
        removed.add(parsed.events[eventIndex].source->index);
}

bool writeReplacesPoint(const PointWrite &write, const ProtocolEvent &event,
                        uint8_t selector) noexcept
{
    return write.stream == event.stream && write.tick == event.tick &&
           descriptorForLane(write.lane)->selector == selector;
}

bool pointIsReplaced(const NormalizedPointWrites &writes, const ProtocolEvent &event,
                     uint8_t selector) noexcept
{
    for (const PointWrite *write : writes.active)
        if (writeReplacesPoint(*write, event, selector))
            return true;
    return false;
}

void emitPointRewritePoint(std::vector<Emission> &inserts, const ProtocolEvent &event,
                           const SelectorBlock &block, const PointRewritePlan &plan) noexcept
{
    if (plan.removedPointIdentities.contains(event.source->index) ||
        pointIsReplaced(plan.writes, event, block.selector))
        return;
    appendCanonicalPoint(inserts, event.tick, block.selector, event.value, event.channel);
}

Patch emitPointRewrite(const ParsedEvents &parsed, const PointRewritePlan &plan) noexcept
{
    RemoveSet removed;
    std::vector<Emission> inserts;
    for (size_t blockIndex = 0; blockIndex < parsed.blocks.size(); ++blockIndex) {
        const SelectorBlock &block = parsed.blocks[blockIndex];
        if (!plan.touchedBlocks[blockIndex])
            continue;
        appendPointRewriteBlockRemoval(parsed, block, removed);
        if (!isKnownLaneBlock(block))
            continue;
        for (const size_t eventIndex : block.payloadEvents)
            emitPointRewritePoint(inserts, parsed.events[eventIndex], block, plan);
    }
    for (const PointWrite *write : plan.writes.active) {
        const Descriptor *descriptor = descriptorForLane(write->lane);
        const uint8_t value = uint8_t(std::clamp(int(write->value), int(descriptor->minimumValue),
                                                 int(descriptor->maximumValue)));
        appendCanonicalPoint(inserts, write->tick, descriptor->selector, value, write->channel);
    }
    return finishPatch(std::move(removed), std::move(inserts));
}

bool recordRawOperation(const ParsedEvents &parsed, RawOperations &operations, uint64_t identity,
                        RawOperationKind kind, const Relocation *relocation) noexcept
{
    const auto found = parsed.indexOf.find(identity);
    if (found == parsed.indexOf.end())
        return false;
    const auto [existing, inserted] =
        operations.byEvent.try_emplace(found->second, RawOperation{kind, relocation});
    if (inserted)
        return true;
    const RawOperation &current = existing->second;
    if (current.kind != kind)
        return false;
    if (relocation == nullptr)
        return current.relocation == nullptr;
    if (current.relocation == nullptr)
        return false;
    return current.relocation->tick == relocation->tick &&
           current.relocation->channel == relocation->channel;
}

std::optional<RawOperations> collectRawOperations(const ParsedEvents &parsed,
                                                  std::span<const uint64_t> removals,
                                                  std::span<const Relocation> moves,
                                                  std::span<const Relocation> copies) noexcept
{
    RawOperations operations;
    for (const uint64_t identity : removals)
        if (!recordRawOperation(parsed, operations, identity, RawOperationKind::Remove, nullptr))
            return std::nullopt;
    for (const Relocation &move : moves)
        if (!recordRawOperation(parsed, operations, move.index, RawOperationKind::Move, &move))
            return std::nullopt;
    for (const Relocation &copy : copies)
        if (!recordRawOperation(parsed, operations, copy.index, RawOperationKind::Copy, &copy))
            return std::nullopt;
    return operations;
}

bool isKnownSelectorGlue(const ParsedEvents &parsed, const ProtocolEvent &event) noexcept
{
    return event.isSelector && isKnownLaneBlock(parsed.blocks[event.block]);
}

bool isInvalidOpaqueBlockOperation(const SelectorBlock &block,
                                   const BlockOperation &blockOperation) noexcept
{
    return blockOperation.affectedMemberCount != 0 && !isKnownLaneBlock(block) &&
           (blockOperation.mixed ||
            blockOperation.affectedMemberCount != blockOperation.memberCount);
}

std::optional<std::vector<BlockOperation>>
classifyBlockOperations(const ParsedEvents &parsed, const RawOperations &operations) noexcept
{
    std::vector<BlockOperation> blockOperations(parsed.blocks.size());
    for (const auto &[eventIndex, operation] : operations.byEvent) {
        const ProtocolEvent &event = parsed.events[eventIndex];
        if (isKnownSelectorGlue(parsed, event))
            continue;
        BlockOperation &blockOperation = blockOperations[event.block];
        ++blockOperation.affectedMemberCount;
        if (blockOperation.affectedMemberCount == 1)
            blockOperation.kind = operation.kind;
        else if (blockOperation.kind != operation.kind)
            blockOperation.mixed = true;
    }
    for (size_t blockIndex = 0; blockIndex < parsed.blocks.size(); ++blockIndex) {
        const SelectorBlock &block = parsed.blocks[blockIndex];
        BlockOperation &blockOperation = blockOperations[blockIndex];
        blockOperation.memberCount = block.payloadEvents.size() + (block.selectorEvent != SIZE_MAX);
        if (isInvalidOpaqueBlockOperation(block, blockOperation))
            return std::nullopt;
    }
    return blockOperations;
}

bool rawPointStaysInPlace(const RawOperations &operations, size_t eventIndex) noexcept
{
    const auto found = operations.byEvent.find(eventIndex);
    return found == operations.byEvent.end() || found->second.kind == RawOperationKind::Copy;
}

bool blockSurvivesInPlace(const ParsedEvents &parsed, const RawOperations &operations,
                          std::span<const BlockOperation> blockOperations,
                          size_t blockIndex) noexcept
{
    const SelectorBlock &block = parsed.blocks[blockIndex];
    const BlockOperation &blockOperation = blockOperations[blockIndex];
    if (blockOperation.affectedMemberCount == 0)
        return true;
    if (!isKnownLaneBlock(block))
        return blockOperation.kind == RawOperationKind::Copy;
    for (const size_t eventIndex : block.payloadEvents)
        if (rawPointStaysInPlace(operations, eventIndex))
            return true;
    return false;
}

bool relocationConflictsWithBlock(const ParsedEvents &parsed, const RawOperations &operations,
                                  std::span<const BlockOperation> blockOperations,
                                  const ProtocolEvent &source, size_t blockIndex,
                                  const Relocation &relocation) noexcept
{
    if (blockIndex == source.block)
        return false;
    const SelectorBlock &block = parsed.blocks[blockIndex];
    if (block.stream != source.stream)
        return false;
    if (!blockSurvivesInPlace(parsed, operations, blockOperations, blockIndex))
        return false;
    return block.firstTick <= relocation.tick && relocation.tick <= block.lastTick;
}

bool validateDestinations(const ParsedEvents &parsed, const RawOperations &operations,
                          std::span<const BlockOperation> blockOperations) noexcept
{
    for (const auto &[eventIndex, operation] : operations.byEvent) {
        if (operation.kind == RawOperationKind::Remove)
            continue;
        const ProtocolEvent &event = parsed.events[eventIndex];
        for (size_t blockIndex = 0; blockIndex < parsed.blocks.size(); ++blockIndex)
            if (relocationConflictsWithBlock(parsed, operations, blockOperations, event, blockIndex,
                                             *operation.relocation))
                return false;
    }
    return true;
}

void emitKnownPoint(std::vector<Emission> &inserts, const ProtocolEvent &event,
                    const SelectorBlock &block, const RawOperation *operation) noexcept
{
    if (operation == nullptr) {
        appendCanonicalPoint(inserts, event.tick, block.selector, event.value, event.channel);
        return;
    }
    if (operation->kind == RawOperationKind::Remove)
        return;
    if (operation->kind == RawOperationKind::Copy)
        appendCanonicalPoint(inserts, event.tick, block.selector, event.value, event.channel);
    const Relocation &relocation = *operation->relocation;
    appendCanonicalPoint(inserts, relocation.tick, block.selector, event.value, relocation.channel);
}

void appendVerbatimBlockEvents(std::vector<Emission> &inserts, const ParsedEvents &parsed,
                               const RawOperations &operations, const SelectorBlock &block) noexcept
{
    if (block.selectorEvent != SIZE_MAX)
        appendVerbatimEvent(inserts, parsed.events[block.selectorEvent],
                            *operations.byEvent.at(block.selectorEvent).relocation);
    for (const size_t eventIndex : block.payloadEvents)
        appendVerbatimEvent(inserts, parsed.events[eventIndex],
                            *operations.byEvent.at(eventIndex).relocation);
}

void emitKnownBlock(std::vector<Emission> &inserts, RemoveSet &removed, const ParsedEvents &parsed,
                    const RawOperations &operations, const SelectorBlock &block) noexcept
{
    if (block.selectorEvent != SIZE_MAX)
        removed.add(parsed.events[block.selectorEvent].source->index);
    for (const size_t eventIndex : block.payloadEvents)
        removed.add(parsed.events[eventIndex].source->index);
    for (const size_t eventIndex : block.payloadEvents) {
        const auto found = operations.byEvent.find(eventIndex);
        emitKnownPoint(inserts, parsed.events[eventIndex], block,
                       found == operations.byEvent.end() ? nullptr : &found->second);
    }
}

void emitOpaqueBlock(std::vector<Emission> &inserts, RemoveSet &removed, const ParsedEvents &parsed,
                     const RawOperations &operations, const SelectorBlock &block,
                     const BlockOperation &blockOperation) noexcept
{
    if (blockOperation.kind != RawOperationKind::Copy) {
        if (block.selectorEvent != SIZE_MAX)
            removed.add(parsed.events[block.selectorEvent].source->index);
        for (const size_t eventIndex : block.payloadEvents)
            removed.add(parsed.events[eventIndex].source->index);
        if (blockOperation.kind == RawOperationKind::Remove)
            return;
    }
    appendVerbatimBlockEvents(inserts, parsed, operations, block);
}

Patch emitRawReconciliation(const ParsedEvents &parsed, const RawOperations &operations,
                            std::span<const BlockOperation> blockOperations) noexcept
{
    RemoveSet removed;
    std::vector<Emission> inserts;
    for (size_t blockIndex = 0; blockIndex < parsed.blocks.size(); ++blockIndex) {
        const BlockOperation &blockOperation = blockOperations[blockIndex];
        if (blockOperation.affectedMemberCount == 0)
            continue;
        const SelectorBlock &block = parsed.blocks[blockIndex];
        if (isKnownLaneBlock(block))
            emitKnownBlock(inserts, removed, parsed, operations, block);
        else
            emitOpaqueBlock(inserts, removed, parsed, operations, block, blockOperation);
    }
    return finishPatch(std::move(removed), std::move(inserts));
}

} // namespace

Projection projectEvents(std::span<const Event> events) noexcept
{
    return toProjection(parseEvents(events));
}

std::optional<Patch> rewritePoints(std::span<const Event> events,
                                   std::span<const uint64_t> removeIdentities,
                                   std::span<const PointWrite> writes) noexcept
{
    const ParsedEvents parsed = parseEvents(events);
    auto normalized = normalizePointWrites(writes);
    if (!normalized)
        return std::nullopt;
    auto plan = planPointRewrite(parsed, removeIdentities, std::move(*normalized));
    if (!plan)
        return std::nullopt;
    return emitPointRewrite(parsed, *plan);
}

std::optional<Patch> reconcileRaw(std::span<const Event> events, std::span<const uint64_t> removals,
                                  std::span<const Relocation> moves,
                                  std::span<const Relocation> copies) noexcept
{
    const ParsedEvents parsed = parseEvents(events);
    const auto operations = collectRawOperations(parsed, removals, moves, copies);
    if (!operations)
        return std::nullopt;
    const auto blockOperations = classifyBlockOperations(parsed, *operations);
    if (!blockOperations)
        return std::nullopt;
    if (!validateDestinations(parsed, *operations, *blockOperations))
        return std::nullopt;
    return emitRawReconciliation(parsed, *operations, *blockOperations);
}

Patch canonicalizeForExport(std::span<const Event> events) noexcept
{
    const ParsedEvents parsed = parseEvents(events);
    RemoveSet removed;
    std::vector<Emission> inserts;
    for (const SelectorBlock &block : parsed.blocks) {
        if (isKnownLaneBlock(block)) {
            // The shared selector and raw payload bytes leave; every point
            // is re-emitted as an explicit same-tick selector+payload pair.
            appendPointRewriteBlockRemoval(parsed, block, removed);
            for (const size_t eventIndex : block.payloadEvents)
                emitKnownPoint(inserts, parsed.events[eventIndex], block, nullptr);
        } else if (block.selectorEvent != SIZE_MAX && block.payloadEvents.empty() &&
                   descriptorForSelector(block.selector)) {
            // A payload-less known selector is inaudible, and stock mid2agb
            // drops the wait that follows it: remove the dangling byte.
            removed.add(parsed.events[block.selectorEvent].source->index);
        }
        // Unknown selector epochs and stray payload runs stay byte-for-byte.
    }
    return finishPatch(std::move(removed), std::move(inserts));
}

} // namespace xcmd