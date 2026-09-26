# Context

ED11 clipboard track interoperability (task 49). Close the two clipcheck ledgers on top of
the landed session-owned time selection: 38a `92b0754b` (`DocumentSession.timeSelection`
with fork `EditorSelectionModel` co-motion laws) and 38b `f7b04f18` (time/ruler menu
semantics). Census correction vs next-sprint.md §5: `proof.selectioncheck_tracks.txt`
moved to 38a's ledger pass — task 49 does **not** touch it (27 GAP + 20 PARTIAL remain
38a/SelectionChecks territory). Task 49's spec surface is exactly
`src/checks/clipboard/proof.clipcheck_copy.txt` (23 GAP + 8 PARTIAL, verified today) and
`proof.clipcheck_merge.txt` (8 GAP + 4 PARTIAL).

1. **What the open rows are** — three families, none a missing semantic:
   - *Time-selection state observability* (copy A036–A041, A051–A055, A086; merge A019):
     each reason says "no Swift predicate observes the native selection model … the
     selection surface is owned by the selection slice". 38a landed that surface;
     `DocumentSession` now publishes `timeSelection`, `SelectionTransition` observers
     (DocumentSession.swift:130-145, 674-681) and note/time co-motion. The clauses just
     need executing predicates.
   - *Real-key delivery* (copy A003/A010/A017/A022/A028/A030/A042/A056/A063/A081/A090;
     merge A003/A008/A015/A027/A034/A037): the fork drove `sendRollKey`/`sendViewKey`
     (Ctrl+C/V/X, Delete) over time-range fixtures; the Swift core lane calls
     `ClipboardSemantics` directly and the mounted supplement only used note selections.
     The mounted window authority delivers real key sequences today
     (`tst_ShellClipboard.qml:204,258,297`; sweep pattern `tst_ShellGridMenu.qml:413-425`).
   - *Cursor/pasted-selection advance PARTIALs* (copy A013/A014/A024/A025/A029/A031/
     A032/A033; merge A011/A020/A036/A039): semantic halves are MATCHED (S001–S013 in
     `ClipboardEditingChecks.swift`); the unproved halves are "the native view selection
     model receives the pasted notes" and "editCursorTick advances to 72/48/96/192" —
     exact-tick fixtures through the production command path close them on the Swift
     surface (session `selectedNotes`/`editCursor` are the production observations; the
     native-view wording is retired representation).
2. **Fork laws** (`git show fceecd88:src/ui/songview/editactions.cpp`): the command table
   pins precedence and routing — Copy = range `CopySelection`/notes `CopySelection`,
   `AlwaysConsume`, focused-text ownership `Copy`; Cut = range/notes `Cut`,
   `SelectionTargeted`; Paste = standalone `Paste`, `AlwaysConsume`; Delete = range/notes
   `Delete`, `SelectionTargeted`. Fixtures (verbatim in the ledger source contexts):
   timeSelectionCopy (track 0, notes {0,60,24,100} selected, tracks selection 0–96 → note
   selection empty, active, bounds 0/96, scope Tracks, stored scope 0x1);
   scopedRangeCopyPasteCreatesTracks (tracks 0–2, notes 12:60:12:90 / 24:64:24:100 /
   36:68:36:110, modulation 18:11/30:22/42:33, scope 0x7; paste into a one-track
   destination expands tracks, one undo entry restores notes+mod lane+voice seed);
   rangeDeleteCutAndUndo (notes 24/96, voice-lane points 24:3/96:5, tempo 24:600000/
   96:400000, range 0–48: delete removes the in-range triple, keeps 96s, **selection
   stays active**; cut = extract-then-delete, one entry, undo restores all three kinds);
   mergeTimeRangeAndUndo (cursor 24, clip span 48 with note {0,60,24,120}, modulation
   {23:110,24:120}, tempo {1:300000,2:400000}: last-wins exact-tick lane/tempo
   replacement, cursor → 48, **selection inactive after paste**, one entry);
   emptyLaneMergeIsNoop (clip span 48, empty volume lane; existing note 24 + point 144:90
   untouched, no history, cursor stays 120); tiledTimePaste (span-96 tile, two pastes →
   cursors 96/192, two entries, one tile per undo); crossTpbNotePaste (24→48 TPQN,
   cursor 24 → cursor 72).
