# Voice Change drawer page implementation plan

**Date:** 2026-08-28
**Status:** Implemented; archived for decision history
**Scope:** Move the primary track's Voice Change strip out of `AutomationCanvas` into a third, independently visible editor-drawer page.

## Summary

Build `VoiceChangeArea`, a standalone `songview::TimelineSurface` parallel to `VelocityArea`, and add `EditorDrawerPage::VoiceChanges` as a third persisted drawer section. The page owns Voice Change painting, hover, picker, context menu, scrolling, and `DOC_CC_VOICE` commits for the current primary track; `AutomationCanvas` returns to Tempo and CC lanes only. Put Voice Changes at the top of the visible drawer-band stack because it is a full-timeline program-context strip, while Velocity and Automations are detailed editors below it. Keep all three independently toggleable/resizable.

### Rationale and rejected alternatives

- **Dedicated area:** Voice Change is not a node lane. Held program spans, names, picker interaction, and `DOC_CC_VOICE` storage belong behind the same small lifecycle interface as `VelocityArea`, removing special cases from AutomationCanvas.
- **Not Velocity:** velocity is note-scoped/selection-driven; voice changes are track-scoped timeline events.
- **Not an Automation row:** retaining it preserves `contentTopInset()` and input/paint exceptions.
- **Not piano roll:** piano roll is pitch/note editing and can be replaced by raw MIDI event list; Voice Changes must remain independently available.

## Observed baseline and assumptions

- `EditorDrawer::EditorDrawer` (`editordrawer.cpp:17-47`) constructs `AutomationPage(owner,this)` and `VelocityArea(owner,this)`, installs focus filters, then `DrawerSections(this,m_automationPage,m_velocityArea)`.
- `EditorDrawerPage` currently has `Automations`, `Velocity`; drawer/view state has `velocity`, `automation`, `activePage` (`editorviewstate.h:12-65`).
- Reuse existing `:/icons/flat-music.svg`; other resources are velocity/velocity_labels/automation. No new asset/resource registration.
- Plan docs live directly under `docs/` as `*-plan.md`.
- Enum/state plural `VoiceChanges`/`voiceChanges`; surface singular `VoiceChangeArea`.
- Default new section hidden `{false,std::nullopt}`; Automations remains open default.
- Preserve actual current input: plain left press focuses/consumes; left **double-click** opens picker; context-menu action clicks insert/change/remove. Do not open picker on single press because current `mousePress` does not and it would intercept the first half of double-click.

## Changes

### Exact file inventory

**Add**
- `src/ui/editordrawer/voicechangearea/voicechangearea.h`
- `src/ui/editordrawer/voicechangearea/voicechangearea.cpp`
- `src/ui/editordrawer/voicechangearea/voicechangearea_paint.cpp` (meaningful paint seam)
- `src/checks/rollcheckvoicechange.{h,cpp}` helper invoked by existing drawer check; do not add a top-level registered check, preserving 56.

**Modify**
- `CMakeLists.txt`: replace old lane sources with area sources; add check helper; no resource changes.
- `src/ui/editorviewstate.{h,cpp}`
- `src/ui/editordrawer/editordrawer.{h,cpp}`
- `src/ui/editordrawer/drawersections.{h,cpp}`
- `src/ui/editordrawer/automationcanvas.h`, `.cpp`, `_input.cpp`, `_paint.cpp`
- `src/ui/songview.h`, `songview.cpp`, `songview/drawercoordination.cpp`, `songview/trackvoiceops.cpp`
- `src/mainwindow.{h,cpp}`
- `src/checks/rollcheckdrawer.cpp`, `rollcheckautomation.cpp`, `rollcheckautomation_paint.cpp`, `automationgesturecheck/mapping.cpp`, `automationgesturecheck/rig.cpp` plus declaration header, `mainwindowroutingcheck.cpp`
- `CONTEXT.md`, `docsrc/manual/automation.md`, `main-window.md`, `shortcuts.md`
- `docs/tempo-slot-plan.md`: supersession note/link only.

**Delete after all callers migrate**
- `src/ui/editordrawer/voicechangelane.h`
- `src/ui/editordrawer/voicechangelane.cpp`

No alias, forwarding header, or retained type.

### Exact state contract

