// Bundled example plugin (docs/scripting/PLAN.md Phase 3): a stereo VU
// meter in a dock. porydaw.audio fires a frame ~60 times a second with the
// peak and RMS of the mix since the last frame; the panel keeps a decaying
// peak-hold cap per channel and repaints its canvas.

var dock = null;
var canvas = null;
var off = null;
var level = [0, 0];   // displayed RMS (with release)
var hold = [0, 0];    // peak-hold cap
var holdAge = [0, 0]; // frames since the cap was set
var clipped = [false, false];

function toDb(x) { return x > 0 ? 20 * Math.log10(x) : -Infinity; }
// Meter position 0..1 for a linear level: -60 dB .. 0 dB.
function pos(x) {
    var db = toDb(x);
    return Math.max(0, Math.min(1, (db + 60) / 60));
}

function onFrame(frame) {
    for (var c = 0; c < 2; c++) {
        var rms = frame.rms[c], peak = frame.peak[c];
        // Fast attack, slow release, so a transient shows and then decays.
        level[c] = rms > level[c] ? rms : level[c] * 0.85;
        if (peak >= hold[c]) { hold[c] = peak; holdAge[c] = 0; }
        else if (++holdAge[c] > 45) hold[c] *= 0.9;
        if (peak >= 0.999) clipped[c] = true;
    }
    if (canvas) canvas.repaint();
}

function paint(g) {
    var t = porydaw.ui.theme();
    g.clear(t.window_background);
    var pad = 8, gap = 6, labelW = 30, scaleH = 16;
    var barH = Math.max(8, (g.height - pad * 3 - scaleH) / 2);
    var x0 = pad + labelW, w = g.width - x0 - pad;
    if (w < 20) return;
    ["L", "R"].forEach(function (name, c) {
        var y = pad + c * (barH + gap);
        g.text(pad, y + barH / 2, name, t.window_text, { baseline: "middle", bold: true });
        g.fillRoundRect(x0, y, w, barH, 3, t.item_alternate_background);
        // Green up to -12 dB, amber to -3 dB, red above.
        var p = pos(level[c]);
        var segs = [[0, 0.8, "#3fb950"], [0.8, 0.95, "#d29922"], [0.95, 1, "#f85149"]];
        segs.forEach(function (s) {
            var from = s[0], to = Math.min(p, s[1]);
            if (to > from) g.fillRect(x0 + from * w, y + 2, (to - from) * w, barH - 4, s[2]);
        });
        var hp = pos(hold[c]);
        if (hp > 0) g.fillRect(x0 + hp * w - 2, y + 1, 2, barH - 2, t.window_text);
        if (clipped[c]) g.fillRect(x0 + w - 6, y, 6, barH, "#f85149");
    });
    // dB scale under the bars.
    var y = pad * 2 + barH * 2 + gap - 2;
    [-60, -48, -36, -24, -12, -6, 0].forEach(function (db) {
        var x = x0 + (db + 60) / 60 * w;
        g.line(x, y, x, y + 3, t.secondary_text, 1);
        if (y + 14 < g.height)
            g.text(x, y + 5, String(db), t.secondary_text, { size: 0.8, align: db === 0 ? "right" : "center", baseline: "top" });
    });
}

export function activate() {
    dock = porydaw.ui.dock({
        id: "meter", title: "VU Meter", area: "right", minWidth: 160, minHeight: 72,
        paint: paint,
        mouse: function (ev) {
            if (ev.type === "press") { clipped = [false, false]; hold = [0, 0]; }
        }
    });
    canvas = dock.canvas;
    off = porydaw.audio.on("frame", onFrame);
}

export function deactivate() {
    if (off) off();
    if (dock) dock.close();
    dock = canvas = off = null;
}
