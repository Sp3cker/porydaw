# Spec — Swift backend Wave 2: input jurisdiction

Agreed behavior, vocabulary, and frozen interfaces for the
input-jurisdiction wave. The production sources named in §9 are
normative; where this spec and the source disagree, the source wins and
this spec is a defect. Everything here is decided — implementers make no
design choices.

## 1. Purpose and recorded decisions

Give the Swift piano-grid backend the input-jurisdiction properties
required at cutover, while Wave 1 math stays frozen and the numeric epic
ladder (TimeCamera / Grid / PitchBendKernel) stays locked out.

| # | Question | Decision |
| --- | --- | --- |
| D1 | Division of input authority | **Swift owns gesture math and policy data; arbitration stays in the C++/QML host.** The host observes Qt (focus chain, pointer grab, popup stack, window activation) and delivers already-arbitrated plain values into Swift; Swift computes meaning (gesture math, policy decisions, cancel semantics) and returns decisions/mutations the host executes. QML never re-implements a Swift decision; Swift never observes Qt directly. No second dispatcher, no synthetic forwarding, no focus memory (AGENTS.md). |
| D2 | Undo representation in the prototype | **Swift-owned undo stack of value commands inside PianoGrid** (`GridUndoStack`, spec §3.1), mirroring SongDocument's contract: one undoable command per gesture commit, monotonic `revision`, exact state restore, no-op commits push nothing. Rejected: wrapping a C++ `QUndoStack` (the prototype owns no C++ document; a host bridge buys nothing verifiable); emitting mutations for the host to record (leaves the prototype unverifiable standalone). The stack is deleted at cutover — what cuts over is the contract, not the object. |
| D3 | How the four cancel reasons enter Swift | **QML forwards a reason code.** Swift `GridCancelReason: Int` mirrors `TimelineInputCancelReason` declaration order (§3.2). The prototype wires the four production entry paths (§5.2). Rejected: a host C++ `TimelineInputItem` in the prototype — the prototype host is QML, and duplicating the item buys nothing the codes cannot carry. |
| D4 | Where the policy table lives | **Swift: `EditCommands.swift`** in the prototype directory (complete `EditCommandPolicy` mirror, 35 rows, spec §3.3). **C++: extracted data-only TU `src/ui/songview/editcommandtable.cpp`** — `kCommandTable`, the `transposeRow`/`nudgeRow`/`unboundRow`/`eventRow` helpers, and the table `static_assert`s move verbatim out of `editactions.cpp`; `editactions.h` (declarations) is unchanged; `EditActions` stays in `editactions.cpp`. The extraction is behavior-preserving and is this wave's only production edit; it is also the cutover direction (the data Swift will own, isolated from the widget class). |
| D5 | How selectionkey dimensions are exercised | **Ported as a frozen scenario matrix in the prototype's own smoke selftest** (`PolicySelftest.swift`, spec §6.3), driving a Swift routing resolver over the Task-3 table. Rejected: porting scenarios into `src/checks/selectionkey/` (those suites exercise production SongView surfaces, which this wave does not cut over) or a new standalone deno check driver (the prototype smoke already builds and launches everything needed). |
| D6 | Verification authority | The `sgp_*` seam gates the policy **table** only. Undo, cancel, and Escape acceptance is the prototype smoke's event-driven rows (§6). The dual-run oracle pattern is explicitly NOT the gate for undo/cancel — no callable C++ function arbitrates focus/grab/popup state. |

Rejected shapes (stay rejected): Swift observing Qt directly or holding
focus memory; a second dispatcher in QML beside the Swift arbiter;
wrapping `QUndoStack` from Swift; moving the keyboard policy into per-surface
QML handlers; any TimeCamera/Grid/PitchBendKernel task.

## 2. Vocabulary

- **Host** — the C++/QML side of the prototype (Main.qml and the smoke
  harness). Owns event observation and delivery ordering.
- **Gesture** — a live `GridGesture` (left: pendingDraw/draw/move/resize;
  right: pendingMenu/band). `isRight` distinguishes the families.
- **Commit** — a mutation pushed as exactly one undoable command
  (`endPointer` draw/move/resize, `doublePointer` add/remove,
  `deleteSelection`, `commitPitchCurves`).
