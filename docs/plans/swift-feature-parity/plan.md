# Swift rewrite: feature-parity roadmap

Status: **The overall objective is not complete; the plan continues past the earlier user-requested handoff.** Tasks 12 (R07), 13 (R24), 14 (R08 at `563a3540`), 15 (BANK-CLOSE at `92894399`) and 18 (PJ06: `935c6846` + `5c2d04b2`, merged with the R22/R26/R27 + R15-R18/R23/R25 evidence repairs at `b593f20d`) are accepted and pushed at `b5c5d397` (= `origin/feature/swift-qml-grid`). [handoff.md](handoff.md) records the tasks-12/13 checkpoint only; this plan is authoritative for everything landed after it. The rest of this inventory is preserved, not cancelled.

Current authorization: **details of existing surfaces first, with no extra UI beyond C++ checks/proofs.** Reuse/adapt original QML; do not redesign old features. Sample Studio, WAV export, onboarding and other absent surfaces are deferred, not completed or removed from the inventory.

## Goal and scope

Recover every shipped C++ user workflow in the Swift/QML app, without losing musical data, project-write behavior, editor interactions or supported-platform obligations. **Sample Studio and WAV export are first-class delivery tracks**, not polish after the rewrite.

Read [inventory.md](inventory.md) for behavior obligations and source evidence, [spec.md](spec.md) for the detailed sample/export/project contracts, and [verification.md](verification.md) for acceptance. These documents replace stale migration task ordering, not the historical behavior oracles.

This is the cross-feature roadmap, not a single dispatchable implementation brief. Each package below produces a complete user-facing outcome. Before starting its code, freeze bounded `task-N-brief.md` files under that surface's plan, using the repository's SDD brief format: closed write set, existing symbols to preserve/change, chosen interfaces, exact named checks and explicit blocked rows. Do not send a whole multi-surface package to one implementer or invent new interfaces from this roadmap. Sample processing and production WAV export need contract/design work before implementation; the decision is to keep their behavior in Swift, not resurrect unlinked C++ editors.

## Execution status

This file is the single authoritative plan. `inventory.md` supplies behavior/oracle details, `verification.md` supplies acceptance, and `current-surfaces.md` records historical batch evidence only. The live todo mirrors this plan. Every required item is **pending**, **active**, **complete**, or **blocked**. A blocked item does not stop independent authorized work. Completion requires observed acceptance, not an implementer report or an aggregate count.

Assessment base: `86c88903661ee6d44a77da505bf4b9fef777f6e0`; earlier accepted repair checkpoint: `e171f3ef`; prior pushed integration checkpoint: `fea4034d`; whole-branch review base: `fceecd888e29c0a39c3a98d17e47d3d734b1de06`. The commit containing [handoff.md](handoff.md) checkpoints accepted tasks 12/13 on top of `fea4034d`. Preserve the pre-existing dirty tree, staged `.lsp.json` deletion, independently modified `.omp` instructions, and pre-existing `SongTabs.qml` tooltip / `VelocityPage.qml` diagnostic removals outside these checkpoints. Their protected diff still matches its pre-checkpoint snapshot. No red or unrelated changes belong in the milestone.

### Completed earlier batch

| Item | Status | Boundary |
| --- | --- | --- |
| Task 1 | complete | Existing shell command routes; mounted consumer-contract repairs accepted in R11. |
| Task 2 | complete | Ghost projection/input exclusion; consumer migration and executing-predicate index accepted in R10/R19. Unresolved original behavior remains in its surface ledger. |
| Task 3 | complete | Ruler modifier/chip/paused seek; workspace cancellation accepted in R03. Remaining original ruler evidence stays tracked in R15/R18. |

### Assessment repairs

All nontrivial rows route SDD-track because they affect behavior, ownership, or evidence. Briefs freeze bounded write sets before dispatch. R13 is read-only adjudication. GIT is an authorization gate, not permission to stage unrelated work.

