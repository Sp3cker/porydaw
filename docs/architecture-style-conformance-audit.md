# Lifecycle & State-Ownership Conformance Audit

> Scope note (2026-09): this audit covers the retained native C++ seam. Porydaw is now a Swift 6 + QML application: Swift owns behavior and exposes it to QML through QtBridge, with no QWidgets and no new C++ outside the native boundaries. The application entry point is the Swift shell (`src/swift/app/shell/PorydawShellApp.swift` → `src/ui/shell/*.qml`). Findings below still govern the named native owners until they migrate to Swift.

This document is the bounded conformance audit of mutable-state ownership
and lifecycle across the `ProjectWorkspace → WorkspaceUi/SongTab →
MainWindow` seam in Porydaw. It is adjudicated: every accepted finding
below survived independent correctness and architecture review, and
disputed claims were resolved by dedicated re-investigation. Raw scout
claims that were rejected or narrowed are recorded as such.

The governing standards are [../STYLE_GUIDE.md](../STYLE_GUIDE.md); the
observed architectural conventions they codify are analyzed in
[architecture-style-observations.md](architecture-style-observations.md).

This is a read-only audit. No production code was changed, and nothing
here implies a change has been made.

## 1. Scope and exclusions

**In scope:** ownership of mutable facts, lifecycle/transition ordering,
publication atomicity, stale-work defense, and teardown discipline across:

- `src/project/projectworkspace.{h,cpp}` — public project seam and
  startup recipe restoration.
- `src/project/projectio.{h,cpp}` — worker-thread transport, serial
  FIFO, catalog cancellation, teardown.
- `src/ui/workspaceui.{h,cpp}`, `workspaceui_tabs.cpp`,
  `workspaceui_project.cpp`, `workspaceui_voicegroup.cpp`,
  `workspaceui_samples.cpp` — tab ownership, selection, gates, pending
  mutation fields, shared-bank coordination.
- `src/ui/songtab.{h,cpp}`, `songtabquickhost.{h,cpp}`,
  `voicegroupviewcache.{h,cpp}` — per-tab document/view/timeline
  lifecycle, leases, readiness, bank transition cache.
- `src/mainwindow.{h,cpp}` — composition root, audio handoff, teardown
  order.
- `src/audio/audioengine.{h,cpp}` — read-only, to verify borrow
  lifetimes at the handoff boundary.

**Out of scope:** audio DSP correctness, MIDI/SMF semantics, rendering,
and any file not reachable through the lifecycle paths above. No
performance, style-formatting, or test-coverage assessment was performed.

## 2. Methodology

Five scoped read-only audits (project seam, SongTab lifecycle, workspace
tabs/saves, shared-bank lifecycle, composition root) produced candidate
findings. Two independent adjudicators (correctness and architecture)
then accepted, narrowed, or rejected each candidate against the source.
Two residual disputes — the `ProjectIo` worker `deleteLater` claim and
the queued-catalog priority claim — were resolved by a dedicated
re-investigation with Qt lifecycle evidence; both were rejected. The
`m_dialogOps` surplus-consumption dispute was resolved in favor of the
correctness adjudicator (the arithmetic-guard rejection was itself a
false positive). Only adjudicated results appear below.

## 3. Ownership map

| Mutable fact | Unique owner | Source of truth | Key consumers |
|---|---|---|---|
| Open tab pages | `WorkspaceUi` | `m_tabPages` (`vector<unique_ptr<SongTab>>`) | `QTabWidget m_tabs`, persistence, `MainWindow` |
| Selected tab | `WorkspaceUi` | `m_tabs->currentWidget()` / `m_selectedTab` | `MainWindow` (audio handoff), transport, menus |
| Document state per tab | `SongTab` | `m_document` (`SongDocument`: SMF + cfg + undo) | `SongView` (borrow), save snapshots |
| Canonical bank state | Worker (`ProjectIo`/`DecompProject`) | on-disk + in-memory bank | published `LoadedBankView` by value |
| UI bank view cache | `VoicegroupViewCache` (in `WorkspaceUi`) | staged `LoadedBankView` + `PendingBankTransition` | `SongTab` leases, picker presentation |
| Project state | `ProjectWorkspace` | published `ProjectState` value | `WorkspaceUi::applyProjectState` |
| Command queue | `ProjectIo` | `m_queue` FIFO gated by `m_active` | worker thread |
| Dialog/mutation gates | `WorkspaceUi` | `m_dialogOps`, `m_inFlight*`, pending fields | action enablement, reconciliation |
| Audio session | `MainWindow`/`AudioEngine` | borrowed timeline `shared_ptr`, `VoicegroupLease` pin | playback |

