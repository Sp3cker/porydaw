import Foundation
import CoreFoundation
import QtBridgeCpp

/// The historical QSettings workspace recipe. These keys are application-wide,
/// not part of a project's MIDI sidecar or the document's revision/history.
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
/// Chrome visibility, section heights and active page remain in the existing
/// QtCore.Settings-backed EditorDrawer; only the lane blob is owned here.
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
}

public enum EditorViewStateCodec {
    private static let lanesKey = "editorDrawer.automationLanes"

    /// Reads the same application preferences as QtCore.Settings on macOS.
    /// - Parameter applicationName: The `Qt.application.name` of the running shell.
    /// - Returns: The last successfully opened project and its saved tab recipe.
    public static func loadTabs(applicationName: String) -> WorkspaceTabRecipe {
        let store = SettingsStore(applicationName: applicationName)
        return WorkspaceTabRecipe(
            projectPath: store.string("lastProjectDir") ?? "",
            orderedSongs: store.strings("lastOpenSongs") ?? [],
            selectedSong: store.string("lastSongLabel") ?? "")
    }

    /// Saves the tab order and selection after a real tab transition.
    /// - Parameters:
    ///   - recipe: The opened project's live tab order and selection.
    ///   - applicationName: The running shell's settings identity.
    public static func saveTabs(_ recipe: WorkspaceTabRecipe, applicationName: String) {
        let store = SettingsStore(applicationName: applicationName)
        store.setString("lastProjectDir", recipe.projectPath)
        store.setStrings("lastOpenSongs", recipe.orderedSongs.isEmpty ? nil : recipe.orderedSongs)
        store.setString("lastSongLabel", recipe.orderedSongs.isEmpty ? nil : recipe.selectedSong)
        store.sync()
    }

    /// Decodes the lane blob without writing it back during startup. Malformed
    /// blob data defaults only lane fields; the existing drawer chrome survives.
    /// - Parameter applicationName: The running shell's settings identity.
    /// - Returns: The decoded lane preferences.
    public static func loadLanes(applicationName: String) -> EditorLaneState {
        let store = SettingsStore(applicationName: applicationName)
        guard let bytes = store.data(lanesKey) else { return EditorLaneState() }
        return decodeLanes(bytes)
    }

    /// Stores one canonical compact JSON object after a semantic lane change.
    /// - Parameters:
    ///   - state: The global editor lane preference.
    ///   - applicationName: The running shell's settings identity.
    public static func saveLanes(_ state: EditorLaneState, applicationName: String) {
        guard let bytes = encodeLanes(state) else { return }
        let store = SettingsStore(applicationName: applicationName)
        store.setData(lanesKey, bytes)
        store.sync()
    }

    /// Decodes the native lane-row grammar; an invalid member does not discard
    /// other valid members, and malformed JSON defaults only this blob.
    /// - Parameter bytes: QSettings' automationLanes QByteArray.
    /// - Returns: The valid lane members.
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

private struct SettingsStore {
    let applicationID: CFString

    init(applicationName: String) {
        applicationID = Self.cfString("com.sp3cker." + applicationName)
    }

    func string(_ key: String) -> String? {
        CFPreferencesCopyAppValue(Self.cfString(key), applicationID) as? String
    }

    func strings(_ key: String) -> [String]? {
        CFPreferencesCopyAppValue(Self.cfString(key), applicationID) as? [String]
    }

    func data(_ key: String) -> Data? {
        CFPreferencesCopyAppValue(Self.cfString(key), applicationID) as? Data
    }

    func setString(_ key: String, _ value: String?) {
        CFPreferencesSetAppValue(Self.cfString(key), value.map(Self.cfString), applicationID)
    }

    func setStrings(_ key: String, _ value: [String]?) {
        let array: CFArray? = value.map { strings in
            var callbacks = kCFTypeArrayCallBacks
            guard let result = CFArrayCreateMutable(kCFAllocatorDefault, strings.count, &callbacks)
            else { preconditionFailure("Settings array could not be allocated") }
            for string in strings {
                let element = Self.cfString(string)
                CFArrayAppendValue(result, Unmanaged.passUnretained(element).toOpaque())
            }
            return result as CFArray
        }
        CFPreferencesSetAppValue(Self.cfString(key), array, applicationID)
    }

    func setData(_ key: String, _ value: Data) {
        let bytes = value.withUnsafeBytes { buffer in
            CFDataCreate(kCFAllocatorDefault, buffer.bindMemory(to: UInt8.self).baseAddress,
                         value.count)
        }
        CFPreferencesSetAppValue(Self.cfString(key), bytes, applicationID)
    }

    func sync() { _ = CFPreferencesAppSynchronize(applicationID) }

    private static func cfString(_ text: String) -> CFString {
        guard let result = text.withCString({
            CFStringCreateWithCString(kCFAllocatorDefault, $0, CFStringBuiltInEncodings.UTF8.rawValue)
        }) else { preconditionFailure("Settings key could not be encoded") }
        return result
    }
}
