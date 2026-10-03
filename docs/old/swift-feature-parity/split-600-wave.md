# Cohesive split wave for the over-600-line inventory

## Scope and invariant

This is a **behavior-preserving split plan**, not an implementation or permission to change assertions. The 36-file inventory supplied for this wave is the baseline; task-115/task-122 sources must freeze before dispatch. Unbuilt `src/ui/*.cpp` fork leftovers are excluded. All 36 verdicts below are **SPLIT**: each currently combines independently changeable responsibilities. No whole-file KEEP exception is justified. Targets are normally 200–400 lines, with cohesive 100–199 or 401–599-line modules explicitly accepted where preserving whole scenarios avoids arbitrary fragments. Never manufacture an 80-line helper file or move the oversize problem into one giant support module. Sizes below are planning estimates, not acceptance by arithmetic alone.

Global constraints:

- Pure declaration/component moves and the minimum binding/receiver/access-control adaptations required by those moves; no policy, timing, ownership, input routing, assertion, fixture, or capture changes. Preserve every assertion message literal, occurrence ordering inside its function, test function name, data-provider pairing, and Swift check entry call order. Do not rename assertions to make anchors resolve.
- One retained original entry file per family, plus the destinations listed below. The retained file owns the first listed concept; it is not an empty forwarding stub. No compatibility aliases or duplicate test declarations.
- QML checks use shared **family-specific support**, never copied fixture/helper bodies. Support names do not begin `tst_`. A support base owns one fixture per TestCase instance, not a singleton mutable fixture shared between processes. Existing `NativeWait.js`, `GatedVisualsHelpers.js`, and production compositions remain canonical.
- QML `id` scope does not cross files. Shared bases expose the existing session/bootstrap/surface through explicit properties/aliases; extracted visual modules receive typed required inputs. JS helpers take the calling TestCase explicitly and use that receiver for `verify`, `compare`, input, waits and object lookup. Do not replace QtTest assertions with throwing JS assertions. Keep message-bearing helper names; record their source move too.
- QML-facing properties, signals and slots stay in their `@QtBridgeable` **class body**; extensions are invisible to registration. Extract internal implementation, not the bridge declaration. A small bridge slot delegating to a substantial internal implementation is a necessary bridge seam, not a second state owner. Keep actor isolation, weak captures, teardown sequence and public signatures. Widen only cross-file implementation members to module-internal, never public by convenience.
- Qt Quick Test orders functions alphabetically **within a file**, not across files. Keep prefixes and names, but do not mistake them for cross-process ordering. Each moved case starts from its own existing setup. Stateful multi-step journeys stay in one function/file. The two drawer profile cases stay together, with `BeforeCapturePencilCursorScale` before `Capture`; note-visual DPR2 child routing moves with its owner suite.
- Parallel implementers perform read-only structural inspection only; no mid-flight builds, formatters, linters, checks or ledger edits. The controller runs the exact commands recorded here once the relevant writers and registration integration have settled, reusing results across slices. Reassess commands only for a concrete stale/unavailable-command or scope mismatch, never silently narrow coverage.
- This document is the single dispatch artifact requested for the wave. The inline slice contracts below replace separate brief files. All slices use **SDD-track / sdd-implementer**: cross-file fixture lifetime, bridge registration and proof identity make blind mechanical dispatch unsafe. The larger file-count exception is one verification surface per family; do not create one build/commit per new file.

## Evidence and registration facts

- `AGENTS.md:64–68` establishes one concept/file and 200–400L target. `rule://qtbridge-surface` requires class-body bridge declarations.
- `src/checks/editorqml/ShellQmlTests.swift:13–23,59–106` owns shell `Entry(name,inputFileName,fixtureFiles,windowing,testFunctions)` records. Each new file needs an Entry and the **full original family's fixtureFiles**, not an inferred minimal song list.
- `EditorQmlTests.swift:23,154–264` currently runs only `tst_EditorDrawer.qml`; a split alone would silently omit tests. `RollQmlTests.swift:75–184` already sorts `tst_*.qml` and spawns **one process per file** because multiple QuickTest files in one process lose logging after `stopLogging()`.
- `src/checks/CMakeLists.txt:55–283,372–376,434–440,480–488` uses explicit Swift source lists, **not a glob**. New Swift checks and drawer runner sources must be added to the corresponding target.
- Root `CMakeLists.txt:221–268` owns production `qt_add_qml_module(porydaw_app ... QML_FILES ...)`; `src/swift/app/CMakeLists.txt:4–114` explicitly lists `PorydawApp` sources.
- `src/checks/workspace/SessionChecks.swift:61–92` invokes the camera, keyboard, velocity, automation, numeric-input and selection checks under `runProjectSessionSuite`; `checkcatalog.cpp:125` exposes the covering lane `swiftcore-projectsession`.
- Executed for this plan: `deno task proof --help`, `deno task proof:edit --help`, and read-only `git show --stat --oneline 344b711b`. Neither proof command offers bulk repoint. `proof:edit` supports a unique exact replacement inside one S entry. Commit `344b711b` changed 964 S path lines in 39 ledgers after `8065e447`; this wave must integrate its repoint with the source split, not create a later standalone reconciliation commit.

## A — Drawer QML checks

**Verdict:** `src/checks/editorqml/tst_EditorDrawer.qml` (8,941L) — **SPLIT**. Container layout/lifetime, velocity, voice, automation, header rendering and DPR capture are different test surfaces. All 99 current `test_*` declarations are assigned below.

All destinations are in `src/checks/editorqml/`. Keep `tst_EditorDrawer.qml` for ContainerLayout; other filenames are `tst_EditorDrawer<Concept>.qml`. Table entries omit the unchanged `test_` prefix. Each inherits `EditorDrawerTestSupport.qml`; keep `name: "EditorDrawerLane"` so existing qualified selectors remain valid, and route selectors to their owning file in the runner. Tests are unique across files. The original root entry has the same support relationship.

| Concept / destination suffix | Exact test declarations | Approximate test-body lines |
| --- | --- | ---: |
| ContainerLayout | `noPageContributesNothing`, `hostedChromeAndStacking` | 178 |
| ContainerResize | `toggleRetainsStoredHeight`, `resizeClampAndCancellation` | 160 |
| ContainerLifecycle | `voiceChangesSpillAndDetach`, `focusReturnAndPageCancellation`, `mountedDrawerFocusFallbackWalk` | 229 |
| SharedPlayhead | `sharedPlayheadRendersRollAndVisibleBodies`, `sharedPlayheadHidesOutOfViewportAndReprojects`, `sharedPlayheadSuspendsFollowForEveryInteraction` | 233 |
| Chrome | `numericFieldWindowShortcutPriority_data`, `numericFieldWindowShortcutPriority`, `bundledFontsResolveInEditorLane`, `otherEventsBandMountsBetweenDrawerAndScrollbar`, `otherEventsProjectionHoverAndWheel`, `drawerTypographyFromMountedSession`, `productionDrawerBlankBarFocus` | 241 |
| Headers | `quickSurfacePublishesAndRendersHeaders`, `trackActivityRenderedMeterParity`, `headerVoiceChangeAltersRetainedRaster`, `hoveringHeadersDoesNotCreateTooltip`, `headerCtrlScopeKeepsPrimaryAndRendersOverlay` | 227 |
| VelocityRaster | `productionVelocityPageMountsAndRenders`, `productionVelocityMountedInk`, `productionVelocityTransientInk`, `productionVelocityDetentRepaint` | 250 |
| VelocityHitTargets | `productionVelocityCoincidentNodePriority`, `productionVelocityStemGestureCancellation`, `productionVelocityOverlapTargetsVisibleNode` | 227 |
| VelocityEditing | `velocityHintsResumeAfterOutsideRelease`, `productionVelocityPointerEdit`, `productionVelocityNumericInput`, `productionVelocityCancellation`, `productionVelocityPlayheadPerformance`, `productionVelocityContextIsExact` | 228 |
| VelocityPrompt | `productionVelocityPromptTransaction`, `productionVelocityPromptButtonsAndFocus`, `productionVelocityPromptValidationAndDismissal`, `productionVelocityPromptBoundedKeys` | 280 |
| VoiceTransactions | `productionVoiceChangesPageMountsAndRenders`, `productionVoiceChangesPointerAndMenuTransactions`, `productionVoiceChangesInsertAndChangeRowPicks`, `productionVoiceChangesMenuHoldAcrossCameraScroll`, `productionVoiceChangesDismissalAndEscape` | 299 |
| VoicePicker | `productionVoiceChangesPickerKeyboardAndCancellation`, `productionVoicePickerPointerAudition`, `productionVoiceChangesModalLayerComposition`, `productionVoiceChangesSpacePriority` | 342 |
| VoiceInputIsolation | `productionVoiceInputPressIsolatesAutomationAndCursor`, `productionVoiceDragCursorDraftAndBandIsolation`, `productionVoiceJitterAndEscapeKeepArrowAndClearBand`, `productionVoiceCollisionAndAltCursorIsolation`, `productionVoiceChangesCameraTransactions` | 200 |
| AutomationHover | `productionAutomationHoverThroughInput`, `productionAutomationEditGuideTracksCursor`, `productionAutomationHoverTransfersBetweenWrittenNodes`, `automationHintsRetainGrabOrigin` | 340 |
| AutomationCurves | `productionAutomationOriginPhantomCurveRaster`, `productionAutomationGhostCurvesDrawUnderActive`, `productionAutomationLeadInStepAndSelectionPixels` | 309 |
| AutomationPresentation | `automationPresentationCurveTabAndBadgePixels`, `automationPresentationGhostAxisAndResize`, `automationPresentationInactiveInclusionPixels` | 285 |
| AutomationTabs | `parameterLabelsFitGutterAtDerivedMinimum_data`, `parameterLabelsFitGutterAtDerivedMinimum`, `productionAutomationPageMountsAndRenders`, `productionAutomationTabSwitchAndGhosts` | 272 |
| AutomationTransactions | `productionAutomationDomainRowsThroughInput`, `productionAutomationPromptTransaction` | 313 |
| AutomationPointMenu | `productionAutomationRangeSubmenu`, `productionAutomationOutsideRightRetarget`, `productionAutomationPointMenuDeleteAndDismiss`, `productionAutomationSyntheticDefaultMenuRoute` | 312 |
| AutomationFocus | `automationModalsRetireWithPage`, `productionAutomationSetValuePromptFocusRoute`, `productionAutomationTempoPromptFocusRoute`, `productionAutomationSpacePriority` | 328 |
| AutomationLaneMenu | `productionAutomationMenusAndLaneCommands`, `productionAutomationClearRowClick`, `productionAutomationRange64RowClick`, `productionAutomationCopyRowClick`, `productionAutomationPasteRowClick` | 317 |
| AutomationTempo | `productionAutomationTempoPromptPresentation`, `productionAutomationCenteredPromptOffset`, `productionAutomationTapTempoThroughInput` | 234 |
| PagePlayhead | `productionAutomationFollowAndCancellation`, `productionAllPagesPlayheadPerformance`, `productionVoiceChangesPlayheadPerformance` | 340 |
| AutomationCamera | `productionAutomationBandGeometry`, `productionAutomationSectionResizeKeepsTabsClickable`, `productionAutomationMiddlePanAndTrackSwitch`, `productionAutomationEmptySwitchPreservesGrid`, `productionAutomationViewStateAcrossDrawerPages`, `productionAutomationWheelZoomPreservesDrawerState` | 327 |
| AutomationPreview | `productionAutomationDragPreviews`, `productionAutomationPanSelectedRingPixels`, `productionAutomationPencilPreviewAndLabel` | 344 |
| ReferenceProfiles | `referenceProfileCapture`, `referenceProfileBeforeCapturePencilCursorScale` | 97 |

ReferenceProfiles also owns `captureProfilePane`, `captureTrackHeadersProfile` (about 155 lines), so its total is about 270L, not a 97L fragment. Headers owns `headerMeterPixels`. AutomationPresentation owns `compareAutomationPixel` and `automationProjectedY`; AutomationPreview owns `automationPreviewCovers`; AutomationCurves owns `automationPaintRegion`.

