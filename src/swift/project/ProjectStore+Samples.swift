import Foundation
import PorydawSample

public struct SampleCommitRequest: Sendable {
    public let name: String
    public let wav: Data
    public let sidecar: SampleSidecar?
    public let removeSidecar: Bool
    public let update: Bool

    public init(name: String, wav: Data, sidecar: SampleSidecar?, removeSidecar: Bool, update: Bool) {
        self.name = name
        self.wav = wav
        self.sidecar = sidecar
        self.removeSidecar = removeSidecar
        self.update = update
    }
}

public struct SampleCommitReceipt: Sendable {
    public let name: String
    public let sidecarSaved: Bool
    public let sidecarError: String
}

extension ProjectStore {
    /// Commits the WAV and registration, refreshes loaded banks, then writes optional provenance.
    /// - Parameter request: The sample bytes and provenance operation.
    /// - Returns: A receipt and fresh leases to publish to live sessions.
    /// - Throws: A registration or project-loader failure; sidecar failures are returned in the receipt.
    public func commitSample(_ request: SampleCommitRequest) throws -> (SampleCommitReceipt, [ProjectBankLease]) {
        do {
            if request.update {
                try SampleRegistrar.update(projectRoot: projectRoot, name: request.name, wav: request.wav)
            } else {
                try SampleRegistrar.register(projectRoot: projectRoot, name: request.name, wav: request.wav)
            }
        } catch let error as SampleRegistrationError {
            throw VoicegroupStoreError.operationFailed(error.message.isEmpty
                ? "Could not commit \(request.name)." : error.message)
        }
        guard let context = ProjectContext.open(projectRoot: projectRoot) else {
            throw VoicegroupStoreError.operationFailed("Could not refresh the project sample maps.")
        }
        let views = voicegroupStore?.rebind(context: context) ?? []
        projectContext = context
        pickerSamples = nil
        let leases = try views.map { try adoptBankLease(view: $0) }

        var saved = true
        var sidecarError = ""
        if request.removeSidecar {
            SampleRegistrar.removeSidecar(projectRoot: projectRoot, name: request.name)
        } else if let sidecar = request.sidecar {
            do {
                try SampleRegistrar.writeSidecar(projectRoot: projectRoot, name: request.name, sidecar)
            } catch let error as SampleRegistrationError {
                saved = false
                sidecarError = error.message
            }
        }
        return (SampleCommitReceipt(name: request.name, sidecarSaved: saved,
                                    sidecarError: sidecarError), leases)
    }

    /// Reads the committed WAV and optional valid provenance.
    /// - Parameter name: Registered sample name.
    /// - Returns: The committed sample.
    /// - Throws: A project layout or sample read failure.
    public func readCommittedSample(name: String) throws -> CommittedSample {
        try SampleRegistrar.readCommitted(projectRoot: projectRoot, name: name)
    }
}
