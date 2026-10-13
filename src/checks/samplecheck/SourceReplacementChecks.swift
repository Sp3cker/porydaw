import Foundation
import NativeDisplayList
@testable import PorydawApp
import PorydawAppPresentation
import PorydawSample
import PorydawSampleUI
import SwiftCoreCheckSupport

@testable import SwiftCoreCheckLogic

@MainActor
internal func runSourceReplacementChecks(_ report: CheckReport) {
    let replacement = report.scoped(cppID: "swiftcore/SampleStudioPresenter::replaceSource")
    guard let original = try? SampleImport.decode(hiResSampleWav(), sourcePath: "fix/hires_tone.wav") else {
        replacement.expect(false, message: "replacement source could not be decoded")
        return
    }
    var next = original
    next.buffer = (0..<original.frameCount).map { (frame: Int) -> Float in
        let amplitude = frame < original.frameCount / 2 ? 0.45 : 0.05
        return Float(amplitude * sin(2 * .pi * 440 * Double(frame) / original.sampleRate))
    }
    next.suggestedName = "new_tone"
    next.hasLoop = false
    next.exactPitch = 0
    var changedRate = next
    changedRate.sampleRate = 32_000
    let validator: (String) -> String? = { name in name.isEmpty ? "Name required" : nil }
    let palette = GridPalette()
    ShellAppearance.apply(to: palette, mode: "vanilla", contrast: 50)
    func waveformHeight(_ wave: MarkerWaveformModel, atX x: Int) -> Double? {
        wave.displayList(list: 0).withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Double? in
            var view = PdDlView()
            guard pd_dl_decode(raw.baseAddress, raw.count, &view),
                let rects = view.rects, let header = view.header
            else { return nil }
            let ink = PaletteMath.argb(palette.sampleWaveformInk)
            guard
                let index = (0..<Int(header.pointee.rectCount)).first(where: { (index: Int) -> Bool in
                    rects[index].argb == ink && Int(rects[index].x) == x && rects[index].w == 1
                })
            else { return nil }
            return rects[index].h
        }
    }

    func makeWaveform(presenter: SampleStudioPresenter, tools: SampleLoopTools) -> MarkerWaveformModel {
        let wave = MarkerWaveformModel(palette: palette)
        tools.bindWaveform(wave)
        tools.publishWaveform(wave, sourceChanged: true)
        var sourceRevision = presenter.sourceRevision
        presenter.addRenderObserver { [weak presenter, weak wave, weak tools] in
            guard let presenter, let wave, let tools else { return }
            let sourceChanged = sourceRevision != presenter.sourceRevision
            sourceRevision = presenter.sourceRevision
            tools.publishWaveform(wave, sourceChanged: sourceChanged)
        }
        return wave
    }

    let blank = SampleStudioPresenter(document: SampleDocument(source: ImportedSample()), validateName: validator)
    let blankTools = SampleLoopTools(presenter: blank)
    let blankWave = makeWaveform(presenter: blank, tools: blankTools)
    blankWave.setViewport(width: 120, height: 120)
    replacement.expect(
        !blank.hasSource && !blank.canCommit && blank.nameReadOnly,
        message: "empty studio cannot commit or edit an unloaded sample name")
    blank.replaceSource(SampleDocument(source: next))
    replacement.expect(
        blank.hasSource && blank.canCommit && !blank.nameReadOnly && blank.sampleName == "new_tone",
        message: "loading a source enables the prefilled valid name and commit")
    replacement.expect(
        abs(blankWave.xForFrame(6_000) - 60) <= 2
            && (waveformHeight(blankWave, atX: 30) ?? 0) > 10,
        message: "blank studio draws and fits newly loaded audio without a stale empty pyramid")
    blank.replaceSource(SampleDocument(source: ImportedSample(suggestedName: "empty_tone")))
    replacement.expect(
        !blank.hasSource && !blank.canCommit && blank.nameReadOnly
            && waveformHeight(blankWave, atX: 30) == nil,
        message: "zero-frame replacement cannot commit or retain the previous waveform")

    let locked = SampleStudioPresenter(document: SampleDocument(source: original), validateName: validator)
    locked.setEditTarget(name: "registered_tone")
    locked.setCropStart(value: 100)
    locked.beginMarkerGesture()
    replacement.expect(locked.canUndo, message: "pre-replacement edit is undoable")
    var restored = SampleDocument.defaultParams(for: changedRate)
    restored.cropStart = 256
    restored.baseKey = 57
    restored.targetRate = 13_379
    var restoredDocument = SampleDocument(source: changedRate)
    restoredDocument.setParams(restored)
    locked.replaceSource(restoredDocument)
    locked.endMarkerGesture()
    replacement.expect(
        locked.nameReadOnly && locked.sampleName == "registered_tone" && locked.canCommit
            && locked.commitLabel == "Save Sample" && locked.params == restored,
        message: "locked edit retains its identity and restored parameter baseline")
    replacement.expect(
        !locked.canUndo && !locked.canRedo && locked.cropStart == 256,
        message: "source change discards both undo history and unfinished marker gesture")
    replacement.expect(
        locked.sourceFrameCount == next.frameCount && locked.sourceLine.contains("32000 Hz")
            && locked.rateChoices[0] == "Keep source (32000 Hz)" && locked.rateIndex > 0,
        message: "source readouts and rate choices reflect the replacement and restored rate")
    locked.setCropStart(value: 320)
    replacement.expect(locked.canUndo, message: "post-replacement edits start new history")
    locked.replaceSource(SampleDocument(source: original))
    replacement.expect(
        !locked.canUndo && !locked.canRedo && locked.params == SampleDocument.defaultParams(for: original)
            && locked.sampleName == "registered_tone",
        message: "another source change clears new history without unlocking the edit name")
    let unlocked = SampleStudioPresenter(document: SampleDocument(source: original), validateName: validator)
    unlocked.setSampleName(name: "custom_name")
    unlocked.replaceSource(SampleDocument(source: next))
    replacement.expect(
        unlocked.sampleName == "new_tone" && unlocked.canCommit && !unlocked.nameReadOnly,
        message: "unlocked replacement uses the new source suggested name")

    let sourceState = report.scoped(cppID: "swiftcore/MarkerWaveformModel::sourceRevision")
    let presenter = SampleStudioPresenter(document: SampleDocument(source: original), validateName: validator)
    let tools = SampleLoopTools(presenter: presenter)
    let wave = makeWaveform(presenter: presenter, tools: tools)
    wave.setViewport(width: 600, height: 120)
    wave.setSeamViewport(width: 228, height: 56)
    tools.tryAnotherLoop()
    do { try runBlocking { await tools.waitForPitchAnalysis() } } catch {
        sourceState.expect(false, message: "original pitch analysis did not settle: \(error)")
        return
    }
    sourceState.expect(tools.canTryAnother, message: "original source exposes loop candidates before replacement")
    let oldPitchHint = tools.pitchApplyToolTip
    wave.zoom(atX: 300, steps: 3)
    wave.setPlayhead(frame: 5_000)
    guard
        let panStart = (100...500).first(where: { (x: Int) in
            wave.handleAt(x: Double(x), y: 60) == 0
        })
    else {
        sourceState.expect(false, message: "waveform has no unobstructed pan position")
        return
    }
    let panX = Double(panStart)
    sourceState.expect(!wave.press(x: panX, y: 60), message: "waveform body begins a pan, not a marker drag")
    let beforePan = wave.xForFrame(6_000)
    wave.drag(x: panX + 24)
    sourceState.expect(wave.xForFrame(6_000) != beforePan, message: "active pan changes the zoomed viewport")
    let zoomX = wave.xForFrame(6_000)
    presenter.setFineTuneCents(value: 12)
    sourceState.expect(
        wave.xForFrame(6_000) == zoomX,
        message: "parameter edit retains waveform zoom and pan")
    presenter.replaceSource(SampleDocument(source: next))
    sourceState.expect(
        abs(wave.xForFrame(6_000) - 300) <= 2
            && abs(wave.frameAt(600) - next.frameCount + 1) <= 100,
        message: "replacement fits the full source and discards zoom")
    let fittedX = wave.xForFrame(6_000)
    wave.drag(x: 400)
    sourceState.expect(
        wave.xForFrame(6_000) == fittedX,
        message: "replacement discards an unfinished pan")
    let playheadInk = PaletteMath.argb(palette.playhead)
    let hasPlayhead = wave.displayList(list: 0).withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
        var view = PdDlView()
        guard pd_dl_decode(raw.baseAddress, raw.count, &view),
            let rects = view.rects, let header = view.header
        else { return false }
        return (0..<Int(header.pointee.rectCount)).contains { (index: Int) -> Bool in rects[index].argb == playheadInk }
    }
    sourceState.expect(!hasPlayhead, message: "replacement clears the previous source playhead")
    let fresh = SampleStudioPresenter(document: SampleDocument(source: next), validateName: validator)
    let freshTools = SampleLoopTools(presenter: fresh)
    let freshWave = makeWaveform(presenter: fresh, tools: freshTools)
    wave.setViewport(width: 120, height: 120)
    freshWave.setViewport(width: 120, height: 120)
    let loud: Double? = waveformHeight(wave, atX: 30)
    let quiet: Double? = waveformHeight(wave, atX: 90)
    let freshLoud: Double? = waveformHeight(freshWave, atX: 30)
    let freshQuiet: Double? = waveformHeight(freshWave, atX: 90)
    let hasAmplitudeContrast: Bool = loud != nil && quiet != nil && (loud ?? 0) > (quiet ?? 0) * 4
    let matchesFreshGeometry: Bool = loud == freshLoud && quiet == freshQuiet
    sourceState.expect(
        hasAmplitudeContrast && matchesFreshGeometry,
        message: "downsampled replacement waveform matches fresh geometry across loud and quiet regions")

    let analysis = report.scoped(cppID: "swiftcore/SampleLoopTools::sourceRevision")
    do { try runBlocking { await tools.waitForPitchAnalysis() } } catch {
        analysis.expect(false, message: "replacement pitch analysis did not settle: \(error)")
        return
    }
    analysis.expect(
        tools.pitchApplyVisible && tools.pitchApplyToolTip != oldPitchHint
            && !tools.canTryAnother && tools.suggestStatus.isEmpty,
        message: "replacement reanalyzes the new pitch and drops old loop suggestions")
    tools.applyDetectedPitch()
    analysis.expect(
        presenter.baseKey == 69 && abs(presenter.fineTuneCents) < 5,
        message: "detected replacement pitch changes the editor key to A4")
    tools.tryAnotherLoop()
    freshTools.tryAnotherLoop()
    do { try runBlocking { await freshTools.waitForPitchAnalysis() } } catch {
        analysis.expect(false, message: "fresh pitch analysis did not settle: \(error)")
        return
    }
    analysis.expect(
        presenter.loopOn && fresh.loopOn && presenter.loopStart == fresh.loopStart
            && presenter.loopEnd == fresh.loopEnd && presenter.loopEnd < next.frameCount
            && presenter.loopStart < presenter.loopEnd && presenter.processed.looped,
        message: "same-length replacement suggests the new source's valid loop bounds")
}
