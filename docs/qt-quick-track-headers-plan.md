# Qt Quick track headers plan

## Status

Design complete; not implemented.

Open product or architecture decisions: none. Implementers fill function bodies and local test
helpers; they do not choose a second host, state owner, geometry source, role name, QML object name,
scroll rule, input priority, popup owner, cutover order, or check destination.

This plan converts the piano-roll track-header column from per-row `QWidget` painting and input
to the existing timeline `QQuickView`. It does not add another Quick window or `QQuickWidget`.

## Goal

Make Qt Quick own the visible track-header rows, activity meters, mute and solo controls, add-track
control, inline rename field, reorder marker, and raw row input. Keep track edits, selection rules,
voice actions, reorder rules, activity smoothing, and native popup menus in C++.

The migration succeeds only when:

- the existing timeline Quick scene renders the track-header column;
- no `TrackHeaderRow` or full-area `TrackHeaderPanel` widget remains;
- `trackheaderrow.cpp` and `trackheaderrow.h` are deleted;
- the separate `TrackActivityView` / `TrackActivityPresentation` overlay path is deleted;
- macOS uses the same retained Quick scene as the other platforms for header activity;
- the Quick header scrollbar and native menus remain functional;
- all current track-header behavior is preserved.

The native scrollbar implementation itself is intentionally replaced. The fixed Quick scroll
rules under **Scroll behavior** are the required behavior after cutover; an implementer does not
attempt to reproduce undocumented `QScrollArea` style internals or choose a different scroll feel.

The song list and voicegroup list remain QWidget-based. This plan does not convert either list.

## Current implementation

`SongView` creates a fixed-width `QScrollArea` beside the roll. `TrackHeaderPanel` fills that area
with one `TrackHeaderRow` widget for each used track and a native add-track button. Each row:

- paints its background, selection state, title, current instrument, and separator with
  `QPainter`;
- owns native mute and solo buttons;
- creates a native line editor during rename;
- receives selection, voice-click, double-click, context-menu, and reorder-drag input;
- asks `TrackHeaderPanel` to commit a reorder.

`TrackActivityPresentation` adds a second retained presentation over the rows. It uses a separate
`QQuickWidget` on non-macOS platforms and native Core Animation layers on macOS.

The main timeline already uses one retained `QQuickView`. Its host spans the whole `SongView`
because the ruler and other-events bands start at the left edge, but its mask omits the track-header
column. This plan adds the header column to that existing host and mask.

## Fixed design

### One Quick host

Extend `TimelineQuickView` and `TimelineCanvas.qml`. Do not create a
`TrackHeaderQuickView`, another `QQuickView`, or another `QQuickWidget`.

### Parent-owned geometry

`SongView` remains the sole owner of the header column rectangle and width. The header module does
not set outer geometry or request a size.

Replace the current `QScrollArea` with a `QSpacerItem` that reserves the existing header-column
width. No QWidget remains inside that slot.

The spacer is `m_headerSpacer`, created with fixed horizontal and expanding vertical size policy and
added to the existing `mid` layout before `m_rollStack`. `refreshGeometry()` calls
`m_headerSpacer->changeSize(m_geometry.trackHeaderWidth, 0, QSizePolicy::Fixed,
QSizePolicy::Expanding)`, gets `rollPane = m_rollStack->parentWidget()`, then calls
`rollPane->layout()->invalidate()` and `rollPane->layout()->activate()`. Do not invalidate the outer
`SongView` layout for this inner-row width change. In `resolveTimelineBandLayout()`, copy
`m_headerSpacer->geometry()` to `headerRect`, replace its top-left with
`rollPane->mapTo(this, headerRect.topLeft())`, and publish that translated rectangle as the header
band. `QSpacerItem` inherits the `geometry()` accessor from `QLayoutItem`; do not search the layout
by index. Delete `m_headerScroll`; do not keep both members.

`SongView::resolveTimelineBandLayout()` publishes the visible header-content rectangle as
`TimelineBand::TrackHeaders`. The rectangle includes the Quick scrollbar. Its `timelineOrigin`
value is zero and must not be used by the header module.

The scrollbar range is:

```text
0 .. max(0, contentHeight - viewportHeight)
```

where:

```text
contentHeight = (visibleTrackCount + (canAddTrack ? 1 : 0)) * rowHeight
```

`TrackHeaderModel::scrollY` is the only header scroll state. The QML scrollbar writes that property
directly, and the QML row container binds `y` to `-trackHeaderModel.scrollY`. SongView does not
mirror the value and no QWidget participates in scrolling.

### One header model

Replace `TrackHeaderPanel` and `TrackHeaderRow` with one non-widget model:

