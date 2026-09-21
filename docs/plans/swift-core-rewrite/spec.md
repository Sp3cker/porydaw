# Core and first-consumer contract

## Scope inventory

Paths in the first column are relative to `src/core/`. Every existing file is
accounted for. Successors are cohesive Swift files, not one file per C++ type.
The C++ implementations are reference code during parity, then removed in task 7.

| Existing files | Swift responsibility / destination | Task |
| --- | --- | --- |
| `smf.h`, `smf.cpp` | `core/MidiFile.swift`: lossless event/chunk representation, codec, format-0 conversion, engine-track mapping | 1 |
| `noteid.h`, `timedefaults.h`, `tempo.h`, `tracklimits.h` | `core/MusicTypes.swift`: musical identities, tick/tempo/default/track vocabulary | 1 |
| `m4asemantics.h`, `m4asemantics.cpp`, `mid2agbtables.h`, `mid2agbtables.cpp`, `velocitymodel.h`, `velocitymodel.cpp` | `core/MidiSemantics.swift`: classifications, display values, duration/velocity laws | 1 |
| `midiimport.h`, `midiimport.cpp` | `core/MidiImport.swift`: import analysis, setter reduction, division rescaling | 3 |
| `songhistory.h`, `songhistory.cpp` | `core/SongHistory.swift`: document and confirmed bank history, save identity | 2 |
| `songdocument.h`, `songdocument.cpp` | `core/SongDocument.swift`, `core/NoteEditing.swift`, `core/EventEditing.swift`: state/lifecycle/queries and semantic mutations | 2–3 |
| `songdocument_tempo.cpp` | `core/EventEditing.swift`: normalized tempo and atomic raw/tempo edits | 3 |
| `songdocument_xcmd.cpp`, `xcmd.h`, `xcmd.cpp` | `core/Xcmd.swift`, `core/EventEditing.swift`: known echo epochs, opaque traffic, lane rewrite/export | 3 |
| `lanemoveplan.h`, `lanemoveplan.cpp` | Internal lane-move planner in `core/EventEditing.swift` | 3 |
| `songdocument_range.cpp`, `songdocument_timeeditor.hpp`, `songdocument_timeeditor.cpp`, `songdocument_timeeditor_insert.cpp`, `songdocument_timeeditor_xcmd.cpp` | `core/TimeEditing.swift`: one cross-stream range/time transform implementation | 4 |
| `miditimeline.h`, `miditimeline.cpp` | `core/PlaybackTimeline.swift`: immutable sample-positioned projection | 5 |
| `timelineplayer.h`, `timelineplayer.cpp` | `playback/Sequencer.swift`: Swift realtime scheduler using native engine calls | 5 |

Destinations above are under `src/swift/`. `PorydawCore` imports Foundation,
not Qt or a C feed. `PorydawPlayback` imports the core and the existing poryaaaa
C engine through one native module map. `src/swift/app/DocumentSession.swift`
owns per-open-song state; `ApplicationSession.swift` is the QML-facing composition
owner. Existing grid math/scene/palette stay in `swiftroll/`; no broad rehome.

Core has no C++-testability contract. Its Swift APIs and representation are
chosen for domain correctness, ownership and production use, not what the C++
importer or a QTest driver can express. Generics, associated-value enums,
noncopyable/borrowed values, isolation and Swift error models remain available
when appropriate and supported by the qualified toolchain/deployment.
Core imports no check/oracle module and needs no test ABI, generated C++ header
or C++ interoperability setting solely for verification. Native service
adaptation remains outside it.

## Canonical state and storage

`MidiFile` stores `division`, ordered `[MidiChunk]`, and `wasFormat0`.
`MidiChunk` stores ordered `[MidiEvent]` and `endTick`. `MidiEvent` stores a
`Tick`, typed channel/meta/SysEx payload, and optional transient `NoteID` on a
note-on. Preserve the original status byte, including velocity-zero note-ons,
payload bytes, same-tick order, unknown meta/SysEx, and metadata-only chunks.
`NoteID` is document-scoped UInt64; it is not serialized. `Tick` is UInt32;
use the existing maximum/reserved value at file/arithmetic boundaries.

