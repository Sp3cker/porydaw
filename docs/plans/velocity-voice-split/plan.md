# Velocity/voice split — plan

Fowler extraction of the two god files into the migration seam from `spec.md`:
pure Scene/Projection first (timeline-reusable), operation Interaction second,
mechanical cutover last. C++ areas + `velocityquick.cpp` / `voicechangequick.cpp`
stay live; no timeline behavior changes.

## Global Constraints

- Read `spec.md` (vocabulary, forward interfaces, import rule) and the Swift
  backend charter (`docs/plans/swift-backend-charter.md`) plus QtBridge
  integration contract (`docs/plans/qtbridge-integration-contract.md`); briefs
  carry deltas only.
- Behavior-preserving refactor only. No snap/detent/picker/menu/commit/undo,
  occurrence-identity, or QML publish-name changes unless a brief names them.
  QML stays render-only; no logic moves into QML.
- New Swift files are registered in `src/swift/app/CMakeLists.txt` beside the
  existing `drawer/velocity/...` / `drawer/voicechanges/...` entries.
- Cohesion: resulting files target 200–400L; none above 600L without an
  accepted-exception note in review. No `Part1/Part2` fragments; move complete
  responsibilities.
- Import rule (spec.md) holds for every task: only Owner + Transactions import
  `QtBridge`.
- Workarounds require approval per AGENTS.md: stop, name root cause, recommend
  root-cause fix, wait. No guards/fallbacks accommodating broken invariants.
- Implementers reuse the recorded verification commands without repeating
  discovery; reassess only if scope changes or a command proves stale or
  unavailable, reporting the mismatch and revised verification.

## Verification policy

Implementer-runnable after every task (run when desktop is idle; human-input
harnesses flake under desktop use — do not stress-repeat):

- `deno task build:checks` — builds app + checks + mid2agb.
- `deno task verify --filter swiftcore --verbose` — covers
  `VelocityPageChecks.swift` (axis ladder, PSG rows, context, projection,
  frozen gesture, transactions, prompt, cancellation, diagnostics) and
  `VoiceChangesPageChecks.swift` (projection, labels, context, identity,
  picker/drag/menu, cancellation, history, diagnostics).
- `deno task verify --filter editorqml-drawer --verbose` — covers the
  production QML seam (`velocity-lane`, `voice-picker`, `editor-drawer` panes).
- `deno task verify --filter velocity --verbose` — legacy C++ velocity checks
  stay green (behavior preservation proof).
- `deno task verify --filter drawerpresentation --verbose` — legacy drawer
  presentation (incl. voice/menus) stays green.
- `deno task format --check` — formatting gate.

Coverage gap: reference-image panes need a settled desktop; a pass under load
is not evidence of failure — re-run once idle before reporting.

## Tasks

| # | Task | Route + justification | Files |
|---|---|---|---|
| 1 | Extract velocity scene + projection (pure) | SDD-track — judgment on snapshot boundary + numeric parity; seat `sdd-implementer` | `VelocityPage.swift`, `VelocityScene.swift` (new), `VelocityProjection.swift` (new), `src/swift/app/CMakeLists.txt` |
| 2 | Extract velocity interaction + prompt dispatch | SDD-track — frozen-gesture/preview/commit semantics must be preserved verbatim; seat `sdd-implementer` | `VelocityPage.swift`, `VelocityInteraction.swift` (new) |
| 3 | Extract voice scene (pure) | SDD-track — marker/span/label build boundary + slot-blank rules; seat `sdd-implementer` | `VoiceChangesPage.swift`, `VoiceChangesScene.swift` (new) |
| 4 | Extract voice interaction (pointer/picker/menu/hover) | SDD-track — occurrence-identity + camera-scroll staleness are subtle; seat `sdd-implementer` | `VoiceChangesPage.swift`, `VoiceChangesInteraction.swift` (new) |
| 5 | Import-hygiene + cutover + format | Direct — mechanical delegate/include edits, single grep + check predicate. Target: Page forwards to Scene/Projection/Interaction with unchanged publish names; only Owner + Transactions import `QtBridge` (`grep -h "^import" drawer/velocity/*.swift drawer/voicechanges/*.swift` shows no other `QtBridge`); `deno task format` applied to touched files. Change: register new files in `CMakeLists.txt`, delete moved declarations from owners, keep re-export-free forwarding. Acceptance: the six verification commands above all pass. | (no brief; dispatch quotes this cell) |

Briefs: `task-1-brief.md` … `task-4-brief.md`.

## Checkpoints

- Milestone A (velocity done): after task 2 — velocity lane + prompt green in
  swiftcore + editorqml-drawer, legacy velocity green.
- Milestone B (voice done): after task 4 — voice markers/picker/menu green in
  swiftcore + editorqml-drawer, drawerpresentation green.
- Final handoff: after task 5 — full six-command pass + `git status` shows only
  the listed write sets.
