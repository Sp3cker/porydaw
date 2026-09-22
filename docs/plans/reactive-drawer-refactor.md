# Reactive editor-drawer architecture plan

## Summary

Make each drawer domain a deep module with a small value-based interface: typed events enter once at the Qt/session seam; a pure reducer changes domain state and returns semantic effects; pure projection produces value rows; one publisher reconciles those rows and scalar values into the existing QML interface. Keep `DocumentSession`/`SongDocument` as document, selection, camera and history owners. Keep QML unchanged. Do not introduce a second observable object graph merely to flatten it back into Qt properties. Start with Velocity, use it to establish the common Qt/input/publication conventions, then migrate the container and Voice Changes, and finally Automation. The architectural work enables incremental proof conversion; it does not turn every native assertion into a pure assertion.

## Assumptions and scope

- This is a behavior-preserving refactor, with the C++ sources and assertion ledgers as the oracle. Existing Swift behavior is not automatically authoritative where its proof entry remains GAP/PARTIAL.
- Reactive frameworks are allowed if compatible with macOS, Linux and the Windows/MinGW Swift build. They were considered below; the recommendation against adding one is a design conclusion, not a constraint inherited from the original assignment.
- Existing QML member names, raw surface/action identifiers, synchronous return meanings, and model objects remain stable. Internal Swift types and check helpers can migrate cleanly.
- No new app-wide state store, observer bus, scheduler, renderer, camera, clock, clipboard implementation, or history abstraction.
- Inspection measured **38 Swift drawer files / 12,461 lines**, including `PromptAppearance.swift`: Velocity 2,859; Voice Changes 2,533; Automation 5,970; root 1,099. The supplied 37/~12.4k inventory is approximate; use measured numbers for estimates.
- The current root CMake Swift integration and Swift check targets are under `if(APPLE)` (`CMakeLists.txt:168–175`; `src/checks/CMakeLists.txt:103–204`). This does not dispute the product’s three-platform shipping requirement; it means a macOS check run in this tree cannot certify a newly added dependency on the other shipping toolchains. Do not silently turn this drawer refactor into a whole build-platform port.

## What the actual code already does well

Preserve these algorithms rather than replacing them with framework operators:

1. **Frozen Velocity arithmetic.** `VelocityGesturePolicy` already implements pure relative/ramp/paint/update-payload rules (`velocity/VelocityTransactions.swift:112–219`). Keep the arithmetic, activation conditions, per-note maps, ordering, and no-op filtering. `VelocityPromptPolicy` is already a pure validation seam.
2. **Velocity map/axis rules.** `VelocityContextPolicy` and `VelocityAxisModel` already express meaningful, testable domain policy. Keep their PSG, split-key, incompatible-selection, exact-map refusal, density and graduation algorithms. Do not duplicate them in reducers.
3. **Voice occurrence semantics.** `VoiceLanePolicy` and `VoiceChangesTransactions` are already the desired value-policy shape. Preserve exact occurrence validation, same-tick behavior, nearest/later hit tie-breaks, picker no-op refusal, and semantic mutation drafts (`voicechanges/VoiceLanePolicy.swift:49–149`; `VoiceChangesTransactions.swift:1–106`).
4. **Automation transaction math.** `AutomationPointDrag`, `AutomationAxisLock`, drawing transactions, node transactions, lane replacement and `AutomationCommit` already own real complexity. Keep slop reset, held-span restoration, phantom value-only motion, frozen collision occupants, multi-lane deltas, and the one semantic commit path. Do not flatten these into one giant switch.
5. **Shared item-model synchronization.** `src/swift/app/QListModelSync.swift:5–18` already updates changed common rows and inserts/removes the changed tail without replacing the model object. Reuse and extend this implementation.
6. **Distinct presentation paths.** Velocity’s `refreshPlayhead` distinguishes equal presentations/context changes, and hover/gesture paths avoid rebuilding the grid and PSG bands. Voice Changes similarly distinguishes readout from marker content. Automation has separate context and hover updates. Preserve these dependency distinctions inside the scene cache; “one publish” must not mean “rebuild everything on every mouse move.”
7. **Container policy concentration.** `EditorDrawerLayout` already owns stacking, clamping, resize, focus, preferences and spill in one place. `EditorDrawerPresenter` is already mostly an adapter. Its focus target-before-revision publication order must stay.

## Actual friction to remove

### A. The current scene outputs are not plain value scenes

`VelocitySceneInput` is a value, but `VelocitySceneSnapshot` contains `[VelocityHandle]`, `[SceneRect]` and `[SceneText]` and its builders accept `GridTypography` and previous bridged handles (`VelocityScene.swift:112–231`). `VelocityProjection.hitTest` takes `[VelocityHandle]` and is `@MainActor` (`VelocityProjection.swift:45–83`). The supposedly pure `VelocityScene` enum also reads `DocumentSession` and creates Qt objects (`VelocitySceneValues.swift:18–88`, `139–309`).

Voice projection likewise produces bridged markers and uses native font sessions. Automation is further from purity: `AutomationSceneSnapshot.build` receives `DocumentSession` and a mutable projection cache (`AutomationScene.swift:35–106`), while menu state directly stores `[AutomationMenuRowHandle]` (`AutomationModal.swift:32–40`). Merely adding `State.swift` leaves these test costs intact.

### B. State transition and publication are interleaved

Velocity’s pointer/prompt functions mutate page fields, select notes, commit documents, and call multiple `publish*` methods (`VelocityInteraction.swift:35–310`, `391–495`). The state machine is already visible in `switch gesture.kind`; the missing piece is an explicit value transition result and a single adapter path.

Automation’s `rebuildContent` copies a snapshot into numerous page fields and then invokes several publishers (`AutomationLifecycle.swift:20–75`). Its overlay publisher contains another six copies of the generic model synchronization loop (`AutomationOverlayPublication.swift:259–317`). Voice Changes mixes pure projection, Qt handles, font sessions, picker caching and synchronization in `VoiceChangesProjection.swift`.

### C. “Publish only changed fields” is not enough for models

The inspected QtBridge `QListModel` subscript setter emits `dataChanged`; `replaceSubrange` emits insertion/removal signals; `reset` resets everything (`build/_deps/qtbridge-src/Sources/QtBridge/QListModel.swift:106–215`). Current hover paths mutate a bridged row and explicitly assign `model[index] = row` afterward (`VoiceChangesPublication.swift:188–196`; `AutomationOverlayPublication.swift:40–51`). A scalar-equality diff that merely mutates a Swift handle can miss the notification required by model-role delegates. A whole-array assignment/reset destroys the useful no-op/identity behavior.

### D. Session effects synchronously re-enter the pages

