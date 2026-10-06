import PorydawCore

/// Session-scoped, document-only projections, each memoized on the revision
/// stamps it reads so an edit re-derives only the tracks and axes it touched.
/// Bank and presentation state are deliberately absent.
@MainActor
public final class DocumentProjectionCache {
    /// Notes and lanes of one track carry raw event offsets, so they key on any
    /// event edit in the chunk plus the facts that map the track to it.
    private struct TrackKey: Equatable {
        let chunk: Int?
        let events: UInt64
        let structure: UInt64
        let meta: UInt64
    }

    private struct LaneKey: Hashable {
        let track: Int
        let lane: Lane
    }

    private struct AxisKey: Equatable {
        let time: UInt64
        let config: UInt64
        let structure: UInt64
        let meta: UInt64
        let lengthTicks: Tick
        let loopStartTick: Tick
        let loopEndTick: Tick
    }

    private unowned let session: DocumentSession
    private var trackNotes: [Int: (key: TrackKey, notes: [Note])] = [:]
    private var noteIndices: [Int: [NoteID: Int]] = [:]
    private var lanes: [LaneKey: (key: TrackKey, points: [LanePoint])] = [:]
    private var cachedTimeAxis: (key: AxisKey, axis: TimeAxis)?

    init(session: DocumentSession) {
        self.session = session
    }

    public func notes(in track: Int) -> [Note] {
        let key = trackKey(track: track)
        if let cached = trackNotes[track], cached.key == key { return cached.notes }
        let notes = session.document.notes(in: track)
        trackNotes[track] = (key, notes)
        noteIndices.removeValue(forKey: track)
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
        let key = trackKey(track: track)
        let laneKey = LaneKey(track: track, lane: lane)
        if let cached = lanes[laneKey], cached.key == key { return cached.points }
        let points = session.document.lanePoints(track: track, lane: lane)
        lanes[laneKey] = (key, points)
        return points
    }

    public var timeAxis: TimeAxis {
        let stamps = session.document.revisions
        let timeline = session.timeline
        let key = AxisKey(
            time: stamps.time, config: stamps.config, structure: stamps.structure,
            meta: stamps.all.meta, lengthTicks: timeline.lengthTicks,
            loopStartTick: timeline.loopStartTick, loopEndTick: timeline.loopEndTick)
        if let cached = cachedTimeAxis, cached.key == key { return cached.axis }
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
        cachedTimeAxis = (key, axis)
        return axis
    }

    private func trackKey(track: Int) -> TrackKey {
        let document = session.document
        let stamps = document.revisions
        let map = document.engineTracks
        let chunk =
            track >= 0 && track < map.usedTrackCount && map.tracks.indices.contains(track)
            ? map.tracks[track].midiChunk : nil
        let events = chunk.flatMap { stamps.chunks.indices.contains($0) ? stamps.chunks[$0].events : nil } ?? 0
        return TrackKey(chunk: chunk, events: events, structure: stamps.structure, meta: stamps.all.meta)
    }
}
