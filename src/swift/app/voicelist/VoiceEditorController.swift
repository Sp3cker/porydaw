import Foundation
import PorydawProject
import QtBridge

/// The selected bank slot's editable draft. Every commit rereads the current
/// lease after the preceding operation finishes, never replaying a stale copy.
@MainActor
@QtBridgeable
public final class VoiceEditorController {
    @QtTracked public var editable = false
    @QtTracked public var notice = ""
    @QtTracked public var macro = Int(BankVoiceMacro.directSound)
    @QtTracked public var symbol = ""
    @QtTracked public var attack = 0
    @QtTracked public var decay = 0
    @QtTracked public var sustain = 0
    @QtTracked public var release = 0
    @QtTracked public var sweep = 0
    @QtTracked public var duty = 2
    @QtTracked public var period = 0
    @QtTracked public var materializesBlank = false
    @QtTracked public var isSynth = false
    @QtTracked public var waveform = 0
    @QtTracked public var baseDuty = 128
    @QtTracked public var dutyStep = 0
    @QtTracked public var modDepth = 0
    @QtTracked public var phase = 0
    @QtIgnored public weak var owner: VoiceListController?
    private var pending: Task<Void, Never>?

    public init() {}

    @QtIgnored
    public func refresh() {
        guard let owner, owner.isBound, !owner.isLoading else {
            isSynth = false
            editable = false
            notice = ""
            return
        }
        let slot = owner.currentSlot
        guard let draft = owner.voiceDraft(slot) else {
            editable = false
            isSynth = false
            notice = owner.noticeForSlot(slot)
            return
        }
        let voice = draft.voice
        editable = true
        notice = ""
        materializesBlank = draft.materializesBlank
        macro = Int(voice.macro)
        symbol = voice.symbol
        let descriptor = owner.synthDescriptor(symbol: voice.symbol)
        isSynth = descriptor != nil
        let synth = descriptor ?? VgSynthDesc()
        waveform = synth.waveform
        baseDuty = synth.baseDuty
        dutyStep = synth.dutyStep
        modDepth = synth.modDepth
        phase = synth.phase
        attack = Int(voice.attack)
        decay = Int(voice.decay)
        sustain = Int(voice.sustain)
        release = Int(voice.release)
        sweep = Int(voice.sweep)
        duty = Int(voice.duty)
        period = Int(voice.period)
    }

    /// Commits one editor field as a bank history action. Values outside the
    /// instrument's hardware range and uneditable slots are silently refused.
    public func change(field: String, value: Int) {
        guard let owner, editable else { return }
        let slot = owner.currentSlot
        let previous = pending
        pending = Task { [weak self, weak owner] in
            await previous?.value
            guard let self, let owner, owner.currentSlot == slot,
                  let draft = owner.voiceDraft(slot),
                  draft.voice.macro != BankVoiceMacro.keysplit,
                  draft.voice.macro != BankVoiceMacro.keysplitAll else { return }
            var voice = draft.voice
            let cgb = !VoiceListSemantics.isDirectSoundFamily(voice.macro)
            let envelopeMax = cgb ? 7 : 255
            switch field {
            case "attack" where (0...envelopeMax).contains(value): voice.attack = Int32(value)
            case "decay" where (0...envelopeMax).contains(value): voice.decay = Int32(value)
            case "sustain" where (0...(cgb ? 15 : 255)).contains(value):
                voice.sustain = Int32(value)
            case "release" where (0...envelopeMax).contains(value): voice.release = Int32(value)
            case "sweep" where (0...127).contains(value): voice.sweep = Int32(value)
            case "duty" where (0...3).contains(value): voice.duty = Int32(value)
            case "period" where (0...1).contains(value): voice.period = Int32(value)
            default: return
            }
            guard draft.materializesBlank || voice != draft.voice else { return }
            do {
                _ = try await owner.applyVoiceEdit(slot: slot, voice: voice)
                self.refresh()
            } catch {
                self.refresh()
            }
        }
    }

