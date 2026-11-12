import PorydawCore

public enum MidiEffectDiagnostics {
    public static func text(_ report: NormalizationReport?) -> String {
        guard let report else { return "" }
        var text = ""
        func append(_ count: Int, _ description: String) {
            guard count != 0 else { return }
            if !text.isEmpty { text.append(" · ") }
            text.append(String(count))
            text.append(" ")
            text.append(description)
        }
        append(report.notes, "notes")
        append(report.nonNoteEvents, "non-note events")
        append(report.droppedBeforeRange, "dropped before range")
        append(report.droppedAfterRange, "dropped after range")
        append(report.droppedPitch, "dropped pitches")
        append(report.droppedTooShort, "dropped too short")
        append(report.orphanOffs, "orphan note-offs")
        append(report.unterminatedNotes, "unterminated notes")
        append(report.snappedOnsets, "snapped")
        append(report.adjustedDurations, "adjusted durations")
        append(report.velocityClamped, "clamped velocities")
        append(report.overlapsTrimmed, "trimmed overlaps")
        append(report.duplicatesSuppressed, "suppressed duplicates")
        return text
    }
}