- **Cancel reason** — why an interaction ended without committing:
  `focusLost(0)`, `pointerUngrabbed(1)`, `hidden(2)`,
  `windowDeactivated(3)`; raw values mirror `TimelineInputCancelReason`.
- **Policy row** — one `EditCommandPolicy` value for one of the 35
  `SongView::EditCommand` values; the complete struct is mirrored, field
  for field.
- **Resolver** — the Swift port of `SongView::handleEditKey`'s policy
  branches: `EditKeyArbiter.decide(command:surface:)` returning
  `decline / consume / execute`.
- **Arbiter (Escape)** — `PianoGrid.escapePressed(noteMenuOpen:)`, the
  single Swift decision point for Escape across the prototype.

## 3. Frozen Swift interfaces

### 3.1 Undo (Task 1)

New file `GridUndo.swift`:

```swift
@MainActor
struct GridNoteSnapshot {
    let noteId: Int; let tick: Int; let duration: Int
    let pitch: Int; let track: Int; let velocity: Int; let ghost: Bool
}

@MainActor
enum GridEditCommand {
    // Snapshot-pair form: exact restore by construction. The cutover-
    // relevant contract is granularity (one command per gesture commit),
    // not the payload shape.
    case notes(before: [GridNoteSnapshot], after: [GridNoteSnapshot])
    case controllerEvents(before: [GridControllerEvent], after: [GridControllerEvent])
}

@MainActor
struct GridUndoStack {
    private(set) var undoCount: Int = 0
    private(set) var redoCount: Int = 0
    mutating func push(_ command: GridEditCommand)  // no-op if before == after
    mutating func undo() -> GridEditCommand?        // nil when undoCount == 0
    mutating func redo() -> GridEditCommand?        // nil when redoCount == 0
    mutating func removeAll()
}
```

`PianoGrid` gains (QtBridge-visible, smoke reads them via
`model->property(...)`):

```swift
public private(set) var canUndo: Bool = false
public private(set) var canRedo: Bool = false
public private(set) var revision: Int = 0   // +1 per pushed command, mirrors SongDocument::revision()
public func undo()   // notes/controllerEvents := command.before; canUndo/canRedo refresh; noteSummaryDirty; refreshNotes/publishOutputs/synchronizeAudio as the mutation paths do
public func redo()
```

Contract notes (normative):

- One command per gesture commit, exactly at the mutation points listed
  in §5.1. A commit that changes nothing (redundant write) pushes nothing
  and leaves `revision` unchanged — mirrors production redundant-write
  no-ops.
- `undo()`/`redo()` restore note/controller state exactly; selection is
  not restored (production selection is not undoable). Stale selection
  ids are inert: `isSelected` simply stops matching.
- `editCursorTick` changes (pendingDraw release) are view state: never a
  command.
- `resetDemo()` clears the stack and keeps `revision` monotonic or resets
  it — frozen: **reset resets `revision` to 0 and clears history**
  (document-reload semantics, matching a fresh SongDocument).
- Audio resync follows every applied command (`synchronizeAudio`), so the
  smoke's audio invariants cannot drift through undo.

### 3.2 Cancel reasons (Task 2)

```swift
public enum GridCancelReason: Int {
    case focusLost = 0          // TimelineInputCancelReason::FocusLost
    case pointerUngrabbed = 1   // …::PointerUngrabbed
    case hidden = 2             // …::Hidden
    case windowDeactivated = 3  // …::WindowDeactivated
}
```

`PianoGrid` API replaces the no-arg cancels (clean cutover, no shims):

```swift
public func cancelPointer(reason: Int)        // GridCancelReason(rawValue:)
public func cancelRightPointer(reason: Int)
```

Teardown semantics matrix (normative; production sources §9):

| Reason | Left gesture (pendingDraw/draw/move/resize) | Right gesture (pendingMenu/band) | Hover/preview | Pitch editor live preview |
| --- | --- | --- | --- | --- |
| `focusLost` | **survives** — no state change; `updatePointer`/`endPointer` keep working | **survives** | untouched | untouched |
| `pointerUngrabbed` | teardown; preview discarded; notes unmutated | teardown; `selectionAtRightPress` restored | cursor state untouched | untouched |
| `hidden` | same teardown as `pointerUngrabbed` | same | `hoverKey` cleared, `cursorKind` = 0 | discarded (`cancelPitchCurves()` resync) when an editor is open |
| `windowDeactivated` | identical teardown to `hidden` for the grid surface | identical | identical | identical |

