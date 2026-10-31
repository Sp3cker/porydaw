import Foundation
import PorydawAppPresentation
import PorydawPlayback

@testable import PorydawApp

// Qt key and modifier values (qnamespace.h) the keyboard's typing contract names.
private enum Key {
    static let z = 0x5A, s = 0x53, q = 0x51, comma = 0x2C, two = 0x32, zero = 0x30, m = 0x4D
    static let minus = 0x2D, equal = 0x3D, at = 0x40, a = 0x41, space = 0x20
    static let shift = 0x0200_0000, control = 0x0400_0000, alt = 0x0800_0000, keypad = 0x2000_0000
}

@MainActor
public func runVirtualKeyboardChecks(_ report: CheckReport) {
    checkLayout(report.scoped(cppID: "swiftcore/VirtualKeyboard::layout"))
    checkPhysicalKeys(report.scoped(cppID: "swiftcore/VirtualKeyboard::physicalKeys"))
    checkHolders(report.scoped(cppID: "swiftcore/VirtualKeyboard::holders"))
    checkPresenterTyping(report.scoped(cppID: "swiftcore/VirtualKeyboard::typing"))
    checkPresenterMouse(report.scoped(cppID: "swiftcore/VirtualKeyboard::mouse"))
    checkPresenterPersistence(report.scoped(cppID: "swiftcore/VirtualKeyboard::persistence"))
}

private func checkLayout(_ r: CheckReport.Scoped) {
    typealias L = VirtualKeyboardLayout
    r.expectEqual(expected: 28, actual: L.letters.count, what: "28 keys from Z to the D# above 0")
    let whiteCount: Int = (0..<L.span).filter { (offset: Int) -> Bool in !L.isBlack(offset: offset) }.count
    r.expectEqual(expected: 16, actual: whiteCount, what: "16 white keys")
    r.expectEqual(expected: ", Q", actual: L.letters[12], what: "the upper C shows both comma and Q")
    let rawBases: [Int] = [53, 59, -5, 130, 0, 60]
    let roundedBases: [Int] = rawBases.map { (base: Int) -> Int in L.roundBase(base) }
    let expectedBases: [Int] = [48, 48, 0, 108, 0, 60]
    r.expectEqual(expected: expectedBases, actual: roundedBases, what: "bases round down to a C within C-1...C8")
    r.expectEqual(expected: 20, actual: L.playableSpan(base: 108), what: "at C8 only C8...G9 play")
    let middleOctaves: [String] = L.octaveLabels(base: 48).filter { (label: String) -> Bool in !label.isEmpty }
    let expectedMiddle: [String] = ["C3", "C4", "C5"]
    r.expectEqual(expected: expectedMiddle, actual: middleOctaves, what: "each C names its octave with C4 = 60")
    let topOctaves: [String] = L.octaveLabels(base: 108).filter { (label: String) -> Bool in !label.isEmpty }
    let expectedTop: [String] = ["C8", "C9"]
    r.expectEqual(expected: expectedTop, actual: topOctaves, what: "no octave name past G9")
    let width = 330.0
    let height = 120.0
    let lastWhite = L.keyRect(offset: 26, width: width, height: height)
    let topBlack = L.keyRect(offset: 27, width: width, height: height)
    let topBlackRight: Double = topBlack.x + topBlack.width
    let lastWhiteRight: Double = lastWhite.x + lastWhite.width
    r.expect(
        topBlackRight <= width && lastWhiteRight < width,
        message: "the top D# is drawn whole right of the last white key")
    let blackHeight: Double = (height * L.blackHeightRatio).rounded()
    r.expectEqual(
        expected: blackHeight, actual: L.keyRect(offset: 1, width: width, height: height).height,
        what: "black keys cover the upper part of the piano")
    let csharp = L.keyRect(offset: 1, width: width, height: height)
    r.expectEqual(
        expected: 49, actual: L.keyAt(x: csharp.x + 1, y: 2, width: width, height: height, base: 48),
        what: "black keys are hit before the whites under them")
    r.expectEqual(
        expected: 48, actual: L.keyAt(x: csharp.x + 1, y: height - 2, width: width, height: height, base: 48),
        what: "below a black key the white key plays")
    r.expectEqual(
        expected: -1, actual: L.keyAt(x: width - 1, y: height - 2, width: width, height: height, base: 108),
        what: "a faded key past G9 is inert")
    r.expectEqual(
        expected: -1, actual: L.keyAt(x: -1, y: 2, width: width, height: height, base: 48),
        what: "off the piano is no key")
    let minimumHeight: Double = L.minimumPianoHeight(labelHeight: 16, padding: 3, baseFontPx: 13)
    let clearance: Double = minimumHeight * (1 - L.blackHeightRatio)
    r.expect(clearance >= 35, message: "the least height fits a C's two label lines below its black key")
}