`DocumentSession.setSelectedNotes` publishes synchronously, and `mutateCamera` invokes its callback synchronously (`DocumentSession.swift:139–145`, `223–232`). `DocumentWorkspace` fans these changes back into page refresh methods (`DocumentWorkspace.swift:221–267`). A release can therefore cause document refresh before its outer handler returns. New code must install the reduced state before executing effects and must not publish a stale pre-effect scene afterward.

### E. The container’s “pure value” comment currently overstates purity

`EditorDrawerLayout.Section` stores an `EditorDrawerPage?`; layout directly queries page sizing and interaction, and directly calls cancellation in detach/global/visibility transitions (`EditorDrawerLayout.swift:32–74`, `108–117`, `245–253`, `292–304`, `526–531`). `cancelledSections` currently records cancellations that already happened; it is not yet an effect instruction.

### F. The Qt seam includes writable properties, not just functions

`AutomationPage.isPencilMode` already has a `@QtTracked` observer (`AutomationPage.swift:110–118`). `AutomationPage.qml:282–288` writes `plotFocused` through a Binding. These cannot be left as independent mutable truth outside the reducer. Preserve the QML contract with equality-guarded property observers that send `.toolChanged`/`.focusChanged`; treat them as seam inputs, not another derived output loop. Similarly, changing `VoiceChangesPage.onAuditionVoice` must release the old audition callback before replacing it (`VoiceChangesPage.swift:162–167`).

## Changes

### 1. Target layout: logical layers, not five compulsory files everywhere

Use the five logical responsibilities requested—Qt page, events, state/reducer, pure scene, document effects—but do not manufacture a tiny `Events.swift` for each domain. Put each domain’s event enum beside its state/reducer. Decode common Qt bit patterns once in one shared file. Automation keeps cohesive policy files because its real behavior will not fit into five 400-line files.

All paths below are relative to `src/swift/app/drawer/`.

| Area | Target files | Ownership |
|---|---|---|
| Shared/root | `EditorDrawer.swift`, `EditorDrawerTypes.swift`, `EditorDrawerLayout.swift`, existing `PromptAppearance.swift`, new `DrawerInput.swift`, new `DrawerSceneValues.swift` | Container adapter/policy, common Qt input decoding, shared plain rectangle/text/font-metric descriptors and their existing Qt-row conversion seam. |
| Velocity: **6 files** | `VelocityPage.swift`, new `VelocityState.swift`, `VelocityScene.swift`, `VelocityTransactions.swift`, unchanged `VelocityAxis.swift`, unchanged `VelocityContext.swift` | Page owns published members, synchronous send/effect execution and one publisher. State file owns `VelocityEvent`, `VelocityState`, interaction cases and reducer. Scene owns pure output values and geometry. Transactions retains frozen arithmetic/prompt rules and semantic effect execution. |
| Voice Changes: **6 files** | `VoiceChangesPage.swift`, new `VoiceChangesState.swift`, `VoiceChangesScene.swift`, `VoiceChangesTransactions.swift`, `VoiceLanePolicy.swift`, new `VoiceChangesPresentation.swift` | State/reducer owns pointer/picker/menu/hover/audition transitions. Scene owns all value projection. Presentation contains the existing bridged marker/picker/menu classes, native typography adapter and row construction only; it is not another controller. |
| Automation: **15 files** | `AutomationPage.swift`, new `AutomationState.swift`, `AutomationInteraction.swift`, `AutomationModal.swift`, `AutomationSelectionCommands.swift`, `AutomationScene.swift`, new `AutomationPublication.swift`, `AutomationHandles.swift`, `AutomationTransactions.swift`, `AutomationDrawingTransactions.swift`, `AutomationNodeTransactions.swift`, `AutomationEdits.swift`, `AutomationParameter.swift`, `AutomationProjection.swift`, `AutomationLaneProjection.swift` | State file owns event vocabulary, aggregate state, top-level reducer and tap-tempo value state. Interaction/Modal/SelectionCommands become pure reducer/planning helpers, not Page extensions. Publication is one Qt-only diff pass. Existing mathematical policies remain separate. Transactions includes effect execution and session-fact extraction/cache; no new Effects/Store framework file. |

Exact removals after caller cutover:

- Velocity: remove `VelocityInteraction.swift`, `VelocityPublication.swift`, `VelocitySceneValues.swift`, `VelocityProjection.swift`; move their necessary behavior into the files above, not compatibility extensions.
- Voice: remove `VoiceChangesInteraction.swift` and `VoiceChangesPublication.swift`; split the existing `VoiceChangesProjection.swift` by responsibility into pure `VoiceChangesScene.swift` and Qt/native `VoiceChangesPresentation.swift`, then remove the old file.
- Automation: remove `AutomationLifecycle.swift`, `AutomationContentPublication.swift`, `AutomationOverlayPublication.swift`, `AutomationProjectionCache.swift`, `AutomationTapTempo.swift`. Preserve their useful cache and tap-tempo behavior in the named owners above. `AutomationInteraction.swift`, `AutomationModal.swift` and `AutomationSelectionCommands.swift` remain by name but lose mutable `extension AutomationPage` ownership.
- Update the explicit source list in `src/swift/app/CMakeLists.txt:36–75` for every addition/removal.

This is a target of **33 drawer files**, not an artificial five-file target that moves 1,000 lines into each `State.swift`. Aim for 200–400 lines; allow the complete Velocity scene/reducer and Automation interaction/publisher to approach 500–600 where cohesive. No file over 600 without a named reason and a reviewed split decision. Do not achieve line targets by combining declarations onto one line.

### 2. Shared event decoding at the Qt seam

Create `DrawerInput.swift` with:

- `DrawerPointerButton`: `.none`, `.primary`, `.secondary`, `.middle`, `.other(Int)`.
- `DrawerPointerButtons`: typed held-button set for move events.
- `DrawerModifiers`: semantic `shift`, `control`, `alt`, `meta` flags, decoded from Qt’s bits in one initializer.
- `DrawerPointerInput`: position, changed button, held buttons, modifiers and phase. Domain surface decoding stays in the domain event initializer because ruler/gutter/tabs meanings differ.

Each public Qt-facing pointer method constructs one typed event and calls `send`. No Qt bit arithmetic occurs in reducer branches or gesture helpers. Unknown surface values remain rejected; unknown buttons retain each method’s existing consumed/unconsumed result. Keep changed-button and held-button concepts separate.

Velocity-specific event decoding resolves the existing modifier policy once:

- `extendSelection = modifiers.control` and `ramp = modifiers.shift` are membership tests.
- Detent unlock is **exact Control**, or exact Control+Shift only on paths that admit Shift; Alt/Meta disqualify it. Non-shortcut Qt bits must not change that rule.
- Ruler and plot differ: ruler admits no Shift unlock; plot admits it.
- Disabling detents is state policy, applied by the reducer; do not bake a mutable preference into a globally decoded event.
- Do not substitute Command/Meta for Control on macOS; the current contract explicitly distinguishes them.

