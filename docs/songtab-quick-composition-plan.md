# SongView composition and QWidget-free SongTab plan

## Status and scope

The bounded deletion pass completed on 2026-09-09. The application now uses the shared Quick composition described below; the original P1–P8 packets and check-generation guidance remain historical.

Against pre-pass commit `06054ac8`, production changed by +504/−1040 lines (net −536) and checks by +278/−680 (net −402). Against `fork-main`, the branch still carries +2637/−1163 production lines (net +1474) and +2907/−1335 check lines (net +1572). The pass removed more code than it added, but the full branch is still not a “very few new lines” result.

The required bounded matrix passed all 24 selected harnesses. Native application smoke verified visible shared pages and tab selection without blank or overlapping canvases.

This plan extends the earlier [SongView cutover blueprint](songview-quick-cleanse-blueprint.md). That blueprint deliberately retained QWidget SongTab pages. Its rendering, editing, popup, and native-playhead behavior requirements remain applicable; its SongTab hosting end state is superseded here. Historical execution instructions are not new authorization to create worktrees, commit, merge, or push.

**End state:** SongView's presentation is an item subtree, SongTab is a QObject song session, and the song tab strip and pages are Quick. No QWidget page, widget layout, widget focus traversal, or per-song native window remains in those modules. The existing QWidget MainWindow embeds one workspace Quick window through one outer-shell adapter. Transport, browsers, docks, unrelated dialogs, and application startup remain outside this migration.

This is not a promise to remove QtWidgets linkage from the application. Shared layout, typography, and theme startup still depend on QApplication. Replacing those application-wide facilities or MainWindow is a separate scope, not a hidden prerequisite.

**Scope recommendation, not a technical necessity:** replace the song tab strip with Quick in this plan so the song-page module is Quick end to end. The architect identified a smaller alternative: retain a shell-owned QTabBar above the single workspace container while making SongTab QObject and its pages Quick. That alternative would still remove per-song QWidget pages/windows, but would leave song-tab chrome in Widgets. The chosen plan includes that chrome; it does not imply that all MainWindow chrome must migrate.

## Page stacking and tab order

**`StackLayout` and `Repeater` replace the host's hand-rolled page
registry.** `WorkspaceQuickHost` now owns only one engine/window/container,
appearance publication, and explicit widget-to-editor focus entry.

`WorkspaceSongs.qml` owns the page hierarchy:

- an editor-area `FocusScope`,
- a `StackLayout` bound to `workspaceTabs.selectedIndex`,
- a `Repeater` over the ordered session model, and
- one direct child `FocusScope` per row.

Each delegate receives the borrowed session, `TimelineQuickView`, readiness,
and row index. It attaches its persistent scene once, when both component
completion and a shared window are available. `StackLayout` owns page
geometry and visibility. The delegate's `focus` and `enabled` bindings are
true only for the ready current item, so Qt Quick retains each page's focused
descendant without a C++ focus-history table.

`TimelineQuickView::setPageSelected` remains the semantic eligibility gate
used by input, popup, audition, and native-layer cleanup. It is not a page
visibility or geometry mechanism. `QuickWindowInput` now owns only
window-lifetime release swallowing; it has no selected-scene registry or key
fallback.

**`move()` is not needed.** `StackLayout` has no tab drag. The product does
not need pointer reorder. Open order is append order and is persisted as
such. `SongTabsModel::move`, `WorkspaceQuickHost::requestMove` /
`moveRequested`, `WorkspaceUi::moveTab`, and `sessionsReordered` are gone.
Without moves, model row equals `StackLayout` child index. Stock `TabBar`,
`TabButton`, nested close `ToolButton`, and attached `ToolTip` own the strip;
selection and close transactions call the authoritative `WorkspaceUi`.

## Pre-cutover source evidence (historical)

