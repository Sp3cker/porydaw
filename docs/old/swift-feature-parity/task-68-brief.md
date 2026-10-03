# Context

Task 68 — mouse-hints surface: claims from real hover targets, scope behavior,
and status presentation. The ownership/text model already executes
(`MouseHints.swift` + `mouseHintOwnershipChecks` S002–S009 in
`src/checks/workspace/session_editor_semantics.swift`); what is missing is the
user-visible surface the fork proved in four `mouseHint*` clauses: targets
claim profiles through live delivery, menus/popups scope and restore hints,
and the status bar presents the text without shifting layout. Fork oracle is
`fceecd88` (`git show fceecd88:<path>`).

1. **Census (verified this freeze)**:
   - `proof.tst_mainwindowrouting_state.txt` — 80 hint rows: A184–A200
     `mouseHintFollowsRealTargets` (17), A201–A228
     `mouseHintMenuScopeKeepsRenameAndRestoresEditor` (28), A229–A241
     `mouseHintPopupScopeRestoresCoveredTarget` (13), A242–A263
     `mouseHintStatusLayoutStaysStable` (22). Dispositions today: mostly GAP,
     a few PARTIAL citing S002–S009, a few RETIRED-REPRESENTATION.
   - `proof.tst_mainwindowrouting_lifecycle.txt` — A111–A118+
     `mouseHintWidgetDragSettlesOnRelease` (~10 rows): A111 fixture-open GAP,
     A112/A113/A115 RETIRED-REPRESENTATION, A114 (`isVisibleTo`) /
     A116 (`underMouse`) / A117 (`currentSource() == dial`) GAP,
     A118 PARTIAL on S002–S009.
   - Automation/drawer hint rows need no new claims here: the hover model
     (`hoverHintProfile` node/sweep/pencil/empty, menu-muting, tap/ghost
     catalog) already executes through `automationcanvasediting.swift`,
     `AutomationPageChecks.swift` (`tapHintCatalog`, `menuHintMuting`) and the
     `verify:qml` drawer lane (hover ledger S047–S094). Remaining hover-ledger
     GAPs pin `mouseGrabberItem`/native grab cleanup and stay untouched.
2. **Fork laws** (`git show fceecd88:src/ui/mousehints/mousehints.h`,
   `hintprofiles.h`, `tst_mainwindowrouting_state.cpp:492-780`):
   - `claim(source, profile)` replaces ownership even for an identical
     profile; `Empty` is a real claim by a no-hint target; only the current
     owner clears; `hintChanged` fires only when displayed text changes;
     one coalesced `scopeRefresh` follows scope recovery/reactivation.
   - `mouseHintFollowsRealTargets` (:492-545): plot/gutter/headers hover each
     publish a non-empty profile with no manual clear; the mute control
     claims empty instead of leaking the row; returning to the row body
     restores the row text; the scrollbar group is a no-hint cover (source
     leaves headers, text empties).
   - Menu scope (:549-635) keeps the rename hint and restores the editor
     hint on dismiss; popup scope (:639-676) restores the covered target.
   - Status layout (:680-775): the middle caption mirrors the current text,
     stays centered, survives transient messages and the meter without
     shifting the hint center, and elided hints keep the center.
3. **Swift current state**: `MouseHints.swift:7-90` owns tokens, owner,
   profile, window-active gating and `profileText` (Ids 1–27, `⌘/⇧/⌥`
   wording); `ApplicationSession.mouseHintsPresenter()` publishes it and
   `EditorSurface.qml:40-43` drives `setWindowActive` from window activity.
   Drawer pages already receive `hintService` (`AutomationPage`,
   `VelocityPage`, `VoiceChangesPage`, `VoicePicker`, prompts). The gap is
   presentation: `ShellWindow.qml:729-746` footer binds `shell.statusText`
   (`ShellPresenter.swift:170`), not `MouseHints.text` — no production
   binding renders the hint, and no check observes claim→presentation.
