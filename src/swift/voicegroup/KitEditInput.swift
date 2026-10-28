/// The blank sub-voice line shared by empty kit creation and unassigned children.
public let kitBlankChildLine = "\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 0"

/// Distinguishes an undefined-slot precondition from authoritative history replay.
public enum KitParentExpectation: Sendable, Equatable {
    case authoritative
    case parent(VgVoice?)
}

/// One parent-slot, sub-group and optional keysplit-table application.
public struct KitEditInput: Sendable, Equatable {
    public var id: VoicegroupId
    public var slot: Int
    public var parent: VgVoice?
    public var subgroupSymbol: String
    /// Full sub-group content by sub-slot index; nil writes the blank template.
    public var children: [VgVoice?]
    /// Nil for Drumkit mode.
    public var table: KeysplitTable?
    /// Narrow insertion delta used when history restores an undefined parent.
    public var materialization: BlankSlotMaterialization?

    public init(
        id: VoicegroupId, slot: Int, parent: VgVoice?, subgroupSymbol: String,
        children: [VgVoice?], table: KeysplitTable?,
        materialization: BlankSlotMaterialization? = nil
    ) {
        self.id = id
        self.slot = slot
        self.parent = parent
        self.subgroupSymbol = subgroupSymbol
        self.children = children
        self.table = table
        self.materialization = materialization
    }
}

/// Raw kit state read from the same overlays used to build the current bank.
public struct KitSnapshot: Sendable, Equatable {
    public let voicegroup: String
    public let parent: VgVoice?
    public let subgroupSymbol: String
    public let children: [VgVoice?]
    public let table: KeysplitTable?
}

/// Owned PCM and playback metadata resolved through the bank's sample cache.
public struct KitSampleAsset: Sendable, Equatable {
    public let pcm: [Int8]
    public let frequency: UInt32
    public let looped: Bool
    public let loopStart: Int
}

public let kitBlankChildVoice: VgVoice = {
    let text = AsmLine.content(Array(kitBlankChildLine.utf8)[...])
    guard let spec = VoiceMacroSpec.all.first(where: { text.starts(with: $0.prefix) }),
        let voice = try? VoicegroupSource.decode(spec, arguments: text.dropFirst(spec.prefix.count))
    else {
        preconditionFailure("The shared kit blank template must be an editable voice")
    }
    return voice
}()
