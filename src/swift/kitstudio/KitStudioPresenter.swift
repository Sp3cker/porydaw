import PorydawAppAudio
import PorydawAppPresentation
import PorydawSample
import PorydawSampleUI
import PorydawVoicegroup
import QtBridge

@MainActor
@QtBridgeable
public final class KitZoneRow: QmlUncreatable {
    public let startKey: Int
    public let endKey: Int
    public let sampleName: String
    public let rootKey: Int
    public let pan: Int
    public let attack: Int
    public let decay: Int
    public let sustain: Int
    public let release: Int
    public let selected: Bool
    public let panEnabled: Bool
    public let sliceBadge: Int
    private let modeIndex: Int

    init(zone: KitZone, selected: Bool, mode: KitMode, badge: Int) {
        modeIndex = mode == .drumkit ? 0 : 1
        startKey = zone.startKey
        endKey = zone.endKey
        sampleName = zone.sampleName
        rootKey = zone.rootKey
        pan = zone.pan
        attack = zone.adsr.attack
        decay = zone.adsr.decay
        sustain = zone.adsr.sustain
        release = zone.adsr.release
        self.selected = selected
        panEnabled = mode == .drumkit
        sliceBadge = badge
    }

    func matches(zone: KitZone, selected: Bool, mode: KitMode, badge: Int) -> Bool {
        startKey == zone.startKey && endKey == zone.endKey && sampleName == zone.sampleName
            && rootKey == zone.rootKey && pan == zone.pan
            && attack == zone.adsr.attack && decay == zone.adsr.decay && sustain == zone.adsr.sustain
            && release == zone.adsr.release && sliceBadge == badge
            && self.selected == selected && modeIndex == (mode == .drumkit ? 0 : 1)
    }
}

@MainActor
@QtBridgeable
public final class KitSourceRow: QmlUncreatable {
    public let id: Int
    public let name: String
    public let sliceCount: Int
    public let active: Bool

    init(source: KitSourceSession.Source, active: Bool) {
        id = source.id
        name = source.sample.suggestedName
        sliceCount = source.slices.count
        self.active = active
    }

    func matches(source: KitSourceSession.Source, active: Bool) -> Bool {
        id == source.id && name == source.sample.suggestedName && sliceCount == source.slices.count
            && self.active == active
    }
}

/// Window state only; the workflow supplies facts and owns every external effect.
@MainActor
@QtBridgeable
public final class KitStudioPresenter: QmlUncreatable {
    public var titleText: String = ""
    public var dirty: Bool = false
    public var mode: Int = 0
    public var saving: Bool = false
    public var metaText: String = ""
    public var voicegroupName: String = ""
    public var voicegroupNameInvalid: Bool = false
    public var canSave: Bool = false
    public var canUndo: Bool = false
    public var canRedo: Bool = false
    public var zoneRows: QListModel<KitZoneRow> = QListModel()
    public var sourceRows: QListModel<KitSourceRow> = QListModel()
    @QtTracked public var waveform: MarkerWaveformModel? = nil
    public var selectedZone: Int = -1
    public var selectedZoneFirstKey: Int = 0
    public var selectedZoneLastKey: Int = 0
    public var selectedZoneSampleName: String = ""
    public var selectedZoneRootKey: Int = 60
    public var selectedZonePan: Int = 0
    public var selectedZoneAttack: Int = 0
    public var selectedZoneDecay: Int = 0
    public var selectedZoneSustain: Int = 0
    public var selectedZoneRelease: Int = 0
    public var selectedZonePanEnabled: Bool = false
    public var selectedSlice: Int = -1
    public var snap: Bool = true
    public var sliceCount: Int = 0
    public var fileRateText: String = ""
    public var sourceRate: Int = 0
    public var rateChoices: [String] = []
    public var stateRevision: Int = 0
    public var slicesRevision: Int = 0
    private var lastAddedMarkerId: Int?
    @QtIgnored public var onSaveRequested: (() -> Void)?
    @QtIgnored public var onAlert: ((String) -> Void)?
    @QtIgnored public var validateName: ((String) -> String?)?
    @QtIgnored public var validateVoicegroupName: ((String) -> String?)?
    @QtIgnored public var publishKitTone: ((KitAuditionTone, UInt8) -> Bool)?
    @QtIgnored public var playPcm: ((Int) -> Void)?
    @QtIgnored public var samples: [String: ProcessedSample] = [:]
    @QtIgnored public var progWaves: [String: [UInt32]] = [:]
    @QtIgnored public let draft: KitDraft
    @QtIgnored public let session: KitSourceSession
    public private(set) var voicegroupNameEdited = false

