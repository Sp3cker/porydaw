# Editor drawer reimplementation

## Status

This document is the implementation specification for rebuilding the editor
drawer, its automation page, and its velocity page on the current integration
branch.

The branch that contains the reference implementation is a UX oracle, not a
source of commits to port. Its history mixes the requested work with formatting
churn, experiments, build changes, and unrelated fixes. Reimplement the
behavior described here from a fresh branch based on the current integration
tip. Do not cherry-pick or merge the reference branch.

This specification was audited against reference implementation commit
`52fd478f27594ffe410472fb8d4a62e792378f16` on 2026-07-29. Later commits on
that branch do not amend this contract unless this document also changes.
The integration tip observed during that audit was
`4f3735f63542a16931c5c3085f5a2f08b4c8b511`; it is evidence, not permission to
skip a fresh fetch before implementation. `upstream/main` is the authoritative
integration ref unless the integrator names another one.

Normative terms such as **must**, **must not**, and **should** define the
required result. A detail observed in the reference branch but not required
here is not part of the contract.

## Goals

The reimplementation must:

1. Add an overlay editor drawer with Automations and Velocity pages.
2. Preserve the existing automation editor while placing it in the drawer and
   adding the lane, range, and gesture behavior defined below.
3. Add a velocity editor that shares the piano roll's note selection.
4. Show intrinsic PSG velocity graduations without changing exact stored MIDI
   velocities.
5. Persist view-only drawer and lane state per song without changing MIDI.
6. Keep playback rendering and interaction responsive.
7. Arrive as a short, clear series of buildable commits.

## Non-goals

This work must not:

- Change audio playback, m4a mixing, or MIDI export semantics.
- Make velocity graduations depend on mixer automation.
- Add automation lane reordering or per-row collapse controls.
- Add velocity keyboard nudging, node tooltips, or extra focus targets.
- Replace the event list or change its editing behavior.
- Include theme experiments, color benchmarks, application-style changes,
  Visual Studio ignore rules, or unrelated editor sizing fixes.
- Import research scripts, screenshots, generated images, or abandoned test
  widgets from the reference branch.

## Terms and ownership

- **Drawer**: the bottom overlay that owns page choice, visibility, height,
  tabs, shortcuts, and focus return.
- **Automation row**: one tempo, voice, controller, or pitch-bend graph.
- **Lane identity**: an m4a engine-track slot plus a controller number. Pitch
  bend uses pseudo-controller `255`. It is not an SMF chunk index.
- **Velocity value**: the exact stored MIDI value from 1 through 127.
- **Effective velocity**: the value produced by mid2agb quantization.
- **PSG voice**: a GBA Square 1, Square 2, Programmable Wave, or Noise voice.
- **Intrinsic level**: a PSG hardware volume class derived from effective
  velocity and resolved voice type.
- **Representative**: the default exact velocity used when an edit moves into
  an intrinsic level.
- **Gesture snapshot**: the selection, axis, voice context, and starting values
  frozen at the start of a drag.

Keep the modules and their interfaces narrow:

- The drawer owns only layout and view state. It does not edit the song.
- The automation page owns automation display, selection, and gestures.
- The velocity page owns velocity display, note hit testing, and gestures.
- A velocity-axis model resolves continuous or intrinsic graduations without
  depending on widget state.
- `SongDocument` owns batch mutation and Undo commands.
- `SongView` connects shared timeline, selection, scrolling, and focus state.

The final file placement may follow the current codebase, but the reference
implementation used these seams:

- `src/ui/editordrawer.{h,cpp}`
- `src/ui/velocityarea.{h,cpp}`
- `src/ui/velocityaxis.{h,cpp}`
- `src/core/psgvelocitymodel.{h,cpp}`
- `src/ui/songview.{h,cpp}`
- `src/ui/viewsidecar.{h,cpp}`
- `src/core/songdocument.{h,cpp}`

## Refactoring rules

Apply Fowler-style refactoring principles throughout the rewrite:

- Start from the current integration tip and keep the program working.
- Make small, named, behavior-preserving structural changes.
- Add or strengthen a focused check before changing behavior at that seam.
- Separate refactoring commits from feature commits. A commit that changes
  structure must not also make an unrelated UX change.
- Compile and run the focused checks after each step.
- Prefer a series of safe transformations over a wholesale replacement.
- Remove duplication only when the next requested behavior needs the shared
  seam.
- Keep existing names and local style unless a rename makes the new interface
  clearer.
- Do not reformat whole files or clean adjacent code.
- If a step stops being behavior-preserving, name the intended behavior change
  in the commit and cover it with a check.

Each commit in the final series must build, pass its focused checks, and be
safe to review when applied in order. Revert dependent commits in reverse
order.

## Global behavior

The piano roll remains the primary editor. The drawer overlays its bottom edge;
opening or resizing the drawer must not change the roll or track-header model.
The piano roll, automation page, and velocity page share:

- selected track;
- selected notes;
- horizontal scroll and time zoom;
- edit cursor and playhead;
- grid and snap settings; and
- track color and voice context.

View-only actions must not alter MIDI, dirty the song, or create Undo entries.
Song edits must use `SongDocument` and create one Undo command per completed
gesture.

Any live drawer gesture must terminate safely when its page becomes hidden, the
drawer closes, the selected track or song changes, any document mutation, Undo,
Redo, reload, or replacement occurs, or the window loses the gesture. Escape
must do the same while a gesture is active.

Termination depends on the gesture:

