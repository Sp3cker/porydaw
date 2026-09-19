import Foundation
import QtBridge

private final class GridTypeRegistration: @unchecked Sendable {
    static let shared = GridTypeRegistration()
    private var registered = false

    @MainActor
    func register() {
        guard !registered else { return }
        registered = true
        PianoGrid.registerQmlElement()
    }
}

@_cdecl("sg_register_grid_types")
public func sgRegisterGridTypes() {
    MainActor.assumeIsolated {
        GridTypeRegistration.shared.register()
    }
}
