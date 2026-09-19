// EditCommands.swift — Swift port of the canonical EditCommandPolicy table
// (src/ui/songview/editcommandtable.cpp, the production oracle). Pure frozen
// data: the policy column of CommandRow only — keymap id, checkable,
// windowObjectName and delivery stay host-side and are not mirrored here.
// Rows are frozen against the C++ table; a mismatch is a defect report
// (spec §3.3), never a silent edit. The sgp_* parity sweep
// (PolicySelftest.swift) locks every field of every row against production.

/// Mirrors `SongView::EditCommand` (src/ui/songview.h): 35 values in
/// declaration order, copy = 0 … gridTriplet = 34.
public enum EditCommand: Int, CaseIterable, Sendable {
    case copy = 0
    case cut
    case duplicate
    case paste
    case selectAll
    case delete
    case pitchBend
    case transposeUp
    case transposeDown
    case transposeUpOctave
    case transposeDownOctave
    case nudgeLeft
    case nudgeRight
    case muteTracks
    case soloTracks
    case insertTime
    case deleteTime
    case clearTimeSelection
    case setVelocity
    case setLoopStart
    case setLoopEnd
    case loopFromSelection
    case removeLoop
    case editTimeSignature
    case removeTimeSignature
    case pencilMode
    case moveEventUp
    case moveEventDown
    case split
    case join
    case lengthenNote
    case shortenNote
    case gridNarrow
    case gridWiden
    case gridTriplet = 34
}

/// Mirrors `EditRangeOperation` (editactions.h).
public enum EditRangeOperation: Int, Sendable {
    case none, copySelection, cut, duplicate, delete, transpose, nudge, insertTime, removeContents,
        clearTimeSelection, loopFromSelection
}

/// Mirrors `EditNotesOperation` (editactions.h).
public enum EditNotesOperation: Int, Sendable {
    case none, copySelection, cut, delete, transpose, nudge, selectAll, pitchBend, setVelocity,
        duplicate, split, join, lengthen, shorten
}

/// Mirrors `EditStandaloneOperation` (editactions.h).
public enum EditStandaloneOperation: Int, Sendable {
    case none, paste, muteTracks, soloTracks, insertTime, pencilToggle, moveEventRow, setLoopStart,
        setLoopEnd, removeLoop, editTimeSignature, removeTimeSignature, gridNarrow, gridWiden,
        gridTriplet
}

/// Mirrors `EditDeliveryClass` (editactions.h); explicit C++ values kept.
public enum EditDeliveryClass: Int {
    case editorRouted = 1
    case window = 2
}

/// Mirrors `EditKeyRoute` (editactions.h).
public enum EditKeyRoute: Int, Sendable {
    case selectionTargeted, alwaysConsume, availabilityGated
}

/// Mirrors `EditAutoRepeatRule` (editactions.h).
public enum EditAutoRepeatRule: Int, Sendable {
    case reexecute, consumeWhenEligible
}

/// Mirrors `EditKeyOwnershipOnUnavailable` (editactions.h).
public enum EditKeyOwnershipOnUnavailable: Int, Sendable {
    case resolvedByRow, ownsKey
}

/// Mirrors `EditOriginRule` (editactions.h).
public enum EditOriginRule: Int, Sendable {
    case anyOrigin, eventListOnly, timelineOnly
}

/// Mirrors `EditFocusedTextOwnership` (editactions.h).
public enum EditFocusedTextOwnership: Int, Sendable {
    case none, copy, solo
}

/// One policy row of the canonical command table: `command` plus the 13
/// `EditCommandPolicy` fields under their C++ names (the 14 fields the
/// `sgp_*` row carries). Defaults mirror the C++ in-class initializers.
public struct EditCommandPolicy: Sendable {
    public var command: EditCommand
    public var rangeOperation: EditRangeOperation = .none
    public var notesOperation: EditNotesOperation = .none
    public var standaloneOperation: EditStandaloneOperation = .none
    public var keyRoute: EditKeyRoute = .selectionTargeted
    public var originRule: EditOriginRule = .anyOrigin
    public var autoRepeatRule: EditAutoRepeatRule = .reexecute
    public var ownershipOnUnavailable: EditKeyOwnershipOnUnavailable = .resolvedByRow
    public var transposeSemitones: Int = 0
    public var nudgeDelta: Int = 0
    public var eventRowDelta: Int = 0
    public var survivesPointerGesture: Bool = false
    public var terminalWhenUnmatched: Bool = false
    public var focusedTextOwnership: EditFocusedTextOwnership = .none
}

// Row helpers mirror the C++ constexpr builders verbatim: same field sets,
// same comments. Lane-scoped Up/Down is an ineligible mutation, not a
// foreign key: the selection owns it as a consumed no-op.
private func transposeRow(_ command: EditCommand, _ semitones: Int) -> EditCommandPolicy {
    EditCommandPolicy(
        command: command,
        rangeOperation: .transpose,
        notesOperation: .transpose,
        ownershipOnUnavailable: .ownsKey,
        transposeSemitones: semitones)
}

private func nudgeRow(_ command: EditCommand, _ delta: Int) -> EditCommandPolicy {
    EditCommandPolicy(
        command: command,
        rangeOperation: .nudge,
        notesOperation: .nudge,
        nudgeDelta: delta)
}

