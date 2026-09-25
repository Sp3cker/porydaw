import Foundation
import PorydawCore
import PorydawPlaybackNative
import QtBridge
import PorydawAppAudio

/// User-wide audio configuration, kept separate from the song's undoable flags.
public struct EngineSettings: Equatable {
    public var mixer = "ipatix"
    public var maxPcmChannels = 5
    public var mixRate = 13_379
    public var analogFilter = false

    public init() {}

    public init(mixer: String, maxPcmChannels: String, mixRate: String, analogFilter: String) {
        self.mixer = mixer == "sappy" ? "sappy" : "ipatix"
        self.maxPcmChannels = min(Int(MAX_PCM_CHANNELS), max(1, Int(maxPcmChannels) ?? 1))
        let rate = Float(mixRate) ?? 13_379
        self.mixRate = rate >= 0 && rate.isFinite ? Int(rate.rounded()) : 13_379
        self.analogFilter = analogFilter.lowercased() == "true"
    }

    func apply(to settings: inout AudioSettings) {
        settings.pcmMixer = mixer == "sappy" ? M4A_PCM_MIXER_SAPPY : M4A_PCM_MIXER_IPATIX
        settings.maxPcmChannels = UInt8(maxPcmChannels)
        settings.pcmMixRate = Float(mixRate)
        settings.analogFilter = analogFilter
    }
}

/// The dialog edits a draft. Cancel discards it; Apply and OK commit it to
/// the audio owner and to the selected document's ordinary save snapshot.
@MainActor
@QtBridgeable
public final class EngineSettingsStore: QmlInstantiableStatus {
    @QtTracked public var mixer = "ipatix"
    @QtTracked public var maximumPcmChannels = Int(MAX_PCM_CHANNELS)
    @QtTracked public var maxPcmChannels = 5
    @QtTracked public var mixRate = 13_379
    @QtTracked public var analogFilter = false
    @QtTracked public var songAvailable = false
    @QtTracked public var songLabel = ""
    @QtTracked public var voicegroup = ""
    public var voicegroups: [String] = []
    @QtTracked public var masterVolume = 127
    @QtTracked public var reverb = -1
    @QtTracked public var priority = 0
    @QtTracked public var exactGate = false
    @QtTracked public var extendedClocks = false
    @QtTracked public var noCompression = false
    @QtTracked public var isApplying = false
    @QtTracked public var revision = 0

    private weak var session: ApplicationSession?
    private var committed = EngineSettings()
    private var target: DocumentSession?

    public required init() {}
    public func componentComplete() {}

    @QtIgnored
    public func attach(session: ApplicationSession) {
        self.session = session
    }

    public func restore(mixer: String, maxPcmChannels: String, mixRate: String,
                        analogFilter: String) {
        committed = EngineSettings(mixer: mixer, maxPcmChannels: maxPcmChannels,
                                   mixRate: mixRate, analogFilter: analogFilter)
        session?.setEngineSettings(committed)
        resetEngine()
    }

    public func open() {
        resetEngine()
        target = session?.selectedDocument
        songAvailable = target != nil
        songLabel = session?.settingsSongLabel() ?? ""
        let args = session?.settingsVoicegroupArgs() ?? []
        voicegroups = args.map(VoiceListSemantics.voicegroupDisplayName)
        guard let config = target?.document.state.config else { return }
        voicegroup = VoiceListSemantics.voicegroupDisplayName(config.voicegroupArgument)
        masterVolume = config.masterVolume
        reverb = config.reverb ?? -1
        priority = config.priority
        exactGate = config.exactGate
        extendedClocks = config.extendedClocks
        noCompression = config.noCompression
    }

    public func restoreDefaults() {
        let defaults = EngineSettings()
        mixer = defaults.mixer
        maxPcmChannels = defaults.maxPcmChannels
        mixRate = defaults.mixRate
        analogFilter = defaults.analogFilter
    }

    public func changeMixer(value: String) { mixer = value }
    public func changeMaxPcmChannels(value: Int) { maxPcmChannels = value }
    public func changeMixRate(value: Int) { mixRate = value }
    public func changeAnalogFilter(value: Bool) { analogFilter = value }
    public func changeVoicegroup(value: String) { voicegroup = value }
    public func changeMasterVolume(value: Int) { masterVolume = value }
    public func changeReverb(value: Int) { reverb = value }
    public func changePriority(value: Int) { priority = value }
    public func changeExactGate(value: Bool) { exactGate = value }
    public func changeExtendedClocks(value: Bool) { extendedClocks = value }
    public func changeNoCompression(value: Bool) { noCompression = value }

    public func apply() {
        guard !isApplying else { return }
        let engine = EngineSettings(mixer: mixer, maxPcmChannels: String(maxPcmChannels),
                                    mixRate: String(mixRate), analogFilter: String(analogFilter))
        if engine != committed {
            committed = engine
            session?.setEngineSettings(engine)
            revision &+= 1
        }
        guard let target, session?.selectedDocument === target else { return }
        let arg = VoiceListSemantics.voicegroupArg(
            fromDisplay: voicegroup.trimmingCharacters(in: .whitespacesAndNewlines),
            knownArgs: session?.settingsVoicegroupArgs() ?? [])
        let volume = masterVolume
        let songReverb = reverb
        let songPriority = priority
        let gate = exactGate
        let clocks = extendedClocks
        let compression = noCompression
        isApplying = true
        Task { [weak self, weak target] in
            guard let self, let target else { return }
            do {
                if !arg.isEmpty && arg != target.document.state.config.voicegroupArgument {
                    try await target.selectVoicegroup(arg)
                }
                if self.session?.selectedDocument === target, !target.isClosed {
                    let original = target.document.state.config
                    var config = original
                    config.masterVolume = volume
                    config.reverb = songReverb == -1 ? nil : songReverb
                    config.priority = songPriority
                    config.exactGate = gate
                    config.extendedClocks = clocks
                    config.noCompression = compression
                    if config != original { target.document.setConfig(config) }
                }
            } catch {
                self.session?.reportSettingsFailure(String(describing: error))
            }
            self.isApplying = false
        }
    }

    private func resetEngine() {
        mixer = committed.mixer
        maxPcmChannels = committed.maxPcmChannels
        mixRate = committed.mixRate
        analogFilter = committed.analogFilter
    }
}
