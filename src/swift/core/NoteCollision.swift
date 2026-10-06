import Foundation

internal enum NoteCollisionDecision {
    case covered
    case trimmed(start: Tick, end: UInt64)
    case untouched
}

internal nonisolated func collisionOrder(
    _ lhs: (track: Int, pitch: UInt8, tick: Tick),
    _ rhs: (track: Int, pitch: UInt8, tick: Tick)
) -> Bool {
    lhs < rhs
}

// Spans must already be sorted by (track, pitch, tick).
internal nonisolated func spansAreCompatible(
    spans: [TimeNoteSpan], allowExactDuplicates: Bool
) -> Bool {
    guard spans.count > 1 else { return true }
    for index in 1..<spans.count {
        let previous = spans[index - 1]
        let current = spans[index]
        guard previous.track == current.track, previous.pitch == current.pitch,
            previous.end > UInt64(current.tick)
        else { continue }
        if !allowExactDuplicates || previous.tick != current.tick || previous.end != current.end {
            return false
        }
    }
    return true
}

// Spans must be sorted by (track, pitch, tick); the caller excludes edited notes and owns iteration and emission order.
internal nonisolated func resolveStationaryCollisions(
    spans: ArraySlice<TimeNoteSpan>, stationary: Note
) -> NoteCollisionDecision {
    guard let originalEnd = stationary.endTick else {
        return .untouched
    }
    var first = spans.startIndex
    while first < spans.endIndex
        && (spans[first].track != stationary.track || spans[first].pitch != stationary.pitch)
    {
        first += 1
    }
    var after = first
    while after < spans.endIndex
        && spans[after].track == stationary.track && spans[after].pitch == stationary.pitch
    {
        after += 1
    }
    return resolveInterval(
        start: stationary.tick, end: originalEnd, against: spans[first..<after])
}

// Spans must be sorted by tick and already matched to the caller's collision track/pitch.
internal nonisolated func resolveInterval(
    start originalStart: Tick, end originalEnd: UInt64, against spans: ArraySlice<TimeNoteSpan>
) -> NoteCollisionDecision {
    var start = originalStart
    var end = originalEnd
    for span in spans {
        guard span.end > UInt64(start), UInt64(span.tick) < end else { continue }
        if start < span.tick {
            end = UInt64(span.tick)
            break
        }
        if end > span.end {
            start = Tick(span.end)
        } else {
            return .covered
        }
    }
    return start != originalStart || end != originalEnd
        ? .trimmed(start: start, end: end) : .untouched
}
