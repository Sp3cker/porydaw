# Swift keybindings port

## Global Constraints

Port old behavior, not QWidget structure. No new C++ files or code. No shims or legacy-registry routing fallback. Reuse existing visual QML; new shell/input/menu QML is authorized where the old implementation was Widgets. Every new check copies an old C++ fixture, sequence and observable assertion. Every implementation responsibility maps to old checks; unmatched code must be necessary Qt-access glue and explicitly justified. Do not claim MATCHING before controller verification. Preserve the original proof context. Shared-tree implementers perform file-local read-only inspection but defer all builds, tests, formatters and linters to Main. Every tool timeout is at most 300 seconds. No agent commits. No unrelated source-worktree list changes are included.

## Review synthesis

Native Registry owns fixed catalogue, standard-key resolution, alternate sequences, matching masks, hold chords and window/editor scope. Swift EditKeyArbiter already ports semantic routing: reuse it. Native RewriteWindow currently resolves keys before Swift; leaving that path active would be a shim. Replace the executable shell with Swift/QML rather than reproduce QWidget infrastructure. Qt Quick native shortcuts remain event-delivery machinery; catalogue and policy belong to Swift. Native editor-local and window delivery must never both execute one command.

The user approved dependency alignment: base cdac8c53, worktree feature/swift-keybindings, gitlink-only commit 60167ce4. build:app passed on the aligned base.

## Tasks

- Registry: SDD-track, Swift catalogue and Qt-standard sequence resolution. Consumer: Swift shell command routing.
- Registry checks: SDD-track, exact keyboard/keymapregistry.cpp assertions and proof ledger, using Registry interface.
- Shell presentation and routing: SDD-track, Swift semantic command ownership; contracts finalized with expanded plan review before dispatch.
- Shell QML and lifecycle: SDD-track, replace native delivery using proven behavior, reuse existing song-tab/editor visuals.
- Entry and build integration: SDD-track, Swift application entry, resource registration, controller-run checks.
- Final proof and whole-port review: controller verification plus independent review.

## Registry interface

Public KeybindingScope enum: window, editorRouted. Public KeybindingSequence value: strokes: [Int], portableText: String, nativeText: String. Public KeybindingRegistry value with init(), label(_ id: String) -> String, scope(_ id: String) -> KeybindingScope, sequences(_ id: String) -> [KeybindingSequence], modifierBinding(_ id: String) -> Int, matchesModifier(_ modifiers: Int, _ id: String, allowShift: Bool = false) -> Bool, singleStroke(_ id: String) -> Int?, matches(_ key: Int, _ modifiers: Int, _ id: String) -> Bool. IDs and catalogue order come verbatim from keymap.cpp; expose ids: [String] for shell registration. Keys/modifiers use Qt integer values, not a new physical-key mapping. Resolve platform StandardKey bindings through existing Qt APIs using Swift C++ interoperability; no hard-coded replacement platform binding table. Module-map declarations importing existing Qt headers are build configuration, not new C++ code.

## Verification

Controller runs deno task build:app and deno task verify --filter swiftcore --verbose for integrated registry checks. Current keymapcheck is not registered; do not cite it as a runnable gate. Native/window and new-shell gates are selected from the expanded review before those task briefs are frozen. Final proof updates include exact commands and observed output, never inferred passes.

## Verified prototype and final rulings

- Live Swift QApp shell loaded the original qrc SongTabs with mus_littleroot_test. Native Cmd+Shift+E activated once; text Copy/Space stayed local; original DragInput yielded Space twice to transport. Host closing, scene removal, detach acknowledgement and process exit 0 were observed.
- Qt key sequence access from Swift compiled and ran inside that live application: Copy resolved to Ctrl+C plus the alternate Copy key; Up/Delete/Backspace parsed through Qt. Resolve these only after GUI startup. Unavailable imported enum cases use typed raw values verified against installed Qt headers, not a replacement binding table.
- Direct QSettings/QGuiApplication construction was unavailable to Swift. Genuine QtCore.Settings in the new QML test lane must reproduce the four native settings seeds before asserting registry immunity. No mock or claim of equivalence without that fixture.
- Original global Application.font.pixelSize reads are invalid under the new QApp host. Thread a positive resolved font through reused QML rather than suppress warnings.
- Scope is every existing Swift-enabled production target: currently APPLE only, as demonstrated by root CMake's Swift language/subdirectory gate. Other platform/toolchain ports are not introduced. The Swift app has no native-shell fallback; non-Swift builds remain unchanged.
- ShellPresenter additionally publishes windowActionIds so QML does not duplicate Swift scope policy. New shell test lane derives from native mainwindowrouting/selectionkey checks and exercises the actual production QML shell.

