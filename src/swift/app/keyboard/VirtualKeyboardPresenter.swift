import Foundation
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import PorydawPlayback
import QtBridge

/// The Virtual MIDI Keyboard: a floating tool window whose piano plays the selected
/// track's voice from the mouse and, while the window has the keys, the computer
/// keyboard. It owns its held notes; every path that could lose a release (focus
/// loss, hiding, an octave shift, a new target, closing) stops them all first.
@MainActor
@QtBridgeable
public final class VirtualKeyboardPresenter: QmlUncreatable {
    public let keyCount: Int = VirtualKeyboardLayout.span
    public var keyLetters: [String] = VirtualKeyboardLayout.letters
    @QtTracked public var visible = false
    /// Whether showing takes the keys: the user's toggle does, startup's restore does not.
    @QtTracked public var activateOnShow = false
    public var base: Int = VirtualKeyboardLayout.defaultBase
    public var octaveText: String = midiKeyName(VirtualKeyboardLayout.defaultBase)
    @QtTracked public var canOctaveDown = true
    @QtTracked public var canOctaveUp = true
    /// Offsets at or past this are above G9: drawn faded, inert.
    public var playableSpan: Int = VirtualKeyboardLayout.span
    public var octaveLabels: [String] = VirtualKeyboardLayout.octaveLabels(
        base: VirtualKeyboardLayout.defaultBase)
    public var velocity: Int = VirtualKeyboardPresenter.defaultVelocity
    public var targetText: String = VirtualKeyboardPresenter.noSongText
    /// Bit `offset` lights the key `base + offset`.
    @QtTracked public var litMask = 0
    @QtTracked public var windowX = -1
    @QtTracked public var windowY = -1
    @QtTracked public var windowWidth = -1
    @QtTracked public var windowHeight = -1

    @QtIgnored var onVisibilityChanged: (() -> Void)?
    /// The audible sink: the held keys as identity-based audition members.
    @QtIgnored var publishNotes: ([BandAuditionNote]) -> Void = { _ in }
    private(set) var holders = VirtualKeyboardHolders()
    private(set) var keyTable = VirtualKeyboardKeymap.Table.none
    private(set) var targetTrack: Int?
    private weak var session: DocumentSession?
    private var savedVelocity: Int?
    private var disposed = false

    nonisolated static let defaultVelocity = 100
    nonisolated static let noSongText = "No song open"
    nonisolated static let noTrackText = "No track selected"
    static let visibleKey = "virtualKeyboard.visible"
    static let baseKey = "virtualKeyboard.base"
    static let velocityKey = "virtualKeyboard.velocity"
    static let geometryKey = "virtualKeyboard.geometry"

    public init() {}

    // MARK: Window

    /// View → Virtual MIDI Keyboard. Only the toggle persists visibility, so quitting
    /// with the window open brings it back next launch.
    public func toggle() {
        guard !disposed else { return }
        setVisible(!visible, activate: true)
        let store = PreferencesStore()
        store.setBool(key: Self.visibleKey, value: visible)
        store.synchronize()
    }

    /// The title bar's close while the main window shows: hidden until toggled again.
    public func closeRequested() {
        guard visible else { return }
        toggle()
    }

    /// The window lost the keys (deactivated, a modal dialog or a popup took the focus)
    /// or is going away: key releases will go elsewhere, so every note stops now.
    public func focusLost() { releaseAll() }

    public func persistGeometry(x: Int, y: Int, width: Int, height: Int) {
        guard !disposed, width > 0, height > 0 else { return }
        publish(\.windowX, x)
        publish(\.windowY, y)
        publish(\.windowWidth, width)
        publish(\.windowHeight, height)
        let store = PreferencesStore()
        store.setString(key: Self.geometryKey, value: "\(x),\(y),\(width),\(height)")
        store.synchronize()
    }

    @QtIgnored
    func restoreFromPreferences() {
        let store = PreferencesStore()
        applyBase(VirtualKeyboardLayout.roundBase(store.int(key: Self.baseKey, fallback: base)))
        publish(\.velocity, Self.clampVelocity(store.int(key: Self.velocityKey, fallback: Self.defaultVelocity)))
        savedVelocity = store.hasValue(key: Self.velocityKey) ? velocity : nil
        let frame = store.string(key: Self.geometryKey, fallback: "").split(
            separator: ",", omittingEmptySubsequences: false
        ).compactMap { Int($0) }
        if frame.count == 4, frame[2] > 0, frame[3] > 0 {
            windowX = frame[0]
            windowY = frame[1]
            windowWidth = frame[2]
            windowHeight = frame[3]
        }
        if store.bool(key: Self.visibleKey, fallback: false) { setVisible(true, activate: false) }
    }

