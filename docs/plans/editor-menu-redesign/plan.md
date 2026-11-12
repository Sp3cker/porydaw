# Editor menu redesign

## Goal
The user asked Claude Opus5.5 to redesign the MIDI Effects and voice-select menus because both look poor. Deliver the redesigned working production surfaces, not mockups. Desktop/macOS first, keeping cross-platform QML/theme behavior. Existing locale and pointer/keyboard/accessibility conventions remain.
The user's refinement removes the voice-count and preview-hint labels: title, search, list, essential empty state, Cancel/OK only.

The user subsequently approved all four findings in the Impeccable rack critique. Task 3 is a continuation of this menu refinement, governed by `task-3-brief.md`: active-effect identity/Live state, render scoping, secondary library/compact diagnostics, and explicit staged replacement. That brief supersedes the original no-Swift/no-interaction-change restriction only for this surface's presenter and necessary consumers; native/audio/lifecycle owners remain unchanged. No commit, push, or merge is authorized.

## Global Constraints
- Work only in the VST worktree; do not merge, rebase, switch branches or touch main/fork-main. Captured BASE is 290d15671db8d3e8f2e49d63ecc9579e1ea2d5a0.
- This is a visual/interaction-layout redesign of two production QML overlays, not a behavior or backend rewrite. Preserve all existing model calls, guards, public/root properties, signals and consumer objectName identities. No Swift, native/audio/VST lifecycle or QtBridge surface changes.
- Use existing PromptOverlay, PromptCard, PromptAction/PromptButton, typography and GridPalette-derived PromptStyle pairs. Shared controls are read-only. No new theme tokens, literal colors, opacity-dimmed text, assets, shadows, animations, font families, dependencies or focus manager.
- Both surfaces should feel like one family: calm dense desktop dialogs, clear title/context, deliberate padding, framed content/list, consistent footer actions. Creative layout/detail decisions belong to Opus. Functional hierarchy comes before decoration. Geometry scales from existing resolved font/style metrics and clamps to the available window; no fixed pixel geometry. Long names/errors and larger text must not overflow.
- Maintain WCAG AA: windowText on neutral/hover/alternate surfaces, pressedText only on pressed background, selectionText only on selection; disabled text only when actually disabled. Secondary text only on permitted neutral surfaces. Keep keyboard focus visible and pointer/AX/keyboard operability.
- Preserve native Qt/QML focus/navigation and Loader ownership; no synthetic forwarding or new focus state machine. MIDI effects continues yielding bare Space to transport; voice picker keeps its existing search/modal audition/keyboard semantics. Closing/canceling never changes document state; release audition on every exit.
- Do not parse labels/status strings to invent semantic model data. Do not add search/filter/backend features not already provided. No unrelated cleanup or test deletion/repinning (except Task2's explicitly named obsolete geometry pins). Existing behavior checks remain unchanged unless an actual contract requires correction.
- SHARED_TREE: implementers do only read-only file-local inspection and edit their owned QML surface plus only explicitly named check pruning. No builds/checks/tests/lint/format/index/reconfigure/profiling/desktop actions/commits/subagents. Report all runtime checks DEFERRED_TO_CONTROLLER. Controller owns docs, shared verification, screenshot proof, reviews and final checkpoint/push. No proof ledgers are in scope.

## Tasks
1. Opus designs and implements MIDI Effects in MidiEffectsPanel.qml.
2. Opus designs and implements the shared production voice picker in VoicePickerPrompt.qml.
The tasks are independent and may run together; neither edits shared prompt controls. Controller applies visual/behavior verification and independent review, then one coherent checkpoint.
3. Refine the existing MIDI Effects rack against the approved critique; implement and verify the presenter/view/caller cutover as one cohesive task.

## Verification
- uv run --no-sync dev checks:shell --filter shell-midieffects --filter shell-effect-output --filter shell-text-contrast --no-windowing-checks --pool=3
- Drawer (14 voice cases, with the lane's production/container routing):
  ```sh
  uv run --no-sync dev checks:qml --filter editorqml-drawer --no-windowing-checks --pool=3 --qt \
    EditorDrawerLane::test_productionVoiceChangesPickerKeyboardAndCancellation \
    EditorDrawerLane::test_productionVoicePickerPointerAudition \
    EditorDrawerLane::test_productionVoiceChangesModalLayerComposition \
    EditorDrawerLane::test_productionVoiceChangesSpacePriority \
    EditorDrawerLane::test_productionVoiceChangesPageMountsAndRenders \
    EditorDrawerLane::test_productionVoiceChangesPointerAndMenuTransactions \
    EditorDrawerLane::test_productionVoiceChangesInsertAndChangeRowPicks \
    EditorDrawerLane::test_productionVoiceChangesMenuHoldAcrossCameraScroll \
    EditorDrawerLane::test_productionVoiceChangesDismissalAndEscape \
    EditorDrawerLane::test_productionVoiceInputPressIsolatesAutomationAndCursor \
    EditorDrawerLane::test_productionVoiceDragCursorDraftAndBandIsolation \
    EditorDrawerLane::test_productionVoiceJitterAndEscapeKeepArrowAndClearBand \
    EditorDrawerLane::test_productionVoiceCollisionAndAltCursorIsolation \
    EditorDrawerLane::test_productionVoiceChangesCameraTransactions
  ```
- Header: `PORYDAW_ROLL_QML_SUITE=tst_SwiftRollTrackHeaderMenu.qml uv run --no-sync dev checks:qml-roll --filter swiftroll-window --no-windowing-checks --pool=3`.
  The original `voice`/`header` filters were stale: these lanes each publish one aggregate manifest name, not per-suite entries. Drawer Qt selectors preserve its production/container-phase routing; the roll lane's existing suite environment selects the header file.
- uv run --no-sync dev checks:bridge
- uv run --no-sync dev checks:qml-aot
- uv run --no-sync dev format --check
- Controller observes the actual compiled app menus with screenshots and keyboard/AX evidence, without changing or discarding the user's song.

## Checkpoint
One accepted, verified paired-menu batch; no merge. The redesign remains uncommitted because no Git checkpoint/push was requested for this UI change.

## Review rulings
- Six focused QML passes covered bindings, layout, lifecycle, delegates, interaction state, and performance/quality.
- The voice filter/press-order findings were withdrawn: the review compared the legacy drawer picker rather than the captured shared production baseline. Those handlers are unchanged; the real voice/header journeys passed.
- The card-clamp finding was withdrawn: PromptCard's plain Column positioner measures its child's actual clamped size; it is not a ColumnLayout measuring preferred sizes.
- Accepted the unbounded fixed status block risk. Full status text now scrolls inside the existing body, while Reload remains in the fixed footer. No error text is silently discarded.
- Local segmented choices own selection presentation and radio accessibility absent from the read-only shared action control. Shared controls and their other consumers remain unchanged; bare Space still belongs to transport.
- No structural split for line count alone. The effects file still owns one cohesive dialog; tiny divider/rhythm aliases and the existing picker pointer sink do not justify new fragments or unrelated changes.
- The picker-height spacing finding was withdrawn after tracing the real visual tree: the shared content Column has one child; the owned five-section Column has zero spacing. No phantom spacing adjustment.
- AOT exposed three shadowable `Flickable.visibleArea` lookups. ScrollMark now accepts typed real ratios from concrete view ids and an Item for geometry; both changed files compile with zero rejected entries and the baseline is unchanged.

## Verification results
- `build:checks`: passed; the app and affected QML lane binaries were rebuilt.
- Refined effects/output plus six theme/state contrast harnesses: 8 passed, 0 failed. After the typed scroll-marker repair, `shell-midieffects` passed again.
- Final minimal voice chooser: all 14 production voice cases passed; their container-phase counterparts intentionally skip production-only cases. Header-menu journeys passed after label removal.
- Final AOT: 9012/9096 entries compiled, 84 rejected (unchanged baseline); both edited files have zero rejected entries. Bridge guard: zero baselined findings. `format --check`: passed.
- Actual app: inspected both redesigned menus; numeric voice search showed its match, no-match disabled OK, Escape canceled without changing the track voice, and rack Tab moved from Close to Rescan. After the user-approved restart, the voice count and preview hint are absent from the running chooser.
- Generic QML style lint is advisory, not clean: ordering/grouping/list/viewport warnings remain. Its inline-component ordering false positive was reported; production parse/AOT and behavioral gates passed.
- Independent task gates accepted both spec compliance and code quality. No shared control, Swift/audio/backend contract, or check baseline changed. Six obsolete geometry-default pin lines were removed; behavior assertions remain.
- Final Opus standards and spec reviews both accepted, with no required changes. Surface-local rhythm/scroll-cue duplication remains explicit; moving it into shared prompt policy would widen this task's read-only shared boundary. Cost: future style changes must keep both local implementations aligned. The empty-catalog effect hint is a non-blocking wording refinement, not a missing workflow.

## Task 3 — Impeccable rack refinement
- Active view now starts with the document-owned effect name, canonical Live on/off state, Change Plug-in and Open Editor. Input is separate from Render settings (pacing/pre-roll). Library/scanner/folder management is secondary; collapsed failures show a compact summary, expandable to the unmodified full message.
- Plugin rows stage candidates only. Explicit Add/Replace commits; Back/Close discard pending selection. The presenter retains module-path/class-UID identity across catalog changes and invalidates missing/blocked candidates. Retired `selectPlugin` callers migrated completely.
- Build passed. Rack lifecycle, replacement/cancel/history and transport journey passed; Effect Output and all six empty/song theme audits passed. Native `swiftcore-projectsession` passed (71.61s), including presenter and controller lifecycle cases. The Live-off crash fixture now explicitly sets its desired state instead of relying on the superseded default.
- Initial failures were resolved: chooser pointer tests await a submitted frame and native async loading uses the harness main-actor pump; contrast fault injection awaits completed Live configuration. No production guard, fallback or audio behavior was added to hide a failure.
- Bridge guard: zero baselined findings. AOT: 9019/9103 compiled, 84 rejected, unchanged rejection baseline. Named Swift format check passed; final Swift index rebuilt 26/26 targets.
- Before/after SourceKit symbols retain all existing declaration scopes except the intentional immediate-select removal and chooser/apply additions; Swift file-local diagnostics are OK. Semantic references remain unavailable with connectionInterrupted; QML has no configured LSP. Scoped caller search, actual compilation/AOT and behavioral checks provide the covering evidence.
- Inspected actual compiled production QML renders in the isolated fixture: active-effect view and replacement chooser, including compact real scanner failures. Temporary capture code removed. The user's running Debug process and modified song were not restarted, saved, discarded or otherwise edited.
- Independent final gates: task reviewer ACCEPT for both spec compliance and task quality; Claude Opus 5.5 ACCEPT for maintainability, with no blockers. All four originating critique issues are resolved and that exact Impeccable snapshot is closed.
- Ruling: this is the user's approved continuation/fix pass of the existing menu redesign; preserve the incoming uncommitted work and do not commit/push/merge without authorization. Cost: the accepted batch remains uncommitted.
- Ruling: publish controller-owned Live state here without adding a second Live action/orchestrator. Cost: changing Live still uses the existing Effect Output control.
- Opus's non-blocking advisories are not acceptance gaps: optional scan-time focus fallback, text-sized Back/Apply widths, whitespace, a closed-panel cancel guard, and candidate naming. Preserve the accepted bounded implementation rather than widening the pass for those polish suggestions.

### User amendment — hide skipped VSTs
The user subsequently requested that skipped VSTs not be shown. The chooser now publishes only unblocked MIDI-producing entries. Removed the obsolete row `blocked` role, skipped badges, expandable scanner messages, Retry actions, presenter retry slot and retry-only list-focus scaffolding; flattened the now-single-child name row. Rescan and folder management remain, and the canonical scanner catalog still retains failures. This supersedes Task 3's earlier compact-visible-failure presentation, not the scanner's quarantine or diagnostic policy.
- Amendment verification: `build:checks` passed; five rack/output/loaded-theme harnesses passed; native `swiftcore-projectsession` passed (61.82s), including the real-catalog failure/chooser-absence assertion. Bridge guard remains zero findings; AOT 9002/9086 compiled with 84 unchanged rejections. Named Swift format check and final 26/26-target index passed. No scanner/audio policy changed and no user app restart or Git operation was performed.
- Amendment review: the existing spec/task reviewer and Claude Opus 5.5 independently ACCEPT the bounded removal, with no required fixes. The original VST spec now matches the available-only chooser contract.

## Task 4 — Header Effects/Live and opening latency
- Contract: [task-4-brief.md](task-4-brief.md). Effects is content-sized beneath voice, plugin identity is unboxed, and a separate controller-backed Live toggle works on/off and from a configured unloaded effect. Pointer/Return/accessibility share the canonical action; bare Space remains window transport. Live does not select a track, open the rack, or edit song/history.
- Render ownership disables Live through acquisition/capture/restoration, then republishes availability. Preparation joins all pending header commands before its synchronous ownership claim. No second Live boolean, dispatcher, timer, preload/cache, changed public setLive/device-rebind policy, or native helper behavior.
- Actual installed Scaler 3 measured in a disposable native helper: initial load/state 2.124s (plugin creation nested: 1.734s), first editor 1.312s, existing-window raise 0.101s, reopen after close 0.057s. Timings include IPC/helper dispatch and vendor calls, not isolated vendor CPU or fully OS-cold behavior; scanning is excluded. Warm reopening is already fast, so no speculative eager-loading optimization was added. Probe passed after resolving its zero-assertion harness guard; both temporary source edits were byte-restored.
- Initial gates passed: build, native project-session/header/render checks, Effect Output, all three loaded-song theme audits, roll header lane, bridge (zero findings), AOT (9024/9108 compiled;84 unchanged rejections), named Swift format check and 26/26-target index. New shell wait failure was resolved with the existing native-actor pump and remounted object references; focused rack lane passed. Actual compiled production header renders inspected in Live-off/on states; capture-only code removed.
- R0 review: spec/task reviewer accepted; Opus identified a successor-command join gap that could cancel a preparing render. Adopted his simpler drain-until-quiescent loop; also removed duplicate classified-failure publication and disabled-control hover inconsistency. The native regression issues a second real header command from the first completion publication while Render is preparing.
- Final R1: native project-session passed (76.04s), including the successor-command regression; focused rack/header shell lane passed (24.41s). Build, named Swift format check, 26/26-target index and file-local SourceKit diagnostics passed. Bridge/AOT and the unchanged output/theme/roll gates retain the results above. Semantic references remain unavailable; compiled callers and actual behavior provide verification. Both the task/spec reviewer and Claude Opus 5.5 independently ACCEPT, with no remaining blockers.
- Same user-approved refinement continuation. Incoming uncommitted work is preserved; no commit, push, merge, or user-song save/discard occurred.