```cpp
enum class EditorDrawerPage : uint8_t {
    Automations,
    Velocity,
    VoiceChanges,
};

struct EditorDrawerState {
    DrawerSectionState velocity{false, std::nullopt};
    DrawerSectionState automation{true, std::nullopt};
    DrawerSectionState voiceChanges{false, std::nullopt};
    EditorDrawerPage activePage = EditorDrawerPage::Automations;
    bool operator==(const EditorDrawerState &) const noexcept = default;
};

struct EditorViewState {
    DrawerSectionState velocity{false, std::nullopt};
    DrawerSectionState automation{true, std::nullopt};
    DrawerSectionState voiceChanges{false, std::nullopt};
    EditorDrawerPage activePage = EditorDrawerPage::Automations;
    int laneHeight = 0;
    std::map<EditorAutomationRowId, int> laneHeights;
    std::map<EditorAutomationRowId, uint8_t> laneRanges;
    std::set<EditorAutomationRowId> emptyLanes;
    EditorDrawerState drawerState() const noexcept;
    void setDrawerState(const EditorDrawerState &state) noexcept;
    // Existing lane methods/private m_hiddenLanes unchanged.
};
```

`drawerState()` returns `{velocity,automation,voiceChanges,activePage}`; setter assigns all four. It is application-wide chrome.

MainWindow exact keys:
```cpp
const QString kDrawerVoiceChangesVisibleKey = QStringLiteral("editorDrawer/voiceChangesVisible");
const QString kDrawerVoiceChangesHeightKey = QStringLiteral("editorDrawer/voiceChangesHeight");
```
Load/save like other optional states. Active page string `voiceChanges`; explicit velocity/voiceChanges parsing, otherwise Automations fallback.

### Exact `VoiceChangeArea` declaration

```cpp
class VoiceChangeArea final : public songview::TimelineSurface
{
  public:
    explicit VoiceChangeArea(SongView &owner, QWidget *parent = nullptr);
    void songChanged();
    void refreshLiveState(const DrawerPageLiveState &liveState);
    void cancelInteraction();
    void documentChanged();
    void tracksRemapped(const TrackRemap &remap);
    int plotOrigin() const;
    int plotWidth() const;
    void presentPlayhead(double tick);
  protected:
    bool event(QEvent *event) override;
    void paintContent(QPainter &painter) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void leaveEvent(QEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void contextMenuEvent(QContextMenuEvent *event) override;
    void contentGeometryChanged() override;
  private:
    enum class Interaction { None, Pan };
    struct Geometry {
        int plotOrigin = 0;
        int markerHitRadius = 0;
        int hoverPaintPadding = 0;
        int gridMinimumCellWidth = 0;
        void resolve();
    };
    struct VoicePaintText {
        const LoadedVoiceGroup *group = nullptr;
        int type = -1;
        std::array<char, VG_VOICE_NAME_LEN> sourceName{};
        QString label;
        QString hoverLabel;
    };
    void invalidateContent(const QRect &rect = {});
    void rebuildVisualState();
    void rebuildFonts();
    void clearHover();
    void updateHover(qreal x);
    void ensureHoverLabelFontCache();
    bool ready() const noexcept;
    int primaryTrack() const noexcept;
    const VoicePaintText &paintTextFor(int program) const;
    int voiceSlotAt(uint64_t tick) const;
    QRect plotRect() const;
    bool voiceMarkerAt(qreal x, DocLanePoint *out) const;
    void showPicker(const QPoint &globalPosition);
    void showContextMenu(const QPoint &globalPosition);
    SongView &m_owner;
    DrawerPageLiveState m_live;
    Geometry m_geometry;
    int m_engineTrack = -1;
    Interaction m_interaction = Interaction::None;
    QPointF m_previousPosition;
    bool m_suppressContextMenu = false;
    bool m_hoverActive = false;
    qreal m_hoverX = 0.0;
    uint64_t m_hoverTick = 0;
    QString m_hoverLabel;
    QRectF m_hoverLabelRect;
    QRect m_hoverLabelBounds;
    QFont m_titleFont;
    QFont m_captionFont;
    QFont m_hoverLabelFont;
    QFontMetrics m_hoverLabelMetrics{QFont{}};
    mutable std::array<VoicePaintText, VOICEGROUP_SIZE> m_paintTexts;
    mutable QString m_secondary;
    mutable int m_changeCount = -1;
    std::optional<double> m_lastPresentedPlayheadTick;
};
```
Dependencies: array/cstdint/optional, Qt font/geometry/string/widget, `core/songdocument.h`, drawerpage, timelinesurface, voicegroup_loader; forward-declare events/painter/SongView.