- Discard a staged document edit, restore its preview snapshot, and create no
  Undo entry.
- Clear a provisional selection and restore the selection from gesture start.
- End view-only pan or resize capture but keep the scroll position or size
  already applied.

`SongDocument` exposes a monotonic revision. Increment it exactly once for each
successful mutation, load, Undo, or Redo, before any remap or general
document-change notification. Failed edits, no-ops, and view-only actions do
not increment it. Validate a batch's expected revision and every note address
before changing the document.

### Track-identity remapping

Automation view state belongs to a track owner, not a numbered slot. Any
mutation that changes SMF-chunk or engine-track identity or order must publish
one complete remap after the document rebuilds its track map and before the
general document-change notification. This includes move, insert, duplicate,
delete, raw edits that add the first or remove the last channel event in a
chunk, Undo, and Redo.

The remap contains:

- new SMF chunk index by old SMF chunk index; and
- new engine slot by old engine slot.

Use `-1` for a deleted owner. Do not publish a remap for a no-op or an identity
mutation. Consumers use the one event to update selected-track state,
multi-track scope, mute/solo state, event-list chunk anchoring, empty and hidden
lanes, and saved automation row state. Newly inserted owners receive defaults.

Checks must cover apply, Undo, and Redo for move, insert, duplicate, delete, and
the raw-edit transitions between metadata-only chunks and engine tracks. They
must also assert that the remap arrives before the general document-change
signal. Do not port the reference branch's unrelated event-list, mute/solo, or
follow-playhead changes while adding this seam.

## Editor drawer

### Layout

The drawer is an overlay, not a splitter. The main roll and track header retain
their full geometry under it.

| Element | Required geometry |
| --- | --- |
| Track-header gutter | 210 px |
| Piano keyboard | 52 px |
| Plot origin | 262 px from the left edge |
| Automation tab | first 105 px of the header gutter |
| Velocity tab | second 105 px of the header gutter |
| Resize handle | 4 px high, from x=210 through the plot's right edge |
| Default automation row | 48 px high |
| Add-lane strip | 20 px high |
| Minimum open drawer | 68 px, or the host height when smaller |
| Default open height | one fifth of the host height |
| Maximum open height | leave at least 120 px of roll when the host permits |

The tab row sits just above the open drawer. When closed, it sits at the host's
bottom edge and remains visible. The tabs are text-only, use normal checked
`QToolButton` styling, and do not take keyboard focus.

Dragging the resize handle upward with the left button grows the drawer.
Dragging it downward shrinks the drawer. Clamp the result to the limits above.
The handle uses the named splitter theme roles for normal and hover states.

### Pages and toggles

The drawer has two pages:

- `Automations`
- `Velocity`

A new song defaults to an open Automations page unless restored view state says
otherwise.

Clicking the tab for the visible page closes the drawer. Clicking the other tab
switches to that page and opens the drawer. The unmodified `A` and `V` keys
perform the same actions with `Qt::WindowShortcut` scope. These shortcuts are
local editor shortcuts, not entries in the configurable keymap.

There must be at most one active `A` route and one active `V` route per top
level window. Route them to MainWindow's active `SongView`, or disable every
inactive view's drawer shortcuts. With several song tabs open, a shortcut
changes and announces only the active tab. It must not change an inactive
view, its pending sidecar state, or its selected page. Event-list blocking is
based on the active tab.

Use these tab tooltips:

- `Show or hide automation lanes (A)`
- `Show or hide note velocities (V)`

Announce the resulting state with these exact strings:

- `Automation lanes shown`
- `Automation lanes hidden`
- `Velocity lane shown`
- `Velocity lane hidden`

Disable the `A` and `V` drawer shortcuts while the raw MIDI event list is
visible. Entering and leaving event-list mode does not otherwise change the
drawer's page or visibility.

### Focus and lifecycle

The tabs, stack, and automation scroll container do not take focus. The
automation and velocity canvases use click focus so their shared edit commands
work.

If a page switch hides the focused editor canvas, focus the newly shown
canvas. When the drawer closes while focus is inside it, return focus to the
main content.

A page switch or hide must:

- terminate live drawer gestures by the global rules;
- clear automation hover or preview state;
- update scrollbars;
- update the playhead overlay; and
- preserve the selected page and last open height.

There is no per-row collapse button. A user can hide the whole drawer, resize
it, or hide a controller lane.

### Per-song persistence

Store view state at:

```text
<project-root>/.porydaw/<song-label>.json
```

The sidecar is shared with other features. Read and write the drawer state
under the root `view` object. Preserve every unrelated root key and every
unknown key already present in `view`. Save with `QSaveFile`.

The view object includes the existing roll fields plus:

| Key | Value |
| --- | --- |
| `drawerVisible` | Boolean |
| `drawerPage` | `automations` or `velocity` |
| `splitter` | Legacy `[main-content height, drawer height]` array |
| `laneHeight` | Shared default automation-row height |
| `laneHeights` | Object keyed by typed automation-row identity |
| `laneRanges` | Object keyed by typed automation-row identity |
| `emptyLanes` | Array of lane identities |
| `hiddenLanes` | Array of lane identities |

Valid row keys are:

```text
tempo
voice:<track>
cc:<track>:<controller>
```

Tracks must be in `0...15`. A controller must be in `0...127`, or `255` for
pitch bend. Reject malformed, non-canonical, or out-of-range identities.
Missing, malformed, or unreadable state falls back silently to defaults.
Read or write failure must not interrupt song editing.

