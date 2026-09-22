import Foundation
@testable import PorydawApp

func runTrackActivityChecks(_ report: CheckReport) {
    let zero = Array(repeating: AudioActivityLevel(), count: 16)
    func dark(_ value: TrackActivity.Intensity) -> Bool { value.left == 0 && value.right == 0 }
    var activity = TrackActivity()
    let fresh = "TrackActivityTest::freshActivityIsDark"
    for track in 0..<16 {
        report.expect(dark(activity.intensity(track: track)), cppID: fresh, message: "new track is dark")
    }
    report.expect(dark(activity.intensity(track: -1)), cppID: fresh, message: "negative track is dark")
    report.expect(dark(activity.intensity(track: 16)), cppID: fresh, message: "high track is dark")

    for (left, right): (UInt8, UInt8) in [(128, 32), (255, 0), (0, 255)] {
        let id = "TrackActivityTest::attackRetainsStereoTargets"
        activity = TrackActivity()
        var levels = zero
        levels[3] = AudioActivityLevel(left: left, right: right)
        report.expect(activity.advance(levels, elapsedSeconds: 0.017, playing: true),
                      cppID: id, message: "playing requires another tick")
        let first = activity.intensity(track: 3)
        func approaches(_ value: Float, _ peak: UInt8) -> Bool {
            peak > 0 ? value > 0 && value < Float(peak) / 255 : value == 0
        }
        report.expect(approaches(first.left, left), cppID: id, message: "left attacks without snapping")
        report.expect(approaches(first.right, right), cppID: id, message: "right attacks without snapping")
        report.expect(left > right ? first.left > first.right : first.right > first.left,
                      cppID: id, message: "stereo sides retain independent targets")
        for track in 0..<16 where track != 3 {
            report.expect(dark(activity.intensity(track: track)), cppID: id, message: "other tracks remain dark")
        }
    }
    let release = "TrackActivityTest::releaseIsGradualAndMonotonic"
    activity = TrackActivity()
    var levels = zero
    levels[3] = AudioActivityLevel(left: 128, right: 32)
    activity.advance(levels, elapsedSeconds: 0.017, playing: true)
    var previous = activity.intensity(track: 3)
    activity.advance(zero, elapsedSeconds: 0.125, playing: true)
    var current = activity.intensity(track: 3)
    report.expect(current.left > previous.left * 0.5 && current.right > previous.right * 0.5,
                  cppID: release, message: "release remains visibly gradual")
    previous = current
    for _ in 0..<23 {
        activity.advance(zero, elapsedSeconds: 0.125, playing: true)
        current = activity.intensity(track: 3)
        report.expect(current.left <= previous.left && current.right <= previous.right,
                      cppID: release, message: "both sides decay monotonically")
        previous = current
    }
    report.expect(dark(activity.intensity(track: 3)), cppID: release, message: "release settles at zero")

    activity = TrackActivity()
    levels = zero
    levels[3] = AudioActivityLevel(left: 255, right: 255)
    activity.advance(levels, elapsedSeconds: 0.015, playing: true)
    activity.advance(zero, elapsedSeconds: 2, playing: true)
    report.expect(dark(activity.intensity(track: 3)), cppID: "TrackActivityTest::imperceptibleTailSnapsToZero",
                  message: "visible floor removes imperceptible tail")

    activity = TrackActivity()
    levels = zero
    levels[7] = AudioActivityLevel(left: 48)
    activity.advance(levels, elapsedSeconds: 0.017, playing: true)
    activity.advance(zero, elapsedSeconds: 1, playing: true)
    let decayed = activity.intensity(track: 7)
    levels[7] = AudioActivityLevel(left: 224, right: 64)
    activity.advance(levels, elapsedSeconds: 0.017, playing: true)
    let retriggered = activity.intensity(track: 7)
    let retrigger = "TrackActivityTest::retriggerRetainsInertia"
    report.expect(retriggered.left > decayed.left && retriggered.right > decayed.right,
                  cppID: retrigger, message: "new peak retriggers independently")
    report.expect(retriggered.left < 224 / Float(255) && retriggered.right < 64 / Float(255),
                  cppID: retrigger, message: "retrigger retains attack inertia")

    activity = TrackActivity()
    levels = zero
    levels[3] = AudioActivityLevel(left: 200, right: 120)
    activity.advance(levels, elapsedSeconds: 0.017, playing: true)
    activity.reset()
    report.expect((0..<16).allSatisfy { dark(activity.intensity(track: $0)) },
                  cppID: "TrackActivityTest::resetClearsEveryLight", message: "reset clears every light")

    activity = TrackActivity()
    levels[3] = AudioActivityLevel(left: 255, right: 64)
    activity.advance(levels, elapsedSeconds: 0.015, playing: true)
    let beforePause = activity.intensity(track: 3)
    let paused = "TrackActivityTest::pausedFillSettlesEveryTrack"
    report.expect(activity.advance(zero, elapsedSeconds: 0.015, playing: false), cppID: paused,
                  message: "paused fill requires another tick")
    let filling = activity.intensity(track: 3)
    report.expect(filling.left > beforePause.left && filling.right > beforePause.right,
                  cppID: paused, message: "paused fill gently approaches full brightness")
    report.expect(!activity.advance(zero, elapsedSeconds: 10, playing: false), cppID: paused,
                  message: "settled paused fill stops ticks")
    for track in 0..<16 {
        let settled = activity.intensity(track: track)
        report.expect(settled.left == 1 && settled.right == 1, cppID: paused,
                      message: "all sides settle at full brightness")
    }
    report.expect(!activity.advance(zero, elapsedSeconds: 0, playing: false), cppID: paused,
                  message: "settled pause remains settled")

    activity = TrackActivity()
    activity.resetPaused()
    let resume = "TrackActivityTest::resumeUsesFastWindowThenOrdinaryRelease"
    report.expect(activity.advance(zero, elapsedSeconds: 0.075, playing: true), cppID: resume,
                  message: "resume requires ticks")
    let resumed = activity.intensity(track: 3)
    report.expect(abs(resumed.left - exp(-0.075 / Float(0.015))) <= 0.0001, cppID: resume,
                  message: "resume descends through 75ms fast window")
    activity.advance(zero, elapsedSeconds: 0.015, playing: true)
    let ordinary = activity.intensity(track: 3)
    report.expect(abs(ordinary.left - resumed.left * exp(-0.015 / Float(0.250))) <= 0.0001,
                  cppID: resume, message: "release returns to 250ms")
    report.expect(ordinary.left > resumed.left * exp(-0.015 / Float(0.015)), cppID: resume,
                  message: "ordinary release does not retain fast descent")

    activity = TrackActivity()
    activity.resetPaused()
    activity.advance(zero, elapsedSeconds: 0.050, playing: true)
    activity.advance(zero, elapsedSeconds: 0.001, playing: false)
    let beforeRapidResume = activity.intensity(track: 3)
    activity.advance(zero, elapsedSeconds: 0.015, playing: true)
    report.expect(activity.intensity(track: 3).left < beforeRapidResume.left * exp(-0.015 / Float(0.250)),
                  cppID: "TrackActivityTest::rapidPauseRearmsFastDescent", message: "rapid pause restarts descent")

    activity = TrackActivity()
    levels = zero
    levels[3] = AudioActivityLevel(left: 255, right: 255)
    let elapsed = "TrackActivityTest::clampedElapsedNeedsTicksWithoutMovement"
    report.expect(activity.advance(levels, elapsedSeconds: -1, playing: true), cppID: elapsed,
                  message: "negative elapsed still requires ticks")
    report.expect(dark(activity.intensity(track: 3)), cppID: elapsed, message: "negative elapsed does not move")
    activity.advance(levels, elapsedSeconds: 0, playing: true)
    report.expect(dark(activity.intensity(track: 3)), cppID: elapsed, message: "zero elapsed does not move")
}
