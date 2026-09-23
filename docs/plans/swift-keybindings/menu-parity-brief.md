# Native menu and dialog parity

Owner: Main. Preserve the old menu mechanism and the themed, non-native QWidget surfaces; do not redesign retained editor QML.

## Confirmed source contract

Old QMenu copied QAction's primary shortcut into QCocoaMenuItem while the registry separately installed its Qt shortcut-map entry. Qt 6.11 `qcocoansmenu.mm:180-249` sends ShortcutOverride to the focus object: acceptance forwards the native event and suppresses the menu action; rejection lets Cocoa activate the menu item without forwarding keyDown. These are exclusive routes, not duplicate activations. `qcocoamenuitem.mm:345-372,417-424` accepts a tab followed by QKeySequence NativeText as the same native key equivalent. A plain QML MenuItem with that text does not register another Qt shortcut-map entry. QQuickAction.shortcut would, so do not use it. The earlier audit's display-only-title approximation was withdrawn after tracing this event path.

The original standalone context QMenu was non-native and themed. Keep the QML context popup non-native and render its primary shortcut in a separate right-aligned label. Native menu bars, folder panels and message alerts remain system surfaces. Song QInputDialog was palette/QSS-painted; use locally selected theme-capable Quick Controls for its replacement, not a global style/palette change. No new C++, shim, Action shortcut, polling or alternate dispatcher.

## Exact write set

- `src/swift/app/commands/KeybindingRegistry.swift`: publish native text alongside portable text while converting the already-resolved QKeySequence. Preserve every id, binding, stroke, scope, cache timing and match predicate.
- `src/swift/app/shell/ShellPresenter.swift`: add `actionShortcut(id: String) -> String`, exposing only the primary native text (empty for unbound Open Song/Stop). No activation-policy changes.
- `src/swift/app/shell/ShellAppearance.swift` and `src/swift/app/timeline/GridPalette.swift`: publish the existing native menu background/hover roles from presetcolors.h; preserve existing editor color formulas. QtBridge automatically tracks explicitly typed scalar properties and queues their notifications. The throwaway restored-theme probe waits for delivery; no notification workaround or extra annotations are needed.
- `src/ui/shell/ShellWindow.qml`: menu-bar labels append tab/native primary shortcut only when nonempty. Context-menu rows use separate caption/hint items, existing font metrics, and original menu background/hover/pressed/text roles. Song dialog/control styling stays local; native FolderDialog/MessageDialog and retained editor visuals are untouched.
- Existing shell contract/proof notes document the native arbitration distinction and offscreen evidence limit.

## Verification

No invented permanent scenarios. Controller runs `deno task verify:shell --verbose`, `deno task verify --filter swiftcore --verbose`, `deno task verify:qml --verbose`, and `deno task build:app`. Throwaway offscreen probes inspect actual menu captions, theme restoration, context hover and song-dialog colors/interaction; screenshots are inspected, probes removed. Native Cocoa column/arbitration is source-verified, not falsely claimed exercised by the offscreen platform. The original Copy/Solo/text/numeric checks must still pass unchanged. Production bootstrap also receives an offscreen launch smoke before final review.
