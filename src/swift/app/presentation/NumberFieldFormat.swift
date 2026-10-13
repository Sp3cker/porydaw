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

    /// Commits a whole integer; any other text, including this field's own display text, keeps the current value.
    public func value(text: String, current: Int) -> Int {
        Int(text) ?? current
    }
}
