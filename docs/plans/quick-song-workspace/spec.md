# Quick song workspace specification

## Purpose and baseline

First permanent vertical slice toward an all-major-Quick main window: replace
the song tab bar AND per-song window hosting with one Quick song workspace.
Retain the existing QWidget MainWindow, transport, browsers, docks, dialogs and
application startup during this slice. Only the outer embedding adapter is
transitional; do not construct a replacement temporary shell.

Authoritative source baseline: `fork-main` at
`9f651a32406508f35c87df03902d956705df104c`. `SongView` is already QObject.
`SongTab` is QWidget; `TimelineQuickView` creates a QQuickView per song;
WorkspaceUi owns the SongTab vector but QTabWidget currently supplies display
order/selection. The old composition worktree is reference material, never the
branch to merge or wholesale cherry-pick. The earlier
`docs/old/songtab-quick-composition-plan-failed.md` and its follow-on
`docs/old/qtabwidget-quick-alternative-plan-failed.md` are archived failed
attempts, superseded for this execution.

The prototype in the main checkout's
`src/ui/songview/quick/composition-prototype/` is empirical reference, not a
production dependency and not assumed present in a new worktree. Its Qt 6.11
runner passed 18 results including init/cleanup; a separate real
QWidget/container/QQuickView desktop smoke established QAction Space precedence
and literal text Space. It did NOT exercise real QuickPopupSession, CALayer
composition, project persistence or production shared-engine resources. Those
require the checks below.

## S1 — Ownership and permanent structure

MainWindow retains its existing QWidget central-widget slot. WorkspaceUi owns
`std::vector<std::unique_ptr<SongTab>> m_tabPages` and `SongTab *m_selectedTab`;
this vector becomes the one display/persistence order. MainWindow's existing
selected pointer is an audio/UI borrow, not a second selection authority.
SongTab becomes `QObject` with `SongTab(SongName, QObject *parent = nullptr)`;
WorkspaceUi constructs it without a QObject parent because the unique_ptr owns
it. Retain document/history, timeline, bank lease, staged load, signals and
reload semantics. No window, engine, page item, layout or InputGate in SongTab's
final state.

`WorkspaceQuickHost` is the one outer adapter, under `src/ui/workspacequick/`.
It owns one QQuickView through one QWidget::createWindowContainer (the container
takes ownership of the window); WorkspaceUi owns the adapter and destroys
sessions/scenes before the adapter. Its interface is
`WorkspaceQuickHost(SongTabsModel &, QWidget &parent)`,
`QWidget *widget() const`, `QQuickWindow *window() const`,
`void focusEditor(Qt::FocusReason)`, `void focusTabs(Qt::FocusReason)`, and
signals `selectRequested(SongTab *)`, `closeRequested(SongTab *)`,
`moveRequested(SongTab *, int finalRow)`. The QObject signal conversion at the
QML seam checks type; WorkspaceUi validates live membership. No page registry,
manual page creation, resize loop or selection policy belongs here. The adapter
publishes the appearance value below and refreshes it on the existing
application appearance-event path; no new theme provider QObject is required.

`WorkspaceSongs.qml` has required properties `var tabs` and `var appearance`,
signals `selectRequested(QtObject session)`, `closeRequested(QtObject session)`,
`moveRequested(QtObject session, int finalRow)`, and functions
`enterEditor(reason)` and `enterTabs(reason)`. It knows no QWidget, MainWindow
pointer or per-song host. It contains TabBar-based SongTabStrip plus an editor
FocusScope (`focus: true`), StackLayout and Repeater over `tabs`. Root is also
FocusScope with `focus: true`. Each delegate is a persistent clipped FocusScope,
identity = session QObject; focus/enabled =
`(session === tabs.selectedSession) && ready`. Stack currentIndex is
tabs.selectedIndex. Empty-state content is outside the stack. Reorder uses model
moves, never reset/recreate. The delegate root FocusScope itself is the viewport
passed to attachToPage. Consume the separate `quickView` model role and call
`quickView.attachToPage(delegateRoot)`; do not invent a session.quickView
property. On row removal Qt's Repeater retires its delegate. Resource safety
must not depend on synchronous delegate destruction: S2 detaches the canvas
first. Do not add a removal signal, manual delegate.destroy(), or a QML
destruction callback into a potentially retired session.