    /// A type or symbol edit rebuilds the voicegroup's audio source. Synth
    /// is a pseudo-type: its voice remains DirectSound with a synth symbol.
    public func changeType(macro newMacro: Int, symbol newSymbol: String) {
        guard let owner, editable, (-1...12).contains(newMacro) else { return }
        let slot = owner.currentSlot
        let previous = pending
        pending = Task { [weak self, weak owner] in
            await previous?.value
            guard let self, let owner, owner.currentSlot == slot,
                  let draft = owner.voiceDraft(slot) else { return }
            let old = draft.voice
            var voice = old
            let selectedMacro = Int32(newMacro)
            var symbol = newSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
            if selectedMacro == -1 {
                guard owner.canMintSynths || !owner.synthChoices.isEmpty else { return }
                do {
                    if owner.synthDescriptor(symbol: newSymbol) != nil {
                        symbol = newSymbol
                    } else if owner.synthDescriptor(symbol: old.symbol) != nil {
                        symbol = old.symbol
                    } else if let existing = owner.synthChoices.first {
                        symbol = existing
                    } else {
                        symbol = try await owner.mintSynth(VgSynthDesc())
                    }
                    voice.macro = VoiceListSemantics.isDirectSoundFamily(old.macro)
                        ? old.macro : BankVoiceMacro.directSound
                    voice.symbol = symbol
                    voice.keysplitTable = ""
                } catch {
                    self.notice = String(describing: error)
                    return
                }
            } else if VoiceListSemantics.macroHasSymbol(selectedMacro) {
                let wave = selectedMacro == BankVoiceMacro.programmableWave ||
                    selectedMacro == BankVoiceMacro.programmableWaveAlt
                let drumkit = selectedMacro == BankVoiceMacro.keysplitAll
                let choices = wave ? owner.waveSymbols
                    : drumkit ? owner.drumkitSymbols : owner.sampleChoices
                if symbol.isEmpty || (selectedMacro != old.macro
                                      || (owner.synthDescriptor(symbol: old.symbol) != nil
                                          && symbol == old.symbol))
                    && !choices.contains(symbol) && owner.keysplitTables[symbol] == nil {
                    symbol = choices.first ?? ""
                }
                guard !symbol.isEmpty else { return }
                voice.symbol = symbol
                if drumkit {
                    voice.macro = BankVoiceMacro.keysplitAll
                    voice.keysplitTable = ""
                } else if !wave, let table = owner.keysplitTables[symbol] {
                    voice.macro = BankVoiceMacro.keysplit
                    voice.keysplitTable = table
                } else {
                    voice.macro = selectedMacro
                    voice.keysplitTable = ""
                }
            } else {
                voice.macro = selectedMacro
                voice.symbol = ""
                voice.keysplitTable = ""
            }
            let oldFamily = VoiceListSemantics.adsrFamily(forMacro: old.macro)
            let newFamily = VoiceListSemantics.adsrFamily(forMacro: voice.macro)
            if newFamily < 0 {
                voice.key = 60
                voice.pan = 0
                voice.sweep = 0
                voice.duty = 2
                voice.period = 0
                voice.attack = 0
                voice.decay = 0
                voice.sustain = 0
                voice.release = 0
            } else if oldFamily != newFamily {
                let envelope = VoiceListSemantics.defaultAdsr(
                    owner.adsrDefaults, macro: voice.macro, symbol: voice.symbol)
                voice.attack = envelope.attack
                voice.decay = envelope.decay
                voice.sustain = envelope.sustain
                voice.release = envelope.release
            }
            if newFamily >= 0 && !VoiceListSemantics.isDirectSoundFamily(voice.macro) {
                voice.attack = min(voice.attack, 7)
                voice.decay = min(voice.decay, 7)
                voice.sustain = min(voice.sustain, 15)
                voice.release = min(voice.release, 7)
            }
            guard draft.materializesBlank || voice != old else { return }
            do {
                _ = try await owner.applyVoiceEdit(slot: slot, voice: voice)
                if selectedMacro == -1 {
                    if let descriptor = owner.synthDescriptor(symbol: symbol) {
                        owner.synthDefinitions[symbol] = descriptor
                    }
                    owner.synthSymbols.insert(symbol)
                }
                self.refresh()
            } catch {
                self.refresh()
            }
        }
    }
    /// Resolves an edited synth descriptor, then changes the bank slot only
    /// after the new symbol can be minted. The save action persists both.
    public func changeSynth(field: String, value: Int) {
        guard let owner, editable, isSynth else { return }
        let slot = owner.currentSlot
        let previous = pending
        pending = Task { [weak self, weak owner] in
            await previous?.value
            guard let self, let owner, owner.currentSlot == slot,
                  let draft = owner.voiceDraft(slot),
                  var descriptor = owner.synthDescriptor(symbol: draft.voice.symbol) else { return }
            let old = descriptor
            switch field {
            case "waveform" where (0...2).contains(value):
                descriptor = VgSynthDesc(waveform: value)
            case "baseDuty" where (0...255).contains(value) && descriptor.waveform == 0:
                descriptor.baseDuty = value
            case "dutyStep" where (0...255).contains(value) && descriptor.waveform == 0:
                descriptor.dutyStep = value
            case "modDepth" where (0...255).contains(value) && descriptor.waveform == 0:
                descriptor.modDepth = value
            case "phase" where (0...255).contains(value) && descriptor.waveform == 0:
                descriptor.phase = value
            default: return
            }
            guard descriptor != old else { return }
            do {
                let symbol = try await owner.mintSynth(descriptor)
                guard owner.currentSlot == slot else { return }
                var voice = draft.voice
                voice.symbol = symbol
                _ = try await owner.applyVoiceEdit(slot: slot, voice: voice)
                owner.synthDefinitions[symbol] = descriptor
                owner.synthSymbols.insert(symbol)
                self.refresh()
            } catch {
                self.refresh()
                self.notice = String(describing: error)
            }
        }
    }
}