Each `emptyLanes` and `hiddenLanes` entry has this shape:

```json
{"track": 0, "cc": 1}
```

Here, `track` is an engine slot. Ignore one malformed row key or lane entry
without dropping other valid entries. An unknown `drawerPage` value falls back
to Automations.

The overlay uses only `splitter[1]` when restoring drawer height;
`splitter[0]` remains a positive compatibility value and must not shrink the
underlying roll. Missing or short arrays use the one-fifth default.

Clamp `laneHeight` and each `laneHeights` value to `28...128`. A
`laneRanges` value is an integer clamped to `0...127`; `0` means Auto and a
positive value is an exact fixed display maximum. Preserve valid non-menu
values such as 91 across load, track remap, and save. The menu exposes only the
five common choices defined below.

Persist row height and range state even after a row is hidden or deleted so
that recreating it restores its display. Save view state on song-tab close,
project switch, song replacement, and application close. Do not write the
sidecar on each drag update.

## Automations page

### Existing editor parity

The current integration branch already has an automation plot with point
editing, ramps, time selection, lane menus, scrolling, and row resizing.
Moving it into the drawer must preserve all current supported behavior unless
this document changes it.

Automation rows scroll vertically inside the drawer when they do not fit.
Disable an inner horizontal scrollbar; the editor's shared time scroll and zoom
continue to control the plot.

### Row context and order

Rows appear in this order:

1. Tempo.
2. Voice, when a document is attached or the primary selected track has program
   changes.
3. Visible controller lanes for the primary selected track.

Controller rows sort by track and controller number. Pitch bend, represented
by pseudo-controller `255`, comes last. Users cannot reorder rows.

The primary selected track chooses the rows shown. A multi-track header
selection may broaden track-scoped automation edits, but it does not add a
second set of rows to the drawer.

Hidden lanes still participate in track-scoped range edits. A lane-scoped time
selection includes only visible rows crossed by the selection.

### Add-lane strip

Show the 20 px add-lane strip only when a document is attached. Its menu lists
available parameters in this order:

1. `Modulation (MOD)` (CC1)
2. `Volume (VOL)` (CC7)
3. `Pan (PAN)` (CC10)
4. `Bend range (BENDR)` (CC20)
5. `LFO speed (LFOS)` (CC21)
6. `Pitch bend (BEND)`

Omit lanes that already exist or are hidden. After a separator, list hidden
lanes in their stored order as:

```text
Show: <parameter> (hidden)
```

If no new lane can be added, include one disabled item:

```text
All parameters already have lanes
```

That disabled item remains before the separator even when hidden lanes can
still be shown.

Adding an empty lane changes view state only. Once the lane receives its first
event, the document model owns its existence.

Label the strip `+ Add lane` with the named add-automation-lane theme role.
Either a left or right click on it opens this menu.

### Lane menu

Either a left or right click in a controller or pitch-bend row's gutter opens
its lane menu. The menu must provide:

| Action | Behavior |
| --- | --- |
| Copy lane | Copy the whole lane with absolute ticks; disable when empty |
| Paste lane (replace) | Replace the destination lane; enable only for one nonempty whole-lane clip; clamp destination values; create one Undo command |
| Hide lane | Hide the row without changing events or Undo history |
| Clear events | Remove all events but leave an empty row; disable when empty |
| Remove empty lane | Remove a view-only row that has no events |
| Delete lane | Confirm, then remove a nonempty lane and its events |

For eligible controller rows, add a `Value range` submenu:

- Auto (fit to data)
- 0–16
- 0–32
- 0–64
- 0–127 (full)

Do not show this submenu for pitch bend, pan, or tune. Modulation defaults to
Auto. Auto picks the smallest maximum from 16, 32, 64, and 127 that contains
the data. Other eligible lanes default to 127. If data exceeds a chosen range,
grow the display to include it; never clip data.

Removing or deleting a row must not erase its saved height or value range.

Use the existing announcement channel for successful lane actions:

```text
Showed the <name> lane
Hid the <name> lane
Copied the <name> lane (<count> point(s))
Replaced the <name> lane
```

### Pointer and wheel gestures

| Input | Result |
| --- | --- |
| Middle drag | Pan horizontal time and vertical lane scroll |
| Ctrl-wheel | Change all row heights by 4 px per notch, clamped to 28...128 px |
| Shift-wheel or horizontal wheel | Scroll time horizontally |
| Plain wheel over plot | Zoom time around the pointer |
| Plain wheel over gutter | Let the outer vertical scroll handle it |
| Left drag on row divider | Resize only that row |
| Other button on row divider | No action and no menu |

Ctrl-wheel pins the row under the pointer and scales any per-row overrides with
the shared height.

### Point editing

A point dot has a 7 px hit radius in both axes.

- Left-dragging a point moves it.
- Pressing and releasing a point without a change is a no-op.
- Left-dragging elsewhere paints a freehand sweep and replaces crossed grid
  cells. Fast pointer motion must fill every crossed cell.
- Shift-left-drag draws a ramp and takes priority over point grabbing.
- Alt applies the MIDI-clock grid.
- Normal endpoint snapping uses the editor's current snap rules.
- Ctrl magnetizes pan and tune to stored value 64, and pitch bend to zero, when
  the pointer is within about 8 px.

A right drag makes a half-open time selection across every visible row crossed
by the drag. Right-clicking inside that selection opens its menu. Outside a
selection, right-clicking within 9 px on the time axis deletes the nearby
point; its vertical distance does not matter.

