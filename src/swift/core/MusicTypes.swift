import Foundation

public typealias Tick = UInt32

public struct NoteID: Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64 = 0) {
        self.rawValue = rawValue
    }

    public var isAssigned: Bool { rawValue != 0 }
}

public struct NoteVelocity: Equatable, Sendable {
    public var noteID: NoteID
    public var velocity: Int

    public init(noteID: NoteID = NoteID(), velocity: Int = 1) {
        self.noteID = noteID
        self.velocity = velocity
    }
}

public struct TempoPoint: Equatable, Sendable {
    public var tick: Tick
    public var microsecondsPerQuarterNote: UInt32

    public init(tick: Tick = 0, microsecondsPerQuarterNote: UInt32 = 0) {
        self.tick = tick
        self.microsecondsPerQuarterNote = microsecondsPerQuarterNote
    }
}

public struct ControllerDefault: Equatable, Sendable {
    public let controller: UInt8
    public let value: UInt8

    public init(controller: UInt8, value: UInt8) {
        self.controller = controller
        self.value = value
    }
}

public struct LaneDomain: Equatable, Sendable {
    public let minimum: Int
    public let maximum: Int
    public let centered: Bool
    public let zoomable: Bool

    public init(minimum: Int, maximum: Int, centered: Bool, zoomable: Bool) {
        self.minimum = minimum
        self.maximum = maximum
        self.centered = centered
        self.zoomable = zoomable
    }
}

public enum TimeDefaults {
    public static let noTick: Tick = .max
    public static let maxTick: Tick = noTick - 1

    public static let tempoBPM = 120
    public static let minimumTempoBPM = 20
    public static let maximumTempoBPM = 255
    public static let microsecondsPerMinute: UInt32 = 60_000_000
    public static let defaultTempoMicrosecondsPerQuarterNote: UInt32 = 500_000

    public static let ccModulation: UInt8 = 0x01
    public static let ccPortamento: UInt8 = 0x05
    public static let ccVolume: UInt8 = 0x07
    public static let ccPan: UInt8 = 0x0A
    public static let ccBendRange: UInt8 = 0x14
    public static let ccLFOSpeed: UInt8 = 0x15
    public static let ccModulationType: UInt8 = 0x16
    public static let ccPWMCycle: UInt8 = 0x17
    public static let ccFineTune: UInt8 = 0x18
    public static let ccPWMWidth: UInt8 = 0x19
    public static let ccLFODelay: UInt8 = 0x1A

    public static let minimumCCValue = 0
    public static let maximumCCValue = 127
    public static let minimumBendValue = -8192
    public static let maximumBendValue = 8191
    public static let laneCCBend: UInt8 = 0xFF
    public static let laneCCVoice: UInt8 = 0xFD

    public static let controllerDefaultCount = 11

    @inlinable
    public static func controllerDefault(at index: Int) -> ControllerDefault {
        precondition(index >= 0 && index < controllerDefaultCount,
                     "controller default index out of range")
        switch index {
        case 0:
            return ControllerDefault(controller: ccModulation, value: 0)
        case 1:
            return ControllerDefault(controller: ccPortamento, value: 0)
        case 2:
            return ControllerDefault(controller: ccVolume, value: 127)
        case 3:
            return ControllerDefault(controller: ccPan, value: 64)
        case 4:
            return ControllerDefault(controller: ccBendRange, value: 2)
        case 5:
            return ControllerDefault(controller: ccLFOSpeed, value: 22)
        case 6:
            return ControllerDefault(controller: ccModulationType, value: 0)
        case 7:
            return ControllerDefault(controller: ccPWMCycle, value: 0)
        case 8:
            return ControllerDefault(controller: ccFineTune, value: 64)
        case 9:
            return ControllerDefault(controller: ccPWMWidth, value: 0)
        case 10:
            return ControllerDefault(controller: ccLFODelay, value: 0)
        default:
            preconditionFailure("controller default index out of range")
        }
    }

    public static func shiftTickClamped(_ tick: Tick, by delta: Int64) -> Tick {
        let position = Int64(tick)
        if delta <= -position { return 0 }
        let headroom = Int64(maxTick) - position
        if delta >= headroom { return maxTick }
        return Tick(position + delta)
    }

    public static func tick(from value: Double) -> Tick {
        guard value > 0 else { return 0 }
        guard value < Double(noTick) else { return maxTick }
        return Tick(value)
    }

    @inlinable
    public static func controllerDefault(for controller: UInt8) -> UInt8? {
        switch controller {
        case ccModulation, ccPortamento, ccModulationType, ccPWMCycle, ccPWMWidth, ccLFODelay:
            return 0
        case ccVolume:
            return 127
        case ccPan, ccFineTune:
            return 64
        case ccBendRange:
            return 2
        case ccLFOSpeed:
            return 22
        default:
            return nil
        }
    }

    public static func laneDomain(for controller: UInt8) -> LaneDomain {
        switch controller {
        case laneCCBend:
            return LaneDomain(minimum: minimumBendValue, maximum: maximumBendValue,
                              centered: true, zoomable: false)
        case ccPan, ccFineTune:
            return LaneDomain(minimum: minimumCCValue, maximum: maximumCCValue,
                              centered: true, zoomable: false)
        case ccModulationType:
            return LaneDomain(minimum: 0, maximum: 2, centered: false, zoomable: false)
        default:
            return LaneDomain(minimum: minimumCCValue, maximum: maximumCCValue,
                              centered: false, zoomable: true)
        }
    }

    public static func clampLaneValue(_ value: Int, for controller: UInt8) -> Int {
        let domain = laneDomain(for: controller)
        return min(max(value, domain.minimum), domain.maximum)
    }

    public static func hasEngineDefaultNode(for controller: UInt8) -> Bool {
        controller == ccVolume || controller == ccPan
    }

    public static func syntheticTickZero<Value>(for controller: UInt8,
                                                 in points: [(tick: Tick, value: Value)]) -> Int? {
        guard hasEngineDefaultNode(for: controller), !points.contains(where: { $0.tick == 0 }) else {
            return nil
        }
        return controllerDefault(for: controller).map(Int.init)
    }

    public static func microsecondsPerQuarterNote(forBPM bpm: Int) -> UInt32 {
        let clamped = min(max(bpm, minimumTempoBPM), maximumTempoBPM)
        return UInt32(Double(microsecondsPerMinute) / Double(clamped) + 0.5)
    }

    public static func tempoBPM(forMicrosecondsPerQuarterNote value: UInt32) -> Double {
        value == 0 ? Double(tempoBPM) : Double(microsecondsPerMinute) / Double(value)
    }

    public static func clampTempoMicrosecondsPerQuarterNote(_ value: UInt32) -> UInt32 {
        min(max(value, microsecondsPerQuarterNote(forBPM: maximumTempoBPM)),
            microsecondsPerQuarterNote(forBPM: minimumTempoBPM))
    }
}

public enum TrackLimits {
    public static let hardwareCapacity = 16
}
