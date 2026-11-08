import Foundation
import PorydawCore
import PorydawPlayback

@testable import PorydawPluginHost

#if os(macOS)
    import AppKit
    import CoreGraphics
#endif

private enum EditorCheckError: Error {
    case fixture, deadline, eventPermission, window, keyboardEvent
}

private struct EditorFixtureScan: Decodable {
    struct Entry: Decodable {
        let uid: String
        let name: String
    }
    let classes: [Entry]
}

@MainActor
private func editorFixtureEntries() throws -> [PluginCatalogEntry] {
    let module = HelperProcess.executableURL.deletingLastPathComponent().appendingPathComponent(
        "vstfixtures/porydawtestgen.vst3")
    let scanner = Process()
    scanner.executableURL = HelperProcess.executableURL
    scanner.arguments = ["scan", module.path]
    let output = Pipe()
    scanner.standardOutput = output
    scanner.standardError = FileHandle.nullDevice
    try scanner.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    scanner.waitUntilExit()
    guard scanner.terminationStatus == 0 else { throw EditorCheckError.fixture }
    let scanned = try JSONDecoder().decode(EditorFixtureScan.self, from: bytes)
    var entries: [PluginCatalogEntry] = []
    for value in scanned.classes {
        let text = Array(value.uid)
        guard text.count == 32 else { throw EditorCheckError.fixture }
        var uid: [UInt8] = []
        for index in stride(from: 0, to: 32, by: 2) {
            guard let byte = UInt8(String(text[index...index + 1]), radix: 16) else { throw EditorCheckError.fixture }
            uid.append(byte)
        }
        entries.append(
            PluginCatalogEntry(
                modulePath: module.path, classUID: uid, name: value.name,
                vendor: "Porydaw", version: "1.0.0", isMidiProducer: value.name != "TestAudioOnly",
                blockedReason: nil))
    }
    return entries
}

@MainActor
private func editorInstance(
    _ entries: [PluginCatalogEntry], _ name: String,
    body: @MainActor (PluginInstance) async throws -> Void
) async throws {
    guard let entry = entries.first(where: { (entry: PluginCatalogEntry) in entry.name == name }) else {
        throw EditorCheckError.fixture
    }
    let instance = try PluginInstance(entry: entry)
    do { try await body(instance) } catch {
        await instance.shutdown()
        throw error
    }
    await instance.shutdown()
    await instance.shutdown()
}

@MainActor
private func editorWait(_ predicate: @MainActor () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while true {
        if try await predicate() { return }
        guard ContinuousClock.now < deadline else { throw EditorCheckError.deadline }
        await Task.yield()
    }
}

private func editorInteger(_ bytes: [UInt8], offset: Int) throws -> Int32 {
    guard bytes.count >= offset + 4 else { throw EditorCheckError.fixture }
    var value: UInt32 = 0
    for index in 0..<4 { value |= UInt32(bytes[offset + index]) << (index * 8) }
    return Int32(bitPattern: value)
}

private func editorCaptureRequest() -> CaptureRequest {
    let timeline = PlaybackTimeline.build(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 96),
                MidiChunk(events: [.channel(tick: 0, status: 0xC0, data0: 0)], endTick: 96),
            ]), sampleRate: 48_000, settings: PlaybackSettings(exactGate: true))
    return CaptureRequest(
        timeline: timeline, track: 0, range: TimeRange(startTick: 0, endTick: 24),
        input: .none, pacing: .offline, prerollBars: 0)
}

