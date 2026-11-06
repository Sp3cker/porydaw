# Context
A plugin's own editor is its parameter surface. Open it in a separate top-level native `QWindow` in the helper; no QWidgets. Wire resize, scale and the Linux run loop, and expose open/close and user-close to Swift over control frames. Intercept Porydaw's play/pause keystrokes in the helper before the plugin view sees them (plan D6). Consumers: task 10 (`openEditor`/`closeEditor`, `isEditorOpen`, editor play/pause routing) and task 11 (panel surface). Read plan.md Global Constraints and spec.md "Native boundary" plus "Space and transport".

# Exact write set
- src/pluginhost/helper/editor.h (new): helper-private editor and shortcut interfaces
- src/pluginhost/helper/editor.cpp (new): QWindow, `IPlugFrame`, content scale, Linux `IRunLoop`, the editor-window registry
- src/pluginhost/helper/keys.cpp (new): Windows native event filter and X11 key grabs, plus Qt-stroke → platform-key mapping
- src/pluginhost/helper/editor_mac.mm (new): NSView handle extraction and the NSEvent local key monitor
- src/pluginhost/helper/host_control.cpp: editor and shortcut control-frame dispatch
- src/pluginhost/pluginhost.cpp: destroy closes an open editor first; the host context answers `Linux::IRunLoop`
- src/pluginhost/CMakeLists.txt: helper editor sources, OBJCXX for the `.mm` on Apple only, `Qt6::Gui`, X11 on Linux
- src/swift/pluginhost/PluginInstance.swift: `openEditor(title: String) throws`, `closeEditor()`, `isEditorOpen: Bool`, `onEditorClosed: (() -> Void)?`; `shutdown()` closes the editor at its spec position
- src/swift/pluginhost/PluginEditorShortcuts.swift (new, `@MainActor enum`): `static func install(strokes: [Int], onShortcut: @escaping @MainActor (Int) -> Void)`, broadcasting `SetShortcuts` through `HelperProcess` and delivering `Shortcut(index)` on the main actor
- src/checks/vstfixture/porydawtestgen.cpp plus new per-platform fixture views (a minimal native editor view): src/checks/vstfixture/porydawtestgen_view_mac.mm (NSView), src/checks/vstfixture/porydawtestgen_view_win.cpp (HWND child), src/checks/vstfixture/porydawtestgen_view_x11.cpp (X11 child window); src/checks/vstfixture/CMakeLists.txt selects one per platform
- src/checks/pluginhost/PluginHostEditorChecks.swift (new; `public func runPluginHostEditorChecks(_ report: CheckReport)`)
- `.github/workflows/build.yml` and `.github/workflows/release.yml`: `libxcb1-dev` in the Linux apt installs (`build-linux`, `asan-checks`; release `build-linux` gains an apt step on its ubuntu-22.04 runner), because the helper compiles against `xcb/xcb.h` for key grabs and Qt's install action ships no xcb headers

Registration (controller): new windowing suite `swiftcore-pluginhost-editor`, marked as a windowing check so `--no-windowing-checks` skips it.

# Prerequisites
Task 7 (`PluginInstance`, which owns the instance lifecycle this extends) and task 13 (`HelperProcess` and helper control frames).

