# XCMD Behavior-Preserving Complexity Reduction

**Date:** 2026-08-27
**Status:** Implemented
**Scope:** The private implementation in `src/core/xcmd.cpp`, its unchanged
public seam in `src/core/xcmd.h`, and focused behavior checks. SongDocument,
view, AutomationCanvas, sidecar, project/backend, catalog, and playback changes
are out of scope.

This plan contains one behavior-preserving refactor. It reduces the complexity
of `rewritePoints` and `reconcileRaw` while keeping the currently supported
xIECV/xIECL descriptors, all protocol behavior, and every caller unchanged.
It does not prepare types, lane identities, UI mappings, or persistence for
additional XCMD commands.

The read-only OMP thermonuclear review required two corrections that apply to
this refactor:

1. Do not share one mixed-mode patch builder between canonical point rewrites
   and raw reconciliation.
2. Gate aggregate decision count as well as per-function CCN.

OMP's payload-metadata and named-lane-identity requirements remain prerequisites
for a future command-expansion plan. They are deliberately not implemented
speculatively here.

---

## 1. Goal and success criteria

Make `xcmd` easier to change without weakening its interface, protocol rules,
or observable behavior.

Success requires all of the following:

- Keep the public module interface centered on `projectEvents`,
  `rewritePoints`, and `reconcileRaw`.
- Preserve exact `Projection` and `Patch` results for all existing inputs.
- Preserve fail-without-mutation behavior: an unrepresentable edit returns
  `std::nullopt` before any caller mutates the document.
- Keep exactly the currently supported xIECV/xIECL descriptors. No selector,
  lane ID, descriptor field, UI mapping, adapter behavior, or persisted value
  may change.
- Reduce `reconcileRaw` from CCN 57 and `rewritePoints` from CCN 34 to small
  orchestration functions whose helpers express complete decisions rather
  than fragments of one branch cascade.
- Do not increase aggregate decision count while lowering per-function CCN.
- Keep event scans, copies, allocations, and asymptotic costs at or below the
  pre-refactor implementation unless a measured exception is approved.
- Pass focused checks, full verification, formatting, diff, and CC gates.

Lower CCN alone is not success. A refactor that distributes the same nested
logic across ordering-dependent thin wrappers fails this plan.

---

## 2. Current module and measured baseline

### 2.1 Public interface

`src/core/xcmd.h` currently exposes one deep in-process module:

```cpp
Projection projectEvents(std::span<const Event> events) noexcept;

std::optional<Patch> rewritePoints(
    std::span<const Event> events,
    std::span<const uint64_t> removeIdentities,
    std::span<const PointWrite> writes) noexcept;

std::optional<Patch> reconcileRaw(
    std::span<const Event> events,
    std::span<const uint64_t> removals,
    std::span<const Relocation> moves,
    std::span<const Relocation> copies) noexcept;
```

Keep this seam. Parsing, selector epochs, identity validation, collision
checks, and canonical rebuilds stay private to `xcmd.cpp`. Do not expose the
planned internal edit types for tests or callers.

### 2.2 Lizard baseline

Freeze these values again immediately before implementation because line
numbers and tool versions can drift:

| Function | CCN | NLOC | Current lines |
| --- | ---: | ---: | --- |
| `xcmd::reconcileRaw` | 57 | 169 | `xcmd.cpp:315-511` |
| `xcmd::rewritePoints` | 34 | 99 | `xcmd.cpp:186-300` |
| `parseEvents` | 12 | 55 | `xcmd.cpp:55-111` |

`parseEvents` is not a refactor target. Its CCN may remain at the frozen
baseline of 12; do not invent a parser decomposition to satisfy a lower
warning threshold.

Record the complete pre-edit CSV:

```sh
lizard -l cpp --csv src/core/xcmd.cpp \
  > /tmp/porydaw-xcmd-before.csv
```

### 2.3 Current protocol behavior

The current parser:

- consumes only CC `0x1D`, `0x1E`, and `0x1F` as XCMD protocol traffic;
- keeps one open selector block per engine stream;
- starts a new block on each selector event;
- treats payloads before a selector as one opaque stray run;
- treats an unknown selector, or a known selector without payload, as opaque;
- treats each payload under a registered one-byte selector as one logical
  point at the payload tick, identified by the payload event's raw index;
