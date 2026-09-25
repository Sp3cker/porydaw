import Foundation
import PorydawCore
import PorydawProject
import QtBridge

// MARK: - Voice list controller

/// One stable row handle of the 128-slot voice list. The controller keeps
/// the same 128 objects for the model's lifetime and rewrites their tracked
/// fields in place, so QML delegates observe property changes without the
/// model ever resetting. `typeIconKey` is voicetypeicons::iconKey
/// (glyph * 2 + altChip), -1 while the row publishes no type; `glyph` is the
/// Swift-side enum mirror of the same identity.
@MainActor
@QtBridgeable
public final class VoiceListRowHandle {
    public var slot: Int
    public var title: String
    public var typeName: String
    public var adsr: String
    public var typeIconKey: Int
    public var altChip: Bool
    public var used: Bool
    /// The Swift-side glyph identity; QML reads typeIconKey instead.
    @QtIgnored public var glyph: VoiceListGlyph?

    init(_ row: VoiceListRow) {
        slot = row.slot
        title = row.title
        typeName = row.typeName
        adsr = row.adsr
        typeIconKey = VoiceListSemantics.iconKey(glyph: row.glyph, altChip: row.altChip)
        altChip = row.altChip
        used = row.used
        glyph = row.glyph
    }

    @QtIgnored
    func apply(_ row: VoiceListRow) {
        title = row.title
        typeName = row.typeName
        adsr = row.adsr
        typeIconKey = VoiceListSemantics.iconKey(glyph: row.glyph, altChip: row.altChip)
        altChip = row.altChip
        used = row.used
        glyph = row.glyph
    }
}

/// One entry in the voicegroup selector's choice list: the display name the
/// combo shows plus the raw -G arg it stands for.
@MainActor
@QtBridgeable
public final class VoiceListArgChoice {
    public var name: String
    public var arg: String

    init(name: String, arg: String) {
        self.name = name
        self.arg = arg
    }
}

@MainActor
struct VoiceListEditOrigin {
    let session: DocumentSession
    let sourcePath: String
    let sectionLabel: String
}

/// Swift presenter for the voicegroup dock's list contract, mirroring
/// VoicegroupBrowser's observable behavior over DocumentSession's published
/// bank view (bankSlots/bankDirty/bankLoadName) instead of the native
/// LoadedBankView pointer. The 128 rows are stable object handles: binding,
/// loading, and edits rewrite them in place; the list is never rebuilt.
///
/// QML surface: `rows`/`argChoices` models, the tracked selector and
/// loading/selection state, and the invocable user actions (selectSlot,
/// revealSlot, commitVoicegroupSelection, pressVoice/releaseVoice,
/// requestSampleAudition, stopSampleAudition, requestNewVoicegroup,
/// requestNewSample, requestEditSample, slotIsMarkedUsed). revealSlot bumps
/// revealRequest with revealSlotId naming the row, the same reveal-counter
/// pattern SongListPresenter uses.
///
/// Ownership mirrors the native widget: the controller never mutates the
/// bank itself. User intents surface through the on* callbacks
/// (auditionVoice, voicegroupChangeRequested, voiceEditRequested,
/// newVoicegroupRequested, new/editSampleRequested, sampleAudition*), and
/// applyVoiceEdit routes a committed edit through
/// DocumentSession.applyBankEdit so undo/history stay canonical. The edit
/// path requires an explicit session binding: bindSession (or refresh,
/// which binds first) — the granular bindBank/setUsedVoices seam alone is
/// intentionally not edit-capable.
///
/// Refresh is explicit: DocumentSession.onChange is single-subscriber and
/// owned by DocumentWorkspace, so the owner calls refresh(from:) (bank +
/// selector + used marks) or the granular bindBank/setUsedVoices/
/// setCurrentVoicegroupArg/voiceChanged when its own change seam fires.
@MainActor
@QtBridgeable
public final class VoiceListController {
    public static let slotCount = 128

    /// The 128 stable row handles, always present; content rewrites in place.
    public var rows: QListModel<VoiceListRowHandle> = QListModel()
    /// The selector's -G choices (display name + raw arg per entry).
    public var argChoices: QListModel<VoiceListArgChoice> = QListModel()
    @QtIgnored public let editor = VoiceEditorController()

    public func editorModel() -> VoiceEditorController { editor }

