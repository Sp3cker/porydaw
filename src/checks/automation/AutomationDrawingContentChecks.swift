import Foundation
import PorydawCore

@testable import PorydawApp

struct AutomationDrawerProbe {
    struct Rect {
        let start: UInt32
        let end: UInt32
        let y: Float
        let height: Float
        let color: UInt32
        let flags: UInt8
    }
    struct Anchor {
        let tick: UInt32
        let dx: Float
        let width: Float
        let y: Float
        let height: Float
        let color: UInt32
        let flags: UInt8
    }
    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        mutating func u8() -> UInt8? {
            guard offset < bytes.count else { return nil }
            defer { offset += 1 }
            return bytes[offset]
        }
        mutating func u16() -> UInt16? {
            guard let a = u8(), let b = u8() else { return nil }
            return UInt16(a) | UInt16(b) << 8
        }
        mutating func u32() -> UInt32? {
            guard let a = u16(), let b = u16() else { return nil }
            return UInt32(a) | UInt32(b) << 16
        }
        mutating func f32() -> Float? {
            guard let bits = u32() else { return nil }
            return Float(bitPattern: bits)
        }
        mutating func f64() -> Double? {
            guard let low = u32(), let high = u32() else { return nil }
            return Double(bitPattern: UInt64(low) | UInt64(high) << 32)
        }
    }

    let valid: Bool
    let rects: [Rect]
    let anchors: [Anchor]
    let sectionOrder: [UInt16]
    let rectSections: [Range<Int>]
    let anchorSections: [Range<Int>]
    let gridDescriptor: [UInt8]
    let metrics: [Double]

    var axisRects: ArraySlice<Rect> { rectSections.first.map { rects[$0] } ?? [] }
    var selectionRects: ArraySlice<Rect> { rectSections.dropFirst(3).first.map { rects[$0] } ?? [] }
    var selectionEdges: ArraySlice<Anchor> {
        anchorSections.dropFirst(2).first.map { anchors[$0] } ?? []
    }
    var previewNodes: ArraySlice<Anchor> {
        anchorSections.dropFirst(3).first.map { anchors[$0] } ?? []
    }
    var previewRuns: ArraySlice<Rect> { rectSections.dropFirst(4).first.map { rects[$0] } ?? [] }

    init(_ data: Data) {
        var reader = Reader(bytes: Array(data))
        var rects: [Rect] = []
        var anchors: [Anchor] = []
        var rectSections: [Range<Int>] = []
        var anchorSections: [Range<Int>] = []
        var gridDescriptor: [UInt8] = []
        var metrics: [Double] = []
        var order: [UInt16] = []
        var valid = reader.u32() == 0x5054_4452 && reader.u16() == 1
        guard let count = reader.u16(), valid else {
            self.valid = false
            self.rects = []
            self.anchors = []
            self.sectionOrder = []
            self.rectSections = []
            self.anchorSections = []
            self.gridDescriptor = []
            self.metrics = []
            return
        }
        for _ in 0..<count {
            guard let kind = reader.u16(), let length = reader.u32(),
                Int(length) <= reader.bytes.count - reader.offset
            else {
                valid = false
                break
            }
            let end = reader.offset + Int(length)
            order.append(kind)
            if kind == 1 {
                guard length == 15 * 8 else {
                    valid = false
                    break
                }
                for _ in 0..<15 {
                    guard let value = reader.f64() else {
                        valid = false
                        break
                    }
                    metrics.append(value)
                }
                if !valid || reader.offset != end {
                    valid = false
                    break
                }
            }
            if kind == 7 {
                gridDescriptor = Array(reader.bytes[reader.offset..<end])
            }
            if kind == 13 && length != 0 {
                valid = false
                break
            }
            let rectStart = rects.count
            let anchorStart = anchors.count
            if kind == 11 || kind == 12 {
                guard let itemCount = reader.u32(),
                    Int(itemCount) <= (end - reader.offset) / (kind == 11 ? 21 : 25)
                else {
                    valid = false
                    break
                }
                for _ in 0..<itemCount {
                    if kind == 11 {
                        guard let start = reader.u32(), let finish = reader.u32(),
                            let y = reader.f32(), let height = reader.f32(),
                            let color = reader.u32(), let flags = reader.u8()
                        else {
                            valid = false
                            break
                        }
                        rects.append(
                            Rect(
                                start: start, end: finish, y: y,
                                height: height, color: color, flags: flags))
                    } else {
                        guard let tick = reader.u32(), let dx = reader.f32(),
                            let width = reader.f32(), let y = reader.f32(),
                            let height = reader.f32(), let color = reader.u32(),
                            let flags = reader.u8()
                        else {
                            valid = false
                            break
                        }
                        anchors.append(
                            Anchor(
                                tick: tick, dx: dx, width: width,
                                y: y, height: height, color: color, flags: flags))
                    }
                }
                valid = valid && reader.offset == end
                if kind == 11 {
                    rectSections.append(rectStart..<rects.count)
                } else {
                    anchorSections.append(anchorStart..<anchors.count)
                }
            }
            reader.offset = end
        }
        self.valid = valid && reader.offset == reader.bytes.count
        self.rects = rects
        self.anchors = anchors
        self.rectSections = rectSections
        self.anchorSections = anchorSections
        self.gridDescriptor = gridDescriptor
        self.metrics = metrics
        sectionOrder = order
    }
}

