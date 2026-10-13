import PorydawSample

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
        public let sample: ImportedSample
        public fileprivate(set) var markers: [Int]
        public fileprivate(set) var slices: [Slice]
        public fileprivate(set) var targetRate: Double
    }

    /// The complete value state for draft-owned undo, including identity counters.
    public struct Snapshot: Equatable {
        public let sources: [Source]
        fileprivate let nextSourceId: Int
        fileprivate let nextSliceId: Int
    }

    public private(set) var sources: [Source] = []
    /// Returns a refusal for an unavailable name, or nil to accept it.
    public var validateName: ((String) -> String?)?
    private var nextSourceId = 0
    private var nextSliceId = 0

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
                id: nextSourceId, sample: sample, markers: [], slices: [],
                targetRate: SampleRatePolicy.targetRate(gbaReady: sample.gbaReady, sourceRate: sample.sampleRate)))
        nextSourceId += 1
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

    /// Removes a boundary, retaining the left slice; returns any used name the merge would remove.
    @discardableResult
    public func removeMarker(source: Int, frame: Int, usedNames: Set<String> = []) -> String? {
        guard let index = sourceIndex(source), let marker = sources[index].markers.firstIndex(of: frame)
        else { return nil }
        var staged = sources[index]
        removeMarker(at: marker, from: &staged)
        if let removed = removedUsedSlice(from: sources[index], after: staged, usedNames: usedNames) { return removed }
        sources[index] = staged
        return nil
    }

    /// Moves a boundary with optional snap; existing slices follow their old pair ordinals.
    public func moveMarker(source: Int, from: Int, to: Int, snap: Bool) {
        guard let index = sourceIndex(source), let marker = sources[index].markers.firstIndex(of: from) else { return }
        let boundary = markerFrame(to, source: sources[index], snap: snap)
        guard boundary != from, !sources[index].markers.contains(boundary) else { return }
        var staged = sources[index]
        let oldMarkers = staged.markers
        staged.markers.remove(at: marker)
        staged.markers.append(boundary)
        staged.markers.sort()
        for slice in staged.slices.indices {
            guard let ordinal = oldMarkers.firstIndex(of: staged.slices[slice].startFrame) else {
                preconditionFailure("Every slice must begin at a source marker")
            }
            staged.slices[slice].startFrame = staged.markers[ordinal]
            staged.slices[slice].endFrame = staged.markers[ordinal + 1]
        }
        sources[index] = staged
    }

    /// Creates one selection slice; returns any used name that merging its interior would remove.
    @discardableResult
    public func sliceSelection(
        source: Int, startFrame: Int, endFrame: Int, snap: Bool, usedNames: Set<String> = []
    ) -> String? {
        guard let index = sourceIndex(source) else { return nil }
        var staged = sources[index]
        let start = markerFrame(startFrame, source: staged, snap: snap)
        let end = markerFrame(endFrame, source: staged, snap: snap)
        guard start < end else { return nil }
        while let interior = staged.markers.firstIndex(where: { (frame: Int) in frame > start && frame < end }) {
            removeMarker(at: interior, from: &staged)
        }
        var nextId = nextSliceId
        guard insertMarker(start, into: &staged, nextId: &nextId),
            insertMarker(end, into: &staged, nextId: &nextId)
        else { return nil }
        if !staged.slices.contains(where: { (slice: Slice) in slice.startFrame == start && slice.endFrame == end }) {
            guard let slice = newSlice(start: start, end: end, source: staged, nextId: &nextId) else { return nil }
            staged.slices.append(slice)
            staged.slices.sort { (left: Slice, right: Slice) in left.startFrame < right.startFrame }
        }
        if let removed = removedUsedSlice(from: sources[index], after: staged, usedNames: usedNames) { return removed }
        sources[index] = staged
        nextSliceId = nextId
        return nil
    }

    /// Deletes only the indexed slice; retained marker pairs are not implicitly resurrected.
    public func removeSlice(source: Int, slice: Int) {
        guard let index = sourceIndex(source), sources[index].slices.indices.contains(slice) else { return }
        sources[index].slices.remove(at: slice)
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

    /// Renders the indexed slice on demand, with no PCM cache or external effects.
    public func renderSlice(source: Int, slice: Int) -> ProcessedSample {
        guard let index = sourceIndex(source), sources[index].slices.indices.contains(slice) else {
            preconditionFailure("renderSlice requires an existing source and slice index")
        }
        let source = sources[index]
        let region = source.slices[slice]
        var params = SampleDocument.defaultParams(for: source.sample)
        params.cropStart = region.startFrame
        params.cropEnd = region.endFrame
        params.targetRate = source.targetRate
        params.loopOn = false
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
    public func renameSlice(source: Int, slice: Int, to: String) -> Bool {
        guard let index = sourceIndex(source), sources[index].slices.indices.contains(slice) else { return false }
        let name = SampleNames.sanitize(to)
        guard !name.isEmpty else { return false }
        if name == sources[index].slices[slice].name { return validateName?(name) == nil }
        guard nameAvailable(name, source: sources[index]) else { return false }
        sources[index].slices[slice].name = name
        return true
    }

    /// A source can close only when no zone names one of its current slices.
    public func canClose(source: Int, usedNames: Set<String>) -> Bool {
        guard let index = sourceIndex(source) else { return false }
        return !sources[index].slices.contains { (slice: Slice) in usedNames.contains(slice.name) }
    }

    /// Removes a source without reusing its identity; refuses while any slice is used.
    public func removeSource(source: Int, usedNames: Set<String>) -> Bool {
        guard canClose(source: source, usedNames: usedNames), let index = sourceIndex(source) else { return false }
        sources.remove(at: index)
        return true
    }

    private func removedUsedSlice(from original: Source, after staged: Source, usedNames: Set<String>) -> String? {
        guard !usedNames.isEmpty else { return nil }
        let remaining = Set(staged.slices.map(\.name))
        return original.slices.first { (slice: Slice) -> Bool in
            usedNames.contains(slice.name) && !remaining.contains(slice.name)
        }?.name
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
        for number in 0...99 {
            let suffix = number < 10 ? "0\(number)" : "\(number)"
            let name = "\(prefix)_\(suffix)"
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
            guard let slice = newSlice(start: start, end: end, source: source, nextId: &nextId) else { return false }
            source.slices.insert(slice, at: ordinal == 0 ? 0 : source.slices.count)
        }
        source.markers.insert(frame, at: ordinal)
        return true
    }

    private func removeMarker(at ordinal: Int, from source: inout Source) {
        let frame = source.markers[ordinal]
        let left = source.slices.firstIndex { (slice: Slice) in slice.endFrame == frame }
        let right = source.slices.firstIndex { (slice: Slice) in slice.startFrame == frame }
        if ordinal > 0 && ordinal + 1 < source.markers.count {
            if let left {
                source.slices[left].endFrame = source.markers[ordinal + 1]
                if let right { source.slices.remove(at: right) }
            } else if let right {
                source.slices[right].startFrame = source.markers[ordinal - 1]
            }
        } else if let adjacent = left ?? right {
            source.slices.remove(at: adjacent)
        }
        source.markers.remove(at: ordinal)
    }
}
