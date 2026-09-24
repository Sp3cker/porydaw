import Foundation
import QtBridge

@MainActor
@QtBridgeable
public final class ShellPresenter: QmlInstantiableStatus {
    private struct Action {
        let id: String
        let label: String
        let command: EditCommand?

        init(_ id: String, _ label: String, _ command: EditCommand? = nil) {
            self.id = id
            self.label = label
            self.command = command
        }
    }

    private static let actions: [Action] = [
        Action("file.open_project", "Open Project…"),
        Action("file.open_song", "Open Song…"),
        Action("file.save_song", "Save"),
        Action("file.quit", "Quit"),
        Action("edit.undo", "Undo"),
        Action("edit.redo", "Redo"),
        Action("roll.copy", "Copy Notes", .copy),
        Action("roll.cut", "Cut Notes", .cut),
        Action("roll.duplicate_time", "Duplicate", .duplicate),
        Action("roll.paste", "Paste Notes", .paste),
        Action("roll.delete", "Delete Notes", .delete),
        Action("roll.select_all", "Select All Notes", .selectAll),
        Action("edit.insert_time", "Insert Time", .insertTime),
        Action("edit.delete_time", "Delete Time", .deleteTime),
        Action("edit.clear_time_selection", "Clear Time Selection", .clearTimeSelection),
        Action("edit.edit_time_signature", "Edit Time Signature at Edit Cursor…", .editTimeSignature),
        Action("edit.remove_time_signature", "Remove Time Signature", .removeTimeSignature),
        Action("roll.transpose_up", "Transpose Up", .transposeUp),
        Action("roll.transpose_down", "Transpose Down", .transposeDown),
        Action("roll.transpose_up_octave", "Transpose Up an Octave", .transposeUpOctave),
        Action("roll.transpose_down_octave", "Transpose Down an Octave", .transposeDownOctave),
        Action("roll.nudge_left", "Nudge Left", .nudgeLeft),
        Action("roll.nudge_right", "Nudge Right", .nudgeRight),
        Action("roll.mute_tracks", "Mute Selected Tracks", .muteTracks),
        Action("roll.solo_tracks", "Solo Selected Tracks", .soloTracks),
        Action("automation.pencil_mode", "Toggle Pencil Mode", .pencilMode),
        Action("eventlist.move_up", "Move Event Up (Same Tick)", .moveEventUp),
        Action("eventlist.move_down", "Move Event Down (Same Tick)", .moveEventDown),
        Action("roll.split", "Split Notes", .split),
        Action("roll.join", "Join Notes", .join),
        Action("roll.lengthen_note", "Lengthen Notes", .lengthenNote),
        Action("roll.shorten_note", "Shorten Notes", .shortenNote),
        Action("roll.grid_narrow", "Narrow Grid", .gridNarrow),
        Action("roll.grid_widen", "Widen Grid", .gridWiden),
        Action("roll.grid_triplet", "Triplet Grid", .gridTriplet),
        Action("transport.play_pause", "Play/Pause"),
        Action("transport.stop", "Stop"),
        Action("view.event_list", "MIDI Event List"),
        Action("view.polyphony_debugger", "Polyphony Debugger"),
    ]
    private static let byId = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
    private static let allActionIds = actions.map(\.id)
    private static let fileIds = allActionIds.filter { $0.hasPrefix("file.") }
    private static let editTopIds = ["edit.undo", "edit.redo"]
    private static let editClipboardIds = [
        "roll.copy", "roll.cut", "roll.paste", "roll.delete", "roll.select_all",
    ]
    private static let timeIds = [
        "edit.insert_time", "edit.delete_time", "roll.duplicate_time",
        "edit.clear_time_selection", "edit.edit_time_signature", "edit.remove_time_signature",
    ]
    private static let tracksIds = ["roll.mute_tracks", "roll.solo_tracks"]
    private static let editNotesIds = [
        "roll.transpose_up", "roll.transpose_down",
        "roll.transpose_up_octave", "roll.transpose_down_octave",
        "roll.nudge_left", "roll.nudge_right",
    ]
    private static let editTailIds = [
        "automation.pencil_mode", "roll.split", "roll.join",
        "roll.lengthen_note", "roll.shorten_note", "roll.grid_narrow",
        "roll.grid_widen", "roll.grid_triplet",
    ]
    private static let transportIds = allActionIds.filter { $0.hasPrefix("transport.") }
    private static let viewIds = allActionIds.filter { $0.hasPrefix("view.") }
    private static let contextIds = [
        "roll.copy", "roll.cut", "roll.duplicate_time", "roll.paste",
        "roll.delete", "roll.split", "roll.join",
    ]

    /// Scope inspection is pure Swift; Qt resolves sequence strings only after
    /// QGuiApplication starts. Open Song is not in the keymap and stays unbound.
    private static let windowIds: [String] = {
        let registry = KeybindingRegistry()
        let ids = Set(registry.ids)
        return actions.compactMap { action in
            ids.contains(action.id) && registry.scope(action.id) == .window
                ? action.id : nil
        }
    }()

