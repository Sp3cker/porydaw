// Bundled example plugin (docs/scripting/PLAN.md Phase 3, archetype 2): a
// beat-reactive avatar. transport.beat fires when the playhead enters a
// new beat of the meter (the downbeat gets a bigger bounce); transport.tick
// runs every frame so the motion decays smoothly, and the picture keeps a
// gentle sway while nothing plays. dancer.png ships with the plugin —
// swap in any image (or a sprite sheet, with g.image's source rectangle).

var dock = null, canvas = null, offs = [];
var img = 0, imgW = 1, imgH = 1;
var bounce = 0;   // 1 right after a beat, decaying
var lean = 0;     // -1..1, alternates per beat
var phase = 0;    // idle sway clock
var lastBeat = null;

function onBeat(b) {
    bounce = b.beat === 0 ? 1.0 : 0.6;
    lean = (b.bar * b.beatsPerBar + b.beat) % 2 ? 1 : -1;
    lastBeat = b;
}

function onTick(t) {
    bounce *= 0.86;
    if (!t.playing) phase += 0.03;
    canvas.repaint();
}

function paint(g) {
    var t = porydaw.ui.theme();
    g.clear(t.window_background);
    var size = Math.min(g.width, g.height) * 0.7;
    var cx = g.width / 2, floor = g.height * 0.85;
    // Shadow shrinks as the dancer jumps.
    var lift = bounce * size * 0.25;
    g.fillEllipse(cx - size * 0.35 * (1 - bounce * 0.3), floor - size * 0.06,
                  size * 0.7 * (1 - bounce * 0.3), size * 0.12, "rgba(0,0,0,0.25)");
    g.save();
    g.translate(cx, floor - lift);
    var sway = lastBeat ? lean * bounce * 12 : Math.sin(phase) * 6;
    g.rotate(sway);
    // Squash on landing, stretch at the top of the jump.
    var sx = 1 + bounce * 0.15, sy = 1 - bounce * 0.15;
    g.scale(sx, sy);
    g.image(img, -size / 2, -size, size, size, 0, 0, imgW, imgH);
    g.restore();
    if (lastBeat) {
        g.text(6, 6, "bar " + (lastBeat.bar + 1) + " · beat " + (lastBeat.beat + 1) +
               " · " + Math.round(lastBeat.bpm) + " bpm", t.secondary_text,
               { size: 0.85, baseline: "top" });
    }
}

export function activate() {
    img = porydaw.ui.loadImage("dancer.png");
    var s = porydaw.ui.imageSize(img);
    imgW = s.width; imgH = s.height;
    dock = porydaw.ui.dock({ id: "dancer", title: "Dancer", area: "right",
                             minWidth: 120, minHeight: 140, paint: paint });
    canvas = dock.canvas;
    offs.push(porydaw.transport.on("beat", onBeat));
    offs.push(porydaw.transport.on("tick", onTick));
}

export function deactivate() {
    offs.forEach(function (off) { off(); });
    offs = [];
    if (dock) dock.close();
    if (img) porydaw.ui.freeImage(img);
    dock = canvas = null;
    img = 0;
}