```cpp
class TrackHeaderModel final : public QAbstractListModel, public TimelineBandInteraction
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TrackHeaderModel)

    Q_PROPERTY(int rowHeight READ rowHeight NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int activityWidth READ activityWidth NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int scrollbarWidth READ scrollbarWidth NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int scrollbarMinimumThumbHeight READ scrollbarMinimumThumbHeight
                   NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int reorderIndicatorHeight READ reorderIndicatorHeight NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int separatorWidth READ separatorWidth NOTIFY geometryChanged FINAL)
    Q_PROPERTY(QRectF muteButtonRect READ muteButtonRect NOTIFY geometryChanged FINAL)
    Q_PROPERTY(QRectF soloButtonRect READ soloButtonRect NOTIFY geometryChanged FINAL)
    Q_PROPERTY(QRectF voiceLineRect READ voiceLineRect NOTIFY geometryChanged FINAL)
    Q_PROPERTY(QRectF renameEditorRect READ renameEditorRect NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int renamingTrack READ renamingTrack NOTIFY renameChanged FINAL)
    Q_PROPERTY(QString renameDraft READ renameDraft WRITE setRenameDraft NOTIFY renameChanged FINAL)
    Q_PROPERTY(QString renamePlaceholder READ renamePlaceholder NOTIFY renameChanged FINAL)
    Q_PROPERTY(qreal scrollY READ scrollY WRITE setScrollY NOTIFY scrollChanged FINAL)
    Q_PROPERTY(int contentHeight READ contentHeight NOTIFY geometryChanged FINAL)
    Q_PROPERTY(qreal maximumScrollY READ maximumScrollY NOTIFY geometryChanged FINAL)
    Q_PROPERTY(qreal viewportHeight READ viewportHeight NOTIFY geometryChanged FINAL)
    Q_PROPERTY(bool reorderIndicatorVisible READ reorderIndicatorVisible NOTIFY reorderChanged FINAL)
    Q_PROPERTY(qreal reorderIndicatorY READ reorderIndicatorY NOTIFY reorderChanged FINAL)
    Q_PROPERTY(bool toolTipVisible READ toolTipVisible NOTIFY toolTipChanged FINAL)
    Q_PROPERTY(QString toolTipText READ toolTipText NOTIFY toolTipChanged FINAL)
    Q_PROPERTY(QPointF toolTipPosition READ toolTipPosition NOTIFY toolTipChanged FINAL)
    Q_PROPERTY(QVariantMap appearance READ appearance NOTIFY appearanceChanged FINAL)

  public:
    enum Role : int {
        IsAddTrackRole = Qt::UserRole + 1,
        TrackRole,
        TitleRole,
        SubtitleRole,
        ToolTipRole,
        TitleRectRole,
        SubtitleRectRole,
        SelectedTitleOffsetRole,
        BaseColorRole,
        OverlayColorRole,
        TitleColorRole,
        SubtitleColorRole,
        TitleFontRole,
        SubtitleFontRole,
        MuteCheckedRole,
        SoloCheckedRole,
        MuteHoveredRole,
        MutePressedRole,
        SoloHoveredRole,
        SoloPressedRole,
        AddHoveredRole,
        AddPressedRole,
        VoiceHoveredRole,
        VoicePressedRole,
        ActivityDimColorRole,
        ActivityActiveColorRole,
        ActivityLeftHeightRole,
        ActivityRightHeightRole,
    };

    explicit TrackHeaderModel(SongView &owner, QObject *parent = nullptr);
    ~TrackHeaderModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void rebuild(const TrackActivity &activity, bool playing);
    void syncSelection();
    void syncVoices();
    void syncActivity(const TrackActivity &activity, bool playing);
    void syncMuteMask(uint32_t mask);
    void syncSoloMask(uint32_t mask);
    void syncAppearance();
    void beginRename(int track);
    Q_INVOKABLE void finishRename(bool commit, bool restoreRollFocus);
    void cancelRename();
    Q_INVOKABLE void activateMute(int track);
    Q_INVOKABLE void activateSolo(int track);
    Q_INVOKABLE void activateAddTrack();

    int rowHeight() const noexcept;
    int activityWidth() const noexcept;
    int scrollbarWidth() const noexcept;
    int scrollbarMinimumThumbHeight() const noexcept;
    int reorderIndicatorHeight() const noexcept;
    int separatorWidth() const noexcept;
    QRectF muteButtonRect() const;
    QRectF soloButtonRect() const;
    QRectF voiceLineRect() const;
    QRectF renameEditorRect() const;
    int contentHeight() const noexcept;
    int renamingTrack() const noexcept;
    QString renameDraft() const;
    void setRenameDraft(const QString &text);
    QString renamePlaceholder() const;
    qreal scrollY() const noexcept;
    qreal maximumScrollY() const noexcept;
    qreal viewportHeight() const noexcept;
    void setScrollY(qreal value);
    bool reorderIndicatorVisible() const noexcept;
    qreal reorderIndicatorY() const noexcept;
    bool toolTipVisible() const noexcept;
    QString toolTipText() const;
    QPointF toolTipPosition() const noexcept;
    QVariantMap appearance() const;
    void cancelTransientState();

    void attachInputHost(TimelineInputHost &host) override;
    void detachInputHost(TimelineInputHost &host) override;
    bool pointerPress(const TimelinePointerInput &input) override;
    bool pointerDoubleClick(const TimelinePointerInput &input) override;
    bool pointerMove(const TimelinePointerInput &input) override;
    bool pointerRelease(const TimelinePointerInput &input) override;
    void pointerLeave() override;
    bool wheel(const TimelineWheelInput &input) override;
    void inputCancelled(TimelineInputCancelReason reason) override;
    void hostEnvironmentChanged() override;

  signals:
    void geometryChanged();
    void renameChanged();
    void scrollChanged();
    void reorderChanged();
    void toolTipChanged();
    void appearanceChanged();

  private:
    enum class HitTarget : quint8 { None, Body, Voice, Mute, Solo, AddTrack };
    struct TrackHeaderRecord;
    struct PointerState;
    struct Geometry;

    int rowAt(qreal bandY) const;
    int trackAt(qreal bandY) const;
    qreal contentY(qreal bandY) const;
    QRectF rowLocalRect(const QRectF &rect, qreal bandY) const;
    HitTarget hitTarget(int row, const QPointF &bandPosition) const;
    void updatePointerVisuals(int row, HitTarget target, bool pressed);
    void clearPointerVisuals();
    bool scrollVertically(const TimelineWheelInput &input);
    void showContextMenu(int track, const QPointF &globalPosition);
    QString toolTipAt(const QPointF &bandPosition) const;
    void updateToolTip(const TimelinePointerInput &input);
    void clearToolTip();
    void beginReorder(int track, const QPointF &position);
    void updateReorder(const QPointF &position);
    void finishReorder(bool commit);
    std::optional<int> reorderTarget(int fromTrack, int dropSlot) const;
};
```

`appearance` is the one typed C++-to-QML color handoff for controls that used to inherit the
QWidget stylesheet. It contains exactly these `QColor` values:

| Key | Source |
| --- | --- |
| `buttonBackground` | `themes::Role::button_background` |
| `buttonText` | `themes::Role::button_text` |
| `buttonHoverBackground` | `themes::Role::button_hover_background` |
| `buttonHoverText` | `themes::Role::button_hover_text` |
| `buttonPressedBackground` | `themes::Role::button_pressed_background` |
| `buttonPressedText` | `themes::Role::button_pressed_text` |
| `buttonOutline` | `themes::Role::button_outline` |
| `focusOutline` | `themes::Role::focus_outline` |
| `muteCheckedBackground` | `themes::Role::track_mute_checked_background` |
| `muteCheckedText` | `themes::Role::track_mute_checked_text` |
| `soloCheckedBackground` | `themes::Role::track_solo_checked_background` |
| `soloCheckedText` | `themes::Role::track_solo_checked_text` |
| `inputBackground` | `themes::Role::input_background` |
| `inputText` | `themes::Role::input_text` |
| `inputOutline` | `themes::Role::input_outline` |
| `scrollbarHandle` | `themes::Role::scrollbar_handle` |
| `scrollbarHandleHover` | `themes::Role::scrollbar_handle_hover_background` |
| `toolTipBackground` | `themes::Role::tooltip_background` |
| `toolTipText` | `themes::Role::tooltip_text` |
| `toolTipOutline` | `themes::Role::tooltip_outline` |
| `reorderIndicator` | attached host palette `QPalette::Highlight` |