Voice uses live Alt from move events for fine snap. Automation maps Alt→fine lattice, Control→neutral-value snap, Shift→ramp/axis-lock **on each supplied event**. Do not freeze all modifiers at press: the automation update code intentionally reads current modifiers.

Delete `VelocityQtButton`, `VelocityModifier`, `VoiceQtButton`, `VoiceModifier`, `AutomationQtButton`, `AutomationQtModifier` after migrating callers. Keep a small Qt decode contract test; pure behavioral tests send typed events rather than encoding integers. Relevant current test callers include `src/checks/automation/AutomationPageChecks.swift`, `automationactions.swift`, `automationclipboard.swift`, `automationselection.swift`, `domain/gestures.swift`, and `src/checks/drawerpresentation/voice_interaction.swift:264`. Preserve numeric Qt bridge tests where they test the adapter itself; do not retain domain aliases just for fixtures.

### 3. Velocity worked example: state, transitions, and effects

Introduce:

- `VelocityDocumentFacts`: revision, selected track, track notes, ordered selection, program/voice changes/bank facts and edit cursor. These are values sampled from session ownership, not another editable document.
- `VelocityState`: current document/view facts, detent preference, hover identity, presented playback/context facts and interaction mode. Do not store published strings, Qt handles or arbitrary property mirrors here.
- `VelocityMode`: `.idle`, `.gesture(VelocityGesture)`, `.prompt(VelocityPromptState)`; this prevents simultaneous prompt and pointer ownership.
- `VelocityGesture`: `.relative(VelocityEditGesture)`, `.paint(VelocityPaintGesture)`, `.ramp(VelocityEditGesture)`, `.pendingBand(VelocityBandGesture)`, `.band(VelocityBandGesture)`, `.pan(VelocityPanGesture)`.
- `VelocityEvent`: typed pointer events; leave/Escape/cancel; body configuration; document/camera/cursor/playhead facts; detent setting/toggle; prompt open/draft/accept/cancel; detach.
- `VelocityTransition`: synchronous consumed/accepted result plus ordered `[VelocityEffect]`.
- `VelocityEffect`: set ordered selection; set velocities with captured revision; pan shared camera by delta; notify accepted velocity. Document effects do not mutate state directly.

Reducer seam: `VelocityReducer.reduce(_:event:scene:) -> VelocityTransition`, mutating an `inout VelocityState` and reading a plain `VelocityScene` for currently presented hit geometry. This is pure: no session, Qt object, clock, callback or native font access. The scene argument makes explicit that a pointer hits the geometry the page presented; tests call the same `build` then `reduce` functions. After selection changes inside a press, derive the new axis/context from the updated ordered selection before freezing the edit capture; do not keep using the pre-selection axis accidentally.

Use `inout` for the production reduce path. Value semantics need not mean copying the full state tree on every move, and `Equatable` on the entire state is not required. Arrays/dictionaries remain copy-on-write; only the render values that the publisher compares need equality.

#### Transition table

| Start/event | Next state and exact behavior |
|---|---|
| Idle + middle plot press | Pan, remember prior x. Move emits camera deltas; release/cancel ends it with no document edit. Velocity currently ignores move button masks; do not import Automation’s lost-middle-button rule into Velocity. |
| Idle + right plot press | Pending band with press-time ordered selection and optional hit. A non-Control press on an unselected hit selects it immediately. |
| Pending band + move at Manhattan distance `>= dragDistance` | Band; build covered-note preview from the same value handle geometry. Below threshold remains pending. |
| Band + right release | Replace selection, or extend press-time selection under Control, in stable order. No velocity/history effect. |
| Pending band + right release | Control toggles captured hit membership; empty non-Control click clears; an ordinary hit keeps its press selection. No edit. |
| Idle + Shift-left plot press | Ramp over frozen selected notes; preview updates use existing `applyRamp`. Release commits only after actual pointer displacement. |
| Idle + ordinary left hit | Apply press selection rules, then Relative capture. Motion stays pending until vertical activation distance or intrinsic-level crossing. Below-threshold release performs click selection, not an edit; activated release emits one revision-guarded velocity payload. |
| Idle + ordinary left miss | Paint. The press itself can preview a selected note whose x column intersects the pointer even when its node is vertically elsewhere. Freeze participants lazily as the sweep reaches them; release commits iff a real painted target/preview exists, otherwise deselects. |
| Ruler left press | Resolve exact ruler graduation/unlock policy and selected targets, then emit the commit immediately on **press**, not release. Release adds no edit. |
| Prompt draft | Truncate/validate according to existing `VelocityPromptPolicy`; no document effect. Valid acceptance returns accepted=true even for a no-op and still seeds `onVelocityAccepted`. Stale capture returns false after closing. |
| Escape/cancel | Drop draft/gesture, restore press-time selection membership **and order** when canceling a gesture; no edit. Escape with no interaction is unhandled. |
| Document revision/track replacement | Cancel stale captures before building the next scene; never retarget a captured note set. Bank/context changes do not silently replace already frozen per-note maps. |
| Detent toggle | Cancel the gesture, change preference, rebuild the affected axis/handles, no history entry. |

`dispatchPointer*`, `beginGesture`, `finishGesture`, `setSelection`, `updateBandPreview` etc. stop being mutable Page-extension methods. Their decisions become reducer cases/pure helpers. Qt public methods stay in the class body and do only decode/send/return. `commitVelocities` becomes the effect executor calling the existing `SongDocument.setVelocities` operation.

Maintain synchronous method semantics: pointer consumption, prompt acceptance and document mutation are not interchangeable booleans. Velocity’s accepted no-op and Automation’s committed/no-op return conventions must be represented explicitly in their domain transition/outcome types, rather than changing every wrapper to return `effects.isEmpty == false`.

### 4. What frozen and snapshot types become

- **Keep the concept of `VelocityFrozenNote`.** Value state does not eliminate temporal capture. A gesture still requires press-time note values, the exact per-note map and original velocity even when bank/hover/live facts change. Store this once in `VelocityEditGesture`, together with revision, track and frozen axis. Do not snapshot the entire page or document per gesture. Preserve exact-origin behavior; removing its representation is not a prerequisite for the refactor.
- **Delete `VelocityInteractionSnapshot`.** It copies fields the value state already exposes, and its initializer rebuilds the note-ID index (`VelocityScene.swift:20–52`). Let the pure scene read the gesture payload’s existing lookup directly. This removes a wrapper and a repeated index construction, not the required freeze.
- **Replace `VelocitySceneSnapshot` with `VelocityScene`.** A derived scene is still useful, but its rows become plain `VelocityHandleValue`, `DrawerRectValue`, `DrawerTextValue`, axis/readout/ramp values. It must contain no `VelocityHandle`, `SceneRect`, `SceneText`, `GridTypography`, session reference, or QVariant dictionary.
- **Remove `VelocitySceneInput`’s field-for-field interaction repackaging.** Build from the value state and an explicit measured typography input; keep a small distinct document-facts type because document sampling is genuinely a different seam.
- Apply the same distinction to Automation: keep revision-bound `AutomationFrozenFacts` and lane occupants, but remove parallel `gesture`/`frozen`/`frozenCamera` bookkeeping by placing one capture inside the associated gesture case. Derive preview points/text from that capture; do not store both the transaction and separately mutable preview truth.