`hidden` and `windowDeactivated` differ only in **entry**: `hidden` is
per-surface visibility; `windowDeactivated` is window-level, delivered
once, and must not tear down popup-owned surfaces (the pitch popup and
note menu keep their own input; their teardown is theirs, not the grid's
— exactly the production foreign-grab/popup-session protection).

Entry wiring (production path in brackets):

- `onCanceled` of the grid `MouseArea` → `cancelPointer(1)` /
  `cancelRightPointer(1)` [TimelineInputItem::mouseUngrabEvent]
- grid input surface `onActiveFocusChanged` → lost focus while visible →
  `cancelPointer(0)` [focusOutEvent]
- `onVisibleChanged` → false → `cancelPointer(2)` on the grid surface
  **and** on the window [ItemVisibleHasChanged]. Window `hide()` plus
  `onVisibleChanged` is a legitimate Hidden proof; do not treat it as
  WindowDeactivated.
- Native window `eventFilter`: `QEvent::Hide` and
  `QEvent::WindowDeactivate` → `cancelPointer(3)` once
  [TimelineQuickView::eventFilter Hide/WindowDeactivate →
  `cancelActiveGestures`; popup surfaces excluded by host arbitration].
  Installed by the prototype host (`App.swift` and/or a small native
  helper it owns). **Not** QML `onActiveChanged`: `isActive` is app
  bookkeeping and is not synthesizable via `sendEvent`.

### 3.3 Policy table (Task 3)

New file `EditCommands.swift` — the complete `EditCommandPolicy` mirror:

```swift
public enum EditCommand: Int, CaseIterable { case copy = 0 /* …35 values in SongView::EditCommand order… */ case gridTriplet = 34 }
public enum EditRangeOperation: Int { case none, copySelection, cut, duplicate, delete, transpose, nudge, insertTime, removeContents, clearTimeSelection, loopFromSelection }
public enum EditNotesOperation: Int { case none, copySelection, cut, delete, transpose, nudge, selectAll, pitchBend, setVelocity, duplicate, split, join, lengthen, shorten }
public enum EditStandaloneOperation: Int { case none, paste, muteTracks, soloTracks, insertTime, pencilToggle, moveEventRow, setLoopStart, setLoopEnd, removeLoop, editTimeSignature, removeTimeSignature, gridNarrow, gridWiden, gridTriplet }
public enum EditDeliveryClass: Int { case editorRouted = 1, window = 2 }
public enum EditKeyRoute: Int { case selectionTargeted, alwaysConsume, availabilityGated }
public enum EditAutoRepeatRule: Int { case reexecute, consumeWhenEligible }
public enum EditKeyOwnershipOnUnavailable: Int { case resolvedByRow, ownsKey }
public enum EditOriginRule: Int { case anyOrigin, eventListOnly, timelineOnly }
public enum EditFocusedTextOwnership: Int { case none, copy, solo }

public struct EditCommandPolicy { /* all 14 fields, C++ names, Int raw values */ }
public let editCommandTable: [EditCommandPolicy]  // 35 rows, enum order, frozen values
public func editCommandPolicy(_ command: EditCommand) -> EditCommandPolicy
```

Raw values: C++ enums with explicit values keep them
(`EditDeliveryClass.editorRouted = 1`, `.window = 2`); default-numbered
C++ enums get 0,1,2,… in declaration order. The rows are frozen against
`editactions.cpp` — a mismatch is a defect report (port bug or stale
production claim), never a silent edit.

### 3.4 Key resolver (Task 4)

New file `EditKeyArbiter.swift`:

```swift
public enum EditKeyOrigin: Int { case timeline, eventList }
public enum EditKeyDecision: Int { case decline = 0, consume = 1, execute = 2 }

public struct EditSurfaceState {
    public var pointerGestureActive: Bool   // live grid gesture
    public var timeSelectionActive: Bool
    public var noteSelectionEmpty: Bool
    public var origin: EditKeyOrigin
    public var autoRepeat: Bool
    public var commandAvailable: Bool       // host answers eligibility (editCommandAvailable analog); Swift routing treats it as input
}

public enum EditKeyArbiter {
    public static func decide(command: EditCommand?, surface: EditSurfaceState) -> EditKeyDecision
    public static func windowActionEnabled(command: EditCommand, textFocused: Bool, rowAvailable: Bool) -> Bool  // liveRowEnabled analog: Copy defers to focused text
}
```

Decision rules — `handleEditKey` statement order, verbatim (normative):

1. `command == nil` → `decline` (unbound keys are host-owned; Swift never
   sees a binding).
2. `pointerGestureActive && !policy.survivesPointerGesture` → `consume`.
3. `policy.originRule == .eventListOnly && surface.origin != .eventList`
   → `decline`; `policy.originRule == .timelineOnly &&
   surface.origin != .timeline` → `decline`.
4. Switch `policy.keyRoute`:
   - `.alwaysConsume` → `execute` (the executor no-ops when ineligible).
   - `.availabilityGated` → `!commandAvailable` → `decline`;
     `autoRepeat && autoRepeatRule == .consumeWhenEligible` → `consume`;
     else `execute`.
   - `.selectionTargeted` → resolve target (timeSelection active and
     rangeOperation ≠ none → time range; else notesOperation ≠ none and
     origin == timeline → notes; else none). Target none →
     `terminalWhenUnmatched ? consume : decline`. Target set but
     `!commandAvailable` → `ownsKey ? consume : (terminalWhenUnmatched ?
     consume : decline)`. Notes target and `autoRepeat` and
     `consumeWhenEligible` → `consume`. Else `execute`.

### 3.5 Escape arbiter (Task 5)

`PianoGrid` gains:

```swift
public enum GridEscapeAction: Int { case none = 0, cancelGesture = 1, closePitchEditor = 2, closeNoteMenu = 3, clearSelection = 4 }

@discardableResult
public func escapePressed(noteMenuOpen: Bool) -> GridEscapeAction
```

Precedence (normative; `handleEditKey` Escape branch + popup ownership):

1. Live gesture (either family) → teardown identical to
   `cancelPointer(pointerUngrabbed)` (production Escape routes through
   `cancelInteraction()` → the strong pointer teardown), right-gesture
   selection restore included → `.cancelGesture`.
2. Else pitch editor open (`pitchEditor != nil`) → cancel live graph
   gestures, `cancelPitchCurves()` (discard preview, resync), close the
   editor → `.closePitchEditor` (QML closes the popup host).
3. Else `noteMenuOpen` → `.closeNoteMenu` (model keeps no menu state;
   QML executes the close).
4. Else clear the note selection, republish → `.clearSelection`.

Escape is always consumed (production returns true unconditionally).
QML surfaces forward instead of deciding: `NoteMenu.qml`,
`PitchBendPopup.qml`, `PitchBendGraph.qml` (its `Keys.onShortcutOverride`
keeps claiming Escape so the focused graph sees it, but `Keys.onPressed`
forwards) and the grid input surface's window-tier fallback in
`Main.qml` — one call shape everywhere:
`gridModel.escapePressed(noteMenu.opened)` then a switch on the returned
action for visual teardown (`pitchHost.close()`, `noteMenu.close()`).

## 4. Frozen seam ABI — `src/checks/swiftgridprototype/policy_smoke.h`

Plain C, `extern "C"`, imported by Swift through the `NativeGridSmoke`
module (module map gains `header "policy_smoke.h"`). Swift drives, C++
answers — no `@_cdecl`, no C++→Swift calls. Prefix `sgp_` (`sgm_` is the
Wave-1 math seam, `sgc_` the curve seam; both stay frozen).

```c
#include <stdint.h>

typedef struct SGECommandPolicyRow {   // one EditCommandPolicy, flat ints
    int32_t command;                   // SongView::EditCommand ordinal
    int32_t rangeOperation, notesOperation, standaloneOperation;
    int32_t keyRoute, originRule, autoRepeatRule;
    int32_t ownershipOnUnavailable, focusedTextOwnership;
    int32_t transposeSemitones, nudgeDelta, eventRowDelta;
    int32_t survivesPointerGesture;    // 0/1
    int32_t terminalWhenUnmatched;     // 0/1
} SGECommandPolicyRow;

int32_t sgp_command_count(void);                    // 35
void sgp_policy_row(int32_t commandOrdinal, SGECommandPolicyRow *out);
```

