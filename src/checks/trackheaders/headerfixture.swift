import Foundation
@testable import PorydawApp
import PorydawCore

let trackHeadersUnattachedID = "swiftcore/TrackHeaders::unattachedModelPublishesSafeZeroGeometry"
let trackHeadersReorderID = "swiftcore/TrackHeaders::reorderSlotsResolveInsertionTargetsAndUndoRestores"
let trackHeadersUnchangedID = "swiftcore/TrackHeaders::headerReconciliationUnchanged"
let trackHeadersStructuralID = "swiftcore/TrackHeaders::headerReconciliationStructural"
let trackHeadersMixPublicationID = "swiftcore/TrackHeaders::commandMixStatePublishesImmediately"

@MainActor
struct TrackHeadersFixture {
    let session: DocumentSession
    let headers: TrackHeadersPresenter
    var document: SongDocument { session.document }
    var trackRows: [TrackHeaderRowHandle] {
        (0..<headers.rows.count).map { headers.rows[$0] }.filter { !$0.isAddTrack }
    }
    var channelOrder: [UInt8] {
        let map = document.engineTracks
        return map.tracks.prefix(map.usedTrackCount).map(\.channel)
    }

    init(suite: DocumentSession, service: ProjectService, configured: Bool = true) {
        let file = MidiFile(division: 24, chunks: [
            MidiChunk(events: [.meta(type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 96),
            MidiChunk(events: [
                .meta(type: 0x03, data: Array("Lead".utf8)),
                .channel(status: 0xC0, data0: 0),
                .channel(status: 0x90, data0: 60, data1: 100),
                .channel(tick: 24, status: 0x80, data0: 60),
            ], endTick: 96),
            MidiChunk(events: [
                .meta(type: 0x03, data: Array("Bass".utf8)),
                .channel(status: 0xC1, data0: 1),
                .channel(status: 0x91, data0: 48, data1: 80),
                .channel(tick: 48, status: 0x81, data0: 48),
            ], endTick: 96),
        ])
        let document = SongDocument(file: file, config: suite.document.state.config,
                                    source: suite.document.source, trackBudget: 16)
        session = DocumentSession(document: document, service: service,
                                  lease: suite.bankLease, slots: suite.bankSlots,
                                  dirty: false, loadName: suite.bankLoadName,
                                  sampleRate: 48_000)
        session.selectedTrack = 0
        let headers = TrackHeadersPresenter(baseFontPx: 13)
        self.headers = headers
        headers.attach(session: session, palette: GridPalette())
        session.onChange = { [weak headers] change in headers?.documentDidChange(change) }
        if configured {
            headers.configureViewport(width: 228, height: 240, fontPx: 13, dpr: 1)
            headers.configureTextMetrics(titleLineSpacing: 18, boldLineSpacing: 18,
                                         subtitleLineSpacing: 16)
        }
    }

    func drag(_ report: CheckReport, from: Int, target: Int, fraction: Double,
              label: String) {
        let x = headers.trackHeaderWidth / 2
        let height = Double(headers.rowHeight)
        let startY = (Double(from) + 0.25) * height
        let dropY = (Double(target) + fraction) * height
        report.expect(headers.beginPointer(x: x, y: startY, button: 1, modifiers: 0),
                      cppID: trackHeadersReorderID, message: "\(label): header accepts press")
        report.expect(headers.updatePointer(x: x, y: dropY, modifiers: 0),
                      cppID: trackHeadersReorderID, message: "\(label): header accepts drag")
        report.expect(headers.endPointer(x: x, y: dropY, button: 1, modifiers: 0),
                      cppID: trackHeadersReorderID, message: "\(label): header accepts release")
    }

    func expectRows(_ report: CheckReport, names: [String], cppID: String, phase: String) {
        report.expectEqual(Array(names.indices), trackRows.map(\.track), cppID: cppID,
                           what: "\(phase): rows follow engine track order")
        let titles = names.enumerated().map { "\($0.offset + 1) · \($0.element)" }
        report.expectEqual(titles, trackRows.map(\.title), cppID: cppID,
                           what: "\(phase): rows display ordered numbered track names")
        report.expectEqual(names.count + 1, headers.rows.count, cppID: cppID,
                           what: "\(phase): one row per track plus add-track row")
        let addRows = (0..<headers.rows.count).filter { headers.rows[$0].isAddTrack }
        report.expectEqual([names.count], addRows, cppID: cppID,
                           what: "\(phase): add-track row remains last")
    }
}