### Shared drawer support ownership

No copied helper implementations. `EditorDrawerTestSupport.qml` (about 300–400L) owns the existing root properties/counters, font loaders, Shortcut/Keys handlers, `EditorQmlBootstrap` with its direct-child `ApplicationSession`, surface component, `Connections`, `initTestCase`, `init`, `cleanup`, `cleanupTestCase`, `openDiagnostics`, `stagedLabels`, `createSurface`, `chromeState`, `resetChrome`, and the short presenter/page/roll/hint accessors. Expose bootstrap/session as aliases using different internal ids. Keep the staged test-page URL resolved from this same directory. Move remaining support into the following explicit-receiver JS modules, preserving helper names and imports:

| Support destination | Whole existing helper seam / single concept |
| --- | --- |
| `EditorDrawerLayoutSupport.js` (~260L) | `keyName`, `attachPage`, `observePageDestruction`; `seedStore` through `awaitStoreKey`; `clickToggle` through `bodyInsideContainer`; `verifyToggleAccessibility`, `verifyGripAccessibility`: persisted drawer chrome geometry and input. |
| `EditorDrawerPixelSupport.js` (~310L) | `channelsOf` through `verifyBarRendering`: pixel-region/color/tint/bar assertions, including exclusions; no test cases. |
| `EditorDrawerPageSupport.js` (~200L) | `collectByName` through `auditVisibleTextInk`; `collectByNames`, `collectByPrefix`; `playheadPresenter` through `awaitPlayheadVisibility`, including `showSection`: mounted-page tree/visibility observation. |
| `EditorDrawerVelocitySupport.js` (~130–180L) | `velocityPageItem` through `mountProductionVelocity`: velocity node lookup, note summaries, click and reset. Keep `gridNotes`/`primaryGridNotes` here as current shared velocity/grid observation. |
| `EditorDrawerAutomationTabsSupport.js` (~240L) | `automationPageItem` through `automationPlotInput`; `automationTabItems` through `automationCurveItems`; `mountProductionAutomation`, `automationBridgeDiagnostics`, `automationTab`, `drawnAutomationTabLabels`, `verifyAutomationLabelsFitGutter`, `drawnAutomationActiveTab`, `automationTabWithEvents`, `automationEmptyTab`, `revealAutomationTab` through `rightClickAutomationTab`: tab/viewport mounting and discovery. |
| `EditorDrawerAutomationGestureSupport.js` (~230L) | `automationNodeFill` through `automationRowForValue`, except menu helpers: node geometry, written-lane seeding, sweep/band/row drags; also `automationPreviewItems`. |
| `EditorDrawerAutomationMenuSupport.js` (~200L) | `automationMenuRowItems`, `menuRowByAction`, `automationMenuSeparatorItems`; `clearAutomationLane` through `resetAutomationTap`: modal settling and menu activation; exclude `automationPreviewItems`, which belongs to AutomationGestureSupport. |
| `EditorDrawerVoiceSupport.js` (~180–230L) | `voicePageItem` through `typeProgram`, excluding `collectByPrefix`: voice mounting, insertion and picker input. |

Do not leave a second 1,000L base. Imported modules call one another through explicit namespaces/receiver, not a dynamically copied method bag. The precise allocation above assigns every non-test function; overlapping first-through-last ranges exclude functions explicitly assigned elsewhere. Preserve predicates inside helpers rather than replacing them with weaker probes.

Lifecycle risk: common `cleanupTestCase` currently asserts a prior playhead presentation. Preserve its existing opened-session/polling lifecycle and nonzero-presentation precondition; do not remove the assertion, synthesize a passing observation, or infer zero means success. Shared `init` resets preferences and cancels input; production pages remain alive until acknowledged scene removal, whereas container phase detaches them **before mounting**. Do not mount/unmount per test merely to simplify the split.

Acceptance command: `deno task verify:qml --verbose` — every split suite, both production/container phases and all four DPR/font profile children; inspect per-child output and capture metadata, not just parent exit status.

## B — Drawer Swift host and multi-file runner

**Verdict:** `src/checks/editorqml/EditorQmlTests.swift` (1,257L) — **SPLIT**. Executable orchestration, artifact validation and a QML bootstrap are not one concept.

- Retain `EditorQmlTests.swift` (~250–350L): `EditorQmlLane`, `main`, `runLane`, `runSuite`, manifest/fixtures/fail and the new suite enumeration/selection. It is the single orchestration owner.
- `EditorQmlProfileChildren.swift` (~200L): `runPhaseChild`, `runProfileChildren`, the child/phase environment keys, `ReferenceProfile`, `referenceProfiles` and the two profile selectors. Keep process output forwarding, signal/exit failure and recursion rules.
- `EditorQmlProfileEvidence.swift` (~250–350L): `ReferencePaneIdentity`, `paneIdentities`, profile theme/palette/fixture/capture-label constants, `fixtureIdentity`, `profileEvidence`, `profileMetadataMismatch`, `pngPixelSize`, artifact path and the **implementation** of metadata writing/refusal and reference-geometry reading. Pass current staged values and palette explicitly; preserve PNG size checks and offscreen-not-physical-DPR disclaimer.
- `EditorQmlBootstrap.swift` (~400–550L bridge declaration envelope): move the `@QtBridgeable public final class EditorQmlBootstrap` body, keep every existing QML slot/property declared here and retain the direct-child session lookup. Move lengthy internal bodies to `EditorQmlBootstrapSupport.swift` (~150–250L): history request mechanics, open/report outcome, attach/detach test page management, interaction/activity/polling implementation. Keep the bootstrap as the one state/retention owner; support is internal functions/extensions, not a second registered QObject or copied session. Trim only stale/overlong comments per project convention, not declarations to hit a size number. Metadata slot delegates to ProfileEvidence, because moving it to an extension would silently remove it from QML.

Runner contract (reuse the RollQmlLane process-per-file pattern, not one `-input` directory QuickTest call):

1. Replace `inputFileName` with sorted enumeration restricted to `tst_EditorDrawer.qml` and `tst_EditorDrawer*.qml` in `EditorQmlPaths.testDirectory`. Never enumerate neighboring shell suites. Add `PORYDAW_EDITOR_QML_SUITE` child selector; children cannot enumerate or spawn further children.
2. Top-level ordinary dispatch runs one suite child/file in production phase, then one/file with the existing container phase staged before QML construction. A suite child creates exactly one QTestApp and passes its own explicit file to `-input`. Preserve scratch/preferences paths, fixture manifest, `--qt` forwarding, and rejection of caller `-input`.
3. After ordinary and container success, spawn the four existing profile children **only for** `tst_EditorDrawerReferenceProfiles.qml`. Profile environment/scale must be set before QTestApp construction. Keep both original qualified selectors and their alphabetical order in the same child; capture output/artifacts exactly once/profile.
4. Forward qualified user selectors only to the file owning those unchanged functions; maintain a static suite-to-function selector map generated from the plan's exact declarations during implementation, not runtime source parsing. `_data` stays with its consumer; raw Qt options go to all selected suite children. Unknown selectors must fail rather than run zero cases. Unfiltered dispatch enumerates all drawer suites. The map belongs in `EditorQmlTests.swift` unless it would exceed 600L; compact per-suite arrays are data, not new tiny source modules.
5. Forward every child log verbatim and aggregate all nonzero/signal failures. Do not let a successful final child mask a failed earlier suite. No shared in-process QML object graph across files.

The registry/host owner alone edits `EditorQmlTests.swift` and adds its new files to `editor_qml_lane` in `src/checks/CMakeLists.txt`. Verify with `deno task verify:qml --verbose`; also exercise selected routing with `deno task verify:qml --filter editorqml-drawer --verbose --qt EditorDrawerLane::test_referenceProfileCapture` only after defining whether explicit profile selectors invoke the parent profile dispatch: they **must** invoke all four profile children, not an ordinary skipped case. A selected ordinary case command is `deno task verify:qml --filter editorqml-drawer --verbose --qt EditorDrawerLane::test_productionVelocityPointerEdit`.

## C — Shell QML check families

All twelve files below are **SPLIT**, with independently runnable ownership surfaces, not arbitrary line chunks. All paths in this section are relative to `src/checks/editorqml/`. For each family, the **first row stays in the original `tst_<Family>.qml`**; remaining destinations are exactly `tst_<Family><Suffix>.qml`. Table functions omit `test_`, which remains unchanged. Existing TestCase `name` is preserved within each family; separate process registration prevents name collisions. The support base is `<Family>Support.qml` (a non-discovered TestCase base with no `test_*` methods), instantiated once per concrete suite. Lifecycle helpers are inherited rather than copied.

### `ShellWindow` — `src/checks/editorqml/tst_ShellWindow.qml` (3,632L): SPLIT

| Destination suffix / concept | Exact test declarations | Test-body estimate |
| --- | --- | ---: |
| Restore | `savedWindowFrameRestoresAcrossShellSessions`, `offscreenWindowFrameIsIgnored`, `maximizedAndDebuggerWindowStateRestores`, `sessionPreferencesRetainForkKeySpellings`, `yCleanSessionClosesWithoutPrompt`, `zWindowTitleAndStatusMeter`, `chromeTypographyAndWindowGeometry`, `aKeymapNativeSettingsSeeds`, `bThemeRepairThroughProductionShell` | 309L |
| CrossTab | `seededEventListRestoresBothStates`, `dCopyFromOneSongTabPastesIntoAnother` | 120L |
| Drawer | `sharedDrawerWindowShortcutsFanOut`, `drawerHideResizeAndAllHiddenFanOut` | 195L |
| Shortcuts | `cWindowShortcutsAndNumericOwnership`, `fPencilLatchTextAndSpaceOwnership` | 365L |
| EditorKeys | `gEditorRoutedNoteKeysAndChromeArrows`, `cForeignWindowKeepsSoloLocal`, `gMultiNoteArrowSelectionAndHistory`, `iEditorCommandDeliveryAndTextLocalKeys` | 273L |
| Prompts | `cAutomationInsertionPrompts`, `eStandaloneInsertTimeOpensMountedPrompt`, `eStandaloneInsertTimeZeroClickClosesWithoutEdit`, `eTimeAndTracksMenuContainment` | 343L |
| Focus | `hKeyboardFocusAndDrawerSpacePriority`, `lChromeArrowsAndUnknownKey` | 240L |
| TimeEditing | `jTimeSelectionInsertAndDeleteMutatesDocument`, `jPlayingSelectedRangeInsertAndDeleteThroughWindow`, `jWholeSongRangeDeletesBothTracksThroughWindow` | 380L |
| Velocity | `kVelocityStemEscapeFromRollFocus`, `kOverlappingVelocityNodePaintCaptureAndResume`, `kVelocityGestureTermination_data`, `kVelocityGestureTermination` | 331L |
| ParameterKeys | `kParameterTabActivationAndTapCession`, `nLabelTimeSelectionCommands`, `oEmptySelectionLabelUpEditsNothing` | 399L |
| LabelCommands | `mLabelCommandsAndPromptTextOwnership` | 247L |
| Hints | `pMouseHintTargetClaims`, `qMouseHintMenuAndPopupScope`, `rMouseHintStatusPresentation` | 192L |

Verification: `deno task verify:shell --filter shellwindow --verbose`. The substring includes the original entry and all added family-prefixed entries.

### `ShellTabs` — `src/checks/editorqml/tst_ShellTabs.qml` (2,693L): SPLIT

