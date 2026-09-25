@testable import PorydawApp
import PorydawPlaybackNative

func checkAudioVolumeClamps(_ audio: AudioRenderEngine, _ report: CheckReport) {
    report.expectEqual(expected: 100, actual: audio.outputVolume,
        cppID: "audiocheck/AudioTelemetryTest::outputVolumeClamps", what: "initial volume")
    audio.setOutputVolume(42)
    report.expectEqual(expected: 42, actual: audio.outputVolume,
        cppID: "audiocheck/AudioTelemetryTest::outputVolumeClamps", what: "in-range volume")
    audio.setOutputVolume(-1)
    report.expectEqual(expected: 0, actual: audio.outputVolume, cppID: "audiocheck/AudioTelemetryTest::outputVolumeClamps", what: "lower clamp")
    audio.setOutputVolume(101)
    report.expectEqual(expected: 100, actual: audio.outputVolume, cppID: "audiocheck/AudioTelemetryTest::outputVolumeClamps", what: "upper clamp")
    checkAudioActivityTelemetry(report)
}

private func checkAudioActivityTelemetry(_ report: CheckReport) {
    let telemetry = AudioTelemetry()
    let fresh = telemetry.consume()
    report.expectEqual(expected: Int(MAX_TRACKS), actual: fresh.count,
        cppID: "audiocheck/AudioTelemetryTest::freshConsumeIsAllDark", what: "all engine tracks")
    for (track, level) in fresh.enumerated() {
        report.expectEqual(expected: UInt8(0), actual: level.left,
            cppID: "audiocheck/AudioTelemetryTest::freshConsumeIsAllDark", what: "track \(track) left")
        report.expectEqual(expected: UInt8(0), actual: level.right,
            cppID: "audiocheck/AudioTelemetryTest::freshConsumeIsAllDark", what: "track \(track) right")
    }

    var engine = M4AEngine()
    engine.maxPcmChannels = 2
    func publish(_ envelope: UInt8, _ left: UInt8, _ right: UInt8,
                 second: (UInt8, UInt8, UInt8)? = nil) -> AudioActivityLevel {
        withUnsafeMutablePointer(to: &engine.pcmChannels) { storage in
            storage.withMemoryRebound(to: M4APCMChannel.self, capacity: Int(TOTAL_PCM_CHANNELS)) { channels in
                channels[0] = M4APCMChannel()
                channels[0].status = 0x80
                channels[0].envelopeVolume = envelope
                channels[0].leftVolume = left
                channels[0].rightVolume = right
                channels[1] = M4APCMChannel()
                if let second {
                    channels[1].status = 0x80
                    channels[1].envelopeVolume = second.0
                    channels[1].leftVolume = second.1
                    channels[1].rightVolume = second.2
                }
            }
        }
        withUnsafeMutablePointer(to: &engine) { telemetry.publish(engine: $0, position: 0) }
        return telemetry.consume()[0]
    }
    let packedRows: [(String, UInt8, UInt8, UInt32)] = [
        ("silent", 0, 0, 0x0000), ("maximum", 255, 255, 0xffff),
        ("asymmetric", 0x5a, 0xa5, 0xa55a),
    ]
    for (name, left, right, packed) in packedRows {
        let actual = publish(max(left, right), left, right)
        let id = "audiocheck/AudioTelemetryTest::packedActivityPreservesByteOrder[\(name)]"
        report.expectEqual(expected: packed, actual: UInt32(actual.left) | UInt32(actual.right) << 8,
            cppID: id, what: "published low-byte left high-byte right")
        report.expectEqual(expected: left, actual: actual.left, cppID: id, what: "left roundtrip")
        report.expectEqual(expected: right, actual: actual.right, cppID: id, what: "right roundtrip")
    }
    let combined = publish(220, 24, 220, second: (220, 220, 24))
    report.expectEqual(expected: UInt8(220), actual: combined.left,
        cppID: "audiocheck/AudioTelemetryTest::maxLevelIsComponentWise", what: "left maximum")
    report.expectEqual(expected: UInt8(220), actual: combined.right,
        cppID: "audiocheck/AudioTelemetryTest::maxLevelIsComponentWise", what: "right maximum")
    let panRows: [(String, UInt8, UInt8, UInt8, UInt8, UInt8)] = [
        ("center", 255, 127, 127, 255, 255),
        ("hard-left", 255, 127, 0, 255, 0),
        ("hard-right", 255, 0, 127, 0, 255),
        ("asymmetric-balance", 128, 32, 64, 64, 128),
        ("silent", 255, 0, 0, 0, 0),
    ]
    for (name, envelope, left, right, expectedLeft, expectedRight) in panRows {
        let actual = publish(envelope, left, right)
        let id = "audiocheck/AudioTelemetryTest::pcmPanRetainsEnvelope[\(name)]"
        report.expectEqual(expected: expectedLeft, actual: actual.left, cppID: id, what: "left envelope")
        report.expectEqual(expected: expectedRight, actual: actual.right, cppID: id, what: "right envelope")
    }
}
