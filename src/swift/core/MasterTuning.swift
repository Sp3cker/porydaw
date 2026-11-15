import Foundation

/// Per-song tuning in 1/64-semitone units, represented by effective MIDI CC24 values.
public enum MasterTuning {
    private static let metadataPrefix: [UInt8] = [0x7D] + Array("Porydaw.MasterTuning".utf8)
    private static let metadataVersion: UInt8 = 1

    /// Returns the quantized nominal A4 frequency; hardware voices need not sound at this exact frequency.
    /// - Parameter units: Signed 1/64-semitone offset from A4 = 440 Hz.
    /// - Returns: The nominal frequency in Hz.
    public static func frequencyHz(units: Int) -> Double {
        440 * pow(2, Double(units) / 768)
    }

    /// Converts a nominal A4 frequency to the nearest representable tuning unit.
    /// - Parameter frequencyHz: A finite, positive frequency in the supported nominal range.
    /// - Returns: The nearest signed 1/64-semitone offset.
    /// - Throws: `MasterTuningError` when the frequency is outside the supported range.
    public static func units(frequencyHz: Double) throws -> Int {
        guard frequencyHz.isFinite, frequencyHz >= self.frequencyHz(units: -64),
            frequencyHz <= self.frequencyHz(units: 63)
        else { throw MasterTuningError.invalidFrequency }
        return Int((768 * log2(frequencyHz / 440)).rounded())
    }

    static func isMetadata(_ event: borrowing MidiEvent) -> Bool {
        guard case .meta(let type, let bytes) = event.payload else { return false }
        return type == 0x7F && bytes.starts(with: metadataPrefix)
    }

    static func metadata(units: Int) -> MidiEvent {
        .meta(type: 0x7F, data: metadataPrefix + [metadataVersion, UInt8(units + 64)])
    }

    static func appliedUnits(in file: borrowing MidiFile) throws -> Int {
        var result: Int?
        for chunk in file.chunks {
            for event in chunk.events where isMetadata(event) {
                guard let bytes = event.blob, bytes.count == metadataPrefix.count + 2,
                    bytes[metadataPrefix.count] == metadataVersion,
                    bytes[metadataPrefix.count + 1] <= 127
                else { throw MasterTuningError.unsupportedMetadata }
                let units = Int(bytes[metadataPrefix.count + 1]) - 64
                guard result == nil || result == units else { throw MasterTuningError.unsupportedMetadata }
                result = units
            }
        }
        return result ?? 0
    }

    /// One chosen initial value for every encountered source channel, including TUNE-only channels.
    static func uniformEvents(in chunk: borrowing MidiChunk, units: Int) -> [MidiEvent] {
        var seen: UInt16 = 0
        var result: [MidiEvent] = []
        for event in chunk.events where event.isChannel {
            let mask = UInt16(1) << event.channel
            guard seen & mask == 0 else { continue }
            if seen == 0 { result.reserveCapacity(16) }
            seen |= mask
            result.append(
                .channel(
                    status: 0xB0 | event.channel, data0: TimeDefaults.ccFineTune, data1: UInt8(64 + units)))
        }
        return result
    }