The list-position scrollbar track stays transparent, matching the existing
`listPositionIndicator`. `syncAppearance()` resolves this map and the row colors, emits
`appearanceChanged` only when the map changed, then emits only the row color roles that changed.
QML does not hard-code theme colors.

The role names are fixed; do not invent shorter aliases in QML:

| Role | QML name |
| --- | --- |
| `IsAddTrackRole` | `isAddTrack` |
| `TrackRole` | `track` |
| `TitleRole` | `title` |
| `SubtitleRole` | `subtitle` |
| `ToolTipRole` | `toolTip` |
| `TitleRectRole` | `titleRect` |
| `SubtitleRectRole` | `subtitleRect` |
| `SelectedTitleOffsetRole` | `selectedTitleOffset` |
| `BaseColorRole` | `baseColor` |
| `OverlayColorRole` | `overlayColor` |
| `TitleColorRole` | `titleColor` |
| `SubtitleColorRole` | `subtitleColor` |
| `TitleFontRole` | `titleFont` |
| `SubtitleFontRole` | `subtitleFont` |
| `MuteCheckedRole` | `muteChecked` |
| `SoloCheckedRole` | `soloChecked` |
| `MuteHoveredRole` | `muteHovered` |
| `MutePressedRole` | `mutePressed` |
| `SoloHoveredRole` | `soloHovered` |
| `SoloPressedRole` | `soloPressed` |
| `AddHoveredRole` | `addHovered` |
| `AddPressedRole` | `addPressed` |
| `VoiceHoveredRole` | `voiceHovered` |
| `VoicePressedRole` | `voicePressed` |
| `ActivityDimColorRole` | `activityDimColor` |
| `ActivityActiveColorRole` | `activityActiveColor` |
| `ActivityLeftHeightRole` | `activityLeftHeight` |
| `ActivityRightHeightRole` | `activityRightHeight` |

`IsAddTrackRole` returns a bool. `TrackRole` returns the engine track number for a track row and
`-1` for the add row.

The exact private row cache is:

```cpp
struct TrackHeaderRecord {
    bool isAddTrack = false;
    int track = -1;
    QString title;
    QString subtitle;
    QString toolTip;
    QRectF titleRect;
    QRectF subtitleRect;
    QPointF selectedTitleOffset;
    QColor baseColor;
    QColor overlayColor;
    QColor titleColor;
    QColor subtitleColor;
    QFont titleFont;
    QFont subtitleFont;
    bool muted = false;
    bool soloed = false;
    QColor activityDimColor;
    QColor activityActiveColor;
    track_activity_render::State activityState;
    track_activity_render::RenderKey activityRenderKey{-1, -1, false};
    qreal activityLeftHeight = 0.0;
    qreal activityRightHeight = 0.0;
};
```

The exact pointer state is:

```cpp
struct PointerState {
    int hoverRow = -1;
    HitTarget hoverTarget = HitTarget::None;
    int pressedRow = -1;
    int pressedTrack = -1;
    HitTarget pressedTarget = HitTarget::None;
    QPointF pressPosition;
    bool dragArmed = false;
    bool dragging = false;
};
```
`VoiceHoveredRole` is true only for a non-add track row whose current hover target is
`HitTarget::Voice`; `VoicePressedRole` additionally requires its current pressed target to be
`HitTarget::Voice`. They do not add a second per-record interaction cache.


`Geometry::resolve()` carries the fixed row and replacement-control geometry without recomputing it
in QML:

```cpp
struct Geometry {
    int rowHeight;
    int activityWidth;
    int buttonExtent;
    int buttonColumnWidth;
    int textLeft;
    int renameEditorLeft;
    int renameEditorTop;
    int renameEditorRight;
    int renameEditorHeight;
    int reorderIndicatorHeight;
    int separatorWidth;
    int scrollbarWidth;
    int scrollbarMinimumThumbHeight;

    static Geometry resolve();
};
```

The model storage is also fixed:

```cpp
SongView &m_owner;
TimelineInputHost *m_inputHost = nullptr;
std::vector<TrackHeaderRecord> m_rows;
Geometry m_geometry;
PointerState m_pointer;
QFont m_normalTitleFont;
QFont m_boldTitleFont;
QFont m_subtitleFont;
QFontMetrics m_normalTitleMetrics{QFont{}};
QFontMetrics m_boldTitleMetrics{QFont{}};
QFontMetrics m_subtitleMetrics{QFont{}};
std::optional<layout::TwoLineTextLayout> m_textLayout;
QString m_renameDraft;
QString m_renamePlaceholder;
int m_renamingTrack = -1;
bool m_finishingRename = false;
qreal m_scrollY = 0.0;
bool m_reorderIndicatorVisible = false;
qreal m_reorderIndicatorY = 0.0;
bool m_toolTipVisible = false;
QString m_toolTipText;
QPointF m_toolTipPosition;
QVariantMap m_appearance;
```

Do not store a second viewport height, content height, mute mask, solo mask, selected-track set,
document pointer, or activity model. Derive those values from the input host, rows, or `SongView`.

`trackheadermodel.h` includes the list-model, timeline-input, activity-render, and value-type headers
needed by this declaration. It does not include `QWidget`, `QPainter`, `QToolButton`, `QLineEdit`, or
`QScrollArea`. Define `TrackHeaderRecord`, `PointerState`, and `Geometry` in the header: `m_rows`,
`m_geometry`, and `m_pointer` own those types by value and therefore require complete definitions.
Keep the destructor out of line in `trackheadermodel.cpp`.

`Geometry::resolve()` uses these fixed sources:

```text
rowHeight                  = layout::fontPx(4.0)
activityWidth              = layout::space(Space::One)
buttonExtent               = layout::fontPx(1.5)
buttonColumnWidth          = layout::fontPx(2.0)
textLeft                   = layout::fontPx(5.0 / 6.0)
renameEditorLeft           = layout::fontPx(0.5)
renameEditorTop            = layout::fontPx(1.0 / 6.0)
renameEditorRight          = layout::fontPx(8.0 / 3.0)
renameEditorHeight         = layout::fontPx(5.0 / 3.0)
reorderIndicatorHeight     = layout::fontPx(0.25)
separatorWidth             = layout::singlePixel()
scrollbarWidth             = layout::space(Space::Two)
scrollbarMinimumThumbHeight = layout::space(Space::Eight)
```

