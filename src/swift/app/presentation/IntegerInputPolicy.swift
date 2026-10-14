import Foundation
import QtBridge

/// Integer editing decisions for the prompt's validated digit/minus drafts.
@MainActor
@QtBridgeable
public final class IntegerInputPolicy {
    public init() {}

    public func displayedValue(text: String) -> Double {
        Int(text.trimmingCharacters(in: .whitespaces)).map { (value: Int) in Double(value) } ?? .nan
    }

    public func commit(text: String, current: Int, minimum: Int, maximum: Int) -> [String: QVariantSettable] {
        let parsed = Int(text.trimmingCharacters(in: .whitespaces))
        let accepted = parsed.map { (value: Int) in value >= minimum && value <= maximum } ?? false
        let value = accepted ? (parsed ?? current) : current
        return ["accepted": accepted, "value": value, "text": String(value)]
    }

    public func displayText(value: Int) -> String { String(value) }

    public func acceptsPaste(text: String, minimum: Int) -> Bool {
        for (index, scalar) in text.unicodeScalars.enumerated() {
            if (48...57).contains(scalar.value) { continue }
            if scalar == "-", index == 0, minimum < 0 { continue }
            return false
        }
        return true
    }

    public func acceptsCharacter(
        text: String, draft: String, selectedText: String,
        cursor: Int, selectionStart: Int, minimum: Int
    ) -> Bool {
        guard text.utf16.count == 1, let scalar = text.unicodeScalars.first else { return false }
        if (48...57).contains(scalar.value) { return true }
        let replacesStart = selectionStart == 0 && !selectedText.isEmpty
        return scalar == "-" && minimum < 0 && (cursor == 0 || replacesStart)
            && (!draft.utf16.contains(45) || (selectionStart == 0 && selectedText.utf16.contains(45)))
    }
}
