@MainActor
internal enum HistoryStepLabel {
    static func build(
        document: SongDocument, operation: HistoryOperation, changes: DocumentChangeSet
    ) -> String {
        let notes: Bool
        let payloadCount: Int?
        switch operation {
        case .moveNotes(let ids), .moveNotesToPitches(let ids),
            .nudgeNotes(let ids, _, _), .nudgeNotePitches(let ids, _),
            .resizeNotes(let ids, _), .resizeNoteLengths(let ids, _):
            notes = true
            payloadCount = ids.count
        case .addNotes, .deleteNotes, .setVelocities:
            notes = true
            payloadCount = nil
        case .insertRawEvent, .modifyRawEvent, .deleteRawEvents, .moveRawEvent,
            .writeLane, .moveLanePoints, .deleteLanePoints:
            notes = false
            payloadCount = nil
        case .addTrack, .duplicateTrack, .deleteTrack, .moveTrack, .renameTrack,
            .setChunkEnd, .setConfig, .setMasterTuning, .editTempo, .editRawAndTempo, .setLoop,
            .setTimeSignature, .moveTimeSignature, .deleteTimeSignature,
            .applyRangeEdit, .moveRange, .removeTime, .insertBlankTime, .duplicateTime,
            .addEffect, .removeEffect, .updateEffect, .editPluginState:
            return fixedPhrase(for: operation)
        }

        var noteIDs: Set<NoteID> = []
        var tracks: Set<Int> = []
        let map = document.engineTracks
        var changedEvents = 0
        for splice in changes.splices {
            changedEvents += max(splice.inserted.count, splice.removed.count)
            for side in 0..<2 {
                let events = side == 0 ? splice.removed : splice.inserted
                for event in events {
                    guard !notes || event.isNoteOn else { continue }
                    if notes, payloadCount == nil, let id = event.noteID { noteIDs.insert(id) }
                    for track in 0..<map.usedTrackCount {
                        let mapping = map.tracks[track]
                        guard mapping.midiChunk == splice.chunk else { continue }
                        if case .channel(let status, _, _) = event.payload,
                            status & 0x0F != mapping.channel
                        {
                            continue
                        }
                        tracks.insert(track)
                    }
                }
            }
        }
        let count = payloadCount ?? (notes ? noteIDs.count : changedEvents)
        let noun = notes ? "note" : "event"
        let subject = "\(count) \(noun)\(count == 1 ? "" : "s")"
        guard tracks.count == 1, let track = tracks.first else { return "Edited \(subject)" }
        let name = document.trackName(track)
        return "Track \(name.isEmpty ? String(track + 1) : name) - edited \(subject)"
    }

    static func fixedPhrase(for operation: HistoryOperation) -> String {
        switch operation {
        case .addNotes: "Add notes"
        case .deleteNotes: "Delete notes"
        case .moveNotes, .moveNotesToPitches, .nudgeNotes, .nudgeNotePitches: "Move notes"
        case .resizeNotes, .resizeNoteLengths: "Resize notes"
        case .setVelocities: "Set velocities"
        case .addTrack: "Add track"
        case .duplicateTrack: "Duplicate track"
        case .deleteTrack: "Delete track"
        case .moveTrack: "Move track"
        case .renameTrack: "Rename track"
        case .setChunkEnd: "Set song end"
        case .setConfig: "Edit song config"
        case .setMasterTuning: "Set master tuning"
        case .insertRawEvent: "Insert event"
        case .modifyRawEvent: "Modify event"
        case .deleteRawEvents: "Delete events"
        case .moveRawEvent: "Move event"
        case .editTempo, .editRawAndTempo: "Change tempo"
        case .setLoop: "Set loop"
        case .setTimeSignature: "Set time signature"
        case .moveTimeSignature: "Move time signature"
        case .deleteTimeSignature: "Delete time signature"
        case .writeLane: "Edit lane"
        case .moveLanePoints: "Move lane points"
        case .deleteLanePoints: "Delete lane points"
        case .applyRangeEdit: "Range edit"
        case .moveRange: "Move range"
        case .removeTime: "Remove time"
        case .insertBlankTime: "Insert time"
        case .duplicateTime: "Duplicate time"
        case .addEffect: "add MIDI effect"
        case .removeEffect: "remove MIDI effect"
        case .updateEffect: "edit MIDI effect"
        case .editPluginState: "edit plugin settings"
        }
    }
}