3. **Swift owners — all landed, prove do not rebuild**:
   - `ClipboardSemantics` (`src/swift/app/commands/Clipboard.swift:299-563`): document
     semantics — `copyNotes`, `extractTimeRange(_:scope:from:unterminatedDuration:)`,
     `paste`, `deleteTimeRange`, `pasteCursor`, `gather`, and the remap law
     `destinationTrack`/`singleSourceTrack` (:451-473: single-source clip retargets to the
     selected track, multi-source keeps source indices and expands
     `minimumEngineTrackCount`). Unchanged by this task.
   - `AutomationSelectionCommands` (`src/swift/app/drawer/automation/
     AutomationSelectionCommands.swift:11-106`): the production command path —
     `selectionCommandAvailable` (paste reads the live native clip; range ops gate on an
     active selection + resolved scope), `consumeSelectionCommand` (copy/cut/delete/
     clear/loop/transform + paste), `pasteClipboard(at:)` (one native read, TPQN rescale,
     one atomic paste; span-0 selects inserted notes, range paste clears the time
     selection, cursor → `nextCursor`). Capture helpers in `AutomationModal.swift:356-376`.
   - `GridClipboard` (`Clipboard.swift:572-621`): native transport `write(_:ticksPerBeat:)`
     / `read()` + change observation. Unchanged.
   - Precedence: `EditorCommandRouter` (`ApplicationSession.swift:1354-1418`) —
     `targetsTimeSelection` routes every range operation and paste away from
     `NoteCommands` (note path `NoteCommands.swift:119-129` untouched).
   Expected outcome: **no production change**; a bounded repair in
   `AutomationSelectionCommands.swift` only if a new predicate exposes a divergence.
4. **Ledger rows today** — copy GAP: A003 A010 A017 A022 A028 A030 A036 A037 A038 A039
   A040 A041 A042 A051 A052 A053 A054 A055 A056 A063 A081 A086 A090; PARTIAL: A013 A014
   A024 A025 A029 A031 A032 A033. Merge GAP: A003 A008 A015 A019 A027 A031 A034 A037;
   PARTIAL: A011 A020 A036 A039.

# Exact write set

- `src/checks/automation/automationclipboard.swift` — new
  `drawerAutomationTrackScopedSelectionClipboard(_:suite:service:)` with the exact fork
  fixtures driven through `AutomationPage` production commands.
- `src/checks/automation/AutomationPageChecks.swift` — one registration line in
  `runAutomationPageChecks` (:307-332, beside `drawerAutomationRangeEditAndClipboard`).
- `src/checks/editorqml/tst_ShellClipboard.qml` — two new slots:
  `test_timeRangeSelectionKeys`, `test_scopedRangeCopyPasteKeys`.
- `src/swift/app/drawer/automation/AutomationSelectionCommands.swift` — repair only if a
  new predicate fails (bounded fix, same task; report the divergence first).
