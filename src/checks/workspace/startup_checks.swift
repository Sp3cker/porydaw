import Foundation
import PorydawCore
import PorydawPlaybackNative

@testable import PorydawApp

/// Builds the real device, then holds its owner before the session can adopt it.
@MainActor
private final class StartupAudioGate {
    private(set) var calls = 0
    private(set) var wasCancelled = false
    private(set) weak var owner: NativeAudio?
    private var constructionResult: Result<Void, Error>?
    private var constructionWaiter: CheckedContinuation<Void, Error>?
    private var publicationWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func makeAudio(honoringCancellation: Bool = false) async throws -> NativeAudio {
        calls += 1
        let audio: NativeAudio
        do {
            audio = try await NativeAudio()
        } catch {
            constructionResult = .failure(error)
            constructionWaiter?.resume(throwing: error)
            constructionWaiter = nil
            throw error
        }
        owner = audio
        constructionResult = .success(())
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                publicationWaiters.append(continuation)
            }
            constructionWaiter?.resume()
            constructionWaiter = nil
        }
        wasCancelled = Task.isCancelled
        if honoringCancellation { try Task.checkCancellation() }
        return audio
    }

    func waitUntilConstructed() async throws {
        if let constructionResult { return try constructionResult.get() }
        try await withCheckedThrowingContinuation { constructionWaiter = $0 }
    }

    func release() {
        released = true
        for waiter in publicationWaiters { waiter.resume() }
        publicationWaiters.removeAll()
    }
}

@MainActor
private final class StartupAudioFailureProbe {
    private(set) var attempts = 0

    func make(failure: Error) async throws -> NativeAudio {
        attempts += 1
        throw failure
    }
}

@MainActor
internal func runWorkspaceStartupChecks(_ report: CheckReport) {
    startupSingleFlightConsumers(report)
    startupPendingEngineSettings(report)
    startupPreparationFailureRetainsCause(report)
    startupClosingWaitsForPreparation(report)
}

@MainActor
private func startupSingleFlightConsumers(_ report: CheckReport) {
    let id = "swiftcore/ApplicationSession::singleFlightAudioConsumers"
    let session = ApplicationSession()
    let gate = StartupAudioGate()
    session.audioFactory = { try await gate.makeAudio() }
    defer {
        session.hostClosing()
        gate.release()
        do {
            try runBlocking { await session.audioPreparationSettled() }
        } catch {
            report.fail(id, "audio preparation cleanup did not settle: \(error)")
        }
        session.acknowledgeGridDetached()
    }
    do {
        try runBlocking {
            await session.audioPreparationSettled()
            report.expectEqual(
                expected: 0, actual: gate.calls, cppID: id,
                what: "waiting for idle preparation does not start a device")
            var consumersStarted = 0
            let first = Task { @MainActor in
                consumersStarted += 1
                return await session.preparedAudio()
            }
            let peer = Task { @MainActor in
                consumersStarted += 1
                return await session.preparedAudio()
            }
            let cancelled = Task { @MainActor in
                consumersStarted += 1
                return await session.preparedAudio()
            }
            defer {
                first.cancel()
                peer.cancel()
                cancelled.cancel()
                gate.release()
            }
            while consumersStarted < 3 { await Task.yield() }
            try await gate.waitUntilConstructed()
            session.prepareAudio()
            session.prepareAudio()
            cancelled.cancel()
            report.expect(
                session.audio == nil && session.transportAudio == nil,
                cppID: id, message: "consumers cannot observe a held, unadopted audio owner")
            gate.release()
            let firstAudio = await first.value
            let peerAudio = await peer.value
            let cancelledAudio = await cancelled.value
            guard let firstAudio, let peerAudio else {
                report.fail(
                    id, "uncancelled consumers did not receive the real prepared audio: \(session.lastSaveError)")
                return
            }
            report.expect(
                firstAudio === peerAudio && firstAudio === gate.owner
                    && firstAudio === session.transportAudio,
                cppID: id, message: "concurrent consumers receive the same adopted real device")
            report.expect(
                cancelledAudio == nil, cppID: id,
                message: "cancelling one waiting consumer does not cancel its peers' preparation")
            session.prepareAudio()
            let readyAudio = await session.preparedAudio()
            report.expect(
                readyAudio === firstAudio && gate.calls == 1,
                cppID: id, message: "pending and ready preparation requests initialize exactly one device")
        }
    } catch {
        report.fail(id, "single-flight audio scenario failed: \(error)")
    }
}