Right-clicking an empty controller or tempo row clears the time selection.
Right-clicking an empty voice row does not.

Double-clicking opens exact value entry with these domains:

| Row | Entered value |
| --- | --- |
| Tempo | 1...999 |
| Pitch bend | -8192...8191 |
| Pan or tune | -64...63, stored as entered value + 64 |
| Other controller | 0...127 |

Treat the full double-click as one gesture. On blank plot space, do not commit
an interim point from its first click. Canceling the dialog changes nothing and
creates no Undo entry; accepting it creates at most one point and one Undo
entry. Editing an existing point is also one command and skips an unchanged
value.

During a live right-drag, Escape restores the time selection from gesture
start. When no pointer gesture is active, Escape clears the committed time
selection. It always discards an active document-edit preview.

### Voice row

Left-clicking an existing voice marker opens the `Change voice` picker,
initialized to that marker's voice. Commit only a different chosen voice.
Left-clicking empty space opens the `Insert voice change` picker at the snapped
tick, initialized to the voice already in effect there. Commit the chosen
voice. Right-clicking a marker deletes it.

Hovering empty space previews:

```text
→ NNN <short-name>
```

Do not draw the preview near an existing marker. Existing markers draw over
the preview label.

While playing, the current voice follows the rounded playhead tick. While
stopped, it follows the edit cursor.

### Drawing and hover

Draw automation as held-step curves. Show point dots when horizontal zoom is at
least 24 px per beat.

- Tempo uses its accent color.
- Controller rows retain track identity.
- Pitch bend draws a dashed center line.
- Hover shows the value in effect at the raw pointer tick.
- Before the first point, hover shows no value.

### Undo and track remapping

Each completed song-editing gesture creates one `SongEditCommand`. A view-only
operation creates none.

When tracks are deleted or reordered, remap:

- empty lanes;
- hidden lanes; and
- saved row heights and ranges.

Drop state owned by a deleted track. Keep state for surviving tracks under
their new numbers.

## Velocity page

### Data and shared selection

The page draws every note on the primary selected track. It uses the piano
roll's note selection rather than a second selection model.

The reference UI identifies a note by `(start tick, key)` with selected track
implicit. That is a reference defect. The reimplementation's opaque `NoteId`
must distinguish duplicate notes at the same track, tick, and key.

At gesture start, bind each selected `NoteId` to the exact document note
address, including SMF track and note-on index, plus the current document
revision. The binding is valid only for that revision. Any document mutation,
Undo, Redo, or reload cancels the live gesture. The batch mutation seam rejects
an entire stale-revision batch rather than applying part of it.

Add a duplicate-note selection, edit, and Undo regression before building the
velocity page. Failure to provide exact identity blocks the velocity UI work;
documenting the limitation is not an acceptable substitute.

A plain track-header click clears note selection, including a click on the
already-primary track, and refreshes the velocity axis.

A nonempty note selection chooses the intrinsic velocity context only when all
selected notes resolve to compatible PSG graduations. With no note selection,
resolve the current voice at:

- the rounded playhead tick while playing; or
- the edit cursor while stopped.

Use one helper for every drawer playhead lookup:

```text
drawerContextTick(t) = floor(max(0, t) + 0.5)
```

Return that result as an unsigned tick. Do not let one caller truncate while
another rounds.

Compatibility requires the same resolved voice type, the same graduation
count, and the same representative and audible flag for every graduation.
Square 1, Square 2, and Noise therefore do not share one selection axis even
though each has sixteen representatives. A mixed-type selection stays
continuous.

For a key-split voice, resolve selected notes by note key. With no selected
note, a top-level key split has no key context and stays continuous.

Use a continuous axis for DirectSound, a missing voicegroup, an invalid
program, nested key splits, or an incompatible selection. Freeze the resolved
axis, selection, and starting values for the full gesture.

### Continuous axis

The gutter ends at x=262 and the plot begins there. Place stored velocity 127
at the top and 1 at the bottom, with the standard vertical inset
`layout::Space::Three`.

Let `H` be the drawable vertical span from the y position for 127 to the y
position for 1. This is the page height minus the top and bottom
`layout::Space::Three` insets. Adapt ruler density to `H`:

| Drawable span `H` | Labels | Tick marks |
| --- | --- | --- |
| below 72 px | 127, 64, 1 | 127, 96, 64, 32, 1 |
| 72...99 px | 127, 64, 1 | 127, 112, 96, 80, 64, 48, 32, 16, 1 |
| 100...143 px | 127, 96, 64, 32, 1 | 127, 112, 96, 80, 64, 48, 32, 16, 1 |
| 144...287 px | 127, 112, 96, ..., 16, 1 | 127, 120, 112, ..., 8, 1 |
| 288 px or more | 127, 120, 112, ..., 8, 1 | 127, 123, 119, ..., 7, 1 |

Always include 1 and 127. Emphasize only the minimum and maximum active
selected or preview values.

During a relative note drag, hide static continuous-axis labels while keeping
ticks and live extrema visible. Do not hide labels during freehand painting.
Clicking one of the static labeled continuous ruler graduations sets all
selected notes to that exact value in one Undo command. Dynamic selected-value
extrema are not click targets.

### Intrinsic PSG axis

Store and Undo exact MIDI velocity in `1...127`. Derive the effective mid2agb
velocity for stored value `s` as:

```text
E = min(ceil(s / 4) * 4, 127)
```