    private var activeSource: Int?
    private var displayedSource: Int?
    private weak var displayedWaveform: MarkerWaveformModel?
    private var activeMode: KitMode = .drumkit
    private var cleanMode: KitMode = .drumkit
    private var cleanSessionSnapshot: KitSourceSession.Snapshot

    @QtIgnored public init(draft: KitDraft = KitDraft(), session: KitSourceSession = KitSourceSession()) {
        self.draft = draft
        self.session = session
        draft.attachSession(session)
        cleanSessionSnapshot = session.snapshot()
        session.validateName = { [weak self] (name: String) -> String? in self?.validateName?(name) }
    }

    /// Opens an empty kit; the window never reads a song kit.
    @QtIgnored public func open() {
        draft.load(KitDraft.Snapshot())
        session.restore(KitSourceSession().snapshot())
        activeMode = .drumkit
        selectedZone = -1
        activeSource = nil
        displayedSource = nil
        voicegroupName = ""
        voicegroupNameInvalid = true
        voicegroupNameEdited = false
        saving = false
        resetCleanState()
        refresh()
    }

    /// Applies the workflow's suggested name unless the user already chose one.
    @QtIgnored public func applySuggestedVoicegroupName(_ name: String) {
        guard !voicegroupNameEdited else { return }
        voicegroupName = name
        voicegroupNameInvalid = Self.invalidVoicegroupName(name, validate: validateVoicegroupName)
        refresh()
    }

    public func setVoicegroupName(name: String) {
        voicegroupName = name
        voicegroupNameEdited = true
        voicegroupNameInvalid = Self.invalidVoicegroupName(name, validate: validateVoicegroupName)
        refresh()
    }

    private static func invalidVoicegroupName(
        _ name: String, validate: ((String) -> String?)?
    ) -> Bool {
        name.isEmpty || validate?(name) != nil
    }

    @QtIgnored public func markClean() {
        draft.markClean()
        cleanMode = activeMode
        cleanSessionSnapshot = session.snapshot()
        refresh()
    }

    private func resetCleanState() {
        cleanMode = activeMode
        cleanSessionSnapshot = session.snapshot()
    }

    public func requestSave() { if canSave { onSaveRequested?() } }

    public func selectZone(row: Int) {
        selectedZone = zones.indices.contains(row) ? row : -1
        if selectedZone != -1 {
            let sampleName = zones[selectedZone].sampleName
            if let found = session.sources.first(where: { $0.slices.contains { $0.name == sampleName } }) {
                if activeSource != found.id { activeSource = found.id }
                if let slice = found.slices.first(where: { $0.name == sampleName }) {
                    selectedSlice = draft.sliceIds[KitDraft.SliceKey(source: found.id, identity: slice.id)] ?? -1
                }
            }
        } else {
            selectedSlice = -1
        }
        refresh()
    }

    public func selectSlice(id: Int) {
        selectedSlice = id
        guard let address = sliceAddress(id),
            let source = session.sources.first(where: { $0.id == address.source })
        else {
            refresh()
            return
        }
        let slice = source.slices[address.index]
        if activeSource != source.id {
            activeSource = source.id
        }
        if let zoneRow = zones.firstIndex(where: { $0.sampleName == slice.name }) {
            selectZone(row: zoneRow)
        } else {
            refresh()
        }
    }

    /// Typed per-key reads for the AOT-compiled keyboard: QML never indexes zoneRows.
    public func zoneCount() -> Int { zones.count }
    public func zoneIndexAtKey(key: Int) -> Int {
        zones.firstIndex { $0.startKey <= key && key <= $0.endKey } ?? -1
    }
    public func zoneSelected(row: Int) -> Bool { row == selectedZone }
    public func zoneStartKey(row: Int) -> Int { zones.indices.contains(row) ? zones[row].startKey : 0 }
    public func zoneEndKey(row: Int) -> Int { zones.indices.contains(row) ? zones[row].endKey : 0 }
    public func zoneBadge(row: Int) -> Int {
        guard zones.indices.contains(row) else { return 0 }
        return sliceNumber(name: zones[row].sampleName)
    }

