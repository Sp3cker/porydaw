# Task 2 — Implement the Swift/QML editor drawer container

## Context

Follow [Global Constraints](plan.md#global-constraints) and
[spec.md](spec.md) — in particular
[Production composition](spec.md#production-composition),
[Drawer container](spec.md#drawer-container),
[Focus and lifetime](spec.md#focus-and-lifetime) and
[Verification ownership](spec.md#verification-ownership).

The production editor drawer (`src/ui/editordrawer/editordrawer.{h,cpp}`,
`drawersections.{h,cpp}`, `drawerchrome.{h,cpp}`, `drawerpage.h`) is the
behavioral reference: three independently visible sections stacked in the fixed
order Velocity, Voice Changes, Automations; one bottom chrome bar holding one
toggle per section; one resize handle directly above each visible body; a
font-relative minimum body, a piano-roll reserve and a host-height clamp; one
stored body height per section with an "unset" marker; one active page; the
Voice-Changes→Automations spill while resizing; and focus/cancellation rules when
a section hides. `src/checks/drawerpresentation/` records that reference behavior
in a C++ harness that is not part of the compiled manifest — read it as behavior,
never as a target to restore.

This task lands that container as Swift state plus QML composition inside task
1's single production `EditorSurface.qml`, **after** camera integration and
**before** any editor page. It is a container milestone: the velocity,
voice-change and automation page plans each attach a page through the hosting
seam defined here, consume the published rectangles and the shared camera, and
own their own value projection, editing policy and rendering. No page may add a
second camera, a second horizontal viewport or its own history.

Because no production page exists yet, the container's production state is
honest and empty: with no page attached it contributes zero height, renders no
bar, handle, toggle or body, and leaves the roll the full surface height. Once a
page is attached, the bar and its toggles stay visible even while every section is
hidden, so a section can always be reopened from the container's own chrome —
no global View menu is implied by that recovery path. The container is exercised
through its genuine hosting interface with test-only content in the QML lane; that
is container verification, not restored editor-page parity, and it never installs
a fake production page or an inert control advertising absent functionality.

## Exact write set

Create (Swift, app module `PorydawApp`):
- `src/swift/app/EditorDrawer.swift`: pure `EditorDrawerLayout` (state, metrics,
  layout, resize, focus decision, preference-change records) plus the bridged
  `EditorDrawerPresenter` that mirrors it for QML, and the page seam.

Create (test infrastructure):
- `src/checks/swiftcore/EditorDrawerChecks.swift`: direct Swift policy cases.
- `src/checks/editorqml/EditorQmlTests.swift`: the QML lane host — argument and
  `--manifest` handling, lane type registration, the test bootstrap object, and
  the `QTestAppCpp.runQtQuickTests` launch.
- `src/checks/editorqml/DrawerTestPage.swift`: the test-only `EditorDrawerPage`
  implementation (kind, content URL, body policy, cancel counter).
- `src/checks/editorqml/EditorQmlPaths.swift.in`: generated Swift constants for
  the QML test directory and `qmake -query QT_INSTALL_QML QT_INSTALL_PLUGINS`.
- `src/checks/editorqml/tst_EditorDrawer.qml`: container cases hosting the
  production composition.
- `src/checks/editorqml/DrawerTestPage.qml`: the test-only page item the test
  host points its content URL at (not a discovered suite file).

Create (QML):
- `src/ui/songview/quick/drawer/EditorDrawer.qml`: container chrome, section
  content loaders, QML settings store, focus execution, chrome input.

Modify:
- `src/swift/app/ApplicationSession.swift`: own the drawer presenter, expose
  `drawerPresenter()`, install the page attachments before the scene mount and
  detach them only when their owners are released after the existing whole-scene
  detach acknowledgment, and call the container's cancellation entry point where
  the session
  already cancels editor input.
- `src/swift/app/CMakeLists.txt`: add `EditorDrawer.swift` to the source list.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`: place the drawer below the
  roll inside the one production composition, feed the reduced roll height into
  the existing viewport push, make the roll input item focus-returnable, forward
  the palette and the injectable store location, and pass the drawer its layout
  facts.
- `src/checks/swiftcore/SessionChecks.swift`: dispatch `runEditorDrawerChecks`.
- `src/checks/CMakeLists.txt`: add `EditorDrawerChecks.swift` to
  `swift_core_check`; add the test-only `editor_qml_tests` Swift executable and
  its generated paths file.
- `CMakeLists.txt`: two `qt_add_resources` blocks on `porydaw_app` — the drawer
  QML module and the three existing toggle icon resources.
- `deno.json`, `tools/cli.ts`: the `verify:qml` task and subcommand that build
  `editor_qml_tests` (plus `mid2agb`) and run
  `tools/run_checks.ts build/editor_qml_tests`.

Read-only references: `src/ui/editordrawer/*`, `src/checks/drawerpresentation/*`,
`resources/{velocity,automation,flat-music}.svg`, `src/app/RewriteWindow.cpp`,
the retained `src/checks/swiftrollgated/*` suite. No other file changes.

## Prerequisites

Task 1 accepted, checkpointed and pushed: the extracted production
`EditorSurface.qml` (property-injected `applicationSession`, unchanged
objectNames), the session-owned camera, and the existing `configureViewport`
metric push. This task consumes only those interfaces; it never re-integrates or
re-clamps the camera, and it owns no horizontal scroll or time zoom.

Interface consumed by name: `EditorSurface.qml` with
`required property QtObject applicationSession`; the roll plot input item with
`objectName: "swiftRollInput"`; the existing roll viewport push
(`gridModel.configureViewport(width:height:fontPx:dpr:)`); the grid palette
object (`gridModel.palette`); the existing global cancellation entry points on
`ApplicationSession` (`cancelGridInput(reason:)`, the acknowledged scene
detachment used at close/replacement). If task 1 renamed any of these, correct
this brief before dispatch instead of adapting inside the implementation.

The QML lane needs no new native capability and no `porydaw_checks` catalog
entry: the pinned Qt 6.11 installation provides `Qt6::QuickTest`, the `QtCore`
QML module (`Settings`), and the existing `QtBridgeCpp.QTestAppCpp` host. The
lane is a separate Swift executable that reuses `tools/run_checks.ts` exactly as
an existing harness would.

## Interface contract

### Swift ownership and state

`src/swift/app/EditorDrawer.swift` holds two layers:

```swift
public enum DrawerSectionKind: Int, CaseIterable, Sendable {
    case automation = 0        // production EditorDrawerPage values
    case velocity = 1
    case voiceChanges = 2
    static let stackOrder: [DrawerSectionKind] = [.velocity, .voiceChanges, .automation]
    static let toggleOrder: [DrawerSectionKind] = [.voiceChanges, .automation, .velocity]
    var name: String           // "automations" | "velocity" | "voiceChanges"
    var keyName: String        // "automation" | "velocity" | "voiceChanges"
    var iconResource: String   // "qrc:/icons/automation.svg" | velocity.svg | flat-music.svg
}

public struct EditorDrawerMetrics: Equatable, Sendable {
    public let barHeight: Int, handleHeight: Int, minimumBody: Int
    public let pianoRollReserve: Int, toggleInset: Int, resizeStep: Int, pixel: Int
    public static func resolve(baseFontPx: Double, appFontLineSpacing: Double) -> EditorDrawerMetrics
    public func maximumDefaultBodyHeight(hostHeight: Int) -> Int
}
```

`EditorDrawerLayout` is a pure value type: per-kind `visible` (defaults
`.velocity` false, `.automation` true, `.voiceChanges` false) and
`storedBodyHeight: Int?`; the attached page (kind, resolved content URL, body
policy); `activePage: DrawerSectionKind = .automation`; host facts (`hostWidth`,
`hostHeight`, `gutterWidth`); metrics; and the rectangles derived from them. Its
mutating operations are exactly: `configureHost`, `configureMetrics`,
`attachPage`, `detachPage`, `restorePreferences`, `toggleSection`,
`setSectionVisible`, `setSectionBodyHeight`, `beginResize`, `applyResize`,
`endResize`, `cancelResize`, `adjustResizeHandle`, and `cancelInteractions`.
Every operation returns the change set it caused (published values, focus
request, preference-change records); equal values change nothing and publish
nothing. Metrics derive from the pushed facts with the existing helpers
(`fontPx(_:_:)` in `GridGeometry.swift`, hairline = 1 logical pixel). The layout
base font is the `fontPx` argument, which the composition supplies from
`gridModel.baseFontPx` — the same value it already pushes to
`configureViewport(fontPx:)`, so no second base font source exists; the
application font's line spacing is used only for the chrome bar row, exactly as
production's `chromeRowHeight(applicationFont, 0)` does, and derives no other
geometry: `barHeight = max(appFontLineSpacing, 0) + 2 * fontPx(base, 0.125) + 2`,
`handleHeight = fontPx(base, 1/3)`, `minimumBody = fontPx(base, 17/5)`,
`pianoRollReserve = fontPx(base, 10)`, `toggleInset = fontPx(base, 0.25)`,
`resizeStep = fontPx(base, 0.5)`.

`EditorDrawerPresenter` is the `@QtBridgeable` owner of one layout value. It
publishes primitives only: `height`, `barVisible`, `barX/barY/barWidth/barHeight`,
`plotOrigin`, `plotWidth`, `focusRequest` (monotonic revision) and `focusTarget`
(`-1` = roll, otherwise a kind raw value), plus one bridged section state object
per kind carrying `available`, `visible`, `contentUrl`, `bodyX/bodyY/bodyWidth/
bodyHeight`, `handleY/handleHeight`, `toggleX/toggleY/toggleSize`. All rectangles
are drawer-local (origin at the container's top-left); the composition places the
container. `available` is derived state, never an independent flag: it is true
only while a page is attached with a resolved, non-empty content URL. While
`available` is false the container publishes an empty URL, empty rectangles and
no control for that kind. The bridge must never see the pure layout type, the
page protocol or any Core value.

Qt-facing methods: `configureLayout(hostWidth:hostHeight:gutterWidth:fontPx:
appFontLineSpacing:)`, `restoreStoredPreferences(velocityVisible:velocityHeight:
automationVisible:automationHeight:voiceChangesVisible:voiceChangesHeight:
activePage:)`, `toggleSection(kind: Int, drawerOwnsFocus: Bool)`,
`setSectionVisible(kind: Int, visible: Bool, drawerOwnsFocus: Bool)`,
`setSectionBodyHeight(kind: Int, height: Int)`, `beginResize(kind: Int)`,
`applyResize(kind: Int, delta: Double)`, `endResize(kind: Int)`, `cancelResize()`,
`adjustResizeHandle(kind: Int, direction: Int)`,
`inputCancelled(reason: Int)`. Signals: `drawerSectionPreferenceChanged(kind:
Int, visible: Bool, height: Int)` (height `0` means unset) and
`drawerActivePagePreferenceChanged(page: Int)`.

Swift-only API (public, `@QtIgnored`): `attachSection(_:)`, `detachSection(_:)`.
`ApplicationSession` creates the drawer presenter in `init`, keeps it across
project and song replacement (drawer state is application chrome, not document
state), serves it through `drawerPresenter()` with no song-open precondition, and
owns every attach/detach call with a fixed, bounded lifetime: the three allowed
page attachments are installed before the scene is mounted and removed as part of
releasing those page owners, which happens **after** the existing whole-scene
detach acknowledgment completes — the accepted rule that Swift owners stay alive
until the native host confirms the scene is gone. Hiding, collapsing, resizing,
detaching-by-replacement and song/document changes never destroy an attached page
owner; only that owner release detaches. After a detach the container holds no
reference to the released page and no state tied to the previous document; only
the chrome values (visibility, stored heights, active page) survive. Pages must
not retain the drawer presenter, so the container's strong reference creates no
cycle. No API re-points an attached page's content URL: the URL is resolved once
at attach and the body loader is created from it, so replacing content is an
explicit detach followed by an attach.

Nothing here publishes playback, history or dirty state; a drawer change never
dirties a song, consumes Redo or rebuilds audio.

`drawerOwnsFocus` is an observation of the current call, never retained state:
the chrome passes `drawerScope.activeFocus`, the Swift-driven paths pass
`false`. No setter stores a last-focus value.

### Page hosting seam

```swift
public struct EditorDrawerBodyPolicy: Sendable {
    public var maximumBodyHeight: Int?                       // nil = unbounded
    public var preferredBodyHeight: @Sendable (Int, EditorDrawerMetrics) -> Int
}

public protocol EditorDrawerPage: AnyObject {
    var sectionKind: DrawerSectionKind { get }
    var contentUrl: String { get }        // non-empty QML URL, resolved at attach
    var bodyPolicy: EditorDrawerBodyPolicy { get }
    func cancelSectionInteraction()
}
```

`attachSection(_:)` rejects an empty or unresolvable `contentUrl` without
changing any state, and rejects a kind that already holds an attached page:
replacing content is an explicit detach followed by a new attach, never a live
attachment change. A successful attach stores the page strongly in that kind's
slot and makes the kind available in the same publication, so a visible stored
state becomes visible content with no empty frame; the body policy is re-read on
every layout pass, while the content URL is resolved once and never re-pointed.
There is no live URL hot-swap, no per-page acknowledgment protocol, no generic
registry and no retired-page cache. `detachSection(_:)` cancels the page
synchronously, drops the slot, URL and rectangles, and publishes; the stored
visibility and height survive detach but produce no control until a page is
attached again. Hiding, collapsing or resizing never detaches or destroys an
attached page, and the QML body loader stays instantiated for every attached kind
while it is hidden so no page is destroyed by a hide. There is no weak-slot
fallback: a kind is either explicitly attached or explicitly detached, and no
operation may run against a detached page.

Sections with no attached page contribute no height, no handle, no toggle and no
body, and no control may exist for them. This is the production no-page rule, not
a temporary placeholder.

### Layout, visibility and resizing

- Visible and available sections are laid out top to bottom in `stackOrder`: each
  body follows its own handle, then the bar occupies the last `barHeight` of the
  container. `bodyWidth == hostWidth`; the bar spans the full width and is
  rendered whenever at least one section is available, so a hidden section can be
  reopened from the chrome without any global menu. The container height is zero
  only when no page is attached at all.
- `height = min(hostHeight, barHeight + Σ(handleHeight + bodyHeight) for visible
  available kinds)` — the aggregate may fill the host, exactly as production's
  `DrawerSections::preferredHeight()`. Under that clamp the drawn bodies are
  allocated in the order Voice Changes, Automations, Velocity (Velocity takes the
  remainder), production's `arrangeLocal` order, and no stored body height is
  rewritten by the allocation.
- A body's own height is `storedBodyHeight ??
  page.bodyPolicy.preferredBodyHeight(hostHeight, metrics)`, never below
  `minimumBody`, and capped only by the page's declared
  `bodyPolicy.maximumBodyHeight`. There is no container-wide cap: the piano-roll
  reserve applies to neither stored nor drawn bodies, and it never constrains the
  aggregate.
- The reserve bounds *default* sizing only, exactly as production's
  `EditorDrawer::maximumSectionHeight()`: `maximumDefaultBodyHeight(hostHeight) =
  hostHeight >= minimumBody + pianoRollReserve ? hostHeight - pianoRollReserve :
  hostHeight`, exposed through `EditorDrawerMetrics` for a page's
  `preferredBodyHeight` closure. Production's automation default is
  `clamp(hostHeight / 5, minimumBody, maximumDefaultBodyHeight(hostHeight))` and
  its velocity default `clamp(hostHeight / 6, fontPx(base, 8), fontPx(base, 12))`;
  both are page policy, and this bound never caps a resize or the aggregate.
- Toggles keep the three production slots
  (`buttonSize = max(pixel, barHeight - 2 * toggleInset)`,
  `groupWidth = 3 * buttonSize + 2 * toggleInset`,
  `groupX = clamp((gutterWidth - groupWidth) / 2, 0, max(0, hostWidth - groupWidth))`)
  and are positioned by their kind's slot in `toggleOrder`; only available kinds
  are rendered, so page attachment never reflows the group.
- `toggleSection` flips the section's visibility and makes it the active page; a
  hidden section keeps its stored height and re-showing restores it.
  `setSectionBodyHeight` maps a height < 1 to the unset marker; toggling,
  visibility and height calls are ignored for a kind that is not available.
- `beginResize` captures, for the resized kind, the drag start height and its
  original stored value, plus the Automations section's start height and original
  stored value. `applyResize(kind:delta:)` resolves `startHeight + round(delta)`
  (positive delta grows the body, matching a drag toward the top) and clamps it.

  Available body height for the resized kind is `hostHeight - barHeight -
  Σ handleHeight over visible available kinds - Σ bodyHeight over visible available
  kinds except the resized kind, and except Automations only while the resized
  kind is Voice Changes` — production's `applyResize` subtraction, where the
  Automations body is subtracted for every other kind.

  **Voice-Changes→Automations spill (ported production policy):** when the
  resized kind is `.voiceChanges`, it declares a maximum body height and
  `.automation` is visible and available:
  `maximumForResized = min(max(minimumBody, availableBodyHeight), declaredMaximum)`;
  `resized = clamp(requested, minimumBody, maximumForResized)`;
  `automationMaximum = max(minimumBody, availableBodyHeight - resized)`;
  `automation = requested > maximumForResized ? clamp(automationStart + requested -
  maximumForResized, minimumBody, automationMaximum) : automationStart`.
  Every other kind, and Voice Changes without a declared maximum, takes the plain
  `clamp(requested, minimumBody, max(minimumBody, availableBodyHeight))` path, with
  the page's declared maximum applied afterwards as production applies
  `voiceChangesMaxBody`.
- A resolved value equal to that section's drag-start height restores its original
  stored value, including the unset marker; the same rule applies independently to
  the spilled Automations height. A session belongs to one kind:
  `applyResize`/`endResize` for any other kind, and any of them without a live
  session, are ignored. `endResize` records the changed section preferences;
  `cancelResize` and `inputCancelled` drop the session, keep the last applied
  heights and record nothing. `adjustResizeHandle(kind:direction:)` with a
  non-zero direction applies one `resizeStep` through the same path and records
  the change.

### Focus, cancellation and lifetime

A transition that changes section visibility or the active page computes its
focus request from the `drawerOwnsFocus` argument of that call: when it is true,
the request targets the active visible available kind, or the first visible
available kind when the active one is not available, or `-1` (roll) when nothing
visible remains. `focusRequest` increments and `focusTarget` is set only for such
a transition; a request for a kind that is not available and visible is never
published. QML executes a new request by focusing that kind's loaded page item,
or the roll input item for `-1`, and skips the request when the loader has no item
yet.

The same transition cancels content synchronously in Swift, before the new state
is published and before any signal may be delivered: each kind hidden by the
transition and each kind losing the active slot has `cancelSectionInteraction()`
called on its attached page. Cancellation is never ordered by a queued QtBridge
signal. `inputCancelled(reason:)` is the container's single global entry point: it
cancels the chrome resize session and fans out to every attached page in Swift, in
the same way the grid receives `inputCancelled` today, treating every reason
identically; `ApplicationSession` calls it from its existing cancellation sites
(scene hide, song close or replacement, document change) and no new host or native
cancellation API is added. Cancellation ends the current interaction or gesture
for that page only; a page that stays visible keeps operating normally and is not
disabled, and no callback may target QML objects after the scene is gone. The only
ownership boundary is the existing one: page owners stay alive until the native
host acknowledges the whole-scene detachment, and only then are they released and
detached — there is no per-page acknowledgment, no page-level teardown handshake
and no separate lifetime mechanism for this container.

### Persistence boundary

The container owns the section state and the historical key formats, and Swift
owns every default and validation rule. The bytes are read and written by QML
only:

- Keys, under category `editorDrawer` (that is, `editorDrawer/<key>`):
  `<keyName>Visible` (bool) and `<keyName>Height` (integer, `0` means unset; a
  stored value ≤ 0 or unparsable means unset) for each of `automation`,
  `velocity`, `voiceChanges`, plus `activePage` (string
  `"velocity" | "voiceChanges" | "automations"`). Historical defaults: automation
  visible, velocity and voice changes hidden, active page automations.
- Store type: `import QtCore` `Settings` (`Qt.labs.settings` is deprecated since
  Qt 6.5); `category: "editorDrawer"`, `location: preferenceLocation`.
  `EditorDrawer.qml` declares `property url preferenceLocation: ""`;
  `EditorSurface.qml` declares `property url drawerPreferenceLocation: ""` with
  the production default and forwards it. Empty means the application's default
  QSettings store; every lane case points it at a private file under its runner
  scratch, so a test never reads or writes the production store.
- Read: once, in the container root's `Component.onCompleted` (children complete
  first, so the Settings object has already loaded its values). QML maps each
  present key to its raw value and calls `restoreStoredPreferences` a single time,
  with `-1` for an absent visibility or page, `0` for an absent height, and the
  kind raw value for a page name it recognises. Restore applies state and
  publishes geometry, and records no preference change: restoring never writes
  back, and an absent or invalid key leaves the current value untouched.
- Write: only from the two preference signals, followed by `sync()`. A section
  signal is emitted only when an available kind's visibility or stored height
  actually changed through `toggleSection`, `setSectionVisible`,
  `setSectionBodyHeight`, `endResize` or `adjustResizeHandle` — including both
  kinds changed by a spill; QML then writes that one kind's two keys
  (`<keyName>Visible`, `<keyName>Height`) from the signal payload. The page
  signal is emitted only when an interactive call changes the active page to an
  available kind, and writes `activePage`. A kind that is not available never has
  its keys written, and neither restore, attach, detach, `inputCancelled`, a host
  or metric change, nor scene teardown writes any key. No other settings key is
  written here, and `src/ui/editorviewstate.{h,cpp}` stays retired and
  uncompiled.

### QML composition and chrome

`EditorDrawer.qml` is a clipped `FocusScope` (`id: drawerScope`) sized by the presenter's `height`,
declaring `required property QtObject applicationSession`,
`required property QtObject presenter`, `required property QtObject palette`,
`property url preferenceLocation: ""`. It renders, from published values only:

- the bar rectangle (background `palette.chromeBackground`, outline
  `palette.outline`, hairline border) and one toggle per available kind;
- one handle rectangle above each visible available body (color `palette.outline`,
  hovered `palette.selectionRing`, `cursorShape: Qt.SizeVerCursor`);
- one body `Loader` per kind at the published body rectangle, created with
  `setSource(contentUrl, {"applicationSession": applicationSession})`, `focus:
  true` and clipped. The loader is active for as long as the kind is attached, so
  a hidden section keeps its page instance alive; the item's `visible` and
  `enabled` (and the published rectangle) follow effective section visibility.

Toggle icons are rendered in QML only: an inline `Canvas` loads the kind's
existing SVG with `loadImage(iconResource, Qt.size(buttonSize, buttonSize))`,
repaints from `onImageLoaded`, draws it with `drawImage`, then fills the same
rect with `globalCompositeOperation = "source-in"` using `palette.keyboardLabel`
as the tint — the same alpha-mask tint the retired chrome produced with
`QPainter::CompositionMode_SourceIn`. No C++ image provider, no
`QtQuick.Effects`/`Qt5Compat` effect, no new palette role and no second icon set.
Section state stays legible because the button background differs
(`palette.windowBackground` unchecked, `palette.selectionRing` checked).

Toggles: `Accessible.role: Accessible.Button`, `Accessible.checkable: true`,
`Accessible.checked`, `Accessible.focusable: true`, `Accessible.onPressAction`,
`activeFocusOnTab: true`, names `qsTr("Velocity drawer")`,
`qsTr("Voice-change drawer")`, `qsTr("Automation drawer")`, the tinted `Canvas`
icon described above at the button size, background `palette.windowBackground`
unchecked and `palette.selectionRing` checked.
Handles: `Accessible.role: Accessible.Grip`, names
`qsTr("Resize velocity drawer")`, `qsTr("Resize voice-change drawer")`,
`qsTr("Resize automation drawer")`, description
`qsTr("Use Up and Down to resize")`, `Accessible.focusable: true` with
`Accessible.onIncreaseAction`/`onDecreaseAction`. Both control kinds claim keys
only through `Keys.onShortcutOverride` for `Qt.Key_Return`/`Qt.Key_Enter`; bare
Space is never claimed, so the window's transport shortcut keeps priority.
Handles additionally handle `Keys.onUpPressed`/`onDownPressed` (adjust ±1,
accepted) and consume `Keys.onLeftPressed`/`onRightPressed` as accepted no-ops.
Toggle activation and pointer visibility calls pass `drawerScope.activeFocus` as
the focus observation for that call; no focus value is remembered.

Page item contract: the item at `contentUrl` is a `FocusScope` that declares
`required property QtObject applicationSession`; it fills the loader and owns its
internal focus and input. The container never re-declares a page's handlers, and
this task ships no production page.

### Camera and roll feedback

The container owns no horizontal scroll, time zoom or pitch state. It publishes
`plotOrigin` (= the shared gutter width the grid renders with, i.e. the roll plot
origin) and `plotWidth` (= `hostWidth - plotOrigin`) so a page maps ticks with the
session camera at the same origin as the roll. `EditorSurface.qml` places the
container at the bottom, sizes the roll band as `surfaceHeight - container.height`,
and lets the existing `configureViewport(width:height:fontPx:dpr:)` call react to
that height change (it already runs on the roll band's height change), so the
camera's roll height follows the container automatically. The container's layout
facts come from that same push: `configureLayout(hostWidth:hostHeight:gutterWidth:
fontPx:appFontLineSpacing:)` receives `gridModel.baseFontPx` as `fontPx` — never a
second base font — plus the shared gutter width and the
application font's line spacing for the bar row only, bound through
`FontMetrics { font: Application.font }.lineSpacing`.

### QML lane contract

`src/checks/editorqml/EditorQmlTests.swift` is a standalone Swift executable
(`add_executable`, `Swift_MODULE_NAME EditorQmlCheck`, Swift language version 6,
AUTOMOC/AUTUIC/AUTORCC off, `LINKER_LANGUAGE CXX`, the same module-map compile
options `swift_core_check` sets, linking `QtBridge`, `PorydawApp` through
`"$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>"` and `Qt6::QuickTest`).

- Manifest: with `--manifest` and no other work, print exactly
  `{"checks":[{"name":"editorqml-drawer","argv":["{scratch}"],"binary":"checks",
  "windowing":"offscreen","framework":"qt-test","optIn":false,
  "scratchKind":"existing-directory","fixtureRootKind":"decomp-project",
  "fixtureFiles":[…]}]}` and exit 0. The fixture list is the route101 set defined
  in `src/checks/checkcatalog.cpp`: `fixtures::decompProjectFiles()` +
  `sound/songs/midi/mus_route101.mid` + `fixtures::richVoicegroupFiles()`.
- Run: the first argument is the scratch path; remaining arguments are Qt Quick
  Test arguments already unwrapped from the Deno runner's `--qt` option.
  Reject a payload containing `-input`. The lane maps its one entry name to
  `tst_EditorDrawer.qml`, calls `setInputDir(<generated QML test directory>)`,
  `setImportPath(<QT_INSTALL_QML>)`, `setPluginsPath(<QT_INSTALL_PLUGINS>)`
  (both from the generated constants; `runQtQuickTests` overwrites
  `QT_PLUGIN_PATH`/`QML2_IMPORT_PATH` unconditionally), then calls the app
  module's existing registration entry point (`pdAppRegisterTypes()`) and the
  lane's own `EditorQmlBootstrap.registerQmlElement()`, then runs
  `runQtQuickTests([program, "-input", <that file>, <payload…>])` and exits with
  its return value. The QML test imports `PorydawApp` for `ApplicationSession`
  (the production creation path, exactly as `RewriteWindow` uses it) and its own
  module (`EditorQmlCheck 1.0`, following
  `src/checks/swiftqtml/BridgeProbe.qml`) for the bootstrap, and references the
  production composition by relative URL
  (`../../ui/songview/quick/swiftroll/EditorSurface.qml`, the same file the
  application's resource engine loads).
- Bootstrap, QML-facing: `@QtBridgeable EditorQmlBootstrap: QmlInstantiableStatus`
  with `projectRoot` (the scratch path), `pageCancelCount` (accumulating across
  the test pages the bootstrap owns), `start(session:
  ApplicationSession, songLabel: String)` calling
  `session.openProjectAndSong(path:label:)`,
  `preferencesUrl(name: String) -> String` returning a `file://` URL under the
  scratch directory, and `attachTestSection(kind: Int, contentUrl: String) ->
  Bool` / `detachTestSection(kind: Int)` creating or dropping a `DrawerTestPage`
  and attaching it through the production seam. The test page is a real
  `EditorDrawerPage` implementation; the QML side is a real page item at a real
  URL. No production file gains a test branch.

## Implementation steps

1. Add `EditorDrawer.swift` with the metrics, kinds, pure layout (availability,
   stacking, clamp, allocation order, resize including the Voice-Changes→
   Automations spill, focus request, cancellation sets, preference-change
   records) and the page seam, then the bridged presenter that mirrors the layout
   into published values and applies the synchronous cancel-before-publish order.
   Own one presenter in `ApplicationSession` (`init`, `drawerPresenter()`, page
   attachments installed before the scene mount and detached only when their
   owners are released after the existing whole-scene detach acknowledgment, the
   `inputCancelled` call at the existing cancellation sites), and add the file to
   `src/swift/app/CMakeLists.txt`. All
   policy lives in the pure layer; the presenter holds none of its own.
2. Add `EditorDrawerChecks.swift` and dispatch `runEditorDrawerChecks(report)`
   from `runProjectSessionSuite` beside `runEditorCameraChecks`, before the
   fixture guard, and add the file to `swift_core_check`. Assert pure-layer
   values only — no Qt object, no project fixture.
3. Create `src/ui/songview/quick/drawer/EditorDrawer.qml` with the chrome
   (including the inline `Canvas` icon tint), the three content loaders, the
   accessible controls, the key-claim policy, the resize/focus execution and the
   `QtCore` `Settings` store, and register it with one `qt_add_resources` block on `porydaw_app` (`PREFIX "/porydaw/drawer"`,
   `BASE src/ui/songview/quick/drawer`); register the three existing
   `resources/*.svg` toggle icons with a second block (`PREFIX "/icons"`,
   `BASE resources`), matching the `qrc:/icons/…` URLs above.
   `EditorSurface.qml` gains `import "../drawer"` and instantiates `EditorDrawer`
   with the injected properties; because the resource prefix mirrors the source
   layout, that one relative import resolves in both the resource engine and the
   source tree the lane loads.
4. Wire `EditorSurface.qml`: bottom-anchored container below the roll, roll band
   height reduced by the container height, palette and store-location forwarding,
   the layout-fact push, and `activeFocusOnTab: true` on the existing
   `swiftRollInput` item. Do not move, copy or re-implement task 1's handlers, and
   do not change the host's key routing (focus inside `swiftRollInput` stays
   non-local for the host, `RewriteWindow.cpp:76-88`).
5. Build the QML lane: `EditorQmlTests.swift` (manifest, single entry, argument
   validation, registrations, bootstrap, and the `-input` launch),
   `EditorQmlPaths.swift.in` configured into the build directory,
   `DrawerTestPage.swift`, both QML files (`tst_EditorDrawer.qml` and the test
   page item `DrawerTestPage.qml`), the `editor_qml_tests` target in
   `src/checks/CMakeLists.txt` (extending the existing
   `find_package(Qt6 REQUIRED COMPONENTS Test)` with `QuickTest`), and the
   `verify:qml` wiring in `deno.json` and
   `tools/cli.ts`. Builds and runs belong to the controller after the sibling
   edits settle; this step ends with the lane's structure verified by inspection.

## Acceptance predicate

`projectSession` (`runEditorDrawerChecks`) proves, with direct value assertions
and no Qt object: metrics derivation from the pushed font facts; the no-page rule
(zero height, empty rectangles, empty URL, no control, stored intent retained) and
the all-hidden rule (bar and toggles stay, no body or handle); availability
requiring an attached page with a non-empty URL and the rejection of an empty URL,
of a kind that already holds a page and of an operation on a detached page;
stacking
order, handle placement and the bar last; the aggregate host clamp, with the
piano-roll reserve bounding default sizing only and never a stored body, a resize
or the aggregate; the
Voice-Changes→Automations→Velocity allocation order; toggle positions for the
three production slots; toggling flips visibility and active page and retains the
stored height across hide/show; equal setters and unavailable-kind operations
publish nothing; resize growth and shrink from the drag delta, the minimum and
available clamps (including the Voice-Changes-only Automations subtraction), the
page maximum applied after the available clamp, restoration of the unset marker at
the drag start, cross-kind and session-less calls ignored, cancel keeping the
applied heights; the Voice-Changes spill moving the Automations stored height by
the excess with `automationMaximum = max(minimumBody, availableBodyHeight -
resized)`, restoring both original stored values when the drag returns to its
start, and not applying to
non-capped kinds; host shrink re-clamping without rewriting stored heights; the
focus-request target for hide, active-page change and full-hide transitions,
never a kind that is not available and visible, and no request when the
observation is false; the synchronous cancel set for a transition (before the
published change) and for `inputCancelled`; the restore path applying values
without recording any preference change; and the preference-change records for
interactive calls only.

The QML lane (`editorqml-drawer`, `tst_EditorDrawer.qml`, offscreen) hosts the
production `EditorSurface` and exercises the container through the real seam:

| Case | Observable contract |
| --- | --- |
| `test_noPageContributesNothing` | No page attached: container height 0, no bar, handle, toggle or body item rendered, roll band occupies the full surface height; a store value asking for a visible section still produces no control, no page and no write. |
| `test_hostedChromeAndStacking` | Three test pages attached through the bootstrap (velocity, voice changes, automations): bar, per-kind toggle/handle/body appear exactly at the presenter's published rectangles, velocity above voice changes above automations with the bar below all three, each page item fills its body rectangle and uses `plotOrigin` equal to the grid's gutter width, toggle role/name/checkable/checked/focusable and Return/Enter activation hold, and a Space press on the same focused toggle propagates unclaimed. The themed chrome is captured with `grabImage(toggle)` and checked against the palette: the button background matches `palette.windowBackground` and the tinted glyph pixels match `palette.keyboardLabel` (via `fuzzyCompare` with a small channel delta), so the alpha-mask tint is real rendered output, not a property claim. |
| `test_toggleRetainsStoredHeight` | Real pointer click and Return activation hide and re-show a section; hidden sections release their height and the roll grows, re-showing restores the same body height; hiding the last visible section leaves the bar and its toggles in place with no handle and no body, and the container height equal to the bar row. |
| `test_resizeClampAndCancellation` | Real press/drag/release on a handle resizes the body by the drag delta; clamping at the minimum body and at the available height keeps the body inside the container and the container height inside the host; Up/Down adjust by the resize step and Left/Right are consumed; a cancelled drag keeps the last applied height with no session left; a host shrink re-clamps the container without changing the stored height. |
| `test_voiceChangesSpillAndDetach` | With the voice-changes test page declaring a maximum body height beside the automations page, dragging past that maximum moves the automation body by the excess and stops at `max(minimumBody, availableBodyHeight - resized)`; returning to the drag start restores both stored heights. Detach is exercised only after the surface hosting those pages is destroyed and then remounted, matching the real lifetime: the remounted composition shows that kind unavailable with no toggle, handle or body, leaves the automations section untouched, and the detached kind's keys were never written. |
| `test_focusReturnAndPageCancellation` | With the drawer focused, hiding the visible section moves active focus to the roll input item; showing and toggling focus the page item's scope; hide and active-page change bump the test page's cancel counter exactly once per transition; a hidden attached page is neither destroyed nor cancelled again, and a page whose surface was torn down is detached only after that teardown. |
| `test_preferencesRoundTrip` | With `drawerPreferenceLocation` pointing at a case-specific file under `{scratch}`: a pre-seeded store restores visibility, height and active page when the composition mounts without writing anything back; toggling, hiding and resizing write back that kind's visibility and height keys in the historical formats (bool; positive integer; `0` for unset; the page name) and never another kind's keys, `sync()` makes them readable by a freshly created `Settings` instance, and the scratch file is the only store touched. |

Controller verification after writers settle (with an available native desktop
for the last step):

```sh
deno task build:app
deno task verify --filter swiftcore --verbose --qt projectSession     # Swift container policy
deno task verify:qml --filter editorqml-drawer --verbose              # real composition container gate
deno task verify --filter swiftrollgated --verbose                    # retained windowed suites (runner-staged real window)
```

The first command builds the app and `mid2agb`; the second runs the pure Swift
container cases through the existing suite; the third builds `editor_qml_tests`
and runs the lane through `tools/run_checks.ts` (offscreen; the lane's own
manifest entry, not a `porydaw_checks` catalog name); the fourth keeps the
existing window-level grid/key/clipboard protection green, which is also where
the real-window evidence below comes from.

Real-window evidence is the existing runner-staged windowed harness, not a
separate launch: the `swiftrollgated` run above drives the real `RewriteWindow`
against the runner-staged route101 project through `tools/run_checks.ts`, and the
controller records the observations from that run plus a captured window. What it
must show is the honest production state: grid rendering and interaction unchanged,
and the container absent — no bar, no toggle, no handle, roll at full height —
because no page is attached. Container chrome itself is verified by the lane's
grabbed rendering above, since no production page exists to mount it in the
window.

Coverage gaps, named rather than implied: window-level shortcut precedence stays
with the retained windowed suite, since the lane proves only the controls' claim
policy; the container's chrome with a *production* page's own content and colors
arrives with that page; and what the active page means once several real pages
exist (which page should hold the slot on show) is a page-level decision, while
this task verifies the container's stored value and toggle rule.

## Task-specific constraints

No velocity, voice-change or automation page content, value projection, editing
operation, prompt, detent control or page-specific persistence key in this task:
the detent control lives inside the velocity body rectangle and belongs to the
velocity page. No second camera, no horizontal scroll or zoom ownership, no
reciprocal scroll binding, no page registry, plugin host or generic presenter
protocol beyond the four-member page seam; no live attachment changes (an
occupied slot rejects a new attach instead of replacing it), no live content-URL
hot-swap, no per-page acknowledgment or teardown handshake, and no retired-page
cache — the three fixed attachments have a bounded lifetime and hiding a section
never destroys its owner. Icon tinting is the inline QML `Canvas` alpha mask
described above: no C++ image provider, no `QtQuick.Effects`/`Qt5Compat` effect,
no shader framework and no new palette role, and the tint must be observed in
grabbed rendering rather than asserted as a property. No new C++ API, controller, helper,
bootstrap, test scenario, catalog entry, palette/menu/action table row or native
responsibility; the only native-side deltas are the two resource blocks and the
`activeFocusOnTab` flag on the existing roll input item. No global View-menu or
shortcut restoration, no whole-window shell migration, no copied shortcut table,
no synthetic key forwarding and no remembered focus tier. Do not recompile the
retired `EditorViewState` codec or revive `Porydaw.Ui`. Keep the composition to
one production root: the lane hosts the same `EditorSurface.qml` the application
ships, never a copy, and no test-only branch may exist in production QML.
