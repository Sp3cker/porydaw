import Foundation

public enum ImportSupport: Equatable, Sendable {
    case supported
    case notExported
    case needsReview
}

public struct ImportTrackInfo: Equatable, Sendable {
    public var chunk: Int
    public var name: String
    public var noteCount: Int
    public var programs: [UInt8]
    public var notesBeforeProgram: Bool
}

public struct ImportCCUsage: Equatable, Sendable {
    public var controller: UInt8
    public var count: Int
    public var label: String
    public var support: ImportSupport
}

public struct ImportXcmdUsage: Equatable, Sendable {
    public var label: String
    public var count: Int
    public var support: ImportSupport
}

public struct ImportAnalysis: Equatable, Sendable {
    public var division: UInt16
    public var chunkCount: Int
    public var mappedTracks: Int
    public var droppedTracks: Int
    public var silentTracks: Int
    public var peakConcurrentNotes: Int
    public var sampleNoteLimit: Int
    public var tracks: [ImportTrackInfo]
    public var controllers: [ImportCCUsage]
    public var xcmd: [ImportXcmdUsage]
    public var warnings: [String]
}

public enum MidiImportError: Error, Equatable, CustomStringConvertible {
    case invalidDivision
    case tickOverflow(newDivision: UInt16)

    public var description: String {
        switch self {
        case .invalidDivision: return "MIDI division must be nonzero"
        case let .tickOverflow(division):
            return "Tick rescale to division \(division) exceeds 32-bit tick range"
        }
    }
}

