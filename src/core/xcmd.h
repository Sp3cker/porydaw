#pragma once

#include "core/timedefaults.h"
#include <array>
#include <cstdint>
#include <optional>
#include <span>
#include <vector>

// Deep XCMD module: descriptor metadata, a read projection of known logical
// points, one logical lane rewrite, and one raw reconciliation. All protocol
// parsing lives privately in xcmd.cpp; callers translate a flat
// Projection/Patch into their own edit operations.
//
// Decode model: a selector event (CC 0x1E) opens an epoch; payload events
// (CC 0x1D/0x1F) complete it. Selectors 0x08 (echo volume) and 0x09 (echo
// length) yield one logical point per payload byte. Any other selector
// epoch, a payload-less epoch, and payload events before the first selector
// are opaque blocks, preserved byte-for-byte. Every emitted point is an
// explicit selector+payload pair — no selector sharing or restoration.

namespace xcmd {

inline constexpr uint8_t kSelectorController = 0x1E;
inline constexpr uint8_t kPayloadController = 0x1D;
inline constexpr uint8_t kAlternatePayloadController = 0x1F;
inline constexpr uint8_t kEchoVolumeLane = 0xFB;
inline constexpr uint8_t kEchoLengthLane = 0xFC;

struct Descriptor {
    uint8_t laneController = 0;
    uint8_t selector = 0;
    uint8_t minimumValue = 0;
    uint8_t maximumValue = 127;
    uint8_t defaultValue = 0;
    const char *mnemonic = "";
    const char *displayName = "";
};

inline constexpr std::array<Descriptor, 2> kLaneDescriptors{
    Descriptor{kEchoVolumeLane, 0x08, 0, 127, 0, "xIECV", "Echo volume"},
    Descriptor{kEchoLengthLane, 0x09, 0, 127, 0, "xIECL", "Echo length"},
};

constexpr std::span<const Descriptor> laneDescriptors() noexcept
{
    return kLaneDescriptors;
}

constexpr const Descriptor *descriptorForLane(uint8_t controller) noexcept
{
    for (const Descriptor &descriptor : kLaneDescriptors)
        if (descriptor.laneController == controller)
            return &descriptor;
    return nullptr;
}

constexpr const Descriptor *descriptorForSelector(uint8_t selector) noexcept
{
    for (const Descriptor &descriptor : kLaneDescriptors)
        if (descriptor.selector == selector)
            return &descriptor;
    return nullptr;
}

constexpr bool isLaneController(uint8_t controller) noexcept
{
    return descriptorForLane(controller) != nullptr;
}

// ---------------------------------------------------------------------------
// Read projection. Callers adapt their own event type into this flat view;
// points keep caller stream order. `index` is the caller's raw index and
// stays opaque to the module. `channel` propagates through rebuilds of
// existing points.
// ---------------------------------------------------------------------------

struct Event {
    uint64_t index = 0;
    Tick tick = 0;
    uint8_t stream = 0; // decoder stream identity (engine track ordinal)
    uint8_t controller = 0;
    uint8_t value = 0;
    uint8_t channel = 0; // MIDI channel of the source event
};

struct Point {
    uint8_t lane = 0;   // descriptor laneController (known points only)
    Tick tick = 0;      // terminal payload byte tick
    uint32_t value = 0; // decoded payload value
    uint64_t index = 0; // raw index of the payload byte (identity)
    uint8_t stream = 0;
    uint8_t channel = 0;
};

struct Projection {
    std::vector<Point> points;      // completed known points, scan order
    std::vector<uint64_t> consumed; // raw indices absorbed by the protocol
};

// One pass over a caller-adapted event list (all streams at once), in
// caller stream order. Callers build it once per track/edit batch.
Projection projectEvents(std::span<const Event> events) noexcept;

// ---------------------------------------------------------------------------
// Export-compatibility assessment of the protocol traffic. Read-only lens
// over the same per-stream parse projectEvents uses — never a presentation
// verdict. Converter mapping (bundled mid2agb, agb.cpp): CC 0x1E only
// latches the extended-command register and emits nothing; the payload CCs
// 0x1D/0x1F route to PrintExtendedOp, which emits the game commands XCMD
// xIECV (selector 0x08) and XCMD xIECL (selector 0x09) and falls back to a
// bare PrintWait for every other selector. So only complete 0x08/0x09
// pairs export; all other opaque traffic is byte-preserved here but never
// becomes a game command.
// ---------------------------------------------------------------------------

enum class TrafficKind : uint8_t {
    CompleteEchoPoints,   // known 0x08/0x09 epoch with payload bytes
    DanglingSelector,     // known 0x08/0x09 epoch with zero payload bytes
    UnknownSelectorEpoch, // selector outside the known set (payloads optional)
    StrayPayloads,        // payload bytes before any selector in their stream
};

enum class ExportClass : uint8_t {
    Supported,   // converter emits the game command (XCMD xIECV / xIECL)
    NotExported, // converter drops it (PrintExtendedOp default: PrintWait)
    NeedsReview, // unresolved or incomplete protocol traffic
};

struct EchoPointCounts {
    uint32_t volume = 0; // complete selector-0x08 payload bytes (xIECV)
    uint32_t length = 0; // complete selector-0x09 payload bytes (xIECL)
};

struct TrafficBlock {
    TrafficKind kind = TrafficKind::StrayPayloads;
    ExportClass exportClass = ExportClass::NeedsReview;
    uint8_t stream = 0;
    uint8_t selector = 0;      // epoch selector; unset for StrayPayloads
    uint32_t payloadCount = 0; // payload bytes; == logical points when complete
    Tick firstTick = 0;        // occupied tick span (selector and payloads)
    Tick lastTick = 0;
};

struct TrafficAssessment {
    EchoPointCounts echoPoints;       // completed logical points, per selector
    std::vector<TrafficBlock> blocks; // every protocol block, scan order
};

// Classify every per-stream protocol block. Complete 0x08/0x09 pairs are
// Supported and counted per selector; unknown-selector epochs are
// NotExported; dangling known selectors (incomplete) and stray payload runs
// (unresolved: the converter would print them against whatever the register
// held earlier) are NeedsReview.
TrafficAssessment assessTraffic(std::span<const Event> events) noexcept;

// ---------------------------------------------------------------------------
// Logical lane rewrite: remove known point identities and write known lane
// points. Any epoch owning a removed point or containing a write tick is
// rebuilt — its bytes leave and its surviving points are re-emitted as
// explicit selector+payload pairs. Writes land as canonical pairs. Opaque
// traffic is preserved; the rewrite is rejected (nullopt) when a write
// would land inside an opaque block's occupied tick span or when any
// identity or lane is unknown.
// ---------------------------------------------------------------------------

struct PointWrite {
    Tick tick = 0;
    uint8_t lane = 0; // descriptor laneController
    uint8_t value = 0;
    uint8_t stream = 0;
    uint8_t channel = 0; // MIDI channel stamped on emitted events
};

// ---------------------------------------------------------------------------
// Raw reconciliation: plain removals plus source-indexed relocations and
// copies. A known point's move/copy is rebuilt canonically; an opaque epoch
// may only be removed, moved, or copied as a whole block with one
// operation, byte-exact via Emission::sourceIndex. Unknown identities,
// partial or mixed block operations, and destinations inside the occupied
// span of an epoch whose bytes survive the rewrite reject. Spans vacated by
// this edit (fully removed or fully relocated blocks) accept destinations.
// ---------------------------------------------------------------------------

struct Relocation {
    uint64_t index = 0; // raw index of the event to re-insert
    Tick tick = 0;      // destination tick
    uint8_t channel = 0;
};

// ---------------------------------------------------------------------------
// Flat patch: raw indices to remove plus ordered controller emissions to
// insert. `sourceIndex` marks a byte-exact re-insertion of an existing
// event (the caller copies that event's bytes and re-stamps its tick);
// otherwise `controller`/`value` is a canonical emission on `channel`.
// ---------------------------------------------------------------------------

struct Emission {
    Tick tick = 0;
    uint8_t controller = 0;
    uint8_t value = 0;
    uint64_t sourceIndex = SIZE_MAX; // verbatim re-insertion source
    uint8_t channel = 0;
};

struct Patch {
    std::vector<uint64_t> removeEvents; // ascending, deduplicated
    std::vector<Emission> inserts;      // ordered final-stream order
};

// Remove Point::index identities and write known lanes canonically. A write
// repeating the same (stream, tick, lane) replaces the earlier one (later
// write wins).
std::optional<Patch> rewritePoints(std::span<const Event> events,
                                   std::span<const uint64_t> removeIdentities,
                                   std::span<const PointWrite> writes) noexcept;

std::optional<Patch> reconcileRaw(std::span<const Event> events, std::span<const uint64_t> removals,
                                  std::span<const Relocation> moves,
                                  std::span<const Relocation> copies) noexcept;

// Export canonicalization for SMF saves: every known 0x08/0x09 epoch with
// payloads is rebuilt as explicit same-tick selector+payload pairs, a
// payload-less known selector is removed outright (stock mid2agb drops the
// wait that follows it), and unknown selector epochs plus stray payload
// runs are omitted from the patch — byte-for-byte preserved. Removals
// reference source indices only; inserts are canonical emissions only.
Patch canonicalizeForExport(std::span<const Event> events) noexcept;

} // namespace xcmd