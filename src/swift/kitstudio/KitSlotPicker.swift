import PorydawVoicegroup
import QtBridge

/// The kinds offered by the Split Studio slot picker.
public enum KitSlotKind: String, Sendable { case drumkit, keysplit, empty }

/// Parsed kit facts supplied by the workflow, without project access.
public struct KitLoadResult: Sendable {
    public var kind: KitSlotKind
    public var parent: VgVoice?
    public var children: [VgVoice?]
    public var table: KeysplitTable?
    public var usageSections: [String]

    public init(
        kind: KitSlotKind, parent: VgVoice? = nil, children: [VgVoice?] = [],
        table: KeysplitTable? = nil, usageSections: [String] = []
    ) {
        self.kind = kind
        self.parent = parent
        self.children = children
        self.table = table
        self.usageSections = usageSections
    }
}

@MainActor
@QtBridgeable
public final class KitSlotRow: QmlUncreatable {
    public let slot: Int
    public let kind: String
    public let title: String
    public let isNew: Bool
    public let selected: Bool

    init(slot: Int, kind: KitSlotKind, selected: Bool) {
        self.slot = slot
        self.kind = kind.rawValue
        isNew = kind == .empty
        title =
            isNew ? "New kit in empty slot \(slot)…" : "Voice \(slot) · \(kind == .drumkit ? "Drumkit" : "Keysplit")"
        self.selected = selected
    }

}

/// Owns selection and pending retargets, not kit loading or persistence.
@MainActor
public final class KitSlotPicker {
    enum Selection {
        case unchanged, prompt
        case load(Int, KitSlotKind)
    }

    private var slots: [(slot: Int, kind: KitSlotKind)] = []
    public private(set) var selectedSlot: Int?
    public private(set) var pendingSlot: Int?

    public init() {}

    /// Only explicitly undefined slots become new-kit offers; non-kit voices are never offered.
    public func bind(voices: [VgVoice?], undefinedSlots: Set<Int>, slot: Int) {
        refresh(voices: voices, undefinedSlots: undefinedSlots)
        selectedSlot = slots.contains(where: { $0.slot == slot }) ? slot : nil
        pendingSlot = nil
    }

    /// Replaces bank facts without changing the current or pending target.
    func refresh(voices: [VgVoice?], undefinedSlots: Set<Int>) {
        slots = (0..<128).compactMap { (index: Int) -> (slot: Int, kind: KitSlotKind)? in
            guard index < voices.count, let voice = voices[index] else {
                return undefinedSlots.contains(index) ? (index, .empty) : nil
            }
            switch voice.macro {
            case .keysplitAll: return (index, .drumkit)
            case .keysplit: return (index, .keysplit)
            default: return nil
            }
        }
    }

    // Existing rows must be ordered by ascending slot, like slots.
    func rows(existing: QListModel<KitSlotRow>) -> [KitSlotRow] {
        var existingIndex = 0
        return slots.map { (entry: (slot: Int, kind: KitSlotKind)) -> KitSlotRow in
            while existingIndex < existing.count && existing[existingIndex].slot < entry.slot {
                existingIndex += 1
            }
            let selected = entry.slot == selectedSlot
            if existingIndex < existing.count {
                let row = existing[existingIndex]
                if row.slot == entry.slot && row.kind == entry.kind.rawValue && row.selected == selected {
                    return row
                }
            }
            return KitSlotRow(slot: entry.slot, kind: entry.kind, selected: selected)
        }
    }

    func select(row: Int, dirty: Bool) -> Selection {
        guard slots.indices.contains(row), slots[row].slot != selectedSlot else { return .unchanged }
        if dirty {
            pendingSlot = slots[row].slot
            return .prompt
        }
        return .load(slots[row].slot, slots[row].kind)
    }

    func pendingTarget() -> (slot: Int, kind: KitSlotKind)? {
        slots.first { $0.slot == pendingSlot }
    }

    func selectedKind() -> KitSlotKind? {
        slots.first { $0.slot == selectedSlot }?.kind
    }

    func commit(slot: Int, kind: KitSlotKind) {
        selectedSlot = slot
        markSaved(kind: kind)
        pendingSlot = nil
    }

    func markSaved(kind: KitSlotKind) {
        guard let slot = selectedSlot, let index = slots.firstIndex(where: { $0.slot == slot }) else { return }
        slots[index].kind = kind
    }

    func cancel() { pendingSlot = nil }
}
