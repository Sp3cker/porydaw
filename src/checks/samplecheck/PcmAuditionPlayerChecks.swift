import PorydawAppAudio
import PorydawPlayback
import PorydawSample
import PorydawSampleUI

@testable import SwiftCoreCheckLogic

/// Four unretired slots make a fifth note Busy; the player keeps its lease and sounds that note once
/// the callback retires a slot, without asking the holder for fresh content.
@MainActor
internal func runPcmAuditionPlayerChecks(_ report: CheckReport) {
    let scope = report.scoped(cppID: "swiftcore/PcmAuditionPlayer::busyRetry")
    do {
        let renderer = try AudioRenderEngine(sampleRate: 48_000, periodFrames: 512)
        defer { renderer.unload() }
        let player = PcmAuditionPlayer(audition: renderer.audition)
        defer { player.close() }
        var sample = ProcessedSample()
        sample.s8 = (0..<512).map { (index: Int) -> Int8 in index % 32 < 16 ? 64 : -64 }
        sample.freq = 8192 * 1024
        var starts = 0
        var restarts = 0
        player.onStarted = { starts += 1 }
        player.onWillRestart = { restarts += 1 }
        var output = [Float](repeating: 0, count: 8192)
        func renderIsAudible() -> Bool {
            output.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                renderer.render(base, frames: 4096)
            }
            return output.contains { abs($0) > 0.01 }
        }
        for key in UInt8(60)...64 {
            player.play(rendered: sample, looped: false, key: key, adsr: AudioADSR(), toneKey: 60)
        }
        player.advance(bySeconds: 0)
        scope.expect(
            starts == 4 && player.playing && restarts == 0,
            message: "a fifth note waits on four unretired slots without a holder restart")
        _ = renderIsAudible()
        player.advance(bySeconds: 0)
        scope.expect(starts == 5 && renderIsAudible(), message: "slot retirement sounds the waiting note")
        player.advance(bySeconds: 10)
        player.advance(bySeconds: 0.51)
        scope.expect(restarts == 1, message: "only the one-shot repeat asks the holder for fresh content")
    } catch {
        report.fail("swiftcore/PcmAuditionPlayer::fixture", "player fixture failed: \(error)")
    }
}