- reports every protocol byte as consumed so the generic CC projection does
  not display it again.

`rewritePoints` rebuilds every touched known epoch as explicit
selector-plus-payload pairs. `reconcileRaw` rebuilds known points canonically
but preserves opaque blocks byte-exactly through `Emission::sourceIndex`.

These are behavior contracts, not implementation suggestions.

---

## 3. Fixed scope and non-goals

### 3.1 Production files allowed to change

- `src/core/xcmd.cpp`
- `src/core/xcmd.h` only if an existing behavior comment must be clarified;
  do not change a declaration, type, constant, descriptor, or inline function

Do not add a production compilation unit. At roughly 512 lines, `xcmd.cpp`
still owns one cohesive implementation. Keep the completed file below the
repository's 600-line review threshold by replacing the branch cascades rather
than layering new code over them. If it still crosses 600 lines, stop and
report the gate; this plan does not authorize an implementation agent to
invent a new internal-header or compilation-unit split.

### 3.2 Check files allowed to change

- `src/checks/xcmdcheck.cpp`
- `CMakeLists.txt` only if `xcmdcheck.cpp` must be split after crossing 600
  lines

Prefer table-driven additions in `xcmdcheck.cpp`. Split the harness only if
the missing behavior assertions would push it past 600 lines or make its
projection, rewrite, and reconciliation sections hard to find. Do not create
several tiny check files merely to satisfy a line count.

### 3.3 Explicit non-goals

- No new XCMD selector, lane ID, descriptor field, or descriptor row.
- No `LaneId`, payload-width metadata, or byte-order metadata.
- No SongDocument, view-model, M4A semantics, AutomationCanvas, or sidecar
  change.
- No project/backend change.
- No `SongDocument` interface redesign.
- No new class hierarchy, virtual interface, strategy object, or callback
  dispatch per XCMD selector.
- No generic protocol framework shared with MEMACC.
- No playback-engine or `external/poryaaaa` change.
- No editable xWAVE (`0x01`), XCMD `0x0D`, xWAIT (`0x0C`), or other currently
  unsupported selector.
- No support for values above 127 while the editor writes MIDI CC payloads.

---

## 4. Future-extension safety boundary

This refactor must leave later command work safe without trying to design it.
The current two-row descriptor registry and all public types remain
byte-for-byte unchanged.

Future safety comes from existing opaque handling:

- unknown-selector epochs project no logical points;
- all of their protocol bytes remain consumed rather than leaking into generic
  CC lanes;
- point rewrites reject writes inside their occupied spans; and
- raw reconciliation permits only whole-block, byte-exact remove, move, or
  copy operations.

Therefore a project containing an unsupported future command remains visible
as protocol traffic to `xcmd`, but the editor does not partially recognize or
silently re-encode it.

A later command-expansion plan must define its own lane identities, descriptor
payload metadata, command grouping and identity, UI value model, adapter
cutover, persistence rules, and compatibility checks before adding any
selector. None of those future decisions belongs in this refactor.

---

## 5. Internal module design

### 5.1 Keep parser ownership private

Keep `SelectorBlock`, `ProtocolEvent`, `ParsedEvents`, operation planning, and
emission helpers in the unnamed namespace in `xcmd.cpp`.

Do not add a public parsed-command object. `Projection` and `Patch` remain the
interface used by callers and checks.

### 5.2 Reject the mixed-mode shared builder

Do not implement the initial proposal's one shared patch accumulator with both
canonical and source-indexed capabilities.

`rewritePoints` can only emit canonical controller bytes. `reconcileRaw` can
emit canonical bytes for known points and verbatim source-indexed bytes for
opaque blocks. Giving the rewrite path a verbatim method weakens its internal
interface and spreads the existing `sourceIndex != SIZE_MAX` mode flag.

Use planner-local removal and insertion storage. Sharing is limited to the
branch-free `finishPatch` finalizer declared below.

`finishPatch` may only:

1. seal the removal set;
2. move its sorted, deduplicated indices into `Patch::removeEvents`;
3. stable-sort insertions by tick;
4. move them into `Patch::inserts`.

It must not inspect `Emission::sourceIndex`, select an emission mode, validate
protocol meaning, or decide whether an edit is allowed.