## 4. Lifecycle / transition map

- **Startup:** `ProjectWorkspace` restores the QSettings recipe, submits
  startup song opens ahead of catalog scans, and publishes `ProjectState`
  values. `WorkspaceUi` hydrates placeholder tabs while
  `m_awaitingStartupOpen` is set; placeholders become ready on matching
  `SongUpdate`s.
- **Open/switch:** `beginProjectSwitch` → `destroyAllTabs` (nulls and
  publishes selection *before* destruction) → cache/tombstone clear →
  placeholders for the new snapshot.
- **Close:** `requestCloseTab` → dirty check → optional save →
  `removeTab` → `publishSelectedIfChanged` → `MainWindow` rebinds or
  unloads `AudioEngine`.
- **Mutation:** dialog op increments `m_dialogOps` → `ProjectOperation`
  → worker executes serially → staged `ProjectEvent`/`SongUpdate` +
  terminal snapshot → `reconcileSnapshot` consumes pending fields and
  decrements the gate.
- **Bank transition:** edit input → worker applies → staged
  `LoadedBankView` + typed receipt (`Applied`/`Conflict`/`Failed`) →
  `VoicegroupViewCache` resolves the single pending transition →
  borrow-safe lease swap into each `SongTab`.
- **Teardown:** `~MainWindow` runs an explicit shutdown/reset sequence;
  `~ProjectIo` quits and joins the worker thread.

## 5. Accepted findings and known limitations

Severity is conservative: **High** = user-observable data loss or
use-after-free-ordering hazard; **Medium** = state corruption requiring
a specific trigger; **Low** = hygiene/debt. A known limitation retains
its consequence severity but is an accepted user responsibility, not a
remediation target.

### F1 — Close prompt ignores bank dirty state, losing voicegroup edits — High (known limitation)

`WorkspaceUi::requestCloseTab` early-exits to `closeTabNow` when
`!document().isDirty()` (`workspaceui_tabs.cpp:493–500`) without
consulting `bankDirty(*tab)`. `maybeSaveTab`, `selectedSongDirty`,
`hasPendingSaveWork`, and `submitSaveForTab` all correctly OR the two
dirty flags, and the dialog text already anticipates voicegroup edits —
so a tab whose only changes are bank edits (instrument, ADSR, pan)
closes with no prompt and the edits are silently lost.

*Trigger:* close a ready tab whose document is clean but whose bank
view is dirty.

*Operational contract:* users must save bank-only edits before closing
the tab. The close path now records this responsibility in a one-line
source comment.

### F2 — `removeTab` destroys the selected tab before publishing selection — High (correctness/ordering)

`removeTab` detaches the widget, destroys the `SongTab` via
`std::erase_if`, and only then calls `publishSelectedIfChanged`
(`workspaceui_tabs.cpp:59–68`). During `~SongTab` both
`WorkspaceUi::m_selectedTab` and `MainWindow::m_selectedTab` dangle, the
audio-unload publication lands after destruction, and the subsequent
pointer comparison reads a freed address. `destroyAllTabs` proves the
intended order by emitting `selectedSongTabChanged(nullptr)` first. No
synchronous dereference or audio corruption was found (the timeline
`shared_ptr` and voicegroup lease pin the borrows), so this is an
ordering fragility rather than a live crash — but it is a real
use-after-free-ordering violation of the teardown contract.

*Trigger:* close the currently selected tab.

*Smallest correction:* if `tab == m_selectedTab`, clear/retarget and
publish before erasing.

### F3 — Project switch during startup strands placeholder tabs — High (known limitation)