| Destination suffix / concept | Exact test declarations | Test-body estimate |
| --- | --- | ---: |
| Startup | `startupRecipes`, `selectedSongOnlyStartupRecipe`, `missingSongStartupRecipe`, `kStartupRestoresTabsAndFreshCamera`, `oFreshTabViewStateDefaults` | 273L |
| MouseHints | `mouseHintsFollowDialScrollbarHeaderAndFocus`, `mouseHintsReleaseHiddenAndClosedTabOwners` | 195L |
| OpenSelect | `aOpenSwitchAndGeometry`, `fReorderPreservesIdentities`, `bSelectionRepaintAndGlyph`, `cScrollAndGridInput`, `dOpenIndependentWorkspace`, `eSwitchPreservesState` | 378L |
| Close | `gBackgroundClosePreservesActive`, `gSelectedCleanCloseRetargetsSurvivor`, `hFinalCloseEmptyAndReopen`, `iReopenExistingFocusesTab`, `jDirtyCancelDiscardSave` | 269L |
| Drawer | `sharedDrawerCloseAndReopen`, `sharedAutomationParameterAndTrackFocusAcrossTabs` | 441L |
| BankLifetime | `lOrphanDirtyBankGatesProjectSwitch`, `mOrphanDirtyBankGatesWindowClose`, `nDirtyTabThenOrphanBankWalk`, `uSharedBankTwoTabJourney` | 299L |
| Reload | `pReplaceInPlaceRetainsOneTab`, `qReloadPreservesViewAndClearsHistory`, `qSelectionDuringReloadKeepsExplicitTarget`, `qReloadCompletionKeepsDifferentSelection`, `rFinalCloseStopsAdvancingPlayback`, `rTabSwitchStopsPlayback`, `sMidGestureCloseCancelsHeldBand`, `tCloseWalkCancelsHeldBand` | 289L |

Verification: `deno task verify:shell --filter shell-tabs --verbose`. The substring includes the original entry and all added family-prefixed entries.

### `ShellGridMenu` — `src/checks/editorqml/tst_ShellGridMenu.qml` (2,078L): SPLIT

| Destination suffix / concept | Exact test declarations | Test-body estimate |
| --- | --- | ---: |
| Controls | `gridDivisionAndFeelMenusDispatchAndDismiss`, `gridShortcutsWalkDenominationsAndFeel`, `gridControlsShowComboboxAffordance`, `gridMenuKeyboardTraversalClampsAndActivates` | 199L |
| InputZones | `actionRowsCloseBeforePromptAndDisabledRowsStayOpen`, `shiftRightRollSweepOpensCanonicalTimeMenu`, `rollPressFocusAndHoverCursorZones`, `rollKeysEditTimeScopedNotesAndEmptyClickClearsBand`, `transportObservationWithFocusedStop` | 225L |
| NoteActions | `noteCommandRowsDispatchOnSelectedNote`, `noteMenuRetargetAndDismiss`, `noteMenuPromptRoundTripWithHiddenDrawer`, `noteMenuRetiresOnDocumentEditAndPreservesOtherFocus`, `noteMenuKeyboardDeleteAndEscape` | 384L |
| RulerLifecycle | `rulerLoopAndSelectedTimeRowsExecuteFromRenderedPanels`, `rulerInsertTimeOpensExistingPromptAndCommitsBars`, `rulerRightPressCapturesAndReleaseOpensAtReleasePosition`, `rulerEscapeDismissesWithoutHistoryWriteAndRefocuses`, `rulerDragThresholdAndRightDragMenu`, `controlRulerSweepPublishesSecondaryHeaderOverlay`, `rulerClearSelectionAndRetirementFocus`, `forkRulerAndTimeMenuWordingAndHints` | 302L |
| RulerMarkers | `rulerLoopRowsSetRemoveUndoAndDismissFromRenderedPanel`, `rulerSignatureChipPressesCommitExactTicksFromRenderedPanel` | 253L |
| RulerClipboard | `rulerClipboardRowsFollowClipAndTimeSelection`, `rulerSelectionInsertTimeRowsShiftNotesAndUndo`, `timeMenuRenderedPasteRejectsOverlapWithoutEmissions`, `timeMenuClearRowDropsSelectionWithoutEditingSong`, `timeMenuRenderedRangePasteClearsSelectionAndAdvancesCursor`, `timeMenuEscapePreservesSelectionAndRefocuses` | 249L |
| Automation | `automationPointMenuRendersDeleteBeforeDismissal`, `automationHeldBPointerStrokeKeepsPencil`, `automationPointMenuYieldsToPublishedDivisionMenu`, `automationBandMissFallsThroughToTimeMenu` | 104L |

Verification: `deno task verify:shell --filter shell-grid-menu --verbose`. The substring includes the original entry and all added family-prefixed entries.

### `ShellGridInput` — `src/checks/editorqml/tst_ShellGridInput.qml` (2,044L): SPLIT

| Destination suffix / concept | Exact test declarations | Test-body estimate |
| --- | --- | ---: |
| Chrome | `headerRenameFocusAndLifecycle`, `loadedRulerAndFixedInputSurfaces`, `readyRulerControlHoverHelp`, `modifiedRulerSweepPaintsExactNoteScope` | 372L |
| Draw | `exactDrawThreshold`, `modifierVelocityToggle`, `modifierVelocityEscapePreservesTimeline`, `emptyClickSlopAndDoubleDraw`, `rightDragUsesPlatformSlop` | 264L |
| Editing | `drawMoveNeighborTrim`, `resizeMinimum`, `undoRedoRerender`, `rightDragCommit`, `velocityBandExpansionAndContraction` | 308L |
| Cancel | `escapeCancel`, `ungrabCancel`, `hideCancel`, `windowCancelReasons`, `trackFollowReload`, `rightGutterDeclinesPress`, `middleGutterDeclinesPress`, `extraPlotButtonDeclinesPress` | 207L |
| Keyboard | `focusedRouting`, `bareSpace`, `mountedFoldKeyboardNudges`, `gestureKeysPreserveNotesUntilRelease`, `moveGestureEscapeRestoresSelectedNote`, `thumbGrabKeepsDeleteFromSelectedNote` | 351L |
| Automation | `mountedAutomationDragDeleteUndoPreservesRoll`, `mountedMixedAutomationRangeDragDeleteUndo` | 333L |

Verification: `deno task verify:shell --filter shell-grid-input --verbose`. The substring includes the original entry and all added family-prefixed entries.

### `ShellPitchBend` — `src/checks/editorqml/tst_ShellPitchBend.qml` (1,626L): SPLIT

| Destination suffix / concept | Exact test declarations | Test-body estimate |
| --- | --- | ---: |
| Strokes | `committedStrokeKeepsEditorOpen`, `keyboardUndoWhileOpenRestoresCurve`, `mountedStackedStrokesUndoIndependently`, `livePreviewSurvivesUndoRedo` | 141L |
| Cancellation | `typedControllersSurvivePreviewCancellation`, `popupFocusedEscapeDiscardsActivePreview`, `undoAfterDismissalReopensOriginalCurve`, `cancelReopenAndOutsideClickDoNotEdit`, `externalRedoDeletesAnchorAndUnloadsPopup` | 245L |
| Controls | `menuRouteOpensEditorWithoutEditing`, `noteScopedCurveAndControls`, `modulationAndLfoSurviveOutsideDismissal` | 185L |
| Pointer | `gAnchorsPopupAndShrinkingWindowReclamps`, `wheelInsideCanvasOnly`, `pointerScrubsUndoAndStationaryClick`, `scrubHoverAndIdleEnterKeepEditor`, `popupSpaceAuditionSoloAndMuteAbsorption`, `navigationKeysLeaveCurveUntouched` | 238L |
| Keys | `windowUndoReachesOpenPopup`, `graphKeyOwnershipAndRepeatedOpener`, `graphVertexDeleteUndoAndWindowSoloResumption`, `numericFieldOwnsCopyAndYieldsSpace`, `escapeRestoresRollFocus` | 237L |
| Retarget | `outsideNotePressRetargetsWithoutDrag`, `strayNoteRetargetsWithoutDrag`, `trackHeaderPressPassesThrough`, `insideFormBlankKeepsEditor`, `hostWindowLossSettlesHeldStroke_data`, `hostWindowLossSettlesHeldStroke`, `vertexSelectionAltDragAndEndpointProtection`, `opaquePopupAndPaintedDiagonals`, `noteEdgeCursorAcrossDismissal`, `reanchorTargetsNewNoteGraph`, `blankPassThroughAndFixtureFocus` | 275L |

Verification: `deno task verify:shell --filter shell-pitch-bend --verbose`. The substring includes the original entry and all added family-prefixed entries.

### `ShellDrawerParity` — `src/checks/editorqml/tst_ShellDrawerParity.qml` (1,562L): SPLIT

| Destination suffix / concept | Exact test declarations | Test-body estimate |
| --- | --- | ---: |
| Hover | `aAutomationHoverRaster`, `aAutomationFocusAndWindowCancellation` | 117L |
| Automation | `aAutomationNodeGeometryCancellation`, `aAutomationShortcutHintAndMenuScope`, `dGripKeyboardIsolation` | 208L |
| VoiceVelocity | `bVoiceDragCommit`, `cVoiceDragCancel`, `eVelocityLateUnlock`, `fVelocityEarlyUnlock` | 16L |

Verification: `deno task verify:shell --filter shell-drawer-parity --verbose`. The substring includes the original entry and all added family-prefixed entries.

### `ShellEventList` — `src/checks/editorqml/tst_ShellEventList.qml` (1,434L): SPLIT

| Destination suffix / concept | Exact test declarations | Test-body estimate |
| --- | --- | ---: |
| Editing | `filterAndEditOnMountedPage` | 291L |
| Menus | `rowMenuActionAndVoiceReveal`, `menuKeyboardNavigation`, `fullFilterMatrixThroughMountedMenu`, `rowMenuRetiresOnContextMoves`, `rowMenuContextThroughRenderedTable` | 362L |
| Presentation | `eventListRowsFollowAppliedTheme`, `dragReordersOnlySameTickRows`, `drawerFocusCommitsAndOwnsDelete`, `resizedHeaderAndDoubleClickEditor`, `chunkWheelAndDrawerFocus`, `viewStateVisibilityFlag` | 350L |
| KeyboardSelection | `keyboardSelectionStaysOnMountedEventRows`, `tickBoundariesThroughMountedEditor` | 341L |

Verification: `deno task verify:shell --filter shell-event-list --verbose`. The substring includes the original entry and all added family-prefixed entries.

### `ShellNoteVisuals` — `src/checks/editorqml/tst_ShellNoteVisuals.qml` (1,336L): SPLIT

| Destination suffix / concept | Exact test declarations | Test-body estimate |
| --- | --- | ---: |
| Color | `velocityColorRaster`, `drawnNoteFillBorderAndAbuttingSeam`, `noteNameRaster`, `dpr2SmallFontThinning` | 402L |
| Detail | `velocityValueRaster`, `tinyNoteFrameRaster`, `noteRasterParity` | 338L |
| Ruler | `unsignedRulerBarRasterAfterBindAndPan`, `preRollPadAndRulerRaster`, `ghostEdgesAndMinimumZoomFace` | 161L |

Verification: `deno task verify:shell --filter shell-note-visuals --verbose`. The substring includes the original entry and all added family-prefixed entries.

### `ShellVoicegroup` — `src/checks/editorqml/tst_ShellVoicegroup.qml` (1,186L): SPLIT

| Destination suffix / concept | Exact test declarations | Test-body estimate |
| --- | --- | ---: |
| Rows | `128RowsSelectionAndAudition`, `trackHeaderRevealRoutesToMountedDock`, `typeColumnFamiliesAndAlternateChips`, `blankTemplateAndDockWidth` | 193L |
| Editing | `editorAndUndo`, `editorSpinKeyCommitsAndUndo`, `editorQueuedEditsKeepTheirSlot`, `editorSaveCommitsCleanBank`, `xSpaceInFocusedAdsrFieldTogglesTransport` | 158L |
| Picker | `yPickerReturnFallbackAndWaveUndo`, `zPickerAuditionsAndCommitsSampleWaveAndKeysplit`, `zySelectorFailurePreservesBinding` | 217L |
| Save | `zzSynthMintAndMountedSave`, `referenceProfileCapture`, `zzzzzUnifiedSaveAndUndoRestorationReceipts`, `zzzzzzReleaseBoundaryEditsLeaveSongClean`, `zzzzSharedBankBetweenTwoLiveTabs` | 426L |

