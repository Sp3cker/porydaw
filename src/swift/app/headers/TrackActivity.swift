import Foundation
import PorydawAppAudio

/// Stereo meter envelope shared by the live header and its deterministic checks.
public struct TrackActivity {
    public struct Intensity: Equatable {
        public var left: Float = 0
        public var right: Float = 0
    }

    private enum Phase { case playing, pausedFilling, resuming }
    private var intensities = Array(repeating: Intensity(), count: 16)
    private var phase = Phase.playing
    private var resumeRemaining: Float = 0

    public init() {}

    public func intensity(track: Int) -> Intensity {
        intensities.indices.contains(track) ? intensities[track] : Intensity()
    }

    public mutating func reset() {
        intensities = Array(repeating: Intensity(), count: 16)
        phase = .playing
        resumeRemaining = 0
    }

    public mutating func resetPaused() {
        intensities = Array(repeating: Intensity(left: 1, right: 1), count: 16)
        phase = .pausedFilling
        resumeRemaining = 0.075
    }

    /// True while an idle poll still needs to advance the meter envelope.
    public var isAnimating: Bool {
        switch phase {
        case .playing:
            return intensities.contains { $0.left > 0 || $0.right > 0 }
        case .pausedFilling:
            return intensities.contains { $0.left < 1 || $0.right < 1 }
        case .resuming:
            return true
        }
    }

    @discardableResult
    public mutating func advance(_ levels: [AudioActivityLevel], elapsedSeconds: Float,
                                 playing: Bool) -> Bool {
        precondition(levels.count == 16)
        let elapsed = max(0, elapsedSeconds)
        if !playing {
            let amount = 1 - exp(-elapsed / 0.250)
            var animating = false
            func fill(_ value: inout Float) {
                value += (1 - value) * amount
                if elapsed > 0 && 1 - value < 0.002 { value = 1 }
                else if value < 1 { animating = true }
            }
            for index in intensities.indices {
                fill(&intensities[index].left)
                fill(&intensities[index].right)
            }
            phase = .pausedFilling
            resumeRemaining = 0.075
            return animating
        }
        if phase == .pausedFilling {
            phase = .resuming
            resumeRemaining = 0.075
        }
        let attack = 1 - exp(-elapsed / 0.015)
        let release = 1 - exp(-elapsed / 0.250)
        let descent = phase == .resuming ? attack : release
        func advanceSide(_ value: inout Float, target: Float) {
            value += (target - value) * (target > value ? attack : descent)
            if elapsed > 0 && target == 0 && value < 0.002 { value = 0 }
        }
        for index in intensities.indices {
            advanceSide(&intensities[index].left, target: Float(levels[index].left) / 255)
            advanceSide(&intensities[index].right, target: Float(levels[index].right) / 255)
        }
        if phase == .resuming {
            resumeRemaining = max(0, resumeRemaining - elapsed)
            if resumeRemaining == 0 { phase = .playing }
        }
        return true
    }

    public static func physicalHeight(_ intensity: Float, meterHeight: Int,
                                      dpr: Double, playing: Bool,
                                      maximumIntensity: Float = 1) -> Int {
        let painted = playing ? min(intensity, maximumIntensity) : intensity
        return Int((Double(painted) * Double(meterHeight) * dpr).rounded())
    }
}

extension TrackHeadersPresenter {
    /// Runs on the workspace's existing display cadence, including paused fill.
    @discardableResult
    public func advanceActivity(levels: [AudioActivityLevel], elapsedSeconds: Float,
                                playing: Bool) -> Bool {
        let animating = activity.advance(levels, elapsedSeconds: elapsedSeconds, playing: playing)
        activityPlaying = playing
        for index in snapshots.indices where !snapshots[index].isAddTrack {
            var row = snapshots[index]
            let intensity = activity.intensity(track: row.track)
            row.activityLeftHeight = activityHeight(intensity.left)
            row.activityRightHeight = activityHeight(intensity.right)
            publishRow(row, at: index)
        }
        return animating
    }

    func activityHeight(_ intensity: Float) -> Double {
        Double(TrackActivity.physicalHeight(intensity,
            meterHeight: max(0, rowHeight - separatorWidth), dpr: devicePixelRatio,
            playing: activityPlaying)) / devicePixelRatio
    }
}