Produced entry points: `MidiFile.decode(_ bytes: [UInt8]) throws -> MidiFile`,
`encoded() throws -> [UInt8]`, `engineTracks() -> EngineTrackMap`, and
`blankSong() -> MidiFile`. The blank-song factory moves from
`SongRegistry::blankSong`, rather than retaining a native MIDI constructor.
Malformed/truncated files fail as files; no partial successful import.
Format-0 coercion, channel-prefix routing, marker rules, EOT canonicalization,
and running-status reset follow `smfcheck` and the current codec.

`SongState` contains the MIDI store, normalized `[TempoPoint]`, and `SongConfig`.
Match existing document adoption: valid conductor tempos become the typed tempo
stream and are materialized into a detached export copy. Do not keep a second
writable raw-tempo mirror. Preserve the existing handling of malformed or
non-conductor tempo traffic, as established by document/SMF checks.
`SongConfig` retains raw flags and all existing decoded values; no defaults are
silently rewritten on a note-only save. Notes, lane points, signatures and track
names are read projections, not editable copies of a second song model.
`SongSource` holds the loaded song label and MIDI path. It is document source
metadata, not undoable musical state; save snapshots capture that destination.

`MidiImport.analyze(_:trackBudget:playerName:) -> ImportAnalysis` is read-only.
`rescaleDivision(_:to:) throws` uses existing floor arithmetic;
`removeRedundantSetters(_:) -> Int` removes only existing eligible setters.
Task 3 implements the complete importer alongside its XCMD dependency. Do not
publish a provisional ordinary-MIDI-only import report or add an importer UI.

## Document and history

`@MainActor final class SongDocument` owns `SongState`, `SongHistory`, identity
allocation and a single `onChange: ((DocumentChange) -> Void)?` callback.
`DocumentChange` carries the revision and optional `TrackRemap`; the session
reconciles selection before notifying its presenter or publishing playback.
One mutation publishes once. No-op operations do not create history entries.

Public API families (native Swift values, not C envelopes):

- `init(file: MidiFile, config: SongConfig, source: SongSource, trackBudget: Int)`;
  `notes(in: Int) -> [Note]`, `note(_ id: NoteID) -> Note?`,
  `lanePoints(track: Int, lane: Lane) -> [LanePoint]`, `timeSignatures`,
  `trackName(_:)`, `engineTracks`, `ticksPerBeat: Int` from the canonical file
  timing header, and read-only raw chunk/event access. Grid and clipboard consume
  this query; division/clock policy stays in core.
- `addNotes(_ notes: [NewNote]) throws -> [NoteID]`, `deleteNotes(_:)`,
  `moveNotes(_:byTicks:byKeys:group:)`, `moveNotes(_:toPitches:group:)`,
  `resizeNotes(_:edge:byTicks:group:)`,
  `setVelocities(_:expectedRevision:) -> UInt64?` (nil on stale revision),
  and `nudgeVelocities(_:by:)`. One-note operations use a one-element batch;
  do not add duplicate public implementations.
- `addTrack(voice:) -> Int?`, `duplicateTrack(_:) -> Int?`, `deleteTrack(_:)`,
  `moveTrack(_:to:)`, `renameTrack(_:to:)`, `setTrackEnd(_:tick:)`, `setConfig(_:)`.
- `insertRawEvent(_:in:)`, `modifyRawEvent(_:at:)`, `deleteRawEvents(_:)`,
  `moveRawEvent(_:to:)`, `rawMoveBounds(_:)`;
  `editTempo(_ edit: TempoEdit)`, `editRawAndTempo(_ edit: RawTempoEdit)`;
  `setLoop(_:tick: Tick?)`, `setTimeSignature(_:at:)`,
  `moveTimeSignature(from:to:)`, `deleteTimeSignature(at:)`.
