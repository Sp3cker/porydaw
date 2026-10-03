import PorydawSample

/// Parameter history confined to one Sample Studio dialog.
@MainActor
public struct SampleStudioHistory {
    private struct Entry {
        let before: SampleEditParams
        var after: SampleEditParams
        let mergeKey: Int
    }

    private var entries: [Entry] = []
    private var position = 0

    public var canUndo: Bool { position > 0 }
    public var canRedo: Bool { position < entries.count }
    public var undoCount: Int { position }

    public mutating func push(before: SampleEditParams, after: SampleEditParams, mergeKey: Int) {
        guard before != after else { return }
        if position < entries.count { entries.removeSubrange(position...) }
        if mergeKey >= 0, position > 0, entries[position - 1].mergeKey == mergeKey {
            entries[position - 1].after = after
            if entries[position - 1].before == after {
                entries.removeLast()
                position -= 1
            }
        } else {
            entries.append(Entry(before: before, after: after, mergeKey: mergeKey))
            position += 1
        }
    }

    public mutating func undo() -> SampleEditParams? {
        guard canUndo else { return nil }
        position -= 1
        return entries[position].before
    }

    public mutating func redo() -> SampleEditParams? {
        guard canRedo else { return nil }
        defer { position += 1 }
        return entries[position].after
    }
}
