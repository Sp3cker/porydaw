import Foundation
import PorydawAppCommands
import PorydawDocument
import PorydawNativeHost
import QtBridge

@MainActor
@QtBridgeable
public final class ShellPresenter: QmlInstantiableStatus {
    private let keybindings = KeybindingRegistry()
    private var actionStates: [String: ShellActionState] = [:]
    private let clipboard = GridClipboard()
    private var clipboardObserver: UUID?
    public let regularFontSource: String = BundledFont.regular.source
    public let semiboldFontSource: String = BundledFont.semibold.source
    public let monoFontSource: String = BundledFont.mono.source
    public let iconsFontSource: String = BundledFont.icons.source
    public let startupTraceEnabled: Bool = pd_startup_trace_enabled()

    @QtTracked public var session: ApplicationSession
    @QtTracked public var settingsStore: EngineSettingsStore
    @QtTracked public var mouseHints: MouseHints
    public var actionIds: [String] = ShellActionCatalog.allActionIds
    public var fileActionIds: [String] = ShellActionCatalog.fileIds
    public var fileExportActionIds: [String] = ShellActionCatalog.fileExportIds
    public var fileQuitActionIds: [String] = ShellActionCatalog.fileQuitIds
    public var editTopActionIds: [String] = ShellActionCatalog.editTopIds
    public var editClipboardActionIds: [String] = ShellActionCatalog.editClipboardIds
    public var notesActionIds: [String] = ShellActionCatalog.notesIds
    public var moveActionIds: [String] = ShellActionCatalog.moveIds
    public var automationActionIds: [String] = ShellActionCatalog.automationIds
    public var eventsActionIds: [String] = ShellActionCatalog.eventsIds
    public var loopActionIds: [String] = ShellActionCatalog.loopIds
    public var editTailActionIds: [String] = ShellActionCatalog.editTailIds
    public var timeActionIds: [String] = ShellActionCatalog.timeIds
    public var tracksActionIds: [String] = ShellActionCatalog.tracksIds
    public var transportActionIds: [String] = ShellActionCatalog.transportIds
    public var viewActionIds: [String] = ShellActionCatalog.viewIds
    public var toolsActionIds: [String] = ShellActionCatalog.toolsIds
    public var windowActionIds: [String] = ShellActionCatalog.windowIds
    public var contextHeadActionIds: [String] = ShellActionCatalog.contextHeadIds
    public var contextBodyActionIds: [String] = ShellActionCatalog.contextBodyIds

    @QtTracked public var closeReady = false
    @QtTracked public var sceneActive = true
    @QtTracked public var contentRequested = false
    private var startupBegun = false
    private var hasRestoredChrome = false
    private var hasLoadedContent = false
    private var hasLoadedWorkspace = false
    private var hasObservedStartupEditor = false
    @QtIgnored var closeSettlementTask: Task<Void, Never>?
    @QtTracked public var themeMode = "vanilla"
    @QtTracked public var gridLineContrast = 50
    public var dockColumnMinWidth: Int = 15 * 13
    public var dockColumnMaxWidth: Int = 37 * 13
    @QtTracked public var dockColumnWidth = Int((21.5 * 13).rounded())
    @QtTracked public var dockSongsRatio = 0.5
    @QtTracked public var polyphonyVisible = false
    @QtTracked public var windowX = -1
    @QtTracked public var windowY = -1
    @QtTracked public var windowWidth = -1
    @QtTracked public var windowHeight = -1
    @QtTracked public var windowMaximized = false
    @QtTracked public var statusText = "Ready"
    @QtTracked public var windowTitle = "porydaw"
    private var closePending = false
    private var closing = false

