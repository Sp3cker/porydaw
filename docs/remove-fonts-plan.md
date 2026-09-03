# Remove System Fonts and Runtime Font Refresh

## Status

Planned. This document changes no production behavior by itself.

## Goal

Remove the user-facing **Use System Font** feature and the runtime font-change machinery it
requires. Porydaw installs its bundled Atkinson fonts during application startup and keeps those
fonts for the lifetime of the process.

This plan must land before `docs/qt-quick-track-headers-plan.md`. The track-header implementation
must start from the fixed-font contract rather than add another runtime font-refresh path.

## Fixed product contract

- Porydaw always uses the bundled proportional and monospace faces.
- The platform application font is read only at startup to obtain the base pixel size used by
  `layout::initialize()`.
- After startup, Porydaw does not support changing its application font, a `SongView` font, or a
  timeline input host font.
- Themes may still change colors and styles at runtime.
- Moving a window between screens and changing device pixel ratio remain supported.
- Resize-driven geometry remains supported.
- `themes::apply()` still restores the bundled body font if a desktop style or portal replaces the
  application font. That is a defensive reset to the fixed font, not a supported alternate-font
  mode.
- `ui::installOffscreenSystemFont()` remains. It runs before bundled-font installation and avoids a
  macOS CoreText alias-resolution problem in offscreen checks; it is not the removed preference.
- Existing explicit semantic fonts such as bold, italic, caption, table mono, and note-name fonts
  remain. They are derived once from the fixed bundled body font where a module caches them.

An old `systemFont` value may remain in a user's `QSettings`. Porydaw stops reading it. Do not add a
settings migration solely to erase an ignored value.

## Current runtime path to delete

1. `MainWindow` reads `systemFont` before restoring the theme.
2. The **Use System Font** action calls `typography::setUseSystemFont()`.
3. The action calls `QApplication::setFont()`.
4. `resetInheritedWidgetFonts()` walks every widget and clears inherited fonts.
5. `ThemeController::discardPreview()` reapplies the theme and repolishes the widget tree.
6. Qt emits `FontChange` and `ApplicationFontChange` events.
7. widgets recalculate heights, text layouts, font caches, Quick models, and paint geometry.
8. checks mutate fonts at runtime to verify that path.

The target has no step 1 through 8. Startup installs one font set. Runtime theme and screen events
continue through their own existing paths.

## Typography target

Keep this interface in `src/ui/typography.h`:

```cpp
bool installBundledFonts(QApplication &application);
std::optional<int> baseFontPx();
std::optional<QFont> bodyFont();

QFont bodyMono(const QFont &body);
QFont tableMono(const QFont &body);
QFont caption(const QFont &source);
QFont noteName(const QFont &source);
QFont regular(const QFont &source);
QFont bold(const QFont &source);
QFont italic(const QFont &source);
std::optional<QFont> fitted(const QFont &base, int availableHeight);
QPointF glyphCenteringOffset(const QFont &reference, const QFont &displayed, QStringView text);
```

Delete:

```cpp
void setUseSystemFont(bool preferred);
QString systemFontFamily();
QString systemMonoFamily();
```

In `typography.cpp`:

- delete `systemFontPreferred`, `capturedPlatformFont`, `capturedFixedFamily`, `systemBody()`, and
  `bundledBody()`;
- keep `capturedBaseFontPx` and `installedBodyFont`;
- build the bundled body from `application.font()` inside `installBundledFonts()` and assign that
  font directly to `installedBodyFont` after installation succeeds;
- make `bodyMono()` always select `Atkinson Hyperlegible Mono`;
- make `caption()` always select the bundled proportional face;
- retain `fitted()` and `glyphCenteringOffset()` unchanged;
- retain tabular numbers, weights, and font registration as they work today.

`Typography` remains the module that installs and derives semantic fonts. It no longer exposes a
runtime mode.

## Runtime event cleanup

Remove only font cases from handlers that also own supported events:

| Owner | Delete | Retain |
| --- | --- | --- |
| `SongView::event()` | `FontChange`, `ApplicationFontChange`, and the font-triggered `refreshGeometry()` | palette, style, theme, screen, DPR, show, and WinId handling |
| `PlayheadOverlay::changeEvent()` | `FontChange -> synchronizeGeometry()` | palette and style color refresh |
| `EventListView::changeEvent()` | `ApplicationFontChange` | `StyleChange` font-role refresh after stylesheet changes |
| `AutomationPage::event()` | the `FontChange` geometry/background block | style, theme, palette, hide, and deactivation handling |
| `DrawerSections::changeEvent()` | the `FontChange` switch case | style/theme geometry publication and palette-driven icon refresh |
| `PolyphonyPanel::changeEvent()` | heading-font refresh on `FontChange` | palette refresh for existing log rows |

Remove whole overrides when their only job is runtime font repair:

- `KeyboardShortcutsWidget::changeEvent()`;
- `SamplePickerButton::changeEvent()`;
- `VoicePickerDialog::event()`;
- the private polyphony table widget's `changeEvent()`;
- `TrackHeaderRow::event()` and `TrackHeaderPanel::event()` if the fixed-font cleanup lands before
  the Quick track-header cutover. If those widget classes have already been deleted, make no
  replacement.

Fonts and font metrics that these modules need must be set during construction, model rebuild, or
input-host attachment as they already are. Do not add a new application-wide font notification.

## Fixed-font Quick host contract

`TimelineInputHost::font()` remains because non-widget timeline modules need a font to construct
their initial text presentation. Its value is fixed after the input item is created.

Make these one-for-one interface changes; do not add a second notification interface:

```cpp
// TimelineInputItem
void setHostPalette(const QPalette &palette);
void notifyHostEnvironmentChanged();

// TimelineBandInteraction
virtual void hostEnvironmentChanged() {}
```

Replace `setHostAppearance(const QFont &, const QPalette &)` and
`notifyHostAppearanceChanged()`. `TimelineInputItem` keeps the font captured from `qGuiApp->font()`
in its constructor and has no runtime font setter. `TimelineQuickView::syncAppearance()` updates
only the host palette, calls `notifyHostEnvironmentChanged()`, refreshes Quick chrome, and requests
the same paint domains it does today.

`hostEnvironmentChanged()` continues to cover Quick item size, DPR, palette, and theme effects. It
does not mean that fonts changed. Apply these exact implementation rules:

- `TimeRuler`: remove the override. `attachInputHost()` performs its one font/metric setup through
  `refreshGeometry()`.
- `OtherStrip`: remove the override. Its layout-token geometry is resolved in its constructor.
- `PianoRoll`: keep the override under the new name, but remove `rebuildFontCache()`. Continue to
  resolve non-font geometry, reload DPR-dependent cursors, invalidate row edges, and request the
  full roll update.
- `VoiceChangeArea`: keep the override under the new name, but remove `rebuildFonts()`. Continue to
  resolve geometry and rebuild visual state.
- `VelocityArea`: keep the override under the new name, but remove `rebuildFonts()`. Continue to
  resolve geometry and rebuild visual state.
- `AutomationCanvas`: `attachInputHost()` performs `refreshGeometry()`, `rebuildFontCache()`, axis
  setup, and the initial update once. The renamed runtime hook compares only palette and DPR, not
  font. Delete `m_hostFont`. Do not call `rebuildFontCache()` or
  `NodeLaneHoverState::invalidateFontCache()` from the runtime hook. Preserve cursor-DPR reset,
  non-font hover cache invalidation, axis rebuild, and Quick update.
- `NodeLaneHoverState`: delete `invalidateFontCache()` after its only runtime caller is removed. Its
  value-label font cache begins invalid and initializes lazily from the fixed host font.

Do not remove resize callbacks, DPR callbacks, palette publication, or Quick dirty-domain requests
as part of this plan.

## Main-window deletion

In `src/mainwindow.cpp`, delete:

- `kSystemFontKey`;
- `resetInheritedWidgetFonts()`;
- the constructor call that restores `setUseSystemFont()` before theme restore;
- the **Use System Font** action, check state, key binding, settings write, application-font swap,
  widget reset, and toggle-triggered `discardPreview()`;
- comments that describe typeface as an app-wide preference.

In `src/ui/keymap.cpp`, delete the `view.system_font` command definition. Do not replace it with a
disabled action or hidden compatibility command.

