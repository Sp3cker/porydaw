// porydaw scripting prelude: assembles the user-facing `porydaw` object
// from the C++ facades (scriptapi.h). Evaluated once per plugin engine;
// the host calls the returned function with the facades and installs the
// result's `porydaw` and `console` as globals. ES2017 at most: Qt 6.2's
// QJSEngine is the floor.
(function (host, song, selection, cursor, transport, actions, storage, project, edit, view,
          audio, ui) {
    "use strict";

    var listeners = {};
    var runners = {};

    function fmt(v) {
        if (v instanceof Error)
            return v.stack ? String(v.stack) : String(v);
        if (typeof v === "object" && v !== null) {
            try { return JSON.stringify(v); } catch (e) { return String(v); }
        }
        return String(v);
    }
    function joinArgs(args) {
        return Array.prototype.map.call(args, fmt).join(" ");
    }
    function on(event, fn) {
        if (typeof fn !== "function")
            throw new TypeError("listener for '" + event + "' must be a function");
        var l = listeners[event] || (listeners[event] = []);
        l.push(fn);
        host.subscribed(event, l.length);
        return function () { off(event, fn); };
    }
    function off(event, fn) {
        var l = listeners[event];
        if (!l) return;
        var i = l.indexOf(fn);
        if (i >= 0) l.splice(i, 1);
        host.subscribed(event, l.length);
    }
    // Every listener runs even when one throws; a throwing listener is
    // reported against the plugin, not silently dropped.
    function dispatch(event, payload) {
        var l = listeners[event];
        if (!l || !l.length) return;
        l = l.slice();
        for (var i = 0; i < l.length; i++) {
            try { l[i](payload); } catch (e) { host.reportError(e); }
        }
    }
    function events(prefix) {
        return {
            on: function (ev, fn) { return on(prefix + "." + ev, fn); },
            off: function (ev, fn) { off(prefix + "." + ev, fn); }
        };
    }
    function mix(target, source) {
        Object.keys(source).forEach(function (k) { target[k] = source[k]; });
        return target;
    }
    // Note arguments: one note or id, or an array of either.
    function toIds(x) {
        if (x === undefined || x === null) return [];
        if (!Array.isArray(x)) x = [x];
        return x.map(function (n) {
            return typeof n === "object" && n !== null ? n.id : n;
        });
    }
    // Track arguments must be real integers: the C++ side would coerce
    // undefined/NaN to track 0.
    function trackArg(t, api) {
        if (typeof t !== "number" || !isFinite(t) || Math.floor(t) !== t)
            throw new TypeError(api + ": track must be an integer");
        return t;
    }
    function toNotes(x) {
        if (x === undefined || x === null) return [];
        if (!Array.isArray(x)) x = [x];
        var out = [];
        x.forEach(function (n) {
            if (typeof n === "object" && n !== null) { out.push(n); return; }
            var note = song.note(n);
            if (note) out.push(note);
        });
        return out;
    }

    var api = {
        version: host.appVersion,
        api: { version: host.apiVersion, major: host.apiMajor },
        plugin: {
            id: host.pluginId, name: host.pluginName,
            version: host.pluginVersion, dir: host.pluginDir
        },
        log: function () { host.log(0, joinArgs(arguments)); },
        warn: function () { host.log(1, joinArgs(arguments)); },
        error: function () { host.log(2, joinArgs(arguments)); },

        project: {
            get isOpen() { return project.isOpen; },
            get root() { return project.root; },
            songs: function () { return project.songs(); }
        },

        song: mix({
            CC: { BEND: 0xFF, TEMPO: 0xFE, VOICE: 0xFD },
            get loaded() { return song.loaded; },
            get revision() { return song.revision; },
            get label() { return song.label; },
            get midPath() { return song.midPath; },
            get ticksPerBeat() { return song.ticksPerBeat; },
            get ticksPerClock() { return song.ticksPerClock; },
            get startTempo() { return song.startTempo; },
            get trackCount() { return song.trackCount; },
            get trackBudget() { return song.trackBudget; },
            get endTick() { return song.endTick; },
            loop: function () { return song.loop(); },
            timeSigs: function () { return song.timeSigs(); },
            tracks: function () { return song.tracks(); },
            notes: function (opts) { return song.notes(opts || {}); },
            note: function (id) { return song.note(id); },
            lanePoints: function (track, cc, opts) { return song.lanePoints(track, cc, opts || {}); }
        }, events("song")),

        selection: mix({
            get track() { return selection.track; },
            get trackMask() { return selection.trackMask; },
            notes: function () { return selection.notes(); },
            time: function () { return selection.time(); },
            setNotes: function (notes) { selection.setNotes(toIds(notes)); },
            clear: function () { selection.clear(); },
            selectTrack: function (track) {
                selection.selectTrack(trackArg(track, "selection.selectTrack"));
            },
            setTime: function (spec) { selection.setTime(spec || {}); },
            clearTime: function () { selection.clearTime(); }
        }, events("selection")),

        edit: {
            get active() { return edit.active; },
            // Runs fn inside one undo entry named `name`; returns fn's
            // result. An exception (fn's own or a refused edit) rolls the
            // whole transaction back and propagates. Nested transactions
            // join the outermost one.
            transaction: function (name, fn) {
                if (typeof name !== "string" || !name)
                    throw new TypeError("edit.transaction: expected a name");
                if (typeof fn !== "function")
                    throw new TypeError("edit.transaction: expected a function");
                edit.begin(name);
                var result;
                try {
                    result = fn();
                } catch (e) {
                    edit.rollback();
                    throw e;
                }
                edit.commit();
                return result;
            },
            addNotes: function (track, notes) {
                return edit.addNotes(trackArg(track, "edit.addNotes"),
                                     Array.isArray(notes) ? notes : [notes]);
            },
            deleteNotes: function (notes) { return edit.deleteNotes(toIds(notes)); },
            moveNotes: function (notes, dTick, dKey) {
                return edit.moveNotes(toIds(notes), dTick || 0, dKey || 0);
            },
            resizeNotes: function (notes, dLen, opts) {
                return edit.resizeNotes(toIds(notes), dLen || 0, !!(opts && opts.fromLeft));
            },
            // setVelocity(notes, vel) or setVelocity(notes, function (note) { return vel; })
            setVelocity: function (notes, vel) {
                var pairs;
                if (typeof vel === "function") {
                    pairs = toNotes(notes).map(function (n) { return { id: n.id, vel: vel(n) }; });
                } else {
                    pairs = toIds(notes).map(function (id) { return { id: id, vel: vel }; });
                }
                return edit.setVelocities(pairs);
            },
            nudgeVelocity: function (notes, delta) {
                return edit.nudgeVelocity(toIds(notes), delta || 0);
            },
            addLanePoint: function (track, cc, tick, value) {
                edit.addLanePoint(trackArg(track, "edit.addLanePoint"), cc, tick, value);
            },
            writeLanePoints: function (track, cc, from, to, points) {
                edit.writeLanePoints(trackArg(track, "edit.writeLanePoints"), cc, from, to,
                                     points || []);
            },
            moveLanePoints: function (track, cc, moves) {
                return edit.moveLanePoints(trackArg(track, "edit.moveLanePoints"), cc, moves || []);
            },
            deleteLanePoints: function (track, cc, ticks) {
                return edit.deleteLanePoints(trackArg(track, "edit.deleteLanePoints"), cc,
                                             ticks || []);
            },
            setStartTempo: function (bpm) { edit.setStartTempo(bpm); },
            setLoop: function (start, end) { edit.setLoop(start, end); },
            setTimeSig: function (tick, numerator, denominator) {
                edit.setTimeSig(tick, numerator, denominator);
            },
            deleteTimeSig: function (tick) { edit.deleteTimeSig(tick); },
            removeTimeRange: function (start, end, scope) {
                return edit.removeTimeRange(start, end, scope || {});
            },
            insertTimeRange: function (at, span, scope) {
                return edit.insertTimeRange(at, span, scope || {});
            },
            addTrack: function (voice) { return edit.addTrack(voice || 0); },
            duplicateTrack: function (track) {
                return edit.duplicateTrack(trackArg(track, "edit.duplicateTrack"));
            },
            deleteTrack: function (track) { edit.deleteTrack(trackArg(track, "edit.deleteTrack")); },
            moveTrack: function (track, target) {
                return edit.moveTrack(trackArg(track, "edit.moveTrack"),
                                      trackArg(target, "edit.moveTrack"));
            },
            renameTrack: function (track, name) {
                edit.renameTrack(trackArg(track, "edit.renameTrack"), String(name));
            },
            transposeSelection: function (dKey) { return edit.transposeSelection(dKey || 0); },
            // direction: "left" | "right"
            nudgeSelection: function (direction) {
                if (direction !== "left" && direction !== "right")
                    throw new TypeError("edit.nudgeSelection: direction must be 'left' or 'right'");
                return edit.nudgeSelection(direction === "right");
            }
        },

        view: {
            visibleTicks: function () { return view.visibleTicks(); },
            revealTick: function (tick) { view.revealTick(tick); },
            revealRange: function (from, to) { view.revealRange(from, to); },
            revealNote: function (note) { return view.revealNote(toIds(note)[0]); },
            revealKey: function (key) { view.revealKey(key); },
            get velocityLane() { return view.velocityLane; },
            set velocityLane(on) { view.velocityLane = !!on; },
            get automationLanes() { return view.automationLanes; },
            set automationLanes(on) { view.automationLanes = !!on; },
            get tempoLane() { return view.tempoLane; },
            set tempoLane(on) { view.tempoLane = !!on; },
            get eventList() { return view.eventList; },
            set eventList(on) { view.eventList = !!on; },
            get pxPerBeat() { return view.pxPerBeat; },
            get keyHeight() { return view.keyHeight; }
        },

        cursor: {
            get tick() { return cursor.tick; },
            snap: function (tick, mode) { return cursor.snap(tick, mode || "nearest"); },
            grid: function (tick) { return cursor.grid(tick === undefined ? cursor.tick : tick); },
            set: function (tick) { cursor.set(tick); }
        },

        transport: mix({
            get state() { return transport.state; },
            get playheadTick() { return transport.playheadTick; },
            get sampleRate() { return transport.sampleRate; },
            get loopEnabled() { return transport.loopEnabled; },
            play: function () { transport.play(); },
            pause: function () { transport.pause(); },
            stop: function () { transport.stop(); },
            seek: function (tick) { transport.seek(tick); }
        }, events("transport")),

        audio: mix({
            get sampleRate() { return audio.sampleRate; },
            get windowFrames() { return audio.windowFrames; },
            get peak() { return audio.peak(); },
            get rms() { return audio.rms(); },
            pcm: function () { return new Float32Array(audio.pcm()); },
            spectrum: function (bins) { return new Float32Array(audio.spectrum(bins || 64)); },
            channels: function () { return audio.channels(); }
        }, events("audio")),

        actions: {
            // {id, name, context?, default?, run} → full keymap id.
            register: function (spec) {
                if (!spec || typeof spec !== "object")
                    throw new TypeError("actions.register: expected a spec object");
                if (typeof spec.run !== "function")
                    throw new TypeError("actions.register: spec.run must be a function");
                var fullId = actions.registerAction({
                    id: spec.id, name: spec.name,
                    context: spec.context || "global",
                    default: spec.default || ""
                });
                runners[fullId] = spec.run;
                return fullId;
            },
            unregister: function (fullId) {
                delete runners[fullId];
                actions.unregister(fullId);
            }
        },

        ui: {
            statusMessage: function (text) { host.statusMessage(String(text)); },
            // {id, title?, area?, minWidth?, minHeight?, paint?(g), mouse?(ev),
            //  build?(root)} → dock handle. paint makes the dock one canvas;
            // build lays out widgets on root (a column).
            dock: function (spec) {
                if (!spec || typeof spec !== "object")
                    throw new TypeError("ui.dock: expected a spec object");
                var opts = {};
                ["id", "title", "area", "minWidth", "minHeight"].forEach(function (k) {
                    if (spec[k] !== undefined) opts[k] = spec[k];
                });
                if (opts.id !== undefined) opts.id = String(opts.id);
                return ui.dock(opts, spec.build, spec.paint, spec.mouse);
            },
            theme: function (name) { return ui.theme(name === undefined ? "" : String(name)); },
            loadImage: function (path) { return ui.loadImage(String(path)); },
            imageSize: function (id) { return ui.imageSize(id); },
            freeImage: function (id) { ui.freeImage(id); }
        },

        storage: {
            get: function (key, fallback) { return storage.get(String(key), fallback); },
            set: function (key, value) { storage.set(String(key), value); },
            remove: function (key) { storage.remove(String(key)); },
            keys: function () { return storage.keys(); }
        }
    };

    function runAction(fullId) {
        var fn = runners[fullId];
        if (!fn) return false;
        fn({ song: api.song, selection: api.selection, cursor: api.cursor,
             transport: api.transport, edit: api.edit, view: api.view });
        return true;
    }

    var console = {
        log: api.log, info: api.log, debug: api.log,
        warn: api.warn, error: api.error
    };

    return { porydaw: api, console: console, dispatch: dispatch, runAction: runAction };
})
