import SwiftGrid

// Harness surface for the swiftbandkeys check: one SgcKeySurface per
// SwiftGridKeyRouter target id, queried from C++ through the @_cdecl entries
// below. The C++ side owns the window, the band, and the session feed; the
// session id passed at creation must belong to a registered SwiftGridSessionFeed.

@MainActor
private final class BandKeysRegistry {
    static let shared = BandKeysRegistry()
    private var surfaces: [UInt64: SgcKeySurface] = [:]

    private init() {}

    // Full bind (sgs_ + sgk_ + sgb_) for the harness-owned private delivery
    // target: a scratch router/band pair never attached to input items, so its
    // sgb_ endpoint is unclaimed and the surface observes the band's
    // plain-value and key deliveries directly. The production target takes no
    // harness surface — the mounted grid owns both of its slots.
    func createFull(targetId: UInt64, sessionId: UInt64) -> Int32 {
        guard targetId != 0, sessionId != 0, surfaces[targetId] == nil else { return 0 }
        let surface = SgcKeySurface(targetId: targetId, sessionId: sessionId)
        guard surface.connect() else { return 0 }
        surfaces[targetId] = surface
        return 1
    }

    func destroy(targetId: UInt64) -> Int32 {
        guard let surface = surfaces.removeValue(forKey: targetId) else { return 0 }
        surface.disconnect()
        return 1
    }

    func surface(targetId: UInt64) -> SgcKeySurface? { surfaces[targetId] }
}

private func withSurface(targetId: UInt64, _ body: @MainActor (SgcKeySurface) -> Int32) -> Int32 {
    MainActor.assumeIsolated {
        guard let surface = BandKeysRegistry.shared.surface(targetId: targetId) else {
            return -1
        }
        return body(surface)
    }
}

@_cdecl("bandkeys_surface_create_full")
public func bandkeysSurfaceCreateFull(targetId: UInt64, sessionId: UInt64) -> Int32 {
    MainActor.assumeIsolated {
        BandKeysRegistry.shared.createFull(targetId: targetId, sessionId: sessionId)
    }
}

@_cdecl("bandkeys_surface_destroy")
public func bandkeysSurfaceDestroy(targetId: UInt64) -> Int32 {
    MainActor.assumeIsolated {
        BandKeysRegistry.shared.destroy(targetId: targetId)
    }
}

@_cdecl("bandkeys_arrival_count")
public func bandkeysArrivalCount(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        Int32($0.arrivals.count)
    }
}

@_cdecl("bandkeys_last_verdict")
public func bandkeysLastVerdict(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.arrivals.last else { return -1 }
        return last.verdict.rawValue
    }
}

@_cdecl("bandkeys_last_handled")
public func bandkeysLastHandled(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.arrivals.last else { return -1 }
        return last.handled ? 1 : 0
    }
}

@_cdecl("bandkeys_last_command")
public func bandkeysLastCommand(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.arrivals.last else { return -1 }
        return Int32(last.command)
    }
}

@_cdecl("bandkeys_gesture_active")
public func bandkeysGestureActive(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) { $0.gestureActive ? 1 : 0 }
}

@_cdecl("bandkeys_cancel_count")
public func bandkeysCancelCount(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) { Int32($0.cancels.count) }
}

@_cdecl("bandkeys_cancel_at")
public func bandkeysCancelAt(targetId: UInt64, index: Int32) -> Int32 {
    withSurface(targetId: targetId) {
        guard index >= 0, Int(index) < $0.cancels.count else { return -1 }
        return $0.cancels[Int(index)].rawValue
    }
}

@_cdecl("bandkeys_pointer_count")
public func bandkeysPointerCount(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) { Int32($0.pointers.count) }
}

@_cdecl("bandkeys_last_pointer_kind")
public func bandkeysLastPointerKind(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.pointers.last else { return -1 }
        return last.kind
    }
}

@_cdecl("bandkeys_last_pointer_key")
public func bandkeysLastPointerKey(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.pointers.last else { return -1 }
        return last.key
    }
}

@_cdecl("bandkeys_last_pointer_button")
public func bandkeysLastPointerButton(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.pointers.last else { return -1 }
        return last.button
    }
}

@_cdecl("bandkeys_last_pointer_buttons")
public func bandkeysLastPointerButtons(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.pointers.last else { return -1 }
        return last.buttons
    }
}

@_cdecl("bandkeys_last_pointer_modifiers")
public func bandkeysLastPointerModifiers(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.pointers.last else { return -1 }
        return last.modifiers
    }
}

@_cdecl("bandkeys_last_pointer_surface")
public func bandkeysLastPointerSurface(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.pointers.last else { return -1 }
        return last.surface
    }
}

@_cdecl("bandkeys_last_pointer_tick")
public func bandkeysLastPointerTick(targetId: UInt64) -> Double {
    MainActor.assumeIsolated {
        guard let last = BandKeysRegistry.shared.surface(targetId: targetId)?.pointers.last
        else { return -1 }
        return last.tick
    }
}

@_cdecl("bandkeys_wheel_count")
public func bandkeysWheelCount(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) { Int32($0.wheels.count) }
}

@_cdecl("bandkeys_last_wheel_tick")
public func bandkeysLastWheelTick(targetId: UInt64) -> Double {
    MainActor.assumeIsolated {
        guard let last = BandKeysRegistry.shared.surface(targetId: targetId)?.wheels.last
        else { return -1 }
        return last.tick
    }
}

@_cdecl("bandkeys_last_wheel_key")
public func bandkeysLastWheelKey(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.wheels.last else { return -1 }
        return last.key
    }
}

@_cdecl("bandkeys_last_wheel_pixel_delta_x")
public func bandkeysLastWheelPixelDeltaX(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.wheels.last else { return 0 }
        return last.pixelDeltaX
    }
}

@_cdecl("bandkeys_last_wheel_pixel_delta_y")
public func bandkeysLastWheelPixelDeltaY(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.wheels.last else { return 0 }
        return last.pixelDeltaY
    }
}

@_cdecl("bandkeys_last_wheel_angle_delta_x")
public func bandkeysLastWheelAngleDeltaX(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.wheels.last else { return 0 }
        return last.angleDeltaX
    }
}

@_cdecl("bandkeys_last_wheel_angle_delta_y")
public func bandkeysLastWheelAngleDeltaY(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.wheels.last else { return 0 }
        return last.angleDeltaY
    }
}

@_cdecl("bandkeys_last_wheel_modifiers")
public func bandkeysLastWheelModifiers(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.wheels.last else { return -1 }
        return last.modifiers
    }
}

@_cdecl("bandkeys_last_wheel_surface")
public func bandkeysLastWheelSurface(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.wheels.last else { return -1 }
        return last.surface
    }
}

@_cdecl("bandkeys_last_wheel_inverted")
public func bandkeysLastWheelInverted(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) {
        guard let last = $0.wheels.last else { return -1 }
        return last.inverted ? 1 : 0
    }
}

@_cdecl("bandkeys_leave_count")
public func bandkeysLeaveCount(targetId: UInt64) -> Int32 {
    withSurface(targetId: targetId) { Int32($0.leaveCount) }
}
