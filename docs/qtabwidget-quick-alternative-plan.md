# QTabWidget replacement using Qt Quick composition

Status: current specification for the ongoing composition worktree and its bounded deletion pass. Reviewed implementation snapshots are evidence, not a claim that this pass or its acceptance criteria are complete.

## Decision and scope

Replace the song tab strip and page stack together with **Qt Quick Controls `TabBar` / `TabButton`, `StackLayout`, and one `FocusScope` per persistent song page**. Retain exactly one outer `QQuickView` embedded by `QWidget::createWindowContainer` in the existing MainWindow.

The goal is a cohesive tab module that can later live inside an `ApplicationWindow` without rewriting its internals. **Recommendation after tracing and exercising the native embedding seam: retain the widget shell for this tab conversion.** The user permits choosing MainWindow-down conversion if it is the optimal route; it is no longer ruled out by scope alone. The comparison below explains why it is not required to solve tab composition. No production shell conversion is authorized by this planning document.

This can be substantially simpler than `feature/songtab-quick-composition`, but it is not a three-type replacement for every existing input and rendering contract. Qt owns page layout, item focus, control interaction, and visual lifetime. The application still owns document selection, audio handoff, readiness, edit cancellation, save decisions, and native playhead integration.

Implement by adapting `feature/songtab-quick-composition`, not by starting a new worktree based on `fork-main`. Retain its completed QObject/canvas conversion and replace its custom tab-host machinery in place. Do not merge the composition cutover into `fork-main` or layer another host over it.

## Plan precedence and supersession

