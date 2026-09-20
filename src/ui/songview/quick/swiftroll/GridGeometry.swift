import Foundation
import PorydawCore

func fontPx(_ base: Double, _ multiplier: Double) -> Double {
    multiplier == 0.0 ? 0.0 : max(1.0, (base * multiplier).rounded())
}

func fontPxF(_ base: Double, _ multiplier: Double) -> Double {
    base * multiplier
}

func physicalPixel(_ dpr: Double) -> Double {
    dpr > 0.0 ? 1.0 / dpr : 1.0
}

struct GridMetrics {
    var baseFontPx: Double = 13
    var dpr: Double = 1
    var viewportWidth: Double = 0
    var viewportHeight: Double = 0
    var timeAxis = TimeAxis()

    var rowHeight: Double = 13
    var beatWidth: Double = 35
    var keyboardWidth: Double = 56
    var leadPadWidth: Double = 48

    var noteMinWidth: Double = 2
    var noteMinHeight: Double = 2
    var edgeGripReach: Double = 3.25
    var moveZoneMinWidth: Double = 6.5
    var selectionRingDip: Double = 1.625
    var chipHPadding: Double = 9
    var chipVPadding: Double = 2
    var chipRightInset: Double = 2
    var chipRadius: Double = 3
    var keyLabelRightInset: Double = 3
    var drawThreshold: Double = 3

    var detailMinPxPerBeat: Double = 11
    var gridLineStroke: Double = 2
    var autoGridMinCell: Double = 17
    var snapScale: Int = 0
    var tripletGrid = false

    var rulerMinFontPx: Double = 11
    var rulerLetterSpacing: Double = -0.54
    var rulerBeatLabelZoomFactor: Double = 3.0

    var initialViewportHeight: Double = 217
    var spaceHalf: Double = 2
    var spaceTwo: Double = 7

    var pixel: Double = 1

    static let ticksPerBeat = 24
    static let songLengthTicks = 384

    var documentTicksPerBeat: Int { Int(timeAxis.ticksPerBeat) }
    var pxPerTick: Double { beatWidth / Double(documentTicksPerBeat) }
    var gridHeight: Double { 128.0 * rowHeight }

    static func leadPad(viewportWidth: Double) -> Double {
        min(256.0, max(48.0, (viewportWidth * 0.10).rounded()))
    }

    init(
        baseFontPx: Double, dpr: Double, width: Double, height: Double,
        timeAxis: TimeAxis = TimeAxis()
    ) {
        self.baseFontPx = baseFontPx
        self.dpr = dpr
        viewportWidth = width
        viewportHeight = height
        self.timeAxis = timeAxis
        let b = baseFontPx
        rowHeight = fontPx(b, 1.0)
        beatWidth = fontPx(b, 8.0 / 3.0)
        keyboardWidth = fontPx(b, 13.0 / 3.0)
        leadPadWidth = Self.leadPad(viewportWidth: width)
        noteMinWidth = fontPx(b, 1.0 / 6.0)
        noteMinHeight = fontPx(b, 1.0 / 6.0)
        edgeGripReach = fontPxF(b, 0.25)
        moveZoneMinWidth = fontPxF(b, 0.5)
        selectionRingDip = fontPxF(b, 1.0 / 8.0)
        chipHPadding = fontPx(b, 2.0 / 3.0)
        chipVPadding = fontPx(b, 1.0 / 6.0)
        chipRightInset = fontPx(b, 1.0 / 6.0)
        chipRadius = fontPx(b, 0.25)
        keyLabelRightInset = fontPx(b, 0.25)
        drawThreshold = fontPx(b, 0.25)
        detailMinPxPerBeat = fontPx(b, 5.0 / 6.0)
        gridLineStroke = fontPx(b, 1.0 / 6.0) * physicalPixel(dpr)
        autoGridMinCell = fontPx(b, 4.0 / 3.0)
        rulerMinFontPx = fontPx(b, 5.0 / 6.0)
        rulerLetterSpacing = fontPxF(b, -1.0 / 24.0)
        initialViewportHeight = fontPx(b, 50.0 / 3.0)
        spaceHalf = fontPx(b, 0.125)
        spaceTwo = fontPx(b, 0.5)
        pixel = physicalPixel(dpr)
    }

    func contentX(_ tick: Double) -> Double {
        leadPadWidth + tick * pxPerTick
    }

    func tickAtContentX(_ x: Double) -> Double {
        (x - leadPadWidth) / pxPerTick
    }

    func displayX(_ tick: Double) -> Double {
        let x = contentX(tick)
        return dpr > 0.0 ? (x * dpr).rounded() / dpr : x
    }

    func rowEdge(_ row: Int) -> Double {
        let scale = dpr > 0.0 ? dpr : 1.0
        return (Double(row) * rowHeight * scale).rounded() / scale
    }

    func yToPitch(_ y: Double) -> Int {
        guard y >= rowEdge(0), y < rowEdge(128) else { return -1 }
        var first = 0
        var end = 128
        while first < end {
            let middle = first + (end - first) / 2
            if y < rowEdge(middle + 1) { end = middle } else { first = middle + 1 }
        }
        return 127 - first
    }

    func contentEndTick(gridWidth: Double) -> Double {
        tickAtContentX(gridWidth - pixel + pixel / 2) + 1
    }

