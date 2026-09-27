import Foundation

@MainActor
extension SongDocument {
    func makeTimePlan(scope: TimeScope, file: MidiFile) -> TimePlan {
        let map = file.engineTracks()
        var trackByChunk: [Int: Int] = [:]
        for track in 0..<map.usedTrackCount {
            if let chunk = map.tracks[track].midiChunk { trackByChunk[chunk] = track }
        }
        var selected = file.chunks.map { Array(repeating: false, count: $0.events.count) }
        var affected = Array(repeating: false, count: file.chunks.count)
        var events: [TimeEventRef] = []
        var xcmdLaneByChunk = Array(repeating: [Int: UInt8](), count: file.chunks.count)
        for chunk in file.chunks.indices {
            let stream = streamIndex(for: chunk, map: map)
            for point in Xcmd.project(Xcmd.traffic(in: file.chunks[chunk], stream: stream)).points {
                if point.index <= UInt64(Int.max) { xcmdLaneByChunk[chunk][Int(point.index)] = point.lane }
            }
        }
        for chunk in file.chunks.indices {
            let engineTrack = trackByChunk[chunk] ?? -1
            for index in file.chunks[chunk].events.indices {
                let event = file.chunks[chunk].events[index]
                let logicalLane = xcmdLaneByChunk[chunk][index].map { Lane.controller($0) }
                let lane = logicalLane ?? lane(of: event)
                let covered: Bool
                if isTempoEvent(event) { covered = false }
                else if scope.wholeSong { covered = !event.isChannel || engineTrack >= 0 }
                else if event.isChannel && scope.tracks.contains(engineTrack) { covered = true }
                else if let lane { covered = scope.coversLane(track: engineTrack, lane: lane) }
                else { covered = false }
                guard covered else { continue }
                selected[chunk][index] = true
                affected[chunk] = true
                let kind: TimeEventRef.Kind
                let stream: TimeStream?
                if event.isNoteOn || event.isNoteEnd {
                    kind = .note; stream = nil
                } else if isSignature(event) {
                    kind = .signature
                    stream = TimeStream(kind: .signature, chunk: -1, status: 0, data0: 0)
                } else if event.isChannel {
                    kind = .value
                    let data0: UInt8
                    if let logicalLane, case let .controller(controller) = logicalLane {
                        data0 = controller
                    } else if case let .channel(_, first, _) = event.payload,
                              event.typeNibble == 0xA || event.typeNibble == 0xB { data0 = first }
                    else { data0 = 0 }
                    stream = TimeStream(kind: .channel, chunk: chunk,
                                        status: event.status, data0: data0)
                } else {
                    kind = .other; stream = nil
                }
                events.append(TimeEventRef(chunk: chunk, index: index, tick: event.tick,
                                           kind: kind, stream: stream))
            }
        }
        var notes: [Note] = []
        for track in 0..<map.usedTrackCount where scope.coversTrack(track) {
            guard let chunk = map.tracks[track].midiChunk else { continue }
            for note in NoteProjection.pair(events: file.chunks[chunk].events,
                                            channel: map.tracks[track].channel,
                                            chunk: chunk, track: track) {
                guard selected[chunk][note.onIndex],
                      note.endIndex.map({ selected[chunk][$0] }) ?? true else { continue }
                notes.append(note)
            }
        }
        if scope.wholeSong {
            affected = Array(repeating: true, count: file.chunks.count)
        }
        return TimePlan(events: events, notes: notes, selected: selected, affectedChunks: affected)
    }

    func admits(range: TimeRange, scope: TimeScope, mode: TimeTransformMode,
                plan: TimePlan, state: SongState) -> Bool {
        guard mode != .duplicate || range.endTick <= TimeDefaults.maxTick - range.span else {
            return false
        }
        guard mode != .remove else { return true }
        let threshold = mode == .insertBlank ? range.startTick : range.endTick
        for chunk in state.file.chunks.indices where plan.affectedChunks[chunk] {
            let end = state.file.chunks[chunk].endTick
            if end >= threshold && end > TimeDefaults.maxTick - range.span { return false }
        }
        for ref in plan.events where ref.tick >= threshold {
            if ref.tick > TimeDefaults.maxTick - range.span { return false }
        }
        if scope.coversTempo {
            for point in state.tempo where point.tick >= threshold {
                if point.tick > TimeDefaults.maxTick - range.span { return false }
            }
        }
        return true
    }

