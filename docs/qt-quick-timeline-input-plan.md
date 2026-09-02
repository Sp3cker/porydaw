# Qt Quick timeline input migration plan

## Status

Implementation plan for removing the six full-area QWidget input surfaces that remain under the
Qt Quick timeline scene.

This plan supersedes only the input-retention parts of
`docs/qt-quick-timeline-column-plan.md`:

- the decision that QWidget permanently owns timeline input;
- the invariant that the Quick host never receives input;
- the parts of the band steps that retain full-area QWidget hit-test surfaces.

The earlier plan's rendering decisions remain in force. There is still one Quick timeline host,
dense geometry remains batched in C++, sparse text remains QML, and the native playhead remains
outside the Quick framebuffer.

Implementation is authorized only in the dedicated `feature/qt-quick-timeline-input` worktree.

### Phase 0 baseline record

- Base commit: `676e15984af1c766d7f4a7d1144da554a4ce2c31`
  (`Fix clean close and drawer resize cleanup`).
- Initial top-level status: clean except for this untracked plan, which Phase 0 commits before
  implementation.
- Shared `external/poryaaaa` status: detached, clean at
  `5637b20f409e52c44ebd276bfdd217312e3768c8`. The implementation worktree intentionally has no
  nested submodule checkout.
- Qt: 6.11.0.
- Active Quick renderer on the baseline workstation: threaded render loop, QRhi Metal backend,
  Apple M4 Pro device, one-sample swapchain, DPR 2.0.
- `deno task build:checks`: pass.
- Focused baseline checks: `rollcheck` 1/1, `rollwindowingcheck` 1/1, `editor-drawer` 1/1,
  `automation-gestures` 1/1, `automation-popup-menus` 1/1, `automation` 3/3,
  `velocity-page` 1/1, and `rendering-playhead` 1/1 all pass.
- Rendering baseline artifacts: the current playhead check compares live Quick framebuffer and
  native/fallback overlay images in memory. It does not persist a screenshot or framebuffer hash;
  its `screenshotPath` argument is unused.

The six baseline QWidget input surfaces are:

| Band | QWidget type | Event overrides |
| --- | --- | --- |
| Ruler | `TimeRuler` | `event`, wheel, press, move, release, double-click |
| Roll | `PianoRoll` | `event`, wheel, press, move, release, double-click, leave, key press/release |
| Other events | `OtherStrip` | `event`, resize, mouse move |
| Automation | `AutomationCanvas` | `event`, resize, wheel, press, move, release, double-click, leave, key press |
| Velocity | `VelocityArea` | `event`, application event filter, resize, press, move, release, leave, wheel, key press, focus out, context menu |
| Voice changes | `VoiceChangeArea` | `event`, resize, press, move, release, double-click, leave, wheel, key press, focus out, context menu |

### Phase 2 implementation record

- Build checks: `deno task build:checks` passed.
- Focused checks: `host-integration`, `rollwindowingcheck`, `rendering-playhead`, `editor-drawer`, `automation-popup-menus`, `velocity-page`, and `mainwindow-routing` pass.
- Unconverted band state: `Ruler`, `PianoRoll`, `OtherEvents`, `Automation`, and `Velocity` continue to render but are deliberately noninteractive in Phase 2. Production event ownership switched to the Quick host without temporary synthetic forwarding to unconverted QWidgets.
- Expected test failures: `rollcheck` fails four retained PianoRoll/pitch-bend input assertions, and `automation-gestures` fails its retained native AutomationCanvas hover/move assertions, because the native Quick timeline host now owns pointer delivery while those bands have no input item. Voice-change routing passes once retargeted.
- Class declaration deviation: `TimelineInputItem` cannot be declared `final` because Qt 6.11's `qmlRegisterType` internally instantiates `QQmlElement<T>`, which derives from `T`. This is a toolchain-required C++ inheritance constraint, not a compatibility shim.
- Focus seam plan correction: `focusBand()` returns `false` only when the target band's input item is absent in that phase; otherwise it issues the focus request and returns `true`. This avoids an asynchronous `QWindowContainer` / `QQuickWindow` fallback race without caching focus state, keeping `focusedBand()` as the sole live active-focus truth.

## Goal

Make the existing Qt Quick timeline scene own raw pointer, wheel, hover, focus, and keyboard input
for the same six bands that it already draws:

1. `TimeRuler`
2. `PianoRoll`
3. `OtherStrip`
4. `AutomationCanvas`
5. `VelocityArea`
6. `VoiceChangeArea`

Keep the editing rules, hit testing, gesture state, menus, and document mutations in C++. Remove
the six full-size QWidget input surfaces, their geometry observation, and the input-transparent
Quick-window setup.

Every converted band is outer-layout blind. It never chooses, requests, or changes its own outer
height or rectangle. `SongView` owns ruler, roll, and other-events layout;
`DrawerSections` owns automation, velocity, and voice-change layout. A band may still calculate
internal content geometry, such as marker positions or automation lane rows, within the rectangle
its parent supplies.

The migration succeeds only when the old surfaces are deleted. Keeping hidden or transparent
QWidgets after Quick starts receiving input does not meet the goal.

Intermediate feature-branch commits may leave unconverted bands noninteractive. That state is
deliberate: the first complete voice-change conversion enables input on the one shared Quick
window, and later commits restore the other five bands one at a time. The final result must
preserve all current behavior.

## Scope

### Remove

- QWidget inheritance from the six band modules listed above.
- QWidget event overrides used only by those full-area input surfaces.
- QWidget-derived band geometry as the source of Quick layout.
- `Qt::WindowTransparentForInput` on the timeline `QQuickView`.
- `Qt::WA_TransparentForMouseEvents` on the Quick host and container.
- the macOS automation-hover event synthesizer in
  `src/ui/songview/quick/automationhoverpassthrough_macos.mm`.
- `TimelineQuickView` event filters that observe the six obsolete band widgets.
- `PlayheadOverlay` geometry observation of those obsolete widgets.
- checks that send events directly to the deleted QWidget surfaces.

### Retain

- `TimelineQuickView` as the one QWidget-to-`QQuickView` host while the rest of `SongView` remains
  QWidget-based.
- `EditorDrawer`, `DrawerSections`, `AutomationPage`, the automation scrollbar, drawer toggles,
  drawer resize handles, the velocity detent toggle, and the time-ruler grid controls as native
  QWidget chrome.
- the event-list page, track headers, scrollbars, menus, dialogs, and pitch-bend popup.
- the native playhead renderers and QWidget playhead fallback.
- current document commands, undo labels, selection rules, audition behavior, camera behavior,
  and follow-scroll behavior.
- Qt value types such as `QPointF`, `QRectF`, `QFont`, `QPalette`, and `QString` inside the C++ band
  modules where they remain useful.

### Do not add

- input or editing logic in QML JavaScript;
- a second Quick window or one Quick window per band;
- a controller/store framework unrelated to timeline input;
- touch or multi-touch behavior that the current widgets do not support;
- a renderer switch or a permanent old-input fallback;
- new gestures, shortcuts, menus, or product behavior during this migration.

## Current architecture

`TimelineQuickView` creates one `QQuickView`, embeds it with `QWidget::createWindowContainer`, and
loads `TimelineCanvas.qml`. The view and container are input-transparent. The operating system and
Qt skip that native Quick window for input, so the underlying widgets receive events directly.
Quick does not forward the events.

`TimelineQuickView::synchronizeHostGeometryAndVisibility()` currently:

1. reads the mapped geometry and visibility of the six QWidget bands;
2. forms one host rectangle around them;
3. publishes six root-local band rectangles to QML;
4. subtracts native drawer chrome from the Quick native-window mask;
5. invalidates a band's Quick layers when the widget's visible size changes.

The six band modules now combine three concerns:

- semantic/render state used to build `TimelineQuickScene` data;
- interaction rules and transient gesture state;
- QWidget input, focus, cursor, geometry, font, palette, and device-pixel-ratio access.

Their current input responsibilities are:

| Band | Current QWidget input |
| --- | --- |
| `TimeRuler` | wheel zoom; scrub; loop marker, time-signature, and time-selection gestures; ruler menu |
| `PianoRoll` | note hit testing; draw, move, resize, velocity, band, and time-selection gestures; keyboard audition; shortcuts; note menus and pitch-bend popup |
| `OtherStrip` | hover hit testing and native tooltip display |
| `AutomationCanvas` | tempo/CC hit testing; pencil, point, sweep, band, pan, and row-resize gestures; shortcuts; menus; hover and cursor state |
| `VelocityArea` | note/stem hit testing; relative, paint, ramp, band, and pan gestures; wheel zoom; menus; focus cancellation; accessibility text |
| `VoiceChangeArea` | marker hit testing; drag, pan, hover, wheel zoom, picker, context menu, and focus cancellation |

The Qt Quick scene already draws all six bands. No painting must move as part of this plan.

## Target architecture

```text
QQuickView / TimelineCanvas.qml
        |
        | raw Quick events in the visible band rectangles
        v
TimelineInputItem (one instance per band)
        |
        | normalized pointer, wheel, key, focus, and lifecycle values
        v
TimelineBandInteraction
        |
        +--> TimeRuler
        +--> PianoRoll
        +--> OtherStrip
        +--> AutomationCanvas
        +--> VelocityArea
        +--> VoiceChangeArea
                    |
                    +--> SongView / AutomationPage / SongDocument commands

SongView + DrawerSections
        |
        | TimelineBandLayout value
        +--> TimelineQuickView geometry and native-window mask
        +--> QML band geometry
        +--> Timeline input hit regions
        +--> PlayheadOverlay clipping
```

Qt Quick owns raw event delivery and the visible band rectangles. The six C++ modules continue to
own the behavior attached to those events. `TimelineQuickView` wires the modules to their input
items but does not interpret band-specific gestures.

## The input seam

Add `src/ui/songview/quick/timelineinput.h`. The declaration is fixed by this plan; implementation
may split the declarations into adjacent files if that improves include cost without changing the
interface.

