import Foundation
import PorydawCore
import PorydawDocument
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
public final class VoiceListController: QmlUncreatable {
    public static let slotCount = VoiceListSemantics.slotCount

    /// The 128 stable row handles, always present; content rewrites in place.
    public var rows: QListModel<VoiceListRowHandle> = QListModel()
    /// The selector's -G choices (display name + raw arg per entry).
    public var argChoices: QListModel<VoiceListArgChoice> = QListModel()
    public var samplePickerRows: QListModel<SamplePickerRow> = QListModel()
    public var samplePickerCount: Int = 0
    @QtIgnored var samplePickerFilter = ""
    @QtIgnored var samplePickerWaveMode = false
    @QtIgnored var samplePickerDetails: [String: String] = [:]
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
    @QtIgnored public var onSampleAuditionRequested:
        (
            (
                _ symbol: String,
                _ kind: VoiceListAuditionKind,
                _ adsr: VoiceListAdsr
            ) -> Void
        )?
    @QtIgnored public var onSampleAuditionStopRequested: (() -> Void)?
    /// Whether the New Voicegroup prompt is mounted. Owned by the controller
    /// so the dialog survives selector refreshes while it is open.
    @QtTracked public var newVoicegroupPrompt = false
    /// The prompt's in-progress name draft, mirrored from its text field.
    @QtTracked public var newVoicegroupName = ""
    /// The copy source's file name ("Copy of ..."), or "" with no source.
    @QtTracked public var newVoicegroupCopyLabel = ""
    /// Whether accept copies the current bank (false = dummy template).
    @QtTracked public var newVoicegroupUseCopy = true
    /// Refusal and failure messages for the create flow; never empty.
    @QtIgnored public var onNewVoicegroupFailed: ((_ message: String) -> Void)?
    /// The fork's showStatus line for a completed creation.
    @QtIgnored public var onStatusMessage: ((_ message: String) -> Void)?
    /// The project service behind the create op, installed by the owner.
    @QtIgnored public var projectService: ProjectService?

    // MARK: Bound model

    @QtIgnored var slots: [BankSlotView] = []
    @QtIgnored var usedVoices: Set<Int> = []
    /// The arg the selector currently stands at (native m_vgArg).
    @QtIgnored var currentArg = ""
    /// Last list handed to setVoicegroupChoices (native m_vgChoices).
    @QtIgnored var knownArgs: [String] = []

    /// Project-scoped catalogs are injected by ApplicationSession, which owns writes.
    /// QML observes the published synth and drumkit choices without mutating them.
    @QtIgnored public var sampleChoices: [String] = [] {
        didSet {
            if sampleChoices != oldValue {
                rederiveRows()
                refreshSamplePickerRows()
            }
        }
    }
    @QtIgnored public var keysplitTables: [String: String] = [:] {
        didSet { if keysplitTables != oldValue { refreshSamplePickerRows() } }
    }
    @QtIgnored public var synthSymbols: Set<String> = [] {
        didSet { if synthSymbols != oldValue { rederiveRows() } }
    }
    @QtIgnored public var synthDefinitions: [String: VgSynthDesc] = [:]
    public var synthChoices: [String] = []
    @QtTracked public var canMintSynths = false
    @QtIgnored public var pickerSampleInfo: [String: PickerSampleInfo] = [:] {
        didSet {
            if pickerSampleInfo != oldValue {
                refreshSamplePickerDetails()
                refreshSamplePickerRows()
            }
        }
    }
    @QtTracked public var pickerInfoRevision = 0
    @QtIgnored public var onPickerSampleInfoRequested: (() -> Void)?
    @QtIgnored public var adsrDefaults = VoiceListAdsrDefaults()
    @QtIgnored public var waveSymbols: [String] = [] {
        didSet { if waveSymbols != oldValue { refreshSamplePickerRows() } }
    }
    public var drumkitSymbols: [String] = []

    public func sampleDisplayName(symbol: String) -> String {
        Self.sampleDisplayName(symbol)
    }

    public func configureSamplePicker(filter: String, waveMode: Bool) {
        guard samplePickerFilter != filter || samplePickerWaveMode != waveMode else { return }
        samplePickerFilter = filter
        samplePickerWaveMode = waveMode
        refreshSamplePickerRows()
    }

    public func samplePickerRow(index: Int) -> Optional<SamplePickerRow> {
        guard index >= 0, index < samplePickerRows.count else { return nil }
        return samplePickerRows[index]
    }

    public func requestPickerSampleInfo() {
        onPickerSampleInfoRequested?()
    }

    @QtIgnored weak var session: DocumentSession?

    public init() {
        rows.reset(
            to: (0..<VoiceListController.slotCount).map { slot in
                VoiceListRowHandle(VoiceListRow(slot: slot, title: VoiceListSemantics.slotLabel(slot)))
            })
        editor.owner = self
    }

    // MARK: Selector