Use separate private emission functions. `appendCanonicalPoint` is available
to both planners. `appendVerbatimEvent` is called only from raw
reconciliation's opaque block emitter.

Neither function owns ordering or validation.

Use these exact declarations. They remain in the unnamed namespace in
`xcmd.cpp`; do not publish them in `xcmd.h`:

```cpp
void appendCanonicalPoint(std::vector<Emission> &inserts, uint64_t tick,
                          uint8_t selector, uint8_t value,
                          uint8_t channel) noexcept;

void appendVerbatimEvent(std::vector<Emission> &inserts,
                         const ProtocolEvent &event,
                         const Relocation &relocation) noexcept;

Patch finishPatch(RemoveSet removed,
                  std::vector<Emission> inserts) noexcept;
```

`appendCanonicalPoint` appends exactly these two values, in this order:

```cpp
Emission{tick, kSelectorController, selector, SIZE_MAX, channel}
Emission{tick, kPayloadController, value, SIZE_MAX, channel}
```

`appendVerbatimEvent` appends exactly:

```cpp
Emission{relocation.tick, 0, 0, event.source->index, relocation.channel}
```

Neither helper may look up descriptors, validate identities, choose an
operation, sort, deduplicate, or return failure.

### 5.3 Point-rewrite planning

Refactor `rewritePoints` around complete private decisions:

```text
parseEvents
  -> normalizePointWrites
  -> planPointRewrite
  -> emitPointRewrite
  -> finishPatch
```

The internal results should carry facts, not callbacks:

- `normalizePointWrites` validates lane descriptors and produces the active
  write list with later `(stream, tick, lane)` writes winning.
- `planPointRewrite` validates every removed identity, marks blocks touched by
  removal or insertion, and rejects any write inside an opaque occupied span.
- `emitPointRewrite` removes whole touched epochs, preserves non-removed and
  non-replaced known points, and appends requested writes.

Use these exact private types and declarations:

```cpp
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

std::optional<NormalizedPointWrites>
normalizePointWrites(std::span<const PointWrite> writes) noexcept;

std::optional<PointRewritePlan>
planPointRewrite(const ParsedEvents &parsed,
                 std::span<const uint64_t> removeIdentities,
                 NormalizedPointWrites writes) noexcept;

Patch emitPointRewrite(const ParsedEvents &parsed,
                       const PointRewritePlan &plan) noexcept;
```

`normalizePointWrites` is the only helper that rejects an unknown lane and the
only helper that applies later-write-wins normalization.
`planPointRewrite` is the only helper that resolves removal identities, rejects
a selector or opaque identity, marks touched known blocks, and rejects a write
inside an opaque occupied span. `emitPointRewrite` receives a valid plan and
must not return failure; it owns whole-epoch removal, survivor/replacement
decisions, value clamping, canonical emission, and the call to `finishPatch`.

Do not replace the current small-vector duplicate scan with a map solely to
lower CCN. Preserve its allocation and asymptotic behavior unless a measured
workload proves a change is better. A helper may own the scan, but it must
return a concrete normalized list and keep the later-write-wins rule visible.

### 5.4 Raw reconciliation planning

Refactor `reconcileRaw` around these complete private decisions:

```text
parseEvents
  -> collectRawOperations
  -> classifyBlockOperations
  -> validateDestinations
  -> emitRawReconciliation
  -> finishPatch
```

- `collectRawOperations` resolves every source identity and rejects stale,
  mixed, or conflicting duplicate operations.
- `classifyBlockOperations` derives one block-level operation summary and
  rejects partial or mixed opaque-block edits. Known selector bytes remain
  protocol glue; payload operations determine their rebuild.
- `validateDestinations` decides which source spans survive in place and
  rejects a move/copy landing inside another surviving span on the same
  stream.
- `emitRawReconciliation` rebuilds known points canonically and handles an
  opaque block only as one byte-exact remove, move, or copy.

Use these exact private types and declarations:

