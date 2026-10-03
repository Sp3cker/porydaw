import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func timeDocument(division: UInt16 = 24, trackBudget: Int = 3) -> SongDocument {
    SongDocument(file: MidiFile(division: division, chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 240),
        MidiChunk(events: [.channel(status: 0xC1, data0: 1)], endTick: 240),
    ]), trackBudget: trackBudget)
}

@MainActor
func coreTimeBytes(_ document: SongDocument) -> [UInt8] {
    do { return try document.captureSave().bytes }
    catch { return [] }
}

func coreTimeXcmdTraffic(_ chunk: MidiChunk) -> [Xcmd.Event] {
    chunk.events.enumerated().compactMap { index, event in
        guard case let .channel(status, controller, value) = event.payload,
              status >> 4 == 0xB else { return nil }
        return Xcmd.Event(index: UInt64(index), tick: event.tick, stream: 0,
                          controller: controller, value: value, channel: status & 0x0F)
    }
}


func noteShape(_ note: Note) -> String {
    "\(note.tick):\(note.pitch):\(note.duration)"
}

func coreTimePointShape(_ point: LanePoint) -> String {
    "\(point.tick):\(point.value)"
}

func hasChannel(_ events: [MidiEvent], tick: Tick, type: UInt8, key: UInt8) -> Bool {
    events.contains { event in
        guard event.tick == tick,
              case let .channel(status, data0, _) = event.payload else { return false }
        return status >> 4 == type && data0 == key
    }
}


@MainActor
func timeRangeDocument() throws -> SongDocument {
    SongDocument(file: try MidiFile.decode(MidiFile(division: 24, chunks: [
        MidiChunk(events: [], endTick: 200),
        MidiChunk(events: [.channel(status: 0xC0, data0: 1)], endTick: 200),
        MidiChunk(events: [.channel(status: 0xC1, data0: 2)], endTick: 200),
    ]).encoded()))
}

@MainActor
func coreTimeNoteEndsBeforeOnsAt(_ document: SongDocument, track: Int,
                                         tick: Tick) -> Bool {
    guard let chunk = document.engineTracks.tracks[track].midiChunk else { return true }
    var sawNoteOn = false
    for event in document.rawChunks[chunk].events where event.tick == tick && event.isChannel {
        if event.isNoteOn {
            sawNoteOn = true
        } else if event.isNoteEnd && sawNoteOn {
            return false
        }
    }
    return true
}
