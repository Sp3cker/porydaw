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
    public static func applyRelative(_ gesture: inout VelocityEditGesture, y: Double) {
        guard !gesture.notes.isEmpty else { return }
        if !gesture.relativeActivated {
            let intrinsicChange = !gesture.detentUnlock && gesture.axis.mode == .intrinsic
                && gesture.axis.yToLevel(y) != gesture.axis.yToLevel(gesture.pressY)
            if abs(y - gesture.pressY) < gesture.activationDistance && !intrinsicChange {
                return
            }
            gesture.relativeActivated = true
        }
        gesture.preview.reserveCapacity(gesture.notes.count)
        if gesture.detentUnlock || gesture.axis.mode == .continuous {
            let delta = gesture.axis.yToVelocity(y) - gesture.axis.yToVelocity(gesture.pressY)
            for note in gesture.notes {
                let proposal = Int(note.velocity) + delta
                gesture.preview[note.noteID] = gesture.detentUnlock
                    ? clampVelocity(proposal)
                    : note.map.canonicalize(proposal)
            }
        } else {
            let levelDelta = gesture.axis.yToLevel(y) - gesture.axis.yToLevel(gesture.pressY)
            for note in gesture.notes {
                gesture.preview[note.noteID] = note.map.moveLevels(from: note.exactOrigin, by: levelDelta)
            }
        }
    }

    /// One ramp step: a straight line from the press position to the pointer,
    /// evaluated at each frozen note's own x. Notes outside the swept column
    /// keep their captured velocity.
    public static func applyRamp(_ gesture: inout VelocityEditGesture, x: Double, y: Double,
                                 hitRadius: Double, xForNote: (VelocityFrozenNote) -> Double) {
        guard !gesture.notes.isEmpty else { return }
        let first = min(gesture.pressX, x) - hitRadius
        let last = max(gesture.pressX, x) + hitRadius
        gesture.preview.reserveCapacity(gesture.notes.count)
        for note in gesture.notes {
            let noteX = xForNote(note)
            var velocity = note.velocity
            if noteX >= first, noteX <= last {
                let rampedY = velocityRampValue(at: noteX, x0: gesture.pressX, y0: gesture.pressY,
                                                x1: x, y1: y)
                velocity = resolvedVelocity(axis: gesture.axis, noteMap: note.map,
                                            detentUnlock: gesture.detentUnlock, y: rampedY)
            }
            gesture.preview[note.noteID] = velocity
        }
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

    /// Allocation-free paint update for the reducer's press-time candidate
    /// positions. Participants join the revision-bound edit only when a swept
    /// column reaches them.
    static func applyPaint(_ paint: inout VelocityPaintGesture,
                           from: (x: Double, y: Double), to: (x: Double, y: Double),
                           hitRadius: Double) {
        let deltaX = to.x - from.x
        let lower = min(from.x, to.x) - hitRadius
        let upper = max(from.x, to.x) + hitRadius
        for candidate in paint.candidates {
            if deltaX == 0 {
                if abs(candidate.x - to.x) > hitRadius { continue }
            } else if candidate.x < lower || candidate.x > upper {
                continue
            }
            if paint.edit.frozenNote(candidate.note.noteID) == nil {
                paint.edit.append(candidate.note)
                paint.edit.noteX[candidate.note.noteID] = candidate.x
            }
            let y = deltaX == 0 ? to.y : velocityRampValue(
                at: candidate.x, x0: from.x, y0: from.y, x1: to.x, y1: to.y)
            paint.edit.preview[candidate.note.noteID] = resolvedVelocity(
                axis: paint.edit.axis, noteMap: candidate.note.map,
                detentUnlock: paint.edit.detentUnlock, y: y)
        }
    }

    /// The commit payload in frozen order: every previewed value, once.
    public static func updates(_ gesture: borrowing VelocityEditGesture) -> [NoteVelocity] {
        gesture.notes.compactMap { note in
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
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 3, trimmed.allSatisfy(\.isNumber),
              let value = Int(trimmed), (minimum...maximum).contains(value)
        else { return nil }
        return value
    }

    public static func error(draft: String) -> String {
        value(draft: draft) == nil ? "Enter a velocity from \(minimum) to \(maximum)." : ""
    }
}