// One production row shape for the seven unbound cursor/marker/signature
// commands beside transpose/nudge/event: all are EditorRouted, availability
// is their only gate, and keys consume unconditionally once eligible. Each
// row names its vocabulary operation explicitly — without one, availability
// falls through every switch and the command is dead.
private func unboundRow(
    _ command: EditCommand,
    range: EditRangeOperation = .none,
    notes: EditNotesOperation = .none,
    standalone: EditStandaloneOperation = .none
) -> EditCommandPolicy {
    EditCommandPolicy(
        command: command,
        rangeOperation: range,
        notesOperation: notes,
        standaloneOperation: standalone,
        keyRoute: .alwaysConsume)
}

private func eventRow(_ command: EditCommand, _ delta: Int) -> EditCommandPolicy {
    EditCommandPolicy(
        command: command,
        standaloneOperation: .moveEventRow,
        keyRoute: .alwaysConsume,
        originRule: .eventListOnly,
        eventRowDelta: delta)
}

/// The canonical command table: one row per EditCommand value, in enum
/// order — the policy column of the production `kCommandTable`, frozen.
public let editCommandTable: [EditCommandPolicy] = [
    EditCommandPolicy(
        command: .copy,
        rangeOperation: .copySelection,
        notesOperation: .copySelection,
        keyRoute: .alwaysConsume,
        focusedTextOwnership: .copy),
    EditCommandPolicy(
        command: .cut,
        rangeOperation: .cut,
        notesOperation: .cut),
    EditCommandPolicy(
        command: .duplicate,
        rangeOperation: .duplicate,
        notesOperation: .duplicate,
        terminalWhenUnmatched: true),
    EditCommandPolicy(
        command: .paste,
        standaloneOperation: .paste,
        keyRoute: .alwaysConsume),
    EditCommandPolicy(
        command: .selectAll,
        notesOperation: .selectAll),
    EditCommandPolicy(
        command: .delete,
        rangeOperation: .delete,
        notesOperation: .delete),
    EditCommandPolicy(
        command: .pitchBend,
        notesOperation: .pitchBend,
        autoRepeatRule: .consumeWhenEligible),
    transposeRow(.transposeUp, 1),
    transposeRow(.transposeDown, -1),
    transposeRow(.transposeUpOctave, 12),
    transposeRow(.transposeDownOctave, -12),
    nudgeRow(.nudgeLeft, -1),
    nudgeRow(.nudgeRight, 1),
    EditCommandPolicy(
        command: .muteTracks,
        standaloneOperation: .muteTracks,
        keyRoute: .alwaysConsume),
    EditCommandPolicy(
        command: .soloTracks,
        standaloneOperation: .soloTracks,
        keyRoute: .alwaysConsume,
        focusedTextOwnership: .solo),
    EditCommandPolicy(
        command: .insertTime,
        rangeOperation: .insertTime,
        standaloneOperation: .insertTime,
        keyRoute: .alwaysConsume),
    EditCommandPolicy(
        command: .deleteTime,
        rangeOperation: .removeContents,
        keyRoute: .alwaysConsume),
    EditCommandPolicy(
        command: .clearTimeSelection,
        rangeOperation: .clearTimeSelection,
        keyRoute: .alwaysConsume),
    // Commands whose operation arm resolves from cursor/marker/signature
    // state: availability is the only gate, so keys consume unconditionally
    // once eligible.
    unboundRow(.setVelocity, notes: .setVelocity),
    unboundRow(.setLoopStart, standalone: .setLoopStart),
    unboundRow(.setLoopEnd, standalone: .setLoopEnd),
    unboundRow(.loopFromSelection, range: .loopFromSelection),
    unboundRow(.removeLoop, standalone: .removeLoop),
    unboundRow(.editTimeSignature, standalone: .editTimeSignature),
    unboundRow(.removeTimeSignature, standalone: .removeTimeSignature),
    EditCommandPolicy(
        command: .pencilMode,
        standaloneOperation: .pencilToggle,
        keyRoute: .availabilityGated,
        autoRepeatRule: .consumeWhenEligible,
        survivesPointerGesture: true),
    eventRow(.moveEventUp, -1),
    eventRow(.moveEventDown, 1),
    EditCommandPolicy(
        command: .split,
        notesOperation: .split),
    EditCommandPolicy(
        command: .join,
        notesOperation: .join),
    EditCommandPolicy(
        command: .lengthenNote,
        notesOperation: .lengthen),
    EditCommandPolicy(
        command: .shortenNote,
        notesOperation: .shorten),
    EditCommandPolicy(
        command: .gridNarrow,
        standaloneOperation: .gridNarrow,
        keyRoute: .alwaysConsume,
        originRule: .timelineOnly),
    EditCommandPolicy(
        command: .gridWiden,
        standaloneOperation: .gridWiden,
        keyRoute: .alwaysConsume,
        originRule: .timelineOnly),
    EditCommandPolicy(
        command: .gridTriplet,
        standaloneOperation: .gridTriplet,
        keyRoute: .availabilityGated,
        originRule: .timelineOnly,
        // Toggling feel re-lattices the drag's snap positions, so it
        // stays gesture-gated; repeats consume without retoggling.
        autoRepeatRule: .consumeWhenEligible),
]

/// The policy row of one command, read out of the canonical table.
public func editCommandPolicy(_ command: EditCommand) -> EditCommandPolicy {
    editCommandTable[command.rawValue]
}
