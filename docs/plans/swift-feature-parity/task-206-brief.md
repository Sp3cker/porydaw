# Task 206 brief — the mounted event-list stripe and the shipped-theme enumeration close the themelayout residuals

# Context

Two themelayout residuals are closable on mounted surfaces under the
wave-26 rulings:

- `settings` A019 (`tst_themelayout_settings.cpp:178` at `97dc7fea`):
  the fork's event table colors row 1 with
  `themes::Role::item_alternate_background`. The parked note claims
  GridPalette exposes no alternate surface — stale. The real
  replacement surface exists: `EventListCell.qml:72` paints odd rows
  with `page.tableAlternateBackground` inside the mounted
  `EventListPage`, and `tst_ShellEventListPresentation.qml` already
  mounts that page on the `shell-event-list-presentation` lane.
  Predicate: read the mounted row-1 cell delegate's stripe color and
  require `Qt.colorEqual` against `session.palette.alternateBackground`
  (and, in the same test, row 0's stripe against
  `palette.menuBackground`) — a positive observation of the rendered
  surface, MATCHED.
- `color` A038 (`tst_themelayout_color.cpp:205`): S020 in
  `ThemeColorChecks.swift` is the fork's else branch — contrast-100
  grid luminance above the default when the default sits above the
  roll surface — but no shipped preset reaches it. Under the new
  ruling an RR refusal must positively observe the real replacement
  surface: enumerate the shipped themes in `ThemeColorChecks.swift`
  and assert for each that its default grid luminance sits at or below
  its roll surface (the else-branch precondition never holds over real
  theme data). Closes RETIRED-REPRESENTATION — the fork clause is
  unreachable on every shipped preset, observed positively, not by a
  `!("prop" in obj)` tautology.

Surface: the mounted `EventListPage`/`EventListCell` stripe and the
shipped `GridPalette` theme data.

Ledger spec: `themelayout/proof.tst_themelayout_settings.txt` A019
(1 PARTIAL → MATCHED); `themelayout/proof.tst_themelayout_color.txt`
A038 (1 PARTIAL → RETIRED-REPRESENTATION). A039 stays PARTIAL (sample
editor unported, P4).

Verify lanes:
`deno task verify:shell --filter shell-event-list-presentation --verbose`
and the lane that runs `ThemeColorChecks` (confirm its entry name in
`EditorQmlTests.swift`/`ShellQmlEntries.swift` — likely a themecolor
entry on `verify` or `verify:shell`).

Blocked rows left untouched: settings' theme-dialog/QHeaderView/
native GAP family and color A039 (sample editor, P4).

# Exact write set

- `src/ui/songview/quick/EventListCell.qml` — give the background
  stripe Rectangle a stable id (e.g. `rowStripe`) so the lane can read
  its `color`; no behavioral change.
- `src/checks/editorqml/tst_ShellEventListPresentation.qml` — extend
  `test_eventListRowsFollowAppliedTheme` (or a sibling test in this
  file) with the row-1/row-0 stripe color predicates via the existing
  `cellAt(table, row, column)` helper.
- `src/checks/themecolor/ThemeColorChecks.swift` — the shipped-theme
  enumeration refusal for A038.
- `src/checks/themelayout/proof.tst_themelayout_settings.txt`,
  `src/checks/themelayout/proof.tst_themelayout_color.txt` — the
  closed rows only.

# Prerequisites

Read sprint-3 §26, the fork sites at `97dc7fea`
(`tst_themelayout_settings.cpp:178`, `tst_themelayout_color.cpp:205`),
`EventListCell.qml:55-75`, `ShellEventListSupport.qml`'s `cellAt`
helper, and `ThemeColorChecks.swift:355-380` (S020's else-branch
context). Confirm the theme list the lane iterates is the shipped set
(vanilla, dark-neutral-high, immaterial) before writing the refusal.

# Interface contract

One predicate per fork clause with its unique complete literal; each
A-id on exactly one predicate; expectations independent of production
projections; real mounted ingress only; fail-closed staging. The
stripe id names an existing rendered surface — no new production
properties for the check's sake.

# Implementation steps

1. Add the stripe id to `EventListCell.qml`; add the row-0/row-1
   stripe predicates to the mounted event-list lane; close A019.
2. Add the shipped-theme enumeration refusal to `ThemeColorChecks.swift`;
   close A038 RR.
3. Close both rows across the two ledgers, same commit.

# Acceptance predicate

The mounted event-list lane and the themecolor lane execute the new
predicates; `proof check` 0 errors.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-event-list-presentation --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-26 writer of both themelayout ledgers, `EventListCell.qml`,
`tst_ShellEventListPresentation.qml` and `ThemeColorChecks.swift`. Do
not touch the voicegroup or rollcheck ledgers (207/208), any
`Shell*Support.qml`, or `themelayout` GAP rows (theme dialog,
QHeaderView, native family).
