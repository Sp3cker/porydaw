import PorydawApp
import PorydawCore

@MainActor
func runOtherEventsBandChecks(_ report: CheckReport) {
    let file = MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
            .meta(tick: 12, type: 0x06, data: [0x5B]),
            .meta(tick: 18, type: 0x06, data: [0x5D]),
            .meta(tick: 24, type: 0x7F, data: [0x01]),
        ], endTick: 48),
        MidiChunk(events: [
            .channel(tick: 0, status: 0x90, data0: 60, data1: 90),
            .channel(tick: 0, status: 0xB0, data0: 7, data1: 100),
            .channel(tick: 1, status: 0x90, data0: 60, data1: 90),
            .channel(tick: 12, status: 0xB0, data0: 0x1E, data1: 8),
            .channel(tick: 12, status: 0xB0, data0: 0x1D, data1: 32),
            .channel(tick: 24, status: 0xB0, data0: 5, data1: 1),
            .channel(tick: 24, status: 0xB0, data0: 99, data1: 72),
            .channel(tick: 24, status: 0x80, data0: 61),
            .channel(tick: 30, status: 0x80, data0: 60),
            .channel(tick: 32, status: 0x80, data0: 60),
        ], endTick: 48),
    ])
    let timeline = PlaybackTimeline.build(file: file, sampleRate: 48_000)
    let strip = OtherEventsStrip.items(timeline: timeline)
    let id = "swiftcore/OtherEventsBand::projection"
    report.expect(strip.contains { $0.label == m4aAdvancedCCLabel(controller: 5, value: 1) },
                  cppID: id, message: "a non-audible mapped controller appears with its advanced label")
    report.expect(strip.contains { $0.label == "CC 99 = 72 (no m4a meaning)" },
                  cppID: id, message: "an unknown controller appears with its no-meaning label")
    report.expect(strip.contains { $0.label == "Note off (key 61) without a note on" },
                  cppID: id, message: "a note-off without an open note of the same track and key is an orphan")
    report.expect(!strip.contains { $0.label == "Note off (key 60) without a note on" },
                  cppID: id,
                  message: "overlapping same-key notes consume one open note per note-off")
    report.expect(!strip.contains { $0.label.contains("VOL") },
                  cppID: id, message: "audible-lane volume controllers do not enter the other-events strip")
    report.expect(!strip.contains { $0.label.contains("xIECV") || $0.label.contains("CC 30") || $0.label.contains("CC 29") },
                  cppID: id, message: "XCMD selector and payload are consumed before strip projection")
    report.expect(strip.contains { $0.label == "Meta 0x7f (1 bytes)" && $0.track == -1 },
                  cppID: id, message: "file-level other events retain their verbatim labels and file identity")
    report.expect(!strip.contains { $0.label.contains("Marker: [") },
                  cppID: id, message: "recognized loop-marker metas never enter the strip")
    report.expect(strip.map(\.tick) == strip.map(\.tick).sorted(), cppID: id,
                  message: "strip items are ordered by tick")
    report.expect(strip.filter { $0.tick == 24 }.last?.track == -1,
                  cppID: id, message: "events-loop items precede file-level otherEvents at the same tick")
    report.expect(strip.count == 4, cppID: "swiftcore/OtherEventsBand::count",
                  message: "the full strip count includes advanced CCs, orphan note-offs and file-level events")
    report.expect(OtherEventsStrip.bandHeight(baseFontPx: 13, appFontLineSpacing: 17) == 17 + Int((13.0 * 0.5).rounded()),
                  cppID: "swiftcore/OtherEventsBand::metrics",
                  message: "band height derives from application line spacing and a half-font spacing")
    let base = 13.0
    let limits = EditorCamera.Limits(
        defaultPixelsPerBeat: (base * 8 / 3).rounded(),
        minPixelsPerBeat: (base / 3).rounded(),
        maxPixelsPerBeat: (base * 160 / 3).rounded(),
        defaultKeyHeight: base, minKeyHeight: (base / 3).rounded(),
        maxKeyHeight: (base * 8 / 3).rounded(),
        revealViewportFraction: 1 / 3, minimumPlotWidth: (base * 25 / 6).rounded())
    let camera = EditorCamera(ticksPerBeat: 24, lengthTicks: 48,
                              viewportWidth: base * 12, rollHeight: base * 12, limits: limits)
    let palette = GridPalette()
    let markers = OtherEventsStrip.markers(items: strip, camera: camera, plotWidth: base * 12,
                                            baseFontPx: base, palette: palette)
    let fileMarker = markers.first { $0.track == -1 }
    report.expect(markers.count == strip.count, cppID: "swiftcore/OtherEventsBand::markers",
                  message: "every strip event inside the camera viewport has a marker")
    report.expect(fileMarker?.tick == 24 && fileMarker?.color == palette.outline,
                  cppID: "swiftcore/OtherEventsBand::markers",
                  message: "file-level markers use the palette outline")
    report.expect(fileMarker?.x == camera.contentX(tick: 24),
                  cppID: "swiftcore/OtherEventsBand::markers",
                  message: "marker x is the shared camera content position of its tick")
    report.expect(markers.contains { $0.track == 0 && $0.color == PaletteMath.trackIdentityFills[0] },
                  cppID: "swiftcore/OtherEventsBand::markers",
                  message: "track markers use the stable track-identity fill")
    let narrow = OtherEventsStrip.markers(items: strip, camera: camera,
                                          plotWidth: camera.contentX(tick: 24) / 2,
                                          baseFontPx: 13, palette: palette)
    report.expect(!narrow.contains { $0.tick == 24 },
                  cppID: "swiftcore/OtherEventsBand::markers",
                  message: "markers beyond the plot width plus hit slop are culled")
    let lines = OtherEventsStrip.tooltipLines(items: strip, x: camera.contentX(tick: 24),
                                              camera: camera, baseFontPx: 13,
                                              sampleRate: timeline.sampleRate)
    report.expect(lines.contains { $0.contains(" · File · Meta 0x7f (1 bytes)") } &&
                  lines.contains { $0.contains(" · Track 1 · ") },
                  cppID: "swiftcore/OtherEventsBand::tooltip",
                  message: "hover lines format timestamp, File or one-based Track, and the event label")
    let crowded = Array(repeating: strip[0], count: 14)
    let capped = OtherEventsStrip.tooltipLines(items: crowded,
        x: camera.contentX(tick: Double(strip[0].tick)), camera: camera,
        baseFontPx: 13, sampleRate: timeline.sampleRate)
    report.expect(capped.count == 13 && capped.last == "…",
                  cppID: "swiftcore/OtherEventsBand::tooltip",
                  message: "more than twelve hovered events yield twelve lines followed by an ellipsis")
    let presenter = OtherEventsBandPresenter()
    presenter.configure(session: nil, palette: palette, baseFontPx: 13, appFontLineSpacing: 17,
                        plotWidth: 150)
    report.expect(presenter.labelCount == 0 && !presenter.toolTipVisible,
                  cppID: "swiftcore/OtherEventsBand::lifecycle",
                  message: "an unattached band has zero items and no tooltip")
    for mode in ["vanilla", "dark-neutral-high", "immaterial"] {
        let themed = GridPalette()
        ShellAppearance.apply(to: themed, mode: mode, contrast: 100)
        report.expect(PaletteMath.contrastRatio(themed.windowText, themed.chromeBackground) >= 4.5,
                      cppID: "swiftcore/OtherEventsBand::contrast",
                      message: "\(mode) band gutter label keeps WCAG AA normal-text contrast on chrome")
    }
}
