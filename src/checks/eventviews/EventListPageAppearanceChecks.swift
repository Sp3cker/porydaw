import Foundation
@testable import PorydawApp
import QtBridge
import PorydawCore
import PorydawAppEventList
import PorydawAppCommands

@MainActor
internal func eventListTypographyParity(_ report: CheckReport) {
    let palette = GridPalette()
    let seed = Typography(baseFontPx: 13)
    let presenter = EventListPresenter(palette: palette, typography: seed)
    func expectRoles(_ typography: Typography) {
        let roles: [(String, QmlFont, GridFontSpec)] = [
            ("bodyFont", presenter.fonts.body, typography.body),
            ("controlFont", presenter.fonts.body, typography.body),
            ("tableFont", presenter.fonts.tableMono, typography.tableMono),
            ("headerFont", presenter.fonts.caption, typography.caption),
        ]
        for (name, font, spec) in roles {
            report.expect(
                font == spec.qmlFont,
                cppID: pageID, message: "\(name) follows the captured typography role")
        }
    }
    expectRoles(seed)
    let fonts = presenter.fonts
    let defaults = [70.0, 120.0, 36.0, 56.0, 56.0, 140.0]
    for column in defaults.indices {
        report.expect(
            presenter.savedColumnWidth(column: column) == defaults[column],
            cppID: pageID, message: "seed column \(column) follows the fork fraction")
    }
    let doubledTypography = Typography(baseFontPx: 26)
    presenter.configureTypography(typography: doubledTypography)
    expectRoles(doubledTypography)
    for column in defaults.indices {
        report.expect(
            presenter.savedColumnWidth(column: column) == defaults[column] * 2,
            cppID: pageID, message: "base 26 doubles default column \(column)")
    }
    presenter.configureTypography(typography: Typography(baseFontPx: 10))
    for column in defaults.indices {
        report.expect(
            presenter.savedColumnWidth(column: column)
                == Double(Typography(baseFontPx: 10).fontPx(defaults[column] / 13)),
            cppID: pageID, message: "base 10 rounds default column \(column)")
    }
    presenter.resizeColumn(column: 1, width: 200)
    presenter.configureTypography(typography: doubledTypography)
    report.expect(
        presenter.savedColumnWidth(column: 1) == 200,
        cppID: pageID, message: "user-resized Type column survives font changes")
    report.expect(
        presenter.columnWidths.count == defaults.count, cppID: pageID,
        message: "the resized store keeps six entries")
    report.expect(
        presenter.savedColumnWidth(column: 0) == 140
            && presenter.savedColumnWidth(column: 2) == 72,
        cppID: pageID, message: "untouched columns rederive after Type resize")
    ShellAppearance.apply(to: palette, mode: "dark-neutral-high", contrast: 50)
    presenter.refreshAppearance()
    expectRoles(doubledTypography)
    report.expect(
        presenter.fonts === fonts && presenter.colors === palette,
        cppID: pageID, message: "typography and theme retain the published objects")
    let publishedWidths = [
        presenter.tickColumnWidth, presenter.typeColumnWidth, presenter.channelColumnWidth,
        presenter.data1ColumnWidth, presenter.data2ColumnWidth, presenter.dataColumnWidth,
    ]
    for column in defaults.indices {
        report.expect(
            publishedWidths[column] == presenter.savedColumnWidth(column: column),
            cppID: pageID, message: "notifying width \(column) matches the saved native width")
    }
}

