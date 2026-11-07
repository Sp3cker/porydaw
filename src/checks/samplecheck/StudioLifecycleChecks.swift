import Foundation
import PorydawApp
import PorydawAppAudio
import PorydawPlayback
import PorydawSample
import SwiftCoreCheckSupport

@testable import SwiftCoreCheckLogic

@MainActor
internal func runStudioLifecycleChecks(_ report: CheckReport) {
    let audio = report.scoped(cppID: "swiftcore/SampleStudioAudition::sharedOutputOwnership")
    do {
        let source = try SampleImport.decode(hiResSampleWav(), sourcePath: "fix/hires_tone.wav")
        let firstPresenter = SampleStudioPresenter(
            document: SampleDocument(source: source), validateName: { (_: String) -> String? in nil })
        let secondPresenter = SampleStudioPresenter(
            document: SampleDocument(source: source), validateName: { (_: String) -> String? in nil })
        try runBlocking {
            await firstPresenter.waitForRender()
            await secondPresenter.waitForRender()
        }
        let output = SampleAuditionCheckOutput()
        let first = SampleStudioAudition(
            presenter: firstPresenter, beginSampleAudition: output.begin,
            isAudioAvailable: { () -> Bool in output.available }, destinationAdsr: nil)
        let second = SampleStudioAudition(
            presenter: secondPresenter, beginSampleAudition: output.begin,
            isAudioAvailable: { () -> Bool in output.available }, destinationAdsr: nil)
        first.toggle()
        guard let firstNote = output.lastNote() else {
            audio.expect(false, message: "First owner submits its PCM")
            return
        }
        output.start(firstNote)
        audio.expect(first.playing, message: "First owner is playing after engine adoption")
        second.toggle()
        guard let secondNote = output.lastNote() else {
            audio.expect(false, message: "New owner submits replacement PCM")
            return
        }
        output.start(secondNote)
        let successor = output.current
        audio.expect(second.playing && successor?.isCurrent == true, message: "New owner replaces the audition")
        first.tick()
        audio.expect(
            !first.playing && first.playText == "Listen" && second.playing && successor?.isCurrent == true,
            message: "displacement clears the editor holder's playing state without silencing its successor")
        first.setAuditionKey(key: 61)
        audio.expect(
            !first.playing && first.playText == "Listen" && second.playing && successor?.isCurrent == true
                && output.lastNote().map { (_: SampleAuditionNote) -> Bool in true } != true,
            message: "a displaced editor's key change cannot revive its stopped player")
        first.close()
        first.toggle()
        audio.expect(
            !first.available && !first.playing && first.playText == "Listen" && successor?.isCurrent == true,
            message: "Closing displaced editor leaves the current owner intact and cannot restart")
        second.close()
        audio.expect(successor?.isCurrent == false && !second.playing, message: "Closing active editor ends its lease")
    } catch {
        report.fail("swiftcore/SampleStudioAudition::fixture", "audition fixture failed: \(error)")
    }
}