- Ledgers (controller-delegated ledger agent, this task's commit): 
  `src/checks/clipboard/proof.clipcheck_copy.txt`, `proof.clipcheck_merge.txt`.

No changes to `Clipboard.swift`, `EditCommands.swift`, `NoteCommands.swift`,
`PianoGrid.swift`, `RulerMenuPresenter.swift`, `ShellPresenter.swift`, `ShellWindow.qml`,
`GridInputClipProbe`. Sizing exception: one proof-closure family over 3 check files +
2 ledgers with one verification-surface set.

# Prerequisites

38a (`92b0754b`) and 38b (`f7b04f18`) landed. Consumes their interfaces only:
`DocumentSession.timeSelection` / `applyTimeSelection` / `clearTimeSelection` /
`SelectionTransition.trackTime{startTick,endTick,trackScope}`, the mounted ruler/roll
sweep, and the router precedence. No file overlap with in-flight 42 (PianoGrid/
NoteCommands/RulerMenuPresenter), 46 (ShellPresenter/ShellWindow/tst_ShellMenus), 51a
(tst_ShellGridInput) — dispatch is parallel-safe; the controller reruns the shared
baseline after they settle.

# Interface contract

- Swiftcore fixture (uses the existing `drawerAutomationAutomationFixture` harness, its
  clipboard save/restore, and direct `fixture.document` staging — `addNotes`, voice-lane
  writes, `applyTempoEdit` — mirroring the fork fixtures in Context ¶2 verbatim, document
  `ticksPerBeat` 24 where the envelope law pins 24-TPB):
  - Track-scope commits: select notes, then `page.applyTimeSelection(AutomationTimeSelection(
    range: 0..<96, scope: .tracks([0])))` → session `selectedNotes` empty, selection
    active, range/scope exact; repeat with `.tracks([0, 1, 2])` over the 3-track fixture.
  - `page.consumeSelectionCommand(.copy)` over each → `GridClipboard.read()` decodes a
    span clip with exactly the scoped tracks (single-track: one track; three-track:
    three tracks with the fixture notes/lanes).
  - `.delete` over 0–48 → in-range note+voice+tempo removed, out-of-range kept, one
    history entry, **`session.timeSelection?.isActive == true` after**; `.cut` → same
    payload as `.copy` plus the delete, one entry, one undo restores all three kinds.
  - `.paste` numerics: span-0 fixture (notes 24/36 selected+copied, `session.editCursor
    = 48`) → `session.selectedNotes` == the two inserted ids and `session.editCursor ==
    72`; staged last-wins clip (GridClipboard.write of the fork payload, cursor 24) →
    cursor 48 and `session.timeSelection == nil` after an active selection; empty-lane
    clip (cursor 120) → revision/history unchanged, cursor still 120; tiled span-96 clip
    → two `.paste` calls give cursors 96 then 192 and two entries, each undo one tile;
    cross-TPB clip written at `ticksPerBeat: 24` into a 48-TPB document at cursor 24 →
    cursor 72.
  - Availability: `.paste` unavailable after `pd_clipboard_write(nil, 0)`, available
    again after `.copy` (extends the lanes-scope law at automationclipboard.swift:33-44
    to tracks scope).
- New swiftcore anchors (message-anchored, one per fork clause):
  "a time-selection commit clears the competing note selection";
  "the committed time selection is active over its exact range";
  "the committed scope is track-scoped";
  "the stored track scope keeps the swept tracks";
  "Copy over an active time selection writes the decodable span clip";
  "a scoped three-track paste expands the destination tracks";
  "range delete leaves the time selection active";
  "a span-zero paste through the command path selects the pasted notes";
  "a span-zero paste through the command path advances the cursor to the paste end";
  "a rescaled cross-ticks-per-beat paste advances the cursor to the rescaled end";
  "a last-wins range paste advances the cursor by its span";
  "a range paste through the command path clears the active time selection";
  "an empty lane paste through the command path changes neither document nor history";
  "an empty lane paste leaves the edit cursor unchanged";
  "each tiled paste advances the cursor by one span and retracts as its own undo entry".
- Mounted slots (established patterns: sweep `tst_ShellGridMenu.qml:413-425`, real keys +
  native bytes + undo `tst_ShellClipboard.qml:177-336`, staged clips `writeClipJson`
  :184/:240, expansion slot :676):
  - `test_timeRangeSelectionKeys`: Shift+right sweep a visible range → selected note
    flags cleared; real ⌘C → `readClipJson()` decodes with `span == sweptSpan` and the
    scoped track(s); real Delete → covered notes gone (out-of-range kept), selection
    still commands (Duplicate Time enabled); real ⌘X → payload + removal, one undo
    restores; stage the last-wins clip, set cursor via `grid.setEditCursorTick`, real ⌘V
    → merged content, cursor advanced by span, time-selection commands retired; Undo
    retracts. Also stage the empty-lane clip → ⌘V changes nothing (notes, revision,
    cursor, Undo state).
  - `test_scopedRangeCopyPasteKeys`: Ctrl sweep per the 38a `sweepTrackScope` law → ⌘C
    bytes carry ≥2 scoped tracks; real ⌘V pastes them (single-document span merge,
    cursor advance); second real ⌘V tiles once more; Undo retracts tile-by-tile.
  - New mounted anchors: "a swept time selection clears the roll's selected notes";
    "Copy over a swept time selection publishes the span clip bytes"; "Cut over a swept
    time selection removes the covered span in one undo entry"; "Delete over a swept
    time selection removes only the covered content"; "a swept time selection survives
    its range delete"; "a range Paste key merges the staged clip and clears the time
    selection"; "tiled Paste keys advance the cursor by one span per tile"; "an empty
    lane Paste key is a surface no-op"; "Copy and Paste keys drive the window clipboard
    authority"; "a multi-track sweep copies every scoped track".
- Preservation: every existing anchor message in both check files stays verbatim;
  `ClipboardEditingChecks.swift` (S001–S013) and `tst_ShellGridMenu.qml` are untouched;
  no production API changes (the conditional repair keeps all signatures).

# Implementation steps

1. Swiftcore: add the fixture function with the predicates above (RED against any
   genuine divergence — record it; a divergence is a repair item in
   `AutomationSelectionCommands.swift`, never a test tweak). Register it.
2. Mounted: add the two slots; reuse `openRoute101`, the sweep and keySequence patterns;
   compute expected ticks from `grid.beatWidth`/`ticksPerBeat` as the file already does.
3. Run the lanes below; regressions green; if the conditional repair fired, rerun
   `--filter swiftcore` plus `shell-grid-menu` (router/sweep regression).

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — new command-path/state predicates +
  all existing suites (S001–S013 unchanged).
- `deno task verify:shell --filter shell-clipboard --verbose` — both new slots + the
  three existing slots green, anchors verbatim.
- Runtime prerequisite: macOS host (native pasteboard + real window keys); no offscreen
  substitute for the shell lane.
- If `AutomationSelectionCommands.swift` was repaired: `deno task verify:shell --filter
  shell-grid-menu --verbose` and `deno task verify --filter swiftcore --verbose` rerun.

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no pixel
  constants; fixture ticks come from the fork laws, not invented values.
- No production rewrite: `ClipboardSemantics`, `GridClipboard`, `EditCommands`,
  `NoteCommands`, the router and the menus are consumed read-only. One bounded repair
  site only (`AutomationSelectionCommands.swift`), reported before it is made.
- One message-anchored predicate per fork clause; existing ledger-cited anchor messages
  keep their text verbatim.
- Implementers never edit ledgers. Ledger mapping (agent; re-verify each row against the
  landed predicates at freeze; refresh both headers' lane results):
  - clipcheck_copy: A036 → "a time-selection commit clears…" + mounted sweep anchor;
    A037–A040 → "the committed time selection is active over its exact range" /
    "the committed scope is track-scoped"; A041 → "the stored track scope keeps the
    swept tracks" (single-track fixture); A051/A053–A055 → the same two range/scope
    anchors on the three-track fixture; A052 → "the stored track scope keeps the swept
    tracks" (three-track); A042/A056 → "Copy over a swept time selection publishes the
    span clip bytes" (+ swiftcore decode anchor); A063 → "a scoped three-track paste
    expands the destination tracks" (swiftcore, exact fork fixture); A081/A090 → mounted
    Delete/Cut anchors; A086 → "range delete leaves the time selection active" (+ mounted
    survives anchor); A013/A024/A032 → "a span-zero paste … selects the pasted notes";
    A014/A025/A033 → "…advances the cursor to the paste end"; A029 → existing mounted
    "Copy publishes native clip bytes" anchor; A003/A010/A017/A022/A028/A031 → "Copy and
    Paste keys drive the window clipboard authority" (the single window authority is the
    production key ingress; the fork's roll-widget `sendRollKey` target is retired
    representation); A030 → `RETIRED-REPRESENTATION` ("dual roll-view/song-view key
    delivery retired with the widgets; R22 landed one window shortcut authority") — if
    the freeze rejects that disposition, the row stays GAP untouched.
  - clipcheck_merge: A003/A008 → "Copy and Paste keys drive the window clipboard
    authority"; A011 → "a rescaled cross-ticks-per-beat paste advances the cursor…";
    A015 → "a range Paste key merges the staged clip and clears the time selection"
    (+ "a last-wins range paste advances the cursor by its span"); A019 → "a range paste
    through the command path clears the active time selection" (+ mounted); A020 → the
    cursor-by-span anchor; A027 → "an empty lane Paste key is a surface no-op" (+
    swiftcore no-change anchor); A031 → "an empty lane paste leaves the edit cursor
    unchanged"; A034/A037 → mounted tiled Paste-key anchors; A036/A039 → "each tiled
    paste advances the cursor by one span…".
- Blocked/untouched rows this task leaves alone: copy A030 per above; every already
  MATCHED/RETIRED row; the adjacent ledgers `proof.selectioncheck_tracks.txt` (38a),
  `proof.selectioncheck_core.txt` (mask-identity clauses — SelectionChecks surface),
  `proof.clipmime_test.txt` (live QClipboard MIME host observations + `decodeFailed`
  out-parameter — no production flag exists), `proof.laneselection_test.txt` (drawer
  lane-selection ingress/hitTest — ED07/AU families). Focused-text Copy ownership
  (fork `EditFocusedTextOwnership::Copy`, `EditCommands.swift:94-96,175` policy only)
  belongs to the window-tier keyboard slice (task 50), not here.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`, `deno task proof check --strict-mappings` —
   both clipcheck ledgers show executing anchors and no unmapped MATCHED sites.
2. Visual smoke (desktop): sweep a range on the ruler, ⌘C, click elsewhere, ⌘V — the
   range merges at the cursor, the selection band clears, the cursor advances one span,
   one Undo retracts; ⌘X over a swept range removes the span and Undo restores notes,
   automation and tempo; Delete keeps the band so Duplicate Time stays enabled.
