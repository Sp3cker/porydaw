# Swift core rewrite → piano grid

**Current execution boundary:** finish the bounded T7 acceptance checkpoint and
push, then stop before any further T8 work. The user must first amend T8 test
ownership: Swift assertions own application semantics; QML tests exercise QML
interactions through real Swift presenters; C++ checks protect genuine native
boundaries. Preserve existing regression protection until equivalent replacement
assertions execute. This checkpoint is not global core/oracle retirement approval.

Status: implementation underway. The coverage reconciliation, Swift 6.4 and
test-language amendments apply before acceptance of affected work; none
requires restarting the implementation. This replaces the M1/M2 sequence in
[swift-ownership-cutover](../swift-ownership-cutover/plan.md).

## Scope and stop

Rewrite all 33 files currently under `src/core/` as native Swift responsibilities,
then make the existing piano grid their first direct document consumer. Stop.
No header, ruler, drawer, browser, tab, or other consumer port; no new QML feature.
The rewrite application intentionally excludes those unmigrated surfaces from
construction and compilation. Their MIDI data is still loaded, edited by core
operations, saved, and played correctly. No reverse C++ document adapter.

The core includes MIDI storage/import, all document edits, history, tempo,
track/time/velocity/XCMD semantics, timeline projection **and the sequencer**.
`TimelinePlayer` is rewritten, not moved to `audio/` to make the inventory look
complete. Native device/DSP, instrument loading, project-file services, and a
small Qt host remain. See [spec.md](spec.md) for interfaces and file disposition.

The first consumer is PianoGrid because it already exists in Swift but still
receives copied C feeds and sends C intents. Replacing that dependency proves
actual ownership without first implementing another view. The end-to-end gate
is real project/song open → existing note gestures → undo/redo → save/reopen →
playback. Unconverted editors are absent, not misleadingly read-only.

## Global Constraints

- Inherit the [amended charter](../swift-backend-charter.md) and
  [QtBridge integration contract](../qtbridge-integration-contract.md). The
  latter is the capability evidence ledger, not proof of this rewrite.
- Optimize maintained code and concepts. One lossless event store, one history,
  direct Swift calls, no mirror document, C-shaped domain API, command bus,
  general observer framework, or compatibility modes. Do not transliterate
  `EditOp`/`QUndoCommand` class machinery. Public declarations come first.
- Core independence is the governing priority: C++ testability must never
  constrain Core's Swift API, representation, ownership or concurrency model.
  Apply the charter's [Swift implementation policy](../swift-backend-charter.md#swift-implementation-policy).
  Runner/envelope reuse is subordinate to that rule. A demonstrated host
  limitation requires a test-integration correction, not a Core compromise.
- Preserve normal-use behavior and real file errors. Do not add impossible-state
  stress matrices, repeated token guards, synthetic race frameworks, or new
  product features. Existing meaningful assertions remain reference contracts;
  implementation-pinning assertions are removed, not re-pinned.
- Until final cutover, the old application remains its own sole authority and
  Swift is exercised independently by checks. At cutover the new application
  links no old core or unconverted editor. No writable twin in one application.
- Use exact commands in the briefs; change them only for an evidenced scope or
  runner mismatch. New check names are explicitly marked prospective. All
  shared builds, tests, formatting, and native smoke runs belong to the
  controller after writers settle. Writers still inspect their own code.