    private let keybindings = KeybindingRegistry()

    @QtTracked public var session: ApplicationSession
    @QtTracked public var actionIds: [String]
    @QtTracked public var fileActionIds: [String]
    @QtTracked public var editTopActionIds: [String]
    @QtTracked public var editClipboardActionIds: [String]
    @QtTracked public var editNotesActionIds: [String]
    @QtTracked public var editTailActionIds: [String]
    @QtTracked public var timeActionIds: [String]
    @QtTracked public var tracksActionIds: [String]
    @QtTracked public var transportActionIds: [String]
    @QtTracked public var viewActionIds: [String]
    @QtTracked public var windowActionIds: [String]
    @QtTracked public var contextActionIds: [String]

    @QtTracked public var closeReady = false
    @QtTracked public var sceneActive = true
    @QtTracked public var themeMode = "vanilla"
    @QtTracked public var gridLineContrast = 50
    @QtTracked public var songLabels: [String] = []
    @QtTracked public var polyphonyVisible = false
    @QtTracked public var statusText = "Ready"
    private var closePending = false
    private var closing = false

    public init() {
        session = ApplicationSession()
        actionIds = Self.allActionIds
        fileActionIds = Self.fileIds
        editTopActionIds = Self.editTopIds
        editClipboardActionIds = Self.editClipboardIds
        editNotesActionIds = Self.editNotesIds
        editTailActionIds = Self.editTailIds
        timeActionIds = Self.timeIds
        tracksActionIds = Self.tracksIds
        transportActionIds = Self.transportIds
        viewActionIds = Self.viewIds
        windowActionIds = Self.windowIds
        contextActionIds = Self.contextIds
    }

    public func componentComplete() {}

    public func actionLabel(id: String) -> String {
        Self.byId[id]?.label ?? ""
    }

    /// Portable Qt sequence text, including every platform StandardKey
    /// alternative, is resolved by Qt only after QGuiApplication exists.
    public func actionSequences(id: String) -> [String] {
        guard Self.byId[id] != nil, keybindings.ids.contains(id) else { return [] }
        return keybindings.sequences(id).map(\.portableText)
    }

    /// The native menu advertises only QAction::shortcut()'s primary sequence.
    public func actionShortcut(id: String) -> String {
        keybindings.sequences(id).first?.nativeText ?? ""
    }

    public func actionEnabled(id: String) -> Bool {
        guard let action = Self.byId[id] else { return false }
        if id == "view.polyphony_debugger" { return true }
        guard sceneActive else { return false }
        if let command = action.command {
            return session.songOpen && session.gridCommandAvailable(command: command.rawValue)
        }
        switch id {
        case "file.open_song": return session.projectOpen
        case "file.save_song": return session.songOpen && !session.saveInProgress
        case "edit.undo": return session.songOpen && session.canUndo
        case "edit.redo": return session.songOpen && session.canRedo
        case "transport.play_pause", "transport.stop": return session.songOpen
        case "view.event_list": return session.songTabs.selectedPage != nil
        default: return true // open project and quit were always enabled
        }
    }

    /// An action activation has the same enabled gate as QAction::triggered.
    public func activate(id: String) {
        guard actionEnabled(id: id) else { return }
        if let command = Self.byId[id]?.command {
            session.performGridCommand(command: command.rawValue)
            return
        }
        switch id {
        case "file.open_project": chooseProjectRequested()
        case "file.open_song":
            songLabels = (0..<session.songCount()).compactMap { index in
                let label = session.songLabel(index: index)
                return label.isEmpty ? nil : label
            }
            if songLabels.isEmpty {
                informationRequested(title: "Open Song",
                                     message: "The project has no playable songs.")
            } else {
                chooseSongRequested()
            }
        case "file.save_song": session.requestSave()
        case "file.quit": quitRequested()
        case "edit.undo": session.requestUndo()
        case "edit.redo": session.requestRedo()
        case "transport.play_pause": session.playPause()
        case "transport.stop": session.stop()
        case "view.event_list":
            session.songTabs.setSelectedTabEventsVisible(visible:
                !session.songTabs.selectedTabShowsEvents)
        case "view.polyphony_debugger":
            polyphonyVisible.toggle()
            session.polyphony.setVisible(showing: polyphonyVisible)
        default: break
        }
    }

    public func routeEditorKey(key: Int, modifiers: Int, autoRepeat: Bool) -> Bool {
        routeEditorKey(key: key, modifiers: modifiers, autoRepeat: autoRepeat, eventList: false)
    }

    public func routeEventListKey(key: Int, modifiers: Int, autoRepeat: Bool) -> Bool {
        routeEditorKey(key: key, modifiers: modifiers, autoRepeat: autoRepeat, eventList: true)
    }

