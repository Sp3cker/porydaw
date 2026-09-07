# Writing Your First Plugin

This tutorial builds a small arpeggiation plugin from scratch.  It' a note-editing command that transforms a selected chord into a sequence of sixteenth notes.

This takes about fifteen minutes and only requires a text editor. By the end you will have used the four things note-editing plugins use:

- Created a plugin manifest
- Defined a command with a keyboard shortcut
- Read the currently note selection
- Make an undoable edit to the song's notes

The finished plugin is found in Porydaw's source code in `plugins/examples/arpeggiate`, so you can also grab that and read along.

## 1. Make the plugin folder

Open **Edit → Settings… → Plugins** and click **Open Plugins Folder**.

Inside it, create a folder named `arpeggiate`. Every plugin is one folder
holding two files:

```
arpeggiate/
  plugin.json
  main.js
```

## 2. Create the manifest file

Create `plugin.json`:

```json
{
  "id": "arpeggiate",
  "name": "Arpeggiate",
  "version": "1.0.0",
  "api": 1,
  "main": "main.js"
}
```

The `id` must match the folder name exactly. `api` is the version of the scripting
API the plugin is written for. Use `1`.

## 3. Say hello

Create `main.js`:

```js
export function activate() {
    porydaw.log("Arpeggiate is ready");
}
```

Save it. Porydaw will notice the new plugin folder and load the plugin immediately.

Open **View → Script Console** and you'll see the "Arpeggiate is ready" message. You'll also see that the Settings page lists the plugin as successfully loaded.

From here on, every time you save `main.js` Porydaw reloads the plugin automatically, so keep the Script Console open. That's where any errors will show up, including the file and line number.

## 4. Add a command

A plugin command is something the user can trigger with a keyboard shortcut. Replace
`main.js` with:

```js
function arpeggiate() {
    porydaw.ui.statusMessage("Arpeggiate!");
}

export function activate() {
    porydaw.actions.register({
        id: "arpeggiate",
        name: "Arpeggiate",
        context: "roll",          // active while the piano roll has focus
        default: "Ctrl+Shift+R",
        run: arpeggiate
    });
}
```

Open a song, click in the piano roll note area and press ++ctrl+shift+r++. The "Arpeggiate!" message should appear in the status bar at the bottom of the window! The command is now also listed in **Settings → Keyboard Shortcuts**.

## 5. Read the current note selection

Now make the command look at the user's current note selection. `porydaw.selection.notes()` returns the selected notes, each as `{id, track, tick, key, len, vel}`.

!!! tip
    A "tick" is the smallest possible time unit in Porydaw.
    
    `porydaw.song.ticksPerBeat` is how many ticks are in one beat.

```js
function arpeggiate() {
    var notes = porydaw.selection.notes();
    if (notes.length < 2) {
        porydaw.ui.statusMessage("Select a chord first.");
        return;
    }
    porydaw.ui.statusMessage("Got " + notes.length + " notes.");
}
```

Select a chord (multiple notes), press the keyboard shortcut, and you'll see the "Got x notes" message show up.

## 6. Make the arpeggiation note edit

This is the heart of the plugin. We want to effectively do the following things to achieve the arpeggiation effect:
1. Group the selected notes by their start tick (each group is one chord)
2. Delete each chord's notes
3. Add back its pitches one note at a time, low to high, as sixteenth notes, until the chord's original end position.

!!! tip
    Every change to a song must go inside `porydaw.edit.transaction`. Whatever happens inside it becomes **one** entry in Edit → Undo, and if any error happens, the song is left exactly as it was.

```js
function arpeggiate() {
    var notes = porydaw.selection.notes();
    if (notes.length < 2) {
        porydaw.ui.statusMessage("Select a chord first.");
        return;
    }
    var track = porydaw.selection.track;
    var step = porydaw.song.ticksPerBeat / 4;   // one sixteenth note

    // Group the selected notes by start tick: each group is one chord.
    var chords = {};
    notes.forEach(function (n) {
        (chords[n.tick] = chords[n.tick] || []).push(n);
    });

    var ids = porydaw.edit.transaction("Arpeggiate", function () {
        var created = [];
        Object.keys(chords).forEach(function (tick) {
            var chord = chords[tick];
            if (chord.length < 2) return;             // a single note stays as it is
            chord.sort(function (a, b) { return a.key - b.key; });
            var start = chord[0].tick;
            var end = Math.max.apply(null, chord.map(function (n) { return n.tick + n.len; }));

            porydaw.edit.deleteNotes(chord);
            var arp = [];
            for (var t = start, i = 0; t < end; t += step, i++) {
                var source = chord[i % chord.length];
                arp.push({ tick: t, key: source.key, len: Math.min(step, end - t), vel: source.vel });
            }
            created = created.concat(porydaw.edit.addNotes(track, arp));
        });
        return created;
    });

    porydaw.selection.setNotes(ids);
    porydaw.ui.statusMessage("Arpeggiated into " + ids.length + " notes.");
}
```

There are two important details from the code above:

- `porydaw.edit.transaction()` returns whatever your function returns. Here, we returned the newly-created note ids so we could select them afterwards.
- `addNotes` takes the track and a list of `{tick, key, len, vel}` notes, and it returns
 the ids of the notes it created.

With this new code ready, trying selecting a chord and pressing ++ctrl+shift+r++. It becomes an arpeggio! Press ++ctrl+z++ to undo the arpeggio command's changes.

## 7. Put it in the right-click menu

A keyboard shortcut is fine, but a menu entry is easier to discover and sometimes even more convenient. `porydaw.actions.register` returns the command's full `id`. A context-menu item can point at that same exact action, and it will even show the shortcut as a hint. `shouldShow` ensures the menu item only displays when appropriate.

```js
export function activate() {
    var id = porydaw.actions.register({
        id: "arpeggiate",
        name: "Arpeggiate",
        context: "roll",
        default: "Ctrl+Shift+R",
        run: arpeggiate
    });
    porydaw.ui.contextMenu("notes").addItem({
        label: "Arpeggiate",
        action: id,
        shouldShow: function () { return porydaw.selection.notes().length >= 2; }
    });
}
```

Right-click a selected chord, and you'll see an **Arpeggiate** item at the bottom of the menu.

And that's it!  That's the whole plugin.

## Where to go from here

- The [Scripting API](../reference/scripting.md) page lists everything a plugin can do:
    - editing automation lanes
    - following playback
    - drawing panels and overlays
    - showing dialogs
    - reading and writing files
    - ...and more!
- Porydaw's [example plugins](plugins.md#bundled-plugin-examples) demonstrate the various plugin capabilities.
- For editor completion, point your editor at
  [`porydaw.d.ts`](https://github.com/huderlem/porydaw/blob/main/docs/scripting/porydaw.d.ts).

As an exercise for the reader, try extending this arpeggiation plugin to do the following:

- Make the arpeggio's note length a setting (`porydaw.ui.dialog.form` asks, and gets saved in `porydaw.storage`)
- Make the arpeggio's notes go up and then down.