Exact geometry:
```cpp
plotOrigin = layout::fontPx(17.5 + 13.0 / 3.0);
markerHitRadius = layout::fontPx(3.0 / 4.0);
hoverPaintPadding = layout::fontPx(1.0 / 6.0);
gridMinimumCellWidth = layout::fontPx(4.0 / 3.0);
```

### EditorDrawer contract

Add `voiceChangesAction()`, mutable/const `voiceChangeArea()` accessors, members `m_voiceChangeArea`, `m_voiceChangesAction`. Construct AutomationPage, VelocityArea, VoiceChangeArea, then `DrawerSections(this,automation,velocity,voiceChanges)`; focus filter; shortcut-free internal action object `voiceChangesDrawerAction` triggering VoiceChanges.

Replace binary ternaries with exhaustive switches + `Q_UNREACHABLE`: sync/drawer/publish state; diff visibility/fully hidden; transition cancel; `hasVisibleSection`, `sectionHeight`, `pageVisible`, event filter, activation announcement (`Voice changes hidden/shown`), cancel routing, `canvasFor`, `ownsFocus`. `arrangeChildren` remains DrawerSections delegation. `focusVisiblePage` delegates.

### DrawerSections contract/layout

Public:
```cpp
DrawerSections(QWidget *parent, AutomationPage *automation, VelocityArea *velocity,
               VoiceChangeArea *voiceChanges);
std::optional<int> velocityHeight() const noexcept;
std::optional<int> automationHeight() const noexcept;
std::optional<int> voiceChangesHeight() const noexcept;
bool velocityVisible() const noexcept;
bool automationVisible() const noexcept;
bool voiceChangesVisible() const noexcept;
EditorDrawerPage activePage() const noexcept;
void applyState(DrawerSectionState velocity, DrawerSectionState automation,
                DrawerSectionState voiceChanges, EditorDrawerPage activePage);
```
Add `effectiveVoiceChangesBodyHeight()`, pointer, optional height, toggle, handle.

Toggle: object `voiceChangesDrawerToggle`; icon `:/icons/flat-music.svg` mask; accessible/tooltip `Show or hide voice changes (P)`; same icon-only style. Handle `voiceChangesResizeHandle`, accessible/tooltip `Resize voice changes pane`; add stylesheet selectors. Raise all toggles; bar under them.

Default Voice body `m_chrome.minBody`. Preferred height counts 3 handles/bodies. Apply has 3 blockers/heights/visibility. Page mapping exhaustive. Focus active, else first visible visual order VoiceChanges→Velocity→Automations. Cancel all visible independently. Resize filter maps 3 handles, subtracts sum of both other bodies and all handles, updates only target optional. Detent remains visible PSG Velocity only.

Top-to-bottom arrange: Voice handle/body; Velocity handle/body (existing inset); Automation handle/body; bar. Voice spans width. Under host clamp allocate Voice first, preserve Automation second, Velocity remainder; no negative geometry. Toggle order left-right VoiceChanges, Automations, Velocity in same centered piano-key region. Detent stays Velocity body/gutter. Add new widgets to occupiedRegion.

### MainWindow action and shortcut

Replace `toggleDrawerPage(bool automation)` with `toggleDrawerPage(EditorDrawerPage page)`. Pass explicit enums; switch for status. Add `m_voiceChangesDrawerAction`:
```cpp
m_voiceChangesDrawerAction = viewMenu->addAction(tr("Voice &Changes"));
m_voiceChangesDrawerAction->setObjectName(QStringLiteral("voiceChangesDrawerWindowAction"));
m_voiceChangesDrawerAction->setShortcut(QKeySequence(Qt::Key_P));
m_voiceChangesDrawerAction->setShortcutContext(Qt::WindowShortcut);
m_voiceChangesDrawerAction->setToolTip(tr("Show or hide voice changes (P)"));
```
P = Program Change and has no current bare-key binding; menu mnemonic C, accessible/window shortcut P. Event-list disable/re-enable all 3.

### SongView wiring

SongView still constructs only EditorDrawer; EditorDrawer constructs area. Add to actual `SongView::timelineBands()`:
```cpp
{*m_editorDrawer->voiceChangeArea(), m_editorDrawer->voiceChangeArea()->plotOrigin()},
```
Place beside drawer bands for playhead overlay/theme grid refresh initially and after refreshGeometry.

