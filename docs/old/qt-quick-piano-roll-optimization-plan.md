# Qt Quick piano-roll optimization and clean-cutover plan

## Status

Implemented. Qt Quick is the only piano-roll renderer; `PianoRoll` remains
the C++ and Qt input and edit owner. Retained as the renderer-cutover record.

This plan makes Qt Quick the only piano-roll renderer, removes the environment-variable
selector and QWidget/QPainter fallback, and removes the confirmed avoidable CPU mechanisms in
the prototype. It preserves the current Qt Quick appearance and the existing QWidget-owned
interaction behavior.

The expected win is largest for local interaction: hover, sounding-key changes, selection,
gesture previews, and repeated same-turn invalidations. Horizontal pan, zoom, and
follow-playhead scrolling still rebuild the visible plot domains; this plan does not turn them
into a transform-only retained world or reduce them to an overlay blit.

No performance benchmark or profiling work is required by this plan. Verification covers
build, behavior, visual preservation, and the structural removal of the identified costs. The
implementation must not claim a measured CPU improvement.

## Decisions

1. **Qt Quick becomes the only piano-roll renderer.** A normal launch creates it without
   `PORYDAW_PIANO_ROLL_RENDERER`.
2. **`PianoRoll` remains the input owner.** Keyboard shortcuts, mouse gestures, selection,
   context menus, audition, focus, cancellation, and document mutation stay in the existing
   QWidget class.
3. **`PianoRoll` stops deriving from `TimelineSurface`.** It becomes a direct `QWidget` whose
   only visual child is an opaque `PianoRollQuickView`.
4. **`QQuickWidget` remains the embedding mechanism.** Replacing it with a `QQuickWindow` or
   a full-window Qt Quick application would require a separate input, focus, stacking, and
   playhead-overlay migration.
5. **The renderer becomes retained and semantically invalidated.** It does not rebuild a
   complete value snapshot for each small interaction change.
6. **Current Quick visuals are the visual contract.** The optimization does not attempt to
   recreate the deleted QPainter renderer's exact text rasterization or per-note overlap
   ordering.
7. **No dual-renderer seam remains after the cutover.** No alias, fallback, deprecated path,
   or environment switch is retained.

## Visual preservation contract

The optimized renderer must preserve the current Qt Quick output for:

- piano-roll background, accidental rows, scale tint, pre-roll, and adaptive grid;
- ghost-note and active-note geometry, colors, borders, and unterminated-note dashes;
- note-name and velocity labels;
- note selection rings, band selection, and timeline-range selection;
- draw, move, resize, transpose, and velocity previews;
- loop markers and glow;
- edit cursor;
- natural, black, hovered, and sounding piano keys;
- octave labels and keyboard hover chip;
- loading state;
- theme roles, font selection, device-pixel-ratio behavior, and clipping;
- the exact current Quick root stacking topology documented below, including the separate
  placement of draw-preview fill, draw-preview text, draw-preview border, keyboard text, and
  hover-chip text.

The current Quick renderer already differs from the QWidget/QPainter renderer around text and
edge rasterization, loop glow, and overlapping-note ordering. Those pre-existing differences
are not part of this optimization. The plan preserves current Quick visuals rather than
promising pixel identity with the renderer being deleted.

Any unexplained before/after Quick framebuffer difference blocks completion.

## Non-goals

- No CPU benchmark, profiler run, RHI trace, frame counter, signpost, or comparison report.
- No full-window Qt Quick migration.
- No `QQuickWindow`/native-window-container migration.
- No QML ownership of input, gestures, selection, editing, menus, or audition.
- No `QQuickPaintedItem`, QML `Canvas`, private `QSGTextNode`, private Qt Quick APIs, custom
  glyph atlas, or shader rewrite.
- No per-note QML object tree solely to emulate the deleted painter's overlap order.
- No speculative animation or general renderer abstraction.
- No changes to automation, velocity, voice-change, ruler, or other `TimelineSurface` users
  beyond reverting the temporary virtual seam introduced for `PianoRoll`.

## Confirmed problems in the prototype

### Complete rebuild for every invalidation

`PianoRoll::invalidateContent(const QRegion&)` discards the region and calls
`PianoRollQuickView::refresh()`. `refresh()` builds a complete scene, publishes it to all three
items, schedules all three items, and replaces both QML list properties.

Small keyboard-hover, selection, or gesture changes therefore rebuild the grid, all visible
notes, every label, overlays, and keyboard.

### Value-snapshot and QML delegate churn

`PianoRollQuickScene` currently owns `QVariantList` collections of per-label `QVariantMap`
objects. Each publication replaces the root QML properties. The `Repeater`s consume those
replacement lists and recreate their delegates.

### Unconditional geometry work

Each `PianoRollQuickItem::updatePaintNode()` calls `QSGGeometry::allocate()` for its complete
layer, rewrites all vertices, and marks both geometry and the unchanged material dirty.

### Redundant QWidget cache and transparent composition

The parent remains a `TimelineSurface`, so it maintains and paints a QPixmap cache underneath
a transparent `QQuickWidget`. The Quick scene then renders through its own offscreen target and
is composed into the QWidget hierarchy.

### Duplicated visual policy

`pianoroll_paint.cpp` and `pianorollquickscene.cpp` independently implement the same piano-roll
visual policy. The two implementations already disagree on overlapping-note ordering.