Appearance is an explicit value input, not an unspecified global role map.
Task15 builds a QVariantMap, supplies `appearance` in the root's initial
properties, and replaces that writable property with root->setProperty after
ApplicationPaletteChange or ApplicationFontChange when the value changes. The
adapter installs an event filter on the application instance, following the
existing PitchBendEditor appearance-event path; a plain QObject does not receive
those events directly. Ignore unrelated events; do not rebuild it on pointer
moves or scene publication. Task14 forwards the same value to SongTabStrip's
required `var appearance` property. A future Quick outer shell can provide the
same map without the QWidget adapter. Reuse the existing per-owner QVariantMap
delivery pattern; do not add a workspaceChrome object, root-context font globals
or per-tab appearance copies.

Frozen keys and sources:

| Key                                        | Value                                                                |
| ------------------------------------------ | -------------------------------------------------------------------- |
| `font`                                     | QGuiApplication::font(), with the application's installed typography |
| `tabFont`                                  | Same font with QFont::DemiBold, matching the existing tab stylesheet |
| `closeExtent`                              | layout::fontPx(1.0)                                                  |
| `rowHeight`                                | layout::chromeRowHeight(font, closeExtent)                           |
| `horizontalPadding`                        | layout::space(layout::Space::Two)                                    |
| `verticalPadding`, `spacing`, `radius`     | layout::space(layout::Space::Half)                                   |
| `borderWidth`                              | layout::singlePixel()                                                |
| `tabPaneBackground`                        | themes::color(Role::tab_pane_background)                             |
| `tabBackground`, `tabText`                 | Role::tab_background, Role::tab_text                                 |
| `tabHoverBackground`, `tabHoverText`       | Role::tab_hover_background, Role::tab_hover_text                     |
| `tabSelectedBackground`, `tabSelectedText` | Role::tab_selected_background, Role::tab_selected_text               |
| `tabOutline`                               | Role::tab_outline                                                    |
| `background`, `text`, `outline`            | Role::window_background, Role::window_text, Role::palette_outline    |
| `disabledText`, `focus`                    | Role::disabled_text, Role::focus_outline                             |

Every Role entry is resolved with themes::color; colors are QColor values. QML
measures intrinsic label widths using tabFont, uses rowHeight for the row and
square close-button hit area, and uses closeExtent only for its glyph.

## S2 — Session model and mutations

`SongTabsModel final : QAbstractListModel` has
`SongTabsModel(WorkspaceUi &owner, QObject *parent = nullptr)`,
`QObject *selectedSession() const`, `int selectedIndex() const`, Q_PROPERTYs of
those names with `selectionChanged()` / `selectedIndexChanged()`, and normal
rowCount/data/roleNames overrides. Roles: `songKey` (SongName.value), `session`
(QObject*), `quickView` (QObject* coordinator), `title`, `tooltip`, `ready`.
Title preserves refreshTabTitle exactly: document label, falling back to song
name, with '*' appended only while document().isDirty(). Bank dirtiness affects
save policy, not the tab label. Tooltip remains document().midPath(). Do not add
a second dirty/error state model. WorkspaceUi grants friendship; the model
borrows its vector and pointer, owns neither, and reads the title via new
private `QString tabTitle(const SongTab &) const`. Exported C++-owned QObject
borrows are marked QQmlEngine::CppOwnership before QML sees them. The model
NOTIFY signals are exactly `void selectionChanged()` and
`void selectedIndexChanged()`: neither carries a payload. Receivers read the
corresponding getter; no selectedSessionChanged alias is introduced.