    func planRemove(range: TimeRange, scope: TimeScope, plan: TimePlan, state: SongState,
                    actions: inout TimeActions, extra: inout [[MidiEvent]]) {
        let s = range.startTick, e = range.endTick, span = range.span
        var taken = plan.selected.map { Array(repeating: false, count: $0.count) }
        for note in plan.notes {
            if note.tick >= e {
                actions.move(chunk: note.chunk, index: note.onIndex, to: note.tick - span,
                             preserveIdentity: true)
                taken[note.chunk][note.onIndex] = true
                if let endIndex = note.endIndex {
                    let end = state.file.chunks[note.chunk].events[endIndex].tick
                    actions.move(chunk: note.chunk, index: endIndex, to: end - span,
                                 preserveIdentity: false)
                    taken[note.chunk][endIndex] = true
                }
            } else if note.tick >= s {
                actions.remove(chunk: note.chunk, index: note.onIndex)
                taken[note.chunk][note.onIndex] = true
                if let end = note.endIndex { actions.remove(chunk: note.chunk, index: end); taken[note.chunk][end] = true }
            } else {
                taken[note.chunk][note.onIndex] = true
                if let end = note.endIndex { taken[note.chunk][end] = true }
            }
        }
        for ref in plan.events where ref.kind == .note && !taken[ref.chunk][ref.index] {
            if ref.tick < s { continue }
            if ref.tick >= e { actions.move(chunk: ref.chunk, index: ref.index, to: ref.tick - span,
                                             preserveIdentity: state.file.chunks[ref.chunk].events[ref.index].isNoteOn) }
            else { actions.remove(chunk: ref.chunk, index: ref.index) }
        }
        applyRemoveToValueStreams(range: range, plan: plan, state: state, actions: &actions)
        if scope.wholeSong {
            for ref in plan.events where ref.kind == .other {
                if ref.tick >= e { actions.move(chunk: ref.chunk, index: ref.index, to: ref.tick - span,
                                                preserveIdentity: false) }
                else if ref.tick > s { actions.move(chunk: ref.chunk, index: ref.index, to: s,
                                                    preserveIdentity: false) }
            }
            for chunk in actions.endTicks.indices {
                let end = actions.endTicks[chunk]
                actions.endTicks[chunk] = end >= e ? end - span : (end > s ? s : end)
            }
        }
    }

    func planInsert(range: TimeRange, plan: TimePlan, state: SongState,
                    actions: inout TimeActions, extra: inout [[MidiEvent]]) {
        let s = range.startTick, e = range.endTick, span = range.span
        var taken = plan.selected.map { Array(repeating: false, count: $0.count) }
        for note in plan.notes {
            let end = note.endIndex.map { state.file.chunks[note.chunk].events[$0].tick }
            if note.tick >= s {
                actions.move(chunk: note.chunk, index: note.onIndex, to: note.tick + span,
                             preserveIdentity: true)
                taken[note.chunk][note.onIndex] = true
                if let endIndex = note.endIndex, let end {
                    actions.move(chunk: note.chunk, index: endIndex, to: end + span,
                                 preserveIdentity: false)
                    taken[note.chunk][endIndex] = true
                }
            } else if let end, end == s {
                if let index = note.endIndex { taken[note.chunk][index] = true }
                taken[note.chunk][note.onIndex] = true
            } else if let end, end > s, let endIndex = note.endIndex {
                taken[note.chunk][note.onIndex] = true; taken[note.chunk][endIndex] = true
                actions.remove(chunk: note.chunk, index: endIndex)
                var firstEnd = state.file.chunks[note.chunk].events[endIndex]; firstEnd.tick = s
                var secondOn = state.file.chunks[note.chunk].events[note.onIndex]; secondOn.tick = e; secondOn.noteID = nil
                var secondEnd = state.file.chunks[note.chunk].events[endIndex]; secondEnd.tick = end + span
                extra[note.chunk].append(contentsOf: [firstEnd, secondOn, secondEnd])
            } else if note.isUnterminated {
                taken[note.chunk][note.onIndex] = true
                extra[note.chunk].append(.channel(tick: s, status: 0x80 | note.channel,
                                                  data0: note.pitch))
                var second = state.file.chunks[note.chunk].events[note.onIndex]
                second.tick = e; second.noteID = nil; extra[note.chunk].append(second)
            }
        }
        for ref in plan.events where !taken[ref.chunk][ref.index] && ref.tick >= s {
            actions.move(chunk: ref.chunk, index: ref.index, to: ref.tick + span,
                         preserveIdentity: state.file.chunks[ref.chunk].events[ref.index].isNoteOn)
            if ref.kind == .signature && ref.tick == s {
                var copy = state.file.chunks[ref.chunk].events[ref.index]; copy.tick = s
                extra[ref.chunk].append(copy)
            }
        }
        shiftEndsRight(range: range, threshold: s, plan: plan, actions: &actions)
    }

