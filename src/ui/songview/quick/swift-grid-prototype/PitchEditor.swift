import Foundation
import QtBridge

struct PitchPopupGeometry {
    let graph: PitchGraphGeometry
    let metrics: [String: QVariantSettable]

    init(base: Double, dpr: Double, titleHeight: Double, captionHeight: Double) {
        let px = { (ratio: Double) in (base * ratio).rounded() }
        let inset = px(4 / 7)
        let gap = px(0.25)
        let fieldHeight = px(12 / 7)
        let canvasY = titleHeight + px(1.5)
        let graphHeight = canvasY + px(8) + captionHeight + 2 * gap
        let headerHeight = inset + titleHeight + captionHeight + 2 * gap + fieldHeight
        graph = PitchGraphGeometry(
            x: px(26 / 7), y: canvasY, width: px(20), height: px(8),
            hairline: 1 / dpr, zeroDetent: base * 4 / 7,
            hitRadius: base * 4 / 7, nodeRadius: base * 3 / 14,
            selectedRadius: base * 3 / 7, stroke: base / 7)
        metrics = [
            "popupWidth": graph.x + graph.width + inset,
            "popupHeight": headerHeight + 2 * graphHeight,
            "headerHeight": headerHeight, "graphHeight": graphHeight,
            "outerInset": inset, "titleHeight": titleHeight,
            "descriptionHeight": captionHeight, "controlsHeight": fieldHeight,
            "fieldWidth": px(39 / 7), "fieldHeight": fieldHeight,
            "resetWidth": px(30 / 7), "resetHeight": px(13 / 7),
            "axisLabelHeight": captionHeight + gap,
            "scrubThreshold": base * 3 / 14, "hairline": 1 / dpr,
        ]
    }
}

@MainActor
@QtBridgeable
public final class PitchEditor {
    @QtTracked public let pitchGraph: PitchGraph
    @QtTracked public let modGraph: PitchGraph
    public var metrics: [String: QVariantSettable]
    public let appearance: [String: QVariantSettable]
    public let noteDescription: String
    public let startTick: Int
    public var description: String = ""
    public var bendRange: Int
    public var lfoSpeed: Int

    @QtSignal public func previewRequested()
    @QtSignal public func commitRequested()
    @QtSignal public func cancelRequested()
    @QtSignal public func auditionRequested()

    @QtIgnored private let baseline: [GridControllerEvent]
    @QtIgnored private let originalCurves: [Int: [Int: Int]]
    @QtIgnored private let originalNumeric: [Int: Int]
    @QtIgnored private let track: Int
    @QtIgnored private let endTick: Int
    @QtIgnored private let baseFontPx: Double
    @QtIgnored private let dpr: Double
    @QtIgnored private var titleHeight: Double
    @QtIgnored private var captionHeight: Double
    @QtIgnored private var numericChanges: [Int: Int] = [:]

