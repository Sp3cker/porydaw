import PorydawCore

/// Session-scoped, document-only projections. Bank and presentation state are
/// deliberately absent: their changes need not advance the document revision.
@MainActor
final class DocumentProjectionCache {
    private struct LaneKey: Hashable {
        let track: Int
        let lane: Lane
    }

    private unowned let session: DocumentSession
    private var revision: UInt64?
    private var trackNotes: [Int: [Note]] = [:]
    private var noteIndices: [Int: [NoteID: Int]] = [:]
    private var lanes: [LaneKey: [LanePoint]] = [:]
    private var cachedTimeAxis: TimeAxis?

    init(session: DocumentSession) {
        self.session = session
    }

    func notes(in track: Int) -> [Note] {
        invalidateIfNeeded()
        if let notes = trackNotes[track] { return notes }
        let notes = session.document.notes(in: track)
        trackNotes[track] = notes
        return notes
    }

    func note(_ id: NoteID, in track: Int) -> Note? {
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

    func lanePoints(track: Int, lane: Lane) -> [LanePoint] {
        invalidateIfNeeded()
        let key = LaneKey(track: track, lane: lane)
        if let points = lanes[key] { return points }
        let points = session.document.lanePoints(track: track, lane: lane)
        lanes[key] = points
        return points
    }

    var timeAxis: TimeAxis {
        invalidateIfNeeded()
        if let axis = cachedTimeAxis { return axis }
        let timeline = session.timeline
        let axis = TimeAxis(map: TimeMap(
            ticksPerBeat: UInt32(max(1, session.document.ticksPerBeat)),
            lengthTicks: timeline.lengthTicks,
            loopStartTick: timeline.loopStartTick,
            loopEndTick: timeline.loopEndTick,
            timeSigs: session.document.timeSignatures.map {
                TimeSigPoint(tick: $0.tick, numerator: $0.numerator,
                             denomPow2: $0.denominatorPower)
            }))
        cachedTimeAxis = axis
        return axis
    }

    /// Synchronous main-actor invalidation clears every derived fact before a
    /// new revision can be read. Each projection is then rebuilt only on demand.
    private func invalidateIfNeeded() {
        let current = session.document.revision
        guard revision != current else { return }
        trackNotes.removeAll(keepingCapacity: true)
        noteIndices.removeAll(keepingCapacity: true)
        lanes.removeAll(keepingCapacity: true)
        cachedTimeAxis = nil
        revision = current
    }
}
