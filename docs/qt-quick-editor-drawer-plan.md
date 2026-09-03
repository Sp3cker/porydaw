# Qt Quick editor drawer plan

## Status

Design complete; not implemented.

Open product or architecture decisions: none. Implementers fill function bodies and local test
helpers. They do not invent types, signals, parents, Q_PROPERTY names, object names, scrollbar
side, always-on policy, host-envelope math, or check destinations.

This plan converts the remaining native `EditorDrawer` overlay into the existing timeline
`QQuickView`. It does not add another Quick window or `QQuickWidget`.

`qt-cpp-reviewer` audited an earlier draft (FAIL, nine findings). This text is the locked
correction of those findings.

This plan assumes `docs/remove-fonts-plan.md`: bundled Atkinson for the process lifetime,
no `FontChange` / `ApplicationFontChange` handlers, no runtime font setter on timeline
hosts. Chrome metrics use `layout::fontPx` and `typography::bodyFont()`; they are not
recomputed because a font changed. Palette, theme, style, resize, screen, and DPR still
refresh.


## Goal

Make Qt Quick own every visible pixel and pointer target that today lives in the `EditorDrawer`
`QWidget` overlay: page toggles, resize handles, bottom bar, PSG detent, and the automation
vertical scrollbar. Keep section layout math, `EditorViewState`, automation document mutation,
and native popup menus in C++.

The migration succeeds only when:

- the existing timeline Quick scene draws and hit-tests all drawer chrome;
- `EditorDrawer`, `DrawerSections`, and `AutomationPage` are no longer `QWidget`s;
- `QScrollArea#automationScroll` is deleted;
- `EditorDrawer::setMask` and `DrawerSections::occupiedRegion` are deleted;
- `TimelineQuickView::m_nativeChrome` no longer names any drawer widget;
- the automation plot still starts on the same SongView X as the piano grid;
- the automation scrollbar remains permanently visible on the left of the lanes;
- current drawer behavior is preserved.

Time-ruler gutter controls, the native playhead, track headers, and SongView camera scrollbars
are out of scope.

## Current implementation

Timeline bands already render and take input in one Quick scene. `VelocityArea`,
`VoiceChangeArea`, `AutomationCanvas`, and `PianoRoll` are `QObject` +
`TimelineBandInteraction`.

What remains native is a bottom-anchored overlay on `rollPane`:

```
rollPane
 └── EditorDrawer          QWidget, no paint, setMask(occupied)
      └── DrawerSections   QWidget, no paint, owns chrome widgets
           ├── 3× QFrame resize handles
           ├── 3× QToolButton page toggles
           ├── QToolButton velocityDetentToggle
           ├── QFrame automationDrawerBar
           └── AutomationPage QWidget
                └── QScrollArea#automationScroll   empty: setWidget() is never called
                     ├── viewport()                published as TimelineBand::Automation
                     └── vertical QScrollBar       AlwaysOn, layoutDirection RightToLeft
```

`EditorDrawer::bodyRect` maps drawer-local bodies to SongView with
`m_sections->mapTo(&m_owner, body->topLeft())` (`editordrawer.cpp:246-252`).
`SongView::resolveTimelineBandLayout` publishes automation from
`scrollViewport()->mapTo(this)`, not from `bodyRect(Automations)`.

`AutomationCanvas::refreshGeometry` then does `plotOrigin -= scrollGutter()` so the lane
plot lines up with the piano grid after the viewport has already been inset by the native
bar (`automationcanvas.cpp:23-26`). `rollcheckautomation` pins that alignment, plus
always-visible and left-of-viewport.

`TimelineInputItem::setInteraction` attaches one `TimelineBandInteraction` to one host
(`timelineinputitem.cpp:76-85`). `AutomationCanvas::attachInputHost` asserts a single
empty host (`automationcanvas.cpp:79-82`). One interaction object cannot serve five items.

`TimelineQuickView` geometry is the union of band rects only
(`timelinequickview.cpp:470-516`). Chrome outside that envelope is not in the Quick
window.

## What the automation scrollbar actually is

It is not a scrolled child widget. `AutomationCanvas` never lived inside the `QScrollArea`.
The area is a transparent hole whose only job is to host a native `QScrollBar`:

- vertical `AlwaysOn`, horizontal `AlwaysOff`, `NoFocus`, no frame;
- `Qt::RightToLeft` so the bar sits on the left;
- range `0 .. max(0, contentHeight - viewportHeight)` set in
  `AutomationPage::synchronizeAutomationViewport()`;
- value consumed as `verticalScroll()` by canvas mapping, pinned tempo, Quick culling,
  wheel-in-gutter, and middle-button pan.

That hollow `QScrollArea` is why `AutomationPage` is still a `QWidget`. It is the largest
remaining widget surface in the drawer.

## End-state types

Do not invent additional types. These are the only new names.

### Files

Add, and list both in `CMakeLists.txt` immediately after `drawersections.h`:

- `src/ui/editordrawer/drawerchrome.h`
- `src/ui/editordrawer/drawerchrome.cpp`

No other new `.h`/`.cpp`. `TimelineScrollbar` is a QML `component` inside
`TimelineCanvas.qml`.

### `DrawerChromeTarget`

```cpp
enum class DrawerChromeTarget : uint8_t {
    VoiceChangesHandle,
    VelocityHandle,
    AutomationHandle,
    Bar,
    Detent,
};
```

