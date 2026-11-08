import Foundation
import PorydawSample
import Synchronization

/// Window-local sources and slicing state; all external name policy is injected.
@MainActor
public final class KitSourceSession {
    /// One named adjacent-marker region with independently baked edge fades.
    public struct Slice: Equatable, Sendable {
        public var id: Int
        public var name: String
        public var startFrame: Int
        public var endFrame: Int
        public var fadeIn: Bool
        public var fadeOut: Bool
    }

    /// A decoded source and its ordered markers, pending slices and selected rate.
    public struct Source: Equatable, Sendable {
        public let id: Int
        fileprivate let renderIdentity: UUID
        public let sample: ImportedSample
        /// The project symbol of a committed sample loaded from the kit; nil for opened files.
        public let committedSymbol: String?
        public fileprivate(set) var markers: [Int]
        public fileprivate(set) var slices: [Slice]
        public fileprivate(set) var targetRate: Double

        /// The symbol a slice still plays verbatim: the untouched whole committed sample.
        public func committedSymbol(of slice: Slice) -> String? {
            guard let committedSymbol, isCommittedOriginal(slice), slice.startFrame == 0,
                slice.endFrame == sample.frameCount, !slice.fadeIn, !slice.fadeOut, targetRate == sample.sampleRate
            else { return nil }
            return committedSymbol
        }

        /// Whether the slice carries the committed sample's read-only name.
        public func isCommittedOriginal(_ slice: Slice) -> Bool {
            committedSymbol != nil && slice.name == sample.suggestedName
        }
    }

    /// The complete value state for draft-owned undo, including identity counters.
    public struct Snapshot: Equatable {
        public let sources: [Source]
        fileprivate let nextSourceId: Int
        fileprivate let nextSliceId: Int
    }

    public private(set) var sources: [Source] = [] {
        didSet {
            sourcesRevision += 1
            cancelRender()
            cancelRender(metadataRender)
            for job in renderJobs.values { job.task.cancel() }
            renderJobs.removeAll()
            renderCache.removeAll()
        }
    }
    private(set) var sourcesRevision = 0
    /// Returns a refusal for an unavailable name, or nil to accept it.
    public var validateName: ((String) -> String?)?
    private var nextSourceId = 0
    private var nextSliceId = 0

    private struct RenderKey: Hashable, Sendable {
        let source: UUID
        let slice: Int
        let start: Int
        let end: Int
        let fadeIn: Bool
        let fadeOut: Bool
        let rate: Double

        init(source: Source, slice: Slice) {
            self.source = source.renderIdentity
            self.slice = slice.id
            start = slice.startFrame
            end = slice.endFrame
            fadeIn = slice.fadeIn
            fadeOut = slice.fadeOut
            rate = source.targetRate
        }
    }

    private struct RenderInput: Sendable {
        let source: Source
        let slice: Slice
        var key: RenderKey { RenderKey(source: source, slice: slice) }
    }

    private final class RenderRequest {
        let inputs: [RenderInput]
        let completion: @MainActor ([ProcessedSample]) -> Void
        var results: [ProcessedSample] = []

        init(inputs: [RenderInput], completion: @escaping @MainActor ([ProcessedSample]) -> Void) {
            self.inputs = inputs
            self.completion = completion
            results.reserveCapacity(inputs.count)
        }
    }

    private final class RenderLane {
        var generation = 0
    }

    private struct RenderJob {
        let id: UUID
        let task: Task<ProcessedSample?, Never>
    }

    final class RenderCounter: Sendable {
        let value = Atomic<Int>(0)
    }

    private var renderCache: [RenderKey: ProcessedSample] = [:]
    private var renderJobs: [RenderKey: RenderJob] = [:]
    private let auditionRender = RenderLane()
    private let metadataRender = RenderLane()
    var renderCounter: RenderCounter?

    isolated deinit {
        for job in renderJobs.values { job.task.cancel() }
    }

    /// Creates an empty window-local session.
    public init() {}

    /// Captures sources and identity counters without retaining the outward validator.
    public func snapshot() -> Snapshot {
        Snapshot(sources: sources, nextSourceId: nextSourceId, nextSliceId: nextSliceId)
    }

