# Context

Reconcile the seven samplecheck assertion inventories and the sample-editor slice of the historical dialog visual inventory against the runnable Swift/QML behavior delivered by tasks 10–12. Task 11 owns processing predicates; task 12 owns project/editor lifecycle predicates; task 10 owns the production QML editor and its frozen visual pins. Task 17 consumes these correspondence records before retiring the allowlisted uncompiled C++ sources. Task 13 is the separate voicegroupsave/browser proof package and is not part of this write set.

The seven samplecheck inventories currently contain 493 sites (418 GAP, 75 NATIVE): 229 processing sites across 30 methods and 264 lifecycle sites across 32 methods. They are historical source oracles, not an executable C++ suite: do not create, enable, or invoke a `samplecheck` target. Map only `src/checks/visual/proof.dialogs.txt` sites A010–A015; its unrelated dialog sites remain outside this task.

# Exact write set

- `src/checks/samplecheck/proof.analysis.txt`
- `src/checks/samplecheck/proof.decoder.txt`
- `src/checks/samplecheck/proof.dsp.txt`
- `src/checks/samplecheck/proof.editor.txt`
- `src/checks/samplecheck/proof.integration.txt`
- `src/checks/samplecheck/proof.project.txt`
- `src/checks/samplecheck/proof.soundfont.txt`
- `src/checks/visual/proof.dialogs.txt` — only the sample-editor-specific A010–A015 mapping and summary counts made stale by those six entries.

This is a closed write set. Do not edit source, check implementation, build registration, fixture, baseline, any other proof inventory, or any other site in `proof.dialogs.txt`. Do not delete source files; task 17 alone owns its allowlist.

# Prerequisites

Tasks 10, 11, and 12 must have delivered their contracts and already passed their named SwiftCore, SwiftRollGated, and visual checks; task 14 consumes those results rather than rerunning them. Consume the exact sample-processing method predicates and `cppID` contract in task 11; the exact sample lifecycle method predicates and `cppID` contract in task 12; and task 10's production QML editor visual comparisons for `sample-editor/dialog-vanilla` and `sample-editor/dialog-darkneutralhigh`. Task 10 must explicitly assert in the visual slots that `preparedSampleWav` imports through task 11's processing path before capture; A010/A013 mapping depends on that assertion passing. Task 10's visual command requires a native desktop and connected 2x display. Tasks 13 and 14 are disjoint proof packages after task 12. Task 15 owns the history/viewcache behavior predicates; task 16 proof depends on task 15. Task 17 waits for tasks 13, 14, and 16 and all behavior/visual gates.

# Interface contract

- Preserve the following historical source pins verbatim. Keep each inventory's `Reference revision`, `Original`, `Original SHA-256`, all original `A###` identities (including method and source location), assertion expression, and source context/sequence. Do not regenerate or renumber sites, recompute the historical source hashes from edited ledgers, flatten data rows/loops, or replace context with a count summary.

  | Inventory | Original source | Reference revision | Original SHA-256 | Sites / current tally |
  |---|---|---|---|---|
  | `proof.analysis.txt` | `src/checks/samplecheck/analysis.cpp` | `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea` | `da34a411ca0833f4ad3ed01404c49b8e8eee735abc4a5b49b321088e08fbb582` | 35 / 31 GAP, 4 NATIVE |
  | `proof.decoder.txt` | `src/checks/samplecheck/decoder.cpp` | `5af4355e8fc1337f38da60c545da4af246160bcf` | `567e1efd7c3739345c23cadd4fd8ebbc5b9c422c74e6fd252454472f5f1e0d03` | 93 / 93 GAP |
  | `proof.dsp.txt` | `src/checks/samplecheck/dsp.cpp` | `1f9f8a5faa78069bf86c0ed9997c04c07f1f37d7` | `54d949e10083ce459182fa650cae3eb9d601769ab5fa6a052286cfe0924b6b7d` | 67 / 61 GAP, 6 NATIVE |
  | `proof.editor.txt` | `src/checks/samplecheck/editor.cpp` | `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea` | `1ae310e3a37396448c692a91dbd51cac6ed6681ebf0b55e352ee2c488545f99b` | 130 / 80 GAP, 50 NATIVE |
  | `proof.integration.txt` | `src/checks/samplecheck/integration.cpp` | `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea` | `6c9de17973a3ede8a7dd643d494f606a9c1fb0b0fab1742a2b6f7d84abc2bf49` | 71 / 68 GAP, 3 NATIVE |
  | `proof.project.txt` | `src/checks/samplecheck/project.cpp` | `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea` | `a30e72511768146ff4e27a3c2fbb4c9feb7bb1266b71d0caadff1d267e093146` | 63 / 63 GAP |
  | `proof.soundfont.txt` | `src/checks/samplecheck/soundfont.cpp` | `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea` | `6e45372c5a0d33c5d55f1a07d883a5ba5c65a9833877a07076ea517ed1fba310` | 34 / 22 GAP, 12 NATIVE |

