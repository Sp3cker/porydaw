# Drawer anatomy

Paths below are relative to this directory unless stated otherwise. This map covers all 45 drawer Swift files and the shared model-sync file outside it.

## Shared layer

| File | Types / ownership |
| --- | --- |
| `EditorDrawer.swift` | `EditorDrawerPage` attachment/cancellation seam; `EditorDrawerBodyPolicy` sizing contract; `EditorDrawerPresenter` and `EditorDrawerSectionState` publish container chrome, geometry, focus and preferences. |
| `EditorDrawerLayout.swift` | `EditorDrawerLayout` owns attached-page slots, visibility/height preferences, resize sessions, focus transitions and resolved layout snapshots. |
| `DrawerPan.swift` | `DrawerPan` scrolls the shared camera; `DrawerQtButton` holds Qt mouse.button constants shared by all lanes; `manhattanExceeds` tests activation travel. |
| `DrawerStaticsContent.swift` | `DrawerStaticsContent` builds grids, tick/anchored rectangles and dashed frames from `DrawerStaticRect` / `DrawerAnchoredRect`; `gridPaletteColors(_:)` supplies shared grid colors and `retainedEmptyDisplayList(cached:)` reuses a caller-retained empty list. Each lane owns its finish/swap/equality gate. |
| `PromptAppearance.swift` | `PromptAppearance` resolves font-relative prompt layout; `PromptStyle` publishes retained palette/font/surface styling. |
| `LaneCaptionMetrics.swift` | `LaneCaptionMetrics` retains native caption height and text-advance measurements. |
| `../QListModelSync.swift` | `syncModel` preserves matching row prefixes/suffixes; `syncRetained` updates retained row objects; `publish` equality-gates properties; `QmlColor.clear` supplies transparent seeds. |

## Lane lifecycle

Editing gestures follow press-freeze → thresholded preview → release-gated single commit → teardown/republication; prompts and menus have their own captured acceptance paths. The three page types are registered PorydawApp elements, resolved through `ApplicationSession`, and attached through `EditorDrawerPage` with a fixed `contentUrl` for their QML body. Session/document ownership, retained caches and publication ordering remain lane-specific.

## Velocity (`velocity/`)

| File | Role |
| --- | --- |
| `VelocityPage.swift` | QML surface, retained state, lifecycle wiring, body policy and bridged note handles. |
| `VelocityInteraction.swift` | Pointer/prompt state machine: freezes notes/maps, previews drag/ramp/paint/band gestures, selects notes and commits velocities. |
| `VelocityTransactions.swift` | Frozen gesture/prompt values and pure relative/ramp/paint payload and draft-validation policies. |
| `VelocityScene.swift` | Explicit scene/interaction/context inputs and axis/handle outputs; builds handle rows without owning page caches. |
| `VelocitySceneValues.swift` | Session → note/context facts, then ruler rows, grid metrics, time axis and model-band rectangles. |
| `VelocityProjection.swift` | Camera/value-axis → scroll-stable note coordinates and circle/stem hit testing. |
| `VelocityPublication.swift` | Scene assembly, retained axis/handle models, geometry reuse, display lists, transient overlays and readout publication. |
| `VelocityAxis.swift` | Font-relative node/ruler geometry and continuous/intrinsic velocity scales, graduations, labels and coordinate conversion. |
| `VelocityContext.swift` | Resolves bank voice/per-key velocity maps and current-context presentation, including split/keyless context policy. |

## Voice changes (`voicechanges/`)

| File | Role |
| --- | --- |
| `VoiceChangesPage.swift` | QML surface, retained state, attachment/refresh wiring, body policy and pointer/picker/menu entry points. |
| `VoiceChangesInteraction.swift` | Marker drag/pan and captured picker/menu state machine; audition routing, stale-target checks and document mutation dispatch. |
| `VoiceChangesTransactions.swift` | Frozen occurrence targets, drag/picker/menu captures, revision/track validation and semantic mutation construction. |
| `VoiceChangesScene.swift` | Explicit facts → static scene/readout; shared camera x mapping, context resolution and marker-hit delegation. |
| `VoiceChangesProjection.swift` | Facts → marker/gutter/readout/picker/menu rows; bridged handles, caption measurements and filtered picker/audition cache. |
| `VoiceChangesPublication.swift` | Session fact reads, marker cache/reuse, snapping/hit-test adapters and retained scene/display-list/modal publication. |
| `VoiceLanePolicy.swift` | Held-slot and occurrence resolution, marker-hit policy, page constants and voice/slot label formatting. |

## Automation (`automation/`)