    /// Replaces the captured state exactly; the session owns no undo history.
    public func restore(_ snapshot: Snapshot) {
        sources = snapshot.sources
        nextSourceId = snapshot.nextSourceId
        nextSliceId = snapshot.nextSliceId
    }

    /// Adds a source with a monotonic identity, no markers and the shared default rate.
    public func addSource(_ sample: ImportedSample) {
        sources.append(
            Source(
                id: nextSourceId, renderIdentity: UUID(), sample: sample, committedSymbol: nil, markers: [], slices: [],
                targetRate: SampleRatePolicy.targetRate(gbaReady: sample.gbaReady, sourceRate: sample.sampleRate)))
        nextSourceId += 1
    }

    /// Adds a project sample as one whole, fade-free slice named `sample.suggestedName` at its own rate;
    /// false when another slice already uses that name.
    @discardableResult
    public func addCommittedSample(_ sample: ImportedSample, symbol: String) -> Bool {
        let name = sample.suggestedName
        guard !name.isEmpty, sample.frameCount > 0,
            !sources.contains(where: { (source: Source) in source.slices.contains { $0.name == name } })
        else { return false }
        let slice = Slice(
            id: nextSliceId, name: name, startFrame: 0, endFrame: sample.frameCount, fadeIn: false, fadeOut: false)
        sources.append(
            Source(
                id: nextSourceId, renderIdentity: UUID(), sample: sample, committedSymbol: symbol, markers: [],
                slices: [slice],
                targetRate: sample.sampleRate))
        nextSourceId += 1
        nextSliceId += 1
        return true
    }

    /// Renames every edited slice still carrying its committed name, so saving writes a new sample
    /// instead of the project's; returns the renames for zones to follow.
    public func forkEditedCommittedSlices() -> [(from: String, to: String)] {
        var renames: [(from: String, to: String)] = []
        for index in sources.indices {
            for slice in sources[index].slices.indices {
                let value = sources[index].slices[slice]
                guard sources[index].isCommittedOriginal(value), sources[index].committedSymbol(of: value) == nil
                else { continue }
                let name = mintName(for: sources[index])
                guard !name.isEmpty else { continue }
                sources[index].slices[slice].name = name
                renames.append((from: value.name, to: name))
            }
        }
        return renames
    }

    /// Creates the initial whole-buffer slice for a fresh source.
    @discardableResult
    public func createFirstSlice(source: Int) -> Bool {
        guard let index = sourceIndex(source), sources[index].slices.isEmpty, sources[index].sample.frameCount > 0
        else {
            return false
        }
        var nextId = nextSliceId
        guard
            let slice = newSlice(
                start: 0, end: sources[index].sample.frameCount, source: sources[index], nextId: &nextId)
        else {
            return false
        }
        sources[index].slices.append(slice)
        nextSliceId = nextId
        return true
    }

    /// Inserts a boundary, optionally snapping within 3 ms; splits retain the left slice.
    public func setMarker(source: Int, frame: Int, snap: Bool) {
        guard let index = sourceIndex(source) else { return }
        var staged = sources[index]
        var nextId = nextSliceId
        let boundary = markerFrame(frame, source: staged, snap: snap)
        guard insertMarker(boundary, into: &staged, nextId: &nextId) else { return }
        sources[index] = staged
        nextSliceId = nextId
    }

    /// Removes a boundary, merging its adjacent slices and keeping the left name.
    public func removeMarker(source: Int, frame: Int) {
        guard let index = sourceIndex(source), let marker = sources[index].markers.firstIndex(of: frame)
        else { return }
        var staged = sources[index]
        removeMarker(at: marker, from: &staged)
        sources[index] = staged
    }

