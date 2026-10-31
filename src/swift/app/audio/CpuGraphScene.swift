import Foundation
import NativeDisplayList
import PorydawAppPresentation
import QtBridge

/// One mounted graph's retained geometry and pointer projection; never shared between editors.
@MainActor
@QtBridgeable
public final class CpuGraphScene: QmlInstantiable {
    public var displayRevision: Int = 0
    @QtTracked public var meter: CpuMeterPresenter?
    @QtTracked public var palette: GridPalette?

    private struct Colors: Equatable {
        let low: UInt32
        let warning: UInt32
        let error: UInt32

        @MainActor init(_ palette: GridPalette) {
            low = PaletteMath.argb(palette.polyphonyActiveFill)
            warning = PaletteMath.argb(palette.warningText)
            error = PaletteMath.argb(palette.errorText)
        }

        @MainActor func ink(cycles: Int, budget: Int, warmth: Bool) -> UInt32 {
            if cycles > CpuMeterPresenter.vblankCycles { return error }
            if cycles > budget { return warning }
            guard warmth, budget > 0 else { return low }
            let blend = pow(min(1, Double(cycles) / Double(budget)), 1.5) * 0.75
            let overlayAlpha = Double(warning >> 24) / 255 * blend
            let baseAlpha = Double(low >> 24) / 255 * (1 - overlayAlpha)
            let alpha = overlayAlpha + baseAlpha
            guard alpha > 0 else { return 0 }
            var result = UInt32((alpha * 255).rounded()) << 24
            for shift in stride(from: 0, through: 16, by: 8) {
                let channel =
                    (Double((low >> shift) & 255) * baseAlpha
                        + Double((warning >> shift) & 255) * overlayAlpha) / alpha
                result |= UInt32(channel.rounded()) << shift
            }
            return result
        }
    }

    private enum Content: Equatable {
        case history(revision: Int)
        case profile(revision: Int, scrollX: Double, beatWidth: Double, ticksPerBeat: Int, dpr: Double)
    }

    private struct Frame: Equatable {
        let meter: ObjectIdentifier
        let content: Content
        let width: Double
        let height: Double
        let colors: Colors
        let budget: Int
    }

    private var frame: Frame?
    private var writer = DisplayListWriter()
    // Clear this alias before rebuilding so the writer can reuse its Data storage without COW.
    private var bytes = Data()
    private var values: [Int] = []
    private var profileWidth = 0.0

    public required init() {
        bytes = writer.finish()
    }

    /// The generic native renderer reads this frame directly, before scene-graph synchronization.
    public func displayList(list: Int) -> Data {
        precondition(list == 0)
        return bytes
    }

    /// Returns the same span maximum that is painted under this local pointer coordinate.
    public func cyclesAt(x: Double) -> Int {
        guard x.isFinite, x >= 0, x < profileWidth, !values.isEmpty else { return -1 }
        return values[min(values.count - 1, Int(x * Double(values.count) / profileWidth))]
    }

    private func rect(x: Double, y: Double, width: Double, height: Double, ink: UInt32) {
        guard width > 0, height > 0 else { return }
        writer.rect(PdDlRect(x: x, y: y, w: width, h: height, id: UInt64(PD_DL_ID_NONE), argb: ink, flags: 0))
    }

    private func finish(_ next: Frame) {
        bytes = writer.finish()
        frame = next
        displayRevision &+= 1
    }

    private func clearFrame() {
        guard frame != nil else { return }
        bytes = Data()
        values.removeAll(keepingCapacity: true)
        profileWidth = 0
        bytes = writer.finish()
        frame = nil
        displayRevision &+= 1
    }

    /// Builds only for a mounted history panel; the meter continues retaining history while hidden.
    public func updateHistory(width: Double, height: Double) {
        guard let meter, let palette else {
            clearFrame()
            return
        }
        let next = Frame(
            meter: ObjectIdentifier(meter), content: .history(revision: meter.historyRevision),
            width: width, height: height, colors: Colors(palette), budget: meter.budget)
        guard next != frame else { return }
        bytes = Data()
        let scale = Double(CpuMeterPresenter.vblankCycles) * 1.4
        let capacity = Double(CpuMeterPresenter.historyCapacity)
        for index in meter.historyFrames.indices {
            let cycles = meter.historyFrames[index]
            guard cycles >= 0 else { continue }
            let barHeight = min(height, height * Double(cycles) / scale)
            rect(
                x: width * Double(CpuMeterPresenter.historyCapacity - meter.historyFrames.count + index) / capacity,
                y: height - barHeight, width: max(1, width / capacity), height: barHeight,
                ink: next.colors.ink(cycles: cycles, budget: next.budget, warmth: false))
        }
        finish(next)
    }

    private func projectProfile(
        profile: borrowing [CpuProfilePoint], endTick: Double,
        width: Double, scrollX: Double, pixelsPerTick: Double
    ) {
        let firstTick = max(0, scrollX / pixelsPerTick)
        let points = profile.span
        var low = 0
        var high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].tick <= firstTick { low = mid + 1 } else { high = mid }
        }
        var point = max(0, low - 1)
        let count = values.count
        for column in 0..<count {
            let left = (scrollX + Double(column) * width / Double(count)) / pixelsPerTick
            let right = (scrollX + Double(column + 1) * width / Double(count)) / pixelsPerTick
            if right <= points[0].tick || left >= endTick {
                values[column] = -1
                continue
            }
            while point + 1 < points.count && points[point + 1].tick <= left { point += 1 }
            var value = points[point].total
            while point + 1 < points.count && points[point + 1].tick < right {
                point += 1
                value = max(value, points[point].total)
            }
            values[column] = value
        }
    }

    /// Downsamples each physical-pixel span by its maximum, extending frames only to their next tick.
    public func updateProfile(
        width: Double, height: Double,
        scrollX: Double, beatWidth: Double, ticksPerBeat: Int, devicePixelRatio: Double
    ) {
        guard let meter, let palette else {
            clearFrame()
            return
        }
        let dpr = max(1, devicePixelRatio)
        let next = Frame(
            meter: ObjectIdentifier(meter),
            content: .profile(
                revision: meter.profileDataRevision, scrollX: scrollX,
                beatWidth: beatWidth, ticksPerBeat: ticksPerBeat, dpr: dpr),
            width: width, height: height, colors: Colors(palette), budget: meter.budget)
        guard next != frame else { return }
        bytes = Data()
        profileWidth = width
        let count = min(16_384, max(0, Int((width * dpr).rounded(.up))))
        guard count > 0, height > 0, beatWidth > 0, ticksPerBeat > 0, !meter.profilePoints.isEmpty else {
            values.removeAll(keepingCapacity: true)
            finish(next)
            return
        }
        if values.count < count { values.append(contentsOf: repeatElement(-1, count: count - values.count)) }
        if values.count > count { values.removeLast(values.count - count) }
        projectProfile(
            profile: meter.profilePoints, endTick: meter.profileEndTick,
            width: width, scrollX: scrollX, pixelsPerTick: beatWidth / Double(ticksPerBeat))
        var start = 0
        while start < count {
            let cycles = values[start]
            var end = start + 1
            while end < count && values[end] == cycles { end += 1 }
            if cycles >= 0 {
                let x = width * Double(start) / Double(count)
                rect(
                    x: x, y: 1 / dpr,
                    width: min(width, width * Double(end) / Double(count) + 0.05) - x,
                    height: max(0, height - 2 / dpr),
                    ink: next.colors.ink(cycles: cycles, budget: next.budget, warmth: true))
            }
            start = end
        }
        finish(next)
    }
}
