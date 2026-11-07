import Foundation
import PorydawAppAudio
import PorydawPlaybackNative
import PorydawSample

@testable import PorydawPlayback
@testable import PorydawSampleUI
@testable import SwiftCoreCheckLogic

#if canImport(Darwin)
    import Darwin
    import Synchronization
#endif

/// Gates actual native preparation, including cancellation, without sleeps or scheduler polling.
private actor ControlledPcmPreparation {
    private var inputs: [[Int8]] = []
    private var completions: [Int: CheckedContinuation<Void, Never>] = [:]
    private var observers: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func prepare(_ samples: [Int8]) async -> sending SampleAuditionPcm? {
        let index = inputs.count
        inputs.append(samples)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            completions[index] = continuation
            for count in Array(observers.keys) where count <= inputs.count {
                for observer in observers.removeValue(forKey: count) ?? [] { observer.resume() }
            }
        }
        return await SampleAuditionPcm.prepare(samples: samples)
    }

    func started(_ count: Int) async {
        guard inputs.count < count else { return }
        await withCheckedContinuation { observers[count, default: []].append($0) }
    }

    func complete(_ index: Int) {
        guard let continuation = completions.removeValue(forKey: index) else {
            preconditionFailure("Preparation must start before completing")
        }
        continuation.resume()
    }

    func preparedInputs() -> [[Int8]] { inputs }
}

@MainActor
private final class PlayerCheckOutput: SampleAuditionOutput {
    struct Publication {
        let request: UInt64
        let pcm: SampleAuditionPcm
        let frequency: UInt32
        let loopStart: UInt32
        let looped: Bool
        let key: UInt8
        let adsr: AudioADSR
        let toneKey: UInt8
    }

    let renderer: AudioRenderEngine
    private(set) var reservations: [UInt64] = []
    private(set) var attempts: [UInt64] = []
    private(set) var publications: [Publication] = []

    init() throws { renderer = try AudioRenderEngine(sampleRate: 48_000, periodFrames: 512) }

    func beginSampleRequest() -> UInt64 {
        let request = renderer.beginSampleRequest()
        reservations.append(request)
        return request
    }

    func sampleRequestIsCurrent(_ request: UInt64) -> Bool { renderer.sampleRequestIsCurrent(request) }

    func auditionSample(
        request: UInt64, pcm: SampleAuditionPcm, frequency: UInt32, loopStart: UInt32,
        looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) -> Bool {
        attempts.append(request)
        guard
            renderer.auditionSample(
                request: request, pcm: pcm, frequency: frequency, loopStart: loopStart,
                looped: looped, key: key, adsr: adsr, toneKey: toneKey)
        else { return false }
        publications.append(
            Publication(
                request: request, pcm: pcm, frequency: frequency, loopStart: loopStart,
                looped: looped, key: key, adsr: adsr, toneKey: toneKey))
        return true
    }

    func auditionSampleOff(request: UInt64) { renderer.auditionSampleOff(request: request) }

    func render() -> [Float] {
        var samples = [Float](repeating: 0, count: 8192)
        samples.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { preconditionFailure("Positive render buffer") }
            renderer.render(base, frames: 4096)
        }
        return samples
    }
}

private final class PlayerCheckOwner {}

private func playerCheckSample(_ value: Int8) -> ProcessedSample {
    var sample = ProcessedSample()
    sample.s8 = (0..<512).map { (index: Int) -> Int8 in index % 32 < 16 ? value : -value }
    sample.freq = 8192 * 1024
    sample.looped = true
    sample.loopStart = 32
    return sample
}