Model notification methods are private, called only by friend WorkspaceUi:
`void beginInsert(int row)`, `void endInsert()`, `void beginRemove(int row)`,
`void endRemove()`, `bool beginMove(int from, int finalRow)`, `void endMove()`,
`void notifySelectionChanged()`, `void refresh(SongTab *)`. They bracket the
owner's actual vector mutation in the same synchronous operation. If beginMove
returns false, the owner must not mutate the vector or call endMove. It returns
the underlying beginMoveRows result. `beginMove` uses destinationChild =
finalRow + 1 for a forward move, finalRow for a backward move; API finalRow is
always the final index after removal/reinsertion. No-op/invalid requests issue
no begin/end pair. Publish derived index after every structural operation that
changes it even when selected identity is unchanged; emit selected-session
notification only when that identity changes. Do not feed
TabBar.currentIndexChanged back as a select request. For drag requests QML sends
the source session identity and release-hit final row; WorkspaceUi resolves the
current source row from its vector. The tab delegate's live index can skip a
same-row request, but no press-time row is stored and no model get/row-lookup
API or parallel identity map is added.

WorkspaceUi retains `selectSongTab(SongTab *)` and adds
`moveSongTab(SongTab *, int finalRow)`, `selectAdjacentSongTab(int step)`,
`focusSongEditor(Qt::FocusReason)`, `focusSongTabs(Qt::FocusReason)`. Keep
existing private `selectTab`, create/remove/close helpers, persistence and
staged-update handlers. `publishSelectedIfChanged` can be removed once it has no
widget-derived input; do not keep a compatibility alias. Selection validates
membership before dereferencing a possibly stale request. Background open and
late readiness never steal selection or focus. Existing restore,
replacement/new-tab, dirty-close/save cancellation, closed-load tombstones and
bank handoff remain unchanged.

Ordinary switch: cancel outgoing transient input/popup without forced focus
restoration; change m_selectedTab; synchronously emit selectedSongTabChanged for
existing audio handoff; notify model identity/index; rebuild dependent chrome
and persist with the existing restore/teardown suppression. Do not detach either
scene. No selection signal on reorder of the same selected object. Persist
actual vector order.

Selected close after existing policy allows it: cancel transient input; choose
the next row if present, otherwise previous, otherwise null; synchronously
publish successor/audio handoff while old session/lease is live; detach old
scene; beginRemove, move its unique_ptr to a local retirement variable and erase
row, endRemove, publish the successor's new index, then destroy retired session.
A background close does not switch/unload the selected song. Full teardown:
publish null/unload audio first; suppress intermediate selection/persistence;
detach all scenes while models live; remove rows under valid notifications;
destroy sessions; only then destroy workspace window/engine. Never use a model
reset for ordinary close/reorder.

## S3 — Explicit scene interface

Final TimelineQuickView owns no QQuickView/QQmlEngine. Its constructor creates
nonvisual coordination only. Keep existing constructor parameters,
quickWindow/rootObject/popupSession and domain-update methods. Add:

- `void attachScene(QQmlEngine &engine, QQuickItem &viewport)`.
- `Q_INVOKABLE void attachToPage(QQuickItem *viewport)` (QML adapter: obtain
  qmlEngine(viewport), require completed item with window, then call
  attachScene; not a second implementation).
- `void detachScene()` (idempotent; reattachment supported).
- `QQuickItem *viewportItem() const` and `bool isInputEligible() const`.
- Retain `windowAboutToDetach()` spelling, now once per live association before
  window/native teardown, plus existing viewportChanged notification for item
  geometry/association changes.

Keep the existing qt_add_qml_module-generated Porydaw.Ui type registration and
qrc component loading. This extraction needs no new registerQuickTypes facade or
duplicate imperative registration.

Remove takeWindowForEmbedding, detachWindow, owned-window members and
root-window setSource unload behavior. Final removal of the existing
embeddingFocusRequested signal is task 21, not a new replacement signal.
attachScene requires a live window on viewport and at most one attachment;
duplicate attachment to the same viewport is inert, another attachment without
detach is a programming error diagnosed through the existing
construction-failure policy, not a silent fallback. attachToPage is called once
after QML component completion AND window association, independent of readiness;
loading pages still have scenes, but are disabled. Construction/completion flags
are attachment facts, not a lazy loading framework. A newly completed zero-sized
viewport is valid. Attach immediately, use the existing local geometry
calculation at that size, and let subsequent width/ height notifications
republish layout. Do not wait for positive size or readiness, invent a
placeholder timeline, or suppress the later size update.

