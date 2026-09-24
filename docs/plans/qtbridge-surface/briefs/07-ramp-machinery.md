# Brief 07 — Delete the unreachable ramp presentation machinery

## Context

Finding G (audit §2), reachability proven: every automation parameter sets
`interpolation = .step` (`AutomationParameter.swift:195`), the field is
app-internal (never persisted), so `AutomationProjection.swift:301` never
yields `.ramp`, the `ramps` model is always empty, and the QML ramp
`Repeater` can never instantiate — the unexercised path already hid one
exposure bug (`model.primitiveName`, finding A). Decision (plan.md): delete
the presentation path; keep the `.ramp` **math** (live: sweep gestures at
`AutomationDrawingTransactions.swift:108`, domain check
`tst_automationdomain.swift:218`). The dead check helper
`automationRampItems()` is why the bug went unnoticed — it goes too.

## Exact write set

- `/src/ui/songview/quick/drawer/AutomationPage.qml`
- `/src/swift/app/drawer/automation/AutomationPage.swift`
- `/src/swift/app/drawer/automation/AutomationHandles.swift`
- `/src/swift/app/drawer/automation/AutomationContentPublication.swift`
- `/src/swift/app/drawer/automation/AutomationOverlayPublication.swift`
- `/src/swift/app/drawer/automation/AutomationLifecycle.swift`
- `/src/swift/app/drawer/automation/AutomationParameter.swift` (conditional,
  step 4)
- `/src/swift/app/drawer/automation/AutomationProjection.swift` (conditional,
  step 4)
- `/src/checks/editorqml/tst_EditorDrawer.qml` (helper deletion only)

## Prerequisites

02 (guard), 04; must land **after** 03's recorded state (03 explicitly left
`AutomationHandles.swift:83` to this brief). Parallel with 05/06/08.

## Interface contract — deletions

| What | Site |
|---|---|
| QML ramp `Repeater` (whole block incl. `model.primitiveName` reads) | `AutomationPage.qml:345-362` |
| `ramps` model property | `AutomationPage.swift:140` |
| `syncRamps(_:)` | `AutomationOverlayPublication.swift:320-328` |
| ramp publication branches: `segments` array, `appendCurve(…, ramps:)` parameter/call, `case .ramp:` append | `AutomationContentPublication.swift:126,151,238,257-262` |
| detach-time `ramps` clear | `AutomationLifecycle.swift:41` |
| `AutomationRampHandle` class (whole declaration, `:76-102`) | `AutomationHandles.swift` |
| `automationRampItems()` helper | `tst_EditorDrawer.qml:3187-3190` (zero callers, verified) |

STAY: `AutomationInterpolation` enum incl. `case ramp` and
`value(at:from:to:)` (`AutomationParameter.swift:135-146`); all sweep-gesture
behavior and its checks (`drawerAutomationSweepSteppingAndRampFinish` et al.
— live predicates cited by the automation ledgers' S009-S015/S028-S030).

## Implementation steps

1. `lsp references` on `AutomationRampHandle`, `syncRamps`, `ramps` — the
   table must be complete; extra hits → stop and report.
2. Delete the table's declarations/blocks; repair call sites exactly as
   listed (e.g. `appendCurve` keeps its other parameters).
3. Local inspection: diagnostics across the write set.
4. **Conditional simplification, evidence-gated:** after step 2, `lsp
   references` `AutomationParameterMetadata.interpolation`
   (`AutomationParameter.swift:165`). If the only remaining read was the
   projection branch, delete the property and its `:195` assignment; if
   reads remain, it stays — report which. Same gate for the
   `AutomationProjection.swift:301` branch: if the ramp arm is now the only
   consumer of anything it references, and that thing has no other
   references, delete that arm; otherwise leave the branch.
5. `tst_EditorDrawer.qml`: delete only the helper function
   `automationRampItems()` (`:3187-3190`).

Edge cases: do not touch `AutomationTabs.qml`, `nodes`/`selectionRects`/
`curveRuns` publications, or the step-curve rendering — only the ramp path.
If the QML `Repeater` block sits inside a commented region describing "runs
… and the ramp segments", delete that stale sentence with the block
(comment goes because the code it describes goes).

## Acceptance predicate

NAMED CHECKS (controller): `deno task build:checks` green; `deno task
verify:bridge` no longer reports `AutomationHandles.swift:83`
(`UNANNOTATED_MEMBER` baseline entry disappears with the class); `deno task
verify:qml --verbose` green — the automation suite (incl. the sweep
predicates the ledgers cite) stays green, proving only unreachable code
was removed; `deno task proof check` shows no anchor resolving into the
deleted ranges.

## Task-specific constraints

- Touches `src/checks/editorqml/tst_EditorDrawer.qml` (check QML, not a
  ledger). Ledger areas serving this surface (`src/checks/automation/**`,
  `drawerpresentation/**`) are read-only here: sweep tests stay green and no
  row changes — the deleted helper had zero callers, so no executed
  predicate disappears. If a ledger `Anchor:` line resolves into a deleted
  range (not expected — none was found), repair it in this same commit per
  the workflow's allowed case and say so in the result.
- Nine files exceeds the 3-file default: single behavior (unreachable ramp
  path removal), one verification surface — named exception.