    func maxRulerBar(gridWidth: Double) -> Int {
        let end = TimeDefaults.tick(from: contentEndTick(gridWidth: gridWidth))
        var bar = 1
        let segment = timeAxis.segmentAt(end)
        let beat = segment.start + (end - segment.start) / segment.beatTicks * segment.beatTicks
        timeAxis.forEachGridLine(
            from: beat,
            to: end < TimeDefaults.maxTick ? end + 1 : TimeDefaults.noTick
        ) {
            _, _, number, _ in bar = number
        }
        return bar + 1
    }

    // Index into the subdivision ladder whose cell is the coarsest one still
    // at least autoGridMinCell wide on screen.
    private func gridLadderStep(beatTicks: Int) -> Int {
        var step = Self.gridLadder.count - 1
        for i in 0..<Self.gridLadder.count
        where Double(beatTicks) * pxPerTick / Double(Self.gridLadder[i]) >= autoGridMinCell {
            step = i
            break
        }
        return step
    }

    private static let gridLadder = [32, 16, 8, 4, 2, 1]

    var visibleGridTicks: Int {
        visibleGridTicks(in: timeAxis.segmentAt(0))
    }

    func visibleGridTicks(in segment: GridSegment) -> Int {
        let beat = Int(segment.beatTicks)
        return max(1, beat / Self.gridLadder[gridLadderStep(beatTicks: beat)])
    }

    // Signature-relative subdivisions share the existing ladder. TimeAxis owns
    // segment normalization; only visible segments and ticks are visited here.
    func forEachSubdivision(
        from begin: Tick, to end: Tick, _ visit: (Tick, Int) -> Void
    ) {
        var start = begin
        while start < end {
            let segment = timeAxis.segmentAt(start)
            let stop = min(end, segment.next)
            let beat = UInt64(segment.beatTicks)
            let stride = UInt64(visibleGridTicks(in: segment))
            let anchor = UInt64(segment.start)
            let offset = UInt64(start) - anchor
            var tick = anchor + ((offset + stride - 1) / stride) * stride
            while tick < UInt64(stop) {
                let relative = (tick - anchor) % beat
                if relative != 0 {
                    let level = (relative * 2) % beat == 0 ? 1
                        : ((relative * 4) % beat == 0 ? 2 : 3)
                    visit(Tick(tick), level)
                }
                tick += stride
            }
            start = stop
        }
    }

    var snapTicks: Int {
        let beat = Int(timeAxis.segmentAt(0).beatTicks)
        let step = gridLadderStep(beatTicks: beat)
        let visible = max(1, beat / Self.gridLadder[step])
        let fine = step > 0 ? max(1, beat / Self.gridLadder[step - 1]) : visible
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        var result = max(1, gcd(visible, fine))
        if snapScale < 0 {
            for _ in snapScale..<0 { result = max(1, result / 2) }
        } else if snapScale > 0 {
            for _ in 0..<snapScale {
                result = min(Int(TimeDefaults.maxTick), result * 2)
            }
        }
        if tripletGrid {
            result = max(1, result * 2 / 3)
        }
        return result
    }

    private func latticeFloor(_ tick: Double) -> Int {
        let stride = snapTicks
        let position = max(0.0, tick)
        return Int((position / Double(stride)).rounded(.down)) * stride
    }

    private func latticeCeil(_ tick: Double) -> Int {
        let lo = latticeFloor(tick)
        return Double(lo) >= tick ? lo : lo + snapTicks
    }

    func snapTick(_ tick: Double) -> Int {
        let t = max(0.0, tick)
        let lo = latticeFloor(t)
        let hi = latticeCeil(t)
        return (t - Double(lo)) <= (Double(hi) - t) ? lo : hi
    }

    func snapTickDown(_ tick: Double) -> Int { latticeFloor(max(0.0, tick)) }
    func snapTickUp(_ tick: Double) -> Int { latticeCeil(max(0.0, tick)) }

    func noteRect(x0: Double, x1: Double, pitch: Int) -> (
        x: Double, y: Double,
        w: Double, h: Double
    ) {
        let row = 127 - min(127, max(0, pitch))
        let top = rowEdge(row)
        let bottom = rowEdge(row + 1)
        return (
            x0, top + pixel,
            max(noteMinWidth, x1 - x0),
            max(noteMinHeight * pixel, bottom - top - pixel)
        )
    }

    func noteBox(x0: Double, x1: Double, pitch: Int) -> (
        x: Double, y: Double,
        w: Double, h: Double
    ) {
        let r = noteRect(x0: x0, x1: x1, pitch: pitch)
        return (r.x, r.y, r.w, r.h - pixel)
    }

    func edgeGripInnerReach(rectWidth: Double) -> Double {
        min(edgeGripReach, max(0.0, (rectWidth - moveZoneMinWidth) / 2.0))
    }

    func fittedFrameThickness(
        rectWidth: Double, rectHeight: Double,
        requestedPixels: Int, insetPixels: Int
    ) -> Int {
        let minDim = Int((min(rectWidth, rectHeight) * dpr).rounded())
        return min(
            requestedPixels,
            max(0, (minDim - 1) / 2 - insetPixels))
    }

    var noteBorderPixels: Int { max(1, Int(dpr.rounded())) }

    var selectionRingPixels: Int {
        max(1, Int((selectionRingDip * dpr).rounded()))
    }
}
