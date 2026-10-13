import Foundation
import NativeDisplayList
import PorydawApp
import PorydawAppPresentation
import PorydawSample
import PorydawSampleUI
@testable import SwiftCoreCheckLogic

@MainActor
internal func runWaveformChecks(_ report: CheckReport) {
    let scoped = report.scoped(cppID: "samplecheck/SampleProcessingTest::editorCrossfade")
    guard let source = try? SampleImport.decode(hiResSampleWav(), sourcePath: "fix/hires_tone.wav") else {
        scoped.expect(false, message: "crossfade fixture decode failed")
        return
    }
    scoped.expect(source.frameCount == 12_000, message: "A080 crossfade source imports")
    let presenter = SampleStudioPresenter(document: SampleDocument(source: source), validateName: { _ in nil })
    let palette = GridPalette()
    ShellAppearance.apply(to: palette, mode: "vanilla", contrast: 50)
    let model = MarkerWaveformModel(palette: palette)
    let tools = SampleLoopTools(presenter: presenter)
    tools.bindWaveform(model)
    tools.publishWaveform(model, sourceChanged: true)
    presenter.addRenderObserver { [weak tools, weak model] in
        guard let tools, let model else { return }
        tools.publishWaveform(model, sourceChanged: false)
    }
    model.setViewport(width: 600, height: 120)
    model.setSeamViewport(width: 228, height: 56)
    let geometry = report.scoped(cppID: "swiftcore/MarkerWaveformModel::geometry")
    for frame in [0, 1_000, 5_000, 10_000] {
        geometry.expect(
            abs(model.frameAt(Double(model.xForFrame(frame))) - frame) <= 12,
            message: "sample/x round trip at fit: \(frame)")
    }
    model.zoom(atX: 180, steps: 3)
    let anchor = model.frameAt(180)
    model.zoom(atX: 180, steps: 2)
    geometry.expect(abs(model.frameAt(180) - anchor) <= 2, message: "zoom preserves anchored sample")
    let beforePan = model.frameAt(180)
    model.pan(byPixels: -20)
    geometry.expect(model.frameAt(180) > beforePan, message: "pan moves the source viewport")
    let zoomSpan = model.frameAt(300) - model.frameAt(0)
    model.setViewport(width: 500, height: 120)
    geometry.expect(model.frameAt(300) - model.frameAt(0) == zoomSpan, message: "resize preserves user zoom")
    model.setViewport(width: 600, height: 120)
    model.fit()
    geometry.expect(
        abs(model.frameAt(600) - source.frameCount + 1) <= 100,
        message: "fit exposes complete sample")
    presenter.setLoopOn(enabled: false)
    geometry.expect(
        model.handleAt(x: Double(model.xForFrame(presenter.cropStart)), y: 10) == 1
            && !presenter.loopOn && model.markers.count == 2,
        message: "crop markers publish while disabled loop markers are absent")
    var params = presenter.params
    params.loopOn = true
    params.loopStart = 2_000
    params.loopEnd = 2_137
    presenter.commitParams(params, mergeKey: -1)
    let startX = Double(model.xForFrame(presenter.loopStart))
    geometry.expect(model.handleAt(x: startX, y: 110) == 3, message: "loop markers own the bottom band")
    scoped.expect(
        !model.seamEndWindow.isEmpty && model.seamEndWindow.count == model.seamStartWindow.count,
        message: "A082 looped render feeds the seam overlay")
    let prior = model.seamEndWindow
    let pyramidRevision = model.pyramidRevision
    tools.setCrossfade(on: true)
    presenter.undo()
    let togglesAsOneEntry = !presenter.params.crossfadeOn && presenter.canRedo
    presenter.redo()
    scoped.expect(
        togglesAsOneEntry && presenter.params.crossfadeOn,
        message: "A083 crossfade toggle creates an undo entry")
    scoped.expect(
        model.seamEndWindow != prior && model.seamEndWindow.count == model.seamStartWindow.count,
        message: "A084 crossfade bake reshapes the seam overlay")
    let dragX = Double(model.xForFrame(presenter.loopEnd))
    geometry.expect(model.press(x: dragX, y: 110), message: "loop end is draggable")
    model.drag(x: Double(model.xForFrame(presenter.cropEnd + 100)))
    model.release()
    geometry.expect(
        presenter.loopEnd < presenter.cropEnd && presenter.loopStart < presenter.loopEnd,
        message: "drag clamps loop within crop")
    presenter.undo()
    geometry.expect(presenter.loopEnd == 2_137, message: "drag undoes as one entry")
    let main = model.displayList(list: 0)
    let seam = model.displayList(list: 1)
    let display = report.scoped(cppID: "swiftcore/MarkerWaveformModel::displayLists")
    func colors(_ data: Data) -> Set<UInt32>? {
        data.withUnsafeBytes { raw in
            var view = PdDlView()
            guard pd_dl_decode(raw.baseAddress, raw.count, &view),
                let header = view.header, let rects = view.rects
            else { return nil }
            return Set((0..<Int(header.pointee.rectCount)).map { rects[$0].argb })
        }
    }
    let mainColors = colors(main)
    let seamColors = colors(seam)
    display.expect(
        mainColors?.contains(PaletteMath.argb(palette.sampleWaveformInk)) == true
            && mainColors?.contains(PaletteMath.argb(palette.sampleCropHandle)) == true
            && mainColors?.contains(PaletteMath.argb(palette.sampleLoopHandle)) == true,
        message: "decoded main list draws ink and both marker colors")
    display.expect(
        seamColors?.contains(PaletteMath.argb(palette.sampleSeamEndInk)) == true
            && seamColors?.contains(PaletteMath.argb(palette.sampleLoopHandle)) == true,
        message: "decoded seam list draws processed end and start colors")
    display.expect(
        main.withUnsafeBytes { raw -> Bool in
            var view = PdDlView()
            guard pd_dl_decode(raw.baseAddress, raw.count, &view),
                let header = view.header, let labels = view.labels
            else { return false }
            return Int(header.pointee.labelCount) == model.markers.count
                && (0..<Int(header.pointee.labelCount)).allSatisfy { (index: Int) -> Bool in
                    labels[index].textLength > 0
                }
        },
        message: "marker tabs draw one nonempty label per published marker")
    params.cropStart = params.loopStart
    presenter.commitParams(params, mergeKey: -1)
    geometry.expect(
        model.handleAt(x: Double(model.xForFrame(presenter.cropStart)), y: 10) == 1
            && model.handleAt(x: Double(model.xForFrame(presenter.loopStart)), y: 110) == 3,
        message: "coincident crop and loop starts remain independently reachable")
    geometry.expect(
        model.press(x: Double(model.xForFrame(presenter.cropStart)), y: 10),
        message: "coincident crop marker begins a drag")
    model.drag(x: Double(model.xForFrame(presenter.cropEnd + 100)))
    model.release()
    geometry.expect(
        presenter.cropStart <= presenter.cropEnd - 2
            && presenter.loopStart >= presenter.cropStart
            && presenter.loopEnd < presenter.cropEnd,
        message: "crop drag preserves an interior loop")
    presenter.undo()
    geometry.expect(model.pyramidRevision == pyramidRevision, message: "parameter edits never rebuild peaks")

    // Exercise the public value model directly, independently of the Sample Studio adapter.
    model.onMarkerPressed = nil
    model.onMarkerDragged = nil
    model.onMarkerReleased = nil
    model.setMarkers([(41, 2_000, "crop", "A"), (72, 6_000, "crop", "B")])
    geometry.expect(
        model.markers.count == 2 && model.markers[0].id == 41 && model.markers[0].frame == 2_000
            && model.markers[0].kind == "crop" && model.markers[0].label == "A" && !model.markers[0].selected,
        message: "QML rows publish stable id, frame, kind, label and selection")
    geometry.expect(model.press(x: Double(model.xForFrame(2_000)), y: 10), message: "arbitrary marker id grabs")
    model.setMarkers([(41, 2_500, "crop", "A"), (72, 6_000, "crop", "B")])
    model.drag(x: Double(model.xForFrame(9_000)))
    geometry.expect(
        model.markers[0].id == 41 && model.markers[0].frame == 5_999 && model.markers[0].selected,
        message: "frame-only replacement preserves grab and same-kind forward drag clamps to neighbor")
    model.release()
    let releasedFrame = model.markers[0].frame
    model.drag(x: 0)
    geometry.expect(
        model.markers[0].frame == releasedFrame && !model.markers[0].selected,
        message: "release clears selection and stops marker edits")
    model.zoom(atX: Double(model.xForFrame(6_000)), steps: 40)
    geometry.expect(model.press(x: Double(model.xForFrame(6_000)), y: 10), message: "second marker grabs")
    model.drag(x: 0)
    model.release()
    geometry.expect(model.markers[1].frame == 6_000, message: "backward drag clamps after same-kind neighbor")
    geometry.expect(model.pyramidRevision == pyramidRevision, message: "marker replacement and gestures reuse peaks")
    model.setSamples(source.buffer, sampleRate: source.sampleRate, gain: 1)
    geometry.expect(model.pyramidRevision == pyramidRevision + 1, message: "setSamples rebuilds peaks exactly once")
}
