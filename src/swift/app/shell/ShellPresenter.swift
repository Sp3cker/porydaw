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
        Action("songs.find", "Find Song"),
        Action("file.save_song", "Save"),
        Action("file.close_tab", "Close Tab"),
        Action("file.quit", "Quit"),
        Action("edit.undo", "Undo"),
        Action("edit.redo", "Redo"),
        Action("edit.preferences", "Preferences…"),
        Action("edit.song_settings", "Song Settings…"),
        Action("edit.engine_settings", "Engine Settings…"),
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
        Action("edit.loop_from_selection", "Loop from Time Selection", .loopFromSelection),
        Action("roll.transpose_up", "Transpose Up", .transposeUp),
        Action("roll.transpose_down", "Transpose Down", .transposeDown),
        Action("roll.transpose_up_octave", "Transpose Up an Octave", .transposeUpOctave),
        Action("roll.transpose_down_octave", "Transpose Down an Octave", .transposeDownOctave),
        Action("roll.pitch_bend", "Edit Note Pitch Bend", .pitchBend),
        Action("edit.set_velocity", "Set Velocity…", .setVelocity),
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
        Action("transport.go_to_start", "Go to Start"),
        Action("transport.play", "Play"),
        Action("transport.play_pause", "Play/Pause"),
        Action("transport.pause", "Pause"),
        Action("transport.stop", "Stop"),
        Action("transport.loop", "Toggle Loop"),
        Action("transport.follow_playhead", "Follow Playhead"),
        Action("transport.resonance", "Suppress Resonances"),
        Action("view.event_list", "MIDI Event List"),
        Action("view.automation_drawer", "Automation Drawer"),
        Action("view.velocity_drawer", "Velocity Drawer"),
        Action("view.voice_changes_drawer", "Voice Changes Drawer"),
        Action("view.polyphony_debugger", "Polyphony Debugger"),
        Action("view.velocity_colors", "Color Notes by Velocity"),
        Action("view.note_names", "Show Note Names"),
        Action("help.about", "About porydaw"),
    ]
    private static let byId = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
    private static let allActionIds = actions.map(\.id)
    private static let fileIds = allActionIds.filter { $0.hasPrefix("file.") || $0 == "songs.find" }
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
        "roll.grid_widen", "roll.grid_triplet", "roll.pitch_bend",
        "edit.set_velocity", "edit.loop_from_selection", "eventlist.move_up",
        "eventlist.move_down", "edit.preferences", "edit.song_settings",
        "edit.engine_settings",
    ]
    private static let transportIds = allActionIds.filter {
        $0.hasPrefix("transport.") && $0 != "transport.resonance"
    }
    private static let viewIds = allActionIds.filter { $0.hasPrefix("view.") }
    private static let contextIds = [
        "roll.copy", "roll.cut", "roll.duplicate_time", "roll.paste",
        "roll.delete", "roll.split", "roll.join",
    ]

    /// Scope inspection is pure Swift; Qt resolves sequence strings only after
    /// QGuiApplication starts.
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
    @QtTracked public var settingsStore: EngineSettingsStore
    public var actionIds: [String]
    public var fileActionIds: [String]
    public var editTopActionIds: [String]
    public var editClipboardActionIds: [String]
    public var editNotesActionIds: [String]
    public var editTailActionIds: [String]
    public var timeActionIds: [String]
    public var tracksActionIds: [String]
    public var transportActionIds: [String]
    public var viewActionIds: [String]
    public var windowActionIds: [String]
    public var contextActionIds: [String]

    @QtTracked public var closeReady = false
    @QtTracked public var sceneActive = true
    @QtTracked public var themeMode = "vanilla"
    @QtTracked public var gridLineContrast = 50
    @QtTracked public var polyphonyVisible = false
    @QtTracked public var statusText = "Ready"
    private var closePending = false
    private var closing = false

    public init() {
        session = ApplicationSession()
        settingsStore = EngineSettingsStore()
        settingsStore.attach(session: session)
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
    private var lastEventListGate:
        (attached: Bool, visible: Bool, editing: Bool, menuOpen: Bool,
         tableRevision: Int)?

    public func actionShortcut(id: String) -> String {
        keybindings.sequences(id).first?.nativeText ?? ""
    }

    public func actionEnabled(id: String) -> Bool {
        guard let action = Self.byId[id] else { return false }
        if id == "view.polyphony_debugger" || id == "edit.preferences"
            || id == "edit.engine_settings" { return true }
        guard sceneActive else { return false }
        if id == "eventlist.move_up" || id == "eventlist.move_down" {
            guard session.songOpen else { lastEventListGate = nil; return false }
            let events = session.eventListPresenter()
            let gate = (attached: events.attached, visible: events.visible,
                        editing: events.editing, menuOpen: events.menuOpen,
                        tableRevision: events.tableRevision)
            if lastEventListGate.map({ $0 == gate }) != true {
                lastEventListGate = gate
                eventListGateChanged()
            }
            guard gate.attached, gate.visible, !gate.editing, !gate.menuOpen else { return false }
            return events.model.row(at: events.currentRow)?.eventIndex != nil
        }
        if let command = action.command {
            return session.songOpen && session.gridCommandAvailable(command: command.rawValue)
        }
        switch id {
        case "songs.find": return session.projectOpen
        case "file.save_song": return session.songOpen && !session.saveInProgress
        case "file.close_tab": return session.songTabs.selectedPage != nil
        case "edit.undo": return session.songOpen && session.canUndo
        case "edit.redo": return session.songOpen && session.canRedo
        case "edit.song_settings": return session.songOpen
        case "transport.follow_playhead":
            return session.songOpen
        case "transport.go_to_start", "transport.play_pause":
            return session.songOpen && session.transportBarPresenter().state != 0
        case "transport.play":
            let state = session.transportBarPresenter().state
            return session.songOpen && state > 0 && state != 3
        case "transport.pause":
            return session.songOpen && session.transportBarPresenter().state == 3
        case "transport.stop":
            return session.songOpen && session.transportBarPresenter().state > 1
        case "transport.loop", "transport.resonance":
            return session.songOpen && session.transportBarPresenter().state != 0
        case "view.event_list", "view.automation_drawer", "view.velocity_drawer",
            "view.voice_changes_drawer":
            return session.songTabs.selectedPage != nil
        default: return true // open project and quit were always enabled
        }
    }

    public func actionCheckable(id: String) -> Bool {
        switch id {
        case "view.event_list", "view.automation_drawer", "view.velocity_drawer",
            "view.voice_changes_drawer", "view.polyphony_debugger",
            "view.velocity_colors", "view.note_names", "transport.loop",
            "transport.follow_playhead", "transport.resonance":
            return true
        default: return false
        }
    }

    public func actionChecked(id: String) -> Bool {
        switch id {
        case "view.event_list": return session.songTabs.selectedTabShowsEvents
        case "view.automation_drawer":
            return session.songTabs.selectedPage?.drawerPresenter().automationSection.visible ?? false
        case "view.velocity_drawer":
            return session.songTabs.selectedPage?.drawerPresenter().velocitySection.visible ?? false
        case "view.voice_changes_drawer":
            return session.songTabs.selectedPage?.drawerPresenter().voiceChangesSection.visible ?? false
        case "view.polyphony_debugger": return polyphonyVisible
        case "view.velocity_colors": return session.velocityColorMode
        case "view.note_names": return session.noteNameMode
        case "transport.loop": return session.transportBarPresenter().loopEnabled
        case "transport.follow_playhead": return session.transportBarPresenter().followPlayhead
        case "transport.resonance": return session.transportBarPresenter().resonanceSuppression
        default: return false
        }
    }

    /// An action activation has the same enabled gate as QAction::triggered.
    public func activate(id: String) {
        guard actionEnabled(id: id) else { return }
        if let command = Self.byId[id]?.command {
            if command == .moveEventUp || command == .moveEventDown {
                session.performEventListCommand(command: command.rawValue)
            } else {
                session.performGridCommand(command: command.rawValue)
            }
            return
        }
        switch id {
        case "file.open_project": chooseProjectRequested()
        case "songs.find": session.songDockController().presenter.focusSearch()
        case "file.save_song": session.requestSave()
        case "file.close_tab":
            session.songTabs.requestClose(tabId: session.songTabs.selectedId)
        case "file.quit": quitRequested()
        case "edit.undo": session.requestUndo()
        case "edit.redo": session.requestRedo()
        case "edit.preferences": settingsRequested(songFirst: session.songOpen)
        case "edit.song_settings": settingsRequested(songFirst: true)
        case "edit.engine_settings": settingsRequested(songFirst: false)
        case "transport.go_to_start": session.transportBarPresenter().goToStart()
        case "transport.play": session.transportBarPresenter().play()
        case "transport.play_pause": session.playPause()
        case "transport.pause": session.transportBarPresenter().pause()
        case "transport.stop": session.stop()
        case "transport.loop":
            let loopTransport = session.transportBarPresenter()
            loopTransport.setLoopEnabled(enabled: !loopTransport.loopEnabled)
        case "transport.follow_playhead":
            let followTransport = session.transportBarPresenter()
            followTransport.setFollowPlayhead(enabled: !followTransport.followPlayhead)
        case "transport.resonance":
            let transport = session.transportBarPresenter()
            transport.setResonanceSuppression(enabled: !transport.resonanceSuppression)
        case "view.event_list":
            session.songTabs.setSelectedTabEventsVisible(visible:
                !session.songTabs.selectedTabShowsEvents)
        case "view.automation_drawer":
            session.songTabs.selectedPage?.drawerPresenter()
                .toggleSection(kind: DrawerSectionKind.automation.rawValue, drawerOwnsFocus: false)
        case "view.velocity_drawer":
            session.songTabs.selectedPage?.drawerPresenter()
                .toggleSection(kind: DrawerSectionKind.velocity.rawValue, drawerOwnsFocus: false)
        case "view.voice_changes_drawer":
            session.songTabs.selectedPage?.drawerPresenter()
                .toggleSection(kind: DrawerSectionKind.voiceChanges.rawValue, drawerOwnsFocus: false)
        case "view.velocity_colors":
            session.setVelocityColorMode(enabled: !session.velocityColorMode)
        case "view.note_names":
            session.setNoteNameMode(enabled: !session.noteNameMode)
        case "view.polyphony_debugger":
            polyphonyVisible.toggle()
            session.polyphony.setVisible(showing: polyphonyVisible)
        case "help.about": aboutRequested()
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

    /// The native window rejects the first close while tabs and dirty banks
    /// answer their gate; no close bypasses hostClosing -> scene removal ->
    /// detach ack.
    public func beginClose() -> Bool {
        if closeReady { return true }
        if closing || closePending { return false }
        closePending = true
        session.requestCloseAll()
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

    public func openStartup(applicationName: String) {
        session.configurePersistence(applicationName: applicationName)
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
        if !project.isEmpty {
            if song.isEmpty { session.openProject(path: project) }
            else { session.openProjectAndSong(path: project, label: song) }
        } else {
            session.restoreStartup()
        }
    }

    /// FolderDialog supplies a file URL; Foundation decodes it into the local
    /// path that QFileDialog supplied to the native session.
    public func chooseProject(fileURL: String) {
        guard let url = URL(string: fileURL), url.isFileURL, !url.path.isEmpty else { return }
        session.openProject(path: url.path)
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
    @QtSignal public func settingsRequested(songFirst: Bool)
    @QtSignal public func aboutRequested()
    @QtSignal public func quitRequested()
    @QtSignal public func eventListGateChanged()
    @QtSignal public func criticalRequested(title: String, message: String)
}
