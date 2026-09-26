# Context

Event List visual parity with the QWidget app (user direction: rebuilt surfaces
must look like their QWidget counterparts). A side-by-side capture of the Swift
app and the fork-main QWidget build on `mus_route101`
(`/tmp/porydaw-swift-ref/b-event-list.png` vs `/tmp/porydaw-qwidget-ref/b-event-list.png`)
shows two verified defects on the mounted `EventListPage`:

1. **Theme never reaches the table.** `EventListPresenter.init` snapshots
   `EventListAppearance.roles()` from a default (light, vanilla) `GridPalette()`
   (src/swift/app/eventlist/EventListPresenter.swift:87-89). The shared session
   palette is later mutated in place by `ShellAppearance.apply`
   (src/swift/app/shell/ShellAppearance.swift:104-178), but the presenter's
   `appearance` map is never rebuilt, so a dark theme renders cream table rows.
   The role mapping also diverges from the original: fork-main
   `EventListController::rebuildAppearance` (`git show fceecd88:src/ui/songview/quick/eventlistcontroller.cpp`
   lines 141-185) uses theme roles `item_background`, `item_alternate_background`,
   `item_text`, `secondary_text`, `item_selected_background`, `item_selected_text`,
   `palette_outline`, `header_background/text/outline`, `button_*`,
   `scrollbar_handle*`, `tooltip_*`, `input_*`, `focus_outline`. In fork-main
   presets those resolve to preset `item`, `alternate`, `window_text`,
   `secondary`, `selection`, `window_text`, `outline`, `chrome`/`window_text`/
   `outline` (`git show fceecd88:src/ui/theme/presetcolors.h` lines 200-270).
   Swift today uses `rollBackground` and `windowBackground` for the two row
   fills (src/swift/app/eventlist/EventListMenus.swift:35-62).
2. **Summary column text differs.** Swift renders numeric summaries
   (`Note on 60, velocity 98`, `CC 7 = 100`, `CC 10 = 64`, `Voice 0`,
   `Meta 0x20`, `Meta 0x03 …`). The original formatter
   `eventlist::summaryText` / `metaSummary` / `metaName`
   (`git show fceecd88:src/ui/eventtabletypes.cpp` lines 16-72 and 181-221)
   renders `Note on C4, velocity 98`, `Note off C4`,
   `Note off C4 (velocity-0 note-on)`, `Poly aftertouch C4 = N`,
   `CC 7 Volume = 100`, `CC 10 Pan = c_v+0` (m4a CC classification and value
   formatting), `Voice 0 — fixture_loop (Sample)` (voice short name; plain
   `Voice N` when no name), `Channel aftertouch = N`, `Pitch bend +1024`
   (m4a bend formatting), `N payload byte(s)` for SysEx, and named metas
   (`Channel prefix`, `Track name "Route 101 lead"`, `Marker …` with
   ` — loop start`/` — loop end`, `Time signature 4/4`, `Tempo`, …; unknown
   metas `Meta 0x%02x`).

No proof ledger row pins these strings or colors; this is visual-parity work
under the plan's Global constraints, verified by checks plus capture comparison.

# Exact write set

- `src/swift/app/eventlist/EventListMenus.swift` — `EventListAppearance.roles`
  mapping only.
- `src/swift/app/eventlist/EventListPresenter.swift` — take the session palette
  and rebuild `appearance` whenever the palette changes (no second palette, no
  polling).
- `src/swift/app/ApplicationSession.swift` — construct/feed the presenter with
  the shared `palette` and re-publish on theme application; only the lines
  involved.
- The Swift file that formats event-list summaries today (find it:
  `grep -rn "velocity" src/swift/app/eventlist src/swift/core` for the summary
  builder; likely `EventListProjection.swift` in module `PorydawAppEventList`).
  If a voice short-name or m4a CC/bend formatter already exists in Swift
  (search `src/swift` for `shortName`, `m4aClassify`, `formatCcValue`,
  `formatBend`, `c_v`), reuse it; do not duplicate it.
