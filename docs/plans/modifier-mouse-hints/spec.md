# Modifier-mouse hints specification

Revision 3: retain the corrected ownership/delivery contract; constrain implementation proof to realistic workflows and require the plan's bounded thermo gates. [audit.md](audit.md) preserves the rejected first design; [readiness.md](readiness.md) separates prior technical evidence from current review-policy validation. This is an implementation specification, not a claim that the feature exists.

**Subsequent refactor:** [centralization/spec.md](centralization/spec.md) supersedes the string-payload, element-local wording/cache, pointer-text annotation, and associated publication/native-predicate naming contracts when executing [its supplemental plan](centralization/plan.md). Do not restore `fragment`, `publish(QString)`, `setPointerDescription`, or local description caches during that cutover. This document remains authoritative for existing action/hover/lifetime behavior; the supplement adds no input behavior and runs only after the current implementation/fixes are verified.

## Agreed behavior

Hover immediately lists the target's **existing modifier-dependent mouse alternatives**, including click, double-click, drag and wheel/trackpad, in a smaller-font middle status region. Cover the complete [inventory](inventory.md), including ordinary controls, Quick popups, owned dialogs and floating docks.

Show all alternatives without waiting for a modifier, tooltip delay or click. No availability checks, dimming, selection/value/document eligibility, `canGhostParameter`, enabled-command queries or hypothetical execution. Actual target/tool distinctions are allowed: edge versus body, node versus pencil, row versus text editor. A configured widget family/selection mode or style chord is not action availability.

No new actions/chords, changed gesture precedence, changed selection/undo, held-modifier listener, keyboard-only help, keybinding editor, preferences, persistence or tutorial system. Preserve existing press-time versus live/release-time modifier semantics. Retaining a description during a drag does **not** freeze live Alt snapping or other existing input semantics.

## Presentation

- Keep QStatusBar and every existing `showMessage`/`clearMessage`/timeout caller. Operational text remains left; polyphony remains right.
- Add an empty normal reservation with stretch 1 and `setRetainSizeWhenHidden(true)`, then a permanent hint widget with stretch 2 before the existing zero-stretch meter. The proven Qt layout allocates approximately one third/two thirds of the remaining width, without manual geometry.
- Center a single line in the hint region. Use `typography::caption`, existing theme roles and font-relative `layout::` primitives. Horizontal size policy ignores text width; minimum width is zero. Reserve the region when empty.
- Right-elide; expose the full current text through accessible description. **The hint label is noninteractive: no tooltip inspection, retained-history handoff, delayed clear or special ownership on label hover.** Moving there ends the old target's hover normally.
- Hint changes cannot increase window minimum width, change bar height, move the meter or resize the window. Compare equivalent font/window/meter states; intentional font/window/meter changes may naturally change geometry.
- Translate compact mouse-operation phrases. `Shift or Alt` means alternatives, not a combined chord. Use `fragment` and native Qt modifier rendering; read the shipped velocity/detent bindings from `keymap::Registry::modifierBinding` and native spin step modifiers from `QStyle::SH_SpinBox_StepModifier`. Never copy those authorities into another chord table.

## Module and public contracts

One `ui::MouseHints final : QObject`, application-owned under the live QApplication, GUI-thread-only. No null-parent fallback, per-tab destination map, candidate registry, ranked stack, scene search, polling, cursor-sampling timer or document subscription.

Place the service/formatter in `src/ui/mousehints/mousehints.{h,cpp}`. Put the cohesive private native observer, family resolver and eliding status widget in `src/ui/mousehints/widgethints.cpp`. The latter defines native setup/annotation methods; no forwarding-only headers or new public widget framework. Domain phrases and target discrimination remain beside their input owners.

Public service:

- `static MouseHints &instance()` — QApplication child, GUI thread. Adapters borrow it; teardown must not recreate it.
- `void install(QStatusBar &bar)` — install native observation and the status region once; Qt owns bar children, not the service. Private native observation is one application event filter.
- `Q_INVOKABLE void publish(QObject *source, const QString &text)` — a live QWidget or QQuickItem source; replace ownership even for identical text. Empty text is a real claim by a no-hint target. Reject sources outside current native/application input scope.
- `Q_INVOKABLE void clear(QObject *source)` — clear only the current owner. Unhover uses this, not empty publication.
- `QObject *currentSource() const`, `QString currentText() const`, signal `void hintChanged(const QString &text)` — presentation reads; notify only when displayed text changes, not just identity.
- `Q_INVOKABLE QString fragment(int modifiers, const QString &operation) const` — native modifier labels plus translated mouse operation. Callers join fragments with ` · `.
- `static void setPointerDescription(QWidget &widget, const QString &text)` — custom pointer metadata replaces the family's pointer description while retaining inherited wheel behavior; no subclass-name deny-list.
- `bool allowsSource(QObject *source) const` — the same native/application input-scope predicate used by `publish`, available to the physical host's discrete resync. This is not action eligibility.
- Signal `void scopeRefresh()` — one coalesced queued notification after native input-scope recovery/application activation. Receivers re-evaluate their current target; this is not a saved-source stack or polling loop.