Five values, five input items, five `DrawerChromeInteraction` members. The scrollbar is
not a `DrawerChromeTarget`; it is QML handlers on `TimelineScrollbar`.

### `DrawerChromeSnapshot`

All rectangles are SongView-local `QRectF`. Hidden chrome uses `QRectF{}` and
`visible == false`. One arrange produces one snapshot. `DrawerChrome::setSnapshot`
assigns every field, then emits `chromeChanged()` once. It does not write scroll
state.

```cpp
struct DrawerChromeSnapshot {
    QRectF voiceChangesHandleRect;
    QRectF velocityHandleRect;
    QRectF automationHandleRect;
    QRectF barRect;
    QRectF voiceChangesToggleRect;
    QRectF automationToggleRect;
    QRectF velocityToggleRect;
    QRectF detentRect;
    QRectF automationScrollbarRect;
    bool voiceChangesHandleVisible = false;
    bool velocityHandleVisible = false;
    bool automationHandleVisible = false;
    bool detentVisible = false;
    bool detentEnabled = false;
    bool detentChecked = false;
    bool velocityChecked = false;
    bool automationChecked = false;
    bool voiceChangesChecked = false;
    QColor toggleBackground;
    QColor toggleCheckedBackground;
    QColor toggleOutline;
    QColor toggleIconTint;
    QColor toggleCheckedIconTint;
    QColor handleColor;
    QColor handleHoverColor;
    QColor barBackground;
    QColor barOutline;
    QColor scrollbarHandle;
    QColor scrollbarHandleHover;
    QColor detentTint;
    QColor detentCheckedTint;
    QColor detentDisabledTint;
    int barBorderWidth = 0;
    int iconRevision = 0;
};
```

Color sources (do not pick others):

| Field | Source (`drawersections.cpp:154-190`) |
| --- | --- |
| `toggleBackground` | `themes::Role::combo_background` |
| `toggleCheckedBackground` | `QPalette::Highlight` |
| `toggleOutline` | `themes::Role::combo_outline` |
| `toggleIconTint` | `QPalette::WindowText` |
| `toggleCheckedIconTint` | `QPalette::HighlightedText` |
| `handleColor` | `QPalette::Mid` |
| `handleHoverColor` | `QPalette::Highlight` |
| `barBackground` | `QPalette::Window` |
| `barOutline` | `QPalette::Mid` |
| `scrollbarHandle` | `themes::Role::scrollbar_handle` |
| `scrollbarHandleHover` | `themes::Role::scrollbar_handle_hover_background` |
| `detentTint` | `QPalette::WindowText` |
| `detentCheckedTint` | `QPalette::Highlight` |
| `detentDisabledTint` | `QPalette::Disabled, QPalette::WindowText` |
| `barBorderWidth` | `layout::singlePixel()` |

Toggle hover does not recolor. The current stylesheet sets hover fill to `combo_background`.
Do not invent a toggle hover fill. Handle hover *does* recolor to `Highlight`.
Palette colors come from the `QPalette` argument of `EditorDrawer::refreshAppearance`.

### `DrawerChromeInteraction`

Not a `QObject`. One-host `TimelineBandInteraction`. `DrawerChrome` holds

```cpp
std::array<DrawerChromeInteraction, 5> m_interactions;
```

constructed with `(DrawerChrome &, DrawerChromeTarget)` in that enum order.
`attachInputHost` asserts `!m_host` then stores the host. `detachInputHost` clears it
only when `&host == m_host`. Cursor and pointer-grab go to that host only.

```cpp
class DrawerChromeInteraction final : public songview::TimelineBandInteraction
{
  public:
    DrawerChromeInteraction(DrawerChrome &chrome, DrawerChromeTarget target);
    void attachInputHost(songview::TimelineInputHost &host) override;
    void detachInputHost(songview::TimelineInputHost &host) override;
    bool pointerPress(const songview::TimelinePointerInput &input) override;
    bool pointerMove(const songview::TimelinePointerInput &input) override;
    bool pointerRelease(const songview::TimelinePointerInput &input) override;
    void pointerLeave() override;
    void inputCancelled(songview::TimelineInputCancelReason reason) override;
    void hostEnvironmentChanged() override;

  private:
    DrawerChrome &m_chrome;
    const DrawerChromeTarget m_target;
    songview::TimelineInputHost *m_host = nullptr;
};
```

`hostEnvironmentChanged` is a no-op. Palette and icon tints are pushed from
`EditorDrawer::refreshAppearance`. Size comes from `setSnapshot`. Font does not change
at runtime.

### `DrawerChrome`