    /// A user commit of the selector text (activation or editing-finished):
    /// resolves the display text back to an arg and emits the change
    /// request. Suppressed while loading or unbound, and a no-op when the
    /// resolved arg already stands.
    public func commitVoicegroupSelection() {
        guard !isLoading, selectorEnabled else { return }
        let arg = VoiceListSemantics.voicegroupArg(
            fromDisplay: selectorText.trimmingCharacters(
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
            voice.macro == BankVoiceMacro.keysplit || voice.macro == BankVoiceMacro.keysplitAll
        {
            guard
                let leaf = slots[slot].subvoiceMacro(
                    forKey: Int(VoiceListSemantics.auditionKey)),
                VoiceListSemantics.isDirectSoundFamily(leaf) || VoiceListSemantics.isWaveMacro(leaf)
            else { return }
        }
        soundingVoice = slot
        onAuditionVoice?(
            slot, VoiceListSemantics.auditionKey,
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
            adsr = VoiceListAdsr(
                attack: voice.attack & 0x07, decay: voice.decay & 0x07,
                sustain: voice.sustain & 0x0F, release: voice.release & 0x07)
        } else if keysplitTables[symbol] != nil {
            kind = .keysplit
        } else if let voice, VoiceListSemantics.isDirectSoundFamily(voice.macro) {
            adsr = VoiceListAdsr(
                attack: voice.attack & 0xFF, decay: voice.decay & 0xFF,
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
            let adsr = VoiceListSemantics.defaultAdsr(
                adsrDefaults, macro: voice.macro,
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
        let structural =
            draft.materializesBlank || VoiceListSemantics.structuralChange(before: draft.voice, after: voice)
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

    // MARK: New voicegroup

    /// Opens the New Voicegroup prompt. Silent while unbound, loading, or
    /// already open: no dialog, no writes, no failure message.
    public func presentNewVoicegroup() {
        guard !newVoicegroupPrompt, !isLoading, let session, !session.isClosed else { return }
        let source = session.bankLease.id.sourceRelativePath
        if source.isEmpty {
            newVoicegroupCopyLabel = ""
            newVoicegroupUseCopy = false
        } else {
            newVoicegroupCopyLabel = URL(filePath: source).lastPathComponent
            newVoicegroupUseCopy = true
        }
        newVoicegroupName = ""
        newVoicegroupPrompt = true
    }

    /// The fork's name gate: letters, digits and underscores, leading letter.
    public func isValidVoicegroupName(name: String) -> Bool {
        ProjectService.isValidVoicegroupName(name: name)
    }

    /// Whether no catalog arg collides with the name. The dialog gates its
    /// Create button on this; accept rechecks before writing.
    public func newVoicegroupNameAvailable(name: String) -> Bool {
        !knownArgs.contains("_" + name.trimmingCharacters(in: .whitespaces))
    }

    public func cancelNewVoicegroup() {
        newVoicegroupPrompt = false
        newVoicegroupName = ""
    }

    /// Creates the per-file group and binds `_<name>` as an undoable cfg edit; refusals
    /// keep the prompt open and write nothing, service failures report.
    public func acceptNewVoicegroup() {
        guard newVoicegroupPrompt, !isLoading, let session, !session.isClosed else { return }
        let name = newVoicegroupName.trimmingCharacters(in: .whitespaces)
        guard isValidVoicegroupName(name: name) else {
            onNewVoicegroupFailed?("Invalid voicegroup name: \(newVoicegroupName).")
            return
        }
        guard newVoicegroupNameAvailable(name: name) else {
            onNewVoicegroupFailed?("A voicegroup named \(name) already exists.")
            return
        }
        guard let service = projectService else {
            onNewVoicegroupFailed?("The project service is unavailable.")
            return
        }
        newVoicegroupPrompt = false
        let useCopy = newVoicegroupUseCopy
        Task { [weak self] in
            guard let self, !Task.isCancelled, !session.isClosed,
                self.session === session, self.projectService === service
            else { return }
            do {
                let lease = session.bankLease
                let copyFile = useCopy ? lease.id.sourceRelativePath : ""
                let copyLabel = useCopy ? lease.sectionLabel : ""
                try await service.createVoicegroup(
                    name: name, copyFromFile: copyFile,
                    copySectionLabel: copyLabel)
                guard !Task.isCancelled, !session.isClosed,
                    self.session === session, self.projectService === service
                else { return }
                let args = try await service.voicegroupArgs()
                guard !Task.isCancelled, !session.isClosed,
                    self.session === session, self.projectService === service
                else { return }
                try await session.selectVoicegroup("_" + name)
                guard !Task.isCancelled, !session.isClosed,
                    self.session === session, self.projectService === service
                else { return }
                self.setVoicegroupChoices(args)
                self.refresh(from: session)
                let song = session.document.source.label
                self.onStatusMessage?(
                    "Created sound/voicegroups/\(name).inc and assigned it to \(song).")
            } catch {
                guard !Task.isCancelled, !session.isClosed,
                    self.session === session, self.projectService === service
                else { return }
                let message: String
                if case let ProjectServiceError.operationFailed(text) = error, !text.isEmpty {
                    message = text
                } else {
                    message = String(describing: error)
                }
                self.onNewVoicegroupFailed?(message.isEmpty ? "Could not create \(name)." : message)
            }
        }
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

}
