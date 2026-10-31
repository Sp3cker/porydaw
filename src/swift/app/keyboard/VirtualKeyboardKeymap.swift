/// Which physical computer key a key event is, by US-layout position, so AZERTY
/// and QWERTZ play the same rows. Physical keys 0..<29 are the note keys
/// z s x d c v g b h n j m , (offsets 0-12) then q 2 w 3 e r 5 t 6 y 7 u i 9 o 0
/// (offsets 12-27); 29 and 30 are the octave keys - and =.
enum VirtualKeyboardKeymap {
    static let noteKeyCount = 29
    static let octaveDownKey = noteKeyCount
    static let octaveUpKey = noteKeyCount + 1
    static let physicalKeyCount = noteKeyCount + 2

    /// Where a platform's key events name the physical key: XKB keycodes (xcb,
    /// Wayland), PS/2 set-1 scan codes (Windows), macOS virtual key codes, or none.
    enum Table: Equatable {
        case none, xkb, windows, mac

        /// The table for a Qt platform plugin name; fixed for the run.
        init(platformName: String) {
            if platformName == "xcb" || platformName.hasPrefix("wayland") {
                self = .xkb
            } else if platformName == "windows" {
                self = .windows
            } else if platformName == "cocoa" {
                self = .mac
            } else {
                self = .none
            }
        }
    }

    // Qt's key and modifier values (qnamespace.h); Swift's Qt importer cannot name them.
    static let shiftModifier = 0x0200_0000
    static let controlModifier = 0x0400_0000
    static let altModifier = 0x0800_0000
    static let metaModifier = 0x1000_0000
    static let keypadModifier = 0x2000_0000

    /// PS/2 set 1 as Windows reports it; evdev codes match, and XKB adds 8.
    private static let set1: [UInt32] = [
        0x2C, 0x1F, 0x2D, 0x20, 0x2E, 0x2F, 0x22, 0x30, 0x23, 0x31, 0x24, 0x32, 0x33, 0x10, 0x03, 0x11,
        0x04, 0x12, 0x13, 0x06, 0x14, 0x07, 0x15, 0x08, 0x16, 0x17, 0x0A, 0x18, 0x0B, 0x0C, 0x0D,
    ]
    private static let xkbOffset: UInt32 = 8
    /// macOS kVK_ANSI_* codes, which name ANSI positions whatever the layout.
    private static let macAnsi: [UInt32] = [
        0x06, 0x01, 0x07, 0x02, 0x08, 0x09, 0x05, 0x0B, 0x04, 0x2D, 0x26, 0x2E, 0x2B, 0x0C, 0x13, 0x0D,
        0x14, 0x0E, 0x0F, 0x17, 0x11, 0x16, 0x10, 0x1A, 0x20, 0x22, 0x19, 0x1F, 0x1D, 0x1B, 0x18,
    ]
    /// Qt key() on a US layout: Z S X D C V G B H N J M , Q 2 W 3 E R 5 T 6 Y 7 U I 9 O 0 - =.
    private static let usKeys: [Int] = [
        0x5A, 0x53, 0x58, 0x44, 0x43, 0x56, 0x47, 0x42, 0x48, 0x4E, 0x4A, 0x4D, 0x2C, 0x51, 0x32, 0x57,
        0x33, 0x45, 0x52, 0x35, 0x54, 0x36, 0x59, 0x37, 0x55, 0x49, 0x39, 0x4F, 0x30, 0x2D, 0x3D,
    ]
    /// Shift+key's key() on a US layout where it differs: < @ # % ^ & ( ) _ +.
    private static let usShifted: [(key: Int, physical: Int)] = [
        (0x3C, 12), (0x40, 14), (0x23, 16), (0x25, 19), (0x5E, 21), (0x26, 23), (0x28, 26), (0x29, 28),
        (0x5F, octaveDownKey), (0x2B, octaveUpKey),
    ]

    /// A note key's semitones above the base C (comma and q are both 12).
    static func typingOffset(physical: Int) -> Int { physical < 13 ? physical : physical - 1 }

    /// Ctrl/Alt/Meta make a command, never a note; Shift plays the plain key.
    static func isCommandChord(modifiers: Int) -> Bool {
        modifiers & (controlModifier | altModifier | metaModifier) != 0
    }

    /// The physical key, or -1. A scan-code table's non-zero code decides alone (a code
    /// it lacks is no key: key() would read AZERTY's A position as Q); a zero code and
    /// `.none` fall back to the US key() and its shifted symbols, never the keypad. The
    /// Mac never falls back: 0 is kVK_ANSI_A.
    static func physicalKey(
        key: Int, modifiers: Int, nativeScanCode: UInt32, nativeVirtualKey: UInt32, table: Table
    ) -> Int {
        switch table {
        case .mac:
            return macAnsi.firstIndex(of: nativeVirtualKey) ?? -1
        case .xkb where nativeScanCode != 0:
            return set1.firstIndex(of: nativeScanCode &- xkbOffset) ?? -1
        case .windows where nativeScanCode != 0:
            return set1.firstIndex(of: nativeScanCode) ?? -1
        case .xkb, .windows, .none:
            break
        }
        guard modifiers & keypadModifier == 0 else { return -1 }
        if let physical = usKeys.firstIndex(of: key) { return physical }
        return usShifted.first { $0.key == key }?.physical ?? -1
    }
}