@MainActor
func drawerAutomationDrawingContentChecks(
    _ report: CheckReport,
    suite: DocumentSession, service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(0, 30), (24, 100)])
    let page = fixture.page
    _ = page.activateParameter(index: 0)
    let initial = page.drawingContent()
    let revision = page.contentRevision
    let probe = AutomationDrawerProbe(initial)
    let ink = SceneRectPacking.argb(page.palette.automationNodeInk)
    report.expect(
        probe.valid && probe.sectionOrder == [1, 3, 7, 11, 13, 11, 12, 11, 12, 11, 12, 13, 12, 11]
            && probe.metrics.count == 15 && probe.metrics[6] > 0 && probe.metrics[7] > 0
            && !probe.axisRects.isEmpty && probe.axisRects.allSatisfy { $0.flags == 3 }
            && probe.rects.contains { $0.start == 0 && $0.end == 24 && $0.color == ink && $0.flags == 0 }
            && probe.anchors.contains { $0.tick == 24 && $0.width == 2 && $0.color == ink && $0.flags == 1 },
        cppID: drawerAutomationProjectionID,
        message: "automation blob carries roll metrics, sticky axis chrome and anchored curve")
    fixture.session.mutateCamera { _ = $0.setHScroll(17) }
    page.refreshCamera()
    report.expect(
        page.contentRevision == revision && page.drawingContent() == initial,
        cppID: drawerAutomationProjectionID,
        message: "automation scroll preserves content bytes and revision")
    fixture.session.mutateCamera { $0.setTimeZoom($0.snapshot.pixelsPerBeat * 2) }
    page.refreshCamera()
    report.expect(
        page.contentRevision == revision && page.drawingContent() == initial,
        cppID: drawerAutomationProjectionID,
        message: "automation zoom preserves content bytes and revision")
    page.palette.gridLineBar = "#FF214365"
    page.refreshFromDocument()
    let changed = AutomationDrawerProbe(page.drawingContent())
    report.expect(
        changed.valid && page.contentRevision == revision + 1
            && page.drawingContent() != initial,
        cppID: drawerAutomationProjectionID,
        message: "automation palette edit publishes one new blob revision")
    let paletteRevision = page.contentRevision
    page.selectRange(from: 12, to: 48)
    page.refreshFromDocument()
    let selected = AutomationDrawerProbe(page.drawingContent())
    report.expect(
        selected.valid && page.contentRevision == paletteRevision + 1
            && selected.rects.contains {
                $0.start == 12 && $0.end == 48
                    && $0.color == SceneRectPacking.argb(page.palette.selectionFill)
            }
            && selected.anchors.contains {
                $0.tick == 12 && $0.width == 1
                    && $0.color == SceneRectPacking.argb(page.palette.selectionEdge)
            }
            && selected.anchors.contains { $0.tick == 48 && $0.dx == -1 },
        cppID: drawerAutomationProjectionID,
        message: "automation selection emits tick span and anchored pixel-width edges")
    page.detach()
}
