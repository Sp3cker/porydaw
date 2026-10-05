import Foundation
import PorydawDocument
import PorydawProject

/// Application-wide persistence of the editor view state: the drawer chrome,
/// the workspace tab recipe, and the compact `editorDrawer/automationLanes` JSON blob.
public enum EditorViewStatePreferences {
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
    private static func loadSection(
        _ name: String, defaultVisible: Bool,
        store: PreferencesStore
    ) -> DrawerChromeSection {
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
        for (name, section) in [
            ("velocity", state.velocity),
            ("automation", state.automation),
            ("voiceChanges", state.voiceChanges),
        ] {
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
        return WorkspaceTabRecipe(
            projectPath: saved.projectPath,
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
                if EditorLaneState.validRow(row), let height = integer(raw, maximum: Int32.max) {
                    state.laneHeights[row] = clampHeight(height)
                }
            }
        }
        if case let .object(ranges) = root["laneRanges"] {
            for (row, raw) in ranges {
                if EditorLaneState.validRow(row), let range = integer(raw, maximum: 127) {
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
        let heights = state.laneHeights.filter { EditorLaneState.validRow($0.key) && $0.value >= 0 }
        let ranges = state.laneRanges.filter {
            EditorLaneState.validRow($0.key) && (0...127).contains($0.value)
        }
        let empty = state.emptyLanes.sorted(by: laneOrder).map(laneObject)
        let hidden = state.hiddenLanes.filter(EditorLaneState.validLane).map(laneObject)
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

    private static func integer(_ value: JSONValue?, maximum: Int32) -> Int? {
        guard case let .number(raw) = value, raw.isFinite,
            raw.rounded(.towardZero) == raw,
            raw >= 0, raw <= Double(maximum)
        else { return nil }
        return Int(raw)
    }

    private static func decodeLane(_ value: JSONValue) -> EditorLaneState.Lane? {
        guard case let .object(row) = value,
            let track = integer(row["track"], maximum: 15),
            let controller = integer(row["cc"], maximum: 255)
        else { return nil }
        let lane = EditorLaneState.Lane(track: track, controller: controller)
        return EditorLaneState.validLane(lane) ? lane : nil
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
        if scalar.decodeNil() {
            self = .null
        } else if let value = try? scalar.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? scalar.decode(Double.self) {
            self = .number(value)
        } else if let value = try? scalar.decode(String.self) {
            self = .text(value)
        } else if let value = try? scalar.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try scalar.decode([JSONValue].self))
        }
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
