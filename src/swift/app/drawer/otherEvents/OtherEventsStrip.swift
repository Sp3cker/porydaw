import Foundation
import PorydawCore

public struct OtherEventsStripItem: Equatable {
    public let tick: Tick
    public let sample: UInt64
    public let track: Int
    public let label: String
}

public struct OtherEventsMarker: Equatable {
    public let tick: Tick
    public let track: Int
    public let x: Double
    public let color: String
    public let label: String
}

public enum OtherEventsStrip {
    public static func bandHeight(baseFontPx: Double, appFontLineSpacing: Double) -> Int {
        let base = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx : GridCameraPolicy.seedBaseFontPx
        let spacing = appFontLineSpacing.isFinite ? max(0, appFontLineSpacing) : 0
        return Int(spacing) + Int(fontPx(base, 0.5))
    }

    public static func items(timeline: PlaybackTimeline) -> [OtherEventsStripItem] {
        let events = timeline.events
        let ccEvents = events.enumerated().compactMap { index, event -> Xcmd.Event? in
            guard event.type == 0xB else { return nil }
            return Xcmd.Event(index: UInt64(index), tick: event.tick, stream: event.track,
                              controller: event.data0, value: event.data1)
        }
        let consumed = Set(Xcmd.project(ccEvents).consumed)
        var open = Array(repeating: 0, count: TrackLimits.hardwareCapacity * 128)
        var result: [OtherEventsStripItem] = []
        result.reserveCapacity(events.count + timeline.otherEvents.count)
        for (index, event) in events.enumerated() {
            if consumed.contains(UInt64(index)) { continue }
            let track = Int(event.track)
            switch event.type {
            case 0x9:
                open[track * 128 + Int(event.data0 & 0x7F)] += 1
            case 0x8:
                let slot = track * 128 + Int(event.data0 & 0x7F)
                if open[slot] == 0 {
                    result.append(OtherEventsStripItem(tick: event.tick, sample: event.sample,
                        track: track,
                        label: "Note off (key \(event.data0)) without a note on"))
                } else {
                    open[slot] -= 1
                }
            case 0xB:
                if m4aClassifyCC(event.data0).eventClass != .audibleLane {
                    result.append(OtherEventsStripItem(tick: event.tick, sample: event.sample,
                        track: track,
                        label: m4aAdvancedCCLabel(controller: event.data0, value: event.data1)))
                }
            default:
                break
            }
        }
        for other in timeline.otherEvents {
            result.append(OtherEventsStripItem(tick: other.tick, sample: other.sample,
                                               track: other.track, label: other.label))
        }
        return result.enumerated().sorted {
            $0.element.tick == $1.element.tick ? $0.offset < $1.offset
                : $0.element.tick < $1.element.tick
        }.map(\.element)
    }

    @MainActor
    public static func markers(items: [OtherEventsStripItem], camera: EditorCamera,
                               plotWidth: Double, baseFontPx: Double,
                               palette: GridPalette) -> [OtherEventsMarker] {
        let slop = fontPx(baseFontPx, 1.0 / 3.0)
        return items.compactMap { item in
            let x = camera.contentX(tick: Double(item.tick))
            guard x >= -slop && x <= plotWidth + slop else { return nil }
            let color = item.track >= 0
                ? PaletteMath.trackIdentityFills[PaletteMath.trackIdentityIndex(item.track)]
                : palette.outline
            return OtherEventsMarker(tick: item.tick, track: item.track, x: x,
                                     color: color, label: item.label)
        }
    }

    public static func tooltipLines(items: [OtherEventsStripItem], x: Double,
                                    camera: EditorCamera, baseFontPx: Double,
                                    sampleRate: Double) -> [String] {
        guard sampleRate > 0 else { return [] }
        let slop = fontPx(baseFontPx, 1.0 / 3.0)
        var lines: [String] = []
        for item in items where abs(camera.contentX(tick: Double(item.tick)) - x) <= slop {
            if lines.count == 12 {
                lines.append("…")
                break
            }
            let seconds = Int(Double(item.sample) / sampleRate)
            let whereText = item.track >= 0 ? "Track \(item.track + 1)" : "File"
            lines.append("\(seconds / 60):\(String(format: "%02d", seconds % 60)) · \(whereText) · \(item.label)")
        }
        return lines
    }
}
