import Foundation

/// The one search rule every filter box shares: the query splits on
/// whitespace and a row matches when every word folds into some field.
struct SearchQuery: Sendable {
    private let words: [String]

    init(_ text: String) {
        words = text.split(whereSeparator: { (element: Character) -> Bool in element.isWhitespace })
            .map { (part: Substring) -> String in String(part) }
    }

    var isEmpty: Bool { words.isEmpty }

    func matches(_ field: String) -> Bool {
        words.allSatisfy { (word: String) -> Bool in Self.contains(word, in: field) }
    }

    func matches(_ first: String, _ second: String) -> Bool {
        words.allSatisfy { (word: String) -> Bool in
            Self.contains(word, in: first) || Self.contains(word, in: second)
        }
    }

    func matches(_ first: String, _ second: String, _ third: String) -> Bool {
        words.allSatisfy { (word: String) -> Bool in
            Self.contains(word, in: first) || Self.contains(word, in: second)
                || Self.contains(word, in: third)
        }
    }

    private static func contains(_ word: String, in field: String) -> Bool {
        field.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