    /// Moves a boundary with optional snap; existing slices follow their old pair ordinals.
    public func moveMarker(source: Int, from: Int, to: Int, snap: Bool) {
        guard let index = sourceIndex(source), let marker = sources[index].markers.firstIndex(of: from) else { return }
        let boundary = markerFrame(to, source: sources[index], snap: snap)
        guard boundary != from, !sources[index].markers.contains(boundary) else { return }
        var staged = sources[index]
        let left = staged.slices.firstIndex { (slice: Slice) in slice.endFrame == from }
        let right = staged.slices.firstIndex { (slice: Slice) in slice.startFrame == from }
        if let left, let right {
            guard boundary > staged.slices[left].startFrame, boundary < staged.slices[right].endFrame else { return }
            staged.slices[left].endFrame = boundary
            staged.slices[right].startFrame = boundary
            staged.markers.remove(at: marker)
            staged.markers.append(boundary)
            staged.markers.sort()
            sources[index] = staged
            return
        }
        let oldMarkers = staged.markers
        staged.markers.remove(at: marker)
        staged.markers.append(boundary)
        staged.markers.sort()
        for slice in staged.slices.indices {
            guard let ordinal = oldMarkers.firstIndex(of: staged.slices[slice].startFrame) else {
                continue
            }
            staged.slices[slice].startFrame = staged.markers[ordinal]
            staged.slices[slice].endFrame = staged.markers[ordinal + 1]
        }
        sources[index] = staged
    }

    /// Deletes the indexed slice; the previous adjacent slice, else the next, grows over its frames and
    /// their shared marker goes. An isolated slice takes the markers that bordered only it.
    /// A committed sample's source leaves with its last slice.
    public func removeSlice(source: Int, slice: Int) {
        guard let index = sourceIndex(source), sources[index].slices.indices.contains(slice) else { return }
        var staged = sources[index]
        let removed = staged.slices.remove(at: slice)
        if let previous = staged.slices.firstIndex(where: { (other: Slice) in other.endFrame == removed.startFrame }) {
            staged.slices[previous].endFrame = removed.endFrame
            staged.markers.removeAll { (frame: Int) in frame == removed.startFrame }
        } else if let next = staged.slices.firstIndex(where: { (other: Slice) in other.startFrame == removed.endFrame })
        {
            staged.slices[next].startFrame = removed.startFrame
            staged.markers.removeAll { (frame: Int) in frame == removed.endFrame }
        } else {
            staged.markers.removeAll { (frame: Int) in frame == removed.startFrame || frame == removed.endFrame }
        }
        if staged.committedSymbol != nil, staged.slices.isEmpty {
            sources.remove(at: index)
        } else {
            sources[index] = staged
        }
    }

    /// Changes the indexed slice's independently rendered declick overrides.
    public func setSliceFades(source: Int, slice: Int, fadeIn: Bool, fadeOut: Bool) {
        guard let index = sourceIndex(source), sources[index].slices.indices.contains(slice) else { return }
        sources[index].slices[slice].fadeIn = fadeIn
        sources[index].slices[slice].fadeOut = fadeOut
    }

    /// Selects a per-source rate by Hz; rejects values outside the shared option list.
    public func setSourceRate(source: Int, rate: Int) -> Bool {
        guard let index = sourceIndex(source),
            SampleRatePolicy.rateOptions(sourceRate: sources[index].sample.sampleRate).contains(rate)
        else { return false }
        sources[index].targetRate = Double(rate)
        return true
    }


    func cancelRender() {
        cancelRender(auditionRender)
    }

    private func cancelRender(_ lane: RenderLane) {
        lane.generation += 1
    }

    func renderSlices(
        _ slices: [(source: Source, slice: Slice)], metadata: Bool = false,
        completion: @escaping @MainActor ([ProcessedSample]) -> Void
    ) {
        let lane = metadata ? metadataRender : auditionRender
        lane.generation += 1
        let inputs = slices.map { (pair: (source: Source, slice: Slice)) -> RenderInput in
            RenderInput(source: pair.source, slice: pair.slice)
        }
        let request = RenderRequest(inputs: inputs, completion: completion)
        continueRender(request, lane: lane, generation: lane.generation)
    }