@MainActor
private func checkEditorLifecycle(_ entries: [PluginCatalogEntry], _ check: CheckReport.Scoped) async throws {
    try await editorInstance(entries, "TestGen") { (instance: PluginInstance) in
        var edits = 0
        var closes = 0
        instance.onEdit = { edits += 1 }
        instance.onEditorClosed = { closes += 1 }
        try await instance.openEditor(title: "Porydaw editor lifecycle check")
        check.expect(instance.isEditorOpen, message: "fixture editor opens through control IPC")
        try await editorWait { edits > 0 }
        let edited = try await instance.state()
        let pitchOffset = try editorInteger(edited.component, offset: 0)
        check.expect(
            pitchOffset == 5,
            message: "on-attach +5 edit reaches stopped component state before the first Render")
        let captured = try await instance.capture.render(editorCaptureRequest()) { (_: CaptureProgress) in }
        let noteOns = captured.events.filter { (event: RawNoteEvent) -> Bool in
            event.isOn && event.tick >= 0 && event.tick < 24
        }
        check.expectEqual(
            expected: [65, 67, 69, 71], actual: noteOns.map { (event: RawNoteEvent) -> Int in event.pitch },
            what: "the next offline Render consumes the real editor parameter queue (+5 semitones)")
        let attachedEdits = edits
        try await instance.openEditor(title: "Porydaw editor raise check")
        check.expect(
            instance.isEditorOpen && edits == attachedEdits,
            message: "opening an open editor raises it without attaching a second view")
        await instance.closeEditor()
        check.expect(!instance.isEditorOpen && closes == 0, message: "programmatic close is not a user-close event")
        try await instance.openEditor(title: "Porydaw editor reopen check")
        try await editorWait { edits > attachedEdits }
        check.expect(instance.isEditorOpen, message: "a closed editor can reopen and attach again")
        await instance.shutdown()
        check.expect(
            !instance.isEditorOpen && instance.failure == nil, message: "shutdown closes an open editor cleanly")
        do {
            try await instance.openEditor(title: "Porydaw stopped editor check")
            check.fail("shutdown must prevent an editor from reopening")
        } catch {
            check.expect(!instance.isEditorOpen, message: "late open cannot resurrect a stopped editor")
        }
    }
    try await editorInstance(entries, "TestGenRealtimeOnly") { (instance: PluginInstance) in
        do {
            try await instance.openEditor(title: "Porydaw no-editor check")
            check.fail("a class without a view must reject OpenEditor")
        } catch HelperProcessError.native {
            check.expect(
                !instance.isEditorOpen && instance.failure == nil,
                message: "missing editor is a request error, not a crashed helper")
        }
        _ = try await instance.state()
        await instance.closeEditor()
    }
    try await editorInstance(entries, "TestGen") { (instance: PluginInstance) in
        let opening = Task { @MainActor in try await instance.openEditor(title: "Porydaw cancelled editor check") }
        await Task.yield()
        await instance.closeEditor()
        _ = await opening.result
        check.expect(!instance.isEditorOpen, message: "close supersedes an in-flight lazy editor open")
        try await instance.openEditor(title: "Porydaw editor after cancellation")
        check.expect(instance.isEditorOpen, message: "a fresh open works after superseding an older open")
    }
}

