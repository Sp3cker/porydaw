# Context

Task 55 — automation value-prompt / CC-delete / tap-tempo journeys. Close the four
prompt-family ledgers (`proof.valueprompt.txt` 65 open of 103, `proof.ccdeleteconfirmation.txt`
54 of 157, `proof.automationtaptempo.txt` 17 of 162, `proof.automationfixture.txt` 10 of 12;
146 open total) on the mounted automation drawer. Fork oracle `fceecd88`:
`git show fceecd88:src/checks/drawerpresentation/valueprompt.cpp`,
`.../automation/ccdeleteconfirmation.cpp`, `.../automation/automationtaptempo.cpp`
(ledger-pinned revisions `c17d966f`/`f3069ef6` — byte-identity re-verified at freeze).
1. **The surface already exists; this is proof completion, not a build.** The value
   form and the CC-delete confirmation are one component, `AutomationPrompt.qml`
   (`promptKind` 0/1): focus ingress + select-all `:39-47`, accept `:48-53`,
   underlay press-cancel over Left/Right/Middle `:59-64`, card Escape `:80-85`,
   focus-loss cancel `:133-139`, message + Delete/Cancel buttons
   `:94-100,:148-171`. The page hosts it (`AutomationPage.qml:608-678`;
   `onClosed → focusOrigin()` = plot re-focus `:233-236,:631,:639`). Presenter
   policy is complete: `AutomationModal.swift` `openCapturedPrompt` `:263-282`,
   `acceptCapturedPrompt` (revision/parameter/track revalidate, move-or-insert)
   `:284-314`, `openLaneDeleteConfirmation` (count>0 guard, message names the
   written count) `:199-212`, `acceptLaneDeleteConfirmation` `:78-102`, dispatch
   `.setValue`/`.deleteLaneEvents` `:427-441`. Tap-tempo is rendered and wired:
   Tap control `AutomationTabs.qml:91-135`, inline draft readout `:174-181`,
   idle-commit Timer `:219-228`; session + guard `AutomationTapTempo.swift:11-128`.
   The hint catalog exists — `MouseHints.profileText` cases 25/27 `:84,:86`.
2. **Mounted predicates that already execute** (`tst_EditorDrawer.qml`):
   `test_productionAutomationPromptTransaction` `:5070-5229` (Set Value via real
   row click, typed commit, refused out-of-domain draft, Escape/underlay cancel,
   frozen-revision clearing); `...SetValuePromptFocusRoute` `:5463-5581` (field
   focus, draft opens selected `:5500`, Escape and acceptance both return focus
   to the plot `:5515-5549`, parameter-switch close `:5564-5580`);
   `...TempoPromptFocusRoute` `:5587-5652`; `...SyntheticDefaultMenuRoute`
   `:5659-5745`; `...MenusAndLaneCommands` `:5747-5919` (confirmation opens,
   **initial Cancel focus** `:5840-5842`, initial Return cancels `:5844-5850`,
   rendered Cancel `:5851-5865`, rendered Delete click via `clearAutomationLane`
   `:3788-3809`); `...TapTempoThroughInput` `:5925-6041` (pointer/Return taps,
   cancel, deterministic cadence through the injected `tapTempoTap(atMilliseconds:)`
   route `EditorQmlTests.swift:1049-1057`, idle commit, undo/redo, live "120 BPM"
   readout + caption fonts, lone tap). Presenter suites: `localinputtier_text.swift`
   (`drawerOriginalNumericPromptTransaction`, accept-on-closed inert),
   `automationpointmenus.swift` (post-50b open/accept/undo/stale refusal incl.
   centered offset), `automationtaptempo.swift`, `AutomationPageChecks.swift`.
3. **Why 146 rows are still open — three causes, no feature work.** (a) Stale
   mapping: many PARTIAL/GAP reasons predate the mounted tests above (initial
   Cancel focus, rendered Delete click, focus-return and Escape halves already
   have executing anchors). (b) Genuinely unproved clauses, enumerated in the
   Interface contract. (c) Stale preamble: taptempo A160–A162 say the hint
   catalog is "not ported" — `MouseHints.profileText` renders both texts today.