```cpp
class DrawerChrome final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(DrawerChrome)

    Q_PROPERTY(QRectF voiceChangesHandleRect READ voiceChangesHandleRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF velocityHandleRect READ velocityHandleRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF automationHandleRect READ automationHandleRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF barRect READ barRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF voiceChangesToggleRect READ voiceChangesToggleRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF automationToggleRect READ automationToggleRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF velocityToggleRect READ velocityToggleRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF detentRect READ detentRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF automationScrollbarRect READ automationScrollbarRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool voiceChangesHandleVisible READ voiceChangesHandleVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool velocityHandleVisible READ velocityHandleVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool automationHandleVisible READ automationHandleVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool detentVisible READ detentVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool detentEnabled READ detentEnabled NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool detentChecked READ detentChecked NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool velocityChecked READ velocityChecked NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool automationChecked READ automationChecked NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool voiceChangesChecked READ voiceChangesChecked NOTIFY chromeChanged FINAL)
    Q_PROPERTY(int scrollbarWidth READ scrollbarWidth NOTIFY chromeChanged FINAL)
    Q_PROPERTY(int scrollbarMinimumThumbHeight READ scrollbarMinimumThumbHeight NOTIFY chromeChanged FINAL)
    Q_PROPERTY(int barBorderWidth READ barBorderWidth NOTIFY chromeChanged FINAL)
    Q_PROPERTY(int iconRevision READ iconRevision NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor toggleBackground READ toggleBackground NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor toggleCheckedBackground READ toggleCheckedBackground NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor toggleOutline READ toggleOutline NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor handleColor READ handleColor NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor handleHoverColor READ handleHoverColor NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor barBackground READ barBackground NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor barOutline READ barOutline NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor scrollbarHandle READ scrollbarHandle NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor scrollbarHandleHover READ scrollbarHandleHover NOTIFY chromeChanged FINAL)
    Q_PROPERTY(int automationScrollY READ automationScrollY NOTIFY scrollChanged FINAL)
    Q_PROPERTY(int automationContentHeight READ automationContentHeight NOTIFY scrollChanged FINAL)
    Q_PROPERTY(int automationViewportHeight READ automationViewportHeight NOTIFY scrollChanged FINAL)
    Q_PROPERTY(int automationMaximumScrollY READ automationMaximumScrollY NOTIFY scrollChanged FINAL)
    Q_PROPERTY(int hoveredHandle READ hoveredHandle NOTIFY chromeChanged FINAL)

  public:
    DrawerChrome(AutomationPage &page, EditorDrawer *parent);
    DrawerChromeInteraction &interaction(DrawerChromeTarget target) noexcept;
    void setSnapshot(const DrawerChromeSnapshot &snapshot);
    QQuickImageProvider *releaseIconProvider();
    void cancelInteraction();
    Q_INVOKABLE void setAutomationScrollY(int value);
    Q_INVOKABLE void scrollAutomationByWheel(int pixelDeltaY, int angleDeltaY, bool inverted);
    Q_INVOKABLE void pageAutomationToward(int localY);
    Q_INVOKABLE void activateToggle(int page);
    Q_INVOKABLE void setDetentChecked(bool checked);

    // getters matching every Q_PROPERTY; hoveredHandle returns -1 when none,
    // otherwise int(DrawerChromeTarget).

  signals:
    void chromeChanged();
    void scrollChanged();

  private:
    friend class DrawerChromeInteraction;
    bool handlePress(DrawerChromeTarget target, const songview::TimelinePointerInput &input);
    bool handleMove(DrawerChromeTarget target, const songview::TimelinePointerInput &input);
    bool handleRelease(DrawerChromeTarget target, const songview::TimelinePointerInput &input);
    void handleLeave(DrawerChromeTarget target);
    void handleCancelled(DrawerChromeTarget target, songview::TimelineInputCancelReason reason);

    AutomationPage &m_page;
    EditorDrawer &m_drawer;
    DrawerChromeSnapshot m_snapshot;
    std::array<DrawerChromeInteraction, 5> m_interactions;
    std::optional<DrawerChromeTarget> m_resizeTarget;
    qreal m_resizeStartGlobalY = 0.0;
    int m_resizeStartBodyHeight = 0;
    std::optional<int> m_resizeOriginalBodyHeight;
    std::optional<DrawerChromeTarget> m_hoveredHandle;
    std::optional<EditorDrawerPage> m_pressedToggle;
    bool m_pressedDetent = false;
    DrawerChromeIconProvider *m_icons = nullptr;
};
```

Constructor: `: QObject(parent), m_page(page), m_drawer(*parent), m_interactions{...}`.
Connect `AutomationPage::scrollStateChanged` to `DrawerChrome::scrollChanged` in the
constructor (same-thread queued not required; both live on the GUI thread). Do not store
a second `scrollY`.

`scrollbarWidth()` returns `layout::space(layout::Space::Two)`.
`scrollbarMinimumThumbHeight()` returns `layout::space(layout::Space::Eight)`.

`automationScrollY()` / `automationContentHeight()` / `automationViewportHeight()` forward
to `AutomationPage`. `automationMaximumScrollY()` is
`max(0, contentHeight - viewportHeight)`.

`setAutomationScrollY` calls `m_page.setVerticalScroll(value)` only.
`scrollAutomationByWheel` builds

```cpp
songview::TimelineWheelInput{
    .position = {},
    .globalPosition = {},
    .pixelDelta = QPoint(0, pixelDeltaY),
    .angleDelta = QPoint(0, angleDeltaY),
    .modifiers = Qt::NoModifier,
    .phase = Qt::NoScrollPhase,
    .inverted = inverted,
};
```

and calls `m_page.scrollVertically(input)`. `pageAutomationToward(localY)` pages by one
viewport toward the click: if `localY` is above the thumb (`localY < thumbY`),
`setVerticalScroll(verticalScroll() - viewportHeight)`, else
`setVerticalScroll(verticalScroll() + viewportHeight)`. Thumb Y uses the formulas below.

`activateToggle(page)` calls `m_drawer.owner().toggleDrawerSection(EditorDrawerPage(page))`.
`setDetentChecked` calls `m_drawer.velocityArea()->setUseDetents(checked)`.