Derive the 4-bit intrinsic level as:

```text
G = floor((E - 1) / 8)
```

This scale is intrinsic to the resolved voice type. It must not depend on CC7,
song volume, pan, rhythm pan, modulation, or any live mixer value.

Square 1, Square 2, and Noise expose 16 graduations with these
representatives:

```text
1, 12, 20, 28, 36, 44, 52, 60,
68, 76, 84, 92, 100, 108, 116, 127
```

Programmable Wave exposes five output classes:

| Stored velocity range | Output class | Representative |
| --- | --- | --- |
| 1...16 | mute | 1 |
| 17...48 | 25% | 32 |
| 49...80 | 50% | 64 |
| 81...112 | 75% | 96 |
| 113...127 | 100% | 127 |

Label each graduation:

```text
Volume <one-based-level-number> (<exact-value>)
```

Lay out five graduations in one column. Lay out more than eight in two
staggered columns. When notes span more than two active intrinsic levels,
emphasize only the lowest and highest.

If one exact selected value differs from the representative for its class,
replace that class's label value with the selected exact value. If selected
notes have conflicting exact values in one class, show the representative.
Do not draw a held-value ring or a separate silence cue. Keep the standard
`Volume N (value)` label even for a mute class.

For example, stored velocity 95 belongs to the same programmable-wave output
class as representative 96. A relative categorical drag that leaves that
class and returns to its starting class must restore 95. Moving to a different
class uses that class's representative. Typed `Set velocity` entry always
stores the typed exact value and never snaps to a representative.

Exact entry remains the piano roll's existing
`Set velocity… (<current>)` context action on the shared note selection. It
opens the `Note velocity` dialog with prompt `Velocity (1-127):`. The velocity
page adds no separate context menu or value dialog.

Clicking an intrinsic graduation label sets all selected notes to that label's
exact value in one Undo command.

If a note is incompatible with the currently detented axis, draw it at its
continuous stored-velocity position.

### Note drawing

Draw a duration stem at each note's y position and a node at its start tick.
Use the track color. A selected note has a selection-colored, thicker stem and
a selection ring around its node. There is no hover decoration.

Draw the selected track title as a quiet watermark. For an intrinsic axis,
also draw:

```text
<Voice> has N volume levels.
```

### Note hit testing and selection

A note is hit when the pointer is:

- within 6 px of its start node; or
- no more than 4 px vertically from its duration line, with x between 2 px
  before note start and 2 px after note end.

Selection behavior:

| Input | Result |
| --- | --- |
| Plain left press on notes | Keep selection if every hit is already selected; otherwise replace it with the hits |
| Ctrl-left press on notes | Toggle the hits |
| Ctrl-left drag | Union the hits into selection, then drag |
| Right drag | Replace selection with the box hits |
| Ctrl-right drag | Add the box hits to the existing selection |
| Stationary right click | Replace selection with the hits |
| Ctrl-right click without movement | Toggle the hits against the existing selection |

A right press in plot space starts a pending band and consumes its matching
context-menu event. Begin box preview only when movement reaches
`QApplication::startDragDistance()`, and commit it only on right release. A
stationary plain click on blank space clears selection; a stationary Ctrl-click
on blank space preserves it.

### Velocity editing gestures

A relative drag starts once the pointer moves at least 1 Manhattan pixel or the
intrinsic level changes.

On a continuous axis, apply one shared proposed-velocity delta to the gesture
snapshot. Clamp a DirectSound result to `1...127`. For each PSG note in an
otherwise incompatible mixed selection, convert the proposed result to that
note's own intrinsic representative. For example, a shared proposal of 65
commits Wave at 64, Square or Noise at 68, and DirectSound at 65 in one Undo
command. Exact-origin restoration applies only to a compatible categorical
gesture.

On an intrinsic axis, apply one shared level delta. Preserve each note's exact
starting value when the drag returns to its starting level. A move to another
level uses that level's representative.

A left press in blank plot space starts freehand painting at once. The initial
stationary stamp changes start nodes within 6 px on the x axis. During motion,
each segment changes every start node whose x lies between its two pointer
samples, inclusive. It does not hit duration stems. Interpolate pointer y at
each crossed node so a fast sweep does not leave gaps. A note compatible with
the frozen intrinsic axis uses the requested level's representative. An
incompatible note maps y continuously, then canonicalizes through that note's
own voice context; DirectSound and unresolved notes keep the continuous exact
value.

Other input:

| Input | Result |
| --- | --- |
| Middle drag | Pan time horizontally |
| Shift-wheel or horizontal wheel | Scroll time horizontally |
| Plain wheel over plot | Zoom time around the pointer |
| Plain wheel over gutter | No velocity-page action |
| Escape | Restore the gesture snapshot and commit nothing |

### Preview, mutation, and Undo

Drag and freehand updates are UI-only previews. On release, submit one batch to
`SongDocument::setNotesVelocities` and create one Undo command named:

```text
paint note velocities
```

The document seam must:

- address notes by stable document identity;
- accept the gesture's expected document revision;
- reject the whole batch before mutation if the revision or any note address is
  stale;
- deduplicate edits by SMF track and note-on index, with the last edit winning;
- clamp stored values to `1...127`;
- skip no-op edits;
- retain exact old values for Undo; and
- emit the normal document-change and playback-rebuild signals at commit.

After a successful velocity commit, keep the same surviving notes selected.

Only the first pressed hit in a relative drag announces its preview value.

