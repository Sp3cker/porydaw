# Plan 01 — Drawer lanes (planner: SmoggyMollusk — COMPLETE, *NOT VERIFIED as stated*)

> Investigator correction: my original #1 pick (shared lane kernel over 37 files) is REJECTED by the
> planner with evidence. Do NOT build a generic kernel. Execute the narrower win below.

## Verdict

NOT VERIFIED as stated. The three lanes share a lifecycle PATTERN
(press-freeze → thresholded preview → release-gated single commit → teardown/republication),
not one duplicated pipeline. Mechanically extractable overlap is ~400–650 of 11,805 lines (~3.4–5.5%).
Every stage's payload half is lane-specific; genuinely shared machinery is already extracted
(EditorDrawerPage, QListModelSync, DrawerPan, DrawerStaticsContent, PromptAppearance);
a generic kernel would add adapter indirection that RAISES per-change token cost
(73 of 102 recent lane-touching commits touched exactly one lane — today a single-lane change reads one
self-contained lane; post-kernel it reads kernel + adapter + lane).

## Evidence

- Counts (wc -l): automation/ 21 files, velocity/ 9, voicechanges/ 7 = 37 files, 11,805 lines.
  Anchors confirmed: AutomationPage 608, VelocityInteraction 532, VelocityPage 518,
  VoiceChangesPage 513, VoiceChangesInteraction 488, AutomationInteraction 245.
- Stage-by-stage (gesture half, 8 files / 2,499 lines): entry routing SIMILAR, press-freeze SIMILAR,
  preview SIMILAR, release gate SIMILAR — but transaction construction LANE-SPECIFIC and document commit
  LANE-SPECIFIC (three disjoint APIs: `session.document.setVelocities` vs
  moveLanePoints/writeLane/deleteLanePoints vs AutomationCommit.apply). Non-gesture modals LANE-SPECIFIC.
- Projection/publication half (14 files): motif-level similarity only; cache strategies differ per lane
  (velocity handle-geometry key; voice entry/picker caches; automation revision-scoped cache with 3 display
  lists / 3 writers). Automation's content/overlay publication split has no velocity/voice counterpart.
- Already-shared layer exists: EditorDrawerPage protocol (EditorDrawer.swift:27-40), QListModelSync
  (syncModel/syncRetained/publish), DrawerPan (18 lines, used by all 3 lanes), DrawerStaticsContent
  (buildGrid/buildTickRects used by velocity + voice), PromptAppearance.
- Literal duplicates found (~60–100 lines total): (1) identical palette grid color map literal at
  VelocityPublication.swift:236-240 and VoiceChangesPublication.swift:126-130; (2) writer-swap + finish +
  equality-gate + displayRevision bump pattern at VelocityPublication.swift:241-270,
  VoiceChangesPublication.swift:133-148, AutomationDrawingContent.swift:199-203; (3) triplicated
  retainedEmptyDisplayList() (VoiceChangesPublication.swift:92-98, AutomationDrawingContent.swift:205-211,
  VelocityPage.swift:224); (4) identical Qt button enum triples (left=1/right=2/middle=4) at
  VelocityPage.swift:25-28, VoiceChangesPage.swift:18-21, AutomationInteraction.swift:16-19.

## Preservation constraints

- QML-visible surface per lane unchanged (page classes, contentUrl strings, all published props/methods
  consumed by VelocityPage/VelocityPrompt, VoiceChangesPage/VoicePicker(+Prompt)/VoiceChangeMenu,
  AutomationPage/AutomationPlot/AutomationMenu/AutomationPrompt qml; EditorDrawer.qml:386-417 detents).
- QtBridge rules: QML-facing members stay in @QtBridgeable bodies; pages stay registered PorydawApp
  elements via ApplicationSession; QListModel row types registered. Guard `deno task checks:bridge`.
- EditorDrawerPage seam unchanged. Behavior: press-time freezing, commit-at-most-once-per-gesture,
  stale-capture cancellation, syncModel row stability, displayRevision bumps only on change, writer reuse.
- Per-lane InputSurface/Modifier enums keep lane-scoped names — only the identical Qt button constants merge.
- `src/checks/` harnesses reference page internals (velocity/, drawerpresentation/) — reference-scan first.

## Steps

1. Hoist display-list publication residue into DrawerStaticsContent: add shared helper
   (gridPaletteColors + finish-and-swap gate: writer reuse, finish(), equality compare, assignment,
   displayRevision bump) + shared retainedEmptyDisplayList(). Migrate velocity first (simplest 1–2 list
   shape), then voice; automation adopts only color constant + empty-list helper (keep 3-writer shape).
   Files: DrawerStaticsContent.swift (add), VelocityPublication.swift:227-270,
   VoiceChangesPublication.swift:92-148, AutomationDrawingContent.swift:14-18,199-211.
2. Merge triplicated Qt button enum → new `DrawerQtButton` beside DrawerPan.swift; delete the three copies.
   Precondition: grep scan across src/swift + src/checks. Do NOT merge InputSurface/Modifier enums.
3. Write the lane anatomy map (highest token ROI, zero code risk): doc block in EditorDrawer.swift or new
   drawer README — shared layer + per-lane file anatomy (Page/Interaction/Transactions/Scene/Projection/
   Publication + automation extras). Turns 37-file discovery into one read.
4. Verify: `deno task checks:bridge` + harnesses under src/checks/velocity/, drawerpresentation/,
   automation/voice counterparts. No new tests (equality gates observable via existing checks).

## Risks

- Helper extraction must preserve exact buffer swap order (COW-copy avoidance comment at
  VelocityPublication.swift:241-242).
- Enum merge spans 3 lanes — missed src/checks reference breaks build (scan precondition).
- Automation is structurally distinct — do not force into velocity/voice shape.
- Anatomy map must be maintained when lanes are added or it rots.

## Non-goals

- NO generic lane kernel / shared gesture state machine / shared transaction protocol (rejected).
- No changes to EditorDrawerPage, QListModelSync, QML files, QML-visible members, state machines,
  payloads, commit paths, or production-mirror comments. No touching automation's content/overlay split.
- otherEvents lane (2 files, 283 lines) out of scope.

## Assumptions

- Production C++ in mirror comments is external; per-lane traceability comments are load-bearing.
- Overlap figures are structured estimates (scout comparisons + spot verification), not automated detection.
- Co-change counts: last 3 months, 102 lane commits (73 single / 5 double / 24 triple, uninspected —
  may include mechanical sweeps, further weakening the kernel case).
