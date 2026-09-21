# Velocity/voice split — plan

Fowler extraction of the two god files into the migration seam from `spec.md`:
pure Scene/Projection first (scoped-reuse builds), operation Interaction
second as page extensions per the `AutomationInteraction.swift` precedent,
hygiene gate last. C++ areas + `velocityquick.cpp` / `voicechangequick.cpp`
stay live; no timeline behavior changes.

## Global Constraints

- Read `spec.md` (vocabulary, forward interfaces, import rule) and the Swift
  backend charter (`docs/plans/swift-backend-charter.md`) plus QtBridge
  integration contract (`docs/plans/qtbridge-integration-contract.md`); briefs
  carry deltas only.
- Behavior-preserving refactor only. No snap/detent/picker/menu/commit/undo,
  occurrence-identity, or QML publish-name changes. QML stays render-only.
- Interaction files are `extension VelocityPage` / `extension VoiceChangesPage`
  (no wiring object, no forwards). Check-facing `@QtIgnored` accessors and all
  publish-apply plumbing (`publish*`, `sync*`, `matches*`, `setPublished*`)
  never move files.
- New Swift files are registered in `src/swift/app/CMakeLists.txt` beside the
  existing `drawer/velocity/...` / `drawer/voicechanges/...` entries.
- Cohesion: resulting files target 200–400L; none above 600L without an
  accepted-exception note in review. No `Part1/Part2` fragments; move complete
  responsibilities.
- Workarounds require approval per AGENTS.md: stop, name root cause, recommend
  root-cause fix, wait. No guards/fallbacks accommodating broken invariants.
- Implementers run the Verification policy below as written; reassess only if
  scope changes or a command proves stale or unavailable, reporting the
  mismatch and revised verification.

## Verification policy

Run when the desktop is idle; human-input harnesses flake under desktop use —
do not stress-repeat. A pass under load is not failure evidence; re-run once
idle before reporting.

- `deno task build:checks` — builds app + checks + mid2agb.
- `deno task verify --filter swiftcore --verbose` — covers
  `VelocityPageChecks.swift` (axis ladder, PSG rows, context, projection,
  frozen gesture, transactions, prompt, cancellation, diagnostics) and
  `VoiceChangesPageChecks.swift` (projection, labels, context, identity,
  picker/drag/menu, cancellation, history, diagnostics). Proves preservation
  (legacy `src/checks/velocity/`, `src/checks/drawerpresentation/` sources are
  unregistered since the T7A cutover — confirmed absent from
  `src/checks/CMakeLists.txt` and the `porydaw_checks --manifest` name list —
  so no legacy lane command exists; swiftcore is the preservation proof).
- `deno task verify:qml --filter editorqml-drawer --verbose` — covers the
  production QML seam (`velocity-lane`, `voice-picker`, `editor-drawer` panes;
  the entry lives in the `editor_qml_tests` lane, not `porydaw_checks`).
- `deno task format --check` — formatting gate.

## Tasks

| # | Task | Route + justification | Files |
|---|---|---|---|
| 1 | Extract velocity scene + projection (pure build) | SDD-track — snapshot/input boundary + numeric parity need judgment; seat `sdd-implementer` | `VelocityPage.swift`, `VelocityScene.swift` (new), `VelocityProjection.swift` (new), `src/swift/app/CMakeLists.txt` |
| 2 | Extract velocity interaction as page extension | SDD-track — frozen-gesture/preview/commit semantics preserved verbatim across file move; seat `sdd-implementer` | `VelocityPage.swift`, `VelocityInteraction.swift` (new), `src/swift/app/CMakeLists.txt` |
| 3 | Extract voice scene (pure build) | SDD-track — marker/span/label build boundary + slot-blank rules need judgment; seat `sdd-implementer` | `VoiceChangesPage.swift`, `VoiceChangesScene.swift` (new), `src/swift/app/CMakeLists.txt` |
| 4 | Extract voice interaction as page extension | SDD-track — occurrence-identity + camera-scroll staleness are subtle; seat `sdd-implementer` | `VoiceChangesPage.swift`, `VoiceChangesInteraction.swift` (new), `src/swift/app/CMakeLists.txt` |
| 5 | Import-hygiene + format gate | Direct — single grep predicate + formatter, fully reversible. Target: `VelocityInteraction.swift` and `VoiceChangesInteraction.swift` contain no `import QtBridge`; Scene/Projection obey spec.md. Change: no source moves; fix violations by moving the offending import's code home, never by widening the rule. Acceptance: `grep -h "^import" src/swift/app/drawer/velocity/VelocityInteraction.swift src/swift/app/drawer/voicechanges/VoiceChangesInteraction.swift` shows no QtBridge, plus the Verification policy four-command pass. | (no brief; dispatch quotes this cell) |

Briefs: `task-1-brief.md` … `task-4-brief.md` (each cites the Verification
policy above and names only its task-specific check focus).

## Checkpoints

- Milestone A (velocity done): after task 2 — swiftcore velocity + editorqml
  `velocity-lane`/`velocity-prompt` panes green.
- Milestone B (voice done): after task 4 — swiftcore voice + editorqml
  `voice-picker` pane green.
- Final handoff: after task 5 — four-command pass + `git status` shows only
  the listed write sets.
