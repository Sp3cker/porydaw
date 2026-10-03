import Foundation
import NativeDisplayList
import PorydawApp
import PorydawSample

@MainActor
internal func runWaveformChecks(_ report: CheckReport) {
    let scoped = report.scoped(cppID: "samplecheck/SampleProcessingTest::editorCrossfade")
    guard let source = try? SampleImport.decode(hiResSampleWav(), sourcePath: "fix/hires_tone.wav") else {
        scoped.expect(false, message: "crossfade fixture decode failed")
        return
    }
    scoped.expect(source.frameCount == 12_000, message: "A080 crossfade source imports")
    let presenter = SampleStudioPresenter(source: source, validateName: { _ in nil })
    let palette = GridPalette()
    ShellAppearance.apply(to: palette, mode: "vanilla", contrast: 50)
    let model = SampleWaveformModel(presenter: presenter, palette: palette)
    model.setViewport(width: 600, height: 120)
    model.setSeamViewport(width: 228, height: 56)
    let geometry = report.scoped(cppID: "swiftcore/SampleWaveformModel::geometry")
    for frame in [0, 1_000, 5_000, 10_000] {
        geometry.expect(abs(model.sampleForX(Double(model.xForSample(frame))) - frame) <= 12,
                        message: "sample/x round trip at fit: \(frame)")
    }
    model.zoom(atX: 180, steps: 3)
    let anchor = model.sampleForX(180)
    model.zoom(atX: 180, steps: 2)
    geometry.expect(abs(model.sampleForX(180) - anchor) <= 2, message: "zoom preserves anchored sample")
    model.fit()
    geometry.expect(abs(model.sampleForX(600) - source.frameCount + 1) <= 100,
                    message: "fit exposes complete sample")
    geometry.expect(model.handleAt(x: Double(model.xForSample(presenter.cropStart)), y: 10) == 1,
                    message: "crop grips own the top band")
    var params = presenter.params
    params.loopOn = true
    params.loopStart = 2_000
    params.loopEnd = 2_137
    presenter.commitParams(params, mergeKey: -1)
    let startX = Double(model.xForSample(presenter.loopStart))
    geometry.expect(model.handleAt(x: startX, y: 110) == 3, message: "loop grips own the bottom band")
    scoped.expect(!model.seamEndWindow.isEmpty && model.seamEndWindow.count == model.seamStartWindow.count,
                  message: "A082 looped render feeds the seam overlay")
    let prior = model.seamEndWindow
    let tools = SampleLoopTools(presenter: presenter)
    tools.setCrossfade(on: true)
    presenter.undo()
    let togglesAsOneEntry = !presenter.params.crossfadeOn && presenter.canRedo
    presenter.redo()
    scoped.expect(togglesAsOneEntry && presenter.params.crossfadeOn,
                  message: "A083 crossfade toggle creates an undo entry")
    scoped.expect(model.seamEndWindow != prior && model.seamEndWindow.count == model.seamStartWindow.count,
                  message: "A084 crossfade bake reshapes the seam overlay")
    let dragX = Double(model.xForSample(presenter.loopEnd))
    geometry.expect(model.press(x: dragX, y: 110), message: "loop end is draggable")
    model.drag(x: Double(model.xForSample(presenter.cropEnd + 100)))
    model.release()
    geometry.expect(presenter.loopEnd < presenter.cropEnd && presenter.loopStart < presenter.loopEnd,
                    message: "drag clamps loop within crop")
    presenter.undo()
    geometry.expect(presenter.loopEnd == 2_137, message: "drag undoes as one entry")
    let main = model.displayList(list: 0)
    let seam = model.displayList(list: 1)
    let display = report.scoped(cppID: "swiftcore/SampleWaveformModel::displayLists")
    func colors(_ data: Data) -> Set<UInt32>? {
        data.withUnsafeBytes { raw in
            var view = PdDlView()
            guard pd_dl_decode(raw.baseAddress, raw.count, &view),
                  let header = view.header, let rects = view.rects else { return nil }
            return Set((0..<Int(header.pointee.rectCount)).map { rects[$0].argb })
        }
    }
    let mainColors = colors(main)
    let seamColors = colors(seam)
    display.expect(mainColors?.contains(PaletteMath.argb(palette.sampleWaveformInk)) == true
                   && mainColors?.contains(PaletteMath.argb(palette.sampleCropHandle)) == true
                   && mainColors?.contains(PaletteMath.argb(palette.sampleLoopHandle)) == true,
                   message: "decoded main list draws ink and both grip colors")
    display.expect(seamColors?.contains(PaletteMath.argb(palette.sampleSeamEndInk)) == true
                   && seamColors?.contains(PaletteMath.argb(palette.sampleLoopHandle)) == true,
                   message: "decoded seam list draws processed end and start colors")
    params.cropStart = params.loopStart
    presenter.commitParams(params, mergeKey: -1)
    geometry.expect(model.handleAt(x: Double(model.xForSample(presenter.cropStart)), y: 10) == 1
                    && model.handleAt(x: Double(model.xForSample(presenter.loopStart)), y: 110) == 3,
                    message: "coincident crop and loop starts remain independently reachable")
    geometry.expect(model.press(x: Double(model.xForSample(presenter.cropStart)), y: 10),
                    message: "coincident crop grip begins a drag")
    model.drag(x: Double(model.xForSample(presenter.cropEnd + 100)))
    model.release()
    geometry.expect(presenter.cropStart <= presenter.cropEnd - 2
                    && presenter.loopStart >= presenter.cropStart
                    && presenter.loopEnd < presenter.cropEnd,
                    message: "crop drag preserves an interior loop")
    presenter.undo()
}
