# M1/M2 gate decisions — completed inventory and proposal

Status: proposed 2026-09-19 after source-evidenced inventory. Extends
[design.md](design.md) §3/§4 with the caller inventory those sections
required. Not authorized for dispatch: this document records decisions and
names the approvals required from the user.

Evidence base: caller inventory collected 2026-09-19 at `bc24c98d`
(scope: `src/` excluding build/external). Every row cites file:line.

## A. M2 gate — complete mutating-caller inventory

Every document mutation in the application routes through `SongDocument`'s
typed command API into one `QUndoStack` that `SongDocument` owns as a member
(`songdocument.h:621-622`); `SongHistory` holds a reference to that stack and
wraps every pushed command in a `SongHistory::Entry`. Commands are
`SongEditCommand`, `MoveNotesCommand`, `MoveNotesToPitchesCommand`,
`ResizeNotesCommand`, `SongCfgCommand`, `MixedEditCommand`,
`TempoEditCommand`. Lifecycle exceptions that intentionally bypass the
command path: `adoptSmf` (direct publishMutation, `songdocument.cpp:572`) and
`setTrackBudget` (plain setter, `songdocument.h:166`). The mutation API
surface a Swift authority must cover (or serve to legacy clients):

notes (`addNote(s)`, `deleteNotes`, `moveNotes`, `moveNotesToPitches`,
`resizeNotes(Left)`, `setNotesVelocity(ies)`, `nudgeNotesVelocity`), lanes
(`addLanePoint`, `writeLanePoints`, `moveLanePoints`, `deleteLanePoints`),
tempo (`applyTempoEdit`, `removeRawEventsAndEditTempo`,
`replaceTempoPointWithRawEvent`), range (`applyRangeEdit`, `moveRange`,
`removeTimeRange`, `insertBlankTime`, `duplicateTimeRange`), raw events
(`insertRawEvent`, `modifyRawEvent`, `deleteRawEvents`, `moveRawEvent`,
`setTrackEndTick`), markers/sigs (`setLoopTick`, `setTimeSig`,
`moveTimeSig`, `deleteTimeSig`), tracks (`addTrack`, `duplicateTrack`,
`deleteTrack`, `moveTrack`, `renameTrack`), config (`setCfg`), lifecycle
(`adoptSmf`, `setTrackBudget`, `didSave`, `captureSaveSnapshot`;
`buildTimeline` is a const query, not a mutation).

Mutating caller sites by surface (all on the shared stack):

| Swift roll (production) | sgc_ → `intent_executor.cpp` | notes add/move/resize/delete, renameTrack, addTrack, duplicateTrack, deleteTrack, moveTrack (`intent_executor.cpp:208-244`) |
| Time ruler | `timeruler_interaction.cpp:216,224`, `timeruler.cpp:373` | moveTimeSig, setLoopTick, setTimeSig |
| Edit-key routing | `editkeyrouting.cpp:88-89,106,108-110,371,375,388` | setLoopTick ×6, deleteTimeSig |
| Event list controller | `eventlistcontroller.cpp:651,672,700,703,705,721` | insertRawEvent, removeRawEventsAndEditTempo, deleteRawEvents, applyTempoEdit, moveRawEvent |
| Controller lanes | `cclanes.cpp:175` | writeLanePoints |
| Automation canvas | `automationcanvas_gesture.cpp:139` | applyRangeEdit |
| Voice-change area | `voicechangearea.cpp:539`, `voicechangemenu.cpp:251,254,308` | move/add/deleteLanePoints |
| Tempo lane | `tempoadapter.cpp:58` (tap-tempo reaches it indirectly via `TempoLane::replaceSpan`, `automationcanvas_taptempo.cpp:56`) | applyTempoEdit |
| Event table editor | `eventtablemodeledit.cpp:42,55,90,135,272` | setTrackEndTick, applyTempoEdit, raw-event conversions, modifyRawEvent |
| Pitch bend editor (C++) | `pitchbendeditor.cpp:227,236` | writeLanePoints |
| Range edit/clipboard | `rangeedit.cpp:499,534,563,605,626,665,683,749,786` | applyRangeEdit, moveNotes, moveNotesToPitches, moveRange, remove/insert/duplicateTimeRange, addNotes |
| Track/voice ops | `trackvoiceops.cpp:285,287,308,319,329,337,341` | voice lane points, renameTrack, add/duplicate/delete/moveTrack |
| Header menu/model | `trackheadermenu.cpp:153,161`, `trackheadermodel.cpp:571,1187` | duplicate/delete/add/moveTrack |
| Velocity area | `viewstate.cpp:69` (via `velocityarea_interaction.cpp:203`) | setNotesVelocities |
| Legacy C++ pianoroll | `pianoroll_commands.cpp:199,240,273,308,319,704`, `pianoroll_gestures_active.cpp:246,274,287,291`, `pianoroll_interaction.cpp:66` | move/resize/delete/add notes, velocities (retires with the roll cutover) |
| Config/settings | `mainwindow.cpp:490,1353`, `workspaceui.cpp:195`, `workspaceui_project.cpp:210` | setCfg |
| Voice bank (async) | `workspaceui_voicegroup.cpp:52,67`, `voicegroupviewcache.cpp:40` | worker-confirmed SharedBank entries on the same stack |