**This document is the current implementation authority for the tab replacement and deletion pass.** Its [bounded A–F deletion pass](#bounded-deletion-pass-implementation-plan) replaces this document's earlier A–E cutover sequence and the execution instructions in `docs/songtab-quick-composition-plan.md`. Do not concatenate the old and new work packets or verification commands.

The composition plan remains a historical migration record. Its recently updated “Page stacking and tab order” section agrees with the intended Qt ownership, but does not override this document's exact interfaces, deletion targets, test constraints or size gate. Earlier SongView blueprint instructions do not authorize repeating completed conversion work.

| Earlier plan section or requirement | What remains applicable | What changes for current execution |
|---|---|---|
| Composition “Status and scope”, “Target modules and ownership”; earlier SongView blueprint | Existing widget shell, windowless song sessions, document/audio ownership and editor behavior. | Work on the existing composition worktree, not a new fork-main cutover. Preserve behavior rather than every inherited helper. Use the measured size gate; migration completion alone is not acceptance of the deletion pass. |
| “Session and collection contract” | WorkspaceUi's authoritative ordered ownership and selection; stable session identity; incremental model insertion/removal; save/close/persistence behavior. | Delete drag/move and move-notification requirements. Append order is persistence order. QML sends select/close directly to WorkspaceUi; there is no host forwarding controller. |
| “Scene attachment contract”, P3 and P7 | Page-local context, separate canvas QObject/visual ownership, live-model teardown, provider lifetime and native surface safety. | Use the exact existing attachment interface, one-shot QML join and detach-before-row-removal order. Do not invent interface spellings, rehost/recovery modes, or repeat the completed QObject conversion. Apply the named deletion-pass reductions. |
| “Geometry, focus, and input contract”, P4 | Canvas-local geometry, page eligibility, shared semantic edit commands, text/IME precedence and outgoing cancellation. | The old host-side missing-focus dispatcher and queued/default-surface focus requests are superseded: delete them. Use per-page FocusScopes, local initial focus, readiness bindings and one explicit editor-entry operation. |
| “Popup and native-playhead contract”, P5 | Page-bounded popups, owner validation, stale-release safety, native clipping/occlusion/DPR and destruction guarantees. | Retain these behaviors, not duplicate subscriptions or popup retarget machinery. The exact allowed removals are in deletion phase D; this is not permission for a popup/native rewrite. |
| “Page stacking and tab order”, P6 | Persistent page identity, usable strip, accessible controls, titles/tooltips, live appearance and authoritative selection. | Qt owns delegates, layout and control mechanics: Repeater, StackLayout, FocusScope, TabBar/TabButton/ToolButton/ToolTip. No C++ page registry, manual stack, custom drag or manual overflow reveal. Already-corrected code is retained, not reimplemented. |
| “Ordered implementation work packets” P1–P8; “Dispatch and completion criteria” | Source-current references, coordinated shared-file ownership and complete behavioral verification. | Those packets are historical, not a second todo list. Execute only the bounded A–F pass here, with one integration owner and no further redesign hidden inside it. |
| “Check migration ledger”, “Regression scenarios worth retaining”, P6/P8 and “Verification commands and runtime policy” | Existing behavioral assertions for editing, focus, lifecycle, popups, audio and native rendering. | Old instructions to add scenarios/cases or run the original multi-checkpoint/full-suite campaign are superseded. Adapt existing checks; no permanent case/fixture expansion without approval. Use this document's bounded commands, real-app smoke and deletion-phase E corrections. |
| Earlier blanket “keep the implementation” language; this document's former open-ended spike gate | Safety and observable application behavior. | Preserve contracts, delete demonstrated redundant state/plumbing, and count production/check costs separately against the original baseline and pass start. A substantial remaining subsystem requires the explicit architecture/size decision in phase F. |

Implementation agents must update the old plan's status/progress references when reporting completed work, not revive its superseded instructions. Historical evidence and completed packets may remain labeled as history; do not erase them or rewrite them into a competing current plan. No automatic rollback, branch operation, renderer substitution or full-shell migration follows from this supersession.

## End-product constraints, not additional implementation phases

These tighten phases A and F below. They do not authorize new features, abstractions, test suites, a larger platform matrix or another prototype.

### Feasibility before polishing

Phase A must estimate the remaining production cost from the named safe deletions, with moved code and comments separated. The current removal list is not evidence that most of the historical +1,723 production lines can disappear. If the ledger still predicts a substantial subsystem, surface the architecture/size conflict before spending the rest of the pass polishing it. Do not invent a numeric definition of “few” that declares hundreds of retained coordination lines acceptable by default; show the projected residual and obtain the user's decision when it remains material.

### One authority for each kind of state

| Concern | Sole authority / permitted adapter |
|---|---|
| Open sessions, selected song, save/close/audio transaction | WorkspaceUi; SongTabsModel projects it without another collection or selection store. |
| Loading/readiness | SongTab; model/page bindings expose it, not another load-state machine. |
| Page geometry, visibility and remembered input descendant | StackLayout and FocusScope; C++ retains semantic cancellation and the derived eligibility edge, not competing page layout or focus history. |
| Canvas resources and normal destruction | Existing TimelineQuickView attach/detach and WorkspaceUi removal ordering; no ordinary rehost/recovery lifecycle. |
| Popup sequence and native geometry exceptions | Existing page popup adapter, window-lifetime release mask and actual native mapping consumers; no second generic framework. |

Classify every remaining custom field as authority, borrowed handle, derived cache or lifecycle guard in the existing ledger. A derived cache or guard may earn its place through avoided recomputation, edge-triggered cancellation or teardown safety; do not delete it just to reduce the field count. A second authority is not acceptable.

### Future changes must stay local

Review three hypothetical maintenance changes against the final source; do not implement them or add tests for them:

- A tab-title/tooltip presentation change belongs in model projection and/or strip QML, not engine, focus or lifecycle code.
- A shared editor command belongs in the existing semantic edit route, not the host or a handler registered once per open song.
- Opening an additional song must use the same incremental model/delegate path, without another window dispatcher, global shortcut pair or controller.

If an ordinary change requires synchronizing multiple independent registries or editing tab code across the renderer, popup framework and window host, identify that remaining coupling in the size decision. Hiding it behind new forwarding helpers does not make the design simpler.

### Ship the supported Qt surface, not only the local probe

The planning probes used Qt 6.11.0. Existing native CI and release jobs request Qt `6.9.*`, while `find_package(Qt6 ...)` currently states no numeric minimum; the existing Linux toolchain is also part of the supported build matrix. Validate the chosen QML types, focus behavior and imports on the project's existing toolchains. Do not silently rely on a 6.11-only behavior, raise the supported Qt version or add compatibility branches to rescue this design; report a real version conflict for an explicit decision.

Use the existing release/package path to check QML imports, controls/styles and resources in the shipped artifact, not only a development process with system Qt available. Keep the existing platform matrix; record platforms/toolchains not exercised rather than claiming cross-platform native verification. Do not suppress QML import/binding warnings or create a new packaging/check runner.

### Preserve ordinary usability and bounded runtime cost

Fold these observations into the existing native smoke, not new permanent cases: empty workspace; many enough tabs to overflow; long/dirty titles; close-button versus tab activation; keyboard/accessibility entry; font/theme changes; and the already-specified popup, loading and external-focus transitions. Keep stock control behavior and existing styling; no custom animation, navigation framework or visual redesign.

Persistent hidden pages may retain their session/editor state; they must not introduce continued animation, repeated focus work or accumulating scene/window attachments. Observe idle, playback, switching and repeated open/close using the same representative songs as the baseline. Investigate a regression with existing profiling tools, not new timers, logging infrastructure or benchmark targets. Do not infer lower CPU/memory from fewer windows or fewer lines. Functional correctness, maintainable ownership, deployment and size all have to agree before the result is accepted.

## Evidence: what the previous branch actually did

Inspected baseline `fork-main` at `dd3203f2` and composition worktree HEAD `06054ac8`, including its current plan. Paths below refer to the composition worktree unless marked baseline.

| Source | Observed implementation | Alternative |
| --- | --- | --- |
| `workspacequick/workspacequickhost.cpp:204-284` | `attachRow`, `releaseRow`, a `QHash<SongTab *, Page>`, `fitPages`, and `publishSelection` manually create page items, size every page, and toggle visibility. | QML owns persistent page delegates; `StackLayout` owns their geometry and visibility. No parallel host page registry. |
| Same file, constructor and destructor | Host watches row notifications, owns explicit page teardown, installs appearance event filter, and exposes selection/close/move forwarding. | Keep only outer embedding and existing appearance publication at the shell seam. Route semantic requests directly to WorkspaceUi. |
| `songview/quick/quickwindowinput.cpp:96-115` | Window event filter dispatches song keys when there is no `activeFocusItem`, using a separately published selected-scene pointer. | Establish a page focus target and route unaccepted keys through the focused item ancestry to the existing semantic edit handler. |
| Same file, lines 55-85 | Window-lifetime bitmask consumes outstanding mouse releases after popup cancellation/removal. | Retain this existing pointer-sequence mechanism, stripped of selected-scene/key routing. Its lifetime must exceed the dismissed page. |
| `timelinequickview_window.cpp:173-262` | Page-local `QQmlContext`, canvas construction, distinct QObject/visual ownership, and viewport-to-canvas resize connections. | Keep page-local construction/ownership; replace canvas resize forwarding with `anchors.fill: parent`. `attachScene` is not itself a duplicate tab manager. |
| `TimelineQuickView::watchSceneMapping`, `sceneEffectivelyVisible`, `updateInputEligibility` | General ancestor observation and a derived input eligibility system accompany shared scenes. | Bind page enabled/focus from selected/readiness state. Restrict geometry observation to actual popup/native rendering needs. |
| `workspacequick/SongTabStrip.qml` | ListView-based tab controls, drag transforms, custom tooltip presentation. | Styled stock controls and attached `ToolTip`; close remains a small application action. |
| `WorkspaceUi::selectTab`, `removeTab`, `MainWindow::onSelectedTabChanged` | Cancellation, selection, audio borrowing, and destruction have an explicit order. | Preserve these transactions. They are application policy, not gratuitous window management. |

### Important corrections to the diagnosis

- The branch's later `docs/songtab-quick-composition-plan.md`, section “Page stacking and tab order,” **already proposes StackLayout**, but still specifies host-created pages, `setPageSelected`, and `QuickWindowInput`. The inspected implementation still has the manual stack. The alternative must change ownership, not just replace the empty page-container Item.
- The same section explicitly drops pointer reorder, but later acceptance text still asks to reorder tabs and implementation still contains `moveTab` / `requestMove`. This is a stale contract. Use the documented append-order/no-pointer-reorder decision here; do not carry contradictory requirements forward.
- `SongTabsModel` explicitly projects WorkspaceUi's authoritative collection and selection. It does **not** own a second independent selected session. The unnecessary duplication is the host's page/routing mirror, not evidence that the model needs replacing with another controller.
- `FocusScope` is not a native window and does not handle MIDI note-off, mouse release swallowing, OS activation, or CALayer clipping.
- One standard widget embedding adapter is not itself a failure. It remains necessary under this narrowed scope. Do not claim that only a full ApplicationWindow conversion makes Qt Quick composition valid.
- No platform-specific crash or performance claim is inferred from the architectural audit. The user's report that the branch failed is accepted; the table identifies concrete duplication and risks rather than inventing a failure trace.

### Cost diagnosis from the in-flight implementation review

The small-delta outcome is **not yet demonstrated**. The reviewed uncommitted implementation over `06054ac8` deleted 274 net production lines and 482 net check lines, but the whole `src` delta against `fork-main` still stood at +1,723 production and +1,492 check lines. These are a review snapshot, not final acceptance measurements; they include retained branch work.

The planning error was treating two changes as one: replacing tab chrome/layout, and consolidating per-song native Quick windows into one shared window/engine. `fork-main`'s `SongTabQuickHost` transfers each song's window into its own container. The shared-window design replaces that isolation with explicit scene ownership, page eligibility, popup isolation and native mapping. TabBar, StackLayout and FocusScope replace only part of that work; they do not establish that the consolidation has a small implementation cost.

At that snapshot the tab shell/model/host still contributed +847 lines, while `timelinequickview_window.cpp` alone contributed +664. The latter is not an independent measure of added machinery: `timelinequickview.cpp` lost 307 net lines, including construction moved into scene attachment. Account for the module together before calling moved wiring new complexity. Retaining branch machinery for safety is not proof that its present shape or size is necessary. The focus/layout probes proved selected Qt behavior, not the total production-code cost. Do not use passing probes, deletion relative to the composition branch, or deletion of checks as evidence that the small-delta requirement against `fork-main` has been met.

The selected architecture remains the one specified here; this diagnosis does not authorize reverting work, removing safety behavior, or changing window topology. If reducing the retained implementation cannot meet the code-size requirement, surface that architecture/size conflict for the user rather than promising that stock controls alone resolve it.

## Resolved routing and shell decision

**No new keyboard dispatcher. No experiment-dependent permission to add one.** The existing editor already handles focused keyboard delivery; the composition branch added a fallback for missing focus, not a required QWidget-to-Quick bridge.

Personal source trace:

- Baseline `timelinequickview_keyrouting.cpp:21-65` already installs the page's semantic key policy on band/gutter/drawer/event-list inputs. The branch preserves this route.
- Branch `timelineinputitem.cpp:291-314` runs local interaction handling, then that page's policy, accepting consumed events. `TimelineCanvas.qml:34-45` receives unaccepted descendant events through Qt's item ancestry and invokes the same page-local bridge for non-band chrome.
- `quickwindowinput.cpp:96-115` does **nothing when activeFocusItem exists**. Its only keyboard job is selecting a song on behalf of an otherwise unfocused window. Correct focus entry removes that requirement; no replacement router is needed.
- Baseline `mainwindow.cpp:759-766` queues `focusActiveSurface()` after tab activation. `songview.cpp:826-831` chooses the visible drawer or content default, not the previously focused descendant. The branch preserves this queued default-surface behavior as `queueSelectedFocus`.
- Branch `timelineinputitem.cpp:191-197` calls both `forceActiveFocus` and native `requestActivate` for every focus request. Page selection and local input focus must not carry native activation; the outer container owns explicit widget-to-Quick entry.
- `automationpage.cpp:163-205` globally intercepts the pencil shortcut before normal item delivery. That is application-owned command routing to migrate into the existing semantic page policy, not evidence that Qt needs a window dispatcher.

### Exact keyboard routes

```text
Quick focused band → local interaction → existing page key policy
Quick focused chrome → local control → canvas Keys.AfterItem → existing page key policy
Quick text editor → text/IME/ShortcutOverride; preserve existing editing guards
Quick popup → existing popup controls and popup shortcut arbitration
Tab strip → its own navigation/activation handlers, never song edit policy
Widget control → QWidget handling and existing window actions
```

Accepted keys stop. Ignored events propagate through Qt, not through a host-selected scene pointer. Keep `TimelineInputItem`'s local-first policy and the existing `TimelineCanvas` ancestor fallback; do not replace them with another framework or duplicate their handlers on SongPage. The canvas fallback remains **inside** SongPage; tab-strip keys cannot bubble down into it.

For pencil mode, add recognition/dispatch to the existing `SongView::handleEditKey` policy in `editkeyrouting.cpp`, with a semantic AutomationPage operation that triggers its existing QAction. Preserve registry rebinding, visible automation section, action enablement, value-prompt/text-input exclusion, and consumed auto-repeat without toggling. Share the recognition predicate with a page-local `Keys.onShortcutOverride` claim on TimelineCanvas; claiming does not execute the operation. Remove the AutomationPage application filter's KeyPress/ShortcutOverride branches. Keep its deactivation cancellation until the existing lifecycle path owns that cancellation explicitly. No window-wide pencil routing or duplicate per-page global shortcuts.

### Exact focus ownership

- Give each newly attached page its initial input target once with `setFocus(true)` **within its own FocusScope**, without `forceActiveFocus` through all ancestor scopes or native activation. A background page must not select the editor area. The session's initial roll/event-list/drawer state determines the default.
- Ordinary A → B selection changes only the model and scoped logical focus. Enter the editor-area scope on explicit editor-entry intent; Qt resolves the page's retained descendant. Do not call `focusActiveSurface()` on every selection.
- Pointer tab selection runs synchronously from the tab's press activation, before any queued popup focus check: cancel A's transients without restoring A, execute the existing selection/audio transaction, then enter the editor area. Keyboard strip arrows select but retain strip focus. Explicit keyboard/accessibility activation uses the same semantic selection/entry operation, not an independent `currentIndexChanged` controller.
- While the selected page is loading, editorArea is the inert focus target. Its ready-page binding supplies the descendant when ready. Remove the selection/ready QTimer focus queue rather than carrying a deferred activation mechanism into the new host. If focus has moved to the strip, a widget field, or another native window, logical page readiness must not activate the editor area or native window.
- The one outer container uses `Qt::StrongFocus`, permitting Qt's embedded-Quick traversal instead of retaining the old `NoFocus` opt-out. An explicit shell command to enter editing calls container `setFocus(reason)` and editorArea `forceActiveFocus(reason)`. The container handles native activation; no page calls `requestActivate`. Qt documents Tab traversal into/out of embedded Quick windows since 6.8.
- Explicit in-page operations such as revealing a drawer or clicking a band still choose their actual target with item focus. They do not activate a native window. OS reactivation leaves Qt to restore its focus chain; no FocusIn retargeting or page focus-history registry.

### QWidget ↔ Quick: what the seam actually costs

| Obligation | One embedded workspace | MainWindow-down QML |
| --- | --- | --- |
| Page switching/layout/keyboard ancestry | Entirely Quick; no widget crossing between songs. | Identical. |
| Search/transport → editor focus | One container handoff, plus native focus domain crossing. | Ordinary item focus if those surfaces are also converted. |
| Window actions and text precedence | Existing QAction ownership; Quick ShortcutOverride participates in Qt's shortcut system. No event forwarding needed. | One set of QML actions/shortcuts replacing the widget actions; text precedence still required. |
| Drawing over the editor from shell chrome | Embedded native window is an opaque stacking island; do not put widget overlays across it. Existing adjacent docks/toolbar do not require this. | One Quick scene can compose shell/editor overlays normally. |
| Page popup dismissal and stale releases | Retain existing page-bounded popup adapter and window-lifetime release tracking. | Still required by the same page interaction contract; changing the outer window does not make a window-wide modal overlay page-local. |
| CALayer playhead mapping/lifetime | Native child-window coordinates and surface lifetime. | Top-level Quick-window coordinates and surface lifetime. Native renderer integration remains. |

**Recommendation: tab conversion under the current shell.** The measured seam supports the required focused keyboard paths without a dispatcher. The large coordination cluster on the branch mostly concerns pages sharing one Quick window; switching the outermost window to ApplicationWindow would not delete it automatically.

MainWindow-down becomes the preferable architecture when the goal includes one scene for transport, browsers, panels and cross-shell overlays, not merely removing tab-host code. Its minimum coherent scope is `mainwindow.{h,cpp}` shell construction/action presentation, `WorkspaceUi::buildUi` and widget panel access, TransportBar, SongListPanel, VoicegroupBrowser, PolyphonyPanel, dock/layout persistence, and startup/theme publication. Keep audio/project/session ownership in C++; expose those existing owners to QML rather than rebuilding domain policy.

Do not put an ApplicationWindow on top while embedding the same widget toolbar/docks underneath: that preserves the native seams the migration is meant to remove. Standalone settings/import/sample dialogs can remain widget windows under QApplication during a shell conversion; they are explicit window boundaries, not widgets inserted into the Quick scene. Full removal of QtWidgets is a separate scope.

The current dock objects are movable (`workspaceui.cpp:112-143`, `mainwindow.cpp:560-563`). Stock `SplitView` supplies resizing and size persistence, **not dock relocation**. A MainWindow-down plan must either preserve that behavior with a chosen docking solution or obtain an explicit product decision to use fixed panels. Do not repeat the tab mistake by silently replacing Qt-owned docking with a custom framework.

## Proposed ownership

```text
MainWindow / WorkspaceUi                         unchanged widget shell
  ├─ open SongTab sessions                       C++ ownership, stable identity
  ├─ SongTabsModel                               projection, incremental rows
  └─ one outer embedding adapter                container owns one QQuickView
       └─ WorkspaceSongs.qml                    FocusScope + ColumnLayout
            ├─ TabBar
            │    └─ Repeater → TabButton         title, close action, ToolTip
            └─ editor-area FocusScope           focus entry, separate from strip
                 └─ StackLayout
                      └─ Repeater → SongPage    per-song FocusScope
                           └─ TimelineCanvas     created/owned by session coordinator
```

No per-song QWindow, QWidget, QQmlEngine, native activation request, host Page table, or focus-history registry.

Keep related tab files under `src/ui/workspacequick/`; avoid a new generic navigation framework or many tiny forwarding modules. Reuse `SongTab`, `SongTabsModel`, WorkspaceUi, and TimelineQuickView rather than introducing synonymous controllers.

### Session model and selection

- Keep SongTab QObject-only, as on the branch. Documents, undo history, camera/editor state, timeline projections and bank leases stay session-owned.
- Keep one authoritative open-session collection and selected-session identity in WorkspaceUi, exposed through SongTabsModel. Keep existing roles and add `quickView`, a borrowed QObject pointing to the session's TimelineQuickView. `ready` remains the existing model role, not a new SongTab property. `selectedIndex` is a derived position, not identity.
- Both strip and stack consume that model. User requests carry session identity into WorkspaceUi's existing select/close operations. Neither TabBar's default selection nor row position is permission to switch audio independently.
- Use incremental model insert/remove/data-change notifications. No `modelReset` for title/readiness changes, no model reassignment on selection, and no Loader whose `active` follows selected state. Those would destroy persistent pages and their focus state.
- QML Repeater owns its delegates. C++ must not delete/reparent those delegates manually. QObject session ownership remains explicitly C++ ownership.
- Append order is display/persistence order. Delete pointer-reorder interfaces and obsolete reorder-only checks, following the branch's documented product decision. If reorder is restored later, `TabBar.moveItem()` alone is not a document-model reorder implementation.
- Preserve close-current successor policy: next row at the removed position, otherwise previous; last close yields null selection and an empty workspace.
- Closing a clean non-selected tab does not select it or switch audio. The close ToolButton requests close(session) only and consumes its activation independently of TabButton. Preserve existing dirty-close reveal/prompt policy: the requested dirty document may be selected for confirmation; Cancel leaves it open. Do not invent new close behavior while changing chrome.

### Layout

Use a ColumnLayout with strip implicit height and a filling StackLayout. StackLayout owns child width/height/visibility; do not bind anchors or set explicit geometry on the layout-managed page itself. The canvas *inside* its page can use `anchors.fill: parent`.

Use `StackLayout.isCurrentItem` on each direct page delegate to derive page participation. Handle the empty model with `selectedIndex == -1`; place empty-state presentation outside the stack's page children so it cannot shift indices.

The executable interface and attachment sequence are specified below; do not implement an independent interpretation of a structural sketch.

- Root: `FocusScope` containing a `ColumnLayout`; siblings are `SongTabStrip` (root `TabBar`) and `editorArea` (persistent `FocusScope`, initial `focus: true`).
- `editorArea` contains an anchored `StackLayout` with `currentIndex: workspaceTabs.selectedIndex`.
- Its Repeater uses `workspaceTabs`; define the page delegate inline in `WorkspaceSongs.qml`, not in another forwarding file.
- Each page is a `FocusScope` with required model properties `session`, `quickView`, and `ready`. Bind both `enabled` and `focus` to `StackLayout.isCurrentItem && ready`. Do not write its visibility or geometry.
- Each canvas remains coordinator-owned, visually inside its delegate, with `anchors.fill: parent`. The canvas is not another layout child.
- TabBar reflects accepted model selection through `setCurrentIndex()`. Do not bind application selection to `onCurrentIndexChanged`.
- Pointer/accessibility activation selects the requested session synchronously, verifies that it is selected, then enters `editorArea`. Strip Left/Right requests the neighboring session but keeps focus in the strip. Enter/Space enters selected content.
- Selection/row notifications synchronize TabBar after Qt's structural adjustments. No highlighted-but-not-selected song, pending-selection state, or second selected-session property.

### Focus and keys: Qt mechanism, explicit policy

1. A persistent FocusScope remembers its focused descendant while another page is selected. Give each new page a default editor target; do not force the default target on every return and erase that memory.
2. Bind inactive/unready pages disabled as well as unfocused. **Visibility alone is not a keyboard exclusion policy.** A tab loading in the background must not disable the shared window or active song.
3. The workspace FocusScope provides an entry point from the widget shell. Use the one container/editor-area entry operation specified above; delete per-song native activation and selection/ready focus queues.
4. Background readiness changes only scoped logical focus. A QML scope's logical focus is not native activation. While loading, editorArea is an inert target; readiness may choose its selected page's descendant without changing whether the editor area, strip, widget search, or another native window owns active focus.
5. Keep a separate editor-area FocusScope around the stack, sibling to TabBar. Select on pointer press and explicitly enter editorArea after the synchronous selection transaction. Strip keyboard navigation retains strip focus; explicit activation enters content. A tab-cycle command invoked while editing retains editor focus. Do not force the default canvas target on every transition.
6. Unaccepted keys bubble through the selected page to `SongView::handleEditKey` / `handleEditKeyRelease`. Keep existing per-band origins and the shared routing in `songview/editkeyrouting.cpp`; do not copy key matching into each page or band. Use `Keys.AfterItem` where a QML fallback is appropriate.
7. Text, IME, popup and advertised local control keys keep first refusal, including ShortcutOverride behavior. A focus scope does not disable window-scoped Shortcut objects: do not instantiate identical global shortcuts in every page.
8. Move AutomationPage's keyboard dispatch into the existing page semantic route, using the shared recognition/ShortcutOverride contract above; retain necessary lifecycle cancellation independently. Pencil shortcuts cannot act on hidden pages or inside text entry.
9. Delete the no-activeFocusItem fallback and selected-scene pointer from QuickWindowInput. This is a decided cut, not conditional on whether a future implementation invents another dispatcher. Unexpected missing focus is a focus-entry defect to repair at its owner.

### Scene lifetime and attachment

StackLayout does not instantiate scenes, and FocusScope does not make C++ borrows safe.

- Repeater owns the SongPage FocusScope viewport, **not the canvas**. Keep TimelineQuickView's page-local QQmlContext and C++ construction of TimelineCanvas. The context supplies `timelineQuickView`, `timelineScene`, `drawerChrome`, `trackHeaderModel`, `timeRuler`, `otherStrip`, and `eventListController` to existing nested QML. Moving all those consumers to required properties is a separate canvas-interface migration, not a prerequisite for replacing tabs. Never put per-song values on the workspace engine root.
- SongPage attaches once through `TimelineQuickView::attachToPage(QQuickItem *)`, after component completion and its initial QQuickWindow association. The exact one-shot join is specified below. `attachScene` retains canvas/native attachment and ownership; canvas anchors replace viewport resize forwarding. A QQuickWindow association is not proof that its native surface exists: CALayer attachment still follows existing surface lifecycle notifications.
- Use Qt item/window lifecycle notifications for attachment and the existing native surface lifecycle for CALayers. Do not introduce a generalized rehosting/reattachment state machine: pages remain in this workspace for their lifetime.
- Preserve the branch's page-specific drawer icon/provider correction unchanged. Do not introduce a second provider migration in this task.
- Before removing any session's row, explicitly detach its canvas while its viewport, session and window are alive. For the selected session first cancel outgoing edits/audition while it is still authoritative, unload audio while its bank lease lives, and publish null as necessary. Then call the coordinator's existing detach operation **before beginRemoveRows / take()**. It releases native/popup/model borrows and destroys its own canvas/context in their valid order. Only then remove the row so Repeater can destroy its empty viewport; destroy the session afterwards and select the successor.
- Prove this order with the real QAbstractListModel. Do not defer detach to `Component.onDestruction` or assume `endRemoveRows()` leaves the delegate alive. C++ must never delete a Repeater viewport; Repeater must never own the coordinator-owned canvas. This direct per-session detach call does not require a host page table, retired-session queue, or timer-based lifetime workaround.
- Project teardown suppresses intermediate selection/audio publication, detaches all session canvases while viewports/window remain alive, then removes rows and destroys sessions, then releases the workspace window/engine. Keep the same explicit ordering for normal close and bulk teardown.

## Hard contracts that the three Qt types do not replace

### Popups and pointer sequences

The branch deliberately preserves page-bounded popup interaction: an outside click inside the page dismisses without editing through; clicking a different tab cancels the old popup and switches on that click. Closing the page between dismissal press/release must not send the release into the next song.

Retain the existing page-bounded `QuickPopupSession`/`QuickPopupLayer` in this conversion. A stock modal Popup's overlay is window-scoped: `Popup.parent = songPage` does not bound its modality to the page. Replacing all existing forms and menu owners is unnecessary scope and does not help tab ownership.

For this tab conversion:

- Replace the strip's custom tooltip with ToolTip immediately; style from existing theme/layout values, not new hard-coded metrics.
- Keep typed prompt/menu application owners and their validation, revision guards, cancellation and note-off behavior, including popup-local restore-focus state. That transient return target is not a tab focus-history registry.
- Keep `QuickPopupLayer`'s underlay bounded to the visible page rect; the tab strip remains outside its hit area. A B-tab press reaches B's stock control, whose synchronous selection transaction cancels A's popup with `restoreFocus = false` before entering B.
- Keep the outstanding-release bitmask from QuickWindowInput, including clearing stale bits on a newer press and native deactivation. `outsidePressed` arms it before retiring the popup; it must survive row removal. Also retain popup ShortcutOverride arbitration while the popup is open. Remove all selected-scene storage and song-key dispatch from that window owner.
- `QuickPopupSession::checkFocus` currently calls `cancel(true)` after focus leaves its popup. Change this focus-escape path to `cancel(false)`: focus already belongs to the destination, and restoring the outgoing target would steal it back from the strip/editor/widget. Explicit Escape/inside-page dismissal can still restore the valid same-page target. Selection/removal/deactivation never restore outgoing focus.
- Explicitly close page-owned popups on deactivation/removal; hiding the page is not proof that its window-parented popup vanished. Preserve geometry publication used by the native playhead's popup occlusion.

This is a fixed retention decision, not a trial of stock modal overlays followed by permission to build a new router. Popup modernization can be planned independently; it is not necessary to replace QTabWidget.

### macOS native playhead

Retain the existing CALayer renderer. A native layer is outside Qt Quick item clipping/visibility, so `StackLayout` cannot hide it automatically.

Keep mapping at `PlayheadOverlay` / `playheadrenderer_macos.mm`: page-local geometry to scene/native coordinates, selected/effectively-visible state, popup occlusion, DPR and surface destruction. Retain existing render-thread/native lifetime guarantees. Do not silently switch macOS to the Quick renderer or remove native checks to make this cutover easier.
Retain `watchSceneMapping`, clipped mapping helpers, and their popup/native consumers in this delivery. They observe actual mapped geometry; they do not assign StackLayout page geometry. Removing them is not part of the tab replacement. This avoids making agents invent a second geometry-observation scheme while changing hosting.

## Implementation contract: fixed files and operations

### Baseline and change boundary

Implement against `feature/songtab-quick-composition`; inspected revision was `06054ac8`. This document is currently in the main checkout. Do not merge that branch wholesale into `fork-main` as part of implementation, or redo its completed QObject/canvas conversion. Reconcile subsequent user changes before editing. No branch/worktree creation, merge, or production implementation is authorized by writing this plan.

The implementation is one tab-host replacement. Preserve the branch's windowless sessions, canvas behavior, domain model, audio transactions, popup safety and native rendering. Preserve their contracts, not every current helper, cached field or observer. The bounded deletion pass below specifies the permitted reductions and supersedes blanket implementation-retention wording. `SongTabQuickHost` and per-song window transfer were already removed on this branch: do not recreate them as an intermediate step.

**Code-size acceptance:** this is a deletion-led simplification, with substantial net production-code deletion relative to the inspected composition branch. New production code is limited to the small attachment/command connections and QML composition required by this contract; do not replace deleted machinery with equivalent helpers elsewhere. Against `fork-main`, the goal is very few additional tab-composition lines, not thousands of lines of new coordination. Report production and check line deltas separately against both baselines at handoff; retained branch code counts toward the comparison with `fork-main`. Do not pad deletions with unrelated removals or sacrifice lifecycle safety to meet the goal. If the specified design cannot meet it, raise the concrete conflict before expanding the implementation.

Before changing/removing exported symbols, use LSP references in the implementation checkout and migrate every reported production and fixture caller. The inventory below names the intended mutation sites; references resolve current callers, not permission to redesign them.

### File ownership and deletion list

| Files | Required change |
|---|---|
| `src/ui/workspacequick/workspacequickhost.{h,cpp}` | Keep this existing class as the sole embedding/appearance adapter. Delete `Page`, `m_pages`, `attachRow`, `releaseRow`, `fitPages`, selection publication/deactivation, model-row observers, neighbor lookup, and select/close/move forwarding. Keep type registration before engine construction, transparent QQuickView setup, container ownership, and existing theme/font publication. |
| `src/ui/workspacequick/WorkspaceSongs.qml` | Own root/editor FocusScopes, ColumnLayout, StackLayout and persistent page Repeater. Define the small page delegate here. No imperative page sizing/visibility or parallel page array. |
| `src/ui/workspacequick/SongTabStrip.qml` | Replace custom ListView/button/tooltip/drag machinery with TabBar, repeated TabButton, nested close ToolButton, and attached ToolTip. Keep theme/layout values, title/dirty/path presentation and accessible names. Delete drag coordinates, Translate, reorder, tooltip timer/positioning, and manual selected-tab reveal. Use stock TabBar overflow behavior. |
| `src/ui/workspacequick/songtabsmodel.{h,cpp}` | Retain incremental projection over WorkspaceUi storage. Add the borrowed `quickView` role. Delete `move()` and its move-only notifications/documentation. Keep `songAt`, `rowFor`, append/take/takeAll, metadata/readiness updates and selection notifications. |
| `src/ui/workspaceui.{h,cpp}`, `workspaceui_tabs.cpp` | Expose existing select/close commands to QML; implement the ordered transactions below directly against sessions. Delete `moveTab`, `sessionsReordered`, and host-forwarding callers. Preserve append-order persistence, load/save/dirty-close gates, tombstones and successor policy. |
| `src/ui/songview/quick/timelinequickview.{h,cpp}`, `timelinequickview_window.cpp` | Add the single QML attachment entry; retain `attachScene`/`detachScene`, page-local context, input eligibility, native/popup lifecycle and mapping. Delete selected-scene publication into QuickWindowInput and viewport-to-canvas size forwarding. Establish initial local focus once. |
| `src/ui/songview/quick/timelineinputitem.cpp` | `requestFocus()` retains item `forceActiveFocus(reason)`; delete its native `requestActivate()`. Local item requests never activate a native window. |
| `src/ui/songview/quick/quickwindowinput.{h,cpp}` | Delete selected-scene storage/setter and KeyPress/KeyRelease fallback. Retain only the window-lifetime outstanding-release bitmask and its deactivation/new-press handling. |
| `src/ui/songview/quick/TimelineCanvas.qml`, `timelinequickview_keyrouting.cpp` | Keep existing local-first handlers and canvas ancestor fallback. Add canvas fill anchors and the pencil ShortcutOverride claim described below. Do not duplicate key handlers on SongPage or workspace root. |
| `src/ui/editordrawer/automationpage.{h,cpp}`, `src/ui/songview/editkeyrouting.cpp` | Move pencil recognition/execution from the application keyboard filter into the existing page command policy. Retain the existing lifecycle-only cancellation filter. |
| `src/mainwindow.{h,cpp}` | Remove `queueSelectedFocus`, readiness-triggered default-focus queues and ordinary-selection `focusActiveSurface` calls. Preserve synchronous audio handoff, action updates and explicit user editor-entry requests. |
| `src/ui/songview/quick/quickpopupsession.cpp` | Preserve no-restore focus escape, owner validation, page-bound underlay, release suppression and explicit same-page dismissal restoration. Remove only the duplicate page-geometry subscriptions identified in the bounded deletion pass; no popup-framework replacement. |
| `src/ui/playheadoverlay.cpp`, existing macOS renderer | Preserve rendering and mapping contracts. Update only callers affected by deleted host/routing interfaces; no renderer replacement or geometry-watch redesign. |
| `CMakeLists.txt` | Keep existing workspace/scene source and QML registrations. Remove only genuinely deleted entries. Register no second UI module, engine, executable, or permanent probe target. |

### Exact QML-facing interface

Keep context properties `workspaceTabs` and `workspaceChrome`. Replace `workspaceHost` command access with `workspaceUi`, pointing to the existing WorkspaceUi. Do not put song-specific values in this shared context.

- `WorkspaceUi::selectSongTab(SongTab *)`: make the existing validated method Q_INVOKABLE; keep its identity/membership check and synchronous selection transaction.
- `WorkspaceUi::requestCloseTab(SongTab *)`: expose the existing method as Q_INVOKABLE without a forwarding alias; retain the exact save/close gate and dirty-document reveal behavior.
- `SongTabsModel::songAt(int) const`: expose the existing lookup as Q_INVOKABLE for Ctrl+Tab and local neighbor navigation. Preserve null for invalid indices.
- Add `SongTabsModel::QuickViewRole` with name `quickView`, returning `QObject *` for `tab.view().quickView()`. Mark that borrowed object `QQmlEngine::CppOwnership` when exposing the session, alongside the branch's existing session ownership declaration. Metadata updates never replace the object.
- `TimelineQuickView::attachToPage(QQuickItem *viewport)`: Q_INVOKABLE. Require a non-null, window-associated viewport with a QML engine. Resolve `qmlEngine(viewport)` and call existing `attachScene(*engine, *viewport)`. Invalid construction is a reported invariant violation, not a silent fallback or a retry loop.
- Keep existing C++ `attachScene(QQmlEngine &, QQuickItem &)` for native/check fixtures. QML does not receive an engine or own the coordinator.
- `WorkspaceQuickHost::focusEditor(Qt::FocusReason)`: sole explicit widget-to-workspace entry. Focus the container, then invoke root QML `enterEditor(reason)`; that function calls `editorArea.forceActiveFocus(reason)`. Keep at most one guarded root handle, not per-page handles. Ordinary selection/readiness never calls this method.

Keep typed C++ session arguments and their existing QObject metadata; no string-id command protocol or new session controller. QML roles may use `var` for these borrowed QObjects. Existing title, tooltip, songKey and ready roles remain authoritative.

### Exact creation and attachment sequence

1. Construct SongTab and configure document/view state as today, before model append. WorkspaceUi keeps unique ownership.
2. Append through SongTabsModel's existing insertion bracket. Both Repeaters create their own delegates; nothing in the host reacts to row insertion.
3. In the page delegate keep only two local construction booleans, `componentComplete` and `sceneAttached`, initially false. `Component.onCompleted` sets the first and calls `attachWhenReady()`. `Window.onWindowChanged` calls the same function.
4. `attachWhenReady()` returns unless completed, not already attached, and `Window.window` is non-null. It marks `sceneAttached = true` and calls `quickView.attachToPage(page)`. Import `QtQuick.Window` for the attached property. This joins two Qt lifecycle notifications; it is not focus memory, a rehost policy, or a timer.
5. Existing `attachScene` creates the page-local context and canvas, preserving separate QObject and visual ownership. Canvas anchors fill its viewport. Remove its initial explicit canvas size and viewport width/height resize connections. Keep canvas geometry observation that updates SongView's layout.
6. Set the initial logical editor target once after canvas/input construction, from the session's current roll/event-list/drawer presentation. Set focus locally inside the page scope without native activation or forcing ancestor scopes. Ensure the canvas participates in that scope chain. Do not use `focusActiveSurface()` if it forces active/native focus.
7. On page changes, StackLayout and page `focus`/`enabled` bindings do the work. Neither construction flag changes again. No Loader activation, detach/attach cycle or canvas recreation on selection.
8. Normal removal detaches the coordinator before row removal. No `Component.onDestruction` callback into a possibly destroyed session. After an empty viewport is destroyed, QML's attached-signal connections disappear with it.

The coordinator must still tolerate its existing terminal `detachScene()` call in destruction. A page that was removed before initial attachment has no canvas/native resources to release. It is not scheduled for later attachment: there is no queued callback or timer.

### Exact selection, cancellation and lifetime transactions

Use existing `TimelineQuickView::setPageSelected(false)` before relinquishing the outgoing session. It closes the page eligibility gate and cancels its gestures/popup while it remains authoritative. Preserve its no-focus-restoration behavior. This existing page eligibility flag is not the deleted window-selected-scene pointer; retain it for ordered cancellation and native visibility. Do not replace tab switching with broad document/readiness `cancelTransientInput()`.

**Select B from A**

1. Validate B membership; same-session selection does not reload audio or cancel its editor.
2. If A exists, call A's coordinator `setPageSelected(false)` while A still owns semantic/audio routing.
3. Set `m_selectedTab = B`; execute existing `publishSelection()` synchronously, including MainWindow audio handoff. Remove the queued focus work, not audio/state work.
4. Notify model selection, allowing strip/stack/page bindings to settle; set B's coordinator `setPageSelected(true)`. Effective visibility and readiness still gate actual input/native drawing. At return, model selection, visible page and eligible session agree.
5. Only the initiating pointer/accessibility/explicit-entry action enters the editor. Programmatic selection and background readiness do not.

**Close a session**

1. Keep `requestCloseTab` gates unchanged. A clean non-selected close never selects that page. Dirty close reveals its document before the existing prompt; Cancel leaves it open.
2. In `removeTab`, resolve membership and original row before mutation.
3. If selected: close eligibility/cancel while selected, clear `m_selectedTab`, emit the existing null audio handoff while the bank lease lives, and notify model selection.
4. Call the removed session's `detachScene()` **before** `SongTabsModel::take()` starts its removal bracket. This applies to non-selected sessions too.
5. `take()` removes the row; Repeater may now destroy the empty viewport. Destroy the returned unique_ptr only after the model mutation completes.
6. For selected close choose the session now at the original row, otherwise the last row; use the same select transaction. Empty collection stays null. Preserve unaffected page/editor identity.

**Project replacement and destruction**

Keep `m_tearingDown` suppression. Cancel the selected session and synchronously unload audio while leases live. Detach every session before `takeAll()` starts removing rows; only then destroy returned sessions. Release the embedding container/window/engine after all scene borrows are gone, and the model after QML no longer uses it. Update both `destroyAllTabs()` and `WorkspaceUi::~WorkspaceUi()`; do not leave the destructor relying on deleted host row callbacks. Preserve MainWindow's existing audio-before-workspace destruction order.

Cancellation must retire auditions with note-off and preserve existing gesture rollback/commit policy. Do not add a second cancellation traversal or change document history behavior. Readiness loss/deactivation retain their existing independent cleanup paths.

### Exact tab activation and shell focus policy

- Set each TabButton's `focusPolicy: Qt.TabFocus` and `width: implicitWidth`: keyboard entry remains available, pointer press cannot reclaim editor focus, and stock TabBar handles overflow instead of compressing all titles into equal fractions. Its `onPressed` calls the shared semantic activation immediately. After selection returns, compare `workspaceTabs.selectedSession` to `session`; enter editor only if accepted.
- Set local `Keys.priority: Keys.BeforeItem`. Enter/Return/Space call the same activation and accept the event, preventing a second stock key activation. Set `Accessible.onPressAction` to that activation too; accessibility must not merely change `checked`. Do not dispatch selection again from `onClicked`.
- The nested close ToolButton uses `focusPolicy: Qt.TabFocus`; its `onClicked` calls only `requestCloseTab(session)` and consumes its own activation. It must not emit the parent tab's semantic activation.
- Local Left/Right handlers select the next/previous model session, wrap at the ends, and call `forceActiveFocus(Qt.OtherFocusReason)` on the accepted session's TabButton rather than the editor. Zero rows is a no-op. Accept these keys before stock TabBar can independently mutate selection.
- Keep exactly one Ctrl+Tab and one Ctrl+Shift+Tab Shortcut in the workspace strip, using the same wrap calculation and `songAt()`. These change selection without explicit editor entry: editor focus stays within editorArea when already editing; strip focus stays in the strip. Preserve text/IME ShortcutOverride precedence.
- Run strip synchronization on model selection/index notifications, Repeater item-added/item-removed notifications, and strip completion. Use `setCurrentIndex(workspaceTabs.selectedIndex)` only; no reverse `onCurrentIndexChanged` command dispatch. The stack has its direct model binding.
- Retain one `Qt::StrongFocus` outer container. Convert explicit widget-origin editor-entry callers to `focusEditor(reason)`. In-page band/drawer operations continue using local item focus; they do not cross the embedding seam.
- Do not enqueue ready-focus work. Loading selection leaves editorArea as the inert entry target; its selected ready page becomes the local focus descendant when ready. If strip/widget/another application owns focus, readiness does not move it.
- Reuse `workspaceChrome` metrics/colors/font for controls and ToolTip; extend that existing metrics publication only for a needed control measurement. No raw widget pixel constants, second style provider, or custom tooltip overlay.

### Pencil shortcut migration without another dispatcher

Keep the action and registry binding. Expose two semantic operations on AutomationPage: `bool acceptsPencilShortcut(int key, Qt::KeyboardModifiers) const` and `void triggerPencilMode()`. The former incorporates the existing shortcut matcher, visible automation section, enabled action, eligible page, value-prompt exclusion, and focused text/IME exclusion. The latter triggers the existing QAction; it does not duplicate its mode-change implementation.

In `SongView::handleEditKey`, before the existing shared edit-command resolution, ask the existing automation page whether it accepts the key. If accepted, trigger once for a non-repeat press and consume repeats without toggling. Keep this behavior independent of originating band, as the existing visible-drawer shortcut is. Releases continue through the existing shared release path.

Add `Q_INVOKABLE bool TimelineQuickView::claimsPencilShortcut(int key, int modifiers) const`, which checks page eligibility and delegates to the same AutomationPage predicate. `TimelineCanvas.Keys.onShortcutOverride` accepts only that predicate. Claiming does not trigger the action. Do not run shared edit execution while arbitrating shortcuts.

Remove AutomationPage's application-filter KeyPress/ShortcutOverride branches and any keyboard-target helper made unused by that removal. Preserve `WindowDeactivate` cancellation and its window-membership predicate. Preserve TimelineInputItem local-first delivery, current band origins and canvas fallback; do not add Keys forwarding or global shortcuts to every page.

### Bounded verification: preserve existing tests, not their implementation assumptions

Acceptance rows below describe behavior to exercise; they are **not instructions to generate one test per row**. Use a temporary real-app/two-song smoke scenario first, then existing suites. Never replace a whole suite because its fixture used QWidget or the old host.

| Existing coverage | Permitted adjustment |
|---|---|
| `src/checks/support/editorrig.{h,cpp}` | Keep one canonical fixture and the existing `QuickSceneHost` scene attachment seam. Adjust only production-interface callers; no alternate old widget host or second model/controller. |
| `src/checks/workspace/tabs_lifecycle.cpp`, `tabs_persistence.cpp` | Keep lifecycle, undo isolation, reload/fresh-open, dirty-close and persistence assertions. Replace obsolete widget/host access only. |
| `src/checks/workspace/tabs_model.cpp` | Keep `tabModelRemovalKeepsSelection`. Delete `tabModelMovesPreservePersistentIdentity` with the removed move contract; do not translate it into a test that counts QML delegates or re-pins roles. Keep model-removal behavior coverage rather than rebuilding the suite. |
| `src/checks/workspace/tabs_quickshell.cpp`, corresponding declarations | Delete `quickTabStripReorderPreservesPages` and reorder-only registration/assertions. Retain select/close/title/readiness/overflow behavior. Replace ListView/drag-implementation assumptions with actual TabButton/ToolButton interaction only where needed. |
| `src/checks/host/tst_hostadapter.cpp`, `tst_hostseams.cpp`, `tst_pagepopups.cpp` | Preserve shared-window page isolation, popup cancellation, native lifetime and meaningful detach checks. In particular retain `outsidePressOnDestroyedSceneKeepsSiblingReleaseSafe` and `ineligiblePageCancelsPromptAndRejectsEntry`; adapt attachment/access paths, not expected safety. |
| `src/checks/mainwindowrouting/` | Preserve text/action precedence and native/lifecycle scenarios. Change access to the embedding host and remove obsolete missing-focus-fallback expectations; exercise explicit entry instead. No focus-history fixture helpers. |
| `src/checks/automation/automationactions.cpp` | Keep `actionShortcutLatching`, `actionTextInputImmunity`, `actionRepeatImmunity`, `actionCustomBinding`, `actionHeldKeyGestures`. Exercise the real page route after the application keyboard filter is removed; do not call the new predicate directly as a substitute. |
| `src/checks/selectionkey/`, existing event-view/playhead checks | Keep behavioral assertions and fixtures except required host API access. No new suite, golden image, source-string assertion, or window-count requirement. |

Adapt existing checks in place; do not expand the permanent test inventory for this migration. No new test cases, suites, fixtures, helper framework, or permanent probes without explicit user approval. Use temporary smoke scenarios for additional verification, then remove them. Do not duplicate popup release, undo/session isolation, action repeat or text-precedence coverage already listed. Do not weaken a failing safety assertion to finish this migration; if existing coverage cannot express a necessary regression, report that specific gap rather than silently adding test infrastructure.

Run once after integrated edits settle:

```sh
deno task format <changed-C++-and-QML-files>
deno task verify --filter tabcheck --filter sessioncheck --filter selectionkey \
  --filter automation-editing --filter eventviews --filter rollcheck \
  --filter host- --filter page-popup-seams --filter mainwindow-routing \
  --filter playhead --filter rollwindowing --verbose
```

`--filter` uses substring matching; repeated flags are ORed. A pipe-separated regex would match no harness. These names are grounded in `src/checks/checkcatalog.cpp` and `tools/run_checks.ts`; no new runner. Verify builds first, so do not run a duplicate standalone build before it. Review the selected suite list to ensure all four selectionkey suites, page-popup-seams and relevant native host/playhead suites are included. Run native scenarios sequentially; do not repeatedly stress focus-sensitive checks while the desktop is in use.

Actual app smoke must cover two real songs, ready/loading handoff, editor versus strip versus widget-search focus, one-press popup-to-tab selection, close during interaction, and native playhead visibility/alignment. Record observed results and any platform not exercised. Offscreen probes do not substitute for this.

Only after successful smoke/affected verification: remove temporary probe files, obsolete fixture helpers and dead source/resource entries; update the existing composition plan/progress documentation to supersede the host implementation. Do not add a new test framework, documentation tree or permanent probe.

If an integration failure occurs, repair the specified focus owner, cancellation order, or Qt lifecycle hook. Do not add a host page registry, window song-key dispatcher, focus history, native activation on selection, broad canvas rewrite, or alternate implementation mode.

## Bounded deletion pass: implementation plan

This replaces the earlier A–E cutover sequence. Work on the existing composition worktree, on top of its current edits; do not restart the conversion, overwrite another agent's work, merge, or change window topology. One integration owner coordinates these edits because attachment, focus and teardown share files. Investigation may be parallel, but no concurrent edits to these shared files or validation while edits are in flight.

**Deliverable:** a smaller working implementation, adapted existing checks, and an honest remaining-cost report. Completing the removal list is not sufficient if the small-delta goal is still missed. No new general-purpose module, alternate implementation, test fixture family or permanent probe is permitted.

### A. Establish the actual starting point and deletion ledger

1. Reconcile with the active implementation owner before editing. Capture the branch HEAD and the current dirty diff; do not commit, stash or reset it. Use the latest files and LSP references, not review-time line numbers.
2. Pin `fork-main` to its current commit for the comparison. Record three separate deltas: final versus that original baseline, final versus composition commit `06054ac8`, and this pass versus the captured dirty starting state. Separate production, checks, and documentation; include untracked source if any appears.
3. In the existing progress/plan document, use a short ledger with columns: file/symbol, responsibility, delete/retain, surviving consumer, and before/after cost. No new report framework or generated metric file. Distinguish executable/declarative code changes from comment-only reductions and movement between files.
4. Audit these groups together: all six `workspacequick` files; `timelinequickview.{h,cpp}` plus `timelinequickview_window.cpp`; `quickpopupsession.{h,cpp}` plus `quickwindowinput.{h,cpp}`; affected WorkspaceUi/MainWindow callers; modified checks. Do not count construction moved from `timelinequickview.cpp` into the window file as new work, or moving it back as a deletion.
5. The named removal targets below are the pass's scope. If a target is already removed, mark it satisfied. If current references reveal a real extra consumer, retain the required behavior and record it; do not invent a replacement abstraction to force a deletion.
6. Estimate the residual production implementation after the named deletions, using the end-product constraints above. If it still plainly conflicts with the small-delta requirement, report that conflict now rather than treating completion of phases B–F as permission to accept it. This gate does not authorize rollback or a replacement architecture.

**Exit:** a source-current inventory, one owner for edits, and an evidence-backed route to the small-delta goal—or an explicit early report that this pass cannot presently establish one. No production changes solely to improve the count. The historical +1,723/+1,492 figures are context, not a fresh measurement.

### B. Establish correct Qt focus ownership before removing anything else

**Files:** `WorkspaceSongs.qml`, `TimelineCanvas.qml`, existing mainwindow-routing state check.

The live review follow-up already found the corrected structure: `editorArea.focus: true`, a direct `FocusScope` page delegate, required `ready`, and `focus`/`enabled: StackLayout.isCurrentItem && ready`. The redundant inner viewport Item was removed and attachment targets the page delegate itself. Preserve this correction; do not repeat the broken Item experiment or add another page wrapper.

Verify the existing hierarchy against the exact contract above:

- One persistent page scope, one coordinator-owned canvas, one attach; no page recreation on selection.
- Initial descendant focus is local to that page; ordinary selection/readiness never invokes native activation or default-surface refocusing.
- Editor entry resolves the actual selected page's input, not merely a non-null `activeFocusItem`.
- A → B → A reaches B's input and restores A's previously focused descendant, including a non-default text/control target.
- Loading content stays inert; readiness enters its descendant only when the editor area already owns focus. Strip, widget search and external focus are not stolen.

Use the real app with two existing songs for this prerequisite smoke. Use the implementation owner's source-current app build; if it predates the focus correction, run `deno task build:app` for this smoke only. If the scenario fails, fix the specified hierarchy/entry operation; do not add a dispatcher, timer, focus-history field or new permanent check. This small integration smoke is not a request for another synthetic host or prototype. Record it separately from the final affected-suite run, which already builds its own targets.

**Exit:** the actual surface behaves correctly without the fallbacks that this pass is meant to delete.

### C. Reduce the tab module to its actual responsibilities

**Files:** `workspacequickhost.{h,cpp}`, `WorkspaceSongs.qml`, `SongTabStrip.qml`, `songtabsmodel.{h,cpp}` and affected WorkspaceUi callers.

| Target | Exact operation | Must survive |
|---|---|---|
| Host `m_model`, `m_workspaceUi` | Remove these stored references: the reviewed implementation uses them only to publish constructor parameters into the QML context. Publish `&model` and `&workspaceUi` directly. Do not introduce replacement getters or a context wrapper. | Existing context names, C++ ownership, and constructor lifetime ordering. |
| Host page/control machinery | Any remaining Page hash, row observer, sizing/visibility loop, selected-scene publication or select/close/move forwarding is deleted, not relocated. Already-removed code stays removed. | One embedded QQuickView/container, appearance updates, `focusEditor(reason)`, and `window()`/`container()` where real callers need them. |
| Workspace page | Keep the corrected direct FocusScope delegate. Delete unused required `index` if it has no remaining expression consumer. Keep only the existing two one-shot attachment booleans. | Incremental Repeater ownership, empty state outside the stack, ready/focus bindings, detach before row removal. |
| TabButton delegate | Delete unused required `index` when navigation uses `workspaceTabs.selectedIndex`. Remove dead chrome entries such as `minimumTabWidth` only after checking all workspace QML consumers. | Width from implicitWidth, stock overflow, close button, accessible names/actions, ToolTip, theme metrics and plain-text title rendering. |
| Strip command code | Keep one accepted activation function, one neighbor lookup and one `setCurrentIndex` synchronization path. Delete drag/reveal/tooltip-position machinery and any duplicate onClicked selection or reverse currentIndex controller. | Pointer selects on press; close does not select a clean background song; arrows retain strip focus; Enter/Space/accessibility enter the editor; exactly two window tab-cycle shortcuts. |
| Model QML ownership publication | Put the existing session/coordinator CppOwnership assignments in existing `observeTab`, used by constructor and append. In append, establish this exposure invariant before insertion notifications can cause QML to read the objects. Delete the duplicate constructor/append assignment blocks, without adding another helper. | Borrowed authoritative storage, stable identities, ordinary Qt insertion/removal brackets, no selected-session copy or cached row array. |
| Model mutation and notifications | Retain append/take/takeAll, rowFor/songAt, roles, saved-state refresh and the two existing selection notifications where consumed. Remove only dead move/reorder operations or demonstrably unused helpers. Do not replace the model with QQmlListProperty, model resets, a mirror array or a new controller. | Metadata/readiness updates preserve page instances; removed sessions outlive the Qt removal bracket; background removal preserves selected identity. |

The six tab-module files are not individually required to disappear: a Qt model and an embedding adapter perform real work. Do not merge unrelated responsibilities, split files into forwarding fragments, or introduce generic style/token helpers to reduce one file's count.

**Exit:** no duplicated page ownership or command routing; remaining tab-module code implements model notification, appearance, stock-control composition or the single embedding seam.

### D. Remove redundant scene/popup plumbing, not isolation guarantees

**Files:** `timelinequickview.h`, `timelinequickview_window.cpp`, `quickpopupsession.cpp`; affected references only.

**Confirmed removals:**

1. **Remove `retargetPopupSession`.** References found one call from `attachScene`, plus declaration/definition. There is no retarget lifecycle in this design. At that call site construct the popup session once from the already-validated window/context; retain `setPopupSessionBindings`, `setPageRoot` and the existing `viewportChanged` connection. Delete the old destroy-and-recreate branch and nullable-window/context/root recovery branch. Teardown still clears bindings and destroys the session through the existing detach path.
2. **Remove duplicate popup geometry subscriptions.** `QuickPopupSession::setPageRoot` currently observes root x/y/width/height, while `TimelineQuickView` already sends those changes through `viewportChanged` to `handlePageGeometryChanged`. Keep the coordinator as the sole mapping publisher and remove those four direct geometry connections. Keep popup root enabled/visible/destroyed observation, page eligibility checks and root-clear handling; those provide cancellation/entry safety, not merely geometry updates.
3. **Remove duplicate attached-state rejection.** Keep the existing lifetime one-shot guard `m_hasAttached`; remove the later `m_sceneContext || m_root` second-attach check if the same construction path is still fully governed by that guard. Keep null window/engine validation and real QML creation failures. Do not turn failure into silent success or remove validation of required input objects.
4. **Keep deleted rehosting paths deleted.** No `trackViewportWindow`, window reassociation, canvas recovery/reattachment or resize-forwarding connection may return. Retain root geometry observation that actually republishes the editor layout.

**Explicitly retained in this pass:**

- `attachScene`/`detachScene`, page-local context and separate canvas QObject/visual ownership. The context feeds existing nested QML; replacing it with a broad required-property rewrite is out of scope.
- Existing input/layer binding tables and scene wiring moved out of the old constructor. They bind the real canvas; relocating or disguising them is not a reduction.
- `m_detaching` reentrancy protection, hostless input unbinding, and crash-safe handling when a borrowed engine/window dies. Do not delete that safety because normal WorkspaceUi teardown is ordered. No new engine-loss recovery mode.
- `setPageSelected(false)` before relinquishing the outgoing audio/session authority, and existing readiness/cancellation semantics. QML focus is not note-off or gesture rollback.
- `QuickWindowInput`'s window-lifetime outstanding-release bitmask, newer-press handling and deactivation clearing. The popup/page can die before the release; moving the mask into either is invalid.
- `watchSceneMapping`, its current geometry/visibility/clip consumers and clipped rectangle calculation. Keep the cache that suppresses unchanged publications. This pass removes duplicate consumers, not the one remaining ancestor-observation source. No hard-coded strip offset, whole-window clipping fallback or native-renderer replacement.
- Native surface/DPR/deactivation handling and window-bound geometry notifications. A canvas-size notification alone is not proof that a window-bound popup or native clip needs no update.

Do not factor `handleEngineDestroyed` and normal detach into a mode-flag mega-function to reduce repeated-looking lines: one runs against a partially destroyed host and cannot safely perform normal cursor/native work. Do not replace the scene lifecycle with a generic owner/registry/state machine.

**Proof for the geometry deletion:** the existing translated/clipped-page popup case must still re-clamp a live popup when an ancestor shrinks, without a window resize; native playhead alignment must still survive canvas-only resize, workspace resize and DPR changes. If that fails, identify the missing existing notification; do not restore two equivalent observer systems or add polling.

**Exit:** one attach-time popup construction path and one geometry publication path, with all cancellation, engine-loss, sibling isolation and native guarantees intact.

### E. Adapt existing checks and remove the unused fixture expansion

**Files:** `src/checks/support/editorrig.{h,cpp}`, existing host/page-popup checks, workspace quick-shell checks and mainwindow-routing state check.

1. **Delete `EditorRigConfig::attachScene`.** Source-current references found only its declaration and the two internal reads in `EditorRig::create`; no scenario sets it. Restore unconditional ordinary rig attachment and root/input validation; delete the deferred-null-root branch and its comments. Do not add consumers just to justify the option.
2. **Delete both `EditorRig::host()` accessors.** References found declarations/definitions only. No substitute accessor or public fixture exposure.
3. **Keep the actually consumed `QuickSceneHost(..., bool attachScene)` option.** The translated-popup case constructs a real SongView and directly uses `QuickSceneHost(..., false)` to attach once to its custom viewport. That is an adjustment to the canonical existing host, not justification for an unused second deferred mode in EditorRig.
4. **Repair the existing focus assertions, not the input under test.** After `focusEditor`, assert the selected page's intended descendant receives focus before calling any test helper that focuses a band. During A → B → A, assert B receives focus before switching back; use a non-default descendant on A to distinguish retained focus from default refocusing. Keep widget-search and background-readiness assertions. No new test case is required.
5. **Adapt live-theme coverage instead of discarding it.** In the existing quick-shell case, exercise the already-covered theme change and check the stock control's rendered background rather than the removed Rectangle root's `color` property. Reuse the existing theme restoration helper; do not create a second theme fixture or a new test suite.
6. Preserve `tabModelRemovalKeepsSelection`, `sharedHostSceneDetachPreservesEditableSibling`, `outsidePressOnDestroyedSceneKeepsSiblingReleaseSafe`, `pageEdgePopupClampsInsideTranslatedViewport` and `ineligiblePageCancelsPromptAndRejectsEntry`. Preserve their behavioral assertions, adapting only the host/attachment access they need.
7. Remove reorder-only cases and obsolete ListView/window-identity assumptions. Do not remove title/readiness, undo/audio, sibling editing, cancellation, native visibility or lifecycle coverage to make the diff smaller.

The removed engine-recovery/reattachment scenarios are not permission to delete terminal engine-loss safety. If no surviving case exercises that terminal path, use a disposable scenario against the actual coordinator; do not restore unsupported recovery or generate a new permanent harness.

**Exit:** existing checks use the production ownership contract; no new case inventory, unused fixture modes or permanent probes. Any newly introduced runtime failure is fixed, not weakened away.

### F. Run the affected verification once and make the size decision

Once all owners' edits settle, run the existing format/verify commands in “Bounded verification” above. Do not add a duplicate standalone build or run native suites concurrently. A failed check requires a root-cause repair and a targeted rerun, not repeated desktop stress or weakened assertions.

Native smoke uses the real widget shell and two real songs. Exercise the acceptance matrix below, including non-default focus retention, loading handoff, strip/widget text precedence, popup-to-tab one-press selection, stale-release safety, close during interaction, playback and native clipping. Record the platform and actual observed results; offscreen QML evidence is not full-app evidence.

Include the end-product constraints in this same delivery review: supported Qt/toolchains, the existing packaged artifact, ordinary strip usability, bounded idle/playback/open-close behavior and the hypothetical maintenance-locality review. No additional implementation phase, permanent harness or platform expansion follows from these checks.

After that proof, remove temporary probes and obsolete declarations/resource entries, and shorten repeated explanatory prose in changed code to the ownership/cancellation invariants a maintainer needs. Keep comments explaining why engine-loss unbinding differs from normal detach and why release suppression outlives a popup. Comment-only deletion is reported separately, not sold as removal of runtime complexity.

Publish the final ledger using the pinned baselines from A:

- Production additions/deletions/net, check additions/deletions/net and documentation separately.
- Module totals, accounting for moved code; the remaining custom state and observer paths, not just file sizes.
- Which named removals happened, which responsibilities remain and the concrete consumer requiring each.
- Verification evidence and any capability not exercised.

**Hard stop:** a remaining four-digit net production increase over the original baseline does not meet “very few additional lines.” A smaller number is not automatic acceptance either: it must come from deleting responsibility, not comments, formatting, file moves or safety coverage. If the named safe reductions still leave a substantial custom tab/scene subsystem, stop this pass and report that the shared-window architecture has not met the size requirement. Recommend retaining the original QTabWidget/per-song-window design versus explicitly accepting the measured shared-window cost; the user decides. Do not revert ongoing work or launch a second redesign, full-QML shell migration, popup rewrite or canvas-interface migration to avoid that decision.

## Acceptance matrix

| Scenario | Required observable result |
| --- | --- |
| A → B → A | Document, undo, viewport and editor state survive; focused descendant returns according to policy; no canvas recreation on ordinary switch. |
| Select/close by real tab controls | Checked tab, page and audio agree. Clean close of non-selected B leaves A selected without audio handoff. Dirty close reveals/prompts for B according to existing policy; Cancel leaves B open. Close-button activation never also activates its parent tab. Current close selects successor; last close shows empty workspace. |
| Model insertion/removal before selected row | Selected session stays selected; unaffected page/editor identity survives; strip and stack agree after the transaction. |
| A ready, B loading | A stays editable; selecting B blocks only B's editor, not strip/shell. Ready while still in the editor area enters B; ready while in strip, dock search or another app never steals focus. |
| Text editing and keyboard tab navigation | Text undo/clipboard/IME retain precedence. Arrow selection keeps focus within strip while checked tab/page/audio agree; Enter/Space enters content. Ctrl-Tab or existing equivalent switches once, not once per page. |
| Pencil/edit commands with two pages | Only eligible current content acts; hidden automation page never consumes the key. |
| Switch/close during drag or held audition | Outgoing gesture terminates safely, no accidental commit on B, every held audition receives note-off. |
| Popup → different tab | One press on B's tab cancels A's popup and selects B, without a second dismiss-then-select click or outgoing focus restoration. Outside press within A's page dismisses without creating a note/edit; overlay is gone after switch. |
| Dismiss press → close A → release | No release leaks into B, no stuck grab; next complete click on B works. |
| Resize/move workspace; mixed DPR | Canvas hit testing and native playhead remain aligned below strip; hidden page playhead never paints; popup occlusion remains correct. |
| Widget search/transport → Quick → external app → return | Explicit focus handoff works; background readiness does not reactivate the window; no fallback key broadcast required. |
| Project switch / app close while loading or popup open | Audio unloads before bank/session destruction; no stale callbacks, scene borrows, native layers or focus restoration into dead pages. |
| Reopen project | Open order and selected identity restore; title/dirty updates do not reset page state. |

Native/macOS runs must be sequential and performed on the actual app, not inferred from offscreen tests. Do not stress-repeat input checks while the desktop is in use.

## Deletion budget and review gate

The architecture is accepted only if the implementation removes responsibility, not just relocates it:

- Zero C++ loops maintaining page size or visibility.
- Zero host-owned duplicate page tables.
- Zero per-song native windows or native focus activation.
- Zero custom focus-history registries or window-level song-key fallback dispatchers.
- Zero duplicated global shortcuts per song.
- Zero tab drag/reorder machinery under the documented append-order decision.
- No unrelated widget shell conversion in the recommended tab delivery; a MainWindow-down conversion requires its own explicit scope decision.
- Any remaining window event filter must name its real native lifecycle, popup shortcut arbitration, or pointer-sequence contract; it cannot own song selection or substitute for focus propagation.
- Any remaining mapping watcher must have an actual native/popup consumer, not be a general scene-graph clone.

Use the bounded pass's final size gate, not another open-ended integration spike. Stock TabBar does not supply close buttons or application selection transactions; FocusScope does not eliminate all cancellation code. Name and measure what remains. If the safe reductions cannot meet the small-delta goal, report that result and the architecture tradeoff rather than extending this pass or accepting the existing subsystem on faith.

## Planning experiment: result and limits

Ran a disposable QML application with the installed **Qt QML Runtime 6.11.0**, using `TabBar`, `StackLayout`, `Repeater`, per-page `FocusScope`, two TextFields per page, a ListModel and incremental row operations. Command shape:

```sh
QT_QPA_PLATFORM=offscreen /opt/homebrew/opt/qt/bin/qml /tmp/<probe>/Tabs.qml
```

The corrected probe exited 0 and reported all eleven assertions passing:

1. A's second editor receives focus.
2. Switching transfers active page focus.
3. StackLayout owns page visibility.
4. StackLayout sizes the current page.
5. Returning to A restores its second editor without a focus registry.
6. Background readiness does not disable the selected page.
7. Incremental insertion preserves existing page identity.
8. Bound selection survives insertion.
9. Incremental removal preserves page and focused descendant.
10. Resize updates page without a host sizing loop.
11. Last close produces an empty strip and stack.

An initial QML declaration syntax error was corrected before this successful run. This was an offscreen runtime experiment, **not native UI verification**. It used QML ListModel, not the production C++ model; programmatic selection, not actual tab clicks; no QWidget host, popup, MIDI engine or CALayer. It supports the core composition choice and does not waive any integration gate above. No production test suite was run because this deliverable changes documentation only.

A second offscreen probe exercised the nested editor-area FocusScope used in the plan. It exited 0 with five assertions: editor entry reaches the selected page; tab controls can hold focus; selection changes keep focus in the strip when navigating there; explicit editor entry reaches the newly selected page; and switching while editing transfers editor focus. An initial assertion incorrectly required focus to remain on the *old tab button* after changing TabBar.currentIndex. It was corrected to require focus remain anywhere in the strip, rather than pinning the old button. No production failure was hidden by that correction. Actual mouse/keyboard activation and widget-shell handoff remain integration gates. Both disposable probe files were removed after execution.

### Native QWidget/Quick seam experiment

Ran a disposable C++ executable against installed Qt **6.11.0 on the native macOS platform**, not offscreen. It constructed a QMainWindow with a QDockWidget/QLineEdit, one StrongFocus window container holding a QQuickView, a window QAction, and QML TabBar/StackLayout/Repeater/page FocusScopes. The probe had no application/window key filter, selected-scene pointer, focus-history registry, or per-switch native activation.

Built using a standalone `deno task build` in its temporary directory (not a repository build task). Executed as a supervised native process. Its corrected run exited 0 with twelve PASS checks:

1. Native widget shell becomes active.
2. One container/editor-area entry reaches A's initial input.
3. An unclaimed key reaches only A's canvas ancestor handler.
4. A locally accepted key does not propagate.
5. A QWidget-owned window QAction triggers from focused Quick content without forwarding.
6. Quick text input and its local ShortcutOverride precede that QAction.
7. A TabButton mouse press selects B and enters its content without a native activation request.
8. Hidden A receives no B command.
9. Returning to A restores its text descendant without a registry.
10. Changing selected page while QWidget search has focus does not steal that focus.
11. Explicit editor entry returns from widget search into selected B.
12. Quick commands resume after that native embedding crossing.

The initial standalone build needed Qt's integration include path and GUI/Widgets defines. The initial run crashed because the probe searched Repeater-created items through QObject children rather than the visual child tree; LLDB confirmed a null receiver at `QQuickItem::hasActiveFocus`. Correcting the **probe lookup** produced the passing run; no production code was changed or failure suppressed.

Limits: real Qt controls/native windows with QTest-injected keys and mouse events, not a human-input or full-Porydaw run. The scene models the focus hierarchy; it does not instantiate production TimelineInputItem, project sessions, audio, popups or CALayers. It directly establishes that the widget/Quick seam does not require an extra keyboard dispatcher for the exercised paths. Native Tab/Backtab traversal, external-application return, actual popup pointer sequences, production model teardown, and renderer behavior remain integration verification—not undecided architecture.

### Attachment lifecycle specification probe

Ran a further disposable QML application with the exact `Component.onCompleted` / `Window.onWindowChanged` join specified above, on Qt 6.11.0 with `QT_QPA_PLATFORM=offscreen`. It exited 0 with five passing observations:

1. A window-associated component attaches once.
2. A completed component without a window remains unattached.
3. Its initial window association completes attachment.
4. Canvas anchors follow the StackLayout-managed page size.
5. Selection and resize do not reattach either page.

This validates the QML notification syntax and one-shot ordering, not production C++ attachment, model-removal lifetime, or native rendering. The probe was temporary; no permanent test or production source was added.

## Primary Qt references

- [TabBar](https://doc.qt.io/qt-6/qml-qtquick-controls-tabbar.html): stock tab controls, dynamic population, currentIndex binding cautions, overflow flicking; no automatic document-close/reorder policy.
- [StackLayout](https://doc.qt.io/qt-6/qml-qtquick-layouts-stacklayout.html): child geometry/visibility and `isCurrentItem`; since Qt 6.5, insertion/removal adjusts currentIndex to retain the current item where applicable.
- [Keyboard focus and FocusScope](https://doc.qt.io/qt-6/qtquick-input-focus.html): scoped focus and propagation to ancestors.
- [Popup](https://doc.qt.io/qt-6/qml-qtquick-controls-popup.html): Popup.Item content lives in the window overlay; parent-relative placement is not page-local modality.
- [createWindowContainer](https://doc.qt.io/qt-6/qwidget.html#createWindowContainer): container owns window geometry/visibility and lifetime; Qt 6.8 adds Tab traversal into/out of embedded Quick windows; native activation remains platform-dependent.
- [QQuickWidget](https://doc.qt.io/qt-6/qquickwidget.html#performance-considerations): alternative embedding with extra render pass and disabled threaded render loop. Not selected here because it changes rendering characteristics and native-playhead assumptions unnecessarily.
- [Keys](https://doc.qt.io/qt-6/qml-qtquick-keys.html): accepted events stop; unaccepted events propagate to the parent; Keys.AfterItem and ShortcutOverride provide local precedence.
- [SplitView](https://doc.qt.io/qt-6/qml-qtquick-controls-splitview.html): splitter layout and size persistence, not QDockWidget relocation.