### Status and accessibility

Existing piano-roll note clicks continue to announce their hit. The velocity
page announces only the first pressed hit during relative-drag preview
updates. Selection-only clicks, box selection, graduation clicks, and freehand
painting do not announce a note.

When a note is announced, MainWindow's structured note information shows:

- key;
- stored velocity;
- effective velocity;
- raw duration in ticks; and
- effective duration in clocks.

Render the values as fixed-width, monospaced chips in this one-row form:

```text
<key> · velocity <stored> → plays <effective> · length <ticks> ticks → <clocks> clocks
```

A normal status message hides this structured widget. It returns on the next
note announcement, not automatically when the message timeout expires.

The velocity page uses `Qt::ClickFocus` and routes the existing shared commands:

- Copy
- Cut
- Paste
- Select all
- Delete
- Transpose
- Nudge notes left/right

Keep the existing note-position nudge commands. Do not add keys that change
velocity directly.

The page's accessible description is exactly:

```text
Velocity
```

or, for an intrinsic axis:

```text
Velocity. <Voice> has N volume levels.
```

Nodes and graduation labels are not separate focus targets. Do not add
tooltips or a live region as part of this work.

## Rendering and playback performance

Steady playback must not rebuild expensive automation or velocity content on
each UI tick. The playhead overlay owns routine playhead movement. User edits,
selection changes, zoom, scroll, resize, theme changes, document changes, and
voice-context changes must still invalidate the affected content.

Pause follow-scroll during an active drawer gesture. Resume it after commit or
cancel without changing the gesture's frozen coordinate system.

If the current integration branch uses `TimelineSurface`, place the drawer
pages within that rendering contract. Do not restore rejected broad paint
culling. Normal widget painting should honor the event update rectangle; use a
region only when separate invalid areas require it.

Build success alone does not prove this rule. Verification must distinguish
playhead-only presentation from a content rebuild.

For **PERF-01**, expose test-only counters at the content-build,
content-invalidation, and playhead-presentation seams. Then:

1. Show each page on a fixture whose playhead remains onscreen, process pending
   events, and discard the warmup counts.
2. Send 120 playhead-only updates, processing the event loop after each one.
3. Assert that automation and velocity content-build counts did not change.
4. Assert that playhead presentation advanced and ended at the final requested
   tick.
5. Trigger one automation edit, one velocity edit, a selection change, a zoom,
   and a theme change.
6. Assert that each affected page recorded the matching invalidation or content
   rebuild.

Report the fixture, warmup, update count, branch SHA, and observed counters.

## Source defects to fix or contain

The reference implementation exposed these risks. They are not UX to copy:

1. Notes at the same track, tick, and key can share a UI identity. Use stable
   document note identity and make the duplicate-note regression a hard gate
   before velocity editing.
2. A lost mouse release can leave a preview alive. Apply the gesture termination
   rules on page hide, drawer hide, document or track replacement, focus/window
   loss, and Escape.
3. Current-voice lookup must use `drawerContextTick` across the drawer.
4. Applying restored view state more than once must replace, not append,
   view-only lane lists.
5. Very narrow widgets must clamp plot width at zero; no geometry may extend
   through the 262 px gutter.
6. The reference row-key decoder accepts controller numbers `128...254` even
   though no such lane identity is valid. The reimplementation must reject
   them per the sidecar rules.
7. A reference blank-space automation double-click can commit its first click
   before exact entry opens. The reimplementation must use the atomic
   double-click rule.
8. The reference save path rebuilds `view` and can drop unknown fields. The
   reimplementation must merge them per the sidecar rule.

Do not broaden this work to repair unrelated roll, voice, or playback behavior.

## Verification

### Reference audit result

At the audited reference commit, the `porydaw` target built successfully. An
offscreen `--rollcheck` run against a scratch reflink of the `mus_lovely`
fixture reported all twelve PSG velocity benchmark cases as passing. The same
run still exited with three voice-line assertions:

- voice-line click did not request track program;
- name-line click requested voice reveal; and
- reorder drag from voice line requested reveal.

Those three failures were not compared with the same fixture on the current
integration base, so they are not attributed to this feature. Establish that
baseline before using the full roll check as an acceptance gate.

### Focused automated checks

Write or adapt focused checks on the fresh base for:

- **CORE-01** — complete track remaps for move, insert, duplicate, delete, and
  metadata-only/engine-track transitions; no-op suppression; signal order;
  Undo; and Redo;
- **CORE-02** — exact shared selection for duplicate notes at one tick and key;
- **CORE-03** — revision-checked batch velocity mutation, stale rejection,
  no-op filtering, selection continuity, and exact Undo;
- **DRW-01** — overlay geometry, unchanged roll geometry, and widths below
  262 px clamping plot width to zero without drawing through the gutter;
- **DRW-02** — text-only non-focusable tabs, tab toggles, and `A`/`V`
  shortcuts, including a two-song `tabcheck` proving that only the active tab
  changes or announces;
- **DRW-03** — shortcut blocking in event-list mode and exact drawer status
  messages;
- **DRW-04** — sidecar round-trip, unknown-key preservation, per-entry
  validation, malformed-state fallback, and two disjoint sequential restores
  replacing rather than merging both lane lists;
- **DRW-05** — view-only drawer and lane actions change neither MIDI nor Undo;
- **AUT-01** — row order, hidden lanes, empty lanes, value ranges, and
  track-owner remapping;
- **AUT-02** — point, sweep, ramp, exact entry, time selection, and safe
  termination;
