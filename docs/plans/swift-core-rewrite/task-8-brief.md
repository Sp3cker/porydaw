# Task 8 — Direct piano-grid consumer, then stop

## Context

T7 is accepted and checkpointed at `97dc7fea` ("Checkpoint T7 acceptance fixes
and coverage boundaries"). The grid cutover this brief was written for is
**already implemented at that checkpoint**: the grid Swift sources compile into
`PorydawApp` beside `ApplicationSession`/`DocumentSession`, the grid is a direct
session consumer (`PianoGrid(session:)`, `ApplicationSession.gridPresenter()`,
QML `gridModel: appSession.gridPresenter()`), note/clipboard commands live in
`NoteCommands.swift`/`Clipboard.swift` on the two native clipboard calls, the old
feed/executor/band/mount sources and their modules are gone, and the retained
native suite drives the real `RewriteWindow` production surface.

Remaining T8 work is therefore **verification, coverage closure and obsolete-source
retirement**, not another architecture or conversion pass. Read the T7 records in
[plan.md](plan.md) before editing: the raster/Reticle evidence, the pre-deletion
battery and the native render comparison are the executed proof this task builds
on, and their limitations are already stated there.

Frozen native boundary (applies to this task and every task after it): existing
working native support stays. Only *deletions* and *minimal mechanical boundary
maintenance* (rename a symbol and migrate its callers, update an existing
assertion's bridge call, add a suite envelope value that mirrors the eleven
accepted ones) are allowed. No new C++ API, helper, controller, test driver,
test bootstrap, scenario suite or native responsibility without explicit user
approval. Do not rewrite working native support to change the language mix, do
not compensate for a missing capability with "one small C++ exception", and do
not claim a capability a local dependency does not have.

## Exact write set

Already present — completion/defect fixes only (no re-creation, no re-architecture):
- `src/swift/app/{ApplicationSession.swift,DocumentSession.swift,NoteCommands.swift,Clipboard.swift}`,
  the retained `src/ui/songview/quick/swiftroll/*.swift` grid sources, and their
  `PorydawApp` module membership (`src/swift/app/CMakeLists.txt`, `module.modulemap`).
- `src/app/{RewriteWindow.h,RewriteWindow.cpp}`, `src/app/native_host.h`
  (`pd_clipboard_write`/`pd_clipboard_read` are already declared at lines 15–16
  and implemented at `RewriteWindow.cpp:734–760`; `Clipboard.swift:572,579`
  already imports them). Only fix an observed defect here.
- `src/ui/songview/quick/swiftroll/{PianoRollCanvas.qml,TimelineQuickItem.qml}`
  and the retained QML root `SwiftRollOverlay.qml`.
- `src/checks/swiftrollgated/{tst_swiftrollgated.{h,cpp},gesturechecks.cpp,clipboardchecks.cpp,notevisuals.cpp,chromevisuals.cpp}`:
  mechanical updates to existing assertions only. The mode-gated bodies of the
  four catalog names (`swiftrollgated`, `swiftbandkeys`, `swiftqtml`,
  `selectionkey`) are the retained regression protection and stay green.
- `src/checks/support/corecheck/{core_check.h,tst_swiftcore.{h,cpp}}` and
  `src/checks/swiftcore/*.swift`: mechanical only — an existing suite value's
  assertion data may move; do not add per-operation C APIs or C++ domain drivers.
- `src/checks/{checkcatalog.cpp,CMakeLists.txt}`: only if an existing fixture list
  or source list must follow a deletion performed in this task.
- `docs/plans/swift-core-rewrite/plan.md`, `docs/plans/swift-core-rewrite/coverage-ledger.json`:
  T8 evidence, row status transitions and recorded dispositions.

Deletions (authorized here because they remove already-uncompiled obsolete
scaffolding; each requires the mapping check in step 2 first):
- `src/checks/swiftdocfeed/`, `src/checks/swiftcommands/` — the retired
  document-feed/command-feed transport checks. Delete once their meaningful cases
  are reconciled to executed Swift/retained-native cases; never keep token/pipe
  assertions as acceptance.
- Old uncompiled `src/checks/swiftbandkeys/`, `src/checks/swiftqtml/`,
  `src/checks/swiftrollbench/` sources: delete only when the case-by-case
  reconciliation records an executed replacement for every meaningful case in
  them. Otherwise keep them uncompiled and record the disposition; do not add a
  registration for them.
- The leftover empty directory `src/ui/songview/quick/swiftgrid/` and any
  remaining build/module/import references to the deleted `SgdDocument`,
  `SgcCommands`, `SgcKeys`, `SwiftGridSessionFeed`, `SwiftGridKeyFeed`.
- `TrackHeaders.swift` is retained unbuilt reference source (per plan.md): do not
  convert it and do not delete it.

Out of scope: any new C++/Qt test case, raster case, catalog name, QML test host,
benchmark harness or startup path, and any new QML feature compensating for absent
editor surfaces. The follow-on
[camera integration and drawer plan](../swift-editor-consumers/plan.md) owns the
next grid integration, then the drawer container and its QML verification lane
(`src/checks/editorqml/*`, `verify:qml`). Editor pages follow separately; do not
create, register or pre-empt those successors here.

## Prerequisites

T7 accepted, checkpointed and pushed at `97dc7fea`; the recorded T7 evidence in
[plan.md](plan.md) is the current baseline. The three grid raster slots and the
native render comparison are executed evidence, not claims to re-derive. No new
bridge capability is assumed: `swiftcore` and the four windowed grid names are the
only entries this task runs, exactly as registered in `src/checks/checkcatalog.cpp`
(`:146` static swiftcore with the `rich` fixture list; `:158` the four windowed
names with `PORYDAW_AUDIO_BACKEND=null`).

Recorded deferrals that stay deferrals (do not re-open, do not silently promote):
the DPR/font and fractional-scroll matrices, note text/clipping cases,
whole-image baselines, and ruler/tab/drawer surfaces that are not mounted on this
surface. No benchmark is registered in the manifest; frame-cost measurement is
not part of this acceptance, and a bench harness is not authorized under the
frozen boundary.

7B (oracle/core deletion execution) is **not** performed by this task and is not
opened by it. The accepted T7 record blocks 7B until this task's 43 in-scope-core
rows are adjudicated. Their recorded state at this baseline is **29 verified with
evidence and 14 pending**, and the pending 14 are not all of one kind:

- 5 `automation-domain/*` rows carry an *unapproved* exclusion recommendation
  (legacy automation-drawer presentation is absent UI, not core document behavior),
- 5 `vgsavecheck/*` rows carry an *unapproved* exclusion recommendation (legacy
  voicegroup-editor transport gestures are absent UI; bank domain/history stays
  covered by the Swift suites),
- 4 `clipcheck`/`clipmimecheck` rows have no executed equivalent for their native
  MIME transport/failure-routing facets.

T8 therefore executes only what the pending subset still needs, adjudicates their
status (approve the recommended exclusions or record the executed replacements),
and records the resulting gate state in `plan.md`. It does **not** re-run or
re-derive evidence for the 29 verified rows. Deleting `src/core/` remains a
separate, explicitly authorized step after the gate is satisfied; no core source is
removed here.

## Interface contract

The contracts are the ones already implemented; this task verifies them rather than
extending them:
- `ApplicationSession` owns `PianoGrid(session: DocumentSession)`, returns it from
  `gridPresenter()`, and exposes primitive command/key/escape/cancel entry points;
  `aboutToReleaseGrid`/`acknowledgeGridDetached` carry the detach handshake. Swift
  owns semantics; QML renders and delivers input; the native host owns the window,
  the QMenu/keymap routing, the clipboard bytes and the view's lifetime.
- The QML root reads the retained presenter through the session and pushes viewport
  metrics from QML (`SwiftRollOverlay.qml::configureViewport` → `PianoGrid.configureViewport(width:height:fontPx:dpr:)`).
  Keep that direction; do not add a native metric push.
- Clipboard stays `application/x-porydaw-clip` with the TPQN rescaling of
  `src/ui/songview/clipmime.cpp`; native Qt only gets/sets bytes.
- Audition stays on the accepted `NativeAudio.previewNote(track:key:velocity:)`
  route with velocity-zero release and no `-1` key crossing the native boundary.
- Coverage identities are the ledger's, not new names. Where a case is genuinely
  native-boundary-only, keep it in the retained suite and name that boundary in the
  row mapping; where it is domain behavior, it belongs to a `swiftcore` suite.

If a verification step cannot be executed with these interfaces, stop and report:
adding a native helper, host or test driver to make a row executable is a user
decision, not an implementer choice.

## Implementation steps

1. Take the T7 baseline from the recorded evidence in [plan.md](plan.md) — the
   raster/Reticle slots, the pre-deletion battery, the native render comparison and
   their stated limitations. Do **not** re-run that matrix to re-confirm accepted
   T7 behavior. Execute only what this task must newly cover: `swiftcore` headless
   for the unverified remainder of the 43 gating rows, then the retained windowed
   names whose assertions this task touches, in that order, capturing raw output
   before changing any row status.
2. Reconcile coverage row by row against the executed results plus the recorded
   evidence: promote only rows whose assertion actually executed, record the
   executing case/catalog name with the evidence, and record each unreachable,
   deferred or obsolete-implementation row with its reason. Adjudicate the pending
   remainder of the 43 core rows that gate 7B on the fresh headless output — approve
   or replace the 10 exclusion recommendations and record what the 4 clipboard rows
   need — while leaving the 29 verified rows' recorded evidence untouched and
   recorded; this turns that obligation into evidence and does not delete `src/core/`.
   Do not promote historical rows from suite aliases, equal case counts or source
   wiring. Then perform the deletions listed above, re-running the affected filters
   to confirm nothing the manifest compiles depended on them.
3. Run the real-window smoke on the built bundle (below) and record observed facts
   for notes/rendering/gestures/commands/undo/redo/save-reopen/playback/pan-zoom/
   cancellation. Offscreen or model-only evidence is not native visual proof.
4. Update `plan.md` with the executed T8 evidence, the exact commands and the
   remaining deferrals, and this brief's status. Stop there: no further consumer,
   no new feature, no benchmark.
5. Independent spec/quality review of the T8 delta, then the final checkpoint.

## Acceptance predicate

The real application opens a staged song, displays themed notes, executes the
retained grid gestures and commands through Swift, undoes/redoes, saves/reopens and
plays the edited song, with no old core/transport/editor compiled or instantiated.
Controller commands (from the repository root, on a revision with a settled tree):

```sh
deno task build:app
deno task verify --filter swiftcore --verbose
deno task verify --filter swiftrollgated --filter swiftbandkeys --filter swiftqtml --filter selectionkey --verbose
deno task verify --verbose
```

The first three cover Swift domain/session behavior and the retained windowed
regression surface; the last is the **declared rewrite manifest** (18 harnesses at
this revision), not the historical whole-app suite. Filters must be catalog names:
there is no `clipcheck`, `clipmimecheck` or `editorqml` entry at this revision, and
clipboard coverage executes inside `swiftcore` (Swift semantics) and
`swiftrollgated` (`hostClipboardRoundTripAndReplacement`).

Every retained grid/window/input/clipboard row is either mapped to an executed case
or recorded with a reason; the 43 in-scope-core rows that gate 7B are adjudicated —
the 29 verified rows keep their recorded evidence, and the 14 pending rows are
executed or their exclusion recommendations resolved with the controller's decision
recorded. Deleted sources are confirmed absent from the manifest and from the build.

Native smoke requires an available desktop: launch the built bundle through the
supervised process tool with `--project <staged-root> --song mus_route101`, capture
its window, and exercise drawing, both resize edges, move/neighbor trim, right-drag
selection, delete, keyboard undo/redo/copy/paste, pan/zoom, play/pause, save/reopen
and ordinary cancellation/close. Confirm the captured frame shows real notes with
the stored theme and runtime font scaling. The runner-owned scratch directory is
deleted on exit; never prescribe a later launch against that path.

## Task-specific constraints

Do not port TrackHeaders, ruler, tabs, drawers, browsers or dialogs; do not expand
the grid's QML feature set to compensate. Do not keep dead C++ views or feed mirrors
to satisfy old tests, and do not re-register retired check names as aliases of new
coverage. Do not weaken an assertion to make a row executable, and do not promote a
row whose replacement assertion has not run. The four windowed names are retained
regression protection: record which cases each executed, remove only assertions
whose mapped replacements pass, and keep unrelated native boundaries untouched.
After this acceptance, stop.
