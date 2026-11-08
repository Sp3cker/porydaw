import Foundation

/// The current transport bindings, shared by every live plugin helper.
@MainActor
public enum PluginEditorShortcuts {
    @MainActor
    private final class Binding {
        weak var helper: HelperProcess?
        let onFailure: @MainActor (any Error) -> Void
        var pending: Task<Void, any Error>?

        init(helper: HelperProcess, onFailure: @escaping @MainActor (any Error) -> Void) {
            self.helper = helper
            self.onFailure = onFailure
        }

        func enqueue(_ strokes: [HelperShortcut]) -> Task<Void, any Error> {
            let previous = pending
            let task = Task { @MainActor [weak helper, onFailure] in
                if let previous { _ = await previous.result }
                try Task.checkCancellation()
                guard let helper else { throw CancellationError() }
                do {
                    try await helper.setShortcuts(strokes)
                } catch {
                    if !(error is CancellationError) { onFailure(error) }
                    throw error
                }
            }
            pending = task
            return task
        }
    }

    private static var strokes: [HelperShortcut] = []
    private static var onShortcut: (@MainActor (Int) -> Void)?
    private static var bindings: [ObjectIdentifier: Binding] = [:]

    /// Replaces the encoded Qt single-stroke bindings and their main-actor handler.
    /// - Parameters:
    ///   - strokes: Qt key values combined with Qt keyboard modifier bits.
    ///   - onShortcut: Receives the matching stroke's zero-based index.
    public static func install(strokes: [Int], onShortcut: @escaping @MainActor (Int) -> Void) {
        self.strokes = strokes.map { (stroke: Int) -> HelperShortcut in
            let encoded = UInt32(truncatingIfNeeded: stroke)
            return HelperShortcut(key: encoded & 0x01FF_FFFF, modifiers: encoded & 0xFE00_0000)
        }
        self.onShortcut = onShortcut
        for binding in bindings.values { _ = binding.enqueue(self.strokes) }
    }

    static func register(_ helper: HelperProcess, onFailure: @escaping @MainActor (any Error) -> Void) async throws {
        let binding = Binding(helper: helper, onFailure: onFailure)
        bindings[ObjectIdentifier(helper)] = binding
        try await binding.enqueue(strokes).value
    }

    static func synchronize(_ helper: HelperProcess) async throws {
        if let pending = bindings[ObjectIdentifier(helper)]?.pending { try await pending.value }
    }

    static func unregister(_ helper: HelperProcess) {
        bindings.removeValue(forKey: ObjectIdentifier(helper))?.pending?.cancel()
    }

    static func receive(_ index: UInt32) {
        guard Int(index) < strokes.count else { return }
        onShortcut?(Int(index))
    }
}
