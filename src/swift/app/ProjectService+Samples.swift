import Foundation
import PorydawProject

extension ProjectService {
    /// Inspects sample-registration prerequisites on the store's owner.
    public func probeSamples() async throws -> SampleRegistrar.Probe {
        _ = try requireStore()
        return SampleRegistrar.probe(projectRoot: projectRoot)
    }

    /// Commits a sample and republishes refreshed banks to every sharing session.
    /// - Parameter request: Sample bytes and whether they replace a registered sample.
    /// - Throws: `ProjectServiceError` when registration or loader refresh fails.
    public func commitSample(_ request: SampleCommitRequest) async throws {
        let store = try requireStore()
        do {
            let leases = try await store.commitSample(request)
            for lease in leases {
                await publish(appliedBank(lease, token: 0), from: store)
            }
        } catch {
            throw projectFailure(error)
        }
    }

    /// Reads a committed sample without changing the current bank.
    /// - Parameter name: Registered sample name.
    /// - Returns: Committed WAV.
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