Add private `refreshVoiceChangePage()` and update:
- setDocument documentChanged lambda: area `documentChanged()` before refreshDrawerPages.
- notifyDrawerSongChanged: area `songChanged()`; covers song swap and setVoicegroup.
- refreshDrawerPages visible VoiceChanges branch.
- refreshVoiceChangePage calls area refreshLiveState(drawerPageLiveState()).
- refreshAllDrawerPages sends same captured live state to 3.
- onTracksRemapped calls area tracksRemapped beside Velocity after SongView state remap.
- setPlayheadSample visible VoiceChanges calls presentPlayhead; retain voiceContext before/after crossing refresh.
- drawercoordination state height/visibility/toggle/has-visible switches exhaustive over voiceChanges.
- include new complete header where used.
Primary track changes already end in refreshDrawerPages; area compares current primary with captured track and rebuilds.

### VoiceChangeLane → VoiceChangeArea extraction map

|Old|New|
|---|---|
|ctor AutomationPage*|ctor SongView&, TimelineSurface/geometry/fonts/tracking/click focus|
|rebuild(track,width,top,geometry)|rebuildVisualState captures primary/clears/invalidate; DrawerSections owns QWidget geometry|
|paint(...)|paintContent override via owner state/helpers|
|bounds/height/contains|delete; rect/event delivery/plotRect|
|cancel|cancelInteraction incl. Pan/grab/hover|
|clearHover(area)|parameterless clearHover invalidating self|
|invalidateFontCache|FontChange rebuild fonts/geometry/visual|
|mouse press/double/update hover|QWidget event overrides|
|showPicker(area,global,geometry)|showPicker(global), SongView picker/time/grid, SongDocument commits|
|showContextMenu|same retargeted to ui::ContextMenu(this)|
|voiceMarkerAt(area,x,geometry,out)|voiceMarkerAt(x,out), DPR + markerHitRadius|
|plotRect(geometry)|plotRect from rect/origin|
|voiceSlotAt/paintTextFor/font cache|move, replace page access by owner, translations by tr|

Delete AutomationCanvas/AutomationPage friendship. Use only public SongView/SongDocument. Retarget menu parent, mapping, invalidation, grid, picker.

### Geometry and painting

1. Fill `song_view_piano_roll_background`; bottom separator `song_view_separator`.
2. Full-height gutter [0,plotOrigin), plot [plotOrigin,width). Use TwoLineTextLayout, existing lane-title typography, noteName; no hardcoded pixels.
3. Gutter `Voice`; secondary `%n change(s) · double-click to edit` or `no voice set · double-click to add`.
4. `m_owner.paintGrid(painter,plot,plotOrigin())`; no AutomationCanvas fallback because SongView currently always paints/returns true.
5. Held interval tick 0/firstProgram→first change, then each change→next/song end; clip plot; track identity color alpha 18.
6. Two-physical-pixel (`singlePixel()+singlePixel()`) track-color vertical marker each change plus `NNN name (type)` label. Preserve stair-step/elision; all geometry via layout primitives.
7. Right-align current voiceContext: playback tick if playing, edit cursor otherwise; `No voice` unresolved.
8. Preserve dotted hover line and `→ NNN name (type)` held label; suppress held label directly over marker.
9. Paint dashed edit cursor locally; no AutomationCanvas helper retained only for page.
10. Empty: no timeline/valid track `No track selected`; no document `Voice changes are read-only`; unresolved voice `No voice`; null-safe.
Invalidate caches on song/voicegroup/track. No avoidable per-frame copies; reserve layout vector using model voices size.

### Interaction and exact commits

- Left plot press focuses/accepts; gutter consumed; no node/pencil/sweep.
- Left double-click plot opens picker. Hit marker radius uses exact tick; otherwise clamp raw tick≥0 and snapTick(raw,false).
- Picker title `Change voice` or `Insert voice change`; initial marker value or voiceSlotAt. Exact calls:
```cpp
document->addLanePoint(track, DOC_CC_VOICE, tick, selectedVoice);
document->moveLanePoints({{track, DOC_CC_VOICE, existing, tick, selectedVoice}});
```
No value change → no commit/refresh. Real commit refreshAllDrawerPages; documentChanged is revision authority.
- Right plot context: marker `Change voice`,`Delete`; empty `Insert voice change`. Delete exact:
```cpp
document->deleteLanePoints(track, DOC_CC_VOICE, {markerPoint});
```
Then refresh all. Suppress synthesized QContextMenuEvent to avoid double menu.
- Undo remains SongDocument exact labels `add voice change`, `change voice`, `delete voice change(s)` (`songdocument_xcmd.cpp:146,349,397`); no page undo text.
- Hover fine-snaps; exact marker tick; dotted line; held label only away marker; clear on leave/hide/focus/song/doc/track/Escape/cancel.
- Middle Pan and wheel mirror VelocityArea: follow pause, editor horizontal scroll; Shift/horizontal scroll; other wheel zoom timeline at x-origin. No row resize/node/pencil/sweep/ramp/time selection.