Mechanics an authority move must preserve (verified sources):

- **Shared voice-bank history**: bank edits are asynchronous —
  `WorkspaceUi::beginBankTransition` arms a pending transition and sends a
  draft to the background project worker; on `VoicegroupEditApplied`,
  `SongHistory::pushConfirmedBank` pushes an inert-callback
  `HistoryKind::SharedBank` entry (`songhistory.cpp` ~225); undo/redo of bank
  entries does not cross synchronously — the worker confirms, then
  `crossConfirmedBankUndo/Redo` moves the stack index; conflicts mark entries
  obsolete instead of unwinding document edits
  (`resolveBankUndoConflict`/`resolveBankRedoConflict`, `songhistory.cpp`
  ~258/~270); scalar bank edits merge until `sealBankMerge`
  (`songhistory.cpp` ~131/~196).
- **Save identity**: `captureSaveSnapshot` (`songdocument.cpp:605`) freezes
  a canonicalized SMF + revision + saveStateToken + document identity;
  background `ProjectIO::saveSong` writes voicegroup source → `.mid` →
  `midi.cfg`; `didSave` refuses to mark clean if revision/token/identity
  moved (`songtab.cpp:208`; refusal logic `songdocument.cpp` ~617,
  `isDirty` at `songdocument.h:142-146`).
- **Playback publication**: GUI thread builds an immutable `MidiTimeline`
  (`songdocument.cpp:2262`), published lock-free via `TimelineHandoff`;
  adoption mid-playback chases controllers/voices without cutting notes
  (`audioengine.cpp:282-302`).
- **Roll commit path**: Swift intent → `sgc_submit` → executor →
  `SongDocument` mutation → history push → `documentChanged` → timeline
  rebuild + sgd_/sgs_ snapshot push back to Swift.

## B. M2 legacy-client strategy — recommendation

**Options.** (A) Migrate every caller with the authority: one cutover ports
the §A table's 17 C++ editor surfaces' mutation calls to Swift-submitted ops
while the document moves. (B) A bounded shared legacy-client adapter: after
the Swift authority
lands, not-yet-migrated C++ editors submit typed ops to Swift through one
narrow seam with a single invalidation feed back; the adapter retires when
the last legacy editor migrates.

**Recommendation: B.** Costs and reasoning:

- Option A couples the authority move to 50+ enumerated call sites across 17
  surfaces (§A table); any missed surface means a disabled editor —
  explicitly unauthorized — and the single acceptance gate becomes unbounded.
  The surfaces also retire at different times anyway (legacy pianoroll dies
  with the roll cutover; ruler/lanes/event-list/event-table are M3+ waves),
  so "migrate everything first" is sequenced waste.
- Option B is the current architecture mirrored: today Swift submits intents
  to the C++ authority through one seam (`sgc_` + `intent_executor`); after
  M2, C++ editors submit ops to the Swift authority through one seam. No new
  per-surface adapters appear; submission is not state ownership (charter
  restated INV).