- For every original samplecheck assertion site, use the source method identity and original expression/context to select its corresponding runnable predicate. Task 11's exact processing predicate names are:
  - `proof.analysis.txt`: `pitchMatrix`, `pitchNegativeCases`, `loopAndCrossfade`, `auditionSlotLifecycle`.
  - `proof.decoder.txt`: `decodeWidths`, `decodeStereoPolicy`, `decodeAiff`, `decodeRefusalBoundaries`, `compressedContainers`, `compressedRefusals`, `optionalCorpus`.
  - `proof.dsp.txt`: `dspDeterminism`, `markerMapping`, `normalization`, `parityCases`, `parityLoopGeometry`, `parityRiffPadding`, `quantizationDither`, `quantizationU8Roundtrip`, `quantizationVectors`, `resampleAliasRejection`, `resampleDcGain`, `resampleFrequencyAccuracy`, `resampleIdentity`, `resampleImpulseSymmetry`, `resamplePassband`, `retuneVectors`.
  - `proof.soundfont.txt`: `soundFontExtraction`, `soundFontPicker`, `soundFontRefusals`.
- Task 12's exact lifecycle predicate names are:
  - `proof.editor.txt`: `editorAuditionStrip`, `editorCommit`, `editorCrossfade`, `editorDrag`, `editorLoopPopulate`, `editorLoopRefine`, `editorPitchAdoption`, `editorScroll`, `editorSplitter`, `editorUndo`, `pipelineCropNormalize`, `pipelineKeyOverride`, `pipelineLoopToggle`, `pipelinePrefillCollision`, `pipelinePreparedDefaults`, `pipelineRateCommit`, `spaceAudition`.
  - `proof.integration.txt`: `engineLoop`, `sampleUpdate`, `sampleUpdateRefusals`, `sidecarEditDialog`, `sidecarFallback`, `sidecarRemove`, `sidecarRerender`, `sidecarRoundtrip`, `sidecarTouchedSource`.
  - `proof.project.txt`: `projectCrlf`, `projectDuplicate`, `projectInspect`, `projectProbe`, `projectRegister`, `projectSanitizeValidate`.
