import Foundation
import PorydawCore
import PorydawCoreCheckNative

func runMidiExportEquivalence(
    projectSongs: [(path: String, cppID: String)], exportRoot: URL?, report: CheckReport
) {
    guard let exportRoot else {
        report.fail(xcmdConverterID, "missing --swiftcore fixture root")
        return
    }

    let xcmdFile = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(events: [
                .meta(type: 0x51, data: hex("07a120"))
            ]),
            MidiChunk(
                events: [
                    .channel(status: 0x90, data0: 60, data1: 64),
                    .channel(status: 0xB0, data0: 0x1E, data1: 0x08),
                    .channel(status: 0xB0, data0: 0x1D, data1: 0x40),
                    .channel(tick: 10, status: 0xB0, data0: 0x1E, data1: 0x09),
                    .channel(tick: 10, status: 0xB0, data0: 0x1D, data1: 0x33),
                    .channel(tick: 20, status: 0xB0, data0: 0x1E, data1: 0x2A),
                    .channel(tick: 20, status: 0xB0, data0: 0x1D, data1: 0x7F),
                    .channel(tick: 24, status: 0x80, data0: 60),
                ], endTick: 24),
        ])
    do {
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        try Data(xcmdFile.encoded()).write(
            to: exportRoot.appendingPathComponent("echo_traffic.mid"), options: .atomic)
    } catch {
        report.fail(xcmdConverterID, "Swift XCMD fixture write failed: \(error)")
    }

    let native = pdc_check_midi_exports()
    for (index, song) in projectSongs.enumerated() {
        let bit = UInt32(1) << UInt32(index)
        let name = URL(fileURLWithPath: song.path).deletingPathExtension().lastPathComponent
        let originalPath = exportRoot.appendingPathComponent("original/\(name).s")
        let encodedPath = exportRoot.appendingPathComponent("encoded/\(name).s")
        let compiled =
            native.projectOpenFailed == 0 && native.missingSongBits & bit == 0
            && native.originalCompileFailureBits & bit == 0
            && native.encodedCompileFailureBits & bit == 0
        let originalAssembly = compiled ? try? Data(contentsOf: originalPath) : nil
        let encodedAssembly = compiled ? try? Data(contentsOf: encodedPath) : nil
        if native.matchingSongBits & bit != 0, let originalAssembly, let encodedAssembly {
            report.expect(
                originalAssembly == encodedAssembly, cppID: song.cppID,
                message: "mid2agb assembly matches Swift encoding")
            if originalAssembly != encodedAssembly {
                report.fail(
                    song.cppID, "assembly differs — " + firstAssemblyDifference(originalAssembly, encodedAssembly))
            }
        } else {
            let difference =
                originalAssembly.flatMap { original in
                    encodedAssembly.map { encoded in firstAssemblyDifference(original, encoded) }
                } ?? "assembly output unavailable"
            report.fail(
                song.cppID,
                "mid2agb assembly mismatch or compile failure " + "(projectOpen=\(native.projectOpenFailed), "
                    + "missing=\(native.missingSongBits & bit), "
                    + "originalCompile=\(native.originalCompileFailureBits & bit), "
                    + "encodedCompile=\(native.encodedCompileFailureBits & bit), " + "firstDifference=\(difference))")
        }
    }

    report.expectEqual(
        expected: Int32(0), actual: native.xcmdCompileFailed, cppID: xcmdConverterID,
        what: "mid2agb compiles Swift XCMD traffic")
    report.expectEqual(
        expected: Int32(1), actual: native.xiecvCount, cppID: xcmdConverterID,
        what: "one xIECV command")
    report.expectEqual(
        expected: Int32(1), actual: native.xieclCount, cppID: xcmdConverterID,
        what: "one xIECL command")
    report.expectEqual(
        expected: Int32(1), actual: native.xiecv64Count, cppID: xcmdConverterID,
        what: "xIECV carries value 64")
    report.expectEqual(
        expected: Int32(1), actual: native.xiecl51Count, cppID: xcmdConverterID,
        what: "xIECL carries value 51")
    report.expectEqual(
        expected: Int32(0), actual: native.unknown127Count, cppID: xcmdConverterID,
        what: "unknown selector emits no echo command")
}

private func firstAssemblyDifference(_ original: Data, _ encoded: Data) -> String {
    let originalLines = original.split(separator: 0x0A, omittingEmptySubsequences: false)
    let encodedLines = encoded.split(separator: 0x0A, omittingEmptySubsequences: false)
    for index in 0..<min(originalLines.count, encodedLines.count)
    where originalLines[index] != encodedLines[index] {
        return "line \(index + 1): '\(String(decoding: originalLines[index], as: UTF8.self))' "
            + "vs '\(String(decoding: encodedLines[index], as: UTF8.self))'"
    }
    return "line count \(originalLines.count) vs \(encodedLines.count)"
}

