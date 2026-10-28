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
    let pyramidRevision = model.pyramidRevision
    tools.setCrossfade(on: true)
    presenter.undo()
    let togglesAsOneEntry = !presenter.params.crossfadeOn && presenter.canRedo
    presenter.redo()
    scoped.expect(
        togglesAsOneEntry && presenter.params.crossfadeOn,
        message: "A083 crossfade toggle creates an undo entry")
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
    display.expect(
        mainColors?.contains(PaletteMath.argb(palette.sampleWaveformInk)) == true
            && mainColors?.contains(PaletteMath.argb(palette.sampleCropHandle)) == true
            && mainColors?.contains(PaletteMath.argb(palette.sampleLoopHandle)) == true,
        message: "decoded main list draws ink and both marker colors")
    display.expect(
        main.withUnsafeBytes { raw -> Bool in
            var view = PdDlView()
            guard pd_dl_decode(raw.baseAddress, raw.count, &view),
                let header = view.header, let labels = view.labels
            else { return false }
            let tabs = (0..<Int(header.pointee.labelCount)).filter { (index: Int) -> Bool in
                labels[index].id != UInt64(PD_DL_ID_NONE)
            }
            return tabs.count == model.markers.count
                && tabs.allSatisfy { (index: Int) -> Bool in labels[index].textLength > 0 }
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

    let slices = report.scoped(cppID: "swiftcore/MarkerWaveformModel::sliceOverlay")
    func sliceBadges(_ data: Data) -> [(x: Double, text: String)]? {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [(x: Double, text: String)]? in
            var view = PdDlView()
            guard pd_dl_decode(raw.baseAddress, raw.count, &view),
                let header = view.header, let labels = view.labels, let text = view.text
            else { return nil }
            var badges: [(x: Double, text: String)] = []
            for index in 0..<Int(header.pointee.labelCount) {
                let label = labels[index]
                // Ruler ticks share the id-less label kind but sit in the top band.
                guard label.id == UInt64(PD_DL_ID_NONE), label.y > 0 else { continue }
                let base = UnsafeRawPointer(text.advanced(by: Int(label.textOffset)))
                let bytes = Data(bytes: base, count: Int(label.textLength))
                guard let string = String(data: bytes, encoding: .utf8) else { return nil }
                badges.append((label.x, string))
            }
            return badges.sorted { (lhs: (x: Double, text: String), rhs: (x: Double, text: String)) -> Bool in
                lhs.x < rhs.x
            }
        }
    }
    func washRects(_ data: Data, color: UInt32) -> [PdDlRect] {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [PdDlRect] in
            var view = PdDlView()
            guard pd_dl_decode(raw.baseAddress, raw.count, &view),
                let header = view.header, let rects = view.rects
            else { return [] }
            return (0..<Int(header.pointee.rectCount))
                .map { (index: Int) -> PdDlRect in rects[index] }
                .filter { (rect: PdDlRect) -> Bool in rect.argb == color }
        }
    }
    let accent = PaletteMath.argb(palette.sampleWaveformInk)
    let dimInk = (accent & 0x00FF_FFFF) | 0xB800_0000
    let washInk = (accent & 0x00FF_FFFF) | 0x1C00_0000
    model.setRegionBadges(frames: [8_000, 0, 4_000], numbers: [3, 1, 2])
    model.setHighlight(startFrame: 4_000, endFrame: 8_000)
    let numbered = sliceBadges(model.displayList(list: 0)) ?? []
    slices.expect(
        numbered.map { (badge: (x: Double, text: String)) -> String in badge.text } == ["1", "2", "3"],
        message: "slice badges number every region in frame order")
    slices.expect(
        numbered.count == 3 && numbered[0].x >= Double(model.xForFrame(0))
            && numbered[0].x <= Double(model.xForFrame(0)) + 16
            && numbered[1].x >= Double(model.xForFrame(4_000))
            && numbered[2].x >= Double(model.xForFrame(8_000)) && numbered[0].x < numbered[1].x
            && numbered[1].x < numbered[2].x,
        message: "badges sit at the top-left of their own region")
    let washes = washRects(model.displayList(list: 0), color: washInk)
    slices.expect(
        washes.count == 1 && abs(washes[0].x - Double(model.xForFrame(4_000))) <= 1
            && abs(washes[0].x + washes[0].w - Double(model.xForFrame(8_000))) <= 1,
        message: "highlight washes the selected slice range")
    slices.expect(
        colors(model.displayList(list: 0))?.contains(accent) == true
            && colors(model.displayList(list: 0))?.contains(dimInk) == true
            && colors(model.displayList(list: 0))?.contains(washInk) == true,
        message: "selected slice keeps full accent while other slices dim")
    model.setHighlight(startFrame: -1_000, endFrame: 1_000_000)
    let clamped = washRects(model.displayList(list: 0), color: washInk)
    slices.expect(
        clamped.count == 1 && clamped[0].x == 0 && clamped[0].x + clamped[0].w >= 590
            && colors(model.displayList(list: 0))?.contains(dimInk) == false,
        message: "out-of-range highlight clamps to the loaded source")
    model.setHighlight(startFrame: 8_000, endFrame: 4_000)
    slices.expect(
        colors(model.displayList(list: 0))?.contains(washInk) == false
            && colors(model.displayList(list: 0))?.contains(dimInk) == false,
        message: "reversed highlight draws no wash and dims nothing")
    model.setRegionBadges(frames: [0], numbers: [1, 2])
    slices.expect(
        sliceBadges(model.displayList(list: 0))?.map { (badge: (x: Double, text: String)) -> String in
            badge.text
        } == ["1"],
        message: "badge pairs truncate to the shorter array")
    model.setRegionBadges(frames: [], numbers: [])
    model.setHighlight(startFrame: 0, endFrame: 0)
    slices.expect(
        sliceBadges(model.displayList(list: 0))?.isEmpty == true
            && colors(model.displayList(list: 0))?.contains(washInk) == false,
        message: "clearing badges and highlight removes the overlay")
}
