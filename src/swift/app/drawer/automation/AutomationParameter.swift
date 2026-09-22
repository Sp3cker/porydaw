import Foundation
import PorydawCore

// The pure Automation parameter domain: parameter identity, the finite
// production catalog, per-parameter value-axis metadata, and the inline
// value prompt.

// MARK: - Parameter identity

/// One automation parameter. Control-change lanes and Pitch bend are
/// track-scoped; Tempo is song-global. Identity is never a visible-array index:
/// the catalog index of a parameter is presentation, and switching the active
/// parameter never rewrites this value.
public enum AutomationParameter: Hashable, Sendable {
    case controlChange(track: Int, controller: UInt8)
    case pitchBend(track: Int)
    case tempo

    /// The engine track the parameter belongs to, or `nil` for song-global Tempo.
    public var track: Int? {
        switch self {
        case let .controlChange(track, _), let .pitchBend(track): track
        case .tempo: nil
        }
    }

    /// The document lane this parameter reads and writes, or `nil` for Tempo.
    public var lane: Lane? {
        switch self {
        case let .controlChange(_, controller): .controller(controller)
        case .pitchBend: .pitchBend
        case .tempo: nil
        }
    }

    /// The production controller identity: Pitch bend travels as `0xFF` and
    /// Tempo has none. Used for labels, domains and range policy only.
    public var controller: UInt8? {
        switch self {
        case let .controlChange(_, controller): controller
        case .pitchBend: TimeDefaults.laneCCBend
        case .tempo: nil
        }
    }

    public var isTempo: Bool { self == .tempo }
}

/// The finite production catalog: the supported per-track parameters in
/// selector order (mix, pitch, the XCMD echo lanes, the MODT/TUNE/LFODL trio),
/// then song-global Tempo.
public enum AutomationCatalog {
    public static let controllers: [UInt8] = [
        TimeDefaults.ccVolume,
        TimeDefaults.ccPan,
        TimeDefaults.ccModulation,
        TimeDefaults.laneCCBend,
        TimeDefaults.ccLFOSpeed,
        TimeDefaults.ccBendRange,
    ] + Xcmd.descriptors.map(\.lane) + [
        TimeDefaults.ccModulationType,
        TimeDefaults.ccFineTune,
        TimeDefaults.ccLFODelay,
    ]

    /// Volume, Pan, Modulation, Pitch bend, LFO speed, Bend range, the XCMD
    /// lanes, LFO type, Fine tune, LFO delay, Tempo.
    public static let count = controllers.count + 1

    public static func parameters(track: Int) -> [AutomationParameter] {
        controllers.map { parameter(track: track, controller: $0) } + [.tempo]
    }

    public static func parameter(track: Int, controller: UInt8) -> AutomationParameter {
        controller == TimeDefaults.laneCCBend ? .pitchBend(track: track)
                                              : .controlChange(track: track, controller: controller)
    }

    public static func index(of parameter: AutomationParameter, track: Int) -> Int? {
        parameters(track: track).firstIndex(of: parameter)
    }

    public static func parameter(at index: Int, track: Int) -> AutomationParameter? {
        let catalog = parameters(track: track)
        return catalog.indices.contains(index) ? catalog[index] : nil
    }

    /// The selector label: the m4a lane name with no controller decoration.
    public static func tabLabel(_ parameter: AutomationParameter) -> String {
        switch parameter {
        case .tempo: return m4aLaneName(.tempo)
        case .pitchBend: return m4aLaneName(.pitchBend)
        case let .controlChange(_, controller):
            if let descriptor = Xcmd.descriptor(forLane: controller) {
                return m4aLaneName(m4aLane(forXCMDSelector: descriptor.selector))
            }
            return m4aLaneName(m4aClassifyCC(controller).lane)
        }
    }

    /// The lane title: the classified name with its mnemonic, or Tempo's BPM.
    public static func title(_ parameter: AutomationParameter) -> String {
        switch parameter {
        case .tempo: return "Tempo (BPM)"
        case .pitchBend: return "Pitch bend (BEND)"
        case let .controlChange(_, controller):
            if let descriptor = Xcmd.descriptor(forLane: controller) {
                return "\(descriptor.displayName) (\(descriptor.mnemonic))"
            }
            let info = m4aClassifyCC(controller)
            return "\(info.display) (\(info.name))"
        }
    }

    /// `CCLanes::defaultRange`: Modulation opens on 0–16, every other zoomable
    /// parameter on the full 0–127.
    public static func defaultRange(_ controller: UInt8) -> UInt8 {
        controller == TimeDefaults.ccModulation ? 0 : 127
    }

    /// `CCLanes::autoRange`: the presentation maximum that fits the data.
    public static func autoRange(maximum: Int) -> UInt8 {
        if maximum <= 16 { return 16 }
        if maximum <= 32 { return 32 }
        if maximum <= 64 { return 64 }
        return 127
    }
}

// MARK: - Parameter metadata