    private func continueRender(_ request: RenderRequest, lane: RenderLane, generation: Int) {
        guard lane.generation == generation else { return }
        while request.results.count < request.inputs.count {
            let input = request.inputs[request.results.count]
            if let cached = renderCache[input.key] {
                request.results.append(cached)
                continue
            }
            let job: RenderJob
            if let existing = renderJobs[input.key] {
                job = existing
            } else {
                let counter = renderCounter
                let task = Task(priority: .userInitiated) { await Self.renderOffMain(input, counter: counter) }
                job = RenderJob(id: UUID(), task: task)
                renderJobs[input.key] = job
            }
            Task { [weak self] in
                let rendered = await job.task.value
                guard let self else { return }
                if self.renderJobs[input.key]?.id == job.id {
                    self.renderJobs.removeValue(forKey: input.key)
                    if let rendered, self.contains(input) { self.renderCache[input.key] = rendered }
                }
                guard lane.generation == generation, let rendered, self.contains(input) else { return }
                request.results.append(rendered)
                self.continueRender(request, lane: lane, generation: generation)
            }
            return
        }
        request.completion(request.results)
    }

    private func contains(_ input: RenderInput) -> Bool {
        guard
            let source = sources.first(where: { (source: Source) -> Bool in
                source.renderIdentity == input.source.renderIdentity
            }), let slice = source.slices.first(where: { (slice: Slice) -> Bool in slice.id == input.slice.id })
        else { return false }
        return RenderKey(source: source, slice: slice) == input.key
    }

    @concurrent
    private static func renderOffMain(_ input: RenderInput, counter: RenderCounter?) async -> ProcessedSample? {
        guard !Task.isCancelled else { return nil }
        counter?.value.wrappingAdd(1, ordering: .relaxed)
        let result = render(input)
        return Task.isCancelled ? nil : result
    }

    /// Renders and encodes a captured batch independently of audition rendering.
    @concurrent
    public static func renderWavs(_ slices: [(source: Source, slice: Slice)]) async -> [Data] {
        var results: [Data] = []
        results.reserveCapacity(slices.count)
        for pair in slices {
            if Task.isCancelled { return [] }
            let rendered = render(RenderInput(source: pair.source, slice: pair.slice))
            if Task.isCancelled { return [] }
            results.append(SampleWavWriter.bytes(for: rendered))
        }
        return Task.isCancelled ? [] : results
    }

    nonisolated private static func render(_ input: RenderInput) -> ProcessedSample {
        let source = input.source
        let region = input.slice
        var params = SampleDocument.defaultParams(for: source.sample)
        params.cropStart = region.startFrame
        params.cropEnd = region.endFrame
        params.targetRate = source.targetRate
        params.loopOn =
            source.committedSymbol != nil && source.sample.hasLoop && region.startFrame == 0
            && region.endFrame == source.sample.frameCount
        params.fadeIn = false
        params.fadeOut = false
        if source.targetRate != source.sample.sampleRate { params.exactPitchOverride = 0 }
        return SampleSlice.render(source: source.sample, params: params, fadeIn: region.fadeIn, fadeOut: region.fadeOut)
    }

    /// Returns the first session-wide available sanitized prefix plus 00–99, or empty on exhaustion.
    public func mintSliceName(source: Int) -> String {
        guard let index = sourceIndex(source) else { return "" }
        return mintName(for: sources[index])
    }

    /// Sanitizes and validates a rename; refusal preserves the indexed slice's original name.
    /// A committed sample's own name is read-only.
    public func renameSlice(source: Int, slice: Int, to: String) -> Bool {
        guard let index = sourceIndex(source), sources[index].slices.indices.contains(slice),
            !sources[index].isCommittedOriginal(sources[index].slices[slice])
        else { return false }
        let name = SampleNames.sanitize(to)
        guard !name.isEmpty else { return false }
        if name == sources[index].slices[slice].name { return validateName?(name) == nil }
        guard nameAvailable(name, source: sources[index]) else { return false }
        sources[index].slices[slice].name = name
        return true
    }

    /// Removes a source without reusing its identity.
    @discardableResult
    public func removeSource(source: Int) -> Bool {
        guard let index = sourceIndex(source) else { return false }
        sources.remove(at: index)
        return true
    }

    private func sourceIndex(_ id: Int) -> Int? {
        sources.firstIndex { (source: Source) in source.id == id }
    }