`policy_smoke.cpp` implements over the extracted production table
(`editcommandtable.cpp` compiled into the smoke's link; thin conversion
only, no logic). `PolicySelftest.swift`
(`runPolicySelftestIfRequested()`, no-op unless
`PORYDAW_SWIFT_GRID_SMOKE == "1"`, called from `App.init()` after
`runMathSelftestIfRequested()`) asserts the parity sweep and the §6.3
dimension matrix; output convention matches Wave 1:
`SWIFT_GRID_SMOKE policy-<group> PASS` / `… FAIL: <case>` + nonzero
exit; the final `SWIFT_GRID_SMOKE PASS` still comes from `grid_smoke.cpp`
`exercise()`.

## 5. Contract notes (normative)

### 5.1 Undo inventory (Task 1)

| Mutation site | Command | Production analog |
| --- | --- | --- |
| `endPointer` `.draw` | notes before/after (insert one) | `addNote` |
| `endPointer` `.move` (dTick/dKey ≠ 0) | notes before/after (selected set) | `moveNotes(mergeable: false)` — one command per drag |
| `endPointer` `.resize` (delta ≠ 0, leading and trailing) | notes before/after | `resizeNotesLeft` / `resizeNotes` |
| `doublePointer` add | notes before/after | `addNote` |
| `doublePointer` remove | notes before/after | `deleteNotes` (one) |
| `deleteSelection()` (only when it removed notes) | notes before/after | `deleteNotes` (batch, one command) |
| `commitPitchCurves()` (only when events changed) | controllerEvents before/after | `writeLanePoints` gesture write |
| `endPointer` `.pendingDraw` (editCursorTick) | — view state, never a command | edit cursor is not undoable |
| selection changes; `beginPointer`'s selection set | — not undoable | selection model is outside undo |
| `resetDemo()` | clears history, `revision = 0` | fresh document |

### 5.2 Cancel-reason entry parity (Task 2)

Production entries (normative sources §9): per-item focus-out →
FocusLost; per-item mouse ungrab → PointerUngrabbed; per-item hidden →
Hidden (+ focus drop, hover teardown at the item); window Hide/Deactivate
→ one `cancelActiveGestures()` pass, each interaction exactly once,
foreign-window grabs and popup-session grabs released by nobody but their
owner. The prototype mirrors these four entries (§3.2): three QML
surfaces plus a native window eventFilter. The smoke drives each with a
real Qt event (focus steal, `ungrabMouse()`, `visible=false` / window
`hide()`, synthesized `QEvent::WindowDeactivate`) — never by calling
Swift cancel methods directly, except where noted in §6.2. Do not assert
`!QWindow::isActive()` after `sendEvent`; that property does not flip.

### 5.3 Production extraction bounds (Task 3)

Moved verbatim from `editactions.cpp` to `editcommandtable.cpp`:
`CommandRow`, `transposeRow`, `nudgeRow`, `unboundRow`, `eventRow`,
`actionIndex`, `kCommandTable`, `commandTableFollowsEnumOrder`, both
`static_assert`s, and the `editCommandPolicy` definition. Stays in
`editactions.cpp`: `EditActions` (all of it), `liveRowEnabled`,
window-shortcut install, key recognizer, execute. `editactions.h` is not
edited. Root `CMakeLists.txt` gains one source line beside
`editactions.cpp`. No signature, value, or ordering change anywhere.

## 6. Frozen scenario tables

### 6.1 Undo rows (Task 1, `jurisdiction_smoke.cpp` → `verifyGridUndo`)

Fixture baseline: `resetDemo` → 30 notes; `noteSummary` string equality
is the exact-restore oracle (production analog: `smf().write()` equality).

