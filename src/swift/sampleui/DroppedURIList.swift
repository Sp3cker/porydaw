/// Entries of a dragged `text/uri-list` payload (RFC 2483): one URI per line, `#` lines are comments.
public enum DroppedURIList {
    public static func entries(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { (line: Substring) -> String? in
            let entry = line.trimmingCharacters(in: .whitespaces)
            return entry.isEmpty || entry.hasPrefix("#") ? nil : entry
        }
    }
}
