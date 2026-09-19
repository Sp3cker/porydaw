import NativeGridWindowCancel
import SwiftGridKeyFeed
import SwiftGridRollBand

// Swift mirror of the sgk_ key seam and the SwiftRollBand surface (spec.md §4).
// Values are plain Sendable copies: the C structs are rebuilt per delivery and
// never retained. All state lives on SgcKeySurface; the C callbacks below are
// non-capturing shims that route through its Unmanaged context.

// Named cancel reasons carried by the sgb_ surface. The order matches
// TimelineInputCancelReason; hidden (2) and windowDeactivated (3) agree with
// the sgw_ filter's raw values (window_cancel.h).
public enum SgkCancelReason: Int32, Sendable, Equatable {
    case focusLost = 0
    case pointerUngrabbed = 1
    case hidden = 2
    case windowDeactivated = 3
}

// Sendable verdict mirror for the arrival log. Raw values match the
// harness's last_verdict codes (0 decline, 1 consume, 2 execute); the
// Wave-2 EditKeyDecision type itself is not Sendable, so only its verdict
// crosses into stored state.
public enum SgkKeyVerdict: Int32, Sendable, Equatable {
    case decline = 0
    case consume = 1
    case execute = 2
}

// Owned copy of one sgk_ arrival: the command id the host registry matched
// (EditCommand raw value), the origin (EditKeyOrigin raw value), the verdict
// the policy mirror returned, and the synchronous bool answer. Only plain
// Sendable values are stored; the Wave-2 policy types are transient inside
// answer().
public struct SgkKeyArrival: Sendable, Equatable {
    public let command: Int
    public let modifiers: Int32
    public let autoRepeat: Bool
    public let origin: Int
    public let commandAvailable: Bool
    public let verdict: SgkKeyVerdict
    public let handled: Bool
}

// Owned copy of one forwarded pointer sample: the full C fact set (Task 4
// needs the modifier and surface facts for shift-constrained drags). Tick
// carries SGB_INVALID_TICK for gutter samples.
public struct SgbPointerSample: Sendable, Equatable {
    public let kind: Int32
    public let tick: Double
    public let key: Int32
    public let button: Int32
    public let buttons: Int32
    public let modifiers: Int32
    public let surface: Int32
}

// Owned copy of one forwarded wheel sample: the full C fact set.
public struct SgbWheelSample: Sendable, Equatable {
    public let tick: Double
    public let key: Int32
    public let pixelDeltaX: Int32
    public let pixelDeltaY: Int32
    public let angleDeltaX: Int32
    public let angleDeltaY: Int32
    public let modifiers: Int32
    public let surface: Int32
    public let inverted: Bool
}

@MainActor
public final class SgcKeySurface {
    public let targetId: UInt64
    public private(set) var gestureActive = false
    public private(set) var arrivals: [SgkKeyArrival] = []
    public private(set) var pointers: [SgbPointerSample] = []
    public private(set) var wheels: [SgbWheelSample] = []
    public private(set) var cancels: [SgkCancelReason] = []
    public private(set) var leaveCount = 0

    private let sessions: SessionFeed
    private var connected = false

    public init(targetId: UInt64, sessionId: UInt64) {
        precondition(targetId != 0)
        self.targetId = targetId
        self.sessions = SessionFeed(sessionId: sessionId)
    }

