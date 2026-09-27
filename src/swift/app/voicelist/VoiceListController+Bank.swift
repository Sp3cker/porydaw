import Foundation
import PorydawCore
import PorydawProject
import QtBridge

@MainActor
extension VoiceListController {
    /// Binds the weak document session used for edit commits.
    @QtIgnored
    public func bindSession(_ session: DocumentSession) {
        self.session = session
    }

    @QtIgnored
    func editOrigin() -> VoiceListEditOrigin? {
        guard let session else { return nil }
        return VoiceListEditOrigin(session: session,
                                   sourcePath: session.bankLease.sourcePath,
                                   sectionLabel: session.bankLease.sectionLabel)
    }

    @QtIgnored
    func isCurrentEditOrigin(_ origin: VoiceListEditOrigin) -> Bool {
        guard let session else { return false }
        return session === origin.session && !session.isClosed
            && session.bankLease.sourcePath == origin.sourcePath
            && session.bankLease.sectionLabel == origin.sectionLabel
    }

    /// Rebinds the bank, selector, and used marks from a session.
    @QtIgnored
    public func refresh(from session: DocumentSession) {
        bindSession(session)
        bindBank(slots: session.bankSlots, dirty: session.bankDirty,
                 loadName: session.bankLoadName)
        let arg = session.document.state.config.voicegroupArgument
        setCurrentVoicegroupArg(arg.isEmpty ? "_dummy" : arg)
        refreshUsedVoices(from: session)
    }

    /// Derives used programs from active tracks and voice-change lanes.
    @QtIgnored
    public func refreshUsedVoices(from session: DocumentSession) {
        var used = Set<Int>()
        for track in session.timeline.tracks where track.used && track.firstProgram >= 0 {
            used.insert(track.firstProgram)
        }
        for track in 0..<16 {
            for point in session.document.lanePoints(track: track, lane: .voice) {
                used.insert(point.value)
            }
        }
        setUsedVoices(used)
    }

    /// Rewrites stable row handles for the loading overlay.
    @QtIgnored
    public func setLoading(_ loading: Bool) {
        if loading == isLoading && !loading { return }
        isLoading = loading
        if loading {
            releaseVoice()
            selectorText = "Loading..."
            selectorPlaceholder = "Loading..."
        } else {
            selectorText = VoiceListSemantics.voicegroupDisplayName(currentArg)
        }
        rederiveRows()
        editor.refresh()
        updateSelectorEnabled()
    }

    /// Publishes a bank view without replacing the 128 row handles.
    @QtIgnored
    public func bindBank(slots newSlots: [BankSlotView]?, dirty: Bool = false,
                         loadName: String = "") {
        releaseVoice()
        let wasLoading = isLoading
        isLoading = false
        isBound = newSlots != nil
        slots = newSlots ?? []
        bankDirty = dirty
        bankLoadName = loadName
        panelTitle = dirty ? "Voicegroup*" : "Voicegroup"
        if wasLoading {
            selectorText = VoiceListSemantics.voicegroupDisplayName(currentArg)
        }
        if newSlots == nil {
            usedVoices = []
        }
        rederiveRows()
        editor.refresh()
        updateSelectorEnabled()
    }

    /// Re-derives one externally changed voice row unless loading.
    @QtIgnored
    public func voiceChanged(_ slot: Int, slotView: BankSlotView? = nil) {
        guard !isLoading, slots.indices.contains(slot) else { return }
        if let slotView {
            slots[slot] = slotView
        }
        rederiveRow(slot)
        if slot == currentSlot { editor.refresh() }
    }

    /// Publishes selector choices only when the arg list changes.
    @QtIgnored
    public func setVoicegroupChoices(_ args: [String]) {
        guard args != knownArgs else { return }
        knownArgs = args
        argChoices.reset(to: args.map {
            VoiceListArgChoice(name: VoiceListSemantics.voicegroupDisplayName($0), arg: $0)
        })
    }

    /// Reflects the current voicegroup arg without emitting a change intent.
    @QtIgnored
    public func setCurrentVoicegroupArg(_ arg: String) {
        currentArg = arg
        selectorText = VoiceListSemantics.voicegroupDisplayName(arg)
    }

    /// Reveals the track's first program or first voice-change value.
    @QtIgnored
    public func revealTrackVoice(track: Int, session: DocumentSession) {
        guard session.timeline.tracks.indices.contains(track) else { return }
        let first = session.timeline.tracks[track].firstProgram
        let program = first >= 0 ? first
            : session.document.lanePoints(track: track, lane: .voice).first?.value ?? -1
        guard program >= 0 else { return }
        revealSlot(slot: program)
    }

