# porydaw scripting API — v1 (Phases 1–2)

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

Audio/beat frames, docks with a canvas, menus and dialogs, file IO and raw
SMF event edits follow in later phases (docs/scripting/PLAN.md §6).