private func checkPhysicalKeys(_ r: CheckReport.Scoped) {
    typealias K = VirtualKeyboardKeymap
    func physical(
        _ table: K.Table, _ key: Int, modifiers: Int = 0, scan: UInt32 = 0, virtual: UInt32 = 0
    ) -> Int {
        K.physicalKey(key: key, modifiers: modifiers, nativeScanCode: scan, nativeVirtualKey: virtual, table: table)
    }
    let platforms: [String] = ["xcb", "wayland-egl", "windows", "cocoa", "offscreen", "minimal"]
    let tables: [K.Table] = platforms.map { (name: String) -> K.Table in K.Table(platformName: name) }
    let tableExpected: [K.Table] = [.xkb, .xkb, .windows, .mac, .none, .none]
    r.expectEqual(
        expected: tableExpected, actual: tables,
        what: "each platform plugin names its physical-key source")
    let set1Codes: [UInt32] = [0x2C, 0x1F, 0x33, 0x10, 0x03, 0x0B, 0x32, 0x0C, 0x0D]
    let set1Expected: [Int] = [0, 1, 12, 13, 14, 28, 11, K.octaveDownKey, K.octaveUpKey]
    let set1Actual: [Int] = set1Codes.map { (code: UInt32) -> Int in physical(.windows, Key.a, scan: code) }
    r.expectEqual(
        expected: set1Expected, actual: set1Actual,
        what: "Windows set-1 codes decide alone, whatever key() says")
    let xkbCodes: [UInt32] = [0x34, 0x18, 0x15]
    let xkbActual: [Int] = xkbCodes.map { (code: UInt32) -> Int in physical(.xkb, Key.a, scan: code) }
    r.expectEqual(
        expected: [0, 13, K.octaveUpKey], actual: xkbActual,
        what: "XKB keycodes are the evdev codes plus 8")
    let macCodes: [UInt32] = [0x06, 0x01, 0x2B, 0x0C, 0x13, 0x1D, 0x1B, 0x18]
    let macExpected: [Int] = [0, 1, 12, 13, 14, 28, K.octaveDownKey, K.octaveUpKey]
    let macActual: [Int] = macCodes.map { (code: UInt32) -> Int in physical(.mac, Key.a, scan: 1, virtual: code) }
    r.expectEqual(expected: macExpected, actual: macActual, what: "macOS kVK_ANSI codes name the positions")
    r.expectEqual(
        expected: -1, actual: physical(.mac, Key.z, virtual: 0),
        what: "the Mac never falls back to key(): 0 is kVK_ANSI_A")
    r.expectEqual(
        expected: -1, actual: physical(.windows, Key.z, scan: 0x1E),
        what: "a code the table lacks is no key, never key()'s guess (AZERTY's A position)")
    r.expectEqual(
        expected: 22, actual: physical(.windows, Key.z, scan: 0x15),
        what: "QWERTZ's Z key sits on the US Y position and plays it")
    let usKeys: [Int] = [Key.z, Key.s, Key.comma, Key.q, Key.two, Key.zero, Key.minus, Key.equal]
    let usActual: [Int] = usKeys.map { (key: Int) -> Int in physical(.none, key) }
    r.expectEqual(expected: macExpected, actual: usActual, what: "without native codes the US key() decides")
    let shiftedKeys: [Int] = [Key.at, 0x3C, 0x5F, 0x2B]
    let shiftedActual: [Int] = shiftedKeys.map { (key: Int) -> Int in
        physical(.windows, key, modifiers: Key.shift)
    }
    let shiftedExpected: [Int] = [14, 12, K.octaveDownKey, K.octaveUpKey]
    r.expectEqual(
        expected: shiftedExpected, actual: shiftedActual,
        what: "a zero code falls back, shifted US symbols included")
    r.expectEqual(expected: -1, actual: physical(.none, Key.two, modifiers: Key.keypad), what: "the keypad never plays")
    r.expectEqual(
        expected: [0, 12, 27], actual: [0, 12, 28].map { K.typingOffset(physical: $0) },
        what: "comma and q are both the upper C; 0 is the top D#")
    r.expectEqual(expected: 12, actual: K.typingOffset(physical: 13), what: "q plays the upper C")
    r.expect(
        K.isCommandChord(modifiers: Key.control) && K.isCommandChord(modifiers: Key.alt)
            && !K.isCommandChord(modifiers: Key.shift), message: "Ctrl/Alt/Meta make commands; Shift plays")
}