@MainActor
private func checkLatestPlayerPreparation(_ report: CheckReport) async throws {
    let scope = report.scoped(cppID: "swiftcore/PcmAuditionPlayer::latestPreparation")
    let output = try PlayerCheckOutput()
    defer { output.renderer.unload() }
    let gate = ControlledPcmPreparation()
    let player = PcmAuditionPlayer(lane: SampleAuditionArbiter(output: output), prepare: { await gate.prepare($0) })
    defer { player.close() }
    let owner = PlayerCheckOwner()
    let first = playerCheckSample(40)
    let skipped = playerCheckSample(50)
    var newest = playerCheckSample(60)
    player.play(owner: owner, rendered: first, looped: true, key: 60, adsr: AudioADSR(), toneKey: 60)
    await gate.started(1)
    player.play(owner: owner, rendered: skipped, looped: true, key: 61, adsr: AudioADSR(), toneKey: 60)
    player.play(owner: owner, rendered: newest, looped: true, key: 62, adsr: AudioADSR(), toneKey: 60)
    let runningInputs = await gate.preparedInputs()
    scope.expect(
        runningInputs == [first.s8], message: "only one preparation runs while newest content replaces pending work")
    await gate.complete(0)
    await gate.started(2)
    let revision = newest.pcmRevision
    newest.freq = 10_000 * 1024
    newest.loopStart = 64
    let envelope = AudioADSR(attack: 240, decay: 12, sustain: 180, release: 0)
    player.play(owner: owner, rendered: newest, looped: false, key: 69, adsr: envelope, toneKey: 57)
    await gate.complete(1)
    await player.preparationSettled()
    let inputs = await gate.preparedInputs()
    scope.expect(
        inputs == [first.s8, newest.s8] && newest.pcmRevision == revision,
        message: "obsolete content is skipped and same-revision metadata never reparses native PCM")
    guard let published = output.publications.last else {
        scope.expect(false, message: "newest prepared content publishes")
        return
    }
    scope.expect(
        output.publications.count == 1 && published.key == 69 && published.toneKey == 57
            && published.frequency == newest.freq && published.loopStart == 64 && !published.looped
            && published.adsr.attack == 240 && published.adsr.decay == 12
            && published.adsr.sustain == 180 && published.adsr.release == 0,
        message: "the running preparation commits only the latest note, envelope and playback metadata")
    scope.expect(
        published.pcm.count == newest.s8.count && published.pcm.data[0] == newest.s8[0],
        message: "the player publishes the newest content's actual native bytes")
    scope.expect(
        output.render().contains { abs($0) > 0.01 }, message: "latest prepared player publication renders native audio")
    player.stop(owner: owner)
    player.play(owner: owner, rendered: newest, looped: true, key: 60, adsr: AudioADSR(), toneKey: 60)
    scope.expect(
        output.publications.last?.pcm === published.pcm,
        message: "stop/listen and note changes reuse the same native allocation synchronously")
    await player.preparationSettled()
    let reusedInputs = await gate.preparedInputs()
    scope.expect(reusedInputs == inputs, message: "warm stop/listen starts no additional preparation")
}

@MainActor
private func checkStoppedPlayerPreparation(_ report: CheckReport) async throws {
    let scope = report.scoped(cppID: "swiftcore/PcmAuditionPlayer::stoppedPreparation")
    for close in [false, true] {
        let output = try PlayerCheckOutput()
        defer { output.renderer.unload() }
        let gate = ControlledPcmPreparation()
        let player = PcmAuditionPlayer(lane: SampleAuditionArbiter(output: output), prepare: { await gate.prepare($0) })
        let owner = PlayerCheckOwner()
        var terminatedWhileStopped = false
        player.onTerminated = { terminatedWhileStopped = !player.playing }
        player.play(
            owner: owner, rendered: playerCheckSample(64), looped: true, key: 60, adsr: AudioADSR(), toneKey: 60)
        await gate.started(1)
        if close { player.close() } else { player.stop(owner: owner) }
        await gate.complete(0)
        await player.preparationSettled()
        scope.expect(
            terminatedWhileStopped && !player.playing && output.attempts.isEmpty
                && output.render().allSatisfy { abs($0) <= 1e-7 },
            message: "\(close ? "close" : "stop") during running preparation cannot revive or publish late")
        player.onTerminated = nil
        player.close()
    }
}

