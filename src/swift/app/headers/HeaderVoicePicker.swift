import PorydawCore
import QtBridge

@MainActor
@QtBridgeable
public final class HeaderVoicePicker {
    @QtTracked public var pickerOpen = false
    @QtTracked public var pickerTitle = ""
    @QtTracked public var pickerFilter = ""
    @QtTracked public var pickerIndex = -1
    @QtTracked public var pickerHasMatch = false
    @QtTracked public var pickerRows = QListModel<VoicePickerRowHandle>()
    public var promptAppearance: [String: QVariantSettable]
    public var promptFont: [String: QVariantSettable]

    @QtIgnored public var onOpenChanged: ((Bool) -> Void)?
    @QtIgnored public var onComplete: ((Int) -> Void)?
    @QtIgnored public var onAuditionVoice: ((UInt8, UInt8, UInt8) -> Void)? {
        willSet { releasePickerAudition() }
    }
    private weak var headers: TrackHeadersPresenter?
    private let cache = VoicePickerProjectionCache()
    private var selectedProgram = -1
    private var publishedRows: [VoicePickerRowHandle] = []

    public init(headers: TrackHeadersPresenter, typography: Typography) {
        self.headers = headers
        let base = Double(typography.baseFontPx)
        promptAppearance = PromptAppearance.metrics(base: base)
        promptFont = PromptAppearance.font(typography: typography)
    }

    @QtIgnored
    public func open(track: Int) {
        guard let headers, let session = headers.session, !session.isClosed,
            let request = headers.pendingVoice, request.track == track,
            request.matches(session.document)
        else { return }
        releasePickerAudition()
        cache.refresh(slots: session.bankSlots)
        cache.resolve(filter: "")
        let initial = track < 0 ? 0 : headers.firstVoiceProgram(track: track)
        selectedProgram = cache.initialProgram(initial)
        pickerTitle = track < 0 ? "New track voice" : "Track \(track + 1) voice"
        pickerFilter = ""
        publish()
        pickerOpen = true
        onOpenChanged?(true)
    }

    @QtIgnored
    public func refresh() {
        guard pickerOpen else { return }
        guard let headers, let session = headers.session,
            let request = headers.pendingVoice, request.matches(session.document)
        else {
            cancelPicker()
            return
        }
        releasePickerAudition()
        cache.refresh(slots: session.bankSlots)
        cache.resolve(filter: pickerFilter)
        selectedProgram = cache.initialProgram(selectedProgram)
        publish()
    }

    public func setPickerFilter(text: String) {
        guard pickerOpen else { return }
        let filter = String(text.prefix(64))
        guard filter != pickerFilter else { return }
        pickerFilter = filter
        selectedProgram = cache.filteredProgram(filter)
        publish()
    }

    public func selectPickerRow(index: Int) {
        guard pickerOpen else { return }
        selectedProgram = cache.program(at: index)
        publish()
    }

    public func movePickerSelection(delta: Int) {
        guard pickerOpen, let selected = cache.movedProgram(from: selectedProgram, delta: delta)
        else { return }
        selectedProgram = selected
        publish()
    }

    public func pressAndHoldPickerRow(index: Int) {
        guard pickerOpen, let headers, let session = headers.session,
            let request = headers.pendingVoice, request.matches(session.document)
        else {
            releasePickerAudition()
            return
        }
        selectedProgram = cache.program(at: index)
        publish()
        cache.hold(program: selectedProgram, audition: onAuditionVoice)
    }

    public func releasePickerAudition() {
        cache.release(audition: onAuditionVoice)
    }

    @discardableResult
    public func acceptPicker() -> Bool {
        guard pickerOpen, pickerHasMatch else { return false }
        complete(selectedProgram)
        return true
    }

    public func cancelPicker() {
        guard pickerOpen else { return }
        complete(-1)
    }

    @QtIgnored
    public func complete(_ program: Int) {
        guard pickerOpen else {
            headers?.completeVoiceRequest(program: program)
            return
        }
        close()
        if let onComplete { onComplete(program) } else { headers?.completeVoiceRequest(program: program) }
    }

    @QtIgnored
    private func close() {
        releasePickerAudition()
        pickerOpen = false
        pickerTitle = ""
        pickerFilter = ""
        pickerIndex = -1
        pickerHasMatch = false
        selectedProgram = -1
        publishedRows = []
        pickerRows.reset(to: [])
        onOpenChanged?(false)
    }

    @QtIgnored
    private func publish() {
        cache.resolve(filter: pickerFilter)
        cache.releaseIfFilteredOut(audition: onAuditionVoice)
        let values = cache.selectedRows(program: selectedProgram)
        VoiceChangesProjection.publishPickerRows(
            pickerRows, snapshots: &publishedRows, values: values)
        pickerIndex = cache.indices[selectedProgram] ?? -1
        pickerHasMatch = pickerIndex >= 0
    }
}
