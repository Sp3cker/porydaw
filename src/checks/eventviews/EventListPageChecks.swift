import Foundation
import PorydawApp
import QtBridge
import PorydawCore
import PorydawAppEventList

private let pageID = "swiftcore/EventList::pageInteraction"
private let cellCommitContractID = "swiftcore/EventList::cellCommitContract"

@MainActor
internal func runEventListPageChecks(_ report: CheckReport, session suite: DocumentSession,
                                     service: ProjectService) {
    let file = MidiFile(division: 24, chunks: [MidiChunk(events: [
        .meta(tick: 0, type: 6, data: Array("mark".utf8)),
        .channel(tick: 12, status: 0xB0, data0: 7, data1: 80),
        .channel(tick: 12, status: 0xB0, data0: 10, data1: 40),
        .channel(tick: 24, status: 0x90, data0: 60, data1: 80),
        .channel(tick: 48, status: 0x80, data0: 60, data1: 0),
    ], endTick: 96)])
    let document = SongDocument(file: file, config: suite.document.state.config,
                                source: suite.document.source,
                                trackBudget: suite.document.trackBudget)
    let session = DocumentSession(document: document, service: service,
                                  lease: suite.bankLease, slots: suite.bankSlots,
                                  dirty: false, loadName: suite.bankLoadName,
                                  sampleRate: 48_000)
    let presenter = EventListPresenter()
    session.onChange = { [weak presenter] change in presenter?.documentDidChange(change) }
    presenter.attach(session: session)
    presenter.setVisible(visible: true)

    let firstCC = presenter.model.rows.firstIndex { $0.eventIndex == 1 }
    let secondCC = presenter.model.rows.firstIndex { $0.eventIndex == 2 }
    let note = presenter.model.rows.firstIndex { $0.eventIndex == 3 }
    guard let firstCC, let secondCC, let note else {
        report.expect(false, cppID: pageID, message: "the sample exposes its two controls and note")
        return
    }

    presenter.selectRow(row: firstCC, modifiers: 0)
    presenter.selectRow(row: secondCC, modifiers: 0x0400_0000)
    report.expect(presenter.selectedRows == [firstCC, secondCC], cppID: pageID,
                  message: "Control-click adds the second control without dropping the first")
    presenter.selectRow(row: note, modifiers: 0x0200_0000)
    report.expect(presenter.selectedRows == Array(firstCC...note), cppID: pageID,
                  message: "Shift-click extends a contiguous range from the anchor")

    report.expect(presenter.isLegalDrop(fromRow: firstCC, gap: secondCC + 1),
                  cppID: pageID, message: "a same-tick insertion gap permits reordering")
    report.expect(!presenter.isLegalDrop(fromRow: firstCC, gap: note + 1),
                  cppID: pageID, message: "a cross-tick insertion gap rejects reordering")
    presenter.commitDrop(fromRow: firstCC, gap: secondCC + 1)
    report.expect(document.rawChunks[0].events[1].payload
                  == .channel(status: 0xB0, data0: 10, data1: 40)
                  && document.rawChunks[0].events[2].payload
                     == .channel(status: 0xB0, data0: 7, data1: 80),
                  cppID: pageID, message: "legal row drag swaps the two same-tick events")
    let control = presenter.model.rows.firstIndex { $0.eventIndex == 2 }
    guard let control else { return }
    report.expect(presenter.beginEditing(row: control, column: 3), cppID: pageID,
                  message: "a controller number enters cell editing")
    report.expect(!presenter.finishEditing(text: "500", commit: true) && presenter.editing,
                  cppID: pageID, message: "out-of-range input keeps the cell editor active")
    report.expect(presenter.finishEditing(text: "65", commit: true)
                  && document.rawChunks[0].events[2].payload
                     == .channel(status: 0xB0, data0: 65, data1: 80),
                  cppID: pageID, message: "valid input commits a controller number to the song")
    report.expect(document.history.undoDocument()
                  && document.rawChunks[0].events[2].payload
                     == .channel(status: 0xB0, data0: 7, data1: 80),
                  cppID: pageID, message: "cell edit is a reversible document transaction")

    document.editTempo(TempoEdit(add: [TempoPoint(
        tick: 36, microsecondsPerQuarterNote: 600_000)]))
    report.expect(presenter.model.rows.contains(where: { $0.tempo?.tick == 36 }),
                  cppID: pageID, message: "tempo changes appear as editable rows")
    presenter.openFilterMenu(x: 0, y: 0)
    presenter.activateMenuAction(actionId: 64)
    report.expect(!presenter.model.rows.contains(where: { $0.tempo != nil || $0.event?.isMeta == true })
                  && presenter.model.rows.last?.isEndOfTrack == true,
                  cppID: pageID, message: "meta filter hides tempo/meta but retains the end row")
    presenter.activateMenuAction(actionId: 64)
    report.expect(presenter.model.rows.contains(where: { $0.tempo?.tick == 36 }),
                  cppID: pageID, message: "re-enabled meta filter restores tempo rows")
    presenter.dismissMenu()

    presenter.selectAll()
    report.expect(presenter.selectedRows.count == presenter.rowCount, cppID: pageID,
                  message: "Select All includes every visible row")
    guard let protectedID = document.rawChunks[0].events.first(where: { $0.isNoteOn })?.noteID,
          let originalNote = document.note(protectedID),
          let firstVictim = presenter.model.rows.firstIndex(where: { $0.eventIndex == 1 }),
          let secondVictim = presenter.model.rows.firstIndex(where: { $0.eventIndex == 2 }) else {
        return
    }
    session.setSelectedNotes([protectedID])
    presenter.selectRow(row: firstVictim, modifiers: 0)
    presenter.selectRow(row: secondVictim, modifiers: 0x0400_0000)
    report.expect(presenter.selectedRows == [firstVictim, secondVictim], cppID: pageID,
                  message: "the two intended victim rows, not the note, are selected")
    let beforeDeletion = document.rawChunks[0].events.count
    let beforeRows = presenter.rowCount
    presenter.deleteSelected()
    report.expect(document.rawChunks[0].events.count == beforeDeletion - 2
                  && !document.rawChunks[0].events.contains(where: {
                      $0.isChannel && $0.typeNibble == 0xB
                  }),
                  cppID: pageID, message: "Delete removes exactly the two selected raw rows")
    report.expect(presenter.rowCount == beforeRows - 2, cppID: pageID,
                  message: "Delete removes two visible rows without dropping EOT")
    let survivingNote = document.note(protectedID)
    report.expect(session.selectedNotes.contains(protectedID)
                  && survivingNote?.tick == originalNote.tick
                  && survivingNote?.pitch == originalNote.pitch
                  && survivingNote?.duration == originalNote.duration
                  && survivingNote?.isUnterminated == false,
                  cppID: pageID, message: "Delete leaves the unrelated selected note intact")

    eventListAppearanceParity(report, suite: suite, service: service)
    eventListTypographyParity(report)
    eventListSummaryParity(report, suite: suite, service: service)
    eventListCellCommitContract(report, suite: suite, service: service)
    eventListChunkLabelParity(report, suite: suite, service: service)
}

