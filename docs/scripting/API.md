# porydaw scripting API — v1 (Phases 1–3)

Plugins are JavaScript run by porydaw's embedded engine (Qt's `QJSEngine`,
ES2017-level). Everything runs on the UI thread; a script call that runs
longer than 5 s is interrupted and the plugin is disabled until reloaded.

## Installing a plugin

Settings → Plugins shows the plugins folder (`<app data>/plugins`, or the
`PORYDAW_PLUGINS_DIR` environment variable). One folder per plugin:

```
plugins/
  select-same-pitch/
    plugin.json
    main.js
```

`plugin.json`:

```json
{ "id": "select-same-pitch", "name": "Select Same Pitch", "version": "1.0.0",
  "api": 1, "main": "main.js", "description": "…" }
```

- `id` (required): lowercase letters, digits, `-`, `_`; must equal the folder name.
- `api` (required): the API major this plugin was written for. porydaw refuses
  any other major with a message on the Plugins page.
- `main` (default `main.js`): an ES module exporting `activate(ctx)` and,
  optionally, `deactivate()`.

Editing any `.js`/`plugin.json` in the folder reloads the plugin (deactivate,
fresh engine, activate). Everything a plugin registered — commands, listeners,
window actions — is released on unload, so reloads never leak.

`main.js`:

```js
export function activate(ctx) {           // ctx = {id, name, version, dir}
    porydaw.actions.register({
        id: "select", name: "Select notes of the same pitch",
        context: "roll", default: "Ctrl+Shift+A",
        run(api) { /* api = {song, selection, cursor, transport, edit, view} */ }
    });
}
export function deactivate() {}
```

## `porydaw`

| Member | Meaning |
|---|---|
| `porydaw.version` | porydaw's version string |
| `porydaw.api.version` / `.major` | API version (`"1.0.0"`, `1`) |
| `porydaw.plugin` | `{id, name, version, dir}` of the calling plugin |
| `porydaw.log(...)`, `.warn(...)`, `.error(...)` | Script Console lines (objects are JSON-stringified). `console.log` etc. alias these. |
| `porydaw.ui.statusMessage(text)` | Status-bar message |

### `porydaw.project`

`isOpen`, `root`, `songs()` → `[{id, label, constant, player, midPath, hasMid, registered}]`.

### `porydaw.song` — the active tab, read-only

Ticks are document ticks (`ticksPerBeat` per quarter note). Note ids are
opaque numbers valid for the life of the document.

| Member | |
|---|---|
| `loaded`, `revision`, `label`, `midPath` | `revision` bumps on every edit/undo/redo |
| `ticksPerBeat`, `ticksPerClock`, `startTempo`, `trackCount`, `trackBudget`, `endTick` | |
| `loop()` | `{start, end}` or `null` |
| `timeSigs()` | `[{tick, numerator, denominator}]` |
| `tracks()` | `[{index, name, channel, muted, soloed, voice}]` |
| `notes({track?, from?, to?, selectedOnly?})` | `[{id, track, tick, key, len, vel}]`; `from`/`to` bound the start tick, half-open |
| `note(id)` | one note or `null` |
| `lanePoints(track, cc, {from?, to?})` | `[{tick, value}]`; `cc` is 0–127 or `song.CC.BEND` / `.TEMPO` / `.VOICE` |
| `on("changed", fn({revision}))` | after every edit, undo, redo |
| `on("activated", fn({label} \| null))` | the active tab changed |

Every `on()` returns a function that unsubscribes; `off(event, fn)` also works.

### `porydaw.selection`

`track` (selected track), `trackMask` (header multi-selection bitmask),
`notes()` (selected notes, same shape as `song.notes`), `time()` →
`{start, end, scope: "tracks"|"lanes", lanes: [{track, cc}]}` or `null`.
`setNotes(idsOrNotes)` replaces the note selection (all on one track, which
becomes selected), `clear()`, `selectTrack(i)`.
`setTime({start, end, scope?: "tracks"|"lanes", lanes?: [{track, cc}]})`
makes a time selection (track scope covers the header-selected tracks;
`cc` may be `song.CC.TEMPO` with `track: -1`), `clearTime()`. Selection is
view state: no undo entry.

### `porydaw.cursor`

`tick`, `set(tick)` (seeks while playing/paused), `snap(tick, "nearest"|"down"|"up")`,
`grid(tick?)` → `{start, next, beatTicks, feel, minDenom}`.

### `porydaw.view`