Verification: `deno task verify:shell --filter shell-voicegroup --verbose`. The substring includes the original entry and all added family-prefixed entries.

### `ShellClipboard` — `src/checks/editorqml/tst_ShellClipboard.qml` (1,154L): SPLIT

| Destination suffix / concept | Exact test declarations | Test-body estimate |
| --- | --- | ---: |
| Notes | `nativeMimeDisplacedBySongFilterCopy`, `noteDeleteAndCutKeys` | 157L |
| Range | `trackExpandingRangePaste`, `headerScopeChangesMountedRangeCopy`, `timeRangeSelectionKeys`, `scopedRangeCopyPasteKeys` | 389L |
| RoundTrip | `roundTripReplacement` | 442L |

Verification: `deno task verify:shell --filter shell-clipboard --verbose`. The substring includes the original entry and all added family-prefixed entries.

### `ShellTransport` — `src/checks/editorqml/tst_ShellTransport.qml` (1,152L): SPLIT

| Destination suffix / concept | Exact test declarations | Test-body estimate |
| --- | --- | ---: |
| Controls | `chromeTypographyAndSpacing`, `transportButtonMenuCommandParity`, `transportControlTransitionsAndSettings`, `transportClockAndSpacerSurviveTextAndResize`, `unloadedTransportPreferencesStayActionable`, `transportTogglePreferencesSurviveRelaunch`, `visualReferenceProfiles_data`, `visualReferenceProfiles`, `transportGlyphTintMatchesEnabledState` | 459L |
| Volume | `outputDialEndpointPixels`, `outputDialIncrementalDrag`, `outputDialFineDragAndTooltip`, `outputVolumeSurvivesShellRelaunch`, `volumeIsolationAcrossRealInputAndTabs` | 205L |
| Session | `explicitOpenSupersedesStartupRestoreDuringPlayback`, `scaleControlsFollowSelectedTab`, `rulerCommitMovesCursorOnlyInEveryTransportState`, `backgroundRulerSeekCannotMoveSelectedSong`, `toolbarResumeAndSpaceRestartAtEditCursor`, `homeHomesCursorWithoutMovingStoppedPlayhead`, `cancelledSweepAndHiddenMixDoNotPublishIntoSelectedWorkspace` | 378L |

Verification: `deno task verify:shell --filter shell-transport --verbose`. The substring includes the original entry and all added family-prefixed entries.

### `ShellMenus` — `src/checks/editorqml/tst_ShellMenus.qml` (830L): SPLIT

| Destination suffix / concept | Exact test declarations | Test-body estimate |
| --- | --- | ---: |
| Topology | `menuItemsExistWithLabelsAndNoSongGates`, `forkMenuTopologyAndLabels`, `forkNoteContextShapeAndLoopGates`, `editTailItemsExistDisabledAndInertWithNoSong`, `displayModesPersistAcrossShells` | 201L |
| Commands | `songMenuActionsDriveSessionState`, `noteCommandsRouteThroughMenuAndKey`, `explicitSoloEditMenuStaysAvailableWithTextFocus`, `eventMoveRoutesThroughMenuAndEventListKey`, `closeTabClosesTheCleanTab` | 338L |
| Loop | `loopFromRulerSelectionMenuAndUndoRestoresMarkers`, `loopMenuCommandsUseCursorAndUndoOneMarkerAtATime`, `rulerCursorInsertDiffersFromSelectionEditMenu` | 170L |

Verification: `deno task verify:shell --filter shell-menus --verbose`. The substring includes the original entry and all added family-prefixed entries.


### Shell fixture/helper seams and exceptions

Support entries below own **all non-test declarations of that source family**, except explicit local/domain extractions named here. No generic cross-family helper consolidation in this wave.

- **ShellWindowSupport.qml** (~200–300L): `cleanup`, `waitForNative`, `openTwoSongShell`, `openDiagnostics`, `selectedSurface`, `focusBelongsTo`, `selectDrawnVelocityNote`, `selectMountedNotePair`, `drawnNoteContent`, `paintedTimeRange`, `mountedNotePoint`, `windowShortcut`; root components/probes/spies/font metrics and preference lifecycle. `foreignWindowComponent` must retain its original transient/window lifetime; native clipboard probe remains a real TextInput. CrossTab owns cross-song clipboard and event-list view restoration, independently of the window appearance/preferences suite; no cross-file session reuse.
- **ShellTabsSupport.qml** (~250–350L): lifecycle and tab fixture/navigation (`init`, `cleanup`, `waitForNative`, `openDiagnostics`, `seedDrawerPrefs`, `openShell`, `waitForPage`, `tabs` through `gridOf`, `summaryOf`, dialog/gate helpers, `tabOrderIds` through `clickSelectTab`). **ShellTabsRenderingSupport.js** (~200–300L) receives `pointFor`, `drawNote`, `regionOf`, tree/color/pixel/grab helpers through `volumeAxisLabels`. Bank path/orphan/gate helpers stay with BankLifetime (not in a 50L bank-helper fragment). The Drawer suite's ~441L is one coherent cross-tab shared-drawer lifecycle and keeps the two full scenarios intact; it remains below 600.
- **ShellGridMenuSupport.qml** (~300–400L): fixture plus `surface`, `control`, `panel`, `clickRow`, `openGrid`, `assertRows`, `rowTextEqualsControlText`, `alternateGridMenuId`, ruler coordinate/menu/marker helpers, `noteLayout`, `noteTargets`, `noteMenu`, `noteMenuMiss`, `sweepNoteRange`, `stageAutomationMenuPoint`. Preserve the prompt/time-signature host observers, not only visible menu lookup. Automation (~104L tests plus wrapper) is an intentional cohesive menu-arbitration suite; no standalone 27L case files.
- **ShellGridInputSupport.qml** (~250L): `openRoute101`, selected-surface/note/point/band helpers, `dragLeft`, `dragRight`, `rollInput`, `holdBand`, `declinedPointerPress`, probes and cleanup. Velocity-drawer state belongs to its own test setup, not every suite's default preferences. Keyboard and Automation preserve their real input + history chains.
- **ShellPitchBendSupport.qml** (~350L): `init`, `cleanup`, `waitForNative`, `surface`, `openSong`, `visibleNote`, `strokePitchCanvas`, `capturePitchFrame`, `coloredHits`, `openPitchEditor`, `openViaG`, `popupWindowRect`, probes. Entire note-scoped and held-stroke journeys stay in their test functions; the data row remains with host-window-loss test.
- **ShellDrawerParitySupport.qml** (~150–220L): fixture/open/cleanup/accessors, `collectByName`, `gridPointFor`, `clickFirstGridNote`. **ShellDrawerParityRasterSupport.js** (~200–280L): `regionOf` through `grabUntilDifferent`, plus `checkAutomationParameter`. **ShellDrawerParityVelocitySupport.js** (~470L): whole `dragMountedVelocity`, a single late/early-unlock transaction law. **ShellDrawerParityVelocityInputSupport.js** (~270L): `mountedRawVelocityGesture`, `mountedRawVelocityRamp`, `mountedVelocityRulerAndPaint`. Keep `dragVoiceTransaction` in VoiceVelocity; its four test wrappers plus that ~96L helper form a substantive ~130L suite, not a 16L fragment. The velocity helpers remain real assertion-bearing code: include all their anchors in final repoint.
- **ShellEventListSupport.qml** (~100–170L): root shell/components/spies/metrics, `init`, `cleanup`, `waitForNative`, `openEventListFixture`, `cellAt`. KeyboardSelection (~341L) is separate from the 291L filter/editor scenario; each preserves its empty-project startup, loaded page and editor transitions. `typographyPage` destruction remains before release.
- **ShellNoteVisualsSupport.qml** (~250L): normal raster fixture/probe, lookup, capture/frame/color helpers. Ruler owns `unsignedRulerCapture` and `unsignedRulerJourney` (~150L); move `unsignedSongPrepared` and `restoreUnsignedSong` cleanup with them. The first retained original suite owns `test_dpr2SmallFontThinning`; the current runner selector `ShellNoteVisuals::test_dpr2SmallFontThinning` and `entry.name == "shell-note-visuals"` therefore stay valid. Color (~402L plus wrapper) is one raster family, below 600; do not create a tiny DPR-only file.
- **ShellVoicegroupSupport.qml** (~180–250L): stable standalone ApplicationSession/VoicegroupPanel fixture, `initTestCase`, cleanup, compare/capture/geometry helpers, and full-shell factory/save observers used by the mounted journeys. Preserve x/y/z prefixes but do not require earlier files to dirty, save, or mint a bank. Save (~426L) keeps synth mint, receipt and shared-bank journeys whole. `referenceProfileCapture` remains an ordinary existing test unless current runner says otherwise; do not invent a new DPR child.
- **ShellClipboardSupport.qml** (~180–220L): fixture/native clipboard cleanup, `gridNotes`, `editableNotes`, `noteFacts`, `noteById`, `selectedCount`, `noteCenter`, `pastedAt`, `noteFactsFrom`, `pastedOn`, `noteOn`, `tileOn`. RoundTrip (~442L) is **one indivisible replacement/paste/history journey**, retained as a cohesive under-600L exception to the target range, not chopped into order-dependent cases. Notes (~157L) and Range (~389L) are separate ownership laws.
- **ShellTransportSupport.qml** (~130–200L): open/cleanup/session/roll/menu helpers plus `glyphRendersInk`. Controls (~459L) includes glyph/profile/data checks and persists control preferences; Volume is separate. Session (~378L) owns real selected/background workspace transport routing. No standalone 69L profile suite.
- **ShellMenusSupport.qml** (~120–170L): `closeShell`, `cleanup`, `waitForNative`, `openDiagnostics`, `openShell`, `openSong`, `editorPage`, `checkMenuItem`, `menuOrder`. Menu topology, execution and loop editing have distinct assertion oracles.

All fresh shell `Entry` names use `<original-entry>-<kebab-case-suffix>`; the original entry keeps its original filename/name. Copy the original `windowing` and complete fixture set. The special note DPR child stays attached to the original entry only. In particular:

- ShellWindow/GridInput/Clipboard/Transport: `songs("mus_route101", "mus_littleroot_test")`.
- ShellTabs: `songs("mus_route101", "mus_littleroot_test", "mus_route102", "mus_gym")`.
- ShellVoicegroup: `songs("mus_route101", "mus_route102")` plus `asm/macros/synth_test.inc`, `data/sound_data.s`, `sound/voicegroups/fixture_alt.inc`.
- GridMenu/PitchBend/DrawerParity/EventList/NoteVisuals/Menus: `songs("mus_route101")`.

These are the existing `songs` helper's complete project-fixture unions, not just MIDI paths. Shared source QML/JS support is loaded relatively from the source test directory, as `NativeWait.js` already is; it is not a new decomp fixture. Register helper sources in the existing test executable source list for discoverability without placing `tst_` files into the production QML module.

## D — Roll QML checks

Paths relative to `src/checks/rollqml/`; **SPLIT** all three. `RollQmlTests.swift` already directory-enumerates them and is intentionally unchanged. Reuse its existing fixture union, one child per file and verbatim failure forwarding. Shared support bases retain `NativeWait.js` imports via `../editorqml/NativeWait.js`.