### Refresh semantics

- songChanged: cancel; reset live/track/playhead/hover/text caches; capture primary; rebuild.
- refreshLiveState: recapture primary first. Track, revision, zoom, h-scroll, cursor, track color, playback mode, or governing voice change updates/invalidate. Playhead-only within held span uses presentPlayhead without rebuilding marker/text caches.
- presentPlayhead updates live tick and invalidates when displayed context changes; shared overlay paints line.
- documentChanged cancels, clears hover/change count, recaptures primary, rebuilds before live refresh.
- tracksRemapped owns no persistent track id; call documentChanged after SongView full remap.
- contentGeometryChanged resolves hover bounds/invalidate; widget geometry replaces old rebuild width/top.
- FontChange rebuild typography + all font-relative geometry.
- Commits refresh all pages; primary through selection observer; voicegroup through setVoicegroup→notifyDrawerSongChanged.

### AutomationCanvas clean removal

Final production search `VoiceChangeLane|m_voiceLane|contentTopInset` = zero.
- header remove voice include, contentTopInset, friend, member; `layoutLaneStack()` no arg.
- ctor remove initializer.
- refreshGeometry/wheel height/row-resize call no-arg.
- FontChange remove voice cache.
- rebuildRows remove voice track/show/doc/model scan; row data/selection then no-arg layout.
- layoutLaneStack remove voice rebuild; minimumHeight(...,0).
- rebuildNodeStack CC top `layout::space(Zero)`.
- addLaneStripTop returns 0 when no non-Tempo CC.
- cancel remove voice cancel.
- input remove voice hover clear/contains/press/double/move/leave branches; preserve Tempo/CC precedence.
- paint remove voice paint.
- remove plain-grid fallback only if AutomationCanvas no caller; keep edit-cursor helper while automation uses it.
- update min-height/top/tests to zero; no invisible reserve.
- remove VoiceChangeLane assertions/includes/friend expectations.

## Sequence

1. State/enum/projection/MainWindow persistence+routing.
2. New area lifecycle/geometry/paint/hover/picker/commits/context/camera+CMake.
3. EditorDrawer/DrawerSections ownership, actions, layout, focus, resize, mask.
4. SongView timeline/document/song/selection/remap/live/playhead.
5. Canvas removal/inset math/delete old files.
6. Checks, retaining 56 registered.
7. Docs/vocabulary/supersession.
8. Search/format/targeted checks/build/full verify.

Steps 1 and 2 parallel; later consumption waits for fixed interfaces. No shims.

## Edge Cases

- No song/document/voicegroup/valid primary/nonzero timeline.
- Primary changes hidden then open: rebuild current state, not stale track.
- Voicegroup pointer changes without doc revision: refresh cached names/types.
- Tick-0 marker versus firstProgram: explicit governs; deletion reveals initial.
- Same-tick imported points: fresh effective DocLanePoint/SongDocument replacement semantics.
- Camera lead padding before tick 0: clamp before snap.
- Edge elision, dense stair labels, clipped hover dirties.
- Picker cancel/same value/null doc/document changes around modal: no empty undo.
- Right gutter vs plot, synthesized context event, deleting last change.
- All 8 visibility combinations, all hidden, active hidden.
- Host too short: no negative geometry/focus invisible/misplaced bar.
- Resize every page with others visible; persist optional/default heights.
- Event-list disable/restore all 3.
- Playback crossings, stopped cursor, zoom/scroll/font/DPR/theme, undo/redo/remap.

## Risks and notes

- **Friendship:** public SongView/local helpers only; no new friendship/page adapter.
- **CC inset:** minimum height, CC y, add strip, hover/hit, cursor checks, scroll extents must change together.
- **Saturation:** count 3 handles and both other bodies while resizing.
- **Detent:** visible PSG Velocity only; Voice must not expose/change/reposition.
- **Focus:** include third canvas/descendants in ownership/filter/fallback.
- **Menu duplication:** right press + synthesized context needs one suppression path.
- **Voice cache lifetime:** revalidate LoadedVoiceGroup on songChanged; never retain ToneData across refresh.
- **Shortcut:** window P, menu mnemonic C, accessible P; current keymap no bare P/C; routing checks catch future conflict; internal drawer actions shortcut-free.
- **Terminology:** UI/page plural Voice Changes; event/surface singular; storage remains DOC_CC_VOICE.
- **Pixels:** every size/stroke/hit radius via fontPx/fontPxF/space/singlePixel; color alpha/ticks/program values aren't pixel geometry.