    private func setVisible(_ showing: Bool, activate: Bool) {
        guard visible != showing else { return }
        if !showing {
            releaseAll()
            commitVelocity()
        }
        publish(\.activateOnShow, showing && activate)
        visible = showing
        if showing { refreshTarget() }
        onVisibilityChanged?()
    }

    // MARK: Controls

    /// One octave per step; every held note stops first, and keys still down stay
    /// silent until pressed again.
    public func shiftOctave(delta: Int) {
        let next = VirtualKeyboardLayout.roundBase(base + 12 * delta)
        guard !disposed, next != base else { return }
        releaseAll()
        applyBase(next)
        let store = PreferencesStore()
        store.setInt(key: Self.baseKey, value: next)
        store.synchronize()
    }

    /// The velocity for the next notes; persisted when it settles (`commitVelocity`).
    public func setVelocity(value: Int) {
        publish(\.velocity, Self.clampVelocity(value))
    }

    public func commitVelocity() {
        guard !disposed, savedVelocity != velocity else { return }
        savedVelocity = velocity
        let store = PreferencesStore()
        store.setInt(key: Self.velocityKey, value: velocity)
        store.synchronize()
    }

    private func applyBase(_ value: Int) {
        publish(\.base, value)
        publish(\.octaveText, midiKeyName(value))
        publish(\.canOctaveDown, value > VirtualKeyboardLayout.minBase)
        publish(\.canOctaveUp, value < VirtualKeyboardLayout.maxBase)
        publish(\.playableSpan, VirtualKeyboardLayout.playableSpan(base: value))
        publish(\.octaveLabels, VirtualKeyboardLayout.octaveLabels(base: value))
        refreshLit()
    }

    private static func clampVelocity(_ value: Int) -> Int { min(127, max(1, value)) }

    // MARK: Typing

    /// The Qt platform plugin, which decides where key events name the physical key.
    public func configurePlatform(name: String) {
        keyTable = VirtualKeyboardKeymap.Table(platformName: name)
    }

    /// ShortcutOverride: a note key or - / = without Ctrl/Alt/Meta is the keyboard's,
    /// so no window shortcut also runs for it; everything else passes through.
    public func claimsKey(key: Int, modifiers: Int, nativeScanCode: Int, nativeVirtualKey: Int) -> Bool {
        !VirtualKeyboardKeymap.isCommandChord(modifiers: modifiers)
            && physicalKey(key, modifiers, nativeScanCode, nativeVirtualKey) >= 0
    }

    /// Returns whether the press is the keyboard's. Auto-repeat changes nothing.
    public func keyPressed(
        key: Int, modifiers: Int, nativeScanCode: Int, nativeVirtualKey: Int, autoRepeat: Bool
    ) -> Bool {
        let physical = physicalKey(key, modifiers, nativeScanCode, nativeVirtualKey)
        guard physical >= 0, !VirtualKeyboardKeymap.isCommandChord(modifiers: modifiers) else { return false }
        guard !autoRepeat, !disposed else { return true }
        if physical == VirtualKeyboardKeymap.octaveDownKey || physical == VirtualKeyboardKeymap.octaveUpKey {
            shiftOctave(delta: physical == VirtualKeyboardKeymap.octaveUpKey ? 1 : -1)
            return true
        }
        let note = base + VirtualKeyboardKeymap.typingOffset(physical: physical)
        guard VirtualKeyboardLayout.playable(key: note, base: base) else { return true }
        if holders.pressTyped(physical: physical, key: note) { heldKeysChanged() }
        return true
    }

    /// A note key's release stops it whatever the modifiers are by now.
    public func keyReleased(
        key: Int, modifiers: Int, nativeScanCode: Int, nativeVirtualKey: Int, autoRepeat: Bool
    ) -> Bool {
        let physical = physicalKey(key, modifiers, nativeScanCode, nativeVirtualKey)
        guard physical >= 0 else { return false }
        guard !autoRepeat, physical < VirtualKeyboardKeymap.noteKeyCount else { return true }
        if holders.releaseTyped(physical: physical) { heldKeysChanged() }
        return true
    }

    private func physicalKey(_ key: Int, _ modifiers: Int, _ scanCode: Int, _ virtualKey: Int) -> Int {
        VirtualKeyboardKeymap.physicalKey(
            key: key, modifiers: modifiers, nativeScanCode: UInt32(truncatingIfNeeded: scanCode),
            nativeVirtualKey: UInt32(truncatingIfNeeded: virtualKey), table: keyTable)
    }