| Evidence | Architectural consequence |
| --- | --- |
| `src/ui/songview.h:118` already declares `SongView : QObject`; `songview.cpp:277-315` creates semantic interactions, the Quick coordinator, and playhead. | Do not repeat the completed widget-renderer migration or turn SongView into a giant QQuickItem subclass. Keep semantic coordination in C++. |
| `src/ui/songview/quick/timelinequickview.cpp:147-180` creates QQuickView, configures engine-root context properties, installs a drawer image provider, loads TimelineCanvas, and creates the popup session. | The remaining presentation is window-owned, not yet composable. Window/engine creation must move to the host. |
| `src/ui/songview.cpp:213-233` derives viewport dimensions from QQuickWindow. `TimelineCanvas.qml:4` is already an Item. | Reuse the existing QML canvas; derive band layout from the page item, not the workspace window. |
| `src/ui/songtab.h:43`; `songtab.cpp:80-97,117-128` own a QWidget layout and SongTabQuickHost. `songtabquickhost.cpp:18-22` transfers the window into createWindowContainer and bridges focus. | Separate song-session lifetime from presentation and remove per-tab embedding. |
| `src/ui/workspaceui.cpp:146-160`; `workspaceui_tabs.cpp:24-105,126-157` use QTabWidget page identity for selection, insertion, removal, display order, and titles. | A QObject-only SongTab alone is insufficient for the chosen end state. Replace the song tab/page shell too. |
| `songtab.cpp:11-78,93-97` filters all input on its entire window until ready. | Keeping one such filter per tab in a shared window can block a ready page because another page is loading. |
| `src/ui/editordrawer/automationpage.cpp:150-220` identifies shortcut ownership by window identity and installs an application event filter. | A shared window requires active-page and item-ancestry ownership, including text-input precedence. |
| `src/ui/songview/quick/timelinequickview_window.cpp:185-201` dispatches keys with no activeFocusItem through a per-coordinator window filter. | Shared-window fallback must have one host-side dispatcher targeting only the eligible page, not one competing dispatcher per scene. |
| `quickpopupsession.cpp:22-33,119-147,278-280,327-354` uses a window filter, engine-root context, window content item, and window dimensions. | Popups need explicit page context and placement, plus one window-lifetime release-suppression authority. |
| `timelinequickview.cpp:169-170`; `drawerchrome.cpp:80-134`; `drawerchrome.h:271-272` use a fixed engine provider name with per-drawer image ownership. | Simply sharing engines creates image-provider collision/lifetime risks. Preserve page-specific images explicitly. |
| `src/ui/playheadoverlay.cpp:111-123,169-238`; `playheadrenderer_macos.mm:147-177,204-227` assume the timeline occupies the whole native view. | Map page-local geometry to window coordinates and explicitly hide background native playheads. QML visibility alone does not hide a CALayer. |
| `src/mainwindow.cpp:721-766` stops playback on selection change, unloads an unready selection, and queues guarded focus. | Preserve audio handoff and ready-tab guards; replace only the obsolete per-window activation rationale. |
| `src/checks/support/editorrig.h:28-34`; `host/tst_hostseams.cpp:118-203`; `host/tst_hostintegration.cpp:704-731` assume a view-owned window and per-tab window destruction. | Migrate the real fixture host and lifetime scenarios with the production ownership change. Do not re-pin obsolete destruction ordering. |
| `src/checks/scrollbar/tst_scrollbar.cpp:151-180`; `trackheaders/trackheaderfixture.cpp:87-128` call SongTab resize/show directly. | Existing behavioral assertions can survive, but even these otherwise-Quick suites require fixture migration. |

## Original target modules and ownership (historical)

```text
MainWindow / WorkspaceUi                    existing QWidget application shell
  WorkspaceQuickHost                      sole workspace window-container adapter
    one QQuickView + one QQmlEngine
      WorkspaceSongs.qml                  Quick tab strip + persistent page slots
        page viewport item A
          TimelineCanvas.qml A            item-local rendering and input
        page viewport item B
          TimelineCanvas.qml B

WorkspaceUi                               project/load/save/close policy
  ordered SongTab owners                  existing unique_ptr ownership retained
    SongTab : QObject                     document, timeline, bank lease, readiness
      SongView : QObject                  camera, selection, edit coordination
        TimelineQuickView : QObject       scene binding; borrows host engine/window
  SongTabsModel : QAbstractListModel       projection of that ordered collection
```

Names `WorkspaceQuickHost`, `WorkspaceSongs.qml`, and `SongTabsModel` are proposed. Keep the new workspace-presentation files together under `src/ui/workspacequick/`; do not scatter individual controls into top-level ui files. Keep existing SongView and SongTab names unless a necessary interface change justifies a rename. Use LSP for any rename.

