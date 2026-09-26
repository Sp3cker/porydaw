# Context

ED09 slice 1 — the Event List **cell-edit commit contract**: typed and
programmatic tick edits (64-bit exact, `kNoTick`/`kMaxTick` boundaries),
channel/data/blob conversion commits, and the row-menu insert-copy path
including EOT-sentinel refusal, through the mounted Swift surface
(`EventListPresenter` + `src/ui/songview/quick/EventListPage.qml`).

Spec ledger `src/checks/eventviews/proof.edits.txt` (edits.cpp @ `a1244957`;
200 rows = 51 MATCHED, 1 RETIRED, 123 GAP, 25 PARTIAL). The Swift surface
exists (`commitCellEdit` EventListEditing.swift:22, `beginEditing`/
`finishEditing` EventListPresenter.swift:230-248, `addEvent`
EventListEditing.swift:135) and document-level mutations are proven
(`EventViewsEditsParity.swift`, `tst_songdocument_songraw.swift`); every
PARTIAL row's unproved clause is that presenter commit path, which has no
predicates today.

Row classification (148 open = 123 GAP + 25 PARTIAL):

- **Behavior, this task: 65 rows** (47 GAP + 18 PARTIAL) across six edits.cpp
  functions: tickEditQueued A002–A010, tick64BitExact A011–A019,
  tickHighBitExact A020–A031, tickHighBitThroughEditor A032–A047,
  channelAndDataConversions A048–A062 + A065, insertCopy A112–A119. Four rows
  (A035/A036/A039/A040: editor opens, selectAll, re-open) are already asserted
  by `tst_ShellEventList.qml:215-231` plus this task's re-open phase; the
  other 61 get new predicates.
- **Behavior, deferred: 74 rows** — rawTempoAtomic 26 open (presenter tempo↔
  meta conversion commit + projected tempo rows), sameTickReorder 21 (pointer
  drag delivery, currentRow follow, `!isEditing` after refused drop, row-menu
  session, A163 focus + A165 binding — already observable via
  tst_ShellEventList.qml:119-125,169-174), deleteMatrix 14,
  drawerClickAfterEditOwnsDelete 13. Each group gets its own follow-up brief.
- **Representation: 9 rows** — A001 (typeDigits file-local digit guard) and
  sameTickReorder harness/Quick internals A146, A149, A150, A152, A162, A164,
  A170, A177 (scene-coordinate lookup, QuickMenuHost panel/model lookups,
  QSignalSpy validity, TimelineQuickView pointer, async_wait boilerplate,
  `quickView() != nullptr`). RETIRED-REPRESENTATION; never port as checks.
- **Blocked: 0.**

Adjacent ledgers: `proof.chrome.txt` is event-list *chrome* (resize,
filter-menu session, typography, scrollbars, row-menu activation) for a
separate follow-up brief — its unmounted-EventListPage "why" is stale;
`proof.viewbuckets_grid.txt` is grid-paint math, unrelated.

## Product gaps (primary-source evidence)

1. **EOT insert not refused.** Row-menu "Insert event" is the shipped route
   and called `insertCopyOfRow(m_menuRow)` (b28f0827
   eventlistcontroller.cpp:107-109, 655-667: no source event → strict no-op;
   pinned by A118/A119). Swift routes it through `addEvent()`, whose fallback
   inserts a default CC at the cursor when the current row is the sentinel
   (EventListEditing.swift:143-146). **Repair authorized here.**
2. **Tempo-row insert loses the source tempo.** Original copies the row's
   µs-per-quarter (b28f0827 eventlistcontroller.cpp:636-641); Swift hardcodes
   `500_000` (EventListEditing.swift:139-140). **Repair authorized here.**
3. **Insert does not select the inserted row.** Original `selectEventRow`
   after insert (b28f0827 eventlistcontroller.cpp:630, 666); Swift lacks it
   (EventListEditing.swift:146). Mirror the post-drop focus/select pattern
   (EventListSelection.swift:132-137). **Authorized.**
4. **UInt64→Int trap at kMaxTick.** `Int(source.tick)`
   (EventListPresenter.swift:21) and `Int(tick)` (:253) trap above Int64.max;
   `kMaxTick` = `TimeDefaults.maxTick` = UInt64.max−1 (MusicTypes.swift:50-51),
   so committing kMaxTick crashes row publication. No QML consumer reads the
   numeric handle tick (display uses `tickString`/`cellDisplay`).
   **Authorized:** `Int(clamping:)` at both sites; the exact value travels as
   a string.
5. **EOT muted-label regression.** `cell.endRow && cell.row % 2` (src/ui/
   songview/quick/EventListPage.qml:469) mutes only odd EOT rows; the
   original mutes every EOT row. **Repair authorized, AA-gated** (below).
