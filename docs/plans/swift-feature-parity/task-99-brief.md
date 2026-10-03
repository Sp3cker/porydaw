# Task 99 brief — fresh-tab input ownership and complete Copy/Solo routing

# Context

Own window commands on the selected, ready song: focus after opening/switching tabs, complete note/range Copy payloads and exactly-once Solo from chrome versus roll, with text Copy staying local. Task 103 consumes the accepted tab-input expectations; task 106 later extends prompt isolation without changing these command laws.

Verified selection: **48 open rows (34 GAP + 14 PARTIAL)** in `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt`:
A001–A005, A007–A015, A050–A052, A054–A073, A075–A085.
A006/A053/A074 are already closed and are not selected; task 91's range-time rows are excluded.

Oracle: `5f768e3401d74d5df185a6de5692595351156a9d:src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp`, alongside `fceecd88`. Selected clauses were read in ledger :57–272 and :481–809. Copy/Solo successor predicates S223–S226 resolve to `runEditRoutingChecks` (`session_edit_routing.swift:49–98`), not task 91's time-routing file.

# Exact write set

- `src/swift/app/EditorCommandRouter.swift` — conditional active command routing repair.
- `src/ui/shell/ShellWindow.qml` — conditional existing shortcut/focus arbitration repair.
- `src/checks/workspace/session_edit_routing.swift` — Copy/Solo portion only; preserve time-command checks.
- `src/checks/editorqml/tst_ShellWindow.qml`
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt` — selected 48 rows only.

No clipboard codec/native host, application/tab lifecycle owner, automation/velocity owner, fixture, registration or other ledger writes. This ledger remains open; no source/ledger deletion is planned.

# Prerequisites

Start only after all 91–98 land. Rebase router and mounted shell check over 91, and shell keyboard/focus/check changes over 95; preserve 97's pointer-focus ingress and 98's toolbar Space priority. Group A 102 owns document/selection remapping, not this router. Group B 106 may reuse ShellWindow/check files only after the accepted Group A checkpoint; 103 owns lifecycle elsewhere.

# Interface contract

- Preserve `EditorCommandRouter.isAvailable`, `route` and `perform` (`EditorCommandRouter.swift:44–93`) and the existing window-scope `Shortcut` authority (`ShellWindow.qml:226–247`). No second dispatcher, synthetic forwarding or focus memory.
- Two real songs produce two distinct ready pages; completion of one open never routes editing to an inactive document. Real tab selection makes the displayed editor receive input, while persistent chrome retains its intentional focus until the user enters the editor. Swift installs a tab only after loading (`SongTabsController.swift:338–343`); do not recreate the old staged not-ready `SongTab` solely for a test.
- With the drawer hidden and roll active, actual registered Copy executes once and leaves song bytes/history/dirty state unchanged. The copied selected note has the source ticks-per-beat, zero clip span, exactly one track and one note with exact key and velocity. A selected time range instead produces its precise span and source ticks-per-beat, without falling through to note-only Copy.
- A real production text editor selects and copies `copy probe`; native text Paste restores those exact bytes and window Copy remains inactive. Use an existing production prompt, not a newly created fake TextField or new clipboard getter. The existing host text path can be observed by clearing and pasting into that same production field.
- Actual Solo from non-text chrome toggles the active track on/off, then the roll does the same. Each delivery activates the existing window shortcut exactly once; the previous mix returns after each pair, inactive-song state is untouched, and a text-field Solo key never leaks. Reuse the real mounted shortcut spies and header state (`tst_ShellWindow.qml:583–671`), not QAction counters.
- Retire exactly A001/A003/A050/A052/A073 (native session/note/pointer fixture prerequisites), A004/A005 (deleted pre-ready tab stage), A008/A011/A014 (QWidget tab-bar focus identities), A051 (QAction pointer), A056/A080 (native focus-widget existence prerequisites). These **13 representation rows** accompany **35 behavioral rows**. A007's mounted activation and A010/A013/A015/A057/A081's actual input-target outcomes must execute; no physical-macOS focus claim is made.

# Implementation steps

1. Split the missing Copy payload and Solo state conjuncts into independently anchored checks inside `runEditRoutingChecks` (:49–98), preserving existing aggregate messages and all time checks below them.
2. Extend the existing real two-song QML journeys `test_cWindowShortcutsAndNumericOwnership` (:568–743) and `test_dCopyFromOneSongTabPastesIntoAnother` (:782–855). Observe actual ready-page/input behavior and Copy/Solo outcomes through physical test key delivery, with exact clip semantic clauses also proved by Swift.
3. Replace any newly touched fake text/non-text target setup with the already mounted production editor/chrome appropriate to the selected law. Do not add a test seam to expose clipboard fields already available to `GridClipboard.read()` in Swift.
4. Fix only demonstrated router/window divergence; RED may be absent when existing production already matches. Map only selected rows using executed same-change evidence and the 13 bounded retirements.

# Acceptance predicate

`SessionChecks.swift:89` registers `runEditRoutingChecks`; `ShellQmlTests.swift:60–61` registers `shellwindow`. Swift proves each complete clipboard field and active/inactive state, and QML proves actual tab/key/clipboard-text ingress and exactly-once shortcut delivery. Neither lane substitutes for the other.

Controller-run on the settled group under sprint-3 §11 verification policy:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Require fresh `swiftcore-projectsession.json` and `shellwindow.json` under `build/proof-evidence`. Full shell and full verify are mandatory, in addition to the mounted journey; each invoked process has a 175 s alarm and a 180 s ceiling after serialized lock acquisition.

# Task-specific constraints

Read sprint-3 §10 “Wave constraints and verification” and §11 “Inherited constraints and verification” as mandatory parts of this brief. They cover unique literal anchors, fixture-consumer boundaries, CFPreferences staging, honest absent RED, Swift 6.4/no new C++, two-line comments, base-font geometry, WCAG AA, keyboard priority, no `Qt.callLater`/idempotence guards/test seams, and approval before workarounds. All §11 exclusions remain unchanged.
Keep every task-91 time-command predicate and 95 local-capture predicate intact. Native clipboard text is observed through real copy/paste, not clipboard source text or a mock echo.
