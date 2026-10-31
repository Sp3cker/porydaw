/// Who holds each sounding key: the typed physical keys and the mouse. A key's
/// note starts with its first holder and stops with its last, so a C4 typed and
/// clicked at once, or `,` and `q` together, sound once. Every mutation reports
/// whether the set of sounding keys changed.
struct VirtualKeyboardHolders {
    private(set) var counts = [UInt8](repeating: 0, count: 128)
    /// Per physical note key, the MIDI key it holds; -1 when up or let go by `releaseAll`.
    private(set) var typed = [Int](repeating: -1, count: VirtualKeyboardKeymap.noteKeyCount)
    private(set) var mouseKey = -1
    /// `releaseAll` ran since the last press: a drag glides nowhere until pressed again.
    private(set) var dragEnded = false

    func holders(_ key: Int) -> Int { (0..<128).contains(key) ? Int(counts[key]) : 0 }

    /// The sounding keys, ascending.
    var soundingKeys: [Int] { counts.indices.filter { counts[$0] > 0 } }

    /// A typed note key goes down. A second press of a key already down (its release
    /// went elsewhere) is the same holder.
    mutating func pressTyped(physical: Int, key: Int) -> Bool {
        guard (0..<typed.count).contains(physical), typed[physical] < 0, (0..<128).contains(key) else {
            return false
        }
        typed[physical] = key
        return hold(key)
    }

    /// A typed note key comes up, whatever the modifiers by now.
    mutating func releaseTyped(physical: Int) -> Bool {
        guard (0..<typed.count).contains(physical), typed[physical] >= 0 else { return false }
        let key = typed[physical]
        typed[physical] = -1
        return unhold(key)
    }

    /// A press: one mouse note at a time, so a held one (a lost release) goes first.
    /// `key` is -1 off the playable keys.
    mutating func pressMouse(key: Int) -> Bool {
        var changed = releaseMouse()
        dragEnded = false
        guard (0..<128).contains(key) else { return changed }
        mouseKey = key
        changed = hold(key) || changed
        return changed
    }

    /// A glide: another playable key takes over; a gap, a faded key or off the
    /// piano keeps the last note sounding.
    mutating func dragMouse(to key: Int) -> Bool {
        guard !dragEnded, (0..<128).contains(key), key != mouseKey else { return false }
        var changed = releaseMouse()
        mouseKey = key
        changed = hold(key) || changed
        return changed
    }

    mutating func releaseMouse() -> Bool {
        guard mouseKey >= 0 else { return false }
        let key = mouseKey
        mouseKey = -1
        return unhold(key)
    }

    /// Every note stops; typed keys still down and the drag stay silent until pressed again.
    mutating func releaseAll() -> Bool {
        for index in typed.indices { typed[index] = -1 }
        mouseKey = -1
        dragEnded = true
        var changed = false
        for key in counts.indices where counts[key] > 0 {
            counts[key] = 0
            changed = true
        }
        return changed
    }

    private mutating func hold(_ key: Int) -> Bool {
        counts[key] += 1
        return counts[key] == 1
    }

    private mutating func unhold(_ key: Int) -> Bool {
        guard counts[key] > 0 else { return false }
        counts[key] -= 1
        return counts[key] == 0
    }
}