@MainActor
private func checkSharedOutputPlayerDisplacement(_ report: CheckReport) async throws {
    let scope = report.scoped(cppID: "swiftcore/PcmAuditionPlayer::sharedOutputDisplacement")
    let output = try PlayerCheckOutput()
    defer { output.renderer.unload() }
    let gate = ControlledPcmPreparation()
    let lane = SampleAuditionArbiter(output: output)
    let player = PcmAuditionPlayer(lane: lane, prepare: { await gate.prepare($0) })
    defer { player.close() }
    let owner = PlayerCheckOwner()
    let sample = playerCheckSample(64)
    var terminatedWhileStopped = false
    player.onTerminated = {
        terminatedWhileStopped = !player.playing
        player.stop(owner: owner)
    }
    player.play(owner: owner, rendered: sample, looped: true, key: 60, adsr: AudioADSR(), toneKey: 60)
    await gate.started(1)
    let picker = output.beginSampleRequest()
    guard let pickerPcm = await SampleAuditionPcm.prepare(samples: sample.s8) else {
        scope.expect(false, message: "picker native PCM prepares")
        return
    }
    scope.expect(
        output.auditionSample(
            request: picker, pcm: pickerPcm, frequency: sample.freq, loopStart: sample.loopStart,
            looped: true, key: 67, adsr: AudioADSR(), toneKey: 60),
        message: "picker publication claims the same native output while studio preparation runs")
    player.tick()
    await gate.complete(0)
    await player.preparationSettled()
    scope.expect(
        terminatedWhileStopped && !player.playing && output.publications.count == 1
            && output.sampleRequestIsCurrent(picker) && output.render().contains { abs($0) > 0.01 },
        message: "displaced cold studio completion and reentrant Stop leave the newer picker audible")

    let pickerGate = ControlledPcmPreparation()
    let obsoletePicker = output.beginSampleRequest()
    let lookup = Task { @MainActor in
        guard let pcm = await pickerGate.prepare(sample.s8), output.sampleRequestIsCurrent(obsoletePicker) else {
            return
        }
        _ = output.auditionSample(
            request: obsoletePicker, pcm: pcm, frequency: sample.freq, loopStart: sample.loopStart,
            looped: true, key: 72, adsr: AudioADSR(), toneKey: 60)
    }
    await pickerGate.started(1)
    player.play(owner: owner, rendered: sample, looped: true, key: 62, adsr: AudioADSR(), toneKey: 60)
    await gate.started(2)
    await gate.complete(1)
    await player.preparationSettled()
    await pickerGate.complete(0)
    await lookup.value
    output.auditionSampleOff(request: obsoletePicker)
    scope.expect(
        player.playing && output.publications.count == 2 && output.publications.last?.key == 62
            && output.render().contains { abs($0) > 0.01 },
        message: "newer studio playback survives late picker completion and stale picker Stop")
    player.onTerminated = nil

    // A separate studio arbiter must share the same producer reservation too.
    let other = PcmAuditionPlayer(lane: SampleAuditionArbiter(output: output))
    let otherOwner = PlayerCheckOwner()
    other.play(owner: otherOwner, rendered: sample, looped: true, key: 65, adsr: AudioADSR(), toneKey: 60)
    await other.preparationSettled()
    player.stop(owner: owner)
    scope.expect(
        other.playing && output.publications.last?.key == 65 && output.render().contains { abs($0) > 0.01 },
        message: "displaced arbiter cannot stop a newer reservation owned by another arbiter")
    other.close()
}

@MainActor
private func checkWarmPlayerRevert(_ report: CheckReport) async throws {
    let scope = report.scoped(cppID: "swiftcore/PcmAuditionPlayer::warmRevert")
    let output = try PlayerCheckOutput()
    defer { output.renderer.unload() }
    let gate = ControlledPcmPreparation()
    let player = PcmAuditionPlayer(lane: SampleAuditionArbiter(output: output), prepare: { await gate.prepare($0) })
    defer { player.close() }
    let owner = PlayerCheckOwner()
    let warm = playerCheckSample(64)
    player.play(owner: owner, rendered: warm, looped: true, key: 60, adsr: AudioADSR(), toneKey: 60)
    await gate.started(1)
    await gate.complete(0)
    await player.preparationSettled()
    let original = output.publications.last?.pcm
    player.play(owner: owner, rendered: playerCheckSample(32), looped: true, key: 61, adsr: AudioADSR(), toneKey: 60)
    await gate.started(2)
    player.play(owner: owner, rendered: warm, looped: true, key: 64, adsr: AudioADSR(), toneKey: 60)
    player.advance(bySeconds: 0.01)
    let position = player.playheadPosition
    let publications = output.publications.count
    await gate.complete(1)
    await player.preparationSettled()
    let inputs = await gate.preparedInputs()
    scope.expect(
        publications == 2 && output.publications.count == publications && output.publications.last?.pcm === original
            && player.playheadPosition == position && position > 0 && inputs.count == 2,
        message: "reverting to warmed content publishes synchronously without a late retrigger or playhead reset")
}

