# Context

Task 71 — automation command long tail. Close the nine sprint-3 §6 backlog
ledgers (137 open rows, re-censused by awk this freeze: routing 33, voice 31,
actions 17, tst_automationediting 22, menus 12, clipboard 7, stroke 7,
pointmenus 2, canvasediting 6 — counts match the backlog exactly) against the
mounted automation drawer surface (`AutomationPage` + `AutomationPage.qml`),
then delete whichever ledgers reach zero open rows with their C++ sources.
Proof completion + ledger closure; production behavior lands only where a new
predicate exposes a real divergence.

1. **Census (awk over `Disposition:` lines, verified this freeze)**:
   - `proof.automationrouting.txt` — 3 GAP + 30 PARTIAL. Families:
     mid-gesture isolation (view `userGestureActive` A005/A011/A025/A061;
     band-preview lane membership A006/A012/A044/A063/A070/A079; document
     freeze A019/A028/A032/A045; cursor stability A021/A030/A034/A047/A060/A073;
     pan/pencil/body negations A026/A043/A062/A069/A078; second-lane isolation
     A054–A058); native input-delivery GAPs A013/A040/A086.
   - `proof.automationvoice.txt` — 21 GAP + 10 PARTIAL. Retired
     `AutomationCanvas` voice-row bounds/`pan.valid` GAPs (production is the
     `VoiceChangesPage` task-60 landed); native cursor-shape/scene-layer/grab
     GAPs; band-aftermath PARTIALs (A028/A044/A061/A079/A100/A107/A132);
     revision/history-depth PARTIALs (A054–A056).
   - `proof.automationactions.txt` — 6 GAP + 11 PARTIAL. Rendered row-handle
     guards (A022/A029/A030/A041/A046/A069), activateParameter returns
     (A023/A047), native QQuickItem geometry GAPs (A024/A031/A035/A038/A039),
     auto-repeat pair (A015), second-row kind (A037), exact round-trip (A040),
     held-key pointer half (A025).
   - `proof.tst_automationediting.txt` — 1 GAP + 21 PARTIAL. Scene-graph
     transient-layer rows (A005/A006/A036/A037/A041/A042/A046/A047), C++
     `undoStack` count/index rows (A013/A014/A058/A059), playback-timeline
     CC re-reads (A018/A019/A024/A025/A030/A031), blank-tick rows
     (A052/A064), row-handle row (A069), native bounds GAP (A051).
   - `proof.automationmenus.txt` — 12 PARTIAL (Original-line rows, no A-ids):
     rendered right-press delivery, `clickMenuRow` clicks, rendered-tab label
     activation, rendered submenu-model ownership. Document outcomes already
     MATCHED through `consumeMenuAction`.
   - `proof.automationclipboard.txt` — 7 PARTIAL (A003/A004/A006/A011/A012/
     A014/A015): same rendered menu-row click-delivery pattern over the
     tempo/CC copy/paste journey.
   - `proof.automationstroke.txt` — 7 PARTIAL (A004/A005/A036/A037/A061/A062/
     A069): slop positivity, pencil-mode flag, per-sample ±1 tolerance,
     sparse/dense density invariance, freehand end-value tolerance.
   - `proof.automationpointmenus.txt` — 2 PARTIAL (A131 stale-journey
     rendered Delete row; A181 survival-journey no-prompt tail).
   - `proof.automationcanvasediting.txt` — 3 GAP + 3 PARTIAL. Native
     delivery/grab GAPs (A002/A026/A027); left-press time-selection clear
     (A006); Escape-clear selection re-reads (A019/A020).
2. **Fork laws** (`git show <ledger Reference revision>:<Original path>`;
   routing/voice/stroke pin `c17d966f`, the other six pin `f3069ef6`):
   isolation = press-then-verify-frozen (`frozenDocumentState`,
   `editCursorTick`, per-lane `lanePoints`, `tempoPoints`); stroke density
   invariance = sparse and dense runs commit identical points within ±1 of
   the requested sample; menus/clipboard = right-press opens, real row click
   consumes, document shows the effect.
3. **Swift current state — all needed state is already published**:
   `AutomationPage.swift:231-240` publishes `hasBand`, `isPanning`,
   `frozenRevision`, `menuRowActions`; `:274` publishes `documentRevision`;
   `AutomationProjection.swift:48` publishes `nodeDragActivationDistance`
   (base-font sized, positive by construction); `AutomationCommit`
   revalidates every route against the frozen revision. No `userGestureActive`
   flag, no rendered row handles, no `undoStack` counter, no scene-graph
   transient layer exist in Swift — rows pinning those pin the retired C++
   view/harness, not behavior. Tasks 55/56/57/60 landed; their S rows are the
   consumed contract (see Prerequisites).
