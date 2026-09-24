import PorydawCore

@MainActor
func unsignedTicksAndRawSignaturePrecedence(_ report: CheckReport) {
    let onTick: Tick = 0x8000_0010
    let offTick = onTick + 32
    let document = SongDocument(file: MidiFile(division: 960, chunks: [
        MidiChunk(events: [
            .meta(type: 0x58, data: [7, 3, 0x18, 8]),
            .meta(type: 0x58, data: [5, 31, 0x18, 8]),
        ]),
        MidiChunk(events: [
            .meta(type: 0x58, data: [0, 255, 0x18, 8]),
            .channel(tick: onTick, status: 0x90, data0: 64, data1: 81),
            .channel(tick: offTick, status: 0x80, data0: 64),
        ], endTick: offTick),
        MidiChunk(events: [
            .channel(tick: onTick, status: 0x91, data0: 72, data1: 81),
            .channel(tick: offTick, status: 0x81, data0: 72),
        ], endTick: offTick),
    ]))
    let cppID = "swiftdocfeed/SwiftDocFeedTest::unsignedTicksAndRawSignaturePrecedence"
    report.expectEqual(2, document.engineTracks.usedTrackCount,
                       cppID: cppID, what: "conductor chunk leaves two note tracks")
    report.expectEqual(960, document.ticksPerBeat,
                       cppID: cppID, what: "document keeps the 960-tick division")
    report.expectEqual(["0:64:2147483664:32", "1:72:2147483664:32"],
                       (0..<2).flatMap { track in
                           document.notes(in: track).map {
                               "\(track):\($0.pitch):\($0.tick):\($0.duration)"
                           }
                       },
                       cppID: cppID, what: "both tracks preserve unsigned note ticks and durations")
    report.expectEqual(["7:3", "5:31", "0:255"],
                       document.timeSignatures.map {
                           "\($0.numerator):\($0.denominatorPower)"
                       },
                       cppID: cppID, what: "raw signature bytes retain order and full-width values")
}