### Session and collection contract

- SongTab retains its existing keyed identity, document/history ownership, shared timeline publication, bank lease, staged-load methods, readiness signals, and reload-state semantics. Change its parent type to QObject. It does not allocate an engine, window, QWidget, or layout.
- WorkspaceUi remains the sole owner of SongTab instances and project-operation decisions. `m_tabPages` becomes the authoritative display order as well as ownership order. A tab drag moves its unique_ptr in that collection; it does not recreate the session. Persistence reads that same order.
- SongTabsModel is a real Qt item-model projection, not another session registry. It borrows WorkspaceUi's collection and provides roles for stable song identity, session QObject, title, tooltip, and readiness. Add dirty/error roles only where the existing presentation actually needs them; do not invent a loading/error redesign.
- Model insert/remove/move notifications bracket the authoritative collection mutation. One cohesive mutation path owns both; QML never maintains a second array. Moves use correct beginMoveRows destination semantics and preserve the selected session by identity.
- `m_selectedTab` remains the selection authority. Publish it read-only to Quick, with a derived index if needed. QML emits select/close/move requests; WorkspaceUi validates identity and applies existing policies. Close requests never directly destroy a QML delegate or session.
- Preserve empty workspace, background open, single-tab replacement, force-new-tab open, restore without repeated activation, dirty-close cancellation, late staged-result tombstones, and project-switch teardown.

### Scene attachment contract

Implement a small explicit attachment interface on TimelineQuickView, conceptually `attachScene(QQmlEngine &, QQuickItem &viewport)` and `detachScene()`. Final spelling may follow the local implementation, but the following semantics are fixed:

- SongView construction is valid without a scene. Creating a session does not create a native surface. Attachment creates the existing TimelineCanvas under the supplied viewport and wires existing models/interactions. At most one scene is attached to a coordinator.
- The host owns the engine/window. The coordinator owns its canvas and child QQmlContext; visual parenting uses parentItem independently of QObject ownership. Keep models alive until the canvas and popup content are detached/destroyed.
- Use a child QQmlContext per canvas for existing context properties, populated before component creation. Never overwrite the shared engine's rootContext with page-specific values. Typed required properties may replace a context dependency where they simplify the existing module; do not force a wholesale QML interface rewrite.
- Register Quick types once, independent of constructing a timeline. The workspace host and test host use the same registration and resource path.
- Keep the existing per-page icon data. Give each attached drawer provider a unique engine-local identifier, publish its image URL prefix to its canvas, and remove it only after that canvas's image consumers are gone. Clear the drawer's raw provider borrow before removal. Preserve icon-revision cache invalidation. No replacement under the fixed global `drawerchrome` name.
- `quickWindow()` becomes a borrowed association through the attached item, not an ownership handle. Detached scene queries return null; domain updates remain valid. Preserve pending dirty domains and publish a complete scene when attached; do not manufacture empty timeline data as a fallback.
- Observe item size, effective visibility, window association, screen/DPR, and destruction. Scene geometry comes from item dimensions. Actual window/surface loss tears down native and input attachments while their owners remain live.
- Detachment cancels transient edits/audition without restoring focus, disconnects scene callbacks, releases grabs, clears QML borrows, destroys canvas/popup content, then releases context/provider resources. It never unloads the workspace QML root or destroys the shared window.
- A normal tab switch hides/shows persistent page subtrees. It does not detach/recreate scenes, reset cameras, rebind documents, or rebuild timelines. Do not add lazy eviction, pooling, or suspended-session infrastructure.

### Geometry, focus, and input contract

