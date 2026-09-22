/// A changed Qt pointer button decoded once at the page boundary.
enum DrawerPointerButton: Hashable, Sendable {
    case none
    case primary
    case secondary
    case middle
    case other(Int)

    init(qtButton: Int) {
        switch qtButton {
        case 0: self = .none
        case 1: self = .primary
        case 2: self = .secondary
        case 4: self = .middle
        default: self = .other(qtButton)
        }
    }
}

/// The buttons held during a pointer event. This is intentionally distinct
/// from the button whose state changed on a press or release.
struct DrawerPointerButtons: Equatable, Sendable {
    private(set) var held: Set<DrawerPointerButton>

    init(_ held: Set<DrawerPointerButton> = []) {
        self.held = held
    }

    init(qtButtons: Int) {
        let raw = UInt(bitPattern: qtButtons)
        var decoded: Set<DrawerPointerButton> = []
        if raw & 1 != 0 { decoded.insert(.primary) }
        if raw & 2 != 0 { decoded.insert(.secondary) }
        if raw & 4 != 0 { decoded.insert(.middle) }

        var remaining = raw & ~UInt(7)
        while remaining != 0 {
            let bit = remaining & ((~remaining) &+ 1)
            decoded.insert(.other(Int(bitPattern: bit)))
            remaining &= ~bit
        }
        held = decoded
    }

    func contains(_ button: DrawerPointerButton) -> Bool {
        held.contains(button)
    }
}

/// Semantic shortcut modifiers decoded from Qt's modifier flags.
struct DrawerModifiers: Equatable, Sendable {
    static let shiftBit = 0x0200_0000
    static let controlBit = 0x0400_0000
    static let altBit = 0x0800_0000
    static let metaBit = 0x1000_0000

    var shift: Bool
    var control: Bool
    var alt: Bool
    var meta: Bool

    init(shift: Bool = false, control: Bool = false, alt: Bool = false,
         meta: Bool = false) {
        self.shift = shift
        self.control = control
        self.alt = alt
        self.meta = meta
    }

    init(qtModifiers: Int) {
        shift = qtModifiers & Self.shiftBit != 0
        control = qtModifiers & Self.controlBit != 0
        alt = qtModifiers & Self.altBit != 0
        meta = qtModifiers & Self.metaBit != 0
    }

    /// Exact shortcut membership. Non-shortcut Qt bits do not affect it.
    func isExact(shift: Bool = false, control: Bool = false,
                 alt: Bool = false, meta: Bool = false) -> Bool {
        self.shift == shift && self.control == control
            && self.alt == alt && self.meta == meta
    }
}

extension AutomationModifiers {
    /// The single DrawerModifiers→AutomationModifiers mapping; every domain call
    /// site and check helper decodes through this initializer.
    init(_ modifiers: DrawerModifiers) {
        self.init(fine: modifiers.alt, snapValue: modifiers.control, shift: modifiers.shift)
    }
}

enum DrawerPointerPhase: Sendable {
    case press
    case move
    case release
    case leave
}

/// One pointer event after Qt button and modifier integers have been decoded.
/// Domain-specific surface meanings remain with the receiving drawer domain.
struct DrawerPointerInput: Sendable {
    var x: Double
    var y: Double
    var changedButton: DrawerPointerButton
    var heldButtons: DrawerPointerButtons
    var modifiers: DrawerModifiers
    var phase: DrawerPointerPhase

    init(x: Double, y: Double, changedButton: DrawerPointerButton = .none,
         heldButtons: DrawerPointerButtons = DrawerPointerButtons(),
         modifiers: DrawerModifiers = DrawerModifiers(), phase: DrawerPointerPhase) {
        self.x = x
        self.y = y
        self.changedButton = changedButton
        self.heldButtons = heldButtons
        self.modifiers = modifiers
        self.phase = phase
    }

    init(x: Double, y: Double, qtButton: Int = 0, qtButtons: Int = 0,
         qtModifiers: Int = 0, phase: DrawerPointerPhase) {
        self.init(x: x, y: y, changedButton: DrawerPointerButton(qtButton: qtButton),
                  heldButtons: DrawerPointerButtons(qtButtons: qtButtons),
                  modifiers: DrawerModifiers(qtModifiers: qtModifiers), phase: phase)
    }
}
