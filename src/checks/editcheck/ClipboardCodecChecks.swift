import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func runClipboardCodecSuite(_ report: CheckReport) {
    let noteClip = PorydawClip(tracks: [ClipTrack(track: 3, notes: [
        ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
        ClipNote(relTick: 12, key: 64, duration: 12, velocity: 80),
    ])])
    let timeClip = PorydawClip(
        span: 96,
        tracks: [ClipTrack(track: 0, notes: [
            ClipNote(relTick: 0, key: 60, duration: 24, velocity: 100),
            ClipNote(relTick: 72, key: 67, duration: 12, velocity: 90),
        ])],
        lanes: [
            ClipLane(track: 0, cc: 1, points: [
                ClipLanePoint(relTick: 24, value: 80),
                ClipLanePoint(relTick: 72, value: 32),
            ]),
            ClipLane(track: 0, cc: TimeDefaults.laneCCBend, points: [
                ClipLanePoint(relTick: 48, value: 4_096),
            ]),
            ClipLane(track: 0, cc: 7, points: []),
        ],
        tempo: [
            ClipTempo(relTick: 0, microsecondsPerQuarterNote: 500_000),
            ClipTempo(relTick: 48, microsecondsPerQuarterNote: 400_000),
        ])

    roundTrip(noteClip, ticksPerBeat: 24,
              cppID: "clipmimecheck/ClipMimeTest::codecRoundTrips[plain_note_clip]",
              report: report)
    roundTrip(timeClip, ticksPerBeat: 24,
              cppID: "clipmimecheck/ClipMimeTest::codecRoundTrips[time_clip_with_bend_empty_lane_and_tempo]",
              report: report)

    let routedClip = PorydawClip(span: 24, tracks: [ClipTrack(track: 1, notes: [
        ClipNote(relTick: 0, key: 55, duration: 12, velocity: 70),
    ])])
    let routedCore = ClipboardCodec.encode(routedClip, ticksPerBeat: 24)
        .flatMap(ClipboardCodec.decode)
    let routedScaled = routedCore.map {
        ClipboardCodec.rescale($0.clip, sourceTicksPerBeat: $0.ticksPerBeat,
                               destinationTicksPerBeat: 48)
    }
    report.expect(routedCore?.ticksPerBeat == 24 && routedCore?.clip == routedClip
        && routedScaled?.span == 48
        && routedScaled?.tracks.count == 1
        && routedScaled?.tracks.first?.notes.first?.duration == 24,
        cppID: "clipmimecheck/ClipMimeTest::clipboardRoutesClipMime",
        message: "the production codec and rescaler preserve the single routed track; native MIME transport remains a host assertion")

    let malformedKinds = [
        "truncated_json", "garbage_bytes", "wrong_format", "missing_ticks_per_beat",
        "zero_ticks_per_beat", "missing_tracks", "wrong_typed_lanes", "missing_tempo",
        "negative_span", "negative_note_tick", "missing_note_velocity",
        "lane_point_missing_value", "tempo_missing_microseconds", "nonfinite_tick",
    ]
    for kind in malformedKinds {
        report.expect(ClipboardCodec.decode(malformedClipboardPayload(kind)) == nil,
                      cppID: "clipmimecheck/ClipMimeTest::malformedPayloads[\(kind)]",
                      message: "the exact malformed baseline payload is rejected")
    }
    report.expect(ClipboardCodec.decode(Data("not json at all".utf8)) == nil,
                  cppID: "clipmimecheck/ClipMimeTest::malformedCustomMimeReportsDecodeFailure",
                  message: "the production decoder rejects the exact corrupt custom-MIME payload; native failure routing remains a host assertion")

    let upInput = PorydawClip(
        span: 12,
        tracks: [ClipTrack(track: 3, notes: [
            ClipNote(relTick: 6, key: 64, duration: 3, velocity: 91),
        ])],
        lanes: [ClipLane(track: 4, cc: 1, points: [
            ClipLanePoint(relTick: 6, value: -12),
        ])],
        tempo: [ClipTempo(relTick: 6, microsecondsPerQuarterNote: 400_000)])
    let upExpected = PorydawClip(
        span: 24,
        tracks: [ClipTrack(track: 3, notes: [
            ClipNote(relTick: 12, key: 64, duration: 6, velocity: 91),
        ])],
        lanes: [ClipLane(track: 4, cc: 1, points: [
            ClipLanePoint(relTick: 12, value: -12),
        ])],
        tempo: [ClipTempo(relTick: 12, microsecondsPerQuarterNote: 400_000)])
    report.expectEqual(
        expected: upExpected,
        actual: ClipboardCodec.rescale(upInput, sourceTicksPerBeat: 24, destinationTicksPerBeat: 48),
        cppID: "clipmimecheck/ClipMimeTest::rescaleFamilies[up_24_to_48]",
        what: "exact up-scaled clip")

    let downInput = PorydawClip(
        span: 1,
        tracks: [ClipTrack(track: 2, notes: [
            ClipNote(relTick: 1, key: 60, duration: 1, velocity: 100),
            ClipNote(relTick: 3, key: 61, duration: 0, velocity: 80),
        ])],
        lanes: [ClipLane(track: 2, cc: 7, points: [
            ClipLanePoint(relTick: 2, value: 20),
            ClipLanePoint(relTick: 1, value: 10),
            ClipLanePoint(relTick: 3, value: 30),
        ])],
        tempo: [
            ClipTempo(relTick: 2, microsecondsPerQuarterNote: 500_000),
            ClipTempo(relTick: 1, microsecondsPerQuarterNote: 600_000),
            ClipTempo(relTick: 3, microsecondsPerQuarterNote: 700_000),
        ])
    let downExpected = PorydawClip(
        span: 1,
        tracks: [ClipTrack(track: 2, notes: [
            ClipNote(relTick: 1, key: 60, duration: 1, velocity: 100),
            ClipNote(relTick: 2, key: 61, duration: 0, velocity: 80),
        ])],
        lanes: [ClipLane(track: 2, cc: 7, points: [
            ClipLanePoint(relTick: 1, value: 10),
            ClipLanePoint(relTick: 2, value: 30),
        ])],
        tempo: [
            ClipTempo(relTick: 1, microsecondsPerQuarterNote: 600_000),
            ClipTempo(relTick: 2, microsecondsPerQuarterNote: 700_000),
        ])
    report.expectEqual(
        expected: downExpected,
        actual: ClipboardCodec.rescale(downInput, sourceTicksPerBeat: 48, destinationTicksPerBeat: 24),
        cppID: "clipmimecheck/ClipMimeTest::rescaleFamilies[down_48_to_24_round_up_last_wins]",
        what: "half-up down-scaled clip with stable last-wins collisions")

    let identityInput = PorydawClip(
        tracks: [ClipTrack(track: 7, notes: [
            ClipNote(relTick: 9, key: 72, duration: 5, velocity: 44),
        ])],
        lanes: [ClipLane(track: 7, cc: 1, points: [
            ClipLanePoint(relTick: 4, value: 1),
            ClipLanePoint(relTick: 4, value: 2),
            ClipLanePoint(relTick: 2, value: 3),
        ])],
        tempo: [
            ClipTempo(relTick: 4, microsecondsPerQuarterNote: 500_000),
            ClipTempo(relTick: 4, microsecondsPerQuarterNote: 600_000),
            ClipTempo(relTick: 2, microsecondsPerQuarterNote: 700_000),
        ])
    report.expectEqual(
        expected: identityInput,
        actual: ClipboardCodec.rescale(identityInput, sourceTicksPerBeat: 24,
                               destinationTicksPerBeat: 24),
        cppID: "clipmimecheck/ClipMimeTest::rescaleFamilies[same_tpb_is_exact_identity]",
        what: "same-TPB clip including duplicate ordering")

    let saturationInput = PorydawClip(
        span: TimeDefaults.noTick,
        tracks: [ClipTrack(track: 0, notes: [
            ClipNote(relTick: .max, key: 127, duration: .max, velocity: 255),
        ])],
        lanes: [ClipLane(track: 0, cc: 1, points: [
            ClipLanePoint(relTick: .max, value: Int(Int32.min)),
        ])],
        tempo: [ClipTempo(relTick: TimeDefaults.noTick,
                          microsecondsPerQuarterNote: .max)])
    var saturationExpected = saturationInput
    saturationExpected.span = TimeDefaults.maxTick
    saturationExpected.tempo[0].relTick = TimeDefaults.maxTick
    report.expectEqual(
        expected: saturationExpected,
        actual: ClipboardCodec.rescale(saturationInput, sourceTicksPerBeat: 1,
                               destinationTicksPerBeat: .max),
        cppID: "clipmimecheck/ClipMimeTest::rescaleFamilies[saturates_without_wrap]",
        what: "saturated clip without wrapping")
}



