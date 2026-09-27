import Foundation
import PorydawCore
import QtBridge

func sceneTextDictSignature(_ dict: [String: QVariantSettable]) -> String {
    var parts: [String] = []
    parts.reserveCapacity(dict.count)
    for key in dict.keys.sorted() {
        let value = dict[key].map { "\($0)" } ?? ""
        parts.append("\(key)=\(value)")
    }
    return parts.joined(separator: ",")
}

@MainActor
extension GridScene {

    /// Signatures bail out when nothing changed. Changed rows write in place
    /// (per-row dataChanged, delegates persist) instead of reset(to:), which
    /// destroyed every delegate on every zoom tick.
    func syncText(
        _ model: QListModel<SceneText>, _ records: [SceneText],
        signatures: inout [String]
    ) {
        let next = records.map(\.signature)
        guard next != signatures else { return }
        let common = min(model.count, records.count)
        for i in 0..<common where signatures[i] != next[i] {
            model[i] = records[i]
        }
        if model.count > records.count {
            model.replaceSubrange(records.count..<model.count, with: [])
        } else if records.count > model.count {
            model.replaceSubrange(
                model.count..<model.count, with: records[model.count...])
        }
        signatures = next
    }

    func sync(_ model: QListModel<SceneRect>, _ rects: [SceneRect]) {
        let common = min(model.count, rects.count)
        for i in 0..<common where !model[i].matches(rects[i]) {
            model[i] = rects[i]
        }
        if model.count > rects.count {
            model.replaceSubrange(rects.count..<model.count, with: [])
        } else if rects.count > model.count {
            model.replaceSubrange(
                model.count..<model.count,
                with: rects[model.count...])
        }
    }

    private func addFrame(
        _ rects: inout [SceneRect],
        box: (
            x: Double, y: Double,
            w: Double, h: Double
        ), color: String,
        thicknessPixels: Int, insetPixels: Int,
        metrics m: GridMetrics
    ) {
        let pixel = m.pixel
        let inset = Double(insetPixels) * pixel
        let t = Double(thicknessPixels) * pixel
        let fx = box.x + inset
        let fy = box.y + inset
        let fw = box.w - 2 * inset
        let fh = box.h - 2 * inset
        guard fw > 0, fh > 0 else { return }
        rects.append(
            SceneRect(
                x: fx, y: fy, width: fw, height: t,
                fillColor: color))
        rects.append(
            SceneRect(
                x: fx, y: fy + fh - t, width: fw, height: t,
                fillColor: color))
        let side = max(0.0, fh - 2 * t)
        rects.append(
            SceneRect(
                x: fx, y: fy + t, width: t, height: side,
                fillColor: color))
        rects.append(
            SceneRect(
                x: fx + fw - t, y: fy + t, width: t, height: side,
                fillColor: color))
    }

    func addDashedFrame(
        _ rects: inout [SceneRect],
        box: (x: Double, y: Double, w: Double, h: Double),
        clip: (x: Double, y: Double, w: Double, h: Double),
        color: String, metrics m: GridMetrics
    ) {
        let width = m.pixel
        let dash = fontPx(m.baseFontPx, 0.25)
        let gap = dash
        func addClipped(_ r: (x: Double, y: Double, w: Double, h: Double)) {
            let x0 = max(r.x, clip.x)
            let y0 = max(r.y, clip.y)
            let x1 = min(r.x + r.w, clip.x + clip.w)
            let y1 = min(r.y + r.h, clip.y + clip.h)
            guard x1 > x0, y1 > y0 else { return }
            rects.append(
                SceneRect(
                    x: x0, y: y0, width: x1 - x0, height: y1 - y0,
                    fillColor: color))
        }
        func horizontal(_ x0: Double, _ x1: Double, _ y: Double) {
            guard y + width / 2 > clip.y, y - width / 2 < clip.y + clip.h else { return }
            let period = dash + gap
            var x = x0 + max(0.0, ((clip.x - x0) / period).rounded(.down)) * period
            let end = min(x1, clip.x + clip.w)
            while x < end {
                addClipped((x, y - width / 2, min(x + dash, x1) - x, width))
                x += period
            }
        }
        func vertical(_ x: Double, _ y0: Double, _ y1: Double) {
            guard x + width / 2 > clip.x, x - width / 2 < clip.x + clip.w else { return }
            let period = dash + gap
            var y = y0 + max(0.0, ((clip.y - y0) / period).rounded(.down)) * period
            let end = min(y1, clip.y + clip.h)
            while y < end {
                addClipped((x - width / 2, y, width, min(y + dash, y1) - y))
                y += period
            }
        }
        horizontal(box.x, box.x + box.w, box.y)
        horizontal(box.x, box.x + box.w, box.y + box.h)
        vertical(box.x, box.y, box.y + box.h)
        vertical(box.x + box.w, box.y, box.y + box.h)
    }

    func addNoteBorder(
        _ rects: inout [SceneRect],
        box: (x: Double, y: Double, w: Double, h: Double),
        insetPixels: Int, input: GridSceneInput
    ) {
        let m = input.metrics
        let requested = m.noteBorderPixels
        let fitted = m.fittedFrameThickness(
            rectWidth: box.w, rectHeight: box.h,
            requestedPixels: requested,
            insetPixels: insetPixels)
        var color = input.palette.noteBorder
        if fitted == 0 {
            let alpha = min(0.85, max(0.25, min(box.w, box.h) / (3.0 * m.pixel)))
            color = PaletteMath.hex(r: 0, g: 0, b: 0, a: Int((alpha * 255).rounded()))
        }
        addFrame(
            &rects, box: box, color: color, thicknessPixels: max(1, fitted),
            insetPixels: insetPixels, metrics: m)
    }

    func timeCovers(_ input: GridSceneInput, track: Int, tick: Int, end: Int) -> Bool {
        guard let selection = input.timeSelection, selection.isActive else { return false }
        guard case let .tracks(scope) = selection.scope else { return false }
        guard scope.contains(track), track >= 0, track < input.usedTrackCount else { return false }
        return Int(selection.range.startTick) < end && Int(selection.range.endTick) > tick
    }

    func addSelectionRing(
        _ rects: inout [SceneRect],
        box: (x: Double, y: Double, w: Double, h: Double),
        input: GridSceneInput
    ) {
        let m = input.metrics
        let requested = m.selectionRingPixels
        let ring = m.fittedFrameThickness(
            rectWidth: box.w, rectHeight: box.h,
            requestedPixels: requested, insetPixels: 0)
        if ring > 0 {
            addFrame(
                &rects, box: box, color: input.palette.selectionRing,
                thicknessPixels: ring, insetPixels: 0, metrics: m)
            addNoteBorder(&rects, box: box, insetPixels: ring, input: input)
        } else {
            rects.append(
                SceneRect(
                    x: box.x, y: box.y, width: box.w,
                    height: box.h, fillColor: input.palette.selectionRing))
        }
    }
}
