import Foundation

extension VoicegroupSource {
    /// Basename used for a staged preview, matching the loader's selected voicegroup name.
    public var previewShadowName: String { loadName }

    /// Atomically persists the full source and adopts its bytes as the clean baseline.
    /// - Returns: Whether the written bytes are still the current source bytes.
    /// - Throws: The underlying write failure; the caller maps it to a user-facing message.
    public func save() throws -> Bool {
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

    /// Stages the preview under its loader basename, loads it through the project context,
    /// and removes the temporary directory even if the load fails.
    /// - Parameter context: Context holding the current project's loader discovery state.
    /// - Returns: A self-contained preview bank, or nil if staging or loading fails.
    func loadPreviewedSource(using context: ProjectContext) -> BankHandle? {
        let root = URL(filePath: projectRoot).standardizedFileURL.path
        let directory = "\(root)/.porydaw/vgpreview"
        let path = "\(directory)/\(previewShadowName).inc"
        do {
            try ProjectFileStore.remove(directory)
            try ProjectFileStore.mkpath(directory)
        } catch {
            return nil
        }
        defer { try? ProjectFileStore.remove(directory) }
        do {
            try ProjectFileStore.writeAtomic(path, data: Data(renderPreview()))
        } catch {
            return nil
        }
        return context.load(target: .init(filePath: path, sectionLabel: sectionLabel))
    }
}