`cancelInteraction` clears resize/hover/press state, restores handle cursors via each
attached host's `clearCursor()`, and does **not** emit `statePublished`.

Resize math is the current `DrawerSections::eventFilter` body
(`drawersections.cpp:485-537`), with `grabMouse` replaced by the handle input host
remaining the grabber (return true from press/move). `pointerRelease` is the only path
that emits `DrawerSections::statePublished(true)`. `inputCancelled` for `FocusLost`,
`PointerUngrabbed`, `Hidden`, and `WindowDeactivated` calls `cancelInteraction`.

Bar press/release: hit-test the three toggle rects in SongView space. Convert
item-local `input.position` with `targetRect.topLeft() + input.position` where
`targetRect` is the bar snapshot rect. Left press records `m_pressedToggle` if inside a
toggle. Left release activates only when the release hits the same toggle. Detent is
the same with `m_pressedDetent`.

Hover: `pointerMove`/`pointerLeave` on handle targets update `m_hoveredHandle` and emit
`chromeChanged` only when that identity changes. Toggles have no hover fill.


### `DrawerChromeIconProvider`

In `drawerchrome.cpp`, not a public header.

```cpp
class DrawerChromeIconProvider final : public QQuickImageProvider
{
  public:
    DrawerChromeIconProvider();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
    void setIcons(QImage velocity, QImage velocityOn, QImage automation, QImage automationOn,
                  QImage voiceChanges, QImage voiceChangesOn, QImage detent);
};
```

`QQuickImageProvider(QQuickImageProvider::Image)`. Ids (strip any `"/rev"` suffix):
`velocity`, `velocityOn`, `automation`, `automationOn`, `voiceChanges`,
`voiceChangesOn`, `detent`.

`EditorDrawer::refreshAppearance` tints with the SourceIn fill from
`DrawerSections::refreshDetentIcon`:

| Id | SVG | Tint |
| --- | --- | --- |
| `velocity` | `:/icons/velocity.svg` | `toggleIconTint` |
| `velocityOn` | `:/icons/velocity.svg` | `toggleCheckedIconTint` |
| `automation` | `:/icons/automation.svg` | `toggleIconTint` |
| `automationOn` | `:/icons/automation.svg` | `toggleCheckedIconTint` |
| `voiceChanges` | `:/icons/flat-music.svg` | `toggleIconTint` |
| `voiceChangesOn` | `:/icons/flat-music.svg` | `toggleCheckedIconTint` |
| `detent` | `:/icons/velocity_labels.svg` | enabled+checked `detentCheckedTint`; enabled `detentTint`; else `detentDisabledTint` |

Then `setIcons` and increment `iconRevision`. QML:
`"image://drawerchrome/" + name + "/" + drawerChrome.iconRevision`.

`DrawerChrome` constructs the provider in its constructor and stores `m_icons`.
`releaseIconProvider()` returns that pointer exactly once.
`TimelineQuickView` calls
`engine()->addImageProvider(QStringLiteral("drawerchrome"), drawerChrome.releaseIconProvider())`
before `setSource` (engine owns). `DrawerChrome` keeps `m_icons` as non-owning and
never deletes it. Subsequent `refreshAppearance` calls `m_icons->setIcons(...)`.


### `AutomationPage` after cutover

```cpp
class AutomationPage final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AutomationPage)
  public:
    AutomationPage(SongView &owner, QObject *parent);
    AutomationCanvas *canvas() noexcept;
    QSize automationViewportSize() const noexcept;
    int automationContentHeight() const noexcept;
    int verticalScroll() const noexcept;
    void setVerticalScroll(int value);
    bool scrollVertically(const songview::TimelineWheelInput &input);
    void synchronizeAutomationViewport(QSize viewportSize);
    // existing song/live/document/pencil API unchanged
  signals:
    void scrollStateChanged();
  private:
    int m_scrollY = 0;
    int m_contentHeight = 0;
    QSize m_viewportSize;
};
```

Sole owner of scroll state. `setVerticalScroll` clamps to
`[0, max(0, contentHeight - viewportHeight)]`, then if `m_scrollY` changed: updates the
field, `m_canvas->scrollStateChanged()`, `emit scrollStateChanged()`.
`synchronizeAutomationViewport` sets `m_viewportSize`,
`m_contentHeight = max(viewportSize.height(), m_canvas->minimumContentHeight())`,
re-clamps `m_scrollY`, emits `scrollStateChanged` only when value or range changed, then
`m_canvas->scrollStateChanged()` / `viewportResized()` as today.

Delete `scrollViewport()`, `scrollGutter()`, `ScrollArea`, `event()`, viewport resize
filter. Keep the app event filter only for the pencil shortcut. `belongsToPageWindow`
uses `m_owner.window()` (the `QWidget*` SongView) instead of `QWidget::window()`.

`setVerticalScroll` and `scrollVertically` become public (they are private today).

### `EditorDrawer` after cutover

```cpp
class EditorDrawer final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(EditorDrawer)
  public:
    EditorDrawer(SongView &owner, EditorViewState viewState = {});
    SongView &owner() noexcept { return m_owner; }
    DrawerChrome &chrome() noexcept;
    void setHostBounds(const QRect &songViewLocalRollPane);
    void useParentBounds();
    void refreshAppearance(const QPalette &palette);
    int overlayHeight() const noexcept;
    QRect overlayRect() const noexcept; // SongView-local
    // remaining current public API: setViewState, bodyRect, pageVisible, ...
};
```