- Task 12's corrected per-method lane assignment puts `engineLoop` in SwiftCore and `pipelinePrefillCollision` / `pipelineRateCommit` in SwiftRollGated; use the corrected task 12 brief for all other lifecycle methods. Task 11's `auditionSlotLifecycle` maps to the existing predicate in `src/checks/audio/AudioAuditionChecks.swift`; do not assume or create a duplicate.
- The check identity for each method is exactly `samplecheck/SampleProcessingTest::<method>` as specified by tasks 11/12. Name the actual runnable predicate and exact observed check identity in each site's `Mapping/reason`; a matching method name alone or a file/method-wide count is not evidence. Compare each site to the predicate's assertion and exercised branch/row. A site may be `MATCHED` only when that predicate actually observes the original behavior.
- Update stale proof metadata that still says no Swift counterpart exists or that the uncompiled C++ harness owns current execution. Keep the historical reference revision and original source hash unchanged; name the real counterpart/check sources and exact verification command/result. Update disposition tallies to match the individual entries. Do not claim that a structural check establishes source freshness or semantic parity.
- Reconcile visual site identities individually, retaining the original visual inventory's `Reference revision` `4346c26abdcab317ccf97e178c959a82301081c9` and `Original SHA-256` `83b7c5889b8c614092920dd3054fe74bc478aa8fb3c4ddcce7dd515cc2c2428c`:

  | Site identity | Original observation | Required runnable counterpart |
  |---|---|---|
  | A010 `VisualDialogsTest::sampleEditorVanilla` (`src/checks/visual/dialogs.cpp:560`) | `preparedSampleWav` imports successfully for the vanilla editor fixture. | Task 10's runnable vanilla visual slot must explicitly assert that the same prepared WAV imports through task 11's processing path, then compare `sample-editor/dialog-vanilla`; map A010 only after that assertion and visual run pass. |
  | A011 `VisualDialogsTest::sampleEditorVanilla` (`src/checks/visual/dialogs.cpp:565`) | `sampleLoopOn` exists before enabling deterministic loop chrome. | The vanilla visual predicate must find/set the production QML loop control/region and compare `sample-editor/dialog-vanilla`. |
  | A012 `VisualDialogsTest::sampleEditorVanilla` (`src/checks/visual/dialogs.cpp:570`) | Sample-editor waveform, crop/loop handles, seam, and splitter regions are observable. | The vanilla visual predicate must resolve the task 10 QML regions and compare `sample-editor/dialog-vanilla` at the fixed 900x640 editor size. |
  | A013 `VisualDialogsTest::sampleEditorDark` (`src/checks/visual/dialogs.cpp:579`) | `preparedSampleWav` imports successfully for the dark editor fixture. | Task 10's runnable dark visual slot must explicitly assert that the same prepared WAV imports through task 11's processing path, then compare `sample-editor/dialog-darkneutralhigh`; map A013 only after that assertion and visual run pass. |
  | A014 `VisualDialogsTest::sampleEditorDark` (`src/checks/visual/dialogs.cpp:584`) | `sampleLoopOn` exists before enabling deterministic loop chrome. | The dark visual predicate must find/set the production QML loop control/region and compare `sample-editor/dialog-darkneutralhigh`. |
  | A015 `VisualDialogsTest::sampleEditorDark` (`src/checks/visual/dialogs.cpp:589`) | Sample-editor waveform, crop/loop handles, seam, and splitter regions are observable. | The dark visual predicate must resolve the task 10 QML regions and compare `sample-editor/dialog-darkneutralhigh` at the fixed 900x640 editor size. |

  Cite the actual registered task 10 check/predicate name as well as the exact pin above. Do not claim the retired `VisualDialogsTest` is runnable Swift/QML evidence. If a task 10 predicate does not exercise the named fixture/control/region, report the exact site and leave it unmatched; do not infer coverage from a related screenshot.
- Every site needs its own truthful `Disposition` and `Mapping/reason`. Behavior sites must map to a named runnable Swift/QML predicate. A `NATIVE` or `NATIVE-SETUP` entry is allowed only for a genuinely non-behavior setup obligation, and its reason must name the Swift/QML fixture or predicate it supports and explain why it is not a product behavior assertion. Such a setup disposition does not cover any behavior site. No behavior-level GAP, PARTIAL, or NATIVE exception is acceptable at task-17 retirement; an actual missing predicate stays GAP and blocks that retirement gate. Recompute all affected tally/summary counts; never leave a blanket GAP/NATIVE disposition because it was the historical starting state.

# Implementation steps

