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
    public let blocked: Bool

    @QtIgnored
    init(entry: PluginCatalogEntry) {
        name = entry.name
        vendor = entry.vendor
        detail = entry.blockedReason ?? entry.version
        blocked = entry.blockedReason != nil
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
    private var message = ""
    private var scanTask: Task<Void, Never>?
    private var scanID: UUID?
    private var operationTask: Task<Void, Never>?
    private var operationID: UUID?

    private enum Operation { case load, openEditor, closeEditor, reload }

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
        let next = Self.normalized(preferences.strings(Self.foldersKey) ?? [])
        if folders != next { folders = next }
    }

    private func persistFolders() {
        preferences.setStrings(Self.foldersKey, folders)
        preferences.synchronize()
    }

    private func refreshPlugins() {
        let entries = catalog.entries.filter { (entry: PluginCatalogEntry) -> Bool in
            entry.isMidiProducer || entry.blockedReason != nil
        }
        if visibleEntries != entries {
            visibleEntries = entries
            plugins.reset(
                to: entries.map { (entry: PluginCatalogEntry) -> MidiEffectPluginRow in
                    MidiEffectPluginRow(entry: entry)
                })
        }
        selectedPlugin = -1
        if let effect = session.document.effect(onTrack: sourceTrack) {
            selectedPlugin =
                entries.firstIndex { (entry: PluginCatalogEntry) -> Bool in
                    entry.modulePath == effect.config.plugin.modulePath
                        && entry.classUID == effect.config.plugin.classUID
                } ?? -1
        }
    }

    private static func diagnosticText(_ report: NormalizationReport?) -> String {
        guard let report else { return "" }
        let counters: [(String, Int)] = [
            ("notes", report.notes), ("nonNoteEvents", report.nonNoteEvents),
            ("droppedBeforeRange", report.droppedBeforeRange), ("droppedAfterRange", report.droppedAfterRange),
            ("droppedPitch", report.droppedPitch), ("droppedTooShort", report.droppedTooShort),
            ("orphanOffs", report.orphanOffs), ("unterminatedNotes", report.unterminatedNotes),
            ("snappedOnsets", report.snappedOnsets), ("adjustedDurations", report.adjustedDurations),
            ("velocityClamped", report.velocityClamped), ("overlapsTrimmed", report.overlapsTrimmed),
            ("duplicatesSuppressed", report.duplicatesSuppressed),
        ]
        var parts: [String] = []
        for (name, count) in counters where count != 0 { parts.append("\(name): \(count)") }
        return parts.joined(separator: ", ")
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
        diagnostics = Self.diagnosticText(effects.outputs[effect.id]?.report)
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
        folders = Self.normalized(preferences.strings(Self.foldersKey) ?? [])
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
        hasEffect = false
        isLoading = false
        canOpenEditor = false
        isEditorOpen = false
        canReload = false
        inputMode = 0
        pacing = 0
        prerollBars = 0
    }

    public func selectPlugin(index: Int) {
        guard isOpen, visibleEntries.indices.contains(index) else { return }
        let entry = visibleEntries[index]
        guard entry.isMidiProducer, entry.blockedReason == nil else { return }
        let replacing = session.document.effect(onTrack: sourceTrack)?.id
        effectID = nil
        do {
            let config = TrackEffectConfig(
                track: sourceTrack,
                plugin: PluginEffectConfig(
                    modulePath: entry.modulePath, classUID: entry.classUID, name: entry.name,
                    input: .none, pacing: .offline, prerollBars: 0))
            effectID = try session.document.addEffect(config, replacing: replacing)
            message = ""
            refresh()
            perform(.load)
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

    public func retryBlocked(index: Int) {
        guard visibleEntries.indices.contains(index), visibleEntries[index].blockedReason != nil else { return }
        catalog.retry(modulePath: visibleEntries[index].modulePath)
        startScan(force: false)
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