| Source verdict | Target files and exact whole-test seams (unchanged `test_` prefix omitted) | Shared support / lifetime |
| --- | --- | --- |
| `tst_SwiftRollTrackHeaders.qml` (1,118L): **SPLIT** | Retain original for geometry/scroll: `mountedRulerRollVelocityAndDrawerChromeGeometry`, `mountedBandGeometryAndRows`, `addTrackRowPublishesUsableFonts`, `scrollThumbAtBothLimits`, `mountedHeaderVisibilityRowsAndPixels`, `scrollbarThumbVisibleWhenRowsOverflow` (~210L). `tst_SwiftRollTrackHeaderInput.qml`: `renameEditorBoundToTrackRow`, `reorderMarkerStaysInsideInput`, `headerMenuRenameRowActivates`, `headerMenuFrameHasOutsideInputPoint`, `clickingHeaderTitleChangesSelectedRaster`, `hoveringHeaderTitleDoesNotCreateTooltip`, `yRenameEscapeAndTransientCancellation`, `yStructuralRemapDismissesMenuAndRestoresFocus`, `zMountedRenameAndReorderCommit` (~260L). `tst_SwiftRollTrackHeaderMenu.qml`: `zMountedMenuDispatchAndDismissal`, `zMountedHeaderVoicePickerJourneys` (~381L). `tst_SwiftRollTrackHeaderMeter.qml`: `zMountedMeterWindowRasterAndScopedRows` plus `meterPixels` (~160L, one raster domain). | `SwiftRollTrackHeadersSupport.qml` (~140–180L): root/bootstrap/components, `waitForNative`, `initTestCase`, `cleanup`, `cleanupTestCase`, `surface`, `item`, `near`, `rectOnSurface`, `openHeaderMenu`, `menuRow`, `chooseHeaderAction`. Keep meters' native window/capture setup and exact DPR profile assertions; no assumption menu/rename tests in another file ran first. |
| `tst_TimelinePan.qml` (696L): **SPLIT** | Retain original for pointer/camera: `wheelPansCamera`, `middleDragPansCamera`, `hoverChipOverlay`, `preRollCameraBounds`, `selectedPanRenders` (~250L). `tst_TimelinePanPublication.qml`: `coalescedRefreshMatchesFull`, `drumPadNamesFollowInitialProgram` (~220L): camera refresh/keyboard-label publication. | `TimelinePanSupport.qml` (~230L): all existing pre-test declarations, including diagnostics, mount/selected surface, lifecycle, gutter/keyboard-label helpers, selected-note count and `imagesDiffer`. Preserve one overlay lifetime and full native waits. |
| `tst_TimelineScrollbar.qml` (630L): **SPLIT** | Retain original for interaction: `tracksFollowViewportAndCamera`, `dragClampsAndReverses`, `trackPagingAndKeyboardNavigation`, `mountedBoundsAndExactPaging`, `keyboardParksThumbAndPreservesOtherAxis`, `releasedGrabAndExternalCamera`, `mountedAngleWheelMatrix` (~236L). `tst_TimelineScrollbarGeometry.qml`: `wheelAndResizeRebase`, `zoomDuringHeldDragRebase`, `liveGeometryAndDrawerResize`, `foldCollapseAndRestoredDrag`, `eventListHidesOnlyRollTrack`, `standaloneSignedRangeAndRebase`, `resizedAutomationTempoLaneWithoutScrollbar` (~250L). | `TimelineScrollbarSupport.qml` (~145L): all existing fixture properties/components and non-test functions (`waitForNative`, `surface`, `grid`, `bar`, camera values/maxima, midpoint, closeTo, thumb bounds, lifecycle). Keep signed-range standalone model and live-model bindings distinct; held-grab resize/rebase chains stay within their functions. |

Verification for slice D: `deno task verify:qml-roll --verbose`. Check that the child suite list contains every target above, and that no original test function/data row disappears. No new CMake `QML_FILES` entries: these are source-directory QuickTest suites, not production resources.

## E — Swift checks

All nine files are **SPLIT**. All paths below are relative to `src/checks/`. Preserve existing top-level check entry names and call ordering; no dispatcher change is needed. Removing `private` on a moved helper means module-internal only. Shared immutable IDs and fixtures remain defined once. The single covering lane for **every E row** is `deno task verify --filter swiftcore-projectsession --verbose` (SessionChecks.swift dispatch chain), not an invented filename filter.

| Source verdict | Exact destination / declaration seam | Shared state and sizing decision |
| --- | --- | --- |
| `automation/automationselection.swift` (1,038L): **SPLIT** | Retain original: `drawerAutomationRestoredInteractionContracts` (~180L). `automation/automationselection_band.swift`: `drawerAutomationBandIsolatesTempoAndCc`, `drawerAutomationMultiCcDragExcludesOthers`, `drawerAutomationGhostViewOnlyAndSurvives`, `drawerAutomationSelectionDeleteCommand` (~225L). `automation/automationselection_pencil.swift`: `drawerAutomationPencilOwnershipAndShift`, `drawerAutomationDetailThresholdPrecedence`, `drawerAutomationTempoBendClickRestore` (~260L). `automation/automationselection_mixed.swift`: `drawerAutomationMixedSelectionFixture`, `drawerAutomationArmHorizontalTempoDrag`, `drawerAutomationMixedSelectionDragPlayback`, `drawerAutomationTempoOnlyHorizontalPlayback`, `drawerAutomationMixedSelectionDeletePlayback`, `drawerAutomationMixedDragRebuildCancellation` (~370L). | Reuse existing `drawerAutomationAutomationFixture`. Mixed snapshot/playback helpers stay with their consumers. Keep `AutomationPageChecks.swift` invocation sequence untouched. |
| `editcheck/SelectionChecks.swift` (919L): **SPLIT** | Retain original: `runClipboardSelectionChecks`, `clipboardNoteSelectionChecks`, `clipboardLaneSelectionChecks`, `clipboardEmptyAndReplacementChecks` (~240L): selection payload/coverage. `editcheck/SelectionTrackChecks.swift`: `clipboardUnifiedModelChecks`, `clipboardTrackSelectionChecks`, `clipboardRemapBoundaryChecks`, `selectionPayloadMatches` (~320L): scope/remapping. `editcheck/SelectionTransitions.swift`: `clipboardUnifiedTimeSelectionChecks`, `clipboardSelectionTransitionChecks` (~370L): exact previous/current transition laws. | Entrypoint constructs the same session and calls helpers in unchanged order; do not create new fixtures per extracted function. `selectionPayloadMatches` remains single module-internal definition. |
| `selectionkey/localinputtier_text.swift` (779L): **SPLIT** | Retain `drawerOriginalNumericPromptTransaction` and `littlerootVelocityCancellation` in original (~515L): one numeric-prompt transaction/real-fixture cancellation surface. `selectionkey/localinputtier_window.swift`: `windowTierKeyboardOutcomes`, `coreEditingKeyboardOutcomes` (~260L): window command tier and selection command effects. | Keep the long prompt scenario intact; its captured fixture, open prompt, focus loss and revision sequence cannot be broken into new tests without changing meaning. Under-600 cohesive residual is accepted, rather than a 52L fixture file or 63L core-key file. Preserve the original function's calls into extracted outcomes and clipboard restoration. |
| `rollcheck/keyboard.swift` (700L): **SPLIT** | Retain `runKeyboardChecks`, `KeyboardSeed`, `withKeyboardSeed`, `checkKeyboardTranspose`, `checkKeyboardKeepsEditedNoteVisible`, `checkKeyboardResizeNotes`, `checkKeyboardSkipsGhosts` (~410L): note-key transaction semantics. `rollcheck/keyboard_timeline_insert.swift`: `checkTimelineInsertBlankTimeTracks`, `checkTimelineInsertBlankTimeLanes` (~145L): scoped timeline insertion. `rollcheck/keyboard_drum_labels.swift`: `checkDrumPadLabels` (~150L): drum keyboard labels. | `KeyboardSeed`/`withKeyboardSeed` already module-internal and reused by parity/time-selection files; retain ownership here, no 95L helper fragment. Keep both pre-seed and post-seed defers and undo invariants. |
| `velocity/VelocityPaintDetentChecks.swift` (673L): **SPLIT** | Retain ID constants, `drawerVelocityPaintAddNote`, `drawerVelocityPaintSetOrigins`, `drawerVelocityPaintCommitsOnce`, `drawerVelocityRampCommitsOnce`, `drawerVelocityLockedPaintUsesDetents` (~230L): paint/ramp commit law. `velocity/VelocityProgramFlowChecks.swift`: `drawerVelocityProgramFlowChecks`, `drawerVelocityFamilyPaint` (~450L): voice-family program-flow detents. | Program-flow scenario and its family helper stay together; one-domain under-600 exception. Shared constants/seed helpers become module-internal only where needed, no duplicate IDs. |
| `rollcheck/EditorGridCameraChecks.swift` (650L): **SPLIT** | Retain runner, `GridCameraIntegrationCounters`, `checkViewport`, `checkHoverChipResize`, `gridCameraNear` and shared IDs (~200L). `rollcheck/EditorGridLatticeChecks.swift`: `checkFractionalGridLattice`, `checkContentWindowBoundaryReversal` (~200L): fractional lattice/content window. `rollcheck/EditorGridProjectionChecks.swift`: `checkProjection`, `checkScratchDoubleDraw` (~245L): coordinate/hit/scratch projection. | Keep callback installation/restoration in `runEditorGridCameraChecks`. `gridCameraNear` is a three-line shared function, **not** a new support file. `EditorGridCameraIsolation.swift` stays unchanged and uses the retained shared IDs/counters. |
| `automation/domain/gestureNodeDrag.swift` (618L): **SPLIT** | Retain `drawerAutomationPanNeutralSnap`, async `coreAutomationPanUndoRegression`, `drawerAutomationGestureContractParity`, `drawerAutomationContractParityID` (~390L): node gesture/snap/history law. `automation/domain/gestureNodeContract.swift`: `drawerAutomationExactNodeContract` (~230L): exact duplicate-occurrence/index-preservation contract. | Existing call from `drawerAutomationGestureContractParity` to exact contract remains in place. Preserve async throws signature and awaited undo; no 35L history or 95L snap fragments. |
| `drawerpresentation/velocity.swift` (605L): **SPLIT** | Retain `drawerVelocityValueAxisLadder`, `drawerVelocityPsgIntrinsicRows`, `drawerVelocityKeysplitPerNoteMapping` (~305L): voice-derived velocity projection. `drawerpresentation/velocity_context.swift`: `drawerVelocityVoiceContextResolution`, `drawerVelocityProjectionRefresh`, `drawerVelocityVoiceContextInvalidation`, `drawerVelocityPlayheadDiagnostics` (~295L): live context refresh/invalidation. | Reuse existing external fixture builders; keep assertion messages and published-count deltas, no substitute golden data. |
| `rollcheck/static/camera.swift` (601L): **SPLIT** | Retain `runEditorCameraChecks`, `checkAffineCameraProjection`, `checkFallbackCamera` (~285L): pure camera transformations/bounds. `rollcheck/static/camera_wheel.swift`: `checkGridCameraWheel`, `checkVerticalCameraWheelContract`, `checkKeyboardGutterHoverTracksRows`, `checkHorizontalCameraWheelContract` (~320L): wheel-axis/input contract. | No need to dissect `runEditorCameraChecks` internally. Reuse `gridCameraNear` from the retained integration file and shared `gridCameraWheelID` rather than adding a tiny utility. Same entry call order. |

Registration owner adds every new E `.swift` to the explicit `swift_core_check` list in `src/checks/CMakeLists.txt`; original entries stay. No C++ checkcatalog edits because no lane/public entry changes.

## F — Production QML

All five files are **SPLIT**. New destinations stay beside the original. Preserve every `objectName`, component resource identity at the existing outer root, text/palette pair, model/delegate identity, focus scope and input event order. No facade object copying the presenter. Required inputs are the existing presenter objects plus visual geometry/fonts/palette and explicit focus/activation signals; never a second controller.

### `src/ui/songview/quick/EventListPage.qml` (1,402L)