    /// Marks referenced programs on their existing row handles.
    @QtIgnored
    public func setUsedVoices(_ used: Set<Int>) {
        usedVoices = used
        for slot in 0..<rows.count {
            let row = rows[slot]
            let marked = used.contains(slot)
            guard row.used != marked else { continue }
            row.used = marked
            rows[slot] = row
        }
    }

    @QtIgnored
    func voiceAt(_ slot: Int) -> BankVoice? {
        guard slots.indices.contains(slot) else { return nil }
        return slots[slot].voice
    }

    @QtIgnored
    func updateSelectorEnabled() {
        selectorEnabled = isBound && !isLoading
        if !isLoading {
            selectorPlaceholder = isBound ? "dummy" : "No song loaded"
        }
    }

    @QtIgnored
    func rederiveRows() {
        for slot in 0..<rows.count { rederiveRow(slot) }
    }

    /// Reassigning a stable handle publishes its changed roles to QML.
    @QtIgnored
    func publishRow(_ value: VoiceListRow, at slot: Int) {
        let row = rows[slot]
        guard row.title != value.title || row.typeName != value.typeName ||
                row.adsr != value.adsr ||
                row.typeIconKey != VoiceListSemantics.iconKey(glyph: value.glyph,
                                                               altChip: value.altChip) ||
                row.altChip != value.altChip || row.used != value.used else { return }
        row.apply(value)
        rows[slot] = row
    }

    @QtIgnored
    func rederiveRow(_ slot: Int) {
        if isLoading {
            // The overlay rewrites the text cells only; used marks survive
            // (native setLoading never touches kUsedRole).
            publishRow(VoiceListRow(slot: slot,
                                    title: String(format: "%03d  Loading...", slot),
                                    used: usedVoices.contains(slot)), at: slot)
            return
        }
        // Blank slots render like their editor: a None-kind row is a
        // template the user can materialize.
        if slots.indices.contains(slot), slots[slot].kind == BankSlotKind.none {
            publishRow(VoiceListRow(slot: slot,
                                    title: String(format: "%03d  [Blank]", slot),
                                    used: usedVoices.contains(slot)), at: slot)
            return
        }
        // Parsed editable voices are authoritative for unsaved edits. Native
        // loaded-tone facts cover read-only and otherwise unparsed slots.
        if let voice = voiceAt(slot) {
            let synth = slots[slot].isSynth || synthSymbols.contains(voice.symbol)
            let typeByte = VoiceListSemantics.voiceType(forMacro: voice.macro)
            let typeName = VoiceListSemantics.typeDisplayName(typeByte: typeByte, synth: synth)
            let name = VoiceListSemantics.macroHasSymbol(voice.macro) ? voice.symbol : ""
            publishRow(VoiceListRow(
                slot: slot,
                title: VoiceListSemantics.voiceColumnText(slot: slot, symbol: name,
                                                         typeName: typeName),
                typeName: typeName,
                adsr: VoiceListSemantics.adsrText(voice),
                glyph: VoiceListSemantics.glyph(forTypeByte: typeByte, synth: synth),
                altChip: VoiceListSemantics.isAltChip(typeByte),
                used: usedVoices.contains(slot)), at: slot)
            return
        }
        if slots.indices.contains(slot), let tone = slots[slot].tone {
            let typeByte = UInt8(tone.type)
            let typeName = VoiceListSemantics.typeDisplayName(
                typeByte: typeByte, synth: tone.isSynth)
            let adsr = tone.adsr.map {
                "\($0.attack) \($0.decay) \($0.sustain) \($0.release)"
            } ?? ""
            publishRow(VoiceListRow(
                slot: slot,
                title: VoiceListSemantics.voiceColumnText(
                    slot: slot, symbol: tone.name, typeName: typeName),
                typeName: typeName,
                adsr: adsr,
                glyph: VoiceListSemantics.glyph(forTypeByte: typeByte, synth: tone.isSynth),
                altChip: VoiceListSemantics.isAltChip(typeByte),
                used: usedVoices.contains(slot)), at: slot)
            return
        }
        publishRow(VoiceListRow(slot: slot, title: String(format: "%03d", slot),
                                used: usedVoices.contains(slot)), at: slot)
    }
}