- Existing C++ QTest cases and checked-in fixtures are the behavioral oracle,
  not the required language of replacement tests. Apply
  [test-language ownership](spec.md#test-language-ownership): Swift owns domain
  scenarios, direct production calls, comparisons and expected-result assertions.
  C++ is limited to runner/reporting glue, temporary oracle access and genuine
  native integration checks. No permanent C++ domain driver or per-operation
  Swift test ABI; no production `SongDocument` facade. Preserve coverage rather
  than retaining obsolete test bodies or a permanent duplicate suite.
- Required coverage accounting is defined in
  [spec.md](spec.md#case-by-case-coverage-reconciliation). Task 1 creates
  `docs/plans/swift-core-rewrite/coverage-ledger.json`; every task's exact write
  set additionally permits updates to its own rows in that file. The controller
  serializes ledger integration alongside other shared files. This is evidence,
  not a second test framework. Each task's acceptance includes independent
  reconciliation of its due rows against executed Swift-backed assertions.
  Passing suite names or equal test counts cannot substitute for this gate.
  No C++ core/oracle deletion is authorized while the retirement gate is open.
- Each accepted task and each cumulative milestone receives independent,
  read-only thermo-nuclear review, plus the SDD task/spec gate. Review settled
  scope against its recorded base, interface/deletion contract, verification,
  and known gaps. No dependent task consumes a materially changed interface
  before acceptance. One review may satisfy both gates when scope is identical.
  Review cohesion, duplicate state, wrapper count, callback ownership, COW
  cost, and retired code—not arbitrary file-size targets. Resolve material
  findings or reject them with source evidence; recheck material fixes. After
  two unsuccessful fix rounds, stop dependent dispatch and revisit the design.
  Reviewers do not run shared validation or modify the reviewed scope.
- Checkpoint accepted work at the milestones below and before later tasks
  re-edit an earlier uncommitted write set. Batch ready work at each checkpoint;
  no separate commit chore in each brief. Push every resulting commit.
- Apply [Swift 6.4 qualification](#swift-64-qualification) before accepting
  affected work. Each task's write set additionally permits its own qualification
  evidence in this plan and the integration contract; the controller serializes
  those shared documentation edits. Production write sets remain closed.
- The test-language amendment applies to active work before acceptance. Migrate
  already-written C++ domain assertions to the task-owned Swift checks without
  restarting production implementation. Every task's check write set also
  permits `src/checks/swiftcore/{CoreCheckSupport.swift,oracle_check.h,oracle_check.cpp,module.modulemap}`
  for its bounded runner/oracle integration; shared edits remain serialized.
  This is not permission for new C++ domain scenarios.

### Check language layout

Deno remains the build/check orchestration and output-collection interface;
it does not require QtTest as the Swift test framework. The existing native
launcher may remain as bounded infrastructure, not as a Core requirement.
`src/checks/swiftcore/` contains Swift sources only. Native launch/reporting,
engine fixtures, C headers and their module map belong in
`src/checks/support/corecheck/`, whose name describes infrastructure rather
than an implementation language.

Task 1 owns this immediate, serialized test-integration correction before the
next affected acceptance; do not defer directory separation to task 7.
Relocate `tst_swiftcore.cpp`, `tst_swiftcore.h`, `core_check.h`,
`oracle_check.cpp`, `oracle_check.h`, and `module.modulemap` from `swiftcore/`
to `support/corecheck/`, preserving basenames and exported symbols.
The oracle remains temporary at that destination and is deleted in task 7.
Migrate source/include paths, module-map/compiler arguments and actual header
consumers together; no forwarding headers, duplicate files or old-path aliases.
Keep Swift scenarios and `CoreCheckSupport.swift` in `swiftcore/`.

This relocation supersedes native-file locations in the original briefs:
every task's permitted `swiftcore/` native/header/module-map write path maps
to the same basename under `support/corecheck/`. Only Swift source paths stay
unchanged. Task 7's new `native_check.{h,cpp}` also belongs there. This is a
path/ownership correction, not authorization for a new runner or test framework.

## Architecture review amendment

Apply these requirements to in-flight work before the affected task's acceptance;
do not restart completed implementation or infer acceptance from this amendment.
An already accepted task receives a bounded repair and re-review before its next
dependent handoff. Preserve recorded evidence; new assertions need new execution.

| Finding | Owner and binding acceptance |
| --- | --- |
| Track-name selection differs between document queries, rename classification and import | Task 3 centralizes name-role selection and adds prefixed-name/rename/import regressions under its amended brief. Its write set now includes `MidiFile.swift` and `SongDocument.swift`. Close before task 4 consumes the event interfaces. |
| Codec/semantic expected results still depend on C++ oracle calls | Task 1 supplies independent expectations alongside parity comparisons. Later domain tasks apply the same spec requirement; task 7 proves they survive actual oracle removal. |
| Earlier loop comparison did not execute every named row | Task 5 preserves six separately executed semantic rows. The reviewed source now contains them; source inspection is not acceptance or fresh execution evidence. |
| Permanent native fixture services share the temporary oracle files | Task 7 extracts engine/fixture-root support into its explicitly permitted `native_check` files before deleting the oracle and migrates every caller/import/build entry without aliases. |
| Session callers could reconstruct tempo/config projection rules | Task 6 adds the single state-to-playback factory specified in the spec, with edited-tempo/config and undo/reopen checks. Tasks 7–8 consume that result, not a parallel mapping. |
| Both runtime implementations still exist | Task 7 retains its atomic production cutover and source/link-closure gate. Passing standalone Swift checks is not application-wide retirement evidence. |

Preserve the existing semantic edit/commit/history interfaces while applying
these repairs. No generic command framework, file split solely for line counts,
or token-reduction quota is authorized.

## Swift 6.4 qualification

Swift 6.4 is installed (user-reported), but installation is not project
qualification. Preserve the recorded 6.3.3 evidence as historical. The controller
records the selected compiler executable/version, SDK, deployment target,
language/interoperability flags, QtBridge pin/patch and macro compiler in the
[integration contract](../qtbridge-integration-contract.md#swift-64-qualification).
Ensure CMake and QtBridge macros select the intended compatible toolchain and
rebuild affected compiler-dependent artifacts. Keep `Swift_LANGUAGE_VERSION 6`;
it selects a language mode, not compiler release 6.4.

After writers settle, run:

```sh
deno task build:app
deno task verify --filter swiftqtml --filter swiftcore --verbose
```

These qualify app/macro compilation, real QML bridge capability primitives, and
the currently implemented Swift core checks. They do not prove an unexercised
new API, deployment on another OS, realtime safety, or final consumer behavior.
Task-specific checks and case-by-case coverage gates remain mandatory.

Before changing an accepted storage or ABI choice, complete a bounded disposable
comparison on the selected toolchain with the actual deployment/interop flags.
Task 5 owns the playback storage/export comparison; task 7 consumes its accepted
decision rather than reopening it. Record the candidate, exact probe command,
observed result, removed/added ownership and adapter concepts, and the decision.
Freeze any changed representation in the affected brief before implementation;
retain correct existing code when no concrete simplification is demonstrated.
Do not retain alternate implementations or introduce a benchmark framework.

Use new syntax, borrowing iteration, safe memory APIs or concurrency facilities
only where they remove existing work or express a required contract. Do not
replace useful snapshot/history sharing with unique ownership, add async work to
the render path, suppress upgrade diagnostics, retry failing tests until green,
or adopt unverified 6.5/proposal-only APIs. New library availability must be
proven for the deployment target; do not raise it or add fallback branches
without approval.

The app remains Deno/CMake-driven. Audit any SwiftPM invocation in the actual
QtBridge macro build for artifact discovery and compiler selection; do not
migrate the app to SwiftPM or preemptively select its legacy build system.
Report a required build fix outside a task's closed write set before editing it.

Feature references: [Swift 6.4 release](https://www.swift.org/blog/swift-6.4-released/),
[UniqueArray acceptance and rejected RigidArray/Containers scope](https://forums.swift.org/t/accepted-in-principle-se-0527-uniquearray/86943),
[UniqueBox](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0517-uniquebox.md).

## Tasks

All tasks use SDD-track: they introduce or consume a domain/native interface.
The larger write sets close one behavior boundary rather than manufacture
microtasks for individual C++ files.

| Task | Deliverable / brief | Prerequisites | Seat and sizing exception |
| --- | --- | --- | --- |
| 1 | [Lossless MIDI and musical primitives](task-1-brief.md) | None | `sdd-implementer`; codec, semantics and its comparison harness form one storage boundary. |
| 2 | [Document, note edits and history](task-2-brief.md) | 1 | `sdd-implementer`; one mutation/history boundary, including gesture grouping and save identity. |
| 3 | [Tracks, raw events and value streams](task-3-brief.md) | 2 | `sdd-implementer`; all changes share ordered-event mutation and one document transaction. |
| 4 | [Range and time transforms](task-4-brief.md) | 3 | `sdd-implementer`; one cross-stream transform boundary, not separate lane-specific implementations. |
| 5 | [Swift timeline and realtime sequencer](task-5-brief.md) | 1 | `sdd-implementer`; projection and scheduler are verified together against existing rendered behavior. |
| 6 | [Real project persistence and session](task-6-brief.md) | 2–5 | `qt-cpp-reviewer`; native project ownership and Swift persistence/session integration. |
| 7 | [Core runtime cutover and native host](task-7-brief.md) | 6; cumulative semantic gate | `qt-cpp-reviewer`; native clients, build membership and reference retirement are one core-runtime cutover. |
| 8 | [Direct piano-grid consumer, then stop](task-8-brief.md) | 7; core milestone | `qt-cpp-reviewer`; one existing view's direct model/input/host integration and transport retirement. |

Task 5's algorithm work is independent of tasks 2–4 after task 1. Shared build
and check-registration edits are serialized by the controller; no concurrent
writers touch those files. Do not parallelize coupled document mutation work
merely to increase the agent count.

## Milestones

1. **Storage accepted:** task 1 establishes types, the comparison path and the
   complete baseline coverage inventory; its own due rows are reconciled.
2. **Core accepted:** tasks 2–7 provide all old core responsibilities, real
   persistence/playback and the native application host. The old core is gone;
   the editor area is intentionally absent until the next task. Record final
   core comparisons before retirement.
   Retirement additionally requires the case-by-case gate in spec.md, followed
   by post-cutover proof that the mapped retained cases still execute on Swift.
3. **One consumer accepted:** task 8 converts the grid, repoints its actual-surface
   checks and removes obsolete transport. This is the terminal milestone.
   Do not dispatch a second consumer.

Shared CMake/check registration files can require an earlier checkpoint before
reuse; combine it with all other accepted work. Milestone labels do not require
empty or redundant commits.

## Evidence and reduction ledger

Inspected source baseline: `src/core/` has **33 files, 9,409 lines** (including
headers/comments; counted during planning). The scope inventory in spec.md is
exhaustive. Existing covering registrations are in
[`checkcatalog.cpp`](../../../src/checks/checkcatalog.cpp); runner selection
supports repeatable substring `--filter`, exact `--exclude`, and `--qt` for one
selected harness. It does **not** support `--no-build`.

Record actual commands/results with accepted task evidence here during
implementation. No planned command below is claimed to have run.

At core and final gates report three separate quantities:

1. Original core implementation versus replacement Swift core/playback code.
2. Removed feed/executor/mount code versus added necessary native-service/host
   code, including test-driver cost separately.
3. Unconverted UI excluded from the binary. **Do not count excluded features as
   successful code simplification.**

Review a net increase in core-plus-required-glue code before acceptance; explain
what behavior earns it or simplify. There is no arbitrary percentage target and
no pressure to compress readable code into fewer lines. A rename or exclusion
alone is not a Swift rewrite.

## Final verification boundary

The exact retained/deferred test policy is in [spec.md](spec.md#verification).
A default green rewrite suite is not a claim that absent-surface suites passed.
Run the real app with a staged project, not a duplicate demo. Capture a native
window and exercise existing gestures, keyboard priority, save/reopen and audio.
Keep ordinary close/reopen, cancellation and save-failure checks; do not invent
unreachable internal sequences. Planning-only validation checks paths, links,
brief completeness, inventory and registered command names—not application builds.

## Planning review

Independent core-design and native-integration reviews completed. Their findings
are incorporated: timing query, history-token ownership, snapshot/bank lifetimes,
save/close completion, registered-action boundaries and audition routing.
The final module graph and native clipboard/scene-lifetime contracts were also
checked. The later coverage, Swift 6.4 and test-language amendments add
acceptance requirements; the original reviews do not establish their execution
or coverage completeness.

Planning validation covers all 33 source files, eight bounded briefs, local links/
anchors, source-path declarations and verification filter names. `swiftcore`
is now registered; `build:render` remains prospective. No application build,
runtime check or native-window smoke is claimed by this planning review.

Post-amendment `evidence-plan-architect` audit: initially NEEDS_REVISION; final
targeted recheck PASS after restoring 22 task-1 rows to pending with historical
evidence preserved, correcting SE-0527 acceptance/deployment assumptions, and
fixing module-map/registration drift. The wider audit found the Swift-owned
test design and retained native boundaries implementable and consistent.
Mechanical validation passed for 11 Markdown documents, 41 local links/anchors,
eight brief schemas and ledger totals; all 834 baseline identities and historical
per-row evidence were preserved. This closes the planning findings, not task
acceptance: Swift-body execution, storage comparison and retirement gates remain.

## Pre-deletion gate evidence (controller, 2026-09-20)

Fresh full battery at revision 45a52d80 (pre-7A/7B): `deno task verify
--filter swiftcore --filter smfcheck --filter editcheck --filter noteidcheck
--filter xcmdcheck --filter automation-domain --filter velocity-model
--filter savecheck --filter vgbankcheck --filter vgsavecheck --filter
roundtrip --filter loopcheck --filter primecheck --filter trackactivitycheck
--filter exportcheck --verbose` → run_checks PASS. Ledger adjudication:
845 rows, 0 unapproved exclusions (30 excluded, 59 deferred-ui); T1 20 rows
+ history-transition rows promoted with fresh-run evidence. 7B (oracle/core
deletion) blocked until T8's 43 core rows pass headless, per the case-by-case
retirement gate.

## Reticle visual regression evidence (controller, 2026-09-20)

`RewriteWindow::applyGridPalette` now preserves the original absolute
selection-fill alpha of 30/255 while retaining the active theme RGB.
The previous direct theme-role transfer made the selection rectangle opaque.

`SwiftRollGatedTest::selectionReticleRasterTranslucency` drives a real right-drag
through the shown native production window and compares captured framebuffer
pixels with an independent source-over expectation. It covers two contrasting
underlays, a note face beneath the rectangle, and visible dashed edges.
Before the fix it failed: background `#b4aca6`, expected `#b5b3ae`, actual
opaque `#b9e8ee`. After the fix, `deno task verify --filter swiftrollgated
--verbose` passed. Independent bounded spec/quality review passed.

`deno task verify --verbose` then passed all 18 declared harnesses.
This is not T8 coverage acceptance: the native suite aliases still share a
shallow host scenario, and this raster case runs only under `swiftrollgated`.
The sibling worktree's reticle smoke checked dashed edges and cancellation,
but did not check fill transparency. No historical ledger rows are promoted
by this bounded repair, and no full visual parity or DPR/font-matrix coverage
is claimed.

## Expanded retained-grid raster gate (controller, 2026-09-20)

The sibling visual audit found a second role-transfer regression:
`selectionRing` used `song_view_edit_preview_outline` instead of the original
`item_selected_background`. The new note raster check failed before correction
at physical pixel `(314,785)`: expected `#b9e8ee`, actual `#302c29`.
The mapping is corrected without changing the rendering algorithms.

`deno task verify --verbose` passed all 18 declared harnesses after the fixes
and expanded checks (build 25.79s, checks 2.78s). The three raster slots run
under `swiftrollgated` in the shown native `RewriteWindow`/`QQuickView`:

| Slot | Exercised visual contract |
| --- | --- |
| `selectionReticleRasterTranslucency` | Absolute-alpha30 source-over on two distinct backgrounds and a note face; dashed edges; three untouched outside pixels establish containment. |
| `noteRasterParity` | Original track/velocity/theme note-face color; unselected black frame; selected theme-role ring, inset black frame and unchanged face; fitted tiny-note border thinning/preservation. |
| `chromeRasterParity` | Natural/accidental row and key colors; aligned C separators; bar/beat source-over colors; real wheel scroll and hover-chip alignment. |

Chrome color checks do not claim temporal grid-line placement. The fixture
contains another 4/4 event at tick 12; assuming every bar starts at a multiple
of 96 was an invalid test oracle. The checks use independent role/compositing
expectations, not the rewritten palette's published values.

Ghost raster is not claimed: both the current `PianoGrid.refreshFromSession`
and sibling production-bound `swift-grid-prototype/PianoGrid.loadDocument`
filter to the active track and construct `ghost:false`. Sibling ghost examples
belong to its standalone demo. No ghost projection or test-only document
adapter was added to make a coverage label green.

Still unverified: the DPR/font matrix, fractional-scroll/zoom matrix, note
text/clipping cases, custom-theme note-color variants, and whole-image baseline
comparisons. Ruler, time-selection band, drawer/automation lanes, tabs, track
headers and popup baselines are not mounted on this retained surface. These
results do not promote historical ledger rows or close T7/T8 acceptance.

Independent bounded spec/quality review passed; GUI coverage review accepted
the delta with the limitations above. Two redundant row-color reassertions
identified in review were removed. The final post-review
`deno task verify --verbose` passed 18/18 on the current consolidated rewrite
catalog (build 24.72s, checks 2.70s), including all three native raster slots.
The other three grid catalog aliases explicitly skip those raster slots.

## Native render comparison (controller, 2026-09-20)

The current `build/porydaw_render_cli` rendered the checked-in rich-bank
`mus_route101.mid` loop and `mus_route102.mid` tail fixtures for 12 seconds at
48 kHz, with `fixture_rich`, song volume 100 and reverb 50. The tail command
also supplied `--no-loop`. Both outputs are stereo 16-bit PCM, 576,000 frames.
The loop's final second contains 77,801 nonzero samples; the tail's final second
is silent. Both complete WAV files are byte-identical to fresh runs of the
existing main-checkout C++ renderer with identical inputs and arguments.

| Artifact | SHA-256 |
| --- | --- |
| Current Swift-backed renderer | `240aa7b05a93a4906fbec818265b378e6074c266bcf36bdf8160bd9398f035a7` |
| Existing C++ reference renderer | `86418c38914f0b041dd5562ab0d97a05e8b8406b991ca80021ae41b0c66ee1ad` |
| Loop WAV, both renderers | `b196149e44a049ab229e3a18ce5a418fb910a6b9cc8785d313a56530e7da42d7` |
| Tail WAV, both renderers | `531f352e5749f63819296f3a7ecd8ab7c28d87f39c2c61c5d6239b8225b52052` |

The reference executable was
`/Users/spencer/dev/cProjects/porydaw/build/porydaw_render_cli`;
`nm -C` confirmed its `MidiTimeline`, `TimelinePlayer` and `SmfFile` symbols.
Its exact source/build revision has not been established. This is fresh
native-versus-Swift PCM evidence, not a claim that the executable is the pinned
Task 5 reference or that the pre-retirement coverage gate has passed.

Coverage-binding inspection also found that prior blanket playback evidence
did not prove native export, transport, activity or MIDI-engine bounds rows.
Their real native predicates are being restored before ledger acceptance.
Straight-line Swift seek/replace assertions do not replace callback publication,
ownership, latency, tail or suppressor assertions.

## Pinned native reference (controller, 2026-09-20)

The earlier renderer provenance gap is now resolved by an isolated reference
checkout at `0c1d3cd583cf98a81c8bb048eee47815c5e4db1a`, with its recorded
`poryaaaa` revision `f040bafc00bb2e0f5fd9239d68cd74cdc52f4923`.
The controller-owned scratch checkout is
`build/t7-reference-0c1d3cd5-l14_xuyc`; neither the main checkout nor the sibling
worktree was changed. No reference target was added to the production build.

In that checkout, `deno task build:checks` passed, followed by
`deno task verify --filter loopcheck --filter primecheck --verbose`
(`2/107` harnesses passed, `105` unselected). These are the original native
loop/prime suites, not the current generic registration aliases.

A temporary `reference-render.deno.json` task invokes the existing current
`tools/cli.ts build:render` dispatcher against the reference checkout's own
configured build and unchanged CMake target. Its
`deno task --config reference-render.deno.json reference:render` run passed.
The resulting pinned C++ renderer SHA-256 is
`4f8b9bf937f3d05cdd81271e8b3a60e79c1feb5fa764c3ebc5f925d81f526663`.
Running the same 12-second loop/tail inputs and arguments recorded above
produced `pinned-loop.wav` and `pinned-tail.wav`; their SHA-256 values exactly
match the corresponding Swift WAV hashes in the table above.

This establishes source-grounded native playback reference evidence. It does
not approve the remaining converter/save coverage gaps, qualify a grid
performance comparison, or authorize legacy-source retirement.

## Avoid useless check loops (user direction, 2026-09-20)

Keep corrective verification focused on meaningful, user-reachable behavior.
Do not repeatedly repair artificial assertions merely to make a check pass.
The user explicitly clarified that this is not a request to audit the whole
application or rewrite unrelated tests. Apply it locally to the active
gesture/clipboard check corrections, then continue the existing T7/T8 work.

### Settled input and native app evidence — 2026-09-20

- `deno task verify --filter selectionkey --verbose`: PASS (1/25 selected).
  Removing the redundant pre-drag click stopped the test from invoking the
  real double-click delete command. No production workaround was added.
- Bounded re-reviews accepted clipboard semantics and input/lifetime quality.
  GUI review closed mandatory F1/F2/F3/F5; its remaining Open Song availability
  issue was corrected using the existing `projectOpen` property.
- `deno task build:app` and `deno task build:render`: PASS. The host-only
  Open Song correction was followed by another successful app build.
- Actual native app: Open Song disabled without a project, enabled with the
  staged project; the loaded grid was captured and inspected. From canvas focus,
  Select All / Right / Save changed MIDI. Keyboard Undo / Save restored the
  previous bytes exactly; keyboard Redo / Save restored the edited bytes.
  Undo/Redo availability followed those history transitions.
- A further edit caused the real unsaved-changes close prompt. Escape preserved
  the window; Save followed by native window close exited 0 with no runtime log.
- Automation limits: the native project picker exposed no usable accessibility
  children, so startup arguments were used for the loaded-project smoke.
  An accessibility menu Undo attempt did not execute; its byte comparison was
  not counted as a pass. Keyboard Undo/Redo supplied the successful proof.
- Immutable bounded review packages are `local://t7-input-lifetime-r0.diff` and
  `local://t7-input-lifetime-r1.diff`, both against `322bcd40`. These approvals
  do not close converter/save coverage reconciliation, retirement, the
  comparable benchmark, or the complete T8 surface matrix.

## Bounded T7 acceptance checkpoint

The latest user direction supersedes automatic continuation into T8 or the editor
consumer follow-on. Finish the identified verification/review decisions and push
this checkpoint; do not start another whole-app audit or amend/execute T8 here.

### Executed repairs and native protection

- Queued unified save: the original `DocumentSession.save` body reproduced
  `pending save rejected the newer note`. Separating native-bank persistence
  ownership from the history transition preserves newer document edits while
  a captured snapshot is saving. The regression then passed, including exact
  stale/newer MIDI bytes, dirty identity, retry, and bank-preserving note undo.
  `QueuedSaveGate` approved the bounded fix.
- Real saved MIDI: `DocumentSession` edits and saves `mus_route101`, closes its
  native service, and the actual `mid2agb` compiles the persisted MIDI using
  reloaded registry flags. `SavedMidiAcceptance` approved this exact case.
  Its initial lifetime finding was retracted: `DocumentSession.close()` already
  awaits `ProjectService.close()` and native worker destruction.
- Converter coverage: the fourteen original songs and the XCMD fixture execute
  the real converter boundary. `ConverterCoverageGate` approved the mapping;
  a generic compile-nonempty probe is not the replacement.
- Native bank protection: the eight original `VoicegroupBankTest` cases remain
  executable unchanged. Current and pinned-reference runs each passed ten Qt
  slots including initialization/cleanup. `NativeBankGate` approved the partition.
- Native theme/font/layout/palette protection: six original native runners pass,
  with original retained bodies, data generators, and initialization ordering.
  `NativeThemeAcceptance` approved the partition. Missing includes found by the
  first build were corrected; the subsequent build and checks passed. Absent
  editor/widget cases remain source-only and explicitly unverified.

Final scoped command after removing the weak save aliases:

```sh
deno task verify --filter swiftcore --filter vgbankcheck --filter exportcheck --filter themecheck --filter fontcheck --filter darkbasecheck --filter editor-layout --verbose
deno task build:app
```

Both passed: **10/24 selected harnesses**, fourteen unselected, followed by a
successful app build. This is not a new whole-manifest or complete T8 claim.
The earlier uncapped Swift run passed **13 Qt slots, zero failed/skipped**:

```sh
deno task verify --filter swiftcore --verbose --qt -maxwarnings 0 -o build/t7-core-final-identities.log,txt
```

Its log SHA-256 is
`560f5ba11afa50248b821872d1ffb31cd72e827ddb1a9cbd372957b2ff102ae4`.
The exact saved-MIDI and queued-save assertions occur beyond the log's first
4 MB; a truncated grep is not evidence that they did not execute.
Existing compiler warnings remain; no warning suppression was introduced.

Frozen original comparisons at `0c1d3cd583cf98a81c8bb048eee47815c5e4db1a`
also passed: converter roundtrip 17 Qt slots, save 5, native bank 10,
clipboard 12, MIME codec 25, selected history 5, and selected bank-save 8.
These counts include initialization/cleanup. Logs are the corresponding
`build/t7-reference-{roundtrip,save,bank,clipboard,clipmime,history,bank-save}.log`
files. They are reference evidence, not substitutes for current-path execution.

### Coverage decision, not blanket acceptance

- `HeadlessCoverageDecision` reviewed the known 36 headless candidates.
  Thirty-two complete equivalents are now verified. Two missing routes remain
  pending: view-key paste and a foreign clipboard without custom MIME.
  Two further MIME cases have executed decoder/rescaler assertions but not
  complete native transport/failure-routing proof; the controller conservatively
  leaves their complete legacy cases pending as well.
- The ten already identified automation/bank-editor interaction rows remain
  pending for future ownership planning, not newly excluded.
- `SaveCoverageDecision` approved correcting six stale `verified` claims to
  pending: `blankTokenRebasesAcrossSourceReplacement`, `cleanSaveEmitsNoReceipt`,
  `newVoicegroupCreatesAndAssignsUndoably`, `switchCarriesUnsavedBankEdit`,
  `undoShortcutRestoresWithoutWrite`, and
  `valueCommandSurvivesSourceReplacement`. Source-rebind Core facets are not
  simply relabeled UI. Historical evidence and original source are preserved.
- Eleven reviewed save/bank cases have actual executed Swift service/session
  assertions; absent widget presentation/interaction is not claimed.
- Twenty native theme/font/layout/palette ledger rows are verified. The nine
  absent-surface rows remain pending and retain their original assertion bodies.
- Inventory remains **845 cases**: 453 verified, 303 pending, 59 deferred-ui,
  30 excluded. These are bookkeeping totals, not new approval of untouched
  exclusions, deferred rows, or the complete inventory.

The generic `savecheck`/`vgsavecheck` unchanged-input re-save probes and their
unused runner were removed only after the stronger real Swift save assertions
executed and the bounded removal was independently approved. Original project/
voicegroup-save suites are preserved. `exportcheck-loop` and `exportcheck-tail`
now directly invoke the genuine native export runner and both pass.
Earlier duplicate clipboard and weak roundtrip/loop/prime aliases likewise do
not stand in for the accepted Swift assertions.

The old band-key, command-feed, document-feed, and bridge-probe check sources
are preserved at this checkpoint rather than retired. They are not reintroduced
as aliases or compiled fallbacks. The frozen original remains the executable
reference; source-only preservation is not counted as current-path coverage.

**No global core/oracle retirement or full core-milestone approval is claimed.**
Unproved cases keep that gate open. Existing integrated grid work is checkpointed
without claiming full T8 acceptance, its benchmark, or its remaining surface
matrix. Stop here for the user-owned T8 test-ownership planning boundary.

## Bounded T8 closure — controller execution, 2026-09-20

This dispatch verifies the already-converted grid; it does not convert it again.
The separately reviewed pure-camera preparation was checkpointed and pushed as
`d3e49a3a`, after its focused `projectSession` run passed all 30 camera assertions.
The camera remains unconnected to `DocumentSession`, `PianoGrid` and QML.

### Explicit controller decisions and coverage gate

The user/controller answered **“Approve the ten exclusions”** for the five
`automation-domain/*` and five `vgsavecheck/*` existing absent-UI recommendations,
and **“Accept bounded closure with gaps”** for the two negative native clipboard
facets below. These decisions supersede a requirement to close those two rows
before accepting this bounded T8 dispatch; they do not authorize retirement.

- The 43 core-classified T8 rows now comprise **31 verified, 10 explicitly
  approved exclusions, and 2 pending**. The original 29 verified rows, including
  their evidence, remain unchanged and were not re-run.
- The ten approved exclusions retain `runEvidence: null`: absent automation and
  voicegroup-editor gestures did not execute. Existing Swift domain/history
  coverage is separate, not an assertion that their old UI ran.
- `clipcheck/ClipCheckTest::songViewEditKeyPaste` is mapped to the executed
  `selectionkey/SwiftRollGatedTest::hostClipboardRoundTripAndReplacement`.
  Its production-view shortcut and replacement-widget shortcut assert pasted
  note values, selected notes, edit-cursor advancement and undo/redo.
- `clipmimecheck/ClipMimeTest::clipboardRoutesClipMime` combines its unchanged,
  accepted T7 Swift decoder/rescaler evidence with that same newly executed
  host case's actual QMimeData format/payload and production Copy/Paste route.
  This is composition of explicit assertions, not promotion by a catalog alias.
- `clipmimecheck/ClipMimeTest::foreignClipboardIsNotClip` and
  `clipmimecheck/ClipMimeTest::malformedCustomMimeReportsDecodeFailure` remain
  **pending**. Neither the positive host case nor in-memory malformed decoding
  proves their absent-native-MIME/failure-routing facets. Their original source
  and prior partial evidence remain; no new native support was added.
- All 293 T8 rows remain accounted for: the 43 above, 37 unchanged verified
  native-integration rows, and 213 grid/window-input rows retaining their
  individual pending reasons. No native smoke screenshot blanket-promotes them.
  The full inventory remains 845 rows: 455 verified, 291 pending, 59 deferred-ui,
  40 excluded. These totals do not independently approve untouched dispositions.

**7B/core/oracle retirement remains blocked.** Bounded T8 acceptance with the two
pending rows is not global core-milestone acceptance or permission to delete
protected sources.

### Executed commands and reusable evidence

```sh
deno task build:app
deno task verify --filter selectionkey --verbose --qt hostClipboardRoundTripAndReplacement -o build/t8-clipboard-host.log,txt
```

Both passed. The named host case produced **3 passed, 0 failed, 0 skipped**
including initialization/cleanup. Raw log: `build/t8-clipboard-host.log`;
SHA-256 `92dfda62c4055921306f9da909abc0b53a45857c2f0455c606ea5b0e3193d662`.
The current manifest contains 24 catalog entries, not the brief's historical 18.

No fresh headless scenario was needed: the remaining unproved facets were native
input/MIME routes or controller-owned absent-UI decisions, while their existing
headless semantics retain the accepted T7 evidence. No full Swift, T7 battery,
other window-mode aliases, raster matrix or whole-manifest rerun was used merely
to reconfirm recorded results. No assertion bodies or application sources changed.

### Review acceptance and evidence limits

Independent T8 review returned **Spec PASS / Task quality Approved**, with no
critical findings. The controller accepts `clipboardRoutesClipMime` as verified
by the two documented evidence legs: real native MIME payload preservation and
the previously accepted Swift decode/rescale assertions. This is not a claim
that a single native run transported a 24-TPQN clip and decoded it at 48 TPQN.
That combined scenario remains unexecuted; the verified disposition records
composed contract coverage, not an end-to-end rescaled-transport run.

The controller also ratifies reuse of the accepted headless evidence rather
than a redundant fresh headless run: the remaining gaps are the two explicitly
pending native negative routes, not untested headless semantics. Neither
decision relaxes the blocked core/oracle retirement gate or authorizes new
native testing support. The review's optional evidence-schema normalization is
outside this bounded task.

### Actual-window smoke

The built `porydaw.app/Contents/MacOS/porydaw` was launched through the supervised
process tool with `--project build/t8-app-smoke-jlq9eog_ --song mus_route101`.
The private project was staged from the existing manifest's 17 declared
`swiftrollgated` fixture files, not from a user's project or an expired
runner-owned scratch path. The smoke used the null audio backend.

Observed through ordinary OS pointer/keyboard input and captured native windows:
the loaded themed notes; drawing; both resize edges; movement; a same-pitch
neighbor visibly trimmed by an extending note; right-drag selection and Delete;
keyboard Copy/Paste; keyboard Undo/Redo restoring the exact pre-/post-move MIDI
bytes; Escape cancelling an unfinished draw without changing saved MIDI; actual
vertical pan and time zoom; Save, ordinary native close, and reopen with the
edited long note and trimmed neighbor preserved.

Playback was triggered by actual Space input, not by directly invoking Play in
the debugger. Observation at the existing `pd_audio_service_play` entry point
showed the Swift `ApplicationSession` call stack; stepping out changed native
transport from 0 to 2. Continuing advanced the existing playhead to 101622
samples. A second Space reached `pd_audio_service_pause` and left transport 1.
Only existing getters were inspected; no API, hook or test driver was added.
This proves the edited reopened song's null-backend transport, not audible output.
The debugger detached, and both native close operations exited 0.

Captures are retained under `build/t8-native-smoke/`: `initial.png`, `drawn.png`,
`resized.png`, `navigation.png`, `zoom-observed.png`, `neighbor.png`, `pan.png`,
and `reopened.png`. The saved MIDI SHA-256, unchanged by reopen/close, is
`13af1a39d0ea77f66106694152c9516fa439c4dec1d4e567489029629bb0e8ea`.
This is an actual-window smoke at the current theme/font, not a new DPR/font,
fractional-scroll, text/clipping, whole-image or ghost-parity matrix.

### Conditional obsolete-source retirement

Only the explicitly listed empty `src/ui/songview/quick/swiftgrid/` directory was
removed; it contained no tracked files. The following old check directories stay
**uncompiled and unregistered** because complete meaningful-case replacement
evidence or an explicit disposition is still missing:

| Source | Case-by-case disposition |
| --- | --- |
| `swiftdocfeed` | `fixtureMutationHistoryAndTeardown`: direct mutation/history evidence is retained, but old feed teardown/publication has no complete mapping. `unsignedTicksAndRawSignaturePrecedence`: raw-signature/domain evidence is retained, but old snapshot precedence is unmapped. `sessionFeedTransitionsMasksAndReconciliation`: selection/session semantics are partially covered, not the old reconciliation/mask contract. `actualSwiftReceiverGuard`: obsolete transport plumbing, not a new acceptance test. Keep the group; no exclusion was self-approved. |
| `swiftcommands` | `registryRoutingAndOutcomeContract` and `swiftSubmissionGuard`: obsolete pipe/registry guards, not acceptance. `noteIntentValidationAndUndoGranularity`, `batchMoveAndResizeUndoGranularity`, `trackIntentValidationAndRouting`: recorded Swift domain/history evidence covers behavior in part, not a proved complete old matrix. `sessionIntentsLeaveUndoStackUntouched`: direct session evidence is retained without claiming the old pipe/revision contract. `addRoundTripsThroughDocumentFeed`: direct state/rendering replaces the architecture, not a proved callback contract. Keep the group pending complete mapping/disposition. |
| `swiftbandkeys` | `testCommandIdArrivalThroughBandKeyPath`, `testProductionKeyOwnership`, `testEligibilityGatingWithAndWithoutSelection`, `testGestureActiveBlocking`, `testAutoRepeatConsumption`, `testFallbackWhenUnhandled`, `testCancelReasonsMidGesture`, `testPointerWheelLeaveForwarding`, `testPressDeclineRules`: existing production assertions cover portions, not the complete old ordinal/verdict, fallback, cancellation and forwarding contracts. All nine retain their pending reasons. |
| `swiftqtml` | `testPresenterPropertyBinding`, `testInPlaceRowMutation`, `testRowReplacement`, `testInsertRemovePreservesTargets`, `testReorderTargetsIntendedRow`, `testResetWithStaleQmlReference`, `testPendingMutationThenTeardown`, `testObjectReturnCapability`: production session replacement is not proof of these generic model/delegate/capability cases. All eight remain source-only and pending. |
| `swiftrollbench` | `testScrollZoomFrameCadence`, represented by both historical bench rows: no registered or executed replacement; no benchmark or frame-cost claim. Retain uncompiled rather than inventing a driver or exclusion. |

The current compiled source lists contain none of these old check directories or
deleted transport modules. Stale references inside preserved, uncompiled legacy
views are not live application dependencies and were not destructively stripped
to make a text search empty. `TrackHeaders.swift` remains untouched, unbuilt
reference source. No core/oracle file, native check, fixture registration or
working native boundary was removed.

This is the stop after bounded T8. Camera/session integration, a QML test runner,
the velocity surface and window-shell migration require the next controller
dispatch. The velocity menu/shortcut integration remains a planning decision;
there is no new dispatcher or native exception.
