import PorydawApp

// Values from Qt 6.11 qnamespace.h. The Qt enum cases are not imported by the
// Swift Clang module, so these retain the native Qt integer contract directly.
private enum QtKeyCode: Int {
    case backspace = 0x0100_0003
    case delete = 0x0100_0007
    case up = 0x0100_0013
    case space = 0x20
    case b = 0x42
    case c = 0x43
    case d = 0x44
    case g = 0x47
    case i = 0x49
    case m = 0x4d
    case s = 0x53
    case u = 0x55
}

private enum QtKeyboardModifier: Int {
    case none = 0x0000_0000
    case shift = 0x0200_0000
    case control = 0x0400_0000
    case alt = 0x0800_0000
    case keypad = 0x2000_0000
}

/// Runs the native `keymapregistry.cpp` assertion inventory against the
/// production registry and reports every result to the caller.
public func runKeybindingRegistryChecks(
    onAssertion: (Bool, String, String) -> Void
) {
    let registry = KeybindingRegistry()
    let settingsSeeds = "KeymapCheckTest::keymapSettingsSeedsAreIgnored"

    onAssertion(
        registry.sequences("roll.transpose_up").map(\.strokes) == [[QtKeyCode.up.rawValue]],
        settingsSeeds,
        "transpose-up remains the shipped Up sequence")
    onAssertion(
        !registry.matches(QtKeyCode.u.rawValue,
                          QtKeyboardModifier.control.rawValue | QtKeyboardModifier.alt.rawValue,
                          "roll.transpose_up"),
        settingsSeeds,
        "Ctrl+Alt+U does not replace transpose-up")
    onAssertion(
        registry.matches(QtKeyCode.up.rawValue, QtKeyboardModifier.none.rawValue,
                         "roll.transpose_up"),
        settingsSeeds,
        "Up remains transpose-up")
    onAssertion(
        registry.sequences("transport.play_pause").map(\.strokes) == [[QtKeyCode.space.rawValue]],
        settingsSeeds,
        "play-pause remains the shipped Space sequence")
    onAssertion(
        registry.matches(QtKeyCode.space.rawValue, QtKeyboardModifier.none.rawValue,
                         "transport.play_pause"),
        settingsSeeds,
        "Space remains play-pause")
    onAssertion(
        !registry.matchesModifier(QtKeyboardModifier.shift.rawValue, "roll.velocity_drag"),
        settingsSeeds,
        "Shift alone does not arm velocity drag")
    onAssertion(
        registry.matchesModifier(QtKeyboardModifier.control.rawValue, "roll.velocity_drag"),
        settingsSeeds,
        "Control still arms velocity drag")
    onAssertion(
        registry.matchesModifier(QtKeyboardModifier.control.rawValue, "velocity.detent_unlock"),
        settingsSeeds,
        "Control still arms detent unlock")

    let defaultMatching = "KeymapCheckTest::defaultMatching"
    let rows: [(name: String, id: String, key: Int, modifiers: Int, expected: Bool)] = [
        ("semitone-up", "roll.transpose_up", QtKeyCode.up.rawValue, QtKeyboardModifier.none.rawValue, true),
        ("shift-not-semitone", "roll.transpose_up", QtKeyCode.up.rawValue, QtKeyboardModifier.shift.rawValue, false),
        ("octave-up", "roll.transpose_up_octave", QtKeyCode.up.rawValue, QtKeyboardModifier.shift.rawValue, true),
        ("keypad-up", "roll.transpose_up", QtKeyCode.up.rawValue, QtKeyboardModifier.keypad.rawValue, true),
        ("delete", "roll.delete", QtKeyCode.delete.rawValue, QtKeyboardModifier.none.rawValue, true),
        ("backspace", "roll.delete", QtKeyCode.backspace.rawValue, QtKeyboardModifier.none.rawValue, true),
        ("copy", "roll.copy", QtKeyCode.c.rawValue, QtKeyboardModifier.control.rawValue, true),
        ("mute", "roll.mute_tracks", QtKeyCode.m.rawValue, QtKeyboardModifier.none.rawValue, true),
        ("control-not-mute", "roll.mute_tracks", QtKeyCode.m.rawValue, QtKeyboardModifier.control.rawValue, false),
        ("solo", "roll.solo_tracks", QtKeyCode.s.rawValue, QtKeyboardModifier.none.rawValue, true),
        ("automation-pencil", "automation.pencil_mode", QtKeyCode.b.rawValue, QtKeyboardModifier.none.rawValue, true),
        ("pitch-bend", "roll.pitch_bend", QtKeyCode.g.rawValue, QtKeyboardModifier.none.rawValue, true),
        ("play-pause", "transport.play_pause", QtKeyCode.space.rawValue, QtKeyboardModifier.none.rawValue, true),
        ("control-not-play-pause", "transport.play_pause", QtKeyCode.space.rawValue, QtKeyboardModifier.control.rawValue, false),
        ("insert-time", "edit.insert_time", QtKeyCode.i.rawValue,
         QtKeyboardModifier.control.rawValue | QtKeyboardModifier.shift.rawValue, true),
        ("duplicate-time", "roll.duplicate_time", QtKeyCode.d.rawValue,
         QtKeyboardModifier.control.rawValue, true),
    ]
    for row in rows {
        onAssertion(
            row.expected == registry.matches(row.key, row.modifiers, row.id),
            defaultMatching,
            row.name)
    }

    let modifierChords = "KeymapCheckTest::modifierChords"
    onAssertion(
        registry.matchesModifier(QtKeyboardModifier.control.rawValue, "velocity.detent_unlock"),
        modifierChords,
        "Control arms detent unlock")
    onAssertion(
        registry.matchesModifier(QtKeyboardModifier.control.rawValue, "roll.velocity_drag"),
        modifierChords,
        "Control arms velocity drag")
    onAssertion(
        registry.matchesModifier(QtKeyboardModifier.control.rawValue |
                                QtKeyboardModifier.keypad.rawValue,
                                "roll.velocity_drag"),
        modifierChords,
        "Control plus Keypad arms velocity drag")
    onAssertion(
        !registry.matchesModifier(QtKeyboardModifier.control.rawValue |
                                 QtKeyboardModifier.shift.rawValue,
                                 "roll.velocity_drag"),
        modifierChords,
        "Control plus Shift does not arm velocity drag")
}
