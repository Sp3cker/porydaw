import Foundation
import PorydawAppAudio
import PorydawCore
import PorydawDocument
import SwiftCoreCheckSupport

@testable import PorydawApp
@testable import PorydawPluginHost

@MainActor
enum PluginFaultInjector {
    private enum Failure: Error {
        case invalidMode, unavailable, unexpectedSuccess, failureDeadline
        case uncommittedFailure(String)
    }

    private static func state(mode: Int) -> PluginStateBlob {
        // Fixture wire state: four little-endian Int32s, 0 / 128 / 0 / validated fault mode.
        let bytes: [UInt8] = [
            0, 0, 0, 0,
            128, 0, 0, 0,
            0, 0, 0, 0,
            UInt8(mode), 0, 0, 0,
        ]
        return PluginStateBlob(component: bytes, controller: bytes)
    }

    private static func normalizedFailure(_ error: any Error) throws -> PluginHostError {
        if let host = error as? PluginHostError { return host }
        guard let transport = error as? HelperProcessError else { throw error }
        switch transport {
        case .eof, .terminated:
            return .native(transport.description)
        case .stoppedResponding, .timeout:
            return .stoppedResponding(transport.description)
        case .scannerMissing, .channelCreation, .channelUnlink, .invalidPayload, .notReady, .launch, .native:
            throw error
        }
    }

    static func inject(app: ApplicationSession?, track: Int, mode: Int) -> Bool {
        do {
            guard mode == 1 || mode == 2 else { throw Failure.invalidMode }
            guard let app, let workspace = app.workspace,
                let audio = app.transportAudio,
                let id = workspace.session.document.effect(onTrack: track)?.id,
                let instance = workspace.effects.instance(for: id)
            else { throw Failure.unavailable }
            let controller = workspace.effects
            let faultState = state(mode: mode)
            try runBlocking { @MainActor () async throws -> Void in
                let injection = Task { @MainActor () async throws -> Void in
                    try await instance.restore(faultState)
                }
                let stimulus = Task { @MainActor () async throws -> Void in
                    try await injection.value
                    if let failure = instance.failure { throw failure }
                    if controller.isLive(id),
                        audio.requestedTransport == AudioTransportState.playing.rawValue
                            || audio.status.appliedTransport == .playing
                    {
                        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
                        while true {
                            if let failure = instance.failure { throw failure }
                            try Task.checkCancellation()
                            guard ContinuousClock.now < deadline else { throw Failure.failureDeadline }
                            await Task.yield()
                        }
                    }
                    try await controller.render(id, range: TimeRange(startTick: 0, endTick: 24))
                }
                let outcome = await stimulus.result
                _ = await injection.result
                switch outcome {
                case .success:
                    throw Failure.unexpectedSuccess
                case .failure(let error):
                    let committed = try normalizedFailure(error)
                    let reason: String
                    switch (mode, committed) {
                    case (1, .native): reason = "stopped working"
                    case (2, .stoppedResponding): reason = "stopped responding"
                    default: throw error
                    }
                    guard instance.failure == committed, controller.status(id) == .crashed(reason) else {
                        throw Failure.uncommittedFailure(
                            "mode \(mode): \(error); instance \(String(describing: instance.failure)); status \(controller.status(id))"
                        )
                    }
                }
            }
            return true
        } catch {
            FileHandle.standardError.write(Data("MIDI effect fault injection failed: \(error)\n".utf8))
            return false
        }
    }
}