Create the child with `new QQmlContext(engine.rootContext(), this)` inside the
coordinator: rootContext() already returns a pointer. Install the exact existing
canvas context properties before QQmlComponent creation; never overwrite shared
rootContext with page values. Create TimelineCanvas as a coordinator-owned
QQuickItem with viewport as visual parent; the visual parent is not a second
QObject owner. Retain TimelineQuickScene/model data independently of canvas
lifetime. rootObject is canvas; quickWindow is a borrow of viewport.window and
null detached. Match viewport dimensions and emit geometry updates from item
width/height, association, screen/DPR; no window-sized layout assumption.

Detached domain updates remain valid: retain/OR dirty domains and current domain
state; suppress only publication without a scene; attachment performs a complete
current-state publication. No empty timeline replacement or lost dirty flags.
Window hide/deactivate cancels page transients; viewport effective hide/disable
also cancels. Reparenting to a different window loses the old association
through detach; no automatic scene pooling or transfer machinery. A later
explicit attach is supported. Hosts must detach before destroying engine/window;
viewport destruction is also a guarded fallback detach. Destroy native
attachments while the old window is live.

Detach ordering: stop scene timers; cancel popup/gestures/audition without focus
restoration; clear key callbacks and interaction borrows; disconnect window/item
associations; destroy popup session (including deferred popup QObjects) and
canvas while model borrows live; clear drawer provider borrow, remove provider;
destroy child context; clear root/viewport/window borrows. Never destroy shared
engine/window or workspace root. Emitting windowAboutToDetach must precede loss
of the live native window and must be reentry-safe. Use existing
`SongView::cancelTransientInput()` without arguments; it already cancels popups
without restoring focus. The false argument belongs to
`QuickPopupSession::cancel(false)`, not to a new SongView overload.

## S4 — Focus, eligibility and keyboard

TimelineCanvas root becomes FocusScope with `focus: true`; existing Keys
fallback stays there. Popup visual descendants also stay inside this canvas
scope (S5). Qt owns focused descendants. The page scope controls eligibility;
`isInputEligible()` reads attached viewport + canvas effective
enabled/visible/window association, not a second stored ready/selected flag.
Gate scene-root/item policy dispatch and QML scrollbar mutators at this seam. On
eligibility loss cancel interactions and audition immediately without
committing; only ungrab a mouseGrabberItem descended from this canvas/popup,
never a sibling page or tab-strip grab.

Remove TimelineQuickView's window-level KeyPress/KeyRelease no-activeFocus
fallback; do NOT move it into a new host dispatcher. Retain TimelineInputItem
interaction-first delivery, TimelineCanvas declined-key delivery,
SongView::handleEditKey/handleEditKeyRelease and EditActions semantics. With no
focused editor, editor-only commands do not invent a recipient. Existing QWidget
text arbitration and EditActions::installWindowShortcuts(QWidget&) remain
because the outer shell still contains QWidget controls. PencilToggle already
lives in editkeyrouting.cpp at this baseline: there is no AutomationPage
app-wide key filter to replace. Keep AutomationPage::setInputWindow for prompt
cancellation on window deactivation, not pencil dispatch; bind/unbind it at
scene association changes.

Only explicit user entry invokes the outer focus adapter. Native tab pointer
selection uses Qt.NoFocus/Qt.TabFocus controls that do not steal editor focus on
press; QML page bindings perform the switch. Keyboard strip entry is explicit,
not a selection side effect. No forceActiveFocus on ordinary selection, ready
notification, row movement, popup cancellation, window activation or timer.
Native popup-local restoration on ordinary user dismissal is retained; forced
restoration during switching/destruction is not. With no open songs,
focusTabs/F6 and focusEditor are no-ops: do not focus the empty-state label. The
existing transport command id is `transport.play_pause`; use Registry discovery
and the existing WorkspaceUi::playPauseRequested observation rather than
guessing QAction object names.

