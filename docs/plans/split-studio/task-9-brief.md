# Task 9 — `KitStudioPresenter`: picker, zone views, conflict/retarget, validation adapter

## Context

Ninth task of the Split Studio plan; the bridged presenter that owns every
Split Studio surface state except the session wiring (task 10's
`KitStudioWorkflow` feeds it and consumes its callbacks, mirroring the
`SampleStudioPresenter`/`SampleStudioWorkflow` split). This is the
preserver/picker half of the former task 8 (R17 split); the source/slicing
state machine is task 8's. Producers consumed: task 1
(`SampleRatePolicy` behind task 8's session), task 5
(`SampleLibraryModel`, `PcmAuditionPlayer`), task 6
(`MarkerWaveformModel` — injected by task 10, which owns the
`GridPalette`), task 7 (`KitDraft`, `KitDraftCodec`, `KitAuditionTone`),
task 8 (`KitSourceSession`). Consumer: task 10 mounts the presenter in QML
and wires every closure; task 11 extends the workflow-side switch state.

## Exact write set

- Create `src/swift/kitstudio/KitStudioPresenter.swift`
- Create `src/swift/kitstudio/KitSlotPicker.swift` (slot rows + picker
  state; separate file — independent reason to change)
- Edit `src/checks/kitstudio/KitDraftChecks.swift` (append presenter rows
  to `runKitDraftSuite`)

Controller-owned: `PorydawQmlTypes` uncreatable-list rows for the new
bridged types, module source lines, `checks:bridge` baseline.

## Prerequisites

Tasks 1, 5, 6, 7, 8 (interfaces only).

## Interface contract

`spec.md → PorydawKitStudio (task 9)` names the shape. Exact surface:

```swift
@MainActor @QtBridgeable
public final class KitStudioPresenter: QmlUncreatable {
    // Published state — supported types carry NO @QtTracked (R22);
    // unsupported types do.
    public var titleText = ""            // spec §3 format incl. " •"
    public var dirty = false
    public var mode = 0                  // 0 drumkit, 1 keysplit
    public var conflictVisible = false
    public var conflictText = ""         // "Changed in the song"
    public var switchBarVisible = false
    public var statusText = ""           // transient messages
    public var usedByText = ""           // "" or "used by N"
    public var canSave = false
    public var canUndo = false
    public var canRedo = false
    public var zoneRows: QListModel<KitZoneRow>     // active mode view
    public var slotRows: QListModel<KitSlotRow>
    public var sourceRows: QListModel<KitSourceRow>
    @QtTracked public var waveform: Optional<MarkerWaveformModel>
    // Slot API (QML-callable)
    public func selectZone(row: Int)
    public func setMode(index: Int)                  // re-derives zoneRows; both views kept
    public func dropSample(name: String, onKey: Int) // spec §8 rules
    public func moveZone(row: Int, toKey: Int)
    public func resizeZone(row: Int, startKey: Int, endKey: Int)
    public func deleteZone(row: Int)
    public func mapAllSlices(fromKey: Int, whiteKeysOnly: Bool)
    public func setZoneRootKey(_ key: Int); public func setZonePitched(_ on: Bool)
    public func setZonePan(_ pan: Int); public func setZoneAdsr(a: Int, d: Int, s: Int, r: Int)
    public func selectSlot(row: Int)
    public func addMarkerAtCursor(); public func removeMarker(id: Int)
    public func sliceSelection(); public func toggleSnap()   // default ON, spec §15
    public func selectSource(row: Int); public func closeSource(row: Int)
    public func renameSlice(id: Int, name: String)
    public func setSourceRate(rate: Int)                 // Hz; options from SampleRatePolicy.rateOptions (F6)
    public func playSlice(id: Int); public func playKey(key: Int)
    public func undo(); public func redo()
    // Swift-only stored members (@QtIgnored, R22)
    @QtIgnored public var onSaveRequested: (() -> Void)?
    @QtIgnored public var onRetargetPrompt: ((_ answer: Int) -> Void)? // 0 save, 1 discard, 2 cancel
    @QtIgnored public var onConflictAnswer: ((_ keepMine: Bool) -> Void)?
    @QtIgnored public var onSwitchBack: (() -> Void)?
    /// The workflow's validation adapter (R20): existingSymbols =
    /// directSoundSymbols ∪ pending batch names ∪ current draft slice names.
    @QtIgnored public var validateName: ((String) -> String?)?
    @QtIgnored public var onLoadKit: ((_ slot: Int) -> KitLoadResult?)?
    @QtIgnored public var usageScan: ((_ subgroup: String, _ table: String?,
                                       _ excludingSection: String) -> [String])?
    @QtIgnored public var publishKitTone: ((KitAuditionTone, UInt8) -> Bool)?
    @QtIgnored public var playPcm: ((Int) -> Void)?   // slice id; workflow routes to PcmAuditionPlayer
}
```

`KitZoneRow` / `KitSlotRow` / `KitSourceRow` are `@QtBridgeable
QmlUncreatable` row types (Bool/Int/String fields only, unannotated).
`KitLoadResult` (Swift-only struct) carries the parsed parent voice,
sub-group children, table, usage sections, and slot kind. Pinned state
machines:
- **Id ownership (F5)**: the presenter owns the marker/slice id ↔
  (source, index/frame) mapping exposed to QML; `KitSourceSession` stays
  index-based and never sees QML ids.
- **Slot picker**: rows = kit/keysplit slots of the bound voicegroup plus
  one `New kit in empty slot N…` row per undefined slot. Selecting an
  existing kit when dirty raises the retarget prompt (spec §2); clean
  reloads silently (via `onLoadKit`). `New kit` creates an empty draft
  bound to that slot (file creation happens at save, task 10).
- **Zone views**: every mutation routes through `KitDraft`'s setters (the
  only mutation path, R10) — the presenter computes the next zone list
  (drop/move/resize/delete/map-all per spec §7–§11), calls the setter, and
  re-derives rows on rejection (status text explains the rejection).
  Row publication uses the incremental `syncModel` helper
  (`src/swift/app/presentation/QListModelSync.swift:6`) — no whole-model
  resets while dragging.