| ID | Status | Required outcome / dependency |
| --- | --- | --- |
| GIT | complete | Repair checkpoint `e171f3ef` and integration `fea4034d` are pushed. Merged `91727ce7`/`cf990a1c` preserves live origin-scoped Swift callbacks and removes only the unused context-property native seam; live engine access remains. Spec/quality review, merged runtime/bridge/proof/format and native Metal/Space/clean-exit gates passed; unrelated user work remains excluded. |
| POLICY | complete | User authorized deletion of completed proof files and obsolete C++ checks with their validated Swift/QML replacement. Keep unresolved behavior as the surface spec; do not maintain completed ledgers indefinitely or run a separate deletion sweep. |
| R01 | complete | [Task 4](task-4-brief.md): concrete actor-owned project operations; projectstore and swiftcore gate passed (24 applicable entries, 7 filtered skips). Spec/quality review approved; Linux executor/loader boundaries unchanged, Linux runtime not requalified. |
| R02 | complete | [Task 5](task-5-brief.md): selected-workspace mute/solo, activation and track remaps reach the real audio engine; native telemetry and mounted controls passed. Spec/quality review approved. |
| R03 | complete | Task 5: workspace cancellation owns ruler sweep cancellation through hide/tab/close/teardown; mounted cancellation checks and review passed. |
| R04 | complete | Task 5: background callbacks cannot publish into selected shared event-list/playhead presenters; origin guards and isolation checks passed. |
| R05 | complete | Task 5: toolbar Play resumes; Space restarts at the edit cursor with immediate presentation. Final shell-transport lane passed (4.78s); exact unproved legacy timing clauses remain PARTIAL. |
| R06 | complete | [Task 7](task-7-brief.md): queued voice edits retain request-time document/bank identity and discard stale work. Real two-session and mounted voicegroup checks passed; bounded failure wait, proof handoff and spec/quality review accepted. |
| R07 | complete | [Task 12](task-12-brief.md): canonical versioned bank views publish edit/history/save/dirty/audio state across live sessions; stale-store receipts and mutations are refused. Native audio, mounted editor/Save, identity/history and non-autosaving switch gates passed. Spec/quality review approved. Exact remaining original clauses stay GAP/PARTIAL; R08 and BANK-CLOSE are not claimed. |
| R08 | complete | [Task 14](task-14-brief.md) accepted at `563a3540`: `VoicegroupSource.rebasePreservingEdits` adopts disk bytes outside the selected section while keeping local edits; `save()` reconciles against current disk bytes and refuses overlap/malformed/missing/relocated input without touching pending edits; `VoicegroupStore` reuses native bank + tokens on sibling-only change. Banklogic B20–B29, savecore S19–S22 (ledger S012–S015), retargeted E10 + E11 all green; projectstore 23/23 and swiftcore PASS; spec/quality review approved. |
| BANK-CLOSE | complete | [Task 15](task-15-brief.md) accepted at `92894399`: close walks enumerate every dirty cached bank after the tab loop via explicit `pendingCloseBankTitle`/`BankCloseTarget`; `startProjectSwitch`/`beginClose` `tabCount == 0` bypasses removed; `ProjectService.saveBank(lease:)` runs the task-14 bank stage only. Shell-tabs test_l/m/n + swiftcore/shell-voicegroup/shell-songs/bridge green; tabs_lifecycle ledger S186–S192; spec/quality review approved. |
| R09 | complete | [Task 11](task-11-brief.md): finite executor batches preserve `c47b55f4` while allowing Qt events/timers to progress. Actual-source Swift 6.4/Swift 6-mode probe passed FIFO/exactly-once delivery for 128 jobs, pre-application enqueue and nested processing; spec/quality review approved. Linux runtime qualification still requires a host. |
| R10 | complete | [Task 6](task-6-brief.md): drawer comparisons target editable primary notes; clipboard checks preserve whole-document content across ghost projection/track changes. Drawer and clipboard lanes passed; spec/quality review approved. |
| R11 | complete | Task 6: menu checks assert mounted named commands and enablement, not incidental counts/order. Shell-window lane and corrected proof anchors passed; spec/quality review approved. |
| R12 | complete | [Task 8](task-8-brief.md): keyboard labels share the painted keys' clipped gutter; all six contrast profiles and roll lane passed. Native macOS upper/lower clipping observed; spec/quality review approved. A111 ancestry retired; horizontal drum-label overflow remains GAP. |
| R13 | complete | Assessment correction: `runVerify` in `tools/cli.ts` terminates with `Deno.exit(status.code)`; the alleged runtime fallthrough is unreachable. No behavioral fix required. |
| R14 | complete | [Task 9](task-9-brief.md): complete patch relocation/rendering contract verified; count-only diagnostics/tests removed. App/check builds, shell raster, drawer/roll lanes, native Metal load/clean exit and spec/Qt-quality review passed. Git persistence belongs to GIT. |
| R15 | landed | `dc3ae17a`: mounted `tst_ShellGridMenu` drives ruler/time menus through the rendered panel (loop set/remove/undo, Insert Time); `ruler_loop_menu`/`timemenu` ledgers remapped to mounted predicates with PARTIAL demotions for byte-level conjuncts. Its lanes passed in that commit; no separate task review is recorded. |
| R16 | landed | `dc3ae17a`: executed checks for close-tab, surface hide, window deactivate, focus loss, teardown and ungrab cancellation; windowtier-lifetime A045–A048 MATCHED on S057–S062. No separate task review is recorded. |
| R17 | landed | `dc3ae17a`: bridge-retention and mounted-disposal predicates in the swiftroll-window and BridgeProbe lanes; QQuickView rows stay GAP. No separate task review is recorded. |
| R18 | landed | `dc3ae17a`: time-menu clipboard rows and exact signature-chip fixtures driven through the mounted menu; S014 split for the snap-aligned chip. No separate task review is recorded. |
| R19 | complete | Task 2 supplemental proof-only handoff indexed its four executing ghost-keyboard predicates as S078–S081. Frozen source hashes, predicate anchors, structure and execution evidence checked; no A-site disposition changed. Unresolved keyboard behavior prevents whole-ledger retirement. |
| R20 | complete | `e7538e42`: `proof check --strict-mappings` fails on MATCHED sites citing no message-anchored predicate; default `check` reports the same list as a non-fatal debt warning (1,456 sites at introduction — remaining GAP-obligation surface). verification.md records the rule; no bulk ledger rewrite performed. |
| R21 | complete | `f743da6f`: every catalog entry declares `platforms`, the manifest emits them, all 26 Swift lanes register unconditionally as macOS-only, and `run_checks` partitions platform-skipped + exits 2 on a zero-runnable selection. `PORYDAW_CHECK_HOST` simulates a foreign host through `deno task verify`. |
| R22 | landed | `f8489983`: `ShellPresenter.actionEnabled/actionChecked/activate` is the single availability/dispatch authority for menus, shortcuts, context menu and transport buttons; see the landed notes in [repairs/r22-command-authority.md](repairs/r22-command-authority.md) for the QtBridge bound-`Connections` delivery defect. |
| R23 | landed | `dc3ae17a`: memoized note fills, pre-box viewport cull, content-end early return; `checkProjectionEconomy` and `checkRulerSweepSingleTrackScope` executed. |
| R24 | complete | [Task 13](task-13-brief.md): isolated NativeAudio teardown, real null-backend sounding and both final-owner release paths, and actor-qualified dispatch passed. App build, native Metal/Space/normal-exit and consumer gates passed; spec/quality review approved. Native backend coverage remains registered because Swift checks are Apple-gated. |
| R25 | landed | `dc3ae17a`: transport publication deduplicated, `checkSelectedWorkspaceAudio` split into phases, brief-named stale comments removed. |
| R26 | landed (partial) | `f8489983`: keyboard audition pins the pressed track (`checkKeyboardAuditionTrackSwitch`, selection S050). Hidden-tab lifetime, repeated clipping and band-audition projection are not recorded as reassessed. |
| R27 | landed (partial) | `f8489983`: QTP0004 NEW per-directory qmldir, `.qmlls.ini` import root, zero-size font sources isolated. Missing-font and QML lint-import residuals are not recorded as resolved. |
| R28 | blocked | New bank and sample callbacks cannot implement deferred workflows; requires VG03/SA01 scope authorization. |
| R29 | ruled | 2026-09-25 ruling: the `feature/swift-drawer-reactive` drawer-presentation gap files are not a spec. `velocitypres_gap.swift`, `voice_gap.swift` and `drawer_gap.swift` compute one conjunction and report it once per ledger row id (104, 101 and 22 rows; most of the 241 "failures"), and pin pixel constants (`plotWidth == 400`, `rulerWidth == 56`, gutter 584) that contradict font-derived geometry. Porting them would be fake proof and is forbidden. The automation `*_gap.swift` files carry granular assertions against the reactive branch's refactored API and are usable only as leads re-verified against this tree. ED06/ED07/ED08 proceed surface-first from their ledgers (task 21 starts ED07 point menus). |