@MainActor
private func eventListTypographyParity(_ report: CheckReport) {
    let palette = GridPalette()
    let presenter = EventListPresenter(palette: palette)
    let body = presenter.appearance["bodyFont"] as? [String: QVariantSettable]
    let control = presenter.appearance["controlFont"] as? [String: QVariantSettable]
    let table = presenter.appearance["tableFont"] as? [String: QVariantSettable]
    let header = presenter.appearance["headerFont"] as? [String: QVariantSettable]
    report.expect((body?["family"] as? String) == "Atkinson Hyperlegible Next"
                  && (body?["pixelSize"] as? Int) == 15,
                  cppID: pageID, message: "seed body font is Atkinson Next at 15px")
    report.expect((control?["family"] as? String) == "Atkinson Hyperlegible Next"
                  && (control?["pixelSize"] as? Int) == 15,
                  cppID: pageID, message: "seed control font matches the body face and size")
    report.expect((table?["family"] as? String) == "Atkinson Hyperlegible Mono"
                  && (table?["pixelSize"] as? Int) == 15,
                  cppID: pageID, message: "seed table font uses Atkinson Mono at body size")
    report.expect((table?["letterSpacing"] as? Double) == -0.5
                  && (table?["features"] as? [String: QVariantSettable])?["tnum"] as? Int == 1
                  && (table?["hintingPreference"] as? Int) == 1,
                  cppID: pageID, message: "table numerals use negative tracking and no hinting")
    report.expect((header?["family"] as? String) == "Atkinson Hyperlegible Next"
                  && (header?["pixelSize"] as? Int) == 13,
                  cppID: pageID, message: "caption uses the proportional base-size face")
    let defaults = [70.0, 120.0, 36.0, 56.0, 56.0, 140.0]
    for column in defaults.indices {
        report.expect(presenter.savedColumnWidth(column: column) == defaults[column],
                      cppID: pageID, message: "seed column \(column) follows the fork fraction")
    }
    presenter.configureTypography(baseFontPx: 26)
    let doubled = presenter.appearance["tableFont"] as? [String: QVariantSettable]
    let doubledHeader = presenter.appearance["headerFont"] as? [String: QVariantSettable]
    report.expect((doubled?["pixelSize"] as? Int) == 29
                  && (doubledHeader?["pixelSize"] as? Int) == 26
                  && (doubled?["letterSpacing"] as? Double) == -1,
                  cppID: pageID, message: "base 26 scales body caption and mono tracking")
    for column in defaults.indices {
        report.expect(presenter.savedColumnWidth(column: column) == defaults[column] * 2,
                      cppID: pageID, message: "base 26 doubles default column \(column)")
    }
    presenter.configureTypography(baseFontPx: 10)
    for column in defaults.indices {
        report.expect(presenter.savedColumnWidth(column: column)
                      == (10 * defaults[column] / 13).rounded(),
                      cppID: pageID, message: "base 10 rounds default column \(column)")
    }
    presenter.resizeColumn(column: 1, width: 200)
    presenter.configureTypography(baseFontPx: 26)
    report.expect(presenter.savedColumnWidth(column: 1) == 200,
                  cppID: pageID, message: "user-resized Type column survives font changes")
    report.expect(presenter.savedColumnWidth(column: 0) == 140
                  && presenter.savedColumnWidth(column: 2) == 72,
                  cppID: pageID, message: "untouched columns rederive after Type resize")
    ShellAppearance.apply(to: palette, mode: "dark-neutral-high", contrast: 50)
    presenter.refreshAppearance()
    let refreshed = presenter.appearance["tableFont"] as? [String: QVariantSettable]
    report.expect((refreshed?["pixelSize"] as? Int) == 29
                  && (refreshed?["letterSpacing"] as? Double) == -1,
                  cppID: pageID, message: "theme refresh retains the configured typography base")
}