When a user-initiated switch wins the startup race
(`m_openRequested = true` while `m_awaitingStartupOpen` is still true),
`applyProjectState` takes the `m_awaitingStartupOpen` branch
(`workspaceui_project.cpp:111–120`) and skips the
`destroyAllTabs`/cache/tombstone teardown, stranding the first project's
unready placeholders inside the new project. Incoming `SongUpdate`s
never match them, so they stay unready and hold `openProjectEnabled`
false until manually closed. `openProjectEnabled` provably permits the
race: `Closed`/`Failed` returns `!m_openRequested` without consulting
`m_awaitingStartupOpen`, and `beginProjectSwitch` performs no eager
teardown.

*Trigger:* `requestProjectOpenAt`/`beginProjectSwitch` before the
startup `Ready` lands.

*Operational contract:* users must let startup restoration finish before
switching projects. The open gate now records this responsibility in a
one-line source comment.

### F4 — Chained catalog publications over-consume the dialog-operation gate — Medium (correctness)

Every non-open `ProjectState` republication unconditionally calls
`consumeDialogOperation` (`workspaceui_project.cpp:142–149`), but
`acceptSnapshot` chains an automatic `RefreshCatalogInput` after
`RefreshProjectInput`/`DeleteSongInput` (and `CreateSongInput`
additionally emits `SongCreated` plus snapshot plus catalog). One
counted `m_dialogOps++` therefore suffers two to three decrements; the
surplus eats the *next* operation's count and re-enables
project-open/dialog gates while background work still runs. The
arithmetic guard `if (m_dialogOps > 0)` prevents negative values but
does not prevent surplus consumption — the defect is protocol pairing,
not underflow.

*Trigger:* refresh, delete, or create flow overlapping another dialog
operation.

*Smallest correction:* pair increments with typed completion tokens
instead of decrementing per republication.

### F5 — Failed mutations leave sticky pending actions — Medium (correctness)

`m_pendingDeleteSong`, `m_pendingCreatedLabel`/`m_pendingCreatedNewVoicegroup`,
and `m_pendingVoicegroupArg` are written when executions submit and
consumed only in `reconcileSnapshot`
(`workspaceui_project.cpp:186–193`). The
`SongMutationFailed`/`CatalogMutationFailed`/`SampleMutationFailed`
handlers warn without clearing them, so the next unrelated `Ready`
executes stale actions: closing a tab whose deletion failed, opening an
unrelated created tab, or assigning a nonexistent voicegroup arg.
(Narrowed in adjudication: `m_pendingImportSlot` and
`m_pendingEditSampleSlot` reset eagerly and are excluded.)

*Trigger:* fail a delete/create/new-voicegroup flow, then any later
`Ready`.

*Smallest correction:* clear each pending field on its corresponding
typed mutation-failure path (e.g. `m_pendingDeleteSong` on the delete
failure receipt), not indiscriminately on any failure.

### F6 — Tab reorder lost because persistence uses insertion order — Medium (correctness/persistence)

`persistTabs` iterates `m_tabPages` (creation order)
(`workspaceui_tabs.cpp:164–180`) while tab drags reorder only the
`QTabWidget` display order; `tabMoved` re-persists the same wrong order
and never reorders `m_tabPages`. `tabsInDisplayOrder()` already queries
widget order correctly but is unused by persistence, so saved
`lastOpenSongs` disagrees with the visual order after any drag-reorder
and restarts restore insertion order.

*Trigger:* reorder tabs, restart.

*Smallest correction:* iterate `tabsInDisplayOrder()` in `persistTabs`.

### F7 — Dead `m_pendingOpenDir` member — Low (historical debt)

`QString m_pendingOpenDir` (`workspaceui.h:385`) has zero readers or
writers anywhere under `src`; open flows pass directories through lambda
captures. It occupies state and misleads readers about open-directory
lifecycle.

*Smallest correction:* delete the member.

## 6. Conforming patterns (verified)

- **Single ownership and atomic publication.** `ProjectWorkspace`
  publishes immutable `ProjectState`/`ProjectEvent`/`SongUpdate` values
  across the thread boundary; no shared mutable references cross it.
- **Serial FIFO with cooperative cancellation.** `ProjectIo` executes
  one semantic operation at a time (`m_queue` + `m_active`); catalog
  scans cancel cooperatively while in flight.
