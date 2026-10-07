import Foundation
import PorydawVoicegroup

public struct SampleCommitRequest: Sendable {
    public let name: String
    public let wav: Data
    public let update: Bool

    public init(name: String, wav: Data, update: Bool) {
        self.name = name
        self.wav = wav
        self.update = update
    }
}

extension ProjectStore {
    /// Commits the WAV and registration, then refreshes loaded banks.
    /// - Parameter request: The sample bytes and whether they replace a registered sample.
    /// - Returns: Fresh leases to publish to live sessions.
    /// - Throws: A registration or project-loader failure.
    public func commitSample(_ request: SampleCommitRequest) throws -> [ProjectBankLease] {
        do {
            if request.update {
                try SampleRegistrar.update(projectRoot: projectRoot, name: request.name, wav: request.wav)
            } else {
                try SampleRegistrar.register(projectRoot: projectRoot, name: request.name, wav: request.wav)
            }
        } catch {
            throw VoicegroupStoreError.operationFailed(
                error.message.isEmpty
                    ? "Could not commit \(request.name)." : error.message)
        }
        guard let context = ProjectContext.open(projectRoot: projectRoot) else {
            throw VoicegroupStoreError.operationFailed("Could not refresh the project sample maps.")
        }
        let views = voicegroupStore?.rebind(context: context) ?? []
        projectContext = context
        pickerSamples = nil
        return views.map { adoptBankLease(view: $0) }
    }

    /// Reads the committed WAV.
    /// - Parameter name: Registered sample name.
    /// - Returns: The committed sample.
    /// - Throws: A project layout or sample read failure.
    public func readCommittedSample(name: String) throws -> CommittedSample {
        try SampleRegistrar.readCommitted(projectRoot: projectRoot, name: name)
    }
}