The button, text, and rename fields are the existing `TrackHeaderRow::Geometry` values.
`voiceLineRect` deliberately derives from the completed subtitle layout below, rather than retaining
a second approximate voice-line geometry. `rowHeight` is the existing `resolvedHeight()` value.
`reorderIndicatorHeight` comes from `TrackHeaderPanel::Geometry`, `activityWidth` comes from the
current `TrackActivityView::setFixedWidth(space(One))`, and `separatorWidth` is the current painted
bottom line. `scrollbarWidth` and `scrollbarMinimumThumbHeight` are new fixed Quick-scrollbar
choices, using the same `Space::Two` width and `Space::Eight` minimum length that currently style
`QScrollBar#listPositionIndicator`; do not describe them as fields of the old row geometry.

The row width is the input-host width. Resolve the three fixed hit/paint rectangles in C++ with this
exact math, where `buttonGap = max(0, rowHeight - separatorWidth - 2 * buttonExtent)`, `topGap =
buttonGap / 3`, `middleGap = buttonGap / 3`, and any integer remainder stays in the unused bottom
gap:

```text
buttonX          = rowWidth - space(Space::One) - buttonExtent
muteButtonRect   = {buttonX, topGap, buttonExtent, buttonExtent}
soloButtonRect   = {buttonX, topGap + buttonExtent + middleGap, buttonExtent, buttonExtent}
renameEditorRect = {renameEditorLeft, renameEditorTop,
                    rowWidth - renameEditorRight, renameEditorHeight}
```

This is the deterministic Quick replacement for the current three equal layout stretches and
one-pixel outer bottom margin; an implementer does not ask Qt to recreate the deleted widget
layout. The `*Right` value in the rename formula is a width deduction, not a right-edge coordinate.
Compute title and subtitle rectangles with the current `layout::twoLineText(..., Space::Half)` helper
and the width `rowWidth - buttonColumnWidth - textLeft - space(Space::One)`. `voiceLineRect` is the
same completed secondary/subtitle rectangle used by `SubtitleRectRole`: it is the visible
current-instrument line and the sole voice hit target. `VoiceHoveredRole` and `VoicePressedRole`
expose its pointer state so QML gives the target visible feedback; they do not change the existing
select, reveal, or picker routing. Compute selected-title centering with
`typography::glyphCenteringOffset()` exactly as today. QML receives the finished rectangles, fonts,
and offsets; it does not repeat any font or layout formula.

Resolve row presentation exactly as `TrackHeaderRow::paintEvent()` does today:

- normal title font is `inputHost.font()`; primary title font is
  `typography::bold(inputHost.font())`; subtitle font is
  `typography::caption(inputHost.font())`;
- the normal base is `inputHost.palette().color(QPalette::Window)` forced to alpha 255;
- a primary row uses `themes::Role::song_view_track_header_selection` as its opaque base, has no
  overlay, and uses `themes::Role::song_view_track_header_selection_text` for both text roles;
- an in-scope non-primary row keeps the normal base and uses
  `songview::detail::trackHeaderAlsoSelectedColor()` as its overlay;
- an unselected row has no overlay and uses `themes::Role::song_view_primary_text` and
  `themes::Role::song_view_secondary_text` for title and subtitle;
- an over-budget row mixes each resolved text color toward the resolved backdrop with
  `mixTowardOklab`: mix `0.35` for primary and `0.6` otherwise;
- `SelectedTitleOffsetRole` is `typography::glyphCenteringOffset(normalTitleFont,
  boldTitleFont, visibleTitle)` only for the primary row and is empty otherwise.

Resolve `normalTitleFont`, `boldTitleFont`, `subtitleFont`, and their `QFontMetrics` once when the
model attaches to its input host. Store them for the model lifetime. Selection only chooses between
the stored normal and bold title fonts. The model does not subscribe to font-change events or
invalidate font metrics after attachment.

The model caches those finished values in `TrackHeaderRecord`; QML does not re-resolve selection,
budget state, fonts, colors, or text metrics.

`TrackHeaderModel` keeps records in visible row order. Track numbers remain the domain identity;
QML row indexes never enter `SongDocument` calls.

### QML stays presentational

Append `TrackHeaders` immediately before `TimelineBand::Count`; do not reorder the six existing
values. Add `trackHeadersBandRect` and `trackHeadersBandVisible` to the root QML properties and add
`TimelineBandQmlProperties{TimelineBand::TrackHeaders, "trackHeadersBandRect",
"trackHeadersBandVisible"}` to `kTimelineBandQmlProperties`.

Add one `TimelineSceneBand` for `TrackHeaders` to `TimelineCanvas.qml`. Its child order and input
bounds are fixed:

- a clipped viewport that fills the band;
- a row area with width `band.width - trackHeaderModel.scrollbarWidth`;
- one clipped row container inside that area, translated by `-trackHeaderModel.scrollY`;
- one `Repeater` over `trackHeaderModel` inside the translated container;
- background and selection rectangles;
- title and subtitle `Text` items;
- the stereo activity strip;
- visual mute and solo controls;
- the add-track row;
- the reorder marker;
- a `TextInput` shown only for `renamingTrack`, above the row input item;
- a Quick scrollbar built from Qt Quick items whose thumb position and size bind to the model's
  viewport and scroll properties, above and to the right of the row input item;
- one `TimelineInputItem` filling only the visible row area to the left of the Quick scrollbar;
- a tooltip item at the root overlay level, outside the translated row container.

The row input item never overlaps the scrollbar. The rename field accepts text and key input while
visible; the row input stays behind it. The tooltip does not accept input. The scrollbar handlers
accept input only inside the scrollbar column. Do not depend on declaration order alone: set the
rename field and scrollbar above the row input with explicit `z` values.

Render each track delegate with these fixed rules:

- fill the row with `baseColor`, then draw `overlayColor` only when it is valid;
- draw the bottom separator at `rowHeight - separatorWidth`;
- place the activity strip at `x == 0`, with width `activityWidth` and height
  `rowHeight - separatorWidth`; fill it with `activityDimColor`, then bottom-anchor equal-width left
  and right bars using the two activity-height roles;
- draw title and subtitle from their supplied rectangles, fonts, colors, and selected-title offset;
- place the M and S controls in the supplied rects and use the `appearance` state colors. Hover wins
  over rest, checked wins over hover, and pressed uses the checked color for Solo and the generic
  pressed color for Mute, matching the current stylesheet;
- draw the add row as one full-width button in the row area, with the normal, hover, pressed, text,
  and outline colors from `appearance`;
- draw the reorder marker from `reorderIndicatorY` across the row area only.

