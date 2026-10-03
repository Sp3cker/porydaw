# Task 139 brief — failed open keeps the live project; recovery writes the path

# Context

Prove the Swift successor of the old workspace open authority: deliberate project-switch coordination in `ApplicationSession+ProjectOpening.swift` reads each candidate fully on a fresh service before any live tab is released, `failOpen` publishes a nonempty error without touching preferences, and `finishProjectSwitch` installs the candidate then persists the tab recipe (`ApplicationSession+Tabs.swift` `persistTabRecipe` → `EditorViewStateCodec.saveTabs` → `PreferencesStore`). There is no publication log and no loading gate: a deliberate open cancels a startup restore, while replacement adoption is serialized behind `activeReplacementTask`. Preserve this existing priority.

Selected **13 open rows (13 GAP + 0 PARTIAL)** in `src/checks/project/proof.workspace.txt`. The following is the closed row inventory; citations identify individual assertion-start lines, not the ledger file's line numbers.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A005, A006, A007, A008 | `src/checks/project/workspace.cpp:285,288,290,292` — failed terminal: error present and nonempty, no `lastProjectDir` write |
| A009, A010 | `src/checks/project/workspace.cpp:295,297` — recovery reopen reaches ready, path written |
| A011, A012, A013, A014, A015 | `src/checks/project/workspace.cpp:304,307,310,312,313` — failure retains prior root as still open |
| A016, A017 | `src/checks/project/workspace.cpp:317,325` — reopen ready with nonempty catalog, path written |

A003/A004 (`workspace.cpp:280,282`, second open while loading adds no state) stay GAP explicitly: Swift has no refusal gate or state log, so no equivalent claim is made; the live-project-undisturbed consumer is already proved by 138's atomic readiness publication.

# Exact write set

- `src/swift/app/ApplicationSession+Tabs.swift` — conditional, `persistTabRecipe` only if a divergence is demonstrated.
- `src/checks/workspace/session_io.swift`
- `src/checks/editorqml/tst_ShellOpenFailure.qml`
- `src/checks/project/proof.workspace.txt` — separate ledger writer only, selected rows above.

# Prerequisites

Accepted 131–138, including 133's `session_io.swift`/shell-open-failure surface, 135's isolated-preference contract and 138's atomic readiness/`DocumentSession` ownership. Rebase both check files on accepted state; preserve every prior predicate and message. `ProjectService+Songs.swift` `open(root:)` is consumed as-is (read-only).

# Interface contract

Keep the real coordination signatures: `requestProjectSwitch(path:label:)`, `failOpen(_:)`, `finishProjectSwitch(_:)`, `persistTabRecipe()` and the `ProjectService.open(root:)` boundary. On a copied fixture driven through the existing ApplicationSession harness (per `bank_sharing.swift`/`session_view_state.swift` patterns with `until` polling and a synchronized isolated `PreferencesStore`):

- Opening a missing root fails with a nonempty `lastSaveError`; live tabs, `projectRoot`, catalog and `projectOpen` are unchanged. Assert the effective persisted recipe's project path and complete tab selection remain the independently seeded values (or absent for a fresh session). Merely observing that the obsolete `lastProjectDir` key is absent proves nothing.
- Opening the staged root then completes: `settingsVoicegroups` equals the exact catalog literal derived from the checked-in fixture voicegroup config (nonempty by construction), and the persisted recipe carries `projectPath` equal to the staged root with the opened songs and selection.
- After a successful open, opening a missing root fails while the prior root is retained as still open: the prior song still opens with identical complete metadata (per the existing 133 listing-retention predicates, extended to the retained root).

`waitFor`/deque-index/`stateCount` mechanics are retired backend representation with no Swift counterpart; predicates assert published error, retained state, the exact catalog literal and preference values. The restore-failure empty-recipe clearing (`ApplicationSession+ProjectOpening.swift` startup path) is a separate deliberate policy and is excluded, not asserted either way.

# Implementation steps

1. Extend `session_io.swift` with the ApplicationSession-driven failed-open/retained-root/recovery journey on a copied fixture; assert the fixture-derived exact catalog literal and the nonempty failure message, never log sizes or event positions.
2. Extend the mounted `tst_ShellOpenFailure.qml` journey with the retained-live-tab and prior-project-usable observations after a real failed open; no fake popup or second dispatcher.
3. Repair only a demonstrated divergence in the recipe-persistence boundary; add no loading gate, stage enum or publication log, and do not alter open priority.

# Acceptance predicate

A failed deliberate open explains itself, writes no path and leaves the live project fully usable; recovery installs the complete candidate with its exact catalog and persists the path. `swiftcore-projectsession` executes the extended open-guard checks; `shell-open-failure` runs the mounted failed-open journey.

Under sprint-3 §16 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-open-failure --verbose
```

# Task-specific constraints

Only workspace A005–A017 are writable. A003/A004 remain GAP with the reason recorded above; never claim an equivalent refusal. Startup terminal ordering, catalog refresh/duplicate, plan keying, silent completions, reload midi/view/bound and the bank applied/hard-failure PARTIALs are sequenced follow-ons. Setup/restore calls remain fail guards, not passing assertions. Preferences go through synchronized CFPreferences/UserDefaults, never cached plist bytes. No C++ deletion. Read sprint-3 §16 for shared constraints, excluded rows and conditional native retirement.