    public func setMode(index: Int) {
        guard index == 0 || index == 1 else { return }
        activeMode = index == 0 ? .drumkit : .keysplit
        selectedZone = -1
        refresh()
    }

    public func dropSample(name: String, onKey: Int) {
        guard (0...127).contains(onKey), !name.isEmpty else { return }
        guard !zones.contains(where: { $0.startKey <= onKey && onKey <= $0.endKey }) else {
            onAlert?("That key is already occupied")
            refresh()
            return
        }
        let end = activeMode == .drumkit ? onKey : (zones.first { $0.startKey > onKey }?.startKey ?? 128) - 1
        var next = zones
        next.append(newZone(name: name, start: onKey, end: end))
        next.sort { $0.startKey < $1.startKey }
        if commitZones(next) { selectedZone = next.firstIndex { $0.startKey == onKey } ?? -1 }
        refresh()
    }

    public func moveZone(row: Int, toKey: Int) {
        guard zones.indices.contains(row) else { return }
        var next = zones
        let width = next[row].endKey - next[row].startKey
        let start = min(max(0, toKey), 127 - width)
        next[row].startKey = start
        next[row].endKey = start + width
        next.sort { $0.startKey < $1.startKey }
        if commitZones(next) { selectedZone = next.firstIndex { $0.startKey == start } ?? -1 }
        refresh()
    }

    public func resizeZone(row: Int, startKey: Int, endKey: Int) {
        guard zones.indices.contains(row) else { return }
        var next = zones
        next[row].startKey = min(max(0, startKey), 127)
        next[row].endKey = min(max(0, endKey), 127)
        let start = next[row].startKey
        next.sort { $0.startKey < $1.startKey }
        if commitZones(next) { selectedZone = next.firstIndex { $0.startKey == start } ?? -1 }
        refresh()
    }

    /// Moves one edge of a range to `key`, never past the opposite edge.
    public func dragZoneEdge(row: Int, fromStart: Bool, key: Int) {
        guard zones.indices.contains(row) else { return }
        let zone = zones[row]
        selectZone(row: row)
        if fromStart {
            resizeZone(row: row, startKey: min(key, zone.endKey), endKey: zone.endKey)
        } else {
            resizeZone(row: row, startKey: zone.startKey, endKey: max(key, zone.startKey))
        }
    }

    public func deleteZone(row: Int) {
        guard zones.indices.contains(row) else { return }
        var next = zones
        next.remove(at: row)
        if commitZones(next) { selectedZone = -1 }
        refresh()
    }

    public func setZoneRootKey(key: Int) {
        editSelected { $0.rootKey = min(max(0, key), 127) }
    }
    public func setZonePan(pan: Int) {
        guard activeMode == .drumkit else { return }
        editSelected { $0.pan = min(max(-64, pan), 63) }
    }
    public func setZoneAdsr(a: Int, d: Int, s: Int, r: Int) {
        editSelected {
            $0.adsr = (min(max(0, a), 255), min(max(0, d), 255), min(max(0, s), 255), min(max(0, r), 255))
        }
    }

    private var zones: [KitZone] { activeMode == .drumkit ? draft.drumkitZones : draft.keysplitZones }
    var currentSource: KitSourceSession.Source? { session.sources.first { $0.id == activeSource } }

    /// `rateChoices` row for a saved-at rate; row 0 is the file's own rate.
    public func rateChoiceIndex(rate: Double) -> Int {
        guard let source = currentSource else { return -1 }
        if rate.rounded() == source.sample.sampleRate.rounded() { return 0 }
        return SampleRatePolicy.rates.firstIndex(of: Int(rate.rounded())).map { (index: Int) -> Int in index + 1 } ?? -1
    }

    @QtIgnored public func rate(forChoice index: Int) -> Optional<Int> {
        guard let source = currentSource else { return nil }
        if index == 0 { return Int(source.sample.sampleRate.rounded()) }
        return SampleRatePolicy.rates.indices.contains(index - 1) ? SampleRatePolicy.rates[index - 1] : nil
    }

