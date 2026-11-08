import Foundation
import PorydawCore
import PorydawSample
import QtBridge

@MainActor
@QtBridgeable
public final class SampleStudioPresenter: QmlUncreatable {
    private let validateNewName: (String) -> String?
    private var editName: String?
    private var history = SampleStudioHistory()
    private var gestureBase: SampleEditParams?
    private var observers: [@MainActor () -> Void] = []
    private var sourceCents: Double
    private var renderWorker: Task<SampleDocument?, Never>?
    private var renderCompletion: Task<Void, Never>?
    private var pendingRender: (revision: Int, document: SampleDocument)?
    private var requestedRevision = 0
    public private(set) var renderedParams: SampleEditParams
    public private(set) var renderedSource: ImportedSample
    public private(set) var processed: ProcessedSample

    @QtTracked public var windowTitle = "Sample Editor"
    @QtTracked public var sampleName = ""
    @QtTracked public var nameReadOnly = false
    @QtTracked public var nameInvalid = false
    @QtTracked public var canCommit = false
    @QtTracked public var hasSource = false
    @QtTracked public var commitLabel = "Add to Project"
    @QtTracked public var loadedFileName = ""
    @QtTracked public var fileRateText = ""
    @QtTracked public var romText = ""
    @QtTracked public var sourceFrameCount = 0
    @QtTracked public var cropStart = 0
    @QtTracked public var cropEnd = 0
    @QtTracked public var loopOn = false
    @QtTracked public var loopStart = 0
    @QtTracked public var loopEnd = 0
    @QtTracked public var baseKey = 60
    @QtTracked public var fineTuneCents = 0.0
    @QtTracked public var fineTuneText = "0.00"
    @QtTracked public var fineTuneInvalid = false
    public var rateChoices: [String] = []
    @QtTracked public var rateIndex = -1
    @QtTracked public var rateText = ""
    @QtTracked public var normalizeMode = 0
    @QtTracked public var normalizeChoices = ["Auto", "Looped (−9 dBFS loop RMS)", "One-shot (peak)", "Off"]
    @QtTracked public var gainReadout = ""
    @QtTracked public var canUndo = false
    @QtTracked public var canRedo = false
    @QtTracked public var renderRevision = 0

    private var sampleDocument: SampleDocument
    @QtIgnored public var document: SampleDocument { sampleDocument }
    @QtIgnored public var params: SampleEditParams { sampleDocument.params }
    @QtIgnored public var source: ImportedSample { sampleDocument.source }
    private(set) var sourceRevision = 0

    @QtIgnored
    public init(document: SampleDocument, validateName: @escaping (String) -> String?) {
        sampleDocument = document
        renderedParams = document.params
        renderedSource = document.source
        processed = document.prepared ?? ProcessedSample()
        validateNewName = validateName
        sourceCents = (sampleDocument.params.fineTuneCents * 100).rounded() / 100
        sampleName = document.source.suggestedName
        resetSourceReadouts()
        sync()
        refreshName()
    }

    @QtIgnored
    public func replaceSource(_ document: SampleDocument) {
        sampleDocument = document
        history = SampleStudioHistory()
        gestureBase = nil
        sourceCents = (sampleDocument.params.fineTuneCents * 100).rounded() / 100
        if let editName {
            sampleName = editName
        } else {
            sampleName = document.source.suggestedName
        }
        resetSourceReadouts()
        sourceRevision += 1
        sync()
        refreshName()
    }

    private func resetSourceReadouts() {
        hasSource = source.frameCount > 0
        nameReadOnly = editName != nil || !hasSource
        sourceFrameCount = source.frameCount
        fileRateText = SampleStudioReadouts.fileRate(source.sampleRate)
        loadedFileName =
            source.sourcePath.isEmpty
            ? source.suggestedName : URL(fileURLWithPath: source.sourcePath).lastPathComponent
        rateChoices = SampleStudioReadouts.rateChoices(fileRate: source.sampleRate)
    }

    /// The symbol suffix the sample registers under; the field keeps the typed text.
    @QtIgnored public var registeredName: String { editName ?? SampleNames.sanitize(sampleName) }

    public func setSampleName(name: String) {
        guard !nameReadOnly else { return }
        sampleName = name
        refreshName()
    }

    private func refreshName() {
        let valid: Bool
        if let editName {
            valid = sampleName == editName
        } else {
            valid = validateNewName(registeredName) == nil
        }
        nameInvalid = !valid
        canCommit = hasSource && valid
    }

    @QtIgnored public func setEditTarget(name: String) {
        editName = name
        sampleName = name
        nameReadOnly = true
        commitLabel = "Save Sample"
        windowTitle = "Edit Sample — \(name)"
        refreshName()
    }

    private func update(_ mergeKey: Int, _ change: (inout SampleEditParams) -> Void) {
        var next = params
        change(&next)
        next.exactPitchOverride =
            source.exactPitch != 0
                && next.targetRate == source.sampleRate
                && next.baseKey == source.baseKey
                && next.fineTuneCents == sourceCents ? source.exactPitch : 0
        commitParams(next, mergeKey: mergeKey)
    }

