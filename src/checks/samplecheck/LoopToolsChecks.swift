import Foundation
import PorydawApp
import PorydawSample

@MainActor
internal func runLoopToolsChecks(_ report: CheckReport) {
    let validator: (String) -> String? = { _ in nil }
    let pipeline = report.scoped(cppID: "samplecheck/SampleProcessingTest::pipelineLoopToggle")
    guard let prepared = try? SampleImport.decode(preparedSampleWav(), sourcePath: "fix/prepared_tone.wav") else {
        pipeline.expect(false, message: "prepared loop-toggle fixture import failed")
        return
    }
    pipeline.expect(prepared.frameCount == 64 && prepared.hasLoop, message: "A022 prepared loop-toggle source imports")
    let shortPresenter = SampleStudioPresenter(source: prepared, validateName: validator)
    let shortTools = SampleLoopTools(presenter: shortPresenter)
    shortTools.setLoopEnabled(on: false)
    pipeline.expect(
        !shortPresenter.processed.looped && shortPresenter.processed.size == 64,
        message: "A024 loop toggle renders a one-shot")

    let adoption = report.scoped(cppID: "samplecheck/SampleProcessingTest::editorPitchAdoption")
    guard let highResolution = try? SampleImport.decode(hiResSampleWav(), sourcePath: "fix/hires_tone.wav") else {
        adoption.expect(false, message: "hi-res pitch fixture import failed")
        return
    }
    adoption.expect(
        highResolution.frameCount == 12_000 && highResolution.hasLoop,
        message: "A049 hi-res pitch source imports")
    let pitchPresenter = SampleStudioPresenter(source: highResolution, validateName: validator)
    let pitchTools = SampleLoopTools(presenter: pitchPresenter)
    adoption.expect(
        pitchTools.pitchApplyVisible && pitchTools.pitchApplyText == "Use detected pitch (A3)",
        message: "A051 mismatch offers detected-pitch hint")
    let tooltip = report.scoped(cppID: "swiftcore/SampleLoopTools::pitchTooltip")
    tooltip.expect(
        pitchTools.pitchApplyToolTip.contains("A3 +4¢ (220.5 Hz)."),
        message: "detected pitch tooltip rounds cents to whole units")
    pitchTools.applyDetectedPitch()
    adoption.expect(
        pitchPresenter.baseKey == 57 && abs(pitchPresenter.fineTuneCents - 3.93) <= 1.5,
        message: "A052 adopting pitch sets key and cents")
    adoption.expect(
        !pitchTools.pitchApplyVisible && pitchPresenter.canUndo,
        message: "A053 adopted hint hides and creates one history entry")
    pitchPresenter.undo()
    adoption.expect(
        pitchPresenter.baseKey == 60 && !pitchPresenter.canUndo,
        message: "pitch adoption undoes as a single entry")
    var upperFractionSource = highResolution
    upperFractionSource.buffer = (0..<12_000).map { frame in
        Float(0.5 * sin(2 * .pi * 230 * Double(frame) / 44_100))
    }
    let upperFractionPresenter = SampleStudioPresenter(source: upperFractionSource, validateName: validator)
    let upperFractionTools = SampleLoopTools(presenter: upperFractionPresenter)
    let upperFraction = report.scoped(cppID: "swiftcore/SampleLoopTools::positiveCents")
    upperFractionTools.applyDetectedPitch()
    upperFraction.expect(
        upperFractionPresenter.baseKey == 57
            && upperFractionPresenter.fineTuneCents > 50
            && upperFractionPresenter.fineTuneCents < 99.99,
        message: "detected pitch above half-semitone retains floor key and positive cents")

    let populate = report.scoped(cppID: "samplecheck/SampleProcessingTest::editorLoopPopulate")
    populate.expect(
        highResolution.frameCount == 12_000 && highResolution.hasLoop,
        message: "A056 hi-res loop source imports")
    let presenter = SampleStudioPresenter(source: highResolution, validateName: validator)
    let tools = SampleLoopTools(presenter: presenter)
    populate.expect(
        presenter.params.loopOn && tools.loopBodyVisible,
        message: "A058 imported loop body starts visible")
    populate.expect(
        presenter.params.loopStart == 2000 && presenter.params.loopEnd == 9999,
        message: "A059 imported loop markers retain source bounds")
    tools.setLoopEnabled(on: false)
    populate.expect(
        !presenter.params.loopOn && !tools.loopBodyVisible,
        message: "A060 disabling loop hides loop body")
    var reset = presenter.params
    reset.loopStart = 0
    reset.loopEnd = 0
    presenter.commitParams(reset, mergeKey: -1)
    populate.expect(
        presenter.params.loopStart == presenter.params.loopEnd,
        message: "resetting markers produces a loop-free selection")
    tools.setLoopEnabled(on: true)
    populate.expect(
        presenter.params.loopOn && presenter.params.loopStart < presenter.params.loopEnd,
        message: "A061 re-enabling seeds a loop")
    populate.expect(
        tools.loopBodyVisible && presenter.processed.looped,
        message: "A062 seeded loop body is visible and rendered")
    populate.expect(!presenter.params.crossfadeOn, message: "A063 clean tone needs no crossfade bake")
    let seam = presenter.processed.seam
    populate.expect(
        seam.valid && seam.ampLsb <= 2 && seam.derivLsb <= 3
            && (!seam.nccValid || seam.ncc >= 0.95),
        message: "A064 auto-populated loop is clean")
    populate.expect(
        tools.seamBadgeVisible && tools.seamBadgeSeverity == 0 && tools.seamBadgeText == "seam: clean",
        message: "A065 clean loop displays clean badge")
    populate.expect(
        tools.suggestStatus.hasPrefix("loop 1 of ") && tools.canTryAnother,
        message: "A066 first suggested loop is available")
    let lateSearch = report.scoped(cppID: "swiftcore/SampleLoopTools::lateLoopEnd")
    var lateSource = highResolution
    lateSource.buffer = (0..<16_000).map { frame in
        frame < 12_000 ? 0 : Float(0.5 * sin(2 * .pi * 220.5 * Double(frame) / 44_100))
    }
    let latePresenter = SampleStudioPresenter(source: lateSource, validateName: validator)
    let lateTools = SampleLoopTools(presenter: latePresenter)
    lateTools.setLoopEnabled(on: false)
    var lateParams = latePresenter.params
    lateParams.loopStart = 0
    lateParams.loopEnd = 0
    latePresenter.commitParams(lateParams, mergeKey: -1)
    lateTools.setLoopEnabled(on: true)
    lateSearch.expect(
        latePresenter.params.loopOn && latePresenter.params.loopEnd > 12_000
            && latePresenter.processed.looped,
        message: "first populated loop searches beyond three-quarter sample boundary")
    presenter.undo()
    populate.expect(
        !presenter.params.loopOn && !tools.loopBodyVisible,
        message: "A067 undo re-disables auto-populated loop")
    presenter.redo()
    populate.expect(
        presenter.params.loopOn && tools.loopBodyVisible,
        message: "A068 redo re-enables auto-populated loop")
    tools.tryAnotherLoop()
    populate.expect(
        presenter.params.loopOn && presenter.processed.looped,
        message: "A070 try-another keeps a valid loop")

    let refine = report.scoped(cppID: "samplecheck/SampleProcessingTest::editorLoopRefine")
    refine.expect(
        highResolution.frameCount == 12_000 && highResolution.hasLoop,
        message: "A073 hi-res refine source imports")
    let refinePresenter = SampleStudioPresenter(source: highResolution, validateName: validator)
    let refineTools = SampleLoopTools(presenter: refinePresenter)
    var misaligned = refinePresenter.params
    misaligned.loopStart = 2000
    misaligned.loopEnd = 2137
    refinePresenter.commitParams(misaligned, mergeKey: -1)
    refine.expect(
        refinePresenter.params.loopStart == 2000 && refinePresenter.params.loopEnd == 2137,
        message: "A075 misaligned markers are committed")
    let before = refinePresenter.processed.seam
    refineTools.refineLoop()
    let after = refinePresenter.processed.seam
    refine.expect(
        !before.nccValid || (after.nccValid && after.ncc >= before.ncc - 0.02),
        message: "A076 refine keeps the seam at least as clean")
    refinePresenter.undo()
    refine.expect(
        refinePresenter.params.loopStart == 2000 && refinePresenter.params.loopEnd == 2137,
        message: "A077 refinement adds no more than one undo entry")
}