```cpp
namespace songview {

enum class TimelineBand : uint8_t {
    Ruler,
    Roll,
    OtherEvents,
    Automation,
    Velocity,
    VoiceChanges,
    Count,
};

constexpr std::size_t timelineBandIndex(TimelineBand band)
{
    return static_cast<std::size_t>(band);
}

struct TimelinePointerInput {
    QPointF position;       // band-local logical pixels
    QPointF globalPosition; // global logical pixels
    Qt::MouseButton button; // button that changed for press/release/double-click
    Qt::MouseButtons buttons;
    Qt::KeyboardModifiers modifiers;
};

struct TimelineWheelInput {
    QPointF position;       // band-local logical pixels
    QPointF globalPosition; // global logical pixels
    QPoint pixelDelta;
    QPoint angleDelta;
    Qt::KeyboardModifiers modifiers;
    Qt::ScrollPhase phase = Qt::NoScrollPhase;
    bool inverted = false;
};

struct TimelineKeyInput {
    int key = Qt::Key_unknown;
    Qt::KeyboardModifiers modifiers;
    QString text;
    bool autoRepeat = false;
};

enum class TimelineInputCancelReason : uint8_t {
    FocusLost,
    PointerUngrabbed,
    Hidden,
    WindowDeactivated,
};

class TimelineInputHost
{
  public:
    virtual ~TimelineInputHost() = default;

    virtual QRectF bounds() const = 0;
    virtual qreal devicePixelRatio() const = 0;
    virtual QFont font() const = 0;
    virtual QPalette palette() const = 0;
    virtual QPointF mapFromGlobal(QPointF position) const = 0;
    virtual QPointF mapToGlobal(QPointF position) const = 0;

    virtual void requestFocus(Qt::FocusReason reason) = 0;
    virtual void setCursor(const QCursor &cursor) = 0;
    virtual void clearCursor() = 0;
    virtual void releasePointerGrab() = 0;
    virtual void setAccessibilityDescription(const QString &description) = 0;
};

class TimelineBandInteraction
{
  public:
    virtual ~TimelineBandInteraction() = default;

    virtual void attachInputHost(TimelineInputHost &host) = 0;
    virtual void detachInputHost(TimelineInputHost &host) = 0;

    virtual bool pointerPress(const TimelinePointerInput &) { return false; }
    virtual bool pointerDoubleClick(const TimelinePointerInput &) { return false; }
    virtual bool pointerMove(const TimelinePointerInput &) { return false; }
    virtual bool pointerRelease(const TimelinePointerInput &) { return false; }
    virtual void pointerLeave() {}
    virtual bool wheel(const TimelineWheelInput &) { return false; }
    virtual bool keyPress(const TimelineKeyInput &) { return false; }
    virtual bool keyRelease(const TimelineKeyInput &) { return false; }
    virtual void inputCancelled(TimelineInputCancelReason) {}
    virtual void hostAppearanceChanged() {}
};

} // namespace songview
```

Override only the input methods a band handles. Do not add an override merely to return `false` or
do nothing.

`TimelineInputHost` has one production implementation: `TimelineInputItem`, the target
`QQuickItem`. Do not add a QWidget adapter. During row-by-row conversion, the unconverted
QWidgets remain in the tree but stop receiving input as soon as the first Quick input item goes
live. Temporary loss of input on those rows is accepted on the feature branch.

Keep the host seam direct. Its geometry, DPR, font, palette, coordinate mapping, focus, cursor,
pointer-grab, and accessibility methods each replace a concrete service that the six QWidget
surfaces provide today. Do not wrap `TimelineInputHost` in a second implementation object or add
an attachment token. One `inputCancelled(reason)` hook carries focus loss, ungrab, hide, and
window-deactivate causes without forcing two virtual methods. A band may ignore `FocusLost` only
when its current QWidget does so; all other reasons take the strong cancellation route.

Checks may use an in-memory host for C++ interaction tests. The in-memory host must
record focus, cursor, pointer-grab, bounds, font, palette, DPR, and coordinate conversions. It must
not duplicate hit testing or gesture rules.

## Quick input item

Add `src/ui/songview/quick/timelineinputitem.h/.cpp` with this fixed role:

```cpp
class TimelineInputItem final : public QQuickItem, public TimelineInputHost
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelineInputItem)
    Q_PROPERTY(QString accessibilityDescription READ accessibilityDescription
                   WRITE setAccessibilityDescription
                       NOTIFY accessibilityDescriptionChanged FINAL)

  public:
    explicit TimelineInputItem(QQuickItem *parent = nullptr);
    ~TimelineInputItem() override;

    void setInteraction(TimelineBandInteraction *interaction);
    TimelineBandInteraction *interaction() const noexcept;
    void notifyHostAppearanceChanged();
    QString accessibilityDescription() const;

    // TimelineInputHost
    QRectF bounds() const override;
    qreal devicePixelRatio() const override;
    QFont font() const override;
    QPalette palette() const override;
    QPointF mapFromGlobal(QPointF position) const override;
    QPointF mapToGlobal(QPointF position) const override;
    void requestFocus(Qt::FocusReason reason) override;
    void setCursor(const QCursor &cursor) override;
    void clearCursor() override;
    void releasePointerGrab() override;
    void setAccessibilityDescription(const QString &description) override;

  signals:
    void accessibilityDescriptionChanged();

  protected:
    void mousePressEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void hoverMoveEvent(QHoverEvent *event) override;
    void hoverLeaveEvent(QHoverEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void keyReleaseEvent(QKeyEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void mouseUngrabEvent() override;
    void itemChange(ItemChange change, const ItemChangeData &data) override;

  private:
    TimelineBandInteraction *m_interaction = nullptr;
    QString m_accessibilityDescription;
};
```

Construction rules:

- `setAcceptedMouseButtons(Qt::AllButtons)`;
- `setAcceptHoverEvents(true)`;
- `setFlag(QQuickItem::ItemIsFocusScope, true)` only if required by verified keyboard focus
  behavior; otherwise use active focus directly;
- a successfully handled press keeps the normal QQuick pointer grab through release;
- an unhandled event is ignored;
- `wheelEvent()` copies `QWheelEvent::inverted()` into `TimelineWheelInput::inverted`; consumers
  that reproduce native scrolling must not infer scroll direction from the deltas alone;
- `focusOutEvent()` calls `inputCancelled(TimelineInputCancelReason::FocusLost)`;
- `mouseUngrabEvent()` calls
  `inputCancelled(TimelineInputCancelReason::PointerUngrabbed)`;
- `itemChange(ItemVisibleHasChanged, false)` calls
  `inputCancelled(TimelineInputCancelReason::Hidden)` before forwarding the change to QQuickItem;
- `TimelineQuickView` observes `QEvent::WindowDeactivate` on the Quick window and calls
  `inputCancelled(TimelineInputCancelReason::WindowDeactivated)` on every attached item;
- host detachment happens before either object is destroyed;
- `TimelineInputItem::setInteraction()` is the sole attach/detach path: it returns when the pointer
  is unchanged, detaches the old interaction, assigns the new pointer, then attaches the new
  interaction; passing `nullptr` only performs the detach half;
- `TimelineInputItem::~TimelineInputItem()` calls `setInteraction(nullptr)` before its QQuickItem
  base is destroyed; `TimelineQuickView` also clears an item's interaction before destroying an
  interaction module that could otherwise die first;
- each interaction's `detachInputHost()` requires the address to match its stored host, cancels
  transient input, and clears the pointer; no interaction retains a QQuickItem pointer;
- `TimelineQuickView::syncAppearance()` calls `notifyHostAppearanceChanged()` on every attached
  input item after the host font, palette, layout scale, or DPR changes;
- each input item binds `Accessible.description` to its `accessibilityDescription` property; the
  interaction module publishes the description through `TimelineInputHost`, never through a
  hidden QWidget;
- the item contains no hit testing, snapping, gesture thresholds, selection rules, or document
  calls.

The input seam also fixes focus ownership before the first QWidget surface is removed:

```cpp
bool TimelineQuickView::focusBand(TimelineBand band, Qt::FocusReason reason);
std::optional<TimelineBand> TimelineQuickView::focusedBand() const;

bool SongView::focusTimelineBand(TimelineBand band, Qt::FocusReason reason);
std::optional<TimelineBand> SongView::focusedTimelineBand() const;
```

`focusBand()` returns `false` only when that phase has not added the band's input item yet;
otherwise it issues the focus request to that item and returns `true`. `focusedBand()` reads the six
input items' live active-focus state as the sole active-focus truth; it does not cache a second
focus flag. `EditorDrawer::focusVisiblePage()` maps `EditorDrawerPage` to `TimelineBand` and calls
the SongView method. `EditorDrawer::ownsFocus()` returns true when `focusedTimelineBand()` is
Automation, Velocity, or VoiceChanges. Remove `m_drawerCanvasOwnsFocus`, the three canvas event
filters, and `DrawerSections::focusActivePage()`'s QWidget lookup as their converted replacements
become available. Do not leave hidden QWidget focus proxies.

`TimelineCanvas.qml` adds one `TimelineInputItem` filling a `TimelineSceneBand` when that band is
converted. Each item has a stable object name:

- `timelineRulerInput`
- `timelineRollInput`
- `timelineOtherEventsInput`
- `timelineAutomationInput`
- `timelineVelocityInput`
- `timelineVoiceChangesInput`

`TimelineQuickView` finds each input item when its band phase adds it, validates it, and attaches the
matching C++ interaction module. After the final band conversion, startup validates all six. QML
does not contain hit testing or gesture rules.

## Geometry seam

Add `src/ui/songview/timelinebandlayout.h`:

