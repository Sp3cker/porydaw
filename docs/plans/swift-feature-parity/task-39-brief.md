# Context

ED09 slice 2 — the Event List **edit-matrix remainder** (task-19's four
deferred families, 74 rows) plus the **row-menu authority repair** (next-
sprint §3/§5). One verification surface (shell-event-list + swiftcore
eventviews), one dispatch. Fork-main = `fceecd88`.

1. **Ledger** `src/checks/eventviews/proof.edits.txt` (edits.cpp @ 89da4c7d;
   native lane deleted in 67544720): 74 open rows —
   - rawTempoAtomic 26: A067–A070, A072–A073, A077–A080 (A079 PARTIAL),
     A084–A085, A089–A092, A096–A099 (A098 PARTIAL), A103–A104, A108–A111
     (A110 PARTIAL).
   - sameTickReorder 22: A120–A122, A125, A128–A129, A132–A134, A137, A138,
     A140, A144–A145, A147–A148, A151, A153–A155, A163, A165.
   - deleteMatrix 13: A173–A176, A178–A179, A180–A181 (PARTIAL), A182–A184,
     A185 (PARTIAL), A186.
   - drawerClickAfterEditOwnsDelete 13: A187–A189, A191–A194, A195 (PARTIAL),
     A196–A200.
   A177/A190 are already RETIRED-REPRESENTATION. **No ledger row exists** for
   the Show-voice row or the `Delete %n event(s)` label (nearest families
   proof.chrome.txt A081–A112 and proof.trackheadermenu.txt A061–A067 stay
   untouched). `EventViewsEditsParity.swift:107/250` already proves the
   *document-level* transactions; every PARTIAL's unproved clause is the
   presenter/mounted path.
2. **Fork row menu** (`git show fceecd88:src/ui/songview/quick/
   eventlistcontroller.cpp`): ids 1–5 (:45-49); `rebuildRowMenu` (:1057-1089)
   = "Insert event" always; "Show voice in voicegroup" iff the row maps to a
   raw event of typeKind Program (:1061-1066); separator + Move rows iff the
   row maps to a raw event, **action-backed** from `SongView::editActions()`
   so text/shortcut/enabled come from the canonical QAction (:1068-1080; no
   activation case — the host triggers the action, :123-126); trailing
   separator always; Delete last, `deletable` = count of *selected* rows
   mapping to a raw event or tempo point, text `tr("Delete %n event(s)",
   nullptr, deletable)` / "Delete" disabled at 0 (:1083-1092). Activation
   (:105-128): ShowVoice → `emit revealVoice(events[*index].data0)`
   (:113-121). Canonical actions: editactions.cpp:113-128 `eventRow`
   (MoveEventRow, AlwaysConsume, originRule **EventListOnly**, delta ±1),
   :309-310; "Move Event Up/Down (Same Tick)" Alt+Up/Alt+Down
   (keymap.cpp:180-185).
3. **Fork reveal chain**: revealVoice → revealVoiceRequested(program),
   guarded 0..<128 (trackvoiceops.cpp:233-237) → workspaceui.cpp:230-233
   `showVoicegroupPanel(); m_voicegroupBrowser->revealSlot(program)`
   (= selectSlot + scroll, voicegroupbrowser.cpp:726-731). Swift mounts the
   Songs+Voicegroup panes permanently (SongsDockColumn.qml:74-89), so the
   raise is vacuous; the live part exists as
   `VoiceListController.revealSlot(slot:)` (VoiceListController.swift:386-391)
   + VoicegroupPanel.qml:212-215.
4. **Fork move/delete laws** (same controller): `moveDestForRow` (:811-840) —
   destination = the **adjacent table row's** raw event, refused on tick
   mismatch or bounds escape; `canMoveCurrentRow` (:847-850) = visible, not
   editing, current row, legal destination; `moveCurrentRow` (:853-863) →
   `reorderRawEvent` (:709-729: clamp, no-op, select+scroll the moved row).
   `deleteSelected` (:676-705): raw rows → indices, tempo rows → tempo
   removals, EOT ignored; **>1 deletable clears anchor/current/selection
   before the mutation, exactly 1 does not** (:693-697); mixed →
   removeRawEventsAndEditTempo, raw-only → deleteRawEvents, tempo-only →
   applyTempoEdit (:698-705). Delete/Backspace local (:1222-1224), declined
   while editing/menu-open (:1204-1207); EventListOnly origin keeps
   drawer-focus keys away (editkeyrouting.cpp:442-443,
   timelinequickview_keyrouting.cpp:21-35).
