# Task 103 brief — full drawer state survives reload, close and persisted poison

# Context

Own complete shared drawer/lane-state restoration and selected-tab reload, including playback teardown on the final close. This combines the mounted lifecycle with the persisted-state predicates it consumes; it does not reopen the parked project-sidecar boundary or recreate staged QWidget tabs.

Verified selection: **47 open rows (32 GAP + 15 PARTIAL)**:

- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` — 29 (14 GAP + 15 PARTIAL): A001, A006, A007, A009, A011–A018, A022, A023, A025–A029, A032–A041.
- `src/checks/workspace/proof.selftest_workspace.txt` — all 13 GAP: A008–A012, A019, A031, A033, A037–A041.
- `src/checks/workspace/proof.session.txt` — five GAP: A011, A012, A028, A033, A034.

Pinned matching C++ originals: lifecycle `b5815a6e23296a9cc48c85a201a2ce858b99aae9`; selftest workspace `8d10130da34cfa9e1912d22fb11cdd427173e0b2`; session `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea`, alongside fork `fceecd88`. Selected clauses are lifecycle ledger :32–354, selftest :64–301, session :120–136/:199–236. Lifecycle A004/A010/A031 and session A024/A042 are sidecar-directory snapshots and stay open, not retired or inferred from one MIDI fingerprint.

# Exact write set

- `src/swift/app/ApplicationSession.swift` — conditional existing persistence/adoption/full-state fanout repair.
- `src/swift/app/ApplicationSession+Tabs.swift` — conditional lifecycle/teardown repair.
- `src/swift/app/SongTabsController+Close.swift` — conditional reload/close selection repair.
- `src/swift/app/timeline/EditorViewStateCodec.swift` — conditional existing state codec repair.
- `src/checks/workspace/session_view_state.swift`
- `src/checks/workspace/editor_view_state_checks.swift`
- `src/checks/editorqml/tst_ShellTabs.qml`
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` — selected 29 rows only.
- `src/checks/workspace/proof.selftest_workspace.txt` — all open rows; delete after closure.
- `src/checks/workspace/proof.session.txt` — selected five rows only.

No ShellWindow, `tst_ShellWindow.qml`, key arbiter, DocumentSession, automation interaction/prompt, fixture-content, registration or project-store writes. The three original C++ sources were already deleted in `67544720`; only the completed selftest ledger is deleted.

# Prerequisites

All 91–98 and Group A's accepted checkpoint precede this task. Rebase mounted ShellTabs over 95 and preserve its input-target lifetime regressions. Consume 99's accepted selected-tab command behavior without editing its shell files; preserve 98's per-song/global-volume separation. Existing task-84 full state and task-89 document/bank binding remain contractual. Group B 106 alone owns shell key/prompt files.

# Interface contract

- Preserve `ApplicationSession.configurePersistence`, `updateEditorChrome`, `updateEditorLaneRange` and tab adoption (`ApplicationSession.swift:630–637,823–864,1092–1125`); `EditorViewStateCodec.load/saveChrome`, `load/saveLanes` (:72–109,134–144) remain the canonical persistence boundary. Do not add a second full-state object solely to compare old C++ structs.
- “Complete shared editor state” means all three section visibilities/heights, active drawer page and every lane member: global/per-lane height, lane ranges, empty lanes and ordered hidden lanes. Observe mounted chrome and active parameter ranges directly; observe retained lane members through authoritative domain reads after real application resize/close/reopen/startup transitions, not merely a standalone codec round-trip or a new state getter. Do not invent a second per-lane UI for retained settings metadata. The aggregate is the existing chrome+lane values, not the per-song camera. Fresh tabs retain canonical camera defaults; in-place reload preserves camera, track, cursor, grid division/triplet and Event List visibility.
- Persist malformed JSON, empty bytes, array JSON, wrong-typed text, arbitrary valid object and each malformed height boundary through the real CFPreferences/UserDefaults domain, synchronize, then reload through production. Invalid lane data defaults/clamps only its lane fields and leaves chrome unchanged; reads never rewrite poison. A subsequent real section-height mutation publishes canonical compact lane data together with the current complete chrome, and restoring the original state persists all of it. No plist-byte staging or byte-cache oracle.
- In-place reload keeps the selected song/tab identity and presentation while adopting a new ready document with cleared history; switching A→reloading B→A→B does not let completion steal the selected target or discard view state. Preserve `ReloadedTab`'s existing presentation scope (`SongTabsController.swift:132–154`) and actual visible Event List throughout the settled reload journey.
- A real play command advances the playhead before the final tab is closed; closing it stops transport and leaves zero tabs. Preserve page-release-before-retirement (`ApplicationSession+Tabs.swift:27–54,81–117`) and deactivation before row removal (`SongTabsController+Close.swift:117–148`), with no forced early release or delayed workaround.
- Retire lifecycle A001/A011/A012/A032 (native fixture prerequisites), A013–A018 (native seeded-field prerequisites), A022/A036/A039 (deleted pre-ready tab stages), A023/A027 (native timeline pointers), A029 (deleted event-list signal counter). Exactly **16 representation rows** accompany **31 behavior rows**. Visible state stability, restored values, active input and transport stop must execute; do not retire the underlying lifecycle outcome.

# Implementation steps

1. Extend `runEditorViewStateChecks` (`editor_view_state_checks.swift:7–266`) and `runSessionViewStateChecks` (`session_view_state.swift:7–290`) with exact combined-state and production poison/reload transitions. Their existing CFPreferences setup is reusable; replace touched plist-byte observation with authoritative domain reads, preserving behavioral literals.
2. Extend `test_sharedDrawerCloseAndReopen` (:859), `test_oFreshTabViewStateDefaults` (:1469), `test_qReloadPreservesViewAndClearsHistory` (:1569–1640) and final-close/playback journeys in `tst_ShellTabs.qml`. Use real tab, drawer resize and transport controls, not a new state-setting test API.
3. Fix only a demonstrated selected persistence/lifecycle divergence at the listed seams. RED may be absent. Preserve current shared-drawer versus per-song-camera separation and all existing dirty-close gates.
4. Map the selected rows from fresh execution, retire only the 16 named clauses and delete the fully closed selftest ledger in the proving change. Leave sidecar snapshots, staged binding A042 onward, session A017/A024/A042 and transport A062 untouched.

# Acceptance predicate

`SessionChecks.swift:24,43` registers codec and live view-state checks; `ShellQmlTests.swift:86–87` registers the actual mounted tab lane. Swift proves authoritative persisted/member state; shell-tabs proves real reload/close/reopen, active-page behavior, resize and final transport stop.

Controller-run on the settled group under sprint-3 §11 verification policy:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Require fresh `swiftcore-projectsession.json` and `shell-tabs.json` under `build/proof-evidence`. Full shell and full verify are mandatory, in addition to the mounted journey; each invoked process has a 175 s alarm and a 180 s ceiling after serialized lock acquisition.

# Task-specific constraints

Read sprint-3 §10 “Wave constraints and verification” and §11 “Inherited constraints and verification” as mandatory parts of this brief. They cover unique literal anchors, fixture-consumer boundaries, CFPreferences staging, honest absent RED, Swift 6.4/no new C++, two-line comments, base-font geometry, WCAG AA, keyboard priority, no `Qt.callLater`/idempotence guards/test seams, and approval before workarounds. All §11 exclusions remain unchanged.
The existing split of chrome keys and the compact lane blob is not itself a behavior gap. Do not migrate settings representation or add per-song camera persistence. Sidecar-directory snapshots remain blocked on project-store, not a new user decision.