## Checks

Update checks to prove the fixed contract rather than preserve deleted behavior:

- `fontcheck.cpp`: delete the system-family, system-mono, enable, disable, and polished-widget
  toggle assertions. Keep bundled-font registration, semantic face/size/weight, fitting, tabular
  numbers, and the defensive `themes::apply()` body-font restoration check.
- `hostcheck.cpp`: remove the block that assigns a distinct `SongView` font and expects Quick input
  items to follow it. Keep the distinct-palette assertion, geometry publication, visibility, and
  DPR coverage.
- `rollcheckautomation_tempo_paint.cpp`: delete the system-font mutation and the assertions that
  automation text and hover models rebuild onto that alternate font. Keep initial retained-text,
  placement, opacity, and hover-label coverage. Do not replace the deleted test with another
  runtime font mutation. Delete `originalFont` and the three font-reset lines at the start of the
  `restore` lambda; the test does not change the palette, so do not add a palette reset or an
  environment-change notification there. Keep the document, undo, selection, drawer-height, lane,
  and pointer restoration that follows.
- `rollcheckplayhead.cpp`: delete the section that enlarges the application and `SongView` fonts,
  sends synthetic `FontChange`, and verifies font-refreshed band and triangle geometry. Keep
  ordinary playhead placement, host union, screen/DPR, theme color, and lifecycle coverage.
- In `automationgesturecheck`, rename `canvasHostAppearanceChanged()` and both calls to
  `canvasHostEnvironmentChanged()`, then make it call `canvas().hostEnvironmentChanged()`.
- In `mainwindowroutingcheck.cpp`, rename `notifyHostAppearanceChanged()` to
  `notifyHostEnvironmentChanged()` without adding font mutation.

## Active track-header plan correction

Keep `docs/qt-quick-track-headers-plan.md` aligned before starting its implementation:

- remove font change from the model invalidation table and scroll re-clamp triggers;
- state that header fonts and text metrics resolve on input-host attachment or model creation;
- keep theme color and DPR refresh;
- make the planned `TrackHeaderModel` implement `hostEnvironmentChanged()`, not
  `hostAppearanceChanged()`;
- do not add a host-font mutation case to `trackheaderquickcheck`.

Do not alter the rest of the reviewed track-header ownership, geometry, input, or cutover design.

## Implementation phases

Before Phase 0, commit this plan and the fixed-font corrections to the active track-header plan as
a docs-only planning commit. Do not include unrelated dirty paths.

For each implementation phase after Phase 0, use this sequence once at the phase boundary:

1. implement the phase and run its listed checks;
2. while the phase changes are still uncommitted, run a fresh thermonuclear maintainability review
   on that phase's diff;
3. verify each finding against the code, correct every valid finding, and rerun the affected checks;
4. commit the completed phase before starting the next phase.

Do not let the reviewer edit files, and do not carry a known valid finding into the next phase.

### Phase 0: Freeze the baseline

Record the commit, dirty paths, and existing known red piano-selection pixel assertion. Preserve
the archived timeline-input-plan move and the active track-header plan. Build checks and run:

- `fontcheck`
- `host-integration`
- `rollcheck`

Record any existing failures before changing code.

### Phase 1: Remove the feature and simplify Typography

Delete the MainWindow action, setting, keymap command, widget reset, and Typography mode. Update
`fontcheck` and remove the system-font section from `rollcheckautomation_tempo_paint.cpp` in the
same slice. Leave its Quick-host interface names unchanged until Phase 3.

Verification:

- build the app and checks;
- run `fontcheck`;
- search for `setUseSystemFont`, `systemFontFamily`, `systemMonoFamily`, `kSystemFontKey`,
  `resetInheritedWidgetFonts`, and `view.system_font`; every search must be empty.

### Phase 2: Remove direct widget font-change reactions

Apply the runtime event cleanup table and update `rollcheckplayhead.cpp`.

Verification:

- build the app and checks;
- run `rollcheck` and the focused UI checks owning each edited module;
- production code under `src/` must contain no `QEvent::FontChange` or
  `QEvent::ApplicationFontChange` handler.