4. **Fork law for the unproved clauses.** Value prompt (`valueprompt.cpp`): tempo
   insertion opens titled "Set tempo"/"BPM:", bounded `kMinTempoBpm..kMaxTempoBpm`,
   displayed value selected, writes nothing; Enter commits (+1 revision, +1 undo)
   and returns focus to the automation input; the accept seam clamps
   out-of-domain values (`acceptNodeValuePrompt(max±1000)`); centered CC lanes
   (controller 10) prompt in displayed units stored−64, bounds −64..63 — typed
   −64 stores 0, 63 stores 127, displayed 0 inserts stored 64;
   Escape/focus-loss/document-change/window-deactivation/page-hide each cancel
   without a write; the chrome cancel invokable cancels; a late accept is inert.
   CC-delete (`ccdeleteconfirmation.cpp`): label right-press → RemoveLane →
   confirmation with Cancel initially focused; open state writes nothing; a real
   Delete click is one transaction removing only the target lane's written events
   (sibling exact; label stays selectable; undo restores); Cancel/Escape/bare
   Return cancel; an outside right press dismisses without retarget and its
   swallowed release opens no replacement menu; the message advertises the
   written-event count excluding the synthetic node; an eventless lane dispatches
   nothing; a stale (externally rewritten) confirmation refuses. Tap-tempo
   (`automationtaptempo.cpp`): draft from the second tap, recomputed per tap,
   document frozen; the 2000 ms idle window commits one tick-zero tempo edit
   (replacing tick-0, preserving later points, inserting when absent, silent when
   the draft equals the held tempo — sub-ms intervals clamp to 255); a stray
   single tap aborts at idle; document or parameter change aborts synchronously;
   300 ms cadence drafts 170–235 BPM; 150 ms clamps to the 255 ceiling; ≥10 taps
   stay windowed; the TapTempo hint text is non-empty and GhostParameter-distinct.