On owner replacement disconnect the old lifetime/visibility observations even when text is identical. Guard source borrows. Observe current Quick effective visibility, window/parent detachment and QObject destruction, not just QObject lifetime. Destruction callbacks must still clear the correct slot after QPointer has become null; an old object's destruction cannot clear a replacement owner. Source hide/window detachment always terminates that source, including during a grab.

## Native observation and input scope

The observe-only filter always returns false and preserves event acceptance. Use existing configured text/item-view/spin/slider/scroll-area families from the inventory; annotate custom controls once. Do not advertise ExtendedSelection on actual SingleSelection views, or ordinary Shift-click text selection in DragSpinBox's overridden editor.

Observe original spontaneous mouse delivery, Enter/Leave and discrete visibility/style/metadata transitions. Qt already sends application filters mouse moves for widgets without mouse tracking. Do not enable global mouse tracking. Propagated ancestor mouse copies must not overwrite the leaf: the Qt source and executed probe show they are non-spontaneous after original delivery. Cache descriptions by physical widget/profile/style, not pointer pixel.

Track the guarded actual pressed native source until final release; `QWidget::mouseGrabber()` alone does not report implicit button-down routing. Keep its originating profile during the grab. Settle from actual release coordinates and visibility; release outside clears, release inside keeps/refreshes. Focus loss alone is not hover loss. **`QApplication::widgetAt(QCursor::pos())`** may resolve stationary native recovery on a discrete topology/scope transition; no custom global tree walk or per-pixel hit scan.

Use `QGuiApplication::applicationStateChanged`: inactive clears and rejects subsequent updates; active requests resync. MainWindow deactivation alone does not suppress an owned dialog or floating dock.

Mirror **Qt-delivered** `QEvent::WindowBlocked`/`WindowUnblocked` in private metadata on each observed QWindow. `allowsSource` checks the source's window and native parent chain for those bits; do not recreate Qt's modality/ancestry policy or block unrelated windows merely because a window-modal dialog exists. The executed probe confirms delivery to embedded Quick windows. Observe actual native popup scope via `QApplication::activePopupWidget`; exclude tooltip windows. Widget Show precedes Qt's popup registration, so queue one scope reconciliation after Show; Hide follows deregistration. Reject covered background updates throughout the actual scope and emit `scopeRefresh` after recovery. No timer, private Qt API or OS-global input hook.

OS-owned file dialogs and window-manager decorations are outside this feature. Do not replace or raise windows to keep the status bar visible.

## Physical C++ host seam

`TimelineInputHost` gains exactly two pure virtual presentation methods:

```cpp
virtual void setMouseHint(const QString &text) = 0;
virtual void refreshMouseHint(const QString &text) = 0;
```

The three concrete hosts are `TimelineInputItem`, `RasterAutomationInputHost` and `CursorDprHost`. Migrate them together: production publication is real; the two existing headless hosts record the presentation values/ownership instead of fake no-op overrides. No `TimelinePointerInput`, `TimelineWheelInput` or `TimelineBandInteraction` signature changes.

- A band's real delivery uses `input.host` first, existing attached host only as the established fallback, then `setMouseHint`. **The emitting TimelineInputItem is the service source, never the shared band QObject.** Plot/gutter can therefore never clear each other by identity.
- `setMouseHint` claims only while the item is a live hover/grab source and not muted. `refreshMouseHint` is a stationary **non-claiming** update: publish only if this item still owns the display. Automation's stationary pencil refresh uses its existing primary plot host; never retain a raw borrowed gutter host.
- Bands publish descriptions only. They do not clear in `pointerLeave`, cancellation or detach; the physical host owns lifetime. Reuse existing hit results and lazily cached profiles. No new note/point scans or formatting on unchanged per-pixel targets.
- `TimelineInputItem` adds public `setHintMuted(bool)` and `resyncMouseHint()` for its view, plus real HoverEnter handling. Muting suppresses **all** claims, including empty claims, and clears only this item if necessary.
- First idle HoverEnter forwards the existing hover computation once; preserve the existing HoverMove acceptance path. A no-hint interaction still claims empty on entry. After idle dispatch, if no band claimed this item, the adapter claims its empty profile; do not clear/re-publish empty before every nonempty profile.
- `resyncMouseHint` is explicit **reacquisition**, not `refreshMouseHint`: require a visible/windowed, unmuted, still-hovered item, native scope permission, actual cursor containment, no exclusive grab anywhere in its window and no active domain gesture. Recompute the existing idle hover path at current mapped cursor coordinates, then claim through `setMouseHint`. The physical host never injects Qt events or invokes an active pointer-move path. No stale cached target restoration. Lost membership must be restored by Qt's actual leaf delivery, using the guarded view-level recovery below; never force a lower item to claim through a higher leaf.