### Phase 3: Make the Quick font handoff startup-only

Apply the fixed-font Quick host contract, update `hostcheck.cpp`, the automation gesture rig, and
`mainwindowroutingcheck.cpp`, and delete the unused node-lane font-cache invalidator.

Verification:

- build the app and checks;
- run `host-integration` and `rollcheck`;
- verify palette/theme changes still recolor Quick content;
- verify a resize and a DPR/screen transition still update band geometry and DPR-dependent cursors;
- search for `setHostAppearance`, `notifyHostAppearanceChanged`, `hostAppearanceChanged`, and
  `invalidateFontCache`; every search must be empty.

### Phase 4: Align the pending track-header plan and finish

Apply only the fixed-font corrections listed above to the pending track-header plan. Run formatting
on changed C++ files, `git diff --check`, the focused checks, and then the full serial
`deno task verify` suite.

The known right-drag piano-selection pixel assertion remains outside this plan. Report it as an
existing failure if it is still red; do not weaken or delete it here.

## Final invariants

- The app exposes no system-font setting, action, command, or saved-state read.
- Typography has no runtime mode or system-family branch.
- Production code does not react to `FontChange` or `ApplicationFontChange`.
- Timeline input items publish a fixed font and a mutable palette.
- Font caches initialize once and are not invalidated because a font changed.
- Theme, palette, resize, screen, and DPR behavior remain supported.
- Startup still uses the platform font pixel size to scale layout and then installs bundled fonts.
- macOS offscreen checks retain their startup font workaround.
- No replacement font-refresh bus, feature flag, compatibility path, or settings migration is
  introduced.

## File map

Feature and typography:

- `src/mainwindow.cpp`
- `src/ui/keymap.cpp`
- `src/ui/typography.h`
- `src/ui/typography.cpp`

Direct runtime event cleanup:

- `src/ui/songview.cpp`
- `src/ui/playheadoverlay.cpp`
- `src/ui/eventlistview.cpp`
- `src/ui/keyboardshortcutsdialog.h`
- `src/ui/keyboardshortcutsdialog.cpp`
- `src/ui/samplepicker.h`
- `src/ui/samplepicker.cpp`
- `src/ui/polyphonypanel.cpp`
- `src/ui/songview/voicepicker.h`
- `src/ui/songview/voicepicker.cpp`
- `src/ui/editordrawer/automationpage.cpp`
- `src/ui/editordrawer/drawersections.cpp`
- `src/ui/songview/trackheaderrow.h` and `.cpp` when still present
- `src/ui/songview/trackheaderpanel.h` and `.cpp` when still present

Quick host and timeline modules:

- `src/ui/songview/quick/timelineinput.h`
- `src/ui/songview/quick/timelineinputitem.h`
- `src/ui/songview/quick/timelineinputitem.cpp`
- `src/ui/songview/quick/timelinequickview.cpp`
- `src/ui/songview/timeruler.h`
- `src/ui/songview/timeruler.cpp`
- `src/ui/songview/otherstrip.h`
- `src/ui/songview/otherstrip.cpp`
- `src/ui/songview/pianoroll.h`
- `src/ui/songview/pianoroll.cpp`
- `src/ui/editordrawer/automationcanvas.h`
- `src/ui/editordrawer/automationcanvas.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea.h`
- `src/ui/editordrawer/velocityarea/velocityarea.cpp`
- `src/ui/editordrawer/voicechangearea/voicechangearea.h`
- `src/ui/editordrawer/voicechangearea/voicechangearea.cpp`
- `src/ui/editordrawer/nodelane/hover.h`
- `src/ui/editordrawer/nodelane/hover.cpp`

Checks and plan alignment:

- `src/checks/fontcheck.cpp`
- `src/checks/hostcheck.cpp`
- `src/checks/automationgesturecheck/cursor.cpp`
- `src/checks/automationgesturecheck/rig.h`
- `src/checks/automationgesturecheck/rig.cpp`
- `src/checks/mainwindowroutingcheck.cpp`
- `src/checks/rollcheckautomation_tempo_paint.cpp`
- `src/checks/rollcheckplayhead.cpp`
- `docs/qt-quick-track-headers-plan.md`