- Retain `EventListPage.qml` (~300–400L): FocusScope, controller/public page contract, navigationFocus, appearance/font/metric properties, selection/edit/navigation orchestration, existing Shortcut declarations and controller lifecycle Connections.
- `EventListCell.qml` (~290–320L): entire inline `EventCell` declaration, including TextInput `editor`, `cellMouse`, drag/select/edit handlers and `cellHint`. Required inputs: existing row/column roles, controller, page geometry/appearance and owning page; retain controller-as-behavior owner. Send edit/focus/drop requests through the existing page functions, not new selection policy.
- `EventListTable.qml` (~350–400L): `tableHeader` and `tableRegion` including rowHeader, TableView/TableModel seven-column publication, drop indicator, both scrollbars; move `persistedColumnWidth`, `minimumColumnWidth`, `persistedColumnsWidth`, `columnWidth`, `columnOffset`, `boundedContentX/Y`, `requestTableLayout`, `publishTableRows` into this table module with the existing revision reads. Expose table item/row metrics to the page's navigation and edit functions; keep current scroll-to-row and column-revision callbacks pointed at it.
- `EventListToolbar.qml` (~200L): inline `ToolbarButton`, `toolbar`/chunk/filter/add/remove/count label and their tooltip. Signals retain current controller request calls and mapped menu coordinates.
- `EventListMenu.qml` (~150–180L): final menu Loader, type-ahead timer, menuPanel, `hoverRow`, `activateRow`; required controller/page metrics/appearance and focus return. No altered close policy or keyboard wrap/clamp behavior.

Do not separately extract a 50L keyboard or column helper file. Cross-file `page` references become explicit required properties; preserve revision dependency reads even if they look unused.

Verification: `deno task verify:shell --filter shell-event-list --filter shellwindow --verbose`, `deno task verify --filter swiftcore-projectsession --verbose`, `deno task verify:bridge`.

### `src/ui/songview/quick/swiftroll/EditorSurface.qml` (1,351L)

- Retain root (~250–350L): presenter bindings, one `applicationSession`, hint/modal coordination flags, `configureViewport`, `deliverWheel`, root background, drawer/other-events/status/shared-playhead composition, event-list activation. It owns the same bottom-up geometry and presenter lifetime.
- `EditorRollBand.qml` (~350–400L): `rollBandContent`/`rollStack` with gutter `rollGutterSide`, `rollPlot`/plotContent/PianoRollCanvas, `rollInput` and coalescer, and event-list host/Loader. Expose roll plot/input/gutter and event-page aliases; emit existing viewport invalidations. Keep flush-before-release/cancel and raw keyboard routing inside the input owner.
- `EditorRulerBand.qml` (~250L): `rulerBand` and `rulerInput`/coalescer, `rulerControls`/GridRowControl and ruler tooltip. Explicit grid/ruler/header geometry, fonts, hint scope and wheel sink; preserve content/local/window coordinate mappings.
- `EditorSurfaceMenus.qml` (~280–350L): `MenuMeasure`, `hoverRow`, `activateRow`, `headerMenuLoader`, `gridMenuLoader`, `timeSigMenuLoader` and their direct menu-open/focus Connections. Inputs: existing models, root coordinate item, anchor positions and actual input focus-return targets. Flags remain one owner's state, not copied properties.
- `EditorSurfacePrompts.qml` (~170–220L): `headerVoicePickerLoader`, `timeSigPromptLoader`, `insertTimePromptLoader`, `velocityPromptLoader`, `pitchBendPopupLoader`, associated model Connections and retained-release/anchor logic. Inputs include original rollInput/plot, trackHeaders, drawer top and body metrics. Preserve Loader `active/visible/enabled`, prompt z ordering, popup pass-through and completion focus.

Keep horizontal/vertical TimelineScrollbar declarations in the root (about 70L combined), avoiding a small scrollbar shell. Extracted full-size overlays must not create a clipping or z-order barrier; retain equivalent visual parent/stacking to the original root siblings. Header band remains the existing `TrackHeaderBand` instance.

Verification: `deno task verify:qml --verbose`, `deno task verify:qml-roll --verbose`, `deno task verify:shell --filter shell-grid --filter shell-pitch-bend --filter shell-event-list --verbose`, `deno task verify:bridge`.

### `src/ui/shell/ShellWindow.qml` (984L)

- Retain ThemedWindow root (~400–450L): ShellPresenter, startup/typography and normal-frame restore, close/persistence Connections, window Shortcut Repeater, SplitView/dock/editorScene Loader and scene-destroy acknowledgement, dialogs. Do not move the window-session lifetime into a child that can disappear before close acknowledgement.
- `ShellMenuBar.qml` (~310L): entire `menuBar: MenuBar` action tree and `nativeMenuText`. Required shell presenter and actionRevision; preserve `Action`/menu enabled revision dependencies and avoid adding `Action.shortcut` (the existing window dispatcher remains sole owner).
- `ShellStatusBar.qml` (~140–180L): entire `footer: Rectangle`, mouse-hint/status/polyphony caption/value blocks, metrics/spacing inputs; same palette pairs and object names.
- `ShellGridContextMenu.qml` (~120–150L): `contextRow`, outside-click overlay, `gridContextMenu`, right-click retarget/retained-release state. Required shell, original window overlay, editorScene and fonts/colors/spacing. Expose `open/close/x/y/visible` to existing shell Connections without copying command policy; preserve `Popup.Item` and overlay parent.

No new tiny ShellDialogs module. Verification: `deno task verify:shell --verbose` (all shell children, not only shellwindow) and `deno task verify:bridge`.

### `src/ui/songview/quick/swiftroll/TrackHeaderBand.qml` (829L)

- Retain `TrackHeaderBand.qml` (~350–400L): band geometry/text metrics, `configureTextMetrics`, `restoreHeaderFocus`, `rowIndexForTrack`, `hintProfileAt`, `deliverWheel`, `headerInput`/coalescer/hints/reorder marker and clipped `renameClip`/`renameEditor` lifecycle.
- `TrackHeaderRows.qml` (~280–330L): `TrackHeaderToggle`, translatedRows/trackHeaderRows Repeater, row background/activity/title/subtitle/toggles and addTrackRow. Required headersModel, palette, typography and row-area width; expose row-item lookup needed by `rowIndexForTrack`. Keep stable roles/handles, translated scroll offset and `pragma ComponentBehavior: Bound` semantics.
- `TrackHeaderScrollbar.qml` (~170–190L): `trackHeaderScrollBar`, thumb, thumbMouse/hover, track paging/keyboard/wheel/rebase/cancel. Required the same headersModel and original row geometry; emit existing focus-return request, no new camera authority.

Keep rename with root input/focus to avoid a 100L module whose interface mirrors its entire implementation. Verification: `deno task verify:qml-roll --verbose`, `deno task verify:qml --verbose`, `deno task verify:shell --filter shell-grid-input --filter shell-voicegroup --filter shell-note-visuals --verbose`, `deno task verify:bridge`.

### `src/ui/songview/quick/drawer/AutomationPage.qml` (751L)

- Retain `AutomationPage.qml` (~380–420L): FocusScope, `fallbackPalette`/`emptyModel`, geometry/body publication, gutter/AutomationTabs, `pushBodyFacts`, `geometryChanged`, `focusOrigin`, pencilCursor and modal creation/synchronization/destruction (`menuComponent`, `promptComponent`, `syncModals`, `createModals`, model/host Connections).
- `AutomationPlot.qml` (~350–390L): entire `plot` tree from background through all primitive/node/label/band/preview delegates, `plotInput`/MoveCoalescer, HoverHint and `cursorFor`. Required pageModel, gridModel, colors, hint service/scope, plot rect/DPR; expose actual input item/pressed/pointer position and focus item to the existing root. Preserve `Binding.RestoreNone`, release/cancel flush sequence and coordinate mapping of the window-parented pencil cursor.

Do not split the 70L modal lifecycle away from its owning page or manufacture a second empty-model adapter. Verification: `deno task verify:qml --verbose`, `deno task verify:shell --filter shell-drawer-parity --filter shell-grid-input --filter shellwindow --verbose`, `deno task verify:bridge`.

All new F production QML files must appear in root `CMakeLists.txt` `qt_add_qml_module(... QML_FILES ...)`. Root files/resource URLs stay unchanged. The final integrator owns this registration file; slice owners do not edit it concurrently.

## G — Production Swift owners

All five files are **SPLIT**, but **never** by moving registered slots to extensions. In the contracts below, “move a bridged method's implementation” means retain its exact declaration in the original class and call an internal same-type implementation named `<originalName>Impl` with unchanged arguments/return semantics. Non-bridged (`@QtIgnored`, private, internal) whole declarations move under their existing names. No stored-state copies, extra QObject or actor, or new asynchronous hop. Query references before an exported declaration/access change; the Swift index must be current.

### `src/swift/app/ApplicationSession.swift` (1,199L inventory; 1,201L observed during research)

Retain the class-body bridge contract, stored state and construction in `ApplicationSession.swift` (~350–500L), including all presenter accessors, `@QtSignal`s and QmlInstantiableStatus declarations. Split by actual authority:

- `ApplicationSession+ProjectOpening.swift` (~150–220L): `ProjectSwitchCandidate`, `ProjectRead` including `load`, `requestProjectSwitch`, `startProjectSwitch`, `finishProjectSwitch`, `failOpen`, `restoreStartup`. Store task/state properties on the main class; keep cancellation, prior-task chaining, candidate identity and service-close guards unchanged. Do not expose either nested type to QML.
- Extend existing **`ApplicationSession+Tabs.swift`** (118L → ~300L): `startOpen`, `openTab`, `openSongFromDock`, `makeCallbacks`, and implementation of `openSong`. This existing owner already handles reload/retirement and tab publication; do not create competing `+Presenters` or `+TabLifecycle` files.
- Extend existing **`ApplicationSession+Close.swift`** (138L → ~180–220L): implementations of `hostClosing`, `acknowledgeGridDetached`, `requestCloseAll`. Keep exactly-once document release after acknowledgement, and async retirement that captures work rather than retaining the session past QML teardown.
- `ApplicationSession+Ruler.swift` (~110–150L): `PendingTimeSignature`, `invalidateTimeSigPrompt`, and implementations of `openTimeSigPrompt`, `openTimeSigPromptAtCursor`, `acceptTimeSigPrompt`, `cancelTimeSigPrompt`, `captureTimeSigMenuPress`, `openTimeSigMenu`, `closeTimeSigMenu`, `timeSigChipTick`. Prompt state remains stored on the original class; preserve captured revision/session checks.
- `ApplicationSession+Audio.swift` (~190–260L): extract the initializer's polyphony `onJump` binding into `connectPolyphonyJump()` and its contiguous voice audition/voicegroup-change/save/sample-audition binding block into `connectVoiceAudition()`, each called at its original position around the retained eventList wiring; preserve all weak/session/service/revision guards. Move implementations of `play`, `playPause`, `stop`, `goToStart`, plus `publishSeek`, `refreshTransportPresentation`, `resyncTransportAfterEngineTransition`. Non-audio eventList/transport attach wiring can stay in init to preserve ordering; no blanket initializer rewrite.
- `ApplicationSession+Commands.swift` (~180–250L): implementations of `gridCommandAvailable`, `performGridCommand`, `routeGridKey`, `releaseGridKey`, `routeEventListCommand`, `performEventListCommand`, `handleGridEscape`, `cancelGridInput`, `requestSave`, `requestUndo`, `requestRedo`. Keep commandRouter authority and availability-before-async semantics, not a second dispatcher.
- Also place `persistTabRecipe`, `updateEditorChrome`, `updateEditorLaneRange` and implementations of `setVelocityColorMode`/`setNoteNameMode` in existing `ApplicationSession+Tabs.swift` (final ~360–400L): these persist/fan out tab-owned view state. Retain short `configurePersistence`, `restoreDisplayModes`, `fontMaps`, `spaceMap`, `configureTypography` in the main owner. Do not create an ~80L Preferences fragment or new preference keys.

Do not split tiny presenter accessor bodies into another file. This is the only G slice that writes existing `ApplicationSession+Tabs.swift` and `+Close.swift`.

Verification: `deno task verify --filter swiftcore-projectsession --filter swiftcore-bankhistory --verbose`, `deno task verify:shell --filter shellwindow --filter shell-tabs --filter shell-transport --filter shell-voicegroup --filter shell-grid-menu --verbose`, `deno task verify:bridge`.

### `src/swift/app/roll/PianoGrid.swift` (863L)