    func planDuplicate(range: TimeRange, scope: TimeScope, plan: TimePlan, state: SongState,
                       actions: inout TimeActions, extra: inout [[MidiEvent]]) {
        let s = range.startTick, e = range.endTick, span = range.span
        var paired = plan.selected.map { Array(repeating: false, count: $0.count) }
        var taken = paired
        for note in plan.notes {
            paired[note.chunk][note.onIndex] = true
            if let endIndex = note.endIndex { paired[note.chunk][endIndex] = true }
            let end = note.endIndex.map { state.file.chunks[note.chunk].events[$0].tick }
            if note.tick >= e {
                actions.move(chunk: note.chunk, index: note.onIndex, to: note.tick + span,
                             preserveIdentity: true); taken[note.chunk][note.onIndex] = true
                if let endIndex = note.endIndex, let end {
                    actions.move(chunk: note.chunk, index: endIndex, to: end + span,
                                 preserveIdentity: false); taken[note.chunk][endIndex] = true
                }
            } else if let end, let endIndex = note.endIndex {
                if end == e {
                    taken[note.chunk][endIndex] = true
                } else if end > e {
                    actions.remove(chunk: note.chunk, index: endIndex)
                    taken[note.chunk][endIndex] = true
                    var firstEnd = state.file.chunks[note.chunk].events[endIndex]; firstEnd.tick = e
                    var tailOn = state.file.chunks[note.chunk].events[note.onIndex]
                    tailOn.tick = e + span; tailOn.noteID = nil
                    var tailEnd = state.file.chunks[note.chunk].events[endIndex]; tailEnd.tick = end + span
                    extra[note.chunk].append(contentsOf: [firstEnd, tailOn, tailEnd])
                }
            }
        }
        for ref in plan.events where !taken[ref.chunk][ref.index] && ref.tick >= e {
            actions.move(chunk: ref.chunk, index: ref.index, to: ref.tick + span,
                         preserveIdentity: state.file.chunks[ref.chunk].events[ref.index].isNoteOn)
        }
        for note in plan.notes where note.tick < e {
            let end = note.endIndex.map { state.file.chunks[note.chunk].events[$0].tick } ?? e
            let sourceStart = max(note.tick, s), sourceEnd = min(end, e)
            guard sourceEnd > sourceStart else { continue }
            var on = state.file.chunks[note.chunk].events[note.onIndex]
            on.tick = sourceStart + span; on.noteID = nil
            let off: MidiEvent
            if let endIndex = note.endIndex {
                var value = state.file.chunks[note.chunk].events[endIndex]; value.tick = sourceEnd + span; off = value
            } else { off = .channel(tick: sourceEnd + span, status: 0x80 | note.channel, data0: note.pitch) }
            extra[note.chunk].append(contentsOf: [on, off])
        }
        seedAndCopyValueStreams(range: range, plan: plan, state: state,
                                actions: &actions, extra: &extra)
        if scope.wholeSong {
            for ref in plan.events where ref.kind == .other && range.contains(ref.tick) {
                var copy = state.file.chunks[ref.chunk].events[ref.index]; copy.tick += span
                extra[ref.chunk].append(copy)
            }
        }
        for ref in plan.events where ref.kind == .note && !paired[ref.chunk][ref.index] && range.contains(ref.tick) {
            var copy = state.file.chunks[ref.chunk].events[ref.index]; copy.tick += span; copy.noteID = nil
            extra[ref.chunk].append(copy)
        }
        shiftEndsRight(range: range, threshold: e, plan: plan, actions: &actions)
    }
}
