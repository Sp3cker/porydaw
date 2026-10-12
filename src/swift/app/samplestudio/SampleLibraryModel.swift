import Foundation
import PorydawAppPresentation
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
    public let selected: Bool

    init(path: String, selected: Bool) {
        self.path = path
        name = URL(fileURLWithPath: path).lastPathComponent
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

        init(path: String, depth: Int, rootPath: String) {
            self.path = path
            self.depth = depth
            self.rootPath = rootPath
            childPaths = SampleLibraryModel.directoryEntries(at: path, folders: true)
                .map { $0.standardizedFileURL.path }
        }

        func populate() {
            guard !childrenLoaded else { return }
            children = childPaths.map { FolderNode(path: $0, depth: depth + 1, rootPath: rootPath) }
            childrenLoaded = true
        }
    }

    private static let foldersKey = "sampleLibraryFolders"
    private static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "mp3", "flac", "ogg"]
    private static let resourceKeyList: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey,
    ]
    private static let resourceKeys = Set(resourceKeyList)
    private let preferences: PreferencesStore
    private var roots: [FolderNode] = []
    private var visibleFolders: [FolderNode] = []
    private var selectedFolder: FolderNode?
    private var selectedFilePath: String?
    private var currentFiles: [String] = []
    private var message = ""
    private var loadedPath = ""
    private var previewingPath = ""

    public var folders: QListModel<SampleLibraryFolderRow> = QListModel()
    public var files: QListModel<SampleLibraryFileRow> = QListModel()
    @QtTracked public var statusText = ""
    @QtTracked public var statusToolTip = ""
    @QtTracked public var loadedText = "Loaded: none"
    @QtTracked public var loadedToolTip = ""
    @QtTracked public var previewText = "Preview source: none"
    @QtTracked public var previewToolTip = ""
    @QtTracked public var previewButtonLabel = "Preview"
    @QtTracked public var canLoad = false
    @QtTracked public var canPreview = false
    @QtTracked public var canRemove = false
    @QtTracked public var filesVisible = false
    @QtIgnored public var onPreviewRequested: ((String) -> Void)?
    @QtIgnored public var onPreviewStopRequested: (() -> Void)?
    @QtIgnored public var onLoadRequested: ((String) -> Void)?
    @QtIgnored public var onOpenFileRequested: (() -> Void)?

    @QtIgnored
    public init(preferences: PreferencesStore) {
        self.preferences = preferences
        let paths = Self.normalized(preferences.strings(Self.foldersKey) ?? [])
        roots = paths.map { FolderNode(path: $0, depth: 0, rootPath: $0) }
        persistRoots()
        navigate(to: roots.first)
    }

    public func addFolder(path: String) {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let directory: String
        if path.hasPrefix("file://"), let url = URL(string: path), url.isFileURL {
            directory = url.path
        } else {
            directory = path
        }
        let normalized = Self.normalized([directory])
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
        selectedFilePath = currentFiles[row]
        message = ""
        refreshFiles()
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

    public func setLoadedPath(path: String) {
        loadedPath = path
        showMessage(text: "")
    }

    public func setPreviewingPath(path: String) {
        previewingPath = path
        updateState()
    }

    public func clearFileSelection() {
        selectedFilePath = nil
        refreshFiles()
        updateState()
    }

    private func navigate(to node: FolderNode?) {
        selectedFolder = node
        node?.populate()
        node?.expanded = true
        message = ""
        selectedFilePath = nil
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
        folders.reset(
            to: visibleFolders.map { node in
                SampleLibraryFolderRow(
                    path: node.path, depth: node.depth, expanded: node.expanded,
                    hasChildren: !node.childPaths.isEmpty, selected: node === selectedFolder)
            })
    }

    private func refreshFiles() {
        files.reset(to: currentFiles.map { SampleLibraryFileRow(path: $0, selected: $0 == selectedFilePath) })
    }

    private func updateState() {
        var isDirectory: ObjCBool = false
        filesVisible =
            selectedFolder.map {
                FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue
            } ?? false
        canRemove = selectedFolder != nil
        canLoad = selectedFilePath != nil
        canPreview = canLoad || !previewingPath.isEmpty
        previewButtonLabel = previewingPath.isEmpty ? "Preview" : "Stop Preview"
        statusToolTip = selectedFilePath ?? ""
        loadedToolTip = loadedPath
        loadedText =
            loadedPath.isEmpty ? "Loaded: none" : "Loaded: \(URL(fileURLWithPath: loadedPath).lastPathComponent)"
        previewToolTip = previewingPath
        previewText =
            previewingPath.isEmpty
            ? "Preview source: none" : "Preview source: \(URL(fileURLWithPath: previewingPath).lastPathComponent)"

        if !message.isEmpty {
            statusText = message
        } else if roots.isEmpty {
            statusText = "No library folders. Add a folder or open a file."
        } else if !filesVisible {
            statusText = "Library folder is missing: \(selectedFolder?.path ?? "")"
        } else if currentFiles.isEmpty {
            statusText = "No supported audio files in this folder."
        } else if let selectedFilePath {
            statusText = "Selected: \(URL(fileURLWithPath: selectedFilePath).lastPathComponent)"
        } else {
            statusText = "No file selected."
        }
    }

    private func persistRoots() {
        preferences.setStrings(Self.foldersKey, roots.map(\.path))
        preferences.synchronize()
    }

    private static func normalized(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for path in paths where !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let clean = URL(fileURLWithPath: path).standardizedFileURL.path
            if seen.insert(clean).inserted { result.append(clean) }
        }
        return result
    }

    private static func directoryEntries(at path: String, folders: Bool) -> [URL] {
        let keys = resourceKeys
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: path), includingPropertiesForKeys: resourceKeyList,
                options: [.skipsHiddenFiles])
        else { return [] }
        return entries.filter { entry in
            guard !entry.lastPathComponent.hasPrefix("."),
                let values = try? entry.resourceValues(forKeys: keys), values.isHidden != true
            else { return false }
            if folders { return values.isDirectory == true && values.isSymbolicLink != true }
            return values.isRegularFile == true && audioExtensions.contains(entry.pathExtension.lowercased())
        }.sorted { left, right in
            let order = left.lastPathComponent.compare(right.lastPathComponent, options: .caseInsensitive)
            return order == .orderedSame
                ? left.lastPathComponent < right.lastPathComponent : order == .orderedAscending
        }
    }
}