6. *(Deferred)* Single delete clears the cursor (EventListEditing.swift:
   156-159 vs b28f0827 eventlistcontroller.cpp:676-680; A186 edits.cpp:647)
   → deleteMatrix brief.
7. *(Deferred)* Row menu lacks the conditional "Show voice in voicegroup"
   item, separators and the "Delete %n event(s)" count label
   (EventListMenus.swift:94-101 vs b28f0827 eventlistcontroller.cpp:1060-1089).
8. *(Deferred)* Focus-loss ordering: EventListPage.qml:527-531 wires both
   `onEditingFinished` (commit) and `onActiveFocusChanged`→cancel; the
   a1244957 contract commits on focus loss (edits.cpp:675-679) → drawer brief.

# Exact write set

- `src/swift/app/eventlist/EventListEditing.swift` — `dispatchAddEvent` only:
  EOT-sentinel refusal, tempo-µs copy, post-insert focus/select (gaps 1-3).
- `src/swift/app/eventlist/EventListPresenter.swift` — overflow-safe
  `Int(clamping:)` at lines 21 and 253 only (gap 4).
- `src/ui/songview/quick/EventListPage.qml` — the EOT secondary-text
  condition at line 469 only (gap 5). No geometry edits.
- `src/checks/eventviews/EventListPageChecks.swift` — one new internal
  function `eventListCellCommitContract(_ report:suite:service:)` (own
  fixture, mirroring the inline fixture at :10-27) called from
  `runEventListPageChecks`.
- `src/checks/editorqml/tst_ShellEventList.qml` — one new test function for
  the typed-boundary editor path.

No new files, lanes or registrations: swiftcore already runs
EventListPageChecks (SessionChecks.swift:72) and the shell lane runs
tst_ShellEventList. The implementer does **not** edit proof ledgers; the
controller's ledger agent updates `proof.edits.txt` in the same commit.

# Prerequisites

None blocking. The surface is mounted and both lanes are registered; no
overlap with task-18 owners (DocumentSession/SongTabsController/PianoGrid).

# Interface contract

- Fixture: chunk 0 = marker meta 0x06 `"marker"` @ tick 0 + NoteOn (60/90)
  @ tick 12, endTick 12 (C++ `FixtureShape::Basic`); wire
  `session.onChange → presenter.documentDidChange` (EventListPageChecks
  .swift:25); reuse `chunksSortedByTick` (EventChecks.swift:54).
- Presenter predicates G1–G6, one `expect*` per ledger clause, all with
  contract-shaped `what:`/`message:` anchors (R20: message anchors are
  mandatory for MATCHED):
  - G1 → A002–A010: attach/row guards (attach-existence predicates per the
    accepted EventListPlayheadChecks A001/A002 precedent); commit
    `commitCellEdit(row, 0, "15")` → true; row republished at 15;
    `tickString` == "15"; `history.undoIndex` +1; chunk sorted; undo restores
    the tick-12 row.
  - G2 → A011–A019: commit `"3000000000"` → exact back-event tick; undo +1;
    sorted; undo restores.
  - G3 → A020–A031: `String(TimeDefaults.noTick)` → false, undoIndex
    unchanged, row still at 12; `String(TimeDefaults.maxTick)` → true, undo
    +1, last event tick == maxTick, sorted, undo restores.
  - G4 → A032–A034, A037–A038, A041–A047: `beginEditing` true;
    `finishEditing(noTick, commit: true)` → false, `editing` stays true,
    undoIndex unchanged, `try document.file.encoded()` byte-identical; then
    `finishEditing(maxTick, commit: true)` → true, editing false, row at
    maxTick exists, `tickString` equals the exact decimal digits, sorted,
    undo restores.
  - G5 → A048–A062, A065: channel `"5"` → status nibble 4; data1 `"100"`,
    data2 `"33"`; blob `"\"room\""` on the marker row stores `room` bytes
    (parseBlob handles quotes, EventListProjection.swift:92-96); undo
    counts before+1/+3/+4; unwind restores channel 0, 60/90, `"marker"`,
    with the tick-12 row present throughout.
  - G6 → A112–A119: focus row 0 then `addEvent()` → marker count +1, undo
    +1, sorted, undo restores; focus the EOT row then `addEvent()` → no-op
    (undoIndex and event count unchanged) — fails before repair 1.
- QML test (typed path): select a note row, F2, editor focus (existing
  pattern); type the 20 `noTick` digits + Return → `presenter.editing` stays
  true and the displayed tick is unchanged; Escape; F2 again (A039/A040
  re-open + selectAll) → type the 20 `maxTick` digits + Return → editing
  false and `presenter.tickString(row)` equals the exact digit string.
  Compare ticks as **strings only** — the value exceeds 2^53.