### Complete product inventory

Details and pinned oracles remain in [inventory.md](inventory.md). “Pending” includes implementation already present but lacking full acceptance. Split obligations retain separate blocked rows rather than blocking an entire package.

| ID | Status | Required outcome |
| --- | --- | --- |
| SH01 | pending | Existing shell routes, checked/enabled state, fixed shortcuts and About; absent registration UI remains PJ03/PJ04. |
| SH02 | pending | Note names/velocity colors across tabs, themes, persistence, fit, ghosts and drag readouts. |
| SH03 | blocked | Appearance/font/grid controls require scope authorization. |
| SH04 | pending | Existing dock sizing/visibility/constrained layout and workspace restoration. |
| SH05 | blocked | New title/dirty/polyphony chrome requires scope authorization. |
| SH06 | pending | Existing window/filter/follow/suppression/volume/debugger preference persistence. |
| PJ01 | pending | Project open/change/startup arguments and dirty-safe failure paths. |
| PJ02 | pending | Existing song search/filter/badges/reuse/deletion and available registration retry. |
| PJ03 | blocked | New Song UI/transaction requires scope authorization. |
| PJ04 | blocked | File-picker MIDI import workflow requires scope authorization. |
| PJ05 | pending | Ordered document/config/bank saves, conflicts, stale completion and byte conservation. |
| PJ06 | complete | [Task 18](task-18-brief.md) accepted: `proof.tabs_lifecycle.txt` retired (74 MATCHED via new shell-tabs test_o/p/q/r + amended e/j/k + swiftcore); `proof.tabs_persistence.txt` 34 MATCHED/1 PARTIAL (A044 mixer-volume relaunch belongs to transport-settings surface)/36 RETIRED-*. Reload preserves same `tabId` + seeded view state (BEHAVIOR-GAP repaired in `SongTabsController`/`ApplicationSession`); fresh tab homes `scrollX` to `minHScroll` (repaired in `PianoGrid.configureViewport`). Shared-bank lifetime + restored recipe proven. Remaining `proof.session`/`tabs_scale`/`tabs_transport` GAPs route to PJ07/ED05/AU03. |
| PJ07 | pending | View/lane/workspace persistence without writing project song sidecars. |
| VG01 | pending | Existing browsing, typed voice edits, readonly forms and audition. |
| VG02 | pending | Symbol pickers, metadata, unknown symbols and audition envelopes. |
| VG03 | blocked | Create/copy-bank workflow requires scope authorization. |
| VG04 | pending | Synth preview/deduplication and referenced-definition save/include behavior. |
| VG05 | pending | Shared-bank two-song lifecycle; consumes R07/R08. |
| SA01 | blocked | Sample Studio launch/source/reopen requires scope authorization. |
| SA02 | blocked | Full decoder/SoundFont workflow requires scope authorization. |
| SA03 | blocked | Sample DSP/waveform/loop/local-history workflow requires scope authorization. |
| SA04 | blocked | Complete sample-editor audition journey requires SA01–SA03; existing primitive remains in AU03. |
| SA05 | blocked | Sample commit/registration/assignment requires scope authorization. |
| SA06 | blocked | Provenance and changed/missing-source reopen requires scope authorization. |
| AU01 | blocked | Production WAV export workflow requires scope authorization. |
| AU02 | blocked | Complete export cancellation/error/duration/suppression journey requires AU01. |
| AU03 | pending | Transport/seek/loop/follow/live edits/settings/audio; consumes R02/R05/R24. |
| AU04 | pending | Polyphony Debugger counters/inversion/jumps and lifecycle, including rendered flash-state contrast; the incoming ink correction has a contrast calculation but no executing flash-state lane predicate. |
| AU05 | pending | Existing transport preferences; absent compact meter remains SH05. |
| ED01 | pending | Note gestures/collision/history/ghost exclusion and rendered selection. |
| ED02 | pending | Shared camera, zoom/pan/scrollbars/follow/playhead. |
| ED03 | pending | Track mutations/remaps/mute/solo/voices/activity/budget. |
| ED04 | pending | Ruler/loop/signature/time menus and playing-state seek. |
| ED05 | pending | Per-tab scale/fold/highlight and scale-aware motion. |
| ED06 | pending | Velocity scope/grouping/PSG detents/prompts/history. Surface-first from its ledgers; see the R29 ruling. |
| ED07 | pending | Automation/strokes/clipboard/delete/tap tempo/opaque events. Surface-first from its ledgers; point menus are task 21. See the R29 ruling. |
| ED08 | pending | Voice-change picker/preview/commit/cancel/remaps/persistence. Surface-first from its ledgers; see the R29 ruling. |
| ED09 | pending | Event payload/order/tempo/EOT/unknown-data preservation. |
| ED10 | pending | Pitch-bend curve/input/accept/cancel/lifetime. |
| ED11 | pending | Clipboard interoperability/precedence/paste/remap/text ownership. |
| ED12 | pending | Shortcut/popup/numeric-Space ownership and every cancellation cause. |
| PL01-macOS | pending | Current-host package/runtime and nonempty check qualification. |
| PL01-Linux | blocked | Requires available Linux runtime/toolchain host; source-level portability repairs remain R09/R21. |
| PL01-Windows | blocked | Requires Windows MSVC/Swift/Qt runtime host. |
| PL02 | pending | Large-document responsiveness/audio stability/cancellation/release for existing surfaces. |
| DOC01 | pending | Manuals and release/platform claims for completed surfaces; never claim deferred delivery. |