public enum MidiImport {
    public static func analyze(_ file: MidiFile, trackBudget: Int = TrackLimits.hardwareCapacity,
                               playerName: String = "") -> ImportAnalysis {
        let map = file.engineTracks()
        var tracks: [ImportTrackInfo] = []
        tracks.reserveCapacity(map.usedTrackCount)
        var counts: [UInt8: Int] = [:]
        var xcmdEvents: [Xcmd.Event] = []
        var edges: [NoteEdge] = []

        for engineTrack in 0..<map.usedTrackCount {
            guard let chunkIndex = map.tracks[engineTrack].midiChunk else { continue }
            let chunk = file.chunks[chunkIndex]
            var info = ImportTrackInfo(chunk: chunkIndex, name: "", noteCount: 0,
                                       programs: [], notesBeforeProgram: false)
            var nameScanner = TrackNameScan()
            for event in chunk.events {
                let isTrackName = nameScanner.consume(event)
                if info.name.isEmpty, isTrackName, case let .meta(_, data) = event.payload {
                    info.name = String(bytes: data, encoding: .isoLatin1)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
                guard case let .channel(status, data0, data1) = event.payload else { continue }
                switch status >> 4 {
                case 0x9 where data1 != 0:
                    info.noteCount += 1
                    if info.programs.isEmpty { info.notesBeforeProgram = true }
                    edges.append(NoteEdge(tick: event.tick, on: true,
                                          track: engineTrack, key: data0))
                case 0x8, 0x9:
                    edges.append(NoteEdge(tick: event.tick, on: false,
                                          track: engineTrack, key: data0))
                case 0xB:
                    if data0 == Xcmd.selectorController || data0 == Xcmd.payloadController ||
                        data0 == Xcmd.alternatePayloadController {
                        xcmdEvents.append(Xcmd.Event(index: UInt64(xcmdEvents.count),
                            tick: event.tick, stream: UInt8(engineTrack), controller: data0,
                            value: data1, channel: status & 0x0F))
                    } else { counts[data0, default: 0] += 1 }
                case 0xC:
                    if !info.programs.contains(data0) { info.programs.append(data0) }
                default: break
                }
            }
            tracks.append(info)
        }

        edges = edges.enumerated().sorted {
            if $0.element.tick != $1.element.tick { return $0.element.tick < $1.element.tick }
            if $0.element.on != $1.element.on { return !$0.element.on }
            return $0.offset < $1.offset
        }.map(\.element)
        var sounding: [Int: Int] = [:]
        var active = 0
        var peak = 0
        for edge in edges {
            let key = edge.track << 8 | Int(edge.key)
            if edge.on {
                sounding[key, default: 0] += 1
                active += 1
                peak = max(peak, active)
            } else if (sounding[key] ?? 0) > 0 {
                sounding[key]! -= 1
                active -= 1
            }
        }

        var controllers: [ImportCCUsage] = []
        for controller in counts.keys.sorted() {
            let info = m4aClassifyCC(controller)
            controllers.append(ImportCCUsage(
                controller: controller, count: counts[controller]!,
                label: "\(info.name) — \(info.display)",
                support: m4aExportSupport(controller) == .supported ? .supported : .notExported))
        }

        let assessment = Xcmd.assess(xcmdEvents)
        var xcmd: [ImportXcmdUsage] = []
        if assessment.echoVolumePoints > 0 {
            xcmd.append(ImportXcmdUsage(label: "Echo volume",
                                       count: assessment.echoVolumePoints, support: .supported))
        }
        if assessment.echoLengthPoints > 0 {
            xcmd.append(ImportXcmdUsage(label: "Echo length",
                                       count: assessment.echoLengthPoints, support: .supported))
        }
        struct Group { var count = 0; var support = ImportSupport.supported }
        var unknown: [UInt8: Group] = [:]
        var dangling: [UInt8: Group] = [:]
        var stray = Group()
        for block in assessment.blocks {
            let support = importSupport(block.exportClass)
            switch block.kind {
            case .completeEchoPoints:
                break
            case .unknownSelectorEpoch:
                var group = unknown[block.selector] ?? Group()
                group.count += block.payloadCount
                group.support = support
                unknown[block.selector] = group
            case .danglingSelector:
                var group = dangling[block.selector] ?? Group()
                group.count += 1
                group.support = support
                dangling[block.selector] = group
            case .strayPayloads:
                stray.count += block.payloadCount
                stray.support = support
            }
        }
        for selector in unknown.keys.sorted() {
            let group = unknown[selector]!
            xcmd.append(ImportXcmdUsage(
                label: String(format: "Unknown XCMD selector 0x%02x", selector),
                count: group.count, support: group.support))
        }
        for selector in dangling.keys.sorted() {
            let group = dangling[selector]!
            xcmd.append(ImportXcmdUsage(label: Xcmd.descriptor(forSelector: selector)?.displayName ??
                "XCMD selector", count: group.count, support: group.support))
        }
        if stray.count > 0 {
            xcmd.append(ImportXcmdUsage(label: "XCMD payload without a selector",
                                       count: stray.count, support: stray.support))
        }

        let silent = trackBudget >= 0 && trackBudget < TrackLimits.hardwareCapacity ?
            max(0, map.usedTrackCount - trackBudget) : 0
        var warnings: [String] = []
        if map.droppedTracks > 0 {
            warnings.append("Porydaw will not import \(importTrackCountPhrase(map.droppedTracks)). The MIDI file contains more than 16 tracks.")
        }
        if silent > 0 {
            let player = playerName.isEmpty ? "the selected audio player" :
                importPlayerRoleName(playerName, includeSymbol: true)
            warnings.append("The game will not play \(importTrackCountPhrase(silent)) for \(player). This player can play \(importTrackCountPhrase(trackBudget)).")
        }
        if file.division % 24 != 0 {
            warnings.append("Porydaw will adjust the note timing. The source timing value is \(file.division).")
        }
        if peak > 5 { warnings.append(concurrencyNotice(peakNotes: peak, sampleNoteLimit: 5)) }
        if tracks.contains(where: { $0.noteCount > 0 && $0.notesBeforeProgram }) {
            warnings.append(instrumentFallbackNotice)
        }
        return ImportAnalysis(division: file.division, chunkCount: file.chunks.count,
            mappedTracks: map.usedTrackCount, droppedTracks: map.droppedTracks,
            silentTracks: silent, peakConcurrentNotes: peak, sampleNoteLimit: 5,
            tracks: tracks, controllers: controllers, xcmd: xcmd, warnings: warnings)
    }

    public static func rescaleDivision(_ file: inout MidiFile, to newDivision: UInt16) throws {
        guard newDivision != 0, file.division != 0 else { throw MidiImportError.invalidDivision }
        guard newDivision != file.division else { return }
        let old = UInt64(file.division)
        var maximum: UInt64 = 0
        for chunk in file.chunks {
            maximum = max(maximum, UInt64(chunk.endTick))
            for event in chunk.events { maximum = max(maximum, UInt64(event.tick)) }
        }
        guard maximum * UInt64(newDivision) / old <= UInt64(TimeDefaults.maxTick) else {
            throw MidiImportError.tickOverflow(newDivision: newDivision)
        }
        for chunk in file.chunks.indices {
            for event in file.chunks[chunk].events.indices {
                file.chunks[chunk].events[event].tick = Tick(
                    UInt64(file.chunks[chunk].events[event].tick) * UInt64(newDivision) / old)
            }
            file.chunks[chunk].endTick = Tick(
                UInt64(file.chunks[chunk].endTick) * UInt64(newDivision) / old)
        }
        file.division = newDivision
    }

    @discardableResult
    public static func removeRedundantSetters(_ file: inout MidiFile) -> Int {
        var removed = 0
        for chunk in file.chunks.indices {
            let events = file.chunks[chunk].events
            var drop = Array(repeating: false, count: events.count)
            var lastForSlot: [Int: Int] = [:]
            var runTick: Tick?
            for (index, event) in events.enumerated() {
                if runTick != event.tick { lastForSlot.removeAll(keepingCapacity: true); runTick = event.tick }
                guard let slot = setterSlot(event) else { continue }
                if let previous = lastForSlot[slot] { drop[previous] = true; removed += 1 }
                lastForSlot[slot] = index
            }
            file.chunks[chunk].events = events.enumerated().compactMap {
                drop[$0.offset] ? nil : $0.element
            }
        }
        return removed
    }

    public static func playerRoleName(_ symbol: String, includeSymbol: Bool) -> String {
        importPlayerRoleName(symbol, includeSymbol: includeSymbol)
    }

    public static func trackCountPhrase(_ count: Int) -> String { importTrackCountPhrase(count) }
}

private struct NoteEdge { let tick: Tick; let on: Bool; let track: Int; let key: UInt8 }

private func importSupport(_ value: Xcmd.ExportClass) -> ImportSupport {
    switch value {
    case .supported: return .supported
    case .notExported: return .notExported
    case .needsReview: return .needsReview
    }
}
private func importPlayerRoleName(_ symbol: String, includeSymbol: Bool) -> String {
    let role: String
    if symbol == "MUSIC_PLAYER_BGM" { role = "Background music" }
    else if symbol.hasPrefix("MUSIC_PLAYER_SE") {
        let number = String(symbol.dropFirst("MUSIC_PLAYER_SE".count))
        role = number.isEmpty ? "Sound effect" : "Sound effect \(number)"
    } else { return symbol }
    return includeSymbol ? "\(role) (\(symbol))" : role
}
private func importTrackCountPhrase(_ count: Int) -> String {
    count == 1 ? "1 track" : "\(count) tracks"
}
private func concurrencyNotice(peakNotes: Int, sampleNoteLimit: Int) -> String {
    "\(peakNotes) notes play at the same time in one part of the song. The Game Boy Advance can mix \(sampleNoteLimit) sample notes at the same time. Square, wave, and noise sounds do not use this limit. The game can stop some sample notes."
}
private let instrumentFallbackNotice =
    "Some notes start before the MIDI data selects an instrument. These notes use instrument 0."

private func setterSlot(_ event: MidiEvent) -> Int? {
    if case let .meta(type, _) = event.payload {
        return type == 0x51 || type == 0x58 ? 0x10000 | Int(type) : nil
    }
    guard case let .channel(status, data0, _) = event.payload else { return nil }
    let type = status >> 4
    let channel = Int(status & 0x0F)
    switch type {
    case 0xB:
        if (0x0C...0x11).contains(data0) || data0 == Xcmd.selectorController ||
            data0 == Xcmd.payloadController || data0 == Xcmd.alternatePayloadController {
            return nil
        }
        return Int(type) << 12 | channel << 7 | Int(data0)
    case 0xA: return Int(type) << 12 | channel << 7 | Int(data0)
    case 0xC, 0xD, 0xE: return Int(type) << 12 | channel << 7
    default: return nil
    }
}