    init(
        note: GridNote, events: [GridControllerEvent], baseFontPx: Double, dpr: Double,
        titleHeight: Double, captionHeight: Double, bodyFamily: String, monoFamily: String,
        palette: GridPalette
    ) {
        baseline = events
        track = note.track
        startTick = note.tick
        endTick = note.tick + note.duration
        self.baseFontPx = baseFontPx
        self.dpr = dpr
        self.titleHeight = titleHeight
        self.captionHeight = captionHeight
        let geometry = PitchPopupGeometry(
            base: baseFontPx, dpr: dpr,
            titleHeight: titleHeight, captionHeight: captionHeight)
        metrics = geometry.metrics
        let trackEvents = events.filter { $0.track == note.track }
        func value(_ controller: Int, at tick: Int, default initial: Int) -> Int {
            trackEvents.filter { $0.controller == controller && $0.tick <= tick }
                .max(by: { $0.tick < $1.tick })?.value ?? initial
        }
        func curve(_ controller: Int) -> [Int: Int] {
            var result = [note.tick: value(controller, at: note.tick, default: 0)]
            for event in trackEvents
            where event.controller == controller
                && event.tick >= note.tick && event.tick < note.tick + note.duration
            {
                result[event.tick] = event.value
            }
            return result
        }
        bendRange = value(20, at: note.tick, default: 2)
        lfoSpeed = value(21, at: note.tick, default: 22)
        pitchGraph = PitchGraph(
            start: note.tick, end: endTick, curve: curve(255),
            endValue: value(255, at: endTick, default: 0),
            track: note.track, pitch: true, bendRange: bendRange,
            geometry: geometry.graph)
        modGraph = PitchGraph(
            start: note.tick, end: endTick, curve: curve(1),
            endValue: value(1, at: endTick, default: 0),
            track: note.track, pitch: false, bendRange: bendRange,
            geometry: geometry.graph)
        originalCurves = [255: pitchGraph.points, 1: modGraph.points]
        originalNumeric = [20: bendRange, 21: lfoSpeed]
        noteDescription = "\(GridScene.keyName(note.pitch)) · note-scoped · channel-wide"
        let bodyPx = (baseFontPx * 1.125).rounded()
        let bodyFont: [String: QVariantSettable] =
            ["family": bodyFamily, "pixelSize": bodyPx, "weight": 400]
        let titleFont: [String: QVariantSettable] =
            ["family": bodyFamily, "pixelSize": bodyPx, "weight": 600]
        let captionFont: [String: QVariantSettable] =
            ["family": bodyFamily, "pixelSize": baseFontPx.rounded(), "weight": 400]
        let monoFont: [String: QVariantSettable] =
            ["family": monoFamily, "pixelSize": bodyPx, "weight": 400]
        let dragInput: [String: QVariantSettable] = [
            "background": "#ECE7E1", "text": palette.primaryText,
            "outline": palette.outline, "focus": palette.outline, "font": bodyFont,
            "borderWidth": 1 / dpr, "radius": (baseFontPx * 0.25).rounded(),
            "horizontalPadding": (baseFontPx * 0.25).rounded(),
            "verticalPadding": (baseFontPx * 0.125).rounded(), "dragThreshold": baseFontPx * 3 / 14,
        ]
        appearance = [
            "windowBackground": palette.windowBackground,
            "primaryText": palette.primaryText, "secondaryText": palette.secondaryText,
            "outline": palette.outline, "focus": palette.outline,
            "trackColor": PaletteMath.trackIdentityFills[
                PaletteMath.trackIdentityIndex(note.track)],
            "font": bodyFont, "titleFont": titleFont, "captionFont": captionFont,
            "monospaceFont": monoFont, "dragInput": dragInput,
        ]
        refreshDescription()
    }

    public func setFontHeights(title: Double, caption: Double) {
        if title == titleHeight && caption == captionHeight { return }
        titleHeight = title
        captionHeight = caption
        let geometry = PitchPopupGeometry(
            base: baseFontPx, dpr: dpr,
            titleHeight: title, captionHeight: caption)
        metrics = geometry.metrics
        pitchGraph.setGeometry(geometry.graph)
        modGraph.setGeometry(geometry.graph)
    }

    public func setBendRange(value: Int) {
        bendRange = min(127, max(0, value))
        numericChanges[20] = bendRange == originalNumeric[20] ? nil : bendRange
        pitchGraph.setRange(bendRange)
        refreshDescription()
        previewRequested()
        commitRequested()
    }

    public func changeBendRange(steps: Int) {
        setBendRange(value: bendRange + steps)
    }

    public func setLfoSpeed(value: Int) {
        lfoSpeed = min(127, max(0, value))
        numericChanges[21] = lfoSpeed == originalNumeric[21] ? nil : lfoSpeed
        refreshDescription()
        previewRequested()
        commitRequested()
    }

    public func resetPitchCurve() { pitchGraph.resetCurve() }
    public func resetModCurve() { modGraph.resetCurve() }

    public func cancelAndClose() {
        pitchGraph.cancelPointerSilently()
        modGraph.cancelPointerSilently()
        cancelRequested()
    }

    public func routeUnclaimedKey(key: Int, modifiers: Int, autoRepeat: Bool) {
        if key == 0x20 && !autoRepeat { auditionRequested() }
    }

    @QtIgnored
    func controllerEvents() -> [GridControllerEvent] {
        var result = baseline
        for (controller, graph) in [(255, pitchGraph), (1, modGraph)] {
            let points = graph.points
            if points == originalCurves[controller] { continue }
            result.removeAll {
                $0.track == track && $0.controller == controller
                    && $0.tick >= startTick && $0.tick <= endTick
            }
            for (tick, value) in points {
                result.append(
                    GridControllerEvent(
                        tick: tick, track: track,
                        controller: controller, value: value))
            }
        }
        for (controller, value) in numericChanges {
            result.removeAll {
                $0.track == track && $0.controller == controller && $0.tick == startTick
            }
            result.append(
                GridControllerEvent(
                    tick: startTick, track: track,
                    controller: controller, value: value))
        }
        return result.sorted {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            if $0.track != $1.track { return $0.track < $1.track }
            return $0.controller < $1.controller
        }
    }

    @QtIgnored
    private func refreshDescription() {
        description =
            "\(noteDescription). Pitch-bend range \(bendRange) semitones; LFO speed \(lfoSpeed)."
    }
}