### Unavoidable remaining cost

`QQuickWidget` still renders into an offscreen target and does not use the normal threaded Qt
Quick render loop. This plan removes avoidable work around that embedding choice. It does not
claim to eliminate `QQuickWidget`'s inherent cost.

### Expected performance scope

The retained design makes omitted domains do no work and prevents repeated requests in one
event-loop turn from multiplying scene builds. That directly benefits local interaction after
callers migrate to semantic dirty sets.

It deliberately does not retain the note grid as a camera-transformed world. Horizontal camera
movement still changes the visible grid-line set, note culling, note geometry, note borders and
selection, overlays, and labels. Follow-playhead scrolling therefore remains proportional to
visible plot content. Its improvements are limited to retained allocation capacity, no material
dirt, incremental keyed text-model changes, skipped keyboard domains, and one coalesced flush.

Wave 2 installs the retained machinery while the legacy refresh entry point still requests
`All`. Layer-skipping benefits become production behavior only in Wave 3, when callers request
the semantic subsets listed below.

## Target module and ownership

The feature remains discoverable under `src/ui/songview/quick/` with one small external seam:

```text
PianoRoll (QWidget; input and state owner)
    |
    | semantic render invalidation
    v
PianoRollQuickView (QQuickWidget; update coordinator)
    |
    +-- PianoRollQuickScene (stable GUI-thread retained storage)
    |      +-- seven geometry layers and revisions
    |      +-- note text model
    |      +-- loading text model
    |      +-- keyboard text model
    |      +-- hover-chip properties
    |
    +-- QML root
           +-- seven stable PianoRollQuickItem geometry layers
           +-- three stacking Items containing stable text-model Repeaters
           +-- one stable hover-chip Rectangle/Text
```

### Ownership invariants

- `PianoRoll` owns `PianoRollQuickView` through normal QWidget parent ownership.
- `PianoRollQuickView` owns one `PianoRollQuickScene` for its full lifetime.
- `PianoRollQuickScene` owns retained layer data, text models, and hover-chip properties; it
  does not read `PianoRoll` state itself.
- `PianoRollQuickView` remains a private friend of `PianoRoll`. Domain builders are private
  `PianoRollQuickView` methods defined in `pianorollquickscene.cpp`; they read the existing
  `PianoRoll` state through that friendship and mutate only the owned scene.
- Generic node, model, QML-lifecycle, and coalescing code lives in `pianorollquick.cpp`.
  Domain-specific record construction and builder dispatch live only in
  `pianorollquickscene.cpp`.
- QML owns the root object, seven `PianoRollQuickItem`s, text delegates, and hover-chip items.
- QSG nodes, geometries, and materials are owned only by the node tree returned from
  `updatePaintNode()`.
- No QObject owns or deletes QSG resources.
- Audio threads never call the renderer or access its containers.

### Threading invariants

- `PianoRoll`, `PianoRollQuickView`, `PianoRollQuickScene`, text models, dirty flags, and
  primitive construction remain on the GUI thread.
- `updatePaintNode()` is treated as scene-graph synchronization/render-thread code even when
  the current `QQuickWidget` integration uses the basic render loop.
- During `updatePaintNode()`, Qt's synchronization phase prevents concurrent GUI-thread
  mutation of the scene data.
- `updatePaintNode()` creates and mutates only QSG resources, emits no signals, and never calls
  back into document or QWidget state.

## Retained renderer interface

The final interface should be equivalent to the following. Exact naming may follow existing
repository style, but the ownership and performance contracts must remain.

```cpp
enum class PianoRollQuickLayer : quint8 {
    Grid,
    NoteFills,
    DrawPreviewFill,
    NoteBordersAndSelection,
    Overlay,
    KeyboardKeys,
    KeyboardHighlights,
    Count,
};

enum class PianoRollQuickDirty : quint32 {
    None = 0,
    Grid = 1u << 0,
    NoteFills = 1u << 1,
    DrawPreviewFill = 1u << 2,
    NoteBordersAndSelection = 1u << 3,
    Overlay = 1u << 4,
    KeyboardKeys = 1u << 5,
    KeyboardHighlights = 1u << 6,
    NoteText = 1u << 7,
    LoadingText = 1u << 8,
    KeyboardText = 1u << 9,
    HoverChip = 1u << 10,
    All = (1u << 11) - 1,
};
Q_DECLARE_FLAGS(PianoRollQuickDirtySet, PianoRollQuickDirty)

struct PianoRollQuickRect {
    QRectF rect;
    QColor topLeft;
    QColor topRight;
    QColor bottomRight;
    QColor bottomLeft;
};

struct PianoRollQuickLayerData {
    std::vector<PianoRollQuickRect> rects;
    quint64 revision = 0;
};

class PianoRollQuickTextModel final : public QAbstractListModel {
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PianoRollQuickTextModel)

    // Typed roles: rect, text, color, textFont, horizontalAlignment,
    // verticalAlignment. Stable identity keys remain private.
};

class PianoRollQuickScene final : public QObject {
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PianoRollQuickScene)

    Q_PROPERTY(QAbstractItemModel *noteTextModel READ noteTextModel CONSTANT FINAL)
    Q_PROPERTY(QAbstractItemModel *loadingTextModel READ loadingTextModel CONSTANT FINAL)
    Q_PROPERTY(QAbstractItemModel *keyboardTextModel READ keyboardTextModel CONSTANT FINAL)

    // FINAL hover-chip properties: visible, rect, text, fill, font, radius.
};

class PianoRollQuickItem final : public QQuickItem {
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PianoRollQuickItem)

    Q_PROPERTY(PianoRollQuickLayer sceneLayer READ sceneLayer WRITE setSceneLayer
                   NOTIFY sceneLayerChanged FINAL)
};

class PianoRollQuickView final : public QQuickWidget {
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PianoRollQuickView)

  public:
    explicit PianoRollQuickView(PianoRoll &roll);
    void requestUpdate(PianoRollQuickDirtySet dirty);

  protected:
    void resizeEvent(QResizeEvent *event) override;

  private:
    void flushUpdate();
    void synchronize(PianoRollQuickDirtySet dirty);
};
```