- Bounded by enumeration: the adapter's op vocabulary is exactly the §A
  mutation API surface — no open-ended growth. Query/invalidation delivery
  is one snapshot+invalidation channel (the shape `sgd_` already has),
  consumed by remaining C++ views.
- Named deletion gate: the adapter (say `legacy_song_ops`) and the C++
  `SongDocument`/`SongHistory` implementation are deleted together when the
  last legacy editor caller migrates — the retirement table already assigns
  this. Cost of B: a C-shaped transport outlives M2, and the op vocabulary
  must be designed once against the full §A surface (which is also exactly
  the Swift document module's native API — the adapter is a thin envelope
  over it, not a second model).
- Hard cost priced in, not hidden: the seam must carry the asynchronous
  shared-bank protocol (worker-confirmed pushes, two-phase undo/redo
  crossing, conflict resolution, scalar merge sealing) and the save-identity
  handshake (snapshot capture + stale-save refusal) across the C++/Swift
  boundary — these are the two hardest pieces of §A mechanics, and the
  adapter design must specify them, not just op submission. That design work
  is part of the approval request, not deferred to implementation.
- **Requires explicit user approval** (charter: any new shared legacy-client
  adapter). Not implemented by any dispatched task until approved.

## C. M1 staging — two consumers without unauthorized expansion

The C ABI vocabulary is frozen and production header retirement is not
authorized. M1 therefore stages:

- **M1a (dispatchable after probe + org land)**: `DocumentSession` Swift
  object as the composition/lifecycle owner: owns feed payloads (sgd_/sgs_
  receivers), presents one native Swift session interface consumed by the
  grid presenter and the headers presenter core (`TrackHeadersPresenter` on
  a probe-grade QML surface, not the production header). Grid behavior
  unchanged (still submits through `sgc_`). No new C symbols; no production
  header replacement. Proves the two-consumer lifetime/notification shape
  the contract ledger records.
- **M1b (requires approval — track metadata delivery)**: production headers
  need track names/voice labels/activity — not in `sgd_`. Options to decide:
  (1) widen the document feed (C ABI expansion — currently unauthorized);
  (2) C++→Swift push through the session's QtBridge QObject proxy
  (meta-object invocation — no new C symbols, uses the bridge in the
  reverse direction through an existing mechanism; needs a capability probe
  row first); (3) defer headers to the M2 authority move where the feed
  question dissolves. Recommendation: probe (2) in M1a; if unsupported,
  headers wait for M2 rather than widening the ABI.

## D. Named C++ deletions per milestone (proposal)

| Milestone | Deletes | Gate |
| --- | --- | --- |
| M1a | none (additive Swift composition) | two-consumer ledger rows Verified |
| M1b (if approved) | `trackheadermodel.{h,cpp}`, header presenter wiring behind `trackHeaderModel` context property, `TrackHeaders.swift` remaining transport (none left after swift-org) | full header dependency inventory (design §3) migrated; `trackheader` suites re-pointed |
| M2 (+adapter, if approved) | `SgdDocument.swift`/`SgcCommands.swift` transport mirrors, `sgd_`/`sgs_`/`sgc_` feeds + executor + registrations, hand-mirrored C enums, spec §5 leading-resize deviation (one transaction per gesture restored) | §A inventory fully served; save/voice-bank/playback acceptance in design §4; `deno task verify` green with C++ authority out of the build |
| M2 input/mount (separate) | `sgk_`/`sgb_`/`SwiftRollBand` input mirrors — NOT deleted at M2; their own replacement gate | replacement input delivery passes command/priority/cancel behavior |

## E. Decisions requiring user approval

1. **M2 legacy-client adapter (option B)** — scope: single submit-ops +
   invalidation seam over the Swift document module, op vocabulary = §A
   surface, consumers = unmigrated C++ editors only, deletion at last-caller
   migration. Alternative: option A (all callers migrate with the
   authority) or deferring M2 until surfaces migrate (slowest, keeps C++
   authority longest).
2. **M1b track metadata delivery path** — recommendation: probe QtBridge
   reverse-direction invocation in M1a; ABI widening only if that is
   Unsupported and headers cannot wait for M2.
3. **Timing of `swiftroll` (ex-swift-grid-prototype) production mount** —
   default-flag flip is its own gate per the charter retirement table; not
   requested now.