@MainActor
private func checkBusyPlayerRetry(_ report: CheckReport) async throws {
    let scope = report.scoped(cppID: "swiftcore/PcmAuditionPlayer::busySameToken")
    let output = try PlayerCheckOutput()
    defer { output.renderer.unload() }
    let gate = ControlledPcmPreparation()
    let player = PcmAuditionPlayer(lane: SampleAuditionArbiter(output: output), prepare: { await gate.prepare($0) })
    defer { player.close() }
    let owner = PlayerCheckOwner()
    let sample = playerCheckSample(64)
    var restarts = 0
    player.onWillRestart = { restarts += 1 }
    player.play(owner: owner, rendered: sample, looped: false, key: 60, adsr: AudioADSR(), toneKey: 60)
    await gate.started(1)
    await gate.complete(0)
    await player.preparationSettled()
    // No callback adoption: all four native slots remain pending until explicitly rendered.
    for key in UInt8(61)...65 {
        player.play(
            owner: owner, rendered: sample, looped: false, key: key,
            adsr: AudioADSR(attack: 255, decay: 0, sustain: 255, release: 0), toneKey: 60)
    }
    guard let reserved = output.reservations.last else {
        scope.expect(false, message: "player must reserve native output")
        return
    }
    let reservations = output.reservations.count
    scope.expect(
        output.publications.count == 4 && output.sampleRequestIsCurrent(reserved),
        message: "real native slot exhaustion leaves the newest player request reserved")
    player.advance(bySeconds: 0)
    player.advance(bySeconds: 0)
    scope.expect(
        output.reservations.count == reservations && output.attempts.suffix(3).allSatisfy { $0 == reserved }
            && restarts == 0 && output.sampleRequestIsCurrent(reserved),
        message: "native Busy retries reuse their token without invoking fresh-content restart")
    _ = output.render()
    player.advance(bySeconds: 0)
    scope.expect(
        output.publications.count == 5 && output.publications.last?.request == reserved
            && output.publications.last?.key == 65 && output.reservations.count == reservations
            && output.publications.allSatisfy { $0.pcm === output.publications.first?.pcm },
        message: "acknowledged slot retirement accepts the reserved retry with the original native PCM")
    let inputs = await gate.preparedInputs()
    scope.expect(inputs.count == 1, message: "parameter changes and Busy retries do not reprepare PCM")
    player.advance(bySeconds: 10)
    player.advance(bySeconds: 0.51)
    scope.expect(restarts == 1, message: "onWillRestart remains reserved for the automatic one-shot repeat")
}

@MainActor
private func checkNativePlayerTakeovers(_ report: CheckReport) async throws {
    let scope = report.scoped(cppID: "swiftcore/PcmAuditionPlayer::nativeTakeovers")
    for kit in [false, true] {
        let output = try PlayerCheckOutput()
        defer { output.renderer.unload() }
        let gate = ControlledPcmPreparation()
        let player = PcmAuditionPlayer(lane: SampleAuditionArbiter(output: output), prepare: { await gate.prepare($0) })
        defer { player.close() }
        let owner = PlayerCheckOwner()
        let sample = playerCheckSample(64)
        let obsoletePicker = output.beginSampleRequest()
        player.play(owner: owner, rendered: sample, looped: true, key: 60, adsr: AudioADSR(), toneKey: 60)
        await gate.started(1)
        let wave = [UInt8](repeating: 0xFF, count: 8) + [UInt8](repeating: 0, count: 8)
        scope.expect(
            !output.renderer.audition.publishWave(request: obsoletePicker, wave16: wave, key: 60, adsr: AudioADSR()),
            message: "a late picker wave cannot replace a newer studio reservation")
        let takeover = output.beginSampleRequest()
        let accepted: Bool
        if kit {
            let child = KitAuditionTone.Child.sample(
                pcm: sample.s8, frequency: sample.freq, key: 60, panSweep: 0,
                adsr: AudioADSR(), kind: Int(VOICE_DIRECTSOUND), looped: true, loopStart: 32)
            accepted = output.renderer.audition.publishKitTone(
                request: takeover,
                KitAuditionTone(mode: .keysplit, children: [child], splitTable: [UInt8](repeating: 0, count: 128)),
                key: 60)
        } else {
            accepted = output.renderer.audition.publishWave(
                request: takeover, wave16: wave, key: 60,
                adsr: AudioADSR(attack: 0, decay: 0, sustain: 15, release: 0))
        }
        await gate.complete(0)
        await player.preparationSettled()
        player.stop(owner: owner)
        scope.expect(
            accepted && !player.playing && output.publications.isEmpty && output.sampleRequestIsCurrent(takeover),
            message: "\(kit ? "kit" : "wave") takeover rejects late PCM without replacing its own stop token")
        scope.expect(
            output.render().contains { abs($0) > 0.01 }, message: "native takeover remains audible after displaced Stop"
        )
        output.auditionSampleOff(request: takeover)
        _ = output.render()
        scope.expect(
            !output.sampleRequestIsCurrent(takeover),
            message: "the native takeover's original token still owns its Stop")
    }
}