    private func newZone(name: String, start: Int, end: Int) -> KitZone {
        KitZone(
            startKey: start, endKey: end, sampleName: name, rootKey: 60, pan: 0,
            adsr: (255, 0, 255, 0))
    }

    private func editSelected(_ edit: (inout KitZone) -> Void) {
        guard zones.indices.contains(selectedZone) else { return }
        var next = zones
        edit(&next[selectedZone])
        _ = commitZones(next)
        refresh()
    }

    @discardableResult private func commitZones(_ next: [KitZone]) -> Bool {
        guard next != zones else { return true }
        let accepted = activeMode == .drumkit ? draft.setDrumkitZones(next) : draft.setKeysplitZones(next)
        if accepted {
            return true
        } else {
            onAlert?("Zones must stay within 0–127 and cannot overlap")
            return false
        }
    }

    private func autoPlaceSlice(_ sliceName: String) {
        guard let key = nextFreeKey(from: 36) else { return }
        var drumkit = draft.drumkitZones
        var keysplit = draft.keysplitZones
        drumkit.append(newZone(name: sliceName, start: key, end: key))
        keysplit.append(newZone(name: sliceName, start: key, end: key))
        drumkit.sort { $0.startKey < $1.startKey }
        keysplit.sort { $0.startKey < $1.startKey }
        _ = draft.setDrumkitZones(drumkit)
        _ = draft.setKeysplitZones(keysplit)
    }

    private func removeSliceZones(_ sliceNames: Set<String>) {
        guard !sliceNames.isEmpty else { return }
        var drumkit = draft.drumkitZones
        var keysplit = draft.keysplitZones
        let drumBefore = drumkit.count
        let keyBefore = keysplit.count
        drumkit.removeAll { sliceNames.contains($0.sampleName) }
        keysplit.removeAll { sliceNames.contains($0.sampleName) }
        if drumkit.count != drumBefore { _ = draft.setDrumkitZones(drumkit) }
        if keysplit.count != keyBefore { _ = draft.setKeysplitZones(keysplit) }
        if selectedZone >= zones.count { selectedZone = -1 }
    }

    @QtIgnored public func nextFreeKey(from startKey: Int = 36) -> Optional<Int> {
        for key in startKey...127 {
            let inDrum = draft.drumkitZones.contains { $0.startKey <= key && key <= $0.endKey }
            let inKey = draft.keysplitZones.contains { $0.startKey <= key && key <= $0.endKey }
            if !inDrum && !inKey { return key }
        }
        return nil
    }

    private func changeSessionWithAutoPlace(_ change: (KitSourceSession) -> Void) {
        draft.edit {
            let slicesBefore = Set(session.sources.flatMap { $0.slices.map(\.name) })
            change(session)
            let slicesAfter = Set(session.sources.flatMap { $0.slices.map(\.name) })
            let removed = slicesBefore.subtracting(slicesAfter)
            let added = slicesAfter.subtracting(slicesBefore)
            if !removed.isEmpty {
                removeSliceZones(removed)
            }
            if !added.isEmpty {
                for name in session.sources.flatMap(\.slices).map(\.name) where added.contains(name) {
                    autoPlaceSlice(name)
                }
            }
        }
        refresh()
    }

    @QtIgnored public func addSource(_ sample: ImportedSample, autoPlaceFirstSlice: Bool = false) {
        changeSessionWithAutoPlace { (target: KitSourceSession) in
            target.addSource(sample)
            activeSource = target.sources.last?.id
            if autoPlaceFirstSlice, let id = activeSource {
                target.createFirstSlice(source: id)
            }
        }
        // Slices exist but nothing is selected (fresh file load): show slice 1
        // in the inspector instead of an empty panel.
        if selectedZone < 0, !zones.isEmpty {
            selectZone(row: 0)
        }
    }

    public func selectSource(row: Int) {
        guard session.sources.indices.contains(row) else { return }
        activeSource = session.sources[row].id
        refresh()
    }

    public func closeSource(row: Int) {
        guard session.sources.indices.contains(row) else { return }
        let id = session.sources[row].id
        changeSessionWithAutoPlace { _ = $0.removeSource(source: id) }
    }

