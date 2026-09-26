# Context

Shell chrome parity (inventory SH05; user direction 2026-09-25 that surfaces
must look like the fork-main QWidget app authorizes restoring this shipped
chrome). The side-by-side capture shows two missing pieces:

1. **Window title.** Swift `ShellWindow.qml:23` is the static `qsTr("Porydaw")`.
   fork-main `MainWindow::updateWindowTitle`
   (`git show fceecd88:src/mainwindow.cpp` lines 994-1008): with a selected
   tab, `"<song>[*] — <projectDirName> — porydaw"` plus `setWindowModified`
   when the tab is ready and its document dirty (macOS renders the modified
   state in the title bar; `[*]` is Qt's placeholder, not literal text); with no
   tab, `"<projectDirName> — porydaw"`, or `"porydaw"` with no project.
   Separators are U+2014 em dashes. Reference title:
   `mus_route101 — decompproject — porydaw`.
2. **Polyphony meter in the status bar.** fork-main (`mainwindow.cpp`
   lines 674-716 construction, 1093-1117 `updatePolyStatus`): a permanent
   right-side status widget in the application (body) font, laid out
   `PCM` caption, value field `a/m` (active PCM / max PCM), `·`, `CGB` caption,
   value field `c/4`, then — only when the lost total is > 0 — `·`, a value
   field with the lost total and the caption `notes lost`. Value fields are
   right-aligned with a half-space inset and use theme roles
   `polyphony_value_text` on `polyphony_value_background`. The whole meter is
   hidden when audio is not loaded for a selected tab (and its fields
   cleared). Reference: `/tmp/porydaw-qwidget-ref/a-main-window.png`
   bottom-right `PCM 0/12 · CGB 0/4`.

All data already exists in Swift: `NativeAudio.activePcmChannels`,
`maxPcmChannels`, `activeCgbChannels`, `polyLostTotal`, `songLoaded`
(src/swift/app/NativeAudio.swift:45-58); `TransportBarPresenter.refresh()`
(src/swift/app/transport/TransportBarPresenter.swift:41-94) already runs on the
transport clock with the loaded audio and selected document in hand. The
footer is `ShellWindow.qml:652-665` (one `statusText` Text).

Out of scope: clicking the meter to open the Polyphony Debugger (not wired in
fork-main's meter either — verify with `git show fceecd88:src/mainwindow.cpp |
grep -n polyMeter`; if it was wired, report and stop that sub-part).

# Exact write set

- `src/swift/app/transport/TransportBarPresenter.swift` — publish meter state
  (`polyMeterVisible`, `pcmText`, `cgbText`, `lostText`/`lostVisible`) from
  `refresh()`, hidden/cleared on the not-loaded branch.
- `src/swift/app/shell/ShellPresenter.swift` — publish `windowTitle` and
  `windowModified` derived from the session's selected tab title, document
  dirty/ready state, and project directory name; update on the existing
  song/tab/save/project change notifications (reuse `songOpenChanged`,
  `saveStateChanged` and whatever already republishes on tab selection and
  project switch — find them; do not add polling).
- `src/ui/shell/ShellWindow.qml` — bind `title` to the presenter (macOS
  modified indicator: Qt Quick `Window` has no `windowModified`; render the
  title exactly as the QWidget app displayed it on macOS, which is the title
  without `[*]` plus the platform dirty dot. If no Qt Quick route exists for
  the native dirty dot, report it with the Qt docs reference instead of
  inventing a text marker), and add the meter as the footer's right-aligned
  item using font-metric spacing (half-space = the existing layout policy's
  half-space derived from the base font; no pixel constants) and GridPalette
  roles; add `polyphonyValueText`/`polyphonyValueBackground` to `GridPalette`
  and `ShellAppearance.apply` only if they do not exist, mapped from the
  fork-main preset values (`git show fceecd88:src/ui/theme/presetcolors.h`,
  `polyphony_value_*`), meeting WCAG AA.
- `src/checks/editorqml/tst_ShellTransport.qml` (meter) and
  `src/checks/editorqml/tst_ShellWindow.qml` (title) — mounted predicates.
- Swift unit predicates in the existing transport/shell presenter check file
  that already constructs `TransportBarPresenter` / `ShellPresenter` (find
  with `grep -rln "TransportBarPresenter(" src/checks`).

# Prerequisites

HEAD at or after `c47e83d2`; tasks 22/23 own event-list and voice-label files
(disjoint). If `GridPalette.swift`/`ShellAppearance.swift` need edits while
task 22 is uncommitted, coordinate: task 22 does not edit those files.

# Interface contract

- Meter strings: `"\(active)/\(max)"`, `"\(cgb)/4"`, lost total decimal; exact
  captions `PCM`, `CGB`, `notes lost`; separators `·` (U+00B7).
- Title strings as in Context; project name = last path component of the open
  project root.
- Checks: meter hidden with no song; after opening `mus_route101` with the null
  backend, meter visible reading `0/<maxPcm>` and `0/4`, lost row hidden;
  title `mus_route101 — decompproject — porydaw`; after an edit, modified
  state true; after save, false; with no tab, `decompproject — porydaw`.
  Contract-shaped messages, no pixel constants, no sleeps (`waitForNative`).

# Implementation steps

1. Failing checks first; record RED.
2. Presenter state, then QML bindings.
3. Lanes; report GREEN with predicate strings and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:shell --filter shell-transport --verbose`
- `deno task verify:shell --filter shellwindow --verbose`
- `deno task verify:shell --verbose` (split per `--filter` if > 180 s)
- `deno task verify:bridge`
- Controller visual acceptance per skill `porydaw-qwidget-reference-capture`:
  title bar and bottom-right meter match the reference.

# Visual parity

Counterpart: fork-main `fceecd88` `src/mainwindow.cpp` (title and meter),
`src/ui/theme/presetcolors.h` (polyphony value roles); reference capture
`/tmp/porydaw-qwidget-ref/a-main-window.png`.

# Task-specific constraints

- No new C++, no code comments, no pixel constants, no ledger edits, no
  polling timers beyond the existing transport refresh cadence.
- Plan row SH05 moves from blocked to in-progress by user direction (visual
  parity with shipped chrome); the controller records that in plan.md.