    public init() {
        pd_startup_trace_mark("presenter-begin")
        pd_startup_trace_window()
        pd_window_cloak_until_first_frame()
        session = ApplicationSession()
        mouseHints = session.mouseHintsPresenter()
        let settingsStore = EngineSettingsStore()
        self.settingsStore = settingsStore
        settingsStore.attach(session: session)
        session.onVoicegroupCatalogChanged = { [weak settingsStore] in
            settingsStore?.refreshVoicegroups()
        }
        session.onStatusMessage = { [weak self] message in self?.statusText = message }
        session.onFailure = { [weak self] title, message in
            self?.presentFailure(title: title, message: message)
        }
        session.onSaveStateChanged = { [weak self] in self?.saveStateChanged() }
        session.onProjectStateChanged = { [weak self] in self?.projectStateChanged() }
        session.onDocumentStateChanged = { [weak self] songOpenChanged in
            self?.documentStateChanged(songOpenChanged: songOpenChanged)
        }
        session.onCommandAvailabilityChanged = { [weak self] in self?.refreshActionStates() }
        session.eventListPresenter().onAvailabilityChanged = { [weak self] in self?.refreshActionStates() }
        session.sampleStudio().onEditorOpenChanged = { [weak self] in self?.refreshActionStates() }
        session.songDockController().onSongsChanged = { [weak self] in self?.refreshActionStates() }
        let transport = session.transportBarPresenter()
        transport.onAvailabilityChanged = { [weak self] in
            self?.refreshActionStates()
        }
        clipboardObserver = clipboard.addChangeObserver { [weak self] in
            self?.refreshActionStates()
        }
        pd_startup_trace_mark("presenter-end")
    }

    isolated deinit {
        if let clipboardObserver { clipboard.removeChangeObserver(clipboardObserver) }
    }

    public func componentComplete() {
        refreshActionStates()
    }

    /// Returns the same retained state for every lookup of a known action.
    public func action(id: String) -> Optional<ShellActionState> {
        if let state = actionStates[id] { return state }
        guard ShellActionCatalog.byId[id] != nil else { return nil }
        let label = id == "help.about" ? "About porydaw" : keybindings.label(id)
        let state = ShellActionState(
            enabled: isActionEnabled(id: id, workspaceLoaded: hasLoadedWorkspace),
            checked: isActionChecked(id: id), checkable: isActionCheckable(id: id), label: label,
            menuLabel: ShellActionCatalog.menuLabels[id] ?? label,
            shortcut: keybindings.sequences(id).first?.nativeText ?? "")
        actionStates[id] = state
        return state
    }

    /// Existing availability triggers publish only changed action properties.
    public func refreshActionStates() {
        for (id, state) in actionStates {
            state.update(
                enabled: isActionEnabled(id: id, workspaceLoaded: hasLoadedWorkspace),
                checked: isActionChecked(id: id))
        }
    }

    /// Portable Qt sequence text, including every platform StandardKey
    /// alternative, is resolved by Qt only after QGuiApplication exists.
    public func actionSequences(id: String) -> [String] {
        guard ShellActionCatalog.byId[id] != nil, keybindings.ids.contains(id) else { return [] }
        return keybindings.sequences(id).map(\.portableText)
    }

