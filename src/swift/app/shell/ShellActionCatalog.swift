import PorydawAppCommands

@MainActor
enum ShellActionCatalog {
    struct Action {
        let id: String
        let command: EditCommand?

        init(_ id: String, _ command: EditCommand? = nil) {
            self.id = id
            self.command = command
        }
    }

    static let actions: [Action] = [
        Action("file.open_project"),
        Action("file.open_backups"),
        Action("file.new_song"),
        Action("file.import_midi"),
        Action("songs.find"),
        Action("file.save_song"),
        Action("file.register_song"),
        Action("file.close_tab"),
        Action("file.export_wav"),
        Action("file.quit"),
        Action("edit.undo"),
        Action("edit.redo"),
        Action("edit.preferences"),
        Action("edit.song_settings"),
        Action("edit.engine_settings"),
        Action("roll.copy", .copy),
        Action("roll.cut", .cut),
        Action("roll.duplicate_time", .duplicate),
        Action("roll.paste", .paste),
        Action("roll.delete", .delete),
        Action("roll.select_all", .selectAll),
        Action("edit.insert_time", .insertTime),
        Action("edit.delete_time", .deleteTime),
        Action("edit.clear_time_selection", .clearTimeSelection),
        Action("edit.edit_time_signature", .editTimeSignature),
        Action("edit.remove_time_signature", .removeTimeSignature),
        Action("edit.set_loop_start", .setLoopStart),
        Action("edit.set_loop_end", .setLoopEnd),
        Action("edit.loop_from_selection", .loopFromSelection),
        Action("edit.remove_loop", .removeLoop),
        Action("roll.transpose_up", .transposeUp),
        Action("roll.transpose_down", .transposeDown),
        Action("roll.transpose_up_octave", .transposeUpOctave),
        Action("roll.transpose_down_octave", .transposeDownOctave),
        Action("roll.pitch_bend", .pitchBend),
        Action("edit.set_velocity", .setVelocity),
        Action("roll.nudge_left", .nudgeLeft),
        Action("roll.nudge_right", .nudgeRight),
        Action("roll.mute_tracks", .muteTracks),
        Action("roll.solo_tracks", .soloTracks),
        Action("automation.pencil_mode", .pencilMode),
        Action("eventlist.move_up", .moveEventUp),
        Action("eventlist.move_down", .moveEventDown),
        Action("roll.split", .split),
        Action("roll.join", .join),
        Action("roll.lengthen_note", .lengthenNote),
        Action("roll.shorten_note", .shortenNote),
        Action("roll.grid_narrow", .gridNarrow),
        Action("roll.grid_widen", .gridWiden),
        Action("roll.grid_triplet", .gridTriplet),
        Action("transport.go_to_start"),
        Action("transport.play"),
        Action("transport.play_pause"),
        Action("transport.pause"),
        Action("transport.stop"),
        Action("transport.loop"),
        Action("transport.follow_playhead"),
        Action("transport.resonance"),
        Action("view.event_list"),
        Action("view.automation_drawer"),
        Action("view.velocity_drawer"),
        Action("view.voice_changes_drawer"),
        Action("view.polyphony_debugger"),
        Action("view.undo_history"),
        Action("view.note_names"),
        Action("tools.import_sample"),
        Action("help.about"),
    ]
    static let byId = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
    static let allActionIds = actions.map(\.id)
    static let fileIds = allActionIds.filter {
        $0.hasPrefix("file.") && $0 != "file.export_wav" && $0 != "file.quit"
    }
    static let fileExportIds = ["file.export_wav"]
    static let fileQuitIds = ["file.quit"]
    static let editTopIds = ["edit.undo", "edit.redo"]
    static let editClipboardIds = [
        "roll.copy", "roll.cut", "roll.paste", "roll.delete", "roll.select_all", "songs.find",
    ]
    static let timeIds = [
        "edit.insert_time", "edit.delete_time", "roll.duplicate_time",
        "edit.clear_time_selection", "edit.edit_time_signature", "edit.remove_time_signature",
    ]
    static let notesIds = [
        "roll.transpose_up", "roll.transpose_down",
        "roll.transpose_up_octave", "roll.transpose_down_octave",
        "roll.pitch_bend", "edit.set_velocity", "roll.duplicate_time", "roll.split", "roll.join",
    ]
    static let moveIds = ["roll.nudge_left", "roll.nudge_right"]
    static let tracksIds = ["roll.mute_tracks", "roll.solo_tracks"]
    static let automationIds = ["automation.pencil_mode"]
    static let eventsIds = ["eventlist.move_up", "eventlist.move_down"]
    static let loopIds = [
        "edit.set_loop_start", "edit.set_loop_end", "edit.loop_from_selection", "edit.remove_loop",
    ]
    static let editTailIds = [
        "edit.preferences", "edit.song_settings", "edit.engine_settings",
    ]
    static let transportIds = [
        "transport.go_to_start", "transport.play", "transport.play_pause",
        "transport.pause", "transport.stop", "transport.loop",
    ]
    static let viewIds =
        allActionIds.filter { $0.hasPrefix("view.") }
        + ["transport.follow_playhead"]
    static let toolsIds = ["tools.import_sample"]
    static let contextHeadIds = ["edit.set_velocity"]
    static let contextBodyIds = [
        "roll.copy", "roll.cut", "roll.duplicate_time", "roll.split", "roll.join", "roll.delete",
    ]
    static let menuLabels = [
        "file.open_project": "Open Project...",
        "file.open_backups": "Open Backups...",
        "file.import_midi": "Import MIDI...",
        "file.export_wav": "Export WAV...",
        "tools.import_sample": "Import Sample...",
        "edit.preferences": "Preferences...",
        "edit.song_settings": "Song Settings...",
        "edit.engine_settings": "Engine Settings...",
        "view.voice_changes_drawer": "Voice-change Drawer",
    ]

    /// Scope inspection is pure Swift; Qt resolves sequence strings only after
    /// QGuiApplication starts.
    static let windowIds: [String] = {
        let registry = KeybindingRegistry()
        let ids = Set(registry.ids)
        return actions.compactMap { action in
            ids.contains(action.id) && registry.scope(action.id) == .window
                ? action.id : nil
        }
    }()
}