- **Staged `SongUpdate` routing and tombstones.** Per-tab updates are
  matched by key; tombstoned tabs cannot resurrect.
- **Shared-bank transition gating.** `VoicegroupViewCache` holds exactly
  one `PendingBankTransition`; staged view + typed receipt resolve it
  atomically; conflict handling invalidates history entries correctly.
- **Borrow-safe swaps.** `SongTab` lease/timeline swaps keep old
  resources alive until the new ones are installed; `AudioEngine`
  borrows are pinned by `shared_ptr` timeline and `VoicegroupLease`.
- **Explicit teardown ordering.** `destroyAllTabs` publishes
  `selectedSongTabChanged(nullptr)` before destruction; `~MainWindow`
  runs an explicit shutdown/reset sequence rather than relying on
  implicit member destruction.
- **Stale-save defense and input gating.** Save snapshots are taken by
  value; `InputGate` and the in-flight sets block re-entrant mutation.
- **Startup supersession.** Startup song submissions are sequenced ahead
  of catalog scans; a one-shot recipe cannot re-fire.

## 7. Rejected false positives

- **`ProjectIo` worker `deleteLater` leak — REJECTED.** The claim that
  `connect(m_thread, &QThread::finished, m_worker, &QObject::deleteLater)`
  can never fire after `quit()`+`wait()` is false:
  `QThreadPrivate::finish` synchronously flushes `QEvent::DeferredDelete`
  events for thread-affinity objects during thread termination, before
  `wait()` unblocks. The worker is deleted; explicit `delete m_worker`
  after `wait()` would double-free. The destructor comment is accurate.
- **Queued-catalog priority inversion — REJECTED.** `ProjectIo` is
  contractually a deterministic serial FIFO; cooperative preemption
  applies only to an *active* in-flight scan, not to queue reordering.
  A song command queued behind a not-yet-started `RefreshCatalogInput`
  waiting its turn is intended FIFO behavior, not a defect.
- **Dialog-counter arithmetic underflow — REJECTED as stated.** The
  guard at `workspaceui_project.cpp:402` prevents negative counts; the
  real defect is surplus consumption across chained publications
  (accepted as F4 on different reasoning).
- **Tombstone/stale-result loss and readiness/pendingReload leaks —
  REJECTED.** Terminal consumes at the tombstone path are correct, and
  `isReady` gating (`songtab.h`) is sound.

## 8. Not accepted as findings

The following raw candidates were examined in adjudication and are not
accepted as findings: none has an independently established violated
invariant beyond the accepted findings above.

- **`MainWindow::m_selectedTab` raw mirror** (`mainwindow.h:184`):
  duplicates `WorkspaceUi` selection, but has no independent violation
  beyond the F2 ordering window it shares; not separately accepted.
- **Member declaration order vs teardown contract**
  (`mainwindow.h:180–186`): the explicit `~MainWindow` shutdown/reset
  sequence makes the current order conforming; reliance on implicit
  destruction is hypothetical, so no violation is established.
- **Dual readiness channels** (`songtab.h:108–109`):
  `SongTab::readinessChanged` and `WorkspaceUi::songTabReady` serve
  distinct observed roles (InputGate/tests vs. terminal
  `VoicegroupBound` arrival); no misbehavior or violated invariant was
  observed.
- **Retained minted synth descriptors**
  (`workspaceui_voicegroup.cpp:301–310`): `m_pendingSynths` entries can
  survive revert/close-without-save, but `pendingSynthDefsFor` packages
  only symbols referenced by the active bank view, so retention is
  harmless and not independently established as a violation.

## 9. Bounded remediation order

Smallest corrections only, in priority order. F1 and F3 are documented
known limitations and therefore excluded. No implementation plan is in
scope.

1. **F2** — publish/clear selection before `erase_if` in `removeTab`.
2. **F5** — clear each sticky pending field on its corresponding typed
   mutation-failure path.
3. **F4** — pair `m_dialogOps` increments with typed completion tokens.
4. **F6** — persist via `tabsInDisplayOrder()`.
5. **F7** — delete `m_pendingOpenDir`.
