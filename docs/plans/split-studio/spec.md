# Spec: Split Studio — drumkit and keysplit voice editing

Binding decisions: `local://split-studio-decisions.md` (user-confirmed
2026-10-12) plus the controller rulings `local://split-studio-plan-rulings.md`
(R1–R26, r1). This document is the single statement of agreed behavior,
vocabulary and interfaces; briefs link here and carry only deltas. Engine
facts were re-verified in the poryaaaa checkout shared by this worktree
(`external/poryaaaa` of the main checkout; `PORYAAAA_DIR` in
`build/debug/CMakeCache.txt`).

## Vocabulary

- **Source** — one imported audio file loaded into a Split Studio session
  (`ImportedSample`); identified by its sanitized base name. A session holds
  any number of sources; each owns its markers, slices, target rate and name
  prefix.
- **Marker** — a frame position on a source, shown as a draggable tab on the
  waveform. Markers delimit slices; they are free-placed (no beat grid).
- **Slice** — the region between two consecutive markers of one source,
  rendered to its own GBA-ready sample asset (`<source>_NN`). A slice is the
  drop unit for zones. Closing a source is offered only when none of its
  slices are in use.
- **Zone** — a contiguous MIDI key range 0…127 in the bottom editor mapped to
  one sample voice (sample, root key, Pitched flag, pan, ADSR). Zones never
  overlap: one voice per key. A **locked zone** carries a PSG/non-sample voice
  read from the project; it can be moved and deleted but not edited.
- **Draft** — the window-session-only state of one kit target: both mode
  views' edits, the zones, the in-memory slices, and the per-window undo
  stack. The draft dies with the window; nothing is written to the project
  before Save to Song.
- **Mode view** — one of the two bottom-editor representations kept alive in
  the draft simultaneously: **Drumkit** (`voice_keysplit_all`) and **Keysplit**
  (`voice_keysplit` + a 128-byte keysplit table). The toggle changes only the
  bottom editor; the view active at Save decides what is written.
- **Kit edit** — one Save-to-Song application: parent slot line + sub-voice
  group lines + (Keysplit mode) one keysplit table, applied as exactly one
  song undo step, plus the slice sample registrations written at that moment.

## Engine facts (verified; they shape the model)

- `m4a_track.c:61-95` `resolve_voice`: keysplit-all selects `subGroup[key]`;
  keysplit selects `subGroup[splitTable[key]]`.
- `m4a_track.c:413-422`: keysplit-all plays the child's fixed `voice->key`
  (`useKey = voice->key`) — every key sounds the sample at its root unless the
  child key rises. Rhythm pan exists only for keysplit-all, from the child
  `panSweep & 0x80` → `(panSweep - 0xC0) * 2`; applied to channel volumes at
  `:476-488`.
- Keysplit mode pitches from the incoming key (normal direct-sound behavior,
  `m4a_midi_key_to_freq` over the child wave).
- `voicegroup_types.h:28-60`: `WaveData` has no start offset — **each slice is
  its own sample asset**; slices cannot be window regions of one sample.
- `BankBuilder.swift:73-86`: a `.bin`-mapped symbol resolves the sibling
  `.wav` first — registering a `.wav` + `DirectSoundWaveData_` `.incbin` before
  the built `.bin` exists is safe; the bank plays immediately.
- Project layout: a kit parent slot is one line (`voice_keysplit_all <sym>` /
  `voice_keysplit <sym>, keysplit_<table>`) in the song voicegroup's `.inc`;
  the 128 (or starting-slot-offset) child voices are a `voice_group` section
  of their own (`sound/voicegroups/<sym>.inc`, label `<sym>::`) locatable via
  `VoicegroupLocator.locateSubgroup(symbol:)`; keysplit tables live in
  `sound/keysplit_tables.inc` (parse format in `KeysplitTables.swift:44-106`;
  table value = `KeysplitTable {name, startingNote, maxNote, table}`,
  `KeysplitTables.swift:9-14`).

## Behavior contract

### Window and entry

