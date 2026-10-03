# Brief 05 — Delete handler-less signals and their forwarding plumbing

## Context

Finding B (audit §2), symbol table re-verified: six `@QtSignal`s have zero
observers anywhere (QML, Swift, checks) and one signal-handler pair
(`informationRequested`) is never emitted. Three of the six are fed by a
closure→`DocumentWorkspace.Callbacks`→session-signal forwarder that duplicates
the presenter's own live signal — the exact "second dispatcher" pattern the
repo forbids. Spec R6: one channel per observer domain; presenter closure
hooks stay (Swift observers, used by checks), dead session signals go.

## Exact write set

- `/src/swift/app/ApplicationSession.swift`
- `/src/swift/app/DocumentWorkspace.swift`
- `/src/swift/app/headers/TrackHeaders.swift`
- `/src/swift/app/shell/ShellPresenter.swift`
- `/src/ui/songview/quick/swiftroll/EditorSurface.qml`
- `/src/ui/shell/ShellWindow.qml`

No `src/checks/**` write. Ledger check: no `proof.*.txt` row references any
of these seven signals (verified sweep; the one hit —
`proof.trackheadermutations.txt` A096 — cites the **closure**
`onAddTrackRequested`, which stays). No ledger edits.

## Prerequisites

02 (guard B2 names the dead population), 04 (normalization landed; strips
already applied to these files where applicable).

## Interface contract — deletions (whole declarations)

| Symbol | Site | Notes |
|---|---|---|
| `aboutToReleaseGrid()` decl | `ApplicationSession.swift:499` | also remove its emission call at `:565`; the surrounding teardown steps and their order are preserved exactly, minus this dead call |
| `gridContextMenuRequested(x:y:)` decl | `ApplicationSession.swift:504` | delete; also delete `requestGridContextMenu(x:y:)` (`:500-502`) and the QML call `root.applicationSession.requestGridContextMenu(x, y)` at `EditorSurface.qml:118`; the working lines `:119-122` (`root.contextMenuAt(...)`) stay |
| `headerContextMenuRequested(x:y:)` decl | `ApplicationSession.swift:510` | delete + its `makeCallbacks` emission closure (`:964-965`) |
| `addTrackRequested()` decl | `ApplicationSession.swift:511` | delete + emission closure (`:957`) |
| `revealTrackVoiceRequested(track:)` decl | `ApplicationSession.swift:513` | delete + emission closure (`:961-963`) |
| `rollFocusRequested()` decl | `TrackHeaders.swift:386` | delete + the `rollFocusRequested()` call at `:305`; `onRestoreRollFocus?()` on the same line stays (its hook at `:67` is currently never set — kept as the Swift-observer shape, flagged for reviewer) |
| `informationRequested(title:message:)` decl | `ShellPresenter.swift:406` | delete; never emitted |
| `function onInformationRequested(title, message)` | `ShellWindow.qml:222` | delete the handler (inside its `Connections` block; keep the block and siblings) |

STAY (do not touch): `TrackHeadersPresenter.onAddTrackRequested`
(`TrackHeaders.swift:62`, invoked `:281`), `.onContextMenuRequested` (`:66`,
invoked `:421-422`), `.onRevealTrackVoiceRequested` (`:64`, invoked `:352`
and `TrackHeadersInput.swift:145`), `TrackHeadersPresenter.contextMenuRequested`
signal (`:385` — live, handled at `EditorSurface.qml:128`), and
`changeTrackVoiceRequested` (`ApplicationSession.swift:512` — handled in
`src/checks/rollqml/tst_SwiftRollWindowing.qml:52`).

## Implementation steps

1. `lsp references` each deleted symbol; the table above must be the
   complete reference set — any hit outside it: stop and report
   (`NEEDS_CONTEXT`), do not improvise.
2. Delete declarations, emission calls/closures, Callbacks fields/wiring,
   and the two QML fragments; repair the `makeCallbacks` argument list.
3. Local inspection: diagnostics on all six files; confirm no dangling
   references.

Edge cases: `EditorSurface.qml`'s `onContextMenuRequested` handler at
`:128` belongs to the **presenter** signal and must survive; only the
`:118` statement goes. `ShellWindow.qml`'s `Connections` block may become
empty if `onInformationRequested` was its only function — then delete the
whole block; if it has siblings, keep it.

## Acceptance predicate

NAMED CHECKS (controller): `deno task build:checks` green; `deno task
verify:bridge` reports none of the seven as `SIGNAL_NEVER_OBSERVED` /
`HANDLER_NEVER_EMITTED`; `deno task verify:shell --verbose` green
(ShellWindow/ShellPresenter surface); `deno task verify:qml-roll --verbose`
green (EditorSurface/TrackHeaders surface); `deno task verify:qml
--verbose` green.

## Task-specific constraints

- Six files exceeds the 3-file default; single behavior ("no handler-less
  signals"), one verification surface — named exception, do not split.
- No renaming, no new signal, no comment edits beyond deleted lines.