Do not add a pimpl or split these declarations into several tiny files. The feature directory
and existing four Quick files provide sufficient locality.

## Retained geometry layers and exact stacking

The layer split must reproduce the current Quick root-level z topology. Splitting one current
buffer into several items is allowed only where QML declaration order at the same z preserves
the original primitive order.

### Grid (`z = 0`, declared first)

Contains:

- background or clear-dependent coverage;
- accidental pitch rows;
- semitone and octave lines;
- scale highlighting;
- pre-roll tint;
- adaptive time grid.

### NoteFills (`z = 0`, declared after Grid)

Contains ghost-note fills followed by active-track note fills, preserving model order inside
each pass.

### DrawPreviewFill (`z = 0`, declared after NoteFills)

Contains only the draw-preview fill. The prototype appends that fill to the background layer
after existing note fills. Keeping it at `z = 0` and after `NoteFills` preserves overlap
behavior while allowing preview movement to avoid rebuilding every note fill.

### NoteBordersAndSelection (`z = 2`, declared before Overlay)

Contains:

- normal note borders;
- unterminated-note dashes;
- selection rings;
- extreme-zoom solid selection marks.

Separating note borders and selection allows selection changes to avoid rebuilding note fills,
text, and grid.

### Overlay (`z = 2`, declared after NoteBordersAndSelection)

Contains, in this order:

- draw-preview border;
- band-selection fill and dashed edge;
- time-selection fill and edges;
- loop glow and loop edges;
- edit cursor.

The draw-preview fill and velocity text do not belong here: the current Quick renderer places
them below note borders and selection at `z = 0` and `z = 1`.

### KeyboardKeys (`z = 4`, declared before KeyboardHighlights)

Contains stable keyboard geometry:

- natural-key background;
- black keys;
- octave/F separators.

### KeyboardHighlights (`z = 4`, declared after KeyboardKeys)

Contains transient keyboard highlights plus the final keyboard lines needed to preserve the
prototype's primitive order:

- sounding-key fill;
- hovered-key highlight only when the key is not sounding, matching the current
  `!sounding` condition;
- after a sounding natural C/F fill, that row's octave/F separator redrawn above the fill;
- the keyboard boundary appended last, above every sounding or hover primitive.

Do not leave the boundary only in `KeyboardKeys`: the later highlight layer would cover it. Do
not redraw a separator after a non-sounding hover highlight: the current builder draws that
hover after the separator.

The hover-chip rectangle remains one stable QML item at `z = 4.5`. Octave labels remain in the
keyboard-text container at `z = 5`; the stable hover-chip text is also `z = 5` but is declared
after that container, so it wins equal-z sibling order as it does today.

## Semantic dirty-state mapping

Replace pixel-region invalidation with semantic requests. The minimum mapping is:

| State change | Dirty domains |
| --- | --- |
| Initial load or timeline attach/detach | `All` |
| Theme, palette, font, style, DPR | `All` |
| Width resize | Plot domains plus `LoadingText`; keyboard domains only if keyboard geometry changes |
| Horizontal scroll or zoom | `Grid`, `NoteFills`, `DrawPreviewFill`, `NoteBordersAndSelection`, `Overlay`, `NoteText` |
| Height resize, vertical scroll, key-height change | `All` |
| Pitch projection or scale-fold change | `All` |
| Scale-highlight toggle | `Grid` |
| Scale root/id change while fold changes projection | `All` |
| Scale root/id change with only highlighting active | `Grid` |
| Document/model replacement | Plot domains and text; keyboard domains only if projection changed |
| Primary-track change | `NoteFills`, `DrawPreviewFill`, `NoteBordersAndSelection`, `NoteText` |
| Velocity-color mode change | `NoteFills`, `DrawPreviewFill`, `NoteText` |
| Note-name mode or velocity-modifier state | `NoteText` |
| Explicit note-selection change | `NoteBordersAndSelection` |
| Time-selection change | `NoteBordersAndSelection`, `Overlay` |
| Move/resize/transpose live preview | `NoteFills`, `NoteBordersAndSelection`, `NoteText` |
| Velocity preview | `NoteFills`, `NoteText` |
| Draw-preview movement or value change | `DrawPreviewFill`, `Overlay`, `NoteText` |
| Band-reticle movement or membership change | `Overlay`, `NoteBordersAndSelection` |
| Edit cursor or loop marker change | `Overlay` |
| Keyboard hover change | `KeyboardHighlights`, `HoverChip` |
| Sounding-key change | `KeyboardHighlights` |

