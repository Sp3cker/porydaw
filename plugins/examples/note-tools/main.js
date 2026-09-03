// Bundled example plugin (docs/scripting/PLAN.md Phase 2): editing macros
// that act on the piano roll's note selection or the edit cursor. Every
// command wraps its edits in porydaw.edit.transaction, so each run is a
// single entry in Edit → Undo, and a failure part-way leaves the song as
// it was. Copy this folder into the plugins folder shown in
// Settings → Plugins to try it; rebind the keys there too.

// Notes sorted by start tick, then key: the order the tools reason in.
function sorted(notes) {
    return notes.slice().sort(function (a, b) {
        return a.tick - b.tick || a.key - b.key;
    });
}

function needSelection(api) {
    var notes = api.selection.notes();
    if (!notes.length)
        porydaw.ui.statusMessage("Select some notes first.");
    return notes;
}

// Legato: every selected note is stretched (or trimmed) so it ends where
// the next selected note starts. Notes that begin on the same tick keep
// the same end, so chords stay chords. The last note is left alone.
function legato(api) {
    var notes = sorted(needSelection(api));
    if (notes.length < 2) return;
    // Group notes by start tick; each group ends at the next group's start.
    var starts = [];
    notes.forEach(function (n) {
        if (!starts.length || starts[starts.length - 1] !== n.tick) starts.push(n.tick);
    });
    var changed = api.edit.transaction("Legato", function () {
        var count = 0;
        notes.forEach(function (n) {
            var i = starts.indexOf(n.tick);
            if (i + 1 >= starts.length) return;
            var target = starts[i + 1] - n.tick;
            if (target > 0 && target !== n.len) {
                api.edit.resizeNotes(n, target - n.len);
                count++;
            }
        });
        return count;
    });
    api.selection.setNotes(notes);
    porydaw.ui.statusMessage("Legato: adjusted " + changed + " note(s).");
}

// Insert Chord: a major triad (root, +4, +7) at the edit cursor, one grid
// cell long, on the selected track. The root is the selected note's key
// when one note is selected, else middle C.
function insertChord(api) {
    if (!api.song.loaded) return;
    var track = api.selection.track;
    if (track < 0) {
        porydaw.ui.statusMessage("Select a track first.");
        return;
    }
    var selected = api.selection.notes();
    var root = selected.length === 1 ? selected[0].key : 60;
    var tick = api.cursor.snap(api.cursor.tick, "down");
    var grid = api.cursor.grid(tick);
    var len = grid.beatTicks;
    var vel = selected.length === 1 ? selected[0].vel : 100;
    var ids = api.edit.transaction("Insert chord", function () {
        return api.edit.addNotes(track, [0, 4, 7].map(function (interval) {
            return { tick: tick, key: root + interval, len: len, vel: vel };
        }));
    });
    api.selection.setNotes(ids);
    porydaw.ui.statusMessage("Inserted a triad on " + root + " at tick " + tick + ".");
}

// Humanize: nudges every selected velocity by a random amount within
// ±(12% of 127). The seed comes from the plugin's storage so a re-run
// gives a different pattern.
function humanize(api) {
    var notes = needSelection(api);
    if (!notes.length) return;
    var spread = 15;
    api.edit.transaction("Humanize velocities", function () {
        api.edit.setVelocity(notes, function (n) {
            var delta = Math.round((Math.random() * 2 - 1) * spread);
            return Math.max(1, Math.min(127, n.vel + delta));
        });
    });
    api.selection.setNotes(notes);
    porydaw.ui.statusMessage("Humanized " + notes.length + " velocities (±" + spread + ").");
}

// Strum: notes that start together are staggered from low to high by a
// fraction of the grid cell, and each keeps its original end so the chord
// still releases together.
function strum(api) {
    var notes = sorted(needSelection(api));
    if (notes.length < 2) return;
    var step = Math.max(1, Math.floor(api.cursor.grid(notes[0].tick).beatTicks / 8));
    var moved = api.edit.transaction("Strum", function () {
        var count = 0;
        var i = 0;
        while (i < notes.length) {
            var j = i;
            while (j < notes.length && notes[j].tick === notes[i].tick) j++;
            var chord = notes.slice(i, j).sort(function (a, b) { return a.key - b.key; });
            chord.forEach(function (n, k) {
                if (k === 0 || n.len <= k * step) return;
                // Shorten from the left: the note-on moves right, the end stays.
                api.edit.resizeNotes(n, -k * step, { fromLeft: true });
                count++;
            });
            i = j;
        }
        return count;
    });
    api.selection.setNotes(api.song.notes({ track: api.selection.track }).filter(function (n) {
        return notes.some(function (s) { return s.id === n.id; });
    }));
    porydaw.ui.statusMessage("Strummed " + moved + " note(s) by " + step + " ticks per voice.");
}

// Quantize: every selected note's start snaps to the nearest grid line
// (the roll's current grid). Lengths are preserved.
function quantize(api) {
    var notes = needSelection(api);
    if (!notes.length) return;
    var moved = api.edit.transaction("Quantize to grid", function () {
        var count = 0;
        notes.forEach(function (n) {
            var target = api.cursor.snap(n.tick, "nearest");
            if (target !== n.tick) {
                api.edit.moveNotes(n, target - n.tick, 0);
                count++;
            }
        });
        return count;
    });
    api.selection.setNotes(notes);
    porydaw.ui.statusMessage("Quantized " + moved + " of " + notes.length + " note(s).");
}

export function activate(ctx) {
    var tools = [
        { id: "legato", name: "Legato selection", key: "Ctrl+Shift+L", run: legato },
        { id: "chord", name: "Insert chord at cursor", key: "Ctrl+Shift+K", run: insertChord },
        { id: "humanize", name: "Humanize velocities", key: "Ctrl+Shift+H", run: humanize },
        { id: "strum", name: "Strum selection", key: "Ctrl+Shift+U", run: strum },
        { id: "quantize", name: "Quantize selection to grid", key: "Ctrl+Shift+G", run: quantize }
    ];
    tools.forEach(function (tool) {
        porydaw.actions.register({
            id: tool.id, name: tool.name, context: "roll", default: tool.key, run: tool.run
        });
    });
    porydaw.log("ready: " + ctx.name + " " + ctx.version);
}

export function deactivate() {}
