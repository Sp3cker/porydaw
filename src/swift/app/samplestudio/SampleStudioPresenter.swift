import Foundation
import PorydawCore
import PorydawSample
import QtBridge

@MainActor
@QtBridgeable
public final class SampleStudioPresenter: QmlUncreatable {
    // fceecd88:src/ui/enginesettingsdialog.cpp:16–17, kGbaMixRates.
    private static let rates = [5734, 7884, 10512, 13379, 15768, 18157, 21024, 26758, 31536, 36314, 40137, 42048]
    private let validateNewName: (String) -> String?
    private var editName: String?
    private var history = SampleStudioHistory()
    private var gestureBase: SampleEditParams?
    private var observers: [@MainActor () -> Void] = []
    private var sourceCents: Double

    @QtTracked public var windowTitle = "Sample Editor"
    @QtTracked public var sampleName = ""
    @QtTracked public var nameReadOnly = false
    @QtTracked public var nameStatus = ""
    @QtTracked public var canCommit = false
    @QtTracked public var commitLabel = "Add to Project"
    @QtTracked public var sourceLine = ""
    @QtTracked public var sourceFrameCount = 0
    @QtTracked public var cropStart = 0
    @QtTracked public var cropEnd = 0
    @QtTracked public var loopOn = false
    @QtTracked public var loopStart = 0
    @QtTracked public var loopEnd = 0
    @QtTracked public var baseKey = 60
    @QtTracked public var baseKeyText = "C4 (60)"
    @QtTracked public var fineTuneCents = 0.0
    public var rateChoices: [String] = []
    @QtTracked public var rateIndex = -1
    @QtTracked public var rateText = ""
    @QtTracked public var normalizeMode = 0
    @QtTracked public var normalizeChoices = ["Auto", "Looped (−9 dBFS loop RMS)", "One-shot (peak)", "Off"]
    @QtTracked public var gainReadout = ""
    @QtTracked public var outputSummary = ""
    @QtTracked public var techDetail = ""
    @QtTracked public var canUndo = false
    @QtTracked public var canRedo = false
    @QtTracked public var renderRevision = 0

    private var sampleDocument: SampleDocument
    @QtIgnored public var document: SampleDocument { sampleDocument }
    @QtIgnored public var params: SampleEditParams { sampleDocument.params }
    @QtIgnored public var processed: ProcessedSample { sampleDocument.processed }
    @QtIgnored public var source: ImportedSample { sampleDocument.source }

    @QtIgnored
    public init(source: ImportedSample, validateName: @escaping (String) -> String?) {
        sampleDocument = SampleDocument(source: source)
        validateNewName = validateName
        sourceCents = (sampleDocument.params.fineTuneCents * 100).rounded() / 100
        sampleName = source.suggestedName
        sourceFrameCount = source.frameCount
        sourceLine = SampleStudioReadouts.sourceLine(source)
        rateChoices = ["Keep source (\(SampleStudioReadouts.decimal(source.sampleRate, places: source.sampleRate == floor(source.sampleRate) ? 0 : 2)) Hz)"] + Self.rates.map(String.init)
        sync()
        refreshName()
    }

    public func setSampleName(name: String) {
        guard !nameReadOnly else { return }
        sampleName = name
        refreshName()
    }

    private func refreshName() {
        if let editName {
            let valid = sampleName == editName
            canCommit = valid
            nameStatus = valid ? "Saves over DirectSoundWaveData_\(editName)'s sample data" : "the sample keeps its registered name (\(editName))."
        } else if let error = validateNewName(sampleName) {
            canCommit = false
            nameStatus = error
        } else {
            canCommit = true
            nameStatus = "Registers as DirectSoundWaveData_\(sampleName)"
        }
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
        next.exactPitchOverride = source.exactPitch != 0
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
    public func setNormalizeMode(index: Int) {
        guard let mode = SampleEditParams.NormalizeMode(rawValue: index) else { return }
        update(-1) { $0.normalizeMode = mode }
    }
    public func setLoopOn(enabled: Bool) { update(-1) { $0.loopOn = enabled } }

    public func setBaseKeyText(text: String) {
        guard let key = SampleStudioReadouts.midiKey(from: text) else { return }
        update(5) { $0.baseKey = key }
    }

    public func chooseRate(index: Int) {
        guard index >= 0, index <= Self.rates.count else { return }
        update(-1) { $0.targetRate = index == 0 ? source.sampleRate : Double(Self.rates[index - 1]) }
    }

    public func commitRateText(text: String) {
        let parsed = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        update(-1) { $0.targetRate = parsed.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? source.sampleRate }
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
    @QtIgnored public func wavBytes() -> Data { SampleWavWriter.bytes(for: processed) }
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
        baseKeyText = "\(midiKeyName(p.baseKey)) (\(p.baseKey))"
        fineTuneCents = p.fineTuneCents
        normalizeMode = p.normalizeMode.rawValue
        rateIndex = p.targetRate == source.sampleRate
            ? 0 : Self.rates.firstIndex(where: { Double($0) == p.targetRate }).map { $0 + 1 } ?? -1
        rateText = rateIndex == 0 ? rateChoices[0]
            : (p.targetRate.rounded() == p.targetRate ? SampleStudioReadouts.decimal(p.targetRate, places: 0) : String(p.targetRate))
        let result = processed
        gainReadout = SampleStudioReadouts.gain(result, mode: p.normalizeMode)
        outputSummary = SampleStudioReadouts.summary(source: source, output: result)
        techDetail = SampleStudioReadouts.technical(result)
        syncHistory()
        renderRevision += 1
        for observer in observers { observer() }
    }
}