@MainActor
private func checkRetiredToneStorage(_ report: CheckReport) async {
    let scope = report.scoped(cppID: "swiftcore/AudioSampleAudition::retiredToneStorage")
    guard let pcm = await SampleAuditionPcm.prepare(samples: [12, -24, 37]) else {
        scope.expect(false, message: "native PCM guard fixture prepares")
        return
    }
    for kit in [false, true] {
        let slots = AudioSampleAudition()
        let accepted: Bool
        if kit {
            let child = KitAuditionTone.Child.sample(
                pcm: [Int8](repeating: 64, count: 1_048_576), frequency: 8192 * 1024,
                key: 60, panSweep: 0, adsr: AudioADSR(), kind: Int(VOICE_DIRECTSOUND), looped: true, loopStart: 0)
            accepted = slots.publishKitTone(
                KitAuditionTone(mode: .keysplit, children: [child], splitTable: [UInt8](repeating: 0, count: 128)),
                key: 60)
        } else {
            accepted = slots.publish(wave16: [UInt8](repeating: 0x5A, count: 16), key: 60, adsr: AudioADSR())
        }
        weak var retired: SampleAuditionPcm.Allocation?
        retired = slots.retainedBytes[0]
        scope.expect(accepted && retired != nil, message: "retired tone fixture owns its native allocation")
        slots.off()
        slots.reset()  // Parked-engine acknowledgement; no callback may still borrow the old allocation.
        scope.expect(
            slots.publish(
                pcm: pcm, frequency: 8192 * 1024, loopStart: 0,
                looped: false, key: 60, adsr: AudioADSR(), toneKey: 60),
            message: "acknowledged tone slot can be reused for shared PCM")
        await SampleAuditionPcm.Allocation.reclamationSettled()
        scope.expect(
            retired == nil && slots.retainedBytes[0] == nil && pcm.data[pcm.count] == 37,
            message: "\(kit ? "large kit" : "wave") ownership is released on reuse without disturbing shared PCM")
    }
}

#if canImport(Darwin)
    private typealias PcmMallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
    private let pcmReclamationObservation = Mutex((address: UInt(0), freed: false, freedOnMain: false))
    private let pcmMallocLogger: PcmMallocLogger = { type, _, address, _, _, _ in
        guard type & 4 != 0 else { return }
        // No allocating bookkeeping: the allocator invokes this hook for every native free.
        pcmReclamationObservation.withLock { state in
            guard address == state.address && !state.freed else { return }
            state.freed = true
            state.freedOnMain = pthread_main_np() != 0
        }
    }

    @MainActor
    private func checkNativePcmReclamation(_ report: CheckReport) async {
        let cppID = "swiftcore/AudioSampleAudition::nativePcmReclamation"
        // ASAN replaces the system allocator, so its frees do not reach malloc_logger.
        guard dlsym(UnsafeMutableRawPointer(bitPattern: -2), "__asan_init") == nil else {
            report.pass(cppID, row: "native free thread observation skipped under ASAN")
            return
        }
        let scope = report.scoped(cppID: cppID)
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else {
            scope.expect(false, message: "Darwin malloc_logger is available for native reclamation observation")
            return
        }
        let slot = symbol.assumingMemoryBound(to: PcmMallocLogger?.self)
        var pcm = SampleAuditionPcm(samples: [12, -24, 37])
        guard let data = pcm?.data else {
            scope.expect(false, message: "native reclamation fixture prepares")
            return
        }
        pcmReclamationObservation.withLock { state in
            state.address = UInt(bitPattern: data)
            state.freed = false
            state.freedOnMain = false
        }
        let saved = slot.pointee
        slot.pointee = pcmMallocLogger
        defer {
            slot.pointee = saved
            pcmReclamationObservation.withLock { $0.address = 0 }
        }
        // Keep the last owner until after the allocator hook is installed, then drop it on main.
        withExtendedLifetime(pcm) {}
        pcm = nil
        await SampleAuditionPcm.Allocation.reclamationSettled()
        let observation = pcmReclamationObservation.withLock { $0 }
        scope.expect(
            observation.freed && !observation.freedOnMain,
            message: "dropping the last PCM owner on main frees its native bytes off main before drain")
    }
#endif

@MainActor
internal func runPcmAuditionPlayerChecks(_ report: CheckReport) {
    do {
        try runBlocking {
            try await checkLatestPlayerPreparation(report)
            try await checkStoppedPlayerPreparation(report)
            try await checkSharedOutputPlayerDisplacement(report)
            try await checkWarmPlayerRevert(report)
            try await checkBusyPlayerRetry(report)
            try await checkNativePlayerTakeovers(report)
            await checkRetiredToneStorage(report)
            #if canImport(Darwin)
                await checkNativePcmReclamation(report)
            #endif
        }
    } catch {
        report.fail("swiftcore/PcmAuditionPlayer::fixture", "controlled player fixture failed: \(error)")
    }
}