```cpp
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

std::optional<RawOperations>
collectRawOperations(const ParsedEvents &parsed,
                     std::span<const uint64_t> removals,
                     std::span<const Relocation> moves,
                     std::span<const Relocation> copies) noexcept;

std::optional<std::vector<BlockOperation>>
classifyBlockOperations(const ParsedEvents &parsed,
                        const RawOperations &operations) noexcept;

bool blockSurvivesInPlace(const ParsedEvents &parsed,
                          const RawOperations &operations,
                          std::span<const BlockOperation> blockOperations,
                          size_t blockIndex) noexcept;

bool validateDestinations(const ParsedEvents &parsed,
                          const RawOperations &operations,
                          std::span<const BlockOperation> blockOperations) noexcept;

Patch emitRawReconciliation(
    const ParsedEvents &parsed,
    const RawOperations &operations,
    std::span<const BlockOperation> blockOperations) noexcept;
```

`collectRawOperations` is the only helper that resolves raw identities and
rejects unknown identities, mixed operation kinds on one event, or conflicting
duplicate destinations. `classifyBlockOperations` is the only helper that
counts block members and rejects a mixed or partial opaque-block edit.
Opaque-block members must share one operation kind, but each moved or copied
member retains its own relocation tick and channel; no common delta or channel
is required.

Known selector-byte operations are collected and destination-validated, but
do not increment `affectedMemberCount` and do not independently cause removal
or emission. Payload operations determine whether a known block is rebuilt.

`blockSurvivesInPlace` is a pure query used only by `validateDestinations`.
`validateDestinations` is the only helper that rejects a move or copy landing
inside another surviving epoch on the same stream. `emitRawReconciliation`
receives validated facts and must not return failure; it owns known-point
canonical rebuilds, opaque whole-block emission, and the call to
`finishPatch`.

No planner type owns `Event`, `PointWrite`, or `Relocation` values. Pointers in
the plans borrow only from the spans passed to the public function and never
escape that call. Do not replace these declarations with a planner class,
callbacks, `std::function`, a variant hierarchy, or public test seam.

The destination rule must remain a named, inspectable loop. Do not move it
into `std::function`, a generic visitor, a range predicate with shared mutable
state, or template dispatch merely to reduce Lizard output.


---

## 6. Behavior invariants to freeze

Before production edits, confirm or add exact assertions in `xcmdcheck` for
all of these contracts:

### 6.1 Projection

- One selector followed by two one-byte payloads projects two points.
- Point tick and identity come from the terminal payload event.
- Different engine streams never share selector state.
- Payloads before the first selector form an opaque stray run.
- Unknown selectors remain opaque and produce no points.
- A known selector without a payload remains opaque.
- Every selector/payload protocol byte appears once in sorted `consumed`.

### 6.2 Point rewrite

- An empty-track write emits one explicit selector-plus-payload pair.
- A matching active selector is not reused implicitly.
- Replacing a point rebuilds its whole epoch.
- Deleting one of two shared-selector points rebuilds the survivor as an
  explicit pair.
- Removing the final point removes the dead selector epoch.
- Later duplicate writes to the same `(stream, tick, lane)` win.
- Unknown lanes and stale/opaque identities reject.
- A write inside an opaque occupied span rejects.
- A write inside an opaque stray-run span rejects.
- A write inside a known span rebuilds that span.
- Values clamp to the registered descriptor range.
- Same-tick insertion order remains stable.

### 6.3 Raw reconciliation

- Unknown identities reject.
- A repeated identical operation is accepted; conflicting duplicates reject.
- Mixed operation kinds on one byte reject.
- A known selector byte may be addressed as protocol glue without splitting
  the logical point rules. Its operation is destination-validated but does not
  drive the block rebuild; a valid selector-only operation yields an empty
  patch.
- A partial opaque remove/move/copy rejects.
- A whole opaque remove succeeds without insertions.
- A whole opaque move/copy uses byte-exact source-indexed emissions.
- Known-point move/copy emits canonical selector-plus-payload pairs.
- Copy keeps the source point; move removes it.
- Destinations inside another surviving epoch span reject.
- Destinations inside a fully vacated span succeed.
- An event may land in its own rebuilt epoch span.
- Final removals are sorted/deduplicated and inserts are stable-sorted by tick.

Tests must assert complete vectors where practical. Count-only checks are not
enough to freeze emission ordering or source-index semantics.

---

## 7. Ordered implementation phases

The phases form one behavior-preserving refactor. No phase may change lane
identity, descriptor shape, adapters, UI mapping, or persistence.