| Row | Scenario | Assertions |
| --- | --- | --- |
| `undo-draw-commit-restores-fixture` | mouse-draw a note, release | `revision` +1, `canUndo`; `undo()` → noteSummary equals fixture, `canRedo` && !`canUndo`; `redo()` → note back, selection content inert |
| `undo-move-commit` | drag one snapped cell right | undo → exact fixture summary; redo → moved summary |
| `undo-resize-leading-and-trailing` | both edge drags | each is one command; undo/redo exact per drag |
| `undo-menu-delete-selection` | note-menu keyboard Delete (2 selected) | one command; undo restores both notes; `revision` +1 total |
| `undo-doubleclick-add-and-remove` | double-click empty cell; double-click a note | one command each; undo of each exact |
| `undo-pitch-curve-commit` | G → drag curve → commit (popup close) → reopen shows curve; `undo()` → reopen shows the pre-commit curve | controllerEvents command |
| `undo-no-command-for-cursor-and-selection` | pendingDraw click (cursor set); click-select a note | `canUndo` false, `revision` unchanged |
| `undo-reset-clears-history` | after a commit, `resetDemo` | `canUndo` false, `revision` 0 |

### 6.2 Cancel rows (Task 2, `jurisdiction_smoke.cpp` → `verifyGridCancel`)

| Row | Scenario | Assertions |
| --- | --- | --- |
| `cancel-ungrab-discards-move-preview` | mid-move-drag, `ungrabMouse()` on the grabber | notes unmoved, gesture gone (statusText idle), selection unchanged, `revision` unchanged |
| `cancel-focuslost-keeps-live-gesture` | mid-move-drag, steal focus (`forceActiveFocus` on transport Stop) | gesture alive (statusText still Moving); a further move + release **commits**; undo restores — the survival is behavioral, not cosmetic |
| `cancel-hidden-tears-down-and-clears-hover` | mid-draw + keyboard hover set, hide (grid `visible = false` and/or window `hide()` + `onVisibleChanged`) | draw preview gone, `hoverKey` cleared, notes unchanged, pitch preview discarded when editor open; **ends `!isVisible`** on the object that was hidden |
| `cancel-window-deactivated-matches-hidden` | mid-draw, send `QEvent::WindowDeactivate` to the window | same teardown as hidden; delivered once; pitch popup (when open) stays open — host arbitration; **ends `isVisible`** (window still shown). Do not assert `!isActive`. |
| `cancel-right-ungrab-restores-captured-selection` | band-select over 2 notes, `ungrabMouse()` | selection back to pre-press exactly |

### 6.3 Policy parity + dimensions (Tasks 3–4, `PolicySelftest.swift`)

**`policy-table-parity`** — for every command 0…34 and all 14 fields,
Swift `editCommandTable` equals `sgp_policy_row`; a mismatch names
command, field, Swift value, C++ value.

**`policy-dimensions`** — frozen matrix, one decision per row
(`decide` unless noted):

| Dimension (selectionkey provenance) | Frozen rows |
| --- | --- |
| autoRepeat consumption (core editing; local-input pitch bend repeat) | PitchBend + autoRepeat + eligible → `consume`; PencilMode + autoRepeat + available → `consume`; TransposeUp + autoRepeat + eligible → `execute` (Reexecute) |
| unavailable-ownership (lane-scoped transpose owns the key) | TransposeUp + notes target + unavailable → `consume` (ownsKey); Cut + target none + not terminal → `decline`; Duplicate + target none + terminal → `consume` |
| gesture survival (gesture guard) | Delete + gestureActive → `consume`; PencilMode + gestureActive → `execute` (survivesPointerGesture) |
| origin routing (event-list/timeline split) | MoveEventUp from timeline → `decline`; GridNarrow from eventList → `decline`; GridNarrow from timeline + available → `execute` |
| prompt text ownership (Copy/Solo deferral) | `windowActionEnabled(copy, textFocused: true, rowAvailable: false)` → true; `(solo, textFocused: true, rowAvailable: false)` → false; `(copy, textFocused: false, …)` follows rowAvailable |
| unbound-key neutrality | `decide(command: nil, …)` → `decline` for every surface variant |

### 6.4 Escape rows (Task 5, `jurisdiction_smoke.cpp` → `verifyGridEscape`)

