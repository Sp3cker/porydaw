// Range Tools: right-click a time selection for three extra entries. The
// first is also a rebindable command (Settings → Keyboard Shortcuts), and
// the menu entry shows whatever it is bound to.

function rangeScope(sel) {
    if (sel.scope === "lanes") return { lanes: sel.lanes };
    var tracks = [];
    for (var t = 0; t < 32; t++)
        if (porydaw.selection.trackMask & (1 << t)) tracks.push(t);
    return { tracks: tracks };
}

function duplicateAfter() {
    var sel = porydaw.selection.time();
    if (!sel) return;
    var span = sel.end - sel.start;
    var n = porydaw.edit.transaction("Duplicate range after itself", function () {
        return porydaw.edit.duplicateRange(sel.start, sel.end, rangeScope(sel), span);
    });
    porydaw.selection.setTime({ start: sel.start + span, end: sel.end + span, scope: sel.scope,
                            lanes: sel.lanes });
    porydaw.ui.statusMessage(n ? "Duplicated " + n + " events" : "Nothing to duplicate");
}

function echo() {
    var sel = porydaw.selection.time();
    if (!sel) return;
    var answers = porydaw.ui.dialog.form({
        title: "Echo range",
        fields: [
            { key: "copies", label: "Copies", type: "number", value: 3, min: 1, max: 16 },
            { key: "gap", label: "Gap (beats)", type: "number", value: 1, min: 0.25, max: 64,
              decimals: 2 },
            { key: "decay", label: "Velocity per copy (%)", type: "number", value: 70, min: 10,
              max: 100 }
        ]
    });
    if (!answers) return;
    var span = sel.end - sel.start;
    var gap = Math.round(answers.gap * porydaw.song.ticksPerBeat);
    var scope = rangeScope(sel);
    porydaw.edit.transaction("Echo range", function () {
        var vel = 1;
        for (var i = 1; i <= answers.copies; i++) {
            var offset = i * (span + gap);
            porydaw.edit.duplicateRange(sel.start, sel.end, scope, offset);
            vel *= answers.decay / 100;
            if (scope.tracks) {
                scope.tracks.forEach(function (t) {
                    var notes = porydaw.song.notes({ track: t, from: sel.start + offset,
                                                 to: sel.end + offset });
                    var scale = vel;
                    porydaw.edit.setVelocity(notes, function (n) {
                        return Math.max(1, Math.round(n.vel * scale));
                    });
                });
            }
        }
    });
}

function reverse() {
    var sel = porydaw.selection.time();
    if (!sel || sel.scope !== "tracks") return;
    var scope = rangeScope(sel);
    porydaw.edit.transaction("Reverse notes in range", function () {
        scope.tracks.forEach(function (t) {
            var notes = porydaw.song.notes({ track: t, from: sel.start, to: sel.end });
            notes.forEach(function (n) {
                var mirrored = sel.start + (sel.end - (n.tick + n.len));
                if (mirrored < sel.start) mirrored = sel.start;
                porydaw.edit.moveNotes(n, mirrored - n.tick, 0);
            });
        });
    });
}

export function activate() {
    var dup = porydaw.actions.register({
        id: "duplicate-after", name: "Duplicate range after itself", context: "range",
        default: "Ctrl+Alt+Shift+D", run: duplicateAfter
    });
    var menu = porydaw.ui.contextMenu("range");
    menu.addItem({ label: "Duplicate after itself", action: dup });
    menu.addItem({ label: "Echo…", run: echo });
    menu.addItem({ label: "Reverse notes", run: reverse });
}

export function deactivate() {}
