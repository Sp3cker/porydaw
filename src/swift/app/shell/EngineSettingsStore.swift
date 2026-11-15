import Foundation
import PorydawCore
import PorydawDocument
import PorydawPlaybackNative
import QtBridge
import PorydawAppAudio
import PorydawAppPresentation

/// User-wide audio configuration, kept separate from the song's undoable flags.
public struct EngineSettings: Equatable {
    public var mixer = "ipatix"
    public var maxPcmChannels = 5
    public var mixRate = 13_379
    public var analogFilter = false

    public init() {}

    public init(mixer: String, maxPcmChannels: String, mixRate: String, analogFilter: String) {
        self.mixer = mixer == "sappy" ? "sappy" : "ipatix"
        self.maxPcmChannels = min(Int(MAX_PCM_CHANNELS), max(1, Int(maxPcmChannels) ?? 5))
        let rate = Float(mixRate) ?? 13_379
        self.mixRate = rate >= 0 && rate.isFinite ? Int(rate.rounded()) : 13_379
        self.analogFilter = analogFilter.lowercased() == "true"
    }

    init(mixer: String, maxPcmChannels: Int, mixRate: Int, analogFilter: Bool) {
        self.mixer = mixer == "sappy" ? "sappy" : "ipatix"
        self.maxPcmChannels = min(Int(MAX_PCM_CHANNELS), max(1, maxPcmChannels))
        self.mixRate = mixRate >= 0 ? mixRate : 13_379
        self.analogFilter = analogFilter
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
public final class EngineSettingsStore: QmlInstantiableStatus, QmlUncreatable {
    @QtTracked public var channelsFormat = NumberFieldFormat(kind: .channels)
    @QtTracked public var reverbFormat = NumberFieldFormat(kind: .reverb)
    @QtTracked public var mixer = "ipatix"
    @QtTracked public var maximumPcmChannels = Int(MAX_PCM_CHANNELS)
    @QtTracked public var maxPcmChannels = 5
    @QtTracked public var mixRate = 13_379
    @QtTracked public var analogFilter = false
    @QtTracked public var cpuBudgetCycles = 60_000
    @QtTracked public var cpuBudgetPercent = 72
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
    public var masterTuningUnits: Int = 0
    public var masterTuningFrequencyHz: Double = 440
    public var masterTuningFrequencyText: String = "440.000"
    public var masterTuningNominalFrequencyText: String = "440.000"
    public var masterTuningCents: Double = 0
    public var masterTuningCentsText: String = "0.0000"
    public var masterTuningMinimumUnits: Int = -64
    public var masterTuningMaximumUnits: Int = 63
    public var masterTuningEdited: Bool = false
    public var songHasTuningEvents: Bool = false
    public var settingsError: String = ""
    @QtTracked public var isApplying = false
    @QtTracked public var revision = 0

    private weak var session: ApplicationSession?
    private var committed = EngineSettings()
    private var target: DocumentSession?
    private var tuningInputValid = true
    private var applyTask: Task<Void, Never>?

    public required init() {}

    isolated deinit { applyTask?.cancel() }
    public func componentComplete() {}

    @QtIgnored
    public func attach(session: ApplicationSession) {
        self.session = session
    }

    public func restoreFromPreferences() {
        let store = PreferencesStore()
        let legacyBudgetKey = "engine.cpuBudgetPercent"
        let budgetKey = "engine.cpuBudgetCycles"
        if !store.hasValue(key: budgetKey), store.hasValue(key: legacyBudgetKey) {
            let percent = store.int(key: legacyBudgetKey, fallback: 100)
            if percent != 100 {
                let cycles = (Double(percent) * 837.76).rounded()
                store.setInt(key: budgetKey, value: Int(min(280_896, max(1_000, cycles))))
            }
            store.remove(key: legacyBudgetKey)
            store.synchronize()
        }
        let budget = min(280_896, max(1_000, store.int(key: budgetKey, fallback: 60_000)))
        cpuBudgetCycles = budget
        cpuBudgetPercent = Int((Double(budget) * 100 / 83_776).rounded())
        committed = EngineSettings(
            mixer: store.string(key: "engine.pcmMixer", fallback: "ipatix"),
            maxPcmChannels: store.int(key: "engine.maxPcmChannels", fallback: 5),
            mixRate: store.int(key: "engine.pcmMixRate", fallback: 13_379),
            analogFilter: store.bool(key: "engine.analogFilter", fallback: false))
        session?.setEngineSettings(committed)
        resetEngine()
    }

    public func open() {
        guard !isApplying else { return }
        settingsError = ""
        tuningInputValid = true
        masterTuningEdited = false
        resetEngine()
        target = session?.selectedDocument
        songAvailable = target != nil
        refreshTuningEvents()
        songLabel = session?.settingsSongLabel() ?? ""
        refreshVoicegroups()
        guard let config = target?.document.state.config else { return }
        voicegroup = VoiceListSemantics.voicegroupDisplayName(config.voicegroupArgument)
        masterVolume = config.masterVolume
        reverb = config.reverb ?? -1
        priority = config.priority
        exactGate = config.exactGate
        extendedClocks = config.extendedClocks
        noCompression = config.noCompression
        if let document = target?.document {
            updateMasterTuningDraft(units: document.masterTuningUnits)
        }
    }

    @QtIgnored
    public func refreshVoicegroups() {
        voicegroups = (session?.settingsVoicegroupArgs() ?? [])
            .map(VoiceListSemantics.voicegroupDisplayName)
    }

    public func restoreDefaults() {
        let defaults = EngineSettings()
        mixer = defaults.mixer
        maxPcmChannels = defaults.maxPcmChannels
        mixRate = defaults.mixRate
        analogFilter = defaults.analogFilter
        changeCpuBudgetCycles(value: 60_000)
    }

    public func changeMixer(value: String) { mixer = value }
    public func changeMaxPcmChannels(value: Int) { maxPcmChannels = value }
    public func changeMixRate(value: Int) { mixRate = value }
    public func changeAnalogFilter(value: Bool) { analogFilter = value }
    public func changeCpuBudgetCycles(value: Int) {
        let budget = min(280_896, max(1_000, value))
        guard budget != cpuBudgetCycles else { return }
        cpuBudgetCycles = budget
        cpuBudgetPercent = Int((Double(budget) * 100 / 83_776).rounded())
        let store = PreferencesStore()
        store.setInt(key: "engine.cpuBudgetCycles", value: budget)
        store.remove(key: "engine.cpuBudgetPercent")
        store.synchronize()
    }
    public func changeVoicegroup(value: String) { voicegroup = value }
    public func changeMasterVolume(value: Int) { masterVolume = value }
    public func changeReverb(value: Int) { reverb = value }
    public func changePriority(value: Int) { priority = value }
    public func changeExactGate(value: Bool) { exactGate = value }
    public func changeExtendedClocks(value: Bool) { extendedClocks = value }
    public func changeNoCompression(value: Bool) { noCompression = value }

    private func refreshTuningEvents() {
        songHasTuningEvents =
            target?.document.state.file.chunks.contains { (chunk: MidiChunk) in
                chunk.events.contains { (event: MidiEvent) in
                    guard case .channel(let status, let controller, _) = event.payload else { return false }
                    return status >> 4 == 0xB && controller == TimeDefaults.ccFineTune
                }
            } ?? false
    }

    private func validateMasterTuning() -> Bool {
        guard tuningInputValid else { return false }
        guard (-64...63).contains(masterTuningUnits) else {
            settingsError =
                "Master tuning must be −64…+63 units (1/64 semitone per unit). Enter a supported A4 frequency or reset to 440 Hz."
            return false
        }
        settingsError = ""
        return true
    }

    private func updateMasterTuningDraft(units: Int) {
        masterTuningUnits = units
        masterTuningFrequencyHz = MasterTuning.frequencyHz(units: units)
        masterTuningNominalFrequencyText = String(format: "%.3f", masterTuningFrequencyHz)
        masterTuningFrequencyText = masterTuningNominalFrequencyText
        masterTuningCents = Double(units) * 100 / 64
        masterTuningCentsText = String(format: "%.4f", masterTuningCents)
    }

    /// Requests a uniform master tune, replacing all TUNE automation on Apply.
    public func changeMasterTuningUnits(value: Int) {
        guard !isApplying else { return }
        masterTuningEdited = true
        updateMasterTuningDraft(units: value)
        tuningInputValid = true
        _ = validateMasterTuning()
    }

    /// Quantizes a requested nominal A4 frequency to the nearest TUNE unit.
    public func changeMasterTuningFrequency(text: String) {
        guard !isApplying else { return }
        masterTuningEdited = true
        masterTuningFrequencyText = text
        do {
            guard let frequency = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                tuningInputValid = false
                settingsError = "Enter a finite A4 frequency in Hz, for example 440 or 450."
                return
            }
            let units = try MasterTuning.units(frequencyHz: frequency)
            changeMasterTuningUnits(value: units)
        } catch {
            tuningInputValid = false
            settingsError = error.localizedDescription
        }
    }

    private func commitEngine(_ engine: EngineSettings) {
        guard engine != committed else { return }
        committed = engine
        session?.setEngineSettings(engine)
        revision &+= 1
        let store = PreferencesStore()
        store.setString(key: "engine.pcmMixer", value: engine.mixer)
        store.setInt(key: "engine.maxPcmChannels", value: engine.maxPcmChannels)
        store.setInt(key: "engine.pcmMixRate", value: engine.mixRate)
        store.setBool(key: "engine.analogFilter", value: engine.analogFilter)
        store.synchronize()
    }

    public func apply() {
        guard !isApplying else { return }
        let engine = EngineSettings(
            mixer: mixer, maxPcmChannels: String(maxPcmChannels),
            mixRate: String(mixRate), analogFilter: String(analogFilter))
        guard let target else {
            commitEngine(engine)
            settingsError = ""
            applySucceeded()
            return
        }
        guard session?.selectedDocument === target, !target.isClosed else {
            settingsError = "The selected song changed. Close Settings and reopen it for the song you want to edit."
            return
        }
        guard validateMasterTuning() else { return }
        let arg = VoiceListSemantics.voicegroupArg(
            fromDisplay: voicegroup.trimmingCharacters(in: .whitespacesAndNewlines),
            knownArgs: session?.settingsVoicegroupArgs() ?? [])
        let volume = masterVolume
        let songReverb = reverb
        let songPriority = priority
        let gate = exactGate
        let clocks = extendedClocks
        let compression = noCompression
        let tuning = masterTuningUnits
        let replaceTuning = masterTuningEdited
        isApplying = true
        applyTask = Task { [weak self, target] in
            guard let self else { return }
            var succeeded = false
            defer {
                self.isApplying = false
                self.applyTask = nil
                if succeeded { self.applySucceeded() }
            }
            do {
                guard !Task.isCancelled, self.session?.selectedDocument === target,
                    self.target === target, !target.isClosed
                else {
                    self.settingsError =
                        "The selected song changed before Settings could be applied. Reopen Settings for the intended song."
                    return
                }
                guard self.validateMasterTuning() else { return }
                if replaceTuning {
                    try target.document.setMasterTuning(units: tuning)
                    self.masterTuningEdited = false
                    self.refreshTuningEvents()
                }
                let original = target.document.state.config
                var config = original
                config.masterVolume = volume
                config.reverb = songReverb == -1 ? nil : songReverb
                config.priority = songPriority
                config.exactGate = gate
                config.extendedClocks = clocks
                config.noCompression = compression
                if config != original { target.document.setConfig(config) }
                if !arg.isEmpty && arg != target.document.state.config.voicegroupArgument {
                    try await target.selectVoicegroup(arg)
                }
                guard !Task.isCancelled, self.session?.selectedDocument === target,
                    self.target === target, !target.isClosed
                else {
                    self.settingsError =
                        "The selected song changed while applying Settings. Reopen Settings for the intended song."
                    return
                }
                self.commitEngine(engine)
                succeeded = true
            } catch {
                self.settingsError = error.localizedDescription
            }
        }
    }

    private func resetEngine() {
        mixer = committed.mixer
        maxPcmChannels = committed.maxPcmChannels
        mixRate = committed.mixRate
        analogFilter = committed.analogFilter
    }

    @QtSignal public func applySucceeded()
}