    public func addMarker(atX x: Double) {
        guard let waveform else { return }
        placeMarker(frame: waveform.frameAt(x), ensureFirstSlice: true)
    }

    public func insertMarker(frame: Int) {
        placeMarker(frame: frame, ensureFirstSlice: false)
    }

    private func placeMarker(frame: Int, ensureFirstSlice: Bool) {
        guard let id = activeSource else { return }
        let beforeMarkers = currentSource?.markers ?? []
        changeSessionWithAutoPlace {
            if ensureFirstSlice, $0.sources.first(where: { $0.id == id })?.slices.isEmpty == true {
                $0.createFirstSlice(source: id)
            }
            $0.setMarker(source: id, frame: frame, snap: snap)
        }
        let afterMarkers = currentSource?.markers ?? []
        let added = Set(afterMarkers).subtracting(beforeMarkers)
        if let newFrame = added.first,
            let newId = draft.markerIds[KitDraft.MarkerKey(source: id, frame: newFrame)]
        {
            lastAddedMarkerId = newId
        }
    }

    public func markerId(row: Int) -> Int {
        guard let source = currentSource, source.markers.indices.contains(row) else { return 0 }
        return draft.markerIds[KitDraft.MarkerKey(source: source.id, frame: source.markers[row])] ?? 0
    }

    public func removeMarkerAt(x: Double, y: Double) {
        guard let waveform else { return }
        let handle = waveform.handleAt(x: x, y: y)
        guard handle != 0 else { return }
        if handle == lastAddedMarkerId { return }
        removeMarker(id: handle)
    }

    public func removeMarker(id: Int) {
        guard let key = markerKey(id) else { return }
        changeSessionWithAutoPlace { $0.removeMarker(source: key.source, frame: key.frame) }
        if lastAddedMarkerId == id { lastAddedMarkerId = nil }
    }

    public func clearLastAddedMarker() {
        lastAddedMarkerId = nil
    }

    public func moveMarker(id: Int, toFrame: Int) {
        guard let key = markerKey(id) else { return }
        draft.moveMarker(key, toFrame: toFrame, snap: snap)
        refresh()
    }

    public func toggleSnap() { snap.toggle() }

    public func renameSlice(id: Int, name: String) {
        guard let address = sliceAddress(id), let source = session.sources.first(where: { $0.id == address.source })
        else { return }
        let oldName = source.slices[address.index].name
        var renamed = false
        draft.edit {
            guard session.renameSlice(source: address.source, slice: address.index, to: name) else {
                return
            }
            guard let updated = session.sources.first(where: { $0.id == address.source }) else { return }
            let newName = updated.slices[address.index].name
            guard oldName != newName else { return }
            var drumkit = draft.drumkitZones
            var keysplit = draft.keysplitZones
            for index in drumkit.indices where drumkit[index].sampleName == oldName {
                drumkit[index].sampleName = newName
            }
            for index in keysplit.indices where keysplit[index].sampleName == oldName {
                keysplit[index].sampleName = newName
            }
            if drumkit != draft.drumkitZones { _ = draft.setDrumkitZones(drumkit) }
            if keysplit != draft.keysplitZones { _ = draft.setKeysplitZones(keysplit) }
            renamed = true
        }
        if renamed { refresh() }
    }

    public func removeSlice(id: Int) {
        guard let address = sliceAddress(id) else { return }
        changeSessionWithAutoPlace { $0.removeSlice(source: address.source, slice: address.index) }
    }

    public func setSourceRate(rate: Int) {
        guard let id = activeSource else { return }
        changeSession { _ = $0.setSourceRate(source: id, rate: rate) }
    }

    /// Kit-wide table order: every slice across all loaded files, in kit
    /// number order, so added one-shots stay visible. Selecting a row
    /// switches to its file's tab through selectSlice.
    public func sliceId(row: Int) -> Int {
        guard row >= 0 else { return 0 }
        var count = 0
        for source in session.sources {
            if row - count < source.slices.count {
                let identity = source.slices[row - count].id
                return draft.sliceIds[KitDraft.SliceKey(source: source.id, identity: identity)] ?? 0
            }
            count += source.slices.count
        }
        return 0
    }