func compareFixture(
    relativePath: String, cppID: String,
    expectedCanonicalBytes: [UInt8]? = nil,
    assertCanonicalBytes: Bool = true,
    expectedFormatZero: Bool = false,
    expectedDecoded: DecodedCodecExpectation? = nil,
    assertSemanticReparse: Bool = false,
    encodedOutputURL: URL? = nil,
    report: CheckReport
) {
    guard let path = CheckEnvironment.fixturePath(relativePath) else {
        report.fail(cppID, "missing --swiftcore fixture root")
        return
    }
    do {
        let sourceBytes = Array(try Data(contentsOf: URL(fileURLWithPath: path)))
        let observation = compareCodecCase(
            cppID: cppID, bytes: sourceBytes, expectedValid: true,
            expectedCanonicalBytes: expectedCanonicalBytes ?? sourceBytes,
            assertCanonicalBytes: assertCanonicalBytes,
            expectedFormatZero: expectedFormatZero,
            expectedDecoded: expectedDecoded,
            assertSemanticReparse: assertSemanticReparse, report: report)
        if let encodedOutputURL, observation.valid {
            try FileManager.default.createDirectory(
                at: encodedOutputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Data(observation.encoded).write(to: encodedOutputURL, options: .atomic)
        }
    } catch {
        report.fail(cppID, "fixture/export I/O failed for \(path): \(error)")
    }
}
@discardableResult
func compareCodecCase(
    cppID: String, bytes: [UInt8], expectedValid: Bool,
    expectedSwiftError: String? = nil,
    expectedCanonicalBytes: [UInt8]? = nil,
    assertCanonicalBytes: Bool = true,
    expectedFormatZero: Bool = false,
    expectedDecoded: DecodedCodecExpectation? = nil,
    assertSemanticReparse: Bool = false,
    report: CheckReport
) -> CodecObservation {
    let swift = swiftCodec(bytes)
    report.expectEqual(
        expected: expectedValid, actual: swift.valid, cppID: cppID,
        what: "independent Swift validity (error=\(swift.error))")
    if let expectedSwiftError {
        report.expect(
            swift.error.contains(expectedSwiftError), cppID: cppID,
            message: "Swift error expected to contain '\(expectedSwiftError)', actual='\(swift.error)'")
    }

    if expectedValid, let file = swift.decoded {
        if assertCanonicalBytes {
            report.expectEqual(
                expected: expectedCanonicalBytes ?? bytes, actual: swift.encoded, cppID: cppID,
                what: "independent canonical byte vector")
        }
        report.expect(
            swift.encoded.count > 9 && swift.encoded[8] == 0 && swift.encoded[9] == 1,
            cppID: cppID,
            message: "independent encoded format word is 1")
        report.expectEqual(
            expected: expectedFormatZero, actual: file.wasFormat0, cppID: cppID,
            what: "independent format-0 provenance")
        expectDecodedStructure(file, expected: expectedDecoded, cppID: cppID, report: report)
        if assertSemanticReparse {
            let reparsed = swiftCodec(swift.encoded)
            report.expect(
                reparsed.valid, cppID: cppID,
                message: "independent semantic reparse validity (error=\(reparsed.error))")
            if let reread = reparsed.decoded {
                report.expectEqual(
                    expected: file.division, actual: reread.division, cppID: cppID,
                    what: "independent semantic reparse division")
                report.expectEqual(
                    expected: file.chunks, actual: reread.chunks, cppID: cppID,
                    what: "independent semantic reparse chunks")
            }
        }
    }
    return swift
}

private func expectDecodedStructure(
    _ file: MidiFile, expected: DecodedCodecExpectation?,
    cppID: String, report: CheckReport
) {
    for (chunkIndex, chunk) in file.chunks.enumerated() {
        if chunk.events.count > 1 {
            for eventIndex in 1..<chunk.events.count {
                report.expect(
                    chunk.events[eventIndex - 1].tick <= chunk.events[eventIndex].tick,
                    cppID: cppID,
                    message: "independent decoded order chunk=\(chunkIndex) event=\(eventIndex)")
            }
        }
        if let last = chunk.events.last {
            report.expect(
                last.tick <= chunk.endTick, cppID: cppID,
                message: "independent end tick chunk=\(chunkIndex) last=\(last.tick) end=\(chunk.endTick)")
        }
    }
    guard let expected else { return }
    report.expectEqual(
        expected: expected.division, actual: file.division, cppID: cppID,
        what: "independent decoded division")
    report.expectEqual(
        expected: expected.wasFormatZero, actual: file.wasFormat0, cppID: cppID,
        what: "independent decoded format-0 provenance")
    report.expectEqual(
        expected: expected.endTicks.count, actual: file.chunks.count, cppID: cppID,
        what: "independent decoded chunk count")
    for index in 0..<min(expected.endTicks.count, file.chunks.count) {
        report.expectEqual(
            expected: expected.endTicks[index], actual: file.chunks[index].endTick, cppID: cppID,
            what: "independent decoded chunk=\(index) end tick")
        report.expectEqual(
            expected: expected.eventCounts[index], actual: file.chunks[index].events.count,
            cppID: cppID, what: "independent decoded chunk=\(index) event count")
    }
    for item in expected.events {
        guard item.chunk < file.chunks.count,
            item.index < file.chunks[item.chunk].events.count
        else {
            report.fail(cppID, "independent decoded event missing chunk=\(item.chunk) index=\(item.index)")
            continue
        }
        report.expectEqual(
            expected: item.event, actual: file.chunks[item.chunk].events[item.index],
            cppID: cppID,
            what: "independent decoded event chunk=\(item.chunk) index=\(item.index)")
    }
}

// The automation-burst fixture's full decoded contract: conductor metas, the
// program change, 64 groups of (CC, CC, pitch bend) per channel, and the
// trailing note on/off pair. Mirrors the C++ per-group field formulas.
func automationBurstExpectations() -> [DecodedEventExpectation] {
    var events: [DecodedEventExpectation] = [
        DecodedEventExpectation(
            chunk: 0, index: 0, event: .meta(type: 0x51, data: hex("07a120"))),
        DecodedEventExpectation(
            chunk: 0, index: 1, event: .meta(type: 0x58, data: hex("04021808"))),
    ]
    for channel in 0..<2 {
        let chunk = channel + 1
        let ccStatus = UInt8(0xB0 + channel)
        let bendStatus = UInt8(0xE0 + channel)
        events.append(
            DecodedEventExpectation(
                chunk: chunk, index: 0,
                event: .channel(
                    status: UInt8(0xC0 + channel),
                    data0: channel == 0 ? 5 : 40)))
        for group in 0..<64 {
            let base = 1 + group * 3
            let tick = Tick(4 * group)
            let firstController = UInt8(channel == 0 ? 7 : 1)
            let firstValue = UInt8(channel == 0 ? 20 + group : (3 * group) & 0x7F)
            let secondController = UInt8(channel == 0 ? 11 : 10)
            let secondValue = UInt8(channel == 0 ? 0x7F - group : 40 + group)
            let bendLsb = UInt8(channel == 0 ? group : (5 * group) & 0x7F)
            let bendMsb = UInt8(channel == 0 ? (2 * group) & 0x7F : (7 * group) & 0x7F)
            events.append(
                DecodedEventExpectation(
                    chunk: chunk, index: base,
                    event: .channel(
                        tick: tick, status: ccStatus,
                        data0: firstController, data1: firstValue)))
            events.append(
                DecodedEventExpectation(
                    chunk: chunk, index: base + 1,
                    event: .channel(
                        tick: tick, status: ccStatus,
                        data0: secondController, data1: secondValue)))
            events.append(
                DecodedEventExpectation(
                    chunk: chunk, index: base + 2,
                    event: .channel(
                        tick: tick, status: bendStatus,
                        data0: bendLsb, data1: bendMsb)))
        }
        let note = UInt8(channel == 0 ? 0x3C : 0x43)
        events.append(
            DecodedEventExpectation(
                chunk: chunk, index: 193,
                event: .channel(
                    tick: 256, status: UInt8(0x90 + channel),
                    data0: note, data1: 0x50)))
        events.append(
            DecodedEventExpectation(
                chunk: chunk, index: 194,
                event: .channel(tick: 352, status: UInt8(0x80 + channel), data0: note)))
    }
    return events
}

private func swiftCodec(_ bytes: [UInt8]) -> CodecObservation {
    do {
        let file = try MidiFile.decode(bytes)
        return CodecObservation(
            valid: true, encoded: try file.encoded(),
            wasFormatZero: file.wasFormat0, decoded: file)
    } catch {
        return CodecObservation(error: String(describing: error))
    }
}

func midiBytes(format: UInt16, division: UInt16, tracks: [[UInt8]]) -> [UInt8] {
    var bytes: [UInt8] = [0x4D, 0x54, 0x68, 0x64]
    appendUInt32(6, to: &bytes)
    appendUInt16(format, to: &bytes)
    appendUInt16(UInt16(tracks.count), to: &bytes)
    appendUInt16(division, to: &bytes)
    for track in tracks {
        bytes += [0x4D, 0x54, 0x72, 0x6B]
        appendUInt32(UInt32(track.count), to: &bytes)
        bytes += track
    }
    return bytes
}

func formatZeroBytes(_ track: [UInt8]) -> [UInt8] {
    midiBytes(format: 0, division: 24, tracks: [track])
}

private func appendUInt16(_ value: UInt16, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
}

private func appendUInt32(_ value: UInt32, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
}

func hex(_ text: String) -> [UInt8] {
    precondition(text.count.isMultiple(of: 2))
    var bytes: [UInt8] = []
    bytes.reserveCapacity(text.count / 2)
    var index = text.startIndex
    while index < text.endIndex {
        let next = text.index(index, offsetBy: 2)
        bytes.append(UInt8(text[index..<next], radix: 16)!)
        index = next
    }
    return bytes
}
