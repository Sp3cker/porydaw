import PorydawCore

/// Session-scoped, document-only projections. Bank and presentation state are
/// deliberately absent: their changes need not advance the document revision.
@MainActor
public final class DocumentProjectionCache {
    private unowned let session: DocumentSession
    private var trackNotes: [Int: [Note]] = [:]
    private var noteIndices: [Int: [NoteID: Int]] = [:]
    private var lanes: [Int: [Lane: [LanePoint]]] = [:]
    private var cachedTimeAxis: TimeAxis?

    init(session: DocumentSession) {
        self.session = session
    }

    public func notes(in track: Int) -> [Note] {
        if let notes = trackNotes[track] { return notes }
        let notes = session.document.notes(in: track)
        trackNotes[track] = notes
        return notes
    }

    public func note(_ id: NoteID, in track: Int) -> Note? {
        let notes = notes(in: track)
        if noteIndices[track] == nil {
            var indices: [NoteID: Int] = [:]
            indices.reserveCapacity(notes.count)
            for (index, note) in notes.enumerated() where indices[note.id] == nil {
                indices[note.id] = index
            }
            noteIndices[track] = indices
        }
        guard let index = noteIndices[track]?[id] else { return nil }
        return notes[index]
    }

    public func lanePoints(track: Int, lane: Lane) -> [LanePoint] {
        if let points = lanes[track]?[lane] { return points }
        let points = session.document.lanePoints(track: track, lane: lane)
        lanes[track, default: [:]][lane] = points
        return points
    }

    public var timeAxis: TimeAxis {
        if let axis = cachedTimeAxis { return axis }
        let timeline = session.timeline
        let axis = TimeAxis(
            map: TimeMap(
                ticksPerBeat: UInt32(max(1, session.document.ticksPerBeat)),
                lengthTicks: timeline.lengthTicks,
                loopStartTick: timeline.loopStartTick,
                loopEndTick: timeline.loopEndTick,
                timeSigs: session.document.timeSignatures.map {
                    TimeSigPoint(
                        tick: $0.tick, numerator: $0.numerator,
                        denomPow2: $0.denominatorPower)
                }))
        cachedTimeAxis = axis
        return axis
    }

    /// The session invalidates offsets before any observer reads the new document.
    /// Untouched chunks retain their projections, independently of revision.
    func documentDidChange(_ change: DocumentChange) {
        let effects = change.editEffects
        if effects.flags.contains(.structure) {
            trackNotes.removeAll(keepingCapacity: true)
            noteIndices.removeAll(keepingCapacity: true)
            lanes.removeAll(keepingCapacity: true)
        } else if effects.affectsAnyChunk {
            let mapping = session.document.engineTracks
            for track in 0..<mapping.usedTrackCount {
                guard let chunk = mapping.tracks[track].midiChunk,
                    effects.affects(chunk: chunk)
                else { continue }
                // Both notes and lane points carry raw-event offsets.
                trackNotes.removeValue(forKey: track)
                noteIndices.removeValue(forKey: track)
                lanes.removeValue(forKey: track)
            }
        }
        if !effects.flags.intersection([.timeDomain, .structure]).isEmpty {
            cachedTimeAxis = nil
        }
    }
}