The model supplies title and subtitle text already elided with the matching `QFontMetrics` and the
resolved text width. Both QML `Text` items use `Text.PlainText`, `Text.NativeRendering`, one line,
`Text.ElideNone`, and clipping. QML does not elide or remeasure the strings.

Position `timelineTrackHeaderToolTip` at
`x = trackHeadersBandRect.x + trackHeaderModel.toolTipPosition.x` and
`y = trackHeadersBandRect.y + trackHeaderModel.toolTipPosition.y`, then clamp its painted rectangle
to the QML root bounds. It uses the tooltip colors from `appearance` and never changes the logical
pointer position stored by the model.

QML may bind roles and route rename text/accept/cancel signals. On `TextInput::textEdited`, call
`setRenameDraft(text)` so a reorder or other structural action can commit the current draft without
reading a QML object. It must not choose tracks, edit the document, compute reorder targets, resolve
voices, or smooth activity.

The row-area `TimelineInputItem` is the only raw row pointer path. `TrackHeaderModel` hit-tests rows,
voice text, mute, solo, and add-track rectangles from the same resolved geometry values published
to QML. Do not add per-row `MouseArea` behavior.

The scrollbar uses a `DragHandler`, `TapHandler`, and `WheelHandler` in QML. These handlers only
write `TrackHeaderModel::scrollY`; they do not choose tracks or edit the song. Wheel input over the
row area reaches `TrackHeaderModel::wheel()` and updates the same property. Do not add the
`QtQuick.Controls` dependency for this one thin scrollbar.

QML exposes separate accessible mute, solo, add-track, and rename items. Their accessibility
actions call narrow model methods; pointer input still uses the row-area input item.

`SongView` owns `TrackHeaderModel` as a direct child. `TimelineQuickView` takes a
`TrackHeaderModel &` constructor argument, publishes it once with
`rootContext()->setContextProperty(QStringLiteral("trackHeaderModel"), &headers)`, finds
`timelineTrackHeadersInput`, and attaches that item to the model. Do not add the model to
`TimelineQuickScene`; that object remains the owner of dense timeline geometry and timeline text
models only.

The model constructor sets QObject name `trackHeaderModel`; the context-property name is the same
string. Checks may find the typed child by this name, but production code keeps the direct pointer.

The QML object names are fixed:

- band: `timelineQuickTrackHeaders`;
- row input: `timelineTrackHeadersInput`;
- row repeater: `timelineTrackHeaderRows`;
- scrollbar track: `timelineTrackHeaderScrollBar`;
- scrollbar thumb: `timelineTrackHeaderScrollThumb`;
- rename field: `timelineTrackHeaderRename`;
- reorder marker: `timelineTrackHeaderReorderMarker`;
- tooltip: `timelineTrackHeaderToolTip`.

### Construction, attachment, and teardown

Use this order; do not rely on QObject destruction order alone:

1. `SongView` creates `m_headers = new TrackHeaderModel(*this, this)` before it creates
   `TimelineQuickView`.
2. Add `TrackHeaderModel &trackHeaders` immediately before `SongView &songView` in the
   `TimelineQuickView` constructor and store it as `QPointer<TrackHeaderModel> m_trackHeaders`.
3. Before `setSource()`, publish `trackHeaderModel` beside the existing `timelineQuickView` and
   `timelineScene` context properties.
4. After QML reaches `QQuickView::Ready`, find `timelineTrackHeadersInput`, call
   `setInteraction(m_trackHeaders)`, and store the item in the `TrackHeaders` slot of
   `m_inputItems`.
5. `synchronizeTimelineBandLayout()` remains the first production geometry handoff after the Quick
   view and playhead exist. `publishTimelineBandLayout()` publishes the header rect and includes it
   in the Quick-window mask through the existing band loop.
6. `SongView::~SongView()` detaches `TimelineBand::TrackHeaders` with the other bands before member
   teardown. `TimelineQuickView::~TimelineQuickView()` keeps its existing all-slot detach loop.
7. Keep header cancellation separate from `SongView::cancelActiveInteractions()`, because
   `trackHeaderClicked()` calls that method during a live header press. Retarget the existing
   `m_headers->cancelTransientState()` calls in `prepareForSongReplacement()` and
   `cancelTransientInput()` to the model. That method cancels reorder, cancels rename, clears
   tooltip state, and releases the input-host pointer grab; callers do not reach into its fields.

Set the context property before QML loads. Never look up the model through `TimelineQuickScene`,
QML parent walking, or an object-name search.

Match the existing interaction attach contract: `attachInputHost()` asserts that there is no other
host, stores the pointer, resolves geometry, fixed fonts and metrics, and theme appearance, clamps
scroll, and publishes the current accessibility description. `detachInputHost()` asserts identity,
cancels transient state, clears the host cursor, and nulls the pointer. Every host-dependent getter
asserts a live host instead of
falling back to guessed geometry, except for QML-readable startup values: before attachment,
`viewportHeight()` and `maximumScrollY()` both return `0.0`, and activity-height roles return their
stored zero values. QML evaluates bindings while `setSource()` is loading, before C++ can find and
attach `timelineTrackHeadersInput`; these zero values are the only allowed unattached state. After
attachment, `attachInputHost()` emits `geometryChanged`, resolves every row rectangle against the
live host width, and replays stored activity states with the live DPR. Methods that perform input,
focus, cursor, or coordinate mapping still assert a live host.

### Native popups that remain

Keep these separate native popup surfaces:

- context menus;
- the voice picker and other dialogs opened by a header action.

Native menus use `TimelineInputHost::mapToGlobal()` for placement and remain parented to
`SongView`. They do not own header geometry or stay synchronized per frame.

The scrollbar, mute, solo, add-track, inline rename, row drawing, activity meters, and reorder
marker do not remain QWidget surfaces.

### Action routing

Keep the current `SongView` actions; the model does not duplicate their rules:

| Header action | C++ destination |
| --- | --- |
| Select or extend track scope | `SongView::trackHeaderClicked(track, modifiers)` |
| Reveal voice | `SongView::revealTrackVoice(track)` |
| Change voice | `queueHeaderMutation([owner, track] { owner->editTrackVoice(track); })` |
| Commit rename | `SongView::commitTrackRename(track, draft)` |
| Duplicate track | `queueHeaderMutation([owner, track] { owner->duplicateTrack(track); })` |
| Delete track | `queueHeaderMutation([owner, track] { owner->deleteTrack(track); })` |
| Add track | `queueHeaderMutation([owner] { owner->addTrack(); })` |
| Reorder track | `queueHeaderMutation([owner, from, to] { owner->moveTrack(from, to); })` |
| Toggle mute | `SongView::setTrackMute(track, !owner.trackMuted(track))` |
| Toggle solo | `SongView::setTrackSolo(track, !owner.trackSoloed(track))` |