1. Entry is Tools → **Split Studio…** only (`tools.split_studio`; the menu is
   `ShellMenuBar.qml`'s `shellToolsMenu` driven by `toolsActionIds`). Enabled
   iff a project and a song are open.
2. One window app-wide, modeless (no `DialogWindow` modality; a native
   top-level window that does not block the shell). It is bound to one
   (song, voicegroup slot). Activating it while bound to another song
   retargets after Save/Discard/Cancel when the draft is dirty; a clean draft
   retargets silently.
3. Title: `Split Studio — <song> · voice <N>`, suffixed ` •` while the draft
   has unapplied changes. Window size and both splitter positions persist
   across sessions under the preference keys `splitStudioWindowSize` (string,
   `"WxH"`) and `splitStudioSplitters` (string list, left-pane and
   horizontal-split sizes in that order).
4. Layout: sample library pane left (the shared `SampleLibraryPane` /
   `SampleLibraryModel` surface); right side split horizontally —
   waveform/slicing view top, key-range zone editor bottom. Both splitters
   draggable.
5. In-window slot picker: the song voicegroup's drumkit/keysplit slots plus
   `New kit in empty slot N…` for each undefined slot. Converting an empty
   slot creates `sound/voicegroups/<voicegroup>_kit<N>.inc` (existing
   `VoicegroupSource.createVoicegroup` + `appendIncludeLine`) and — when the
   Keysplit view is the one saved — a new table `keysplit_<voicegroup>_kit<N>`
   written by the keysplit table writer; both creations happen in the save
   pipeline (task 10). Converting an existing non-kit voice is not offered
   here (stays in the voicegroup panel).

### Modes and zones

6. The Drumkit ⇄ Keysplit toggle re-renders only the bottom editor. Both
   views keep their edits while the window is open; ranges carry across.
   Values the other mode cannot store (rhythm pan in Keysplit; fixed
   per-key `key` in Keysplit) stay in the zone values but their strip
   editors are shown disabled in the mode that cannot store them.
7. Bottom editor: horizontal keyboard 0–127 with zoom and scroll; zone blocks
   above the keys. No overlaps — dropping onto an occupied range is rejected
   with a status message, never a silent merge.
8. Drop a slice (or a library sample) on a key: creates a one-key zone in
   Drumkit; in Keysplit the zone extends to the start of the next zone (or
   127). Drag a zone's edges to resize, its body to move.
9. **Map all slices from `<key>`** fills consecutive keys with the source's
   slices in order; the white-keys-only option (Slicex "Assign to all")
   skips black keys. Drumkit mode: one key per slice; Keysplit mode: one run
   per slice.
10. Selected-zone strip: sample name, root key, Pitched toggle, pan
    (Drumkit only), ADSR (a/d/s/r). Locked zones show their voice type and a
    Delete affordance instead of the strip editors.
11. Pitched toggle per zone in both modes. Drumkit default off: every key's
    child voice keeps `key` = the zone's root key. Pitched on: child keys rise
    by +1 semitone per key. Keysplit mode: the engine already pitches from
    the incoming key; Pitched only changes the child root key written.
12. Opening an existing kit builds zones by collapsing adjacent identical
    sub-slots (same sample symbol and params, with child key equal or rising
    by +1 per slot; rising ⇒ Pitched on). Slots whose voice is not a
    sample/direct-sound voice become locked zones. Keysplit view builds
    zones from runs of the table (equal consecutive table values), clamped to
    the sub-group's defined slots.

### Slicing

13. A source tab strip above the waveform lists the session's sources; each
    source keeps its own markers and slices. A source with no slice in use
    can be closed (prompt-free removal from the session only).
14. Markers: double-click or `M` adds one at the cursor (playhead/pointer);
    dragging a marker tab moves it; `Delete` or the tab's context menu removes
    it (removing a boundary merges its slice with the neighbor). Drag-select
    a region → **Slice selection** creates one slice bounded by the selection.
    Free placement; no beat grid, no transient detection in v1.
15. Zero-crossing snap toggle, default ON: marker add and drag snap to the
    nearest sign change between consecutive samples, searched outward and
    bounded to 3 ms of frames around the cursor.
16. Declick is baked into each rendered slice: fade-out on by default, at most
    4 ms and never more than half the slice; fade-in off by default (preserve
    attacks), same bound when enabled; per-slice overrides for both. Fades
    use the half-cosine shape identical to the `SampleRender` fade blocks
    (`SampleRender.swift:113-129`), applied tail-ward for fade-out and
    head-ward for fade-in.
17. Slice names are `<source>_NN` (two-digit, from the first free index),
    renamable, sanitized and validated with Sample Studio's rules
    (`SampleNames.sanitize` + the validation adapter of §Save). One
    target-rate control per source uses the shared rate policy in
    `PorydawSample` (`SampleRatePolicy`): the source rate when `gbaReady`,
    else `ImportedSample.gbaDefaultRate` (13379 Hz). Sample Studio and Split
    Studio both call it; local re-implementation is forbidden.

### Audition

18. Clicking a slice plays it (the rendered slice PCM through
    `PcmAuditionPlayer`). Clicking a key in the zone editor plays the
    unapplied draft through the m4a engine from memory — the draft is
    published as a real split `ToneData` (`AudioAudition.publishKitTone`:
    keysplit-all wrapper for Drumkit so rhythm pan and fixed-key semantics
    apply; keysplit wrapper + in-memory table for Keysplit), with the zone's
    pitch/pan/ADSR. No live MIDI input in v1.

### Undo, save, sync

19. The window owns its undo stack for in-window edits (zones, markers,
    names, mode-specific values). Shortcut routing uses an explicit gate,
    not an assumption: the shell window's `Shortcut` delegates
    (`ShellContent.qml`) are enabled only when the shell window itself is
    the active window AND has an active focus item
    (`content.root.active && content.root.activeFocusItem !== null`); Split
    Studio's own `StandardKey.Undo`/`Redo`/`Save`/`Close` `Shortcut`s are
    window-scoped. The stack dies with the window.
20. **Save to Song** (window `StandardKey.Save` shortcut while Split Studio
    has focus, and the window's Save button) is ONE song undo step: slice
    `.wav` + `DirectSoundWaveData_` registrations are written at that moment
    (batch), then the kit edit (parent slot + sub-group lines + table) is
    applied through the document session and recorded as a single history
    action. History replay is authoritative (last writer wins) — see
    Interfaces. **Files survive undo** (R4): song undo/redo replays only the
    kit edit; slice `.wav`s and registrations persist unreferenced and become
    orphan-eligible. The save pipeline never deletes registrations; a saved
    slice that is later renamed leaves the old name behind, also
    orphan-eligible. The song's own Cmd/Ctrl+S (song save to disk) is
    unchanged. Own-save notifications are suppressed (R5): the save
    continuation installs the (generation token, expected after-state) tag
    BEFORE calling `DocumentSession.applyKitEdit` (F4) — both inputs are known
    pre-call, so no synchronous notification can race the tag — clears the
    tag on throw, marks the draft clean on success, and the conflict
    observer drops any bank-change notification matching its own tag — no
    reload, no conflict bar.
21. A song-side change to the window's target kit (song undo/redo of any
    edit, voicegroup-panel edit of the slot): clean draft → silent reload;
    dirty draft → a bar `Changed in the song` with **Reload** / **Keep mine**.
    Shared-kit republish scope (R15): a kit edit republishes only the bound
    song's lease; other voicegroups referencing the same sub-group or table
    keep their previously published banks until their next load — this
    stale-lease window is accepted and recorded here.
22. Voicegroup switch: the voicegroup-selection code (the dropdown's
    `commitVoicegroupSelection` path) checks
    `ApplicationSession.hasUnsavedChanges(song:)` and prompts
    Save/Discard/Cancel BEFORE switching; the check stays at the dropdown, not
    inside Split Studio. After switching, the window follows the same slot
    number in the new voicegroup, reloads, and shows `Voicegroup changed to X`
    with **[Switch back to Y]**. Switch back calls
    `selectVoicegroup(previousArg)` directly — unguarded, because the draft
    has just reloaded from the new voicegroup (clean); if that switch fails
    asynchronously, the bar reverts and a status line reports the failure.
    A non-kit slot in the new voicegroup shows the picker's empty-slot state.
23. Closing with unapplied changes (window close button, Cmd/Ctrl+W, song tab
    close, project close, app quit) prompts Save to Song / Discard / Cancel;
    a clean draft closes silently. Answering **Save** suspends the close
    (tab/project/quit) until the save task settles; **Cancel** aborts the
    close; **Discard** proceeds. On quit the app waits for the save to
    settle; there is no abandon path. Project close and app quit close the
    window (after the same prompt). The Split Studio prompt runs before the
    song's own save prompt on tab/project close.
24. Shared kits/tables: when the opened kit's sub-group or table is
    referenced by other voicegroups, show `used by N`; the user chooses edit
    everywhere vs copy — copy is the default and snapshots the sub-group and
    table under fresh `<voicegroup>_kit<N>` names in the save pipeline,
    repointing the parent slot.
25. Orphan cleanup (Ableton-style): only files Split Studio created this app
    session AND that no voicegroup references at check time. The
    session-created registry is owned by `ApplicationSession` (app-session
    lifetime — closing the Split Studio window does not drop it). Offered on
    song tab close and project close/app quit as a checklist (all checked)
    with **Delete** / **Keep**; Delete removes the `.wav` and its
    `DirectSoundWaveData_` registration lines from `direct_sound_data.inc`.
    Window close never offers cleanup.

## Interfaces (exact; produced by the tasks)

### PorydawSample (task 1)

```swift
/// Bounded nearest-zero-crossing search (port of the deleted C++
/// nearestZeroCrossing, git show 5b8dcc9e^:src/audio/sampledsp.cpp:144-162,
/// bounded to `windowFrames`).
public enum SampleZeroCrossing {
    /// - Returns: The index of the sample closing the nearest sign change
    ///   within `windowFrames` of `index` (alternating outward search), or
    ///   `index` clamped to the buffer when none is found.
    public static func nearest(buffer: Span<Float>, index: Int, windowFrames: Int) -> Int
}

/// Renders one slice and bakes its declick fades.
public enum SampleSlice {
    /// Renders `params.cropStart..<params.cropEnd` of `source` through the
    /// existing `SampleRender.render` pipeline, then bakes half-cosine edge
    /// fades on the rendered output (§16). Loop metadata from the render is
    /// preserved; the function does not force `loopOn`.
    public static func render(
        source: ImportedSample, params: SampleEditParams,
        fadeIn: Bool = false, fadeOut: Bool = true
    ) -> ProcessedSample
}

/// The one GBA target-rate rule and option list, shared by both studios
/// (R16). The fixed table is the presenter's existing list
/// (SampleStudioPresenter.swift:10) moved down.
public enum SampleRatePolicy {
    /// The GBA PCM rate table, ascending.
    public static let rates = [5734, 7884, 10512, 13379, 15768, 18157,
                               21024, 26758, 31536, 36314, 40137, 42048]
    /// The source rate when the source is GBA-ready, else the GBA default.
    public static func targetRate(gbaReady: Bool, sourceRate: Double) -> Double
    /// Selectable options (Hz): the source rate first (when finite > 0),
    /// then `rates`.
    public static func rateOptions(sourceRate: Double) -> [Int]
}
```

### PorydawVoicegroup (task 2)

```swift
public struct KeysplitWriteError: Error, Equatable { public let message: String }

public enum KeysplitTableWriter {
    /// Replaces the definition named `table.name` in `path`
    /// (sound/keysplit_tables.inc), or appends a new definition block after
    /// the last one. Emits run-per-value `split <index>, <end>` lines. Uses
    /// the file's existing indent and EOL convention, detected with
    /// `ProjectFileStore.splitLines` (`crlf`, `endsWithNewline`), the same
    /// detection `SampleRegistrar.register` uses
    /// (SampleRegistrar.swift:109-110). A missing file is an error.
    /// Round-trips: `KeysplitTables.parse` of the result yields a table
    /// whose 128 bytes equal `table.table`.
    public static func replace(table: KeysplitTable, inFile path: String) throws(KeysplitWriteError)
}

/// The blank sub-voice line for unassigned drumkit keys — the same line
/// `createVoicegroup` writes for empty kits. Cross-module public (R3).
public let kitBlankChildLine = "\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 0"

/// One kit application at store level.
public struct KitEditInput: Sendable, Equatable {
    public var slot: Int              // parent slot in the loaded voicegroup
    public var parent: VgVoice        // keysplit-all or keysplit voice
    public var subgroupSymbol: String
    /// Full sub-group content by sub-slot index. nil writes
    /// `kitBlankChildLine` (drumkit indexing: sub-slot == MIDI key, count
    /// 128; keysplit indexing: sub-slot == zone ordinal — see KitDraftCodec).
    public var children: [VgVoice?]
    /// nil for Drumkit mode (no table written).
    public var table: KeysplitTable?
}

extension VoicegroupStore {
    /// Applies parent slot + sub-group lines + keysplit table, saves all
    /// three sources, and republishes ONLY the bound song's lease (R15);
    /// other referencing voicegroups refresh on their next load. Conflict
    /// semantics mirror applyVoicegroupEdit (stale expected state throws;
    /// nothing is written).
    public func applyKitEdit(input: KitEditInput, expectedParent: VgVoice?) throws -> VoicegroupEditResult
}
```

Sub-voicegroup line edits use only existing API: `VoicegroupLocator
.locateSubgroup(symbol:)`, `VoicegroupSource.open(location:error:)`,
`setVoice(slot:voice:)`, `save()`.

### PorydawProject (task 3)

```swift
extension ProjectStore {
    /// Store-level kit application (thin wrapper over VoicegroupStore
    /// .applyKitEdit) adopting the refreshed lease, mirroring
    /// applyVoicegroupEdit's outcome shape.
    public func applyKitEdit(lease: ProjectBankLease, input: KitEditInput,
                             expectedParent: VgVoice) async throws -> ProjectBankEditOutcome
}

/// Usage scan: which voicegroup sections reference a sub-group symbol and/or
/// keysplit table name. One signature everywhere (R13).
public enum KitUsageScanner {
    /// - Returns: Section labels (deduplicated, sorted) whose voice lines
    ///   reference `subgroupSymbol` (keysplit_all or keysplit) or `tableName`.
    ///   The caller passes the kit's own parent section in `excludingSection`
    ///   and the scanner filters it out.
    public static func usage(projectRoot: String, subgroupSymbol: String,
                             tableName: String?, excludingSection: String) -> [String]
}

extension SampleRegistrar {
    /// Validates every name (one refusal names every collision), writes all
    /// WAVs, then appends every registration block in one atomic
    /// `direct_sound_data.inc` write. Names registered earlier this call are
    /// visible to later validations.
    public static func registerBatch(projectRoot: String, samples: [(name: String, wav: Data)]) throws(SampleRegistrationError)

    /// Removes `sound/direct_sound_samples/<name>.wav` and the sample's
    /// registration block (`.align` + label + `.incbin`) from
    /// `direct_sound_data.inc` atomically. Unknown names are a no-op
    /// returning false.
    public static func deleteRegistration(projectRoot: String, name: String) throws(SampleRegistrationError) -> Bool
}
```

### PorydawDocument (task 4)

```swift
/// Document-value form of one kit edit (BankVoice mirrors the scalar path).
public struct KitEditValue: Equatable, Sendable {
    public var voicegroup: String          // the -G arg; rebase identity (R11)
    public var slot: Int
    public var parent: BankVoice
    public var subgroupSymbol: String
    public var children: [BankVoice?]
    public var tableName: String?          // nil in Drumkit mode
    public var table: [UInt8]?             // 128 bytes when tableName != nil
}

extension DocumentSession {
    /// Confirmed Save to Song: applies through the service and records ONE
    /// replayable ServiceKitEditAction. Same transition/in-flight guards and
    /// publish domains as applyBankEdit (DocumentSession.swift:376-415);
    /// conflicts throw and record nothing.
    @discardableResult
    public func applyKitEdit(_ edit: KitEditValue, expected: KitEditValue?) async throws -> AppliedBankEdit
}
```

`ServiceKitEditAction` (in `src/swift/document/ServiceBankHistory.swift`
beside `ServiceBankAction`) replays the **whole** kit edit (parent + children
+ table) in both directions through `ProjectService.applyKitEdit`. Replay is
authoritative (R12): replay passes `expected: nil` and last-writer-wins over
any song-side change; the window reconciles through the decided conflict
behavior (§21: clean → silent reload, dirty → bar) — undo can never be
blocked by a conflict, and a dirty window is never silently overwritten
without the bar. It shares the `BankResultInbox`, seals on `markSaved`,
never merges with scalar bank actions or other kit edits, and carries the
history label `Kit <subgroupSymbol>`. `rebaseCurrent(with:)` adopts the newer
`current` only when the newer action is a kit edit with the same
`voicegroup` and `slot`.

`ProjectService.applyKitEdit(lease:input:expected:)` converts `BankVoice`
rows to `VgVoice` with the existing scalar converter and routes to
`ProjectStore.applyKitEdit`.

### PorydawSampleUI (tasks 5–6; new module `src/swift/sampleui/`)

Module deps (R2), each with its symbol: `PorydawSample`
(`ProcessedSample`, `SamplePeakPyramid`), `PorydawAppAudio` (`AudioADSR`),
`PorydawAppPresentation` (`PreferencesStore` for `SampleLibraryModel`;
`GridPalette`/`DisplayListWriter` for the waveform), `QtBridge`, plus the
`NativeDisplayList` module-map include the scene needs (controller-wired).
No `PorydawDocument`, no `PorydawCore`. QML URI stays `PorydawApp`
(`QMetaObjectBuilder.qmlModuleAliases["PorydawSampleUI"] = "PorydawApp"`).

Task 5 moves verbatim (module change only, declarations unchanged):
`SampleLibraryModel` (with its row types) and `SampleAuditionArbiter`. The
`extension NativeAudio: SampleAuditionOutput` conformance stays in
`PorydawApp`. The presenter-free playback core extracted from
`SampleStudioAudition` (R9 — full surface):

```swift
@MainActor
public final class PcmAuditionPlayer {           // Swift-only, not bridged
    public init(lane: SampleAuditionArbiter?)
    /// Publishes one rendered sample; owner is the caller's identity token.
    public func play(owner: AnyObject, rendered: ProcessedSample,
                     looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8)
    /// Republishes the current sample (parameter-change observer path).
    public func restart(looped: Bool)
    public func stop(owner: AnyObject)
    public func close()
    public var playing: Bool
    /// Frame-tick playhead callback (source frames), nil at end.
    public var onPlayhead: ((Int?) -> Void)?
    /// Position advance driven by the holder's tick timer; the loop/gap
    /// arithmetic is the existing SampleStudioAudition.advance(bySeconds:)
    /// behavior moved (SampleStudioAudition.swift:101-125).
    public func advance(bySeconds dt: Double)
}
```

`SampleStudioAudition` (stays in `PorydawApp`) keeps its public surface and
delegates playback to the player; its checks keep passing unchanged.

Task 6 adds the generalized marker-list waveform (moved logic from
`SampleWaveformModel`/`SampleWaveformScene`, which are deleted from
`PorydawApp`):

```swift
@MainActor @QtBridgeable public final class WaveformMarkerRow: QmlUncreatable {
    public let id: Int            // stable within a source revision
    public let frame: Int
    public let kind: String       // "crop" | "loop" | "slice"
    public let label: String
    public var selected: Bool
}

@MainActor @QtBridgeable public final class MarkerWaveformModel: QmlUncreatable {
    public var markers: QListModel<WaveformMarkerRow>
    public var displayRevision = 0             // Int: supported, unannotated
    public var zoomLabel = ""                  // human zoom readout
    public func displayList(list: Int) -> Data    // 0 wave+markers, 1 seam
    public func setViewport(width: Double, height: Double)
    public func setSeamViewport(width: Double, height: Double)
    public func setBaseFontPx(value: Double)
    public func setSamples(_ samples: [Float], sampleRate: Double, gain: Double)
    /// Installs the full marker set (replaces), preserving grab identity.
    public func setMarkers(_ markers: [(id: Int, frame: Int, kind: String, label: String)])
    @QtIgnored public func frameAt(_ x: Double) -> Int
    public func handleAt(x: Double, y: Double) -> Int     // marker id or 0
    public func press(x: Double, y: Double) -> Bool       // grab nearest marker
    public func drag(x: Double)
    public func release()
    public func zoom(atX x: Double, steps: Double)
    public func pan(byPixels pixels: Double)
    public func fit()
    @QtIgnored public func setPlayhead(frame: Int?)
}
```

Sample Studio migrates onto it: its crop/loop handles become `kind: "crop"` /
`"loop"` markers; the scene's drawing logic moves into the module's scene
type; the existing `SampleWaveform.qml` objectNames
(`sampleWaveformDisplay`, `sampleSeamDisplay`) and interaction semantics
(drag/zoom/scroll/splitter/Space lane) are preserved. The three QML files
that name `SampleWaveformModel` today (`SampleWaveform.qml:9`,
`SampleStudioDialog.qml:18`, `SampleStudioHost.qml:32` — verified) rename the
type to `MarkerWaveformModel`; no check QML names it (verified). Split
Studio's slicing view drives the same model with `kind: "slice"` markers.

### PorydawAppAudio (task 7's audio addition)

```swift
/// Value description of an in-memory split voice for engine-true audition.
/// Lives here (R1): PorydawAppAudio owns the slot storage and retirement
/// protocol; PorydawKitStudio imports this module (downward edge). AppAudio
/// imports no voicegroup types (F3): the locked-voice payload is the
/// AppAudio-owned descriptor below.
public struct KitAuditionPsg: Sendable, Equatable {
    public var kind: Int         // raw macro ordinal of the PSG voice
    public var key: Int
    public var pan: Int
    public var sweep: Int        // square-1 only; 0 otherwise
    public var duty: Int         // square-1/2
    public var period: Int       // noise/programmable
    public var attack: Int; public var decay: Int
    public var sustain: Int; public var release: Int
}

public struct KitAuditionTone: Sendable {
    public enum Child: Sendable {
        case sample(pcm: [Int8], frequency: UInt32, key: UInt8,
                    panSweep: UInt8, adsr: AudioADSR)
        case psg(KitAuditionPsg) // preserved locked-zone voice
    }
    public var mode: KitAuditionMode  // nested drumkit/keysplit enum, AppAudio-owned
    public var children: [Child]      // by sub-slot ordinal
    public var splitTable: [UInt8]?   // 128 bytes in keysplit mode
}

extension AudioAudition {
    /// Publishes a split wrapper ToneData (keysplit-all or keysplit) whose
    /// sub-group, child waves and table live in AudioSampleAudition-owned
    /// storage, retired under the existing generation/acknowledgement
    /// protocol. SampleAuditionOutput and NativeAudio are unchanged.
    public func publishKitTone(_ tone: KitAuditionTone, key: UInt8) -> Bool
}
```

`KitMode` stays in `PorydawKitStudio`; `KitAuditionTone.mode` is the
nested `KitAuditionMode` so AppAudio imports neither the higher module nor
`PorydawVoicegroup`. `PorydawKitStudio` maps a locked zone's `VgVoice` to
`KitAuditionPsg` (field copy; the macro's raw ordinal into `kind`).

### PorydawKitStudio (tasks 7–9; new module `src/swift/kitstudio/`)

Module deps (R2), each with its symbol: `PorydawSample` (`SampleSlice`,
`SampleRatePolicy`, `ProcessedSample`), `PorydawSampleUI`
(`MarkerWaveformModel`, `PcmAuditionPlayer`), `PorydawVoicegroup`
(`VgVoice`, `KeysplitTable`, `kitBlankChildLine`), `PorydawAppAudio`
(`KitAuditionTone`), `QtBridge`. No `PorydawDocument`, no
`PorydawAppPresentation`, no `PorydawCore`: the workflow (task 10, App)
constructs the `MarkerWaveformModel` (it owns the `GridPalette`) and injects
it. QML URI aliased to `PorydawApp`.

Task 7 — draft domain (pure Swift, no bridged members; R10):

```swift
public struct KitZone: Equatable, Sendable {
    public var startKey: Int              // 0...127, inclusive range start
    public var endKey: Int                // inclusive; endKey >= startKey
    public var sampleName: String         // slice or library sample name
    public var rootKey: Int
    public var pitched: Bool
    public var pan: Int                   // -64...63; written only in drumkit
    public var adsr: (attack: Int, decay: Int, sustain: Int, release: Int)
    public var locked: Bool               // PSG/non-sample voice, preserved
    public var lockedVoice: VgVoice?      // the preserved voice when locked
}

public enum KitMode: String, Sendable { case drumkit, keysplit }

@MainActor
public final class KitDraft {
    public struct Snapshot: Equatable, Sendable {
        public var drumkitZones: [KitZone]
        public var keysplitZones: [KitZone]
    }
    /// Replaces the whole draft state; clears undo; dirty = false.
    public func load(_ snapshot: Snapshot)
    /// Marks the current state clean (keeps undo entries).
    public func markClean()
    public func snapshot() -> Snapshot
    /// The ONLY mutation paths (each pushes one undo entry over both views).
    /// Zones arriving unsorted, overlapping, or out of 0...127 are rejected
    /// (returns false, state unchanged) — clamping is the callers' visible
    /// behavior, never silent here.
    @discardableResult
    public func setDrumkitZones(_ zones: [KitZone]) -> Bool
    @discardableResult
    public func setKeysplitZones(_ zones: [KitZone]) -> Bool
    public func undo(); public func redo()
    public var canUndo: Bool; public var canRedo: Bool
    public var dirty: Bool                // any unapplied change since load/markClean
    public private(set) var drumkitZones: [KitZone]
    public private(set) var keysplitZones: [KitZone]
}

public enum KitDraftCodec {
    /// Zones for one mode view from parsed sub-group children (+ table).
    public static func drumkitZones(children: [VgVoice?]) -> [KitZone]
    public static func keysplitZones(children: [VgVoice?], table: KeysplitTable) -> [KitZone]
    /// One mode view's zones back to store inputs. Drumkit: exactly 128
    /// children, sub-slot == MIDI key; Pitched off ⇒ child key = zone root
    /// for every key in range, Pitched on ⇒ root + offset; pan written only
    /// in drumkit; unassigned keys ⇒ nil; locked zones emit their preserved
    /// `lockedVoice`. Keysplit: children indexed by zone ordinal (sorted by
    /// startKey; locked zones occupy their own ordinal with their preserved
    /// voice).
    public static func children(from zones: [KitZone], mode: KitMode) -> [VgVoice?]
    /// Full-range table: startingNote 0, maxNote 128, every key 0...127
    /// mapped to its zone's ordinal; a key inside no zone maps to the
    /// ordinal of the last zone starting before it (0 when none). The
    /// writer's truncation rule is therefore "never": Split Studio tables
    /// always cover 0...127, so gaps above the last zone survive the
    /// round-trip (R14).
    public static func table(from zones: [KitZone], name: String) -> KeysplitTable
    /// Builds the engine-true audition description for one key.
    public static func auditionTone(draft: KitDraft.Snapshot, key: Int) -> KitAuditionTone
}
```

Load-time zone building (§12) and the gap rule above agree: on load, a
table run whose ordinal has no defined child slot renders as unassigned
keys (no zone).

Task 8 — source session (Swift; slices, markers, minting):

```swift
@MainActor
public final class KitSourceSession {
    public struct Slice: Equatable, Sendable {
        public var id: Int; public var name: String
        public var startFrame: Int; public var endFrame: Int
        public var fadeIn: Bool; public var fadeOut: Bool   // §16 defaults
    }
    /// Adds a source (decoded ImportedSample); markers/slices start empty.
    public func addSource(_ sample: ImportedSample)
    /// Markers by source id; setMarker/removeMarker snap via
    /// SampleZeroCrossing when `snap` (windowFrames = 3 ms at source rate).
    public func setMarker(source: Int, frame: Int, snap: Bool)
    public func removeMarker(source: Int, frame: Int)
    /// Slice selection / map-all use the presenter's zone-free forms here;
    /// rendering uses SampleSlice.render with SampleRatePolicy.targetRate.
    public func renderSlice(source: Int, slice: Int) -> ProcessedSample
    /// Minting: first free `<source>_NN`; rename validates through the
    /// injected adapter (R20).
    public var validateName: ((String) -> String?)?
    public func mintSliceName(source: Int) -> String
    public func renameSlice(source: Int, slice: Int, to: String) -> Bool
    /// A source is closable iff no slice of it is named by any zone.
    public func canClose(source: Int, usedNames: Set<String>) -> Bool
}
```

The session is index-based; the **presenter (task 9) owns the marker/slice
id ↔ (source, index/frame) mapping** exposed to QML (F5).

Task 9 — presenter (`KitStudioPresenter`, `@QtBridgeable`,
`QmlUncreatable`), fed by the App-side `KitStudioWorkflow` (task 10):
publishes slot-picker rows (`KitSlotRow`: slot, kind, title, isNew), mode
toggle + the active view's zone rows (`KitZoneRow`: start/end key, sample
name, root, pitched, pan, ADSR, locked, selected), source-tab rows
(`KitSourceRow`: name, slice count, active, closable), the injected
`MarkerWaveformModel` (stored `@QtTracked public var waveform:
Optional<MarkerWaveformModel>` — non-supported type, R22), strip state, the
conflict bar (`conflictText` = `Changed in the song`, `Reload`/`Keep mine`),
retarget prompt state, `usedByText`, title text, and status text. Revision
counters for QML observation live on the presenter (R10), never on
`KitDraft`. The presenter performs no session, file, engine or project
calls: every external effect is an `@QtIgnored` closure — `onSaveRequested`,
`onRetargetPrompt(answer: Int)` (0 save, 1 discard, 2 cancel),
`onConflictAnswer(keepMine: Bool)`, `onSwitchBack`,
`validateName: ((String) -> String?)` (the workflow's adapter, R20:
`existingSymbols = VoicegroupSource.directSoundSymbols(projectRoot)` ∪
pending batch names ∪ current draft slice names — rename validation sees
batch-local names), `loadKit(slot: Int) -> KitLoadResult?`,
`usageScan(subgroup: String, table: String?, excludingSection: String) ->
[String]` (R13 signature), `publishKitTone(KitAuditionTone, key: UInt8) ->
Bool`. `KitLoadResult` (Swift-only struct) carries the parsed parent voice,
sub-group children, table, usage sections, and slot kind.
Per-source rate selection is value-based: `setSourceRate(rate: Int)` (Hz)
picks from the option list `SampleRatePolicy.rateOptions(sourceRate:)`
(task 1, F6); no index-based rate API exists.

### PorydawApp (tasks 10–12)

`KitStudioWorkflow` (`src/swift/app/kitstudio/`, `@QtBridgeable`): holds the
window lifecycle (`windowOpen`, one instance app-wide in `ApplicationSession`
as `kitStudio()` beside `sampleStudio()`), the current target
(song label + voicegroup slot), the save orchestration, the conflict
observer with the R5 suppression tag, and the close/retarget guard
(`KitStudioCloseGuard`). The **session-created sample registry** lives on
`ApplicationSession` (R6): `recordCreatedSample(name:)` /
`orphanSplitStudioSamples() -> [String]` / `deleteOrphanSamples(_:)`, so
closing the window never drops it. Save pipeline (single async task,
generation-guarded like `SampleStudioWorkflow.accept`
(`SampleStudioWorkflow.swift:278-346`)): render pending slices →
`SampleRegistrar.registerBatch` (names validated through the R20 adapter) →
[new kit only: `createVoicegroup` + `appendIncludeLine` + (Keysplit view)
`KeysplitTableWriter` for `keysplit_<vg>_kit<N>`; copy default for shared
kits snapshots sub-group + table under fresh names] →
`DocumentSession.applyKitEdit(KitEditValue, expected:)` →
`session.recordCreatedSample` for each written slice →
`session.refreshVoicegroupCatalog()` (`ApplicationSession+Catalog.swift:9`)
→ presenter `markClean` path with the R5 tag installed synchronously before
the continuation yields. The pipeline never deletes registrations (§20).

Action registration: `tools.split_studio` (`.window` scope, no default key)
in `KeybindingRegistry.definitions` (label `Split Studio`), `ShellActionCatalog
.actions` + `toolsIds` + `menuLabels` (`"tools.split_studio": "Split
Studio..."`), `ShellPresenter+ActionPolicy` (`session.projectOpen &&
session.songOpen`), `ShellPresenter` activate →
`session.kitStudio().requestOpen()`.

QML (task 10): `src/ui/shell/kitstudio/SplitStudioWindow.qml` (modeless
top-level `ThemedWindow`, `flags: Qt.Window`, no modality),
`KitStudioHost.qml` (Loader in `ShellContent.qml` beside
`SampleStudioHost`), `SliceEditorView.qml`, `ZoneEditorView.qml`,
`KitSlotPicker.qml`. Window-local `Shortcut`s: `StandardKey.Save` →
Save to Song, `StandardKey.Undo`/`Redo` → draft stack, `StandardKey.Close` →
close-with-prompt. Shell routing gate (§19) is an explicit
`ShellContent.qml` edit: the shortcut delegate's `enabled` becomes
`actionState.enabled && content.root.active &&
content.root.activeFocusItem !== null`.

Task 11 (switch sync): the dropdown path (`VoiceListController
.commitVoicegroupSelection`, `VoiceListController.swift:270-278` →
`onVoicegroupChangeRequested` in `ApplicationSession+Audio.swift:95-103`)
consults `ApplicationSession.hasUnsavedChanges(song: SongTabSession) -> Bool`
and prompts (shell-owned `SongConfirmDialog`-style prompt,
`src/ui/songview/quick/docks/SongConfirmDialog.qml`) before
`selectVoicegroup`; Cancel restores the pre-edit arg via
`VoiceListController.setCurrentVoicegroupArg(_:)`
(`VoiceListController+Bank.swift:133`). Post-switch follow + unguarded
switch-back per §22.

Task 12 (close + orphan): `KitStudioCloseGuard` integrates with
`saveTabBeforeClose` / `closeAllResolved` / `hostClosingImpl`
(`ApplicationSession+Close.swift:44,118,151`) and
`SongTabsController+Close` with the §23 sequencing;
`OrphanCleanupDialog.qml` per §25.

Text contrast (R19): the new window and the orphan dialog register in the
existing audit's reachable entries — `textContrastEntries` in
`src/checks/editorqml/ShellQmlEntries.swift:16-29` gains a `split-studio`
state crossed with the two modes that differ most in contrast (`vanilla`,
`dark-neutral-high`; the `immaterial` entry is cut for the ≤ 3 s budget
(F1) — plan.md names the gap), and `tst_TextContrast.qml` gains the state
that opens the window. The `shell-split-studio` lane keeps no inline
rows.

## Non-goals (do not add)

- Transient/beat-grid slice detection; live MIDI input; audio recording.
- Converting an existing non-kit voice into a kit from Split Studio.
- Editing locked (PSG/non-sample) zone contents (move/delete only).
- A second window, a second Sample Studio, or multi-window Split Studio.
- New audio engine lanes beyond the `publishKitTone` publication shape; no
  changes to the audio callback structure or the retirement protocol.
- Changing the voicegroup panel's own kit-creation flow beyond the shared
  writer/store APIs; no changes to scalar voice editing or its merge policy.
- Local re-implementation of the rate policy (§17) — both studios call
  `SampleRatePolicy`.
- Proof-ledger work: no `src/checks/**/proof.*.txt` is touched by this plan
  (none exists; verified).
