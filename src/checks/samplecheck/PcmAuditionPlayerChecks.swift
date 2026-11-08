import PorydawAppAudio
import PorydawPlayback
import PorydawSampleUI
import Synchronization

@testable import SwiftCoreCheckLogic

private final class SampleAuditionCheckCommands: Sendable {
    private let pending = Mutex<[SampleAuditionCommand]>([])

    func append(_ command: SampleAuditionCommand) {
        pending.withLock { (commands: inout [SampleAuditionCommand]) in commands.append(command) }
    }

    func drain() -> [SampleAuditionCommand] {
        pending.withLock { (commands: inout [SampleAuditionCommand]) -> [SampleAuditionCommand] in
            let result = commands
            commands.removeAll()
            return result
        }
    }
}

@MainActor
internal final class SampleAuditionCheckOutput {
    private let commands = SampleAuditionCheckCommands()
    let feedback: SampleAuditionFeedbackCell
    let status: SampleAuditionStatus
    private(set) var current: SampleAuditionLease?
    private var nextLease: UInt64 = 0
    var available = true
    init() {
        let feedback = SampleAuditionFeedbackCell()
        self.feedback = feedback
        status = SampleAuditionStatus(feedback: feedback)
    }

    func begin(_ onEvent: @escaping @MainActor (SampleAuditionEvent) -> Void) -> SampleAuditionLease? {
        guard available else { return nil }
        nextLease += 1
        let commands = self.commands
        let lease = SampleAuditionLease(
            id: nextLease, status: status,
            submit: { (command: SampleAuditionCommand) in
                commands.append(command)
            }, onEvent: onEvent)
        let previous = current
        current = lease
        commands.append(.begin(lease.id))
        previous?.end(.displaced)
        return lease
    }

    func drain() -> [SampleAuditionCommand] { commands.drain() }

    func lastNote() -> SampleAuditionNote? {
        drain().compactMap { (command: SampleAuditionCommand) -> SampleAuditionNote? in
            if case let .play(_, note) = command { return note }
            return nil
        }.last
    }

    func start(_ note: SampleAuditionNote, frame: Int = 0) {
        guard let current else { return }
        let generation = note.id.rawValue
        status.publish(lease: current.id, note: note.id, generation: generation)
        feedback.publish(
            adoptedGeneration: generation, finishedGeneration: 0, resetGeneration: 0,
            resetPublicationGeneration: 0, soundingGeneration: generation, soundingFrame: frame)
        current.deliver(.started(note.id))
    }

    func finish(_ note: SampleAuditionNote) {
        current?.deliver(.finished(note.id))
    }
}

@MainActor
internal func runPcmAuditionPlayerChecks(_ report: CheckReport) {
    let scope = report.scoped(cppID: "swiftcore/PcmAuditionPlayer::busyRetry")
    let output = SampleAuditionCheckOutput()
    let player = PcmAuditionPlayer(beginSampleAudition: output.begin)
    defer { player.close() }
    let note = SampleAuditionNote(
        id: .unassigned, source: .pcm(samples: [0, 64, -64, 0], frequency: 8192 * 1024, loopStart: 0, looped: false),
        key: 60, adsr: AudioADSR(), toneKey: 60)
    var lifecycle: [String] = []
    player.onLifecycle = { (state: PcmAuditionPlayer.Lifecycle) in
        switch state {
        case .starting: lifecycle.append("starting")
        case .sounding: lifecycle.append("sounding")
        case .repeatGap: lifecycle.append("gap")
        case .ended: lifecycle.append("ended")
        }
    }
    var frames: [Int] = []
    player.onPlayhead = { (frame: Int) in frames.append(frame) }
    player.play(note, repeatPolicy: .repeatSame)
    guard let first = output.lastNote() else {
        scope.expect(false, message: "a requested note is submitted through its lease")
        return
    }
    scope.expect(player.playing && lifecycle == ["starting"], message: "play waits for engine adoption")
    player.advance(bySeconds: 10)
    scope.expect(lifecycle == ["starting"] && frames.isEmpty, message: "time cannot fabricate adoption or playhead")
    output.start(first, frame: 3)
    player.tick()
    scope.expect(
        lifecycle == ["starting", "sounding"] && frames.last == 3,
        message: "adoption and engine frame drive presentation")
    output.finish(first)
    scope.expect(lifecycle.last == "gap" && player.playing, message: "natural finish enters repeat gap")
    player.advance(bySeconds: 0.49)
    scope.expect(
        output.lastNote().map { (_: SampleAuditionNote) -> Bool in true } != true,
        message: "repeat does not start before the half-second gap")
    player.advance(bySeconds: 0.02)
    guard let repeated = output.lastNote() else {
        scope.expect(false, message: "repeat submits the same source after the gap")
        return
    }
    scope.expect(repeated.id != first.id, message: "repeat mints a fresh note identity")
    if case let .pcm(samples, frequency, loopStart, looped) = repeated.source {
        scope.expect(
            samples == [0, 64, -64, 0] && frequency == 8192 * 1024 && loopStart == 0 && !looped
                && repeated.key == first.key && repeated.toneKey == first.toneKey,
            message: "repeat-same preserves the source and pitch")
    } else {
        scope.expect(false, message: "repeat-same preserves the PCM source")
    }
    output.current?.deliver(.started(first.id))
    scope.expect(lifecycle.last == "starting", message: "stale adoption cannot start the replacement")
    output.start(repeated, frame: 2)
    player.tick()
    scope.expect(frames.last == 2, message: "replacement playhead follows its own engine identity")
    let successor = output.begin { (_: SampleAuditionEvent) in }
    scope.expect(
        !player.playing && lifecycle.last == "ended" && successor?.isCurrent == true,
        message: "displacement ends the old player without stopping the successor")
    player.stop()
    scope.expect(successor?.isCurrent == true, message: "stopping a displaced player cannot stop its successor")
    var freshCount = 0
    player.play(
        note,
        repeatPolicy: .repeatFresh { () -> SampleAuditionNote? in
            freshCount += 1
            var refreshed = note
            refreshed.key = 61
            return refreshed
        })
    guard let original = output.lastNote() else {
        scope.expect(false, message: "fresh-repeat player submits its initial note")
        return
    }
    output.start(original)
    output.finish(original)
    player.advance(bySeconds: 0.51)
    guard let fresh = output.lastNote() else {
        scope.expect(false, message: "fresh-repeat player submits the provider's new note")
        return
    }
    scope.expect(
        freshCount == 1 && fresh.key == 61 && fresh.id != original.id,
        message: "fresh repeat requests and publishes new content after the gap")
    output.current?.deliver(.ended(.engineReset))
    scope.expect(!player.playing && lifecycle.last == "ended", message: "engine reset terminates the active player")
    player.play(note, repeatPolicy: .once)
    guard let oneShot = output.lastNote() else {
        scope.expect(false, message: "one-shot submits its note")
        return
    }
    output.start(oneShot)
    output.finish(oneShot)
    player.advance(bySeconds: 1)
    scope.expect(
        !player.playing && output.lastNote().map { (_: SampleAuditionNote) -> Bool in true } != true,
        message: "one-shot finishes without an automatic repeat")
    output.available = false
    player.play(note, repeatPolicy: .once)
    scope.expect(!player.playing, message: "unavailable output cannot start playback")
}