#if os(macOS)
    private struct EditorCheckWindow {
        let id: UInt32
        let pid: Int32
        let bounds: CGRect
    }

    @MainActor
    private func editorWindows() -> [EditorCheckWindow] {
        guard
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
                as? [[String: Any]]
        else { return [] }
        var result: [EditorCheckWindow] = []
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                let application = NSRunningApplication(processIdentifier: pid),
                application.executableURL?.resolvingSymlinksInPath()
                    == HelperProcess.executableURL.resolvingSymlinksInPath(),
                let id = window[kCGWindowNumber as String] as? UInt32,
                let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                let bounds = window[kCGWindowBounds as String] as? [String: Double],
                let x = bounds["X"], let y = bounds["Y"],
                let width = bounds["Width"], let height = bounds["Height"]
            else { continue }
            result.append(EditorCheckWindow(id: id, pid: pid, bounds: CGRect(x: x, y: y, width: width, height: height)))
        }
        return result
    }

    @MainActor
    private func editorNewWindow(excluding ids: Set<UInt32>) async throws -> EditorCheckWindow {
        var found: EditorCheckWindow?
        try await editorWait {
            found = editorWindows().first { (window: EditorCheckWindow) -> Bool in !ids.contains(window.id) }
            return found != nil
        }
        guard let found else { throw EditorCheckError.window }
        return found
    }

    private func editorPostKey(
        _ key: CGKeyCode, to pid: Int32, repeating: Bool = false, flags: CGEventFlags = []
    ) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
        else { throw EditorCheckError.keyboardEvent }
        down.flags = flags
        up.flags = flags
        down.postToPid(pid)
        if repeating {
            guard let repeated = down.copy() else { throw EditorCheckError.keyboardEvent }
            repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
            repeated.postToPid(pid)
        }
        up.postToPid(pid)
    }

    private func editorClickClose(_ window: EditorCheckWindow) throws {
        let point = CGPoint(x: window.bounds.minX + 14, y: window.bounds.minY + 14)
        guard
            let down = CGEvent(
                mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
            let up = CGEvent(
                mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { throw EditorCheckError.keyboardEvent }
        down.postToPid(window.pid)
        up.postToPid(window.pid)
    }

    @MainActor
    private func editorReceivedKeys(_ instance: PluginInstance) async throws -> Int32 {
        let state = try await instance.state()
        return try editorInteger(state.component, offset: 8)
    }

    @MainActor
    private func checkEditorModifiedKeys(
        _ instance: PluginInstance, window: EditorCheckWindow, check: CheckReport.Scoped
    ) async throws {
        let bindings: [(stroke: Int, matching: CGEventFlags, nonmatching: CGEventFlags, name: String)] = [
            (0x0400_0041, .maskCommand, .maskControl, "Qt ControlModifier maps to physical Command+A"),
            (0x1000_0041, .maskControl, .maskCommand, "Qt MetaModifier maps to physical Control+A"),
        ]
        for binding in bindings {
            var shortcuts: [Int] = []
            PluginEditorShortcuts.install(strokes: [binding.stroke]) { (index: Int) in shortcuts.append(index) }
            try await instance.openEditor(title: "Porydaw modified binding check")
            _ = NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
            let before = try await editorReceivedKeys(instance)
            try editorPostKey(0, to: window.pid, repeating: true, flags: binding.matching)
            try await editorWait { shortcuts.count == 1 }
            let received = try await editorReceivedKeys(instance)
            check.expect(
                received == before && shortcuts == [0],
                message: "\(binding.name): system down/repeat/up fires once without a fixture key-down")
            try editorPostKey(0, to: window.pid, flags: binding.nonmatching)
            try await editorWait { try await editorReceivedKeys(instance) == before + 1 }
            check.expect(
                shortcuts == [0],
                message: "\(binding.name): the other physical modifier passes to the view without a shortcut")
        }
    }

    @MainActor
    private func checkEditorKeys(_ entries: [PluginCatalogEntry], _ check: CheckReport.Scoped) async throws {
        guard CGPreflightPostEventAccess() else { throw EditorCheckError.eventPermission }
        var shortcuts: [Int] = []
        defer { PluginEditorShortcuts.install(strokes: []) { (_: Int) in } }
        try await editorInstance(entries, "TestGen") { (first: PluginInstance) in
            let originalWindows = Set(editorWindows().map { (window: EditorCheckWindow) -> UInt32 in window.id })
            try await first.openEditor(title: "Porydaw editor key check one")
            let firstWindow = try await editorNewWindow(excluding: originalWindows)
            check.expect(
                firstWindow.bounds.width == 400 && firstWindow.bounds.height >= 240,
                message: "on-attach resizeView applies the fixture's 400 by 240 content request")
            PluginEditorShortcuts.install(strokes: [0x20]) { (index: Int) in shortcuts.append(index) }
            try await first.openEditor(title: "Porydaw editor key check one")
            _ = NSRunningApplication(processIdentifier: firstWindow.pid)?.activate(options: [])
            try editorPostKey(49, to: firstWindow.pid, repeating: true)
            try await editorWait { shortcuts.count == 1 }
            let firstKeysAfterSpace = try await editorReceivedKeys(first)
            check.expect(
                firstKeysAfterSpace == 0 && shortcuts == [0],
                message: "system Space down/repeat/up invokes shortcut zero exactly once and never reaches the view")
            try editorPostKey(0, to: firstWindow.pid)
            try await editorWait { try await editorReceivedKeys(first) == 1 }
            check.expect(shortcuts == [0], message: "nonmatching system A reaches the view, not the transport callback")
            try await editorInstance(entries, "TestGen") { (second: PluginInstance) in
                let existing = Set(editorWindows().map { (window: EditorCheckWindow) -> UInt32 in window.id })
                try await second.openEditor(title: "Porydaw editor key check two")
                let secondWindow = try await editorNewWindow(excluding: existing)
                _ = NSRunningApplication(processIdentifier: secondWindow.pid)?.activate(options: [])
                try editorPostKey(49, to: secondWindow.pid)
                try await editorWait { shortcuts.count == 2 }
                let secondKeysAfterSpace = try await editorReceivedKeys(second)
                check.expect(
                    secondKeysAfterSpace == 0 && shortcuts == [0, 0],
                    message: "a helper started after install receives the current binding immediately after Ready")
                PluginEditorShortcuts.install(strokes: [0x41]) { (index: Int) in shortcuts.append(index + 10) }
                for (instance, window) in [(first, firstWindow), (second, secondWindow)] {
                    try await instance.openEditor(title: "Porydaw replacement binding check")
                    _ = NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
                    let before = shortcuts.count
                    try editorPostKey(0, to: window.pid)
                    try await editorWait { shortcuts.count == before + 1 }
                    check.expect(shortcuts.last == 10, message: "replacement A binding broadcasts to every live helper")
                }
                try await checkEditorModifiedKeys(first, window: firstWindow, check: check)
                PluginEditorShortcuts.install(strokes: [0x20]) { (index: Int) in shortcuts.append(index) }
                PluginEditorShortcuts.install(strokes: []) { (index: Int) in shortcuts.append(index + 100) }
                for (instance, window) in [(first, firstWindow), (second, secondWindow)] {
                    try await instance.openEditor(title: "Porydaw disabled binding check")
                    _ = NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
                    let before = try await editorReceivedKeys(instance)
                    let callbacks = shortcuts.count
                    try editorPostKey(49, to: window.pid)
                    try await editorWait { try await editorReceivedKeys(instance) == before + 1 }
                    check.expect(
                        shortcuts.count == callbacks,
                        message: "ordered replacement with an empty set sends Space to each fixture without a shortcut")
                }
                var userCloses = 0
                second.onEditorClosed = { userCloses += 1 }
                _ = NSRunningApplication(processIdentifier: secondWindow.pid)?.activate(options: [])
                try editorClickClose(secondWindow)
                try await editorWait { !second.isEditorOpen && userCloses == 1 }
                check.expect(userCloses == 1, message: "native window close delivers EditorClosed exactly once")
                try await second.openEditor(title: "Porydaw editor after user close")
                check.expect(second.isEditorOpen, message: "user-closed editor can be reopened")
            }
        }
    }
#endif

/// Exercises native helper editor windows; registered as a windowing-only suite.
@MainActor
public func runPluginHostEditorChecks(_ report: CheckReport) {
    let check = report.scoped(cppID: "no-row/pluginhost/editor")
    do {
        let entries = try editorFixtureEntries()
        try runBlocking { try await checkEditorLifecycle(entries, check) }
        #if os(macOS)
            try runBlocking { try await checkEditorKeys(entries, check) }
        #endif
    } catch { check.fail("real plugin editor: \(error)") }
}