### Phase 0 — Freeze evidence and contracts

Production changes: none.

1. Record Git status, HEAD, Lizard version, and the baseline CSV.
2. Run current `xcmdcheck`, `editcheck`, `viewcheck`,
   `automationgesturecheck`, and `rollcheck`.
3. Audit `xcmdcheck` against Section 6.
4. Add only missing exact assertions; do not refactor the harness yet.
5. Record current `Projection`/`Patch` outputs for all new assertions.

Gate:

```sh
deno task verify --filter xcmdcheck --verbose
deno task verify --filter editcheck --verbose
deno task verify --filter viewcheck --verbose
deno task verify --filter automationgesturecheck --verbose
deno task verify --filter rollcheck --verbose
```

### Phase 1 — Refactor `rewritePoints`

1. Add `NormalizedPointWrites` and `PointRewritePlan` with the exact fields and
   declarations from Section 5.3.
2. Extract `normalizePointWrites`, `planPointRewrite`,
   `emitPointRewrite`, `appendCanonicalPoint`, and branch-free
   `finishPatch` only as justified by Section 5.
3. Keep current scans, ordering, and allocation shape.
4. Compare every frozen `Patch` exactly.
5. Run Lizard and report leaf plus aggregate results before continuing.

Gate: `rewritePoints <= 7`; every rewrite-only helper `<= 7`; aggregate gate
in Section 8 passes.

### Phase 2 — Refactor `reconcileRaw`

1. Add `RawOperationKind`, `RawOperation`, `RawOperations`, and
   `BlockOperation` with the exact fields and declarations from Section 5.4.
2. Extract `collectRawOperations`, `classifyBlockOperations`,
   `blockSurvivesInPlace`, `validateDestinations`,
   `emitRawReconciliation`, and `appendVerbatimEvent` as defined in Section 5.
3. Reuse only `appendCanonicalPoint` and branch-free `finishPatch` from the
   rewrite path.
4. Preserve all opaque-block rejection and byte-exact emission rules.
5. Compare every frozen `Patch` exactly.
6. Run Lizard and report leaf plus aggregate results before continuing.

Gate: `reconcileRaw <= 7`; every reconciliation-only helper `<= 7`;
aggregate gate in Section 8 passes.

### Phase 3 — Full verification and cleanup

1. Delete only obsolete local helpers, includes, and comments made unused by
   the planner cutover.
2. Confirm the diff contains no public declaration, descriptor, selector,
   lane, adapter, UI, or sidecar change.
3. Run the complete verification sequence in Section 10.
4. Produce the final report from Section 12.
5. Report any gate that cannot be proved; do not convert an unproved gate into
   a pass by assertion.

No old and new planner implementation may coexist after this phase.

---

## 8. Cyclomatic-complexity gates

Use Lizard's ordinary McCabe CCN, not modified CCN.

### 8.1 Per-function gates

- `rewritePoints <= 7`
- `reconcileRaw <= 7`
- every extracted edit helper `<= 7`
- `parseEvents <= 12` and unchanged in structure
- no newly changed production function above `10`

### 8.2 Aggregate gates

For a planner path, calculate:

```text
sum(max(CCN - 1, 0))
```

This removes each function's unavoidable base path and counts decisions that
could otherwise be hidden by extraction.

- The rewrite aggregate includes `rewritePoints` and every helper used only by
  it, including any permitted duplicate-scan helper, and must be `<= 33`
  (baseline aggregate `34 - 1`).
- The reconciliation aggregate includes `reconcileRaw`,
  `collectRawOperations`, `classifyBlockOperations`, `blockSurvivesInPlace`,
  `validateDestinations`, `emitRawReconciliation`, `appendVerbatimEvent`, and
  any additional helper used only by that path, and must be `<= 56` (baseline
  aggregate `57 - 1`).
- Shared `appendCanonicalPoint` and `finishPatch` are reported separately and
  counted once in the whole-module total.
- `parseEvents`, `toProjection`, and projection-only helpers are excluded from
  the two planner aggregates but included in the whole-module total.
- Whole `xcmd.cpp` aggregate must not exceed its pre-edit total.

The target is to lower these values where real decisions can be removed. The
hard gate prevents a false improvement obtained by moving the same decisions
into more functions.

Also report:

- maximum nested decision depth before and after;
- function count before and after;
- `xcmd.cpp` NLOC before and after;
- any helper below 10 NLOC, with a one-line reason it earns its name.

Reject the implementation if it uses `std::function`, template dispatch,
mutable range predicates, or a visitor solely to hide a decision from Lizard.

Suggested warning commands:

```sh
lizard -C 7 -w src/core/xcmd.cpp
lizard -C 10 -w src/core/xcmd.cpp
lizard --csv src/core/xcmd.cpp > /tmp/porydaw-xcmd-after.csv
```

The `-C 7` and `-C 10` warning runs may contain `parseEvents` only, and only
while it stays at or below its unchanged baseline of 12.

---

## 9. Performance and allocation gates

This code runs during view projection and document edits, not in the audio
callback. The playback benchmark skill does not apply unless implementation
work changes playback or timeline scheduling outside this plan.

Preserve these structural costs:

- one `parseEvents` pass per public operation;
- one per-stream open-block table, not a map keyed by stream;
- no new per-event heap allocation;
- no copy of the input `Event` span;
- no `std::function` or virtual dispatch;
- no extra full pass over events solely to format the patch;
- stable-sort insertions once and sort/deduplicate removals once;
- no new map allocation in point-write deduplication without measurement;
- descriptor lookup remains bounded by the small compile-time table.

If an implementation changes an asymptotic cost, container type, or number of
event passes, stop and add a deterministic Release microbenchmark before
accepting it. Process startup timing of `porydaw_checks --xcmdcheck` is not a
valid substitute for an in-process workload.

---

## 10. Verification sequence

Use repository tasks; do not invoke CMake directly.

```sh
deno task format --check \
  src/core/xcmd.h \
  src/core/xcmd.cpp \
  src/checks/xcmdcheck.cpp

deno task build:checks

deno task verify --filter xcmdcheck --verbose
deno task verify --filter editcheck --verbose
deno task verify --filter viewcheck --verbose
deno task verify --filter automationgesturecheck --verbose
deno task verify --filter rollcheck --verbose

lizard -C 7 -w src/core/xcmd.cpp
lizard -C 10 -w src/core/xcmd.cpp
lizard --csv src/core/xcmd.cpp > /tmp/porydaw-xcmd-after.csv

deno task verify
git diff --check
git status --short
```

If native-window checks fail because no screen is available, rerun them in a
native session before calling the change a product regression. Report the
first environment-limited result and the native rerun separately.

---

## 11. Deferred command expansion

No additional one-byte or multi-byte selector becomes editable in this work.
Unknown selectors, including xWAVE (`0x01`) and XCMD `0x0D`, stay opaque.

A later plan must define the following before adding any command:

- stable lane IDs and their compatibility policy;
- payload width and byte order in the descriptor model;
- grouping payload events into one completed logical command;
- one stable logical identity, normally the terminal payload event index;
- terminal-payload tick semantics when source payload bytes have different
  ticks;
- canonical decode and re-encode behavior;
- behavior for a complete command followed by an incomplete tail under the
  same sticky selector;
- whole-command raw remove/move/copy validation;
- the UI value width, formatting, edit controls, and transport limits;
- the exact view-model and M4A-semantics cutover;
- persistence behavior and compatibility checks for any new stored lane
  identity.

Until that model exists, unknown selector epochs remain opaque and
byte-preserving. Do not partially recognize their payloads.

xWAIT (`0x0C`) remains unsupported because the MIDI ingress has no song-script
program counter to stall and the driver reports zero payload length.

---

## 12. Final report requirements

The implementation handoff must include:

- changed files grouped as core module and checks;
- focused and full verification results;
- before/after per-function CCN;
- before/after aggregate `sum(max(CCN - 1, 0))` for each planner path and the
  whole module;
- nesting, function-count, and NLOC comparison;
- confirmation that public declarations and the existing xIECV/xIECL
  descriptors, IDs, and behavior remain unchanged;
- confirmation that every other selector remains opaque/unsupported as
  specified;
- confirmation that no adapter, UI, sidecar, project, or playback file changed;
- any performance or allocation shape change;
- every plan gate that could not be proved;
- final Git status.

Do not commit, stage, or push during implementation unless the user gives new
authorization.