Replace the `TrackHeaderPanel` friend declaration and forward declaration in `songview.h` with
`TrackHeaderModel`. Do not widen the listed `SongView` methods merely to avoid that friend.

The sole QWidget-to-Quick boundary is the existing `SongView` parent layout publishing the header
rectangle when layout changes. There is no per-frame QWidget geometry read, event forwarding,
scroll mirroring, or duplicate painted surface. Removing that last rectangle handoff would require
converting the whole `SongView` container, which is outside this plan.

### Activity rendering

Keep `TrackActivity`, `TrackActivityLevel`, and `track_activity_render`; they own smoothing and
physical-pixel height policy.

Move the retained activity roles into `TrackHeaderModel`. One `syncActivity()` call:

1. builds `track_activity_render::State{activity.intensity(track), playing}` for each track row;
2. computes its `RenderKey` with `rowHeight - separatorWidth` and the input-host DPR;
3. updates the stored state for every changed input, but recomputes the two logical heights only
   when the physical key changed;
4. computes those heights with `track_activity_render::snappedHeight()`;
5. emits at most one `dataChanged` span with only the two height roles.

During rebuild, derive dim and active colors once with
`track_activity_render::colors(SongView::trackColor(track))`. On DPR or row-height change, replay the
stored activity states through the same render-key path; do not ask the audio engine for another
sample.

The existing timeline Quick scene draws the meter rectangles. Delete the separate Quick model,
Quick widget, presentation facade, geometry observers, and macOS Core Animation backend after the
new path passes the existing meter checks.

### Model update rules

The model uses a reset only when the ordered set of used tracks or the add-track row changes.
Everything else updates retained rows:

| Source change | Model action | Roles/signals |
| --- | --- | --- |
| Song/document replacement | rebuild; compare ordered row identities first | one reset only if identities changed, otherwise bounded changed roles |
| Track add/delete/reorder | rebuild ordered records | one model reset |
| Primary or scoped selection | compare every track record | changed title, style, font, rect, and offset roles only |
| Edit cursor/playhead changes voice | compare `currentProgram(track)` | subtitle and tooltip roles only |
| Mute mask | compare affected bits | `MuteCheckedRole` only |
| Solo mask | compare affected bits | `SoloCheckedRole` only |
| Keymap bindings | recompute a visible Mute/Solo tooltip from the stored pointer position | `toolTipChanged` or none |
| Theme or palette | resolve the appearance map and row colors | `appearanceChanged`, then bounded color-role `dataChanged` |
| DPR | replay activity render keys and physical heights | one bounded height-role `dataChanged` or none |
| Activity tick | compare physical render keys | one bounded height-role `dataChanged` or none |
| Viewport height/content height | clamp the one `scrollY` value | `geometryChanged`, then `scrollChanged` if clamped |
| Pointer hover/press | compare old and new row targets | eight pointer-state roles over affected rows only |

Connect `SongView::muteMaskChanged`, `SongView::soloMaskChanged`, and
`keymap::Registry::bindingsChanged` once in the model constructor. Existing `SongView` call sites
continue to call `rebuild`, `syncSelection`, `syncVoices`, and `syncActivity`; they change only from
the old panel pointer to the new model pointer.

The add-track row is the last model record only when `SongDocument::canAddTrack()` is true. It has
`isAddTrack == true`, `track == -1`, no activity, and no mute or solo state. `contentHeight()` is
always `rowCount() * rowHeight()`; do not keep a separate add-row height.

### Scroll behavior

The model derives `viewportHeight()` from its attached input host. Because the input item fills the
row area but has the full band height, its bounds are the one viewport source. `maximumScrollY()` is
`max(0, contentHeight() - viewportHeight())`. `setScrollY()` clamps to that range before comparing
and emitting. Rebuild, resize, and host attach all re-clamp the current value; they do not reset a
still-valid user position.

The Quick scrollbar uses these formulas:

```text
thumbHeight = max(minimumThumbHeight,
                  viewportHeight / max(contentHeight, viewportHeight) * viewportHeight)
thumbTravel = viewportHeight - thumbHeight
thumbY      = maximumScrollY == 0 ? 0 : scrollY / maximumScrollY * thumbTravel
```

Hide the track and thumb when `maximumScrollY == 0`. A track click pages by one viewport toward the
click. Thumb dragging maps `thumbY / thumbTravel` back to `scrollY / maximumScrollY`. Wheel behavior
is fixed in `scrollVertically()`: reject zero or horizontal-dominant input; use `pixelDelta.y()` for
pixel wheels and `angleDelta.y() / 120.0 * rowHeight()` for rotary wheels; add the delta when
`inverted` and subtract it otherwise; then pass the result to `setScrollY()`. Momentum pixel events
use the same path. A wheel event with a usable vertical delta returns true even when already at the
limit. Extract no new generic scrolling layer.
Every path that re-clamps scroll also clears a visible header tooltip, even when the value was already
in range.


The row under a pointer is:

```text
contentY = pointerBandY + scrollY
row      = floor(contentY / rowHeight)
```

Reject negative or out-of-range rows. Convert to row-local Y with
`contentY - row * rowHeight`. All button, voice-line, and rename hit tests use row-local
coordinates.

### Pointer priority and gesture state

For a press in the row input area, use this order:

1. If the target is the add-track row, arm it only for a left press; consume every other button
   without selecting track `-1`, opening a menu, or starting a drag.
2. If the target is a mute button and the button is left, arm that button and stop.
3. If the target is a solo button and the button is left, arm that button and stop.
4. If the button is right and `input.buttons` also contains the left button, stop without opening a
   menu; keep the current pointer state until the non-left release cancels it below.
5. If the button is right, call `SongView::selectTrack(track)`, open its context menu at
   `input.globalPosition`, and stop. Do not call `trackHeaderClicked()` for right-click selection;
   right click collapses the selection scope exactly as the current `showContextMenu()` does.
6. Otherwise call `SongView::trackHeaderClicked(track, modifiers)`.
7. Arm reorder and voice-click only for an unmodified left press with a live document.

On release, activate Add, Mute, or Solo only when the left release is over the same target in the
same row as its press; otherwise clear the pressed state without an action. This retains native
button click semantics and supplies the `*PressedRole` values. Accessible activation calls the same
narrow `activate*` methods directly.

