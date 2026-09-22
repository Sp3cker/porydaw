# Task 1 — DocumentWorkspace activate/deactivate + per-workspace drawer presenter

## Context

Prepares the multi-tab lifecycle: today `DocumentWorkspace.init` binds audio
eagerly and `teardown()` is the only way down. Tabs need a non-destructive
`deactivate()` so hidden workspaces keep state while releasing the shared
audio engine, playhead and drawer attachment. The drawer presenter moves from
`ApplicationSession` into the workspace (per-tab drawer state, C++ parity).
Consumer: Task 2's `SongTabsController` calls `activate()`/`deactivate()` on
selection changes.

## Exact write set

- `src/swift/app/DocumentWorkspace.swift`
- `src/swift/app/ApplicationSession.swift`

## Prerequisites

None.

## Interface contract

- `DocumentWorkspace.init(session:audio:drawer:playhead:callbacks:)` loses the
  `drawer` parameter; the workspace constructs and owns its own
  `EditorDrawerPresenter`. Audio is NOT bound in init.
- `public let drawer: EditorDrawerPresenter` on `DocumentWorkspace`.
- `activate()`: binds audio via `audio.bind(timeline:bank:config:)` using the
  session's stored timeline/bank/config (add whatever stored access
  `DocumentSession` already exposes; do not invent new session API beyond
  reading existing fields), then the existing attach sequence (playhead
  callbacks, `drawer.attachSection` ×3, `playhead.attach`, `startPolling`).
- `deactivate()`: public, idempotent, only when active. Cancels input
  (`cancel(reason: GridCancelReason.hidden.rawValue)` semantics), detaches
  playhead, `drawer.detachSection` ×3, `audio.stop()` + `audio.unload()`,
  clears `session.onPlayback`. Leaves `session.onChange` live.
- `teardown()`: calls `deactivate()` first, then the existing presenter
  `detach()` sequence. `isTornDown` semantics unchanged.
- `ApplicationSession`: `private let drawer` removed; `drawerPresenter()`
  returns `workspace?.drawer ?? emptyDrawerPresenter` where
  `emptyDrawerPresenter` is a retained never-attached instance. The
  `DocumentWorkspace.Callbacks` init call drops the drawer argument.

## Implementation steps

1. Move `EditorDrawerPresenter` ownership into `DocumentWorkspace`; update
   `init` signature and `ApplicationSession`'s construction call.
2. Move `audio.bind` from `init` into `activate()`; store nothing new — read
   timeline/bank/config from `session` at activate time.
3. Extract the inverse of activation into `deactivate()`; make `teardown()`
   call it.
4. Update `ApplicationSession.drawerPresenter()` forwarding and the
   `retireCurrentDocument` path (it already calls `teardown()`).
5. Verify no other file references `ApplicationSession.drawer` directly —
   `lsp references` on the property before editing.

## Acceptance predicate

Behavior-preserving: single-song open/edit/close unchanged; drawer sections
attach/detach identically; audio binds on activation exactly once.

NAMED CHECKS (controller runs): `deno task build:checks` &&
`deno task verify --filter swiftrollgated --filter swiftcore --filter editorqml --verbose`.
Covers: mounted grid render, document feed, drawer page binding.

## Task-specific constraints

- No new public API beyond `deactivate()` and the moved `drawer` property.
- `activate()` must remain idempotent (`guard !isActive`).
- Do not change `DocumentSession`'s public surface; read existing stored
  timeline/bank/config — if they are not exposed, add the minimal internal
  accessor and name it in the report.