# Interface contract
Exactly spec.md "Native boundary" editor half and "Space and transport", plus the mechanics below that the spec leaves open:
- **Open.** The helper handles `OpenEditor(title)` by creating the controller view (`createView(kEditor)`). A missing view returns `PDPH_ERR_NO_EDITOR`. The platform type is `kPlatformTypeNSView` (macOS), `kPlatformTypeHWND` (Windows) or `kPlatformTypeX11EmbedWindowID` (Linux, only when `QGuiApplication::platformName() == "xcb"`, else `PDPH_ERR_UNSUPPORTED_PLATFORM` with the message "Plugin editors need X11 (QT_QPA_PLATFORM=xcb)"). The view must support that type. Open then creates a titled, closable, non-resizable-unless-`canResize()` top-level `QWindow` without a cross-process owner at the view's `getSize`, calls `attached(winId-derived handle, type)` and shows the window. Swift `openEditor` while an editor is open sends `RaiseEditor` and returns normally.
- **Resize.** `IPlugFrame::resizeView` sets window geometry and calls `onSize`, guarded against recursive growth: a resize in flight is not re-entered, and a constrained size is applied only when it differs (JUCE: "This can cause the window to unexpectedly grow while it's moving."). Sizes are logical on macOS and physical (× `devicePixelRatio`) on Windows and Linux.
- **Scale.** `IPlugViewContentScaleSupport::setContentScaleFactor(devicePixelRatio)` runs on Windows and Linux at open and on screen change (JUCE).
- **User close.** Closing the window calls `removed()`, deletes the window and sends `EditorClosed`.
- **Programmatic close.** `CloseEditor` does the same without the user-close event.
- **Linux run loop.** `IRunLoop` event handlers map to `QSocketNotifier` (read) and timers to `QTimer`, all on the GUI thread, unregistered on removal — the same adapter as ossia, MuseScore and Qtractor.
- **Fixture editor.** A 320×200 native child view (NSView, HWND or X11 window, solid fill) that takes keyboard focus when clicked or attached, and counts every key-down it receives into component state `int32 LE keysReceived` at byte offset 8, the field reserved by task 6; `fault` stays at offset 12. Preserve decoding of 8-byte and 12-byte legacy states with `fault = 0`. On `attached` it requests `resizeView` to 400×240, then performs `beginEdit`/`performEdit(Pitch Offset = 5 semitones)`/`endEdit`.
- **Key interception.**
  - Scope: `SetShortcuts` replaces that helper's stroke set; an empty set disables interception. A key event matches when its window is an open editor `QWindow` or a descendant of one, its key equals the stroke's `Qt::Key`, and its modifier set equals the stroke's modifiers, ignoring Caps/Num Lock.
  - Delivery: the matching key-down sends `Shortcut(index)` once to Swift. That key-down, its auto-repeats and its key-up are swallowed; non-matching keys pass through untouched. Swift runs `ShellPresenter.activate(id: "transport.play_pause")`. Broadcast `SetShortcuts` to every live helper; send the current set to a new helper immediately after `Ready`.
  - macOS: `addLocalMonitorForEventsMatchingMask:(KeyDown|KeyUp)` returning nil for matches; installed once, removed when the set is empty.
  - Windows: a `QAbstractNativeEventFilter` on `"windows_dispatcher_MSG"` for `WM_KEYDOWN`/`WM_KEYUP`/`WM_SYSKEYDOWN` whose `hwnd` has an editor root (`GetAncestor(GA_ROOT)`).
  - Linux/X11: `xcb_grab_key` on each editor window for the stroke's keycode, with every Caps/Num Lock variant of its modifiers, plus a native event filter on `"xcb_generic_event_t"` for the grabbed events. Grabs are released on close.

# Implementation steps
1. Implement the editor object owning the `QWindow`, `IPlugView` and `IPlugFrame`. Window lifetime ends in exactly one of the two close paths.
2. Implement Linux `IRunLoop` on the host context (`IPlugFrame` query and the factory host context).
3. Wire `OpenEditor`, `RaiseEditor`, `CloseEditor`, `EditorClosed`, `SetShortcuts` and `Shortcut(index)` control frames; add the Swift API and main-actor event handling through `HelperProcess`.
4. Add the fixture view per platform.
5. Implement key interception per platform, and `PluginEditorShortcuts`.
6. Checks:
   - fixture `openEditor` succeeds and `isEditorOpen` is set;
   - the fixture's on-attach edit fires `onEdit`, and the next offline render's notes are +5 semitones (proves the task 6 parameter queue);
   - `closeEditor` then reopen works;
   - destroying an instance with an open editor is clean;
   - a class without a view reports no editor (use `TestGenRealtimeOnly` without a view);
   - macOS: with the Space stroke installed and the fixture view focused in the helper, post synthetic Space key-down/key-up as system keyboard events to the focused helper window, then assert `onShortcut(0)` fires exactly once and `keysReceived` stays 0; a posted `A` key-down raises `keysReceived` to 1;
   - with an empty set installed, Space reaches the fixture.

# Acceptance predicate
Editor checks pass on macOS with a display and system-event posting permission for the check process, and the ASAN run is clean. NAMED CHECKS (controller):
- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks --filter swiftcore-pluginhost-editor`
- `uv run --no-sync dev build:checks --asan && uv run --no-sync dev checks --asan --filter swiftcore-pluginhost-editor`
- `uv run --no-sync dev checks --filter swiftcore-pluginhost`: regression.
- `uv run --no-sync dev checks --filter swiftcore-pluginhost-abi`, plus `--asan`: ABI regression after the destroy-path and fixture-state changes. The fixture still decodes the 8-byte task 6 state format.

# Controller verification
Windowing checks need the desktop free, so do not rerun them repeatedly. Native smoke from a throwaway Swift check invocation (removed afterward): open the editor of an installed third-party plugin in its helper. Verify that it draws, that resize requests apply, that closing the window fires the closed path, and that Space with the plugin view focused fires the shortcut callback. Installed-plugin editor use in the app moves to the final smoke. Windows and Linux editor attach and key interception are covered only by CI compilation; the check-driven proof is macOS-only. Record that gap in the handoff.

# Task-specific constraints
- No QWidgets, no `QWindow::createWindowContainer`, no Qt Quick `WindowContainer`.
- The window is never parented into a QML scene.
- No editor calls off the GUI thread.