5. **Fork tempo atomicity** (`src/ui/eventtablemodeledit.cpp`, setData
   :289-326): tempo tick edit = one `TempoEdit{remove, add(same µs)}` +
   select at the new tick (:47-70); BPM edit validates whole 20…255, writes
   µs = lround(60000000/bpm) atomically (:18-21, :99-109); tempo type change
   → replaceTempoPointWithRawEvent (:72-97); raw type→tempo, chunk 0 only,
   default µs 500000 (:124-146). Native contracts (edits.cpp):
   rawTempoAtomic :304-410 (meta↔tempo round trip = one undo step each way,
   tick-0 metas preserved), sameTickReorder :441-603 (drag swap +
   currentRow follow; refused drop = no undo + `!isEditing`; cross-tick and
   pinned no-ops; the menu Move row triggers the canonical action exactly
   once; Alt+Down reaches the same command; boundary key no-op),
   deleteMatrix :605-651 (multi clears the cursor, single keeps a valid
   current row), drawerClickAfterEditOwnsDelete :653-690 (focus-loss commit
   lands without focus reclaim; Delete at drawer focus changes nothing).
6. **Current Swift** (`2503f41e`): row menu = four rows, no separators, no
   shortcut texts, static "Delete" enabled on any selection
   (EventListMenus.swift:92-107); Move rows call
   `session.document.moveRawEvent` directly, bypassing canonical
   `performEventListCommand` (EventListMenus.swift:150-153 vs
   ApplicationSession.swift:531-540, ShellPresenter.swift:277-281 — the
   misbinding); `moveEvent(delta:)` steps raw indices with bounds only
   (EventListSelection.swift:149-160); `dispatchDeleteSelected` always
   clears the cursor, even single (EventListEditing.swift:165-178); drag +
   right-click QML is fork-identical (EventListPage.qml:559-643); the editor
   commits on focus loss via `onEditingFinished → finishEditor(false)` and
   cancels via `onActiveFocusChanged` (EventListPage.qml:422-428, :531-535)
   — ordering unproved mounted (A195). Document layer already fork-equal
   (EventEditing.swift:237-295, pinning `eventPinnedBefore`); BPM 20…255
   validated (EventListModel.swift:246-250); µs conversion lround-equal
   (MusicTypes.swift:155-158). No check drives the row menu today
   (tst_ShellMenus.qml:467-529 covers only the shell Edit action + Alt+Down
   key route).
7. **Reveal seam**: `EventListPresenter.session` is a `DocumentSession`
   (EventListPresenter.swift:87) with no voice-list access; the established
   cross-surface pattern is the `@QtIgnored` callback (TrackHeaders.swift:64
   `onRevealTrackVoiceRequested`), and ApplicationSession already pairs
   presenters with voiceList callbacks (ApplicationSession.swift:126,
   :151-176).
8. **Fixture**: shell lane keeps `mus_route101` (ShellQmlTests.swift:92-94).
   Track 1 tick 0 = Program(0) + CC7 + CC10 + CC1 + NoteOn (same-tick run,
   setup-before-note pinning), track 0 has tempo metas at 0/192 and marker
   metas at 96/288 (parsed from the .mid) — every mounted predicate is
   exercisable without a new fixture.

# Exact write set

- `src/swift/app/eventlist/EventListMenus.swift` — fork-shaped row menu
  (ids 1–5, separators, canonical Move rows with shortcut texts, Show-voice
  condition, dynamic delete count); canonical activation; reveal request.
- `src/swift/app/eventlist/EventListPresenter.swift` — `EventListMenuItem`
  gains `separator: Bool = false` and `shortcutText: String = ""`;
  `@QtIgnored public var onRevealVoiceRequested: ((Int) -> Void)?`.
- `src/swift/app/eventlist/EventListSelection.swift` — `moveEvent(delta:)`
  destination law + shared can-move predicate.
- `src/swift/app/eventlist/EventListEditing.swift` — delete cursor law.
- `src/swift/app/ApplicationSession.swift` — one assignment beside the
  :151-176 block: `eventList.onRevealVoiceRequested = { [voiceList] program
  in voiceList.revealSlot(slot: program) }`. Hot file — 3-line region;
  controller sequences the dispatch if 37/38 are in flight.