No `QWidget`. No `setMask`. No parent event filter.

`setHostBounds` stores `m_hostBounds` (SongView-local roll-pane rect) and
`m_usesParentBounds = false`, then `arrange()`. `useParentBounds` sets the flag true
and `arrange()`. When the flag is true, `arrange` reads (EditorDrawer is already a
friend of SongView):

```cpp
QWidget *host = m_owner.m_rollStack->parentWidget();
m_hostBounds = QRect(host->mapTo(&m_owner, QPoint()), host->size());
```


`overlayHeight()` is the current `preferredHeight()` result, not `QWidget::height()`.
`overlayRect()` is

```cpp
QRect(m_hostBounds.x(),
      std::max(m_hostBounds.y(),
               m_hostBounds.bottom() - overlayHeight() + layout::singlePixel()),
      m_hostBounds.width(), overlayHeight());
```

`bodyRect(page)` is `QRect(overlayRect().topLeft() + localBody.topLeft(), localBody.size())`
when `DrawerSections` still returns overlay-local bodies. No `QWidget::mapTo`.

`refreshAppearance` copies palette roles into the snapshot colors, retints icons,
increments `iconRevision`, and `setSnapshot`. It does **not** take a font, store a
font, set `m_chromeDirty`, or call `arrange()`. Header height is
`layout::chromeRowHeight(*typography::bodyFont(), layout::space(layout::Space::Zero))`
inside `ensureChrome`, once per dirty chrome, using the process-lifetime bundled body.
Other chrome metrics stay `layout::fontPx(...)`.


### `DrawerSections` after cutover

`class DrawerSections final : public QObject` with `Q_OBJECT` kept (it already has
signals `geometryChanged` and `statePublished`). Delete every `QFrame` / `QToolButton`.
`arrangeLocal()` only writes `m_*BodyRect` and builds a `DrawerChromeSnapshot` in
overlay-local coordinates; `EditorDrawer::arrangeChildren` translates those rects by
`overlayRect().topLeft()` into SongView-local and calls `chrome().setSnapshot`.

Delete `occupiedRegion`, handle `eventFilter`, stylesheets, `changeEvent`.

### `TimelineQuickView` constructor

```cpp
TimelineQuickView(TimeRuler &ruler, PianoRoll &roll, OtherStrip &otherEvents,
                  AutomationPage &automation, VelocityArea &velocity,
                  VoiceChangeArea &voiceChanges, DrawerChrome &drawerChrome,
                  SongView &songView);
```

Members: `QPointer<DrawerChrome> m_drawerChrome;`,
`std::array<TimelineInputItem *, 5> m_drawerChromeInputs{};`,
`QRect m_publishedHostRect;`. Add
`Q_PROPERTY(qreal hostX READ hostX NOTIFY hostGeometryChanged FINAL)` and
`hostY` the same way. `hostX()`/`hostY()` return `m_publishedHostRect.x()`/`.y()`.
Signal `hostGeometryChanged()`.


Before `setSource`:

```cpp
m_quickView->rootContext()->setContextProperty(QStringLiteral("timelineQuickView"), this);
m_quickView->rootContext()->setContextProperty(QStringLiteral("timelineScene"), m_scene);
m_quickView->rootContext()->setContextProperty(QStringLiteral("drawerChrome"), &drawerChrome);
m_quickView->engine()->addImageProvider(QStringLiteral("drawerchrome"),
                                        drawerChrome.releaseIconProvider());
```

Do not construct a second provider.


After `setSource`, find and attach, `qFatal` if missing:

| objectName | interaction |
| --- | --- |
| `drawerVoiceChangesHandleInput` | `VoiceChangesHandle` |
| `drawerVelocityHandleInput` | `VelocityHandle` |
| `drawerAutomationHandleInput` | `AutomationHandle` |
| `drawerBarInput` | `Bar` |
| `drawerDetentInput` | `Detent` |

Destructor: `setInteraction(nullptr)` on all five, then the existing band loop.

WindowDeactivate filter that today walks `m_inputItems` also walks `m_drawerChromeInputs`
and calls `inputCancelled(WindowDeactivated)` on each attached interaction.

Connect `drawerChrome.chromeChanged` to `publishTimelineBandLayout` (the existing
zero-timer path is fine: start `m_layoutTimer`). Connect `scrollChanged` only to
`requestAutomationUpdate(AutomationRefresh::All)` — scroll does not relayout the host
envelope.

## Geometry

Keep VoiceChanges-first / Automation-preserved / Velocity-remainder allocation and the
current chrome metrics (`drawersections.cpp:206-210`).

`TimelineBand::Automation` is the lane **viewport**: SongView-local automation body minus
the left scrollbar column.

```text
scrollbarWidth = layout::space(Space::Two)
body           = EditorDrawer::bodyRect(Automations)          // SongView-local
band.rect      = {body.x() + scrollbarWidth, body.y(),
                  body.width() - scrollbarWidth, body.height()}
band.timelineOrigin = max(0, AutomationGeometry::resolve().plotOrigin - scrollbarWidth)
```