    private func markerFrame(_ frame: Int, source: Source, snap: Bool) -> Int {
        let clamped = min(max(0, frame), source.sample.frameCount)
        guard snap, clamped != source.sample.frameCount else { return clamped }
        return SampleZeroCrossing.nearest(
            buffer: source.sample.buffer.span, index: clamped,
            windowFrames: Int((0.003 * source.sample.sampleRate).rounded()))
    }

    private func nameAvailable(_ name: String, source: Source) -> Bool {
        guard !source.slices.contains(where: { (slice: Slice) in slice.name == name }) else { return false }
        for other in sources where other.id != source.id {
            if other.slices.contains(where: { (slice: Slice) in slice.name == name }) { return false }
        }
        return validateName?(name) == nil
    }

    private func mintName(for source: Source) -> String {
        let prefix = SampleNames.sanitize(source.sample.suggestedName)
        let base = prefix.isEmpty ? "slice" : prefix
        for number in 0...99 {
            let suffix = number < 10 ? "0\(number)" : "\(number)"
            let name = "\(base)_\(suffix)"
            if nameAvailable(name, source: source) { return name }
        }
        return ""
    }

    private func newSlice(start: Int, end: Int, source: Source, nextId: inout Int) -> Slice? {
        let name = mintName(for: source)
        guard !name.isEmpty else { return nil }
        let slice = Slice(id: nextId, name: name, startFrame: start, endFrame: end, fadeIn: false, fadeOut: true)
        nextId += 1
        return slice
    }

    private func insertMarker(_ frame: Int, into source: inout Source, nextId: inout Int) -> Bool {
        guard !source.markers.contains(frame) else { return true }
        if let sliceIndex = source.slices.firstIndex(where: { (slice: Slice) in
            slice.startFrame < frame && frame < slice.endFrame
        }) {
            let oldEnd = source.slices[sliceIndex].endFrame
            guard let right = newSlice(start: frame, end: oldEnd, source: source, nextId: &nextId) else {
                return false
            }
            source.slices[sliceIndex].endFrame = frame
            source.slices.insert(right, at: sliceIndex + 1)
        } else {
            let ordinal = source.markers.firstIndex { (marker: Int) in marker > frame } ?? source.markers.count
            if ordinal > 0 && ordinal < source.markers.count {
                let start = source.markers[ordinal - 1]
                let end = source.markers[ordinal]
                if let left = source.slices.firstIndex(where: { (slice: Slice) in
                    slice.startFrame == start && slice.endFrame == end
                }) {
                    source.slices[left].endFrame = frame
                    guard let right = newSlice(start: frame, end: end, source: source, nextId: &nextId) else {
                        return false
                    }
                    source.slices.insert(right, at: left + 1)
                }
            } else if !source.markers.isEmpty {
                let start = ordinal == 0 ? frame : source.markers[ordinal - 1]
                let end = ordinal == 0 ? source.markers[0] : frame
                guard let slice = newSlice(start: start, end: end, source: source, nextId: &nextId) else {
                    return false
                }
                source.slices.insert(slice, at: ordinal == 0 ? 0 : source.slices.count)
            }
        }
        let ordinal = source.markers.firstIndex { (marker: Int) in marker > frame } ?? source.markers.count
        source.markers.insert(frame, at: ordinal)
        return true
    }

    private func removeMarker(at ordinal: Int, from source: inout Source) {
        let frame = source.markers[ordinal]
        let left = source.slices.firstIndex { (slice: Slice) in slice.endFrame == frame }
        let right = source.slices.firstIndex { (slice: Slice) in slice.startFrame == frame }
        if let left, let right {
            source.slices[left].endFrame = source.slices[right].endFrame
            source.slices.remove(at: right)
        } else if ordinal > 0 && ordinal + 1 < source.markers.count {
            if let left {
                source.slices[left].endFrame = source.markers[ordinal + 1]
            } else if let right {
                source.slices[right].startFrame = source.markers[ordinal - 1]
            }
        } else if let adjacent = left ?? right {
            source.slices.remove(at: adjacent)
        }
        source.markers.remove(at: ordinal)
    }
}
