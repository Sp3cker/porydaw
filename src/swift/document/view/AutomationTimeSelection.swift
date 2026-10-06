import Foundation
import PorydawCore

/// The explicit time selection the page publishes for its parameters, with the
/// production coverage rules of `EditorSelectionModel::TimeSelection`.
public struct AutomationTimeSelection: Equatable, Sendable {
    public enum Scope: Equatable, Sendable {
        /// A scope derived from the shared track selection.
        case tracks(Set<Int>)
        /// An explicit lane list plus the song-global Tempo flag.
        case lanes
    }

    public var range: TimeRange
    public var scope: Scope
    public var lanes: Set<AutomationParameter>
    public var tempo: Bool

    public init(
        range: TimeRange, scope: Scope = .lanes,
        lanes: Set<AutomationParameter> = [], tempo: Bool = false
    ) {
        self.range = range
        self.scope = scope
        self.lanes = lanes
        self.tempo = tempo
    }

    /// `endTick > startTick`: a zero-width selection is no selection.
    public var isActive: Bool { range.endTick > range.startTick }

    public func covers(_ parameter: AutomationParameter, usedTracks: Set<Int>) -> Bool {
        guard isActive else { return false }
        switch scope {
        case .lanes: return parameter.isTempo ? tempo : lanes.contains(parameter)
        case let .tracks(trackScope):
            if parameter.isTempo { return coversTempo(usedTracks: usedTracks) }
            guard let track = parameter.track else { return false }
            return trackScope.contains(track) && usedTracks.contains(track)
        }
    }

    public func coversTempo(usedTracks: Set<Int>) -> Bool {
        guard isActive else { return false }
        switch scope {
        case .lanes: return tempo
        case let .tracks(trackScope):
            return !usedTracks.isEmpty && trackScope.intersection(usedTracks) == usedTracks
        }
    }

    public func contains(_ tick: Tick) -> Bool { range.contains(tick) }
}