    public func setCropStart(value: Int) { update(1) { $0.cropStart = value } }
    public func setCropEnd(value: Int) { update(2) { $0.cropEnd = value } }
    public func setLoopStart(value: Int) { update(3) { $0.loopStart = value } }
    public func setLoopEnd(value: Int) { update(4) { $0.loopEnd = value } }
    public func setFineTuneCents(value: Double) { update(6) { $0.fineTuneCents = value } }
    public func commitFineTuneCentsText(text: String) {
        guard let parsed = SampleStudioReadouts.decimalValue(from: text) else { fineTuneInvalid = true; return }
        fineTuneInvalid = false
        update(6) { $0.fineTuneCents = (parsed * 100).rounded() / 100 }
    }
    public func setNormalizeMode(index: Int) {
        guard let mode = SampleEditParams.NormalizeMode(rawValue: index) else { return }
        update(-1) { $0.normalizeMode = mode }
    }
    public func setLoopOn(enabled: Bool) { update(-1) { $0.loopOn = enabled } }

    public func setBaseKey(key: Int) {
        update(5) { $0.baseKey = min(max(0, key), 127) }
    }

    public func chooseRate(index: Int) {
        guard index >= 0, index <= SampleRatePolicy.rates.count else { return }
        update(-1) { $0.targetRate = index == 0 ? source.sampleRate : Double(SampleRatePolicy.rates[index - 1]) }
    }

    public func commitRateText(text: String) {
        guard let parsed = SampleStudioReadouts.decimalValue(from: text), parsed > 0 else { return }
        update(-1) { $0.targetRate = parsed }
    }

    @QtIgnored public func commitParams(_ newParams: SampleEditParams, mergeKey: Int) {
        let previous = params
        guard previous != newParams else { return }
        sampleDocument.setParams(newParams)
        history.push(before: previous, after: newParams, mergeKey: mergeKey)
        sync()
    }

    @QtIgnored public func applyParamsExternal(_ newParams: SampleEditParams) {
        guard params != newParams else { return }
        sampleDocument.setParams(newParams)
        sync()
    }

    public func undo() {
        guard let previous = history.undo() else { return }
        applyParamsExternal(previous)
        syncHistory()
    }
    public func redo() {
        guard let next = history.redo() else { return }
        applyParamsExternal(next)
        syncHistory()
    }
    public func beginMarkerGesture() { gestureBase = params }
    public func dragMarkers(cropStart: Int, cropEnd: Int, loopStart: Int, loopEnd: Int) {
        var next = params
        next.cropStart = cropStart
        next.cropEnd = cropEnd
        next.loopStart = loopStart
        next.loopEnd = loopEnd
        applyParamsExternal(next)
    }
    public func endMarkerGesture() {
        guard let base = gestureBase else { return }
        gestureBase = nil
        history.push(before: base, after: params, mergeKey: -1)
        syncHistory()
    }
    @QtIgnored public func wavBytes() async -> Data {
        await Self.encodeWav(sampleDocument)
    }

    @QtIgnored public static func wavBytes(for snapshot: SampleDocument) async -> Data {
        await encodeWav(snapshot)
    }

    @concurrent
    private static func encodeWav(_ snapshot: SampleDocument) async -> Data {
        var document = snapshot
        document.prepare(checkpoint: {})
        return SampleWavWriter.bytes(for: document.processed)
    }

    @QtIgnored public func waitForRender() async {
        while let completion = renderCompletion { await completion.value }
    }

    @concurrent
    private static func render(_ snapshot: SampleDocument) async -> SampleDocument? {
        do {
            var document = snapshot
            try document.prepare(checkpoint: { try Task.checkCancellation() })
            try Task.checkCancellation()
            return document
        } catch {
            return nil
        }
    }

    private func landRender(_ document: SampleDocument, result: ProcessedSample) {
        processed = result
        renderedParams = document.params
        renderedSource = document.source
        gainReadout = SampleStudioReadouts.gain(result, mode: document.params.normalizeMode)
        romText = SampleStudioReadouts.romSize(bytes: SampleStudioReadouts.romBytes(result))
        renderRevision += 1
        for observer in observers { observer() }
    }

    private func startPendingRender() {
        guard renderWorker == nil, let request = pendingRender else { return }
        pendingRender = nil
        let worker = Task(priority: .userInitiated) { await Self.render(request.document) }
        renderWorker = worker
        renderCompletion = Task { [weak self] in
            let document = await worker.value
            guard let self else { return }
            self.renderWorker = nil
            self.renderCompletion = nil
            if request.revision == self.requestedRevision, let document, let result = document.prepared {
                self.landRender(document, result: result)
            }
            self.startPendingRender()
        }
    }

    deinit {
        renderWorker?.cancel()
        renderCompletion?.cancel()
    }
    @QtIgnored public func addRenderObserver(_ body: @escaping @MainActor () -> Void) { observers.append(body) }

    private func syncHistory() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }
    private func sync() {
        let p = params
        cropStart = p.cropStart
        cropEnd = p.cropEnd
        loopOn = p.loopOn
        loopStart = p.loopStart
        loopEnd = p.loopEnd
        baseKey = p.baseKey
        fineTuneCents = p.fineTuneCents
        fineTuneText = SampleStudioReadouts.decimal(p.fineTuneCents, places: 2)
        normalizeMode = p.normalizeMode.rawValue
        rateIndex =
            p.targetRate == source.sampleRate
            ? 0 : SampleRatePolicy.rates.firstIndex(where: { Double($0) == p.targetRate }).map { $0 + 1 } ?? -1
        rateText =
            rateIndex == 0
            ? rateChoices[0]
            : (p.targetRate.rounded() == p.targetRate
                ? SampleStudioReadouts.decimal(p.targetRate, places: 0) : String(p.targetRate))
        syncHistory()
        requestedRevision += 1
        renderWorker?.cancel()
        if let result = sampleDocument.prepared {
            pendingRender = nil
            landRender(sampleDocument, result: result)
        } else {
            pendingRender = (requestedRevision, sampleDocument)
            startPendingRender()
        }
    }
}
