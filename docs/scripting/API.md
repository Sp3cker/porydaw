# porydaw scripting API — v1 (Phase 1)

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
        run(api) { /* api = {song, selection, cursor, transport} */ }
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
becomes selected), `clear()`, `selectTrack(i)`. Selection is view state:
no undo entry.

### `porydaw.cursor`

`tick`, `set(tick)` (seeks while playing/paused), `snap(tick, "nearest"|"down"|"up")`,
`grid(tick?)` → `{start, next, beatTicks, feel, minDenom}`.

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
a warning and the command ships unbound. Users rebind plugin commands in
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

Editing (`porydaw.edit.*` inside undoable transactions), audio/beat frames,
docks with a canvas, menus and dialogs follow in later phases
(docs/scripting/PLAN.md §6).