### 5. Pure scenes and one publication pass

`DrawerSceneValues.swift` owns reusable plain rectangles/text rows and `DrawerTextMetrics`. Reuse the existing `GridFontSpec` rather than inventing a competing font specification; add value conformances where needed in `src/swift/app/timeline/GridTypography.swift`. QVariant font/rect maps are constructed only in the Qt adapter.

Native text measurement is a real external dependency. `VoiceCaption` currently owns an `OpaquePointer`, calls `sgf_advance`, and measures prefixes for elision; `AutomationCaption` does the same for caption widths. A pure builder cannot take those objects and still claim a portable seam. Preserve the measurement algorithm in the adapter, cache measured widths/extents (and needed prefix widths for voice-label elision), and feed immutable metrics to the builder. Pure checks use literal measured inputs; native font/raster checks remain native. Do not replace font measurements with guessed character widths.

Each Page has exactly one publication entry:

`publish(state)` → build/reuse pure scene → reconcile existing primitives and item models.

Its invariants:

1. The reducer never writes a Qt property and the publisher never changes domain state, selection, document, camera or audition state.
2. Compare primitive values before assignment. The inspected QtBridge macro emits property signals in `didSet` without an equality guard (`QtBridgeableMacro.swift:115–120`), so repeated equal assignments are not free.
3. Compare **plain row descriptors before allocating bridged rows**. Extend `QListModelSync.swift` with a value-row overload accepting previous plain rows and a row factory; keep the existing positional common-row/tail algorithm. Allocate and assign only changed rows; insert/remove only required ranges. Keep the `QListModel` instance stable.
4. Separate scalar equality from structural row changes. Changed hover/selection roles still need a `model[index]` write. Rows that appear/disappear require model insertion/removal signals. Never suppress those signals because all surviving scalar values are equal.
5. Do not introduce a generic keyed tree diff. Current `syncModel` is positional; unchanged rows at unchanged indexes remain untouched, but it does not promise persistent QML delegate identity across arbitrary middle insertions/reorders. Preserve that contract. Where a domain already reuses row handles by note/occurrence identity, the adapter may retain those handles, but pure scenes and hit tests never depend on them.
6. Stable semantic identity remains mandatory: Velocity `NoteID`; Voice exact occurrence; Automation parameter/tick/occurrence/value identity. Do not reduce automation identity to tick alone or deduplicate written collision occupants just because display rows do.
7. Publish dependent data before activation flags: prompt fields before opening; model rows before count/selection indexes that refer to them; focus target before focus revision. Closing/canceling happens synchronously. Qt primitive properties are not an atomic transaction; a single pass guarantees consistent ordering and no redundant writes, not an impossible atomic multi-property notification.
8. Maintain a dependency-keyed scene cache. Separate static content, camera projection, axis/handle interaction and readout/modal/overlay blocks. Same-context playhead ticks reuse static rows; hover reuses grid/bands; preview moves reuse font measurements; bank or font/DPR changes invalidate the appropriate geometry. Equality over the whole document/scene on every tick would replace one performance problem with another.

For effect reentrancy, the page’s synchronous send path installs reduced state before running effects. Use an outer-dispatch depth/coalescing guard so session callbacks can ingest current facts but only the outermost dispatch builds/publishes the final state. Do not hold an `inout state` borrow across effect execution. Never publish a saved pre-effect scene after a callback advanced state. Preserve synchronous return results; do not move commits/cancellation onto an asynchronous publisher scheduler. If Qt notifications cause an additional real input during publication, process it as a subsequent event/pass, not a mutation hidden inside the current diff.

### 6. Voice Changes: same shape, with occurrence and audition policy retained

`VoiceChangesState` owns typed events, current lane/bank/view facts, selected/hovered occurrence, a pointer mode (`idle`, pending/active drag, pan), modal mode (`none`, picker, menu) and auditioned program. Preserve the current behavior instead of forcing every domain into Velocity’s selection model:

- Gutter press does not edit.
- A press while picker/menu is open dismisses it and starts **nothing**; no retargeting through the dismissing click (`VoiceChangesInteraction.swift:60–67`).
- Left marker press captures exact occurrence; horizontal slop activates the drag; live Alt controls fine snap; release drafts one `VoiceLaneMutation`.
- Right press captures menu target before any signal-producing step; double-click captures picker target.
- Filter/navigation select among current bank rows without changing the frozen target. Bank updates re-resolve available rows, not the occurrence.
- Blank/unparsed bank slots remain selectable if present; do not “validate them away.”
- Audition becomes ordered effects `.audition(program, key:60, velocity:112)` / release with velocity zero. Release the previous voice before changing program, filtering it out, replacing the bank/callback owner, closing or detaching. Audio remains owned by the existing callback, not the reducer.
- Hit tests consume pure marker geometry. Preserve label stair/elision behavior in the scene and native measurement adapter.

`VoiceChangesTransactions` continues drafting `.move/.replace/.insert/.delete`; an adapter applies them through the same existing SongDocument operations. Do not add a second history abstraction.

### 7. Automation: explicit aggregate state, retained domain subreducers

`AutomationState` stores value document/catalog facts, active parameter, ghost pins, lane display ranges, explicit selection, pencil/focus inputs, hover, one pointer state, one modal state and tap session. Do not retain parallel `gesture`, `band`, `panActive`, `frozen`, `frozenCamera` fields.

Use `AutomationPointerState` cases:

- `.idle`
- `.node(AutomationNodeDragTransaction, capture/projection)`
- `.phantom(AutomationPhantomDragTransaction, capture/projection)`
- `.pencil(AutomationPencilTransaction, capture/projection)`
- `.sweep(AutomationSweepTransaction, capture/projection)`; the existing `.drag/.ramp` distinction stays in the transaction
- `.pendingBand(AutomationRangeBand)` / `.band(AutomationRangeBand)`
- `.pan(previousX)`

`AutomationInteraction.reduce` preserves the actual transition rules:

- Left press chooses visible node, origin phantom, pencil cell or background sweep according to the existing precedence and pencil-cell containment checks (`AutomationInteraction.swift:163–217`).
- Node motion uses the existing pending → reset → dragging phases, not a simple threshold boolean (`AutomationTransactions.swift:112–141`). Live Shift lock is retained; releasing Shift removes the lock according to current policy.
- Stationary node release deletes when allowed; Shift suppresses that delete. A phantom only commits a changed, activated value drag; a stationary phantom is **not** an insertion (`AutomationNodeTransactions.swift:193–213`).
- Pencil/sweep motion updates pure draft state. Sweep drag below slop parks the edit cursor at release instead of writing a lane; ramp is armed from press.
- Right press captures range anchor and inside-selection status. Movement reaches band at Manhattan threshold. Active right release sets/clears the range; stationary release opens the point menu if there is a hit, or the range menu if the press was inside selection. A stationary background miss is a no-op here; lane menus come from the parameter selector. Do not adopt the scout’s incorrect “otherwise lane menu” interpretation.
- Pan ends when the move’s middle-button mask is absent, unlike Velocity. Camera deltas remain session effects.
- Gesture mapping stays tied to its press-time camera/projection; live camera refresh may re-render content without remapping the gesture.

`AutomationModal` becomes value menu/prompt/confirmation policy and a modal subreducer; menu rows are `AutomationMenuRowValue`, not bridged handles. `AutomationSelectionCommands` becomes semantic command planning over supplied values plus effects. Retain the canonical command priority and clipboard implementations. In particular, do **not** impose a universal one-undo-entry rule: `consumeSelectionCommand(.loopFromSelection)` intentionally makes two loop edits (`AutomationSelectionCommands.swift:43–46`).

Keep `AutomationCommit.apply` as the final revision/unchanged gate for ordinary lane/plan commits. Keep captured range/point collision semantics. The effect adapter gathers native clipboard data once at the event seam and passes decoded values into planning; it uses existing `ClipboardCodec`/`ClipboardSemantics` rather than reimplementing them.

Move the pure `AutomationTapTempoSession` into State and its clock read into the Qt seam. `.tap(nowMilliseconds:)` and `.tapIdleElapsed` are reducer events; the existing QML timer/published `tapTempoIdleCommitMs` contract stays. Do not add a framework timer or a second playback clock. Preserve revision/parameter guard and tick-zero tempo commit semantics.

### 8. EditorDrawer: keep the existing module, make its value claim true

Keep the existing three container files; do not build a second presenter/store/scene hierarchy.

- `EditorDrawerPresenter` owns the attached `EditorDrawerPage` instances in fixed kind slots. It validates same-instance detach and URL acceptance, and reads body policies synchronously.
- `EditorDrawerTypes.swift` gains `EditorDrawerEvent` and plain `EditorDrawerPageFacts` (resolved URL, preferred height for current host/metrics, optional maximum). The preferred-height closure stays on the attached page and is evaluated by the presenter on every relevant layout pass; do not snapshot it only at attach.
- `EditorDrawerLayout` remains the state/policy value, with `reduce(event:) -> EditorDrawerChangeSet`. Remove `EditorDrawerPage` references and direct cancellation calls; availability and sizing use the supplied facts. Remove `@MainActor` only after this value seam has no actor-owned references.
- Reuse `EditorDrawerSnapshot`, section geometry, metrics, preference records and focus request value types. Their shapes already fit.
- Reuse `resolveSnapshot` and `resolveResize` algorithms, changing page-policy reads to fact reads, not rewriting the rules.
- `cancelledSections` becomes an actual ordered effect list. The presenter executes it while the **old published layout is still visible**, then applies the new snapshot, preference signals, and focus target/revision. Detach must keep the page retained through its cancellation call.
- Aggregate `interactionActive` remains a synchronous presenter read of resize state plus attached-page interaction; do not cache page activity in the pure layout or subscribe to a second observation system.
- Combine the metrics/host configure input into one event/pass instead of today’s two `publish(layout.configure…)` calls. Apply scalar equality guards in the presenter; section `apply` already has them.

Required retained rules: stack order Velocity → Voice → Automation; fixed toggle slots; host clamp allocates Voice first, Automation second, Velocity remainder; Voice→Automation spill only under its existing visibility/maximum conditions; returning resize to its start restores the original nil stored-height marker; canceled resize keeps applied heights but writes no preference; restored preferences do not write back; focus only requests a visible/available target, otherwise the roll.

## Framework comparison

### Recommendation: no added framework; a small synchronous send function per page

All candidates still require the domain reducer, frozen transaction types, pure scene values, Qt class-body properties, scalar comparison and structural QListModel reconciliation. Their useful replacement here would mainly be **event delivery and observing changed state**, which the page’s synchronous `send`/single publisher already handles. QML already performs reactive binding. None turns a Swift struct into the required QML interface.