### End-to-end objective gate

| ID | Status | Required journey |
| --- | --- | --- |
| J01 | pending | Existing composition edit/undo/save/relaunch; independent MIDI conservation. |
| J02 | blocked | New composition requires PJ03/VG03 authorization. |
| J03 | blocked | External MIDI journey requires PJ04 authorization. |
| J04 | pending | Shared instruments edit/play/switch/undo/save/relaunch. |
| J05 | blocked | Sample asset journey requires SA01–SA06 authorization. |
| J06 | blocked | Unsaved-state export journey requires AU01/AU02 authorization. |
| J07 | pending | Native window/focus/popup/gesture/asynchronous teardown. |
| J08 | pending | Existing settings and constrained-layout reopen. |
| J09 | blocked | Clean-host distribution depends on complete authorized product and platform hosts. |
| FINAL | pending | Settled ALL/SHELL/DRAWER/ROLL/PROOF/EXECUTED/format/review gates; report batch and overall status separately. |

Tasks 4–11 and the task 2 ghost-predicate handoff were accepted and pushed with integration `fea4034d`. That merged current-host app built in 92.17s; native suite passed 31/31 (20.61s), shell 26/26 (58.66s), drawer four profiles (35.04s), and roll (22.97s). Its proof classification had 9,491 resolved anchors, 8,863 executed, 13 not executed and 615 unverifiable. Tasks 12/13 then passed their bounded CORE/projectstore/audio/voicegroup/tabs/transport/polyphony/app/bridge/proof/format gates and both spec/quality reviews. Latest proof classification is 9,496 resolved, 8,868 executed, 13 not executed and 615 unverifiable; this is not full parity. Native Metal rendered `mus_route101`, actual Space advanced playback and normal Cmd-Q exited zero. See [handoff.md](handoff.md) for exact commands, observations, limits and review rulings. Font warnings remain R27; SourceKit indexing remains 0/0. No next implementation task was started.

