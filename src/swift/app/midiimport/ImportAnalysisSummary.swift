import PorydawCore

public struct ImportAnalysisSummary: Equatable, Sendable {
    public let fileTracks: String
    public let gameTrackLimit: String
    public let status: String
    public let trackAction: String
    public let summary: String
    public let polyphony: String
    public let defaultInstrument: String
    public let format: String
    public let controller: String

    public init(analysis: ImportAnalysis, trackLimit: Int, wasFormat0: Bool) {
        let sourceTracks = analysis.mappedTracks + analysis.droppedTracks
        fileTracks = "This file has \(MidiImport.trackCountPhrase(sourceTracks))."
        gameTrackLimit = "The maximum number of tracks in the game is \(trackLimit)."
        if analysis.droppedTracks > 0 {
            status = "Porydaw will not import \(trackRangeText(analysis.mappedTracks + 1, sourceTracks))."
        } else if analysis.silentTracks == 0 {
            status = "Porydaw can import this MIDI file."
        } else {
            status = ""
        }

        var actions: [String] = []
        if analysis.droppedTracks > 0 {
            actions.append("To import all tracks, use a maximum of 16 tracks in the MIDI file.")
        }
        if analysis.silentTracks > 0 {
            actions.append(
                "To play all tracks in the game, use a maximum of \(MidiImport.trackCountPhrase(trackLimit)) in the MIDI file."
            )
            if analysis.silentTracks == 1 {
                actions.append(
                    "After import, move track \(analysis.mappedTracks) above track \(trackLimit) to play it.")
            } else {
                actions.append(
                    "After import, move tracks \(trackLimit + 1) through \(analysis.mappedTracks) above track \(trackLimit) to play them."
                )
            }
        }
        trackAction = actions.joined(separator: " ")

        if analysis.droppedTracks > 0 {
            var text =
                "Porydaw will import \(analysis.mappedTracks) of \(sourceTracks) tracks. It will not import \(MidiImport.trackCountPhrase(analysis.droppedTracks))."
            if analysis.silentTracks > 0 {
                text += " The game will mute \(trackRangeText(trackLimit + 1, analysis.mappedTracks))."
            }
            summary = text
        } else if analysis.silentTracks > 0 {
            summary =
                "Porydaw will import all \(sourceTracks) tracks, but the game will mute \(trackRangeText(trackLimit + 1, analysis.mappedTracks))."
        } else if analysis.mappedTracks == 1 {
            summary = "Porydaw will import the file's only track."
        } else {
            summary = "Porydaw will import all \(analysis.mappedTracks) tracks."
        }

        polyphony =
            analysis.peakConcurrentNotes > analysis.sampleNoteLimit
            ? MidiImport.concurrencyNoticeText(
                peakNotes: analysis.peakConcurrentNotes,
                sampleNoteLimit: analysis.sampleNoteLimit) : ""
        defaultInstrument =
            analysis.tracks.contains { $0.noteCount > 0 && $0.notesBeforeProgram }
            ? MidiImport.instrumentFallbackNoticeText : ""
        format =
            wasFormat0
            ? "This MIDI file contains all channels in one track. Porydaw will put each channel in a different track."
            : ""
        let notExported =
            analysis.controllers.contains { $0.support == .notExported }
            || analysis.xcmd.contains { $0.support == .notExported }
        let needsReview = analysis.xcmd.contains { $0.support == .needsReview }
        var notices: [String] = []
        if notExported { notices.append("Some controller commands are not used in the game.") }
        if needsReview {
            notices.append("Some controller commands need review. Check how the MIDI file uses them.")
        }
        controller = notices.joined(separator: " ")
    }
}

private func trackRangeText(_ first: Int, _ last: Int) -> String {
    first == last ? "track \(first)" : "tracks \(first) through \(last)"
}