    @QtTracked public var isLoading = false
    /// Whether a bank view is bound (setSource(nullptr) detaches).
    @QtTracked public var isBound = false
    @QtTracked public var bankDirty = false
    @QtTracked public var bankLoadName = ""
    /// The dock title: the native "Voicegroup" caption with the dirty star.
    @QtTracked public var panelTitle = "Voicegroup"
    /// The selector's editable text (the combo's currentText): the standing
    /// arg's display name, the user's in-progress text, or "Loading...".
    @QtTracked public var selectorText = ""
    @QtTracked public var selectorPlaceholder = "No song loaded"
    /// Whether user commits are live (bound and not loading).
    @QtTracked public var selectorEnabled = false
    /// The selected row's slot, or -1 with no selection (native currentSlot).
    @QtTracked public var currentSlot = -1
    /// The slot currently sounding under press-and-hold audition, or -1.
    @QtTracked public var soundingVoice = -1
    /// Incremented when revealSlot asks the shell to scroll; revealSlotId
    /// names the row. Never takes keyboard focus.
    @QtTracked public var revealRequest = 0
    @QtTracked public var revealSlotId = -1
    @QtTracked public var catalogRevision = 0

    // MARK: Outward intents (the native signals)

    /// velocity 0 releases. Routed to the audio preview seam by the owner.
    @QtIgnored public var onAuditionVoice: ((_ voice: Int, _ key: Int32, _ velocity: Int32) -> Void)?
    /// The user picked/typed a different voicegroup arg; the owner commits
    /// it as an undoable cfg edit and reflects it back via
    /// setCurrentVoicegroupArg.
    @QtIgnored public var onVoicegroupChangeRequested: ((_ arg: String) -> Void)?
    /// The user edited the selected voice; the owner applies it (as a song
    /// undo command) and reflects it back via voiceChanged / a bank rebind.
    /// `structural` means scalar pokes are not enough (type or symbol
    /// changed) and the bank needs a reload to audition.
    @QtIgnored public var onVoiceEditRequested: ((_ slot: Int, _ voice: BankVoice, _ structural: Bool) -> Void)?
    @QtIgnored public var onNewVoicegroupRequested: (() -> Void)?
    @QtIgnored public var onSaveRequested: (() -> Void)?
    /// "New sample…" beside the sample picker: create a sample and point
    /// this slot's voice at it; the owner runs the dialog and applies the
    /// assignment as an undo command.
    @QtIgnored public var onNewSampleRequested: ((_ slot: Int) -> Void)?
    /// "Edit…" beside the same picker: reopen this voice's committed sample.
    @QtIgnored public var onEditSampleRequested: ((_ slot: Int) -> Void)?
    /// The sample picker's browse audition: play the symbol's committed data
    /// through the selected voice's envelope.
    @QtIgnored public var onSampleAuditionRequested: ((_ symbol: String,
                                                      _ kind: VoiceListAuditionKind,
                                                      _ adsr: VoiceListAdsr) -> Void)?
    @QtIgnored public var onSampleAuditionStopRequested: (() -> Void)?

    // MARK: Bound model

    private var slots: [BankSlotView] = []
    private var usedVoices: Set<Int> = []
    /// The arg the selector currently stands at (native m_vgArg).
    private var currentArg = ""
    /// Last list handed to setVoicegroupChoices (native m_vgChoices).
    private var knownArgs: [String] = []

    /// Project-scoped catalogs the bank view cannot carry, injected by the
    /// owner exactly like setSource's symbol lists. The sample list feeds
    /// blank-slot templates; the keysplit table map classifies picker
    /// auditions; the synth symbol set classifies synth rows.
    @QtIgnored public var sampleChoices: [String] = [] {
        didSet { if sampleChoices != oldValue { rederiveRows() } }
    }
    @QtIgnored public var keysplitTables: [String: String] = [:]
    @QtIgnored public var synthSymbols: Set<String> = [] {
        didSet { if synthSymbols != oldValue { rederiveRows() } }
    }
    @QtIgnored public var synthDefinitions: [String: VgSynthDesc] = [:]
    @QtIgnored public var synthChoices: [String] = []
    @QtTracked public var canMintSynths = false
    @QtTracked public var pickerSampleDetail = ""
    @QtTracked public var pickerSampleLoop = false
    @QtIgnored public var adsrDefaults = VoiceListAdsrDefaults()
    @QtIgnored public var waveSymbols: [String] = []
    @QtIgnored public var drumkitSymbols: [String] = []

