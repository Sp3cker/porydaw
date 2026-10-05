import Foundation

/// New Song name laws (fork newsongwizard identity field), Qt-free so both
/// the document model and the QML presenters share one implementation.
public enum SongLabelPolicy {
    /// Filters each character for the existing ProjectService create-song path.
    /// The text field uses acceptEdit instead.
    public nonisolated static func normalize(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text.lowercased() {
            guard ch.isASCII, ch == "_" || ch.isLowercase || ch.isNumber else { continue }
            if out.isEmpty, ch.isNumber { continue }
            out.append(ch)
        }
        return out
    }

    /// Folds the whole proposed edit and accepts only an ASCII song name or empty text.
    public nonisolated static func acceptEdit(previous: String, proposed: String) -> String {
        let folded = proposed.lowercased()
        guard let first = folded.utf8.first else { return folded }
        guard first == 95 || (97...122).contains(first),
            folded.utf8.dropFirst().allSatisfy({ $0 == 95 || (97...122).contains($0) || (48...57).contains($0) })
        else { return previous }
        return folded
    }
}
