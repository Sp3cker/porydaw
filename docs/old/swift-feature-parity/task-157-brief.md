# Task 157 brief — startup restores the saved tab recipe through the real session path

# Context

Lift §16's startup-terminal-order deferral for its consumer-visible half: what the user
sees when the app restores a persisted workspace recipe. The Swift owner exists and is
unexecuted by any check: `ApplicationSession.restoreStartup()`
(`src/swift/app/ApplicationSession+ProjectOpening.swift:23-28`) loads
`EditorViewStateCodec.loadTabs(store:)` and switches to the recipe's project;
`finishProjectSwitch` (`:101-146`) then restores tabs through
`WorkspaceTabRecipe.normalized(available:)` in saved order and reselects the saved
selection. The fork observed this through its publication deque's terminal ordering;
Swift has no event log, so the ordering rows retire as representation and the observable
restore contract is proved instead.

Selected **12 GAP rows (A018–A029)** in `src/checks/project/proof.workspace.txt`
(pinned revision `a7fcaa3e`), fork `ProjectWorkspaceTest::
startupLoadingLeadsReadyLeadsSongs_selectedFirstInOrder` (`src/checks/project/workspace.cpp:332-355`):

| Target A-ids | Fork lines / clause | Disposition after this task |
|---|---|---|
| A018–A022 | 332,337,338,339,342 — restore-start guard, three `SongName::create` guards, terminal wait | NATIVE-SETUP (fixture/staging guards, no A-ids on predicates) |
| A023, A024 | 349,350 — Loading is state index 0; Ready after Loading | RETIRED-REPRESENTATION (publication-deque positions; the main-actor restore has no event log) |
| A025 | 351 — the selected song's terminal follows Ready | MATCHED: the saved-selected song's tab is restored and selected |
| A026 | 352 — the second song's terminal follows Ready | MATCHED: the second saved tab restores |
| A027 | 353 — the missing song's terminal follows Ready | MATCHED: the missing label restores no tab and does not abort the restore |
| A028 | 354 — selected terminal before the rest | MATCHED: tab order equals the recipe order (selected first) |
| A029 | 355 — rest terminal before the failed one | RETIRED-REPRESENTATION (deque ordering of the failed terminal has no Swift observable) |

The fixture pattern is proven in `checkFailedProjectSwitch`
(`src/checks/workspace/session_io.swift:10-139`): isolated `PreferencesStore`, seeded
`WorkspaceTabRecipe` via `EditorViewStateCodec.saveTabs`, `ApplicationSession()` +
`configurePersistence()`, run-loop `until` helper, `hostClosing()` teardown.

# Exact write set

- `src/checks/workspace/session_io.swift` — one new `sessionStartupRestore(report:projectDir:)` scenario, invoked from `sessionOpenAndRecovery`; no `SessionChecks.swift` edit.
- `src/checks/project/proof.workspace.txt` — A018–A029 only.
- Conditional production repair, only if the journey exposes a real defect: `src/swift/app/ApplicationSession+ProjectOpening.swift` (`restoreStartup`/`finishProjectSwitch` restore leg only).

# Prerequisites

**Task 152 must be accepted/checkpointed first**: it is in flight and owns
`src/checks/project/proof.workspace.txt` (A084–A098) plus
`DocumentSession.swift`/`SharedBankState.swift`/`ProjectService.swift`/`bank_edits.swift`.
This task's rows and files are disjoint from 152's. Read sprint-3 §18 for shared
constraints.

# Interface contract

`restoreStartup()`, `WorkspaceTabRecipe` fields and `EditorViewStateCodec.saveTabs/
loadTabs` are consumed unchanged. The check seeds a recipe with
`projectPath = projectDir`, `orderedSongs = ["mus_session_test",
"mus_session_test2", "porydaw_missing_song"]`, `selectedSong = "mus_session_test"`,
then observes through the session: both available tabs open in recipe order
(`songTabs.tabs` order by label), the missing label yields no tab, the selected tab is
`mus_session_test`, `projectOpen` holds, and the persisted recipe still carries all
three labels (restore does not rewrite the recipe). Independent literal expectations
for order and selection; no read-back-as-expected comparisons.

# Implementation steps

1. Add the scenario beside `checkFailedProjectSwitch` reusing its store/session/teardown
   pattern; seeding or open failure fails the row without an A-id.
2. Drive `app.restoreStartup()` and settle on `projectOpen` plus the expected tab count;
   assert the ordered labels, the selection, and the missing label's absence (A025–A028
   predicates).
3. Assert the recipe is unchanged on disk after the completed restore.
4. Dispose A018–A022 as NATIVE-SETUP and A023/A024/A029 as RETIRED-REPRESENTATION with
   one-line reasons naming the deque; land A025–A028 MATCHED with their executed
   message anchors in the same commit.

# Acceptance predicate

A persisted recipe with an available song, a second song and a missing label restores
exactly the available tabs in order with the saved selection, through the production
restore path — no direct tab construction. Service-level execution is the real owner
here (no mounted surface is required for restore semantics).

Named checks under §18 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

# Task-specific constraints

Do not assert C++ event ordering, catalog-once publication, or any A030+ reconcile/
catalog clause — those deferrals stand. No workspace FIFO, no event-bus invention, no
`bank_edits.swift`/`DocumentSession.swift`/`ProjectService.swift` edits (Task 152's
files). `session_io.swift` stays cohesive: one scenario function, no helper extraction
into new files.