@MainActor
private func eventListChunkLabelParity(_ report: CheckReport, suite: DocumentSession,
                                      service: ProjectService) {
    let file = MidiFile(division: 24, chunks: [
        MidiChunk(events: [.meta(tick: 0, type: 0x58, data: [4, 2, 24, 8])], endTick: 24),
        MidiChunk(events: [.channel(tick: 0, status: 0x90, data0: 60, data1: 90),
                           .channel(tick: 12, status: 0x80, data0: 60)], endTick: 24),
        MidiChunk(events: [.channel(tick: 0, status: 0x91, data0: 64, data1: 90),
                           .channel(tick: 12, status: 0x81, data0: 64)], endTick: 24),
    ])
    let document = SongDocument(file: file, config: suite.document.state.config,
                                source: suite.document.source,
                                trackBudget: suite.document.trackBudget)
    let session = DocumentSession(document: document, service: service,
                                  lease: suite.bankLease, slots: suite.bankSlots,
                                  dirty: false, loadName: suite.bankLoadName,
                                  sampleRate: 48_000)
    let presenter = EventListPresenter()
    presenter.attach(session: session)
    report.expectEqual(expected: "Chunk 0 (tempo/meta)", actual: presenter.chunkLabels[0],
                       cppID: pageID, what: "unmapped conductor chunk names tempo/meta")
    report.expectEqual(expected: "Chunk 1 — Track 1", actual: presenter.chunkLabels[1],
                       cppID: pageID, what: "first engine track names its raw chunk")
    report.expectEqual(expected: "Chunk 2 — Track 2", actual: presenter.chunkLabels[2],
                       cppID: pageID, what: "second engine track names its raw chunk")
}

@MainActor
private func eventListAppearanceParity(_ report: CheckReport, suite: DocumentSession,
                                       service: ProjectService) {
    let palette = GridPalette()
    let presenter = EventListPresenter()
    presenter.attach(session: suite)
    func value(_ name: String) -> String? { presenter.appearance[name] as? String }
    report.expectEqual(expected: palette.menuBackground, actual: value("tableBackground") ?? "",
                       cppID: pageID, what: "tableBackground resolves item_background")
    report.expectEqual(expected: palette.alternateBackground,
                       actual: value("tableAlternateBackground") ?? "",
                       cppID: pageID, what: "tableAlternateBackground resolves item_alternate_background")
    report.expectEqual(expected: palette.windowText, actual: value("tableText") ?? "",
                       cppID: pageID, what: "tableText resolves item_text")
    report.expectEqual(expected: palette.secondaryText, actual: value("tableSecondaryText") ?? "",
                       cppID: pageID, what: "tableSecondaryText resolves secondary_text")
    report.expectEqual(expected: palette.tabSelectedBackground,
                       actual: value("tableSelectedBackground") ?? "",
                       cppID: pageID, what: "tableSelectedBackground resolves item_selected_background")
    report.expectEqual(expected: palette.selectionText, actual: value("tableSelectedText") ?? "",
                       cppID: pageID, what: "tableSelectedText resolves item_selected_text")
    report.expectEqual(expected: palette.outline, actual: value("tableOutline") ?? "",
                       cppID: pageID, what: "tableOutline resolves palette_outline")
    report.expectEqual(expected: palette.chromeBackground, actual: value("headerBackground") ?? "",
                       cppID: pageID, what: "headerBackground resolves header_background")
    report.expectEqual(expected: palette.outline, actual: value("headerOutline") ?? "",
                       cppID: pageID, what: "headerOutline resolves header_outline")
    report.expectEqual(expected: "#A49D97", actual: value("scrollbarHandle") ?? "",
                       cppID: pageID, what: "scrollbarHandle resolves the dedicated vanilla preset")
    report.expectEqual(expected: palette.outline, actual: value("scrollbarHandleHover") ?? "",
                       cppID: pageID, what: "scrollbarHandleHover resolves scrollbar_handle_hover_background")
    report.expectEqual(expected: palette.inputBackground, actual: value("toolTipBackground") ?? "",
                       cppID: pageID, what: "toolTipBackground resolves tooltip_background")
    report.expectEqual(expected: palette.buttonHoverBackground, actual: value("inputBackground") ?? "",
                       cppID: pageID, what: "inputBackground resolves input_background")
    report.expectEqual(expected: palette.windowText, actual: value("inputText") ?? "",
                       cppID: pageID, what: "inputText resolves input_text")

    let themed = GridPalette()
    ShellAppearance.apply(to: themed, mode: "dark-neutral-high", contrast: 50)
    let themedPresenter = EventListPresenter(palette: themed)
    themedPresenter.attach(session: suite)
    report.expectEqual(expected: "#424242",
                       actual: (themedPresenter.appearance["tableBackground"] as? String) ?? "",
                       cppID: pageID, what: "attached presenter spells the session palette's item surface")
    ShellAppearance.apply(to: themed, mode: "vanilla", contrast: 50)
    themedPresenter.refreshAppearance()
    report.expectEqual(expected: "#D2D0CA",
                       actual: (themedPresenter.appearance["tableBackground"] as? String) ?? "",
                       cppID: pageID, what: "refreshAppearance rebuilds the map after a theme swap")
    report.expectEqual(expected: "#A49D97",
                       actual: (themedPresenter.appearance["scrollbarHandle"] as? String) ?? "",
                       cppID: pageID, what: "vanilla returns the dedicated scrollbar preset")
    ShellAppearance.apply(to: themed, mode: "dark-neutral-high", contrast: 50)
    themedPresenter.refreshAppearance()
    report.expectEqual(expected: "#262626",
                       actual: (themedPresenter.appearance["scrollbarHandle"] as? String) ?? "",
                       cppID: pageID, what: "dark theme swaps the scrollbar thumb preset")
    report.expectEqual(expected: "#5C5C5C",
                       actual: (themedPresenter.appearance["inputBackground"] as? String) ?? "",
                       cppID: pageID, what: "dark theme swaps the input surface preset")

    for preset in ["vanilla", "dark-neutral-high", "immaterial"] {
        let presetPalette = GridPalette()
        ShellAppearance.apply(to: presetPalette, mode: preset, contrast: 50)
        let map = EventListPresenter(palette: presetPalette).appearance
        let pairs: [(String, String)] = [
            ("tableText", "tableBackground"),
            ("tableText", "tableAlternateBackground"),
            ("tableSecondaryText", "tableBackground"),
            ("tableSelectedText", "tableSelectedBackground"),
            ("headerText", "headerBackground"),
            ("buttonText", "buttonBackground"),
            ("inputText", "inputBackground"),
            ("toolTipText", "toolTipBackground"),
        ]
        for (text, background) in pairs {
            let ink = map[text] as? String ?? ""
            let fill = map[background] as? String ?? ""
            let ratio = PaletteMath.contrastRatio(ink, fill)
            report.expect(ratio >= 4.5, cppID: pageID,
                          message: "\(preset) \(text) on \(background) holds WCAG AA "
                              + "(ratio \(String(format: "%.2f", ratio)))")
        }
    }
}