4. **Serialize after task 65.** The two-song Qt MainWindow session
   fixture-open preconditions (state A184/A201/A229, lifecycle A111) overlap
   in-flight task 65 (`ApplicationSession`, `DocumentWorkspace`,
   `ShellPresenter`, `EditorViewStateCodec`, `tst_ShellWindow`,
   `tst_ShellTabs`). This task consumes 65's session/tab fixture; it does
   not edit 65's files. Message `Task65` before touching shared fixtures.

# Exact write set

- `src/ui/shell/ShellWindow.qml` — footer hint caption bound to the hints
  presenter text (centered, elided, layout-stable against transient
  status/meter).
- `src/swift/app/shell/ShellPresenter.swift` — publish the hints presenter
  (or its text) to the footer binding; arbitration between transient status
  messages and hint text.
- `src/swift/app/MouseHints.swift` — scope behaviors only if a new
  predicate exposes a divergence (menu/popup scope entry points); no
  ownership-model change expected.
- `src/checks/workspace/session_editor_semantics.swift` — scope predicates
  (menu-keeps-rename, dismiss-restores-editor, popup-restores-covered,
  transient-message preservation) against `MouseHints` + presenter.
- `src/checks/shell/tst_ShellWindow.qml` (or the existing shell hint lane,
  if 65 created one — reuse, do not duplicate) — claim→caption presentation
  predicates over real QML hover delivery with fixture data.
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  row flips only in `proof.tst_mainwindowrouting_state.txt` and
  `proof.tst_mainwindowrouting_lifecycle.txt`.

No new C++; no `src/project/` or `external/` changes; `ApplicationSession.swift`,
`DocumentWorkspace.swift`, `EditorViewStateCodec`, drawer pages untouched
(hintService plumbing already lands via 65/clearance lanes).

# Prerequisites

- Task 65 settled (session/tab fixture, `tst_ShellWindow`/`tst_ShellTabs`
  ownership). This task consumes its two-song open fixture and shell lane;
  it starts after 65 lands.

# Interface contract

- `MouseHints` keeps its published shape (`allocateSourceToken`,
  `claim(sourceToken:profile:)`, `clear(sourceToken:)`,
  `setWindowActive(active:)`, `text`, `scopeRefresh`); scope entry points
  only if the fork's menu/popup behavior needs production state beyond
  claim/clear (prefer QML-scoped claims through existing `hintService`
  props — no new presenter singletons).
- Footer binding: the hint caption renders `MouseHints.text`, horizontally
  centered, elided at the tail; transient `statusText` messages never shift
  the hint center; showing/clearing the meter never shifts it. Sizing
  derives from the resolved base font (`bodyMetrics`/`captionMetrics`
  pattern); no hard-coded pixel constants.
- New check anchors (message-anchored, one per fork clause; the `message:`
  strings are the ledger anchors and stay verbatim once written):
  - `mouseHintScopeChecks::menuScope` — "an open menu keeps the rename hint
    and dismiss restores the editor hint".
  - `::popupScope` — "dismissing a popup restores the covered target hint".
  - `::statusPresentation` — "the footer caption mirrors the current hint
    text"; "transient status and meter changes keep the hint center";
    "elided hints retain the status center".
  - `::targetClaims` — "each hover target publishes its own non-empty
    profile"; "a no-hint control claims empty instead of leaking";
    "returning to the row body restores the row text".
- Preservation contract: every existing check message in touched files
  stays verbatim; `profileText` wording unchanged (hintprofiles.cpp is the
  oracle — record RED→GREEN only for a real divergence).

# Implementation steps

1. Confirm 65's landed fixture: two-song open helper and shell lane entry.
   If the fixture is absent, stop and report Blocked-by-65; do not build a
   parallel session harness.