- `writeLane(_:track:points:span:)`, `moveLanePoints(_:)`, `deleteLanePoints(_:)`;
  `applyRangeEdit(_:)`, `moveRange(_:by:)`,
  `removeTime(_:scope:)`, `insertBlankTime(_:scope:)`, `duplicateTime(_:scope:)`.
- `captureSave() throws -> SaveSnapshot`, `didSave(_:)`, `isDirty`, `revision`.
  `SaveSnapshot` owns canonical bytes, config/flags-needed, destination and
  captured state identity. A successful old save cannot mark newer edits clean.

Payloads carry the same musical facts as their current C++ counterparts, not
an isomorphic list of compatibility overloads. Positions into raw event vectors
are short-lived references for one edit; note selections use `NoteID`.

**History decision (superseded by the typed change-set amendment,
2026-09-19):** document undo/redo uses typed, reversible change sets — not
retained whole-song before/after snapshots. One linear history serves
document changes and confirmed bank edits. Records are a small set of Swift
value types, not a class per command or a general command framework.
Transactions capture the actual changes made — exact event
insertions/removals/replacements preserving MIDI payloads, ordering, and
note identities; chunk insertion/deletion/reordering; tempo and
configuration changes; and every affected collision victim, not only the
selected notes. Capture happens during mutation, never by diffing the
entire song afterward. Undo applies recorded changes backward; redo applies
them forward; neither reruns the semantic edit algorithm, and inverse
intentions are insufficient. Naturally coarse records are correct where the
operation warrants them (a deleted track retains its chunk); unrelated song
state and arbitrary snapshot fallbacks are not retained. Short-lived
candidate state for atomic validation is acceptable; whole-song snapshots
retained in history are not. A `HistoryGroup` is an opaque caller-minted
token per gesture run; gesture merging preserves the earliest original and
the latest result of all affected data, including trimmed or deleted
neighbors. Repeated keyboard edits rebuild from the group origin so
crossing a neighbor then moving back restores it; an edit returning to its
origin removes the redundant entry while still publishing. Rejected and
no-op edits preserve any existing redo branch. Groups never merge across
save, a different command/selection, or key release. Undo/redo restore
note identities; the allocator never rewinds. Compatibility findings and
acceptance gates: [undo-redo-compatibility-report.md](undo-redo-compatibility-report.md).

`SongHistory` supplies `undo()`, `redo()`, `canUndo`, `canRedo`, `currentIdentity`,
`markSaved(_:)`, and `recordConfirmedBank(_:)`. It has one entry sequence, not a
second voice-bank stack. Bank entries do not change document identity. A narrow
`BankHistoryAction` service contract supplies `apply(direction:) async throws`
and `merged(with:) -> BankHistoryAction?`: actual native bank edits/reverts and
materialization receipts stay with the project service. Record/cross an entry
only after confirmation; conflicts leave the document unchanged and follow the
existing bank conflict policy. Preserve scalar merge boundaries and save sealing.
The bank editor is absent, but **this existing core behavior is still ported and
checked through its service**, not deferred or filled with dummy entries.

### Editing behavior

- Pair notes with the first following same-channel/key end, preserving exact
  duplicate identities and unterminated notes. Edited notes win collisions
  with stationary notes: trim head/tail or remove, never split a stationary
  note. Conflicting edited participants reject the whole operation; identical
  inserted copies remain permitted as in the existing insertion path.
- Resize either edge as one edit, minimum one tick; leading resize preserves
  the end and identity. Batched velocity edits are all-or-nothing.
- Engine-track order remains channel-bearing chunk order with the existing
  16-track ceiling and project budget. Track deletion/reorder preserves conductor
  globals and winning loop markers; rename respects channel-prefix/marker rules.
  Document name queries, rename classification and import share the same
  channel-prefix-aware track-name role rule specified in task 3. Prefixed names
  remain opaque channel metadata, not rename targets or global track labels.
  Existing display/import formatting differences remain intentional.
- Canonical inserted-event order and raw same-tick reorder bounds stay intact.
  Raw editing retains its existing ability to store non-musical/opaque events.