@MainActor
private func eventListSummaryParity(_ report: CheckReport, suite: DocumentSession,
                                    service: ProjectService) {
    let file = MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(tick: 0, type: 3, data: Array("Route 101 lead".utf8)),
            .meta(tick: 48, type: 1, data: Array("[".utf8)),
            .meta(tick: 96, type: 1, data: Array("]".utf8)),
            .meta(tick: 60, type: 6, data: Array("mid".utf8)),
            .meta(tick: 70, type: 0x20, data: [0]),
            .meta(tick: 80, type: 0x59, data: [0xFF, 0x03]),
            .meta(tick: 85, type: 0x2A, data: [0x01]),
            .meta(tick: 90, type: 0x58, data: [0x04, 0x02, 0x18, 0x08]),
            .channel(tick: 0, status: 0xC0, data0: 0),
            .channel(tick: 4, status: 0xC0, data0: 5),
            .channel(tick: 8, status: 0x90, data0: 60, data1: 0),
            .channel(tick: 10, status: 0x90, data0: 60, data1: 98),
            .channel(tick: 12, status: 0x80, data0: 60),
            .channel(tick: 16, status: 0xA0, data0: 60, data1: 30),
            .channel(tick: 20, status: 0xB0, data0: 10, data1: 64),
            .channel(tick: 24, status: 0xD0, data0: 40),
            .channel(tick: 28, status: 0xE0, data0: 0, data1: 72),
            .systemExclusive(tick: 32, status: 0xF0, data: [0x7E, 0x00, 0x09, 0x01, 0xF7]),
        ], endTick: 144),
    ])
    let document = SongDocument(file: file, config: suite.document.state.config,
                                source: suite.document.source,
                                trackBudget: suite.document.trackBudget)
    let session = DocumentSession(document: document, service: service,
                                  lease: suite.bankLease, slots: suite.bankSlots,
                                  dirty: false, loadName: suite.bankLoadName,
                                  sampleRate: 48_000)
    let presenter = EventListPresenter()
    presenter.attach(session: session)
    presenter.setChunk(index: 0)
    func summary(of predicate: (EventListRow) -> Bool) -> String {
        guard let row = presenter.model.rows.first(where: predicate) else { return "" }
        return presenter.cellDisplay(row: row.index, column: 6)
    }
    report.expectEqual(expected: "Track name \"Route 101 lead\"",
                       actual: summary { $0.event?.metaType == 3 },
                       cppID: pageID, what: "text meta names its kind and quoted text")
    report.expectEqual(expected: "Text \"[\" — loop start",
                       actual: summary { $0.event?.metaType == 1 && $0.tick == 48 },
                       cppID: pageID, what: "bracket text meta gains the loop-start suffix")
    report.expectEqual(expected: "Text \"]\" — loop end",
                       actual: summary { $0.event?.metaType == 1 && $0.tick == 96 },
                       cppID: pageID, what: "close-bracket text meta gains the loop-end suffix")
    report.expectEqual(expected: "Marker \"mid\"",
                       actual: summary { $0.event?.metaType == 6 },
                       cppID: pageID, what: "marker meta keeps lowercase sentence spelling")
    report.expectEqual(expected: "Channel prefix",
                       actual: summary { $0.event?.metaType == 0x20 },
                       cppID: pageID, what: "channel prefix names its meta kind")
    report.expectEqual(expected: "Key signature",
                       actual: summary { $0.event?.metaType == 0x59 },
                       cppID: pageID, what: "key signature names its meta kind")
    report.expectEqual(expected: "Time signature 4/4",
                       actual: summary { $0.event?.metaType == 0x58 },
                       cppID: pageID, what: "time signature summarizes numerator and denominator")
    report.expectEqual(expected: "Voice 0 — Square 1",
                       actual: summary { $0.tick == 0 && $0.event?.typeNibble == 0xC },
                       cppID: pageID, what: "program change names the bank voice at its slot")
    report.expectEqual(expected: "Meta 0x2a",
                       actual: summary { $0.event?.metaType == 0x2A },
                       cppID: pageID, what: "unknown meta names its type in lowercase hex")
    report.expectEqual(expected: "Voice 5",
                       actual: summary { $0.tick == 4 && $0.event?.typeNibble == 0xC },
                       cppID: pageID, what: "empty-name slots fall back to the bare voice number")
    report.expectEqual(expected: "Note off C4 (velocity-0 note-on)",
                       actual: summary { $0.event?.typeNibble == 0x9 },
                       cppID: pageID, what: "velocity-zero note-on spells the key name")
    report.expectEqual(expected: "Note on C4, velocity 98",
                       actual: summary { $0.tick == 10 && $0.event?.typeNibble == 0x9 },
                       cppID: pageID, what: "note-on spells key name and velocity")
    report.expectEqual(expected: "Note off C4",
                       actual: summary { $0.event?.typeNibble == 0x8 },
                       cppID: pageID, what: "note-off spells the key name")
    report.expectEqual(expected: "Poly aftertouch C4 = 30",
                       actual: summary { $0.event?.typeNibble == 0xA },
                       cppID: pageID, what: "poly aftertouch spells key and pressure")
    report.expectEqual(expected: "CC 10 Pan = c_v+0",
                       actual: summary { $0.event?.typeNibble == 0xB },
                       cppID: pageID, what: "control change shows classified name and formatted value")
    report.expectEqual(expected: "Channel aftertouch = 40",
                       actual: summary { $0.event?.typeNibble == 0xD },
                       cppID: pageID, what: "channel aftertouch shows its pressure")
    report.expectEqual(expected: "Pitch bend +1024",
                       actual: summary { $0.event?.typeNibble == 0xE },
                       cppID: pageID, what: "pitch bend formats a signed 14-bit value")
    report.expectEqual(expected: "5 payload byte(s)",
                       actual: summary { $0.event?.isChannel == false && $0.event?.metaType == nil },
                       cppID: pageID, what: "sysex rows count their payload bytes")
}

