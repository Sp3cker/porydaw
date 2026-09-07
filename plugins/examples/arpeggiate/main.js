// Arpeggiate: the plugin built step by step in the manual's
// "Writing your first plugin" tutorial (docsrc/manual/writing-plugins.md).
//
// Select a chord (or several) in the piano roll and press Ctrl+Shift+R.
// Every group of selected notes that starts on the same tick is replaced
// by its notes played one at a time, lowest first, in sixteenth notes,
// cycling until the chord's original end.

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

export function deactivate() {}
