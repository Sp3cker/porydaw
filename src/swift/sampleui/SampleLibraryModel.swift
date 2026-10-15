import Foundation
import PorydawAppAudio
import PorydawAppPresentation
import PorydawSample
import QtBridge

@MainActor
@QtBridgeable
public final class SampleLibraryFolderRow: QmlUncreatable {
    public let path: String
    public let title: String
    public let depth: Int
    public let expanded: Bool
    public let hasChildren: Bool
    public let selected: Bool

    init(path: String, depth: Int, expanded: Bool, hasChildren: Bool, selected: Bool) {
        self.path = path
        title = URL(fileURLWithPath: path).lastPathComponent
        self.depth = depth
        self.expanded = expanded
        self.hasChildren = hasChildren
        self.selected = selected
    }
}

@MainActor
@QtBridgeable
public final class SampleLibraryFileRow: QmlUncreatable {
    public let path: String
    public let name: String
    public let fileURL: String
    public var selected: Bool

    init(path: String, selected: Bool) {
        self.path = path
        let url = URL(fileURLWithPath: path)
        name = url.lastPathComponent
        fileURL = url.absoluteString
        self.selected = selected
    }
}

/// Saved library roots, their lazily expanded directory tree, and the current audio list.
@MainActor
@QtBridgeable
public final class SampleLibraryModel: QmlUncreatable {
    @MainActor private final class FolderNode {
        let path: String
        let depth: Int
        let rootPath: String
        let childPaths: [String]
        var children: [FolderNode] = []
        var childrenLoaded = false
        var expanded = false
        private var cachedRow: SampleLibraryFolderRow?

        init(path: String, depth: Int, rootPath: String) {
            self.path = path
            self.depth = depth
            self.rootPath = rootPath
            childPaths = SampleLibraryModel.directoryEntries(at: path, folders: true)
                .map { (url: URL) -> String in url.standardized.path }
        }

        func populate() {
            guard !childrenLoaded else { return }
            children = childPaths.map { FolderNode(path: $0, depth: depth + 1, rootPath: rootPath) }
            childrenLoaded = true
        }

        func row(selected: Bool) -> SampleLibraryFolderRow {
            if let cachedRow, cachedRow.expanded == expanded, cachedRow.selected == selected {
                return cachedRow
            }
            let row = SampleLibraryFolderRow(
                path: path, depth: depth, expanded: expanded,
                hasChildren: !childPaths.isEmpty, selected: selected)
            cachedRow = row
            return row
        }
    }

