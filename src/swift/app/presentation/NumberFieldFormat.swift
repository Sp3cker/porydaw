import Foundation
import QtBridge

/// Presenter-owned formats for the shell's integer SpinBox fields.
/// QML constructs the plain-digits default; Swift builds the labelled kinds.
@MainActor
@QtBridgeable
public final class NumberFieldFormat: QmlInstantiable {
    public enum Kind { case integer, seconds, channels, reverb }
    private let kind: Kind
    public var textPattern: String = "%1 channels"
    public var defaultText: String = "Default (50)"

    public required init() { kind = .integer }

    public init(kind: Kind) { self.kind = kind }

    public func text(value: Int) -> String {
        switch kind {
        case .integer:
            String(value)
        case .seconds:
            String(format: "%.1f s", Double(value) / 10)
        case .channels:
            textPattern.replacingOccurrences(of: "%1", with: String(value))
        case .reverb:
            value == -1 ? defaultText : String(value)
        }
    }

    /// Commits a whole integer; surrounding whitespace is ignored and any
    /// other text, including this field's own display text, keeps the value.
    public func value(text: String, current: Int) -> Int {
        Int(text.trimmingCharacters(in: .whitespaces)) ?? current
    }
}