private func roundTrip(_ clip: PorydawClip, ticksPerBeat: UInt32,
                       cppID: String, report: CheckReport) {
    let decoded = ClipboardCodec.encode(clip, ticksPerBeat: ticksPerBeat)
        .flatMap(ClipboardCodec.decode)
    report.expect(decoded == DecodedPorydawClip(ticksPerBeat: ticksPerBeat, clip: clip),
                  cppID: cppID, message: "codec round-trip preserves payload")
}

private func malformedClipboardPayload(_ kind: String) -> Data {
    if kind == "truncated_json" { return Data("{\"format\": 1".utf8) }
    if kind == "garbage_bytes" { return Data("not json at all".utf8) }
    if kind == "nonfinite_tick" {
        return Data("""
        {"format":1,"ticksPerBeat":24,"span":0,"tracks":[{"track":0,"notes":[{"relTick":NaN,"key":60,"duration":24,"velocity":100}]}],"lanes":[],"tempo":[]}
        """.utf8)
    }
    var payload: [String: Any] = [
        "format": 1,
        "ticksPerBeat": 24,
        "span": 0,
        "wholeLane": false,
        "tracks": [[
            "track": 0,
            "notes": [["relTick": 0, "key": 60, "duration": 24, "velocity": 100]],
        ]],
        "lanes": [],
        "tempo": [],
    ]
    switch kind {
    case "wrong_format":
        payload["format"] = 2
    case "missing_ticks_per_beat":
        payload.removeValue(forKey: "ticksPerBeat")
    case "zero_ticks_per_beat":
        payload["ticksPerBeat"] = 0
    case "missing_tracks":
        payload.removeValue(forKey: "tracks")
    case "wrong_typed_lanes":
        payload["lanes"] = [:]
    case "missing_tempo":
        payload.removeValue(forKey: "tempo")
    case "negative_span":
        payload["span"] = -1
    case "negative_note_tick":
        payload["tracks"] = [[
            "track": 0,
            "notes": [["relTick": -1, "key": 60, "duration": 24, "velocity": 100]],
        ]]
    case "missing_note_velocity":
        payload["tracks"] = [[
            "track": 0,
            "notes": [["relTick": 0, "key": 60, "duration": 24]],
        ]]
    case "lane_point_missing_value":
        payload["lanes"] = [["track": 0, "cc": 1, "points": [[12]]]]
    case "tempo_missing_microseconds":
        payload["tempo"] = [["relTick": 12]]
    default:
        return Data()
    }
    return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
}