    private static let foldersKey = "sampleLibraryFolders"
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey,
    ]
    private let preferences: PreferencesStore
    private var roots: [FolderNode] = []
    private var visibleFolders: [FolderNode] = []
    private var selectedFolder: FolderNode?
    private var selectedFileRow: Int?
    private var selectedFilePath: String? {
        selectedFileRow.map { (row: Int) -> String in currentFiles[row] }
    }
    private var currentFiles: [String] = []
    private var message = ""
    private var previewingPath = ""
    private var previewFrames = 1
    // The selected file's scan; its result is the decode a preview reuses.
    private var scanPath = ""
    private var scan: Task<ImportedSample?, Never>?
    private var settle: Task<Void, Never>?
    @QtIgnored let previewPlayer: PcmAuditionPlayer
    /// How long a selection rests before its scan starts; explicit previews and loads skip it.
    @QtIgnored var settleDelay: Duration = .milliseconds(200)

    public var folders: QListModel<SampleLibraryFolderRow> = QListModel()
    public var files: QListModel<SampleLibraryFileRow> = QListModel()
    @QtTracked public let preview: LibraryPreviewStrip
    // Failure-only readout: empty unless the last preview/load attempt failed.
    @QtTracked public var statusText = ""
    @QtTracked public var canRemove = false
    @QtTracked public var filesVisible = false
    @QtTracked public var previewing = false
    @QtIgnored public var onPreviewRequested: ((String) -> Void)?
    @QtIgnored public var onPreviewStopRequested: (() -> Void)?
    @QtIgnored public var onLoadRequested: ((String) -> Void)?
    @QtIgnored public var onOpenFileRequested: (() -> Void)?

    @QtIgnored
    public init(preferences: PreferencesStore, palette: GridPalette, lane: SampleAuditionArbiter?) {
        self.preferences = preferences
        preview = LibraryPreviewStrip(palette: palette)
        previewPlayer = PcmAuditionPlayer(lane: lane)
        let paths = Self.normalized(preferences.strings(Self.foldersKey) ?? [])
        roots = paths.map { FolderNode(path: $0, depth: 0, rootPath: $0) }
        previewPlayer.onPlayhead = { [weak self] (frame: Int?) in self?.previewPlayheadMoved(frame) }
        persistRoots()
        navigate(to: roots.first)
    }

    public func addFolder(path: String) {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let normalized = Self.normalized([Self.directoryPath(path)])
        guard let chosen = normalized.first else { return }
        if let existing = roots.first(where: { $0.path == chosen }) {
            navigate(to: existing)
            return
        }
        let node = FolderNode(path: chosen, depth: 0, rootPath: chosen)
        roots.append(node)
        persistRoots()
        navigate(to: node)
    }

    /// Whether every entry of a dragged `text/uri-list` names an existing folder the library may add.
    public func areFolders(uriList: String) -> Bool {
        let entries = DroppedURIList.entries(uriList)
        return !entries.isEmpty && entries.allSatisfy { (path: String) -> Bool in Self.isFolder(path) }
    }

    private static func isFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: Self.directoryPath(path), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func directoryPath(_ path: String) -> String {
        if path.hasPrefix("file://"), let url = URL(string: path), url.isFileURL { return url.path }
        return path
    }

    public func removeSelectedRoot() {
        guard let selectedFolder else { return }
        roots.removeAll { $0.path == selectedFolder.rootPath }
        persistRoots()
        navigate(to: roots.first)
    }

    public func selectFolder(row: Int) {
        guard visibleFolders.indices.contains(row) else { return }
        navigate(to: visibleFolders[row])
    }

    public func selectedFolderRow() -> Int {
        visibleFolders.firstIndex { (node: FolderNode) -> Bool in node === selectedFolder } ?? -1
    }

    public func parentFolderRow(row: Int) -> Int {
        guard visibleFolders.indices.contains(row) else { return -1 }
        let depth = visibleFolders[row].depth
        return visibleFolders[..<row].lastIndex { (node: FolderNode) -> Bool in node.depth < depth } ?? row
    }

    public func toggleFolder(row: Int) {
        guard visibleFolders.indices.contains(row) else { return }
        let node = visibleFolders[row]
        guard !node.childPaths.isEmpty else { return }
        if !node.expanded { node.populate() }
        node.expanded.toggle()
        refreshFolders()
    }

    public func selectFile(row: Int) {
        guard currentFiles.indices.contains(row) else { return }
        setFileSelection(row)
        message = ""
        updateState()
    }

    public func clickFile(row: Int) {
        guard currentFiles.indices.contains(row) else { return }
        selectFile(row: row)
        guard let onPreviewRequested else { return }
        onPreviewRequested(currentFiles[row])
    }

    public func activateFile(row: Int) {
        guard currentFiles.indices.contains(row) else { return }
        selectFile(row: row)
        startScan(currentFiles[row])
        loadSelected()
    }

    public func togglePreview() {
        showMessage(text: "")
        if !previewingPath.isEmpty {
            guard let onPreviewStopRequested else { return }
            onPreviewStopRequested()
        } else if let selectedFilePath {
            guard let onPreviewRequested else { return }
            onPreviewRequested(selectedFilePath)
        }
    }

    public func loadSelected() {
        guard let selectedFilePath else { return }
        showMessage(text: "")
        guard let onLoadRequested else { return }
        onLoadRequested(selectedFilePath)
    }

    public func requestOpenFile() {
        guard let onOpenFileRequested else { return }
        onOpenFileRequested()
    }

    public func showMessage(text: String) {
        message = text
        updateState()
    }

    public func setPreviewingPath(path: String) {
        previewingPath = path
        updateState()
    }

    /// The selected file's decode, starting its scan now if the settle has not; nil when the
    /// decode fails or the selection moves on.
    @QtIgnored public func decodedSample(path: String) async -> Optional<ImportedSample> {
        guard path == selectedFilePath else { return nil }
        startScan(path)
        return await scan?.value
    }

    /// Sounds a prepared preview once at `key`; the end clears `previewing`.
    @QtIgnored public func playPreview(_ rendered: ProcessedSample, path: String, key: UInt8, toneKey: UInt8) {
        previewPlayer.play(
            owner: self, rendered: rendered, looped: false, key: key, adsr: AudioADSR(), toneKey: toneKey)
        previewFrames = max(1, rendered.s8.count)
        setPreviewingPath(path: path)
        previewPlayheadMoved(0)
    }

    public func tickPreview() { previewPlayer.tick() }

    @QtIgnored public func stopPreview() {
        previewPlayer.stop(owner: self)
        setPreviewingPath(path: "")
    }

    private func previewPlayheadMoved(_ frame: Int?) {
        let drawn = previewingPath == selectedFilePath ? frame : nil
        preview.setPlayhead(fraction: drawn.map { (frame: Int) -> Double in Double(frame) / Double(previewFrames) })
        // A nil frame while still playing is the one-shot's natural end.
        if frame == nil, previewPlayer.playing { stopPreview() }
    }

    private func scheduleScan() {
        settle?.cancel()
        scan?.cancel()
        scan = nil
        scanPath = ""
        preview.setOverview(SampleOverview())
        preview.setPlayhead(fraction: nil)
        guard let path = selectedFilePath else { return }
        let delay = settleDelay
        settle = Task { [weak self] in
            // A cancelled sleep is a superseded selection; the check below ends it.
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.startScan(path)
        }
    }

    private func startScan(_ path: String) {
        settle?.cancel()
        guard scanPath != path else { return }
        scan?.cancel()
        scanPath = path
        let publish: @Sendable (SampleOverview) -> Void = { [weak self] (overview: SampleOverview) in
            Task { @MainActor [weak self] in self?.showOverview(overview, path: path) }
        }
        scan = Task { () -> ImportedSample? in await Self.scanFile(path, publish: publish) }
    }

    @concurrent
    private static func scanFile(
        _ path: String, publish: @escaping @Sendable (SampleOverview) -> Void
    ) async -> ImportedSample? {
        // A failed or cancelled scan yields nil; the preview then decodes itself and reports the error.
        try? SampleOverview.scan(path: path, publish: publish, isCancelled: { () -> Bool in Task.isCancelled })
    }

    private func showOverview(_ overview: SampleOverview, path: String) {
        // Snapshot tasks may land out of order; a shorter prefix is stale.
        guard path == scanPath, overview.decodedFrames >= preview.decodedFrames else { return }
        preview.setOverview(overview)
    }

    public func clearFileSelection() {
        setFileSelection(nil)
        updateState()
    }

    private func navigate(to node: FolderNode?) {
        selectedFolder = node
        node?.populate()
        node?.expanded = true
        message = ""
        setFileSelection(nil)
        currentFiles = node.map { Self.directoryEntries(at: $0.path, folders: false).map(\.path) } ?? []
        refreshFolders()
        refreshFiles()
        updateState()
    }

    private func refreshFolders() {
        visibleFolders.removeAll(keepingCapacity: true)
        func append(_ node: FolderNode) {
            visibleFolders.append(node)
            if node.expanded {
                for child in node.children { append(child) }
            }
        }
        for root in roots { append(root) }
        let rows = visibleFolders.map { (node: FolderNode) -> SampleLibraryFolderRow in
            node.row(selected: node === selectedFolder)
        }
        syncModel(
            folders, rows,
            matches: { (lhs: SampleLibraryFolderRow, rhs: SampleLibraryFolderRow) -> Bool in lhs === rhs })
    }

    private func refreshFiles() {
        files.reset(to: currentFiles.map { SampleLibraryFileRow(path: $0, selected: $0 == selectedFilePath) })
    }

    private func setFileSelection(_ row: Int?) {
        guard selectedFileRow != row else { return }
        let previous = selectedFileRow
        selectedFileRow = row
        files.update {
            if let previous {
                let item = files[previous]
                item.selected = false
                files[previous] = item
            }
            if let row {
                let item = files[row]
                item.selected = true
                files[row] = item
            }
        }
        scheduleScan()
    }

    private func updateState() {
        var isDirectory: ObjCBool = false
        filesVisible =
            selectedFolder.map {
                FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue
            } ?? false
        canRemove = selectedFolder != nil
        statusText = message
        previewing = !previewingPath.isEmpty
    }

    private func persistRoots() {
        preferences.setStrings(Self.foldersKey, roots.map(\.path))
        preferences.synchronize()
    }

    private static func normalized(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for path in paths where !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let clean = URL(filePath: path, directoryHint: .isDirectory).standardized.path
            if seen.insert(clean).inserted { result.append(clean) }
        }
        return result
    }

    private static func directoryEntries(at path: String, folders: Bool) -> [URL] {
        let directory = URL(filePath: path, directoryHint: .isDirectory)
        // Path enumeration follows an explicit root symlink without canonicalizing its bookmark.
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        var result: [URL] = []
        for name in names {
            let entry = directory.appendingPathComponent(name, isDirectory: false)
            guard !name.hasPrefix("."),
                let values = try? entry.resourceValues(forKeys: resourceKeys), values.isHidden != true
            else { continue }
            let included =
                folders
                ? values.isDirectory == true && values.isSymbolicLink != true
                : values.isRegularFile == true && SampleImport.fileExtensions.contains(entry.pathExtension.lowercased())
            if included {
                result.append(entry)
            }
        }
        result.sort { (left: URL, right: URL) -> Bool in
            let order = left.lastPathComponent.compare(right.lastPathComponent, options: .caseInsensitive)
            return order == .orderedSame
                ? left.lastPathComponent < right.lastPathComponent : order == .orderedAscending
        }
        return result
    }
}