## Inspected baseline

- Swift branch revision: `3029be5639d8f13c1f57db5e4a822a48dedcd119`.
- Pre-widget-deletion source reference: `b28f082758e63ef3cd2868f9205b96acfffb94f5` (`ab73ca06^`). Each proof ledger's own pinned revision remains authoritative for its original assertion.
- `feature/swift-project-store` at `91e714d2` and `feature/swift-qml-grid-rollqml-checks` at `d861f8c3` are already ancestors of this baseline. Do not re-plan their merges or reimplement their existing owners.
- `1096534c7d3e97c17a785625a93a215459c39d6e` subsequently integrated menu and roll display-mode work. Inventory line anchors describe the earlier research snapshot; re-verify each claim at brief freeze rather than reimplementing those changes. The former menu handoff is consolidated in [shell migration history](../../old/swift-migration-shell.md).
- The proof reader currently indexes 188 proof files; `proof list --no-swift` selects 38. Those numbers are **not** a completion percentage. Some missing counterparts are real missing surfaces; others are stale/partial mappings or native observations.
- `INSTALL.md` reports a working Linux ARM64 Swift build as well as macOS. Windows remains pending. Older macOS-only statements and old check commands are not a current support matrix.

### Evidence precedence

1. Shipped C++ behavior in source and its historical checks.
2. Existing files, written formats and manuals describing shipped workflows.
3. Current production Swift/QML call path and actually registered checks.
4. Old specifications/plans as research leads, not proof of shipping or completion.