@MainActor
internal func eventListChunkLabelParity(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(events: [.meta(tick: 0, type: 0x58, data: [4, 2, 24, 8])], endTick: 24),
            MidiChunk(
                events: [
                    .channel(tick: 0, status: 0x90, data0: 60, data1: 90),
                    .channel(tick: 12, status: 0x80, data0: 60),
                ], endTick: 24),
            MidiChunk(
                events: [
                    .channel(tick: 0, status: 0x91, data0: 64, data1: 90),
                    .channel(tick: 12, status: 0x81, data0: 64),
                ], endTick: 24),
        ])
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName,
        sampleRate: 48_000)
    let presenter = EventListPresenter()
    presenter.attach(session: session)
    report.expectEqual(
        expected: "Chunk 0 (tempo/meta)", actual: presenter.chunkLabels[0],
        cppID: pageID, what: "unmapped conductor chunk names tempo/meta")
    report.expectEqual(
        expected: "Chunk 1 — Track 1", actual: presenter.chunkLabels[1],
        cppID: pageID, what: "first engine track names its raw chunk")
    report.expectEqual(
        expected: "Chunk 2 — Track 2", actual: presenter.chunkLabels[2],
        cppID: pageID, what: "second engine track names its raw chunk")

    guard let handle = presenter.rowHandle(row: 0) else {
        report.expect(false, cppID: pageID, message: "attached event table publishes its first row")
        return
    }
    for column in 0..<EventListModel.columnCount {
        let tableHandle = presenter.tableRows.value(row: 0, column: column) as? EventListRowHandle
        report.expect(
            tableHandle === handle, cppID: pageID,
            message: "table column \(column) shares the retained typed row")
    }
    report.expect(
        handle.c0 == presenter.cellDisplay(row: 0, column: 0)
            && handle.c1 == presenter.cellDisplay(row: 0, column: 1)
            && handle.c5 == presenter.cellDisplay(row: 0, column: 5)
            && handle.c6 == presenter.cellDisplay(row: 0, column: 6)
            && handle.editData == presenter.cellEdit(row: 0, column: 5),
        cppID: pageID, message: "published cells preserve display and editor formatting")
    presenter.selectRow(row: 0, modifiers: 0)
    report.expect(
        handle.selected && presenter.rowHandle(row: 0) === handle,
        cppID: pageID, message: "selection publishes in place on the retained row")
    presenter.selectRow(row: 0, modifiers: 0x04000000)
    report.expect(
        !handle.selected && presenter.rowHandle(row: 0) === handle,
        cppID: pageID, message: "Control toggle clears the notifying row selection")
    presenter.refresh()
    report.expect(
        presenter.rowHandle(row: 0) === handle,
        cppID: pageID, message: "document refresh reuses its row handle")
    let projection = EventListModel(
        chunk: MidiChunk(
            events: [
                .channel(tick: 0, status: 0x90, data0: 60, data1: 90),
                .meta(tick: 12, type: 0x06, data: Array(repeating: UInt8(ascii: "a"), count: 65)),
                .meta(tick: 24, type: 0x7F, data: Array(repeating: 0x80, count: 65)),
                .systemExclusive(tick: 36, status: 0xF0, data: Array(repeating: 0x7D, count: 65)),
            ], endTick: 48),
        tempos: [TempoPoint(tick: 0, microsecondsPerQuarterNote: 600_000)])
    let expectedMasks = [35, 31, 43, 43, 35, 1]
    for source in projection.rows {
        let row = EventListRowHandle()
        report.expect(
            row.update(source, model: projection, selected: false)
                && !row.update(source, model: projection, selected: false),
            cppID: pageID, message: "row \(source.index) equality-gates an unchanged snapshot")
        let cells = [row.c0, row.c1, row.c2, row.c3, row.c4, row.c5, row.c6]
        for column in 0..<EventListModel.columnCount {
            report.expect(
                cells[column] == projection.cellText(row: source.index, column: column)
                    && ((row.editableMask & (1 << column)) != 0)
                        == projection.isCellEditable(row: source.index, column: column),
                cppID: pageID,
                message: "row \(source.index) column \(column) preserves text and editability")
        }
        report.expectEqual(
            expected: expectedMasks[source.index], actual: row.editableMask,
            cppID: pageID, what: "row \(source.index) publishes the native editable-column mask")
        report.expect(
            row.editType == projection.cellText(row: source.index, column: 1, editing: true)
                && row.editData == projection.cellText(row: source.index, column: 5, editing: true)
                && row.rowKind == projection.rowKind(row: source.index),
            cppID: pageID, message: "row \(source.index) preserves editor text and kind")
    }
    presenter.detach()
    report.expect(
        presenter.rowHandle(row: 0) == nil && presenter.rowCount == 0,
        cppID: pageID, message: "detaching clears the sole table model")
}