    /// An action activation has the same enabled gate as QAction::triggered.
    public func activate(id: String) {
        guard isActionEnabled(id: id, workspaceLoaded: hasLoadedWorkspace) else { return }
        defer { refreshActionStates() }
        if let command = ShellActionCatalog.byId[id]?.command {
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
        case "file.new_song": session.songDockController().newSongController().requestNewSong()
        case "file.import_midi": session.songDockController().midiImportController().requestImport()
        case "tools.import_sample": session.sampleStudio().requestImport(slot: -1)
        case "file.save_song": session.requestSave()
        case "file.register_song": session.songDockController().requestRegisterSelectedTab()
        case "file.close_tab":
            session.songTabs.requestClose(tabId: session.songTabs.selectedId)
        case "file.export_wav": session.wavExportPresenter().open()
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
            session.songTabs.setSelectedTabEventsVisible(
                visible:
                    !session.songTabs.selectedTabShowsEvents)
        case "view.automation_drawer":
            session.songTabs.selectedPage?.drawerPresenter()
                .toggleSection(kind: DrawerSectionKind.automation.rawValue, drawerOwnsFocus: true)
        case "view.velocity_drawer":
            session.songTabs.selectedPage?.drawerPresenter()
                .toggleSection(kind: DrawerSectionKind.velocity.rawValue, drawerOwnsFocus: true)
        case "view.voice_changes_drawer":
            session.songTabs.selectedPage?.drawerPresenter()
                .toggleSection(kind: DrawerSectionKind.voiceChanges.rawValue, drawerOwnsFocus: true)
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

    private func routeEditorKey(
        key: Int, modifiers: Int, autoRepeat: Bool,
        eventList: Bool
    ) -> Bool {
        guard sceneActive, session.songOpen else { return false }
        defer { refreshActionStates() }
        if !eventList && key == 0x0100_0000 && !autoRepeat && session.handleGridEscape() {
            return true
        }
        for action in ShellActionCatalog.actions {
            guard let command = action.command,
                keybindings.scope(action.id) == .editorRouted,
                keybindings.matches(key, modifiers, action.id)
            else { continue }
            let decision =
                eventList
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

    public func releaseEditorKey(autoRepeat: Bool) -> Bool {
        guard sceneActive, session.songOpen, !autoRepeat else { return false }
        defer { refreshActionStates() }
        return session.releaseGridKey(autoRepeat: autoRepeat)
    }

    /// The native window rejects the first close while tabs and dirty banks
    /// answer their gate; no close bypasses hostClosing -> scene removal ->
    /// detach ack.
    public func beginClose() -> Bool {
        if session.wavExportPresenter().active { return false }
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
        beginStartupIfReady()
    }

    private func finishClose() {
        guard !closing else { return }
        closing = true
        // This must precede sceneActive=false: workspace input cancellation
        // still reaches the live QML scene (ApplicationSession.hostClosing).
        session.hostClosing()
        sceneActive = false
        refreshActionStates()
    }

    /// Called after Loader invalidates the scene's QML contexts and detaches
    /// its item. Qt emits Component.onDestruction before that invalidation
    /// completes; physical QObject deletion may follow later.
    public func sceneDestroyed() {
        guard closing, !closeReady, closeSettlementTask == nil else { return }
        session.acknowledgeGridDetached()
        guard case .preparing = session.audioReadiness else {
            closeReady = true
            return
        }
        let session = session
        closeSettlementTask = Task { @MainActor [weak self] in
            await session.audioPreparationSettled()
            guard let self, self.closing, !self.closeReady else { return }
            self.closeReady = true
            self.closeSettlementTask = nil
        }
    }

    /// Records completion of chrome and persisted preference restoration.
    public func chromeRestored() {
        pd_startup_trace_mark("chrome-restored")
        if !hasRestoredChrome, sceneActive, !closing {
            pd_startup_prewarm_fonts()
        }
        hasRestoredChrome = true
    }

    /// The first submitted window frame releases construction of the application UI.
    public func firstFrameRendered() {
        guard hasRestoredChrome, sceneActive, !closing, !closePending else { return }
        contentRequested = true
    }

    /// Start services after the mounted shell can consume their publications.
    public func contentReady() {
        guard contentRequested, sceneActive, !closing else { return }
        hasLoadedContent = true
        pd_startup_trace_mark("content-ready")
        pd_startup_trace_next_frame("chrome-frame")
        beginStartupIfReady()
    }

    /// Records workspace mounting, not restored-song or editor readiness.
    public func workspaceReady() {
        guard sceneActive, !closing else { return }
        hasLoadedWorkspace = true
        refreshActionStates()
        pd_startup_trace_mark("workspace-ready")
        pd_startup_trace_next_frame("workspace-frame")
    }

    /// QML supplies the selected roll's visible, applied positive-viewport predicate.
    public func editorReady(tabId: Int) {
        guard startupTraceEnabled, !hasObservedStartupEditor, sceneActive,
            !closing, !closePending, let selected = session.songTabs.selectedPage,
            selected.tabId == tabId, selected.isReady
        else { return }
        pd_startup_trace_mark("editor-ready")
        pd_startup_trace_next_frame("editor-frame")
        hasObservedStartupEditor = true
    }

    private func beginStartupIfReady() {
        guard hasRestoredChrome, hasLoadedContent, !startupBegun,
            sceneActive, !closing, !closePending
        else { return }
        startupBegun = true
        session.prepareAudio()
        session.prefetchStartup(arguments: CommandLine.arguments)
        openStartup()
    }

    public func openStartup() {
        let cli = parseStartupArguments(CommandLine.arguments)
        if !cli.project.isEmpty {
            if cli.song.isEmpty {
                session.openProject(path: cli.project)
            } else {
                session.openProjectAndSong(path: cli.project, label: cli.song)
            }
        } else if !cli.song.isEmpty {
            let recipe = EditorViewStatePreferences.loadTabs(store: session.preferences)
            if !recipe.projectPath.isEmpty {
                session.openProjectAndSong(path: recipe.projectPath, label: cli.song)
            } else {
                session.restoreStartup()
            }
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

    private func refreshWindowChrome() {
        let project =
            session.projectOpen
            ? URL(fileURLWithPath: session.projectRoot, isDirectory: true).lastPathComponent : ""
        if let selected = session.songTabs.selectedPage {
            windowTitle = "\(selected.title) — \(project) — porydaw"
        } else {
            windowTitle = project.isEmpty ? "porydaw" : "\(project) — porydaw"
        }
    }

    private func projectStateChanged() {
        refreshWindowChrome()
        refreshActionStates()
        if session.projectOpen {
            statusText = "Opened " + session.projectRoot
        }
    }

    private func documentStateChanged(songOpenChanged: Bool) {
        if songOpenChanged && session.songOpen { statusText = "Song open" }
        refreshWindowChrome()
        refreshActionStates()
    }

    private func saveStateChanged() {
        refreshWindowChrome()
        refreshActionStates()
        guard !session.saveInProgress, !session.lastSaveError.isEmpty else { return }
        criticalRequested(title: "Save Failed", message: session.lastSaveError)
    }

    private func presentFailure(title: String, message: String) {
        guard !message.isEmpty else { return }
        statusText = message
        criticalRequested(title: title, message: message)
    }

    public func configureSettings(applicationName: String) {
        PreferencesStore.configureShared(applicationName: applicationName)
        session.configurePersistence()
        let store = PreferencesStore()
        publish(\.dockColumnMinWidth, 15 * session.baseFontPx)
        publish(\.dockColumnMaxWidth, 37 * session.baseFontPx)
        let defaultDockWidth = Int((21.5 * Double(session.baseFontPx)).rounded())
        publish(\.dockColumnWidth, store.int(key: "swiftDock.columnWidth", fallback: defaultDockWidth))
        dockSongsRatio = store.double(key: "swiftDock.songsRatio", fallback: 0.5)
        let frame = store.string(key: "windowGeometry", fallback: "").split(
            separator: ",", omittingEmptySubsequences: false
        ).compactMap { Int($0) }
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
        refreshActionStates()
    }

    public func persistSessionState(
        x: Int, y: Int, width: Int, height: Int,
        maximized: Bool, debuggerVisible: Bool
    ) {
        let store = PreferencesStore()
        store.setString(key: "windowGeometry", value: "\(x),\(y),\(width),\(height)")
        var state: [String] = []
        if maximized { state.append("maximized") }
        if debuggerVisible { state.append("debugger") }
        store.setString(key: "windowState", value: state.joined(separator: ","))
        session.songDockController().presenter.persistFilters(to: store)
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

    private struct AppearancePreview {
        var mode = "vanilla"
        var contrast = 50
    }

    private var committedAppearance = AppearancePreview()

    public func previewAppearance(mode: String, contrast: Int) {
        publish(\.themeMode, ShellAppearance.mode(mode))
        publish(\.gridLineContrast, min(100, max(0, contrast)))
        applyAppearance()
    }

    public func commitAppearance() {
        committedAppearance = AppearancePreview(mode: themeMode, contrast: gridLineContrast)
        let store = PreferencesStore()
        store.setString(key: "theme.mode", value: committedAppearance.mode)
        store.setInt(key: "theme.grid-line-contrast", value: committedAppearance.contrast)
        store.synchronize()
    }

    public func discardAppearance() {
        previewAppearance(mode: committedAppearance.mode, contrast: committedAppearance.contrast)
    }

    private func applyAppearance() {
        ShellAppearance.apply(to: session.palette, mode: themeMode, contrast: gridLineContrast)
        session.refreshPromptStyle()
        session.eventListPresenter().refreshAppearance()
        // Shared roles update direct bindings; each open workspace also owns
        // color snapshots and display lists, including those in hidden tabs.
        for index in 0..<session.songTabs.tabs.count {
            session.songTabs.tabs[index].workspace.refreshAppearance()
        }
    }

    public func restoreAppearance() {
        let store = PreferencesStore()
        ShellAppearance.removeLegacyCustomKeys(store: store)
        let mode = ShellAppearance.mode(store.string(key: "theme.mode", fallback: ""))
        let contrast = ShellAppearance.contrast(
            store.string(key: "theme.grid-line-contrast", fallback: ""))
        previewAppearance(mode: mode, contrast: contrast)
        committedAppearance = AppearancePreview(mode: themeMode, contrast: gridLineContrast)
        store.setString(key: "theme.mode", value: themeMode)
        store.setInt(key: "theme.grid-line-contrast", value: gridLineContrast)
        store.synchronize()
    }

    @QtSignal public func chooseProjectRequested()
    @QtSignal public func settingsRequested(songFirst: Bool)
    @QtSignal public func aboutRequested()
    @QtSignal public func quitRequested()
    @QtSignal public func criticalRequested(title: String, message: String)
}
