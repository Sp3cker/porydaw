import Foundation
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import PorydawPluginHost
import QtBridge

@MainActor
@QtBridgeable
public final class MidiEffectPluginRow: QmlUncreatable {
    public let name: String
    public let vendor: String
    public let detail: String

    @QtIgnored
    init(entry: PluginCatalogEntry) {
        name = entry.name
        vendor = entry.vendor
        detail = entry.version
    }
}

/// Workspace-owned setup surface; the workspace fans document, controller and catalog changes into it.
@MainActor
@QtBridgeable
public final class MidiEffectsPresenter: QmlUncreatable {
    public var isOpen: Bool = false
    public var trackLabel: String = ""
    public var status: String = ""
    public var diagnostics: String = ""
    public var plugins: QListModel<MidiEffectPluginRow> = QListModel()
    public var selectedPlugin: Int = -1
    public var candidatePlugin: Int = -1
    public var browsingPlugins: Bool = false
    public var effectName: String = ""
    public var isLive: Bool = false
    public var hasEffect: Bool = false
    public var isScanning: Bool = false
    public var isLoading: Bool = false
    public var canOpenEditor: Bool = false
    public var isEditorOpen: Bool = false
    public var canReload: Bool = false
    public var inputMode: Int = 0
    public var pacing: Int = 0
    public var prerollBars: Int = 0
    public var folders: [String] = []
    public var baseFontPx: Double = 13
    @QtTracked public var promptStyle = PromptStyle()
    @QtTracked public var colors: GridPalette
    @QtTracked public var bodyFont = QmlFont(family: gridBodyFamily, pixelSize: 13)

    private static let foldersKey = "vst3PluginFolders"
    private let session: DocumentSession
    private let effects: TrackEffectsController
    private let catalog: PluginCatalog
    private let preferences: PreferencesStore
    private var sourceTrack = -1
    private var effectID: EffectID?
    private var settingsGroup: HistoryGroup?
    private var visibleEntries: [PluginCatalogEntry] = []
    private var pendingPlugin: PluginCatalogEntry?
    private var folderInput: [String]?
    private var normalizedFolders: [String] = []
    private var message = ""
    private var scanTask: Task<Void, Never>?
    private var scanID: UUID?
    private var operationTask: Task<Void, Never>?
    private var operationID: UUID?

    private enum Operation { case load, startLive, openEditor, closeEditor, reload }