If these disagree, record the concrete behavior difference and resolve it before the affected brief freezes. Do not quietly pick the easier contract. `SPEC.md` contains both shipped-feature sections and aspirational roadmap items; do not count the latter as lost functionality without source evidence.

## Global constraints

- Swift owns application/domain behavior; QML owns rendering/input delivery through existing QtBridge patterns. Keep the poryaaaa/native platform seams narrow. No QWidget resurrection, C++ presenter mirror, generic dispatcher or new compatibility layer.
- Reuse `ApplicationSession`, `DocumentSession`, `DocumentWorkspace`, `ProjectService`/`ProjectStore`, `SongTabsController`, `VoiceListController`, `VoiceEditorController`, `NativeAudio`/`AudioRenderEngine`, the existing command registry and shell composition. One document/history authority, one window shortcut authority, one authoritative project store.
- Data safety comes before visual equivalence: preserve opaque MIDI, exact ordering where meaningful, config flags, unrelated project bytes, bank-save conflict behavior and dirty/save identity. Audition is not commit; sample write-through is not song undo; bank assignment is undoable.
- Complete each surface through its production entry point, cancellation/error path, persistence/audio result and behavior checks. No disabled placeholder action or test-only implementation can close an inventory row.
- Follow the current font-derived geometry, unhinted font and GridPalette contrast rules. Preserve keyboard and accessibility routes; bare Space in persistent chrome remains transport-owned. Do not copy obsolete pixel constants or old low-contrast colors as compatibility requirements.
- Visual parity with the QWidget app is required (user direction, 2026-09-25). A rebuilt or touched surface reproduces its QWidget counterpart in the last pure C++ app, fork-main `fceecd88` (runnable reference build: `build-asan/porydaw.app` in the main checkout, ≈ `6cd77773`): control types, order, labels, grouping, alignment, per-state visibility, menu rows and focus indication, with relative sizes expressed through font metrics and colors through GridPalette pairs. `b28f0827` is a mid-migration hybrid and is not a visual reference for surfaces rebuilt in Qt Quick after the Swift migration began. Each brief names the counterpart source and the visual contract, and acceptance includes comparing a capture of the real Swift surface against that reference with every deviation listed and justified.
- Proof work is surface-local and accompanies the code/checks it proves. Use the proof-only ledger handoff and acceptance policy in [verification.md](verification.md). Delete a completed proof file and its obsolete C++ check when the Swift/QML replacement is validated; retain unresolved GAP/PARTIAL behavior as the remaining spec. No standalone reconciliation/count-reduction/deletion waves.
- The controller runs shared builds/checks after writers settle. Reuse the exact commands recorded in verification and the frozen briefs; reassess only on a concrete scope/command mismatch. Native desktop and platform checks require the relevant host, not an offscreen substitute.
- Preserve independently owned work. Serialize edits to shared composition/build/registration files; parallelize domain work only with explicit ownership. Checkpoint accepted work before another task reuses its files; push every commit made. The accepted repair/integration batch is pushed as `fea4034d`.
- Preserve the Linux Swift-main-actor/Qt GUI event-loop integration from `c47b55f4` and `ProjectContext`'s dedicated native-loader worker. The user reports that a Linux Qt timer/thread-affinity issue was fixed today; actor cleanup must not undo either ownership boundary.
- Authorized bank-safety policy: extend existing project/window Save–Discard–Cancel handling to every dirty bank, including unbound banks. Ordinary Save stays current-song/current-bank-only; changing `-G` does not autosave or prompt. This explicitly repairs the inherited orphan-bank close gap without authorizing new unrelated UI.

## Dependency-ordered work packages

All behavior packages route **SDD-track / `sdd-implementer`**: they change user-visible contracts, persistence, asynchronous lifetimes, or multiple surfaces. The package is a milestone, not a single oversized task. Pure final removal of fully replaced, explicitly allowlisted source is Direct and belongs to its owning surface, not a separate cleanup project.

