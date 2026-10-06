import Foundation
import PorydawCore

internal func xcmdPairedProjection(_ report: CheckReport) {
    let events = [
        Xcmd.Event(index: 9, tick: 1, stream: 0, controller: 0x1E, value: 0x08),
        Xcmd.Event(index: 2, tick: 2, stream: 0, controller: 0x1D, value: 34),
        Xcmd.Event(index: 7, tick: 3, stream: 0, controller: 0x1F, value: 35),
    ]
    let projection = Xcmd.project(events)
    report.expectEqual(
        expected: [34, 35], actual: projection.points.map { Int($0.value) },
        cppID: "xcmdcheck/XcmdTest::sharedSelectorServesTwoCompletions",
        what: "one selector serves every payload in its epoch")
    report.expectEqual(
        expected: [2, 7, 9], actual: projection.consumed,
        cppID: "xcmdcheck/XcmdTest::consumedIsSortedDedupIndexSet",
        what: "consumed identities are sorted")
    let opaque = Xcmd.project([
        Xcmd.Event(index: 0, tick: 0, stream: 0, controller: 0x1E, value: 0x2A),
        Xcmd.Event(index: 1, tick: 1, stream: 0, controller: 0x1D, value: 99),
    ])
    report.expect(
        opaque.points.isEmpty && opaque.consumed == [0, 1],
        cppID: "xcmdcheck/XcmdTest::unknownSelectorEpochStaysOpaque",
        message: "unknown epoch is consumed but not projected")
}

private func xcmdPairSharedSelectorServesTwoCompletions(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08),
        xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34),
        xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 35),
    ]
    let result = Xcmd.project(events)
    report.expect(
        result.points.count == 2 && result.points[0].lane == Xcmd.echoVolumeLane && result.points[0].value == 34
            && result.points[0].tick == 2 && result.points[0].index == 1 && result.points[1].value == 35
            && result.points[1].tick == 3 && result.points[1].index == 2 && result.consumed == [0, 1, 2],
        cppID: "xcmdcheck/XcmdTest::sharedSelectorServesTwoCompletions",
        message: "shared-selector projection did not expose both points and consumed indices")
}

private func xcmdPairUnknownSelectorEpochStaysOpaque(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x01),
        xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 1),
        xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 2),
    ]
    let result = Xcmd.project(events)
    report.expect(
        result.points.isEmpty && result.consumed == [0, 1, 2],
        cppID: "xcmdcheck/XcmdTest::unknownSelectorEpochStaysOpaque",
        message: "unknown-selector epoch did not stay opaque with consumed bytes")
}

private func xcmdPairDanglingKnownSelectorProjectsOpaque(_ report: CheckReport) {
    let events = [xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08)]
    let result = Xcmd.project(events)
    report.expect(
        result.points.isEmpty && result.consumed == [0],
        cppID: "xcmdcheck/XcmdTest::danglingKnownSelectorProjectsOpaque",
        message: "payload-less selector epoch did not project as opaque")
}

private func xcmdPairLeadingStrayPayloadsStayOpaque(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(0, 1, 0, Xcmd.payloadController, 99),
        xcmdPairEvent(1, 2, 0, Xcmd.selectorController, 0x09),
        xcmdPairEvent(2, 3, 0, Xcmd.payloadController, 17),
    ]
    let result = Xcmd.project(events)
    report.expect(
        result.points.count == 1 && result.points[0].value == 17 && result.consumed == [0, 1, 2],
        cppID: "xcmdcheck/XcmdTest::leadingStrayPayloadsStayOpaque",
        message: "leading stray payload run was not kept opaque")
}

private func xcmdPairStreamsProjectIndependently(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(0, 1, 0, Xcmd.selectorController, 0x08), xcmdPairEvent(1, 2, 0, Xcmd.payloadController, 34),
        xcmdPairEvent(2, 1, 1, Xcmd.selectorController, 0x09), xcmdPairEvent(3, 2, 1, Xcmd.payloadController, 17),
    ]
    let result = Xcmd.project(events)
    report.expect(
        result.points.count == 2 && result.points[0].stream == 0 && result.points[0].lane == Xcmd.echoVolumeLane
            && result.points[1].stream == 1 && result.points[1].lane == Xcmd.echoLengthLane
            && result.points[1].value == 17,
        cppID: "xcmdcheck/XcmdTest::streamsProjectIndependently",
        message: "streams did not project independently")
}

private func xcmdPairConsumedIsSortedDedupIndexSet(_ report: CheckReport) {
    let events = [
        xcmdPairEvent(9, 1, 0, Xcmd.selectorController, 0x08),
        xcmdPairEvent(2, 2, 0, Xcmd.payloadController, 34),
        xcmdPairEvent(7, 3, 0, Xcmd.alternatePayloadController, 35),
    ]
    let result = Xcmd.project(events)
    report.expect(
        result.consumed == [2, 7, 9],
        cppID: "xcmdcheck/XcmdTest::consumedIsSortedDedupIndexSet",
        message: "protocol consumption was not a sorted raw-index set")
}

