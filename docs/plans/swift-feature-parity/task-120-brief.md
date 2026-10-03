# Task 120 brief — Event List filter and cell gestures finish without hidden edits

# Context

Complete the existing mounted Event List chrome/filter/raw-edit journey and its remaining font/editor-close conjuncts. This adds no event gesture or popup authority. No later wave task consumes a new interface.

Verified planning selection: **13 open rows (0 GAP + 13 PARTIAL)**. This is the in-flight §13 census, not a completion claim.

- `src/checks/eventviews/proof.chrome.txt` — A016, A018, A071, A073, A075, A078, A079, A080, A084, A106, A116, A132.
- `src/checks/eventviews/proof.edits.txt` — A196.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `9f1bdd1b021196289b916074dd8eda12e80b7cc2`, `a1244957bb05a59d62b8912e053d49b2a6f3d771`. Read selected expressions with `deno task proof sites` / `show`; deleted C++ check paths are references, never write targets.

# Exact write set

- `src/swift/app/eventlist/EventListPresenter.swift`
- `src/swift/app/eventlist/EventListEditing.swift`
- `src/ui/songview/quick/EventListPage.qml`
- `src/checks/eventviews/EventListPageChecks.swift`
- `src/checks/eventviews/EventListPlayheadChecks.swift`
- `src/checks/editorqml/tst_ShellEventList.qml`
- `src/checks/eventviews/proof.chrome.txt`
- `src/checks/eventviews/proof.edits.txt`

Closed list: production writes are limited to the interface below. The implementer owns code/check files; the separate ledger writer alone owns the listed proof files after evidence settles, in the same surface change.

# Prerequisites

The preceding wave and Group A checkpoint settle first. Preserve 106/113 local-input routing; consume the current production EventListPage and ShellWindow dispatcher without editing either shared command owner.

# Interface contract

- A016/A018 inspects the instantiated tick editor’s actual resolved family and absolute pixel tracking, not just its parent’s font binding. Expected family/tracking derives from the captured base font and typography contract, never the editor itself.
- After filter-menu Escape, the mask is unchanged (A071); bare cell selection leaves editing closed (A073). A075/A084/A116 must actually target the Data-column cell at the original row, not a generic table rectangle or neighboring column. Use actual delegate geometry solely for input placement.
- On the filter-menu cell press, compare the original cursor, closed editor and unchanged mask at that press boundary (A078–A080). After the outside right press and its paired release, compare cursor again (A132); menu non-reentry alone is insufficient.
- The rendered raw insert produces exactly revision+1 (A106) and retains the existing single Undo outcome. Drawer focus loss commits the existing editor transaction and leaves the actual editor closed (edits A196), anchored by a complete unique message rather than a bare tryCompare. Retain all existing literal messages unchanged.
- Repair only demonstrated presenter/edit/focus divergence in the existing owners; do not add QuickPopupSession, synthetic menu callbacks or event injection APIs. These thirteen rows are behavioral; locating a cell is part of real input delivery, not a new setup-only test.

# Implementation steps

1. Extend the existing shell-event-list journeys at press, Escape, release, raw insert and focus-loss boundaries with independent snapshots.
2. Complete the registered Swift revision/editor state conjuncts where full domain state is required, paired with the same mounted fixture.
3. Repair only selected production divergence and hand executed anchors to the separate ledger writer; delete chrome/edits ledgers only when both full inventories are closed.

# Acceptance predicate

shell-event-list executes every actual cell/key/menu/editor transition; registered Swift predicates establish exact revision/history consequences. All thirteen selected conjuncts have individual executed message anchors.

The implementer runs these exact covering lanes under §13’s build-lock policy; the controller runs the settled-group full gates:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-event-list --verbose
```

# Task-specific constraints

No registration, ShellWindow, local-input arbiter, ApplicationSession, core raw-event or fixture edits. Theme and header tasks have distinct files; do not borrow their font assertions as proof of this editor’s resolved font.

Read sprint-3 §13 “Evidence and execution contract” as part of this brief: real input; independent expectations; no setup-only assertions; exact raster colors/positions and executed DPR2 where claimed; no shell dispatcher in editorqml; verbatim existing and unique complete new messages; all exact-content fixture consumers updated; copied-fixture isolation for shared bank leases; implementer-owned locked lanes; separate ledger writer.
