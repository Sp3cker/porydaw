import PorydawCore

struct BenchWorkload {
    var notesPerTrack = 1
    var trackCount = 1
    var selectedNodes = 1
    var visibleNodes = 0
    var duplicateOccupants = 2
    var bulkPoints = 32
    var historyDepth = 0
    var editCount = 100

    mutating func consume(option: String, value: String) throws -> Bool {
        let bounds: ClosedRange<Int>
        switch option {
        case "--tracks": bounds = 1...16
        case "--visible-nodes": bounds = 0...100
        case "--history-depth": bounds = 0...100_000
        case "--notes", "--selected-nodes", "--duplicate-occupants", "--bulk-points", "--edits":
            bounds = 1...100_000
        default: return false
        }
        guard let count = Int(value), bounds.contains(count) else {
            throw BenchFailure(description: "\(option) requires an integer in \(bounds)")
        }
        switch option {
        case "--notes": notesPerTrack = count
        case "--tracks": trackCount = count
        case "--selected-nodes": selectedNodes = count
        case "--visible-nodes": visibleNodes = count
        case "--duplicate-occupants": duplicateOccupants = count
        case "--bulk-points": bulkPoints = count
        case "--history-depth": historyDepth = count
        case "--edits": editCount = count
        default: preconditionFailure("Unrecognized workload dimension")
        }
        return true
    }

    func midiChunks(conductor: [MidiEvent], end: Tick) -> [MidiChunk] {
        var chunks = [MidiChunk(events: conductor, endTick: end)]
        chunks.reserveCapacity(trackCount + 1)
        for track in 0..<trackCount {
            let channel = UInt8(track)
            var events: [MidiEvent] = []
            events.reserveCapacity(notesPerTrack * 2)
            for index in 0..<notesPerTrack {
                let start = Tick(Int64(index) * Int64(end) / Int64(notesPerTrack))
                let finish: Tick
                if notesPerTrack == 1 {
                    finish = end
                } else {
                    let next = Tick(Int64(index + 1) * Int64(end) / Int64(notesPerTrack))
                    finish = min(end, start + max(1, (next - start) / 2))
                }
                let pitch = UInt8(60 + index % 12)
                events.append(.channel(tick: start, status: 0x90 | channel, data0: pitch, data1: 100))
                events.append(.channel(tick: finish, status: 0x80 | channel, data0: pitch))
            }
            events.sort { $0.tick < $1.tick }
            chunks.append(MidiChunk(events: events, endTick: end))
        }
        return chunks
    }
}