5. **Dependencies — consume, never duplicate.** 50b landed (`5579eb11`): the
   arbitration seam's standing law is *prompts and the lane-delete confirmation
   are never displaced by a foreign menu* (fork parity for every user-reachable
   path — the confirmation underlay absorbs presses; the fork's programmatic
   takeover invalidation is unreachable by input). 50a-finish (in flight) owns
   `SongTabs.qml` ownership, the `ShellWindow.qml` `drawerModalLayer` focus-loss
   guard `:594-609` (the prompt's focus survival depends on it), deferred menu
   focus in `AutomationMenu.qml`, and the `tst_ShellWindow.qml` prompt
   text-ownership/Escape predicates. Task 55 touches none of those; its journeys
   live in the drawer lane, which mounts the page without `ShellWindow`.
   Window-deactivation wiring already exists shell-side (`ShellWindow.qml:175-178`
   `onActiveChanged → cancelGridInput(3)`); the page-level outcome is this
   task's, the trigger wiring is not.

# Exact write set

- `src/checks/editorqml/tst_EditorDrawer.qml` — append two functions
  (`test_productionAutomationPromptPresentationAndInsertion`,
  `test_productionAutomationCenteredPromptOffset`), extend
  `test_productionAutomationMenusAndLaneCommands`,
  `test_productionAutomationSetValuePromptFocusRoute`,
  `test_productionAutomationTapTempoThroughInput`; existing anchor messages
  verbatim.
- `src/checks/automation/automationtaptempo.swift` — fork-staging presenter
  predicates (255-dedup, two-later-points, 300 ms band) beside the existing ones.
- `src/checks/automation/AutomationPageChecks.swift` — register the new presenter
  predicates; add the hint-catalog predicate (real `MouseHints` service).
- Repair-only, RED-gated: `src/ui/songview/quick/drawer/AutomationPrompt.qml`,
  `src/swift/app/drawer/automation/AutomationPage.swift` — only if a new predicate
  exposes a defect; no planned change.
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  `src/checks/drawerpresentation/proof.valueprompt.txt`,
  `src/checks/automation/proof.ccdeleteconfirmation.txt`,
  `proof.automationtaptempo.txt`, `proof.automationfixture.txt`.

No CMake, `AutomationTabs.qml`, `AutomationMenu.qml`, `AutomationPage.qml`,
`localinputtier_text.swift`, `automationpointmenus.swift`, shell-lane files.
Sizing exception: one proof-completion family over 3–5 files with one
verification-surface set — named for the dispatch table.

# Prerequisites

- 50a settled (owns the `drawerModalLayer` guard and `tst_ShellWindow.qml` regions
  this task's mapping cites; the shell-level prompt predicates are 50a's, not
  re-proved here). 41b settled (owns in-flight `AutomationPage.qml` edits;
  sprint gate for 52–55). 50b's seam law consumed as landed (`5579eb11`).
- Consumes the existing helpers unchanged: `writeVolumeLanePoints` `:3692`,
  `clearAutomationLane` `:3788`, `openAutomationNodeMenu`/`clickAutomationMenuRow`,
  `bootstrap.automationPanIndex()` (`EditorQmlTests.swift:1000`),
  `bootstrap.automationTapCadence` `:1049`.

# Interface contract

New message-anchored predicates (one per fork clause; drawer lane drives real
keys/pointers on the mounted page, presenter predicates use injected readings):

- **Presentation + insertion** (public route `model.openPrompt(tick, value)` — the
  Swift seam equivalent of the fork's `openValuePromptForInsertion`, which has no
  fork production caller either):
  - "the tempo insertion prompt opens without a write" (promptOpen, revision/undo
    unchanged; stage on the Tempo tab at an empty tick).
  - "the tempo prompt shows its title, label and bounds" (`promptTitle` "Set
    tempo", `promptLabel` "BPM:", `promptMinimum`/`promptMaximum` = tempo bounds,
    draft = supplied displayed value).
  - "the typed tempo draft commits at the prompt's tick" (type 90, Return → BPM
    90 at that tick, +1 revision, one history entry, prompt closed).
  - "the insertion prompt's acceptance returns focus to the plot".
- **Centered offset through the rendered field** (Pan tab, written node):
  - "the centered parameter's prompt opens in displayed units" (bounds −64..63,
    draft = stored − 64).
  - "the centered draft's lower bound stores zero" (type −64 → stored 0).
  - "the centered draft's upper bound stores one twenty-seven" (reopen, type 63 →
    stored 127).
- **Invalidation family** (extend the focus-route function):
  - "moving focus off the open prompt cancels it without a write"
    (`plot.forceActiveFocus` while the value prompt is open).
  - "switching the drawer's visible page cancels the open prompt" (drawer page
    toggle while open; no write) — the page-hide/deactivation clauses' page-level
    outcome.
  - "a late acceptance after the close writes nothing" (after Escape,
    `acceptPromptDraft()` returns false; revision unchanged).
- **CC-delete completion** (extend the lane-commands function):
  - "the confirmation advertises the lane's written events" (digits parsed from
    the rendered `automationPromptMessage` contain the written count, not
    count+1).
  - "accepting through the rendered Delete button returns focus to the plot".
  - "the accepted deletion spares the sibling lane" (Pan + Volume both written;
    confirm-delete Pan; Volume values exact; undo restores Pan byte-identically).
  - "an outside right press dismisses the confirmation without a write" (press on
    the underlay outside the card with the right button; prompt closes; the
    release over the plot opens no menu).
  - "the cancelled confirmation keeps the band's focus" (after initial-Return and
    rendered-Cancel journeys, plot holds active focus).
  - "a stale confirmation never deletes the rewritten lane" (external lane
    rewrite through the session staging family while open; real Delete click →
    no additional revision, rewritten points intact).
- **Tap-tempo completion**:
  - "the draft readout starts hidden" (`automationTempoTapDraft` invisible before
    the first tap).
  - "the readout recomputes on every tap" (500 ms gaps → "120 BPM", continuing at
    750 ms → "80 BPM").
  - Presenter (`automationtaptempo.swift`): "a 300-millisecond cadence drafts in
    the fork's band" (170–235); "tapping the tempo the song already holds stays
    silent" (seed 255, two 0-gap taps draft 255 — the sub-ms clamp — idle commits
    nothing, no revision); "the commit replaces only the tick-zero tempo" (later
    points at two ticks survive with values exact; undo restores).
  - Hint catalog (`AutomationPageChecks.swift`, real `MouseHints`): "the tap hint
    publishes its catalog text" and "the tap and ghost hints stay distinct"
    (claim 27 then 25; non-empty, unequal).