Host transition rules:

| Transition | Hint effect; domain input remains unchanged |
| --- | --- |
| First enter / idle move | Real physical source, current target; empty for no-hint targets |
| Plot → gutter, late plot leave | Gutter owns; clear(plot) cannot erase it |
| Exclusive drag outside | Retain originating profile; Qt freezes ordinary hover during the grab |
| Ordinary leave without own grab | End this item's hover and source-check clear |
| Release/ungrab | Forward existing cancellation; actual inside keeps/refreshes, outside clears; handle both normal ungrab and cancelled/stolen grab |
| FocusLost | No hint clear solely for focus; preserve domain cancellation |
| Hidden/destroyed/detached/rebound | Clear only this physical item; no teardown singleton recreation |
| Popup mute / native block / app inactive | Covered updates rejected, not merely cleared once |
| Scope recovery | Idle reacquisition for retained membership; guarded view-level recovery lets Qt restore lost membership to the actual leaf |

## Quick popup authority and declarative groups

Create the existing QuickPopupSession before loading TimelineCanvas. Expose **`mouseHints` and `quickPopupSession`** in the existing engine root context before `setSource`. Mark the existing `QuickPopupSession::owns(const QObject *) const` Q_INVOKABLE; preserve its implementation and C++ callers. No MainWindow ancestry lookup: SongTab is initially unparented. No mirrored popup state/property or static `popupOwned` exemptions.

QuickPopupSession remains the authority. On open, after canonical state/parenting and the `isOpenChanged` gate update, publish empty with its **physical overlay root** as source. On end, clear that captured root before detach and before the closing notification; current popup children clear through real hide/detach observations. Never restore a previously saved source.

TimelineQuickView connects session changes to `setHintMuted(isOpen)` for every existing borrowed primary/gutter/event-list/drawer input item, then calls `resyncMouseHint` on unmute. It also resyncs them on native `scopeRefresh`. All borrowed lists already exist; no registry or new destination map. QML consumers use the same session's actual `isOpen` and `owns(source)` on each sync; no cached/static ownership exemption. **Do not infer that inserting a non-hovering overlay sends Leave.**

The three gates are deliberately distinct:

| Scope | Enforcing owner |
| --- | --- |
| Custom QuickPopupSession | **HoverHint** skips when `quickPopupSession.isOpen && !quickPopupSession.owns(source)`; **TimelineInputItem** skips while view-muted |
| Native QWidget popup / Qt modal blocking | **MouseHints::allowsSource** uses activePopupWidget and delivered QWindow blocked bits |
| Application inactive | **MouseHints** rejects all publication |

A QuickPopupSession is not QApplication's activePopupWidget and does not natively block its own QQuickWindow. The core does **not** police this custom Quick scope. If a new background producer bypasses HoverHint/the physical-host mute gate and calls publish directly, it can overwrite the overlay's empty claim: that is a caller contract violation, not a service priority rule.

### Guarded Quick membership recovery

Native modality can send Leave and never restore stationary membership on close; an executed probe reproduced this. Still-hovered resync alone cannot recover. After Quick session close and native `scopeRefresh`, TimelineQuickView requests one coalesced, lifetime-bound queued callback. This is the **only** synthetic-input exception: one idle, non-spontaneous MouseMove through the existing QQuickWindow, never a press, release, click, wheel or key.

Task 17 owns the private `requestMouseHintRecovery(ui::MouseHints *)` helper and `bool m_mouseHintRecoveryQueued = false` in timelinequickview.h, its implementation in timelinequickview_window.cpp, and constructor connections in timelinequickview.cpp. Capture a guarded service borrow; use existing `m_view` (not the ownership-transfer `m_quickView` unique_ptr), existing `m_detachStarted`, and the existing item lists. No public interface, extra observer, timer or registry.

Inside the callback, clear the coalescing flag and **re-read** all state immediately before delivery: service/window live and coordinator not detaching; window visible/exposed; actual current cursor inside its bounds; `allowsSource(window->contentItem())`; `QGuiApplication::topLevelAt(globalPosition)` is this window or its native ancestor (`QWindow::ExcludeTransients`); no physical mouse buttons; no window mouseGrabberItem; and no active interaction across existing primary/gutter/event-list/drawer hosts. If a guard fails, do not inject or poll; subsequent normal pointer/scope delivery supplies the next safe opportunity.

