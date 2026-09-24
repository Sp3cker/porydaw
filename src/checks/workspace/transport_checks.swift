@testable import PorydawApp
import PorydawCore

@MainActor
internal func runTransportBarChecks(_ report: CheckReport) {
    let id = "swiftcore/TransportBar::clockAndMeasure"
    report.expectEqual("0:00.0", TransportBarPresenter.clock(sample: 0, sampleRate: 48_000),
                       cppID: id, what: "empty transport starts at zero tenths")
    report.expectEqual("0:59.9", TransportBarPresenter.clock(sample: 2_879_999,
                                                              sampleRate: 48_000),
                       cppID: id, what: "subminute clock truncates rather than rounds")
    report.expectEqual("1:00.0", TransportBarPresenter.clock(sample: 2_880_000,
                                                              sampleRate: 48_000),
                       cppID: id, what: "clock carries seconds at minute boundary")

    var file = makeMidiFixture()
    file.chunks[0].events.append(.meta(tick: 192, type: 0x58, data: [3, 2, 24, 8]))
    let timeline = PlaybackTimeline.build(file: file, sampleRate: 48_000)
    report.expectEqual("1:1", TransportBarPresenter.measure(at: 0, timeline: timeline),
                       cppID: id, what: "opening bar and beat are one-based")
    report.expectEqual("1:4", TransportBarPresenter.measure(at: 72, timeline: timeline),
                       cppID: id, what: "fourth beat belongs to opening measure")
    report.expectEqual("2:1", TransportBarPresenter.measure(at: 96, timeline: timeline),
                       cppID: id, what: "bar increments at its beat boundary")
    report.expectEqual("3:1", TransportBarPresenter.measure(at: 192, timeline: timeline),
                       cppID: id, what: "time-signature change starts the third bar")
    report.expectEqual("4:1", TransportBarPresenter.measure(at: 264, timeline: timeline),
                       cppID: id, what: "new 3/4 segment advances after three beats")
}