4. **Classification summary**: behavior ~55 (isolation predicates, stroke
   tolerance/density, blank-tick, second-row kind, exact round-trip,
   menu/clipboard QML click delivery, Escape-clear re-reads, pointmenu tails,
   voice band aftermath); representation ~60 (QQuickItem bounds, cursor
   shapes, `mouseGrabberItem`, scene-layer revisions/rects, rendered row
   handles, `undoStack` count/index, `userGestureActive`, `activateParameter`
   rendered-tab returns, auto-repeat synthesis); blocked ~6 (playback-timeline
   CC re-reads — no Swift timeline accessor identified) plus voice GAPs
   pending re-verification against task-60's landed rows.

# Exact write set

- `src/checks/automation/automationselection.swift` — gesture-isolation
  predicates: band-membership (`hasBand` + active parameter), mid-gesture
  document freeze (`documentRevision` vs `frozenRevision`), cursor stability,
  second-lane isolation over a two-lane fixture.
- `src/checks/automation/domain/gesturePencil.swift` — stroke predicates:
  slop positivity, pencil-mode flag, ±1 sample tolerance, sparse/dense
  invariance, freehand end-value tolerance.
- `src/checks/automation/tst_automationediting.swift` — blank-tick-no-point
  predicates; timeline CC rows resolved per the Blocked rule below.
- `src/checks/automation/automationactions.swift` — second-row-kind and
  exact round-trip predicates; A015 disposition only.
- `src/checks/automation/automationmenus.swift` + `automationclipboard.swift`
  — presenter halves already MATCHED; check-side drivers only if the QML
  probes need them.
- `src/checks/editorqml/tst_EditorDrawer.qml` — append-only rendered
  menu-row click probes (Clear/Range64/Copy/Paste journeys).
- `src/checks/drawerpresentation/voice_*.swift` — band-aftermath predicates
  only if `VoiceChangesPage` exposes an equivalent; otherwise no edit.
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  row flips only in the nine files censused above.
- Production Swift: contingent only — every behavior predicate reads
  already-published page state; no production file is named upfront.

No `src/project/` or `external/` changes, no new C++, no hot files
(`ShellWindow.qml`, `ShellPresenter.swift`, `ApplicationSession.swift`,
`DocumentWorkspace.swift`, `EditorSurface.qml`, `PianoGrid.swift`,
`tst_ShellWindow.qml` untouched).

# Prerequisites

- Serialize after task-65 (in flight; owns all hot files and
  `tst_ShellWindow.qml` — disjoint from this write set, controller orders 65
  first among shell work).
- Consumes landed contracts, not implementation detail: 55 (prompt/commit
  path), 56 (rendered geometry), 57 (gesture domain predicates this task
  extends), 60 (`VoiceChangesPage` predicates the voice GAPs re-verify
  against).

# Interface contract

- New check anchors (message-anchored, one per fork clause family; the
  `what:`/`message:` strings are the ledger anchors and stay verbatim once
  written):
  - isolation — "a pan press publishes its pan and no band"; "a pending band
    leaves the document revision and edit cursor untouched"; "a pencil press
    leaves the document revision and edit cursor untouched"; "a pencil stroke
    leaves the LFO, Volume, Voice, bend and tempo lanes untouched"; "a body
    press starts no pan and no band".
  - stroke — "the activation slop is positive"; "the stroke runs in pencil
    mode"; "sparse and dense strokes commit identical points within one of
    the requested value"; "the freehand end value is within one of the
    requested sample".
  - editing — "an unwritten tick holds no point".
  - actions — "the second published row is a ControlChange"; "value-at-y of
    y-of-64 is exactly 64".
  - menus/clipboard (QML probes) — "a real click on the published Clear row
    clears"; "a real click on the published Range64 row rescales and closes";
    "a real click on the published Copy row copies"; "a real click on the
    published Paste row pastes".
  - canvasediting — "a plain left press clears the time selection"; "Escape
    clears the selection and the rebuilt selection is empty".
  - pointmenus — "the stale journey renders no Delete row"; "the survival
    journey leaves no prompt visible".