    /// Newest slice id for scroll-to-row after a table drop add; 0 when empty.
    public func newestSliceId() -> Int {
        draft.sliceIds.values.max() ?? 0
    }

    public func sliceName(id: Int) -> String { sliceValue(id)?.name ?? "" }
    public func sliceStartFrame(id: Int) -> Int { sliceValue(id)?.startFrame ?? 0 }
    public func sliceEndFrame(id: Int) -> Int { sliceValue(id)?.endFrame ?? 0 }
    public func sliceNumber(name: String) -> Int {
        var count = 0
        for source in session.sources {
            for slice in source.slices {
                count += 1
                if slice.name == name { return count }
            }
        }
        return 0
    }

    public func sliceOrdinal(id: Int) -> Int {
        guard let address = sliceAddress(id) else { return 0 }
        var count = 0
        for source in session.sources {
            if source.id == address.source { return count + address.index + 1 }
            count += source.slices.count
        }
        return 0
    }

    public func isSliceNameInvalid(sliceId: Int, name: String) -> Bool {
        guard !name.isEmpty else { return true }
        let sanitized = SampleNames.sanitize(name)
        guard sanitized == name else { return true }
        guard let address = sliceAddress(sliceId),
            let currentSource = session.sources.first(where: { $0.id == address.source })
        else { return true }
        let currentSlice = currentSource.slices[address.index]
        for source in session.sources {
            for slice in source.slices {
                if (source.id != address.source || slice.id != currentSlice.id) && slice.name == name {
                    return true
                }
            }
        }
        return validateName?(name) != nil
    }

    public func playSlice(id: Int) { if sliceAddress(id) != nil { playPcm?(id) } }
    public func playSelectedSlice() {
        playSlice(id: sliceAddress(selectedSlice) != nil ? selectedSlice : sliceId(row: 0))
    }

    /// Engine note and envelope for the slice's lowest mapped zone: drumkits sound the zone's
    /// root key, keysplits the zone key nearest it. Nil while the slice is unmapped.
    @QtIgnored public func sliceVoice(id: Int) -> Optional<(note: UInt8, adsr: AudioADSR)> {
        guard let name = sliceValue(id)?.name,
            let zone = zones.filter({ (zone: KitZone) -> Bool in zone.sampleName == name })
                .min(by: { (a: KitZone, b: KitZone) -> Bool in a.startKey < b.startKey })
        else { return nil }
        let note = activeMode == .drumkit ? zone.rootKey : min(max(zone.rootKey, zone.startKey), zone.endKey)
        let adsr = AudioADSR(
            attack: UInt8(clamping: zone.adsr.attack), decay: UInt8(clamping: zone.adsr.decay),
            sustain: UInt8(clamping: zone.adsr.sustain), release: UInt8(clamping: zone.adsr.release))
        return (UInt8(clamping: note), adsr)
    }

    public func playKey(key: Int) {
        guard (0...127).contains(key), let publishKitTone,
            zones.contains(where: { $0.startKey <= key && key <= $0.endKey })
        else { return }
        var rendered = samples
        let names = Set(zones.map(\.sampleName))
        for source in session.sources {
            for (index, slice) in source.slices.enumerated() where names.contains(slice.name) {
                rendered[slice.name] = session.renderSlice(source: source.id, slice: index)
            }
        }
        guard
            let tone = KitDraftCodec.auditionTone(
                draft: draft.snapshot(), mode: activeMode, key: key, samples: rendered, progWaves: progWaves)
        else { return }
        _ = publishKitTone(tone, UInt8(key))
    }

    @QtIgnored public func renderedSlice(id: Int) -> Optional<ProcessedSample> {
        guard let address = sliceAddress(id) else { return nil }
        return session.renderSlice(source: address.source, slice: address.index)
    }

    /// Converts the audition player's rendered-grid position back to a source frame.
    @QtIgnored public func sourceFrame(sliceId: Int, renderedPosition: Double) -> Optional<Int> {
        guard renderedPosition.isFinite, let address = sliceAddress(sliceId),
            let source = session.sources.first(where: { $0.id == address.source }),
            source.sample.sampleRate.isFinite, source.targetRate.isFinite,
            source.sample.sampleRate > 0, source.targetRate > 0
        else { return nil }
        let slice = source.slices[address.index]
        let offset = min(
            max(0, renderedPosition / (source.targetRate / source.sample.sampleRate)),
            Double(slice.endFrame - slice.startFrame))
        return slice.startFrame + Int(offset.rounded())
    }