@MainActor
internal func eventListAppearanceParity(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let palette = GridPalette()
    let presenter = EventListPresenter()
    presenter.attach(session: suite)
    report.expectEqual(
        expected: palette.menuBackground, actual: presenter.colors.menuBackground,
        cppID: pageID, what: "tableBackground resolves item_background")
    report.expectEqual(
        expected: palette.alternateBackground, actual: presenter.colors.alternateBackground,
        cppID: pageID, what: "tableAlternateBackground resolves item_alternate_background")
    report.expectEqual(
        expected: palette.windowText, actual: presenter.colors.windowText,
        cppID: pageID, what: "tableText resolves item_text")
    report.expectEqual(
        expected: palette.secondaryText, actual: presenter.colors.secondaryText,
        cppID: pageID, what: "tableSecondaryText resolves secondary_text")
    report.expectEqual(
        expected: palette.tabSelectedBackground, actual: presenter.colors.tabSelectedBackground,
        cppID: pageID, what: "tableSelectedBackground resolves item_selected_background")
    report.expectEqual(
        expected: palette.selectionText, actual: presenter.colors.selectionText,
        cppID: pageID, what: "tableSelectedText resolves item_selected_text")
    report.expectEqual(
        expected: palette.outline, actual: presenter.colors.outline,
        cppID: pageID, what: "tableOutline resolves palette_outline")
    report.expectEqual(
        expected: palette.chromeBackground, actual: presenter.colors.chromeBackground,
        cppID: pageID, what: "headerBackground resolves header_background")
    report.expectEqual(
        expected: palette.outline, actual: presenter.colors.outline,
        cppID: pageID, what: "headerOutline resolves header_outline")
    report.expectEqual(
        expected: PaletteMath.qmlColor(argb: 0xFFA49D97), actual: presenter.colors.scrollbarHandle,
        cppID: pageID, what: "scrollbarHandle resolves the dedicated vanilla preset")
    report.expectEqual(
        expected: palette.outline, actual: presenter.colors.outline,
        cppID: pageID, what: "scrollbarHandleHover resolves scrollbar_handle_hover_background")
    report.expectEqual(
        expected: palette.inputBackground, actual: presenter.colors.inputBackground,
        cppID: pageID, what: "toolTipBackground resolves tooltip_background")
    report.expectEqual(
        expected: palette.buttonHoverBackground, actual: presenter.colors.buttonHoverBackground,
        cppID: pageID, what: "inputBackground resolves input_background")
    report.expectEqual(
        expected: palette.windowText, actual: presenter.colors.windowText,
        cppID: pageID, what: "inputText resolves input_text")

    let themed = GridPalette()
    ShellAppearance.apply(to: themed, mode: "dark-neutral-high", contrast: 50)
    let themedPresenter = EventListPresenter(palette: themed)
    themedPresenter.attach(session: suite)
    report.expectEqual(
        expected: "#424242",
        actual: PaletteMath.hex(themedPresenter.colors.menuBackground),
        cppID: pageID, what: "attached presenter spells the session palette's item surface")
    ShellAppearance.apply(to: themed, mode: "vanilla", contrast: 50)
    themedPresenter.refreshAppearance()
    report.expectEqual(
        expected: "#D2D0CA",
        actual: PaletteMath.hex(themedPresenter.colors.menuBackground),
        cppID: pageID, what: "refreshAppearance preserves the live theme surface")
    report.expectEqual(
        expected: "#A49D97",
        actual: PaletteMath.hex(themedPresenter.colors.scrollbarHandle),
        cppID: pageID, what: "vanilla returns the dedicated scrollbar preset")
    ShellAppearance.apply(to: themed, mode: "dark-neutral-high", contrast: 50)
    themedPresenter.refreshAppearance()
    report.expectEqual(
        expected: "#262626",
        actual: PaletteMath.hex(themedPresenter.colors.scrollbarHandle),
        cppID: pageID, what: "dark theme swaps the scrollbar thumb preset")
    report.expectEqual(
        expected: "#5C5C5C",
        actual: PaletteMath.hex(themedPresenter.colors.buttonHoverBackground),
        cppID: pageID, what: "dark theme swaps the input surface preset")

    for preset in ["vanilla", "dark-neutral-high", "immaterial"] {
        let presetPalette = GridPalette()
        ShellAppearance.apply(to: presetPalette, mode: preset, contrast: 50)
        let colors = EventListPresenter(palette: presetPalette).colors
        let pairs: [(String, String, QmlColor, QmlColor)] = [
            ("tableText", "tableBackground", colors.windowText, colors.menuBackground),
            ("tableText", "tableAlternateBackground", colors.windowText, colors.alternateBackground),
            ("tableSecondaryText", "tableBackground", colors.secondaryText, colors.menuBackground),
            ("tableSelectedText", "tableSelectedBackground", colors.selectionText, colors.tabSelectedBackground),
            ("headerText", "headerBackground", colors.windowText, colors.chromeBackground),
            ("buttonText", "buttonBackground", colors.buttonText, colors.buttonBackground),
            ("inputText", "inputBackground", colors.windowText, colors.buttonHoverBackground),
            ("toolTipText", "toolTipBackground", colors.windowText, colors.inputBackground),
        ]
        for (text, background, textColor, backgroundColor) in pairs {
            let ink = PaletteMath.hex(textColor)
            let fill = PaletteMath.hex(backgroundColor)
            let ratio = PaletteMath.contrastRatio(ink, fill)
            report.expect(
                ratio >= 4.5, cppID: pageID,
                message: "\(preset) \(text) on \(background) holds WCAG AA "
                    + "(ratio \(String(format: "%.2f", ratio)))")
        }
    }
}