    private func routeEditorKey(key: Int, modifiers: Int, autoRepeat: Bool,
                                eventList: Bool) -> Bool {
        guard sceneActive, session.songOpen else { return false }
        if !eventList && key == 0x0100_0000 && !autoRepeat && session.handleGridEscape() {
            return true
        }
        for action in Self.actions {
            guard let command = action.command,
                  keybindings.scope(action.id) == .editorRouted,
                  keybindings.matches(key, modifiers, action.id) else { continue }
            let decision = eventList
                ? session.routeEventListCommand(command: command.rawValue, autoRepeat: autoRepeat)
                : session.routeGridKey(command: command.rawValue, autoRepeat: autoRepeat)
            if decision == EditKeyDecision.decline.rawValue { return false }
            if decision == EditKeyDecision.execute.rawValue {
                if eventList {
                    session.performEventListCommand(command: command.rawValue)
                } else {
                    session.performGridCommand(command: command.rawValue)
                }
            }
            return true
        }
        return false
    }

    /// The native window rejects the first close while tabs answer their dirty
    /// gate; no tab closes bypass hostClosing -> scene removal -> detach ack.
    public func beginClose() -> Bool {
        if closeReady { return true }
        if closing || closePending { return false }
        if session.songTabs.tabCount > 0 {
            closePending = true
            session.requestCloseAll()
            return false
        }
        finishClose()
        return false
    }

    public func allTabsClosed() {
        guard closePending else { return }
        closePending = false
        finishClose()
    }

    public func closeCancelled() {
        closePending = false
    }

    private func finishClose() {
        guard !closing else { return }
        closing = true
        // This must precede sceneActive=false: workspace input cancellation
        // still reaches the live QML scene (ApplicationSession.hostClosing).
        session.hostClosing()
        sceneActive = false
    }

    /// Called after Loader invalidates the scene's QML contexts and detaches
    /// its item. Qt emits Component.onDestruction before that invalidation
    /// completes; physical QObject deletion may follow later.
    public func sceneDestroyed() {
        guard closing, !closeReady else { return }
        session.acknowledgeGridDetached()
        closeReady = true
    }

    public func openStartup() {
        let arguments = CommandLine.arguments
        var project = ""
        var song = ""
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--project" || argument == "--song" {
                if index + 1 < arguments.count {
                    index += 1
                    if argument == "--project" { project = arguments[index] }
                    else { song = arguments[index] }
                }
            } else if argument.hasPrefix("--project=") {
                project = String(argument.dropFirst("--project=".count))
            } else if argument.hasPrefix("--song=") {
                song = String(argument.dropFirst("--song=".count))
            }
            index += 1
        }
        guard !project.isEmpty else { return }
        if song.isEmpty { session.openProject(path: project) }
        else { session.openProjectAndSong(path: project, label: song) }
    }

    /// FolderDialog supplies a file URL; Foundation decodes it into the local
    /// path that QFileDialog supplied to the native session.
    public func chooseProject(fileURL: String) {
        guard let url = URL(string: fileURL), url.isFileURL, !url.path.isEmpty else { return }
        session.openProject(path: url.path)
    }

    /// Completion of the QML selection dialog, whose labels come from the
    /// session's actual project song catalogue.
    public func chooseSong(label: String) {
        guard !label.isEmpty else { return }
        session.openSong(label: label)
    }

    public func songOpenChanged() {
        if session.songOpen { statusText = "Song open" }
    }

    public func saveStateChanged() {
        guard !session.saveInProgress, !session.lastSaveError.isEmpty else { return }
        criticalRequested(title: "Save Failed", message: session.lastSaveError)
    }

    public func openFailed(message: String) {
        guard !message.isEmpty else { return }
        statusText = message
        criticalRequested(title: "Open Failed", message: message)
    }

    public func operationFailed(message: String) {
        guard !message.isEmpty else { return }
        statusText = message
        criticalRequested(title: "Operation Failed", message: message)
    }

    /// QML's QtCore.Settings reads the original ThemeController settings keys;
    /// Swift owns validation, palette policy and the canonical values to write.
    public func restoreAppearance(mode: String, gridLineContrast: String, applicationName: String) {
        ShellAppearance.removeLegacyCustomKeys(applicationName: applicationName)
        themeMode = ShellAppearance.mode(mode)
        self.gridLineContrast = ShellAppearance.contrast(gridLineContrast)
        ShellAppearance.apply(to: session.palette, mode: themeMode, contrast: self.gridLineContrast)
        if session.songOpen { session.gridPresenter().reloadVisuals() }
    }

    @QtSignal public func chooseProjectRequested()
    @QtSignal public func chooseSongRequested()
    @QtSignal public func quitRequested()
    @QtSignal public func informationRequested(title: String, message: String)
    @QtSignal public func criticalRequested(title: String, message: String)
}