| Package | User outcome and scope | Depends on | Acceptance basis |
| --- | --- | --- | --- |
| P1 — Shell completeness and roll display | Restore missing action/keyboard routes, including pitch bend, velocity and loop commands, close-tab/register-song, transport/drawer actions and About; restore velocity colors/note names and ghost-track context. | Baseline inventory | SH01–SH02, ED01/ED10/ED12; CORE + SHELL + ROLL; actual menus and shortcuts |
| P2 — New Song and MIDI onboarding | Create a song, import external MIDI through the file picker, choose/create a bank, analyze/convert, write and register safely, retry partial registration. | Existing ProjectStore; P5 bank-creation contract; shared shell mount after P1 writer settles | Onboarding/project rows; PROJECT + CORE + shell-songs plus new production onboarding lane |
| P3 — WAV export | Export current unsaved song/bank state with old format/rate/loop/fade/tail/settings behavior, progress, cancellation and errors. One production rendering/writing implementation used by app and checks. | Existing playback/leases; explicit snapshot/job contract | WAV rows; EXPORT rewritten to call production owner + CORE + new export shell lane + independent WAV inspection |
| P4 — Sample Studio | Complete file/SoundFont source selection, non-destructive editor/DSP/loop tools, engine-true rendered audition, write-through registration, provenance/reopen and voice assignment through the existing sample catalog. | Existing ProjectStore/voice/audition owners; explicit decode/DSP/project-write contract | Sample rows and all seven samplecheck ledgers; new Swift sample checks + production shell/editor lane + ROM asset comparison |
| P5 — Voicegroup completion | First restore shared-bank cross-tab correctness and create/copy-bank workflow; then finish picker/editor proof gaps and integrate New/Edit Sample return paths. Preserve typed edits, synth definitions, audition and save conflicts. | Existing bank owner; creation precedes P2; only the sample return path consumes P4 | VG01–VG05; CORE + PROJECT + BANK + shell-voicegroup + two-tab edit/save/undo journey |
| P6 — Editor interaction parity | Restore modifier-scoped ruler sweeps, exact loop-chip hit/seek behavior and concrete roll/track/drawer/event-list/pitch-bend/clipboard differences, one surface at a time. Do not rebuild already-mounted panels. | Existing editor; P1 where display modes overlap | Editor rows and their ledger families; CORE + SHELL + DRAWER + ROLL, scoped per surface |
| P7 — Preferences and workspace ergonomics | Restore appearance controls, title/dirty indication, status polyphony meter, missing preference writes and window/dock/song-view persistence. Preserve fixed shortcuts; no remapping UI. | P1; serialize shell/settings edits with P2–P6 mounts | SH03–SH06, PJ07, AU05; shell-settings/theme/typography/tabs + native reopen journey |
| P8 — Native lifecycle and audible integration | Prove real keyboard/focus/popups, gesture cancellation, tab/project close, async teardown, engine accuracy/telemetry and responsive interaction across the completed surfaces. Repair concrete mismatches in their existing owners. | Can add scenarios throughout; final acceptance after P1–P7 | Native/audio rows; CORE + all QML lanes + actual desktop/device scenarios |
| P9 — Platform and distribution parity | Qualify Swift toolchain/QtBridge/runtime/packaging and real workflows on supported macOS architectures, Linux and Windows MSVC; reconcile platform check exclusions and support claims. | Toolchain work can begin immediately; full journeys consume P1–P8 | Platform row; per-platform production packages and applicable nonempty checks |
| P10 — Full-product acceptance | Execute no-loss journeys, reconcile only feature-owned evidence, audit all inventory obligations, update user documentation and retire only proved obsolete code. | P1–P9 for full cross-platform parity | Complete release exit in verification.md |

P3's effective-bank snapshot contract and P4's bank assignment/commit-visibility contract depend on the P5/VG05 shared-bank policy being frozen first; their independent rendering/DSP work need not wait. Implement and verify bank coherence before accepting either complete journey. P1 restores routes for existing behavior only: P2 mounts New Song/Import MIDI, P3 mounts Export WAV, P4 mounts Import Sample, and P7 mounts Theme when their real workflows are ready. Compare the complete registry/action/menu sets when freezing briefs, not only the examples in SH01; never mount a dead action.