Whenever a fill color changes, every label whose color is derived through
`contrastingTextColor(fill)` must be dirtied with that fill. The table therefore couples
velocity-color mode and velocity preview to `NoteText`.

Where one state mutation changes several concepts, request their union once. `requestUpdate()`
coalesces repeated requests, so callers do not need their own scheduling logic.

## Update coalescing

`PianoRollQuickView::requestUpdate()` must:

1. OR the incoming bits into `m_pendingDirty`;
2. post exactly one queued `flushUpdate()` if none is pending;
3. let further requests accumulate before the queued call executes;
4. atomically take the current pending bits in `flushUpdate()`;
5. synchronize only those domains;
6. call `update()` only on geometry items whose layer revision advanced;
7. schedule another turn if a request arrives during synchronization.

Use the context-bound public `QMetaObject::invokeMethod` functor overload or the repository's
existing equivalent. Do not introduce a timer.

The initial scene may synchronize once after QML source loading and validation. Resize queues
`All` or the appropriate geometry subset against the final size; it does not rebuild the scene
synchronously inside every `resizeEvent()`.

## Geometry-buffer policy

Each geometry layer retains its scene-graph nodes and buffer capacity.

Required behavior:

- `PianoRollQuickLayerData::rects.clear()` retains high-water vector capacity.
- The layer revision advances only after that layer is rebuilt.
- An unchanged revision returns the old QSG node without touching geometry or material.
- Materials and blending flags are created once.
- Content changes mark geometry dirty, not material dirty.
- Existing geometry storage is not reallocated merely because the layer refreshed.
- Geometry grows only when the visible rectangle count exceeds current capacity.
- Ordinary updates do not shrink high-water capacity.
- Primitive construction continues to clip/cull to the viewport.

If the project's minimum supported Qt lacks a public active-vertex-count setter that avoids
reallocation, use fixed-capacity geometry chunks, for example 256 rectangles per node:

- allocate each chunk once;
- add chunks only when the high-water count crosses a boundary;
- clear formerly-used tails with transparent degenerate triangles;
- block completely unused chunks;
- retain chunks for future updates.

Do not use a private Qt API to avoid this compatibility constraint.

## Incremental text models

Delete the current `QVariantList`/`QVariantMap` transport. `PianoRollQuickScene` owns three
stable `PianoRollQuickTextModel` instances:

1. note text, including note labels and draw-preview velocity text in current append order;
2. loading text;
3. keyboard text, containing octave labels only.

The hover-chip text is one persistent QML `Text`, not a model row.

Each record stores typed values directly:

- internal stable key;
- `QRectF`;
- `QString`;
- `QColor`;
- `QFont`;
- horizontal alignment;
- vertical alignment.

Stable keys include:

- `NoteId + label kind` for note-name and velocity labels;
- one singleton draw-preview key appended after visible note-label keys;
- MIDI key for octave labels;
- one singleton loading key.

Synchronization rules:

- Never replace the model object.
- Never call `beginResetModel()` for normal synchronization.
- Build an old-key index and reconcile the complete new key sequence by stable key, not merely
  by common prefix/suffix.
- Preserve surviving rows across viewport slides with balanced `beginMoveRows`/`endMoveRows`;
  remove keys that left the viewport and insert only genuinely new keys.
- After structural reconciliation, compare records and emit `dataChanged` only for contiguous
  changed rows with exact, non-empty role lists.
- Preserve the new sequence's model order so equal-z text ordering remains identical to the
  current Quick builder.
- Cache `roleNames()`.
- Resolve and cache font information once per active font, not once per label.
- Construct `QFontMetricsF` once per active font per synchronization pass.
- Preserve `Text.NativeRendering`; text-rendering-mode changes are outside this optimization.

## QML structure

`PianoRollCanvas.qml` will no longer expose `property var textItems` or
`property var roundedRects`.

It will contain:

- seven stable `PianoRollQuickItem` instances;
- three root-level stacking `Item`s, each containing one `Repeater` permanently bound to a
  stable `QAbstractListModel`;
- one stable hover-chip `Rectangle` and one stable hover-chip `Text`;
- typed required roles rather than `modelData` map lookup.

Every delegate's `z` is local to its stacking container. Model records must not carry the old
root-level values `1` or `5` into delegate `z`, because that would compete with sibling geometry
items and invert the intended layers.

Conceptual text container and delegate:

```qml
Item {
    id: noteTextLayer
    anchors.fill: parent
    z: 1

    Repeater {
        model: pianoRollScene.noteTextModel

        delegate: Text {
            required property rect rect
            required property string text
            required property color color
            required property font textFont
            required property int horizontalAlignment
            required property int verticalAlignment

            x: rect.x
            y: rect.y
            width: rect.width
            height: rect.height
            z: 0
            font: textFont
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideNone
            maximumLineCount: 1
            clip: true
        }
    }
}
```

The exact root-level topology is:

| Root z | Declaration order and content |
| ---: | --- |
| 0 | `Grid`, `NoteFills`, `DrawPreviewFill` |
| 1 | `NoteText` container; note labels followed by draw-preview velocity text |
| 2 | `NoteBordersAndSelection`, then `Overlay`; Overlay begins with draw-preview border |
| 4 | `KeyboardKeys`, then `KeyboardHighlights` |
| 4.5 | stable hover-chip rectangle |
| 5 | `KeyboardText` container, then stable hover-chip text, then `LoadingText` container |

This reproduces the prototype's effective order. Do not move draw-preview fill into Overlay, do
not place draw-preview text above note borders and selection, and do not put keyboard labels
after hover-chip text.

Do not attempt to interleave QML text between per-note geometry using one Quick item per note.
That would trade the current known overlap behavior for large QObject and node counts.

## Opaque composition

Configure `PianoRollQuickView` as follows:

```cpp
setAttribute(Qt::WA_TransparentForMouseEvents);
setAttribute(Qt::WA_OpaquePaintEvent);
setFocusPolicy(Qt::NoFocus);
setResizeMode(QQuickWidget::SizeRootObjectToView);
setClearColor(themes::color(themes::Role::song_view_piano_roll_background));
```

Requirements:

- update the clear color on theme and palette changes;
- keep `WA_AlwaysStackOnTop` disabled;
- keep the existing `PlayheadOverlay` above the roll;
- remove the transparent clear color;
- remove parent QWidget/QPixmap underpainting;
- remove a full-viewport background rectangle only after proving the opaque clear produces the
  same pixels for the current theme and loading state.

## Failure policy

Qt Quick is required after the cutover. QML type registration, resource loading, and required
item lookup are packaging invariants.

- Register the custom type before loading the QML source.
- Set the stable controller context property before `setSource()`.
- Validate the root and all seven geometry items.
- Report every `QQmlError` with its source location.
- Fail fast on invalid packaged QML instead of silently activating a deleted renderer or
  continuing with a blank piano roll.

## Clean-cutover inventory

### Delete files

- `src/ui/songview/pianoroll_paint.cpp`
- `docs/qt-quick-piano-roll-comparison.md`
- `docs/qt-quick-piano-roll-comparison/quick-native-window.png`
- `docs/qt-quick-piano-roll-comparison/quick-presentation.png`
- `docs/qt-quick-piano-roll-comparison/qwidget-native-window.png`
- `docs/qt-quick-piano-roll-comparison/qwidget-presentation.png`

### Delete or replace production symbols

From `src/ui/songview/pianoroll.h` and related implementations:

- `PianoRoll::paintContent`;
- `PianoRoll::invalidateContent(const QRegion&)`;
- `PianoRoll::invalidateTimeSelection` and its repaint-region arguments;
- `PianoRoll::drawNotes`;
- `PianoRoll::drawNoteName`;
- `PianoRoll::drawDragPreview`;
- `PianoRoll::drawKeyboard`;
- `PianoRoll::buildQuickScene`;
- `PianoRollQuickScene` value-snapshot forward declaration;
- painter-only frame helpers;
- `KeyboardHoverGeometry::paintRegion`;
- painter-only includes and forward declarations.

From `src/ui/songview/quick/pianorollquick.h/.cpp`:

- `pianoRollQuickRendererRequested()`;
- `PORYDAW_PIANO_ROLL_RENDERER` lookup;
- old three-layer snapshot structure;
- `std::shared_ptr<const PianoRollQuickScene>` publication;
- `PianoRollQuickView::isReadyForPresentation()`;
- `PianoRollQuickView::refresh()` as a complete rebuild;
- `PianoRollQuickView::publish()`;
- `QVariantList textItems`;
- `QVariantList roundedRects`;
- transparent clear color;
- fallback initialization path.

### Relocate surviving non-paint logic

- `PianoRoll::noteNameFits` from `pianoroll_paint.cpp` to
  `pianoroll_geometry.cpp` or a private helper in `pianorollquickscene.cpp`.
- `PianoRoll::auditionBandEntrants` from `pianoroll_paint.cpp` to
  `pianoroll_gestures.cpp`.
- `PianoRoll::stopBandAuditions` from `pianoroll_paint.cpp` to
  `pianoroll_gestures.cpp`.

### Revert temporary shared-surface changes

- `src/ui/timelinesurface.h`: restore non-virtual `invalidateContent()` overloads.
- `src/ui/editordrawer/automationcanvas.h`: remove the temporary `override`.

### CMake cleanup

In `CMakeLists.txt`:

- keep `Qt6::Qml`, `Qt6::Quick`, and `Qt6::QuickWidgets`;
- keep the three Quick C++ sources;
- keep `qt_add_qml_module` and the QML resource alias;
- remove `src/ui/songview/pianoroll_paint.cpp`;
- remove the macOS framework-header symlink bridge added by the prototype.

The header bridge encodes local stale `/usr/local/include/Qt*` contamination into the project.
Imported Qt targets must provide the selected Qt installation's headers. Fix a leaking toolchain
include path at the toolchain/environment level rather than shipping generated symlink trees.

## Implementation sequence

The implementation should remain buildable and behaviorally green at each wave. Temporary
selector use during the first two waves is allowed only as an implementation-order device; it
must be deleted in the cutover wave and must not appear in the final result.

### Wave 1: lock the current Quick visual and interaction contract

**Agents:** dispatch one `task` agent for the Quick-aware rollcheck harness and one parallel
`task` agent for disjoint visual fixtures/check cases. Use a dedicated `reviewer` after the
wave.

