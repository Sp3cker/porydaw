// Bundled example plugin (docs/scripting/PLAN.md Phase 3): a spectrum
// analyser built with build(root) — a slider above a canvas. Each audio
// frame pulls porydaw.audio.spectrum(bands) (an FFT the host computes on
// demand, so a hidden panel costs nothing) and smooths it for display.

var dock = null, canvas = null, off = null;
var bands = porydaw.storage.get("bands", 32);
var smooth = [];
var peaks = [];

function onFrame() {
    if (!dock.visible) return;
    var s = porydaw.audio.spectrum(bands);
    if (smooth.length !== s.length) { smooth = []; peaks = []; }
    for (var i = 0; i < s.length; i++) {
        var v = Math.sqrt(s[i]); // perceptual-ish: sqrt lifts the quiet bins
        smooth[i] = v > (smooth[i] || 0) ? v : (smooth[i] || 0) * 0.8;
        peaks[i] = v > (peaks[i] || 0) ? v : (peaks[i] || 0) - 0.01;
    }
    canvas.repaint();
}

function paint(g) {
    var t = porydaw.ui.theme();
    g.clear(t.song_view_piano_roll_background);
    var n = smooth.length;
    if (!n) return;
    var pad = 4, bottom = g.height - 14;
    var bw = (g.width - pad * 2) / n;
    for (var i = 0; i < n; i++) {
        var x = pad + i * bw, h = smooth[i] * (bottom - pad);
        g.fillRect(x + 1, bottom - h, Math.max(1, bw - 2), h, t.song_view_selection_edge);
        var ph = Math.max(0, peaks[i]) * (bottom - pad);
        g.fillRect(x + 1, bottom - ph - 1, Math.max(1, bw - 2), 1, t.window_text);
    }
    // Frequency labels: bands are linear from 0 to sampleRate / 2.
    var nyquist = porydaw.audio.sampleRate / 2;
    [0.25, 0.5, 0.75, 1].forEach(function (f) {
        var x = pad + f * (g.width - pad * 2);
        g.text(x, g.height - 2, Math.round(nyquist * f / 1000) + "k", t.secondary_text,
               { size: 0.8, align: "right" });
    });
}

export function activate() {
    dock = porydaw.ui.dock({
        id: "spectrum", title: "Spectrum", area: "bottom", minWidth: 200, minHeight: 90,
        build: function (root) {
            var row = root.addRow();
            row.addLabel("Bands");
            row.addSlider(8, 128, bands, function (v) {
                bands = v;
                porydaw.storage.set("bands", v);
            }, {});
            canvas = root.addCanvas({ minHeight: 60 }, paint, null);
        }
    });
    off = porydaw.audio.on("frame", onFrame);
}

export function deactivate() {
    if (off) off();
    if (dock) dock.close();
    dock = canvas = off = null;
}
