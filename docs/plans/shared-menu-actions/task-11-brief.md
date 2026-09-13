## 1. Context

Standalone Quick and SongTab fixtures lack MainWindow but need real action identities for menus as well as keys. Task 10 supplies binding; this uniform migration makes the later action-row and keyboard cutovers executable without fake actions.

## 2. Exact write set

- `src/checks/support/editorrig.cpp`
- `src/checks/support/songfixture.cpp`
- `src/checks/rollcheck.cpp`
- `src/checks/automation/automationfixture.cpp`
- `src/checks/automation/raster/rasterfixture.cpp`
- `src/checks/clipboard/clipcheck_fixture.cpp`
- `src/checks/drawerpresentation/fixtures.cpp`
- `src/checks/drawerpresentation/velocity.cpp`
- `src/checks/eventviews/eventview_fixture.cpp`
- `src/checks/pitchbend/fixture.cpp`
- `src/checks/rollcheck/static/fixtures.cpp`
- `src/checks/rollcheck/static/geometry.cpp`
- `src/checks/rollcheck/identity.cpp`
- `src/checks/rollcheck/remap.cpp`
- `src/checks/scrollbar/tst_scrollbar.cpp`
- `src/checks/timelinepan/timelinepanfixture.cpp`
- `src/checks/trackheaders/trackheaderfixture.cpp`
- `src/checks/trackheaders/trackheaderinput.cpp`
- `src/checks/trackheaders/tst_trackactivitymeter.cpp`
- `src/checks/trackheaders/tst_trackheadermodel.cpp`
- `src/checks/velocity/tst_velocityediting.cpp`
- `src/checks/host/tst_hostseams.cpp`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp`

Mechanical exception: Every listed file receives the same construction-only operation at each standalone SongView/SongTab root: construct production EditActions parented to the view and rebind it before command-bearing interaction. No fixture assertions or input semantics change.

## 3. Prerequisites

- [Task 10](task-10-brief.md).

## 4. Interface contract

Every standalone constructed view in this closed list has exactly one production EditActions parented to it and rebound to it. MainWindow-based fixtures use the production window owner and must not create another set.

## 5. Implementation steps

1. At each standalone construction in the listed files, include the production action header, create the real action set parented to the view and rebind before showing or exercising commands; cover multiple roots in the same fixture file.
2. Preserve existing document/timeline staging order, ownership and geometry. QObject-parent the set rather than introducing fixture header members or alternate command callbacks.

## 6. Acceptance predicate

All standalone fixtures retain real menus and editing behavior with the production action implementation; native MainWindow fixtures have no extra owner. Named checks: `deno task verify --filter selectionkey --filter rollcheck --filter automation --filter eventviews --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not make binding conditional on whether a fixture currently sends shortcut keys: context menus also consume actions. Do not register Window shortcuts or synthesize forwarding in unhosted rigs.