    @discardableResult
    public func connect() -> Bool {
        guard !connected else { return false }
        guard sessions.connect() else { return false }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard
            sgk_set_delivery(
                targetId,
                {
                    facts, context in
                    guard let facts, let context else { return 0 }
                    return MainActor.assumeIsolated {
                        let surface: SgcKeySurface = Unmanaged.fromOpaque(context)
                            .takeUnretainedValue()
                        return surface.answer(
                            command: facts.pointee.command,
                            modifiers: facts.pointee.modifiers,
                            autoRepeat: facts.pointee.autoRepeat != 0,
                            origin: facts.pointee.origin,
                            commandAvailable: facts.pointee.commandAvailable != 0) ? 1 : 0
                    }
                }, context)
        else {
            sessions.disconnect()
            return false
        }
        var surface = SgbSurface(
            pointer: {
                kind, event, context in
                guard let event, let context else { return 0 }
                let facts = event.pointee
                return MainActor.assumeIsolated {
                    let surface: SgcKeySurface = Unmanaged.fromOpaque(context)
                        .takeUnretainedValue()
                    return surface.receivePointer(
                        kind: kind, tick: facts.tick, key: facts.key, button: facts.button,
                        buttons: facts.buttons, modifiers: facts.modifiers,
                        surface: facts.surface) ? 1 : 0
                }
            },
            wheel: {
                event, context in
                guard let event, let context else { return 0 }
                let facts = event.pointee
                return MainActor.assumeIsolated {
                    let surface: SgcKeySurface = Unmanaged.fromOpaque(context)
                        .takeUnretainedValue()
                    return surface.receiveWheel(
                        tick: facts.tick, key: facts.key, pixelDeltaX: facts.pixelDeltaX,
                        pixelDeltaY: facts.pixelDeltaY, angleDeltaX: facts.angleDeltaX,
                        angleDeltaY: facts.angleDeltaY, modifiers: facts.modifiers,
                        surface: facts.surface, inverted: facts.inverted != 0) ? 1 : 0
                }
            },
            leave: {
                context in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let surface: SgcKeySurface = Unmanaged.fromOpaque(context)
                        .takeUnretainedValue()
                    surface.receiveLeave()
                }
            },
            cancel: {
                reason, context in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let surface: SgcKeySurface = Unmanaged.fromOpaque(context)
                        .takeUnretainedValue()
                    surface.receiveCancel(reason: reason)
                }
            },
            gestureActive: {
                context in
                guard let context else { return 0 }
                return MainActor.assumeIsolated {
                    let surface: SgcKeySurface = Unmanaged.fromOpaque(context)
                        .takeUnretainedValue()
                    return surface.gestureActive ? 1 : 0
                }
            }, context: context)
        guard sgb_set_surface(targetId, &surface) else {
            sgk_clear_delivery(targetId)
            sessions.disconnect()
            return false
        }
        connected = true
        return true
    }

    public func disconnect() {
        // A surface whose binding failed must not clear the actual recipient.
        guard connected else { return }
        connected = false
        sgb_clear_surface(targetId)
        sgk_clear_delivery(targetId)
        sessions.disconnect()
    }

    // Synchronous sgk_ answer: eligibility from the sgp_ policy mirror over
    // the latest sgs_ snapshot. Only consume verdicts return true; execute and
    // decline defer so execution stays in the single host tier.
    public func answer(
        command: Int32, modifiers: Int32, autoRepeat: Bool, origin: Int32,
        commandAvailable: Bool
    ) -> Bool {
        guard let mapped = EditCommand(rawValue: Int(command)),
            let mappedOrigin = EditKeyOrigin(rawValue: Int(origin))
        else { return false }
        let snapshot = sessions.session
        let surface = EditSurfaceState(
            pointerGestureActive: gestureActive,
            timeSelectionActive: snapshot?.timeSelection.active ?? false,
            noteSelectionEmpty: snapshot?.selectedNoteIds.isEmpty ?? true,
            origin: mappedOrigin,
            autoRepeat: autoRepeat,
            commandAvailable: commandAvailable)
        let verdict = EditKeyArbiter.decide(command: mapped, surface: surface)
        let handled = verdict == .consume
        let stored: SgkKeyVerdict
        switch verdict {
        case .decline: stored = .decline
        case .consume: stored = .consume
        case .execute: stored = .execute
        }
        arrivals.append(
            SgkKeyArrival(
                command: mapped.rawValue, modifiers: modifiers, autoRepeat: autoRepeat,
                origin: mappedOrigin.rawValue, commandAvailable: commandAvailable, verdict: stored,
                handled: handled))
        if arrivals.count > 128 { arrivals.removeFirst(arrivals.count - 128) }
        return handled
    }

    // Pointer forwarding: press and double-click open the Swift gesture and
    // absorb; moves report handled only while the gesture owns the stream;
    // release closes it and absorbs. Unknown kinds decline.
    public func receivePointer(
        kind: Int32, tick: Double, key: Int32, button: Int32, buttons: Int32, modifiers: Int32,
        surface: Int32
    ) -> Bool {
        func record() {
            pointers.append(
                SgbPointerSample(
                    kind: kind, tick: tick, key: key, button: button, buttons: buttons,
                    modifiers: modifiers, surface: surface))
            if pointers.count > 64 { pointers.removeFirst(pointers.count - 64) }
        }
        switch kind {
        case Int32(SGB_POINTER_PRESS), Int32(SGB_POINTER_DOUBLE_CLICK):
            gestureActive = true
            record()
            return true
        case Int32(SGB_POINTER_MOVE):
            let owned = gestureActive
            record()
            return owned
        case Int32(SGB_POINTER_RELEASE):
            gestureActive = false
            record()
            return true
        default:
            return false
        }
    }

    public func receiveWheel(
        tick: Double, key: Int32, pixelDeltaX: Int32, pixelDeltaY: Int32, angleDeltaX: Int32,
        angleDeltaY: Int32, modifiers: Int32, surface: Int32, inverted: Bool
    ) -> Bool {
        // The overlay WheelHandler keeps viewing scroll; the band path records
        // and declines so the host owns wheels that reach it.
        wheels.append(
            SgbWheelSample(
                tick: tick, key: key, pixelDeltaX: pixelDeltaX, pixelDeltaY: pixelDeltaY,
                angleDeltaX: angleDeltaX, angleDeltaY: angleDeltaY, modifiers: modifiers,
                surface: surface, inverted: inverted))
        if wheels.count > 64 { wheels.removeFirst(wheels.count - 64) }
        return false
    }

    public func receiveLeave() {
        leaveCount += 1
    }

    public func receiveCancel(reason: Int32) {
        // A cancel ends the Swift gesture whatever the named reason; unknown
        // codes are ignored (the host only sends the four named reasons).
        gestureActive = false
        guard let mapped = SgkCancelReason(rawValue: reason) else { return }
        cancels.append(mapped)
        if cancels.count > 32 { cancels.removeFirst(cancels.count - 32) }
    }
}
