import Foundation
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
    @QtIgnored public weak var owner: VoiceListController?
    @QtIgnored private var pending: Task<Void, Never>?

    public init() {}

    @QtIgnored
    public func refresh() {
        guard let owner, owner.isBound, !owner.isLoading else {
            editable = false
            notice = ""
            return
        }
        let slot = owner.currentSlot
        guard let draft = owner.voiceDraft(slot) else {
            editable = false
            notice = owner.noticeForSlot(slot)
            return
        }
        let voice = draft.voice
        editable = true
        notice = ""
        materializesBlank = draft.materializesBlank
        macro = Int(voice.macro)
        symbol = voice.symbol
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

    /// A type or symbol edit must rebuild the voicegroup's audio source.
    /// Nested keysplits and unresolved symbol names are not committed.
    public func changeType(macro newMacro: Int, symbol newSymbol: String) {
        guard let owner, editable, (0...12).contains(newMacro) else { return }
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
            if VoiceListSemantics.macroHasSymbol(selectedMacro) {
                let wave = selectedMacro == BankVoiceMacro.programmableWave ||
                    selectedMacro == BankVoiceMacro.programmableWaveAlt
                let drumkit = selectedMacro == BankVoiceMacro.keysplitAll
                let choices = wave ? owner.waveSymbols
                    : drumkit ? owner.drumkitSymbols : owner.sampleChoices
                if symbol.isEmpty || (!choices.contains(symbol)
                                       && owner.keysplitTables[symbol] == nil) {
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
                self.refresh()
            } catch {
                self.refresh()
            }
        }
    }
}