| Row | Scenario | Assertions |
| --- | --- | --- |
| `escape-cancels-live-gesture-preserving-selection` | mid-move-drag, Escape | notes unmoved, gesture gone, selection as captured at press, `revision` unchanged |
| `escape-closes-pitch-editor-discarding-preview` | G popup with dragged live preview, Escape from the graph's focus | popup closed (`pitchBridge` null), preview discarded (reopen shows pre-edit curve), committed earlier numeric edits survive |
| `escape-closes-note-menu` | right-click menu open, Escape | menu closed, selection preserved |
| `escape-idle-clears-selection` | selection without gesture/popups, Escape | selection empty, `revision` unchanged |
| `escape-single-arbiter-paths` | Escape delivered while pitch graph focused, while popup focused, from grid surface | one path decides every time — no surface closes independently of the arbiter's returned action |

## 7. Edge cases and error conditions

- No-op commits (draw of zero length cannot happen — min duration is one
  snap; move/resize with zero delta; redundant curve write) push nothing;
  `revision` proves it.
- `undo()`/`redo()` with empty stack are inert (return without state
  change).
- `cancelPointer` with no live gesture is a no-op for every reason
  (production `cancelActiveGestures` is per-interaction, exactly once).
- Reason codes outside 0…3 arriving from QML: `GridCancelReason(rawValue:)`
  nil → the call is a no-op (defensive; the smoke never sends one).
- Escape during a live right-gesture restores `selectionAtRightPress`
  (production: "cancels only that gesture and preserves its captured
  selection").
- The extraction must keep `static_assert`s compiling in the new TU — a
  table edit without the enum edit must still fail the production build.

## 8. Deferred (forward contracts, not this wave)

- Popup-session lifecycle parity (production `QuickPopupSession`:
  WindowDeactivate/Hide/Close cancel, ShortcutOverride swallowing) — the
  prototype's popups keep their simple close paths; only the grid's
  window-deactivate entry is wired here.
- Availability predicates (`editCommandAvailable`'s SongView state
  machine) — Swift routing takes availability as host input; porting the
  predicates belongs to the surface cutover wave.
- `keymap::Registry` binding lookup (key+modifiers → command) — host
  delivery, stays in C++ until the keyboard cutover.
- TimeCamera / Grid / PitchBendKernel (sequence lock).
- Undo UI (menu items, chords) — the smoke drives `undo()`/`redo()`
  directly.

## 9. Normative sources

| File | Role |
| --- | --- |
| `src/ui/songview/quick/timelineinput.h` | cancel-reason enum order; `cancelInteraction` default route |
| `src/ui/songview/quick/timelineinputitem.cpp` | FocusLost / PointerUngrabbed / Hidden entry paths + item teardown |
| `src/ui/songview/quick/timelinequickview_window.cpp`, `timelinequickview_keyrouting.cpp` | window-level entry; `cancelActiveGestures` once-per-interaction; grab protection |
| `src/ui/songview/pianoroll_interaction.cpp`, `pianoroll.cpp` | roll cancel semantics; strong pointer teardown; Hidden/WindowDeactivated extras |
| `src/ui/songview/timeruler_interaction.cpp`, `src/ui/editordrawer/voicechangearea/voicechangearea.cpp` | FocusLost keeps pointer delivery; menu-session protection on FocusLost/PointerUngrabbed |
| `src/ui/editordrawer/drawerchrome.cpp`, `src/ui/editordrawer/automationcanvas_input.cpp` | uniform-reset and FocusLost-ignore reason tables |
| `src/ui/songview/editactions.h`, `editactions.cpp` | policy struct, table, row helpers, asserts |
| `src/ui/songview/editkeyrouting.cpp` | `handleEditKey` branch order (resolver + Escape), `resolveSelectionTarget`, `editCommandAvailable` |
| `src/core/songdocument.h` | undo granularity contract, `revision`, mergeable keyboard vs one-per-drag mouse |
| `src/ui/songview.h` | `SongView::EditCommand` 35-value order |
| `src/checks/selectionkey/*` | dimension provenance (core editing, gesture guard, window tiers, local input) |
| `src/checks/swiftgridprototype/interaction_smoke.cpp`, `grid_smoke.{h,cpp}` | QTest row style, PASS convention, `exercise()` call order |
| `src/checks/checkcatalog.cpp` | coverage comments for the production gates |