- XCMD recognizes selector/payload epochs, not isolated CC bytes. Known echo
  lanes rewrite canonically; unknown traffic is preserved. Export normalization
  affects a detached copy, not the live undo state.
- Time transforms preserve effective values at seams, scoped versus whole-song
  behavior, EOT changes, and raw/opaque traffic. Blank insertion splits crossing
  notes, assigning the new half a new identity. Range insertion may expand
  tracks under the existing budget. One operation is one undo entry.

## Playback and native services

`PlaybackTimeline.build(file:tempo:sampleRate:settings:)` is pure Swift and
returns immutable contiguous playback data plus tick/sample conversion data.
Accumulate unrounded tempo-map origins and round final sample positions once.
Project document and playback tracks with the same map; keep loop marker,
exact-gate, extended-clock, and mid2agb duration/velocity behavior.
Task 6 adds `PlaybackTimeline.build(state: borrowing SongState, sampleRate: Double)`
for document consumers. This is the only mapping from canonical `SongState`
tempo/config to playback inputs; sessions and presenters do not reconstruct it.
The file-based builder remains for standalone MIDI callers. See task 6 for
the authoritative-tempo and gate/clock acceptance scenarios.

`Sequencer` owns preallocated fixed-capacity key/gate/pending-release state.
Its methods are `reset`, `seek`, `replaceTimeline`, `chase`, `primeVoices`,
and `render(engine:timeline:left:right:looping:muteMask:)`. It calls the existing
poryaaaa engine, not a new synth. Port loop-end ordering, gate carry and long
TIE behavior exactly. The native callback gets an opaque sequencer pointer
allocated before device start; it borrows storage without Swift ARC, allocation,
locks, actor hops or collection growth in render. Destroy after callback quiescence.

One internal `src/audio/swift_playback.h` defines the required C boundary:
create/destroy sequencer on the control thread; reset/seek/replace/chase/prime/
render and position access on the existing caller threads; an immutable
`PlaybackData` view containing event pointer/count, timing/loop/track metadata
and its owned lifetime. Note identifiers remain 64-bit. No packed structs,
per-field getter ABI, C++ MIDI parser, or duplicate duration table. Swift-to-Swift
callers use native types. The audio service and render CLI use task 5's explicit
publication retain/release/file-load contract; callback consumers only borrow.
`TimelineHandoff` keeps its current current/retired-owner and raw-pointer exchange
algorithm. Native owners release Swift-backed snapshots on the control thread;
the callback never retains/releases them. No new reclamation protocol.

Retain `AudioEngine`, `wavexport`, poryaaaa/miniaudio/DSP and instrument leases.
Repoint `porydaw_render_cli` to the same Swift timeline/sequencer. That executable
is a playback verification client, not another document editor conversion.

`ProjectService` is a narrow Swift wrapper over native project I/O, not a Swift
copy of `ProjectWorkspace`. It offers `open(root:)`, `openSong(label:)`,
`save(snapshot:)`, and confirmed bank edit/replay operations. Native work reuses
`DecompProject::{open,playableSong,loadBank,applyVoicegroupEdit,saveVoicegroup}`
and `SongRegistry::{mergeCfgFlags,writeSongFlags}`. A serial native worker owns
`DecompProject`; Swift receives owned metadata/bytes and immutable bank leases.
The adapter carries only these service results, never document-edit requests.
Reuse existing save ordering: optional bank save, MIDI, then flags; failures are
reported and never mark the document clean. Swift alone parses/encodes MIDI.
The existing `ProjectIo`/`ProjectWorkspace` application orchestration is excluded
with the old workspace at cutover, not wrapped as a second Swift application.
Native tone inspection supplies a resolved voice kind to Swift `VelocityMap`;
do not duplicate the recursive instrument tree in core.

`DocumentSession` owns the document/history, selection, track scope, camera,
mute/solo and playback projection. Session changes do not dirty the song.
It coordinates project-save completion and the one document change callback.
An `ApplicationSession` owns the open session and strongly retains its grid
presenter. QML gets that presenter via a verified object-return method; QML
proxy lifetime is not Swift ownership. No QML→Swift object-argument setter.