Changes:

1. Add a rollcheck capture helper that locates `pianoRollQuickCanvas` and uses
   `QQuickWidget::grabFramebuffer()` after the widget is visible and exposed.
2. Route existing Quick visual probes through the framebuffer helper rather than parent
   `QWidget::grab()`/`render()`.
3. Exercise the Quick path in the harness before the production selector is removed.
4. Preserve behavior checks for shortcuts, focus, draw, move, resize, velocity drag, band and
   time selection, context menu, audition, keyboard hover, and cancellation.
5. Add representative current-Quick visual states for grid/notes, labels, selection, keyboard,
   loop markers, edit cursor, loading, and overlap ordering.

Acceptance:

- the existing Quick implementation passes the migrated behavioral checks;
- framebuffer captures are non-empty and use the framebuffer DPR;
- the current Quick output is recorded as the refactor baseline;
- no benchmark or CPU threshold is introduced.

Verification:

```bash
deno task build:checks
deno task verify --filter rollcheck --verbose
```

### Wave 2: replace snapshot publication with retained Quick internals

**Agent:** one `task` implementation agent owns the four files under
`src/ui/songview/quick/`; follow with `qt-cpp-reviewer` and `cpp-smell-reviewer` agents in
parallel. The retained controller is one cohesive contract and must not be split among
same-file writers.

Target files:

- `src/ui/songview/quick/pianorollquick.h`
- `src/ui/songview/quick/pianorollquick.cpp`
- `src/ui/songview/quick/pianorollquickscene.cpp`
- `src/ui/songview/quick/PianoRollCanvas.qml`

Changes:

1. Introduce the stable scene controller, dirty flags, retained layer data, revisions, and text
   models.
2. Replace the monolithic scene build with cohesive domain builders:
   - `rebuildGrid()`;
   - `rebuildNoteFills()`;
   - `rebuildDrawPreviewFill()`;
   - `rebuildNoteBordersAndSelection()`;
   - `rebuildOverlay()`;
   - `rebuildKeyboardKeys()`;
   - `rebuildKeyboardHighlights()`;
   - note/loading/keyboard text-model and hover-chip synchronizers.
3. Implement queued update coalescing.
4. Replace complete geometry allocation with retained capacity and revision early-outs.
5. Replace QVariant list/map publication with stable typed models and keyed row reconciliation.
6. Replace the rounded-rectangle Repeater with one stable hover chip.
7. Preserve the exact current Quick root topology, colors, geometry, fonts, clipping, and
   `NativeRendering`.
8. Keep the legacy `refresh()` entry point temporarily, but make it request `All`; do not claim
   production layer-skipping until Wave 3 migrates callers.

Acceptance:

- no `QVariantMap` or scene `QVariantList` remains;
- no text-model reset or model-object replacement remains;
- a layer omitted from an explicit dirty set does not rebuild, advance revision, receive
  `update()`, or rewrite geometry;
- the temporary legacy `refresh()` is explicitly understood to request every domain;
- repeated same-turn requests synchronize once;
- before/after Quick framebuffer states have no unexplained visual differences;
- all Wave 1 checks remain green.

Verification:

```bash
deno task format src/ui/songview/quick/pianorollquick.h \
  src/ui/songview/quick/pianorollquick.cpp \
  src/ui/songview/quick/pianorollquickscene.cpp
deno task build:checks
deno task verify --filter rollcheck --verbose
```

### Wave 3: migrate callers to semantic dirty domains

**Agents:** dispatch parallel `task` agents with disjoint file ownership after the dirty-flag
interface from Wave 2 is fixed. Follow with one `qt-cpp-reviewer` integration review.

Suggested ownership:

- interaction agent: `pianoroll_geometry.cpp`, `pianoroll_interaction.cpp`,
  `pianoroll_gestures.cpp`, `pianoroll_gestures_active.cpp`;
- command/state agent: `pianoroll_commands.cpp`, `pianoroll.cpp`, `camera.cpp`, `viewstate.cpp`;
- selection coordination agent: `songview.cpp` and any exact selection-transition callers found
  through LSP references.

Changes:

1. Replace complete `invalidateContent()` calls with the narrow semantic union justified by the
   state change.
2. Remove `invalidateContent(const QRegion&)`, `invalidateTimeSelection(...)`, and keyboard
   paint-region construction.
3. Keep a full `All` request only for changes that genuinely alter every domain.
4. Preserve state mutation order before requesting an update; queued synchronization must see
   the final state.
5. Audit every fill-color change against derived text color, every pitch-projection change
   against all y-dependent domains, and sounding/hover interaction against the current
   `!sounding` highlight rule.

Acceptance:

- no piano-roll call site constructs a repaint `QRegion`;
- hover changes request keyboard highlights/chip and preserve hover suppression on a sounding key;
- sounding-key changes request keyboard highlights;
- note selection requests note borders and selection;
- time selection requests note borders and selection plus overlay;
- primary-track and velocity-color changes refresh an active draw-preview fill;
- velocity-color and velocity-preview changes update both fill and derived label color;
- draw preview updates body at z 0, text at z 1, and border at z 2;
- scale-fold/projection changes update every pitch-dependent domain;
- full invalidation is limited to document, projection, theme/font/DPR, and equivalent global
  changes;
