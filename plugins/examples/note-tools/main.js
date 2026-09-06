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

function needSelection() {
    var notes = porydaw.selection.notes();
    if (!notes.length)
        porydaw.ui.statusMessage("Select some notes first.");
    return notes;
}

// Legato: every selected note is stretched (or trimmed) so it ends where
// the next selected note starts. Notes that begin on the same tick keep
// the same end, so chords stay chords. The last note is left alone.
function legato() {
    var notes = sorted(needSelection());
    if (notes.length < 2) return;
    // Group notes by start tick; each group ends at the next group's start.
    var starts = [];
    notes.forEach(function (n) {
        if (!starts.length || starts[starts.length - 1] !== n.tick) starts.push(n.tick);
    });
    var changed = porydaw.edit.transaction("Legato", function () {
        var count = 0;
        notes.forEach(function (n) {
            var i = starts.indexOf(n.tick);
            if (i + 1 >= starts.length) return;
            var target = starts[i + 1] - n.tick;
            if (target > 0 && target !== n.len) {
                porydaw.edit.resizeNotes(n, target - n.len);
                count++;
            }
        });
        return count;
    });
    porydaw.selection.setNotes(notes);
    porydaw.ui.statusMessage("Legato: adjusted " + changed + " note(s).");
}

// Insert Chord: a major triad (root, +4, +7) at the edit cursor, one grid
// cell long, on the selected track. The root is the selected note's key
// when one note is selected, else middle C.
function insertChord() {
    if (!porydaw.song.loaded) return;
    var track = porydaw.selection.track;
    if (track < 0) {
        porydaw.ui.statusMessage("Select a track first.");
        return;
    }
    var selected = porydaw.selection.notes();
    var root = selected.length === 1 ? selected[0].key : 60;
    var tick = porydaw.cursor.snap(porydaw.cursor.tick, "down");
    var grid = porydaw.cursor.grid(tick);
    var len = grid.beatTicks;
    var vel = selected.length === 1 ? selected[0].vel : 100;
    var ids = porydaw.edit.transaction("Insert chord", function () {
        return porydaw.edit.addNotes(track, [0, 4, 7].map(function (interval) {
            return { tick: tick, key: root + interval, len: len, vel: vel };
        }));
    });
    porydaw.selection.setNotes(ids);
    porydaw.ui.statusMessage("Inserted a triad on " + root + " at tick " + tick + ".");
}

// Humanize: nudges every selected velocity by a random amount within
// ±(12% of 127). The seed comes from the plugin's storage so a re-run
// gives a different pattern.
function humanize() {
    var notes = needSelection();
    if (!notes.length) return;
    var spread = 15;
    porydaw.edit.transaction("Humanize velocities", function () {
        porydaw.edit.setVelocity(notes, function (n) {
            var delta = Math.round((Math.random() * 2 - 1) * spread);
            return Math.max(1, Math.min(127, n.vel + delta));
        });
    });
    porydaw.selection.setNotes(notes);
    porydaw.ui.statusMessage("Humanized " + notes.length + " velocities (±" + spread + ").");
}

// Strum: notes that start together are staggered from low to high by a
// fraction of the grid cell, and each keeps its original end so the chord
// still releases together.
function strum() {
    var notes = sorted(needSelection());
    if (notes.length < 2) return;
    var step = Math.max(1, Math.floor(porydaw.cursor.grid(notes[0].tick).beatTicks / 8));
    var moved = porydaw.edit.transaction("Strum", function () {
        var count = 0;
        var i = 0;
        while (i < notes.length) {
            var j = i;
            while (j < notes.length && notes[j].tick === notes[i].tick) j++;
            var chord = notes.slice(i, j).sort(function (a, b) { return a.key - b.key; });
            chord.forEach(function (n, k) {
                if (k === 0 || n.len <= k * step) return;
                // Shorten from the left: the note-on moves right, the end stays.
                porydaw.edit.resizeNotes(n, -k * step, { fromLeft: true });
                count++;
            });
            i = j;
        }
        return count;
    });
    porydaw.selection.setNotes(porydaw.song.notes({ track: porydaw.selection.track }).filter(function (n) {
        return notes.some(function (s) { return s.id === n.id; });
    }));
    porydaw.ui.statusMessage("Strummed " + moved + " note(s) by " + step + " ticks per voice.");
}

// Quantize: every selected note's start snaps to the nearest grid line
// (the roll's current grid). Lengths are preserved.
function quantize() {
    var notes = needSelection();
    if (!notes.length) return;
    var moved = porydaw.edit.transaction("Quantize to grid", function () {
        var count = 0;
        notes.forEach(function (n) {
            var target = porydaw.cursor.snap(n.tick, "nearest");
            if (target !== n.tick) {
                porydaw.edit.moveNotes(n, target - n.tick, 0);
                count++;
            }
        });
        return count;
    });
    porydaw.selection.setNotes(notes);
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
    var ids = {};
    tools.forEach(function (tool) {
        ids[tool.id] = porydaw.actions.register({
            id: tool.id, name: tool.name, context: "roll", default: tool.key, run: tool.run
        });
    });
    // The note context menu lists the selection tools. Legato and Strum
    // relate one note to the next, so they only appear when two or more
    // notes are selected: shouldShow() is asked as the menu opens.
    var twoOrMore = function () { return porydaw.selection.notes().length >= 2; };
    var menu = porydaw.ui.contextMenu("notes");
    menu.addItem({ label: "Legato", action: ids.legato, shouldShow: twoOrMore });
    menu.addItem({ label: "Strum", action: ids.strum, shouldShow: twoOrMore });
    menu.addItem({ label: "Humanize velocities", action: ids.humanize });
    menu.addItem({ label: "Quantize to grid", action: ids.quantize });
    porydaw.log("ready: " + ctx.name + " " + ctx.version);
}

export function deactivate() {}