1. Confirm tasks 10–12's exact check registrations and already-green results before mapping. Use task 12's fixed split of 18 SwiftCore predicates and 14 SwiftRollGated predicates; specifically, `engineLoop` is SwiftCore while `pipelinePrefillCollision` and `pipelineRateCommit` are SwiftRollGated. Verify the remaining method assignments against task 12's corrected brief and landed results, and consume passed evidence without rerunning predecessor commands.
2. For each of the 493 existing samplecheck `A###` entries, compare its original expression and source context with the named predicate above. Update that site only with a truthful disposition and mapping/evidence. Preserve all site identities, order, reference metadata, hashes, source context, branch and row constraints, and optional-corpus semantics. Replace stale native-runner verification/ownership claims with the real Swift check ownership and observed results.
3. Map only visual/dialogs A010–A015 to the matching task 10 visual predicates and their exact pins. Keep the other 21 visual dialog entries unchanged; update only the aggregate summary needed to reflect the changed six site dispositions.
4. Audit that all 493 samplecheck records and all six targeted visual records remain represented, mappings name actually registered predicates/fixtures, counts reconcile, and all eight proof files remain present. If any behavior site is not covered, preserve the truthful GAP and report its exact ledger/site and owning predecessor; do not waive it to satisfy the tally.

# Acceptance predicate

- All seven samplecheck ledgers remain present with exactly 493 original site identities and provenance (35 analysis, 93 decoder, 67 dsp, 130 editor, 71 integration, 63 project, 34 soundfont). Every behavior assertion maps individually to its exact runnable predicate and observed check identity; no count-only or method-wide blanket claim. Any remaining setup-only NATIVE/NATIVE-SETUP entry names its supporting Swift/QML fixture/predicate and rationale. No behavior-level GAP/PARTIAL/NATIVE remains for task 17; a truthful uncovered GAP blocks task 17.
- `proof.dialogs.txt` retains A010–A015 and their original source identities, maps each to its specified QML visual predicate, and leaves all unrelated entries unchanged. The referenced task 10 results must show both named editor pins passing in both `visual-swift-12` and `visual-swift-16`, using frozen baselines, a native desktop, and a connected 2x display.
- The exact commands below are required predecessor evidence and must already have successful runtime results before task 14 starts. Their owners are tasks 10–12; task 14 consumes the results and does not rerun these commands:
  - `deno task verify --filter swiftcore --verbose` — task 11's 30 processing predicates and task 12's fixed 18 SwiftCore predicates pass and report their exact `samplecheck/SampleProcessingTest::<method>` identities.
  - `deno task verify --filter swiftrollgated --verbose` — task 12's fixed 14 production-QML lifecycle/editor predicates pass and report their exact method identities.
  - `deno task verify --filter visual-swift --verbose` — both task 10 sample-editor pins match their frozen baselines in both font profiles and both visual lanes (`visual-swift-12`, `visual-swift-16`). A native desktop plus connected 2x display is required; do not record new baselines.
- Task 14's only verification command is `deno task proof check`, run after the prerequisite results above are recorded green. It must exit successfully with no proof structure or tally errors. This command validates proof grammar, metadata presence, unique site entries, and present tally consistency only; it does not validate original-source freshness, execute a predicate, or prove parity. Do not run `deno task verify --filter samplecheck` or treat the old C++ source suite as evidence.

# Task-specific constraints

- Read-only source oracles are the original `src/checks/samplecheck/*.cpp`, `src/checks/samplecheck/fixtures.*`, task 10 QML/visual sources, and the task 11/12 check implementations. Do not add tests or test registrations in this correspondence-only task.
- Keep every `proof.*.txt` inventory and frozen fixture/baseline after reconciliation. No source retirement belongs here; task 17 consumes the completed evidence separately.
- Task 12's lane split is fixed by its corrected brief: 18 named SwiftCore predicates and 14 named SwiftRollGated predicates; `engineLoop` is SwiftCore, while `pipelinePrefillCollision` and `pipelineRateCommit` are SwiftRollGated. Confirm all methods against landed registrations and prerequisite results; if they disagree, report the exact predicate and owner rather than reassigning a lane or rerunning task 12.