- TimelineBandLayout, TimeCamera, scene data, guides, and hit tests stay canvas-local. The viewport's origin is `(0,0)` even when its position in the workspace window is nonzero.
- Convert item-local/window/global coordinates only at actual input, popup, and native-compositor seams. Use Qt item mapping, not a hard-coded tab-bar offset. Keep fractional DIPs until the existing raster/device-pixel rounding seam.
- The workspace layout uses font-scaled geometry and axis-aligned page slots. Support translation, resizing, clipping, and DPR/screen changes; arbitrary rotated/animated 3D page transforms are not requested.
- A page is input-eligible only when selected, ready, attached, and effectively visible. Keep readiness authoritative in SongTab and selection authoritative in WorkspaceUi; eligibility is a derived presentation value, not another load-state machine.
- Readiness loss cancels that page's transient input immediately while preserving its visible content and persistent state. An inactive/unready page must not consume another page's key, wheel, pointer, IME, or shortcut events.
- Remove SongTab's broad per-window InputGate. Apply page eligibility at the page input delivery seam, including Quick text editors, scrollbars, popup entry, and C++ key fallbacks. Do not disable shared tab-strip controls or the whole workspace window while one song loads.
- Shared editing commands remain in SongView::handleEditKey and handleEditKeyRelease. TimelineInputItem and QML controls keep local-key first refusal. AutomationPage's pencil shortcut must be owned by the eligible page and actual focused subtree, not merely a matching QWindow.
- Move the no-activeFocusItem KeyPress/KeyRelease fallback from TimelineQuickView's window filter to one host-side dispatcher. It forwards once to the eligible selected page; it does not broadcast to all scenes. Page coordinators may observe lifecycle events but must not compete to consume window-global input.
- On selection change: cancel outgoing gestures/prompts/audition without focus restoration; mark it inactive; publish the new selection/audio handoff; reveal and enable the incoming page as readiness allows; request its existing active content surface. Guard any queued focus callback by live selected-session identity and readiness. Do not add historical focus memory.

### Popup and native-playhead contract

- Keep typed menu/form owners, draft validation, document revision guards, and QuickPopupSession behavior. Give each session its explicit page root and QML context for content placement and construction. Retain the overlay under the window content item and preserve the existing scene-coordinate anchor interface (`EventListPage.qml:172,580`; `RulerControls.qml:65`; `pianoroll_commands.cpp:348`). Compute the page rectangle in scene coordinates and clip/clamp/center within it; do not reparent the overlay into page coordinates and rewrite every caller unnecessarily.
- Popup content and its input shield are bounded to that page rectangle, not the whole workspace. The tab strip remains independently usable. A tab-strip activation cancels the old page's popup and switches once; ordinary outside clicks within the page retain the existing dismiss-and-swallow behavior.
- Mouse release suppression must survive removal of the page that swallowed its press. Use one workspace-window-lifetime input owner for this delivery fact, reused by the standalone test host; it stores only the outstanding swallowed button/sequence, not song/editor state. Page popup sessions must not install competing global swallow state.
- Escape, outside dismissal, deactivation, resize, readiness loss, page switch, owner replacement, and close retain their appropriate cancellation semantics. Never focus the outgoing page on a cancellation caused by switching or destruction. Preserve right-click retarget behavior and all note-off paths.
- Keep the macOS CALayer playhead. Map its canvas-local timeline column and clip regions into the shared window's native coordinate space. Include selected/effectively-visible page status in its visibility, not just window visibility. Suppress or clip it under page popups so the native layer cannot paint over a form; retain existing uncovered guide behavior.
- Keep the Quick playhead renderer on its existing non-macOS path. No silent platform substitution or new renderer.

## Ordered implementation work packets (historical)

Each packet requires source-current LSP references before exported-interface changes. Integrating owner freezes the stated interfaces before parallel implementation. Agents skip builds/tests/formatters while sibling edits are in flight; Main runs the union's validation after each integration checkpoint. Each packet updates its affected existing checks alongside production, not in a final catch-up phase.

### P1 — Remove direct widget utility dependencies

**Files:** QApplication call sites in `songview/pianoroll_commands.cpp`, `pianoroll_gestures.cpp`, `timeruler_interaction.cpp`, `trackheadermodel.cpp`, `quick/eventlistcontroller.cpp`, `quick/timelinequickview*.cpp`, `editordrawer/nodelane/gesture.cpp`, `velocityarea/velocityarea_interaction.cpp`, and `voicechangearea/voicechangearea.cpp`.

**Change:** use QGuiApplication for GUI-global font/button/modifier queries; QStyleHints through QGuiApplication for drag distance and wheel-scroll hints. Verify installed Qt declarations before selecting replacements. Preserve current wheel signs, platform drag thresholds, and live modifier queries. Remove obsolete direct QApplication includes/comments only in these migrated modules. Do not split shared layout/theme startup or add a style abstraction.

