import Foundation
import QtBridge

@testable import PorydawApp

/// Reads the production keyboard's audition membership, which QML cannot see:
/// what the presenter publishes to the shared audio engine after each change.
/// The test pushes the live ShellPresenter into this probe's children.
@MainActor
@QtBridgeable
public final class VirtualKeyboardShellProbe: QmlInstantiableStatus {
    public init() {}
    public func componentComplete() {}

    private var keyboard: VirtualKeyboardPresenter? {
        qmlChildren.compactMap { $0 as? ShellPresenter }.last?.session.virtualKeyboard
    }

    /// "track:key:velocity" per sounding member, ascending by key; empty when silent.
    public func members() -> String {
        guard let keyboard else { return "<no keyboard>" }
        return keyboard.auditionMembers().map { "\($0.track):\($0.key):\($0.velocity)" }.joined(separator: ",")
    }

    public func holders(key: Int) -> Int {
        keyboard?.holders.holders(key) ?? -1
    }
}