- `src/ui/songview/quick/EventListPage.qml` — **only if** the drawer-focus
  RED proves the cancel path wins; bounded repair in the contract.
- `src/checks/eventviews/EventListPageChecks.swift` — new internal
  functions `eventListTempoContract`, `eventListDeleteMatrix`,
  `eventListRowMenuContract` (own inline fixtures, mirroring :10-27), called
  from `runEventListPageChecks`.
- `src/checks/editorqml/tst_ShellEventList.qml` — new mounted tests: row-menu
  session + Show voice + delete count; drag delivery; drawer-focus Delete.

No new files, lanes or registrations. Sizing exception: 8 files, one
verification surface, one dispatch.

# Prerequisites

None blocking. Task 19 landed. Parallel with 37/38; only shared file is
ApplicationSession.swift's construction region (above).

# Interface contract

- Row menu (rebuilt at every `dispatchOpenRowMenu`, ids fork-identical):
  1. "Insert event", id 1, enabled.
  2. "Show voice in voicegroup", id 2, present iff the menu row maps to a
     raw event of kind `.program`; enabled.
  3. separator, then "Move Event Up (Same Tick)" id 3 and "Move Event Down
     (Same Tick)" id 4 — present iff the menu row maps to a raw event;
     `shortcutText` = `KeybindingRegistry().sequences("eventlist.move_up" |
     "move_down").first?.nativeText ?? ""`; enabled iff the shared move
     predicate holds for ∓1/±1.
  4. separator, then Delete id 5: text `Delete \(n) event(s)` when n > 0
     else "Delete", enabled iff n > 0; n = count of selected rows whose
     `EventListRow` has `eventIndex` or `tempo` (EOT never counts).
- Move predicate (one law, EventListSelection): destination = raw event of
  the adjacent table row `currentRow + delta`; legal iff it exists, shares
  the source tick, lies inside `rawMoveBounds(chunk:index:)`, differs from
  the source; `moveEvent(delta:)` performs `moveRawEvent` to it and keeps
  the existing focus/selectedRows/selectionAnchor follow. Unfiltered
  behavior unchanged (S171–S182 stay green).
- Activation: ids 3/4 call `session?.performEventListCommand(command:
  EditCommand.moveEventUp/.moveEventDown.rawValue)` — exactly one move, one
  undo step per activation; id 2 invokes `onRevealVoiceRequested?(data0)`
  guarded 0..<128 (no-op when unassigned); ids 1/5 unchanged.
- `dispatchDeleteSelected`: deletable > 1 → clear anchor/current/selection
  before the mutation (as today); exactly 1 → keep the cursor, after the
  rebuild clamp `currentRow` into `0..<rowCount` and leave the selection to
  the rebuild; 0 (EOT-only) → strict no-op. The `editRawAndTempo` document
  call is unchanged.
- Drawer focus: mounted behavior = focus leaving the cell editor commits the
  editor text without the page reclaiming focus; Delete while a drawer
  control holds focus removes no rows and pushes no undo. No production
  change unless RED proves otherwise; bounded repair = make
  `onActiveFocusChanged` (EventListPage.qml:532-535) commit
  `finishCellEdit(true, editor.text, false)` instead of cancelling.
- Preserve: type/chunk/filter menus, `commitCellEdit` semantics, `addEvent`
  and row-menu Insert routing (task-19 pins A112–A119),
  `routeEventListCommand` gates, all MATCHED rows, proof.chrome.txt /
  proof.trackheadermenu.txt / proof.localinputtier_eventlist.txt rows.

# Implementation steps

1. Failing predicates first; record RED per family. Presenter
   (EventListPageChecks; inline MidiFile fixture + `editTempo` seed,
   mirroring :73):
   - tempo contract → A067–A111: meta row type-commit "9" → tempo row
     appears at that tick, meta row gone, one undo step, tick-0 metas
     untouched, undo/redo round trip; tempo row type-commit "10" → meta row
     back, one undo step each way; tempo row BPM "140" → µs 428571, one undo
     step; "19"/"256" → false, editing stays open, document unchanged;
     tempo row tick "60" → row moves, µs preserved, one undo step.
   - delete matrix → A173–A186: two-row selection delete → both gone,
     selectedRows empty, currentRow −1; single-row delete → row gone and
     `0 <= currentRow < rowCount`; EOT-only selection → no-op.
   - row-menu contract → A144–A155: open on a program row vs a CC row vs the
     EOT row; assert exact rows, ids, texts, separators, shortcut texts,
     enablement; two rows selected → `Delete 2 event(s)`; activate Move →
     exactly one reorder, one undo step, selection follows; Show voice via
     an assigned callback capture asserts the program value.