- `dispatchAddEvent` keeps its no-selection default-CC fallback and the
  editCursor re-tick; only the sentinel guard, tempo-µs copy and post-insert
  selection change.

# Visual parity

- Counterpart (pre-widget-deletion `b28f0827`): the Event List was already Qt
  Quick — `git show b28f0827:src/ui/songview/quick/EventListPage.qml` plus
  `eventlistcontroller.h/.cpp`, `eventtablemodel.h`, `eventtabletypes.h`
  (widget ancestor `eventlistview.cpp` retired earlier). Narrative contract:
  `docs/old/quick-eventlist-local-plan.md` §5 "PAGE CONTRACT". No manual
  screenshots exist (checked docs/ and src/checks/fixtures/visual).
- Contract to reproduce: 7 columns Tick/Type/Ch/Data 1/Data 2/Data/Summary
  (widths 70/120/36/56/56/140, Summary stretch; right-align 0/2/3/4,
  left-align 1/5/6); toolbar (chunk selector, filter, add, delete, count
  text); 1-based row-index header; striping; current-cell focus outline;
  playhead tint `#2CE24244`; muted "End of track" EOT row with only the tick
  cell editable; column 1 edits open the 11-entry type menu, columns 2-4
  steppable numeric TextInputs, column 5 blob editor; row-menu separators.
- Geometry is font-derived in both revisions (rowHeight `ceil(metrics+6)`,
  padding `max(4, ceil(h/3))`, scrollbar breadth `max(10, ceil(h*0.85))`,
  minimum column width from header advance) — the metric ratios are the
  requirement, not pixel constants; colors are GridPalette pairs via
  `EventListAppearance.roles()` (EventListMenus.swift:35-63).
- This task's visual change is limited to gap 5: restore unconditional
  `tableSecondaryText` for EOT rows **only after** the pair verifies WCAG AA
  on both `rollBackground` and `windowBackground`; if it fails, pick the
  nearest AA-passing GridPalette role and record the deviation. The
  TextInput selection-color pair (original `focusOutline` vs current
  `tableSelectedBackground/Text`) and the monospace family default are
  pre-existing deviations: list them, do not change them here.
- Visual acceptance (controller, after the writer freezes): capture the
  mounted `eventListPage` raster via the existing shell-lane grab pattern and
  compare against the contract above (columns, striping, muted EOT label on
  both parities, editor focus outline); every deviation listed and justified.

# Implementation steps

1. Add G1–G6 presenter predicates; run CORE to observe the expected failures
   (gap 4 may crash — that is the failing-before evidence; isolate G3/G4
   first if needed).
2. Apply repairs 1-4 in the two Swift files; G1–G6 pass.
3. Apply the EOT label-color fix with its AA check; extend the QML lane.
4. Report every new predicate's `message:`/`what:` strings with file:line so
   the controller's ledger agent can anchor the handoff; any further
   BEHAVIOR-GAP beyond gaps 1-5 stops and escalates.

# Acceptance predicate

- All 65 in-slice rows have executing predicates (61 new + 4 via
  tst_ShellEventList.qml:215-231 and the new re-open phase); insertCopy's EOT
  predicates fail before repair 1 and pass after.
- Controller-run named checks after the writer freezes:
  - `deno task verify --filter swiftcore --verbose` (CORE)
  - `deno task verify:shell --filter shell-event-list --verbose`
  - `deno task verify:bridge`
  - `deno task proof check` and `deno task proof check --executed`
  - `deno task proof check --strict-mappings` (post-handoff): proof.edits.txt
    shows zero strict-list sites except the explicitly deferred
    rawTempoAtomic/sameTickReorder/deleteMatrix/drawer rows.
- Ledger handoff (controller-owned, same commit): slice rows → MATCHED citing
  the new message-anchored predicates; A001, A146, A149, A150, A152, A162,
  A164, A170, A177 → RETIRED-REPRESENTATION (reasons above); all other rows
  unchanged.

# Task-specific constraints

No implementer proof edits. No representation rows as checks. No pixel
constants (the color fix is palette-role logic only; geometry untouched). No
new lanes, files or registrations beyond the write set. No sleeps; QML waits
use `waitForNative`. QML tick comparisons are string-based. Predicate
messages are contract-shaped ("typed kNoTick leaves the document bytes
unchanged", not "equal == true"). Do not port `insertCopyOfRow` as a new API —
repair `dispatchAddEvent` in place. Keep the deferred groups' rows untouched,
including proof.chrome.txt and proof.viewbuckets_grid.txt.