```cpp
namespace songview {

struct TimelineBandGeometry {
    QRect rect;          // SongView-local logical pixels
    int timelineOrigin; // x offset within rect where timeline content begins

    friend bool operator==(const TimelineBandGeometry &, const TimelineBandGeometry &) = default;
};

struct TimelineBandLayout {
    std::array<std::optional<TimelineBandGeometry>, timelineBandIndex(TimelineBand::Count)> bands;

    const std::optional<TimelineBandGeometry> &geometry(TimelineBand band) const
    {
        return bands.at(timelineBandIndex(band));
    }

    std::optional<TimelineBandGeometry> &geometry(TimelineBand band)
    {
        return bands.at(timelineBandIndex(band));
    }

    friend bool operator==(const TimelineBandLayout &, const TimelineBandLayout &) = default;
};

} // namespace songview
```

`SongView` owns the canonical `TimelineBandLayout`. All rectangles use SongView coordinates. A
hidden band has a `std::nullopt` entry; no hidden band retains stale geometry. Producers and
consumers address entries only through `geometry(TimelineBand)`. Code that must handle every band
iterates from `Ruler` through `VoiceChanges`; it does not repeat six independent optional branches.

The same value feeds:

- `TimelineQuickView` host geometry and QML band properties;
- the Quick native-window mask;
- all six input items;
- `PlayheadOverlay` clipping and timeline origins;
- checks that compare rendering and input coordinates.

Do not keep a second array of QWidget-derived rectangles in `TimelineQuickView`.

### C++ to QML geometry handoff

Keep the existing root-property handoff. `TimelineQuickView` obtains the loaded
`TimelineCanvas.qml` root with `rootObject()`. For each visible entry in
`TimelineBandLayout`, it translates the SongView-local rectangle into Quick-host-local
coordinates, converts it to `QRectF`, and calls `QObject::setProperty()` with the existing
QML property name. A missing entry publishes an empty rectangle and `false` visibility.

Keep the unavoidable QML property names in one table rather than scattering string literals:

```cpp
struct TimelineBandQmlProperties {
    TimelineBand band;
    const char *rect;
    const char *visible;
};

inline constexpr std::array kTimelineBandQmlProperties{
    TimelineBandQmlProperties{TimelineBand::Ruler, "rulerBandRect", "rulerBandVisible"},
    TimelineBandQmlProperties{TimelineBand::Roll, "rollBandRect", "rollBandVisible"},
    TimelineBandQmlProperties{TimelineBand::OtherEvents, "otherEventsBandRect",
                              "otherEventsBandVisible"},
    TimelineBandQmlProperties{TimelineBand::Automation, "automationBandRect",
                              "automationBandVisible"},
    TimelineBandQmlProperties{TimelineBand::Velocity, "velocityBandRect",
                              "velocityBandVisible"},
    TimelineBandQmlProperties{TimelineBand::VoiceChanges, "voiceChangesBandRect",
                              "voiceChangesBandVisible"},
};
```

Before the first publication, iterate that table and fatally reject a missing QML root or any
missing named property. `publishTimelineBandLayout()` then iterates the same table exactly once.
For each row it reads `layout.geometry(properties.band)`, publishes the translated rectangle or an
empty `QRectF`, and publishes `geometry.has_value()` to the visibility property. A typed C++
`Q_PROPERTY` would not make QML member names compile-time checked, so do not add a wrapper object
that only moves these strings to another layer.

`TimelineCanvas.qml` keeps its six `property rect` and six visibility properties. Each
`TimelineSceneBand` continues to bind `x`, `y`, `width`, `height`, and `visible` to those
values. QML consumes the geometry; it does not calculate band placement or read native
widgets.

### Layout production

The retained widget layout remains responsible for native chrome, but it publishes values instead
of requiring full-area child widgets:

- `SongView` replaces the ruler and other-events widget layout slots with fixed-height
  `QSpacerItem`s. `SongView::Geometry::resolve()` calculates both heights with the current font and
  spacing formulas. During migration, the old widgets are positioned over those spacer
  rectangles; deleting a widget does not change layout.
- the retained roll page supplies the roll rectangle. `PianoRoll` no longer supplies its size.
- `DrawerSections` publishes body rectangles for automation, velocity, and voice changes while it
  continues to position the retained resize handles, toggles, bar, and detent control. During
  migration it also positions any old body widget into the already-calculated rectangle.
- `EditorDrawer` maps those drawer-local body rectangles into SongView coordinates.
- automation vertical scrolling remains part of automation scene/input projection; the visible
  automation band rectangle is the scroll viewport, not the full lane-stack height.

Step 2 therefore owns all six band sizes and positions before any QWidget is deleted. During the
transition, assert that each old full-area widget exactly fills its parent-owned rectangle. Later
band phases delete widgets without introducing or changing a height rule.

### Phase 1 declarations and call sequence

Use these declaration-only interfaces for the canonical-layout phase:

```cpp
// SongView
const songview::TimelineBandLayout &timelineBandLayout() const noexcept;

private:
songview::TimelineBandLayout resolveTimelineBandLayout() const;
void synchronizeTimelineBandLayout();
songview::TimelineBandLayout m_timelineBandLayout;

// DrawerSections
std::optional<QRect> bodyRect(EditorDrawerPage page) const noexcept;

// TimelineQuickView
void setBandLayout(songview::TimelineBandLayout layout);

private:
songview::TimelineBandLayout m_bandLayout;

// PlayheadOverlay
explicit PlayheadOverlay(QWidget &owner, const songview::TimelineBandLayout &layout);
void updateBands(const songview::TimelineBandLayout &layout);
```

In Phase 1, `SongView::resolveTimelineBandLayout()` derives all six entries from parent-owned layout
values:

- the ruler spacer rectangle with `m_geometry.plotOrigin`;
- the retained roll-page rectangle with `m_geometry.pianoKeyboardWidth`, only while the roll page
  is visible;
- the other-events spacer rectangle with `m_geometry.plotOrigin`;
- the automation scroll viewport rectangle with `automationPage()->canvas()->plotOrigin()`;
- `DrawerSections::bodyRect(EditorDrawerPage::Velocity)` with `velocityArea()->plotOrigin()`;
- `DrawerSections::bodyRect(EditorDrawerPage::VoiceChanges)` with
  `voiceChangeArea()->plotOrigin()`.

Map every rectangle into SongView coordinates. Do not translate it into Quick-host coordinates in
`SongView`; that translation belongs only to `TimelineQuickView` when it publishes QML properties.

`SongView::synchronizeTimelineBandLayout()` performs this fixed sequence:

1. call `resolveTimelineBandLayout()`;
2. return when the value equals `m_timelineBandLayout`;
3. replace `m_timelineBandLayout`;
4. call `m_quickView->setBandLayout(m_timelineBandLayout)`;
5. call `m_playheadOverlay->updateBands(m_timelineBandLayout)`.

Call it after the existing SongView layout has settled, after `EditorDrawer::arrangeChildren()`,
and from `SongView::refreshGeometry()`. Call it once after both consumers are constructed. Both
consumers begin with an empty layout, and the QML properties already default to empty rectangles
and `false` visibility, so an unchanged empty first value needs no special publication flag. Do
not add a Qt signal for this private, synchronous, SongView-owned handoff.

`TimelineQuickView::setBandLayout()` stores the value, returns when it has not changed, and invokes
the existing deferred host-geometry synchronization. That synchronization must use only
`m_bandLayout`; remove its private `PublishedLayout` type and all QWidget geometry reads. It still
performs the host union, QML root-property publication, native-chrome mask subtraction, and Quick
layer invalidation.

Phase 1 changes only the geometry source. It does not remove the six QWidget pointers that
`TimelineQuickView` still needs for scene data, and it does not change input transparency or event
delivery.

### Native-window mask

Once Quick receives input, build the `QQuickView` mask from the union of the six visible band
rectangles, translated into Quick-root coordinates. Subtract retained native chrome rectangles.
Do not begin with the full bounding rectangle: gaps must remain available to the underlying native
controls.

## Playhead geometry

Change `PlayheadBand` from a `QWidget &` plus timeline origin to a SongView-local `QRect` plus
timeline origin. Change `PlayheadOverlay::updateBands()` to accept the canonical
`TimelineBandLayout` or values derived directly from it.

Remove event filters that exist only to observe deleted band widgets. `SongView` calls
`updateBands()` when the canonical layout changes. Preserve:

- the macOS CALayer renderer;
- Windows DirectComposition;
- the QWidget fallback;
- existing clip order and triangle direction;
- position-only playhead updates that do not rebuild Quick geometry.

## Band-module target

The six existing domain names remain. Async, Quick, controller, or model suffixes are not added to
their public names merely because their base class changes.

At the end:

- none of the six classes derives from QWidget;
- none exposes `sizeHint()`, calls a fixed/minimum/maximum-height setter, calls
  `updateGeometry()`, or writes its outer rectangle;
- each implements `TimelineBandInteraction`;
- each owns its existing semantic, scene-build, hit-test, and gesture state;
- each receives host geometry/appearance through `TimelineInputHost` rather than QWidget
  inheritance;
- each continues to publish the same Quick dirty domains;
- `SongView` or `EditorDrawer` owns the module lifetime, independent of QML object lifetime.

Qt Quick input items are event receivers. They do not own `SongDocument`, `SongView`, the six
modules, or any gesture object.

## Migration phases

Every phase is one reviewable commit unless a compile-only mechanical split is required. Each
phase ends with formatting, an incremental `porydaw_app` and `porydaw_checks` build, and the
converted band's focused checks. Record unconverted-band input checks as expected failures after
Phase 2, then restore them as their band phases land. Do not wait until all six conversions are
complete before compiling.

Every band-conversion phase has the same outer-layout acceptance gate:

1. the parent-owned rectangle is the sole outer size and placement source;
2. the shared SongView layout rectangle, matching QML band rectangle, and Quick input-item bounds
   equal that parent rectangle after coordinate mapping;
3. resize, visibility, drawer-state, font, and theme changes travel through that one parent path;
4. the converted band contains no outer-height calculation or geometry mutation.

### Phase 0 — Isolated worktree and baseline

Create the implementation worktree only after this plan is committed and `fork-main` is clean:

```sh
git worktree add ../porydaw-qt-quick-input \
  -b feature/qt-quick-timeline-input fork-main
```

Record:

- base commit;
- top-level and `external/poryaaaa` status;
- Qt version and active Quick graphics backend;
- focused-check results;
- screenshots or framebuffer hashes used by the current rendering checks;
- the six current widget types and their event overrides.

Baseline checks:

```sh
deno task build:checks
deno task verify --filter=rollcheck
deno task verify --filter=rollwindowingcheck
deno task verify --filter=editor-drawer
deno task verify --filter=automation-gestures
deno task verify --filter=automation-popup-menus
deno task verify --filter=automation
deno task verify --filter=velocity-page
deno task verify --filter=rendering-playhead
```

Run window-system checks with a real logged-in display. Do not treat an offscreen native-window
failure as product evidence.

### Phase 1 — Canonical band layout

Files:

- new `src/ui/songview/timelinebandlayout.h`
- `src/ui/songview.h/.cpp`
- `src/ui/editordrawer/editordrawer.h/.cpp`
- `src/ui/editordrawer/drawersections.h/.cpp`
- `src/ui/songview/quick/timelinequickview.h/.cpp`
- `src/ui/playheadoverlay.h/.cpp`
- focused geometry/playhead checks

Work:

1. Add `TimelineBandLayout` and make `SongView` publish it.
2. Add `rulerHeight` and `otherEventsHeight` to `SongView::Geometry`, resolve them with the existing
   font-derived formulas, and apply them to SongView-owned spacer layout items.
3. Make `DrawerSections` retain and publish its three calculated body rectangles before it applies
   them to the current widgets.
4. Assert that every current full-area widget exactly fills the new parent-owned rectangle.
5. Make `TimelineQuickView` consume the value instead of holding its private `PublishedLayout`.
6. Make `PlayheadOverlay` consume value geometry rather than widget references.
7. Keep input transparency and all widget event handling unchanged.

Acceptance:

- one value describes render, input-to-be, and playhead geometry;
- all six band sizes and positions come from SongView or DrawerSections, not the band widgets;
- Quick framebuffer placement is unchanged;
- native playhead clipping is unchanged;
- no new input behavior exists;
- geometry checks cover hidden drawer bands, event-list switching, resize, theme/font changes, and
  fractional DPR.

### Phase 2 — Convert VoiceChangeArea and enable Quick input

This is the first complete band conversion and the only point where production event ownership
changes. Do not add a temporary QWidget event receiver.

Files:

- new `src/ui/songview/quick/timelineinput.h`
- new `src/ui/songview/quick/timelineinputitem.h/.cpp`
- `src/ui/songview/quick/TimelineCanvas.qml`
- `src/ui/songview/quick/timelinequickview.h/.cpp`
- `src/ui/editordrawer/voicechangearea/voicechangearea.h/.cpp`
- `src/ui/editordrawer/drawersections.h/.cpp`
- `CMakeLists.txt`
- focused voice-change and Quick-input checks

Work:

1. Add the normalized input values, `TimelineInputHost`, `TimelineBandInteraction`, and
   `TimelineInputItem` declarations defined above.
2. Add only `timelineVoiceChangesInput` to the voice-change `TimelineSceneBand` in
   `TimelineCanvas.qml`; it fills the band rectangle and contains no gesture rules.
3. Change `VoiceChangeArea` from a QWidget to a SongView-owned QObject that implements
   `TimelineBandInteraction`.
4. Move its QWidget-dependent calls behind the attached `TimelineInputHost`:

   - focus requests;
   - horizontal-resize cursor and cursor clearing;
   - global/local mapping for picker and context menu;
   - pointer-grab cancellation;
   - bounds, font, palette, and DPR access.

5. Make `DrawerSections` retain and publish the voice-change body rectangle without positioning a
   `VoiceChangeArea` QWidget.
6. Attach the `VoiceChangeArea` object to `timelineVoiceChangesInput` from `TimelineQuickView`.
7. Remove `Qt::WindowTransparentForInput` from the `QQuickView` and
   `Qt::WA_TransparentForMouseEvents` from its host and container.
8. Apply the visible-band native-window mask described above so retained native chrome still
   receives input.
9. Delete the old VoiceChangeArea QWidget event overrides, focus plumbing, geometry observation,
   and full-area widget surface.
10. Add the focus bridge above. VoiceChanges is the only drawer band it can focus in this phase;
    attempts to focus the other two drawer bands return `false` until their phases add input items.

Preserve marker hit testing, pending/active drag threshold, pan behavior, hover labels, picker
selection, right-click suppression behavior, document revision check, follow-scroll pause, and
Quick dirty domains.

Acceptance:

- `DrawerSections::bodyRect(EditorDrawerPage::VoiceChanges)` is the sole voice-change height and
  placement source;
- the SongView-mapped shared-layout rectangle, the QML `voiceChangesBandRect`, and the
  `timelineVoiceChangesInput` bounds match that parent-owned rectangle exactly;
- resize-handle movement, collapse, reopen, font change, and theme change update all three through
  the same parent-owned layout path;
- `VoiceChangeArea` has no height setter, size hint, geometry calculation, or QWidget geometry
  dependency;
- marker click, drag, cancel, pan, hover, picker, context menu, wheel zoom, focus loss, and song
  switch match current behavior;
- the voice-change checks no longer need a concrete `VoiceChangeArea` QWidget;
- no scene or interaction state moves into QML;
- VoiceChangeArea has no QWidget base, event override, or hidden compatibility surface;
- voice-change pixels remain unchanged;
- the other five bands still render but are temporarily noninteractive on this feature branch;
- record those five known input-check failures rather than adding forwarding code.

### Phase 3 — OtherStrip conversion

Add `timelineOtherEventsInput`, attach `OtherStrip`, and remove the OtherStrip QWidget surface.
Keep its scene state, font-derived metrics, event-marker hit testing, and tooltip decisions in the
non-widget module. SongView already owns the row height and rectangle from Step 2; do not add a new
height path in this phase.

Retain native tooltip presentation, using `SongView` as the associated widget. The interaction
module decides the tooltip text and anchor; `TimelineInputItem::mapToGlobal()` provides the screen
position. Call `QToolTip::showText(globalPosition, text, &songView)` for a hit and
`QToolTip::hideText()` for no hit or pointer leave.

Acceptance:

- marker hover and leave behavior match;
- no `OtherStrip` QWidget event override or full-area widget remains;
- scene output and strip height are unchanged;
- voice changes and other events receive Quick input; the other four bands remain temporarily
  noninteractive.

### Phase 4 — TimeRuler conversion

`TimeRuler` becomes the non-widget ruler module. Extract the two real grid combo boxes into a
retained `TimeRulerControls` QWidget in the ruler gutter. Do not replace them with QML controls in
this project.

Add `timelineRulerInput`, attach `TimeRuler`, and remove the full-width TimeRuler QWidget surface.

Use these declaration-only target interfaces:

```cpp
class TimeRulerControls final : public QWidget
{
  public:
    explicit TimeRulerControls(SongView &owner, QWidget *parent);
    void syncFromView();
    void closePopups();

  private:
    SongView &m_owner;
    QComboBox *m_divCombo = nullptr;
    QComboBox *m_feelCombo = nullptr;
};

class TimeRuler final : public TimelineBandInteraction
{
  public:
    explicit TimeRuler(SongView &owner);

    bool gestureActive() const noexcept;
    void cancelInteraction();

    void attachInputHost(TimelineInputHost &host) override;
    void detachInputHost(TimelineInputHost &host) override;
    bool pointerPress(const TimelinePointerInput &input) override;
    bool pointerDoubleClick(const TimelinePointerInput &input) override;
    bool pointerMove(const TimelinePointerInput &input) override;
    bool pointerRelease(const TimelinePointerInput &input) override;
    void pointerLeave() override;
    bool wheel(const TimelineWheelInput &input) override;
    void inputCancelled(TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

  private:
    SongView &m_owner;
    TimelineInputHost *m_inputHost = nullptr;
};
```

`SongView` owns `TimeRuler` by `std::unique_ptr` and owns `TimeRulerControls` as native QWidget
chrome. `TimeRuler` does not own or call the controls. Apply these exact call-site replacements:

- `TimeRuler::syncGridControls()` becomes `TimeRulerControls::syncFromView()`;
- `TimeRuler::cancelTransientInput()` splits into `TimeRuler::cancelInteraction()` and
  `TimeRulerControls::closePopups()`, both called by SongView's existing cancellation path;
- `TimeRuler::gestureActive()` remains on the non-widget module;
- the controls' two `activated` connections continue to call `SongView::setGridMinDenom()` and
  `SongView::setGridFeel()` directly.

SongView positions `TimeRulerControls` at the ruler rectangle's left edge with width
`plotOrigin - layout::space(Space::One)` and the full parent-owned ruler height, matching today's
`m_gridBox`. Register that control rectangle as native chrome so the Quick native-window mask
leaves it available to QWidget input. The QML ruler band and `timelineRulerInput` still use the
full ruler rectangle; the native-window hole prevents them from receiving events over the
controls.

`attachInputHost()` requires no current host and stores the address. `detachInputHost()` requires
the same address, cancels ruler interaction, clears the cursor, and then clears the pointer. The
module never retains a `QQuickItem` or QWidget pointer.

Move all former QWidget reads and services to the attached input host:

- `width()` and `height()` become `host.bounds()`;
- `font()` and `devicePixelRatioF()` become `host.font()` and `host.devicePixelRatio()`;
- `setCursor()` and `unsetCursor()` become `host.setCursor()` and `host.clearCursor()`;
- global popup positions come from `TimelinePointerInput::globalPosition`;
- `QMenu` and `askTimeSignature()` use `SongView` as their native QWidget parent, never the Quick
  item or the non-widget module.

`hostAppearanceChanged()` rebuilds the same ruler fonts, marker-row height, chip layout, and Quick
scene data. It does not change the outer ruler height; SongView already owns that height from Step
2. The ruler input item does not request keyboard focus because the current ruler has no keyboard
handler. The two combo boxes retain `Qt::NoFocus`.

Change the shared wheel helper to consume `TimelineWheelInput` rather than retaining a
`QWheelEvent` dependency:

```cpp
void SongView::zoomTimelineAtWheel(const songview::TimelineWheelInput &input,
                                   qreal anchorContentX);
```

Preserve the current rule: ignore `Qt::ScrollMomentum`; otherwise use `pixelDelta` when present,
fall back to `angleDelta`, and multiply pixel-wheel zoom units by five. Ruler Shift-wheel and
horizontal-delta scrolling keep their current branches before calling the zoom helper.

Preserve scrub, loop markers, signature chips, time-selection sweep/edge drag, ruler menu, wheel
zoom, adaptive fonts, and cursor behavior.

Acceptance:

- the ruler has no full-width QWidget input surface;
- `TimeRuler` has no control-widget pointer, QWidget event override, outer-height calculation, or
  native popup parent of its own;
- the two combo boxes remain native, focusable only as they are today, and are subtracted from the
  Quick input mask;
- all ruler visuals and gestures retain current coordinates;
- loading and ruler checks pass.

### Phase 5 — VelocityArea conversion

Add `timelineVelocityInput`, attach `VelocityArea`, and remove the VelocityArea QWidget surface.
Move its former widget duties behind the input host. Keep `VelocityAxis`, frozen-note snapshots,
selection, detent behavior, preview, announcements, and scene builders in the non-widget module.

Use this declaration-only target interface:

```cpp
class VelocityArea final : public QObject, public songview::TimelineBandInteraction
{
  public:
    explicit VelocityArea(SongView &owner, QObject *parent = nullptr);

    void songChanged();
    void refreshLiveState(const DrawerPageLiveState &liveState);
    void cancelInteraction();
    void documentChanged();
    void tracksRemapped(const TrackRemap &remap);
    void setUseDetents(bool on);
    void setContextChangedCallback(std::function<void()> callback);

    VelocityAreaDiagnostics diagnostics() const noexcept;
    const VelocityAxis &axis() const noexcept;
    int plotOrigin() const;
    int plotWidth() const;
    bool useDetents() const noexcept;
    bool isPsgContext() const;
    void clearTrackHeaderSelection();
    void presentPlayhead(double tick);
    void velocityGestureChanged();

    void attachInputHost(songview::TimelineInputHost &host) override;
    void detachInputHost(songview::TimelineInputHost &host) override;
    bool pointerPress(const songview::TimelinePointerInput &input) override;
    bool pointerMove(const songview::TimelinePointerInput &input) override;
    bool pointerRelease(const songview::TimelinePointerInput &input) override;
    void pointerLeave() override;
    bool wheel(const songview::TimelineWheelInput &input) override;
    bool keyPress(const songview::TimelineKeyInput &input) override;
    void inputCancelled(songview::TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

  private:
    SongView &m_owner;
    songview::TimelineInputHost *m_inputHost = nullptr;
};
```

Keep the current private gesture types and helpers behind this interface. `EditorDrawer` owns the
QObject; `TimelineQuickView` holds a non-owning pointer, attaches it to
`timelineVelocityInput`, and detaches it before destruction. The module never retains a
`QQuickItem` or QWidget pointer.

Apply these exact QWidget-service replacements:

- `width()`, `height()`, `font()`, `palette()`, and `devicePixelRatioF()` read from the attached
  `TimelineInputHost` for axis and Quick-scene construction;
- `plotWidth()` is `max(0, host.bounds().width() - plotOrigin())`;
- pointer press calls `host.requestFocus(Qt::MouseFocusReason)` before starting a gesture;
- `inputCancelled(reason)` calls `cancelInteraction()` for every reason;
  `PointerUngrabbed` replaces the old `QEvent::UngrabMouse` branch;
- `hostAppearanceChanged()` runs the current font-metric and internal-geometry rebuild, then
  requests the Velocity Quick dirty domain; it never changes the outer band height;
- Escape in `keyPress()` cancels and returns `true`; other keys return `false`;
- `wheel()` keeps the current horizontal-scroll branch and otherwise calls the normalized
  `SongView::zoomTimelineAtWheel(TimelineWheelInput, anchorContentX)` declared in Phase 4;
- `publishAccessibleDescription()` calls
  `host.setAccessibilityDescription(QString::fromLatin1(description.data(), int(description.size())))`
  for the current `m_axis.accessibleDescription()` value;
  on attach, publish the current value before the first focused interaction;
- use `QApplication::startDragDistance()` for the existing right-button band threshold. This is a
  platform metric, not QWidget ownership.

Delete the application-wide modifier event filter with no replacement. It only requests a scene
rebuild on modifier press and release; the Velocity scene does not read global modifier state.
Gesture-time detent unlock already comes from `TimelinePointerInput::modifiers` on press and stays
frozen for the gesture. Do not add a modifier observer or polling path.

Delete `m_suppressContextMenu` and `contextMenuEvent()`. The Quick item receives the right-button
press and release directly and does not synthesize the QWidget context-menu event that field used
to swallow. Keep the current right-button pending-band, drag threshold, selection, and release
rules unchanged.

Apply these owner changes in the same phase:

- `EditorDrawer` creates the QObject-owned `VelocityArea` and stops installing a QWidget event
  filter on it;
- `DrawerSections` keeps the non-owning module pointer only for `plotOrigin()`, detent state,
  context state, and cancellation;
- `DrawerSections` no longer parents, shows, positions, focuses, masks, or adds a VelocityArea
  QWidget to `occupiedRegion()`;
- the retained velocity resize handle and detent toggle remain native chrome;
- position the detent toggle from `DrawerSections::bodyRect(EditorDrawerPage::Velocity)` and the
  module's `plotOrigin()`, not from a removed widget geometry;
- `EditorDrawer::focusVisiblePage()` uses the shared `focusTimelineBand(Velocity, reason)` route,
  and `ownsFocus()` uses `focusedTimelineBand()`.

Update `rollcheckpsgvelocity` to drive the declared interaction interface with the in-memory input
host. Assert the published host accessibility description instead of casting VelocityArea to
QWidget. Keep the Quick integration check for item focus, bounds, pointer grab, and scene output;
keep drawer checks for the native detent toggle, resize handle, and parent-owned body rectangle.

Acceptance:

- relative, paint, ramp, band, and pan gestures match;
- detent lock/unlock, track context, cancellation, and one-note announcements match;
- the input host's bounds are the only source for scene width and height, and
  `DrawerSections::bodyRect(EditorDrawerPage::Velocity)` matches the shared layout rect, QML band,
  and `timelineVelocityInput` bounds;
- focus enters the Velocity Quick item, focus loss and pointer-ungrab cancel once, and
  `EditorDrawer::ownsFocus()` reports the Quick focus correctly;
- accessibility description remains observable through `timelineVelocityInput` and its QML
  `Accessible.description` binding;
- no application-wide modifier filter, context-menu suppression field, QWidget event override,
  or full-area Velocity QWidget remains;
- velocity and drawer checks pass.

### Phase 6 — PianoRoll conversion

Add `timelineRollInput`, attach `PianoRoll`, and remove the PianoRoll QWidget surface. Move its
former QWidget-dependent focus, cursor, coordinate mapping, DPR, and bounds access behind the input
host. Parent retained menus and the pitch-bend popup to the existing SongView/native window.

Use this declaration-only target interface. Keep the existing private drag enums, frozen gesture
state, geometry helpers, scene data, and command helpers behind it.

```cpp
class PianoRoll final : public QObject, public TimelineBandInteraction
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PianoRoll)

  public:
    explicit PianoRoll(SongView *songView);

    bool gestureActive() const;
    void cancelPitchBendPopup();
    void cancelTransientInput();
    void cancelVelocityInteraction();
    void refreshTextLayout();
    void copySelectedNotes();
    void requestQuickUpdate(PianoRollQuickDirtySet dirty);

    void attachInputHost(TimelineInputHost &host) override;
    void detachInputHost(TimelineInputHost &host) override;
    bool pointerPress(const TimelinePointerInput &input) override;
    bool pointerDoubleClick(const TimelinePointerInput &input) override;
    bool pointerMove(const TimelinePointerInput &input) override;
    bool pointerRelease(const TimelinePointerInput &input) override;
    void pointerLeave() override;
    bool wheel(const TimelineWheelInput &input) override;
    bool keyPress(const TimelineKeyInput &input) override;
    bool keyRelease(const TimelineKeyInput &input) override;
    void inputCancelled(TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

  private:
    SongView *const m_sv;
    TimelineInputHost *m_inputHost = nullptr;
};
```

`PianoRoll` remains a QObject because it owns popup connections and queued callbacks. `SongView`
owns it as a QObject child; `TimelineQuickView` keeps a `QPointer<PianoRoll>`, attaches it to
`timelineRollInput`, and detaches it before destruction. Keep the `pianoRoll` object name and the
existing `hoverKey` dynamic property until the rollcheck harness no longer reads it. Do not add a
hidden QWidget or a wrapper QWidget.

The constructor stores SongView, resolves the scale-based `PianoRollGeometry`, and creates the
SongView-parented note menu. It does not read font, palette, DPR, bounds, or build cursor pixmaps.
`attachInputHost()` requires no current host, stores the address, resolves the current cursors and
font caches from that host, invalidates the row-edge cache, then requests the first full Quick
sync. SongView constructs and attaches the input item before its first camera/layout refresh.
Methods that need host geometry require an attached host; do not add guessed startup dimensions.

#### Normalized input conversion

No PianoRoll declaration may take `QMouseEvent`, `QWheelEvent`, or `QKeyEvent` after this phase.
Convert these existing helpers to take `const TimelinePointerInput &` without changing their
branch order:

- `updateHoverKey`, `panMove`, `kbdGlissandoMove`, and `resolvePendingPresses`;
- `beginPanGesture`, `beginKbdAudition`, `beginPendingMenu`, `beginLeftPress`, `pressContent`, and
  `beginNotePress`;
- `resolveRightPress`, `resolveDrawPress`, `resolveVelocityPress`, `updateMoveDrag`,
  `updateResizeDrag`, `updateVelocityDrag`, `updateDrawDrag`, and `updateTimeSelDrag`;