/// Held-value (step) is the production curve for every catalog parameter; the
/// linear ramp is the interpolation a ramp sweep writes, and the segment kind a
/// projection builds from it.
public enum AutomationInterpolation: Equatable, Sendable {
    case step
    case ramp

    /// `ui::linearRampValue` at `tick` between two endpoints.
    public func value(at tick: Double, from: AutomationLanePoint, to: AutomationLanePoint) -> Int {
        let span = Double(to.tick) - Double(from.tick)
        guard self == .ramp, span != 0 else { return from.value }
        let fraction = min(max((tick - Double(from.tick)) / span, 0), 1)
        let exact = Double(from.value) + fraction * Double(to.value - from.value)
        return Int(exact.rounded())
    }
}

/// Everything one parameter owns about its value axis: exact range, neutral and
/// default values, formatting, the inline value prompt, and interpolation.
public struct AutomationParameterMetadata: Equatable, Sendable {
    public let parameter: AutomationParameter
    public let minimum: Int
    public let maximum: Int
    public let centered: Bool
    public let zoomable: Bool
    /// The snap target a value-drag may lock onto, or `nil` when the parameter
    /// has no neutral value (`NodeLane::neutralValue` returning -1).
    public let neutral: Int?
    /// The engine/tick-zero default, or `nil` when the parameter has none.
    public let defaultValue: Int?
    /// Volume and Pan project a synthetic tick-zero node when the document
    /// never writes them; every other parameter supplies a lead-in instead.
    public let projectsTickZero: Bool
    public let interpolation: AutomationInterpolation

    public init(parameter: AutomationParameter) {
        self.parameter = parameter
        switch parameter {
        case .tempo:
            minimum = TimeDefaults.minimumTempoBPM
            maximum = TimeDefaults.maximumTempoBPM
            centered = false
            zoomable = false
            defaultValue = TimeDefaults.tempoBPM
            projectsTickZero = false
        case .pitchBend:
            let domain = TimeDefaults.laneDomain(for: TimeDefaults.laneCCBend)
            minimum = domain.minimum
            maximum = domain.maximum
            centered = domain.centered
            zoomable = domain.zoomable
            defaultValue = 0
            projectsTickZero = false
        case let .controlChange(_, controller):
            let domain = TimeDefaults.laneDomain(for: controller)
            minimum = domain.minimum
            maximum = domain.maximum
            centered = domain.centered
            zoomable = domain.zoomable
            defaultValue = TimeDefaults.controllerDefault(for: controller).map(Int.init)
            projectsTickZero = TimeDefaults.hasEngineDefaultNode(for: controller)
        }
        neutral = centered ? (minimum + maximum + 1) / 2 : nil
        interpolation = .step
    }

    public func clamp(_ value: Int) -> Int { min(max(value, minimum), maximum) }

    /// The neutral snap of `updateValuePoint`: within the font-relative radius
    /// the value locks onto the parameter's neutral, and the tick never moves.
    public func snappedValue(_ value: Int, snapValue: Bool, plotHeight: Double,
                             neutralSnapRadius: Double) -> Int {
        let clamped = clamp(value)
        guard snapValue, let neutral else { return clamped }
        let span = maximum - minimum
        let height = max(1.0, plotHeight)
        let threshold = Int(Double(span) * neutralSnapRadius / height)
        return abs(clamped - neutral) <= threshold ? neutral : clamped
    }

    /// The lane's displayed text for one stored value.
    public func valueText(_ value: Int) -> String {
        switch parameter {
        case .tempo: return String(value)
        case .pitchBend: return m4aFormatBend(value)
        case let .controlChange(_, controller):
            if Xcmd.descriptor(forLane: controller) != nil { return String(value) }
            return m4aFormatCCValue(controller: controller, value: UInt8(clamping: value))
        }
    }

    /// The inline value prompt: displayed values are stored values offset by the
    /// centered parameter's midpoint, exactly as the lane adapters publish them.
    public func prompt(storedValue: Int) -> AutomationValuePrompt {
        let offset = centered ? (minimum + maximum + 1) / 2 : 0
        let label: String
        if parameter == .tempo {
            label = "BPM:"
        } else if centered {
            label = offset == 0 ? "Bend (0 = none):" : "c_v value (0 = center):"
        } else {
            label = "Value:"
        }
        return AutomationValuePrompt(
            title: parameter == .tempo ? "Set tempo" : AutomationCatalog.title(parameter),
            label: label,
            initialValue: clamp(storedValue) - offset,
            minimum: minimum - offset,
            maximum: maximum - offset,
            storedOffset: offset)
    }

    public func storedValue(prompted value: Int) -> Int {
        let offset = centered ? (minimum + maximum + 1) / 2 : 0
        return clamp(value + offset)
    }
}

/// `NodeValuePrompt`: the inline prompt's own displayed domain.
public struct AutomationValuePrompt: Equatable, Sendable {
    public let title: String
    public let label: String
    public let initialValue: Int
    public let minimum: Int
    public let maximum: Int
    public let storedOffset: Int
}