@MainActor
internal func eventListSummaryParity(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
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
                ], endTick: 144)
        ])
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
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
    report.expectEqual(
        expected: "Track name \"Route 101 lead\"",
        actual: summary { $0.event?.metaType == 3 },
        cppID: pageID, what: "text meta names its kind and quoted text")
    report.expectEqual(
        expected: "Text \"[\" — loop start",
        actual: summary { $0.event?.metaType == 1 && $0.tick == 48 },
        cppID: pageID, what: "bracket text meta gains the loop-start suffix")
    report.expectEqual(
        expected: "Text \"]\" — loop end",
        actual: summary { $0.event?.metaType == 1 && $0.tick == 96 },
        cppID: pageID, what: "close-bracket text meta gains the loop-end suffix")
    report.expectEqual(
        expected: "Marker \"mid\"",
        actual: summary { $0.event?.metaType == 6 },
        cppID: pageID, what: "marker meta keeps lowercase sentence spelling")
    report.expectEqual(
        expected: "Channel prefix",
        actual: summary { $0.event?.metaType == 0x20 },
        cppID: pageID, what: "channel prefix names its meta kind")
    report.expectEqual(
        expected: "Key signature",
        actual: summary { $0.event?.metaType == 0x59 },
        cppID: pageID, what: "key signature names its meta kind")
    report.expectEqual(
        expected: "Time signature 4/4",
        actual: summary { $0.event?.metaType == 0x58 },
        cppID: pageID, what: "time signature summarizes numerator and denominator")
    report.expectEqual(
        expected: "Voice 0 — Square 1",
        actual: summary { $0.tick == 0 && $0.event?.typeNibble == 0xC },
        cppID: pageID, what: "program change names the bank voice at its slot")
    report.expectEqual(
        expected: "Meta 0x2a",
        actual: summary { $0.event?.metaType == 0x2A },
        cppID: pageID, what: "unknown meta names its type in lowercase hex")
    report.expectEqual(
        expected: "Voice 5",
        actual: summary { $0.tick == 4 && $0.event?.typeNibble == 0xC },
        cppID: pageID, what: "empty-name slots fall back to the bare voice number")
    report.expectEqual(
        expected: "Note off C4 (velocity-0 note-on)",
        actual: summary { $0.event?.typeNibble == 0x9 },
        cppID: pageID, what: "velocity-zero note-on spells the key name")
    report.expectEqual(
        expected: "Note on C4, velocity 98",
        actual: summary { $0.tick == 10 && $0.event?.typeNibble == 0x9 },
        cppID: pageID, what: "note-on spells key name and velocity")
    report.expectEqual(
        expected: "Note off C4",
        actual: summary { $0.event?.typeNibble == 0x8 },
        cppID: pageID, what: "note-off spells the key name")
    report.expectEqual(
        expected: "Poly aftertouch C4 = 30",
        actual: summary { $0.event?.typeNibble == 0xA },
        cppID: pageID, what: "poly aftertouch spells key and pressure")
    report.expectEqual(
        expected: "CC 10 Pan = c_v+0",
        actual: summary { $0.event?.typeNibble == 0xB },
        cppID: pageID, what: "control change shows classified name and formatted value")
    report.expectEqual(
        expected: "Channel aftertouch = 40",
        actual: summary { $0.event?.typeNibble == 0xD },
        cppID: pageID, what: "channel aftertouch shows its pressure")
    report.expectEqual(
        expected: "Pitch bend +1024",
        actual: summary { $0.event?.typeNibble == 0xE },
        cppID: pageID, what: "pitch bend formats a signed 14-bit value")
    report.expectEqual(
        expected: "5 payload byte(s)",
        actual: summary { $0.event?.isChannel == false && $0.event?.metaType == nil },
        cppID: pageID, what: "sysex rows count their payload bytes")
}