- `updateLeftDragMove`, `dispatchLiveDragMove`, `releaseRightPress`, `releasePendingMenu`,
  `releasePendingLeftPress`, `releasePendingDrawClick`, and `finishReleaseWithoutCommit`.

Remove unused event parameters from `beginPendingDraw()`, `releasePendingVelocityClick()`, and
`commitDrag()`. Keep `updateBandDrag()` event-free. Replace every `event->position()`,
`event->globalPosition()`, `event->button()`, `event->buttons()`, and `event->modifiers()` read with
the matching normalized field. Keep `QApplication::startDragDistance()` for the two existing drag
thresholds.

The four public pointer methods return `true` for the branches the current QWidget accepts and
`false` for ignored buttons or unavailable document/timeline branches. `pointerPress()` requests
`Qt::MouseFocusReason` through the host before starting a valid interaction. The Quick item owns
the pointer grab; PianoRoll must not call `grabMouse()` or `releaseMouse()`.

`pointerLeave()` clears `m_hoverKey`. `inputCancelled(reason)` preserves the current `event()` rule
for every reason: cancel a pending or active velocity drag. Song/tab/project cancellation
continues to call the stronger `cancelTransientInput()` route. `detachInputHost()` calls
`cancelTransientInput()`, clears the host cursor, and then clears the pointer.

#### Keys and wheel

Add this value overload to `keymap::Registry`; keep the QKeyEvent overload temporarily and make it
delegate to this one until the other QWidget bands are converted:

```cpp
bool matches(int key, Qt::KeyboardModifiers modifiers, const QString &id) const;
```

It preserves the current rejection of zero, `Qt::Key_unknown`, and bare modifier keys, strips
Keypad and GroupSwitch modifiers with the existing helper, and compares the same one-stroke
`QKeySequence` value.

Change the SongView key helpers to plain values:

```cpp
bool SongView::handleEditKey(const TimelineKeyInput &input);
int SongView::transposeStepFor(const TimelineKeyInput &input) const;
```

They return whether the command was consumed; they do not accept a Qt event. PianoRoll's
`keyPress()` keeps the exact current command order: modifier-text invalidation, paste, shared edit
commands, cut, select-all, delete, pitch bend, transpose, nudge, then Escape. `keyRelease()` keeps
modifier-text invalidation and stops transpose audition only for a non-auto-repeat release while
no drag is live. It returns `false` after those side effects so unrelated keys can continue through
the Quick focus chain.

Add the normalized wheel companion used by this phase:

```cpp
void SongView::zoomKeyHeight(const TimelineWheelInput &input);
```

Keep the old QWheelEvent overload only while unconverted widgets call it; delete it in Phase 8.
The normalized method uses `input.position.y()` as the vertical anchor and the same momentum,
pixel-delta, angle-delta, and exponential zoom rules. PianoRoll's `wheel()` preserves the current
branch order: Control zooms key height; Shift scrolls horizontally; horizontal-only delta scrolls
horizontally; wheel over the keyboard scrolls pitch; wheel over notes calls the Phase 4 normalized
timeline zoom helper.

#### Host geometry, appearance, and cursor

Replace all former widget reads as follows:

- PianoRoll hit testing, row edges, note geometry, hover-chip clamping, and scene construction read
  `host.bounds()` and `host.devicePixelRatio()`;
- font and palette reads use `host.font()` and `host.palette()`;
- edge, velocity-drag, pan, and arrow cursors use `host.setCursor()` or `host.clearCursor()`;
- `refreshHoverAtCursor()` maps `QCursor::pos()` through the host, tests `host.bounds()`, and keeps
  `QApplication::keyboardModifiers()` because the current cursor shape depends on the live
  velocity-drag modifier;
- `hostAppearanceChanged()` resolves `PianoRollGeometry`, cursor pixmaps, fonts, text layout, and
  row-edge cache, then requests all PianoRoll Quick domains. It does not set a minimum height or
  call `SongView::syncTimelineQuickAppearance()` recursively.

Step 2 already owns outer geometry. Remove `setMinimumHeight()`, `setSizePolicy()`, mouse tracking,
focus policy, and the full-area widget insertion from SongView. The retained roll page, vertical
scrollbar, track headers, event-list stack, and parent layout remain native. Apply these direct
SongView replacements:

- `viewportWidth()` uses the canonical roll rectangle width minus its timeline origin;
- `rollViewportHeight()` uses the canonical roll rectangle height minus the visible drawer height,
  preserving today's camera extent;
- camera and projection code use `TimelineQuickView::quickDevicePixelRatio()` instead of
  `m_roll->devicePixelRatioF()`;
- Quick scene builders use the attached roll input host's bounds, font, palette, and DPR instead
  of the deleted widget;
- the canonical roll rectangle, QML `rollBandRect`, and `timelineRollInput` bounds remain equal.

Add the exact host query used by those SongView call sites:

```cpp
qreal TimelineQuickView::quickDevicePixelRatio() const;
```

It returns the live QQuickWindow DPR and falls back to `1.0` only before the window exists. Do not
declare `devicePixelRatio()` because `TimelineQuickView` already inherits the QPaintDevice method
with that name.

#### Native menus and pitch-bend editor

Keep `NoteContextMenu` native and parent it to `SongView`, not PianoRoll. Its outside-right-click
callback still calls `PianoRoll::moveNoteMenu(globalPosition)`. Convert `showNoteMenu()`,
`focusNoteUnderCursor()`, and `moveNoteMenu()` to use the input host's global mapping and focus
request. Parent `QInputDialog::getInt()` to `SongView`.

Remove `PitchBendEditor`'s `QPointer<QWidget> focusTarget` constructor parameter and member. It
already owns a `SongView` pointer; on a close that restores focus, queue
`SongView::focusTimelineBand(TimelineBand::Roll, Qt::PopupFocusReason)` on that SongView. Keep the
existing `focusNoteUnderCursor(globalPosition)` callback for outside right-click retargeting. Build
the note's global rectangle with `TimelineInputHost::mapToGlobal()`, and use the host mapping for
the cursor fraction. The popup remains a native tool window parented to SongView's native window.

When the popup dies, keep the queued `refreshHoverAtCursor()` call on the PianoRoll QObject. It
must use the attached host and do nothing if the host has detached. All direct focus call sites in
`SongView::focusContent()`, track/voice operations, and popup close paths use
`SongView::focusTimelineBand(TimelineBand::Roll, reason)`.

#### Check migration

Change the rollcheck harness to hold both the `PianoRoll` QObject and
`timelineRollInput`. Geometry and DPR probes read the input item's bounds and host DPR. Framebuffer
crops use
`SongView::timelineBandLayout().geometry(TimelineBand::Roll).value().rect`, after the harness has
required the roll band to be visible, through the existing rectangle overload of
`captureQuickBand()`.

Add `TimelineInputItem` overloads to `checks::events::sendMouse()` and `sendWheel()`; construct the
same Qt events with band-local and host-mapped global positions, then send them to the real Quick
item. `sendKey()` already targets QObject and should target the Quick input item. Keep a focused
integration check for Quick focus, pointer grab, hide/ungrab/window-deactivate cancellation,
cursor publication, and native popup return focus. Delete assertions that only prove PianoRoll is
a QWidget or owns outer geometry.

The focused integration check sends its pointer sequence to `QQuickWindow` at the mapped root
coordinate, not directly to the item, so it proves Quick hit testing and exclusive grab delivery.
The larger semantic rollcheck suite may send directly to `timelineRollInput` to avoid repeating
window-system setup in every scenario.

Preserve every current drag state, keyboard audition, note audition, scale/fold rejection,
selection, clipboard command, context menu, cursor, wheel, and pitch-bend route.

Acceptance:

- `PianoRoll` has no QWidget base, QWidget event override, widget geometry read, or hidden
  compatibility surface;
- all rollcheck domains pass;
- keyboard focus and shortcuts work after switching tabs, drawer focus, menus, and event-list
  pages;
- every pointer helper consumes normalized values, and no private helper retains a Qt event
  pointer;
- roll height and placement come only from the canonical parent-owned layout;
- note menus and pitch-bend popup preserve placement and lifetime;
- pitch-bend close returns focus to `timelineRollInput`, never a deleted QWidget;
- cursor shape, keyboard hover, note hover, audition, and cancellation match current behavior;
- Quick rendering output is unchanged.

### Phase 7 — AutomationCanvas conversion

Add `timelineAutomationInput`, attach `AutomationCanvas`, and remove the AutomationCanvas QWidget
surface. Keep `AutomationPage`, its native `QScrollArea`, and its left vertical scrollbar. Most
automation behavior transfers without redesign: the row model, hit testing, gesture state,
selection, edits, menus, hover, cursors, and scene builders remain inside `AutomationCanvas`.

The required redesign is the scroll contract. Today the full-height QWidget is both the input
target and the object from which `QScrollArea` derives its range. The target removes only the child
widget contract: `AutomationPage` computes content height and sets the retained scrollbar range
itself. Do not replace `QScrollArea`, add a scroll model, or keep an invisible full-height widget.

#### Exact target declarations

`AutomationCanvas` keeps `QObject` because QAction connections, queued refreshes, and translated
strings still need it. Its target declaration is:

```cpp
class AutomationCanvas final
    : public QObject
    , public songview::TimelineBandInteraction
{
    Q_DISABLE_COPY_MOVE(AutomationCanvas)

  public:
    explicit AutomationCanvas(AutomationPage &page);
    ~AutomationCanvas() override = default;

    void requestFullQuickUpdate() const;
    const std::vector<AutomationRow> &rows() const noexcept;
    void rebuildRows();
    void updateTempoLayout();
    void cancelInteraction();
    void setPencilMode(bool enabled);
    bool isPanning() const noexcept;
    bool bandPreviewContainsLane(LaneHandle handle) const noexcept;
    QRect labelGutter() const noexcept;
    int plotOrigin() const noexcept;
    QRect laneBody(LaneHandle handle) const;
    QRect pinnedTempoRect() const noexcept;
    int minimumContentHeight() const noexcept;

    void attachInputHost(songview::TimelineInputHost &host) override;
    void detachInputHost(songview::TimelineInputHost &host) override;
    bool pointerPress(const songview::TimelinePointerInput &input) override;
    bool pointerDoubleClick(const songview::TimelinePointerInput &input) override;
    bool pointerMove(const songview::TimelinePointerInput &input) override;
    bool pointerRelease(const songview::TimelinePointerInput &input) override;
    void pointerLeave() override;
    bool wheel(const songview::TimelineWheelInput &input) override;
    bool keyPress(const songview::TimelineKeyInput &input) override;
    void inputCancelled(songview::TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

  private:
    friend class AutomationPage;
    friend class songview::TimelineQuickView;

    struct PointerLaneHit;
    struct NodeLaneSlot;

    void viewportResized();
    void scrollStateChanged();
    void relayoutContent();
    void contentGeometryChanged();

    QPointF contentPosition(QPointF viewportPosition) const noexcept;
    QPointF viewportPosition(QPointF contentPosition) const noexcept;
    QPointF contentPositionFromGlobal(QPointF globalPosition) const;
    QRect viewportRect(QRect contentRect) const noexcept;
    QRect contentBounds() const noexcept;

    void clearTimeSelectionIfOutsidePress(QPointF contentPosition,
                                          const AutomationProjection &projection,
                                          LaneHandle lane,
                                          const NodeLaneSlot *slot);
    bool beginPencilPress(QPointF contentPosition,
                          Qt::KeyboardModifiers modifiers,
                          LaneHandle handle,
                          const NodeLane &lane,
                          const QRect &body,
                          const AutomationProjection &projection);
    bool beginDragOrSweep(QPointF contentPosition,
                          Qt::KeyboardModifiers modifiers,
                          LaneHandle handle,
                          const AutomationProjection &projection);

    AutomationPage &m_page;
    songview::TimelineInputHost *m_inputHost = nullptr;

    // Retain the current row, lane, gesture, selection, clipboard, hover,
    // font, cursor, and cache members.
};
```

`inputCancelled(FocusLost)` returns without changing state because the current canvas does not
cancel on focus-out and native menus temporarily transfer focus. Pointer ungrab, hide, and window
deactivation use the strong cancellation path. Tab/song/project change continues to call the
module's explicit cancellation route.

`AutomationPage` retains its QWidget role and adds this fixed interface:

```cpp
AutomationCanvas *canvas() noexcept;
const AutomationCanvas *canvas() const noexcept;
QWidget *scrollViewport() const noexcept;
QSize automationViewportSize() const noexcept;
int automationContentHeight() const noexcept;
int verticalScroll() const noexcept;

private:
void synchronizeAutomationViewport();
void setVerticalScroll(int value);
bool scrollVertically(const songview::TimelineWheelInput &input);
void requestTimeZoom(const songview::TimelineWheelInput &input,
                     qreal anchorContentX) const;
bool matchesPencilShortcut(int key, Qt::KeyboardModifiers modifiers) const noexcept;
bool belongsToPageWindow(const QObject *target) const noexcept;

int m_automationContentHeight = 0;
qreal m_verticalWheelRemainder = 0.0;
```

`AutomationPage::ScrollArea` remains a `QScrollArea`. Delete
`setWidgetResizable(true)`, `setWidget(m_canvas)`, the canvas layout-direction call, and every canvas
minimum-height or outer-geometry call. Construct the canvas as an `AutomationPage`-owned QObject.
Extend the page's existing application event filter so `watched == m_scroll->viewport()` and a
Resize event calls `canvas->viewportResized()` and then `synchronizeAutomationViewport()`; do not
install the same filter on the viewport a second time. Connect scrollbar value changes directly to
`canvas->scrollStateChanged()`; scrolling does not recompute the range.

#### Parent geometry and scroll range

`DrawerSections` remains the sole owner of the outer AutomationPage rectangle. The page layout
fills that rectangle with the retained scroll area. The scroll viewport rectangle is all three of
these values after coordinate mapping:

- `TimelineBandLayout::geometry(TimelineBand::Automation)`;
- the QML automation band rectangle;
- `timelineAutomationInput` bounds.

AutomationCanvas may calculate row heights inside its content. It never sets the page, viewport,
or outer band height.

Use these formulas:

```cpp
const int ccHeight =
    m_rowData.minimumHeight(m_geometry, layout::space(layout::Space::Zero));
const int minimumContentHeight =
    ccHeight + m_tempoLane.totalHeight(m_geometry);
const int contentHeight = std::max(viewportHeight, minimumContentHeight);

verticalBar->setPageStep(viewportHeight);
verticalBar->setRange(0, std::max(0, contentHeight - viewportHeight));

const int tempoTop =
    std::min(verticalScroll + viewportHeight, contentHeight) -
    m_tempoLane.totalHeight(m_geometry);
```

This preserves the current `QScrollArea`, resizable child, and minimum-height result without the
child widget. `synchronizeAutomationViewport()` uses this fixed order:

1. Read `scrollViewport()->size()`.
2. Read `canvas->minimumContentHeight()` and calculate final content height.
3. Store `m_automationContentHeight`.
4. Block the scrollbar's value signal while setting its page step and range.
5. Read the range-clamped scrollbar value and unblock the signal.
6. Call `canvas->scrollStateChanged()` once.

`viewportResized()` relayouts lane rectangles from `m_page.automationViewportSize()`; it stores no
copy of that size. `scrollStateChanged()` reads `m_page.automationContentHeight()` and
`m_page.verticalScroll()`, then resynchronizes the pinned tempo layout, labels, and visible Quick
domains. Row-height changes, shared Control-wheel height changes, add/hide/remove lane, and tempo
expand/collapse use this order:

1. `AutomationCanvas::relayoutContent()`;
2. `AutomationPage::synchronizeAutomationViewport()`;
3. hover and preview-label synchronization;
4. full Automation Quick update.

`contentGeometryChanged()` is the single private helper that performs those four steps. Callers do
not reproduce the sequence.

Middle-button pan calls
`AutomationPage::setVerticalScroll(startScroll - qRound(delta.y()))`. A row resize updates the
stored lane height and runs the same content-relayout sequence during the drag, so the scrollbar
range and pinned tempo position remain current.

#### Coordinate contract

Every `TimelinePointerInput::position` begins in automation-viewport coordinates. Convert it once
at the public AutomationCanvas input method before calling existing lane, point, phantom, pencil,
sweep, resize, pan, selection, or menu helpers:

```cpp
QPointF AutomationCanvas::contentPosition(QPointF viewport) const noexcept
{
    return viewport + QPointF(0.0, m_page.verticalScroll());
}

QPointF AutomationCanvas::viewportPosition(QPointF content) const noexcept
{
    return content - QPointF(0.0, m_page.verticalScroll());
}
```

Existing internal hit testing and gesture state continue to use content coordinates. The pinned
tempo lane also uses content coordinates: its logical rectangle moves to `tempoTop` when scrolling,
so adding `m_page.verticalScroll()` to the Quick input position hits the same rectangle that the old
scrolled child widget used. Rendering translates logical lane rectangles by `-verticalScroll`.

`contentBounds()` reads its width from `m_page.automationViewportSize().width()` and its height
from `m_page.automationContentHeight()`. AutomationCanvas does not cache viewport size, content
height, or scroll position; `AutomationPage` and its native viewport/scrollbar are the single source
for all three values.

Keep subtracting `AutomationPage::scrollGutter()` from `plotOrigin`. The viewport already excludes
the left scrollbar, so the timeline origin remains aligned with the other bands.

Convert only the three remaining event-dependent private helpers to the declarations above:
`clearTimeSelectionIfOutsidePress`, `beginPencilPress`, and `beginDragOrSweep`. All other private
gesture helpers already accept points, buttons, or modifiers and retain their current shapes. No
AutomationCanvas declaration may take `QMouseEvent`, `QWheelEvent`, `QKeyEvent`, `QResizeEvent`, or
`QEvent` after this phase.

#### Wheel behavior

Preserve the current branch order:

1. Control scales the shared lane height.
2. Shift scrolls the timeline horizontally.
3. A horizontal-only delta scrolls the timeline horizontally.
4. A pointer left of `plotOrigin` scrolls the automation rows vertically.
5. A pointer in the plot area performs normalized timeline zoom.

Branch 4 replaces the QAbstractScrollArea propagation that disappears when Quick owns input. It
uses `angleDelta`, ignores a wheel whose horizontal magnitude exceeds its vertical magnitude,
honors `input.inverted`, uses the native scrollbar's `singleStep()` and page step, retains a
fractional remainder, clears that remainder on direction change or a blocked endpoint, and clamps
one event to one page. Apply the resulting step through `setVerticalScroll()`. Branch 5 calls the
new normalized `AutomationPage::requestTimeZoom(const TimelineWheelInput &, qreal)` overload.

#### Host, focus, and cancellation

Replace QWidget services directly:

- viewport bounds, font, palette, and DPR come from the attached host; content height and vertical
  scroll come from `AutomationPage`;
- cursors use `host.setCursor()` and `host.clearCursor()`;
- a handled press calls `host.requestFocus(Qt::MouseFocusReason)`;
- asynchronous cursor refresh maps `QCursor::pos()` through the host, then through
  `contentPosition()`;
- pointer cancellation uses `host.releasePointerGrab()`;
- attach publishes `tr("Automation lanes")` as the accessibility description.

`hostAppearanceChanged()` resolves `AutomationGeometry`, rebuilds title/caption fonts from the
host font, rebuilds the pencil cursor for the host DPR, invalidates hover/text caches, relayouts
content, asks the page to synchronize its range, and requests all Automation Quick domains. It
does not set any outer height.

For every reason except `FocusLost`, `inputCancelled(reason)` clears gesture, resize, pan, band,
preview, hover, and cursor state, releases the Quick grab, resumes follow-scroll, and publishes the
matching dirty domains. Escape retains the current softer `cancelInteraction()` behavior.

