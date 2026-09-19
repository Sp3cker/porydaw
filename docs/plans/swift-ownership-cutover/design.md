# Swift ownership design and cutover plan

Status: proposed to the user 2026-09-19. Not dispatched. Governing docs:
`docs/plans/swift-backend-charter.md` (amended 2026-09-19) and
`docs/plans/qtbridge-integration-contract.md` (integration contract; all
scenarios Unverified until runtime evidence is recorded there).

## 1. Ownership map

**Swift owns** (native Swift modules, no C ABI shapes in domain types):

- Document state: notes, tracks, meter/signature state, revisions.
- Editing operations and transactions: one gesture = one transaction, by
  construction (closes the Wave-4 leading-resize deviation).
- History: the single undo/redo stack, including shared voice-bank history
  ordering.
- Session state: selection, focus track, playback view state fed to
  presenters.
- Presenters: grid, track headers, and every later surface — exposed to QML
  through QtBridge directly.

**QML owns**: views, delegates, input items, visual trees — consuming
QtBridge-exposed Swift presenters and collections. QML interfaces may change
to fit Swift presenters; user-visible behavior is the contract.

**Native C++ remains** in exactly two classes:

- Retained native services: audio engine/DSP (`src/audio/`, poryaaaa
  compat) and platform integration, behind a narrow service interface.
  Kept deliberately; never rewritten merely to remove C++.
- Legacy document adapters (until their retirement milestone): the
  `sgd_`/`sgc_`/`sgs_`/`sgk_`/`sgb_` seams, hand-mirrored C enums, parity
  oracles, and the C++ `SongDocument` authority itself — read-only oracle
  (S-1) until the cutover that deletes them.

Not owned anywhere: per-surface handwritten C++ presenter mirrors (class
forbidden; `TrackHeaderModel` is the named retiree of milestone M1).

## 2. Grid and headers on shared Swift state (M1 — QtBridge two-consumer proof)

One Swift `DocumentSession` object per open song, exposed to QML via
QtBridge. Both the grid presenter and the track-headers presenter are
children of that session and read/write through it Swift-to-Swift — never
through per-surface feeds. Today the session is *fed* by the single legacy
`sgd_`+`sgs_` adapter pair (one feed, N consumers); after M2 the session is
the authority itself and the feed is deleted.

- Grid: `PianoGrid` presenter keeps its proven band math and gesture logic;
  its editing intents become direct Swift transactions on the session
  (replacing the `sgc_` pipe) in M2 — in M1 the grid keeps its current
  seam path and only its *presenter surface* moves to the shared session.
- Headers: `TrackHeaders.swift` (preserved, unreferenced) is re-based onto
  the session and exposed through QtBridge as the `trackHeaderModel`
  replacement. No C++ presenter, no `sgth_`-style mirror; its current C
  callback plumbing is replaced by native Swift observation of the session.
- Deletes: `src/ui/songview/trackheadermodel.{h,cpp}` and the C++
  presenter path behind `TrackHeaderBand.qml`'s current context property,
  at the row set defined in the integration contract.

Acceptance is the contract's evidence ledger: every scenario in
`qtbridge-integration-contract.md` (rename in place, insert/remove/reorder
with stable identity, edit+undo observed from both consumers, collection
reset vs. transient editors, tab close with pending notifications, sibling
tab survival, reopen/teardown) gets a registered check under `src/checks/`
exercising real QML delegates, plus the lifetime ownership table the
contract requires. All rows start Unverified; none are promoted without
recorded commands and observed results in the contract file.

## 3. Moving document/editing/history authority without twins (M2)

The C++ `SongDocument` + `QUndoStack` authority moves into the Swift
`DocumentSession` as the single writable model and single history:

- Migrate the document core (notes/tracks/meter, command set, undo/redo)
  into Swift as native types. One history object; every mutating surface —
  grid gestures, headers ops, voice-bank edits — commits transactions to it.
- The shared voice-bank history behavior is explicit acceptance: voice
  edits and note edits interleave in one undo ordering, proven by checks
  that interleave them and undo across both.
- Remaining C++ consumers (any surface not yet migrated) read the Swift
  authority through a bridge view; they never write. No synchronized twin
  exists at any instant — the cutover is atomic per document-open, INV-2
  style: checks re-pointed, green, then C++ deleted.
- Keyboard arbitration, popups, and window behavior are untouched by M2
  (INV-1/INV-3): the same single authority, whatever host tier it lives in.

## 4. Deletions named per milestone

| Milestone | Deletes |
| --- | --- |
| M1 (QtBridge two-consumer) | `trackheadermodel.{h,cpp}`, the C++ header presenter wiring behind `trackHeaderModel`, `TrackHeaders.swift`'s dead C-callback layer (replaced by session observation). |
| M2 (authority cutover) | `sgd_`/`sgc_`/`sgs_`/`sgk_`/`sgb_` adapter sources and registries (`document_feed`, `session_feed`, `command_feed`, `key_feed`, `swift_roll_band`, `intent_executor`, mount plumbing), hand-mirrored C enums in Swift, `SgdDocument.swift` mirror types, the Wave-4 spec deviation (leading resize becomes one transaction). |
| M3+ (surfaces: ruler, lanes, songtabs, chrome) | Each surface's C++ widget/presenter implementation at its cutover; no new seams created. |
| Final | Nothing in class 1 remains; audio service (class 2) remains. |

Naming debt (`swift-grid-prototype/` directory name, `sg*` prefixes) dies
with M2's deletions or earlier renaming inside M1 where files are touched
anyway.

## 5. Proof scenarios and commands

- M1: new harness `swiftqtml` (working name) under `src/checks/`, one row
  per contract scenario, real QML delegates over the real integration;
  `deno task verify --filter swiftqtml --verbose`. Existing production
  suites must stay green unmodified (V-1): `deno task verify --filter
  trackheaders --verbose`, `--filter swiftrollgated --verbose`,
  `--filter selectionkey --verbose`. Evidence recorded in
  `qtbridge-integration-contract.md` with exact commands and observed
  results; the two-consumer acceptance runs on the recorded toolchain
  baseline (Qt/Swift/bridge/patch revisions logged there first).
- M2: `deno task verify` full corpus green with the C++ document authority
  removed from the build, plus a dedicated `swiftdoccore` harness proving
  interleaved note/voice undo ordering, revision monotonicity under
  concurrent-surface observation, and tab-close/sibling-tab lifetime under
  the new authority. selectionkey suites re-pointed at the unchanged
  arbitration tier and green before any deletion (INV-2).

## Bounded milestones, in order

1. **M0 — Toolchain baseline + lifetime table** (half-day): record the
   contract's dependency baseline (exact Qt/Swift/bridge/patch revisions,
   build config, patch purposes); author the ownership table skeleton; pick
   the smallest real-QML probe proving one QtBridge presenter mutation
   reaches an existing delegate (first ledger row, honestly Unverified →
   Verified/Unsupported).
2. **M1 — Two consumers** (bounded by the contract's scenario table, not by
   surface features).
3. **M2 — Authority cutover** (its own charter-level spec; includes
   voice-bank history acceptance; deletes the legacy adapter class).
4. **M3+ — Surfaces**, each a Swift+QML consumer with named deletions.

No milestone dispatches before the user approves this document. M1 and M2
briefs will reference the charter amendment and the integration contract
by path, not by copy.
