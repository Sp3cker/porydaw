import Foundation

/// Serializes project-store operations; native blocking work belongs on ProjectContext's worker.
public actor ProjectStore {
    let projectRoot: String
    var openedSnapshot: ProjectSnapshot?
    var projectContext: ProjectContext?
    var voicegroupStore: VoicegroupStore?
    var pendingSynths: [String: VgSynthDesc] = [:]
    var pickerSamples: PickerSampleCache?

    /// Creates a store rooted at a lexically normalized project path.
    /// - Parameter projectRoot: The project directory URL.
    public init(projectRoot: URL) {
        self.projectRoot = ProjectFileStore.cleanPath(projectRoot.path)
    }

    public func readFile(_ path: String) throws -> Data {
        try ProjectFileStore.read(path)
    }

    public func writeFile(_ path: String, data: Data) throws {
        try ProjectFileStore.writeAtomic(path, data: data)
    }

    public func voicegroupCatalog() -> (groups: VgCatalogScan, direct: VgDirectSoundScan) {
        (VoicegroupSource.catalogScan(projectRoot),
         VoicegroupSource.directSoundCatalog(projectRoot))
    }
}
