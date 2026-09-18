# spec.md — Swift roll production mount: behavior contract

Wave 3 of the Swift backend track ([plan.md](plan.md)). This file fixes
the agreed behavior and the shared vocabulary; briefs cite it and never
restate it.

## §1 Scope and non-goals

The Swift note grid renders a real `SongDocument` inside the production
window, read-only, behind `PORYDAW_SWIFT_ROLL=1`. Non-goals (this wave,
explicitly): key delivery to Swift, Swift-originated edits, undo crossing,
selection sharing, popup sessions, pitch editing surfaces, TimeCamera /
Grid / PitchBendKernel numeric work, any user-visible surface without the
flag. Flag off = zero behavior change, zero load-time cost beyond a linked
library.

Retirement is governed by the charter's
[Compatibility and retirement decision](../swift-backend-charter.md#compatibility-and-retirement-decision-2026-09-18),
not by demo API compatibility. This wave retires demo initialization and
standalone app/selftest entry points **from the production path** only;
fixtures and the standalone lane still needed by acceptance remain.
Read-only mounting does not meet the editable/default cutover gates for
local undo, the rollout flag/old renderer, or duplicate behavioral checks,
nor does it by itself retire callable parity adapters. The production
grid and document feed are built to stay, while enumerated overlay-only
machinery has the charter's removal gate. INV-3's window/focus/keymap host
boundary remains permanent; this wave neither rewrites production undo nor
declares the current C++ document seam eternal.

## §2 The `sgd_` snapshot ABI

Declared in `src/ui/songview/quick/swiftgrid/document_feed.h`; imported
through the dedicated `SwiftGridDocumentFeed` Clang module in that directory's
`module.modulemap`. This is production state delivery, not a compatibility
shim. Snapshot payloads contain copied values, never Qt/document objects.

```c
typedef struct {
    int32_t trackIndex;
    int32_t key;
    uint32_t onTick;         // SongDocument Tick, not demo tick space
    uint32_t durationTicks;
    int32_t velocity;
} SgdNote;

typedef struct {
    uint32_t startTick;
    uint8_t numerator;      // raw SMF value; normalization belongs to TimeAxis
    uint8_t denomPow2;      // raw exponent, not a computed denominator
} SgdTimeSignature;

typedef struct {
    uint64_t documentId;     // unique nonzero token for this feed lifetime
    uint64_t revision;       // SongDocument::revision()
    int32_t ticksPerBeat;    // SongDocument::smf().division
    int32_t trackCount;
    int32_t noteCount;
    int32_t timeSignatureCount;
} SgdDocumentHeader;

typedef void (*SgdDeliveryFn)(const SgdDocumentHeader *header,
                             const SgdNote *notes,
                             const SgdTimeSignature *signatures,
                             void *context);
typedef struct {
    SgdDeliveryFn fn;
    void *context;
} SgdDelivery;

void sgd_register_feed(uint64_t document_id, SgdDelivery *delivery);
void sgd_unregister_feed(uint64_t document_id);
bool sgd_set_delivery(uint64_t document_id, SgdDeliveryFn fn, void *context);
void sgd_clear_delivery(uint64_t document_id);
```

- **Per-feed binding.** Each `SwiftGridDocumentFeed` owns a zero-initialized
  `SgdDelivery`; there is no singleton active document or callback. The host
  mints a process-unique, nonzero `uint64_t` token at feed construction, never
  reuses it, and binds it to that feed's fixed `const SongDocument &`.
  Exhaustion must fail, never wrap/reuse. `documentId` identifies this lifetime
  binding, not an undo history position, file path, address cast, or new core
  accessor. It stays constant over edits/undo/redo; remount gets a fresh token.
- **Live endpoint routing.** `document_feed.cpp` owns a GUI-thread-only map
  from token to borrowed `SgdDelivery *`, registered by the host feed before
  QML creation and erased by its destructor. This is a routing table only:
  no document pointer, snapshot cache, Swift retain or closed endpoint survives
  unregister. Register requires unique nonzero id and an empty slot; duplicate
  registration is an invariant failure. Set returns false for absent id,
  null callback/context or an already-bound slot, otherwise binds exactly once.
  Clear nulls both fields; unregister clears then erases. Clear/unregister
  of an absent id are harmless for idempotent teardown.
- **Host observer.** `SwiftGridDocumentFeed(const SongDocument &)` exposes
  `uint64_t documentId() const`, `SgdDelivery *delivery()`, and
  `void pushSnapshot()`. It observes `documentChanged()` and pushes one complete
  snapshot per emission, using `engineTrackCount()`, `notesForTrack()`,
  `smf().division`, `timeSigs()`, and `revision()`. No constructor delivery:
  host binds the recipient, then explicitly calls `pushSnapshot()` once.
- **Per-grid Swift guard.** `DocumentFeed(documentId: UInt64)` owns one immutable
  nonzero identity, `appliedRevision: UInt64?`, and `document: SgdDocument?`.
  `apply(header:notes:signatures:) -> Bool` first rejects unrelated identities,
  then accepts the first snapshot (including revision zero) or a strictly
  greater revision. Equal/lower revisions never replace values or notify.
  `onDocument: ((SgdDocument) -> Void)?` notifies only accepted snapshots.
  One grid owns one receiver; no changing identities to reset the guard, global
  cache, fallback document, or retention of closed documents.
  `connect() -> Bool` registers its C trampoline and unretained self context
  through `sgd_set_delivery`; `disconnect()` clears the endpoint and is also
  called at receiver destruction. The grid owns the receiver while connected.
- **Call lifetime.** All creation, binding, delivery, and destruction occur on
  the GUI/main thread, synchronously. Array pointers are call-scoped borrows
  (null permitted for count zero); Swift copies accepted data before return.
  `sgd_set_delivery` only binds, never pushes; clear nulls both fields.
  Destructor disconnects the document signal and clears delivery before the
  Swift recipient can be released. No delivery after teardown.

## §3 Read-only grid mode

`PianoGrid.readOnly: Bool` defaults to `false`; `init()` is empty in both
lanes. Production QML supplies `readOnly: true` before component completion,
never initializes demo notes/controllers or local undo. Prototype `App.swift`
explicitly initializes demo audio then calls `resetDemo()` on its editable grid.
`AudioSession.init()` is inert; only explicit `initializeDemo()` accesses the
bundled fixture/native audio session. Production never attempts fixture loading
or uses a missing-fixture fallback. That demo path remains only until its
charter retirement gate.

- User mutation entry points are inert: draw/move/resize, double-click
  add/remove, controller edits, selection changes, menu/pitch opening and
  commits, undo/redo, and demo reset. They produce no musical-state, selection,
  undo, or revision change. Escape has no open edit session to resolve.
- Pan, zoom, hover and keyboard-gutter hover preview remain real and live;
  host accepts pointer/wheel events and routes normalized viewing input,
  never forwards it to the C++ editing surface underneath. No keys enter Swift.
- Accepted document snapshots and selected-track changes are the explicit
  host-driven exception: they replace rendered notes, never record `GridUndo`,
  and preserve current viewport scroll/zoom. Feed revision is `UInt64`;
  viewport/track changes do not increment it.
- `PianoGrid.bindDocumentFeed(_ feed: DocumentFeed, trackIndex: Int)` binds
  once before initial push; callback capture does not create a retain cycle.
  `loadDocument(_ document: SgdDocument, trackIndex: Int)` maps only matching
  bound identity, filtering notes by engine-track index without tick
  re-quantization. `setDocumentTrack(_ trackIndex: Int)` re-filters the current
  accepted snapshot without passing it through the revision guard again.
  Invalid/no selected track renders no notes, never another track.
- Metrics and scene generation consume actual document ticks-per-beat and
  raw signature fields through the existing Swift `TimeMap` / `TimeSigPoint`
  / `TimeAxis` semantics. Preserve every imported UInt8 numerator/exponent,
  including zero numerator and exponents >=31; do not expand denominators or
  reject events at the feed boundary. `TimeAxis` already owns normalization,
  bounded beat-stride shifts, implicit opening 4/4 and coincident-event
  last-wins precedence. Notes remain in document tick space; demo defaults
  remain unchanged. Parameterize the existing grid geometry/scene path using
  those values; do not duplicate math, edit frozen Wave-1 sources, or convert
  TimeCamera/Grid/PitchBendKernel.
- Unmount releases grid, receiver, accepted snapshot and callback together.
  Existing editable smoke outcomes remain required, not permanent demo API
  compatibility.

## §4 Production mount and ownership ABI

`PORYDAW_SWIFT_ROLL` is read once at construction using
`qEnvironmentVariableIsSet`; mount only on APPLE with the flag set. Flag off
creates no grid, receiver, feed or QML component and registers no Swift type.

The approved QtBridge change makes existing
`QmlInstantiable.registerQmlElement()` public (currently package at the pinned
revision); Task 1 owns that dependency patch. Task 4's
`swiftgrid/grid_host.h` exposes only:

```c
void sg_register_grid_types(void);
```

`SwiftGridHost.swift` exports this main-thread entry point, registers
`PianoGrid.registerQmlElement()` once, and never creates another application or
engine. `PianoGrid` conforms to `QmlInstantiableStatus` (which extends
`QmlInstantiable`). QtBridge's generated creation callback retains the Swift
model and its QObject destructor releases it. Use ordinary QML ownership:
no custom factory handles, manually retained grid, proxy extraction,
package/private access, or additional QtBridge patch.

`SwiftRollOverlay.qml` has `required property string documentToken` and
`required property int selectedTrack`; its `readonly property QtObject
gridModel` instantiates the registered nonvisual `PianoGrid`, setting
`readOnly: true`, `documentToken`, and `documentTrack`. This is NOT a
QQuickItem: existing visual QML canvas components consume its scene.
Registration uses Swift module name `SwiftGrid` in both lanes, so the QML
import is `SwiftGrid 1.0`. It never launches prototype `Main.qml`.

`PianoGrid.documentToken: String` carries a canonical decimal UInt64 string,
not a QObject address. This avoids narrowing through QtBridge's Qt `UInt`
variant conversion or QML numeric precision. `documentTrack: Int` is the
engine-track index. `componentComplete()` calls public scalar
`bindDocument(_ documentToken: String)`, which parses a nonzero token,
constructs/binds one receiver and calls `connect()`. The same binding method
supports a host-created grid; snapshot mapping itself remains Swift-internal.
A missing/invalid/unregistered token or duplicate recipient is a mount error,
not demo fallback. Token is immutable after binding. `documentTrack` changes
call `setDocumentTrack`.
Swift receives only these values and snapshot PODs, never window, engine,
document or host QObject. Prototype Swift construction does not invoke QML
component completion and keeps its explicit demo setup.

Mount order:
1. Construct feed, mint token and register its empty endpoint.
2. Call `sg_register_grid_types()` before loading the component. Through
   the existing `QQuickView::engine()` (not a nonexistent `quickEngine()`),
   call `QQmlComponent::createWithInitialProperties` with the decimal token
   and selected-track values. QML creates/owns model and visual renderer;
   component completion binds the receiver before creation returns.
3. Verify component success and a bound delivery slot; parent the visual item
   to the existing window's `contentItem`, bind position/size/visibility to
   canonical roll-band geometry, above C++ painting with opaque background.
   It never claims focus. Connect selected-track changes to the overlay value.
4. Explicitly call `feed.pushSnapshot()`; initial rendering must not wait for
   an edit or property-change signal.
5. On detach/destruction/failure, disconnect host track/document observers and
   unregister/destroy feed BEFORE deleting the overlay and its QML-owned
   model. Receiver deinit clears an already-absent token harmlessly. Cover
   externally destroyed transferred windows and partial creation failures;
   no queued delivery, dangling callback or retained closed-document state.

## §5 Acceptance surfaces

- `swiftdocfeed`: real fixture contents, document tick base/signatures, one
  delivery per mutation/undo/redo with advancing revision and stable token;
  explicit initial push after binding; no callback after clear/destruction.
  A check-only Swift entry point exercises the ACTUAL shared `DocumentFeed`:
  first revision zero, equal/lower drop, higher accept, unrelated-id drop,
  two receivers interleaved, fresh remount token and released receiver state.
  A C++ mirror of the guard is not evidence.
- Prototype smoke: editable rows unchanged; read-only draw/move/resize,
  menu/undo/controller paths inert; real pan/zoom/hover; filtered snapshot
  refresh; non-24 timebase and changing signatures render correctly.
- `swiftrollgated`: production fixture initially renders without an edit,
  track-follow, C++ edit/undo/redo refresh, two open tabs isolated under
  interleaved updates, close one and continue the other, remount fresh state,
  pointer editing blocked without focus change, viewing input live, flag-off
  absence and detach lifecycle safe.
- Existing production `selectionkey-core` and `rollcheck-static` unchanged.