**Acceptance/checks:** same drag activation and scrollbar behavior; `rollcheck`, `scrollbar`, `automation-editing`, `velocity-editing`, `trackheaderquickcheck`. This may run in parallel with P2, with `timelinequickview.cpp` reserved to P2 and its utility edit integrated there once.

### P2 — Make viewport geometry item-local

**Files:** `songview.cpp` viewport methods, `songview.h`, `timelinequickview.h/.cpp`, `TimelineCanvas.qml`, `timelinebandlayout.h` comments as needed, `checks/support/timelinequickcheck.h`, existing host/guide geometry checks.

**Change:** expose the attached canvas viewport size and local-to-scene mapping through the existing Quick coordinator. Switch SongView geometry from QWindow dimensions to the root item. Keep one analytic layout authority. Observe root size changes rather than treating all window resizes as equivalent geometry. This packet can use the current window-owned canvas until P3 relocates ownership.

**Acceptance/checks:** put the real canvas beneath a translated and smaller parent item in a real Quick window; resize parent without resizing window. Ruler, roll, headers, drawer, scrollbars, event list, guides, pointer hits, and popup anchors use the correct local positions. Add the offset scenario in `host-adapter`/`playhead-guides`; run those plus `scrollbar`, `timelinepancheck`, and relevant editor-drawer suites. Native playhead completion is P5, not claimed here.

### P3 — Move scene creation out of SongView's window ownership

**Files:** `timelinequickview.h/.cpp`, `timelinequickview_window.cpp`, `songview.cpp`, `TimelineCanvas.qml`, `drawerchrome.h/.cpp`, drawer QML image consumers, `songtabquickhost.h/.cpp`, `checks/support/editorrig.h/.cpp`, dependent fixture constructors, host-seams tests.

**Change:** implement the attachment contract, per-scene context and provider identities, explicit scene teardown, and shared type registration. Remove `takeWindowForEmbedding()` and window-owning storage from TimelineQuickView. As a bounded intermediate state, the **existing** SongTabQuickHost creates/owns the per-tab host window and attaches the scene; SongTab remains QWidget until P7. This is the current host rewritten to consume the new interface, not a second compatibility path. Its entire implementation is deleted in P7.

**Check-host contract:** extend the existing EditorRig/support module with an explicit host owning engine/window/viewport and attaching a borrowed SongView. Both the document-driven rig and staged SongTab fixtures use that same real scene path. A SongTab fixture resizes/shows its host, never its session. Support nonzero viewport origin and more than one viewport in a window without introducing a fake renderer.

**Acceptance/checks:** a SongView exists and accepts document/state changes before attachment; two canvases in one engine show distinct song data and drawer icons; destroying one leaves the other interactive. Reattach only if required by the implemented surface lifecycle; do not invent reusable pooling. Rewrite obsolete hosted/unhosted transfer tests as scene-lifetime contracts. Run `host-seams`, `host-adapter`, plus all fixture-migrated suites listed below.

**Parallel fixture ownership after interface freeze:** one agent owns EditorRig/support; separate agents own roll/scrollbar/timelinepan/trackheaders fixtures and automation/velocity/eventviews/clipboard/drawer fixtures. They consume the frozen host interface and never edit the shared helper simultaneously.

### P4 — Make popup, readiness, and keyboard delivery page-scoped

**Files:** `songtab.cpp` InputGate, `quickpopupsession.h/.cpp`, `quickmenuhost.cpp`, `quickengine.h` callers, `timelinequickview_keyrouting.cpp`, `timelinequickview_window.cpp`, `timelineinputitem.*`, `automationpage.h/.cpp`, page root QML, existing selectionkey and popup tests.

**Change:** implement eligibility and page focus ancestry, scope popup creation/placement to its page/context, and introduce the single window-lifetime release-suppression owner at the actual host seam. Remove whole-window assumptions and duplicate filters as their callers migrate. Preserve typed prompt/menu logic and existing edit-key routing. During the intermediate per-tab host state, the same page-scoped implementation works with a single page; no separate legacy path.

