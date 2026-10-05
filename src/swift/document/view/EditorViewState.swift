/// The historical QSettings workspace recipe. These keys are application-wide,
/// not part of a project's files or the document's revision/history.
public struct WorkspaceTabRecipe: Equatable, Sendable {
    public var projectPath: String
    public var orderedSongs: [String]
    public var selectedSong: String

    public init(projectPath: String, orderedSongs: [String], selectedSong: String) {
        self.projectPath = projectPath
        self.orderedSongs = orderedSongs
        self.selectedSong = selectedSong
    }

    public func normalized(available: [String]) -> WorkspaceTabRecipe {
        let playable = Set(available)
        var seen = Set<String>()
        let songs = orderedSongs.filter { playable.contains($0) && seen.insert($0).inserted }
        return WorkspaceTabRecipe(
            projectPath: projectPath, orderedSongs: songs,
            selectedSong: songs.contains(selectedSong) ? selectedSong : songs.first ?? "")
    }
}

/// The `editorDrawer/automationLanes` compact JSON grammar from editorviewstate.cpp.
public struct EditorLaneState: Equatable, Sendable {
    public struct Lane: Hashable, Sendable {
        public let track: Int
        public let controller: Int

        public init(track: Int, controller: Int) {
            self.track = track
            self.controller = controller
        }
    }

    public var laneHeight = 0
    public var laneHeights: [String: Int] = [:]
    public var laneRanges: [String: Int] = [:]
    public var emptyLanes: Set<Lane> = []
    public var hiddenLanes: [Lane] = []

    public init() {}

    /// Remaps track-owned lanes as one value, rejecting invalid destinations.
    /// Returns false for rejection or an unchanged value.
    public mutating func remapEngineTracks(_ map: [Int?]) -> Bool {
        var destinations: Set<Int> = []
        for destination in map.compactMap({ $0 }) {
            guard (0...15).contains(destination), destinations.insert(destination).inserted else {
                return false
            }
        }
        func remap(_ lane: Lane) -> Lane? {
            guard map.indices.contains(lane.track), let track = map[lane.track] else { return nil }
            return Lane(track: track, controller: lane.controller)
        }
        func remapRows(_ rows: [String: Int]) -> [String: Int] {
            var result: [String: Int] = [:]
            for (key, value) in rows {
                if key == "tempo" {
                    result[key] = value
                } else if case let .controlChange(track, controller) =
                    Self.parameter(forRowKey: key),
                    let lane = remap(Lane(track: track, controller: Int(controller)))
                {
                    result["cc:\(lane.track):\(lane.controller)"] = value
                } else if case let .pitchBend(track) = Self.parameter(forRowKey: key),
                    let lane = remap(Lane(track: track, controller: 255))
                {
                    result["cc:\(lane.track):255"] = value
                }
            }
            return result
        }
        var next = self
        next.laneHeights = remapRows(laneHeights)
        next.laneRanges = remapRows(laneRanges)
        next.emptyLanes = Set(emptyLanes.compactMap(remap))
        next.hiddenLanes = hiddenLanes.compactMap(remap)
        guard next != self else { return false }
        self = next
        return true
    }

    /// The persisted row key for an automation lane, or nil for an invalid lane.
    public static func rowKey(for parameter: AutomationParameter) -> String? {
        switch parameter {
        case .tempo: return "tempo"
        case let .controlChange(track, controller):
            let lane = Lane(track: track, controller: Int(controller))
            return validLane(lane) ? "cc:\(track):\(controller)" : nil
        case let .pitchBend(track):
            let lane = Lane(track: track, controller: 255)
            return validLane(lane) ? "cc:\(track):255" : nil
        }
    }

    /// The automation parameter a persisted row key names, or nil for an invalid key.
    public static func parameter(forRowKey key: String) -> AutomationParameter? {
        if key == "tempo" { return .tempo }
        guard validRow(key) else { return nil }
        let parts = key.split(separator: ":")
        guard parts.count == 3, let track = Int(parts[1]), let controller = UInt8(parts[2]) else {
            return nil
        }
        return AutomationCatalog.parameter(track: track, controller: controller)
    }

    /// Whether a lane names a MIDI track and a persistable controller.
    public static func validLane(_ lane: Lane) -> Bool {
        (0...15).contains(lane.track) && validController(lane.controller)
    }

    /// Whether a key is `tempo` or a canonical `cc:<track>:<controller>` row.
    public static func validRow(_ key: String) -> Bool {
        if key == "tempo" { return true }
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "cc",
            let track = decimal(parts[1]), let controller = decimal(parts[2])
        else { return false }
        return validLane(.init(track: track, controller: controller))
    }

    private static func validController(_ value: Int) -> Bool {
        (0...127).contains(value) || value == 255
            || ((128...254).contains(value) && AutomationCatalog.controllers.contains(UInt8(value)))
    }

    private static func decimal(_ value: Substring) -> Int? {
        guard !value.isEmpty, (value.count == 1 || value.first != "0"),
            value.allSatisfy({ $0 >= "0" && $0 <= "9" })
        else { return nil }
        return Int(value)
    }
}

/// One complete, presentation-only editor preference transaction.
public struct EditorViewState: Equatable, Sendable {
    public var chrome = EditorDrawerChromeState()
    public var lanes = EditorLaneState()

    public init() {}
}

extension EditorViewState {
    /// Remaps track-owned lanes while preserving chrome.
    /// Returns false for rejection or an unchanged value.
    public mutating func remapEngineTracks(_ map: [Int?]) -> Bool {
        lanes.remapEngineTracks(map)
    }
}

public struct DrawerChromeSection: Equatable, Sendable {
    public var visible: Bool
    public var height: Int?

    public init(visible: Bool, height: Int? = nil) {
        self.visible = visible
        self.height = height
    }
}

public struct EditorDrawerChromeState: Equatable, Sendable {
    public var velocity = DrawerChromeSection(visible: false)
    public var automation = DrawerChromeSection(visible: true)
    public var voiceChanges = DrawerChromeSection(visible: false)
    public var activePage: DrawerSectionKind = .automation

    public init() {}
}