    public func undo() {
        guard draft.canUndo else { return }
        let before = session.snapshot()
        draft.undo()
        if session.snapshot() != before { displayedSource = nil }
        refresh()
    }

    public func redo() {
        guard draft.canRedo else { return }
        let before = session.snapshot()
        draft.redo()
        if session.snapshot() != before { displayedSource = nil }
        refresh()
    }

    private func changeSession(_ change: (KitSourceSession) -> Void) {
        draft.edit {
            change(session)
        }
        refresh()
    }

    private func markerKey(_ id: Int) -> KitDraft.MarkerKey? {
        guard let key = draft.markerIds.first(where: { $0.value == id })?.key,
            session.sources.contains(where: { $0.id == key.source && $0.markers.contains(key.frame) })
        else { return nil }
        return key
    }

    @QtIgnored public func sliceAddress(_ id: Int) -> (source: Int, index: Int)? {
        guard let key = draft.sliceIds.first(where: { $0.value == id })?.key,
            let source = session.sources.first(where: { $0.id == key.source }),
            let index = source.slices.firstIndex(where: { $0.id == key.identity })
        else { return nil }
        return (key.source, index)
    }

    private func sliceValue(_ id: Int) -> KitSourceSession.Slice? {
        guard let address = sliceAddress(id), let source = session.sources.first(where: { $0.id == address.source })
        else { return nil }
        return source.slices[address.index]
    }