    // MARK: Mouse

    public func mousePressed(x: Double, y: Double, width: Double, height: Double) {
        guard !disposed else { return }
        if holders.pressMouse(key: keyAt(x: x, y: y, width: width, height: height)) { heldKeysChanged() }
    }

    /// Only while the button is down: the pointer glides to another playable key.
    public func mouseMoved(x: Double, y: Double, width: Double, height: Double) {
        guard !disposed else { return }
        if holders.dragMouse(to: keyAt(x: x, y: y, width: width, height: height)) { heldKeysChanged() }
    }

    /// The release stops the mouse note wherever it lands.
    public func mouseReleased() {
        if holders.releaseMouse() { heldKeysChanged() }
    }

    public func keyAt(x: Double, y: Double, width: Double, height: Double) -> Int {
        VirtualKeyboardLayout.keyAt(x: x, y: y, width: width, height: height, base: base)
    }

    // MARK: Piano geometry

    public func isBlackKey(offset: Int) -> Bool {
        (0..<VirtualKeyboardLayout.span).contains(offset) && VirtualKeyboardLayout.isBlack(offset: offset)
    }

    public func keyX(offset: Int, width: Double, height: Double) -> Double {
        VirtualKeyboardLayout.keyRect(offset: offset, width: width, height: height).x
    }

    public func keyWidth(offset: Int, width: Double, height: Double) -> Double {
        VirtualKeyboardLayout.keyRect(offset: offset, width: width, height: height).width
    }

    public func keyHeight(offset: Int, width: Double, height: Double) -> Double {
        VirtualKeyboardLayout.keyRect(offset: offset, width: width, height: height).height
    }

    public func minimumPianoHeight(labelHeight: Double, padding: Double, baseFontPx: Double) -> Double {
        VirtualKeyboardLayout.minimumPianoHeight(labelHeight: labelHeight, padding: padding, baseFontPx: baseFontPx)
    }

    // MARK: Application

    @QtIgnored
    func attach(audio: NativeAudio) {
        publishNotes = { [weak audio] notes in audio?.updateKeyboardAudition(notes) }
    }

    /// The selected tab changed: its engine binding is new, so nothing held carries over.
    @QtIgnored
    func setContext(session: DocumentSession?) {
        if self.session !== session {
            releaseAll()
            self.session = session
        }
        refreshTarget()
    }

    /// The selected track (the keyboard's target), its name, voice or the edit cursor
    /// may have moved. A new target stops every held note.
    @QtIgnored
    func refreshTarget() {
        guard !disposed else { return }
        let track = session.flatMap { session -> Int? in
            guard let track = session.selectedTrack, track >= 0,
                track < min(16, session.timeline.tracks.count)
            else { return nil }
            return track
        }
        if track != targetTrack {
            releaseAll()
            targetTrack = track
        }
        publish(\.targetText, targetLine(track: track))
    }

    /// The header's title and the voice in effect at the edit cursor.
    private func targetLine(track: Int?) -> String {
        guard let session else { return Self.noSongText }
        guard let track else { return Self.noTrackText }
        let program = TrackHeadersPresenter.resolvedProgramSpan(
            track: track, session: session, tick: session.editCursor
        ).program
        let title = TrackHeadersPresenter.title(track: track, session: session)
        return "\(title) — \(TrackHeadersPresenter.voiceLabel(program: program, session: session))"
    }

    /// The host is closing: notes stop and nothing more is sounded or persisted.
    @QtIgnored
    func dispose() {
        releaseAll()
        disposed = true
        session = nil
        publishNotes = { _ in }
    }

    /// Every held note stops, the mouse's included.
    @QtIgnored
    func releaseAll() {
        if holders.releaseAll() { heldKeysChanged() }
    }

    /// What sounds: every held key on the target track, identified by key, so a held
    /// member never retriggers and velocity is the one in effect at its entrance.
    @QtIgnored
    func auditionMembers() -> [BandAuditionNote] {
        guard let track = targetTrack else { return [] }
        return holders.soundingKeys.map { key in
            BandAuditionNote(
                noteID: UInt64(key), track: UInt8(track), key: UInt8(key),
                velocity: UInt8(velocity), durationSamples: .max)
        }
    }

    private func heldKeysChanged() {
        publishNotes(auditionMembers())
        refreshLit()
    }

    private func refreshLit() {
        var mask = 0
        for offset in 0..<VirtualKeyboardLayout.playableSpan(base: base) where holders.holders(base + offset) > 0 {
            mask |= 1 << offset
        }
        publish(\.litMask, mask)
    }
}