The roll's camera and lane visibility (view state, no undo entries).
`visibleTicks()` → `{from, to}` (or `null`), `revealTick(tick)`,
`revealRange(from, to)`, `revealNote(idOrNote)` → whether it was found,
`revealKey(key)`; read/write booleans `velocityLane`, `automationLanes`,
`tempoLane`, `eventList`; read-only `pxPerBeat`, `keyHeight`.

### `porydaw.edit` — document edits

Every mutation happens inside a **transaction**:

```js
var ids = porydaw.edit.transaction("Insert chord", function () {
    var ids = porydaw.edit.addNotes(track, [{tick: 0, key: 60, len: 24, vel: 100},
                                            {tick: 0, key: 64, len: 24, vel: 100}]);
    porydaw.edit.moveNotes(ids, 48, 0);
    return ids;                              // transaction() returns fn's result
});
```

- One transaction is **one entry in Edit → Undo**, named after it, however
  many calls it makes. A transaction that changes nothing leaves no entry.
- An exception inside `fn` — the script's own, or an edit that was refused
  — **rolls every edit back** and propagates; the document is exactly as it
  was, with no undo or redo entry. Nested transactions join the outermost
  one (their edits share its entry); an inner failure aborts the whole
  thing even if the script catches it.
- The transaction expects the document to change only through its own
  calls. If anything else edits the song while it is open (a nested event
  loop, another plugin), the next edit call throws and the transaction
  rolls back at commit.
- A `song.changed` listener can't edit during the edit that woke it, and
  can't open a transaction of its own (the undo stack may be mid-undo);
  both throw. Only one plugin can have a transaction open at a time.
- Calling any edit outside a transaction throws. `edit.active` tells.
- If the watchdog stops a script mid-transaction, the host rolls it back.
- A transaction that never pushes an edit (nothing to do, or it threw
  before its first edit) leaves the undo stack exactly as it was — the
  user's redo entries included. One that did push and was rolled back
  leaves no entry of its own, but its edits cleared any redo like every
  edit does.

Ids that no longer resolve are skipped and the count actually edited is
returned. Ticks, keys, velocities and values are clamped to their ranges;
a bad track, cc or scope throws — track arguments must be actual integers
(a missing or `undefined` track throws rather than targeting track 0).
Note arguments accept an id, a note object, or an array of either.

| Call | |
|---|---|
| `addNotes(track, [{tick, key, len, vel}])` | → the new ids, in order. Two entries on one tick and key can't both exist: the later wins and the earlier reports `0`. Existing overlapping same-key notes are trimmed like a draw |
| `deleteNotes(notes)` | |
| `moveNotes(notes, dTick, dKey)` | ids survive the move |
| `resizeNotes(notes, dLen, {fromLeft?})` | `dLen` is the change in length; `fromLeft` moves the start instead of the end |
| `setVelocity(notes, vel)` / `setVelocity(notes, fn(note) → vel)` | |
| `nudgeVelocity(notes, delta)` | |
| `addLanePoint(track, cc, tick, value)` | replaces a point already at that tick; `cc` as in `song.lanePoints` (tempo: `track` ignored, use -1) |
| `writeLanePoints(track, cc, from, to, [{tick, value}])` | replaces every point of the lane in `[from, to]` with the list (not for the voice lane) |
| `moveLanePoints(track, cc, [{tick, newTick?, newValue?}])` | |
| `deleteLanePoints(track, cc, [ticks])` | |
| `setStartTempo(bpm)`, `setLoop(start, end)` (`null` removes a marker), `setTimeSig(tick, numerator, denominator)`, `deleteTimeSig(tick)` | |
| `removeTimeRange(start, end, scope)`, `insertTimeRange(at, span, scope)` | ripple delete/insert; `scope` is `{tracks: [i], lanes: [{track, cc}]}` or `{wholeSong: true}`; → whether anything changed |
| `addTrack(voice)` → index or -1, `duplicateTrack(i)`, `deleteTrack(i)`, `moveTrack(i, target)`, `renameTrack(i, name)` | |
| `transposeSelection(dKey)`, `nudgeSelection("left"\|"right")` | the roll's own keyboard moves on the note selection (all-or-nothing transpose, grid-line nudge); → whether anything moved |

The bundled `plugins/examples/note-tools` plugin (Legato, Insert chord,
Humanize, Strum, Quantize) shows the pattern.

### `porydaw.transport`

`state` (`"stopped"|"paused"|"playing"`), `playheadTick`, `sampleRate`,
`loopEnabled`, `play()`, `pause()`, `stop()`, `seek(tick)`,
`on("state", fn({state}))`.