- unchanged domains now do no production work because callers no longer route through the
  temporary `All` refresh;
- all behavioral and visual checks remain green.

Verification:

```bash
deno task format src/ui/songview/pianoroll*.cpp src/ui/songview/camera.cpp \
  src/ui/songview/viewstate.cpp src/ui/songview.cpp
deno task build:checks
deno task verify --filter rollcheck --verbose
```

### Wave 4: perform the clean renderer cutover

**Agents:** one `task` agent owns the base-class and deletion seam; a parallel `sonic` agent may
remove the comparison artifacts and stale CMake entries after the production-file ownership is
fixed. Follow with `qt-cpp-reviewer` and `reviewer` agents in parallel.

Production targets:

- `src/ui/songview/pianoroll.h`
- `src/ui/songview/pianoroll.cpp`
- `src/ui/songview/pianoroll_paint.cpp`
- `src/ui/songview/pianoroll_geometry.cpp`
- `src/ui/songview/pianoroll_gestures.cpp`
- `src/ui/timelinesurface.h`
- `src/ui/editordrawer/automationcanvas.h`
- `CMakeLists.txt`

Changes:

1. Make `PianoRoll` a direct `QWidget`.
2. Construct the Quick view unconditionally.
3. Remove the environment selector and fallback.
4. Make the Quick view opaque and update clear color on appearance changes.
5. Delete the QWidget painter and obsolete painter helpers.
6. Relocate surviving geometry/audition helpers.
7. Revert the temporary `TimelineSurface` virtual seam.
8. Delete the comparison document and captures.
9. Remove the macOS header-symlink workaround.
10. Remove all obsolete includes, declarations, aliases, comments, and test branches.

Acceptance:

- normal launch always creates Qt Quick without an environment variable;
- no QPainter piano-roll renderer remains;
- `PianoRoll` no longer allocates or paints through a `TimelineSurface` cache;
- the Quick child is opaque and the playhead overlay remains visible above it;
- QML failure cannot select a deleted renderer;
- no repository file references `PORYDAW_PIANO_ROLL_RENDERER`;
- no stale comparison statement claims an alternate renderer remains;
- visual and interaction checks remain green.

Verification:

```bash
deno task build:app
deno task build:checks
deno task verify --filter rollcheck --verbose
```

Actual-surface smoke verification is mandatory in this wave:

1. Launch the built `.app` without `PORYDAW_PIANO_ROLL_RENDERER`.
2. Open the checked-in project fixture used by the existing roll checks.
3. Position and expose the real application window.
4. Start playback and observe the playhead crossing the opaque Quick piano roll.
5. Capture the application window with the `capture-macos-app-window` workflow.
6. Verify the playhead remains above the Quick child and that no transparent, stale, or
   QWidget-cache underlay appears.

Build/check commands do not substitute for this surface verification.

### Wave 5: remove obsolete cache checks and run final gates

**Agent:** one `task` agent adapts or deletes only checks made obsolete by removing the roll's
`TimelineSurface` cache. Use a final `reviewer` plus `qt-cpp-reviewer` in parallel after edits.

Changes:

- remove roll-specific `TimelineSurfaceDiagnostics` expectations;
- retain cache checks for automation, velocity, voice-change, ruler, and other surfaces still
  using `TimelineSurface`;
- retain all observable piano-roll interaction and rendering checks;
- ensure Quick framebuffer capture is used consistently.

Final verification:

```bash
deno task format --check
deno task build:app
deno task build:checks
deno task verify
```

No benchmark command belongs in this wave.

## File-level implementation map

### `src/ui/songview/quick/pianorollquick.h`

- replace the value snapshot with retained layer/controller types;
- add dirty flags and `Q_DECLARE_FLAGS`;
- add the stable text model;
- replace shared-pointer scene publication with one-time controller association;
- remove the renderer-request function.

### `src/ui/songview/quick/pianorollquick.cpp`

- implement stable node ownership and revision-aware `updatePaintNode()`;
- implement retained geometry capacity;
- implement generic keyed text-model reconciliation;
- implement queued update coalescing;
- configure opaque composition;
- load and validate QML without fallback;
- remove environment lookup and complete-scene publication;
- do not contain piano-roll domain policy or duplicate scene-builder dispatch.

### `src/ui/songview/quick/pianorollquickscene.cpp`

- define private `PianoRollQuickView` domain builders and synchronization dispatch;
- read `PianoRoll` private state through the existing friendship;
- mutate only the view-owned `PianoRollQuickScene`;
- build note, loading, and keyboard text records, then call the generic model reconciler;
- preserve all current visual calculations and the exact root stacking topology;
- cache font information and metrics per synchronization pass;
- reuse retained vector capacity;
- advance only rebuilt layer revisions.

### `src/ui/songview/quick/PianoRollCanvas.qml`

- replace list-backed map delegates with typed stable models;
- add seven stable geometry items;
- wrap each of the three text Repeaters in a root-level stacking Item;
- keep delegate z local to its container;
- replace rounded-rectangle Repeater with one hover chip;
- preserve the exact z/declaration table above and `Text.NativeRendering`.

### `src/ui/songview/pianoroll.h`

- change base to `QWidget`;
- remove painter, region, snapshot, and fallback declarations;
- expose or privately map semantic invalidation to the Quick view;
- retain every interaction method and state field.