- Retain `PianoGrid.swift` (~350–450L): all bridge fields/slots/signals, stored state, init, `GridNote`, cancel/scroll enums and `GridSubdivisionMenuItem` bridge declaration. Leave simple setters/accessors where their implementation is already trivial.
- Extend existing **`PianoGrid+Gestures.swift`** (180L → ~430–550L): implementations of `beginPointer`, `updatePointer`, `endPointer`, `beginRightPointer`, `updateRightPointer`, `endRightPointer`, `doublePointer`, `beginPan`, `updatePan`, `endPan`, keyboard pointer/audition completion and input cancellation. Keep left/right gesture interaction in one owner; do not split press/release states across new state objects.
- `PianoGrid+Camera.swift` (~120–180L): implementations of `configureViewport`, `resetCameraScroll`, camera H/V scroll setters, horizontal/vertical wheel helpers and `handleWheel`. This owns camera mutation entry mechanics, not a copied camera. Preserve initial-home application and font-relative viewport zoom.
- `PianoGrid+Commands.swift` (~150–200L): implementations of `commandAvailable`, `performCommand`, `openGridMenu`, `dismissGridMenu`, `activateGridMenuRow`; move `gridDivisionText` and `refreshGridMenuPresentation` from existing Gestures into this single menu/command owner. Leave existing `PianoGrid+Support.swift` (172L) and `+SceneSync.swift` (314L) unchanged: they already own session projection/publication, so do not introduce a second Rendering extension.

Verification: `deno task verify --filter swiftcore-projectsession --verbose`, `deno task verify:shell --filter shell-grid --filter shell-clipboard --filter shellwindow --verbose`, `deno task verify:qml-roll --verbose`, `deno task verify:bridge`.

### `src/swift/app/drawer/automation/AutomationPage.swift` (808L)

- Retain `AutomationPage.swift` (~450–550L): complete bridge class surface, all stored state and stable handles/snapshots, policy/initialization and existing short public command/modal/tap dispatch slots.
- `AutomationPage+Session.swift` (~150–200L): move the entire `// MARK: Check-facing state` declarations (`hasGesture` through `laneClipAvailable`, all explicitly `@QtIgnored`) and `attach(session:palette:)`, `detach()`; these are the Swift-only observation/attachment contract. Keep the weak session, observer token and mutable storage on the original owner; widen private token to ignored internal only if needed. Do not turn diagnostics into QML properties.
- Extend existing **`AutomationLifecycle.swift`** (193L → ~290–360L) with implementations of `configureBody`, `refreshFromDocument`, `refreshEditCursor`, `refreshCamera`, `refreshPlayhead`. This is already the content rebuild/owned-state application owner. Keep per-parameter selection, prompt/menu/tap dispatch where it is; do not add new Publication/Modal/TapTempo files beside the existing `AutomationContentPublication.swift`, `AutomationOverlayPublication.swift`, `AutomationModal.swift` (485L) and `AutomationTapTempo.swift` (138L).

### `src/swift/app/drawer/automation/AutomationInteraction.swift` (719L)

- Retain `AutomationInteraction.swift` (~250–300L): input/button/modifier/cursor enums, `AutomationHover`/hint resolution, `AutomationGesture`, `AutomationRangeBand`, `updateHover`, `mappedPoint`, `phantomHit`, `snapped`, `source(of:)`, `shiftedAutomationSelection`: coordinate/identity input facts.
- `AutomationGestureEditing.swift` (~250–330L): whole existing `pressPlot`, `releasePlot`, `releaseBand`, `endPan`, `clearSelectionIfPressIsOutside`, `selectionContains`, sweep/pencil `update` overloads, `cancelGesture`, `commit`, `selectionScope`, `coveredLanes`, `coveredEventCount`, `selectedNodesDrag`: frozen transaction editing.
- `AutomationPointerDispatch.swift` (~200–250L): final extension's `dispatchPointerPress`, `dispatchPointerMove`, `updateGesture`, `dispatchPointerRelease`, `dispatchPointerDoubleClick`, `dispatchPointerLeave`, `dispatchEscape`, `cancelAllInteractions`: event dispatch/termination. Preserve `updateGesture`'s exact press-time facts and no-op guard, no repeated projection allocation.

The AutomationPage and AutomationInteraction rows are one slice because their internal extension contracts/access may change together. Verification: `deno task verify --filter swiftcore-projectsession --verbose`, `deno task verify:qml --verbose`, `deno task verify:shell --filter shell-drawer-parity --filter shell-grid-input --filter shellwindow --verbose`, `deno task verify:bridge`.

### `src/swift/app/voicelist/VoiceListController.swift` (658L)

- Retain `VoiceListController.swift` (~380–430L): `VoiceListRowHandle`, `VoiceListArgChoice`, `VoiceListEditOrigin`, the controller bridge contract/storage/init, choice/selection/reveal/audition/edit-intent slots. Do not split the small row-handle types into tiny files. The editor continues to be retained once, with `editor.owner = self` at the same point.
- `VoiceListController+Bank.swift` (~240–300L): whole ignored/internal binding/row-publication declarations `bindSession`, `editOrigin`, `isCurrentEditOrigin`, `refresh(from:)`, `refreshUsedVoices`, `setLoading`, `bindBank`, `voiceChanged`, `setVoicegroupChoices`, `setCurrentVoicegroupArg`, `revealTrackVoice`, `setUsedVoices`, and the final row-derivation helper block beginning `voiceAt`, `updateSelectorEnabled` through end-of-class helpers. Shared backing storage stays owned by the controller. Do not move live QML slots such as `selectSlot`, `pressVoice`, `commitVoicegroupSelection` to this extension.

Maintain stable 128 handles and targeted assignment, not model reset/reallocation. Verification: `deno task verify --filter swiftcore-projectsession --filter swiftcore-bankhistory --verbose`, `deno task verify:shell --filter shell-voicegroup --verbose`, `deno task verify:qml-roll --verbose`, `deno task verify:bridge`.

All new G Swift files are explicitly added to `PorydawApp` in `src/swift/app/CMakeLists.txt` by the final integrator. Existing companion files named above belong only to their indicated slice.

## H — Parallel execution slices and closed write sets

The table is the dispatch map. “Destinations in §X” is a closed expansion to the exact filenames named there, **not** permission to edit the whole directory. Original-file retention follows each section's table. All A/C/D/E/F/G write sets are pairwise disjoint. Only I owns registration/runner integration; only P owns ledger files. No slice edits this plan during parallel work.

| Slice / route | Exact write set | Prerequisites | Acceptance commands |
| --- | --- | --- | --- |
| A / SDD-track | `src/checks/editorqml/tst_EditorDrawer.qml`; the other 25 `tst_EditorDrawer<Concept>.qml` files from §A; `EditorDrawerTestSupport.qml`; the eight `EditorDrawer*Support.js` files named in §A. | Frozen 115/122 sources. | §A `verify:qml`; selector/process checks in I. |
| C01 / SDD-track | `src/checks/editorqml/tst_ShellWindow.qml`, `src/checks/editorqml/tst_ShellWindowCrossTab.qml`, `src/checks/editorqml/tst_ShellWindowDrawer.qml`, `src/checks/editorqml/tst_ShellWindowShortcuts.qml`, `src/checks/editorqml/tst_ShellWindowEditorKeys.qml`, `src/checks/editorqml/tst_ShellWindowPrompts.qml`, `src/checks/editorqml/tst_ShellWindowFocus.qml`, `src/checks/editorqml/tst_ShellWindowTimeEditing.qml`, `src/checks/editorqml/tst_ShellWindowVelocity.qml`, `src/checks/editorqml/tst_ShellWindowParameterKeys.qml`, `src/checks/editorqml/tst_ShellWindowLabelCommands.qml`, `src/checks/editorqml/tst_ShellWindowHints.qml`, `src/checks/editorqml/ShellWindowSupport.qml` | Frozen source family. | `deno task verify:shell --filter shellwindow --verbose` |
| C02 / SDD-track | `src/checks/editorqml/tst_ShellTabs.qml`, `src/checks/editorqml/tst_ShellTabsMouseHints.qml`, `src/checks/editorqml/tst_ShellTabsOpenSelect.qml`, `src/checks/editorqml/tst_ShellTabsClose.qml`, `src/checks/editorqml/tst_ShellTabsDrawer.qml`, `src/checks/editorqml/tst_ShellTabsBankLifetime.qml`, `src/checks/editorqml/tst_ShellTabsReload.qml`, `src/checks/editorqml/ShellTabsSupport.qml`, `src/checks/editorqml/ShellTabsRenderingSupport.js` | Frozen source family. | `deno task verify:shell --filter shell-tabs --verbose` |
| C03 / SDD-track | `src/checks/editorqml/tst_ShellGridMenu.qml`, `src/checks/editorqml/tst_ShellGridMenuInputZones.qml`, `src/checks/editorqml/tst_ShellGridMenuNoteActions.qml`, `src/checks/editorqml/tst_ShellGridMenuRulerLifecycle.qml`, `src/checks/editorqml/tst_ShellGridMenuRulerMarkers.qml`, `src/checks/editorqml/tst_ShellGridMenuRulerClipboard.qml`, `src/checks/editorqml/tst_ShellGridMenuAutomation.qml`, `src/checks/editorqml/ShellGridMenuSupport.qml` | Frozen source family. | `deno task verify:shell --filter shell-grid-menu --verbose` |
| C04 / SDD-track | `src/checks/editorqml/tst_ShellGridInput.qml`, `src/checks/editorqml/tst_ShellGridInputDraw.qml`, `src/checks/editorqml/tst_ShellGridInputEditing.qml`, `src/checks/editorqml/tst_ShellGridInputCancel.qml`, `src/checks/editorqml/tst_ShellGridInputKeyboard.qml`, `src/checks/editorqml/tst_ShellGridInputAutomation.qml`, `src/checks/editorqml/ShellGridInputSupport.qml` | Frozen source family. | `deno task verify:shell --filter shell-grid-input --verbose` |
| C05 / SDD-track | `src/checks/editorqml/tst_ShellPitchBend.qml`, `src/checks/editorqml/tst_ShellPitchBendCancellation.qml`, `src/checks/editorqml/tst_ShellPitchBendControls.qml`, `src/checks/editorqml/tst_ShellPitchBendPointer.qml`, `src/checks/editorqml/tst_ShellPitchBendKeys.qml`, `src/checks/editorqml/tst_ShellPitchBendRetarget.qml`, `src/checks/editorqml/ShellPitchBendSupport.qml` | Frozen source family. | `deno task verify:shell --filter shell-pitch-bend --verbose` |
| C06 / SDD-track | `src/checks/editorqml/tst_ShellDrawerParity.qml`, `src/checks/editorqml/tst_ShellDrawerParityAutomation.qml`, `src/checks/editorqml/tst_ShellDrawerParityVoiceVelocity.qml`, `src/checks/editorqml/ShellDrawerParitySupport.qml`, `src/checks/editorqml/ShellDrawerParityRasterSupport.js`, `src/checks/editorqml/ShellDrawerParityVelocitySupport.js`, `src/checks/editorqml/ShellDrawerParityVelocityInputSupport.js` | Frozen source family. | `deno task verify:shell --filter shell-drawer-parity --verbose` |
| C07 / SDD-track | `src/checks/editorqml/tst_ShellEventList.qml`, `src/checks/editorqml/tst_ShellEventListMenus.qml`, `src/checks/editorqml/tst_ShellEventListPresentation.qml`, `src/checks/editorqml/tst_ShellEventListKeyboardSelection.qml`, `src/checks/editorqml/ShellEventListSupport.qml` | Frozen source family. | `deno task verify:shell --filter shell-event-list --verbose` |
| C08 / SDD-track | `src/checks/editorqml/tst_ShellNoteVisuals.qml`, `src/checks/editorqml/tst_ShellNoteVisualsDetail.qml`, `src/checks/editorqml/tst_ShellNoteVisualsRuler.qml`, `src/checks/editorqml/ShellNoteVisualsSupport.qml` | Frozen source family. | `deno task verify:shell --filter shell-note-visuals --verbose` |
| C09 / SDD-track | `src/checks/editorqml/tst_ShellVoicegroup.qml`, `src/checks/editorqml/tst_ShellVoicegroupEditing.qml`, `src/checks/editorqml/tst_ShellVoicegroupPicker.qml`, `src/checks/editorqml/tst_ShellVoicegroupSave.qml`, `src/checks/editorqml/ShellVoicegroupSupport.qml` | Frozen source family. | `deno task verify:shell --filter shell-voicegroup --verbose` |
| C10 / SDD-track | `src/checks/editorqml/tst_ShellClipboard.qml`, `src/checks/editorqml/tst_ShellClipboardRange.qml`, `src/checks/editorqml/tst_ShellClipboardRoundTrip.qml`, `src/checks/editorqml/ShellClipboardSupport.qml` | Frozen source family. | `deno task verify:shell --filter shell-clipboard --verbose` |
| C11 / SDD-track | `src/checks/editorqml/tst_ShellTransport.qml`, `src/checks/editorqml/tst_ShellTransportVolume.qml`, `src/checks/editorqml/tst_ShellTransportSession.qml`, `src/checks/editorqml/ShellTransportSupport.qml` | Frozen source family. | `deno task verify:shell --filter shell-transport --verbose` |
| C12 / SDD-track | `src/checks/editorqml/tst_ShellMenus.qml`, `src/checks/editorqml/tst_ShellMenusCommands.qml`, `src/checks/editorqml/tst_ShellMenusLoop.qml`, `src/checks/editorqml/ShellMenusSupport.qml` | Frozen source family. | `deno task verify:shell --filter shell-menus --verbose` |
| D / SDD-track | Three original roll QML files and the five new `tst_` destinations plus three support bases explicitly named in §D, all under `src/checks/rollqml/`. | None beyond source freeze. | `deno task verify:qml-roll --verbose` |
| E / SDD-track | Nine original Swift check files and all 14 new `.swift` destinations explicitly named in §E. Existing dispatchers/fixtures/IDs outside those files are read-only. | Frozen checks. | `deno task verify --filter swiftcore-projectsession --verbose` |
| F1 / SDD-track | `src/ui/songview/quick/EventListPage.qml`, `EventListCell.qml`, `EventListTable.qml`, `EventListToolbar.qml`, `EventListMenu.qml`. | Existing page interface remains stable. | Event-list commands in §F. |
| F2 / SDD-track | `src/ui/songview/quick/swiftroll/EditorSurface.qml`, `EditorRollBand.qml`, `EditorRulerBand.qml`, `EditorSurfaceMenus.qml`, `EditorSurfacePrompts.qml`. | Child production root interfaces remain unchanged in F1/F3/F4. | EditorSurface commands in §F. |
| F3 / SDD-track | `src/ui/shell/ShellWindow.qml`, `ShellMenuBar.qml`, `ShellStatusBar.qml`, `ShellGridContextMenu.qml`. | Existing shell/session interface remains stable. | `deno task verify:shell --verbose`; `deno task verify:bridge`. |
| F4 / SDD-track | `src/ui/songview/quick/swiftroll/TrackHeaderBand.qml`, `TrackHeaderRows.qml`, `TrackHeaderScrollbar.qml`. | Existing band interface remains stable. | TrackHeaderBand commands in §F. |
| F5 / SDD-track | `src/ui/songview/quick/drawer/AutomationPage.qml`, `AutomationPlot.qml`. | Existing page/model interface remains stable. | AutomationPage QML commands in §F. |
| G1 / SDD-track | `src/swift/app/ApplicationSession.swift`, existing `ApplicationSession+Tabs.swift`, `ApplicationSession+Close.swift`, and new `ApplicationSession+ProjectOpening.swift`, `+Ruler.swift`, `+Audio.swift`, `+Commands.swift`. The `+` abbreviations all expand to `ApplicationSession+…` in this directory. | Freeze in-flight production edits first. | ApplicationSession commands in §G. |
| G2 / SDD-track | `src/swift/app/roll/PianoGrid.swift`, existing `PianoGrid+Gestures.swift`, new `PianoGrid+Camera.swift`, `PianoGrid+Commands.swift`. | Existing grid bridge interface remains stable. | PianoGrid commands in §G. |
| G3 / SDD-track | `src/swift/app/drawer/automation/AutomationPage.swift`, `AutomationInteraction.swift`, existing `AutomationLifecycle.swift`, new `AutomationPage+Session.swift`, `AutomationGestureEditing.swift`, `AutomationPointerDispatch.swift`. | Shared Page/Interaction internal contracts are owned within this one slice. | Automation Swift commands in §G. |
| G4 / SDD-track | `src/swift/app/voicelist/VoiceListController.swift`, new `VoiceListController+Bank.swift`. | Existing controller bridge interface remains stable. | VoiceListController commands in §G. |
| I / SDD-track, single integrator | `src/checks/editorqml/EditorQmlTests.swift`, `EditorQmlProfileChildren.swift`, `EditorQmlProfileEvidence.swift`, `EditorQmlBootstrap.swift`, `EditorQmlBootstrapSupport.swift`; `ShellQmlTests.swift`, new `ShellQmlEntries.swift`; `src/checks/CMakeLists.txt`, `src/swift/app/CMakeLists.txt`, root `CMakeLists.txt`. | A–G source moves ready and reviewed; no other registration writer. | Controller union below, plus selected drawer routing commands in §B. |
| P / SDD-track, one repoint owner | Only `src/checks/**/proof.*.txt` entries whose **S header file/function pairs occur in A–G/I's move manifest**, including message-bearing support helpers. No source or registration writes. This semantic set is frozen from the pre-move inventory before dispatch. | All sources/registration frozen and runnable. | `deno task proof check`; then `deno task proof check --executed --strict-mappings` after fresh executed evidence. |

