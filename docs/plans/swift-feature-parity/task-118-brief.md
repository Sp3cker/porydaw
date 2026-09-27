# Task 118 brief — complete editor view state fans out once and follows engine-track remaps

# Context

Replace the current range-only fanout with the fork’s complete typed editor-state transaction. ApplicationSession currently retains EditorLaneState privately and copies only laneRanges to pages; hidden/empty lane identity and complete-state remapping have no live document owner. This is a genuine fceecd88 divergence, not a stale ledger preamble. Task 122 later reuses ApplicationSession; task 119 later reuses AutomationPage.

Verified planning selection: **71 open rows (60 GAP + 11 PARTIAL)**. This is the in-flight §13 census, not a completion claim.

- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_state.txt` — A103, A105, A106, A107, A108, A109, A110, A111, A112, A113, A114, A115, A116, A117, A118, A119, A122, A124, A125, A126, A127, A128, A129, A130, A131, A132, A133, A134, A135, A136, A137, A138, A139, A140, A141, A142, A143, A144, A146, A147, A148, A149, A150, A151, A152, A153, A154, A156, A157, A158, A159, A160, A161, A162, A163, A165, A166, A167, A168, A169, A170, A173, A174, A175, A176, A177, A179, A180, A181, A182, A183.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `85b97239ce94dc4c4cf5f3f4fb66fc96ff2cf27e`. Read selected expressions with `deno task proof sites` / `show`; deleted C++ check paths are references, never write targets.

# Exact write set

- `src/swift/app/timeline/EditorViewStateCodec.swift`
- `src/swift/app/DocumentSession.swift`
- `src/swift/app/DocumentSession+Internals.swift`
- `src/swift/app/DocumentWorkspace.swift`
- `src/swift/app/ApplicationSession.swift`
- `src/swift/app/drawer/automation/AutomationPage.swift`
- `src/checks/workspace/session_view_state.swift`
- `src/checks/editorqml/TabsDrawerProbe.swift`
- `src/checks/editorqml/tst_ShellTabs.qml`
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_state.txt`

Closed list: production writes are limited to the interface below. The implementer owns code/check files; the separate ledger writer alone owns the listed proof files after evidence settles, in the same surface change.

# Prerequisites

All 111/112/114 work and the 113 follow-up must be accepted and checkpointed. Preserve 103’s tab lifecycle, 110’s save/Undo ownership and 114’s hint lifecycle. Group A 115 owns interaction/QML, not AutomationPage.swift; do not require a new 115 interface.

# Interface contract

- In EditorViewStateCodec.swift define public EditorViewState: Equatable, Sendable containing chrome: EditorDrawerChromeState and lanes: EditorLaneState, initialized from their existing defaults. Preserve all existing codec keys and normalization. Add mutating EditorLaneState.remapEngineTracks(_ map: [Int?]) -> Bool: validate the entire mapping before mutation, reject duplicate non-nil destinations, preserve Tempo identity, remap each CC track in height/range dictionaries and empty/ordered-hidden collections, drop deleted owners, preserve hidden ordering, and return false for rejection or no value change. Do not manufacture a document edit to carry cosmetic state.
- DocumentSession owns public private(set) editorViewState and setEditorViewState(_ state: EditorViewState) -> Bool. A value-changing origin publishes one onEditorViewStateChanged callback; an identical value publishes none. An internal applyEditorViewStateProjection(_:) updates a sibling silently. These are production state-transfer interfaces, equivalent to fork setEditorViewState/applyEditorViewState, not test-only setters. DocumentSession+Internals consumes valid DocumentChange.trackRemap before normal session publication; do not replace the existing onChange subscriber or double-remap on Undo.
- ApplicationSession consumes each session’s origin callback, projects the complete value to every tab including the selected/nonselected pair, applies chrome and current lane ranges through existing drawer/page methods, and persists the value once. Keep public editorChrome compatibility as the existing externally used projection, not a second authority. Expose owned QtBridge editorViewStateChanged and editorViewStatePersisted signals as the real fanout and completed preference-write notifications; emit each exactly once for a changing origin, never for sibling projection, unchanged values or rejected remaps. No debug counter/property is added. Combine chrome/lane preference writes into one synchronized persistence operation while retaining the existing individual codec APIs for their actual callers.
- Fork completeSeed includes section visibility/heights, active page, base/per-lane heights, ranges, empty lanes and ordered hidden lanes. Preserve every member in both tabs and CFPreferences, not just current laneRanges. Hidden records [(1,7),(0,80)] retain that order. A nonselected origin changing CC74 range to 80 updates both tabs and emits origin/hub/persist once with zero sibling-origin emission. Identical range/set insert/nonexistent erase are all silent. Legacy per-lane metadata remains codec-backed state; this task does not invent a new stacked-lane UI or hide one of the fixed parameter tabs.
- For move/Undo, use the existing real document moveTrack transaction from track 1 to the fork’s target and preserve exact remapped CC identities, Tempo range 100 and full state equality. Origin/hub/persist count 1 after move and 2 after Undo; sibling origin remains 0. Undo restores original MIDI bytes and clean dirty state. With reduced state containing no track-owned metadata, the same move/Undo emits no cosmetic changes.
- View-only empty-lane insertion/removal emits exactly one origin/hub/persist per change while full MIDI bytes, revision and history count stay unchanged. Rejected map [0,0] leaves both tabs, preferences, bytes, revision and all notification counts unchanged; the value-copy remap also returns false and retains the complete value. The original snapshot conjuncts A164/A171/A178 are explicitly excluded: no sidecar-directory claim is made. A122 is a native fixture track-count guard; preserve the real two-track move scenario rather than adding a setup assertion.

# Implementation steps

1. Consolidate the existing chrome/lane value into the named typed transaction and add atomic pure remapping without changing codec grammar.
2. Wire origin versus silent projection through DocumentSession, ApplicationSession and existing drawer/page range consumers; release callbacks during detach to avoid dead-tab publication.
3. Extend session_view_state with completeSeed, exact notification counts, real move/Undo, view-only and invalid-remap predicates; use a copied project fixture and isolated preference domain.
4. Extend shell-tabs with real two-tab range/menu and track-reorder interactions plus projected state/viewport consequences. The existing TabsDrawerProbe may stage typed initial state but may not fake a user gesture or expected values.
5. The separate ledger writer updates only these 71 state rows; keep this ledger and every unselected snapshot/lifecycle/input row.

# Acceptance predicate

The complete typed state, atomic remap, origin/sibling notification distinction and synchronized preference receipt are proven by registered session checks. shell-tabs supplies actual range/reorder/tab-switch smoke. No value is reconstructed from the implementation as its own oracle, and the three unselected sidecar snapshots stay open.

The implementer runs these exact covering lanes under §13’s build-lock policy; the controller runs the settled-group full gates:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs --verbose
```

# Task-specific constraints

No SongTabsController, ShellWindow, automation interaction/QML, core document/history or project-store edits. The larger write set is the existing origin→fanout→persistence surface, not permission for unrelated lifecycle work. No new user gesture is introduced.

Read sprint-3 §13 “Evidence and execution contract” as part of this brief: real input; independent expectations; no setup-only assertions; exact raster colors/positions and executed DPR2 where claimed; no shell dispatcher in editorqml; verbatim existing and unique complete new messages; all exact-content fixture consumers updated; copied-fixture isolation for shared bank leases; implementer-owned locked lanes; separate ledger writer.
