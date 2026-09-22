import Foundation
import PorydawApp
import PorydawCore

enum HeaderProbe { case title, voice, mute, solo, add }

@MainActor
extension TrackHeadersFixture {
    func point(_ probe: HeaderProbe, row: Int = 0) -> (x: Double, y: Double) {
        let offset = Double(row * headers.rowHeight) - headers.scrollY
        if probe == .add {
            return (headers.trackHeaderWidth / 2, offset + Double(headers.rowHeight) / 2)
        }
        let rect = switch probe {
        case .title: headers.rows[row].titleRect
        case .voice: headers.rows[row].subtitleRect
        case .mute: headers.muteButtonRect
        case .solo: headers.soloButtonRect
        case .add: headers.renameEditorRect
        }
        return ((rect["x"] as? Double ?? 0) + (rect["width"] as? Double ?? 0) / 2,
                offset + (rect["y"] as? Double ?? 0) + (rect["height"] as? Double ?? 0) / 2)
    }

    func click(_ report: CheckReport, _ probe: HeaderProbe, row: Int = 0,
               cppID: String, modifiers: Int = 0) {
        let p = point(probe, row: row)
        report.expect(headers.beginPointer(x: p.x, y: p.y, button: 1, modifiers: modifiers),
                      cppID: cppID, message: "\(probe) row \(row) accepts press")
        report.expect(headers.endPointer(x: p.x, y: p.y, button: 1, modifiers: modifiers),
                      cppID: cppID, message: "\(probe) row \(row) accepts release")
    }

    func openMenu(_ report: CheckReport, track: Int = 0, cppID: String) {
        let p = point(.title, row: track)
        report.expect(headers.beginPointer(x: p.x, y: p.y, button: 2, modifiers: 0),
                      cppID: cppID, message: "right press is handled")
        report.expect(headers.menuOpen, cppID: cppID, message: "right press opens header menu")
    }

    func rebuild() {
        headers.detach()
        headers.attach(session: session, palette: GridPalette())
        headers.configureViewport(width: 228, height: 240, fontPx: 13, dpr: 1)
        headers.configureTextMetrics(titleLineSpacing: 18, boldLineSpacing: 18,
                                     subtitleLineSpacing: 16)
    }
}

@MainActor
struct HeaderDocumentBaseline {
    let state: SongState
    let revision: UInt64
    let history: DocumentIdentity

    init(_ document: SongDocument) {
        state = document.state
        revision = document.revision
        history = document.history.currentIdentity
    }

    func expectUnchanged(_ report: CheckReport, _ document: SongDocument,
                         cppID: String, phase: String) {
        report.expectEqual(state, document.state, cppID: cppID, what: "\(phase): song unchanged")
        report.expectEqual(revision, document.revision, cppID: cppID,
                           what: "\(phase): no document write")
        report.expectEqual(history, document.history.currentIdentity, cppID: cppID,
                           what: "\(phase): history unchanged")
    }
}