    /// Cold projection shared by playback and save. Explicit source points are already effective;
    /// only missing initial state is supplied, without changing source or applying another offset.
    static func initialEvents(in chunk: borrowing MidiChunk, units: Int) -> [MidiEvent] {
        guard units != 0 else { return [] }
        var channels = InlineArray<16, UInt8>(repeating: 0)
        var channelCount = 0
        var seen: UInt16 = 0
        var initialized: UInt16 = 0
        var sounding: UInt16 = 0
        for event in chunk.events where event.isChannel {
            let mask = UInt16(1) << event.channel
            if seen & mask == 0 {
                seen |= mask
                channels[channelCount] = event.channel
                channelCount += 1
            }
            if event.isNoteOn { sounding |= mask }
            if event.tick == 0, sounding & mask == 0,
                case .channel(let status, let controller, _) = event.payload,
                status >> 4 == 0xB, controller == TimeDefaults.ccFineTune
            {
                initialized |= mask
            }
        }
        var result: [MidiEvent] = []
        result.reserveCapacity(channelCount)
        for index in 0..<channelCount {
            let channel = channels[index]
            guard initialized & (UInt16(1) << channel) == 0 else { continue }
            result.append(
                .channel(
                    status: 0xB0 | channel, data0: TimeDefaults.ccFineTune, data1: UInt8(64 + units)))
        }
        // Playback merges source channels within each chunk. Seed its original primary first
        // when only secondary defaults are missing: preserve track identity, then let every
        // original tick-zero TUNE override the synthesized baselines in its original order.
        if !result.isEmpty, channelCount > 0, initialized & (UInt16(1) << channels[0]) != 0 {
            result.insert(
                .channel(
                    status: 0xB0 | channels[0], data0: TimeDefaults.ccFineTune, data1: UInt8(64 + units)), at: 0)
        }
        return result
    }
}

/// A rejected tuning request never partially edits the song or its history.
public enum MasterTuningError: Error, LocalizedError, Equatable {
    case invalidFrequency
    case outsideSafeRange(requested: Int, minimum: Int, maximum: Int)
    case unsupportedMetadata

    public var errorDescription: String? {
        switch self {
        case .invalidFrequency:
            "Enter a finite A4 frequency between \(MasterTuning.frequencyHz(units: -64)) and \(MasterTuning.frequencyHz(units: 63)) Hz."
        case .outsideSafeRange(let requested, let minimum, let maximum):
            "Master tuning \(requested) is outside the supported range \(minimum)...\(maximum). Choose a tuning within that range."
        case .unsupportedMetadata:
            "This MIDI contains unsupported or conflicting Porydaw master-tuning metadata. Open it with a compatible version to avoid applying tuning twice."
        }
    }
}

@MainActor
extension SongDocument {
    /// The master offset already applied to source CC24 values, not a second playback control.
    public var masterTuningUnits: Int { (try? MasterTuning.appliedUnits(in: state.file)) ?? 0 }
    /// Lowest supported master setting in signed 1/64-semitone units.
    public var masterTuningMinimumUnits: Int { -64 }
    /// Highest supported master setting in signed 1/64-semitone units.
    public var masterTuningMaximumUnits: Int { 63 }

    /// Replaces every track's TUNE automation with the chosen uniform initial tuning.
    /// - Parameter units: Requested master setting in signed 1/64-semitone units.
    /// - Throws: `MasterTuningError` if metadata is unsupported or units are outside -64...63.
    public func setMasterTuning(units: Int) throws {
        guard history.acceptsDocumentMutation else { return }
        guard (-64...63).contains(units) else {
            throw MasterTuningError.outsideSafeRange(requested: units, minimum: -64, maximum: 63)
        }
        _ = try MasterTuning.appliedUnits(in: state.file)
        var mutation = DocumentMutation(state)
        for chunk in state.file.chunks.indices {
            let initial = MasterTuning.uniformEvents(in: state.file.chunks[chunk], units: units)
            for index in state.file.chunks[chunk].events.indices.reversed() {
                let event = state.file.chunks[chunk].events[index]
                if MasterTuning.isMetadata(event) {
                    mutation.remove(chunk: chunk, offset: index)
                } else if case .channel(let status, let controller, _) = event.payload,
                    status >> 4 == 0xB, controller == TimeDefaults.ccFineTune
                {
                    mutation.remove(chunk: chunk, offset: index)
                }
            }
            for event in initial.reversed() {
                mutation.state.file.chunks[chunk].events.insert(event, at: 0)
                mutation.changes.events.append(.insert(EventInsertion(chunk: chunk, offset: 0, event: event)))
            }
        }
        if mutation.state.file.chunks.isEmpty { mutation.appendChunk(MidiChunk()) }
        mutation.insert(MasterTuning.metadata(units: units), chunk: 0)
        commit(mutation, group: nil, operation: .setMasterTuning)
    }
}
