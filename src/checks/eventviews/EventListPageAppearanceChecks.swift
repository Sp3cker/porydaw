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
        let roles: [(String, GridFontSpec)] = [
            ("bodyFont", typography.body), ("controlFont", typography.body),
            ("tableFont", typography.tableMono), ("headerFont", typography.caption),
        ]
        for (name, spec) in roles {
            let map = presenter.appearance[name] as? [String: QVariantSettable]
            report.expect((map?["family"] as? String) == spec.family
                          && (map?["pixelSize"] as? Int) == spec.pixelSize
                          && (map?["weight"] as? Int) == spec.weight
                          && (map?["letterSpacing"] as? Double) == spec.letterSpacing,
                          cppID: pageID, message: "\(name) follows the captured typography role")
        }
    }
    expectRoles(seed)
    let defaults = [70.0, 120.0, 36.0, 56.0, 56.0, 140.0]
    for column in defaults.indices {
        report.expect(presenter.savedColumnWidth(column: column) == defaults[column],
                      cppID: pageID, message: "seed column \(column) follows the fork fraction")
    }
    let doubledTypography = Typography(baseFontPx: 26)
    presenter.configureTypography(typography: doubledTypography)
    expectRoles(doubledTypography)
    for column in defaults.indices {
        report.expect(presenter.savedColumnWidth(column: column) == defaults[column] * 2,
                      cppID: pageID, message: "base 26 doubles default column \(column)")
    }
    presenter.configureTypography(typography: Typography(baseFontPx: 10))
    for column in defaults.indices {
        report.expect(presenter.savedColumnWidth(column: column)
                      == Double(Typography(baseFontPx: 10).fontPx(defaults[column] / 13)),
                      cppID: pageID, message: "base 10 rounds default column \(column)")
    }
    presenter.resizeColumn(column: 1, width: 200)
    presenter.configureTypography(typography: doubledTypography)
    report.expect(presenter.savedColumnWidth(column: 1) == 200,
                  cppID: pageID, message: "user-resized Type column survives font changes")
    report.expect(presenter.columnWidths.count == defaults.count, cppID: pageID,
                  message: "the resized store keeps six entries")
    report.expect(presenter.savedColumnWidth(column: 0) == 140
                  && presenter.savedColumnWidth(column: 2) == 72,
                  cppID: pageID, message: "untouched columns rederive after Type resize")
    ShellAppearance.apply(to: palette, mode: "dark-neutral-high", contrast: 50)
    presenter.refreshAppearance()
    expectRoles(doubledTypography)
}

@MainActor
internal func eventListChunkLabelParity(_ report: CheckReport, suite: DocumentSession,
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
internal func eventListAppearanceParity(_ report: CheckReport, suite: DocumentSession,
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
internal func eventListSummaryParity(_ report: CheckReport, suite: DocumentSession,
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
