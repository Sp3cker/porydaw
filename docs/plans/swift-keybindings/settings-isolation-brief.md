# Native settings isolation

Owner: Main. This corrects the shell-proof fixture before acceptance; it does not add a scenario or alter production settings.

## Problem and contract

The original `themelayout/tst_themelayout_color.cpp::settingsRepair` has a private QTemporaryDir/INI store. The new shell fixture uses genuine QtCore.Settings but shares `com.sp3cker.porydaw` with running applications. One run observed 96 after seeding 80; its specific writer is unproven. Shared user state is independently an invalid fixture boundary. Snapshot/restore cannot prevent concurrent writes. A throwaway native-domain probe showed CFFIXED_USER_HOME does not isolate current macOS preferences; do not use it.

Application metadata belongs to executable startup, before settings creation, not to the reusable ShellWindow. Production retains application `porydaw`, organization `sp3cker`, empty organization domain. The test executable uses a fresh application name in that organization, retaining the actual native backend. Legacy-key removal follows the active application name in the same prescribed organization. No fake Settings, production test hook, new C++, default-value workaround, or second storage mechanism.

Verified Qt-access constraint: importing public qcoreapplication.h failed because QCoreApplication lacks a copy/move constructor; Swift cannot access even its static metadata methods (compiler evidence artifact://256). That attempted module/header change is removed. A small QML application Loader uses the existing public Qt.application API before constructing ShellWindow. This bootstrap is necessary Qt access, not a second shell controller or fallback.

## Exact write set and changes

- Root `CMakeLists.txt`, `src/swift/app/shell/PorydawShellApp.swift`, and new `src/ui/shell/PorydawApplication.qml`: bundle/select the application bootstrap; set the three unchanged metadata values before loading ShellWindow. Keep its lifecycle under the existing QApp and Loader ownership.
- `src/ui/shell/ShellWindow.qml`: remove metadata mutation; retain lazy Settings loading and restoration/startup ordering.
- `src/swift/app/shell/ShellPresenter.swift` and `ShellAppearance.swift`: QML supplies Qt.application.name to restoreAppearance; derive the CFPreferences application identifier from that value, retaining the prescribed `com.sp3cker.` prefix and exact legacy removals.
- `src/checks/editorqml/ShellQmlTests.swift` and `tst_ShellWindow.qml`: use a fresh native application name; remove the user-domain snapshot/restore machinery and clean only the private domain. Preserve all seeds, operations, assertions and genuine Qt Settings reads.
- Update the existing shell contract/proof evidence to name startup ownership and fixture isolation after verification.

## Preservation and verification

No registry policy, command scope, keyboard routing, action enabledness, theme values/formulas, project lifecycle or retained editor visual changes. The only new resource is the necessary application bootstrap. No tools/run_checks.ts change.

Controller commands: `deno task verify:shell --verbose --qt -v1` covers original seeds/repair and real routing assertions; `deno task build:app` proves the production entry/resource integration; production offscreen startup proves metadata is established before Settings and the Loader creates the real window. Compare real application domain before/after the isolated lane using a throwaway read-only snapshot; remove the snapshot after equality is established. Recompute proof hashes. Review this correction with the shell-proof and final whole-port gates.

Observed isolation evidence: the production domain's read-only exports were byte-identical (3520 bytes) before/after the passing private-domain lane; no production preference was written by that comparison. The private store also exposed the original drawer fixture's previously implicit dependency: openTwoSongShell now copies velocity visible/height 173, automation hidden, voice changes hidden, active velocity page, and the exact empty automation-lane JSON from mainwindowroutingfixture.h/editorviewstate.cpp. Absent nullopt height keys stay absent. No expected selection assertion was weakened.