    public func sampleSymbols() -> [String] {
        sampleChoices.filter { !$0.contains("Phoneme") }
    }
    public func phonemeSymbols() -> [String] {
        sampleChoices.filter { $0.contains("Phoneme") }
    }
    public func samplePickerSymbols() -> [String] {
        keysplitTables.keys.sorted() + sampleChoices
    }
    public func waveChoices() -> [String] { waveSymbols }
    public func keysplitPickerSymbols() -> [String] { keysplitTables.keys.sorted() }
    public func drumkitChoices() -> [String] { drumkitSymbols }
    public func synthCatalogChoices() -> [String] { synthChoices }

    private weak var session: DocumentSession?

    public init() {
        rows.reset(to: (0..<VoiceListController.slotCount).map { slot in
            VoiceListRowHandle(VoiceListRow(slot: slot, title: String(format: "%03d", slot)))
        })
        editor.owner = self
    }

    // MARK: Session binding (the owner's refresh seam)

    /// Binds the document session the edit path applies through. Explicit:
    /// the granular bindBank/setUsedVoices seam alone is not edit-capable.
    /// The reference is weak — the workspace owns the session.
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

    /// Full owner-equivalent sync: bind the session, rebind the bank view,
    /// reflect the document's voicegroup arg, and re-derive the used marks.
    /// Call this from the owner's session-change seam when bank/document
    /// domains publish; it is the Swift counterpart of the native owner's
    /// rebuildVoicegroupPresentation sequence.
    @QtIgnored
    public func refresh(from session: DocumentSession) {
        bindSession(session)
        bindBank(slots: session.bankSlots, dirty: session.bankDirty,
                 loadName: session.bankLoadName)
        let arg = session.document.state.config.voicegroupArgument
        setCurrentVoicegroupArg(arg.isEmpty ? "_dummy" : arg)
        refreshUsedVoices(from: session)
    }

    /// The programs the song actually references, derived like the native
    /// SongView::usedVoices: first programs of used tracks plus every
    /// voice-change lane point across the 16 engine tracks.
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

    // MARK: Loading overlay

    /// The async-load placeholder: loading fills the stable rows with
    /// "NNN  Loading..." and disables the selector in place; nothing is
    /// hidden or rebuilt. Exiting — setLoading(false) or a bindBank — restores
    /// the selector text from the standing arg and re-derives the rows.
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

    // MARK: Bank binding (setSource)

    /// Publishes a bank view: slots is the copied BankSlotView array (nil
    /// detaches, like setSource(nullptr)). A nil bind also exits loading and
    /// drops the used marks; a live rebind keeps them — the owner re-marks
    /// after the new bank lands (native setSource clears kUsedRole only on
    /// a null view).
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

    /// One slot's voice changed outside the editor (an undo/redo, or the
    /// owner applying a requested edit): the owner hands over the changed
    /// slot's new view and only that row re-derives — the narrow-refresh
    /// counterpart of the native owner swapping the bank view before
    /// calling voiceChanged. Ignored while loading, matching the native
    /// early-out.
    @QtIgnored
    public func voiceChanged(_ slot: Int, slotView: BankSlotView? = nil) {
        guard !isLoading, slots.indices.contains(slot) else { return }
        if let slotView {
            slots[slot] = slotView
        }
        rederiveRow(slot)
        if slot == currentSlot { editor.refresh() }
    }

    // MARK: Selector

    /// The selector's -G choices (native args; display names are published).
    /// A same-list call is a no-op; the current arg never emits back.
    @QtIgnored
    public func setVoicegroupChoices(_ args: [String]) {
        guard args != knownArgs else { return }
        knownArgs = args
        argChoices.reset(to: args.map {
            VoiceListArgChoice(name: VoiceListSemantics.voicegroupDisplayName($0), arg: $0)
        })
    }

    /// Reflects the song's current -G arg without emitting (programmatic
    /// feedback never requests a change).
    @QtIgnored
    public func setCurrentVoicegroupArg(_ arg: String) {
        currentArg = arg
        selectorText = VoiceListSemantics.voicegroupDisplayName(arg)
    }

