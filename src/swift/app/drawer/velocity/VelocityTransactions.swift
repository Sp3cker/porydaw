import Foundation
import PorydawCore

/// `ui::linearRampValue`: the ramp's y at `x`, clamped to the drawn span.
public func velocityRampValue(at x: Double, x0: Double, y0: Double, x1: Double,
                              y1: Double) -> Double {
    let deltaX = x1 - x0
    guard deltaX != 0 else { return y1 }
    let t = min(max((x - x0) / deltaX, 0), 1)
    return y0 + t * (y1 - y0)
}

// MARK: - Frozen gesture

/// One note captured when a gesture begins. Motion never reads the document, so
/// every field the preview needs — including the gesture-time voice map — is
/// frozen here: a hover or voicegroup change mid-gesture must not retarget the
/// axis or the map the gesture started on.
public struct VelocityFrozenNote: Sendable {
    public var noteID: NoteID
    public var tick: Tick
    public var duration: Tick
    public var pitch: UInt8
    public var velocity: UInt8
    public var map: VelocityMap
    public var exactOrigin: UInt8

    public init(noteID: NoteID, tick: Tick, duration: Tick, pitch: UInt8, velocity: UInt8,
                map: VelocityMap, exactOrigin: UInt8) {
        self.noteID = noteID
        self.tick = tick
        self.duration = duration
        self.pitch = pitch
        self.velocity = velocity
        self.map = map
        self.exactOrigin = exactOrigin
    }
}

public enum VelocityGestureKind: Int, Sendable {
    case relative = 0
    case paint = 1
    case ramp = 2
    case pendingBand = 3
    case band = 4
    /// Middle-drag pan: the shared camera's own scroll, requested by the page.
    case pan = 5
}

/// One live gesture: the frozen targets, the captured document/track identity,
/// the axis map it started on and the preview it publishes.
public struct VelocityGestureState: Sendable {
    public var kind: VelocityGestureKind
    public var revision: UInt64
    public var track: Int
    public private(set) var notes: [VelocityFrozenNote]
    private var noteIndices: [NoteID: Int]

    public func frozenNote(_ id: NoteID) -> VelocityFrozenNote? {
        noteIndices[id].map { notes[$0] }
    }

    public mutating func append(_ note: VelocityFrozenNote) {
        guard note.noteID.isAssigned, (1...127).contains(Int(note.velocity)),
              noteIndices[note.noteID] == nil else { return }
        noteIndices[note.noteID] = notes.count
        notes.append(note)
    }

    /// The original is visible immediately; only changed targets enter the draft.
    public func previewVelocity(_ id: NoteID) -> UInt8? {
        guard let index = noteIndices[id] else { return nil }
        return preview[id] ?? notes[index].velocity
    }

    @discardableResult
    public mutating func updatePreview(_ updates: [NoteVelocity]) -> Bool {
        guard !updates.isEmpty else { return false }
        if updates.count == 1 {
            let update = updates[0]
            guard noteIndices[update.noteID] != nil else { return false }
            preview[update.noteID] = UInt8(min(max(update.velocity, 1), 127))
            return true
        }
        var seen: Set<NoteID> = []
        for update in updates {
            guard noteIndices[update.noteID] != nil,
                  seen.insert(update.noteID).inserted else { return false }
        }
        for update in updates {
            preview[update.noteID] = UInt8(min(max(update.velocity, 1), 127))
        }
        return true
    }
    public var axis: VelocityAxisModel
    public var detentUnlock: Bool
    public var activationDistance: Double
    public var relativeActivated: Bool = false
    public var pressX: Double
    public var pressY: Double
    public var previousX: Double
    public var previousY: Double
    public var bandX: Double
    public var bandY: Double
    public private(set) var preview: [NoteID: UInt8] = [:]
    public var bandPreview: [NoteID] = []
    public var controlPress: Bool = false

