import Foundation
import QtBridge
import PorydawAppCommands

@MainActor
@QtBridgeable
public final class ShellPresenter: QmlInstantiableStatus {
    private struct Action {
        let id: String
        let command: EditCommand?

        init(_ id: String, _ command: EditCommand? = nil) {
            self.id = id
            self.command = command
        }
    }

    private static let actions: [Action] = [
        Action("file.open_project"),
        Action("songs.find"),
        Action("file.save_song"),
        Action("file.close_tab"),
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
        Action("view.velocity_colors"),
        Action("view.note_names"),
        Action("help.about"),
    ]
    private static let byId = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
    private static let allActionIds = actions.map(\.id)
    private static let fileIds = allActionIds.filter { $0.hasPrefix("file.") }
    private static let editTopIds = ["edit.undo", "edit.redo"]
    private static let editClipboardIds = [
        "roll.copy", "roll.cut", "roll.paste", "roll.delete", "roll.select_all", "songs.find",
    ]
    private static let timeIds = [
        "edit.insert_time", "edit.delete_time", "roll.duplicate_time",
        "edit.clear_time_selection", "edit.edit_time_signature", "edit.remove_time_signature",
    ]
    private static let notesIds = [
        "roll.transpose_up", "roll.transpose_down",
        "roll.transpose_up_octave", "roll.transpose_down_octave",
        "roll.pitch_bend", "edit.set_velocity", "roll.duplicate_time", "roll.split", "roll.join",
    ]
    private static let moveIds = ["roll.nudge_left", "roll.nudge_right"]
    private static let tracksIds = ["roll.mute_tracks", "roll.solo_tracks"]
    private static let automationIds = ["automation.pencil_mode"]
    private static let eventsIds = ["eventlist.move_up", "eventlist.move_down"]
    private static let loopIds = [
        "edit.set_loop_start", "edit.set_loop_end", "edit.loop_from_selection", "edit.remove_loop",
    ]
    private static let editTailIds = [
        "edit.preferences", "edit.song_settings", "edit.engine_settings",
    ]
    private static let transportIds = [
        "transport.go_to_start", "transport.play", "transport.play_pause",
        "transport.pause", "transport.stop", "transport.loop",
    ]
    private static let viewIds = allActionIds.filter { $0.hasPrefix("view.") }
        + ["transport.follow_playhead"]
    private static let contextHeadIds = ["edit.set_velocity"]
    private static let contextBodyIds = [
        "roll.copy", "roll.cut", "roll.duplicate_time", "roll.split", "roll.join", "roll.delete",
    ]
    private static let menuLabels = [
        "file.open_project": "Open Project...",
        "edit.preferences": "Preferences...",
        "edit.song_settings": "Song Settings...",
        "edit.engine_settings": "Engine Settings...",
        "view.voice_changes_drawer": "Voice-change Drawer",
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
    public var notesActionIds: [String]
    public var moveActionIds: [String]
    public var automationActionIds: [String]
    public var eventsActionIds: [String]
    public var loopActionIds: [String]
    public var editTailActionIds: [String]
    public var timeActionIds: [String]
    public var tracksActionIds: [String]
    public var transportActionIds: [String]
    public var viewActionIds: [String]
    public var windowActionIds: [String]
    public var contextHeadActionIds: [String]
    public var contextBodyActionIds: [String]

    @QtTracked public var closeReady = false
    @QtTracked public var sceneActive = true
    @QtTracked public var themeMode = "vanilla"
    @QtTracked public var gridLineContrast = 50
    @QtTracked public var dockColumnWidth = 280
    @QtTracked public var dockSongsRatio = 0.5
    @QtTracked public var polyphonyVisible = false
    @QtTracked public var windowX = -1
    @QtTracked public var windowY = -1
    @QtTracked public var windowWidth = -1
    @QtTracked public var windowHeight = -1
    @QtTracked public var windowMaximized = false
    @QtTracked public var statusText = "Ready"
    @QtTracked public var windowTitle = "porydaw"
    @QtTracked public var windowModified = false
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
        notesActionIds = Self.notesIds
        moveActionIds = Self.moveIds
        automationActionIds = Self.automationIds
        eventsActionIds = Self.eventsIds
        loopActionIds = Self.loopIds
        editTailActionIds = Self.editTailIds
        timeActionIds = Self.timeIds
        tracksActionIds = Self.tracksIds
        transportActionIds = Self.transportIds
        viewActionIds = Self.viewIds
        windowActionIds = Self.windowIds
        contextHeadActionIds = Self.contextHeadIds
        contextBodyActionIds = Self.contextBodyIds
    }

    public func componentComplete() {}

    public func actionLabel(id: String) -> String {
        guard Self.byId[id] != nil else { return "" }
        return id == "help.about" ? "About porydaw" : keybindings.label(id)
    }

