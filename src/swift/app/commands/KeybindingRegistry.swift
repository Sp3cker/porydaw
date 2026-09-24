import Foundation
import QtBridgeCpp
import QtKeybindings

/// Whether a command is delivered by a window shortcut or routed by its editor.
public enum KeybindingScope: Sendable {
    case window
    case editorRouted
}

/// One Qt-resolved binding, with combined strokes and portable/native Qt text.
public struct KeybindingSequence: Sendable {
    public let strokes: [Int]
    public let portableText: String
    public let nativeText: String
}

/// The fixed shipped catalogue from `src/ui/keymap.cpp:54-185`.
/// Constructing this value does not touch Qt; resolve bindings only after a
/// QGuiApplication exists, as required by QKeySequence.keyBindings.
public struct KeybindingRegistry {
    public init() {}

    /// Catalogue IDs in the native registry's stable order, including hold chords.
    public var ids: [String] { Self.allIDs }

    /// The user-visible name of a shipped command, or empty for an unknown ID.
    public func label(_ id: String) -> String { Self.byID[id]?.label ?? "" }

    /// The delivery scope for a shipped command.
    public func scope(_ id: String) -> KeybindingScope {
        guard let definition = Self.byID[id] else { preconditionFailure("Unknown keybinding: \(id)") }
        return definition.scope
    }

    /// Qt's actual platform bindings, or the parsed literal alternates; empty for holds.
    public func sequences(_ id: String) -> [KeybindingSequence] {
        guard Self.byID[id]?.holdChord == 0 else { return [] }
        return Self.resolvedSequences[id] ?? []
    }

    /// The fixed chord of a hold command, or zero for other/unknown IDs.
    public func modifierBinding(_ id: String) -> Int { Self.byID[id]?.holdChord ?? 0 }

    /// Match a hold chord ignoring non-shortcut modifiers; optionally accept added Shift.
    public func matchesModifier(_ modifiers: Int, _ id: String, allowShift: Bool = false) -> Bool {
        let chord = modifierBinding(id)
        guard chord != 0 else { return false }
        let held = modifiers & Self.shortcutModifierMask
        return held == chord || (allowShift && held == (chord | Self.shiftModifier))
    }

    /// The first combined Qt keystroke, only when the first binding has one stroke.
    public func singleStroke(_ id: String) -> Int? {
        guard let first = sequences(id).first, first.strokes.count == 1 else { return nil }
        return first.strokes[0]
    }

    /// Match any single-stroke binding, ignoring Keypad and GroupSwitch modifiers.
    public func matches(_ key: Int, _ modifiers: Int, _ id: String) -> Bool {
        guard key != 0, key != Self.unknownKey, !Self.modifierKeys.contains(key),
              Self.byID[id]?.holdChord == 0 else { return false }
        let combined = key | (modifiers & Self.shortcutModifierMask)
        return sequences(id).contains { $0.strokes.count == 1 && $0.strokes[0] == combined }
    }

    // Qt namespace constants in qnamespace.h:1071-1085, 700-703, 1068.
    // Swift's Qt C++ importer cannot name these enum members; the integers
    // are Qt's API values, not a substitute platform keyboard mapping.
    private static let shiftModifier = 0x0200_0000
    private static let controlModifier = 0x0400_0000
    private static let shortcutModifierMask = 0x1e00_0000
    private static let unknownKey = 0x01ff_ffff
    private static let modifierKeys: Set<Int> = [0x0100_0020, 0x0100_0021, 0x0100_0022, 0x0100_0023]

    // StandardKey raw values from QtGui/qkeysequence.h:39-110. Qt resolves
    // every platform's actual bindings (including alternates) at runtime.
    private enum Standard: UInt32, Sendable {
        case open = 3, close = 4, save = 5, new = 6
        case cut = 8, copy = 9, paste = 10, undo = 11, redo = 12
        case find = 22, selectAll = 26, preferences = 64, quit = 65
    }

    private struct Definition: Sendable {
        let id: String
        let scope: KeybindingScope
        let label: String
        let standard: Standard?
        let keys: String
        let holdChord: Int

        init(_ id: String, _ scope: KeybindingScope, _ label: String,
             standard: Standard? = nil, keys: String = "", holdChord: Int = 0) {
            self.id = id
            self.scope = scope
            self.label = label
            self.standard = standard
            self.keys = keys
            self.holdChord = holdChord
        }
    }