## Single consumer and host

Task 8 converts existing `PianoGrid` to a required `DocumentSession` dependency.
Remove document/session IDs, subscriptions, revision feed copies, command pipe,
read-only rollout mode and the local row-ID versus NoteID translation. Scene
geometry remains a derived rendering representation, never mutable song storage.
Reuse `GridGesture`, `GridScene`, `GridGeometry`, `TimeAxis`, palette and typography.
The final `PorydawApp` module contains both the session composition and retained
grid sources; it does not depend on a SwiftGrid module that depends back on it.
Core and playback remain separate modules.

A small `RewriteWindow` QWidget/QQuickView container replaces—not subclasses or
conditionally hosts—`MainWindow`, `SongTab` and `SongView`. Keeping this narrow
native container preserves existing `keymap::Registry` window QActions and native
menus without introducing a second dispatcher. It owns Qt window/event delivery;
Swift owns application/document policy. Use existing application startup, theme
and font services; transfer the existing palette mapping, not hardcoded colors.
No header/list/drawer/transport-bar presentation is constructed.

Open Project/Open Song, Save, Undo/Redo and Play/Pause remain available through
native actions/dialogs. Existing registered actions keep canonical shortcuts;
Open Song is an unshortcutted menu action, not a new registry ID. Task 7 names
the scalar host queries and asynchronous-save completion contract, including
Save/Discard/Cancel before close or replacement. Optional `--project <path>
--song <label>` arguments select real data for deterministic native smoke;
they do not select an alternate implementation.

Existing plot and gutter QML input is rewired from the old band to the same
Swift gesture logic. Preserve drawing, selecting, moving, resizing, deleting,
right-drag selection, double-click behavior, audition, pan/zoom and cancellation.
Do not invent right-drag erasing: inspect the existing right-pointer behavior.
Leading resize uses the already-present grip and new atomic core operation;
this closes the old transport limitation, not a new tool or QML control.

Keep note-targeted existing commands (copy/cut/paste/duplicate, delete/select,
transpose/nudge, split/join/lengthen/shorten), snap/pencil controls and track
mute/solo. Use the current clipboard payload/TPQN rules. Commands which open
excluded editors (pitch bend, velocity/signature prompts, time/ruler editing)
are absent with those surfaces; do not add replacements. Core operations behind
them are still complete. Window actions retain priority over Quick focus, bare
Space stays transport, and the existing editor key policy handles grid keys.
No QML shortcut map. The host delivers the four named cancel reasons correctly.

## Verification

### Test-language ownership

Swift owns the setup, operations, expected results and comparisons for Swift
codec, musical semantics, document edits/history, imports and timeline logic.
Checks call production Swift directly; they are not Swift forwarding functions
whose results are asserted by a C++ semantic driver. Preserve baseline inputs
and assertions, not the language or class structure of their original tests.

Reuse the existing Deno/CMake execution and fixture-staging path where it does
not constrain Core. `swiftcore` remains the permanent Swift-domain harness.
Named QTest slots may remain selection/reporting envelopes: they invoke a Swift
suite and forward its completion/failures, never receive or manipulate Core
objects. This hosting choice is replaceable test infrastructure, not a Core
compatibility obligation. If it cannot support a required Swift lifetime or
execution model, correct the test host and its bounded integration write set;
do not simplify Core to fit it. Preserve selection, staging, diagnostics,
failure propagation and coverage through that correction.

New cases/data rows live in Swift without a C++ test body, expectation table
or per-operation export. Native glue may report a Swift failure but must not
decide musical expected values or reconstruct domain state. Assertion-specific
projections belong in Swift test code, not public Core inspection APIs.
Use normal Swift test access where needed rather than widening production
visibility for C++. Keep reporting support small; no test DSL, custom discovery
framework or parallel fixture runner.

Swift Testing/XCTest adoption is not required to move assertions into Swift.
If proposed, qualify its supported entrypoint, linkage, selection and failure
propagation on the actual toolchain first; do not assume SwiftPM integration,
use private test-library entrypoints, or migrate the app's build system.
Async service checks must finish before the envelope reports completion and
must not block the main actor waiting for their own continuation.