    /// A user commit of the selector text (activation or editing-finished):
    /// resolves the display text back to an arg and emits the change
    /// request. Suppressed while loading or unbound, and a no-op when the
    /// resolved arg already stands.
    public func commitVoicegroupSelection() {
        guard !isLoading, selectorEnabled else { return }
        let arg = VoiceListSemantics.voicegroupArg(fromDisplay: selectorText.trimmingCharacters(
            in: .whitespaces), knownArgs: knownArgs)
        guard arg != currentArg else { return }
        currentArg = arg
        onVoicegroupChangeRequested?(arg)
    }

    // MARK: Selection and reveal

    /// Selects a row; out-of-range slots are ignored (native selectSlot).
    public func selectSlot(slot: Int) {
        guard slot >= 0 && slot < rows.count else { return }
        currentSlot = slot
        editor.refresh()
    }

    /// Jump-from-context navigation: select the slot and ask the shell to
    /// scroll it into view (revealRequest/revealSlotId). Never takes
    /// keyboard focus.
    public func revealSlot(slot: Int) {
        selectSlot(slot: slot)
        guard slot >= 0 && slot < rows.count else { return }
        revealSlotId = slot
        revealRequest += 1
    }

    // MARK: Used marks

    /// The programs the song actually references; their rows render marked.
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

    public func slotIsMarkedUsed(slot: Int) -> Bool {
        slot >= 0 && slot < rows.count && rows[slot].used
    }

    // MARK: Audition

    /// Press-and-hold audition: press sounds the voice, releasing anywhere
    /// releases the note. Suppressed while loading; a press while another
    /// voice sounds releases it first.
    public func pressVoice(slot: Int) {
        releaseVoice()
        guard !isLoading, slots.indices.contains(slot) else { return }
        if let voice = slots[slot].voice,
           voice.macro == BankVoiceMacro.keysplit ||
               voice.macro == BankVoiceMacro.keysplitAll {
            guard let leaf = slots[slot].subvoiceMacro(
                forKey: Int(VoiceListSemantics.auditionKey)),
                  VoiceListSemantics.isDirectSoundFamily(leaf) ||
                  VoiceListSemantics.isWaveMacro(leaf) else { return }
        }
        soundingVoice = slot
        onAuditionVoice?(slot, VoiceListSemantics.auditionKey,
                         VoiceListSemantics.auditionVelocity)
    }

    public func releaseVoice() {
        guard soundingVoice >= 0 else { return }
        onAuditionVoice?(soundingVoice, VoiceListSemantics.auditionKey, 0)
        soundingVoice = -1
    }

    /// The sample picker's browse audition: the destination voice's
    /// envelope, so the browse sounds like the commit would. A keysplit
    /// row's envelope comes from its resolved sub-voice (a keysplit
    /// destination has no envelope of its own), so adsr stays default there.
    public func requestSampleAudition(symbol: String) {
        let voice = voiceAt(currentSlot)
        var kind = VoiceListAuditionKind.sample
        var adsr = VoiceListAdsr()
        if let voice, VoiceListSemantics.isWaveMacro(voice.macro) {
            kind = .wave
            adsr = VoiceListAdsr(attack: voice.attack & 0x07, decay: voice.decay & 0x07,
                                 sustain: voice.sustain & 0x0F, release: voice.release & 0x07)
        } else if keysplitTables[symbol] != nil {
            kind = .keysplit
        } else if let voice, VoiceListSemantics.isDirectSoundFamily(voice.macro) {
            adsr = VoiceListAdsr(attack: voice.attack & 0xFF, decay: voice.decay & 0xFF,
                                 sustain: voice.sustain & 0xFF, release: voice.release & 0xFF)
        }
        onSampleAuditionRequested?(symbol, kind, adsr)
    }

    public func stopSampleAudition() {
        onSampleAuditionStopRequested?()
    }

    // MARK: Edit intents

    /// The slot's draft: an editable voice edits in place; a blank slot
    /// materializes a template (DirectSound, key 60, the first sample
    /// symbol, and the project-typical envelope); read-only and broken
    /// slots — and slots the bank view doesn't cover — have none.
    @QtIgnored
    public func voiceDraft(_ slot: Int) -> Optional<VoiceListDraft> {
        guard slots.indices.contains(slot) else { return nil }
        switch slots[slot].kind {
        case BankSlotKind.editable:
            guard let voice = slots[slot].voice else { return nil }
            return VoiceListDraft(voice: voice, materializesBlank: false)
        case BankSlotKind.none:
            var voice = BankVoice()
            voice.symbol = sampleChoices.first ?? ""
            let adsr = VoiceListSemantics.defaultAdsr(adsrDefaults, macro: voice.macro,
                                                      symbol: voice.symbol)
            voice.attack = adsr.attack
            voice.release = adsr.release
            return VoiceListDraft(voice: voice, materializesBlank: true)
        default:
            return nil
        }
    }