For a double-click, reject add, mute, and solo targets. Select the track first. Open the voice picker
only when the double-click lands in `voiceLineRect`; otherwise call `beginRename(track)`. A completed
single voice-line click reveals the voice only when the release remains in the same track's voice
rectangle and no drag started.

Do not arm reorder when the press starts on mute, solo, add-track, or the Quick scrollbar. Start the
drag only after the current `QApplication::startDragDistance()` threshold. While dragging, compute
the drop slot from row centers in content coordinates and expose the marker in band coordinates as
`dropSlot * rowHeight - scrollY`. Clamp the marker to the visible band in QML; do not change the
logical drop slot when clipped.

`pointerRelease()` commits only a left-button reorder. Any other release, pointer ungrab, focus
loss, view hide, window deactivation, song rebuild, or model reset calls `finishReorder(false)` and
clears every field in `PointerState`. Hover movement compares the old and new row and hit target,
then emits the eight hover/pressed roles only for the affected row span. `pointerLeave()` clears
hover and tooltip state unless a pointer grab keeps an active reorder alive; it never leaves a
control in a pressed visual state after the grab ends.

### Rename sequence

There is one rename owner: `TrackHeaderModel::m_renamingTrack`. Use this sequence:

1. `beginRename(track)` validates the live document and track, stores the current name in
   `m_renameDraft` and the fallback in `m_renamePlaceholder`, emits `renameChanged`, and makes no
   document edit.
2. QML makes `timelineTrackHeaderRename` visible in `renameEditorRect`, copies `renameDraft`, calls
   `forceActiveFocus(Qt::PopupFocusReason)`, and selects all text.
3. Every user text edit calls `setRenameDraft(text)`; programmatic initialization does not write the
   value back.
4. Return calls `finishRename(true, true)`; Escape calls `finishRename(false, true)`.
5. Losing active focus calls `finishRename(true, false)` only if the same rename is still
   open.
6. `finishRename` copies the track and draft, clears `m_renamingTrack` before it calls
   `SongView::commitTrackRename`, so the
   resulting rebuild cannot commit twice.
7. Structural rebuilds call `cancelRename()` unless reorder is committing it first.
8. Reorder calls `finishRename(true, false)`, queues the rename, then queues the move;
   the existing event order keeps the captured track numbers valid.

Use one `m_finishingRename` guard for Return/focus-loss reentry. Do not add a hidden `QLineEdit` or
read the draft back by finding or invoking the QML `TextInput`.

### Tooltip and popup sequence

Header tooltips render in the existing Quick scene. Pointer hover sets `toolTipText`,
`toolTipPosition`, and `toolTipVisible`; QML draws the root-clamped tooltip above the rows. Leave,
press, scroll, rebuild, and input cancellation hide it. This avoids a QWidget tooltip crossing.

Context menus and voice dialogs remain native because they are short-lived application popups, not
part of the retained header surface. `showContextMenu()` creates a stack-owned `QMenu` parented to
`SongView`, maps the Quick position through the input host, and connects actions to guarded
`QPointer<SongView>` callbacks. Voice, duplicate, delete, and add remain queued through
`SongView::queueHeaderMutation`; Show voice is immediate. Rename starts only after `QMenu::exec()`
returns. No action captures a model row index.

### Input and edit rules to preserve

- Plain click selects the track.
- Control/Command and Shift selection keep their current meanings through
  `SongView::trackHeaderClicked()`.
- Mute and solo change only their matching masks.
- A single click on the voice line selects the track and reveals its current voice.
- A double-click on the voice line selects the track and opens the voice picker.
- A double-click elsewhere starts inline rename.
- Rename Return commits; Escape cancels; focus loss commits.
- Right-click selects the track and opens Change voice, Show voice, Rename, Duplicate, and Delete.
- A plain left drag reorders tracks after `QApplication::startDragDistance()`.
- The two no-op reorder slots beside the source row remain no-ops.
- A non-left release during reorder cancels it.
- Reorder commits any open rename first, then queues the move.
- Rebuild, view hide, window deactivation, focus loss, and pointer ungrab cancel live drag state.
- Loading gates and native popup dismissal keep their current behavior.
- Header tooltips and live key-binding hints remain current after shortcut changes.

## Implementation phases

### Phase 0: Freeze the baseline

Record the base commit and dirty state. Preserve the existing move of
`docs/qt-quick-timeline-input-plan.md` into `docs/old` without editing it.

Build checks, then run the current header and activity coverage:

- `trackactivitymetercheck`
- `rollwindowingcheck`
- `editor-drawer`
- `host-integration`
- `mainwindow-routing`
- the track-header sections in `rollcheck`, `rollcheckdrawer`, and `vgsavecheck`

The known right-drag selection-ring pixel assertion is not part of this work and remains unchanged.

### Phase 1: Build the replacement without a production dual path

1. Append `TimelineBand::TrackHeaders` before `Count`, extend every Count-sized array, and add the
   fixed QML rect/visibility property entry. Update `hostcheck.cpp`'s fixed band-property table from
   six entries to seven in the same change, while leaving the production header geometry null.
2. Add `TrackHeaderModel`, its exact roles, properties, helpers, and normalized input methods.
3. Add the header QML object tree to `TimelineCanvas.qml`, initially with
   `trackHeadersBandVisible == false` because production does not publish the band yet.
4. Register `trackHeaderModel` as the fixed root-context name and locate the fixed QML object names.
5. Add `src/checks/trackheaderquickcheck.cpp`. Register `runTrackHeaderQuickCheck()` in
   `src/checks/fwd.hpp`, `src/checks/checkcatalog.cpp`, and `CMakeLists.txt` under the check name
   `trackheaderquickcheck`, using the same Route 101 decomp fixture and
   `Windowing::WindowSystem` setting as `rollcheck`.
6. In that one check, cover model rebuild, selection, voice, mute/solo, activity, scrolling, pointer
   priority, reorder targeting, rename state, tooltip state, and cancellation through public model
   and input APIs.
7. In the same check, take a copy of `SongView::timelineBandLayout()`, supply only a
   `TrackHeaders` test rectangle to `TimelineQuickView::setBandLayout()`, process the queued layout
   publication, and capture `timelineQuickTrackHeaders`. Do not add a test-only production switch.

Do not hide the old widgets under a live Quick header, forward widget events into the model, add a
feature flag, or keep two production header models synchronized.

Compare isolated Quick captures with the current header for normal, selected, multi-selected,
over-budget, muted, soloed, playing activity, paused activity, long elided names, add-track, rename,
and reorder-marker states.

### Phase 2: Make one atomic production cutover

