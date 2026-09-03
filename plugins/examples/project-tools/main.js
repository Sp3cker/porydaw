// Project Tools: two entries in the Plugins menu built on the project
// adapter API. "Registration audit…" lists the songs whose registration
// files lack a line and registers them (porydaw.project.registerSong);
// "Apply envelope to sample voices…" writes one ADSR into every
// DirectSound voice of the song's voicegroup as a single undo entry
// (porydaw.voicegroup + porydaw.edit.setVoice), saved with the song.

function registrationAudit() {
    if (!porydaw.project.isOpen) {
        porydaw.ui.dialog.alert("Open a project first.");
        return;
    }
    var gaps = porydaw.project.songs().filter(function (s) {
        return s.hasMid && s.registrationGaps.length > 0;
    });
    if (!gaps.length) {
        porydaw.ui.dialog.alert("Every song is fully registered.");
        return;
    }
    var detail = gaps.map(function (s) {
        return s.label + " — missing in " + s.registrationGaps.join(", ");
    }).join("\n");
    if (!porydaw.ui.dialog.confirm("Register " + gaps.length + " song(s)?",
                                   { title: "Registration audit", detail: detail, ok: "Register" }))
        return;
    var failed = [];
    gaps.forEach(function (s) {
        try {
            porydaw.project.registerSong(s.label);
        } catch (e) {
            failed.push(s.label + ": " + e.message);
        }
    });
    if (failed.length)
        porydaw.ui.dialog.alert("Some songs could not be registered.", { detail: failed.join("\n") });
    else
        porydaw.ui.statusMessage("Registered " + gaps.length + " song(s)");
}

function applyEnvelope() {
    if (!porydaw.voicegroup.isOpen) {
        porydaw.ui.dialog.alert("Open a song whose voicegroup can be edited first.");
        return;
    }
    var voices = porydaw.voicegroup.voices().filter(function (v) {
        return v.kind === "voice" && v.type.indexOf("voice_directsound") === 0;
    });
    if (!voices.length) {
        porydaw.ui.dialog.alert(porydaw.voicegroup.name + " has no DirectSound voices.");
        return;
    }
    var typical = porydaw.voicegroup.typicalAdsr("voice_directsound");
    var field = function (key, label, value) {
        return { key: key, label: label, type: "number", value: value, min: 0, max: 255 };
    };
    var answers = porydaw.ui.dialog.form({
        title: "Apply envelope",
        text: "Every DirectSound voice of " + porydaw.voicegroup.name + " (" + voices.length +
              " voices) gets this envelope. Undo reverts all of them at once; Save writes the file.",
        fields: [field("attack", "Attack", typical.attack), field("decay", "Decay", typical.decay),
                 field("sustain", "Sustain", typical.sustain),
                 field("release", "Release", typical.release)]
    });
    if (!answers) return;
    porydaw.edit.transaction("Apply envelope", function () {
        voices.forEach(function (v) {
            porydaw.edit.setVoice(v.slot, { attack: answers.attack, decay: answers.decay,
                                            sustain: answers.sustain, release: answers.release });
        });
    });
    porydaw.ui.statusMessage("Envelope applied to " + voices.length + " voices — save to keep it");
}

export function activate() {
    var menu = porydaw.ui.menu();
    menu.addItem({ label: "Registration audit…", run: registrationAudit,
                   tooltip: "Register every song whose registration files miss a line" });
    menu.addItem({ label: "Apply envelope to sample voices…", run: applyEnvelope,
                   tooltip: "One ADSR for every DirectSound voice of the song's voicegroup" });
}

export function deactivate() {}
