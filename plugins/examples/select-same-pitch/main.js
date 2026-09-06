// Bundled example plugin (docs/scripting/PLAN.md Phase 1): a piano-roll
// command that reads the selection and the track's notes and writes the
// selection back. Copy this folder into the plugins folder shown in
// Settings → Plugins to try it.

export function activate(ctx) {
    porydaw.actions.register({
        id: "select",
        name: "Select notes of the same pitch",
        context: "roll",
        default: "Ctrl+Shift+A",
        run: function () {
            var selected = porydaw.selection.notes();
            if (!selected.length) {
                porydaw.ui.statusMessage("Select a note first.");
                return;
            }
            var keys = {};
            selected.forEach(function (n) { keys[n.key] = true; });
            var matches = porydaw.song.notes({ track: porydaw.selection.track }).filter(function (n) {
                return keys[n.key];
            });
            porydaw.selection.setNotes(matches);
            porydaw.ui.statusMessage("Selected " + matches.length + " notes across " +
                Object.keys(keys).length + " pitch(es).");
        }
    });
    porydaw.log("ready: " + ctx.name + " " + ctx.version);
}

export function deactivate() {
    // Actions, listeners and storage handles are released by the host.
}
