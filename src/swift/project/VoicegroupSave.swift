import Foundation

extension VoicegroupSource {
    /// Basename used for a staged preview, matching the loader's selected voicegroup name.
    public var previewShadowName: String { loadName }

    /// Rebases onto the current disk bytes, then atomically writes the selected section's pending
    /// change into that fresh image and adopts it as the clean baseline.
    /// - Returns: Whether the written bytes are still the current source bytes.
    /// - Throws: `VoicegroupSourceConflict` for a missing, invalid, relocated, or conflicting source,
    ///   or the underlying write failure. Pending edits and dirty state survive every failure.
    public func save() throws -> Bool {
        guard try rebasePreservingEdits(from: diskSnapshot()) else {
            throw VoicegroupSourceConflict(message: "\(loadName) changed in \(filePath) since it was loaded.")
        }
        let bytes = sourceBytes()
        try ProjectFileStore.writeAtomic(filePath, data: Data(bytes))
        return didSave(savedBytes: bytes)
    }

    /// Renders a standalone preview, isolating the selected section of a monolithic file.
    /// - Returns: Complete source bytes for a per-file voicegroup, or its section with LF terminators.
    public func renderPreview() -> [UInt8] {
        guard isMonolithic else { return sourceBytes() }
        var bytes: [UInt8] = []
        guard sectionBegin >= 0, sectionEnd <= lines.count, sectionBegin < sectionEnd else { return bytes }
        bytes.reserveCapacity(lines[sectionBegin..<sectionEnd].reduce(0) { $0 + $1.raw.count + 1 })
        for index in sectionBegin..<sectionEnd {
            bytes.append(contentsOf: lines[index].raw)
            bytes.append(10)
        }
        return bytes
    }

    /// Stages the preview outside the project, loads it through the project context,
    /// and removes the staging directory even if the load fails.
    /// The loader takes the staged file by absolute path while sample and include
    /// references still resolve against the project root, so the preview matches
    /// the saved result. Staging under a per-process temporary directory keeps
    /// previews out of the user's project folder (and its git); any staging or
    /// load failure refuses the preview.
    /// - Parameter context: Context holding the current project's loader discovery state.
    /// - Returns: A self-contained preview bank, or nil if staging or loading fails.
    func loadPreviewedSource(using context: ProjectContext) -> BankHandle? {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(
            "porydaw-vgpreview-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: staging) }
        let path = staging.appendingPathComponent("\(previewShadowName).inc").path
        do {
            try ProjectFileStore.writeAtomic(path, data: Data(renderPreview()))
        } catch {
            return nil
        }
        guard let handle = context.load(target: .init(filePath: path, sectionLabel: sectionLabel)) else {
            return nil
        }
        handle.graftMintedSynths(source: self)
        return handle
    }
}
