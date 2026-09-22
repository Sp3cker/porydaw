import PorydawCore

/// A validated semantic lane edit. The page applies it through the existing
/// SongDocument operations, preserving the canonical history path.
enum VoiceLaneMutation: Sendable {
    case move(track: Int, occurrence: VoiceOccurrence, tick: Tick)
    case replace(track: Int, occurrence: VoiceOccurrence, value: Int)
    case insert(track: Int, tick: Tick, value: Int)
    case delete(track: Int, occurrence: VoiceOccurrence)
}

/// Frozen-target validation and semantic mutation drafting. It owns no document
/// and introduces no history abstraction.
enum VoiceChangesTransactions {
    static func move(_ drag: borrowing VoiceDragState, revision: UInt64, track: Int,
                     points: borrowing [LanePoint]) -> VoiceLaneMutation? {
        guard drag.previewTick != drag.occurrence.tick,
              drag.revision == revision, drag.track == track,
              let occurrence = VoiceLanePolicy.occurrence(drag.occurrence, in: points)
        else { return nil }
        return .move(track: drag.track, occurrence: occurrence, tick: drag.previewTick)
    }

    static func picker(_ target: borrowing VoiceTarget, program: Int, slotCount: Int,
                       revision: UInt64, track: Int,
                       points: borrowing [LanePoint]) -> VoiceLaneMutation? {
        guard program >= 0, program < slotCount,
              target.revision == revision, target.track == track
        else { return nil }
        if let captured = target.occurrence {
            guard let occurrence = VoiceLanePolicy.occurrence(captured, in: points),
                  occurrence.value != program else { return nil }
            return .replace(track: target.track, occurrence: occurrence, value: program)
        }
        return .insert(track: target.track, tick: target.tick, value: program)
    }

    static func delete(_ target: borrowing VoiceTarget, revision: UInt64, track: Int,
                       points: borrowing [LanePoint]) -> VoiceLaneMutation? {
        guard target.revision == revision, target.track == track,
              let captured = target.occurrence,
              let occurrence = VoiceLanePolicy.occurrence(captured, in: points)
        else { return nil }
        return .delete(track: target.track, occurrence: occurrence)
    }

    @MainActor
    static func apply(_ mutation: consuming VoiceLaneMutation, to session: DocumentSession) {
        switch mutation {
        case let .move(track, occurrence, tick):
            session.document.moveLanePoints(
                track: track, lane: .voice,
                moves: [LanePointMove(point: occurrence.point, tick: tick,
                                      value: occurrence.value)])
        case let .replace(track, occurrence, value):
            session.document.moveLanePoints(
                track: track, lane: .voice,
                moves: [LanePointMove(point: occurrence.point, tick: occurrence.tick,
                                      value: value)])
        case let .insert(track, tick, value):
            session.document.writeLane(
                track: track, lane: .voice, from: tick, through: tick,
                points: [LaneWrite(tick: tick, value: value)])
        case let .delete(track, occurrence):
            session.document.deleteLanePoints(
                track: track, lane: .voice, points: [occurrence.point])
        }
    }
}