**Acceptance/checks:** active ready A is editable while hidden B is unready; inactive B cannot toggle pencil mode; text entry retains local undo/clipboard; switch during drag or held audition cancels without committing into B; close A between dismissal press/release leaves B safe and editable afterward. Use `selectionkey` four-tier coverage, `automation-editing`, `eventviews`, `rollcheck`, and `host-integration`. These are real window/QML input scenarios, not direct calls to accept or command dispatch alone.

### P5 — Preserve native playhead under page composition

**Files:** `playheadoverlay.h/.cpp`, `playheadrenderer_macos.mm`, existing playhead/rendering/windowing checks. Coordinate common TimelineQuickView header additions through P3's integration owner before dispatch.

**Change:** consume root/window mapping and effective page visibility; translate and clip native geometry; detach on surface destruction before native handles die; retain the layer tree/re-attachment semantics already used. Account for page popup occlusion and root movement even if the window size does not change.

**Acceptance/checks:** at nonzero page origin the native playhead aligns with ruler and notes, clips out of the tab strip/hidden bands, disappears for background pages, and returns correctly after switching, resizing, and platform-surface recreation. Use `playhead-guides`, `rendering-playhead`, `rollwindowingcheck`, and `mainwindow-routing-native`; actual macOS window smoke is mandatory. Offscreen Quick framebuffer success does not prove CALayer correctness.

**Parallelism:** P4 and P5 are independent after P3's geometry/lifecycle interface is fixed. Neither edits the other's files.

### P6 — Implement the Quick song-tab shell and model

**Files:** proposed `src/ui/workspacequick/songtabsmodel.h/.cpp`, `WorkspaceSongs.qml` and a cohesive tab-strip QML file only if warranted, proposed workspace host, `workspaceui.h` model exposure under its integration owner, existing QML/build registration.

**Change:** implement the collection/selection contract. Quick strip
preserves selection, close buttons, title/dirty marker, tooltip, overflow
access, font-scaled chrome, and non-stealing editor focus. No pointer
reorder. `Repeater` creates one persistent `FocusScope` page slot per model
row as a direct `StackLayout` child; it never resets a song scene. Preserve
accessibility names, selected state, and the shell's existing keyboard
access through semantic commands.

**Acceptance/checks:** actual Quick strip click selects the correct
session; closing a nonselected tab does not change the selected document;
dirty-close cancellation leaves the page intact; display order is open
order; narrow width leaves every tab reachable; loading one tab never
blocks selection/close of another. Extend `tabcheck` and
`mainwindow-routing-input` with real strip input, plus focused model
invariant checks only where invalid notifications/order would affect
consumers.

**Dependency:** may be implemented in parallel with P4/P5 after P3. WorkspaceUi shared mutations remain reserved for P7's owner. P6's host/model must be complete and exercised through the real check host, not merged as unused scaffolding.

### P7 — Atomically cut over SongTab and WorkspaceUi

**Files:** `songtab.h/.cpp`, `workspaceui.h/.cpp`, `workspaceui_tabs.cpp`, other WorkspaceUi collection callers, `mainwindow.cpp` focus handoff, workspace Quick host, `songtabquickhost.h/.cpp` deletion, CMake source/resource lists, remaining SongTab fixtures.

**Change:** SongTab becomes QObject. Replace QTabWidget setup and all tabForWidget/indexOf/currentWidget/addTab/removeTab paths with model/identity operations. Attach persistent page subtrees through the one workspace host. Remove the old host, embedding-transfer interface, obsolete widget-focus bridge, and ownership comments. MainWindow embeds the workspace window once. Preserve project worker, save/close decisions, bank leases, document-before-view borrow ordering, and MainWindow's audio publication behavior.

**Destruction protocol:** publish null selection/unload audio before destroying the selected session's borrowed bank; cancel transient input; detach and destroy that page's scene while its models are live; remove its model row/page references without exposing a dangling session; destroy the session. During project/application teardown suppress intermediate selection publication, detach all pages, destroy sessions, then destroy the workspace scene/window/engine in valid ownership order. Define one owner for each QObject and native window; no unique_ptr/container double ownership.