- **AUT-03** — one Undo entry per completed automation edit and none for a
  no-op;
- **VEL-01** — shared note selection and plain track-header clearing;
- **VEL-02** — continuous drag, freehand sweep, box selection, label click, and
  safe termination;
- **VEL-03** — DirectSound, invalid voice context, and incompatible selections
  use a continuous axis; a mixed PSG/PCM or incompatible PSG drag applies one
  proposed delta, canonicalizes each PSG note through its own voice context,
  leaves DirectSound exact, and creates one Undo command;
- **VEL-04** — intrinsic Square, Noise, and Wave graduations, exact-value
  restoration, and label layout; and
- **A11Y-01** — exact continuous and intrinsic velocity accessible
  descriptions, with no node or graduation focus targets;
- **LIFE-01** — automation point, sweep, ramp, and band gestures and velocity
  relative, freehand, and band gestures terminate on page hide, drawer hide,
  track/song/document replacement, any document mutation, mouse-grab loss,
  window deactivation, and Escape; staged edits and provisional selections
  restore snapshots without MIDI or Undo changes; pan and resize retain applied
  view state; no cursor, grab, hover, or preview remains; and
- **PERF-01** — steady playhead updates do not rebuild drawer content.

The PSG velocity harness must report these twelve named results:

```text
track_header_updates_voice_type
intrinsic_levels_ignore_mixer
noise_has_sixteen_levels
noise_edit_preserves_graduations
square_selection_labels
wave_selection_labels
intrinsic_level_message
exact_velocity_is_graduation
exact_velocity_has_no_ring
origin_level_restores_exact
undo_restores_exact
typed_velocity_stays_exact
```

The native check executable must return nonzero when a case is false, missing,
duplicated, or when the total is not exactly twelve. Printed metrics alone are
not an acceptance gate, and the excluded `autoresearch.sh` must not be required
to parse them.

`src/editcheck.cpp` must cover the batch document mutation seam.
`src/rollcheckautomation.cpp` should cover the drawer and automation page.
`src/rollcheckpsgvelocity.cpp` should cover continuous and intrinsic velocity
behavior. Keep each harness focused enough to attribute a failure to this work.
Use the reference checks as evidence; do not copy their files wholesale.

### Manual UX checks

On a representative song with tempo, voice, controller, DirectSound, Square,
Noise, Wave, and key-split notes:

1. **UX-01** — Open, switch, resize, close, and restore both drawer pages.
2. **UX-02** — Confirm focus return, event-list shortcut blocking, and
   announcements.
3. **UX-03** — Add, hide, show, clear, remove, delete, copy, and paste
   automation lanes.
4. **UX-04** — Exercise point move, freehand, ramp, exact entry, range changes,
   selection, Undo, and track reorder/delete.
5. **UX-05** — Exercise velocity note selection from both roll and velocity
   page.
6. **UX-06** — Exercise continuous relative drag, freehand painting, box
   selection, cancel, exact entry, and Undo.
7. **UX-07** — Confirm intrinsic labels and exact-value restoration for Square,
   Noise, and Wave.
8. **UX-08** — Change CC7, song volume, pan, and modulation and confirm
   graduations do not move.
9. **UX-09** — Play while each page is open and confirm the playhead stays
   smooth without steady content rebuilds.
10. **UX-10** — Close and reopen the song and confirm view state returns
    without a MIDI diff.

Run the full existing roll check after the focused checks. Compare any
pre-existing failure against the same current-base fixture before assigning it
to this feature.

### Required final suite

Build the application, then run at least these native checks from the final
commit. Use fresh scratch project copies for checks that can mutate a project,
and record the second valid song used by `tabcheck`.

```text
<porydaw> --editcheck <scratch-project>
<porydaw> --rollcheck <scratch-project> mus_lovely <roll-screenshot>
<porydaw> --eventviewcheck <scratch-project> mus_lovely <event-screenshot>
<porydaw> --keymapcheck
<porydaw> --sessioncheck <scratch-project> mus_lovely
<porydaw> --tabcheck <scratch-project> mus_lovely <second-valid-song>
```

Run each command on the pinned fixture revision with isolated settings where
the harness supports them. A skipped command needs a recorded reason. Also run
`git diff --check` and the project's configured test runner if it covers any
touched module.

### Traceability

| Contract section | Acceptance IDs |
| --- | --- |
| Track-identity remapping | CORE-01, UX-04 |
| Drawer layout, pages, focus, and persistence | DRW-01...DRW-05, LIFE-01, UX-01, UX-02, UX-10 |
| Automation rows, menus, gestures, and Undo | AUT-01...AUT-03, LIFE-01, UX-03, UX-04 |
| Velocity identity, selection, mutation, status, and access | CORE-02, CORE-03, VEL-01, VEL-02, A11Y-01, LIFE-01, UX-05, UX-06 |
| Continuous and intrinsic axes | VEL-03, VEL-04, A11Y-01, UX-07, UX-08 |
| Rendering and playback performance | PERF-01, UX-09 |

When a normative rule cannot be automated, record its result under the mapped
manual ID. A bare build result does not satisfy a UX or performance ID.

## Implementation preflight

Before the first code change:

1. Fetch and prune all remotes.
2. Create a clean implementation worktree and branch from the fetched
   `upstream/main`, unless the integrator has named another authoritative ref.
3. Record the exact base SHA, this specification's commit SHA, and the
   reference-oracle SHA in the first implementation commit body.
