// Song Report: two entries in the Plugins menu. "Song report…" asks what
// to include, then writes a text summary wherever the user points the
// save dialog; "Render to WAV…" renders the song through the Export WAV
// path. Both use porydaw.ui.dialog.* and porydaw.io.

function pad(n, width) {
    var s = String(n);
    while (s.length < width) s = " " + s;
    return s;
}

function buildReport(includeLanes) {
    var song = porydaw.song;
    var lines = [];
    lines.push("Song: " + song.label);
    lines.push("Ticks per beat: " + song.ticksPerBeat + "   Start tempo: " + song.startTempo +
               " BPM   End tick: " + song.endTick);
    var loop = song.loop();
    lines.push(loop ? "Loop: " + loop.start + " .. " + loop.end : "Loop: none");
    lines.push("");
    lines.push("Track  Chunk  Voice  Notes  Lowest  Highest  Lanes");
    song.tracks().forEach(function (t) {
        var notes = song.notes({ track: t.index });
        var lo = 127, hi = 0;
        notes.forEach(function (n) { if (n.key < lo) lo = n.key; if (n.key > hi) hi = n.key; });
        var lanes = [];
        if (includeLanes) {
            for (var cc = 0; cc < 128; cc++)
                if (song.lanePoints(t.index, cc).length) lanes.push("CC" + cc);
            if (song.lanePoints(t.index, song.CC.BEND).length) lanes.push("bend");
            if (song.lanePoints(t.index, song.CC.VOICE).length > 1) lanes.push("voice");
        }
        lines.push(pad(t.index + 1, 5) + "  " + pad(t.chunk, 5) + "  " + pad(t.voice, 5) + "  " +
                   pad(notes.length, 5) + "  " + pad(notes.length ? lo : "-", 6) + "  " +
                   pad(notes.length ? hi : "-", 7) + "  " + lanes.join(" "));
    });
    lines.push("");
    lines.push("Time signatures: " + song.timeSigs().map(function (ts) {
        return ts.numerator + "/" + ts.denominator + "@" + ts.tick;
    }).join(", "));
    return lines.join("\n") + "\n";
}

function songReport() {
    if (!porydaw.song.loaded) {
        porydaw.ui.dialog.alert("Open a song first.");
        return;
    }
    var answers = porydaw.ui.dialog.form({
        title: "Song report",
        text: "Write a plain-text summary of " + porydaw.song.label + ".",
        fields: [
            { key: "lanes", label: "List automation lanes", type: "checkbox", value: true },
            { key: "open", label: "Show it afterwards", type: "checkbox", value: true }
        ]
    });
    if (!answers) return;
    var path = porydaw.ui.dialog.saveFile({
        title: "Save song report", name: porydaw.song.label + "-report.txt",
        filter: "Text files (*.txt)"
    });
    if (!path) return;
    var text = buildReport(answers.lanes);
    porydaw.io.writeText(path, text);
    porydaw.ui.statusMessage("Wrote " + path);
    if (answers.open)
        porydaw.ui.dialog.alert(text, { title: "Song report" });
}

function renderWav() {
    if (!porydaw.song.loaded) {
        porydaw.ui.dialog.alert("Open a song first.");
        return;
    }
    var looping = !!porydaw.song.loop();
    var answers = porydaw.ui.dialog.form({
        title: "Render to WAV",
        fields: [
            { key: "rate", label: "Sample rate", type: "combo",
              items: ["32000 Hz", "44100 Hz", "48000 Hz"], value: 2 },
            { key: "loops", label: looping ? "Loop count" : "Loop count (no loop markers)",
              type: "number", value: 2, min: 1, max: 20 },
            { key: "fade", label: "Fadeout / tail (s)", type: "number", value: looping ? 5 : 3,
              min: 0, max: 60, decimals: 1 }
        ]
    });
    if (!answers) return;
    var path = porydaw.ui.dialog.saveFile({
        title: "Render to WAV", name: porydaw.song.label + ".wav", filter: "WAV files (*.wav)"
    });
    if (!path) return;
    var result = porydaw.audio.render(path, {
        sampleRate: [32000, 44100, 48000][answers.rate], loopCount: answers.loops,
        fadeout: answers.fade, tail: answers.fade
    });
    porydaw.ui.statusMessage("Rendered " + result.path + " (" + result.seconds.toFixed(1) + " s)");
}

export function activate() {
    var menu = porydaw.ui.menu();
    menu.addItem({ label: "Song report…", run: songReport,
                   tooltip: "Write a text summary of the song" });
    menu.addItem({ label: "Render to WAV…", run: renderWav });
}

export function deactivate() {}