2. Bind the footer hint caption in `ShellWindow.qml` to the hints presenter
   text with centering + tail elision; add `ShellPresenter` publication and
   status-vs-hint arbitration (transient message preserves/restores hint
   per the fork's status-layout clause).
3. Add scope predicates to `session_editor_semantics.swift` per the
   contract using real `MouseHints` claims (token claims stand in for
   delivery; QML delivery itself is asserted in step 4 — never assert
   `currentSource`-style object identity in Swift).
4. Add the shell QML presentation predicates over real hover delivery with
   checked-in fixture data (roll plot/gutter/headers incl. a no-hint
   control); follow the drawer lane's `testCase` input pattern, not
   synthetic `QTest::mouseMove` equivalents.
5. Run the lanes below; the per-lane evidence JSONs under
   `build/proof-evidence/` feed the ledger agent.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — scope predicates +
  existing `mouseHintOwnershipChecks` regressions.
- `deno task verify:shell --filter shell-window --verbose` (or 65's hint
  lane name if renamed — reassess only if stale) — claim→caption
  presentation over real QML delivery.
- `deno task verify:qml --verbose` — drawer hover/hint regressions
  (no new drawer predicates; proves no scope regression).
- Runtime prerequisite: macOS with display for the shell/QML lanes;
  headless runs prove swiftcore only (report the limit, do not
  re-pin from related passes).

# Task-specific constraints

- Hint/Ukraine-profile wording follows `hintprofiles.cpp`; `⌘` for Qt
  Control on macOS is a description, never a second shortcut map. No new
  `Shortcut`, no `ShortcutOverride`, no `Keys` handlers, no synthetic
  forwarding or focus memory — keyboard priority stands; hints are
  pointer-descriptive only.
- Typography: Atkinson Next 400/600 + Mono 400 through the session
  chrome-typography roles; WCAG AA contrast for the caption against the
  footer surface beats pixel parity with the QWidget status bar.
- No test-only seams: QML claims go through the production `hintService`
  props; Swift owns no settings here (`PreferencesStore` untouched — hints
  are transient, never persisted).
- Implementers never edit ledgers; the controller delegates them to the
  ledger agent. Ledger mapping (agent; re-verify each row against the
  evidence JSONs and the fork sources cited above):
  - state A190/A192/A195 (non-empty profile text) → `::targetClaims`
    anchors (MATCHED); A189/A191/A194/A197/A198/A200
    (`currentSource()` identity/delivery) → RETIRED-REPRESENTATION
    (QObject delivery identity, no Swift ingress; verify at the ledger's
    Reference revision); A185–A187 (Quick item/window handles),
    A199 (scrollbar `isVisible`), A193/A196 (header probe guards) →
    RETIRED-REPRESENTATION only where the row pins handles/visibility,
    else leave GAP with the 65-fixture blocker named.
  - state A201–A241 (menu/popup scope): behavior rows → scope anchors
    (MATCHED); rows pinning `QStatusBar`/widget observers or
    `quick_popup` native session handles → RETIRED-REPRESENTATION
    (fork-verified); fixture-open preconditions stay GAP Blocked-by-65
    if 65 did not provide them.
  - state A242–A263 (status layout): caption-mirror/center/stability
    rows → `::statusPresentation` anchors (MATCHED); rows pinning
    `QStatusBar` geometry handles or pixel grabs →
    RETIRED-REPRESENTATION (fork-verified).
  - lifecycle A114/A116/A117 (`isVisibleTo`/`underMouse`/dial identity)
    → RETIRED-REPRESENTATION (native delivery/visibility, fork-verified
    at the ledger's Reference revision); A118 → scope/target anchor
    (MATCHED); A111 stays GAP Blocked-by-65 unless the fixture lands.
  - RETIRED-REPRESENTATION is used ONLY for rows pinning C++/QWidget/
    QAction/native-delivery internals, each fork-verified at the ledger's
    Reference revision — never for wording or scope behavior.
  - No ledger is deleted by this task (both families retain Blocked and
    native-delivery rows outside this surface).

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed` (hint behavior rows closed with
   executing anchors; representation rows cited to revision).
2. `deno task proof sites --area mainwindowrouting` confirms no non-hint
   row moved and both ledgers survive.
3. Visual smoke: shell window with a song open shows the hover hint
   centered in the footer; opening a menu keeps scope text; dismiss
   restores; transient status never shifts the center.
