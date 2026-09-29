import Foundation
import PorydawProject

extension ProjectService {
    /// Inspects sample-registration prerequisites on the store's owner.
    public func probeSamples() async throws -> SampleRegistrar.Probe {
        _ = try requireStore()
        return SampleRegistrar.probe(projectRoot: projectRoot)
    }

    /// Commits a sample and republishes refreshed banks to every sharing session.
    /// - Parameter request: Sample bytes and sidecar operation.
    /// - Returns: The commit receipt, including nonfatal provenance failure.
    /// - Throws: `ProjectServiceError` when registration or loader refresh fails.
    public func commitSample(_ request: SampleCommitRequest) async throws -> SampleCommitReceipt {
        let store = try requireStore()
        do {
            let (receipt, leases) = try await store.commitSample(request)
            for lease in leases {
                await publish(appliedBank(lease, token: 0), from: store)
            }
            return receipt
        } catch {
            throw projectFailure(error)
        }
    }

    /// Reads a committed sample without changing the current bank.
    /// - Parameter name: Registered sample name.
    /// - Returns: Committed WAV and optional sidecar.
    /// - Throws: `ProjectServiceError` when the committed sample is unavailable.
    public func readCommittedSample(name: String) async throws -> CommittedSample {
        let store = try requireStore()
        do {
            return try await store.readCommittedSample(name: name)
        } catch {
            throw projectFailure(error)
        }
    }
}