#### Native menus, dialogs, and pencil shortcut

Use `AutomationPage` as the QWidget parent for every QMenu, `ui::ContextMenu`, QMessageBox, and
`NodeLane::promptValue` call that currently uses the canvas. Initial popup placement uses
`TimelinePointerInput::globalPosition`. An outside-right-click callback converts in this order:

```text
global position -> host.mapFromGlobal() -> contentPosition() -> lane/point hit test
```

After a blocking menu or dialog returns, request automation input focus with
`Qt::PopupFocusReason` when the host remains attached. QML owns no menu or gesture logic.

Keep the pencil QAction and application event filter on `AutomationPage`. Change only
`matchesPencilShortcut()` to accept key and modifiers. `belongsToPageWindow()` accepts QWidget
targets in the page's top-level window and QWindow targets whose parent-window chain reaches the
page window handle. Preserve text-input suppression, ShortcutOverride handling, auto-repeat
suppression, and QAction toggling.

#### Quick scene and deletion

Add `timelineAutomationInput` inside the existing Automation `TimelineSceneBand`, filling that
band. `TimelineQuickView` attaches `automationPage.canvas()` through the existing
`setInteraction()` path and detaches it before either object dies. Do not add an adapter.

Keep current visible-row virtualization:

- the QML band and input item equal viewport height only;
- logical lane rectangles remain in content coordinates;
- visible CC rows translate by `-verticalScroll`;
- rows with empty viewport clips build no point or text records;
- pinned tempo clips the CC viewport before visible-row collection;
- no QML item or scene surface uses content height.

After native Quick hover passes on macOS, delete
`automationhoverpassthrough_macos.mm`, `automationgesturecheck/nativehover_macos.mm`, and both CMake
entries. Remove AutomationCanvas QWidget event filters from EditorDrawer and TimelineQuickView.
Automation focus then goes only through `focusTimelineBand(TimelineBand::Automation, reason)`.

#### Check migration and acceptance

Retarget existing checks; do not add another check program:

- automation-gestures uses the non-widget module through the shared in-memory host; its public rig
  may retain content-coordinate helpers but converts to viewport coordinates before constructing
  normalized input;
- routing, lifecycle, and hover add the real `timelineAutomationInput` and QQuickWindow checks for
  focus, pointer grab, native hover, leave, hide, and cancellation;
- automation-popup-menus opens through the Quick item and checks Page-parented native popups;
- rollcheckautomation replaces QWidget minimum-height and mapping queries with
  `minimumContentHeight()`, `verticalScroll()`, and explicit content/viewport conversion;
- hostcheck and mainwindowroutingcheck obtain the module from `AutomationPage::canvas()`, not
  `findChild<AutomationCanvas>()`;
- checks may continue to find the retained QScrollArea and its scrollbar.

Acceptance:

- the parent page rect, canonical automation rect, QML band rect, and Quick input bounds match;
- the left scrollbar receives native clicks through the Quick native-window mask hole;
- scrollbar maximum equals `max(0, contentHeight - viewportHeight)` after lane add/hide/remove,
  row resize, tempo expand/collapse, font change, and drawer resize;
- AutomationCanvas retains no viewport-size, content-height, or vertical-scroll copy; all mapping
  reads AutomationPage and its native viewport/scrollbar;
- pinned tempo bottom equals viewport height at minimum, middle, and maximum scroll;
- row resize updates range during the drag and clamps the current value;
- tempo and CC point, phantom, pencil, sweep, selection, resize, pan, menus, cursors, hover, and
  cancellation match current behavior through normalized input;
- the pressed Quick item keeps its grab across row and band edges until release or cancellation;
- no hover survives leave, hide, tab switch, song switch, or window deactivation;
- scene records contain only visible rows when content height exceeds viewport height;
- no full-content-height QWidget, QML item, or scene surface remains;
- macOS hover passes without synthesized QWidget moves;
- automation behavior, popup, paint, and gesture checks pass.

Add final searches for `setWidget(m_canvas)`, Qt event-pointer types in `automationcanvas*`, and both
hover-synthesizer names. No product decision remains in this phase.

### Phase 8 — Finish all-band Quick input

Add `timelineAutomationInput` in Phase 7 only after the first five items already exist. This phase
audits the complete six-band result and removes migration-only code; it does not switch event
ownership again.

Work:

1. Validate that all six input items exist and have the matching non-widget module attached.
2. Stop deriving every band rectangle from deleted widgets; native layout owners now publish all
   six rectangles directly.
3. Delete widget event filters and QWidget-only code made unreachable by the six conversions.
4. Retarget integration checks to the real Quick items and QQuickWindow delivery path.
5. Restore every check that was recorded as temporarily failing after the first input cutover.

Acceptance:

- the six domain classes do not derive from QWidget;
- Quick receives input only inside visible band regions;
- retained native controls receive input normally through holes in the native-window mask;
- switching to the event-list page removes roll input and pixels together;
- hidden/collapsed drawer bands receive neither pixels nor input;
- pointer grab remains with the pressed band until release or cancellation;
- no hover state survives leave, hide, tab switch, project/song switch, window deactivation, or
  focus transfer;
- the macOS native hover checks pass without synthesized QWidget mouse moves.

### Phase 9 — Check cleanup and final verification

Update test ownership rather than layering new tests over the old ones:

- interaction-rule checks call the non-widget module interface through the in-memory host;
- integration checks send events through the actual Quick item/window;
- rendering checks continue to inspect Quick output;
- native playhead checks continue to inspect native/fallback presentation;
- delete checks whose only purpose was proving QWidget event forwarding or widget geometry.

Run:

```sh
deno task format:check
deno task build:app
deno task build:checks
deno task verify --filter=rollcheck
deno task verify --filter=rollwindowingcheck
deno task verify --filter=editor-drawer
deno task verify --filter=automation-gestures
deno task verify --filter=automation-popup-menus
deno task verify --filter=automation
deno task verify --filter=velocity-page
deno task verify --filter=rendering-playhead
deno task verify
```

Linux ASAN currently excludes specific Quick/native-window harnesses. Do not count those exclusions
as coverage of this migration. The normal window-system suite and platform CI jobs must exercise
the migrated input path.

## Behavior parity checklist

### Shared

- hover enter, movement, leave, and source ownership;
- left, right, and middle button press/move/release;
- double-click;
- vertical and horizontal wheel input, including pixel deltas;
- Shift/Alt/Control/Meta modifiers;
- drag activation threshold;
- cursor changes and clearing;
- pointer grab across band edges;
- focus acquisition and focus-loss cancellation;
- window deactivation, tab switch, song switch, and hidden-band cancellation;
- native menus, dialogs, tooltips, and popup placement;
- fractional DPR coordinate mapping;
- theme and font changes;
- accessibility description and announcements;
- no document mutation during a cancelled gesture.

### Ruler

- edit-cursor scrub;
- loop marker drag;
- time-signature chip drag and menu;
- time-selection create and edge drag;
- grid controls and wheel zoom.

### Piano roll

- note draw, move, left/right resize, velocity drag, and audition;
- band and time selection;
- keyboard-column hover and glissando;
- scale/fold rules;
- note menu, clipboard commands, shortcuts, and pitch-bend popup.

### Other events

- event-marker hit slop;
- multi-line tooltip content and dismissal.

### Automation

- tempo and CC lanes;
- point, phantom, pencil, sweep, band, and pan gestures;
- lane height resize and vertical scroll;
- hover/value labels and cursor states;
- add/lane/time-selection menus;
- pencil shortcut and gesture cancellation.

### Velocity

- DirectSound and PSG mappings;
- detents and unlock modifiers;
- relative, paint, ramp, band, and pan gestures;
- accessibility description and preview announcements.

### Voice changes

- held spans and marker hit testing;
- marker drag and pan;
- picker and context menu;
- hover label and cancellation.

## Static deletion gates

The final diff must satisfy targeted searches equivalent to:

```sh
rg -n "class (TimeRuler|PianoRoll|OtherStrip|AutomationCanvas|VelocityArea|VoiceChangeArea).*public QWidget" src
rg -n "WindowTransparentForInput|WA_TransparentForMouseEvents" src/ui/songview/quick
rg -n "automationhoverpassthrough" src CMakeLists.txt
rg -n "set(Fixed|Minimum|Maximum)(Size|Height)|updateGeometry|sizeHint|setGeometry" \
  src/ui/songview/timeruler* src/ui/songview/pianoroll* src/ui/songview/otherstrip* \
  src/ui/editordrawer/automationcanvas* src/ui/editordrawer/velocityarea \
  src/ui/editordrawer/voicechangearea
```

All four searches must produce no target-path hits. `TimelineQuickView`, `EditorDrawer`,
`AutomationPage`, retained controls, and the playhead fallback may remain QWidget-based.

## Commit sequence

Use these review slices:

1. `Publish canonical timeline band layout`
2. `Route voice-change input through Qt Quick`
3. `Route other-events input through Qt Quick`
4. `Route time-ruler input through Qt Quick`
5. `Route velocity input through Qt Quick`
6. `Route piano-roll input through Qt Quick`
7. `Route automation input through Qt Quick`
8. `Finish all-band Quick input cleanup`
9. `Remove obsolete QWidget input checks`

Do not combine any band conversion with a gesture redesign. The first conversion deliberately
makes the five unconverted rows noninteractive on the feature branch. Do not add forwarding code
to hide that temporary state. If a conversion reveals an existing behavior bug, record it
separately unless it blocks parity for that band.

## Completion definition

The work is complete when:

- the six rendered bands receive production input through Quick;
- their C++ modules no longer derive from QWidget;
- the old full-area widgets are deleted;
- every outer band height and rectangle comes only from SongView or DrawerSections;
- one canonical layout value drives Quick rendering, Quick input, and native playhead clipping;
- native controls remain functional;
- current behavior and rendered output pass focused and full verification;
- macOS needs no automation-hover event synthesizer;
- no permanent dual-input path, runtime switch, or hidden compatibility surface remains.
