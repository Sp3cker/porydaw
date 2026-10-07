import Foundation

/// Cross-platform byte parser; keep index loops (generic slice helpers tripled allocations).
public struct AsmLine {
    public typealias Bytes = ArraySlice<UInt8>

    public let bytes: Bytes
    public private(set) var position: Int

    public init(_ bytes: Bytes) {
        self.bytes = bytes
        position = bytes.startIndex
    }

    public static func lines(_ path: String) -> [Bytes]? {
        guard let bytes = try? VoicegroupText.read(path) else { return nil }
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

    public static func isSpace(_ byte: UInt8) -> Bool { byte == 32 || (byte >= 9 && byte <= 13) }

    public static func isWord(_ byte: UInt8) -> Bool {
        (byte >= 97 && byte <= 122) || (byte >= 65 && byte <= 90) || (byte >= 48 && byte <= 57) || byte == 95
    }

    public static func text(_ bytes: Bytes) -> String { String(decoding: bytes, as: UTF8.self) }

    static func text(_ bytes: borrowing Span<UInt8>) -> String {
        let view = copy bytes
        if let utf8 = try? UTF8Span(validating: view) { return String(copying: utf8) }
        var repaired: [UInt8] = []
        repaired.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count { repaired.append(bytes[index]); index += 1 }
        return String(decoding: repaired, as: UTF8.self)
    }

    public static func hasPrefix(_ bytes: Bytes, _ literal: [UInt8]) -> Bool {
        guard bytes.count >= literal.count else { return false }
        let source = bytes.span
        var offset = 0
        while offset < literal.count {
            if source[offset] != literal[offset] { return false }
            offset += 1
        }
        return true
    }

    public static func equals(_ bytes: Bytes, _ literal: [UInt8]) -> Bool {
        bytes.count == literal.count && hasPrefix(bytes, literal)
    }

    public static func contains(_ bytes: Bytes, _ needle: [UInt8]) -> Bool {
        var index = bytes.startIndex
        while index + needle.count <= bytes.endIndex {
            if hasPrefix(bytes[index...], needle) { return true }
            index += 1
        }
        return false
    }

    public static func trimmed(_ bytes: Bytes) -> Bytes {
        var start = bytes.startIndex
        var end = bytes.endIndex
        while start < end, isSpace(bytes[start]) { start += 1 }
        while end > start, isSpace(bytes[end - 1]) { end -= 1 }
        return bytes[start..<end]
    }

    public static func content(_ bytes: Bytes) -> Bytes {
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
    public mutating func skipSpaces() -> Bool {
        let start = position
        while position < bytes.endIndex, Self.isSpace(bytes[position]) { position += 1 }
        return position > start
    }

    public mutating func word() -> Bytes? {
        let start = position
        while position < bytes.endIndex, Self.isWord(bytes[position]) { position += 1 }
        return position > start ? bytes[start..<position] : nil
    }

    public mutating func consume(_ literal: [UInt8]) -> Bool {
        guard Self.hasPrefix(bytes[position...], literal) else { return false }
        position += literal.count
        return true
    }

    public mutating func consume(_ byte: UInt8) -> Bool {
        guard position < bytes.endIndex, bytes[position] == byte else { return false }
        position += 1
        return true
    }

    public mutating func until(_ terminator: UInt8) -> Bytes? {
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

/// Borrowed byte key with concrete hashing and comparison on bank-loading paths.
public struct SymbolKey: Hashable, Sendable {
    public let bytes: ArraySlice<UInt8>

    public init(_ bytes: ArraySlice<UInt8>) { self.bytes = bytes }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.bytes.count == rhs.bytes.count else { return false }
        let left = lhs.bytes.span
        let right = rhs.bytes.span
        var index = 0
        while index < left.count {
            if left[index] != right[index] { return false }
            index += 1
        }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Self.byteHash(bytes.span))
    }

    static func byteHash(_ source: borrowing Span<UInt8>) -> UInt64 {
        var value: UInt64 = 14_695_981_039_346_656_037
        var index = 0
        while index < source.count {
            value = (value ^ UInt64(source[index])) &* 1_099_511_628_211
            index += 1
        }
        return value
    }
}