### `src/ui/songview/pianoroll.cpp`

- construct Quick unconditionally;
- forward semantic updates;
- call `QWidget::event()` rather than `TimelineSurface::event()`;
- handle theme, palette, font, style, and DPR changes directly;
- preserve focus, mouse tracking, menu ownership, and event behavior.

### `src/ui/songview/pianoroll_geometry.cpp`

- remove QPainter frame helpers and repaint-region calculation;
- retain geometry, hit testing, hover geometry, and display-note projection;
- relocate `noteNameFits` if still used by the Quick builder.

### `src/ui/songview/pianoroll_gestures.cpp`

- receive `auditionBandEntrants` and `stopBandAuditions`;
- preserve their behavior unchanged.

### `src/ui/timelinesurface.h`

- restore non-virtual invalidation methods after `PianoRoll` stops deriving from it.

### `src/ui/editordrawer/automationcanvas.h`

- remove the temporary `override`; no behavioral change.

### `CMakeLists.txt`

- remove the painter source and local framework-header bridge;
- retain permanent Qt Quick/QML modules and resources.

### `src/checks/rollcheck/`

- capture the Quick framebuffer;
- preserve visual and interaction contracts;
- remove only cache-specific assertions that no longer describe the roll.

## Verification matrix

| Contract | Verification |
| --- | --- |
| Normal launch uses Quick | Launch built app without renderer environment variable and inspect `pianoRollQuickCanvas` |
| Shortcuts and focus | Existing roll command/focus checks |
| Draw, move, resize, velocity drag | Existing roll gesture checks |
| Band and time selection | Existing selection checks plus Quick framebuffer probes |
| Context menu and audition | Existing behavioral checks |
| Keyboard hover/sounding state | Existing keyboard checks through Quick framebuffer capture |
| Current Quick visual preservation | Before/after framebuffer comparison for representative fixtures |
| Theme/font/DPR refresh | Existing theme/layout checks plus Quick framebuffer capture |
| Playhead overlay stacking | Launch the actual built app, start playback in a visible/exposed window, capture it with `capture-macos-app-window`, and inspect the opaque Quick/playhead composition |
| QML packaging invariant | Focused invalid-resource/item-topology failure check where supported |
| No dual renderer | Scoped source search for selector, environment variable, painter symbols, and stale docs |
| No red tree | `deno task verify` |

## Risks and mitigations

### Quick framebuffer capture timing

`QQuickWidget::grabFramebuffer()` requires a rendered, visible widget. The harness must show the
window, process events until the Quick widget is ready, and use the framebuffer's DPR. It must
not sample an unexposed or stale frame.

### Theme invalidation after leaving `TimelineSurface`

`TimelineSurface::changeEvent()` currently performs appearance invalidation. `PianoRoll::event()`
must explicitly handle theme, application palette, palette, style, font, and DPR changes before
the base class is removed.

### Opaque-child stacking

`WA_OpaquePaintEvent` and opaque clear color must not cover the separate playhead overlay. Keep
`WA_AlwaysStackOnTop` disabled and verify the actual playback surface.

The Wave 4 build and check commands do not exercise this stacking contract. The visible
playback launch and captured application window are required evidence, not an optional manual
note.

### Pan, zoom, and follow-playhead cost

The semantic dirty model still rebuilds all visible plot domains when the camera changes. Do
not describe this as transform retention or overlay-blit-equivalent scrolling. A future
camera-transform scene is a separate design.

### Geometry capacity growth

A large temporary viewport may establish a high-water buffer capacity. Retaining that capacity
is intentional to avoid churn, but growth must remain bounded by viewport-visible primitives,
not the full song.

### Text-model structural edits

Incorrect model row signaling can corrupt delegate identity or crash QML. Every remove/insert
must use balanced model notifications on the GUI thread. Do not use model reset as a fallback.

### Pixel checks inherited from QPainter

Existing exact pixel expectations may describe QPainter rasterization rather than the current
Quick contract. Migrate them against the current Quick baseline; do not weaken unrelated
behavioral assertions or silently add broad tolerances.

## Completion criteria

The work is complete only when all of the following hold:

- Qt Quick is the sole piano-roll renderer on normal launch.
- The environment selector and QPainter fallback are absent.
- `PianoRoll` is a direct `QWidget` and has no `TimelineSurface` cache.
- The Quick child is opaque; redundant parent underpainting is absent.
- Renderer state is retained and updates are coalesced by semantic dirty domain.
- After caller migration, a geometry layer omitted from the dirty set does no scene-graph work.
- Text uses stable typed models, keyed row reconciliation, no QVariant property bags, and no
  model reset.
- The exact current Quick root stacking/declaration order is preserved.
- Fill-color changes invalidate derived contrasting text colors.
- Hover highlighting remains suppressed on the sounding key.
- Sounding natural C/F keys retain their separator, and the keyboard boundary remains above
  transient keyboard fills.
- The duplicate painter implementation and obsolete experiment artifacts are deleted.
- Existing interaction behavior remains intact.
- Current Quick visuals have no unexplained changes.
- Visible playback proves the playhead remains above the opaque Quick child.
- Build, targeted roll checks, and the full verification suite pass.
- No benchmark, transform-retention claim, or measured performance threshold is required or
  claimed.
