import Foundation

struct AsmLine {
    typealias Bytes = ArraySlice<UInt8>

    let bytes: Bytes
    private(set) var position: Int

    init(_ bytes: Bytes) {
        self.bytes = bytes
        position = bytes.startIndex
    }

    static func lines(_ path: String) -> [Bytes]? {
        guard let data = try? ProjectFileStore.read(path) else { return nil }
        let bytes = [UInt8](data)
        var lines: [Bytes] = []
        var start = 0
        var index = 0
        while index < bytes.count {
            if bytes[index] == 10 {
                lines.append(bytes[start..<index])
                start = index + 1
            }
            index += 1
        }
        lines.append(bytes[start..<bytes.count])
        return lines
    }

    static func isSpace(_ byte: UInt8) -> Bool { byte == 32 || (byte >= 9 && byte <= 13) }

    static func isWord(_ byte: UInt8) -> Bool {
        (byte >= 97 && byte <= 122) || (byte >= 65 && byte <= 90) || (byte >= 48 && byte <= 57) || byte == 95
    }

    static func text(_ bytes: Bytes) -> String { String(decoding: bytes, as: UTF8.self) }

    static func hasPrefix(_ bytes: Bytes, _ literal: [UInt8]) -> Bool {
        guard bytes.count >= literal.count else { return false }
        var offset = 0
        while offset < literal.count {
            if bytes[bytes.startIndex + offset] != literal[offset] { return false }
            offset += 1
        }
        return true
    }

    static func equals(_ bytes: Bytes, _ literal: [UInt8]) -> Bool {
        bytes.count == literal.count && hasPrefix(bytes, literal)
    }

    static func contains(_ bytes: Bytes, _ needle: [UInt8]) -> Bool {
        var index = bytes.startIndex
        while index + needle.count <= bytes.endIndex {
            if hasPrefix(bytes[index...], needle) { return true }
            index += 1
        }
        return false
    }

    static func trimmed(_ bytes: Bytes) -> Bytes {
        var start = bytes.startIndex
        var end = bytes.endIndex
        while start < end, isSpace(bytes[start]) { start += 1 }
        while end > start, isSpace(bytes[end - 1]) { end -= 1 }
        return bytes[start..<end]
    }

    static func content(_ bytes: Bytes) -> Bytes {
        var end = bytes.endIndex
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == 64 || (byte == 47 && index + 1 < bytes.endIndex && bytes[index + 1] == 47) {
                end = index
                break
            }
            index += 1
        }
        return trimmed(bytes[..<end])
    }

    @discardableResult
    mutating func skipSpaces() -> Bool {
        let start = position
        while position < bytes.endIndex, Self.isSpace(bytes[position]) { position += 1 }
        return position > start
    }

    mutating func word() -> Bytes? {
        let start = position
        while position < bytes.endIndex, Self.isWord(bytes[position]) { position += 1 }
        return position > start ? bytes[start..<position] : nil
    }

    mutating func consume(_ literal: [UInt8]) -> Bool {
        guard Self.hasPrefix(bytes[position...], literal) else { return false }
        position += literal.count
        return true
    }

    mutating func consume(_ byte: UInt8) -> Bool {
        guard position < bytes.endIndex, bytes[position] == byte else { return false }
        position += 1
        return true
    }

    mutating func until(_ terminator: UInt8) -> Bytes? {
        var end = position
        while end < bytes.endIndex {
            if bytes[end] == terminator {
                let result = bytes[position..<end]
                position = end + 1
                return result
            }
            end += 1
        }
        return nil
    }
}