- **Conflict**: the workflow reports a song-side slot change; clean draft ⇒
  workflow reloads and the presenter re-derives; dirty ⇒
  `conflictVisible = true`, `conflictText = "Changed in the song"`;
  Reload reloads, Keep mine hides the bar and keeps the draft (spec §21).
- **Mode toggle**: `setMode` swaps the published view; both views' edits
  are kept (each view's zone list lives in the draft); unstoreable strip
  fields (pan in Keysplit) publish but flag disabled (spec §6).
- **playKey** builds the tone with `KitDraftCodec.auditionTone(draft:key:)`
  and publishes via `publishKitTone`; locked zones play their preserved
  voice. **playSlice** routes to `playPcm`.
- QML observation: revision counters (Int) owned by the presenter +
  `Connections` functions, matching the existing studio. Add a
  `@QtSignal` only for a prompt answer the QML must push back, and then it
  needs both a QML handler and an emission path.
- Strings in spec §3/§5/§21/§22/§24 are verbatim contract.

## Implementation steps

1. Write `KitSlotPicker` (rows + state machine) — no engine/session calls.
2. Write `KitStudioPresenter`: compose picker + task 8's session + task
   7's draft; publish rows/state; implement the slot API per the contract;
   wire undo/redo/canSave (`canSave` ⇔ a kit target is selected AND
   `dirty`).
3. Append presenter rows to `runKitDraftSuite` (labels
   `swiftcore/KitStudioPresenter::`, budgeted 0.05 s — the essentials):
   picker row derivation incl. empty slots; drop rules in both modes
   (occupied rejection, keysplit extension to next zone); move/resize
   maintaining disjointness via draft rejection; mode toggle keeps both
   views; conflict bar lifecycle; retarget prompt emission; rename
   validation through the injected adapter; canSave/dirty/title
   transitions. All via the closures with stub workflow answers.

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded):

- `uv run --no-sync dev checks --filter kitstudio-draft`
  — the lane's presenter rows cover the state machines above. Lane total
  stays within the budget (plan.md table).
- `uv run --no-sync dev checks:bridge`
  — every bridged member is legal: unannotated supported types,
  `@QtTracked` on the stored `Optional<MarkerWaveformModel>`, `@QtIgnored`
  on Swift-only members, `Optional<T>` slot returns.
- `uv run --no-sync dev checks --filter samplecheck-editor`
  — regression: `PorydawSampleUI` consumers (Sample Studio) untouched.

Runtime prerequisites: none; offscreen. No audio output is asserted (tone
building is value-level).

## Task-specific constraints

- The presenter performs NO session, file, engine or project calls: every
  external effect is an `@QtIgnored` closure; every external fact arrives
  as a value (`KitLoadResult`). Task 10 wires them.
- Do NOT edit `KitDraft.swift` (R10); the draft API is complete from
  task 7. Report a missing API instead of widening it here.
- Follow `rule://qtbridge-surface` exactly (R22): bridged members in the
  class body, public; no `@QtTracked` on supported Int/Bool/String
  members.
- No QML files in this task.

## Controller verification

1. Add the new sources to `src/swift/kitstudio/CMakeLists.txt` and the
   `PorydawQmlTypes.uncreatableTypes` rows (`KitStudioPresenter`,
   `KitZoneRow`, `KitSlotRow`, `KitSourceRow`) in alphabetical position.
2. `uv run --no-sync dev build:checks` then
   `uv run --no-sync dev checks --filter kitstudio-draft`
3. `uv run --no-sync dev checks:bridge` (baseline rewrite only for the
   intended new surface)
4. `uv run --no-sync dev checks --filter samplecheck-editor`
5. `uv run --no-sync dev format --check` on changed lines.
