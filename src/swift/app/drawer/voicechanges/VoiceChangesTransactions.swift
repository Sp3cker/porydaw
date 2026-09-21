import PorydawCore

/// One captured target: the document/track identity it was captured in, the
/// snapped tick, and the occurrence when the press hit a marker.
struct VoiceTarget {
    var revision: UInt64
    var track: Int
    var tick: Tick
    var occurrence: VoiceOccurrence?
}

/// One in-flight marker drag, frozen at press.
struct VoiceDragState {
    var revision: UInt64
    var track: Int
    var occurrence: VoiceOccurrence
    var identity: String
    var pressX: Double
    var previewTick: Tick
    var active: Bool = false
}

/// One open picker: the captured target plus its filter and row drafts.
struct VoicePickerState {
    var target: VoiceTarget
    var filter: String = ""
    var program: Int = -1

    var title: String { target.occurrence == nil ? "Insert voice change" : "Change voice" }
}

/// One open context menu and its frozen target.
struct VoiceMenuState {
    var target: VoiceTarget
}

/// A validated semantic lane edit. The page remains the only owner that applies
/// these to `SongDocument`, preserving the document's canonical history path.
enum VoiceLaneMutation {
    case move(track: Int, occurrence: VoiceOccurrence, tick: Tick)
    case replace(track: Int, occurrence: VoiceOccurrence, value: Int)
    case insert(track: Int, tick: Tick, value: Int)
    case delete(track: Int, occurrence: VoiceOccurrence)
}

/// Stale-target validation and transaction drafting for captured interactions.
/// Inputs are snapshots from the page; this policy never owns a document or
/// commits history.
enum VoiceChangesTransactions {
    static func capture(revision: UInt64, track: Int, tick: Tick,
                        occurrence: VoiceOccurrence?) -> VoiceTarget {
        VoiceTarget(revision: revision, track: track, tick: tick, occurrence: occurrence)
    }

    static func drag(target: VoiceTarget, pressX: Double) -> VoiceDragState? {
        guard let occurrence = target.occurrence else { return nil }
        return VoiceDragState(revision: target.revision, track: target.track,
                              occurrence: occurrence, identity: occurrence.text,
                              pressX: pressX, previewTick: occurrence.tick)
    }

    static func openPicker(target: VoiceTarget, filter: String,
                           program: Int) -> VoicePickerState {
        VoicePickerState(target: target, filter: filter, program: program)
    }

    static func openMenu(target: VoiceTarget) -> VoiceMenuState {
        VoiceMenuState(target: target)
    }

    static func isCurrent(_ target: VoiceTarget, revision: UInt64, track: Int) -> Bool {
        target.revision == revision && target.track == track
    }

    static func move(_ drag: VoiceDragState, revision: UInt64, track: Int,
                     points: [LanePoint]) -> VoiceLaneMutation? {
        guard drag.active, drag.previewTick != drag.occurrence.tick,
              drag.revision == revision, drag.track == track,
              let occurrence = VoiceLanePolicy.occurrence(drag.occurrence, in: points)
        else { return nil }
        return .move(track: drag.track, occurrence: occurrence, tick: drag.previewTick)
    }

    static func picker(_ target: VoiceTarget, program: Int, slotCount: Int,
                       revision: UInt64, track: Int,
                       points: [LanePoint]) -> VoiceLaneMutation? {
        guard program >= 0, program < slotCount,
              isCurrent(target, revision: revision, track: track)
        else { return nil }
        if let captured = target.occurrence {
            guard let occurrence = VoiceLanePolicy.occurrence(captured, in: points),
                  occurrence.value != program else { return nil }
            return .replace(track: target.track, occurrence: occurrence, value: program)
        }
        return .insert(track: target.track, tick: target.tick, value: program)
    }

    static func delete(_ target: VoiceTarget, revision: UInt64, track: Int,
                       points: [LanePoint]) -> VoiceLaneMutation? {
        guard isCurrent(target, revision: revision, track: track),
              let captured = target.occurrence,
              let occurrence = VoiceLanePolicy.occurrence(captured, in: points)
        else { return nil }
        return .delete(track: target.track, occurrence: occurrence)
    }
}
