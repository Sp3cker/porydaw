// porydaw scripting prelude: assembles the user-facing `porydaw` object
// from the C++ facades (scriptapi.h). Evaluated once per plugin engine;
// the host calls the returned function with the facades and installs the
// result's `porydaw` and `console` as globals. ES2017 at most: Qt 6.2's
// QJSEngine is the floor.
(function (host, song, selection, cursor, transport, actions, storage, project) {
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
        (listeners[event] || (listeners[event] = [])).push(fn);
        return function () { off(event, fn); };
    }
    function off(event, fn) {
        var l = listeners[event];
        if (!l) return;
        var i = l.indexOf(fn);
        if (i >= 0) l.splice(i, 1);
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
            setNotes: function (ids) {
                ids = Array.prototype.map.call(ids || [], function (n) {
                    return typeof n === "object" && n !== null ? n.id : n;
                });
                selection.setNotes(ids);
            },
            clear: function () { selection.clear(); },
            selectTrack: function (track) { selection.selectTrack(track); }
        }, events("selection")),

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
            statusMessage: function (text) { host.statusMessage(String(text)); }
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
             transport: api.transport });
        return true;
    }

    var console = {
        log: api.log, info: api.log, debug: api.log,
        warn: api.warn, error: api.error
    };

    return { porydaw: api, console: console, dispatch: dispatch, runAction: runAction };
})