| Option | Cross-platform evidence | What it could replace | Why it does not win here |
|---|---|---|---|
| **OpenCombine** | [README](https://github.com/OpenCombine/OpenCombine/blob/master/README.md) explicitly targets macOS/Linux/Windows; [manifest](https://github.com/OpenCombine/OpenCombine/blob/master/Package.swift) includes Windows and a C++ helper target; [Windows CI](https://github.com/OpenCombine/OpenCombine/blob/master/.github/workflows/windows.yml) inspected uses standard Swift 5.4.2–5.7.2 Windows toolchains. [Helper source](https://github.com/OpenCombine/OpenCombine/blob/master/Sources/COpenCombineHelpers/COpenCombineHelpers.cpp) has pthread/std::mutex and Windows handling. | Subject/scan/state delivery, deduplication, subscriptions; Dispatch/Foundation scheduling if added. | Strongest candidate if future cross-platform stream composition is actually needed, but inspected evidence does not certify this Swift 6 + MinGW build. It adds module/library/C++ helper integration and cancellation lifetime management without replacing the difficult layers. Avoid OpenCombineShim switching implementations by platform. |
| **ReactiveSwift** | [README](https://github.com/ReactiveCocoa/ReactiveSwift/blob/master/README.md) documents Apple platforms and Linux, not required Windows/MinGW; [manifest](https://github.com/ReactiveCocoa/ReactiveSwift/blob/master/Package.swift) is SwiftPM/Swift 5; [Atomic.swift](https://github.com/ReactiveCocoa/ReactiveSwift/blob/master/Sources/Atomic.swift) uses a pthread fallback outside Apple. | Signal/Property delivery and lifetime management. | Windows/MinGW is unverified, not proven impossible. No Qt binding advantage; `Property<State>` plus published Qt properties still means two observation mechanisms and the same flattening adapter. |
| **RxSwift / RxRelay** | [README](https://github.com/ReactiveX/RxSwift/blob/main/README.md) documents Apple/Linux; [manifest](https://github.com/ReactiveX/RxSwift/blob/main/Package.swift) excludes RxCocoa off Darwin and has no declared Windows support contract. Core [lock implementation](https://github.com/ReactiveX/RxSwift/blob/main/Platform/RecursiveLock.swift) uses Foundation NSRecursiveLock. | Observable/relay event composition, scan/distinct and disposables. | RxCocoa is not a Qt adapter and is unavailable off Darwin. Core portability to this Windows stack needs verification. RxTest tests streams, not the existing gesture/projection algorithms. More lifetime/scheduler concepts than this state flow needs. |
| **Domain-local hand-written send/reduce/build/publish** | Uses the project’s existing Swift value types and QtBridge; no additional runtime/package dependency. | Replaces dispatch/publication orchestration directly. | Best match for synchronous cancel, return values, revision-guarded effects and QML. Keep it local and boring, not a homemade Combine. |

The current build is more specifically CMake-led than “an app SwiftPM package”: `PorydawApp` is an explicit CMake static target, `cmake/QtBridge.cmake` pins/fetches QtBridge, and QtBridge’s macro ExternalProject reads the SwiftSyntax version from Package.swift then builds its CMake targets (`build/_deps/qtbridge-src/Sources/QtBridgeMacros/CMakeLists.txt`). Adding a library is not just appending a product to an existing application Package.swift. It requires target/module/search-path/link/runtime handling on all shipping toolchains or introducing another package-build stage. Since no framework is selected, no dependency/build-framework change belongs in this plan.

## Sequence and dependencies

These are behavioral migration units, not one-file extraction chores. Use the existing SDD-track for each state/publication migration because it changes ownership and effect ordering; the source-list-only updates remain part of their owning task.

### 1. Velocity value-scene and publication seam

**Write set:** new `drawer/DrawerInput.swift`, new `drawer/DrawerSceneValues.swift`; `velocity/VelocityPage.swift`, `VelocityScene.swift`, `VelocitySceneValues.swift`, `VelocityProjection.swift`, `VelocityPublication.swift`; `src/swift/app/QListModelSync.swift`; `src/swift/app/timeline/GridTypography.swift`; production CMake list; affected Velocity projection checks in `src/checks/drawerpresentation/velocity.swift` and `src/checks/velocity/VelocityPageChecks.swift`.

Produce plain `VelocityScene`/row descriptors; make hit testing use those values; separate native metrics; centralize publishing while retaining old behavior. Delete obsolete scene/publication/projection wrappers when their callers migrate. Test model no-op/structural updates through the real QListModel adapter, not source-text assertions. This establishes contracts consumed by all later domains.

**Acceptance:** command V1 below; pure build predicates for geometry, selected/hovered rows, camera projection and transient values; native command V2 for published surface/model behavior. Preserve no-static-rebuild on same-context playhead updates.

### 2. Velocity reducer and exact click correspondence

**Prerequisite:** Task 1 scene/input/publication contracts.

**Write set:** new `velocity/VelocityState.swift`; `VelocityPage.swift`, `VelocityTransactions.swift`, `VelocityScene.swift`; remove `VelocityInteraction.swift`; `src/checks/velocity/velocitydetentdragging.swift`, `tst_velocityediting.swift`, `VelocityPageChecks.swift`; new `src/checks/velocity/velocityclicks.swift`; `src/checks/velocity/proof.velocityclicks.txt` and proof ledgers whose changed counterpart hashes must be refreshed; production/check CMake source lists.

Migrate all six gesture cases, prompt, cancel, refresh and effects at once. Existing pure arithmetic checks keep their behavioral predicates against the new payload/reducer seam. New exact click cases use the original three-note stacked fixture and actual original event sequence. Retain real document/history/timeline adapter assertions for transaction obligations. Do not leave old dispatch or Qt-button aliases behind.

**Acceptance:** V1 + V2; original click-site predicates mapped individually; correct ruler-on-press commit; exact cancellation selection order; accepted no-op prompt latch; stale revision; equal publication; typed decode edge cases. Checkpoint the accepted Velocity/shared seam before later work reuses these files.

### 3. Container purity and Voice Changes migration, independently owned

These can proceed independently after Task 2 because their only shared dependency is the stable value-row/input contract. One integration owner owns later edits to shared helpers/CMake.

**Container write set:** `EditorDrawer.swift`, `EditorDrawerTypes.swift`, `EditorDrawerLayout.swift`; `src/checks/drawerpresentation/EditorDrawerChecks.swift`, `drawer_basics.swift`, `drawer_resize.swift`, `drawer_state.swift`, `proof.drawer.txt`; check-only `src/checks/editorqml/DrawerTestPage.swift` if its fixture interface changes. Existing production QML stays unchanged.

Convert stub-page-dependent layout predicates to plain page facts/effect assertions; retain real presenter cancellation-before-publish checks. Acceptance V1, V2, and V3’s keyboard test. Do not remove native focus/loader/pointer assertions.

**Voice write set:** all seven existing `voicechanges/*.swift` files, adding `VoiceChangesState.swift` and `VoiceChangesPresentation.swift` and removing the three obsolete files described above; `src/checks/drawerpresentation/VoiceChangesPageChecks.swift`, `voice_projection.swift`, `voice_picker.swift`, `voice_interaction.swift`, `voice_lifecycle.swift`, `voicemenus.swift`, `proof.voice.txt`, `proof.voicemenus.txt`; production/check CMake lists. Keep `DocumentWorkspace` callback and attachment interfaces unchanged.

Acceptance V1 + V2 + V3 voice case; exact occurrence refusal, dismissal no-retarget, bank/filter updates, fine-snap modifiers, preview-only movement and audition stop ordering. Checkpoint the accepted container/voice milestone before shared-file reuse.

### 4. Automation value scene and single Qt publication

**Prerequisite:** stable shared descriptor/model contract.

**Write set:** `AutomationPage.swift`, `AutomationScene.swift`, `AutomationHandles.swift`, `AutomationContentPublication.swift`, `AutomationOverlayPublication.swift`, `AutomationLifecycle.swift`, `AutomationProjectionCache.swift`, `AutomationTransactions.swift`; new `AutomationPublication.swift`; existing automation projection/presentation checks (`src/checks/automation/domain/tst_automationdomain.swift`, `presentation/tst_automationpresentation.swift`, `presentation/painting.swift`, `automationcanvaslayout.swift`), corresponding proof headers; production CMake list.

Move session snapshot extraction/cache to the adapter; make scene build consume values. Move content/overlay calculations into pure scene construction and all Qt writes into one publication pass. Replace menu/handle snapshot references with values where needed. Preserve projection cache keys, hovered-node role notifications and structural menu child updates. Remove replaced publication/lifecycle/cache files only after their callers migrate.

**Acceptance:** V1 + V2 + V3 automation hover case. Equal hover/raster stability, active/ghost curve order, scale/grid and node visibility, model-count changes, readout-only playhead path.

### 5. Automation reducer/effect cutover

**Prerequisite:** Task 4 pure scene and publication contract.

**Write set:** new `AutomationState.swift`; `AutomationPage.swift`, `AutomationInteraction.swift`, `AutomationModal.swift`, `AutomationSelectionCommands.swift`, `AutomationTransactions.swift`, `AutomationTapTempo.swift`, `AutomationScene.swift`; remove `AutomationTapTempo.swift` after relocating pure ring/clock roles; affected existing checks `AutomationPageChecks.swift`, `automationactions.swift`, `automationcanvasediting.swift`, `automationclipboard.swift`, `automationmenus.swift`, `automationpointmenus.swift`, `automationselection.swift`, `automationtaptempo.swift`, `domain/gestures.swift`, `domain/xcmd.swift`, `tst_automationediting.swift`; their corresponding proof ledgers; production/check CMake lists. `AutomationDrawingTransactions`, `AutomationNodeTransactions`, `AutomationEdits`, `AutomationParameter`, `AutomationProjection`, `AutomationLaneProjection` retain their policy algorithms; only type/reference adjustments demanded by the new owner are permitted.

Replace Page-extension mutations with the top reducer and pure gesture/modal/selection subreducers. Route writable `plotFocused`/`isPencilMode` through typed events while retaining their Qt surface. Keep clipboard, camera, cursor, audio and document effects at the adapter. Eliminate parallel frozen/preview truth. Preserve consumed-versus-written outcomes and the intentional two-edit loop command exception.

**Acceptance:** V1 + V2 + V3. Matrix includes stationary node delete/Shift suppression; phantom no-op; slop reset; live modifiers; cross-lane shared delta and collision occupants; pencil/ramp/sweep tail restoration; captured menus/confirmation; selection command priority; tap timing and stale guards. Checkpoint the integrated architecture.

### 6. Incremental proof conversion through the new seam

Do this alongside each domain, not as a requirement to port all ~3,572 GAP sites before accepting the architectural refactor. After Velocity’s three exact click sequences prove the method, convert proof files in coherent behavior groups: hit/selection; relative/detent/paint/ramp; voice occurrence/modal; container sizing; automation drawing/node/cross-lane; automation modal/clipboard/tap.

Per proof group: preserve pinned C++ source/context/rows/loops; implement exact predicate sequence; identify which assertions are pure state/scene, actual document effects, or native setup/render/input; run the corresponding commands; then update that group’s counterpart hashes/dispositions with evidence. Never bulk-mark an entire C++ method MATCHED because a similarly named Swift scenario passes. Do not delete original C++ checks on the strength of a rewritten proof inventory.

## Proof portability: concrete Velocity example

`src/checks/velocity/proof.velocityclicks.txt:13–24` defines MATCHED/PARTIAL/GAP/NATIVE-SETUP and explicitly says unresolved entries do not authorize removing native checks. It pins full source hashes, event setup, helper assertions and source-order context—not just method names.

For `blankClickDeselectsOnRelease` (`velocityclicks.cpp:32–61`):

- A001/A005: pure reducer setup/press preserve the ordered selected note IDs.
- A002/A003: pure scene geometry proves the blank point is in the plot and beyond the last stem.
- A006: release clears selection; the emitted effects contain selection change and **no** velocity mutation.
- A007 onward document revision/history/document-vs-timeline values: keep an in-memory real document/effect-runner check. “No commit effect” is useful but not alone proof that the actual adapter records no history.
- A004 mouse-grabber ownership is native input correspondence. It cannot be replaced by `transition.consumed == true`; keep it native/unresolved until real pointer evidence exists.

For `graduationClickEditsSelectedNotes` (`velocityclicks.cpp:64–115`), exact predicates include values becoming 127 **between press and release**, unchanged later note, selection retention, and one history change. For `clickBelowSelectedNodeChangesOnlySelection` (`velocityclicks.cpp:117–156`), do not trust the method’s name: it actually expects a preview of 40 on press and a committed velocity/history change on release for the selected loud note, with the quiet/later notes untouched. This is exactly why whole assertion sequences—not method labels—must drive migration.

Plain reducer/scene tests can use `Note`, `LanePoint`, `VelocityMap`, camera/axis values, ordered IDs and literal text metrics without QQuickWindow, QML, ProjectService, parsed bank leases, event-loop polling or QTest fixtures. Real document mutation tests still need SongDocument and history; native loader/focus/pointer/render/font predicates remain native. Do not promise all GAPs become pure tests or that GAP count equals independent behavior count.

## Edge cases and error conditions

- Preserve changed-button versus held-buttons; unknown surfaces/buttons; Control+Shift exact unlock versus Control+Alt/Meta; live automation modifiers.
- Zero/non-finite body dimensions and DPR/font sanitization retain existing behavior. Do not generalize unrelated pointer rejection behavior while refactoring.
- Ordered selection restoration, duplicate notes at the same tick, circle-versus-stem priority, selected-first hit preference and later-row tie-breaks remain intact.
- No track/no session, blank bank slot, unresolved/split-key maps and stale revision are distinct states, not generic disabled flags.
- Selection can change during a press before the edit captures axis/map; a pure reducer must model that order deliberately.
- A frozen transaction’s map/camera/occupants do not become live merely because the outer state is a struct.
- Voice bank refresh may invalidate audition/filtered selection but must not retarget a frozen occurrence.
- Automation display deduplication and written occurrence identity are different; collision plans must retain all frozen source occupants.
- Preserve prompt accepted-no-op versus mutation failure/unchanged; menu consumed-no-op versus false refusal; clipboard paste cursor outcomes.
- Do not turn every operation into one history entry: the existing loop-from-selection command intentionally records two.
- QListModel length/reorder changes and model-role notification require explicit model operations; primitive diffing is insufficient.
- Native font metrics cannot be silently guessed to make the scene “pure.”
- Synchronous cancellation must complete before hide/detach publication and before the document/audio owner retires.
- Session/camera callbacks can re-enter dispatch; no stale post-effect scene, exclusivity conflict, asynchronous cancellation, or duplicate commit.
- Published property writes can re-enter QML; a single pass is ordered, not atomically observable across all properties.

## Verification

No builds/tests were run for this read-only planning assignment. The following commands were selected from actual registrations and source; they are the implementation acceptance commands, not claimed execution results.

**V1 — Swift state/scene and real document effects:**

`deno task verify --filter=swiftcore --verbose --qt projectSession`

`SwiftCoreTest::projectSession` dispatches the session suite; `SessionChecks.swift:424`, `1052–1054` invokes the container and all three drawer check groups. New pure cases can initially run under this existing entry without native window setup, even though the harness itself is Qt-hosted. Do not claim this is already a cross-platform standalone Swift test target.

**V2 — existing actual QML drawer surface:**

`deno task verify:qml --verbose`

Covers the production and container lanes, including hosted stacking, resize clamp/cancellation, Voice→Automation spill, focus/page cancellation, preferences, numeric modal/shortcut ordering, shared playhead and interaction follow suspension. Relevant existing functions are in `src/checks/editorqml/tst_EditorDrawer.qml:798–1770` and modal cases near the beginning. Use native desktop access; this is not replaced by pure checks.

**V3 — focused production raster/real-input parity:**

`deno task verify --filter=swiftrollgated --verbose --qt drawerAutomationHoverRaster drawerVoicePreviewTransaction drawerGripKeyboardIsolation`

Source `src/checks/swiftrollgated/drawerparity.cpp:159–405` tests rendered automation hover stability, voice preview/commit/Escape/undo raster, and drawer grip keyboard isolation. These cases do not prove every legacy Velocity mouse-grabber assertion; those remain explicit native obligations in their ledgers.

**Final settled-tree build and integrated check:**

`deno task build:app`

`deno task verify --filter=swiftcore --verbose`

Run final controller-owned checks once on the settled integrated tree, not parallel with ongoing edits. Cross-platform build acceptance for any newly introduced dependency would require the same source and effect/decode smoke scenarios on the actual Linux and Windows/MinGW toolchains. The selected no-dependency architecture avoids adding that risk, but do not label a macOS-only run as cross-platform proof.

Add narrowly targeted behavioral checks for the new uncertain seams: exact input decode, nested session callback ordering, changed-row data notification plus insertion/removal, equality no-op, cancel-before-publish, and native-measurement/value-scene agreement. Do not add tests that merely assert enum fields were copied or that a wrapper forwarded its arguments.

## Honest simplification and estimated size

These are **estimates**, not promised output counts. Keep existing explanatory comments that capture real domain invariants; cut duplicated ownership/forwarding narration and field-copy machinery instead.

| Area | Measured now | Estimated target | Estimated reduction |
|---|---:|---:|---:|
| Velocity | 9 files / 2,859 L | 6 files / 2,200–2,400 L | 459–659 L |
| Voice Changes | 7 files / 2,533 L | 6 files / 2,000–2,200 L | 333–533 L |
| Automation | 18 files / 5,970 L | 15 files / 4,800–5,250 L | 720–1,170 L |
| Root/container/shared | 4 files / 1,099 L | 6 files / 1,150–1,350 L | grows 51–251 L to pay for shared seams |
| **Drawer total** | **38 / 12,461 L** | **33 / 10,150–11,200 L** | **~1,260–2,310 L (~10–19%)** |

Small changes outside the directory (`QListModelSync`, font value conformances, CMake source lists) are additional; do not hide them in the drawer saving. Pure test fixtures should shrink materially, but no numeric test-line saving is supportable until exact proof groups are translated.

What does **not** simplify away:

- QtBridge member pinning. The inspected macro requires a class and traverses `classDecl.memberBlock.members` (`QtBridgeableMacro.swift:324–365`); class-body published members and callable Qt methods remain. Swift stored properties cannot move into extensions. A framework property wrapper does not remove this constraint.
- The actual supported Qt surface includes primitive scalars, string lists, QVariant maps, QListModel/QTableModel and explicitly tracked bridged objects—not arbitrary Swift structs (`QtBridgeMacros/Extensions.swift:113–202`). Scene flattening remains necessary.
- Model structural notifications, native text measurement, QML focus/grab/modal/loader behavior and real rendering remain adapter/native concerns.
- Temporal freezes, revision guards, exact occurrence identities, PSG maps, snap lattices, collision plans, selection scope, tap tempo and undo semantics remain domain complexity.
- Derived scene values add a deliberate representation. Their benefit is eliminating QObject construction from policy/tests and removing ad-hoc repackaging/publication paths—not claiming that every value can have one physical representation from reducer to QML.

The main gain is locality: an implementer can inspect state transitions, value output and semantic effects without reading page extensions, Qt models, a session fixture and publication side paths to understand one click. The line/file reduction is useful but secondary to that deeper test seam.

## Critical files for implementation

1. `src/swift/app/drawer/EditorDrawer.swift` — current page protocol, Qt class-body members, presenter publication/focus ordering.
2. `src/swift/app/drawer/EditorDrawerLayout.swift:32–117,245–315,329–456,526–531` and `EditorDrawerTypes.swift` — reference retention/cancellation, layout/spill, value change records.
3. `src/swift/app/drawer/velocity/VelocityPage.swift:137–488` — input/lifecycle/publication contract and caches.
4. `src/swift/app/drawer/velocity/VelocityInteraction.swift:35–240,244–497` — all six current gesture branches, prompt, selection restore and effects.
5. `src/swift/app/drawer/velocity/VelocityScene.swift:20–52,112–336`, `VelocitySceneValues.swift:18–309`, `VelocityProjection.swift:45–83`, `VelocityPublication.swift:23–327` — the current Qt-coupled scene seam and duplicated apply paths.
6. `src/swift/app/drawer/velocity/VelocityTransactions.swift` — frozen values, arithmetic, prompt policy to preserve.
7. `src/swift/app/drawer/voicechanges/VoiceChangesInteraction.swift`, `VoiceChangesProjection.swift:82–174,388–528`, `VoiceChangesPublication.swift:188–196,251–296`, `VoiceChangesTransactions.swift` — capture, picker/audio effects, native font and item-role notification seams.
8. `src/swift/app/drawer/automation/AutomationPage.swift:110–118,300–490`, `AutomationInteraction.swift:163–320,508–695`, `AutomationLifecycle.swift`, `AutomationScene.swift:35–106` — current aggregate state and non-pure scene/rebuild flow.
9. `src/swift/app/drawer/automation/AutomationTransactions.swift`, `AutomationNodeTransactions.swift`, `AutomationDrawingTransactions.swift`, `AutomationEdits.swift:359–412`, `AutomationSelectionCommands.swift` — irreducible rules and semantic mutation owners.
10. `src/swift/app/QListModelSync.swift`, `src/swift/app/roll/GridScene.swift:1–76`, `src/swift/app/timeline/GridTypography.swift` — existing bridge row/model/font conventions.
11. `src/swift/app/DocumentSession.swift:139–145,217–232`, `DocumentWorkspace.swift:221–274` — synchronous effect/refresh fanout.
12. `src/checks/velocity/proof.velocityclicks.txt`, `velocityclicks.cpp`, `VelocityPageChecks.swift`, `tst_velocityediting.swift` — exact oracle format versus current related-but-not-exact fixtures.
13. `src/checks/CMakeLists.txt`, `src/checks/checkcatalog.cpp:154–181`, `src/checks/workspace/SessionChecks.swift:424,1052–1054`, `tools/checks_options.ts:8–27` — registration and exact verification routes.
14. `cmake/QtBridge.cmake`; pinned downloaded `QtBridgeableMacro.swift`, `Extensions.swift`, `QListModel.swift` — directly verified registration/type/notification constraints. Do not rely only on explanatory comments in Page files.

### Inspection provenance

Three independent scout investigations were used to discover automation, voice and container/check slices. All architectural claims above were then checked against the actual source by the plan author. In particular, the report corrects scout misstatements about the container being pure, Automation line counts, stationary phantom insertion and stationary background lane-menu behavior. No file was changed and no state-changing validation command was executed.