Realtime events (each `on` returns an unsubscribe function; the host's ~60 Hz
frame clock runs only while some plugin listens to one of these or to
`audio.frame`):

| Event | Payload | When |
|---|---|---|
| `tick` | `{state, tick, playing}` | every frame, whatever the transport is doing |
| `beat` | `{bar, beat, beatsPerBar, beatTicks, tick, bpm}` | the playhead enters a new beat of the meter in force (`bar` 0-based, `beat` 0-based within the bar); also the beat playback starts on, and again after a loop wrap or seek. Nothing while stopped/paused. |

### `porydaw.audio`

The final stereo mix as the device hears it (song playback, auditions and
reverb tails alike, after the Output level), analysed once per frame in C++
and shared by every subscriber. `on("frame", fn(frame))` fires every frame
with `frame = {peak: [l, r], rms: [l, r], frames, sampleRate, playing}` —
`peak`/`rms` cover the samples written since the previous frame (0..1,
linear; `frames` is how many there were, 0 when the device is idle). On
demand, and no more expensive than what you ask for:

| Member | Meaning |
|---|---|
| `sampleRate`, `windowFrames` | device rate; the analysis window (2048 frames) |
| `peak`, `rms` | the last frame's `[l, r]` |
| `pcm()` | `Float32Array` of the newest `windowFrames` frames, interleaved L/R, oldest first |
| `spectrum(bins = 64)` | `Float32Array` of `bins` bands, linear in frequency from 0 to `sampleRate / 2`, each 0..1 (1 = a full-scale sine there); a Hann-windowed FFT of the window's mono mix, computed at most once per frame |
| `channels()` | `{pcm: [{on, releasing, track, key}], cgb: [...], maxPcm, activePcm, activeCgb}` — the engine's channel pools — or `null` without a song |

Bundled examples: `plugins/examples/vu-meter`, `plugins/examples/spectrum`,
`plugins/examples/dancer` (beats).

### `porydaw.ui`

`statusMessage(text)`; `theme(role?)` → a color string (`"#rrggbb"` or
`"#rrggbbaa"`) for one of the exposed theme roles (`window_background`,
`window_text`, `secondary_text`, `disabled_text`, `selection_background`,
`selection_text`, `link_text`, `palette_outline`, `item_background`,
`item_text`, `item_alternate_background`, `header_background`, `header_text`,
`button_background`, `button_text`, `tooltip_background`, `tooltip_text`, the
`polyphony_cell_*`/`polyphony_flash_background` cells, and the roll's
`song_view_piano_roll_background`, `song_view_grid`, `song_view_separator`,
`song_view_primary_text`, `song_view_secondary_text`,
`song_view_selection_fill`, `song_view_selection_edge`, `song_view_playhead`,
`song_view_edit_cursor`, `song_view_loop_marker`,
`song_view_automation_default_curve`, `song_view_automation_tempo_curve`,
`sample_waveform_ink`), or an object of all of them with no argument. Read
it at paint time: theme changes repaint your canvases.

`loadImage(path)` decodes an image file inside the plugin's folder (PNG, JPEG,
…) → an image id for `g.image`; `imageSize(id)` → `{width, height}` or
`null`; `freeImage(id)`.

#### `porydaw.ui.dock(spec)` → dock

A panel next to Songs / Voicegroup / Polyphony. `spec`:

| Field | Meaning |
|---|---|
| `id` | required; letters, digits, `_`, `-`. The window remembers the dock's placement per `plugin.<pluginId>.<id>`, and whether the user closed it. |
| `title` | dock title (default: the plugin name) |
| `area` | `"right"` (default), `"left"`, `"top"`, `"bottom"` — the first-ever placement |
| `minWidth`, `minHeight` | minimum body size (defaults 120 × 60) |
| `paint(g)` | shorthand: the dock is one canvas painted by this function (see below); `mouse(ev)` optional |
| `build(root)` | otherwise: lay out widgets on `root`, a column container |

The dock handle: `id`, `title` (read/write), `visible` (read/write),
`open` (false after `close()`), `show()`, `hide()`, `raise()`, `close()`,
`root` (the column), `canvas` (the shorthand canvas, else `null`). Docks are
closed automatically on unload/reload; call `close()` from `deactivate()`
anyway so a plugin that stays loaded can tidy up.

Containers (`root`, `addRow()`, `addColumn()`) build children in order:

| Call | Widget / handle |
|---|---|
| `addLabel(text)` | label; `text` |
| `addButton(text, onClick())` | button; `text`, `enabled` |
| `addCheckbox(text, checked, onChange(on))` | checkbox; `checked` |
| `addSlider(min, max, value, onChange(v), {vertical?})` | integer slider; `value` |
| `addCombo(items, index, onChange(i))` | drop-down; `index`, `text`, `setItems(items)` |
| `addCanvas({minWidth?, minHeight?}, paint(g), mouse(ev)?)` | canvas; `repaint()`, `width`, `height` |
| `addRow()`, `addColumn()` | nested containers |
| `addStretch()`, `addSpacing(px)` | layout filler |

Every handle also has `kind`, `visible`, `enabled`, `setMinimumSize(w, h)`,
`setToolTip(text)`. Callbacks (`onChange` etc.) don't fire for changes the
script makes itself. Plugin widgets never take keyboard focus, so the roll's
shortcuts keep working with a panel open.

#### Canvas painting

`paint(g)` runs on the UI thread whenever the canvas repaints — after
`repaint()`, on resize, on theme change. It is under the watchdog like any
call; a paint that throws is logged and paints are held back for a second.
`g` is valid only inside `paint`. Coordinates are device-independent pixels
from the canvas's top-left; `g.width`, `g.height`, `g.dpr`. Colors are CSS
strings (`"#f80"`, `"#ff8800"`, `"#ff880080"`, `"rgb(255,136,0)"`,
`"rgba(255,136,0,0.5)"`, names) or `[r, g, b, a?]` arrays.

| `g.` | |
|---|---|
| `clear(color)` | fill everything (ignores transforms) |
| `fillRect(x, y, w, h, color)`, `strokeRect(x, y, w, h, color, lineWidth)`, `fillRoundRect(x, y, w, h, radius, color)` | |
| `line(x1, y1, x2, y2, color, lineWidth)` | |
| `fillCircle(cx, cy, r, color)`, `strokeCircle(cx, cy, r, color, lineWidth)`, `fillEllipse(x, y, w, h, color)` | |
| `fillPolygon(points, color)`, `strokePolyline(points, color, lineWidth, close)` | `points`: `[x0, y0, x1, y1, …]` or `[{x, y}, …]` |
| `text(x, y, str, color, {size?, bold?, align?, baseline?})` | `size` multiplies the UI font (1 = as is); `align` `"left"|"center"|"right"`; `baseline` `"alphabetic"` (default, y is the baseline) `|"top"|"middle"|"bottom"` |
| `measureText(str, opts)` | `{width, height, ascent, descent}` |
| `image(id, dx, dy, dw, dh, sx, sy, sw, sh)` | an `ui.loadImage` image; `dw`/`dh` ≤ 0 keep the source size; `sx, sy, sw, sh` select a source rectangle (sprite sheets), `sw`/`sh` ≤ 0 meaning "to the edge" |
| `save()`, `restore()`, `translate(dx, dy)`, `rotate(degrees)`, `scale(sx, sy)`, `opacity(0..1)`, `clip(x, y, w, h)`, `antialias(on)` | painter state; unbalanced saves are restored for you |

`mouse(ev)` receives `{type, x, y, button, left, right, middle}` with `type`
one of `press`, `move`, `release`, `doubleclick`, `leave`, or `wheel`
(`deltaX`, `deltaY` in notches, positive = down).

### `porydaw.actions`

`register({id, name, context, default?, run})` → the full keymap id
`plugin.<pluginId>.<id>`. `context`: `"global"` (window-wide), `"roll"`,
`"velocity"`, or `"range"` (only while a time selection is active).
`default` is a portable key sequence (`"Ctrl+Shift+A"`); a default that
collides with an existing binding in an overlapping context is dropped with
a warning and the command ships unbound. Escape is never a plugin
shortcut (it cancels drags and clears selections everywhere). Users rebind plugin commands in
Settings → Keyboard Shortcuts; rebinds survive reloads. `unregister(fullId)`.

### `porydaw.storage`

Per-plugin key/value store of JSON-serializable values, persisted in
porydaw's settings: `get(key, fallback)`, `set(key, value)`, `remove(key)`,
`keys()`.

## Errors and the watchdog

Exceptions thrown from `activate`, an action's `run`, or a listener are
logged in the Script Console with file:line and a stack; an exception in
`activate` marks the plugin Error (see Settings → Plugins). Listeners that
throw don't stop the others. A call that exceeds the watchdog budget is
interrupted, the plugin is disabled until Reload, and other plugins are
unaffected.

## Roadmap

Menus and dialogs, file IO, raw SMF event edits and piano-roll overlays
follow in later phases (docs/scripting/PLAN.md §6).