    private static func normalized(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for path in paths where !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let clean = URL(filePath: path, directoryHint: .isDirectory).standardized.path
            if seen.insert(clean).inserted { result.append(clean) }
        }
        return result
    }

    private func refreshFolders() {
        let paths = preferences.strings(Self.foldersKey) ?? []
        if folderInput != paths {
            normalizedFolders = Self.normalized(paths)
            folderInput = paths
        }
        if folders != normalizedFolders { folders = normalizedFolders }
    }

    private func persistFolders() {
        preferences.setStrings(Self.foldersKey, folders)
        preferences.synchronize()
        folderInput = folders
        normalizedFolders = folders
    }

    private func refreshPlugins() {
        let entries = catalog.entries.lazy.filter { (entry: PluginCatalogEntry) -> Bool in
            entry.isMidiProducer && entry.blockedReason == nil
        }
        if !visibleEntries.elementsEqual(entries) {
            visibleEntries = Array(entries)
            plugins.reset(
                to: visibleEntries.map { (entry: PluginCatalogEntry) -> MidiEffectPluginRow in
                    MidiEffectPluginRow(entry: entry)
                })
        }
        selectedPlugin = -1
        if let effect = session.document.effect(onTrack: sourceTrack) {
            selectedPlugin =
                visibleEntries.firstIndex { (entry: PluginCatalogEntry) -> Bool in
                    entry.modulePath == effect.config.plugin.modulePath
                        && entry.classUID == effect.config.plugin.classUID
                } ?? -1
        }
        candidatePlugin = -1
        if let pendingPlugin {
            candidatePlugin =
                visibleEntries.firstIndex { (entry: PluginCatalogEntry) -> Bool in
                    entry.modulePath == pendingPlugin.modulePath && entry.classUID == pendingPlugin.classUID
                } ?? -1
            if candidatePlugin < 0 { self.pendingPlugin = nil }
        }
    }

    private func refresh() {
        refreshFolders()
        isScanning = catalog.isScanning || scanID != nil
        refreshPlugins()
        guard isOpen else { return }
        guard !session.isClosed, (0..<session.document.engineTracks.usedTrackCount).contains(sourceTrack) else {
            close()
            return
        }
        let name = session.timeline.tracks[sourceTrack].name.trimmingCharacters(in: .whitespacesAndNewlines)
        trackLabel = name.isEmpty ? "Track \(sourceTrack + 1)" : name
        let effect = session.document.effect(onTrack: sourceTrack)
        hasEffect = effect != nil
        effectName = effect?.config.plugin.name ?? ""
        isLive = effect.map { (effect: TrackEffect) -> Bool in effects.isLive(effect.id) } ?? false
        inputMode = effect?.config.plugin.input.rawValue ?? 0
        pacing = effect?.config.plugin.pacing.rawValue ?? 0
        prerollBars = effect?.config.plugin.prerollBars ?? 0
        isLoading = operationID != nil
        canReload = false
        canOpenEditor = false
        isEditorOpen = false
        diagnostics = ""
        status = message
        guard let effect else {
            if status.isEmpty { status = catalog.error ?? "" }
            if status.isEmpty, visibleEntries.isEmpty {
                status = "No MIDI-producing VST3 plugins found. Add a folder or Rescan."
            }
            return
        }
        diagnostics = MidiEffectDiagnostics.text(effects.outputs[effect.id]?.report)
        isEditorOpen = effects.instance(for: effect.id)?.isEditorOpen == true
        switch effects.status(effect.id) {
        case .idle, .ready, .rendering, .nothingHeard:
            break
        case .loading:
            isLoading = true
        case .unavailable(let reason):
            status = "Plugin unavailable: \(reason)"
        case .crashed(let reason):
            status = "\(effect.config.plugin.name) \(reason)."
            canReload = true
        case .failed(let reason):
            status = reason
        }
        canOpenEditor = !isLoading && !canReload && effects.instance(for: effect.id) != nil
        if status.isEmpty { status = catalog.error ?? "" }
    }

    private func startScan(force: Bool) {
        refreshFolders()
        scanTask?.cancel()
        let token = UUID()
        scanID = token
        let roots = folders
        let catalog = catalog
        scanTask = Task { @MainActor [weak self] in
            await catalog.scan(folders: roots, force: force)
            guard let self, self.scanID == token else { return }
            self.scanID = nil
            self.scanTask = nil
            self.refresh()
        }
        refresh()
    }

    private func perform(_ operation: Operation) {
        guard isOpen, let id = effectID else { return }
        let previous = operationTask
        previous?.cancel()
        let token = UUID()
        operationID = token
        message = ""
        let effects = effects
        operationTask = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled, self?.isOpen == true, self?.effectID == id else { return }
            var failure = ""
            do {
                switch operation {
                case .load: try await effects.load(id)
                case .startLive: try await effects.setLive(id, true)
                case .openEditor: try await effects.openEditor(id)
                case .closeEditor: await effects.closeEditor(id)
                case .reload: try await effects.reload(id)
                }
            } catch is CancellationError {
                // Controller lifecycle changes supersede panel requests without a user-facing error.
            } catch {
                failure = String(describing: error)
            }
            guard let self, self.operationID == token, self.isOpen, self.effectID == id else { return }
            self.operationID = nil
            self.operationTask = nil
            self.message = failure
            self.refresh()
        }
        refresh()
    }

    private func updateSettings(_ change: (inout PluginEffectConfig) -> Void) {
        guard isOpen, let id = effectID, var effect = session.document.effect(onTrack: sourceTrack), effect.id == id
        else {
            return
        }
        change(&effect.config.plugin)
        do {
            try session.document.updateEffect(id, config: effect.config, group: settingsGroup)
            message = ""
        } catch { message = String(describing: error) }
        refresh()
    }

    @QtIgnored
    public init(
        session: DocumentSession, effects: TrackEffectsController, catalog: PluginCatalog,
        preferences: PreferencesStore, palette: GridPalette, typography: Typography
    ) {
        self.session = session
        self.effects = effects
        self.catalog = catalog
        self.preferences = preferences
        colors = palette
        refreshFolders()
        persistFolders()
        configure(fontPx: Double(typography.baseFontPx))
        refresh()
    }

    public func configure(fontPx: Double) {
        guard fontPx.isFinite, fontPx > 0 else { return }
        baseFontPx = fontPx
        bodyFont = Typography(baseFontPx: Int(fontPx.rounded())).body.qmlFont
        refreshAppearance()
    }

    @QtIgnored
    public func refreshAppearance() {
        promptStyle.update(metrics: PromptAppearance.Layout(base: baseFontPx), palette: colors, font: bodyFont)
    }

    @QtIgnored
    public func catalogDidChange() { refresh() }

    @QtIgnored
    public func documentChanged() {
        guard isOpen else { return }
        if let id = effectID {
            guard
                let effect = session.document.effects.first(where: { (effect: TrackEffect) -> Bool in effect.id == id })
            else {
                close()
                return
            }
            sourceTrack = effect.config.track
        } else {
            effectID = session.document.effect(onTrack: sourceTrack)?.id
        }
        refresh()
    }

    public func open(track: Int) {
        close()
        guard !session.isClosed, (0..<session.document.engineTracks.usedTrackCount).contains(track) else { return }
        sourceTrack = track
        effectID = session.document.effect(onTrack: track)?.id
        browsingPlugins = effectID == nil
        settingsGroup = HistoryGroup()
        isOpen = true
        startScan(force: false)
        if let id = effectID {
            if case .crashed = effects.status(id) { return }
            perform(.load)
        }
    }

    public func close() {
        operationTask?.cancel()
        operationTask = nil
        operationID = nil
        settingsGroup = nil
        effectID = nil
        sourceTrack = -1
        isOpen = false
        trackLabel = ""
        status = ""
        message = ""
        diagnostics = ""
        selectedPlugin = -1
        pendingPlugin = nil
        candidatePlugin = -1
        browsingPlugins = false
        effectName = ""
        isLive = false
        hasEffect = false
        isLoading = false
        canOpenEditor = false
        isEditorOpen = false
        canReload = false
        inputMode = 0
        pacing = 0
        prerollBars = 0
    }

    public func showPluginChooser() {
        guard isOpen, !isLoading else { return }
        pendingPlugin = nil
        candidatePlugin = -1
        browsingPlugins = true
    }

    public func cancelPluginChooser() {
        pendingPlugin = nil
        candidatePlugin = -1
        browsingPlugins = !hasEffect
    }

    public func choosePlugin(index: Int) {
        guard isOpen, browsingPlugins, !isLoading, !isScanning, visibleEntries.indices.contains(index) else { return }
        let entry = visibleEntries[index]
        pendingPlugin = entry
        candidatePlugin = index
    }

    public func applyPlugin() {
        refreshPlugins()
        guard isOpen, browsingPlugins, !isLoading, !isScanning,
            candidatePlugin >= 0, candidatePlugin != selectedPlugin, let entry = pendingPlugin
        else { return }
        let replacing = session.document.effect(onTrack: sourceTrack)?.id
        effectID = nil
        do {
            let config = TrackEffectConfig(
                track: sourceTrack,
                plugin: PluginEffectConfig(
                    modulePath: entry.modulePath, classUID: entry.classUID, name: entry.name,
                    input: .trackNotes, pacing: .offline, prerollBars: 0))
            effectID = try session.document.addEffect(config, replacing: replacing)
            message = ""
            pendingPlugin = nil
            candidatePlugin = -1
            browsingPlugins = false
            refresh()
            perform(.startLive)
        } catch {
            effectID = replacing
            message = String(describing: error)
            refresh()
        }
    }

    public func rescan() { startScan(force: true) }

    public func cancelScan() {
        scanTask?.cancel()
        catalog.cancelScan()
        refresh()
    }

    public func addFolder(path: String) {
        refreshFolders()
        var path = path
        if path.hasPrefix("file://"), let url = URL(string: path), url.isFileURL { path = url.path }
        let next = Self.normalized(folders + [path])
        guard folders != next else { return }
        folders = next
        persistFolders()
        startScan(force: false)
    }

    public func removeFolder(index: Int) {
        guard folders.indices.contains(index) else { return }
        let path = folders[index]
        refreshFolders()
        guard let current = folders.firstIndex(of: path) else { return }
        folders.remove(at: current)
        persistFolders()
        startScan(force: false)
    }

    public func setInputMode(value: Int) {
        guard let mode = EffectInput(rawValue: value) else { return }
        updateSettings { (plugin: inout PluginEffectConfig) in plugin.input = mode }
    }

    public func setPacing(value: Int) {
        guard let mode = EffectPacing(rawValue: value) else { return }
        updateSettings { (plugin: inout PluginEffectConfig) in plugin.pacing = mode }
    }

    public func setPrerollBars(value: Int) {
        guard (0...2).contains(value) else { return }
        updateSettings { (plugin: inout PluginEffectConfig) in plugin.prerollBars = value }
    }

    public func removeEffect() {
        guard isOpen, let id = effectID else { return }
        do {
            try session.document.removeEffect(id)
            close()
        } catch {
            message = String(describing: error)
            refresh()
        }
    }

    public func openEditor() {
        guard canOpenEditor else { return }
        perform(.openEditor)
    }

    public func closeEditor() {
        guard isEditorOpen else { return }
        perform(.closeEditor)
    }

    public func reloadPlugin() {
        guard canReload, !isLoading else { return }
        perform(.reload)
    }
}