    @QtIgnored
    public func noticeForSlot(_ slot: Int) -> String {
        guard slots.indices.contains(slot) else { return "Select a voice to edit it." }
        switch slots[slot].kind {
        case BankSlotKind.readOnlyVoice: return "Cry voices are read-only."
        case BankSlotKind.broken:
            return "This voice line couldn't be parsed; it is kept as-is."
        default: return "No voice is defined at this slot."
        }
    }

    /// Emits the edit intent for a slot: the owner applies it through the
    /// song undo stack and reflects it back. `structural` mirrors
    /// materializesBlank || vgVoiceStructuralChange; the native
    /// synth-to-synth scalar downgrade needs the synth catalog and is not
    /// reproduced here (see the uncovered-dependency report). No-ops for
    /// draft-less slots and unchanged non-materializing edits.
    @QtIgnored
    public func requestVoiceEdit(slot: Int, voice: BankVoice) {
        guard let draft = voiceDraft(slot) else { return }
        if !draft.materializesBlank && voice == draft.voice { return }
        let structural = draft.materializesBlank ||
            VoiceListSemantics.structuralChange(before: draft.voice, after: voice)
        onVoiceEditRequested?(slot, voice, structural)
    }

    /// Applies a committed voice edit through the session's canonical bank
    /// pipeline (service apply + undoable history action). Requires an
    /// explicit session binding (bindSession, or refresh which binds
    /// first); the granular bindBank seam alone is not edit-capable. The
    /// expected value is the slot's currently published voice — nil for a
    /// blank slot materialization. Conflicts propagate to the caller.
    @discardableResult
    @QtIgnored
    public func applyVoiceEdit(slot: Int, voice: BankVoice) async throws -> AppliedBankEdit {
        guard let session else {
            throw ProjectServiceError.operationFailed("No document session is bound.")
        }
        let expected = slots.indices.contains(slot) ? slots[slot].voice : nil
        return try await session.applyBankEdit(slot: slot, value: voice, expected: expected)
    }

    @QtIgnored
    public func synthDescriptor(symbol: String) -> Optional<VgSynthDesc> {
        synthDefinitions[symbol] ?? mintedSynthDesc(symbol: symbol)
    }

    @QtIgnored
    public func mintSynth(_ descriptor: VgSynthDesc) async throws -> String {
        guard let session else {
            throw ProjectServiceError.operationFailed("No document session is bound.")
        }
        return try await session.mintSynth(descriptor)
    }

    public func requestNewVoicegroup() {
        onNewVoicegroupRequested?()
    }

    public func requestSave() {
        onSaveRequested?()
    }

    public func requestNewSample(slot: Int) {
        onNewSampleRequested?(slot)
    }

    public func requestEditSample(slot: Int) {
        onEditSampleRequested?(slot)
    }

    // MARK: Row derivation

    private func voiceAt(_ slot: Int) -> BankVoice? {
        guard slots.indices.contains(slot) else { return nil }
        return slots[slot].voice
    }

    private func updateSelectorEnabled() {
        selectorEnabled = isBound && !isLoading
        if !isLoading {
            selectorPlaceholder = isBound ? "dummy" : "No song loaded"
        }
    }
    private func rederiveRows() {
        for slot in 0..<rows.count { rederiveRow(slot) }
    }

    /// QListModel snapshots each handle's role values. Mutating the handle
    /// alone leaves QML delegates on their original snapshot; setting the same
    /// handle back emits the model's dataChanged without replacing row identity.
    private func publishRow(_ value: VoiceListRow, at slot: Int) {
        let row = rows[slot]
        guard row.title != value.title || row.typeName != value.typeName ||
                row.adsr != value.adsr ||
                row.typeIconKey != VoiceListSemantics.iconKey(glyph: value.glyph,
                                                               altChip: value.altChip) ||
                row.altChip != value.altChip || row.used != value.used else { return }
        row.apply(value)
        rows[slot] = row
    }

    private func rederiveRow(_ slot: Int) {
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