4. Record the `hearth-test` fixture SHA, make a fresh scratch reflink for each
   mutating check, and use `mus_lovely` for the roll baseline.
5. Build the unchanged base and run the entire Required final suite below.
   Record the exact commands, exit codes, named failures, screenshot paths,
   platform mode, settings isolation, and any skipped checks.

The roll baseline command has this form:

```text
QT_QPA_PLATFORM=offscreen <porydaw-executable> \
  --rollcheck <scratch-hearth-project> mus_lovely <screenshot-path>
```

Do not start feature work until the base build and baseline record exist. Use
the same build type, fixture snapshot, platform mode, settings isolation, and
commands for the final run and when attributing failures.

## Required commit series

Implement the work as eight ordered commits:

1. **Publish complete track-identity remaps**
   - Cover move, insert, duplicate, delete, metadata-only/engine-track
     transitions, Undo, Redo, no-op, and signal order.
   - Adapt existing consumers without changing their UX.
   - Make no drawer or velocity change.
2. **Use exact note identity in shared selection**
   - Distinguish duplicate notes through the view model, piano roll selection,
     and document lookup.
   - Cover duplicate selection and selection continuity.
   - Make no drawer or velocity-page change.
3. **Add revision-checked batch velocity editing**
   - Add the batch mutation at the document seam.
   - Cover stale rejection, deduplication, no-op filtering, and one-command
     Undo.
   - Make no drawer UI change.
4. **Characterize and expose the existing automation page**
   - Add focused checks for the current point, sweep, ramp, row-resize, range,
     menu, selection, and Undo behavior on the fresh base.
   - Make only the structural change needed to host the page in an overlay.
   - Make no visible UX change.
5. **Add the editor drawer shell and saved page state**
   - Add overlay layout, tabs, shortcuts, resize, focus return, cancellation,
     and sidecar fields.
   - Place the existing automation editor in the drawer without changing its
     editing rules.
6. **Complete the automation drawer deltas**
   - Preserve the base's row resizing, range behavior, and menus.
   - Add typed row-state persistence and remapping, hidden/show lanes, and only
     the exact menu and gesture differences named in this document.
   - Extend the characterization checks for the new behavior.
7. **Add the continuous velocity page and shared selection editing**
   - Keep intrinsic axes disabled.
   - Add continuous gesture, freehand, cancellation, accessibility, status,
     and Undo checks.
8. **Add intrinsic PSG graduations and finish velocity UX**
   - Add Square, Noise, Wave, exact-value, mixer-independence, and native
     pass/fail checks.

If a feature commit first needs a structural change, land that change as its
own behavior-preserving refactor immediately before the feature. Do not hide a
refactor inside a feature diff. Do not combine this series into one large
commit, and do not mix optional fixes into it.

Before each commit:

1. Build the application.
2. Run the focused checks added or touched by that commit.
3. Inspect the staged diff for whole-file churn and unrelated files.
4. Confirm the commit message names one behavior or refactor.

After the eighth commit, run the full relevant check set and manual UX pass.

## Explicit exclusions from the reference branch

Do not port these files or changes:

- `.omp/velocity-detent-ux-result.json`
- `autoresearch.sh`
- `resources/velocity-bars.png`
- `resources/velocity-bars@2x.png`
- `resources/velocity-bars-selected.png`
- `resources/velocity-bars-selected@2x.png`
- their `CMakeLists.txt` resource entries
- temporary `rollcheckpsgvelocitymixed` sources
- Visual Studio `.gitignore` changes
- forcing Fusion before `QApplication`
- removal of unrelated theme checks
- `SPEC.md` deletions for mute/solo and follow-playhead behavior
- keymap-check deletions for existing `M` and `S` bindings
- removal of event-list follow-playhead checks
- broad OKLab cache or color-blend benchmark work
- whole-file formatting and line-wrap churn

The one-line voice-editor sizing change and any color-cache performance work
must be proposed and reviewed as separate follow-up commits if they are still
needed on the integration branch.

## Definition of done

The work is complete when:

- every required behavior in this document has recorded evidence under its
  mapped automated or manual acceptance ID;
- all eight commits, plus any named preparatory refactor, build and pass their
  focused checks when applied in order;
- the feature diff adds or modifies none of the excluded paths or hunks;
- drawer and lane state round-trip without altering MIDI;
- automation parity and the new lane behavior pass;
- continuous and intrinsic velocity editing obey the exact-value and
  per-voice canonicalization rules and preserve exact Undo;
- steady playback does not rebuild drawer content on each UI tick;
- the full relevant check set has been run with pre-existing failures
  attributed against the same base and fixture; and
- the staged and final diffs contain no unrelated churn.

## Reference sources

Use the reference branch only to answer behavior questions. The main evidence
is:

- `src/ui/editordrawer.{h,cpp}`
- `src/ui/songview.{h,cpp}`
- `src/ui/velocityarea.{h,cpp}`
- `src/ui/velocityaxis.{h,cpp}`
- `src/core/psgvelocitymodel.{h,cpp}`
- `src/ui/viewsidecar.{h,cpp}`
- `src/core/songdocument.{h,cpp}`
- `src/rollcheckautomation.cpp`
- `src/rollcheckpsgvelocity.cpp`
- `src/editcheck.cpp`
- `docs/PROGRAMMABLE_WAVE_VELOCITY.md`

When source code, a check, and this document disagree, this document defines
the target. Record any ambiguity before changing behavior.