Make these changes in one slice; do not leave a mixed production state between them:

1. Replace the `QScrollArea` in `SongView` with the fixed-width spacer.
2. Publish the full header rectangle from `resolveTimelineBandLayout()`.
3. Pass `TrackHeaderModel &` into `TimelineQuickView`, expose it as `trackHeaderModel`, find
   `timelineTrackHeadersInput`, and attach it.
4. Make the Quick band visible, including its Quick scrollbar, rename field, tooltip, and reorder
   marker.
5. Retarget every `SongView` header call site from `TrackHeaderPanel` to `TrackHeaderModel`.
6. Retarget widget-based checks to the model and `timelineTrackHeadersInput` before deleting their
   old lookup helpers.
7. Delete `TrackHeaderRow`, `TrackHeaderPanel`, the native header scrollbar, and the add button.
8. Delete `TrackActivityView`, `TrackActivityPresentation`, the macOS activity backend, their QML,
   their private facade, and their CMake entries.
9. Remove the `QWidget#trackHeaderPanel` rules from `trackHeaderStyleSheet()` in
   `themeruntime.cpp`. Rename the remaining function to `polyphonyStyleSheet()` because its only
   remaining rules style the polyphony labels, and update `colorStyleSheet()` to call that name.
10. Update comments in `trackvoiceops.cpp` and `SongView` that still say a header widget, row, or
    panel rebuild owns the operation.

The cutover is complete only when the app builds with no old header or activity presentation path.
Do not leave hidden, transparent, disabled, or fallback row widgets behind.

### Phase 3: Migrate activity and integration checks

1. Retarget `trackactivitymetercheck` to `TrackHeaderModel` and the existing timeline Quick
   framebuffer.
2. Prove unchanged activity updates emit no model notification.
3. Prove a physical-pixel height change emits one bounded notification.
4. Prove stereo levels, paused fill, cap policy, DPR changes, and model rebuilds still render.
5. Replace `rollcheckwindowing` row-widget presence assertions with ordered model-record and Quick
   geometry assertions.
6. Replace `rollcheckdrawer` `QApplication::widgetAt` header assertions with real
   `QQuickWindow` input delivery and resulting track selection.
7. Replace `vgsavecheck`'s row-lifetime test with a Quick press that triggers the same queued
   structural change and proves the attached model survives and accepts the next header press.
8. Keep existing behavior coverage for track selection, voice reveal/pick, rename, duplicate,
   delete, add, reorder, mute, solo, tooltips, scrolling, and loading gates.
9. Rewrite `rollcheck/header_reconciliation.cpp` around model signals: unchanged content causes no
   reset, non-structural updates retain rows and emit bounded role changes, structural edits cause
   one reset, the add row stays last, and an open rename cancels on replacement. Do not preserve
   QWidget object-identity assertions after the QObjects cease to exist.

### Phase 4: Cleanup and full verification

Delete all widget-only geometry, event, paint, rename-editor, and activity-overlay code. Exact
searches must find no production reference to:

- `TrackHeaderRow`
- `trackHeaderRow`
- `TrackActivityView`
- `TrackActivityPresentation`
- `PORYDAW_FORCE_QUICK_TRACK_ACTIVITY`
- `QPainter` in the track-header module

Run formatting, the app and checks builds, all focused checks from Phase 0, and the full verify
suite. Also inspect the app on a real macOS display for:

- text and meter alignment;
- header scrolling;
- Quick scrollbar input, wheel scrolling, track clicks beside the scrollbar, and thumb sizing;
- mute and solo;
- rename focus;
- context-menu placement;
- drag reorder;
- activity while playing and paused;
- switching songs and tabs.

## File map

### Modify

- `src/ui/songview.cpp`
- `src/ui/songview.h`
- `src/ui/songview/timelinebandlayout.h`
- `src/ui/songview/quick/timelinequickview.cpp`
- `src/ui/songview/quick/timelinequickview.h`
- `src/ui/songview/quick/TimelineCanvas.qml`
- `src/ui/songview/trackvoiceops.cpp`
- `src/ui/theme/themeruntime.cpp`
- `src/checks/fwd.hpp`
- `src/checks/checkcatalog.cpp`
- `src/checks/hostcheck.cpp`
- `src/checks/trackactivitymetercheck.cpp`
- `src/checks/rollcheck/header_reconciliation.cpp`
- `src/checks/rollcheck/keyboard.cpp`
- `src/checks/rollcheck/presentation.cpp`
- `src/checks/rollcheck/remap.cpp`
- `src/checks/rollcheckwindowing.cpp`
- `src/checks/rollcheckdrawer.cpp`
- `src/checks/vgsavecheck.cpp`
- `CMakeLists.txt`

### Add

- `src/ui/songview/trackheadermodel.cpp`
- `src/ui/songview/trackheadermodel.h`
- `src/checks/trackheaderquickcheck.cpp`

### Delete after cutover

- `src/ui/songview/trackheaderrow.cpp`
- `src/ui/songview/trackheaderrow.h`
- `src/ui/songview/trackheaderpanel.cpp`
- `src/ui/songview/trackheaderpanel.h`
- `src/ui/activity/TrackActivityView.qml`
- `src/ui/activity/trackactivityview.cpp`
- `src/ui/activity/trackactivityview.h`
- `src/ui/activity/trackactivitypresentation.cpp`
- `src/ui/activity/trackactivitypresentation.h`
- `src/ui/activity/trackactivitypresentation_p.h`
- `src/ui/activity/trackactivityrenderer_macos.mm`
- `src/checks/trackactivitymetercheck_macos.mm`

## Performance gate

The conversion must not turn every activity tick into a full header rebuild. Retain these rules:

- no model reset for an activity-only update;
- no notification when the physical meter heights stay unchanged;
- at most one bounded `dataChanged` signal for changed activity rows per tick;
- no per-tick QML object creation;
- no second Quick scene or render loop.

Measure activity presentation and header interaction on the same visible song, build type, window
size, DPR, and track count before and after. A median regression above five percent blocks
completion. Fix the new path before completing the cutover; do not retain the old activity backend
or row-widget painter as a fallback.

## Allowed implementation freedom

An implementation agent may choose local variable names, private source-file helper order, and
check-only helper functions. If `trackheadermodel.cpp` crosses a repository size or complexity
check, report it to the orchestrator instead of inventing a file split. The agent must not change the
declared model surface, add another state holder, move document rules into QML, add a second Quick
host, retain a QWidget fallback, or weaken a behavior or performance gate without returning the
choice to the orchestrator.
