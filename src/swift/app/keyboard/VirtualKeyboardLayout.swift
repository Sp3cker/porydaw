import PorydawCore

/// The Virtual MIDI Keyboard's piano: 28 keys from a base C (16 white, 12 black),
/// the computer key that plays each, and the geometry painting and hit testing share.
enum VirtualKeyboardLayout {
    /// Keys drawn: base ..< base + span (C to the D# 27 semitones up).
    static let span = 28
    static let whiteKeyCount = 16
    static let minBase = 0  // C-1
    static let maxBase = 108  // C8: the keys above G9 are drawn faded and play nothing
    static let defaultBase = 48  // C3: the two octaves bracket middle C
    /// A black key's share of a white key's width and of the piano's height.
    static let blackWidthRatio = 0.6
    static let blackHeightRatio = 0.62

    /// The typing letters by offset; comma and Q both play the upper C.
    static let letters = [
        "Z", "S", "X", "D", "C", "V", "G", "B", "H", "N", "J", "M", ", Q", "2",
        "W", "3", "E", "R", "5", "T", "6", "Y", "7", "U", "I", "9", "O", "0",
    ]
    /// Each white key's index from the left by offset; -1 marks a black key.
    private static let whiteIndex = [
        0, -1, 1, -1, 2, 3, -1, 4, -1, 5, -1, 6, 7, -1,
        8, -1, 9, 10, -1, 11, -1, 12, -1, 13, 14, -1, 15, -1,
    ]

    static func isBlack(offset: Int) -> Bool { whiteIndex[offset] < 0 }

    /// A base rounded down to its C (also below zero) and clamped to C-1...C8.
    static func roundBase(_ base: Int) -> Int {
        min(maxBase, max(minBase, base - ((base % 12) + 12) % 12))
    }

    /// Whether `key` is drawn from `base` and within MIDI's 0...127.
    static func playable(key: Int, base: Int) -> Bool {
        key >= base && key < base + span && key <= 127
    }

    /// How many offsets from `base` play (the rest are past G9).
    static func playableSpan(base: Int) -> Int { max(0, min(span, 128 - base)) }

    /// Octave names on the playable Cs ("C3"), empty elsewhere.
    static func octaveLabels(base: Int) -> [String] {
        (0..<span).map { offset in
            offset % 12 == 0 && base + offset <= 127 ? midiKeyName(base + offset) : ""
        }
    }

    struct KeyRect: Equatable {
        var x: Double
        var width: Double
        var height: Double
    }

    /// Whites share the width less half a black key, so the top D# is drawn whole;
    /// a black key is centred on the line between its two whites. Whole pixels.
    static func keyRect(offset: Int, width: Double, height: Double) -> KeyRect {
        guard (0..<span).contains(offset), width > 0, height > 0 else {
            return KeyRect(x: 0, width: 0, height: 0)
        }
        let whiteWidth = width / (Double(whiteKeyCount) + blackWidthRatio / 2)
        func whiteX(_ index: Int) -> Double { (Double(index) * whiteWidth).rounded() }
        let index = whiteIndex[offset]
        if index >= 0 {
            return KeyRect(x: whiteX(index), width: whiteX(index + 1) - whiteX(index), height: height.rounded())
        }
        let blackWidth = max(3, (whiteWidth * blackWidthRatio).rounded())
        let line = whiteX(whiteIndex[offset - 1] + 1)
        return KeyRect(
            x: line - (blackWidth / 2).rounded(.down), width: blackWidth,
            height: (height * blackHeightRatio).rounded())
    }

    /// The playable key under a point (black keys first), or -1.
    static func keyAt(x: Double, y: Double, width: Double, height: Double, base: Int) -> Int {
        for black in [true, false] {
            for offset in 0..<span where isBlack(offset: offset) == black {
                let rect = keyRect(offset: offset, width: width, height: height)
                guard x >= rect.x, x < rect.x + rect.width, y >= 0, y < rect.height else { continue }
                return playable(key: base + offset, base: base) ? base + offset : -1
            }
        }
        return -1
    }

    /// The least height at which a C's octave and letter lines clear its black key.
    static func minimumPianoHeight(labelHeight: Double, padding: Double, baseFontPx: Double) -> Double {
        let labels = 2 * labelHeight + padding
        return max(5 * baseFontPx, ((labels + 2) / (1 - blackHeightRatio)).rounded(.up))
    }
}