`focusBand` and `focusEventListInput` retain their names/parameters, but return
false without focus/activation requests if the input item is absent OR the scene
is ineligible; true means an eligible request was made. This also guards
programmatic mode restoration on a background/loading song. Task1 establishes
the guard, task21 removes the old embedding signal without weakening it.
`WorkspaceUi::openSongFromList` (task16, workspaceui_tabs.cpp) enters the editor
area only after an actual accepted user open/activation; rejected/busy opens do
not move focus. Restore/background staging uses its existing non-activating
paths. Explicit next/previous window commands enter the editor after a real
selection change; ordinary model selection notification does not. MainWindow
task18 removes the queued handoff rather than adding an origin flag or another
delayed callback.

Add keymap Registry window commands `view.next_song_tab`
(QKeySequence::NextChild), `view.previous_song_tab` (PreviousChild),
`view.focus_song_tabs` (F6). Attach their QActions to existing MainWindow; first
two call selectAdjacentSongTab(+1/-1), third focusSongTabs. They replace
QTabWidget's implicit next/previous navigation and provide explicit accessible
strip entry. No duplicate QML shortcuts. Existing file.close_tab and transport
actions stay unchanged. Popup/text ShortcutOverride arbitration remains intact.
Left/Right use the proven explicit TabButton/KeyNavigation pattern: bind
KeyNavigation.left/right to adjacent Repeater tab items; the matching
Keys.onLeftPressed/onRightPressed handler emits exactly one selectRequested for
that neighbour's session, then leaves event.accepted false so native
KeyNavigation moves focus. A missing neighbour is inert. Use the live delegate's
session, not an invented QAbstractListModel.get API. Do not infer arrow
selection from onClicked or feed currentIndexChanged back into the controller.
Enter/Return request the focused tab's selection and explicitly enter the editor
scope. Space is never claimed by persistent tab chrome. Window next/previous
commands wrap cyclically across live rows, preserving QTabWidget::keyPressEvent
behavior. Empty/single-tab or no selected session is inert; loading rows remain
selectable. This differs intentionally from local Left/Right at strip ends,
where a missing KeyNavigation neighbour is inert. focusEditor can enter the
editor-area scope while a selected song is loading; it never focuses an
ineligible child. Readiness subsequently enables the scoped descendant without a
queued repair.

## S5 — Real popup seam, not the prototype Popup

Use the existing QuickPopupSession and typed forms/menu owners. Change
constructor to
`QuickPopupSession(QQuickWindow &, QQmlContext &, QObject *parent = nullptr)`
and add `void setCanvasScope(QQuickItem &canvasScope)` and
`QQmlContext *qmlContext() const`. Attachment order resolves the construction
dependency: create context and popup session first, install the non-null
quickPopupSession context property, create TimelineCanvas, call setCanvasScope
exactly once for that session, then enable interaction binding/publication.
ensureLayer/open entry points decline until canvasScope exists; no popup is
opened during canvas construction. Its layer is visually parented to
canvasScope, NOT window.contentItem or a sibling of the canvas. Layer
fills/clips the page; canvas is the FocusScope from S4, so popup focus stays
within its native scope chain. The layer keeps QObject ownership in the session.
Construct all popup QML with the page context. No new popup framework or
tab-focus cache.

Live parent distinctions:

| Object                    | QObject owner     | Visual parent                          |
| ------------------------- | ----------------- | -------------------------------------- |
| QuickPopupLayer           | QuickPopupSession | TimelineCanvas canvasScope             |
| Menu panel                | Popup layer       | Popup layer                            |
| Form/surface content root | QuickPopupSession | Existing form container or popup layer |

Retirement clears visual parenting, not these QObject ownership chains.