    /// Re-publishes values after the workflow injects a waveform or value-only facts.
    @QtIgnored public func refresh() {
        mode = activeMode == .drumkit ? 0 : 1
        dirty = draft.dirty || activeMode != cleanMode || session.snapshot() != cleanSessionSnapshot
        canSave = !zones.isEmpty && !saving && !voicegroupNameInvalid && !voicegroupName.isEmpty
        canUndo = draft.canUndo
        canRedo = draft.canRedo
        titleText = "Split Studio" + (dirty ? " •" : "")
        updateMeta()
        if !zones.indices.contains(selectedZone) { selectedZone = -1 }
        selectedZoneFirstKey = zones.indices.contains(selectedZone) ? zones[selectedZone].startKey : 0
        selectedZoneLastKey = zones.indices.contains(selectedZone) ? zones[selectedZone].endKey : 0
        selectedZoneSampleName = zones.indices.contains(selectedZone) ? zones[selectedZone].sampleName : ""
        selectedZoneRootKey = zones.indices.contains(selectedZone) ? zones[selectedZone].rootKey : 60
        selectedZonePan = zones.indices.contains(selectedZone) ? zones[selectedZone].pan : 0
        selectedZoneAttack = zones.indices.contains(selectedZone) ? zones[selectedZone].adsr.attack : 0
        selectedZoneDecay = zones.indices.contains(selectedZone) ? zones[selectedZone].adsr.decay : 0
        selectedZoneSustain = zones.indices.contains(selectedZone) ? zones[selectedZone].adsr.sustain : 0
        selectedZoneRelease = zones.indices.contains(selectedZone) ? zones[selectedZone].adsr.release : 0
        selectedZonePanEnabled = zones.indices.contains(selectedZone) && activeMode == .drumkit
        let zoneValues = zones.enumerated().map { (entry: (offset: Int, element: KitZone)) -> KitZoneRow in
            let selected = entry.offset == selectedZone
            let badge = sliceNumber(name: entry.element.sampleName)
            if entry.offset < zoneRows.count,
                zoneRows[entry.offset].matches(
                    zone: entry.element, selected: selected, mode: activeMode, badge: badge)
            {
                return zoneRows[entry.offset]
            }
            return KitZoneRow(zone: entry.element, selected: selected, mode: activeMode, badge: badge)
        }
        syncModel(zoneRows, zoneValues, matches: { (lhs: KitZoneRow, rhs: KitZoneRow) -> Bool in lhs === rhs })
        if !session.sources.contains(where: { $0.id == activeSource }) { activeSource = session.sources.first?.id }
        let sourceValues = session.sources.enumerated().map {
            (entry: (offset: Int, element: KitSourceSession.Source)) -> KitSourceRow in
            let active = entry.element.id == activeSource
            if entry.offset < sourceRows.count, sourceRows[entry.offset].matches(source: entry.element, active: active)
            {
                return sourceRows[entry.offset]
            }
            return KitSourceRow(source: entry.element, active: active)
        }
        syncModel(sourceRows, sourceValues, matches: { (lhs: KitSourceRow, rhs: KitSourceRow) -> Bool in lhs === rhs })
        sliceCount = session.sources.reduce(0) { (total: Int, source: KitSourceSession.Source) -> Int in
            total + source.slices.count
        }
        sourceRate = currentSource.flatMap { Int(exactly: $0.targetRate.rounded()) } ?? 0
        if let currentSource {
            let rate = currentSource.sample.sampleRate
            fileRateText = rate == rate.rounded() ? "\(Int(rate)) Hz" : String(format: "%.2f Hz", rate)
            rateChoices = ["File rate (\(fileRateText))"] + SampleRatePolicy.rates.map(String.init)
        } else {
            fileRateText = ""
            rateChoices = []
        }
        if let waveform {
            if displayedWaveform !== waveform {
                waveform.onMarkerDragged = { [weak self] (id: Int, frame: Int) in
                    self?.moveMarker(id: id, toFrame: frame)
                }
            }
            if displayedSource != activeSource || displayedWaveform !== waveform {
                let buffer = currentSource?.sample.buffer ?? []
                // Amplitude fit: quiet one-shots fill the height like the mockup.
                var peak: Float = 0
                for value in buffer {
                    let magnitude = value >= 0 ? value : -value
                    if magnitude > peak { peak = magnitude }
                }
                let fit = peak > 0.01 ? min(8, 0.9 / Double(peak)) : 1
                waveform.setSamples(
                    buffer, sampleRate: currentSource?.sample.sampleRate ?? 1, gain: fit)
                displayedSource = activeSource
                displayedWaveform = waveform
            }
            if let source = currentSource {
                waveform.setMarkers(
                    source.markers.map { (frame: Int) in
                        guard let id = draft.markerIds[KitDraft.MarkerKey(source: source.id, frame: frame)] else {
                            preconditionFailure("Published source markers must have presenter-owned ids")
                        }
                        return (id: id, frame: frame, kind: "slice", label: "")
                    })
                let frames = source.slices.map(\.startFrame)
                let numbers = source.slices.map { sliceNumber(name: $0.name) }
                waveform.setRegionBadges(frames: frames, numbers: numbers)
                if let address = sliceAddress(selectedSlice), address.source == source.id {
                    let slice = source.slices[address.index]
                    waveform.setHighlight(startFrame: slice.startFrame, endFrame: slice.endFrame)
                } else {
                    waveform.setHighlight(startFrame: 0, endFrame: 0)
                }
            } else {
                waveform.setMarkers([])
                waveform.setRegionBadges(frames: [], numbers: [])
                waveform.setHighlight(startFrame: 0, endFrame: 0)
            }
        }
        slicesRevision += 1
        stateRevision += 1
    }

    /// Footer readout: slice count across sources and ROM bytes of the unique
    /// samples the active layout maps, each counted once at its saved-at rate.
    private func updateMeta() {
        var slices = 0
        for source in session.sources { slices += source.slices.count }
        let mapped = Set(zones.map(\.sampleName))
        var seen = Set<String>()
        var bytes: UInt64 = 0
        for source in session.sources {
            for (index, slice) in source.slices.enumerated()
            where mapped.contains(slice.name) && seen.insert(slice.name).inserted {
                let rendered = session.renderSlice(source: source.id, slice: index)
                bytes += 16 + ((UInt64(rendered.size) + 3) & ~UInt64(3))
            }
        }
        metaText = "\(slices) \(slices == 1 ? "slice" : "slices") · \(Self.formatRomBytes(bytes)) ROM"
    }

    private static func formatRomBytes(_ bytes: UInt64) -> String {
        guard bytes >= 1024 else { return "\(bytes) bytes" }
        let tenths = (bytes * 10 + 512) / 1024
        return "\(tenths / 10).\(tenths % 10) KB"
    }
}