2. Row-menu rebuild + canonical dispatch + reveal request + delete-count
   label (EventListMenus.swift, EventListPresenter.swift).
3. Move destination law, shared with menu enablement
   (EventListSelection.swift).
4. Delete cursor law (EventListEditing.swift).
5. Wire `eventList.onRevealVoiceRequested` beside the voiceList callbacks
   (ApplicationSession.swift).
6. Mounted tests (tst_ShellEventList.qml, mus_route101):
   - drag delivery → A120–A140: real press/move/release on the tick-0 CC run
     swaps neighbors, currentRow follows, one undo step; a refused drop
     (before run start / cross-tick / across the pinned note) pushes no undo
     and leaves `presenter.editing` false.
   - row-menu session → A147–A155: right-click (real RightButton release)
     opens the fork-shaped menu; click Move through the rendered
     `eventListMenuRow_*` row; Show voice on the track-1 tick-0 program row
     bumps `voiceList.revealRequest` with `revealSlotId == 0` and
     `currentSlot == 0`; two Ctrl-clicked rows → the delete label.
   - focus/key → A163/A165: Alt+Down at event-list focus performs the same
     canonical move; assert `KeybindingRegistry().sequences(
     "eventlist.move_down").first` resolves so A165 closes on evidence.
   - drawer focus → A187–A200: open the tick editor (existing F2 pattern),
     selectAll + type, click a focusable drawer control (EditorDrawer.qml
     :165-167/:241-242) → commit landed (row at the new tick, undo +1,
     `!editing`), drawer keeps active focus; then Delete removes no rows,
     pushes no undo, focus unchanged. If RED, apply the bounded
     EventListPage.qml repair and re-run.
7. Run the lanes; report GREEN with predicate messages + file:line for the
   controller's ledger handoff.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` (new predicates;
  swiftcore-eventedits stays green)
- `deno task verify:shell --filter shell-event-list --verbose`
- `deno task verify:bridge`
- `deno task format --check`
- RED evidence per family before the repairs; the canonical-dispatch
  predicate must fail on the current `moveRawEvent` bypass.

# Task-specific constraints

- No new C++; no code comments (delete stale comments in touched regions);
  no pixel constants; typography/geometry/palette untouched.
- Implementers never edit ledgers; the controller's ledger agent updates
  `proof.edits.txt` in the same commit: the 74 rows → MATCHED citing the new
  message-anchored predicates (mapping in steps 1/6); A165 may cite the
  registry predicate; currently-MATCHED rows and every proof.chrome/
  trackheadermenu/localinputtier row stay unchanged.
- Message anchors mandatory, contract-shaped ("menu Move row moves the
  current event through the canonical command once", "single delete keeps
  the cursor on a valid row").
- No QML sleeps (waitForNative pattern); tick comparisons string-based above
  2^53. Keep `mus_route101`; no new fixtures or registrations.
- Out of scope, fork evidence recorded, no ledger rows: move-refusal and BPM
  announcement status-bar strings (fork announce, eventlistcontroller.cpp
  :824-838/:103-108 — Swift has no event-list announce channel); undo label
  texts ("delete %n event(s)", "reorder event" — no user-visible label
  surface in Swift's history); row-menu Insert copy-at-tick vs
  addEvent-at-cursor divergence (task-19 pins the current behavior, A112–A119
  MATCHED) — controller decision, see open questions.

# Controller verification

1. After the writer settles (no `porydaw|_qml_tests|swift_core_check`
   processes): re-run the acceptance lanes, then `deno task proof check`,
   `deno task proof check --executed`, `deno task proof check
   --strict-mappings` before treating the four families as closed.
2. Native smoke (desktop): open a song, show the Event List — right-click a
   Program row (Insert / Show voice / separator / Move rows with ⌥ shortcuts
   / separator / Delete n event(s)) vs a CC row (no Show voice) vs the EOT
   row (no Move rows); two rows selected → "Delete 2 event(s)", Delete →
   cursor on a valid row, single delete likewise; Alt+↑/↓ and row drag
   reorder only within the tick; Show voice selects + scrolls the
   voicegroup pane to the program slot; edit a cell then click the drawer →
   value committed, drawer focused, Delete inert for rows.
