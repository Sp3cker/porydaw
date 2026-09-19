import Foundation
import PorydawCore

@_cdecl("pdc_codec_roundtrip")
public func pdcCodecRoundTrip(
    _ input: UnsafePointer<UInt8>?, _ inputCount: Int,
    _ output: UnsafeMutablePointer<UInt8>?, _ outputCapacity: Int,
    _ wasFormatZero: UnsafeMutablePointer<UInt8>?,
    _ summary: UnsafeMutablePointer<CChar>?, _ summaryCapacity: Int,
    _ summarySize: UnsafeMutablePointer<Int>?,
    _ errorOut: UnsafeMutablePointer<CChar>?, _ errorCapacity: Int,
    _ errorSize: UnsafeMutablePointer<Int>?
) -> Int64 {
    do {
        let bytes = inputCount == 0 ? [] : Array(UnsafeBufferPointer(start: input, count: inputCount))
        let file = try MidiFile.decode(bytes)
        let encoded = try file.encoded()
        let summaryBytes = Array(codecSummary(file).utf8)
        wasFormatZero?.pointee = file.wasFormat0 ? 1 : 0
        summarySize?.pointee = summaryBytes.count
        errorSize?.pointee = 0
        copy(encoded, to: output, capacity: outputCapacity)
        copyCBytes(summaryBytes, to: summary, capacity: summaryCapacity)
        return Int64(encoded.count)
    } catch {
        let bytes = Array(String(describing: error).utf8)
        wasFormatZero?.pointee = 0
        summarySize?.pointee = 0
        errorSize?.pointee = bytes.count
        copyCBytes(bytes, to: errorOut, capacity: errorCapacity)
        return -1
    }
}

@_cdecl("pdc_blank_song")
public func pdcBlankSong(_ output: UnsafeMutablePointer<UInt8>?, _ outputCapacity: Int) -> Int64 {
    do {
        let bytes = try MidiFile.blankSong().encoded()
        copy(bytes, to: output, capacity: outputCapacity)
        return Int64(bytes.count)
    } catch {
        return -1
    }
}

@_cdecl("pdc_semantic_value")
public func pdcSemanticValue(_ operation: UInt32, _ a: Int64, _ b: Int64,
                             _ c: Int64, _ d: Int64) -> Int64 {
    switch operation {
    case 1: return Int64(m4aClassifyCC(UInt8(truncatingIfNeeded: a)).eventClass.rawValue)
    case 2: return Int64(m4aClassifyCC(UInt8(truncatingIfNeeded: a)).lane.rawValue)
    case 3: return Int64(m4aExportSupport(UInt8(truncatingIfNeeded: a)).rawValue)
    case 4: return Int64(m4aLane(forXCMDSelector: UInt8(truncatingIfNeeded: a)).rawValue)
    case 5: return Int64(mid2agbEffectiveVelocity(Int(a)))
    case 6:
        return Int64(mid2agbEffectiveDuration(a, division: UInt32(truncatingIfNeeded: b),
                                              extendedClocks: c != 0, exactGate: d != 0))
    case 10: return velocityMap(a).isPSG ? 1 : 0
    case 11: return velocityMap(a).compatible(with: velocityMap(b)) ? 1 : 0
    case 12: return Int64(velocityMap(a).levelCount)
    case 13:
        let range = velocityMap(a).levelRange(Int(b))
        return Int64(range.first) << 8 | Int64(range.last)
    case 14: return Int64(velocityMap(a).level(of: Int(b)) ?? -1)
    case 15: return Int64(velocityMap(a).representative(Int(b)))
    case 16: return Int64(velocityMap(a).canonicalize(Int(b)))
    case 17:
        return Int64(velocityMap(a).moveLevels(from: UInt8(truncatingIfNeeded: b), by: Int(c)))
    case 20:
        return TimeDefaults.controllerDefault(for: UInt8(truncatingIfNeeded: a)).map(Int64.init) ?? -1
    case 21: return Int64(TimeDefaults.laneDomain(for: UInt8(truncatingIfNeeded: a)).minimum)
    case 22: return Int64(TimeDefaults.laneDomain(for: UInt8(truncatingIfNeeded: a)).maximum)
    case 23: return TimeDefaults.laneDomain(for: UInt8(truncatingIfNeeded: a)).centered ? 1 : 0
    case 24: return TimeDefaults.laneDomain(for: UInt8(truncatingIfNeeded: a)).zoomable ? 1 : 0
    case 25: return TimeDefaults.hasEngineDefaultNode(for: UInt8(truncatingIfNeeded: a)) ? 1 : 0
    case 26: return Int64(TimeDefaults.microsecondsPerQuarterNote(forBPM: Int(a)))
    case 27:
        let value = TimeDefaults.tempoBPM(forMicrosecondsPerQuarterNote: UInt32(truncatingIfNeeded: a))
        return Int64(bitPattern: value.bitPattern)
    case 28:
        return Int64(TimeDefaults.clampTempoMicrosecondsPerQuarterNote(UInt32(truncatingIfNeeded: a)))
    case 29:
        return Int64(TimeDefaults.shiftTickClamped(UInt32(truncatingIfNeeded: a), by: b))
    case 30:
        let value = Double(bitPattern: UInt64(bitPattern: a))
        return Int64(TimeDefaults.tick(from: value))
    case 31: return Int64(TrackLimits.hardwareCapacity)
    case 33: return NoteID(UInt64(bitPattern: a)).isAssigned ? 1 : 0
    case 34:
        let plain = MidiEvent.channel(tick: 12, status: 0x90, data0: 60, data1: 100)
        let stamped = MidiEvent.channel(tick: 12, status: 0x90, data0: 60, data1: 100,
                                        noteID: NoteID(42))
        do {
            let plainBytes = try MidiFile(division: 24,
                                          chunks: [MidiChunk(events: [plain], endTick: 24)]).encoded()
            let stampedBytes = try MidiFile(
                division: 24, chunks: [MidiChunk(events: [stamped], endTick: 24)]
            ).encoded()
            return plain == stamped && plainBytes == stampedBytes ? 1 : 0
        } catch {
            return 0
        }
    default: return Int64.min
    }
}

