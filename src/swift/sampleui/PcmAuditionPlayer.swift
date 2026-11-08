import Foundation
import PorydawAppAudio
import PorydawPlayback

@MainActor
public final class PcmAuditionPlayer {
    public enum RepeatPolicy {
        case once
        case repeatSame
        case repeatFresh(() -> SampleAuditionNote?)
    }

    public enum Lifecycle {
        case starting
        case sounding
        case repeatGap
        case ended(SampleAuditionEndReason)
    }

    private struct Active {
        let lease: SampleAuditionLease
        var note: SampleAuditionNote
        var noteID: SampleAuditionNoteID
        let repeatPolicy: RepeatPolicy
    }

    private enum State {
        case idle
        case starting(Active)
        case sounding(Active)
        case repeatGap(Active, remaining: Double)
    }

    private let beginSampleAudition: (@escaping @MainActor (SampleAuditionEvent) -> Void) -> SampleAuditionLease?
    private var state: State = .idle
    private var claimedLease: SampleAuditionLease?
    private var lastTick: ContinuousClock.Instant?

    public var onLifecycle: ((Lifecycle) -> Void)?
    public var onPlayhead: ((Int) -> Void)?
    public var playing: Bool {
        if case .idle = state { return false }
        return true
    }

    public var canRepublish: Bool {
        switch state {
        case .starting, .sounding: return true
        case .idle, .repeatGap: return false
        }
    }

    public init(
        beginSampleAudition: @escaping (@escaping @MainActor (SampleAuditionEvent) -> Void) -> SampleAuditionLease?
    ) {
        self.beginSampleAudition = beginSampleAudition
    }

    public func claim() -> SampleAuditionLease? {
        stop()
        let lease = beginSampleAudition { [weak self] (event: SampleAuditionEvent) in
            self?.receive(event)
        }
        claimedLease = lease
        return lease
    }

    public func play(_ note: SampleAuditionNote, lease: SampleAuditionLease? = nil, repeatPolicy: RepeatPolicy) {
        guard let lease = lease ?? claim(), lease.isCurrent else { return }
        claimedLease = nil
        let id = lease.play { (id: SampleAuditionNoteID) -> SampleAuditionNote in
            var next = note
            next.id = id
            return next
        }
        state = .starting(Active(lease: lease, note: note, noteID: id, repeatPolicy: repeatPolicy))
        lastTick = ContinuousClock.now
        onLifecycle?(.starting)
    }

    public func republish(_ note: SampleAuditionNote) {
        let active: Active
        switch state {
        case .starting(let current), .sounding(let current): active = current
        case .idle, .repeatGap: return
        }
        guard active.lease.isCurrent else { return }
        play(note, lease: active.lease, repeatPolicy: active.repeatPolicy)
    }

    public func stop() {
        switch state {
        case .idle: claimedLease?.stop()
        case .starting(let active), .sounding(let active), .repeatGap(let active, _): active.lease.stop()
        }
    }

    public func close() { stop() }

    public func tick() {
        let now = ContinuousClock.now
        defer { lastTick = now }
        if case .sounding(let active) = state, let frame = active.lease.soundingFrame {
            onPlayhead?(frame)
        }
        guard let lastTick else { return }
        let elapsed = lastTick.duration(to: now)
        advance(bySeconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }

    public func advance(bySeconds dt: Double) {
        guard dt.isFinite, dt >= 0, case .repeatGap(let active, let remaining) = state else { return }
        guard active.lease.isCurrent else { return }
        let next = remaining - dt
        guard next <= 0 else {
            state = .repeatGap(active, remaining: next)
            return
        }
        let note: SampleAuditionNote?
        switch active.repeatPolicy {
        case .once: note = nil
        case .repeatSame: note = active.note
        case .repeatFresh(let fresh): note = fresh()
        }
        guard let note else { active.lease.stop(); return }
        play(note, lease: active.lease, repeatPolicy: active.repeatPolicy)
    }

    private func receive(_ event: SampleAuditionEvent) {
        switch event {
        case .started(let id):
            guard case .starting(let active) = state, active.noteID == id else { return }
            state = .sounding(active)
            onLifecycle?(.sounding)
        case .finished(let id):
            guard case .sounding(let active) = state, active.noteID == id else { return }
            switch active.repeatPolicy {
            case .once:
                active.lease.stop()
            case .repeatSame, .repeatFresh:
                state = .repeatGap(active, remaining: 0.5)
                lastTick = ContinuousClock.now
                onLifecycle?(.repeatGap)
            }
        case .ended(let reason):
            state = .idle
            claimedLease = nil
            lastTick = nil
            onLifecycle?(.ended(reason))
        }
    }
}