Public menu anchors, outsidePressed, outsideRightPressed and note-anchor inputs
remain WINDOW-SCENE coordinates. Convert only at sinks with QQuickItem mappings:
QuickMenuHost root placement in applyLevel via overlayRoot()->mapFromScene
(createPanel handles construction, not anchor conversion); submenu geometry
remains overlay-local; measure and clamp panels using overlayRoot()->size, not
window size. PitchBendEditor::placeContent converts its scene note rect via
overlayRoot()->mapRectFromScene and clamps locally. QuickPopupLayer maps
underlay press coordinates to scene before outsidePressed. Keep all existing
caller signatures/global retarget conversions. Form centering/clamping uses page
dimensions. QuickMenuHost::createPanel uses session.qmlContext; panels are
QObject/visual children of the popup layer so they cannot outlive its context.
Remove quickengine.h only after all remaining usages are migrated to explicit
context/engine.

In QuickPopupSession::end, clear live borrows and visually detach retiring
content/layer immediately, but KEEP their QObject parent as the session while
deleteLater is pending. No retiring-object vector or extra owner is necessary.
Session destruction synchronously deletes all remaining child QObjects before
page context teardown. Preserve cancellation signals, draft/revision validation,
local Escape/dismiss restoration, right-click retarget and note-off.
Resize/readiness loss/switch/close use cancellation without forced focus. The
tab bar is outside the input shield; a pointer tab activation switches exactly
once even with a form open.

`QuickWindowInput` is a new window-owned QObject in songview/quick with
`static QuickWindowInput &forWindow(QQuickWindow &)`,
`void swallowRelease(Qt::MouseButton)`. Store outstanding buttons in one
Qt::MouseButtons bitmask, not an allocating set or a single-button slot.
Consuming a matching release or fresh matching press/double-click clears only
that button; window deactivation/hide/close clears all. It outlives individual
popup sessions, including when a tab closes between dismissal press and release.
It owns NO selected scene, key dispatcher, editor pointers, focus history or
activation policy. QuickPopupSession delegates arm/clear consumption to it
instead of owning m_swallowedReleaseButton. It must not consume a tab-strip
click merely because another page has a popup.

## S6 — Shared engine resources

DrawerChrome replaces one-shot releaseIconProvider with
`QQuickImageProvider *createIconProvider()`, `void clearIconProvider()`, and
`QString iconUrlPrefix` property/setter/notification. The engine owns the
returned provider; DrawerChrome retains only a cleared-before-removal borrow.
Create and initialize from current appearance on each attachment, using existing
icon generation/revision behavior; detached updates must not dereference the
provider. No duplicated icon state or provider registry.

Each attachment receives a fresh monotonic GUI-thread-generated provider name
`drawerchrome_<n>` (never pointer-address identity, never reused within an
engine/cache lifetime). Coordinator registers it and sets full image:// prefix
before canvas creation. DrawerChromeLayer's two Image sources use this prefix
plus existing icon name/revision. Remove only that attachment's provider after
all its image-consuming QML is destroyed. Closing/reloading A must not
invalidate B's icons; reattaching A must not retrieve cached images from an
earlier provider incarnation. No asynchronous provider mode or new threading. Do
not rely on removeImageProvider deleting the provider synchronously. Qt owns
provider and texture retirement after removal; clear the borrow first, never
delete the provider manually, and add no thread/deferred-deletion tracker.

## S7 — Geometry and native playhead

SongView::resolveViewportGeometry reads the attached viewport's size;
TimelineBandLayout, TimeCamera, selection and hit-test coordinates remain
canvas-local. Use existing refreshViewportLayout choreography. Do not scatter
tab-strip offsets into band code. Support translated/resized/clipped
axis-aligned pages, screen/DPR changes and actual native surface
loss/recreation; rotations/3D transforms are out of scope.