`AutomationCanvas::refreshGeometry` uses that same subtraction
(`layout::space(Space::Two)`), never `QStyle::PM_ScrollBarExtent` or `scrollGutter()`.
SongView plot X stays `body.x() + AutomationGeometry.plotOrigin`, which is what
`rollcheckautomation` already pins.

Velocity and voice-change bands stay `bodyRect(page)` as today.

`synchronizeAutomationViewport(band.rect.size())` from `EditorDrawer::arrange` when the
automation page is visible, and from canvas `rebuildRows` as today.

### Host envelope (Quick window geometry)

`TimelineQuickView::publishTimelineBandLayout` computes one SongView-local envelope:

```text
publishedHostRect = union(every visible TimelineBand.rect,
                          every visible DrawerChrome rect:
                            handles, bar, detent, automationScrollbarRect)
```

`setGeometry(publishedHostRect)`. Every QML local rect is `songViewRect.translated(
-publishedHostRect.topLeft())`. The QQuickView mask is that same union in host-local
coordinates, minus remaining native chrome (`timeRulerControls`, and track-header
widgets until that plan lands). Delete the five drawer names from `nativeChromeNames`.

Chrome outside the old band union (bar below bodies, scrollbar left of the automation
band) is why the envelope must include chrome rects. Do not call `mapTo` on a drawer
widget.

## Scroll

`AutomationPage` is the only scroll store. Range
`0 .. max(0, contentHeight - viewportHeight)`. Rebuild/resize re-clamp; they do not
reset a still-valid position.

The bar is **always shown**, including when `maximumScrollY == 0`. Do not copy the
track-headers hide-when-empty rule. Side is left. No `QtQuick.Controls`.

Thumb:

```text
thumbHeight = max(minimumThumbHeight,
                  viewportHeight / max(contentHeight, viewportHeight) * viewportHeight)
thumbTravel = viewportHeight - thumbHeight
thumbY      = maximumScrollY == 0 ? 0 : scrollY / maximumScrollY * thumbTravel
```

Gutter wheel (`x < plotOrigin` on `AutomationCanvas`) still calls
`AutomationPage::scrollVertically`. Scrollbar `WheelHandler` calls
`drawerChrome.scrollAutomationByWheel`. Same stepper.

## QObject parents and teardown

```text
EditorDrawer(SongView &owner, ...)           : QObject(&owner)
DrawerSections(..., EditorDrawer *parent)    : QObject(parent)
AutomationPage(SongView &, EditorDrawer *p)  : QObject(p)
DrawerChrome(AutomationPage &, EditorDrawer *p) : QObject(p)
```

SongView construction order, matching the existing velocity reparent comment
(`songview.cpp:304-311`):

```cpp
m_editorDrawer = new EditorDrawer(*this, m_editorViewState);
m_quickView = new TimelineQuickView(
    *m_ruler, *m_roll, *m_strip, *m_editorDrawer->automationPage(),
    *m_editorDrawer->velocityArea(), *m_editorDrawer->voiceChangeArea(),
    m_editorDrawer->chrome(), *this);
m_editorDrawer->automationPage()->setParent(this);
m_editorDrawer->velocityArea()->setParent(this);
m_editorDrawer->voiceChangeArea()->setParent(this);
m_editorDrawer->chrome().setParent(this);
m_strip->setParent(this);
m_roll->setParent(this);
m_quickView->lower();
```

Reparenting those interactions onto `SongView` *after* `TimelineQuickView` makes them
later QObject children, so they are destroyed *before* the Quick host. The host
destructor still `setInteraction(nullptr)` first.

Wave 1 (EditorDrawer still a `QWidget` on `rollPane`) uses the same Quick ctor addition
and the same reparent of `DrawerChrome` / `AutomationPage` once `AutomationPage` is a
`QObject`. Until Wave 2, `new EditorDrawer(*this, rollPane, state)` remains.

## Non-widget lifecycle

After `SongView::refreshGeometry` activates layouts, it calls
`m_editorDrawer->arrange()`. `arrange()` re-reads `m_rollStack->parentWidget()` only
when `m_usesParentBounds` is true. Tests that called `setHostBounds` keep that rect.
Do not reinstall a rollPane event filter on `EditorDrawer`.

On SongView PaletteChange / ApplicationPaletteChange / StyleChange / ThemeChange / DPR
(the same `appearanceChanged` path as `syncTimelineQuickAppearance`, minus any font
event), call `m_editorDrawer->refreshAppearance(palette())`. Do not call it from
`refreshGeometry`. Do not handle `FontChange` or `ApplicationFontChange`.


On SongView Hide / WindowDeactivate (existing cancel paths in `SongView` plus the Quick
WindowDeactivate filter), call `m_editorDrawer->cancelVisiblePageInteraction()` and
`m_editorDrawer->chrome().cancelInteraction()`. Delete `AutomationPage::event`.

`SongView::camera` code that reads `m_editorDrawer->height()` reads
`m_editorDrawer->overlayHeight()` instead (`camera.cpp:155`).

## QWidget API replacements

- Drawer `QAction`s: parent `EditorDrawer` (QObject). Do not call `addAction` on
  `EditorDrawer`. If they must remain window shortcuts, `m_owner.addAction(...)`.
- `m_pencilModeAction`: parent `AutomationPage`; `m_owner.addAction(m_pencilModeAction)`
  so `WindowShortcut` still fires. App event filter stays, predicate is
  `m_owner.window()` and the automation page is visible.
