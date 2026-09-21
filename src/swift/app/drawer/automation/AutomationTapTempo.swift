import Foundation
import PorydawCore

// Tap-tempo fixed-ring state, monotonic timing policy, and event-boundary clock.

/// The tap-tempo session, exactly the production `TapTempoSession`
/// (`src/ui/editordrawer/taptempo.h`): a fixed interval ring, a clipped mean of
/// the newest intervals, and the idle-commit window scaled to the tapped tempo.
/// Pure state — the monotonic reading arrives per tap and nothing here allocates
/// beyond the fixed ring.
public struct AutomationTapTempoSession: Equatable, Sendable {
    /// A tap becomes tap one after this idle gap; that distance only decides
    /// session boundaries.
    public static let gapMs = 2000
    public static let commitMinimumMs = 600
    public static let commitMaximumMs = gapMs
    /// The commit lands after this many tapped beats' worth of silence.
    public static let commitBeats = 1.5
    /// The rounded mean covers the newest intervals in this window.
    public static let window = 8
    /// Two taps have one interval, which already yields a rounded draft.
    public static let minimumTaps = 2

    private var intervals = [Int64](repeating: 0, count: AutomationTapTempoSession.window)
    private var head = 0
    private var lastMs: Int64 = 0
    public private(set) var tapCount = 0
    public private(set) var draftBpm = 0

    public init() {}

    /// One tap at a caller-supplied monotonic millisecond reading. The first tap
    /// of a session (or a tap past the gap distance) starts a session and
    /// produces no draft; every later tap recomputes the draft from the clipped
    /// mean of the newest intervals.
    public mutating func registerTap(nowMs: Int64) {
        let gap = nowMs - lastMs
        if tapCount == 0 || gap > Int64(Self.gapMs) {
            self = AutomationTapTempoSession()
            lastMs = nowMs
            tapCount = 1
            return
        }
        intervals[head] = gap
        head = (head + 1) % Self.window
        lastMs = nowMs
        tapCount += 1
        let used = min(tapCount - 1, Self.window)
        var sum: Int64 = 0
        for index in 0..<used {
            sum += intervals[(head + Self.window - 1 - index) % Self.window]
        }
        draftBpm = Self.bpm(forMeanIntervalMs: sum / Int64(used))
    }

    public mutating func reset() { self = AutomationTapTempoSession() }

    public var readyToCommit: Bool { tapCount >= Self.minimumTaps }

    /// The idle silence that lands the current draft: ~1.5 tapped beats' worth of
    /// time, clamped, and never past the gap distance, so a slow next tap can
    /// never read as a fresh session and silently drop the pending draft.
    public var idleCommitMs: Int {
        guard draftBpm > 0 else { return Self.gapMs }
        let exact = (Self.commitBeats * 60_000.0 / Double(draftBpm)).rounded()
        return min(max(Int(exact), Self.commitMinimumMs), Self.commitMaximumMs)
    }

    /// `TapTempoSession::bpmForMeanIntervalNs`, in milliseconds.
    public static func bpm(forMeanIntervalMs meanMs: Int64) -> Int {
        guard meanMs > 0 else { return TimeDefaults.maximumTempoBPM }
        let exact = (60_000.0 / Double(meanMs)).rounded()
        return min(max(Int(exact), TimeDefaults.minimumTempoBPM), TimeDefaults.maximumTempoBPM)
    }
}

/// The tap-tempo session's only clock: a monotonic reading taken at a tap's own
/// event boundary. It measures tapped intervals alone and is never a playback
/// position, so it starts no second playhead clock.
final class AutomationMonotonicClock {
    private let origin = DispatchTime.now().uptimeNanoseconds

    var milliseconds: Int64 {
        Int64((DispatchTime.now().uptimeNanoseconds &- origin) / 1_000_000)
    }
}

@MainActor
extension AutomationPage {
    func registerTapTempoEvent() {
        registerTapTempoEvent(atMilliseconds: tapClock.milliseconds)
    }

    func registerTapTempoEvent(atMilliseconds nowMs: Int64) {
        guard let session else {
            resetTapTempo()
            return
        }
        if tapGuard == nil { tapGuard = (session.document.revision, activeParameter) }
        guard tapGuard?.revision == session.document.revision,
              tapGuard?.parameter == activeParameter else {
            resetTapTempo()
            return
        }
        tapSession.registerTap(nowMs: nowMs)
        publishTapTempo()
        publishInteractionState()
    }

    func commitTapTempoAfterIdle() -> Bool {
        guard let session, tapSession.readyToCommit,
              let guardValue = tapGuard,
              guardValue.revision == session.document.revision,
              guardValue.parameter == activeParameter else {
            resetTapTempo()
            return false
        }
        let target = TimeDefaults.microsecondsPerQuarterNote(forBPM: tapSession.draftBpm)
        let existing = session.document.state.tempo.first { $0.tick == 0 }
        resetTapTempo()
        guard existing?.microsecondsPerQuarterNote != target else { return false }
        // One `SongDocument.editTempo` call per session: the draft replaces the
        // tick-zero point and nothing else in the stream moves.
        session.document.editTempo(TempoEdit(
            remove: session.document.state.tempo.filter { $0.tick == 0 },
            add: [TempoPoint(tick: 0, microsecondsPerQuarterNote: target)]))
        refreshFromDocument()
        return true
    }

    func clearTapTempoSession() {
        guard tapGuard != nil || tapSession.tapCount != 0 else { return }
        tapSession.reset()
        tapGuard = nil
        publishTapTempo()
        publishInteractionState()
    }
}
