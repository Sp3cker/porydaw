# Context
R27, link-warning portion: production QML lane links repeatedly report `ld: warning: ignoring duplicate libraries: 'lib/libQtBridge.a', 'src/swift/app/libPorydawApp.a'`. Route: SDD-track, Qt/CMake-heavy Implement mode, SHARED_TREE. Base: `86c88903661ee6d44a77da505bf4b9fef777f6e0`. Read plan.md Global constraints and linked spec.md. Fonts, zero-pixel initialization and QML lint remain separately pending within R27; do not hide those obligations or expand this write set into UI owners.

# Exact write set
- src/checks/CMakeLists.txt
- src/swift/app/CMakeLists.txt
- CMakeLists.txt

Only dependency/usage-requirement declarations necessary to remove the duplicate QtBridge/PorydawApp library inputs are authorized. Existing source membership, check registrations, resources, target names, language versions, platform gates and compiler/Swift module-map contracts remain unchanged. Do not edit `cmake/QtBridge.cmake`, its patch files, QML or Swift source. These files have no earlier task's uncommitted writes.

# Contract
Use one correct CMake dependency graph, preserving each consumer's compile-time Swift modules/macros/Clang imports and link-time native/Swift symbols. Keep whole-archive resource/@main retention and Linux Swift autolink/runtime handling. Preserve the Linux Qt-main executor integration from c47b55f4 verbatim. No duplicate-warning suppression flag, linker warning filter, missing-library fallback, platform support downgrade or hidden manual build prerequisite.

# Steps
1. Trace the actual generated link inputs for editor_qml_tests, roll_qml_tests and shell_qml_tests through their lane archives, PorydawApp, QtBridge and porydaw_app. Distinguish redundant explicit edges from required Swift autolink/usage requirements before editing.
2. Remove the redundant ownership at the responsible target declarations; do not rely on the linker silently ignoring duplicates. Keep required PUBLIC/PRIVATE propagation explicit and boring. If a genuine toolchain limitation requires a workaround or broader redesign, report the precise prerequisite instead of suppressing it.
3. Inspect resulting declarations and references; report why every removed edge remains transitively satisfied. No comments added; delete stale comments only in touched constructs.

# Acceptance
Controller runs serially after both writers freeze:
- `deno task build:app`: app, @main, resource and runtime link contracts remain valid.
- `deno task build:checks`: native/Swift check targets link.
- `deno task verify:shell --filter shell-chrome-visuals --verbose`: shell QML lane links and mounts the production surface.
- `deno task verify:qml --verbose`: editor lane links and executes.
- `deno task verify:qml-roll --verbose`: roll lane links and executes.
Inspect each relevant final link output: the duplicate QtBridge/PorydawApp warning must be absent, not filtered. Existing unrelated warnings remain visible and tracked in R27. Linux/Windows runtime qualification is unavailable on this host and must not be claimed.

# Shared-tree execution
Skip builds/tests/lint/formatters during implementation; report `DEFERRED_TO_CONTROLLER`. Generated build files may be inspected read-only; do not invoke CMake directly or alter the build tree. Perform prescribed local inspection and report unavailable CMake semantic tooling honestly. No commits, scratch reports or unrelated source changes. Qt pack self-review plus controller build evidence supplies the quality verdict; a task reviewer still gates spec compliance.

# Accepted result
App and check builds passed. The shell, roll and editor QML executables each actually relinked without the duplicate-library warning; shell chrome, roll and all four drawer profiles passed. No warning filtering or suppression was used. Qt-pack quality and independent task spec review approved. Fonts, zero-pixel initialization, QTP0004 and lint imports remain pending in R27; Linux/Windows runtime qualification is not inferred from these macOS gates.