During parity, a separate check-only native oracle adapter calls the frozen C++
implementation and returns observed results to Swift for comparison. It owns no
Swift implementation driver, musical policy or alternate domain model. Keep it
separate from the permanent suite-reporting boundary and delete it with the
oracle at task 7. Expected-result assertions survive that deletion; equality
between two implementations is not their sole correctness condition.

C++ tests remain appropriate for real Qt/QML interaction, retained engine/device
behavior, native project services and C ABI/lifetime integration. Split mixed
suites at their observable contracts: pure Swift-domain assertions move to Swift;
native interaction assertions remain where native access is required. Calling
Swift through a C wrapper does not by itself make a test native integration.
No new C++ domain checks or permanent reverse Swift-operation adapter.
After this rewrite is accepted, the follow-on
[camera/drawer verification ownership](../swift-editor-consumers/spec.md#verification-ownership)
keeps new semantic assertions in Swift and new component interaction coverage in
QML, while retaining native-boundary regression protection; it does not reopen
this task's placement for the core rewrite.

Acceptance review rejects any Core type/signature/conformance/access-control or
compiler-setting change justified only by C/C++ harness compatibility. Prove
tests execute the actual Swift API/ownership model, not a copyable or C-shaped
test-only variant of Core. The old oracle returns comparison observations to
Swift; it does not dictate the replacement model.

| Source evidence / current filter | Required rewrite coverage |
| --- | --- |
| `smfcheck`, `roundtrip`; `src/checks/midi/` | Codec, unknown data, import verdicts, exact tempo samples, exported assembly parity |
| `editcheck`, `noteidcheck`; `src/checks/editcheck/` | All note/event/track/time operations, identity, dirty/save, normal undo grouping |
| `xcmdcheck`, `automation-domain` | Echo epochs, value-stream rewrite/collision/seams, opaque preservation |
| `velocity-model` | Velocity quantization and real voice-kind resolution; not the absent velocity UI |
| `savecheck`, core portions of `vgbankcheck`/`vgsavecheck` | Real project save/reopen, confirmed bank/history ordering and save failures |
| `loopcheck`, `primecheck`, `transportcheck`, `trackactivitycheck`, `exportcheck-loop`, `exportcheck-tail` | Swift timeline/sequencer through retained engine, looping/chase/live replacement/export |
| `clipcheck`, `clipmimecheck` | Retained grid clipboard semantics; absent lane UI is not needed to preserve stored clip data |
| `swiftrollgated`, `swiftbandkeys`, grid/window portions of `selectionkey`, `swiftqtml` | Repoint actual-surface input/render/lifetime coverage; remove old flag/token/plumbing assertions |

Task 7 builds `porydaw_checks` with permanent Swift-domain suites and retained
native-service checks; task 8 adds converted grid/window cases. `swiftcore`
survives; its oracle dependency does not. Retire superseded pure-domain C++
test bodies/registrations after their mapped Swift assertions pass. Do not keep
alias registrations or repoint those bodies through per-operation Swift exports.
Absent UI scenarios stay in source as deferred references, excluded from
registration/compilation: headers, rulers, drawers, browser/settings dialogs,
event views, pitch-bend editor, multi-tab/workspace chrome, and their visual
suites. Mixed suites must separate the retained core/grid rows from absent UI
rows; a filter name is not permission to disable its useful domain coverage.
List exact deferred case names with the final implementation evidence. Do not
claim the historical whole-app suite passed. Unfiltered verification then means
the entire **declared rewrite manifest** only.

### Case-by-case coverage reconciliation

**Effective immediately for active task 1.** Before accepting it, create
`coverage-ledger.json` beside this spec. Preserve work already implemented;
backfill its mapping and evidence rather than restart. This file is execution
evidence, not a pre-populated claim that the conversion has passed.

Freeze the reference revision before check migration. Inventory every existing
C++ case covering an in-scope core behavior, including meaningful data rows,
fixture variants and core assertions embedded in mixed UI/service cases.
The table above is a starting index, not the inventory's completeness proof.
Reconcile catalogue registrations, test source and generated row discovery;
independent review must detect omitted cases, not merely inspect listed rows.
Keep the frozen identities even after their C++ source or registration retires.

The JSON has `referenceRevision`, `inventoryEvidence`, and `cases`. Each case
records `cppId` (harness/class/function/data-row or explicit no-row marker),
`source`, `fixturesAndInputs`, `operations`, `observableAssertions`, `dueTask`,
`swiftTargets`, `status`, `runEvidence`, and `exclusionReview`.
`swiftTargets` identifies the executed case/data row and assertion location.
For domain rows, that location must be a Swift test body, not just a containing
QTest slot or a C++ assertion over a Swift result. Native integration rows name
their real native boundary and may identify a C++ assertion. Run evidence records
exact command, tested revision, executed case/row identities, results and durable
output paths.
Use only `pending`, `verified`, `excluded` or `deferred-ui` for status.

Prior C++-assertion results remain historical parity evidence, not proof of
Swift test ownership. A migrated row is pending until its new Swift assertion
location and fresh execution evidence are reconciled. Preserve the old evidence
and frozen identity; do not relabel an old run or erase the baseline.

**1:1 means behavioral traceability, not copied test code or equal counts.**
Preserve each baseline input, operation and observable assertion. Consolidated
tests must retain every mapped scenario and identify failures by baseline ID.
Split mixed cases by their observable assertions: excluding the UI portion must
not discard core coverage. No weakening expected values or widening tolerances
to fit Swift. Existing tolerances remain; any necessary comparison normalization
requires an explicit rationale and independent review before it counts.

`verified` requires execution against production Swift, expected-result
assertions, and comparison with C++ while the oracle exists. A passing C++ run,
an unexecuted Swift target, or skipped/disabled row is not verification.
Task 1 assigns the complete inventory to tasks 1–8 and closes its own rows;
later-task rows may remain pending only until their named acceptance gate.
Tasks 2–6 close their due rows with their recorded covering commands. Native
integration cases due in task 7 are exercised before reference retirement.

Exclusions require case/assertion-level reason and independent reviewer approval.
Only genuinely obsolete transport/implementation assertions may be `excluded`;
only approved absent-surface assertions may be `deferred-ui`. Core behavior
cannot be relabelled as UI simply because its old test constructed a widget.
Any behavioral ambiguity or requested scope reduction remains pending until
resolved; implementation difficulty is not an exclusion reason.

**Task 7 retirement gate, before deleting any C++ core/oracle:** reconcile the
frozen inventory against the ledger with zero missing IDs, unmapped assertions,
unapproved exclusions, or pending/failed/skipped core rows. All retained core
rows must have reviewed Swift and C++ execution evidence. Task 8's retained
grid-only rows may remain pending, but its core assertions must already pass
through a headless driver. Capture the reference results before removing it.

After task 7 retires oracle adapters and superseded test drivers, reconcile the
ledger against the retained manifest and executed results: every required core
row still runs, with domain assertions in Swift and native-boundary assertions
exercising the actual replacement.
Task 8 closes retained grid rows and repeats final reconciliation. Do not shrink
the denominator by editing the baseline or silently dropping a registration.
Record totals for baseline, verified, approved exclusions, deferred UI and
pending rows, with zero unexplained gaps; totals supplement assertion review,
never replace it. No permanent coverage framework or impossible-state tests
are required by this amendment.

Native smoke uses the actual production window and staged project fixture:
load a looping song, draw/move/resize/delete, undo/redo, save/reopen, play/pause,
edit during playback, cancel by Escape and ordinary focus/window transitions,
close/reopen. Inspect rendered notes, theme and font scaling. Core fixtures also
prove data not displayed by this grid survives saving and rendering. Benchmarks
compare the same scene/workload; record measured allocation/render cost without
adding a performance-monitoring subsystem.
