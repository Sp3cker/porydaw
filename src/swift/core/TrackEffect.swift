/// A session-stable identity for a track's effect.
public struct EffectID: Hashable, Sendable, Codable {
    public let raw: UInt64

    public init(raw: UInt64) {
        self.raw = raw
    }
}

public enum EffectInput: Int, Sendable, Codable {
    case none = 0
    case trackNotes = 1
}

public enum EffectPacing: Int, Sendable, Codable {
    case offline = 0
    case realtime = 1
}

/// The selected plugin and its capture configuration.
public struct PluginEffectConfig: Equatable, Sendable, Codable {
    public var modulePath: String
    public var classUID: [UInt8]
    public var name: String
    public var input: EffectInput
    public var pacing: EffectPacing
    public var prerollBars: Int

    public init(
        modulePath: String, classUID: [UInt8], name: String,
        input: EffectInput, pacing: EffectPacing, prerollBars: Int
    ) {
        self.modulePath = modulePath
        self.classUID = classUID
        self.name = name
        self.input = input
        self.pacing = pacing
        self.prerollBars = prerollBars
    }
}

/// A whole-track plugin insert, addressed by engine track.
public struct TrackEffectConfig: Equatable, Sendable {
    public var track: Int
    public var plugin: PluginEffectConfig

    public init(track: Int, plugin: PluginEffectConfig) {
        self.track = track
        self.plugin = plugin
    }
}

/// Opaque component and controller state captured from a plugin.
public struct PluginStateBlob: Equatable, Sendable, Codable {
    public var component: [UInt8]
    public var controller: [UInt8]

    public init(component: [UInt8], controller: [UInt8]) {
        self.component = component
        self.controller = controller
    }
}

/// Undoable configuration and the last recorded plugin settings.
public struct TrackEffect: Equatable, Sendable {
    public let id: EffectID
    public var config: TrackEffectConfig
    public var pluginState: PluginStateBlob?

    public init(id: EffectID, config: TrackEffectConfig, pluginState: PluginStateBlob? = nil) {
        self.id = id
        self.config = config
        self.pluginState = pluginState
    }
}