| File | Role |
| --- | --- |
| `AutomationPage.swift` | QML surface, retained state, body policy and wrappers for lifecycle, input, modal and command operations. |
| `AutomationPage+Session.swift` | Catalog queries and viewport/session attach/detach ownership, callback setup and initial publication. |
| `AutomationInteraction.swift` | Input/modifier/cursor vocabulary, hover resolution, gesture/range-band state and point/selection mapping helpers. |
| `AutomationPointerDispatch.swift` | Pointer/Escape/cancellation state-machine dispatch; routes tabs, pan, range band and active gesture updates. |
| `AutomationGestureEditing.swift` | Press-time captures, gesture preview/release, selection-aware node drag and semantic commit dispatch. |
| `AutomationTransactions.swift` | Frozen lane facts, axis locking and thresholded point-drag/release policy. |
| `AutomationNodeTransactions.swift` | Single/selected-node and origin-phantom drag transactions, plus captured value-prompt outcomes. |
| `AutomationDrawingTransactions.swift` | Frozen pencil/freehand and drag/ramp sweep sampling, previews and completed span edits. |
| `AutomationEdits.swift` | Lane replacement canonicalization, occurrence move/delete resolution, range plans and revision-gated document commits. |
| `AutomationScene.swift` | Session/cache → active lane, tab/selection/context facts; pure preview, body-configuration and activity resolution. |
| `AutomationProjection.swift` | Camera/scale/snap facts → coordinates, cells, curves, scale labels and marker visibility. |
| `AutomationLaneProjection.swift` | Revision-bound occurrence snapshots, projected nodes/curves/phantoms and row-stack selection/hit policies. |
| `AutomationProjectionCache.swift` | Revision-scoped snapshots/rows and camera/parameter-sensitive lane projection and snap-policy reuse. |
| `AutomationContentPublication.swift` | Fact/projection assembly and retained tabs, value-axis labels, ghost names and active node-model publication. |
| `AutomationDrawingContent.swift` | Builds and equality-publishes three display lists: grid/chrome, static curves/selection and preview drawing. |
| `AutomationOverlayPublication.swift` | Publishes band/hover/preview/readout geometry, prompt/menu/tap-tempo state, typography and retained node rows. |
| `AutomationLifecycle.swift` | Sequences rebuilds, context/activity publication, configuration and document/camera/playhead refresh with stale-capture cancellation. |
| `AutomationModal.swift` | Captured point/lane/range menus, value/delete prompts, lane clipboard and acceptance/action dispatch. |
| `AutomationSelectionCommands.swift` | Selection command availability/routing, scopes, clipboard range operations, transforms, nudges and reveal behavior. |
| `AutomationTapTempo.swift` | Tap cadence/session and monotonic timing; publishes live BPM and commits the captured tempo after idle. |
| `AutomationHandles.swift` | Bridged tab/node/menu/hover row objects and equality-aware retained-node value updates. |

## Other-events band (`otherEvents/`)

This is a read-only diagnostic band, not an editable drawer page.

| File | Role |
| --- | --- |
| `OtherEventsBandPresenter.swift` | QML-facing retained marker rows, viewport/document/camera refresh and hover tooltip publication. |
| `OtherEventsStrip.swift` | Classifies playback events, excludes consumed XCMD data, finds orphan note-offs and builds markers/tooltip lines. |

## Where to change X

| Change | Start here |
| --- | --- |
| Velocity document commit | `VelocityPage.commitVelocities` → `session.document.setVelocities`; both gesture release and prompt acceptance use this path. |
| Voice-change document commit | `VoiceChangesTransactions` validates captures; `VoiceChangesPage.commit` dispatches `moveLanePoints`, `writeLane` or `deleteLanePoints`. |
| Automation document commit | `AutomationCommit.apply` applies lane edits through `writeLane` / `editTempo`, and document plans through `applyRangeEdit`; range clipboard/transforms also route through selection commands. |
| Other-events document commit | None: classification and presentation only. |
| Hit testing | `VelocityProjection.hitTest` (circles/stems); `VoiceChangesScene.markerHit` → `VoiceLanePolicy.marker`; `AutomationLaneProjection.hitTest` (nodes), `AutomationRowStack.hitTest` (selection), plus `AutomationPage.phantomHit`. |
| QML-facing members | The `@QtBridgeable` page/presenter/handle class bodies above, not their helper extensions; `@QtTracked` / `@QtSignal` declarations stay on those owners. |
| Velocity checks | `src/checks/velocity/` and `src/checks/drawerpresentation/` (repository-relative). |
| Voice-change checks | `src/checks/drawerpresentation/` (voice projection, picker, interaction, lifecycle and menu coverage). |
| Automation checks | `src/checks/automation/`; shared chrome/layout coverage in `src/checks/drawerpresentation/`. |
| Other-events band checks | `src/checks/drawerpresentation/` (other-events band coverage). |

No shared lane kernel by design: lanes share a lifecycle pattern, not a pipeline; see [Plan 01](../../../../docs/plans/swift-token-cost/01-drawer-lanes.md).