## Implementation order and parallelism

1. **Accepted repair wave.** Tasks 4–8 repaired project operations, workspace/transport, QML consumers, queued voice identity and contrast. Covering native/QML/proof gates and task reviews passed; checkpoint accepted work before reusing its files.
2. **Handoff: shared-bank safety and audio lifetime accepted.** Tasks 12/13 are complete at this checkpoint. The next implementation is [task 14](task-14-brief.md), same-file section preservation, followed by a bounded brief for the authorized all-dirty-bank close policy. The user requested a stop and handoff; these and other independent obligations remain pending for the successor.
3. **Continue existing-surface parity (remaining P1/P5/P6/P7).** Freeze one behavior-sized brief at a time from current source and original assertions. Do not replay the three completed briefs or treat their partial proof coverage as full native parity.
4. **Deferred delivery and release.** P2–P4 and absent P5/P7 workflows require scope expansion before implementation. Their dependency contracts below remain reference material, not authorization to add UI. P9 requires platform evidence; P10 stays blocked until the full required scope is accepted.

A checkpoint is a coherent accepted behavior boundary, not one commit per task. Earlier file-ownership checkpoints can satisfy a nearby milestone. Unreviewed or failing work is repaired before reuse.

## Historical migration records

Superseded plans and task briefs have been consolidated into the records below. They preserve decisions, provenance and historical findings, not executable work queues. This plan remains the active parity roadmap.

| Historical record | Retained information |
| --- | --- |
| [Core and bridge](../../old/swift-migration-core.md) | Core ownership, history semantics, QtBridge boundary decisions and superseded cutover alternatives |
| [Editor migration](../../old/swift-migration-editors.md) | Camera/drawer/editor behavior contracts, check migration, retirement limits and historical input failures |
| [Project and dock migration](../../old/swift-migration-project.md) | Project persistence, bank leases/save conflicts, voice/sample workflows and recorded integration milestones |
| [Shell and parity audit](../../old/swift-migration-shell.md) | Fixed shortcuts, shell integration, menu handoff and the limits of earlier parity audits |
| `docs/old/sample-editor/` | Separate retained reference for shipped sample algorithms, formats and project refusals; not a dispatch plan |

## Scope decisions and unresolved design prerequisites

- **No feature removal is approved by this plan.** Missing shipped behavior stays an obligation even if its old C++ source is already deleted.
- **Do not expand parity into never-shipped features:** sample rename/delete management, 16-bit sample-output toggle, automatic wav2agb installation/legacy AIF writing, MIDI recording, plugin hosting, keysplit-table editing, audio-device selection, track-header volume/pan mini-sliders or shortcut customization. Current manuals explicitly specify fixed shortcuts. Window-level MIDI file-drop and song-package transfer were not established in the inspected baseline; the required import route is its file picker, not an invented drop/package workflow. About did ship despite a stale backlog entry.
- **Sample implementation prerequisite:** choose a decoder strategy that preserves every supported format and the old deterministic PCM/build contract without putting application behavior back into C++. Define isolation, cancellation, immutable decoded source, derived audition bytes, registration and provenance before code dispatch. A decoder-library C seam is a separately justified technical decision, not blanket permission to port the old C++ pipeline.
- **WAV implementation prerequisite:** define an immutable capture of unsaved document + effective bank + settings, its lease lifetime and cancellation/file-publication contract. Do not render from saved MIDI or borrow the live audio engine. Preserve the old UI's stop-playback-before-render behavior, configurable loop/fade/tail law and suppression pre-roll; concurrent live playback export is not a new parity requirement.
- **Onboarding prerequisite:** the existing store's registration/read/edit behavior is not a complete create/import transaction. Freeze the write order, partial-success/refusal behavior, identity refresh and dirty-tab/project-close interactions before wiring buttons.
- **Platform prerequisite:** native-host/toolchain execution is needed to certify platforms not exercised here. Existing setup/build files and historical documentation are evidence of intent, not a passing runtime gate.

## Historical planning-pass evidence

The initial documentation-only pass inspected production sources, legacy references, manuals, registrations and proof tooling, and ran proof-list/CLI-help commands. Application implementation and verification happened afterward; see [current-surfaces.md](current-surfaces.md) for that completed batch. The initial snapshot must not override the execution status above.