    // Exact IDs, order, labels, scopes and bindings: keymap.cpp:58-185.
    // No QSettings reads: native keymapregistry.cpp:11-37 proves old keymap/
    // settings (including empty and conflicting overrides) are ignored.
    private static let definitions: [Definition] = [
        .init("file.open_project", .window, "Open Project", standard: .open),
        .init("file.new_song", .window, "New Song", standard: .new),
        .init("file.import_midi", .window, "Import MIDI"),
        .init("file.save_song", .window, "Save Song", standard: .save),
        .init("file.register_song", .window, "Register Song"),
        .init("file.close_tab", .window, "Close Tab", standard: .close),
        .init("file.export_wav", .window, "Export WAV"),
        .init("file.quit", .window, "Quit", standard: .quit),
        .init("edit.undo", .window, "Undo", standard: .undo),
        .init("edit.redo", .window, "Redo", standard: .redo),
        .init("edit.insert_time", .window, "Insert Time", keys: "Ctrl+Shift+I"),
        .init("edit.delete_time", .window, "Delete Time"),
        .init("edit.clear_time_selection", .editorRouted, "Clear Time Selection"),
        .init("edit.preferences", .window, "Preferences", standard: .preferences, keys: "Ctrl+,"),
        .init("edit.song_settings", .window, "Song Settings"),
        .init("edit.engine_settings", .window, "Engine Settings"),
        .init("edit.set_velocity", .editorRouted, "Set Velocity…"),
        .init("edit.set_loop_start", .editorRouted, "Set Loop Start at Edit Cursor"),
        .init("edit.set_loop_end", .editorRouted, "Set Loop End at Edit Cursor"),
        .init("edit.loop_from_selection", .editorRouted, "Loop from Time Selection"),
        .init("edit.remove_loop", .editorRouted, "Remove Loop Markers"),
        .init("edit.edit_time_signature", .editorRouted, "Edit Time Signature at Edit Cursor…"),
        .init("edit.remove_time_signature", .editorRouted, "Remove Time Signature"),
        .init("view.theme", .window, "Theme"),
        .init("view.event_list", .window, "MIDI Event List", keys: "Ctrl+Shift+E"),
        .init("view.velocity_colors", .window, "Color Notes by Velocity"),
        .init("view.note_names", .window, "Show Note Names"),
        .init("view.automation_drawer", .window, "Automation Drawer", keys: "A"),
        .init("view.velocity_drawer", .window, "Velocity Drawer", keys: "V"),
        .init("view.voice_changes_drawer", .window, "Voice Changes Drawer", keys: "P"),
        .init("view.polyphony_debugger", .window, "Polyphony Debugger", keys: "Ctrl+Shift+P"),
        .init("tools.import_sample", .window, "Import Sample"),
        .init("transport.go_to_start", .window, "Go to Start", keys: "Home"),
        .init("transport.play", .window, "Play"),
        .init("transport.play_pause", .window, "Play/Pause", keys: "Space"),
        .init("transport.pause", .window, "Pause"),
        .init("transport.stop", .window, "Stop"),
        .init("transport.loop", .window, "Toggle Loop"),
        .init("transport.follow_playhead", .window, "Follow Playhead"),
        .init("songs.find", .window, "Find Song", standard: .find),
        .init("help.about", .window, "About porydaw"),
        .init("roll.copy", .window, "Copy Selection", standard: .copy),
        .init("roll.cut", .editorRouted, "Cut Selection", standard: .cut),
        .init("roll.duplicate_time", .editorRouted, "Duplicate", keys: "Ctrl+D"),
        .init("roll.split", .editorRouted, "Split Notes", keys: "Ctrl+E"),
        .init("roll.join", .editorRouted, "Join Notes", keys: "Ctrl+J"),
        .init("roll.paste", .editorRouted, "Paste at Edit Cursor", standard: .paste),
        .init("roll.select_all", .editorRouted, "Select All Notes", standard: .selectAll),
        .init("roll.delete", .editorRouted, "Delete Selection", keys: "Delete;Backspace"),
        .init("roll.pitch_bend", .editorRouted, "Edit Note Pitch Bend", keys: "G"),
        .init("roll.transpose_up", .editorRouted, "Transpose Up (Semitone)", keys: "Up"),
        .init("roll.transpose_down", .editorRouted, "Transpose Down (Semitone)", keys: "Down"),
        .init("roll.transpose_up_octave", .editorRouted, "Transpose Up (Octave)", keys: "Shift+Up"),
        .init("roll.transpose_down_octave", .editorRouted, "Transpose Down (Octave)", keys: "Shift+Down"),
        .init("roll.nudge_left", .editorRouted, "Nudge Left", keys: "Left"),
        .init("roll.nudge_right", .editorRouted, "Nudge Right", keys: "Right"),
        .init("roll.lengthen_note", .editorRouted, "Lengthen Note", keys: "Shift+Right"),
        .init("roll.shorten_note", .editorRouted, "Shorten Note", keys: "Shift+Left"),
        .init("roll.grid_widen", .editorRouted, "Widen Grid", keys: "Ctrl+2"),
        .init("roll.grid_narrow", .editorRouted, "Narrow Grid", keys: "Ctrl+1"),
        .init("roll.grid_triplet", .editorRouted, "Toggle Triplet Grid", keys: "Ctrl+3"),
        .init("roll.mute_tracks", .editorRouted, "Mute Selected Tracks", keys: "M"),
        .init("roll.solo_tracks", .window, "Solo Selected Tracks", keys: "S"),
        .init("roll.velocity_drag", .editorRouted, "Adjust Velocity (Hold + Drag Note)",
              holdChord: controlModifier),
        .init("velocity.detent_unlock", .editorRouted, "Unlock Detents (Hold)",
              holdChord: controlModifier),
        .init("automation.pencil_mode", .editorRouted, "Toggle Pencil Mode", keys: "B"),
        .init("eventlist.move_up", .editorRouted, "Move Event Up (Same Tick)", keys: "Alt+Up"),
        .init("eventlist.move_down", .editorRouted, "Move Event Down (Same Tick)", keys: "Alt+Down"),
    ]