PlayheadOverlay maps the canvas-local timeline-column rect into window scene
coordinates with QQuickItem mapping, intersects it with effective page/ancestor
clipping and window bounds, and applies pixel rounding only at the existing
native seam. Its effective visibility includes attached/selected-ready effective
page visibility and input eligibility, not just QWindow.isVisible. Keep macOS
CALayer renderer and the existing non-mac Quick renderer. For an open page
popup, hide that page's native playhead entirely; restore it after dismissal if
otherwise eligible. Do not substitute a renderer or implement complex partial
native-popup occlusion. The same popup visibility policy applies to the Quick
playhead for consistent observable behavior. WindowAboutToDetach and
PlatformSurface destruction remove the native attachment before losing the
NSView; never force native surface creation merely to query geometry. No
per-frame scene reconstruction. On scene association, PlayheadOverlay subscribes
to the existing QuickPopupSession::isOpenChanged signal and immediately samples
isOpen(). That notification updates visibility on open and dismissal, without
waiting for viewportChanged or a later frame. Disconnect the association on
detach; no new popup-state signal or callback registry is needed.

## S8 — Verification interfaces and required outcomes

Add test-only `checks::QuickSceneHost` in
src/checks/support/quickscenehost.h/.cpp. Interface: static
`create(SongView &, const QSize &, QString &error)` and
`create(SongTab &, const QSize &, QString &error)` returning unique_ptr;
`QQuickWindow *window() const`, `QQuickItem *viewport() const`,
`QQmlEngine &engine() const`, `void resizeViewport(const QSize &)`,
`bool show(QString &error)`. It owns engine/window/simple native page scope and
borrows the view, uses S3 verbatim, and detaches before destroying hosts.
SongTab overload mirrors isReady through the page's enabled/focus state;
SongView overload is ready by definition. No auto-host-on-query, synthetic
forwarding or global map. Fixture declaration order must destroy host before
borrowed view/tab/document. EditorRig and SongViewRig explicitly own this host.
Existing framebuffer helpers size/capture the viewport, mapping its scene origin
to window image pixels with DPR; do not resize the entire shared window to size
a page.

Existing harness families, not new standalone executables, own new scenarios.
Preserve domain assertions; remove tests asserting old per-song window
destruction or QWidget identity rather than repinning them. Behavioral coverage:

- Two real song scenes in one window/engine; A/B/A retains page QObject, camera,
  selection, undo, focused editor; reorder retains these and persisted order.
- Empty/background-open/replace/force-new/restore, dirty-close cancellation and
  asynchronous close/reopen tombstones; selected close unloads/hands off audio
  before lease destruction, background close does not unload.
- Selected unready A blocks all page pointer/wheel/text/IME input; ready B
  remains editable; readiness loss cancels drag/audition, returning readiness
  resumes scoped input without focus theft.
- Real QuickPopupSession form/menu/pitchbend: pointer tab switch and popup-owner
  close; no outgoing forced focus; immediate editor command on survivor;
  dismissal press -> close owner -> release is swallowed, next full click works;
  popup content is destroyed before context/engine.
- No focus recipient means no editor fallback; TextInput keys remain local;
  focused tab Space triggers real MainWindow QAction once; numeric popup Space
  retains existing transport exception; persistent chrome Enter/Return works;
  next/previous/F6, close and accessibility press use real control/action paths.
- Intrinsic-width tabs and overflow; horizontal wheel exposes offscreen tabs;
  drag release must be inside viewport over an actual tab, with
  PointerDevice.UngrabExclusive AND EventPoint.Released AND enabled strip.
  CancelGrabExclusive, disabled-mid-drag, outside release and a close-button
  press never reorder. Qt DragHandler owns threshold/grab; no stale drop index.
  Use DragHandler target: null with native pressed/hover styling only; no drag
  ghost, drop caret or speculative sibling movement before release. Reject a
  close-button press origin, not the close-button area of a destination tab: a
  valid drag released there still targets that tab and does not close it.
- Page at nonzero origin, smaller than window: notes, scrollbars, menu anchors
  and CALayer align after viewport-only resize; hidden page playhead absent;
  popup hides native playhead and dismissal restores it; DPR/screen and native
  surface recreation remain correct.
- Detached mutations followed by reattachment render current data; destroying a
  page does not destroy shared window/engine; provider A removal cannot break B;
  all scene borrows retire before domain resources.

Acceptance must be through real QML/C++ scene and native input where named.
Direct controller calls alone do not prove tab controls, drag/drop, shortcut
precedence or popup shielding. Prototype pass counts are not production
acceptance.