    public init?(kind: VelocityGestureKind, revision: UInt64, track: Int,
                 notes: [VelocityFrozenNote], axis: VelocityAxisModel, detentUnlock: Bool,
                 activationDistance: Double, pressX: Double, pressY: Double,
                 controlPress: Bool = false) {
        if (kind == .relative || kind == .ramp) && notes.isEmpty { return nil }
        var indices: [NoteID: Int] = [:]
        indices.reserveCapacity(notes.count)
        for (index, note) in notes.enumerated() {
            guard note.noteID.isAssigned, (1...127).contains(Int(note.velocity)),
                  indices.updateValue(index, forKey: note.noteID) == nil else { return nil }
        }
        self.kind = kind
        self.revision = revision
        self.track = track
        self.notes = notes
        noteIndices = indices
        self.axis = axis
        self.detentUnlock = detentUnlock
        self.activationDistance = activationDistance
        self.pressX = pressX
        self.pressY = pressY
        self.previousX = pressX
        self.previousY = pressY
        self.bandX = pressX
        self.bandY = pressY
        self.controlPress = controlPress
    }
}

/// The gesture's whole rule set as pure functions: absolute resolution, the
/// relative delta, the ramp, the paint sweep and the commit payload.
public enum VelocityGesturePolicy {
    /// One absolute pointer position to one velocity. The unlock modifier takes
    /// exact MIDI, continuous mode canonicalizes onto the note's own map, and
    /// intrinsic mode takes the representative of the level under the pointer.
    public static func resolvedVelocity(axis: VelocityAxisModel, noteMap: VelocityMap,
                                        detentUnlock: Bool, y: Double) -> UInt8 {
        if detentUnlock { return clampVelocity(axis.yToVelocity(y)) }
        if axis.mode == .continuous { return noteMap.canonicalize(axis.yToVelocity(y)) }
        return noteMap.representative(axis.yToLevel(y))
    }

    /// One relative drag step: one clamped delta covers every frozen note at
    /// once, so relative offsets never collapse. Nothing moves until the drag
    /// leaves the activation distance or crosses an intrinsic level.
    public static func applyRelative(_ gesture: inout VelocityGestureState, y: Double) {
        guard !gesture.notes.isEmpty else { return }
        if !gesture.relativeActivated {
            let intrinsicChange = !gesture.detentUnlock && gesture.axis.mode == .intrinsic
                && gesture.axis.yToLevel(y) != gesture.axis.yToLevel(gesture.pressY)
            if abs(y - gesture.pressY) < gesture.activationDistance && !intrinsicChange {
                return
            }
            gesture.relativeActivated = true
        }
        var updates: [NoteVelocity] = []
        updates.reserveCapacity(gesture.notes.count)
        if gesture.detentUnlock || gesture.axis.mode == .continuous {
            let delta = gesture.axis.yToVelocity(y) - gesture.axis.yToVelocity(gesture.pressY)
            for note in gesture.notes {
                let proposal = Int(note.velocity) + delta
                let velocity = gesture.detentUnlock
                    ? clampVelocity(proposal)
                    : note.map.canonicalize(proposal)
                updates.append(NoteVelocity(noteID: note.noteID, velocity: Int(velocity)))
            }
        } else {
            let levelDelta = gesture.axis.yToLevel(y) - gesture.axis.yToLevel(gesture.pressY)
            for note in gesture.notes {
                updates.append(NoteVelocity(noteID: note.noteID,
                                            velocity: Int(note.map.moveLevels(from: note.exactOrigin, by: levelDelta))))
            }
        }
        gesture.updatePreview(updates)
    }