/// ED09 slice 1: the cell-edit commit contract through the mounted presenter —
/// typed and programmatic tick commits (64-bit exact, kNoTick/kMaxTick),
/// channel/data/blob conversion commits, and the insert-copy path including
/// the EOT-sentinel refusal. Fixture mirrors C++ `FixtureShape::Basic`.
@MainActor
private func eventListCellCommitContract(_ report: CheckReport, suite: DocumentSession,
                                         service: ProjectService) {
    let file = MidiFile(division: 24, chunks: [MidiChunk(events: [
        .meta(tick: 0, type: 0x06, data: Array("marker".utf8)),
        .channel(tick: 12, status: 0x90, data0: 60, data1: 90),
    ], endTick: 12)])
    let document = SongDocument(file: file, config: suite.document.state.config,
                                source: suite.document.source,
                                trackBudget: suite.document.trackBudget)
    let session = DocumentSession(document: document, service: service,
                                  lease: suite.bankLease, slots: suite.bankSlots,
                                  dirty: false, loadName: suite.bankLoadName,
                                  sampleRate: 48_000)
    let presenter = EventListPresenter()
    session.onChange = { [weak presenter] change in presenter?.documentDidChange(change) }
    presenter.attach(session: session)
    presenter.setVisible(visible: true)

    func noteOnRow(at tick: Tick) -> Int? {
        presenter.model.rows.firstIndex {
            $0.kind == .noteOn && $0.tick == tick
        }
    }

    // A002/A011/A020/A032/A048/A112: direct fixture construction replaces the
    // native rig-open guard; the Swift equivalent is an attached presenter.
    report.expect(presenter.attached && document.rawChunks.indices.contains(0),
                  cppID: cellCommitContractID,
                  message: "A002 event-list presenter attaches to the basic fixture")
    // A003/A012/A021/A033/A049/A113: presenter attachment is the Swift
    // equivalent of locating EventWidgets.
    report.expect(presenter.rowCount == 3
                  && presenter.model.rows.last?.isEndOfTrack == true,
                  cppID: cellCommitContractID,
                  message: "A003 mounted rows expose two events and one EOT sentinel")

    // A004/A013/A022/A034/A050: the tick-12 NoteOn row lookup succeeds.
    let noteRow = noteOnRow(at: 12)
    report.expect(noteRow != nil, cppID: cellCommitContractID,
                  message: "A004 tick-12 NoteOn row exists in the fixture")
    guard let noteRow else { return }

    // --- G1: typed/programmatic tick edit through commitCellEdit ------------
    let baselineIndex = document.history.undoIndex
    // A005: the presenter commit path accepts the typed tick.
    report.expect(presenter.commitCellEdit(row: noteRow, column: 0, text: "15"),
                  cppID: cellCommitContractID,
                  message: "A005 commitCellEdit commits the typed tick 15")
    // A006: the row is republished at the committed tick.
    let moved15 = noteOnRow(at: 15)
    report.expect(moved15 != nil, cppID: cellCommitContractID,
                  message: "A006 the NoteOn row republishes at tick 15")
    // A007: the published tick string carries the exact committed digits.
    report.expect(moved15.map { presenter.tickString(row: $0) } == "15",
                  cppID: cellCommitContractID,
                  message: "A007 tick string equals the typed digits")
    // A008: the cell commit pushes exactly one undo step.
    report.expectEqual(expected: baselineIndex + 1, actual: document.history.undoIndex,
                       cppID: cellCommitContractID,
                       what: "A008 typed tick commit pushes one undo step")
    // A009: the committed chunk stays tick-sorted.
    report.expect(chunksSortedByTick(document.state.file), cppID: cellCommitContractID,
                  message: "A009 chunk stays tick-sorted after the typed commit")
    // A010: undo restores the tick-12 row.
    report.expect(document.history.undoDocument() && noteOnRow(at: 12) != nil,
                  cppID: cellCommitContractID,
                  message: "A010 undo restores the tick-12 NoteOn row")

    // --- G2: 64-bit exact tick ---------------------------------------------
    let indexBefore64 = document.history.undoIndex
    // A014: the commit path accepts a tick beyond 32 bits.
    report.expect(presenter.commitCellEdit(row: noteRow, column: 0, text: "3000000000"),
                  cppID: cellCommitContractID,
                  message: "A014 commitCellEdit commits the 64-bit tick")
    // A015: the exact commit pushes one undo step.
    report.expectEqual(expected: indexBefore64 + 1, actual: document.history.undoIndex,
                       cppID: cellCommitContractID,
                       what: "A015 64-bit commit pushes one undo step")
    // A016: the committed chunk has events.
    report.expect(!document.rawChunks[0].events.isEmpty, cppID: cellCommitContractID,
                  message: "A016 committed chunk keeps its events")
    // A017: the moved event lands exactly at the 64-bit tick.
    report.expectEqual(expected: Tick(3_000_000_000),
                       actual: document.rawChunks[0].events.last?.tick ?? 0,
                       cppID: cellCommitContractID,
                       what: "A017 back event tick is exactly 3000000000")
    // A018: the exact commit keeps the chunk tick-sorted.
    report.expect(chunksSortedByTick(document.state.file), cppID: cellCommitContractID,
                  message: "A018 chunk stays tick-sorted after the 64-bit commit")
    // A019: undo restores the tick-12 row.
    report.expect(document.history.undoDocument() && noteOnRow(at: 12) != nil,
                  cppID: cellCommitContractID,
                  message: "A019 undo restores the tick-12 NoteOn row")

    // --- G3: kNoTick refusal and kMaxTick acceptance ------------------------
    let indexBeforeBoundary = document.history.undoIndex
    // A023: the commit path refuses the reserved kNoTick sentinel.
    report.expect(!presenter.commitCellEdit(row: noteRow, column: 0,
                                          text: String(TimeDefaults.noTick)),
                  cppID: cellCommitContractID,
                  message: "A023 typed kNoTick commit is refused")
    // A024: the refused commit pushes no undo step.
    report.expectEqual(expected: indexBeforeBoundary, actual: document.history.undoIndex,
                       cppID: cellCommitContractID,
                       what: "A024 refused kNoTick pushes no undo step")
    // A025: the refused commit leaves the tick-12 row in place.
    report.expect(noteOnRow(at: 12) != nil, cppID: cellCommitContractID,
                  message: "A025 the tick-12 NoteOn row survives the refusal")
    // A026: the commit path accepts kMaxTick, the largest document tick.
    report.expect(presenter.commitCellEdit(row: noteRow, column: 0,
                                          text: String(TimeDefaults.maxTick)),
                  cppID: cellCommitContractID,
                  message: "A026 typed kMaxTick commits")
    // A027: the boundary commit pushes one undo step.
    report.expectEqual(expected: indexBeforeBoundary + 1,
                       actual: document.history.undoIndex,
                       cppID: cellCommitContractID,
                       what: "A027 kMaxTick commit pushes one undo step")
    // A028: the committed chunk has events.
    report.expect(!document.rawChunks[0].events.isEmpty, cppID: cellCommitContractID,
                  message: "A028 committed chunk keeps its events")
    // A029: the back event lands exactly at kMaxTick.
    report.expectEqual(expected: TimeDefaults.maxTick,
                       actual: document.rawChunks[0].events.last?.tick ?? 0,
                       cppID: cellCommitContractID,
                       what: "A029 back event tick is exactly kMaxTick")
    // A030: the boundary commit keeps the chunk tick-sorted.
    report.expect(chunksSortedByTick(document.state.file), cppID: cellCommitContractID,
                  message: "A030 chunk stays tick-sorted after the kMaxTick commit")
    // A031: undo restores the tick-12 row.
    report.expect(document.history.undoDocument() && noteOnRow(at: 12) != nil,
                  cppID: cellCommitContractID,
                  message: "A031 undo restores the tick-12 NoteOn row")

    // --- G4: the same boundaries through the presenter edit session --------
    let indexBeforeEditor = document.history.undoIndex
    let bytesBeforeEditor = try? document.state.file.encoded()
    // A037: beginEditing opens the tick cell.
    report.expect(presenter.beginEditing(row: noteRow, column: 0), cppID: cellCommitContractID,
                  message: "A037 beginEditing opens the tick cell")
    // A037 (refusal half): a typed kNoTick commit keeps the editor open.
    report.expect(!presenter.finishEditing(text: String(TimeDefaults.noTick), commit: true)
                  && presenter.editing,
                  cppID: cellCommitContractID,
                  message: "A037 typed kNoTick leaves the edit session open")
    // A037 (undo half): the refused commit pushes no undo step.
    report.expectEqual(expected: indexBeforeEditor, actual: document.history.undoIndex,
                       cppID: cellCommitContractID,
                       what: "A037 refused kNoTick pushes no undo step")
    // A038: the refused typed commit leaves the document bytes unchanged.
    report.expect((try? document.state.file.encoded()) == bytesBeforeEditor
                  && bytesBeforeEditor != nil,
                  cppID: cellCommitContractID,
                  message: "A038 typed kNoTick leaves the document bytes unchanged")
    // A041: the open session commits a typed kMaxTick.
    report.expect(presenter.finishEditing(text: String(TimeDefaults.maxTick), commit: true)
                  && !presenter.editing,
                  cppID: cellCommitContractID,
                  message: "A041 typed kMaxTick commits and closes the editor")
    // A041 (undo half): the committed edit pushes one undo step.
    report.expectEqual(expected: indexBeforeEditor + 1, actual: document.history.undoIndex,
                       cppID: cellCommitContractID,
                       what: "A041 committed kMaxTick pushes one undo step")
    // A042: the committed chunk has events.
    report.expect(!document.rawChunks[0].events.isEmpty, cppID: cellCommitContractID,
                  message: "A042 committed chunk keeps its events")
    // A043: the back event lands exactly at kMaxTick.
    report.expectEqual(expected: TimeDefaults.maxTick,
                       actual: document.rawChunks[0].events.last?.tick ?? 0,
                       cppID: cellCommitContractID,
                       what: "A043 back event tick is exactly kMaxTick")
    // A044: the moved NoteOn row republishes at kMaxTick.
    let movedMax = noteOnRow(at: TimeDefaults.maxTick)
    report.expect(movedMax != nil, cppID: cellCommitContractID,
                  message: "A044 the NoteOn row republishes at kMaxTick")
    // A045: the published tick string carries the exact boundary digits.
    report.expect(movedMax.map { presenter.tickString(row: $0) }
                  == String(TimeDefaults.maxTick),
                  cppID: cellCommitContractID,
                  message: "A045 tick string equals the exact kMaxTick digits")
    // A046: the boundary commit keeps the chunk tick-sorted.
    report.expect(chunksSortedByTick(document.state.file), cppID: cellCommitContractID,
                  message: "A046 chunk stays tick-sorted after the kMaxTick commit")
    // A047: undo restores the tick-12 row.
    report.expect(document.history.undoDocument() && noteOnRow(at: 12) != nil,
                  cppID: cellCommitContractID,
                  message: "A047 undo restores the tick-12 NoteOn row")

    // --- G5: channel, data-byte and blob conversion commits -----------------
    let indexBeforeCells = document.history.undoIndex
    // A051: the commit path accepts the one-based channel value.
    report.expect(presenter.commitCellEdit(row: noteRow, column: 2, text: "5"),
                  cppID: cellCommitContractID,
                  message: "A051 commitCellEdit commits the typed channel 5")
    // A053: the tick-12 NoteOn survives the channel edit.
    let editedEventIndex = document.rawChunks[0].events.firstIndex {
        $0.tick == 12 && $0.isNoteOn
    }
    report.expect(editedEventIndex != nil, cppID: cellCommitContractID,
                  message: "A053 tick-12 NoteOn event survives the channel edit")
    guard let editedEventIndex else { return }
    // A055: the data1 commit is accepted.
    report.expect(presenter.commitCellEdit(row: noteRow, column: 3, text: "100"),
                  cppID: cellCommitContractID,
                  message: "A055 commitCellEdit commits the typed data1 100")
    // A056: the data2 commit is accepted.
    report.expect(presenter.commitCellEdit(row: noteRow, column: 4, text: "33"),
                  cppID: cellCommitContractID,
                  message: "A056 commitCellEdit commits the typed data2 33")
    report.expectEqual(expected: indexBeforeCells + 3, actual: document.history.undoIndex,
                       cppID: cellCommitContractID,
                       what: "A057 the three cell commits push one undo step each")
    report.expectEqual(expected: UInt8(0x04),
                       actual: document.rawChunks[0].events[editedEventIndex].status & 0x0F,
                       cppID: cellCommitContractID,
                       what: "A058 typed channel 5 stores the status nibble 4")
    report.expect(document.rawChunks[0].events[editedEventIndex].payload
                  == .channel(status: 0x94, data0: 100, data1: 33),
                  cppID: cellCommitContractID,
                  message: "A059 typed data bytes land on the note event")
    // A060: the marker row lookup succeeds for the blob edit.
    let blobRow = presenter.model.rows.firstIndex {
        $0.kind == .meta && $0.tick == 0
    }
    report.expect(blobRow != nil, cppID: cellCommitContractID,
                  message: "A060 tick-0 meta row exists in the fixture")
    // A061: the meta row maps to a raw event index.
    let blobEventIndex = blobRow.flatMap { presenter.model.rows[$0].eventIndex }
    report.expect(blobEventIndex != nil, cppID: cellCommitContractID,
                  message: "A061 meta row exposes its raw event index")
    guard let blobRow, let blobEventIndex else { return }
    // A062: the quoted blob commit is accepted.
    report.expect(presenter.commitCellEdit(row: blobRow, column: 5,
                                          text: "\"room\""),
                  cppID: cellCommitContractID,
                  message: "A062 commitCellEdit commits the quoted blob")
    report.expectEqual(expected: indexBeforeCells + 4, actual: document.history.undoIndex,
                       cppID: cellCommitContractID,
                       what: "A063 the blob commit pushes the fourth undo step")
    report.expectEqual(expected: Optional(Array("room".utf8)),
                       actual: document.rawChunks[0].events[blobEventIndex].blob,
                       cppID: cellCommitContractID,
                       what: "A064 quoted blob stores the room bytes")
    // A065: unwinding every cell commit restores the tick-12 NoteOn row.
    while document.history.undoIndex > indexBeforeCells {
        _ = document.history.undoDocument()
    }
    let restoredIndex = document.rawChunks[0].events.firstIndex {
        $0.tick == 12 && $0.isNoteOn
    }
    report.expect(noteOnRow(at: 12) != nil && restoredIndex != nil
                  && document.rawChunks[0].events[restoredIndex ?? 0].status & 0x0F == 0x00
                  && document.rawChunks[0].events[restoredIndex ?? 0].payload
                     == .channel(status: 0x90, data0: 60, data1: 90)
                  && document.rawChunks[0].events[blobEventIndex].blob
                     == Array("marker".utf8),
                  cppID: cellCommitContractID,
                  message: "A065 undo restores channel 0, 60/90 and the marker bytes")

    // --- G6: insert-copy through addEvent ----------------------------------
    let markerEvent = document.rawChunks[0].events[blobEventIndex]
    let markerCount = document.rawChunks[0].events.filter { $0 == markerEvent }.count
    let indexBeforeInsert = document.history.undoIndex
    presenter.focusRow(row: 0)
    presenter.addEvent()
    // A114: insert-copy duplicates the focused row's event.
    report.expect(document.rawChunks[0].events.filter { $0 == markerEvent }.count
                  == markerCount + 1,
                  cppID: cellCommitContractID,
                  message: "A114 insert-copy adds one copy of the marker event")
    // A115: the insert pushes one undo step.
    report.expectEqual(expected: indexBeforeInsert + 1, actual: document.history.undoIndex,
                       cppID: cellCommitContractID,
                       what: "A115 insert-copy pushes one undo step")
    // A116: the inserted copy keeps the chunk tick-sorted.
    report.expect(chunksSortedByTick(document.state.file), cppID: cellCommitContractID,
                  message: "A116 chunk stays tick-sorted after the insert")
    // Repair evidence (no ledger clause): the original selects the inserted
    // row via selectEventRow.
    report.expect(presenter.currentRow >= 0
                  && presenter.isSelected(row: presenter.currentRow),
                  cppID: cellCommitContractID,
                  message: "insert-copy focuses and selects the inserted row")
    // A117: undo drops the inserted copy.
    report.expect(document.history.undoDocument()
                  && document.rawChunks[0].events.filter { $0 == markerEvent }.count
                     == markerCount,
                  cppID: cellCommitContractID,
                  message: "A117 undo restores the marker count")

    // Repair evidence (no ledger clause): a tempo row's insert copies its
    // µs-per-quarter-note instead of the hardcoded default.
    document.editTempo(TempoEdit(add: [TempoPoint(
        tick: 0, microsecondsPerQuarterNote: 600_000)]))
    let tempoRow = presenter.model.rows.firstIndex { $0.tempo?.tick == 0 }
    report.expect(tempoRow != nil, cppID: cellCommitContractID,
                  message: "tempo row exists after the tempo edit")
    if let tempoRow {
        presenter.focusRow(row: tempoRow)
        session.editCursor = 6
        presenter.addEvent()
        report.expectEqual(expected: UInt32(600_000),
                           actual: document.state.tempo.last(where: { $0.tick == 6 })?
                               .microsecondsPerQuarterNote ?? 0,
                           cppID: cellCommitContractID,
                           what: "tempo insert copies the source µs-per-quarter-note")
    }

    // A118/A119: the EOT sentinel refuses insert-copy.
    let indexBeforeSentinel = document.history.undoIndex
    let eventCountBeforeSentinel = document.rawChunks[0].events.count
    presenter.focusRow(row: presenter.rowCount - 1)
    presenter.addEvent()
    report.expectEqual(expected: indexBeforeSentinel, actual: document.history.undoIndex,
                       cppID: cellCommitContractID,
                       what: "A118 EOT-row insert pushes no undo step")
    report.expectEqual(expected: eventCountBeforeSentinel,
                       actual: document.rawChunks[0].events.count,
                       cppID: cellCommitContractID,
                       what: "A119 EOT-row insert adds no event")
}
