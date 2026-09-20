import QtBridge

@MainActor
@QtBridgeable
public final class NewSongWizardController {
    // QtBridge does not expose private(set), so these are writable snapshots.
    // The ignored draft and session fields below remain the canonical state.
    public var active: Bool = false
    public var page: Int = 0
    public var name: String = ""
    public var constant: String = ""
    public var playerNames: [String] = []
    public var playerIndex: Int = 0
    public var voicegroupNames: [String] = []
    public var voicegroupIndex: Int = -1
    public var voicegroupText: String = ""
    public var masterVolume: Int = 100
    public var reverb: Int = 50
    public var priority: Int = 0
    public var exactGate: Bool = true
    public var extendedClocks: Bool = false
    public var noCompression: Bool = false
    public var identityError: String = ""
    public var soundError: String = ""
    public var canNext: Bool = false
    public var canFinish: Bool = false

    public init(
        catalog: NewSongCatalog, onCompleted: @escaping (NewSongRequest?) -> Void
    ) {
        draft = NewSongDraft(catalog: catalog)
        self.onCompleted = onCompleted
        publish()
    }

    public func begin() {
        guard !sessionActive else { return }
        draft.reset()
        sessionActive = true
        currentPage = 0
        publish()
    }

    public func next() {
        guard sessionActive, currentPage == 0 else { return }
        let identity = draft.identityValidation()
        let sound = draft.soundValidation()
        if identity.valid {
            currentPage = 1
        }
        publish(identity: identity, sound: sound)
    }

    public func back() {
        guard sessionActive, currentPage == 1 else { return }
        currentPage = 0
        publish()
    }

    public func finish() {
        guard sessionActive else { return }

        let identity = draft.identityValidation()
        let sound = draft.soundValidation()
        guard identity.valid, sound.valid else {
            currentPage = identity.valid ? 1 : 0
            publish(identity: identity, sound: sound)
            return
        }

        let request = draft.request()
        sessionActive = false
        publish(identity: identity, sound: sound)
        onCompleted(request)
    }

    public func cancel() {
        guard sessionActive else { return }
        sessionActive = false
        publish()
        onCompleted(nil)
    }

    public func editName(text: String) {
        guard sessionActive else { return }
        draft.editName(text)
        publish()
    }

    public func editConstant(text: String) {
        guard sessionActive else { return }
        draft.editConstant(text)
        publish()
    }

    public func selectPlayer(index: Int) {
        guard sessionActive else { return }
        draft.selectPlayer(index)
        publish()
    }

    public func selectVoicegroup(index: Int) {
        guard sessionActive else { return }
        draft.selectVoicegroup(index)
        publish()
    }

    public func editVoicegroup(text: String) {
        guard sessionActive else { return }
        draft.editVoicegroup(text)
        publish()
    }

    public func setMasterVolume(value: Int) {
        guard sessionActive else { return }
        draft.setMasterVolume(value)
        publish()
    }

    public func setReverb(value: Int) {
        guard sessionActive else { return }
        draft.setReverb(value)
        publish()
    }

    public func setPriority(value: Int) {
        guard sessionActive else { return }
        draft.setPriority(value)
        publish()
    }

    public func setExactGate(value: Bool) {
        guard sessionActive else { return }
        draft.setExactGate(value)
        publish()
    }

    public func setExtendedClocks(value: Bool) {
        guard sessionActive else { return }
        draft.setExtendedClocks(value)
        publish()
    }

    public func setNoCompression(value: Bool) {
        guard sessionActive else { return }
        draft.setNoCompression(value)
        publish()
    }

    @QtIgnored private var draft: NewSongDraft
    @QtIgnored private let onCompleted: (NewSongRequest?) -> Void
    @QtIgnored private var sessionActive = false
    @QtIgnored private var currentPage = 0

    private func publish() {
        publish(identity: draft.identityValidation(), sound: draft.soundValidation())
    }

    private func publish(
        identity: (valid: Bool, error: String), sound: (valid: Bool, error: String)
    ) {
        if page != currentPage { page = currentPage }
        if name != draft.name { name = draft.name }
        if constant != draft.constant { constant = draft.constant }
        if playerNames != draft.playerNames { playerNames = draft.playerNames }
        if playerIndex != draft.playerIndex { playerIndex = draft.playerIndex }
        if voicegroupNames != draft.voicegroupNames { voicegroupNames = draft.voicegroupNames }
        if voicegroupIndex != draft.voicegroupIndex { voicegroupIndex = draft.voicegroupIndex }
        if voicegroupText != draft.voicegroupText { voicegroupText = draft.voicegroupText }
        if masterVolume != draft.masterVolume { masterVolume = draft.masterVolume }
        if reverb != draft.reverb { reverb = draft.reverb }
        if priority != draft.priority { priority = draft.priority }
        if exactGate != draft.exactGate { exactGate = draft.exactGate }
        if extendedClocks != draft.extendedClocks { extendedClocks = draft.extendedClocks }
        if noCompression != draft.noCompression { noCompression = draft.noCompression }
        if identityError != identity.error { identityError = identity.error }
        if soundError != sound.error { soundError = sound.error }
        if canNext != identity.valid { canNext = identity.valid }
        let finishEnabled = identity.valid && sound.valid
        if canFinish != finishEnabled { canFinish = finishEnabled }
        // A host may create the window synchronously when active changes.
        if active != sessionActive { active = sessionActive }
    }
}
