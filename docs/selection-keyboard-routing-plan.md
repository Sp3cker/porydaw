# Selection-driven keyboard routing

Scope: shared keyboard routing only. Keyboard resizing is implemented as the separate keyboard note-length feature (`docs/keyboard-note-resize-plan.md`); contextual Duplicate remains a separate deferred feature, and the existing time-range Duplicate operation is unchanged.

## Goal and user contract

A user must be able to predict a command's target from its documented selection and editing-context rule. In particular: arrows move selected notes after incidental automation/velocity drawer interaction; contextual Duplicate uses the eligible selection and editing context. Do not generalize either rule to every command. Text/value entry, popups, live gestures, and deliberately keyboard-focused controls that visibly advertise arrow navigation retain their local keys. An ordinary drawer canvas, page toggle, or mute button is not an exception to the note-arrow rule.

Adopt LMMS's note-property selection continuity and Qtractor's explicit shared-editor keyboard dispatch. Do not build an application-wide focus framework, force focus back to the roll after every click, or make arrows window-global shortcuts.

## Reference implementations

- [LMMS piano roll](https://github.com/LMMS/lmms/blob/master/src/gui/editors/PianoRoll.cpp): adopt note-property selection continuity, not its bindings or monolithic widget structure.
- [Qtractor MIDI editor](https://github.com/rncbc/qtractor/blob/main/src/qtractorMidiEditor.cpp): adopt explicit shared dispatch, not source-pane-dependent pitch/value targeting.
- [Qt Quick focus](https://doc.qt.io/qt-6/qtquick-input-focus.html): ignored keys propagate through item parents; do not assume they will reach a QWidget song editor.

## Non-goals

- No QML-to-QWidget reversal, new global event-filter framework, new generic command bus, document/history rewrite, configurable shortcut redesign, or new focus manager.
- No change to application-wide drawer visibility/active-page state or current drawer-if-visible focus restoration. No new last-focused-band memory.
- No broad test-suite migration, wholesale file splitting, unrelated formatting, new tracing/profiling, or telemetry project.
- Do not silently change pitch/time movement increments, snapping, scale-fold rules, clipboard format, undo granularity, or automation authoring semantics.
- Event-list clipboard redesign is excluded. It is a replacement table editor, not a drawer. Preserve row-local navigation/Delete/Select All and existing non-note shared behavior; do not newly expose selected-note Cut/Delete through its fallback. Its existing window Copy-versus-row Delete mismatch is documented, not claimed fixed here.

## Interaction contract

### Selection and focus

1. `EditorSelectionModel` remains authoritative for note and scoped time selection. Resolve targets using that selection and the command's explicit context rule; do not store a parallel "active selection" that can drift.
2. Preserve note/time mutual exclusion. Focusing a band, opening/resizing chrome, or hovering does not replace selection. Editing already-selected velocity stems preserves their selection; clicking an unselected stem or completing an existing empty-plot deselect is a real selection transition and stays that way. A new automation/time-range selection replaces notes through the existing model.
3. Automation points are derived from `LaneSelection` plus the time interval in `EditorSelectionModel`; add no target/selection state. Nonempty notes imply no active time selection. Empty note setters do not clear time selection; inactive time setters do not clear notes. Preserve these details and primary-track transitions that intentionally clear both.
4. Physical keyboard focus remains available to drawers. The receiving band does not by itself override the selected-note arrow target. Context-dependent commands such as Duplicate may use the editing context, but must still require an eligible selection. Preserve focused text, popup, and explicitly keyboard-operated grip/scrollbar behavior; buttons retain Space/Enter activation but do not own note arrows.
5. Keep `focusActiveSurface` and drawer close/open focus behavior. Tab restoration must not change selection or resurrect a stale selection after document/primary-track changes. The proof is that note commands work even if restoration focuses a visible drawer.

### Command matrix

Precedence is protected local input, then active-gesture ownership, then shared command policy using the existing selection and any command-specific editing context, then eligible no-selection tools for commands that explicitly allow them. A recognized but unavailable command is a terminal no-op; it must not fall through to unrelated objects. A focused event-list table is its own editor and retains local keys.

| Situation | Arrows / movement | Delete/Cut/Copy | Escape |
|---|---|---|---|
| Editable text/value input, dialog or popup | Local editing; no shared selection commands | Local command, where supported | Close/cancel local interaction |
| Keyboard-focused grip/scrollbar showing focus and advertising arrows | Advertised navigation stays local; do not move notes | Only locally advertised keys are owned; no new clipboard semantics | Preserve local exit behavior |
| Live pointer gesture | Consume selection-movement keys without mutation | Block competing mutations; do not change selection under the gesture | Cancel gesture only; preserve/restore its captured selection |
| Selected notes, including incidental drawer/button focus | Move selected notes with existing increments and fold behavior | Target selected notes | Clear note selection when idle |
| Track-scoped time selection | Preserve existing transpose/nudge | Existing track-time operation | Clear selection when idle |
| Lane-scoped time selection | Up/Down transpose is consumed no-op; Left/Right nudge scoped contents and interval | Existing lane-scoped operation; no hidden-note edits | Clear selection when idle |
| No selection | No mutation of unselected notes | No destructive selection operation; qualified hover Delete below | Clear transient hover as appropriate; no song mutation |
| Event-list table owns input | Row navigation/reorder remains local | Row Delete remains local; no new note-edit fallback | Preserve table-local behavior |

The following feature rows extend, rather than override, that local-input and gesture precedence. The Shift+Left/Right row is implemented; the Cmd+D rows remain future work:

| Command | Eligible context and selection | Outcome |
|---|---|---|
| Shift+Left/Right | Selected notes, including incidental drawer focus | Shorten/lengthen those notes. Implemented: one live-grid boundary per press delivered as one shared delta anchored at the maximum end; one-tick floor; whole-selection no-op for an unterminated note; Edit-menu adapters, no context-menu entries |
| Cmd+D | Note editing with selected notes | Duplicate notes; placement remains a later-feature decision |
| Cmd+D | Automation lane with a scoped time selection | Duplicate the entire selected interval into the following interval, preserving node values, relative timing and empty gaps within that scope |
| Cmd+D | Track-scoped time editing with a selected interval | Existing scoped time duplication |
| Cmd+D | No eligible selection in the resolved context | Consumed no-op, never duplication of unrelated objects |

### Deferred feature decisions

Keyboard resize decisions are settled and implemented: one live-grid boundary per press with fixed starts, one shared delta anchored at the maximum selected end, a one-tick floor clamped against the shortest selected note, whole-selection no-ops for unterminated notes and for shortening a zero-duration terminated note, and rejection of steps outside `uint32_t` duration representability (no arbitrary cap). See `docs/keyboard-note-resize-plan.md`.

Before implementing contextual Duplicate, resolve these separately:

- Note duplication: placement and post-duplicate selection.
- Scoped time duplication: destination collisions, insertion versus overlay, shifting later content, post-duplicate selection, and empty-span behavior, grounded in the existing operation.
- Contextual Duplicate: the precise mapping when incidental chrome has focus, when notes remain selected but an automation canvas is focused, and when a menu invokes Duplicate. The user has established that context matters, but not every context/selection combination. Do not invent persistent focus memory or infer that notes always win. This decision is required before adding contextual Duplicate, not before preserving existing range duplication during the routing refactor.

These deferred questions do not reopen the established automation timing contract: selected measures 1–4 repeat into 5–8, not a span inferred from the first and last nodes.

### Existing shared-command details

Deliberate keyboard focus matters for navigation controls: Tab to a resize grip/scrollbar with its visible focus indication invokes its advertised keys. Mouse interaction that leaves focus on a timeline band must not silently create this exception. Other chrome, such as mute/solo/page toggles, owns activation keys only; unclaimed note commands continue to the song policy. Do not change their accessible descriptions to excuse dead shortcuts.

`roll.select_all` is named **Select All Notes**. From every timeline band and incidental chrome it selects all notes on the primary track using `PianoRoll::selectAllNotes`, including when no notes are selected. A nonempty result replaces time selection through the existing model. Text and table Select All stay local. Do not invent lane Select All or retain a drawer-only no-op. Pitch-bend editing likewise uses selected notes from every timeline band.

Paste is not selected-object editing. `SongView::pasteFromClipboard` already owns clip dispatch, edit-cursor placement, note-clip primary-track retargeting, range-clip mapping, undo, cursor advance and announcements. Preserve it exactly; do not claim every range clip is forced onto the primary track. Remove the roll's redundant forwarding method during cutover once its callers have migrated. The automation context-menu lane-replace clipboard is a separate tool operation, not the song Paste shortcut.

Automation pencil-hover Delete is a tool action, not a selection. Any active note OR time selection wins; hover-delete is eligible only with no song selection, pencil mode and the automation tool's valid hover context. A hover miss is a terminal no-op. In particular, guarding only `noteSelection().empty()` is insufficient: a track-time selection can coexist with a hovered automation lane too.

Copy/Cut/Delete agree on the selected-object target across the timeline editor. Keep MainWindow's unique Copy owner. Note menus reuse the same semantic operations; targeted automation context-menu tools keep their explicit lane semantics. This claim does not extend to the pre-existing event-list clipboard mismatch.

### Motivating commands: keyboard resize and note duplication

The user identified two concrete reasons for this work: **Shift+Left/Right to shorten/lengthen selected notes**, and **Cmd+D to duplicate selected notes or a scoped time selection, including automation**. This routing plan is their prerequisite. Keyboard resizing is now implemented as the keyboard note-length feature (`docs/keyboard-note-resize-plan.md`); contextual Duplicate is not implemented, and its remaining decisions stay deferred.

Resize uses the selected-note target after incidental drawer/property interaction. Duplicate is contextual as specified below; do not impose the note-arrow targeting rule on every command. Both preserve text/local-control capture, execute once, and support undo. Adding them must require a binding plus semantic operations, not another focus workaround or a second dispatcher. Shift+Left/Right in text input continues to select text.

**Duplicate contract (latest user clarification):** Cmd+D is one contextual Duplicate command. The active editing context and eligible selection determine the operation: selected notes in note editing → duplicate notes; automation lane time selection → duplicate that selected span in its lane scope; track time selection → duplicate that span in its track scope. No eligible selection in the chosen context means a consumed no-op, not fallback to unrelated objects. Text/popup ownership remains first. Existing `keymap.cpp` assigns `Ctrl+D` (Cmd+D on macOS) to `roll.duplicate_time`; evolve that single dispatch and preserve custom bindings, rather than registering competing shortcuts.

**Automation duplication uses the selected time span, not the selected nodes' bounding extent.** For a selection `[start, end)`, duplicate contained automation events at `tick + (end - start)`, preserving values and each event's offset within the span. Selecting measures 1–4 (start of measure 1 through start of measure 5) duplicates the pattern into measures 5–8, including its leading/trailing empty time. Do not normalize the first node to the destination start or derive the repeat length from the first/last node. Existing lane-scoped time selection is the appropriate representation; no independent point-selection store or separate node-only duplication mode is required. Lane scope limits affected content; this does not imply duplicating all tracks.

Keyboard resize has pinned and implemented its increment, minimum length, fixed-start anchoring, and mixed-length selection behavior through `PianoRoll::resizeSelectedNotes` behind the guarded `SongView::resizeSelectedNotes` seam. Note duplication placement and all post-duplicate selection behavior still need existing conventions when Duplicate lands. Automation span length and relative event placement are fixed above; reconcile destination collisions, insertion versus overlay, and any shifting of later content with existing time-duplication semantics rather than inventing them here.

Feature acceptance sequences: selected notes plus incidental drawer interaction → Shift+Right/Left changes only their lengths; note-editing context plus selected notes → Cmd+D duplicates notes once; automation context plus a four-measure lane time selection → Cmd+D duplicates that span into the next four measures, preserving relative node positions and leading/trailing gaps; track time selection → existing scoped time duplication. Cover a first node after the selection start and a last node before its end to catch accidental node-bounds duplication. Verify scope, exactly-once execution, undo and post-operation selection. Repeat with text input focused to prove no unintended song mutation. The resize sequence is covered by the permanent checks specified in `docs/keyboard-note-resize-plan.md`, whose final full-gate verification is still pending. The Cmd+D sequences become required when that command is implemented; they are not passing checks or extra feature scope claimed by routing-only work.

### Visual feedback

Prefer existing selection rendering when it already matches these rules. Audit whether actual selection replacement immediately removes the old selected appearance and whether lane-range selection can be mistaken for note selection. Fix misleading feedback in the same feature; do not add banners or a second generic focus highlight just to explain broken targeting. A focused drawer border alone must not imply that note arrows stopped working.

**Velocity overlap rule:** duration stems remain visually underneath node handles, including a following note's node overlapping an earlier note's stem. Draw stems below nodes even when the stem's note is selected or hovered. Hit testing must agree: an overlapping node's hit area wins over a stem hit, regardless of the stem note's selection status. Clicking or beginning a drag there targets the visible node, not the underlying duration line. Keep existing node-versus-node tie-breaking; this requirement does not introduce a new selection hierarchy.

Existing source already expresses this intent: `VelocityArea::notesAt` (`velocityarea.cpp:358-393`) compares circle-hit priority before selected status, distance and order; `quick/velocityquick.cpp` emits separate `VelocityStems` and `VelocityNodes` layers. Preserve the hit-test rule and verify actual scene stacking, selected/hover styling and rendered overlap rather than assuming separate layer names prove drawing order.

## Implementation seam

`SongView::handleEditKey` owns shared command matching and target resolution in `src/ui/songview/editkeyrouting.cpp`. `rangeedit.cpp` keeps range mutations; PianoRoll keeps note operations, audition and pointer-gesture implementation. Do not add a parallel dispatcher.

### Small interfaces and ownership

- In an eligible editing context, a recognized command is consumed even when its target is unavailable. An unmatched command or one owned by another editor/shortcut owner is declined. A bool expresses this acceptance contract; a disabled selection command must not fall through to an unrelated target.
- Pass the existing editing context or a narrow input-origin value when a command needs it: contextual Duplicate and event-list ownership are examples. Context is an explicit input to the command's target policy, not permission to make all commands follow focus. Note arrows retain their selection-driven rule. Derive context from existing surfaces and selection scope; do not add a shadow selection store or generic active-target state.
- Expose only note semantic operations needed by SongView, following `copySelectedNotes`: `cutSelectedNotes`, `deleteSelectedNotes`, transpose/nudge, `selectAllNotes`, and pitch-bend opening. Keep `resolveSelection` and note-copy plumbing private. Preserve document dirty hints, clear/reconcile behavior, mergeable movement and scale-fold rules.
- Never call `PianoRoll::keyPress` from shared policy. The common route owns shared matching; band handlers retain genuinely local input behavior and semantic operations accept editing intent, not synthesized keys.
- MainWindow remains the unique owner of Copy/Solo shortcuts and explicitly configures that ownership on its SongViews. Standalone SongViews own those shortcuts themselves. Song policy must not inspect or depend on MainWindow's concrete type.
- Public-interface edits require LSP references. Audit direct callers in menus, checks and constructors; delete obsolete forwarders/comments after migration, not compatibility aliases.

### Make the supported extension pattern obvious

Future agents learn from executable examples more reliably than a plan. This cutover must establish one dominant pattern, not add a preferred route beside several equally plausible legacy routes.

**Canonical path:** binding or menu action → shared song command entry → selection-target decision → semantic edit operation. Physical key translation is an adapter; semantic operations accept editing intent, never `QKeyEvent`, focus widgets, or shortcut strings. Reuse the existing keymap identities rather than adding a second command registry. A concrete command identity at the semantic seam is appropriate if needed to let keys and menus enter it without synthesizing events.

1. **Migrate the examples agents will find.** Existing note movement, Cut/Delete, Select All Notes, range duplication and window Copy must enter the same command-policy module. They need not have identical targeting rules: note arrows are selection-driven; Duplicate is context-and-selection-driven. Preserve one physical activation owner for window actions, but let that owner call the shared semantic operation. Do not leave Copy/Solo window deferral as unexplained special knowledge every new command must reproduce.
2. **Remove competing shared-command implementations.** Delete migrated matching/selection branches from band handlers, redundant paste forwarding and stale QWidget-propagation comments. Keep genuinely local gesture/text/control behavior, with a short comment distinguishing it from song commands. A future source search for an existing command should reveal its definition and authoritative dispatch, not several independent edit implementations.
3. **Keep the feature discoverable.** Command policy lives in the cohesive `src/ui/songview/editkeyrouting.cpp` module with a small declared interface; note/range mutations stay in their existing feature files. Do not create one tiny file per command or a plugin/provider framework.
4. **Use honest names.** The semantic operation is `Duplicate Selection`, not `Duplicate Time` once it handles notes too. Preserve persisted custom bindings through an explicit settings migration when an identifier changes, rather than propagating a misleading runtime name or keeping a permanent alias path. UI grouping is not execution scope.
5. **Provide real reference examples.** Existing note nudge demonstrates selected-note targeting independent of input surface. Existing time duplication demonstrates target-specific editing. Copy demonstrates native action activation entering the same semantic policy. Resize has landed as an example of extending the pattern; Duplicate Selection should join it, not sit beside it as an exception, when implemented.
6. **Keep tests discoverable by behavior.** Cross-focus checks should read as user sequences (select notes → click drawer → nudge; rename → key → text changes only). Mutation checks separately cover edit bounds and undo. Do not add source-text assertions that enforce where code is written.
7. **Document only the seam.** During implementation, add a brief ownership comment at the common entry and a short pointer in the existing agent guide describing where to add a song editing command and which native regression covers it. Name real final symbols, not planned ones. Do not duplicate the full policy in several docs; the executable examples remain authoritative.

**Future command recipe:** add/reuse its existing-registry binding; add one case in the common command policy; implement/reuse its semantic operation; prove the operation's observable contract and representative input delivery. Update effective activation/conflict metadata when needed. A new command must not need edits to AutomationCanvas, VelocityArea, VoiceChangeArea, QML input adapters, or focus restoration merely to work from those surfaces.

**Extension acceptance:** the routing cutover's change-impact walkthrough used Shift+Left/Right resize and Cmd+D duplication of notes and scoped time selections, including automation spans, to identify the exact binding, context/selection resolution and mutation seams. Resize has since landed through exactly those seams. The Cmd+D portion stays open: when it lands, adding it must still require no new event filter, per-drawer key forwarding, text-widget whitelist, or focus-restoration patch, or the routing cutover is incomplete. Reuse existing lane-scoped range duplication where it meets the contract; do not add a node-only duplication operation. This is an ownership review, not a reason to add a generic abstraction or fake test command.

### Input integration

`TimelineInputItem::keyPressEvent` is the common band entry. Install a lifetime-safe song-policy callback through `TimelineQuickView` attachment, without expanding `TimelineInputHost` merely to access SongView. Clear callbacks when interaction/owner detaches; use existing QObject lifetime ownership or a guarded pointer rather than a raw unbounded capture.

One ordering must cover all bands: protected local capture/gesture cancellation, shared selected-object policy, then eligible no-selection local tools. Equivalent band-first integration is acceptable only if local handlers are explicitly restricted to gesture handling and cannot preempt selection commands; do not leave the current raw automation Delete/idle Escape branches ahead of the policy.

The Quick scene also contains focusable QML chrome outside band items. Provide a single scene-level fallback for unclaimed keys from those items, using the existing Quick root/bridge and the same SongView policy. Preserve `Keys` acceptance for TextInput, resize grips and scrollbars. Keep the band path and chrome path mutually exclusive for handled keys; do not install one application-wide filter. Verify the root fallback actually receives unclaimed keys rather than assuming QML ancestry.

`SongView::event` remains the QWidget-side entry for supported shared commands. Preserve EventListView's row-local keys and do not widen its fallback to the newly enabled selected-note operations. Native tests must establish that a key executes once, not rely on an assumed Qt bubbling route.

QML rename uses TextInput `ShortcutOverride`; MainWindow guards QWidget text editors. Do not assume the guards are sufficient, but do not add private-QQuickTextInput casts or an unnecessary guard based on speculation. Probe actual rename Copy/Solo behavior first. If a real action path bypasses text acceptance, add a narrow public text-editing-state guard and preserve actual text Copy, not a silent no-op.

### Binding scope

Shared timeline commands have an effective activation scope spanning timeline bands, independent of their display category. Conflict detection must preserve existing bindings and display grouping without marking all Velocity/Automation tools mutually overlapping merely because shared commands span both.

Ground changes in `keymap.cpp` command definitions, `contextsOverlap`, `conflicts`, `modifierConflicts`, and attachment. Shared movement/Delete must conflict with incompatible band-local bindings in every band where they are active. Account for existing window-owned Copy/Solo when reporting collisions rather than documenting a knowingly false scope. Use the same registered `roll.delete` binding for the selected-object Delete path, including automation point selection. Escape stays the platform gesture-cancel key.

## Verification

Use only repository Deno tasks. Keep three distinct evidence levels:

- **Logic:** direct policy/semantic calls can prove targeting and terminal no-ops. `src/checks/support/eventsynth.cpp` and `rollcheck/keyboard.cpp` are existing references. These calls do not prove keyboard delivery.
- **Qt delivery:** a shown `Windowing::WindowSystem` surface with QTest input to `view.quickView()->quickWindow()` exercises Quick delivery; `scrollbarquickcheck_songview.cpp` is a working pattern. QWidget-side input through QApplication exercises a different route. Record which shortcut/delivery stages the installed helper actually reaches; do not claim either is native OS injection.
- **Native smoke:** actual launched app, physical or verified OS-level key input after real mouse/focus interaction. Cover the reported sequence, local text input and window shortcuts. If the runtime cannot be driven, explicitly report the missing capability; synthetic-only proof does not silently satisfy this gate.

Required scenarios (use isolated/reset state for destructive variants):

1. Select two notes; click automation background without making a replacement range; all four arrows move only those notes. Preserve increments, selection and undo. Repeat delivery across velocity, voice changes, ruler and other-events bands where available.
2. Drag already-selected velocity stems then move notes: same targets. Click an unselected stem then move: only its new selection moves. Preserve existing empty-plot deselection behavior.
3. Create an actual automation lane range: notes clear, lane/point selection becomes visible; Delete affects covered points only.
4. Selected notes plus pencil hover: Delete edits notes only. Active track-time selection plus hover: time-selection operation wins. No selection plus eligible hover hit: point deletion. Hover miss: terminal no-op.
5. QML track rename, a real QWidget text input, modal numeric entry (`NodeLane::promptValue`/QInputDialog), and pitch-bend overlay: caret/local commands own keys. Copy copies text where appropriate. Solo/Pencil typing in text/value input must not toggle song state; graph-focused pitch-bend Solo retains its existing local operation. Commands resume after closing.
6. Note/velocity/automation live gestures: first Escape cancels only the gesture and preserves/restores its selection; second clears the remaining selection. Movement/Cut/Delete cannot mutate under the gesture. Idle drawer Escape clears selected notes.
7. Track-time commands stay within track scope. Lane Up/Down never transpose hidden notes; lane Left/Right move selected points/tempo and the time interval, including the existing empty-range movement behavior.
8. Timeline Copy/Cut/Delete and existing note menus agree on objects. Roll/drawer Paste produce the same clip/destination result using actual clipboard data.
9. Native Copy/Solo from Quick focus execute once. Rebound Delete works for both note and automation selections. Shared-command collisions are reported without falsely merging independent local tool contexts.
10. Switch A/B tabs, hide drawers, change primary track and replace/destroy documents: correct tab selection only, no stale callback, existing drawer visibility/restoration policy unchanged.
11. Event list: arrows navigate rows, Delete/Backspace delete rows, Alt+Up/Down reorder, Select All selects rows. No new selected-note Cut/Delete fallback. Existing shared paste/mute/solo and window Copy do not acquire duplicate owners.
12. Select All Notes from automation/velocity/incidental chrome selects all primary-track notes; a nonempty result replaces time selection. It works when initially nothing is selected. Text/table Select All remains local.
13. Tab to a resize grip/scrollbar with advertised arrow use and visible focus: its advertised keys remain local. Tab to mute/solo/page toggles: Space/Enter activate; note arrows route to selected notes. Ordinary mouse clicks without local keyboard-control focus do not create an arrow dead zone.
14. Earlier note A's velocity duration stem overlaps following note B's node. With A selected and B unselected, B remains visibly above the stem; clicking or beginning a drag within B's node hit area targets B and follows normal note-selection transitions. Repeat with hover/selected styling and zoom changes; the stem must never paint over or steal B's node. Confirm subsequent arrow movement affects the resulting selection. Node-versus-node overlap retains existing tie-breaking.

### Harness and command map

The four registered suites live in the cohesive `src/checks/selectionkey/` module: standalone policy, gesture ownership, window lifecycle, and local input. Reuse shared production-backed session and automation projection helpers; keep distinct scenario behavior local. Do not append unrelated scenarios to `mainwindowroutingcheck.cpp` or create fake routing echoes.

Registration points: CMake's `porydaw_checks` sources, `src/checks/fwd.hpp`, and `src/checks/checkcatalog.cpp` (`CheckDefinition`, scratch kind, fixture root/files, `Windowing::WindowSystem`). Follow `scrollbarquickcheck`/`trackheaderquickcheck`: `route101Files` already declares its complete song fixture; use an existing two-song bundle such as `twoSongRichFiles` only when the scenario needs it. Do not hand-copy the decomp project or invent redundant fixture lists.

Avoid duplicating existing mutation tests in `rollcheck/keyboard.cpp`, model contracts in selection/laneselection checks, or clipboard-format tests in clip checks. Keep new tests for the real cross-focus routing regressions, plus an offscreen-eligible policy case where native checks can be skipped. The native harness must not substitute direct QAction triggers for key delivery.

Commands after implementation edits settle:

```sh
deno task build:checks
deno task verify --filter selectionkey --verbose
deno task verify --filter rollcheck
deno task verify --filter clipcheck
deno task verify --filter selectioncheck
deno task verify --filter keymapcheck
deno task verify --filter mainwindow-routing
deno task verify --filter eventviewcheck
deno task verify
```

Verify current catalog/filter names before execution; substring filtering may include related checks. `--no-windowing-checks` cannot be used to claim native acceptance. Run formatting through `deno task format` on intended supported files only, after edits settle; never pass QML to C++ formatting. Resolve and report every assertion failure before handoff.

## Completion gate

Deliver real click/selection/key evidence, target-specific regression results, exactly-once execution and local text-entry protection. Update affected docs/changelog and remove throwaway probes after verification. The requested delivery is a commit onto `fork-main` after verification and resolution of the dual thermo auditors' accepted findings; no push. Do not substitute menu activation for a failed native shortcut criterion.

The canonical extension contract above is part of completion: migrated commands are working reference examples, obsolete shared-command paths are removed, the extension walkthrough needs no per-surface patches, and brief agent guidance points to the actual implemented seam.

## Runtime ownership

`TimelineQuickView` attaches one lifetime-safe key-policy handler to each band and connects declined chrome keys to `SongView::handleEditKey`. Detachment clears the handler; reattachment installs the current handler rather than reviving retained callback state. Key release acceptance follows actual audition completion rather than swallowing every release.

`SongView::timelinePointerGestureActive()` is the command gate for live pointer gestures. Follow-playhead pause state and popup visibility are separate concerns. `SongView::cancelActiveInteractions()` is the canonical pointer-cancellation entry for Escape and lifecycle events. Stronger document/readiness teardown also performs modal cleanup; ordinary pointer cancellation must not close a newly opened pitch-bend popup when its parent deactivates.

Quick scrollbar gesture state is exposed through the typed input bridge. Native mouse ungrab must cancel a press without allowing subsequent held-pointer motion to revive the drag. Coordinate/value mapping, geometry rebasing and model-authoritative position remain scrollbar responsibilities.

Permanent acceptance suites are `selectionkey-core`, `selectionkey-gesture`, `selectionkey-window`, and `selectionkey-local-input`. These deliver Qt input to production surfaces; they do not claim OS-level injection. Keep run-specific results and audit deliberation in commit notes rather than this specification.
