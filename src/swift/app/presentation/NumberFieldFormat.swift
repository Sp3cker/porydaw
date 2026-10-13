import Foundation
import QtBridge

/// Presenter-owned formats for the shell's custom integer SpinBox fields.
@MainActor
@QtBridgeable
public final class NumberFieldFormat {
    public enum Kind { case seconds, channels, reverb }
    private let kind: Kind
    public var textPattern: String = "%1 channels"
    public var defaultText: String = "Default (50)"
    public var defaultPrefix: String = "Default"

    public init(kind: Kind) { self.kind = kind }

    public func text(value: Int) -> String {
        switch kind {
        case .seconds:
            String(format: "%.1f s", Double(value) / 10)
        case .channels:
            textPattern.replacingOccurrences(of: "%1", with: String(value))
        case .reverb:
            value == -1 ? defaultText : String(value)
        }
    }

    public func value(text: String) -> Double {
        switch kind {
        case .seconds:
            (Double(text.hasSuffix(" s") ? text.dropLast(2) : text[...]).map { (value: Double) in value * 10 } ?? .nan)
                .rounded()
        case .channels:
            decimalPrefix(text)
        case .reverb:
            text.hasPrefix(defaultPrefix) ? -1 : decimalPrefix(text)
        }
    }

    private func decimalPrefix(_ text: String) -> Double {
        let digits = text.first == "+" || text.first == "-" ? text.index(after: text.startIndex) : text.startIndex
        let end =
            text[digits...].firstIndex { (character: Character) in character < "0" || character > "9" } ?? text.endIndex
        return Int(text[..<end]).map { (value: Int) in Double(value) } ?? .nan
    }
}