During dispatch use the expanded concrete filename lists, not directory globs; no arbitrary additional helper file is authorized. D adds five test files and three support bases; E adds fourteen Swift files.

## I — Integration and verification gate

1. **Freeze and inventory before dispatch.** Do not move task-115/task-122 checks while writers/ledger reviewers still edit them. Snapshot every original `test_*`/Swift entry, data row, assertion message+occurrence, support function, required fixture and process/profile selector. Capture the S entries citing those exact sources/functions. This is source-move provenance, not a ledger disposition audit. Check QtBridge references before changing exported access.
2. **Integrate registered sources once.** I implements §B and updates all three CMake lists, with the exact new production QML/Swift/check files; add no glob convention. CMake must see every new Swift implementation and production QML module. Test QML stays source-discovered/entry-dispatched. Preserve generated EditorQmlPaths/RollQmlPaths and existing import/plugin paths.
3. **Keep shell registration cohesive.** Adding all entries to the current 420L ShellQmlTests.swift risks creating the next oversize file. Move `Entry`, `textContrastEntries`, `projectFixture`, `songs`, and `entries` as one ~250–400L `ShellQmlEntries.swift` registry; `ShellQmlTests.swift` retains process bootstrap, manifest generation and special DPR child execution (~320L). Use a single internal registry namespace/type, no public shim. Add ShellQmlEntries.swift to `shell_qml_lane`. Preserve existing text-contrast and polyphony entries and DPR profiles untouched. Original note-visual filename/entry retains its DPR2 selector.
4. **Inspect moved interfaces and ordering.** Compare the frozen declaration/assertion inventory with the complete new ownership map; each original test/data function occurs exactly once, every helper's assertions still execute, no suite is silently undiscovered, no unreachable production QML remains. Reconcile objectName/resource/bridge member inventories. Record actual destination sizes/cohesion; no new >600L multi-concept file or <100L fragment. Preserve existing selective entry filtering and source fixture restoration. File-boundary movement must not be “fixed” by deleting assertions or changing expected values.
5. **Run settled-tree controller checks once**, coalescing identical slice commands into this covering union:

   ```sh
   deno task verify --filter swiftcore-projectsession --filter swiftcore-bankhistory --verbose
   deno task verify:qml --verbose
   deno task verify:qml-roll --verbose
   deno task verify:shell --verbose
   deno task verify:bridge
   ```

   Run the two selected drawer commands in §B once as runner smoke, observing which child files and profiles run. These are deliberate distinct selection paths, not repeats to confirm a reported failure. The harness builds incrementally itself; no direct CMake invocation and no `--no-build` flag. Native-window suites require an idle macOS desktop; do not run them concurrently with another UI lane or user interaction. Compare log test identities/data rows and profile output, not raw pass-count equality (shared setup assertions now execute per suite).
6. **Actual application smoke for F/G**, after `deno task build:app`: launch `open -n build/porydaw.app --args --project "$scratch" --song mus_route101`, with `$scratch` set to the controller-staged disposable `build/split-smoke-project` copy of `src/checks/fixtures/decompproject`, never the checked-in fixture itself or a manually copied `/tmp` decomp tree. The executable's real help declares `--project`/`--song` (`PorydawShellApp.swift`). Observe the production ShellWindow: switch both songs/tabs, pan/zoom and draw/undo a note, rename/scroll a track header, open/reroute/dismiss ruler and note menus, edit an event-list cell and return focus, show/resize each drawer and complete/cancel automation and velocity gestures/prompts, open voice picker/editor, audition, undo, close/reopen and quit. Capture the actual window via the macOS app-window skill; verify no missing controls, changed stacking/focus or Qt warning. Offscreen profile PNGs remain **offscreen composition evidence**, not physical DPR proof. New QML parent/stacking changes need this visual smoke in addition to tests.
7. **Review gate and bounded fixes.** Each slice is reviewed against its exact move and preservation contract; integration gate covers runner discovery/fixtures/bridge reachability. Fix only split-induced regressions in the owning write set; do not run checks against sibling half-edits. Review milestones are the accepted source/integration freeze and the final proof-complete wave. There is one Git checkpoint after P, containing source moves, registration and their repaired anchors together. Never persist a split commit that drops its proof anchors and rely on a later standalone ledger reconciliation to repair it. The parallel write sets avoid cross-slice file reuse before this checkpoint; no per-file or per-suite commits are required.

## P — ONE final proof-anchor repoint pass

This is the **last source-migration operation**, performed once after the checks and registrations freeze. The path-only precedent is `344b711b` after `8065e447` (964 S lines); this wave must avoid leaving that temporal gap.

1. Merge the per-slice old-file/function → new-file/function move manifest and use the pre-dispatch S inventory to find affected records. Include predicates in JS/QML support and reused Swift companion files, not only the 36 original files. Preserve all A/S IDs, dispositions, Mapping text, counts and C++ reference revision/hash. No new coverage claim or ledger-status upgrade belongs in this pass.
2. `deno task proof --help` has **no repoint command**. Use existing exact-entry editing rather than inventing a nonexistent flag:

   ```sh
   deno task proof:edit <proof-path> <S-id> --before '<exact old S header>' --after '<exact new S header>' --apply
   ```

   Apply each affected S header once. Whole moved test/check functions keep function names, so normally only the path changes. If a formerly inline predicate necessarily moved into a named internal implementation, update the function field to its real new owner in this same pass; the message literal and `#n` occurrence stay verbatim. Never use a broad basename replacement, `Anchor: function`, or `Anchor: deleted` to hide a failed message resolution. Ambiguous repeated messages require the original occurrence order, not a guessed match.
3. Run `deno task proof check` and `deno task proof check --executed --strict-mappings` against the freshly generated controller lane evidence. The first proves every path/message resolves; the second checks execution identity/mapping shape. Distinguish unrelated pre-existing execution debt from moved-anchor failures, report it without silently weakening the strict command or changing dispositions. Do not make a second speculative “reconciliation” pass: any real code fix after source freeze invalidates the gate and must be reviewed as a fix to that source slice, with its exact anchor update in the same integrated change.
4. Final acceptance: all 36 verdicts implemented; every target is registered/discovered; source/function/assertion inventories agree; all named lanes and actual app smoke recorded; no stale moved S paths; no unrelated ledger rows edited. Commit/checkpoint ownership remains with the controller. This planning task itself performs **no builds, tests, source edits or commits**; only the requested plan file is written.