- Every `QMenu menu(&m_page)` / `ui::ContextMenu` currently parented at `&m_page`
  becomes `&m_owner` (`automationcanvas_menu.cpp`).
- `lane->promptValue(&m_page, ...)` becomes `lane->promptValue(&m_owner, ...)` at both
  call sites (`automationcanvas.cpp:653`, `automationcanvas_input.cpp:456`).
  `NodeLane::promptValue(QWidget *)` is unchanged.

## QML

`TimelineCanvas.qml` gains a `DrawerChromeLayer` sibling of the `TimelineSceneBand`s,
`z: 20` (bands use z 0–2). Playhead is native and stays above the Quick framebuffer.

`TimelineQuickView` exposes the envelope origin:

```cpp
Q_PROPERTY(qreal hostX READ hostX NOTIFY hostGeometryChanged FINAL)
Q_PROPERTY(qreal hostY READ hostY NOTIFY hostGeometryChanged FINAL)
```

`hostX`/`hostY` are `publishedHostRect.x()` / `.y()`. Emit `hostGeometryChanged` from
`publishTimelineBandLayout` when the envelope origin or size changes. Every chrome
item is positioned:

```qml
x: drawerChrome.barRect.x - timelineQuickView.hostX
y: drawerChrome.barRect.y - timelineQuickView.hostY
width: drawerChrome.barRect.width
height: drawerChrome.barRect.height
```

`DrawerChromeLayer` children, in order:

1. Three handle `Rectangle`s + `TimelineInputItem`s
   (`drawerVoiceChangesHandleInput`, `drawerVelocityHandleInput`,
   `drawerAutomationHandleInput`), visible with the matching `*Visible`. Fill
   `handleHoverColor` when `hoveredHandle == int(target)`, else `handleColor`.
2. Bar `Rectangle`: fill `barBackground`, border `barOutline` with
   `border.width: drawerChrome.barBorderWidth`. `TimelineInputItem` `drawerBarInput`
   fills the bar.
3. Three toggle `Rectangle`s + `Image`s. Fill `toggleCheckedBackground` when that
   page's `*Checked` is true, else `toggleBackground`. Border as the bar.
   Image source is `image://drawerchrome/<id>/<iconRevision>` with `<id>`
   `voiceChangesOn`/`automationOn`/`velocityOn` when checked, else the off id.
4. Detent `Image` + `TimelineInputItem` `drawerDetentInput`, visible with
   `detentVisible`. Source `image://drawerchrome/detent/${iconRevision}`.
5. `TimelineScrollbar` filling `automationScrollbarRect`, `alwaysVisible: true`.

Windows-only `DrawerToggle` extra stroke is dropped; every platform uses the outline.

### `TimelineScrollbar` component (in `TimelineCanvas.qml`)

```qml
component TimelineScrollbar: Item {
    id: root
    required property int scrollY
    required property int contentHeight
    required property int viewportHeight
    required property int maximumScrollY
    required property int minimumThumbHeight
    required property color handleColor
    required property color handleHoverColor
    property bool alwaysVisible: false

    visible: alwaysVisible || maximumScrollY > 0

    readonly property int thumbHeight: {
        const vh = Math.max(1, viewportHeight)
        const ch = Math.max(vh, contentHeight)
        return Math.max(minimumThumbHeight, Math.round(vh / ch * vh))
    }
    readonly property int thumbTravel: Math.max(0, height - thumbHeight)
    readonly property int thumbY: maximumScrollY === 0 ? 0
        : Math.round(scrollY / maximumScrollY * thumbTravel)

    property int dragStartThumbY: 0

    TapHandler {
        onTapped: (eventPoint) => {
            const y = eventPoint.position.y
            if (y >= root.thumbY && y < root.thumbY + root.thumbHeight)
                return
            drawerChrome.pageAutomationToward(y)
        }
    }
    WheelHandler {
        onWheel: (event) => drawerChrome.scrollAutomationByWheel(
                     event.pixelDelta.y, event.angleDelta.y, event.inverted)
    }
    Rectangle {
        y: root.thumbY
        width: parent.width
        height: root.thumbHeight
        color: thumbHover.hovered ? root.handleHoverColor : root.handleColor
        HoverHandler { id: thumbHover }
        DragHandler {
            yAxis.enabled: true
            xAxis.enabled: false
            onActiveChanged: if (active)
                root.dragStartThumbY = root.thumbY
            onTranslationChanged: {
                const travel = Math.max(1, root.thumbTravel)
                const y = Math.min(travel, Math.max(0, root.dragStartThumbY + translation.y))
                drawerChrome.setAutomationScrollY(
                    root.maximumScrollY === 0 ? 0
                        : Math.round(y / travel * root.maximumScrollY))
            }
        }
    }
}
```

If `docs/qt-quick-track-headers-plan.md` has already landed a component with this
contract, reuse it and add `alwaysVisible`. Do not create a second QML scrollbar.

`timelineAutomationInput` stays `anchors.fill` of the automation **band** (the
viewport, already excluding the scrollbar). It does not overlap the bar.

## Checks

No compatibility `QWidget` shell.

