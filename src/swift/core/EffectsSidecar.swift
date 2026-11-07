import Foundation

/// The config-only, versioned companion to a song's unchanged MIDI bytes.
public struct EffectsSidecar: Equatable, Sendable, Codable {
    public var version: Int
    public var effects: [StoredEffect]

    public init(effects: [TrackEffect]) {
        version = 2
        self.effects = effects.sorted { (left: TrackEffect, right: TrackEffect) in
            left.config.track < right.config.track
        }.map { (effect: TrackEffect) in StoredEffect(effect) }
    }

    private enum CodingKeys: String, CodingKey { case version, effects }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        guard version == 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: values, debugDescription: "Unsupported MIDI-effects version.")
        }
        effects = try values.decode([StoredEffect].self, forKey: .effects)
    }

    /// Encodes keys deterministically; binary plugin state uses Codable's base64 Data form.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

/// A field-by-field disk representation of an effect, with a hexadecimal class UID.
public struct StoredEffect: Equatable, Sendable, Codable {
    public let id: EffectID
    public let track: Int
    public let modulePath: String
    public let classUID: String
    public let name: String
    public let input: EffectInput
    public let pacing: EffectPacing
    public let prerollBars: Int
    public let component: Data?
    public let controller: Data?

    public init(_ effect: TrackEffect) {
        id = effect.id
        track = effect.config.track
        let plugin = effect.config.plugin
        modulePath = plugin.modulePath
        classUID = plugin.classUID.map { (byte: UInt8) in String(format: "%02x", byte) }.joined()
        name = plugin.name
        input = plugin.input
        pacing = plugin.pacing
        prerollBars = plugin.prerollBars
        component = effect.pluginState.map { (state: PluginStateBlob) in Data(state.component) }
        controller = effect.pluginState.map { (state: PluginStateBlob) in Data(state.controller) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, track, modulePath, classUID, name, input, pacing, prerollBars, component, controller
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(EffectID.self, forKey: .id)
        track = try values.decode(Int.self, forKey: .track)
        modulePath = try values.decode(String.self, forKey: .modulePath)
        classUID = try values.decode(String.self, forKey: .classUID)
        name = try values.decode(String.self, forKey: .name)
        input = try values.decode(EffectInput.self, forKey: .input)
        pacing = try values.decode(EffectPacing.self, forKey: .pacing)
        prerollBars = try values.decode(Int.self, forKey: .prerollBars)
        component = try values.decodeIfPresent(Data.self, forKey: .component)
        controller = try values.decodeIfPresent(Data.self, forKey: .controller)
        guard id.raw < UInt64.max,
            classUID.utf8.count == 32,
            classUID.utf8.allSatisfy({ (byte: UInt8) in
                (48...57).contains(byte) || (97...102).contains(byte)
            }),
            (0...2).contains(prerollBars),
            (component == nil) == (controller == nil)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .classUID, in: values, debugDescription: "Invalid MIDI-effect configuration or state.")
        }
    }

    /// Restores the validated UID and opaque state without altering song data.
    public var effect: TrackEffect {
        let hex = Array(classUID.utf8)
        let uid = stride(from: 0, to: hex.count, by: 2).map { (offset: Int) in
            let high = hex[offset] <= 57 ? hex[offset] - 48 : hex[offset] - 87
            let low = hex[offset + 1] <= 57 ? hex[offset + 1] - 48 : hex[offset + 1] - 87
            return high << 4 | low
        }
        let state: PluginStateBlob?
        if let component, let controller {
            state = PluginStateBlob(component: Array(component), controller: Array(controller))
        } else {
            state = nil
        }
        return TrackEffect(
            id: id,
            config: TrackEffectConfig(
                track: track,
                plugin: PluginEffectConfig(
                    modulePath: modulePath, classUID: uid, name: name,
                    input: input, pacing: pacing, prerollBars: prerollBars)),
            pluginState: state)
    }
}