private func checkHolders(_ r: CheckReport.Scoped) {
    var holders = VirtualKeyboardHolders()
    r.expect(holders.pressTyped(physical: 0, key: 60), message: "the first holder sounds the key")
    r.expect(!holders.pressMouse(key: 60), message: "a clicked C4 over a typed C4 does not retrigger")
    r.expectEqual(expected: 2, actual: holders.holders(60), what: "typed and clicked C4 are two holders")
    r.expect(!holders.releaseTyped(physical: 0), message: "the first release keeps the note")
    r.expect(holders.releaseMouse(), message: "the last release stops it")
    r.expect(
        holders.pressTyped(physical: 12, key: 72) && !holders.pressTyped(physical: 13, key: 72),
        message: "comma and q together sound the upper C once")
    r.expect(!holders.pressTyped(physical: 12, key: 72), message: "a second press of a down key is the same holder")
    r.expect(
        !holders.releaseTyped(physical: 12) && holders.releaseTyped(physical: 13),
        message: "the upper C stops with its last key")
    _ = holders.pressMouse(key: 50)
    r.expect(holders.dragMouse(to: 51) && holders.soundingKeys == [51], message: "a glide releases the previous key")
    r.expect(
        !holders.dragMouse(to: -1) && holders.soundingKeys == [51],
        message: "a gap or faded key keeps the last note sounding")
    _ = holders.pressTyped(physical: 4, key: 52)
    r.expect(holders.releaseAll() && holders.soundingKeys.isEmpty, message: "releasing everything stops every holder")
    r.expect(
        !holders.dragMouse(to: 53) && holders.soundingKeys.isEmpty,
        message: "after releasing everything a drag glides nowhere")
    r.expect(!holders.releaseTyped(physical: 4), message: "a key let go by releaseAll sends nothing on its release")
    r.expect(holders.pressTyped(physical: 4, key: 52), message: "it sounds again when pressed again")
    r.expect(holders.pressMouse(key: 53) && holders.dragMouse(to: 54), message: "a new press restarts the glide")
}

@MainActor
private func makePresenter(_ published: UnsafeMutablePointer<Int>) -> VirtualKeyboardPresenter {
    let presenter = VirtualKeyboardPresenter()
    presenter.publishNotes = { _ in published.pointee += 1 }
    return presenter
}