| Harness | After |
| --- | --- |
| `editor-drawer` | Resize via handle `TimelineInputItem`s / `DrawerChrome` rects. Mask **contains** chrome rects (inverted from today). Header punch-through: Quick mask does not contain that header point. `overlayRect().bottom()` stays pinned when a handle grows the drawer. |
| `host-adapter` / `host-seams` | Drop `automationScroll` stylesheet asserts and drawer names in `visibleNativeChromeExcluded`. Capture automation from `TimelineBand::Automation` rect. |
| `velocity-page` | Toggle/detent from `DrawerChrome` / `EditorViewState`. No `parentWidget() == drawerSections`. |
| `automation` | `automationScrollbarRect.right() <= band.rect.x()` and the scrollbar item `visible == true` at `maximumScrollY == 0`. Plot X equals piano grid X. Scroll from `AutomationPage::verticalScroll()`. |
| `automation-gestures` | Viewport size from band geometry. Delete `scrollViewport()->resize`. |
| `automation-popup-menus` | Menu parent is `SongView`. |
| `mainwindow-routing` / `host-integration` | `setVerticalScroll` / `verticalScroll()`, not `QScrollBar`. |
| `rendering-playhead` | Canonical automation rect is the band. Handle visibility from `DrawerChrome`. |

`captureQuickBand` gains `QImage captureQuickBand(SongView &view, const QRect &songViewLocal)`.
Delete the `QWidget &` overload once no caller remains. Do not keep a dummy viewport
widget.

`EditorDrawer::setHostBounds` / `useParentBounds` remain for `editor-drawer`.

## Cutover waves

Each wave is a complete production owner for the pixels it touches. No dual scrollbar,
no `QWidget` handle that QML also draws.

### Wave 1 — Automation scroll off `QScrollArea`

Subagent: `task`.

1. Add `drawerchrome.h/.cpp` and the CMake rows. Construct `DrawerChrome` in
   `EditorDrawer` (still a `QWidget` this wave). Pass it to `TimelineQuickView` and
   `setContextProperty` before `setSource`. Register `image://drawerchrome`.
2. Move scroll state into `AutomationPage` fields + `scrollStateChanged`. Keep the
   native bar only if it is deleted in the same wave; do not land a write-through
   `QScrollBar` view.
3. Publish `TimelineBand::Automation` as body minus `Space::Two`. Canvas plotOrigin
   subtracts `Space::Two`. `synchronizeAutomationViewport(band.size())`.
4. Add `TimelineScrollbar` + `automationScrollbarRect` in `DrawerChromeLayer` (other
   chrome rects empty/hidden). Host envelope unions bands + scrollbar rect.
5. Delete `QScrollArea`, `scrollViewport`, `scrollGutter`, RTL trick. `AutomationPage`
   is a `QObject`. Drop `m_automation` from `occupiedRegion()`. Reparent
   `AutomationPage` and `DrawerChrome` onto `SongView` after Quick construction.
6. QMenu / `promptValue` parents become `&m_owner` in this wave (page is no longer a
   `QWidget`).
7. Retarget automation / host-integration / playhead / gesture checks that fish
   `automationScroll`. Invert the Quick-mask assert for the scrollbar: mask contains
   the scrollbar rect.

Verify: `deno task verify --filter automation` plus `host-adapter`, `host-integration`,
`automation-gestures`, `rendering-playhead`, `automation-popup-menus`. Left always-on
bar, piano-grid alignment, wheel/pan/thumb move `verticalScroll()`.

### Wave 2 — Remaining chrome off `QWidget`

Subagent: `task`. Depends on Wave 1.

1. Fill `DrawerChromeSnapshot` from `arrangeLocal()`. Draw handles, bar, toggles,
   detent. Attach the five named input items to the five `DrawerChromeInteraction`s.
2. Delete native chrome widgets, `occupiedRegion`, `setMask`. `EditorDrawer` and
   `DrawerSections` become `QObject`s with the ctor/parentage above.
   `overlayHeight()` replaces `QWidget::height()`.
3. `m_nativeChrome` is only `timeRulerControls` (plus headers until that plan).
4. Wire `arrange()` from `SongView::refreshGeometry`. Wire `refreshAppearance(palette)`
   from SongView palette/theme/style/DPR events. Do not wire font events.
5. Retarget `editor-drawer`, `velocity-page`, `host-adapter` chrome/mask asserts.

Verify: `deno task verify --filter editor-drawer` plus `velocity-page`, `host-adapter`,
`host-seams`, `mainwindow-routing`. Resize, V/A/P, detent, header punch-through.

### Wave 3 — Review

Subagent: `reviewer` (`qt-cpp-reviewer`).

Confirm no leftover drawer `QWidget`, no drawer `setMask`, no `findChild` of deleted
object names, no second Quick host, playhead still native, menus parented to
`SongView`, one scroll store, five one-host interactions, Quick envelope includes
chrome. Run the wave 1–2 filters.

Do not start Wave 2 in parallel with Wave 1: both mutate `TimelineCanvas.qml`,
`timelinequickview.cpp`, `occupiedRegion`, and the same checks.

## Non-goals

- Track headers (`docs/qt-quick-track-headers-plan.md`).
- Time-ruler native controls.
- Moving the playhead into Quick.
- `QtQuick.Controls`, `QQuickPaintedItem`, per-toggle `MouseArea` trees.
- One `TimelineInputItem` covering the whole Quick host.
- Reproducing `QScrollArea` style metrics (`PM_ScrollBarExtent`, RTL `layoutDirection`).
- A generic C++ scroll/chrome framework.
- Event-list view, song list, voicegroup list.