    /// One ramp step: a straight line from the press position to the pointer,
    /// evaluated at each frozen note's own x. Notes outside the swept column
    /// keep their captured velocity.
    public static func applyRamp(_ gesture: inout VelocityGestureState, x: Double, y: Double,
                                 hitRadius: Double, xForNote: (VelocityFrozenNote) -> Double) {
        guard !gesture.notes.isEmpty else { return }
        let first = min(gesture.pressX, x) - hitRadius
        let last = max(gesture.pressX, x) + hitRadius
        var updates: [NoteVelocity] = []
        updates.reserveCapacity(gesture.notes.count)
        for note in gesture.notes {
            let noteX = xForNote(note)
            var velocity = note.velocity
            if noteX >= first, noteX <= last {
                let rampedY = velocityRampValue(at: noteX, x0: gesture.pressX, y0: gesture.pressY,
                                                x1: x, y1: y)
                velocity = resolvedVelocity(axis: gesture.axis, noteMap: note.map,
                                            detentUnlock: gesture.detentUnlock, y: rampedY)
            }
            updates.append(NoteVelocity(noteID: note.noteID, velocity: Int(velocity)))
        }
        gesture.updatePreview(updates)
    }

    /// One paint step: the frozen notes whose x falls in the swept column (or
    /// within the hit radius when the pointer did not move) take the linear
    /// interpolation of the pointer's y at their own x.
    public static func paint(axis: VelocityAxisModel, detentUnlock: Bool,
                             candidates: [(note: VelocityFrozenNote, x: Double)],
                             from: (x: Double, y: Double), to: (x: Double, y: Double),
                             hitRadius: Double) -> [NoteVelocity] {
        let deltaX = to.x - from.x
        let lower = min(from.x, to.x) - hitRadius
        let upper = max(from.x, to.x) + hitRadius
        var updates: [NoteVelocity] = []
        updates.reserveCapacity(candidates.count)
        for candidate in candidates {
            var y = to.y
            if deltaX == 0 {
                if abs(candidate.x - to.x) > hitRadius { continue }
            } else {
                if candidate.x < lower || candidate.x > upper { continue }
                y = velocityRampValue(at: candidate.x, x0: from.x, y0: from.y,
                                      x1: to.x, y1: to.y)
            }
            let velocity = resolvedVelocity(axis: axis, noteMap: candidate.note.map,
                                            detentUnlock: detentUnlock, y: y)
            updates.append(NoteVelocity(noteID: candidate.note.noteID, velocity: Int(velocity)))
        }
        return updates
    }

    /// The commit payload in note order: every previewed value, once.
    public static func updates(_ gesture: VelocityGestureState) -> [NoteVelocity] {
        gesture.notes.sorted { $0.noteID.rawValue < $1.noteID.rawValue }.compactMap { note in
            guard let velocity = gesture.preview[note.noteID],
                  velocity != note.velocity
            else { return nil }
            return NoteVelocity(noteID: note.noteID, velocity: Int(velocity))
        }
    }
}

// MARK: - Prompt transaction

/// The Set Velocity prompt's frozen transaction: the captured targets, their
/// before-values and the document identity they were captured under. The draft
/// is presentation state; only acceptance mutates the document.
public struct VelocityPromptState: Sendable {
    public var revision: UInt64
    public var track: Int
    public var noteIDs: [NoteID]
    public var beforeValues: [UInt8]
    public var initialValue: Int
    public var draft: String
    public var error: String

    public init(revision: UInt64, track: Int, noteIDs: [NoteID], beforeValues: [UInt8],
                initialValue: Int, draft: String, error: String = "") {
        self.revision = revision
        self.track = track
        self.noteIDs = noteIDs
        self.beforeValues = beforeValues
        self.initialValue = initialValue
        self.draft = draft
        self.error = error
    }
}

/// The draft rule: decimal `1...127`, nothing else. An invalid draft publishes
/// an error and commits nothing.
public enum VelocityPromptPolicy {
    public static let minimum = 1
    public static let maximum = 127

    public static func value(draft: String) -> Int? {
        guard !draft.isEmpty, draft.count <= 3,
              draft.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int(draft), (minimum...maximum).contains(value)
        else { return nil }
        return value
    }

    public static func error(draft: String) -> String {
        value(draft: draft) == nil ? "Enter a velocity from \(minimum) to \(maximum)." : ""
    }
}