Integrated gates: `deno task build:app` compiles the real Swift entry; `deno task verify --filter swiftcore --verbose` runs retained core/session checks plus registry assertions; `deno task verify:shell --verbose` exercises the production shell with native-derived key/settings/tab/lifecycle fixtures. The shell lane follows the existing standalone Qt Quick Test manifest and Deno task pattern. It is offscreen and does not consume desktop authorization. `deno task verify:qml --verbose` runs the existing editor-QML reference checks without changing their baselines.

## Final review and verification

Whole-port spec/quality review approved the implementation. Independent proof review approved after correcting four evidence/isolation descriptions; no permanent test was weakened. The current registry proof maps all 13 native assertion sites (28 expanded predicates). The shell crosswalk deliberately retains its named native-platform and identity gaps.

Controller gates passed: `build:app`, `verify --filter swiftcore --verbose`, `verify:shell --verbose --qt -v1` (five Qt Test slots, no failures), and `verify:qml --verbose` (all four retained DPR/font profiles, no rebaseline). `deno task format --check tools/cli.ts` passed after applying the formatter. `deno task lsp:swift` indexed all eight targets. No C++ source/header was added or modified. Temporary prototypes and extra integration scenarios are absent from the deliverable.

Responsibility map: KeybindingRegistry owns the fixed catalogue and Qt sequence conversion; ShellPresenter owns command and lifecycle policy; ShellAppearance owns native theme projection; PorydawShellApp/PorydawApplication own entry and Qt metadata access; ShellWindow renders menus/dialogs and delivers Qt events. Existing editor components retain visual ownership. GridScene.swift (734 lines) is an **accepted exception**: the existing scene-projection module receives only narrow palette-role consumption changes, not a new responsibility. No other changed source file exceeds 600 lines.

### Deferred observations, adjudicated

- Registry conversion/index widths follow imported Qt signatures. The Qt-free public value API keeps conversion at one boundary; no extra wrapper is needed.
- Unknown-id lookups preserve empty/false results where native APIs have counterparts. The plan-only scope lookup traps on programmer misuse; all internal callers use known catalogue ids.
- Appearance roles are copied from presetcolors.h and themeresolver.cpp, including menu hover, active foreground and disabled/velocity-zero roles.
- CLI error handling is not claimed equivalent to QCommandLineParser. Its lenient treatment of malformed/unknown options remains a reviewed non-blocking gap, outside the native keybinding proof.
- Cancellation integers are the existing TimelineInputCancelReason order: FocusLost 0, PointerUngrabbed 1, Hidden 2, WindowDeactivated 3.
- Separator insertion follows native File `[open, openSong, separator, save, quit]` and Edit `[undo, redo, separator, grid actions]` order.
- Body font scaling is the native `max(1, round(base * 1.125))` typography policy.
- Separate shell Connections blocks handle disjoint signals; merging them would be cosmetic, so they remain.
- Qt Quick activeFocus is not QApplication::focusWidget identity. The proof names that boundary and checks the original routed effects.
- Shortcut sequences are immutable after first resolution under the live GUI application; QML therefore needs no mutable-binding notification layer.
- Qt6::Gui PUBLIC linkage carries the serialized Clang-module/header dependency to downstream Swift consumers, consistently with the existing PUBLIC interop compile options.
- Missing bundle version remains a loud invariant failure, not a fabricated fallback version.
- The original-editor-qrc comment is correct: whole-archive linkage retains those resources; fonts.qrc is separately linked into the executable.
- No unused shell modulemap declaration remains; the generated QtKeybindings module map is consumed through the app's interop options.
- Pre-GUI help is not duplicated in one executable: Swift owns the Apple entry, while main.cpp remains the non-Swift entry.

Physical Cocoa menu/key-equivalent behavior is source-verified but not exercised by the final offscreen runs. Existing Qt font-size/importer/linker warnings are not suppressed.
