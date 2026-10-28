import Foundation
import PorydawCore
import QtBridge

/// Presenter-owned formats for the shell's integer SpinBox fields.
/// QML constructs the plain-digits default; Swift builds the labelled kinds.
@MainActor
@QtBridgeable
public final class NumberFieldFormat: QmlInstantiable {
    public enum Kind { case integer, seconds, channels, reverb, note }
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
        case .note:
            midiKeyName(value)
        }
    }

    /// Commits a whole integer (a note name too for `.note`); surrounding whitespace
    /// is ignored and any other text, including this field's own display text, keeps the value.
    public func value(text: String, current: Int) -> Int {
        if kind == .note { return midiKey(from: text) ?? current }
        return Int(text.trimmingCharacters(in: .whitespaces)) ?? current
    }
}