## Verification

### Automated checklist

1. clang-format all changed/new C++; formatting check clean.
2. Scoped searches:
   - no production `VoiceChangeLane|m_voiceLane|contentTopInset`;
   - every EditorDrawerPage switch has all 3;
   - voiceChanges in state projection, persistence, layout, SongView coordination, checks.
3. Targeted drawer/automation/routing filters.
4. `deno task build:app` succeeds.
5. `deno task verify` reports **56/56 PASS**.

### Behavioral/visual checklist

- Toggle all 3 from bar and View/window; test 8 combinations.
- Stack Voice→Velocity→Automation→bar; each handle persists only own height.
- Detent only visible PSG Velocity.
- Change primary/voicegroup open/hidden; labels/context refresh.
- Double-click empty insert/existing edit; right empty insert/marker change+delete; cancel/no-change no undo.
- Undo/redo each; inspect exact labels.
- Hover dotted line/held label correctly on/off marker.
- Compare markers, labels/stair/elision, current readout, grid, cursor, track color to former appearance.
- Held fills tick 0→song end without gaps/gutter bleed.
- Pan/horizontal wheel/zoom keeps bands aligned.
- Shortcut opening does not steal hotkey focus; mouse focus/hide/switch fallback; all-hidden returns content.
- Event-list disables/re-enables all routes.
- Automation first CC y=0, no blank reserve; Tempo/CC paint/hit/resize/scroll unchanged.

## Acceptance criteria

- Standalone VoiceChangeArea in voicechangearea/ is sole Voice Change strip UI owner.
- Persisted VoiceChanges/voiceChanges third page independently toggles/resizes.
- Voice top; Velocity/Automation retain relative order.
- Insert/change/delete, picker, hover, spans, markers, current program, grid, cursor, pan/zoom, undo/redo, track/voicegroup refresh work.
- Former visual vocabulary preserved with specified held fill addition.
- Old files/type and all canvas voice logic/inset/friendship/dispatch/paint deleted.
- P WindowShortcut/accessibility works; internal actions shortcut-free.
- CC/Tempo geometry and Velocity detent/focus correct.
- clang-format clean; build succeeds; verify 56/56.

## Critical Files

- `src/ui/editordrawer/voicechangelane.h:1-91`, `.cpp:27-504` — behavior/commits.
- `velocityarea/velocityarea.h:27-177`, `.cpp:47-260`, `_interaction.cpp:259-505`, `_paint.cpp:44-200` — TimelineSurface template.
- `editordrawer.cpp:17-296`, `.h:1-91` — ownership/state/focus/actions.
- `drawersections.cpp:71-521`, `.h:1-91` — chrome/sizing/resize/layout/mask/detent.
- `editorviewstate.h:12-82`, `.cpp:6-18`.
- AutomationCanvas header; cpp `17-235,396-425`; input `35-100,250-310,400-420,500-510`; paint `120-140`.
- `songview.cpp:101-109,172-178,226-334,428-499,528-560`; drawercoordination `14-179`; trackvoiceops `226-250,379-437`; songview.h `96-220,294-405,500-612`.
- `mainwindow.cpp:92-148,358-375,1103-1135` and header declarations.
- `songdocument_xcmd.cpp:130-150,320-355,380-400`.
- `CMakeLists.txt:315-356,554-588`, `resources/flat-music.svg`.
- Drawer/automation/gesture/routing checks in inventory.

## Suggested subagent decomposition

Use fixed contract EditorDrawerPage::VoiceChanges, declaration above, state `voiceChanges`; avoid overlap:

1. **State/enum + DrawerSections agent:** state, EditorDrawer/DrawerSections, MainWindow persistence/actions; owns 3-page switches/layout/focus.
2. **VoiceChangeArea extraction agent:** new module + feature helper; owns paint/hover/picker/menu/commits.
3. **AutomationCanvas removal + SongView wiring agent:** canvas, SongView, CMake, stale checks; consumes fixed interface and deletes old only after extraction.
4. **Reviewer:** exhaustive enum/friendship/inset/resize/focus/detent/commit parity/test quality; final one format/build/56-check pass.

Agents 1 and 2 concurrent. Agent 3 waits for header/accessor before deletion/final wiring. Reviewer adds no aliases/shims.
