import Foundation
import CoreFoundation
import PorydawProject
import QtBridgeCpp

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
        return WorkspaceTabRecipe(projectPath: projectPath, orderedSongs: songs,
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
                    EditorViewStateCodec.parameter(for: key),
                    let lane = remap(Lane(track: track, controller: Int(controller))) {
                    result["cc:\(lane.track):\(lane.controller)"] = value
                } else if case let .pitchBend(track) = EditorViewStateCodec.parameter(for: key),
                          let lane = remap(Lane(track: track, controller: 255)) {
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

public enum EditorViewStateCodec {
    private static let lanesKey = "editorDrawer.automationLanes"
    private static let chromePrefix = "editorDrawer."

    @MainActor
    public static func load(store: PreferencesStore) -> EditorViewState {
        var state = EditorViewState()
        state.chrome = loadChrome(store: store)
        state.lanes = loadLanes(store: store)
        return state
    }

    @MainActor
    public static func save(_ state: EditorViewState, store: PreferencesStore) {
        writeChrome(state.chrome, store: store)
        writeLanes(state.lanes, store: store)
        store.synchronize()
    }

    @MainActor
    public static func loadChrome(store: PreferencesStore) -> EditorDrawerChromeState {
        var state = EditorDrawerChromeState()
        state.velocity = loadSection("velocity", defaultVisible: state.velocity.visible, store: store)
        state.automation = loadSection("automation", defaultVisible: state.automation.visible, store: store)
        state.voiceChanges = loadSection("voiceChanges", defaultVisible: state.voiceChanges.visible, store: store)
        switch store.string(key: chromePrefix + "activePage", fallback: "") {
        case "velocity": state.activePage = .velocity
        case "voiceChanges": state.activePage = .voiceChanges
        case "automations": state.activePage = .automation
        default: break
        }
        return state
    }

    @MainActor
    private static func loadSection(_ name: String, defaultVisible: Bool,
                                    store: PreferencesStore) -> DrawerChromeSection {
        DrawerChromeSection(
            visible: store.storedBool(key: chromePrefix + name + "Visible") ?? defaultVisible,
            height: store.storedPositiveInt(key: chromePrefix + name + "Height"))
    }

    @MainActor
    public static func saveChrome(_ state: EditorDrawerChromeState, store: PreferencesStore) {
        writeChrome(state, store: store)
        store.synchronize()
    }

    @MainActor
    private static func writeChrome(_ state: EditorDrawerChromeState, store: PreferencesStore) {
        for (name, section) in [("velocity", state.velocity),
                                ("automation", state.automation),
                                ("voiceChanges", state.voiceChanges)] {
            store.setBool(key: chromePrefix + name + "Visible", value: section.visible)
            let heightKey = chromePrefix + name + "Height"
            if let height = section.height, height > 0 {
                store.setInt(key: heightKey, value: height)
            } else {
                store.remove(key: heightKey)
            }
        }
        store.setString(key: chromePrefix + "activePage", value: state.activePage.name)
    }


    @MainActor
    public static func loadTabs(store: PreferencesStore) -> WorkspaceTabRecipe {
        let selected = store.string(key: "lastSongLabel", fallback: "")
        let saved = normalizeSavedRecipe(
            projectPath: store.string(key: "lastProjectDir", fallback: ""),
            labels: store.strings("lastOpenSongs") ?? [], selected: selected)
        return WorkspaceTabRecipe(projectPath: saved.projectPath,
                                  orderedSongs: saved.orderedSongs.map(\.value),
                                  selectedSong: saved.selected?.value ?? "")
    }

    @MainActor
    public static func saveTabs(_ recipe: WorkspaceTabRecipe, store: PreferencesStore) {
        store.setString(key: "lastProjectDir", value: recipe.projectPath)
        store.setStrings("lastOpenSongs", recipe.orderedSongs.isEmpty ? nil : recipe.orderedSongs)
        if recipe.orderedSongs.isEmpty {
            store.remove(key: "lastSongLabel")
        } else {
            store.setString(key: "lastSongLabel", value: recipe.selectedSong)
        }
        store.synchronize()
    }

    @MainActor
    public static func loadLanes(store: PreferencesStore) -> EditorLaneState {
        guard let bytes = store.data(lanesKey) else { return EditorLaneState() }
        return decodeLanes(bytes)
    }

    @MainActor
    public static func saveLanes(_ state: EditorLaneState, store: PreferencesStore) {
        writeLanes(state, store: store)
        store.synchronize()
    }

    @MainActor
    private static func writeLanes(_ state: EditorLaneState, store: PreferencesStore) {
        guard let bytes = encodeLanes(state) else { return }
        store.setData(lanesKey, bytes)
    }

    public static func decodeLanes(_ bytes: Data) -> EditorLaneState {
        guard case let .object(root) = try? JSONDecoder().decode(JSONValue.self, from: bytes) else {
            return EditorLaneState()
        }
        var state = EditorLaneState()
        if let height = integer(root["laneHeight"], maximum: Int32.max) {
            state.laneHeight = height == 0 ? 0 : clampHeight(height)
        }
        if case let .object(heights) = root["laneHeights"] {
            for (row, raw) in heights {
                if validRow(row), let height = integer(raw, maximum: Int32.max) {
                    state.laneHeights[row] = clampHeight(height)
                }
            }
        }
        if case let .object(ranges) = root["laneRanges"] {
            for (row, raw) in ranges {
                if validRow(row), let range = integer(raw, maximum: 127) {
                    state.laneRanges[row] = range
                }
            }
        }
        if case let .array(entries) = root["emptyLanes"] {
            for entry in entries { if let lane = decodeLane(entry) { state.emptyLanes.insert(lane) } }
        }
        if case let .array(entries) = root["hiddenLanes"] {
            for entry in entries {
                if let lane = decodeLane(entry), !state.hiddenLanes.contains(lane) {
                    state.hiddenLanes.append(lane)
                }
            }
        }
        return state
    }

    /// Serializes the canonical lane members as one compact JSON object.
    /// - Parameter state: The lane preferences.
    /// - Returns: The compact JSON bytes, or nil if serialization fails.
    public static func encodeLanes(_ state: EditorLaneState) -> Data? {
        let heights = state.laneHeights.filter { validRow($0.key) && $0.value >= 0 }
        let ranges = state.laneRanges.filter { validRow($0.key) && (0...127).contains($0.value) }
        let empty = state.emptyLanes.sorted(by: laneOrder).map(laneObject)
        let hidden = state.hiddenLanes.filter(validLane).map(laneObject)
        let root: JSONValue = .object([
            "laneHeight": .number(Double(state.laneHeight)),
            "laneHeights": .object(heights.mapValues { .number(Double($0)) }),
            "laneRanges": .object(ranges.mapValues { .number(Double($0)) }),
            "emptyLanes": .array(empty),
            "hiddenLanes": .array(hidden),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(root)
    }

    public static func rowKey(for parameter: AutomationParameter) -> String? {
        switch parameter {
        case .tempo: return "tempo"
        case let .controlChange(track, controller):
            let lane = EditorLaneState.Lane(track: track, controller: Int(controller))
            return validLane(lane) ? "cc:\(track):\(controller)" : nil
        case let .pitchBend(track):
            let lane = EditorLaneState.Lane(track: track, controller: 255)
            return validLane(lane) ? "cc:\(track):255" : nil
        }
    }

    public static func parameter(for key: String) -> AutomationParameter? {
        if key == "tempo" { return .tempo }
        guard validRow(key) else { return nil }
        let parts = key.split(separator: ":")
        guard parts.count == 3, let track = Int(parts[1]), let controller = UInt8(parts[2]) else {
            return nil
        }
        return AutomationCatalog.parameter(track: track, controller: controller)
    }

    private static func integer(_ value: JSONValue?, maximum: Int32) -> Int? {
        guard case let .number(raw) = value, raw.isFinite,
              raw.rounded(.towardZero) == raw,
              raw >= 0, raw <= Double(maximum) else { return nil }
        return Int(raw)
    }

    private static func validController(_ value: Int) -> Bool {
        (0...127).contains(value) || value == 255
            || ((128...254).contains(value) && AutomationCatalog.controllers.contains(UInt8(value)))
    }

    private static func validLane(_ lane: EditorLaneState.Lane) -> Bool {
        (0...15).contains(lane.track) && validController(lane.controller)
    }

    private static func validRow(_ key: String) -> Bool {
        if key == "tempo" { return true }
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "cc",
              let track = decimal(parts[1]), let controller = decimal(parts[2]) else { return false }
        return validLane(.init(track: track, controller: controller))
    }

    private static func decimal(_ value: Substring) -> Int? {
        guard !value.isEmpty, (value.count == 1 || value.first != "0"),
              value.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        return Int(value)
    }

    private static func decodeLane(_ value: JSONValue) -> EditorLaneState.Lane? {
        guard case let .object(row) = value,
              let track = integer(row["track"], maximum: 15),
              let controller = integer(row["cc"], maximum: 255) else { return nil }
        let lane = EditorLaneState.Lane(track: track, controller: controller)
        return validLane(lane) ? lane : nil
    }

    private static func clampHeight(_ height: Int) -> Int {
        // The native lane floor/ceiling are layout::fontPx(7/3, 32/3).
        let font = GridCameraPolicy.seedBaseFontPx
        return min(max(height, Int((font * 7 / 3).rounded())), Int((font * 32 / 3).rounded()))
    }

    private static func laneOrder(_ lhs: EditorLaneState.Lane, _ rhs: EditorLaneState.Lane) -> Bool {
        lhs.track == rhs.track ? lhs.controller < rhs.controller : lhs.track < rhs.track
    }

    private static func laneObject(_ lane: EditorLaneState.Lane) -> JSONValue {
        .object(["track": .number(Double(lane.track)), "cc": .number(Double(lane.controller))])
    }
}

private indirect enum JSONValue: Codable {
    case object([String: JSONValue])
    case array([JSONValue])
    case number(Double)
    case text(String)
    case boolean(Bool)
    case null

    init(from decoder: Decoder) throws {
        let scalar = try decoder.singleValueContainer()
        if scalar.decodeNil() { self = .null }
        else if let value = try? scalar.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? scalar.decode(Double.self) { self = .number(value) }
        else if let value = try? scalar.decode(String.self) { self = .text(value) }
        else if let value = try? scalar.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try scalar.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var scalar = encoder.singleValueContainer()
        switch self {
        case let .object(value): try scalar.encode(value)
        case let .array(value): try scalar.encode(value)
        case let .number(value): try scalar.encode(value)
        case let .text(value): try scalar.encode(value)
        case let .boolean(value): try scalar.encode(value)
        case .null: try scalar.encodeNil()
        }
    }
}