**Acceptance/checks:** open/reload/replace/close/restore multiple songs; isolated undo/camera/selection; live bank replacement; late updates after close ignored; readiness order permutations; ready-song failure keeps existing loaded state. Closing one tab never destroys the shared window or damages another page. Run `tabcheck`, `sessioncheck`, `selftest-timeline`, `selftest-transport`, `selftest-workspace`, `mainwindow-routing`, `selectionkey`, and `host-integration`.

**Integration rule:** P7 consumes P3-P6 together. Do not land a QWidget-free SongTab against QTabWidget, or share a window while the old broad input gates/native visibility rules still exist.

### P8 — Prove the final integrated surface

Run the final matrix below and a bounded actual-application smoke. Resolve every failing assertion before handoff. Run the complete `deno task verify` once for this cross-cutting ownership/input change, after targeted fixes settle. Explicitly run opt-in native panning separately. Compare the same song, viewport, and gesture before/after when measuring performance; do not infer a CPU improvement from fewer windows alone.

After smoke proves the behavior, reconcile the existing blueprint/status notes with the implemented scope, remove temporary experiment files, and remove obsolete test helpers only after their last callers migrate. Do not perform unrelated architectural cleanup or create arbitrary file fragments to meet a line-count target.

## Check migration ledger (historical)

Harness names below are from `src/checks/checkcatalog.cpp`; directory names are not necessarily runnable suite names.

| Existing coverage | Required change / proof |
| --- | --- |
| `host-seams` — `src/checks/host/tst_hostseams.cpp` | Delete old window-transfer/unhosted-window ownership assertions. Cover idempotent scene detach with live models and continued editing of a sibling scene. Keep camera/state behavior assertions. |
| `host-integration` — `src/checks/host/tst_hostintegration.cpp` | Replace `songTabTeardownDestroysQuickWindowBeforeDocument`; exercise closing one page while a sibling/shared window stays live, then project teardown with queued popup work. Do not merely assert a new type or a reordered list of destroyed-signal strings. |
| `host-adapter`, `playhead-guides` | Add translated/smaller viewport scenarios; confirm actual hit target and rendered guide/band alignment. Reuse canonical item-space helper. |
| `rollcheck`, `rollcheck-static`, `rollwindowingcheck`, `scrollbar`, `timelinepancheck`, `timelinepan-native`, `trackheaderquickcheck`, `trackheader-model` | Migrate SongTab/window construction and root-to-scene coordinate injection; preserve note edits, pan/zoom/drag, header reorder, and camera assertions. `trackheader-model` may need only fixture changes. |
| `automation-editing`, `velocity-editing`, `clipcheck`, `eventviews-chrome`, `eventviews-edits`, `eventviews-remap`, `eventviews-playhead` | Migrate SongTab fixtures and popup coordinates; retain document/undo semantics and real Quick editor behavior. Add only cross-page failure cases absent from selection/host suites. |
| `editor-drawer`, `automation-raster`, `velocity-page`, `automation-domain`, `automation-presentation`, `automation-hover` | Reuse changed EditorRig/presentation fixtures; retain domain behavior. Do not claim these files are untouched merely because their assertions are widget-independent. |
| `selectionkey-core`, `selectionkey-gesture`, `selectionkey-window`, `selectionkey-local-input` | Preserve semantic core tests; window/local tiers exercise shared-window active-page ownership, text precedence, cancellation and press/release. MainWindow fixture windows remain valid QWidget shell hosts. |
| `tabcheck`, `sessioncheck`, workspace selftests | Preserve load/save/reload/lease/undo/audio assertions; add actual strip select/close, persist-and-restore open order, and two-page readiness isolation. |
| `mainwindow-routing-input`, `mainwindow-routing-state`, `mainwindow-routing-lifecycle`, `mainwindow-routing-native` | Preserve app-action/audio semantics; replace obsolete per-tab native activation assumptions and any tab-widget drivers. Verify queued focus cannot return to a closed/background page. |
| `rendering-playhead`, `playhead-guides`, `rollwindowingcheck` | Native offset, hidden-page and popup occlusion behavior; shared-window surface teardown/recreation. |

Before each interface cutover, run LSP references for SongTab, TimelineQuickView attachment/window methods, and any renamed helper. Include additional fixture consumers reported by LSP, notably pitchbend, onboarding, voicegroup-save, and browser-driver support. The ledger is not permission to ignore a compile-breaking caller outside its listed suites. Register new cases inside existing `src/checks/` suites where cohesive; new standalone suites require an independent behavior/fixture reason.

