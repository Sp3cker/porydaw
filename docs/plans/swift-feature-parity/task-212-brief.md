# Task 212 brief — rename commit/cancel restores roll focus through a real signal

# Context

`TrackHeadersPresenter.onRestoreRollFocus` (`src/swift/app/headers/
TrackHeaders.swift:67`, fired at `:311` from `finishRename(commit:
restoreRollFocus:)`) is declared but assigned by nobody in production —
only `src/checks/trackheaders/trackheadermutations.swift:79` observes it.
The mounted `swiftroll/TrackHeaderBand.qml` editor already passes the flag:
`Keys.onReturnPressed`/`onEnterPressed` call `finishRename(true, true)` and
`Keys.onEscapePressed` calls `finishRename(false, true)`
(`TrackHeaderBand.qml:321-331`), so after committing or cancelling a track
rename the focus simply drops — where the fork's
`TrackHeaderModel::finishRename` calls `m_owner.focusContent()`
(`trackheadermodel.cpp:514-530` at `fceecd88`), and `SongView::focusContent`
(`songview.cpp:833-843`) focuses the event-list input when the event list
owns the band's screen space, else the roll band's input.

Focus restore can't be wired through `DocumentWorkspace` — the target is a
QML input item, not a Swift presenter — so the correct port is the same
pattern `contextMenuRequested` already uses in this class (`:398`, consumed
by `EditorSurface.qml:149-154`): a `@QtSignal` the mounted surface observes.

Surface: the track-header rename editor's Enter/Escape path on the mounted
roll surface — rename ends and the roll input (or the event-list input when
events are shown) holds focus again.
Ledger spec: none — the trackheaders ledgers are already deleted; no open
row pins the focus-restore conjunct. Feature port with zero ledger edits.
Verify lanes: `deno task verify --filter swiftcore-projectsession
--verbose` (signal/callback emission predicates in
`trackheadermutations.swift`, which runs under `runTrackHeadersChecks`) and
`deno task verify:qml-roll` (`swiftroll-window` entry,
`tst_SwiftRollTrackHeaderInput.qml` mounted journeys).

# Exact write set

Production:

- `src/swift/app/headers/TrackHeaders.swift` — add
  `@QtSignal public func restoreRollFocusRequested()` beside
  `contextMenuRequested` (`:398`), and emit it in `finishRename`'s
  `restoreRollFocus` branch next to the existing `onRestoreRollFocus?()`
  call (both fire: the callback stays for the harness boundary the fork
  keeps separate — `mainwindow.cpp:943-951` precedent).
- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — inside the existing
  `Connections { target: root.headersModel }` block (`:149-154`), add
  `onRestoreRollFocusRequested` implementing `focusContent` verbatim:
  if `root.showEvents && eventPage.item`, `eventPage.item.forceActiveFocus(Qt.OtherFocusReason)`;
  else `rollInput.forceActiveFocus(Qt.OtherFocusReason)`.

Checks:

- `src/checks/trackheaders/trackheadermutations.swift` — extend the
  existing `finishRename(commit: true, restoreRollFocus: true)` leg
  (`:82`) with a signal-spy/style observation that
  `restoreRollFocusRequested` emitted alongside the callback (through the
  bridged object's signal, e.g. a QML Connections probe or the check's
  existing Qt-signal observation idiom — reuse whatever the check file
  already does for `contextMenuRequested`), plus the negative legs:
  `finishRename(commit: false, restoreRollFocus: false)` and commit-only
  `restoreRollFocus: false` emit neither.
- `src/checks/rollqml/tst_SwiftRollTrackHeaderInput.qml` — extend the
  mounted journeys (assertions appended inside existing tests, not new
  copies):
  - `test_zMountedRenameAndReorderCommit`: after `keyClick(Qt.Key_Return)`
    commits, assert `item("swiftRollInput").activeFocus` becomes true.
  - `test_yRenameEscapeAndTransientCancellation`: after
    `keyClick(Qt.Key_Escape)` discards, assert `swiftRollInput` regains
    focus (the Escape leg passes `entered=true` → restore fires even on
    cancel — verify the fork passes the same flag; the mounted QML does,
    and `focusContent` applies identically).

Ledgers: none.

# Prerequisites

None in-wave. Disjoint from 210/211 (no shared file; this task alone owns
`TrackHeaders.swift` and `EditorSurface.qml` in the wave). Read sprint-3 §28.

# Interface contract (fork clauses)

- Trigger (`trackheadermodel.cpp:514-530`): `finishRename` fires the
  restore iff the caller passed `restoreRollFocus` (the mounted editor's
  Enter/Enter-pad/Escape keys do; focus-loss cancellation at
  `TrackHeaderBand.qml:308-311` passes `false` and must not steal focus
  back from whatever the user just focused).
- Target (`songview.cpp:833-843`): the event-list input when the event
  page owns the band's space, else the roll band input — never the header
  input (that restore is `restoreHeaderFocus`, a different seam used after
  the voice picker closes).
- Ordering: the signal fires after `renamingTrack`/draft state clears and
  the commit lands (`session.document.renameTrack` runs before the
  restore branch), matching the fork's sequence — focus lands on a clean
  surface state, never mid-edit.
- No recursive focus fight: the restore is synchronous on emission; the
  QML handler must not use `Qt.callLater` (the banned mid-flight pattern);
  `forceActiveFocus(Qt.OtherFocusReason)` on the visible item only.

# Implementation steps

1. `TrackHeaders.swift`: declare and emit `restoreRollFocusRequested`.
2. `EditorSurface.qml`: the `focusContent` handler in the headers
   Connections block.
3. `trackheadermutations.swift`: signal + callback emission predicates and
   the two negative legs.
4. `tst_SwiftRollTrackHeaderInput.qml`: activeFocus assertions on
   `swiftRollInput` in the commit and Escape legs.
5. Run both lanes; no ledger edits (zero open rows claimed).

# Acceptance predicate

Committing a mounted track rename with Return, or cancelling it with
Escape, returns focus to `swiftRollInput` (the event-list input when
`showEvents` is on); a focus-loss cancel restores nothing — the fork's
`finishRename`/`focusContent` contract on the mounted surface.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --verbose
deno task proof check --executed
```

# Task-specific constraints

Real production signal and mounted QML target only — the restore never
goes through a test hook, a hard-coded window search, or `Qt.callLater`.
`onRestoreRollFocus` stays: the check-file harness boundary mirrors the
fork's harness-only persistence-seam convention, and existing predicates
at `trackheadermutations.swift:79,129-130` keep meaning. One predicate per
fork clause; focus assertions observe `activeFocus` on the real mounted
item, never a flag. Swift 6.4, comments ≤2 lines, no hard-coded px.
Workarounds or architectural changes: stop and report.