    private static let allIDs = definitions.map(\.id)
    private static let byID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })

    // First access must occur under the live QGuiApplication. Neither init()
    // nor catalogue inspection triggers Qt; this cache preserves the native
    // shippedSequences fallback: use a nonempty standard list, otherwise
    // parse semicolon-separated PortableText alternates (keymap.cpp:19-37).
    private static let resolvedSequences: [String: [KeybindingSequence]] = {
        var result: [String: [KeybindingSequence]] = [:]
        result.reserveCapacity(definitions.count)
        for definition in definitions where definition.holdChord == 0 {
            result[definition.id] = resolve(definition)
        }
        return result
    }()

    private static func resolve(_ definition: Definition) -> [KeybindingSequence] {
        let portable = QtKeybindings.QKeySequence.SequenceFormat(rawValue: 1)
        if let standard = definition.standard {
            let bindings = QtKeybindings.QKeySequence.keyBindings(
                QtKeybindings.QKeySequence.StandardKey(rawValue: standard.rawValue)
            )
            if !bindings.isEmpty() || definition.keys.isEmpty {
                var converted: [KeybindingSequence] = []
                converted.reserveCapacity(Int(bindings.size()))
                for index in 0..<Int(bindings.size()) {
                    converted.append(value(bindings[Int64(index)], portable: portable))
                }
                return converted
            }
        }
        var converted: [KeybindingSequence] = []
        for part in definition.keys.split(separator: ";", omittingEmptySubsequences: true) {
            let sequence = QtKeybindings.QKeySequence.fromString(
                QtKeybindings.QString.fromStdString(std.string(String(part))), portable
            )
            if !sequence.isEmpty() { converted.append(value(sequence, portable: portable)) }
        }
        return converted
    }

    private static func value(
        _ sequence: QtKeybindings.QKeySequence,
        portable: QtKeybindings.QKeySequence.SequenceFormat
    ) -> KeybindingSequence {
        let strokes = (0..<Int(sequence.count())).map { index in
            Int(sequence[UInt32(index)].toCombined())
        }
        let native = QtKeybindings.QKeySequence.SequenceFormat(rawValue: 0)
        return KeybindingSequence(
            strokes: strokes,
            portableText: String(sequence.toString(portable).toStdString()),
            nativeText: String(sequence.toString(native).toStdString())
        )
    }
}
