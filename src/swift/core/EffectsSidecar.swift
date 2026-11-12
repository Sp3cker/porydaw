import Foundation

/// The config-only, versioned companion to a song's unchanged MIDI bytes.
public struct EffectsSidecar: Equatable, Sendable, Codable {
    public var version: Int
    public var effects: [StoredEffect]

    public init(effects: [TrackEffect]) {
        version = 2
        self.effects = effects.map { (effect: TrackEffect) in StoredEffect(effect) }
        self.effects.sort { (left: StoredEffect, right: StoredEffect) in left.track < right.track }
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
        classUID = String(unsafeUninitializedCapacity: plugin.classUID.count * 2) {
            (buffer: UnsafeMutableBufferPointer<UInt8>) -> Int in
            var output = OutputSpan<UInt8>(buffer: buffer, initializedCount: 0)
            for byte in plugin.classUID {
                let high = byte >> 4
                let low = byte & 0xF
                output.append(high < 10 ? 48 + high : 87 + high)
                output.append(low < 10 ? 48 + low : 87 + low)
            }
            return output.count
        }
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
        var uid: [UInt8] = []
        uid.reserveCapacity(classUID.utf8.count / 2)
        var hex = classUID.utf8.makeIterator()
        while let high = hex.next(), let low = hex.next() {
            let highNibble = high <= 57 ? high - 48 : high - 87
            let lowNibble = low <= 57 ? low - 48 : low - 87
            uid.append(highNibble << 4 | lowNibble)
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