- Representation dispositions (ledger agent; each fork-verified at the
  ledger's Reference revision): `RETIRED-REPRESENTATION` for QQuickItem
  bounds/delivery rows (routing A040/A086, actions A024/A031/A035/A038/A039,
  tst A051, canvas A002), cursor-shape rows (voice A014/A029/A039/A076/A101),
  `mouseGrabberItem` rows (voice A102/A103, canvas A026/A027), scene-layer
  rows (voice A011/A115, tst A005/A006/A036/A037/A041/A042/A046/A047),
  rendered row-handle rows (actions A022/A029/A030/A041/A046/A069, tst A069),
  `undoStack` count/index rows (tst A013/A014/A058/A059, voice A055/A056),
  `userGestureActive` rows (routing A005/A011/A025/A061), rendered-tab
  activation returns (actions A023/A047, menus Original 251/252/266/267
  activation halves, clipboard A003/A011/A014 session halves), auto-repeat
  synthesis (actions A015 — QTest cannot synthesize `isAutoRepeat`; the held-B
  latch itself stays proved by S031).
- Blocked (name the blocker, leave unchanged): tst
  A018/A019/A024/A025/A030/A031 stay PARTIAL — Blocked on the
  playback-timeline read boundary (no Swift accessor exposes the compiled
  timeline CC value); voice A001/A002/A032/A033/A045/A062/A063/A109/A110 stay
  GAP only if task-60's landed rows do not cover the input-item-exists guard,
  otherwise retire as representation with the guard's S-cite.
- Preservation contract: production behavior in `AutomationPage`,
  `AutomationInteraction`, `AutomationNodeTransactions`,
  `AutomationSelectionCommands`, `AutomationLaneProjection` is unchanged
  (contingent edits only if a new predicate exposes a real divergence —
  record RED→GREEN for that fix only); every existing check message in
  touched files stays verbatim.

# Implementation steps

1. Re-verify the voice GAP guards against task-60's landed S rows
   (`drawerpresentation/voice_*.swift` + `verify:qml` evidence); report which
   guards are already proved before writing any voice predicate.
2. `automationselection.swift`: mid-gesture freeze/cursor/band predicates per
   the contract, driving the production page (press → read
   `documentRevision`/`frozenRevision`/cursor/`hasBand` → release). Extend
   the pencil fixture with a second written lane for A054–A058; use real
   fixture data, never synthetic seams.
3. `gesturePencil.swift`: tolerance/density predicates over the production
   `AutomationPencilTransaction` path; slop positivity reads the production
   `nodeDragActivationDistance`.
4. `tst_automationediting.swift`: blank-tick predicates through the shared
   document accessor; leave the six timeline rows PARTIAL with the Blocked
   note if no Swift timeline accessor exists — never invent a seam.
5. `automationactions.swift`: second-row-kind predicate over the published
   row stack; exact round-trip predicate over the production projection.
6. `tst_EditorDrawer.qml` (append-only functions): rendered click probes for
   the Clear/Range64/Copy/Paste journeys against the mounted drawer; keep
   menu dismissal/close asserts with each probe.
7. Pointmenu tails + canvasediting Escape/left-press predicates per the
   contract; voice band-aftermath predicates only if the page exposes an
   equivalent, else retire.
8. Run the lanes below; the per-lane evidence JSONs under
   `build/proof-evidence/` feed the ledger agent.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — isolation, stroke,
  blank-tick, actions, pointmenu and canvasediting predicates plus
  automation/drawerpresentation regressions.
- `deno task verify:qml --verbose` — rendered menu-row click probes on the
  mounted drawer; no lane regresses against the pre-task run.
- `deno task proof check --executed` — every new anchor executes.
- Runtime prerequisite: macOS for the QML lane; native audio not required.

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions.
- One message-anchored predicate per fork clause; keyboard priority holds
  (no second dispatcher, synthetic forwarding, or focus memory — the QML
  probes deliver real clicks through the mounted scene, never synthesized
  key events).
- WCAG AA beats parity where they conflict; visual parity with the fork at
  each ledger's Reference revision; base-font sizing only.
- `tst_EditorDrawer.qml` additions are append-only functions; shared with no
  in-flight task after 55–60 landed, but re-snapshot the file at freeze.
- Implementers never edit ledgers; the controller delegates them to the
  ledger agent. Delete each of the nine ledgers with its C++ source only
  when every row is MATCHED or RETIRED-*; menus/clipboard/stroke/pointmenus/
  canvasediting are deletion candidates this task, routing/voice/actions/tst
  close only if their Blocked/GAP rows resolve per the contract.
- Swift owns settings — no preferences surface is involved; do not add one.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`, then `deno task proof sites --area
   automation` confirms the surviving open rows (expected: ≤6 Blocked
   timeline rows plus any voice GAPs task-60 did not cover).
2. Confirm `deno task verify --filter swiftcore` and `deno task verify:qml`
   are green at the settled tree; store-level smoke (headless): isolation
   predicates appear in `swiftcore` verbose output, click probes in the
   drawer lane output.