@MainActor
private func checkPresenterTyping(_ r: CheckReport.Scoped) {
    stagePreferences()
    let published = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    published.initialize(to: 0)
    defer { published.deallocate() }
    let keyboard = makePresenter(published)
    keyboard.configurePlatform(name: "offscreen")
    func press(_ key: Int, _ modifiers: Int = 0, repeated: Bool = false) -> Bool {
        keyboard.keyPressed(
            key: key, modifiers: modifiers, nativeScanCode: 0, nativeVirtualKey: 0, autoRepeat: repeated)
    }
    func release(_ key: Int, _ modifiers: Int = 0, repeated: Bool = false) -> Bool {
        keyboard.keyReleased(
            key: key, modifiers: modifiers, nativeScanCode: 0, nativeVirtualKey: 0, autoRepeat: repeated)
    }
    r.expect(
        keyboard.claimsKey(key: Key.s, modifiers: 0, nativeScanCode: 0, nativeVirtualKey: 0)
            && keyboard.claimsKey(key: Key.minus, modifiers: Key.shift, nativeScanCode: 0, nativeVirtualKey: 0),
        message: "note keys and octave keys (Shift too) are claimed from window shortcuts")
    r.expect(
        !keyboard.claimsKey(key: Key.space, modifiers: 0, nativeScanCode: 0, nativeVirtualKey: 0)
            && !keyboard.claimsKey(key: Key.a, modifiers: 0, nativeScanCode: 0, nativeVirtualKey: 0)
            && !keyboard.claimsKey(key: 0x42, modifiers: Key.alt, nativeScanCode: 0, nativeVirtualKey: 0)
            && !keyboard.claimsKey(key: Key.z, modifiers: Key.control, nativeScanCode: 0, nativeVirtualKey: 0),
        message: "Space, unmapped keys and Ctrl/Alt chords pass through to the shell")
    r.expect(
        press(Key.z) && keyboard.litMask == 1 && keyboard.holders.holders(48) == 1,
        message: "Z plays the base C and lights it")
    r.expect(press(Key.z, repeated: true) && keyboard.holders.holders(48) == 1, message: "auto-repeat changes nothing")
    r.expect(
        press(Key.m) && press(Key.q) && keyboard.holders.soundingKeys == [48, 59, 60],
        message: "chords hold every key")
    r.expect(!press(Key.z, Key.control), message: "a Ctrl chord is a command, not a note")
    r.expect(
        release(Key.m, Key.control) && keyboard.holders.soundingKeys == [48, 60],
        message: "a release stops its note whatever the modifiers")
    r.expect(
        release(Key.z, repeated: true) && keyboard.holders.holders(48) == 1,
        message: "an auto-repeat release keeps the note")
    let before = published.pointee
    r.expect(
        press(Key.equal) && keyboard.base == 60 && keyboard.holders.soundingKeys.isEmpty
            && keyboard.litMask == 0 && published.pointee > before,
        message: "= shifts up an octave after releasing every held note")
    r.expect(
        release(Key.z) && keyboard.holders.soundingKeys.isEmpty,
        message: "a key held through the shift stays silent at its release")
    r.expect(
        press(Key.z) && keyboard.holders.soundingKeys == [60], message: "it plays the new octave when pressed again")
    keyboard.focusLost()
    r.expect(
        keyboard.holders.soundingKeys.isEmpty && keyboard.litMask == 0,
        message: "losing the keys releases everything")
    for _ in 0..<12 { keyboard.shiftOctave(delta: 1) }
    r.expect(
        keyboard.base == 108 && !keyboard.canOctaveUp && keyboard.playableSpan == 20,
        message: "the base stops at C8")
    r.expect(press(Key.two) && keyboard.holders.soundingKeys == [121], message: "C#9 plays at C8")
    r.expect(press(Key.zero) && keyboard.holders.soundingKeys == [121], message: "the D# past G9 is inert")
    for _ in 0..<12 { keyboard.shiftOctave(delta: -1) }
    r.expect(
        keyboard.base == 0 && !keyboard.canOctaveDown && keyboard.octaveText == "C-1",
        message: "the base stops at C-1")
    r.expectEqual(expected: [], actual: keyboard.auditionMembers(), what: "with no target nothing sounds")
    keyboard.dispose()
    r.expect(press(Key.z) && keyboard.holders.soundingKeys.isEmpty, message: "a disposed keyboard sounds nothing")
}

