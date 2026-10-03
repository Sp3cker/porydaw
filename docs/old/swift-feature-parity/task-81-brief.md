# Task 81 brief — standalone window Insert Time uses the mounted prompt

# Context

The ruler can already open Insert Time, but the canonical window command is
unavailable without a time range. Connect that command to the existing prompt;
do not build another form or dispatcher. A range still inserts immediately in
its selected scope. This is a real missing ingress, not the ledger preamble's
claim that the prompt itself is unmounted.

1. **Verified census: 27 open rows** in
   `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt`:
   - PARTIAL (**7**): A093, A094, A095, A100, A101, A102, A103.
   - GAP (**20**): A096, A097, A098, A099, A104, A105, A106, A107, A108,
     A109, A110, A111, A112, A113, A114, A115, A116, A117, A118, A119.
   - A096/A105/A112 are native popup/window pointer-pair checks, currently
     GAP. This surface owns their replacement: retire the pointer
     representation here and separately prove the visible prompt. The other
     **24** are behavior/input outcomes. No QAction/focusWidget chain is ported.
   - One existing MATCHED row needs anchor repair, not a new disposition:
     A168 maps to S191, the obsolete no-selection **Insert**-disabled check.
     The fork clause is **Delete** disabled without a range. Re-anchor it to
     the already-existing Delete-disabled predicate when removing S191.
2. **Fork laws**, `fceecd88:src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp`:
   - `:342-346,379-415`: a 3/64 signature at 24 PPQN has one-tick beats;
     opening captures the edit cursor, not the playhead, and displays 1 bar,
     0 beats, 0 fractions. The playhead may continue moving under the form.
   - `:420-503`: Tab edits the actual fields; click or Return accepts;
     stopped two-beat, playing one-bar, and playing quarter-beat cases shift
     both active-song tracks by the exact span, commit once, leave the other
     tab unchanged, and one undo restores exact MIDI bytes. Fractions round
     upward: `(fractions * beatTicks + 3) / 4`, not truncation.
   - `:505-545`: zero accept and Cancel close without changing bytes,
     revision or history; zero accept also leaves the inactive song alone.
   - `:547-567`: a revision-changing edit under the form invalidates its
     captured insertion. Accepting the stale form closes it and changes
     nothing beyond the intervening edit.
   - `:729-738`: Delete Time is disabled without a selection (A168 repair).
3. **Current state**, read after the split:
   - `src/swift/app/EditorCommandRouter.swift:39-51,64-80` delegates range
     commands to Automation but sends standalone commands to PianoGrid;
     no standalone Insert Time branch exists. `:85-90` constructs the router
     from the selected workspace.
   - `src/swift/app/shell/ShellPresenter.swift:228-247` derives command
     enablement from that router through ApplicationSession. Do not add a
     second ShellPresenter special case.
   - `src/swift/app/timeline/RulerMenuPresenter.swift:224-236` opens the form
     only from its captured ruler-menu action. `:266-309` already captures
     revision/signature, publishes defaults/appearance and implements exact
     whole-song insertion, zero-span and stale-revision refusal.
   - `src/ui/songview/quick/swiftroll/EditorSurface.qml:1101-1118` mounts
     `InsertTimePrompt` with the same ruler presenter. Reuse it unchanged.
   - `src/checks/editorqml/tst_ShellWindow.qml:751-754` pins the obsolete
     no-selection Insert-disabled implementation and the still-correct
     Delete-disabled behavior. Remove the former, preserve the latter.
   - Router construction sites are `session_edit_routing.swift:37-42`,
     `session_editor_semantics.swift:96-101`, `session_time_routing.swift:39-45`
     under `src/checks/workspace/`, and
     `src/checks/rollcheck/note_commands.swift:185-191`. Migrate all four.
     LSP references failed to load the Swift standard library during freeze;
     these current source reads and scoped constructor search are the fallback.

# Exact write set