- `src/checks/eventviews/EventListPageChecks.swift` — summary-string and
  appearance-role predicates.
- `src/checks/editorqml/tst_ShellEventList.qml` — one mounted predicate that
  the rendered row background under a dark theme is the palette's item color.
- Remove the two comment lines in `EventListEditing.swift:138-139`
  (`// The EOT sentinel …`) — AGENTS.md forbids code comments; no other edit to
  that file.

If the voice short name needs data not reachable from the event-list presenter
(the voicegroup slot names), stop and report the owner and the smallest
interface; do not add a second voicegroup lookup.

# Prerequisites

Task 19 checkpointed at `c47e83d2`. Task 21 writes `tst_EditorDrawer.qml`,
`automationpointmenus.swift`, possibly `EditorQmlTests.swift` — disjoint.

# Interface contract

- `EventListAppearance.roles(palette:)` maps: tableBackground←`menuBackground`
  (preset item), tableAlternateBackground←`alternateBackground`,
  tableText←`windowText`, tableSecondaryText←`secondaryText`,
  tableSelectedBackground←`tabSelectedBackground` (preset selection),
  tableSelectedText←`windowText`, tableOutline←`outline`,
  headerBackground←`chromeBackground`, headerText←`windowText`,
  headerOutline←`outline`; keep the existing button/scrollbar/tooltip/input/
  focus keys unless the original maps them differently (check lines 141-185).
  Verify every text/background pair meets WCAG AA (4.5:1) in all three presets
  using the existing `PaletteMath`/`GridPalette.contrastRatio`; if a pair
  fails, report it rather than substituting a color.
- Summary formatting reproduces `summaryText` exactly for every event kind
  listed in Context, including the em dash (U+2014) and `%n payload byte(s)`
  plural rule (`1 payload byte`, `2 payload bytes`).
- Checks assert the exact strings on the fixture (e.g. `mus_route101` rows:
  `CC 7 Volume = 100`, `Voice 0 — fixture_loop (Sample)`,
  `Track name "Route 101 lead"`, `Note on C4, velocity 98`, `Pitch bend +1024`)
  and the appearance roles after `ShellAppearance.apply` for
  `dark-neutral-high` (tableBackground == `#424242`) and `vanilla`
  (`#D2D0CA`). Contract-shaped messages; no pixel constants.

# Implementation steps

1. Write failing predicates first (summary strings, dark-theme table role);
   record the RED output.
2. Fix the appearance mapping and the palette-change rebuild.
3. Port the summary formatter, reusing existing Swift m4a/voice helpers.
4. Remove the stale comment in EventListEditing.swift.
5. Run the lanes below; report GREEN and exact predicate strings with file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:shell --filter shell-event-list --verbose`
- `deno task verify:shell --verbose` (all shell lanes; the palette feed touches
  ApplicationSession)
- `deno task verify:bridge`
- Controller visual acceptance: relaunch the Swift app per skill
  `porydaw-qwidget-reference-capture`, capture the Event List in the same theme
  as the QWidget reference, and list remaining differences.

# Visual parity

Counterpart: fork-main `fceecd88` `src/ui/songview/quick/EventListPage.qml`
(same QML as today apart from import renames), `eventlistcontroller.cpp`
`rebuildAppearance`, `eventtabletypes.cpp` formatters; reference capture
`/tmp/porydaw-qwidget-ref/b-event-list.png`. Out of scope here (list them in
the report if still visible): taller rows / wide Data column (PROPORTION),
chunk combo label `1: MIDI chunk` vs `Chunk 1 — Track 1`, Event List hiding
the drawer.

# Task-specific constraints

- No new UI, no new C++, no code comments, no pixel constants.
- One palette authority: the session's `GridPalette`; no copies cached beyond
  the published appearance map that is rebuilt on change.
- No proof ledger edits.