    public func menuLabel(id: String) -> String {
        Self.menuLabels[id] ?? actionLabel(id: id)
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
        case "transport.follow_playhead", "transport.resonance":
            return true
        case "transport.go_to_start", "transport.play_pause":
            return session.songOpen && session.transportBarPresenter().state != 0
        case "transport.play":
            let state = session.transportBarPresenter().state
            return session.songOpen && state > 0 && state != 3
        case "transport.pause":
            return session.songOpen && session.transportBarPresenter().state == 3
        case "transport.stop":
            return session.songOpen && session.transportBarPresenter().state > 1
        case "transport.loop":
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


    public func refreshWindowChrome() {
        let project = session.projectOpen
            ? URL(fileURLWithPath: session.projectRoot, isDirectory: true).lastPathComponent : ""
        if let selected = session.songTabs.selectedPage {
            windowTitle = "\(selected.title) — \(project) — porydaw"
            windowModified = selected.workspace.session.document.isDirty
        } else {
            windowTitle = project.isEmpty ? "porydaw" : "\(project) — porydaw"
            windowModified = false
        }
    }

    public func songOpenChanged() {
        if session.songOpen { statusText = "Song open" }
        refreshWindowChrome()
    }

    public func saveStateChanged() {
        refreshWindowChrome()
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

    public func configureSettings(applicationName: String) {
        PreferencesStore.configureShared(applicationName: applicationName)
        session.configurePersistence()
        let store = PreferencesStore()
        dockColumnWidth = store.int(key: "swiftDock.columnWidth", fallback: 280)
        dockSongsRatio = store.double(key: "swiftDock.songsRatio", fallback: 0.5)
        let frame = store.string(key: "windowGeometry", fallback: "").split(
            separator: ",", omittingEmptySubsequences: false).compactMap { Int($0) }
        if frame.count == 4, frame[2] > 0, frame[3] > 0 {
            windowX = frame[0]
            windowY = frame[1]
            windowWidth = frame[2]
            windowHeight = frame[3]
        }
        let state = store.string(key: "windowState", fallback: "").split(separator: ",")
        windowMaximized = state.contains("maximized")
        polyphonyVisible = state.contains("debugger")
        session.polyphony.setVisible(showing: polyphonyVisible)
        session.songDockController().presenter.restoreFromPreferences()
    }

    public func persistSessionState(x: Int, y: Int, width: Int, height: Int,
                                    maximized: Bool, debuggerVisible: Bool) {
        let store = PreferencesStore()
        store.setString(key: "windowGeometry", value: "\(x),\(y),\(width),\(height)")
        var state: [String] = []
        if maximized { state.append("maximized") }
        if debuggerVisible { state.append("debugger") }
        store.setString(key: "windowState", value: state.joined(separator: ","))
        let songs = session.songDockController().presenter
        store.setString(key: "songFilterText", value: songs.searchText)
        store.setInt(key: "songFilterSort", value: songs.sortIndex)
        store.setString(key: "songFilterCategory", value: songs.categoryPrefix())
        store.synchronize()
    }

    public func setDockColumnWidth(width: Int) {
        guard dockColumnWidth != width else { return }
        dockColumnWidth = width
        let store = PreferencesStore()
        store.setInt(key: "swiftDock.columnWidth", value: width)
        store.synchronize()
    }

    public func setDockSongsRatio(ratio: Double) {
        guard dockSongsRatio != ratio else { return }
        dockSongsRatio = ratio
        let store = PreferencesStore()
        store.setDouble(key: "swiftDock.songsRatio", value: ratio)
        store.synchronize()
    }

    public func restoreAppearance() {
        let store = PreferencesStore()
        ShellAppearance.removeLegacyCustomKeys(store: store)
        themeMode = ShellAppearance.mode(store.string(key: "theme.mode", fallback: ""))
        gridLineContrast = ShellAppearance.contrast(
            store.string(key: "theme.grid-line-contrast", fallback: ""))
        ShellAppearance.apply(to: session.palette, mode: themeMode, contrast: gridLineContrast)
        session.eventListPresenter().refreshAppearance()
        if session.songOpen { session.gridPresenter().reloadVisuals() }
        store.setString(key: "theme.mode", value: themeMode)
        store.setInt(key: "theme.grid-line-contrast", value: gridLineContrast)
        store.synchronize()
    }

    @QtSignal public func chooseProjectRequested()
    @QtSignal public func settingsRequested(songFirst: Bool)
    @QtSignal public func aboutRequested()
    @QtSignal public func quitRequested()
    @QtSignal public func eventListGateChanged()
    @QtSignal public func criticalRequested(title: String, message: String)
}