- `src/swift/app/EditorCommandRouter.swift`
- `src/swift/app/timeline/RulerMenuPresenter.swift`
- `src/checks/workspace/session_edit_routing.swift`
- `src/checks/workspace/session_editor_semantics.swift`
- `src/checks/workspace/session_time_routing.swift`
- `src/checks/rollcheck/note_commands.swift`
- `src/checks/editorqml/tst_ShellWindow.qml` — **hot: sole Group A owner**.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt` — selected rows, new anchors, removal of obsolete S191, and A168 anchor repair only.

`ShellWindow.qml`, `ShellPresenter.swift`, `ApplicationSession.swift`,
`DocumentWorkspace.swift`, `EditorSurface.qml`, `PianoGrid.swift`,
`InsertTimePrompt.qml` and every task-78 reserved file are unchanged. No CMake
or bridge-registration changes. The constructor migrations are required
callsite changes, not separate behavioral expansion.

# Prerequisites

Use the settled split/path repair in sprint-3 §8. The existing ruler prompt,
selected-workspace command router and range executor are the only consumed
interfaces. No dependency on a new interface from 79, 80 or 82; Group A parallel.

# Interface contract

- Extend `EditorCommandRouter.init(session:grid:automation:drawer:velocity:)`
  with a **required** `rulerMenu: RulerMenuPresenter` dependency, using the
  existing unowned workspace-presenter lifetime convention. No optional
  fallback/default stub for old callers. Supply the workspace ruler in the
  existing ApplicationSession extension in the same file; each isolated
  check constructs and retains its real ruler for the router's lifetime.
- Add `RulerMenuPresenter.openInsertTimePromptAtCursor() -> Bool` in the
  bridge-visible class body. It opens only for a live session, an editable
  cursor before `TimeDefaults.maxTick`, and no active range. It captures
  `session.editCursor` and the signature/revision at that tick, using the
  same private prompt preparation as the ruler-menu opener. It never seeks,
  toggles playback, or synthesizes a ruler-menu click.
- `EditorCommandRouter.isAvailable` and `perform` gain the standalone
  `.insertTime` case **after** range ownership has been resolved. Active
  range behavior remains `consumeSelectionCommand`; no range opens the form.
  The form participates in the existing router modal gate, not a new matcher.
- `acceptInsertTimePrompt(bars:beats:fractions:)` and cancellation retain their
  existing semantics. Opening never edits; accepted nonzero span affects all
  tracks of the captured active document exactly once; zero, cancel and stale
  acceptance create no new history. Closing/changing tab uses existing
  workspace prompt cancellation; no pending insertion follows a different tab.
- Separate message anchors for each A093/A094/A095 conjunct: visible defaults,
  exact span, both shifted tracks, one revision/undo entry, inactive bytes,
  closed form and exact undo restoration. A097/A098/A099, A106/A107/A108 and
  A113/A114/A115 prove field input/button/closing outcomes on the mounted form.
  A100–A104, A109–A111 and A116–A119 read their respective bytes/history/
  revision/no-cross-tab-write conditions independently.
- Existing messages stay verbatim. The sole deliberate removal is the
  obsolete assertion and anchor “an open song without a time selection cannot
  insert a selected range”. Do not rewrite its message into new meaning.
  A168 stays MATCHED by the existing message “an open song without a time
  selection cannot delete a selected range”. All other messages are preserved.

# Implementation steps

1. **RED first:** in ShellWindow, no range + the actual Insert Time menu row
   or registered shortcut must open the form. Observe current disabled
   behavior. Add the stopped/playing/quarter-beat and zero/cancel/stale
   owner-level predicates in `session_time_routing.swift`, before the fix.
2. Wire the required ruler dependency through every named constructor. Add
   the standalone opener and route it once through the existing router;
   reuse prompt preparation/acceptance, never duplicate the time arithmetic.
3. Complete the mounted journey using real field Tab/typing/Return and button
   clicks, selected tabs and a playhead separate from the edit cursor. Observe
   defaults and document outcomes, not popup pointer identity or focus memory.
   Pair QML outcomes with direct session byte/history checks; do not add a
   QML-only serialization probe to production.
4. Remove the obsolete Insert-disabled assertion, preserve Delete-disabled,
   and repair A168's anchor in this same feature change. Exercise existing
   active-range insertion as a regression: it must still act immediately,
   preserve scope and never open the form.
5. Run the two named lanes after the group settles. Retire only the three
   pointer-pair rows; map each other selected clause to executed predicates.

# Acceptance predicate

Controller-run on a settled built tree, separate invocations, each at most 180 s:

- `deno task verify --filter swiftcore-projectsession --verbose` — exact
  spans, raw MIDI bytes, history/revision, zero/cancel/stale and range
  precedence; `build/proof-evidence/swiftcore-projectsession.json`.
- `deno task verify:shell --filter shellwindow --verbose` — actual menu/key
  ingress, form defaults, Tab/input/Return/click, close and active-tab smoke;
  `build/proof-evidence/shellwindow.json`.

The Swift suite calls time routing at `src/checks/workspace/SessionChecks.swift:
88`; its manifest is `src/checks/checkcatalog.cpp:107-125`. Shell registration
is `src/checks/editorqml/ShellQmlTests.swift:60-61`; evidence writing is
`tools/run_checks.ts:426-434`. No unfiltered shell aggregate is required.

# Task-specific constraints

All **sprint-3 §8 Wave constraints** are incorporated: Swift 6.4 spans/fixed
storage/ownership idioms where appropriate, typed throws/strict concurrency,
no hot-path temporaries, two-line comments, base-font/WCAG AA, sole window
shortcut authority/no synthetic forwarding/focus memory/bare Space in chrome,
message-per-clause, real fixtures/no test seams, no `Qt.callLater` coalescing
or idempotence workarounds, approval for workarounds, deferred menus and parked
areas unchanged. No new C++.

Preserve the user ruling that cursor commits never seek or move the playhead
in any transport state; the existing resume settle hold is unrelated. Do not
port the fork's focusWidget identity: the existing modal ingress/return path
must work without new focus memory. No user policy decision is needed here.

# Controller verification

After fresh evidence, run `deno task proof check --executed`, then:

- `deno task proof sites --area mainwindowrouting --status PARTIAL`
- `deno task proof sites --area mainwindowrouting --status GAP`
- `deno task proof sites mainwindowrouting/proof.tst_mainwindowrouting_input.txt --status PARTIAL`
- `deno task proof sites mainwindowrouting/proof.tst_mainwindowrouting_input.txt --status GAP`

Expected: A093–A119 close, with A096/A105/A112 RETIRED-REPRESENTATION and the
other 24 MATCHED only when every clause executes. A168 remains MATCHED with
its corrected Delete predicate. No other disposition changes; the ledger stays.