internal func runXcmdProjectionOriginalChecks(_ report: CheckReport) {
    xcmdPairSharedSelectorServesTwoCompletions(report)
    xcmdPairUnknownSelectorEpochStaysOpaque(report)
    xcmdPairDanglingKnownSelectorProjectsOpaque(report)
    xcmdPairLeadingStrayPayloadsStayOpaque(report)
    xcmdPairStreamsProjectIndependently(report)
    xcmdPairConsumedIsSortedDedupIndexSet(report)
}

internal func runReusableTimelineBuilderChecks(_ report: CheckReport) {
    let id = "no-row/playback/reusableTimelineRetainsPublishedSnapshots"
    let originalFile = MidiFile(
        division: 48,
        chunks: [
            MidiChunk(
                events: [
                    .meta(type: 0x51, data: [0x07, 0xA1, 0x20]),
                    .meta(type: 0x58, data: [4, 2]),
                    .meta(type: 0x06, data: [0x5B]),
                    .meta(tick: 12, type: 0x06, data: [0x5D]),
                ], endTick: 12),
            MidiChunk(
                events: [
                    .meta(type: 0x03, data: Array("Lead".utf8)),
                    .channel(status: 0xC0, data0: 7),
                    .channel(tick: 2, status: 0x90, data0: 60, data1: 100, noteID: NoteID(41)),
                    .channel(tick: 10, status: 0x80, data0: 60),
                    .meta(tick: 12, type: 0x05, data: Array("end".utf8)),
                ], endTick: 12),
        ])
    let replacementFile = MidiFile(
        division: 48,
        chunks: [
            MidiChunk(
                events: [
                    .meta(type: 0x51, data: [0x07, 0xA1, 0x20]),
                    .meta(type: 0x03, data: Array("Bass".utf8)),
                    .channel(status: 0xC0, data0: 9),
                    .channel(tick: 2, status: 0x90, data0: 62, data1: 80, noteID: NoteID(83)),
                    .meta(tick: 4, type: 0x58, data: [3, 3]),
                    .meta(tick: 4, type: 0x06, data: [0x5B]),
                    .channel(tick: 4, status: 0x90, data0: 64, data1: 90, noteID: NoteID(84)),
                    .channel(tick: 8, status: 0x80, data0: 64),
                    .meta(tick: 8, type: 0x06, data: [0x5D]),
                    .channel(tick: 9, status: 0xD0, data0: 40),
                ], endTick: 9)
        ])
    let replacementState = SongState(
        file: replacementFile,
        tempo: [
            TempoPoint(tick: 0, microsecondsPerQuarterNote: 1_000_000),
            TempoPoint(tick: 4, microsecondsPerQuarterNote: 250_000),
            TempoPoint(tick: 4, microsecondsPerQuarterNote: 500_000),
        ],
        config: SongConfig(exactGate: true, extendedClocks: true))
    let settings = PlaybackSettings(exactGate: true, extendedClocks: true)
    var builder = PlaybackTimelineBuilder()
    let original = builder.build(file: originalFile, sampleRate: 48_000, settings: settings)
    let replacement = builder.build(state: replacementState, sampleRate: 48_000)
    let unmatchedEnd = builder.build(
        file: MidiFile(
            division: 48,
            chunks: [
                MidiChunk(events: [.channel(tick: 5, status: 0x80, data0: 62)], endTick: 5)
            ]),
        tempo: [], sampleRate: 48_000)
    let empty = builder.build(file: MidiFile(division: 48, chunks: []), sampleRate: 24_000)
    let restored = builder.build(file: originalFile, sampleRate: 48_000, settings: settings)

    let originalEvents = [
        PlaybackEvent(sample: 0, tick: 0, type: playbackTempoEventType, track: 0, data0: 120, data1: 0),
        PlaybackEvent(sample: 0, tick: 0, type: 0xC, track: 0, data0: 7, data1: 0),
        PlaybackEvent(sample: 1_000, tick: 2, type: 0x9, track: 0, data0: 60, data1: 100, noteID: NoteID(41)),
        PlaybackEvent(sample: 5_000, tick: 10, type: 0x8, track: 0, data0: 60, data1: 0),
    ]
    report.expectEqual(
        expected: originalEvents, actual: original.events, cppID: id,
        what: "retained original event samples, order and identity")
    report.expectEqual(
        expected: originalEvents, actual: restored.events, cppID: id,
        what: "restored input scheduling after larger and empty builds")
    report.expect(
        original.tracks[0] == PlaybackTrack(name: "Lead", used: true, noteCount: 1, firstProgram: 7)
            && original.tracks.dropFirst().allSatisfy { !$0.used }
            && original.usedTrackCount == 1 && original.droppedTracks == 0
            && original.tempoMap.count == 1 && original.tempoMap[0].microsecondsPerQuarterNote == 500_000
            && original.timeSignatures == [PlaybackTimeSignature(tick: 0, numerator: 4, denominatorPowerOfTwo: 2)]
            && original.otherEvents.count == 1 && original.otherEvents[0].tick == 12
            && original.otherEvents[0].sample == 6_000 && original.otherEvents[0].track == 0
            && original.otherEvents[0].label == "Lyric: end",
        cppID: id, message: "later builds changed retained original track, tempo, signature or other-event storage")
    report.expect(
        original.hasLoop && original.loopStartSample == 0 && original.loopEndSample == 6_000
            && original.loopStartTick == 0 && original.loopEndTick == 12
            && original.lengthSamples == 5_000 && original.lengthTicks == 12 && original.settings == settings,
        cppID: id, message: "retained original loop, length or gate settings changed")

    let replacementEvents = [
        PlaybackEvent(sample: 0, tick: 0, type: playbackTempoEventType, track: 0, data0: 60, data1: 0),
        PlaybackEvent(sample: 0, tick: 0, type: 0xC, track: 0, data0: 9, data1: 0),
        PlaybackEvent(sample: 2_000, tick: 2, type: 0x9, track: 0, data0: 62, data1: 80, noteID: NoteID(83)),
        PlaybackEvent(sample: 4_000, tick: 4, type: playbackTempoEventType, track: 0, data0: 112, data1: 1),
        PlaybackEvent(sample: 4_000, tick: 4, type: playbackTempoEventType, track: 0, data0: 120, data1: 0),
        PlaybackEvent(sample: 4_000, tick: 4, type: 0x9, track: 0, data0: 64, data1: 90, noteID: NoteID(84)),
        PlaybackEvent(sample: 6_000, tick: 8, type: 0x8, track: 0, data0: 64, data1: 0),
    ]
    report.expectEqual(
        expected: replacementEvents, actual: replacement.events, cppID: id,
        what: "retained replacement scheduling with authoritative same-tick tempo precedence")
    report.expect(
        replacement.tracks[0] == PlaybackTrack(name: "Bass", used: true, noteCount: 2, firstProgram: 9)
            && replacement.tempoMap.map(\.microsecondsPerQuarterNote) == [1_000_000, 250_000, 500_000]
            && replacement.timeSignatures == [PlaybackTimeSignature(tick: 4, numerator: 3, denominatorPowerOfTwo: 3)]
            && replacement.otherEvents.count == 1 && replacement.otherEvents[0].tick == 9
            && replacement.otherEvents[0].sample == 6_500 && replacement.otherEvents[0].track == 0
            && replacement.otherEvents[0].label == "Channel pressure 40"
            && replacement.hasLoop && replacement.loopStartSample == 4_000 && replacement.loopEndSample == 6_000
            && replacement.lengthTicks == 9 && replacement.lengthSamples == 6_000 && replacement.settings == settings,
        cppID: id, message: "replacement retained stale projection data or lost authoritative timing")
    report.expectEqual(
        expected: [
            PlaybackEvent(sample: 0, tick: 0, type: playbackTempoEventType, track: 0, data0: 120, data1: 0),
            PlaybackEvent(sample: 2_500, tick: 5, type: 0x8, track: 0, data0: 62, data1: 0),
        ], actual: unmatchedEnd.events, cppID: id,
        what: "unmatched note end must not pair with a previous build's dangling note")
    report.expect(
        !unmatchedEnd.hasLoop && unmatchedEnd.timeSignatures.isEmpty && unmatchedEnd.otherEvents.isEmpty
            && unmatchedEnd.tracks[0].name.isEmpty && unmatchedEnd.tracks[0].noteCount == 0
            && unmatchedEnd.tracks[0].firstProgram == -1 && unmatchedEnd.settings == PlaybackSettings(),
        cppID: id, message: "shorter build inherited names, programs, signatures, loops or settings")
    report.expect(
        empty.events.count == 1 && empty.events[0].type == playbackTempoEventType
            && empty.usedTrackCount == 0 && empty.tracks.allSatisfy { !$0.used }
            && empty.timeSignatures.isEmpty && empty.otherEvents.isEmpty && !empty.hasLoop
            && empty.lengthTicks == 0 && empty.lengthSamples == 0 && empty.sampleRate == 24_000,
        cppID: id, message: "empty build did not reset prior populated scratch")
}