@_cdecl("pdc_semantic_text")
public func pdcSemanticText(_ operation: UInt32, _ a: Int64, _ b: Int64,
                            _ output: UnsafeMutablePointer<CChar>?, _ outputCapacity: Int) -> Int64 {
    let text: String
    switch operation {
    case 1: text = m4aClassifyCC(UInt8(truncatingIfNeeded: a)).name
    case 2: text = m4aClassifyCC(UInt8(truncatingIfNeeded: a)).display
    case 3: text = m4aLaneName(M4aLane(rawValue: Int(a)) ?? .modulation)
    case 4:
        text = m4aFormatCCValue(controller: UInt8(truncatingIfNeeded: a),
                                value: UInt8(truncatingIfNeeded: b))
    case 5:
        text = m4aAdvancedCCLabel(controller: UInt8(truncatingIfNeeded: a),
                                  value: UInt8(truncatingIfNeeded: b))
    case 6: text = m4aFormatBend(Int(a))
    case 7: text = m4aVoiceTypeName(UInt8(truncatingIfNeeded: a))
    case 8: text = midiKeyName(Int(a))
    case 9: text = midiTimeSignatureLabel(numerator: Int(a), denominatorPowerOfTwo: Int(b))
    case 10: text = velocityMap(a).voiceName
    default: text = ""
    }
    let bytes = Array(text.utf8)
    copyCBytes(bytes, to: output, capacity: outputCapacity)
    return Int64(bytes.count)
}

private func velocityMap(_ rawValue: Int64) -> VelocityMap {
    VelocityMap(voiceKind: VoiceKind(rawValue: Int(rawValue)) ?? .invalid)
}

private func codecSummary(_ file: MidiFile) -> String {
    var parts = [
        "division=\(file.division)",
        "chunks=\(file.chunks.count)",
        "was0=\(file.wasFormat0 ? 1 : 0)",
    ]
    for (index, chunk) in file.chunks.enumerated() {
        parts.append("chunk\(index)=\(chunk.endTick),\(chunk.events.count)")
    }
    let mapping = file.engineTracks()
    parts.append("map=\(mapping.usedTrackCount),\(mapping.droppedTracks)")
    for index in 0..<mapping.usedTrackCount {
        let track = mapping.tracks[index]
        parts.append("slot\(index)=\(track.midiChunk ?? -1),\(track.channel)")
    }
    return parts.joined(separator: ";")
}

private func copy(_ bytes: [UInt8], to output: UnsafeMutablePointer<UInt8>?, capacity: Int) {
    guard let output, capacity > 0 else { return }
    for index in 0..<min(bytes.count, capacity) { output[index] = bytes[index] }
}

private func copyCBytes(_ bytes: [UInt8], to output: UnsafeMutablePointer<CChar>?, capacity: Int) {
    guard let output, capacity > 0 else { return }
    for index in 0..<min(bytes.count, capacity) { output[index] = CChar(bitPattern: bytes[index]) }
}