Only then construct a stack-local `QMouseEvent(QEvent::MouseMove, currentLocalPosition, currentGlobalPosition, Qt::NoButton, Qt::NoButton, currentModifiers)` and `QCoreApplication::sendEvent(window, &event)`. Queue the **callback**, not a prevalidated event: a new grab, cursor move or teardown may intervene. Canonical popup visual detachment precedes the close signal; correctness does not depend on DeferredDelete FIFO. Qt recomputes the true leaf, producing HoverEnter or HoverMove through ordinary delivery. Keep host/group membership guards; do not introduce geometry-only publication or saved-source restoration.

Native recovery may occur while a Quick popup remains open. Do not require `!session.isOpen`: the real leaf may be an owned popup field/graph. Existing `owns` and host-mute gates continue to exclude its background. The window-targeted non-spontaneous move does not impersonate original native QWidget input.

### Declarative target groups

Add one reusable `HoverHint.qml` HoverHandler subclass in the existing Quick module; register it in both CMake QML lists. It owns exactly one logical target group, uses default nonblocking/passive input, and never grabs, focuses or handles keys. Contract:

- `required property Item source`, `property string text`, `property bool gestureOwning`, and `property bool releaseInside` for a group with a drag (derived from that existing drag owner's actual release coordinates, not frozen `hovered`).
- One sync path checks effective visibility/window and actual Quick session ownership, then publishes if hovered, otherwise source-check clears. Suppressed groups cannot publish empty either.
- Sync on hover/profile changes, session open/close and native `scopeRefresh`; close must work even when `hovered` remains true. Do not rely on `hoveredChanged` alone.
- During the existing group's grab, retain the originating profile; on its end use actual `releaseInside` to clear outside even if Qt froze hover membership. Hide/detach/scope loss overrides retention. No independent gesture mode or modifier listener.
- One publisher per group. Child HoverHandlers may provide target identity but never compete by publishing independently. No page-wide ancestor publisher over different-profile descendants.

Event-list repair: put the existing keyboard-policy TimelineInputItem **below** EventListPage at the same z. It already declines pointer/wheel input but currently intercepts hover above the page; the isolated probe verified that ignoring a hover event does not make an accepting leaf transparent to lower siblings. Preserve focus/key wiring, handler blocking settings, press/wheel results and reorder semantics; explicitly verify this delivery correction.

Each event cell has one publisher. While actually over the visible inline editor, select the text profile from its child hover state; editing-cell margins are empty, not row-action help. Outside editing, use row-selection alternatives. Row headers get row help; toolbar/header/corner targets get empty. Never attach a publisher to the whole page/table root. Existing keyboard-policy input may own otherwise empty regions.

Track-header rename gets one publisher on its actual editor group; its passive hover claim makes it the leaf above the C++ input. No second header-row geometry classifier. Rename show/hide under a stationary cursor requires real Qt membership/Enter coverage. A lower host's resync cannot bypass its lost hover membership.

TimelineScrollbar gets one empty publisher covering its entire existing footprint, not only the thumb; preserve thumb colors, wheel/click/key behavior and default handler blocking. All five instances inherit it. DrawerChrome's existing five physical input items claim empty for bar/detent/resize regions. Its inline value prompt uses one group publisher: text-selection over its actual text editor, empty on its shield/card. Do not put a handler on the full-window DrawerChromeLayer root. QuickPopupLayer shields/cards and menu surfaces similarly own no-hint regions without an ancestor publisher overwriting numeric/text/graph children.

PitchBendGraph is its own physical Quick source. Add passive initial hover using existing `hitTest`/`canvasRect`; retain its existing gesture description and settle release/cancel from actual position. Respect native scope refresh and source hide/window detach. Background Shift-or-Alt line drawing, interior Alt time movement, and **empty pinned endpoints/margins** remain distinct.

## Required implementation proof

Use actual composed MainWindow/Quick input and the plan's [realism rule](plan.md#realistic-scope-and-checks), not forwarding/wording/count assertions or invented event schedules. Cover normal hover between targets and same-profile controls, plot/gutter movement, row/editor and rename precedence, popup suppression and stationary dismissal, the existing PencilToggle command with a stationary pointer, drag/release outside, real tab/popup closure, keyboard focus changes, application switching and existing owned-dialog routing. Exercise native modal recovery through WAV export's existing progress dialog in the native walkthrough. Preserve edits, selection/undo and global Space priority. Cheap ownership/lifetime/dispatch-time guards remain required; manufacturing a callback race or unsupported window arrangement is not a permanent-test requirement.

Verify native families and inherited wheel behavior, status caption/elision/accessibility, temporary messages, meter visible/hidden, ordinary/minimum usable widths and enlarged fonts. Capture the actual native app for visual evidence; isolated offscreen probes prove Qt primitives, not finished Porydaw integration. The task plan names bounded write sets, shared checks and native scenarios.