@MainActor
private func checkPresenterMouse(_ r: CheckReport.Scoped) {
    let published = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    published.initialize(to: 0)
    defer { published.deallocate() }
    let keyboard = makePresenter(published)
    let width = 330.0
    let height = 120.0
    func center(_ offset: Int) -> (Double, Double) {
        let rect = VirtualKeyboardLayout.keyRect(offset: offset, width: width, height: height)
        return (rect.x + rect.width / 2, rect.height - 2)
    }
    let c = center(0)
    let d = center(2)
    let e = center(4)
    keyboard.mousePressed(x: c.0, y: c.1, width: width, height: height)
    r.expect(keyboard.holders.soundingKeys == [48] && keyboard.litMask == 1, message: "a press sounds its key")
    keyboard.mouseMoved(x: d.0, y: d.1, width: width, height: height)
    r.expect(keyboard.holders.soundingKeys == [50], message: "a drag glides to the next key")
    keyboard.mouseMoved(x: width + 40, y: d.1, width: width, height: height)
    r.expect(keyboard.holders.soundingKeys == [50], message: "overshooting the edge keeps the note")
    keyboard.mouseReleased()
    r.expect(keyboard.holders.soundingKeys.isEmpty, message: "the release stops it wherever it lands")
    keyboard.mousePressed(x: e.0, y: e.1, width: width, height: height)
    keyboard.shiftOctave(delta: 1)
    keyboard.mouseMoved(x: d.0, y: d.1, width: width, height: height)
    r.expect(keyboard.holders.soundingKeys.isEmpty, message: "an octave shift ends the drag until the next press")
    keyboard.mouseReleased()
}

@MainActor
private func checkPresenterPersistence(_ r: CheckReport.Scoped) {
    stagePreferences()
    let published = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    published.initialize(to: 0)
    defer { published.deallocate() }
    let first = makePresenter(published)
    var visibilityChanges = 0
    first.onVisibilityChanged = { visibilityChanges += 1 }
    first.restoreFromPreferences()
    r.expect(
        !first.visible && first.base == 48 && first.velocity == 100,
        message: "defaults: hidden, base C3, velocity 100")
    first.toggle()
    r.expect(
        first.visible && first.activateOnShow && visibilityChanges == 1,
        message: "the user's toggle shows it and hands it the keys")
    first.shiftOctave(delta: -1)
    first.setVelocity(value: 200)
    r.expectEqual(expected: 127, actual: first.velocity, what: "velocity clamps to 127")
    first.setVelocity(value: 64)
    r.expect(
        !PreferencesStore().hasValue(key: VirtualKeyboardPresenter.velocityKey),
        message: "a velocity drag persists nothing until it settles")
    first.commitVelocity()
    first.persistGeometry(x: 40, y: 60, width: 560, height: 180)
    let second = makePresenter(published)
    second.restoreFromPreferences()
    r.expect(second.visible && !second.activateOnShow, message: "a restored keyboard shows without taking the keys")
    r.expect(
        second.base == 36 && second.octaveText == "C2" && second.velocity == 64,
        message: "octave and velocity persist")
    r.expect(
        second.windowX == 40 && second.windowY == 60 && second.windowWidth == 560 && second.windowHeight == 180,
        message: "the window geometry persists")
    second.closeRequested()
    let third = makePresenter(published)
    third.restoreFromPreferences()
    r.expect(!second.visible && !third.visible, message: "the title bar's close hides it for the next launch too")
    third.toggle()
    third.dispose()
    third.toggle()
    r.expect(
        third.visible && PreferencesStore().bool(key: VirtualKeyboardPresenter.visibleKey, fallback: false),
        message: "closing the app leaves an open keyboard shown for the next launch")
}

@MainActor
private func stagePreferences() {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("porydaw-virtual-keyboard-\(ProcessInfo.processInfo.processIdentifier).plist")
    PreferencesStore.stageShared(plistPath: path.path)
}