@MainActor
private func startupPendingEngineSettings(_ report: CheckReport) {
    let id = "swiftcore/ApplicationSession::pendingEngineSettings"
    let session = ApplicationSession()
    let gate = StartupAudioGate()
    session.audioFactory = { try await gate.makeAudio() }
    defer {
        session.hostClosing()
        gate.release()
        do {
            try runBlocking { await session.audioPreparationSettled() }
        } catch {
            report.fail(id, "audio preparation cleanup did not settle: \(error)")
        }
        session.acknowledgeGridDetached()
    }
    do {
        try runBlocking {
            session.prepareAudio()
            try await gate.waitUntilConstructed()
            session.setEngineSettings(
                EngineSettings(
                    mixer: "sappy", maxPcmChannels: "8",
                    mixRate: "21024", analogFilter: "true"))
            session.polyphony.setInvertChecked(checked: true)
            session.polyphony.setVisible(showing: true)
            gate.release()
            guard let audio = await session.preparedAudio() else {
                report.fail(id, "pending settings lost their real audio owner: \(session.lastSaveError)")
                return
            }
            let settings = audio.songSettings(for: SongConfig(masterVolume: 83, reverb: 17))
            report.expect(
                settings.pcmMixer == M4A_PCM_MIXER_SAPPY
                    && settings.maxPcmChannels == 8 && settings.pcmMixRate == 21_024
                    && settings.analogFilter,
                cppID: id,
                message: "engine settings changed during preparation reach the native owner's first song settings")
            report.expect(
                audio.polyDebugInvert && session.polyphony.invertChecked,
                cppID: id,
                message: "visible checked polyphony requested before readiness inverts the real engine on adoption")
        }
    } catch {
        report.fail(id, "pending engine settings scenario failed: \(error)")
    }
}

@MainActor
private func startupClosingWaitsForPreparation(_ report: CheckReport) {
    for honoringCancellation in [false, true] {
        let id =
            honoringCancellation
            ? "swiftcore/ApplicationSession::cancelledPreparationDoesNotPublishError"
            : "swiftcore/ApplicationSession::lateAudioOwnerDiscarded"
        let session = ApplicationSession()
        let gate = StartupAudioGate()
        session.audioFactory = { try await gate.makeAudio(honoringCancellation: honoringCancellation) }
        defer {
            session.hostClosing()
            gate.release()
            do {
                try runBlocking { await session.audioPreparationSettled() }
            } catch {
                report.fail(id, "audio preparation cleanup did not settle: \(error)")
            }
            session.acknowledgeGridDetached()
        }
        do {
            try runBlocking {
                var consumerStarted = false
                let consumer = Task { @MainActor in
                    consumerStarted = true
                    return await session.preparedAudio()
                }
                defer {
                    consumer.cancel()
                    gate.release()
                }
                while !consumerStarted { await Task.yield() }
                try await gate.waitUntilConstructed()
                session.hostClosing()
                session.acknowledgeGridDetached()
                var settlementStarted = false
                var didSettle = false
                let settlement = Task { @MainActor in
                    settlementStarted = true
                    await session.audioPreparationSettled()
                    didSettle = true
                }
                defer { settlement.cancel() }
                while !settlementStarted { await Task.yield() }
                report.expect(
                    !didSettle && gate.owner != nil,
                    cppID: id, message: "closing waits while real device construction still owns an unpublished result")
                let disposedAudio = await session.preparedAudio()
                report.expect(
                    disposedAudio == nil && gate.calls == 1,
                    cppID: id, message: "a disposed session refuses new consumers without starting another device")
                gate.release()
                await settlement.value
                let lateAudio = await consumer.value
                report.expect(
                    gate.wasCancelled, cppID: id,
                    message:
                        "host closing cancels the shared real-device preparation before its late result is published")
                report.expect(
                    didSettle && lateAudio == nil && session.audio == nil
                        && session.transportAudio == nil && session.lastSaveError.isEmpty,
                    cppID: id,
                    message:
                        "settlement discards late success or cancellation without publishing audio, readiness or an error"
                )
                report.expect(
                    gate.owner == nil, cppID: id,
                    message: "the discarded real audio owner deallocates when preparation settles")
            }
        } catch {
            report.fail(id, "close-during-preparation scenario failed: \(error)")
        }
    }
}

@MainActor
private func startupPreparationFailureRetainsCause(_ report: CheckReport) {
    let id = "swiftcore/ApplicationSession::preparationFailureRetainsCause"
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(id, "missing project fixture root")
        return
    }
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-startup-audio-failure")
    let session = ApplicationSession()
    let failure = NativeAudioError.initializationFailed("The audio backend rejected device preparation.")
    let probe = StartupAudioFailureProbe()
    session.audioFactory = { try await probe.make(failure: failure) }
    defer {
        session.hostClosing()
        session.acknowledgeGridDetached()
    }
    session.openProjectAndSong(path: root, label: "mus_session_test")
    let deadline = Date().addingTimeInterval(25)
    while !session.projectOpen && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    guard session.projectOpen, let opening = session.activeReplacementTask else {
        report.fail(id, "the real project did not reach its song-open consumer")
        return
    }
    do {
        try runBlocking {
            await opening.value
            report.expect(
                !session.songOpen && session.audio == nil && session.transportAudio == nil,
                cppID: id, message: "failed preparation cannot install an audio owner or open a song")
            report.expectEqual(
                expected: String(describing: failure), actual: session.lastSaveError,
                cppID: id, what: "the song-open failure keeps its preparation cause instead of a generic fallback")
            await session.openTab(label: "mus_session_test", at: nil)
            report.expectEqual(
                expected: 1, actual: await probe.attempts, cppID: id,
                what: "a second song-open consumer does not restart terminally failed preparation")
            report.expectEqual(
                expected: String(describing: failure), actual: session.lastSaveError,
                cppID: id, what: "a later consumer retains the same device failure")
        }
    } catch {
        report.fail(id, "preparation-failure scenario failed: \(error)")
    }
}