### Regression scenarios worth retaining

1. Two live pages, B unready: edit A by actual pointer/key input; verify only A's document/undo changes. Reverse readiness/selection and verify the same isolation.
2. Pencil shortcut with two open automation drawers: only the eligible page toggles; text editor keys remain text, not global commands.
3. Open a prompt or hold voice audition on A; select B or close A; no stale edit, no outgoing focus restoration, note-off occurs, B remains interactive.
4. Dismiss A's popup with an outside press; remove A before release; release neither edits nor leaves a grab on B. A subsequent complete click on B works.
5. Canvas below a strip and inside a smaller translated viewport: edit the intended note/node, pan/zoom, open a popup near an edge, and align guides/playhead after resizing only the viewport.
6. Reorder actual Quick tabs; selected session, per-tab state and undo survive; close/reopen the workspace and observe the same display order and selection.
7. Close one page with a queued scene update while another remains open; sibling editing succeeds. Project teardown then cancels pending UI/audio work without dangling consumers.
8. On macOS, background A's playhead cannot paint over B or the tab strip; popup/native clipping and surface recreation remain correct.
9. Two pages in one engine keep distinct event rows, header labels, and drawer icons; destroy/reopen one and reapply theme without stale providers or cross-page context data.

Keep these as consumer-visible behavior tests, not source scans, class-name checks, forwarding assertions, or default-value snapshots. Exact pixel comparisons belong only where the existing rendering contract requires them.

## Verification commands and runtime policy (historical)

The current runner builds before verification and accepts repeated filters (`tools/cli.ts:128-181`). It rejects `--no-build`. There is no `deno task check`.

```bash
# Geometry and attachment checkpoint
deno task verify --filter host-seams --filter host-adapter --filter playhead-guides --filter scrollbar --verbose

# Editor fixtures and page-local input
deno task verify --filter selectionkey --filter automation-editing --filter velocity-editing --filter eventviews --filter rollcheck --filter clipcheck --verbose

# Workspace cutover
deno task verify --filter tabcheck --filter sessioncheck --filter mainwindow-routing --filter host-integration --filter selftest --verbose

# Native rendering and bounded performance comparison
deno task verify --filter rendering-playhead --filter rollwindowingcheck --filter timelinepan-native --verbose

# Final cross-cutting gate
deno task verify
```

Check all other fixture-migrated suites from the ledger at their packet checkpoint; the command groups above are not a substitute for that inventory. Format the changed C/C++/Objective-C++ union through `deno task format`, once per settled integration wave. The repository formatter explicitly rejects QML (`tools/format.ts:9-12`); preserve its existing formatting conventions and validate it through real component loading and interaction.

Native acceptance requires a real application window: two songs, tab
selection/close, note and automation edits, popup/audition cancellation,
readiness transitions, playback, panning, resize, and native playhead
clipping. Run native/window-system checks sequentially so they do not
steal focus from each other. If desktop use is unavailable at
implementation time, report native acceptance as pending rather than
treating offscreen checks as equivalent. Use bounded measurements and
screenshots; do not collect Instruments trace archives for this
migration.

## Dispatch and completion criteria (historical)

Dependency order: `P1 || P2` → `P3 + its disjoint fixture migrations` → `P4 || P5 || P6` → `P7` → `P8`. P1's edits in shared files go through the reserved owner. Parallel waves must define their header/QML contracts before spawning; only the integration owner edits shared lifecycle headers, WorkspaceUi, and build registration.

Every implementation handoff contains: exact owned files, consumed/provided interfaces, prohibited sibling edits, observable acceptance scenarios, existing harness filters, and explicit deletions. Report discovered dependencies early; do not let each agent invent its own scene host, tab registry, readiness state, or focus policy.

Complete means: Quick song strip/pages used by the actual application; SongTab and SongView are widget-free; no per-song window ownership remains; all callers and fixtures use the new seam; input/popups/native layers isolate pages; session/audio/undo/persistence semantics survive; all affected checks and actual-surface acceptance pass. The one outer QWidget embedding adapter is explicit and intentional, not a hidden per-tab fallback.