- **automationfixture**: no new predicates — its open rows (window exposure,
  input bounds, lane body, band focus, staged values) map to the converted-window
  anchors that already execute (mount/render function, focus-route function,
  staging helpers' own verify messages).

Non-goals: no new prompt/menu/arbitration behavior; no shell-lane predicates; no
`velocity_prompt` (task-54), point-menu, gesture, or geometry work (56/57); no
change to the 50b seam or 50a ownership laws.

# Implementation steps

1. Re-verify mounts and pinned revisions at freeze (stale-preamble hazard):
   confirm each mapped row's cited anchor still executes and the four ledgers'
   reference revisions match `git show fceecd88:<path>` output.
2. Drawer-lane predicates first (RED discipline: record RED only where a
   predicate fails — that is a discovered defect; repair inside
   `AutomationPrompt.qml`/`AutomationPage.swift` only, then GREEN).
3. Presenter predicates for the deterministic tap-tempo journeys (injected
   readings; no wall-clock waits beyond the existing idle-route call).
4. Ledger mapping per the constraints below, in the same commit as the predicates
   that prove each row.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:qml --verbose` — the editor-drawer lane: existing prompt/
  confirmation/tap anchors re-run green verbatim plus the new presentation,
  offset, invalidation, confirmation, and tap predicates.
- `deno task verify --filter swiftcore --verbose` — automation suite + new
  tap-tempo staging predicates + hint-catalog predicate; `localinputtier_text`
  suite unchanged-green.
- Implementer runs these; no desktop audio or native window input is required
  (deterministic cadences use the injected reading route; idle commit uses the
  page's own idle route, matching the existing tap test).

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no
  pixel constants; no palette literals; geometry stays base-font multiples;
  existing anchor messages verbatim; one message-anchored predicate per fork
  clause. WCAG AA: the prompt/card ink audit (`auditVisibleTextInk`) stays in the
  extended functions' paths.
- Implementers never edit ledgers; the controller delegates per-commit:
  - valueprompt: staging/fixture rows (A002–A004, A031–A034, A058–A062, A071–A073,
    A093–A095) → converted-window staging anchors; presentation rows (A005–A013,
    A036–A040, A046–A047, A051–A052) → presentation/offset anchors; open-no-write
    and commit rows → existing transaction/tempo/synthetic anchors + insertion
    anchors; clamp rows (A023–A028) → presenter accept-clamp anchors plus the
    mounted refused-draft anchor; focus ingress/return rows (A014–A015, A020,
    A060, A064–A070, A072–A079, A095–A100) → focus-route + new focus-loss
    anchors; deactivation/page-hide (A087–A092) → page-switch/cancel anchors with
    the shell wiring (`cancelGridInput(3)`) recorded in the reason; late accept
    (A102–A103) → inert-accept anchors; the 10 RETIRED rows stand.
  - ccdeleteconfirmation: initial-Cancel-focus rows (A010, A067, A075, A091,
    A139) → the `:5840` anchor; rendered-button rows (A011, A036, A142, A021–A022,
    A127) → real-click row/button anchors (`clickAutomationMenuRow`,
    `clearAutomationLane`'s Delete click); focus-return rows (A013, A042, A050,
    A064, A073) → new focus anchors; outside-press family (A052–A064) → new
    outside-right-press anchor; content rows (A012, A038, A046, A069) →
    message-digits anchor; stale family mounted halves (A074–A079) → stale-accept
    anchor; foreign-popup family (A090–A110) → spared-confirmation law: map
    user-reachable clauses to the underlay-absorption/outside-press anchors and
    record the programmatic-takeover deviation (fork invalidates, Swift spares —
    50b's binding seam design); rows pinning the native shared-session object
    model (QPointer/contentItem/popup-panel identity) retire as
    RETIRED-REPRESENTATION per the task-50 A170–A177 precedent; the 13 standing
    RETIRED rows stay.
  - automationtaptempo: A001 → activation anchors; A015/A060 → recompute anchor;
    A032, A050, A074 → new presenter anchors; A117–A121 → no-session/no-op
    presenter anchors (reset idempotence) with the disabled-canvas premise
    recorded; A130 → hidden-readout anchor; A131/A137 → count-free revision/
    history anchors (signal-spy counts have no Swift counterpart — deviation
    recorded); A160–A162 → hint-catalog anchors (stale "not ported" reasons
    corrected).
  - automationfixture: A002–A004, A007–A008, A011 → converted-window staging
    anchors (mount/render, input-bounds, focus-route); A005–A006, A009–A010 →
    staging anchors; A012 stays MATCHED.
- All four ledgers are deletion candidates: every row must land MATCHED or
  RETIRED-* (the C++ sources are already deleted — `31ea635f` recorded in the
  valueprompt/fixture headers). If any row cannot close, leave it open with its
  reason; do not force a mapping.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`, `deno task proof check
   --executed`, `deno task proof check --strict-mappings`.
2. If all four ledgers close: delete them in the closing commit and re-run
   `deno task proof check` (area census drops by 146).
3. Native smoke (desktop): open the automation drawer; right-click a Pan node →
   Set Value shows −64..63 in displayed units, typing 63 and Enter stores 127;
   Escape and clicking outside close without writes and focus returns to the
   plot; right-click a written lane's tab → Delete automation events → the
   question names the written count, Delete empties only that lane, Cancel/Return
   keep it; tap Tempo four times at ~300 ms — the readout shows a draft near
   200 BPM and, after two idle seconds, the song tempo adopts it as one undoable
   edit; hovering Tap and a ghost-able tab shows distinct hint texts.
