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
    public let pitched: Bool
    public let pan: Int
    public let attack: Int
    public let decay: Int
    public let sustain: Int
    public let release: Int
    public let locked: Bool
    public let voiceType: String
    public let selected: Bool
    public let panEnabled: Bool
    public let pitchedEnabled: Bool
    public let rootKeyEnabled: Bool
    private let storedPitched: Bool
    private let modeIndex: Int
    private let lockedMacro: Int

    init(zone: KitZone, selected: Bool, mode: KitMode) {
        storedPitched = zone.pitched
        modeIndex = mode == .drumkit ? 0 : 1
        lockedMacro = Int(zone.lockedVoice?.macro.rawValue ?? -1)
        startKey = zone.startKey
        endKey = zone.endKey
        sampleName = zone.sampleName
        rootKey = zone.rootKey
        pitched = mode == .keysplit || zone.pitched
        pan = zone.pan
        attack = zone.adsr.attack
        decay = zone.adsr.decay
        sustain = zone.adsr.sustain
        release = zone.adsr.release
        locked = zone.locked
        voiceType = zone.lockedVoice.map { vgMacroDisplayName($0.macro) } ?? ""
        self.selected = selected
        panEnabled = !zone.locked && mode == .drumkit
        pitchedEnabled = !zone.locked && mode == .drumkit
        rootKeyEnabled = !zone.locked
    }

    func matches(zone: KitZone, selected: Bool, mode: KitMode) -> Bool {
        startKey == zone.startKey && endKey == zone.endKey && sampleName == zone.sampleName
            && rootKey == zone.rootKey && storedPitched == zone.pitched && pan == zone.pan
            && attack == zone.adsr.attack && decay == zone.adsr.decay && sustain == zone.adsr.sustain
            && release == zone.adsr.release && locked == zone.locked
            && lockedMacro == Int(zone.lockedVoice?.macro.rawValue ?? -1)
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
    public let closable: Bool

    init(source: KitSourceSession.Source, active: Bool, closable: Bool) {
        id = source.id
        name = source.sample.suggestedName
        sliceCount = source.slices.count
        self.active = active
        self.closable = closable
    }

    func matches(source: KitSourceSession.Source, active: Bool, closable: Bool) -> Bool {
        id == source.id && name == source.sample.suggestedName && sliceCount == source.slices.count
            && self.active == active && self.closable == closable
    }
}

/// Window state only; the workflow supplies facts and owns every external effect.
@MainActor
@QtBridgeable
public final class KitStudioPresenter: QmlUncreatable {
    public var titleText: String = ""
    public var dirty: Bool = false
    public var mode: Int = 0
    public var conflictVisible: Bool = false
    public var conflictText: String = ""
    public var switchBarVisible: Bool = false
    public var statusText: String = ""
    public var usedByText: String = ""
    public var canSave: Bool = false
    public var canUndo: Bool = false
    public var canRedo: Bool = false
    public var zoneRows: QListModel<KitZoneRow> = QListModel()
    public var slotRows: QListModel<KitSlotRow> = QListModel()
    public var sourceRows: QListModel<KitSourceRow> = QListModel()
    @QtTracked public var waveform: MarkerWaveformModel? = nil
    public var selectedZone: Int = -1
    public var selectedSlot: Int = -1
    public var retargetVisible: Bool = false
    public var retargetSlot: Int = -1
    public var snap: Bool = true
    public var cursorFrame: Int = 0
    public var selectionStartFrame: Int = 0
    public var selectionEndFrame: Int = 0
    public var sliceCount: Int = 0
    public var sourceRate: Int = 0
    public var rateChoices: [String] = []
    public var stateRevision: Int = 0
    public var slicesRevision: Int = 0

    @QtIgnored public var onSaveRequested: (() -> Void)?
    @QtIgnored public var onRetargetPrompt: ((_ answer: Int) -> Void)?
    @QtIgnored public var onConflictAnswer: ((_ keepMine: Bool) -> Void)?
    @QtIgnored public var onSwitchBack: (() -> Void)?
    @QtIgnored public var validateName: ((String) -> String?)?
    @QtIgnored public var onLoadKit: ((_ slot: Int) -> KitLoadResult?)?
    @QtIgnored public var usageScan: ((_ subgroup: String, _ table: String?, _ excludingSection: String) -> [String])?
    @QtIgnored public var publishKitTone: ((KitAuditionTone, UInt8) -> Bool)?
    @QtIgnored public var playPcm: ((Int) -> Void)?
    @QtIgnored public var samples: [String: ProcessedSample] = [:]
    @QtIgnored public var progWaves: [String: [UInt32]] = [:]
    @QtIgnored public let draft: KitDraft
    @QtIgnored public let session: KitSourceSession

    private let picker = KitSlotPicker()
    private var song = ""
    private var section = ""
    private var boundSlot = -1
    private var activeSource: Int?
    private var displayedSource: Int?
    private weak var displayedWaveform: MarkerWaveformModel?
    private var activeMode: KitMode = .drumkit
    private var cleanMode: KitMode = .drumkit
    private var cleanSessionSnapshot: KitSourceSession.Snapshot
    private var nextId = 1

    @QtIgnored public init(draft: KitDraft = KitDraft(), session: KitSourceSession = KitSourceSession()) {
        self.draft = draft
        self.session = session
        draft.attachSession(session)
        cleanSessionSnapshot = session.snapshot()
        session.validateName = { [weak self] (name: String) -> String? in self?.validateName?(name) }
    }

    /// Binds a clean target; callers guard dirty retargets before supplying new facts.
    @QtIgnored public func bind(
        song: String, section: String, voices: [VgVoice?], undefinedSlots: Set<Int>, slot: Int
    ) {
        self.song = song
        self.section = section
        boundSlot = slot
        draft.load(KitDraft.Snapshot())
        activeMode = .drumkit
        selectedZone = -1
        usedByText = ""
        resetCleanState()
        picker.bind(voices: voices, undefinedSlots: undefinedSlots, slot: slot)
        retargetVisible = false
        retargetSlot = -1
        switchBarVisible = false
        if let kind = picker.selectedKind() {
            load(slot: slot, kind: kind)
        } else {
            refresh()
        }
    }

    /// Re-publishes bank facts without rebinding the working kit or its pending target.
    @QtIgnored public func refreshSlots(voices: [VgVoice?], undefinedSlots: Set<Int>) {
        picker.refresh(voices: voices, undefinedSlots: undefinedSlots)
        syncModel(
            slotRows, picker.rows(existing: slotRows),
            matches: { (lhs: KitSlotRow, rhs: KitSlotRow) -> Bool in lhs === rhs })
        stateRevision += 1
    }

    public func selectSlot(row: Int) {
        switch picker.select(row: row, dirty: dirty) {
        case .unchanged: break
        case .prompt:
            retargetSlot = picker.pendingSlot ?? -1
            retargetVisible = true
            stateRevision += 1
        case .load(let slot, let kind): load(slot: slot, kind: kind)
        }
    }

    public func answerRetarget(answer: Int) {
        guard retargetVisible, (0...2).contains(answer) else { return }
        if answer == 2 {
            picker.cancel()
            retargetVisible = false
            retargetSlot = -1
        }
        onRetargetPrompt?(answer)
        if answer == 1 { completeRetarget() }
    }

    /// The workflow calls this only after a successful save when answering Save.
    @QtIgnored public func completeRetarget() {
        guard let target = picker.pendingTarget() else { return }
        load(slot: target.slot, kind: target.kind)
    }

    private func load(slot: Int, kind: KitSlotKind) {
        if kind == .empty {
            install(KitLoadResult(kind: .empty), slot: slot)
        } else if let result = onLoadKit?(slot) {
            install(result, slot: slot)
        } else {
            statusText = "Could not load voice \(slot)"
            refresh()
        }
    }

    /// Installs a workflow-loaded kit after reload, conflict resolution or voicegroup switch.
    @QtIgnored public func install(_ result: KitLoadResult, slot: Int) {
        let loadedZones: [KitZone]
        switch result.kind {
        case .drumkit:
            loadedZones = KitDraftCodec.drumkitZones(children: result.children)
        case .keysplit:
            guard let table = result.table else {
                statusText = "Could not load keysplit table"
                refresh()
                return
            }
            loadedZones = KitDraftCodec.keysplitZones(children: result.children, table: table)
        case .empty:
            loadedZones = []
        }
        draft.load(KitDraft.Snapshot(drumkitZones: loadedZones, keysplitZones: loadedZones))
        boundSlot = slot
        activeMode = result.kind == .keysplit ? .keysplit : .drumkit
        picker.commit(slot: slot, kind: result.kind)
        selectedZone = -1
        retargetVisible = false
        retargetSlot = -1
        conflictVisible = false
        conflictText = ""
        statusText = ""
        var usage = result.usageSections
        if let parent = result.parent, let usageScan {
            usage = usageScan(parent.symbol, result.table?.name, section)
        }
        let count = Set(usage.filter { $0 != section }).count
        usedByText = count == 0 ? "" : "used by \(count)"
        resetCleanState()
        refresh()
    }

    @QtIgnored public func markClean() {
        draft.markClean()
        cleanMode = activeMode
        cleanSessionSnapshot = session.snapshot()
        picker.markSaved(kind: activeMode == .drumkit ? .drumkit : .keysplit)
        conflictVisible = false
        conflictText = ""
        refresh()
    }

    private func resetCleanState() {
        cleanMode = activeMode
        cleanSessionSnapshot = session.snapshot()
        conflictVisible = false
        conflictText = ""
    }

    /// Dirty targets wait for an answer; clean targets reload through the workflow adapter.
    @QtIgnored public func songKitChanged() {
        guard let slot = picker.selectedSlot else { return }
        if dirty {
            conflictVisible = true
            conflictText = "Changed in the song"
        } else if let result = onLoadKit?(slot) {
            install(result, slot: slot)
        }
        stateRevision += 1
    }

    public func answerConflict(keepMine: Bool) {
        guard conflictVisible else { return }
        onConflictAnswer?(keepMine)
        if keepMine {
            conflictVisible = false
            conflictText = ""
        } else if let slot = picker.selectedSlot, let result = onLoadKit?(slot) {
            install(result, slot: slot)
        }
        stateRevision += 1
    }

    public func requestSave() { if canSave { onSaveRequested?() } }
    public func switchBack() { onSwitchBack?() }

    public func selectZone(row: Int) {
        selectedZone = zones.indices.contains(row) ? row : -1
        refresh()
    }

    public func selectedZoneRow() -> Optional<KitZoneRow> {
        guard (0..<zoneRows.count).contains(selectedZone) else { return nil }
        return zoneRows[selectedZone]
    }

    public func setMode(index: Int) {
        guard index == 0 || index == 1 else { return }
        activeMode = index == 0 ? .drumkit : .keysplit
        selectedZone = -1
        refresh()
    }

    public func dropSample(name: String, onKey: Int) {
        guard picker.selectedSlot != nil, (0...127).contains(onKey), !name.isEmpty else { return }
        guard !zones.contains(where: { $0.startKey <= onKey && onKey <= $0.endKey }) else {
            statusText = "That key is already occupied"
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

    public func deleteZone(row: Int) {
        guard zones.indices.contains(row) else { return }
        var next = zones
        next.remove(at: row)
        if commitZones(next) { selectedZone = -1 }
        refresh()
    }

    public func mapAllSlices(fromKey: Int, whiteKeysOnly: Bool) {
        guard let source = currentSource, (0...127).contains(fromKey), !source.slices.isEmpty else { return }
        let keys = (fromKey...127).filter { (key: Int) -> Bool in
            !whiteKeysOnly || ![1, 3, 6, 8, 10].contains(key % 12)
        }
        guard keys.count >= source.slices.count else {
            statusText = "Not enough keys for all slices"
            return
        }
        var next = zones
        for (index, slice) in source.slices.enumerated() {
            let start = keys[index]
            let end: Int
            if activeMode == .drumkit || whiteKeysOnly {
                end = start
            } else if index + 1 < source.slices.count {
                end = keys[index + 1] - 1
            } else {
                end = (zones.first { $0.startKey > start }?.startKey ?? 128) - 1
            }
            next.append(newZone(name: slice.name, start: start, end: end))
        }
        next.sort { $0.startKey < $1.startKey }
        _ = commitZones(next)
        refresh()
    }

    public func setZoneRootKey(key: Int) {
        editSelected { $0.rootKey = min(max(0, key), 127) }
    }
    public func setZonePitched(on: Bool) {
        guard activeMode == .drumkit else { return }
        editSelected { $0.pitched = on }
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
    private var currentSource: KitSourceSession.Source? { session.sources.first { $0.id == activeSource } }
    private var usedNames: Set<String> { Set((draft.drumkitZones + draft.keysplitZones).map(\.sampleName)) }

    private func newZone(name: String, start: Int, end: Int) -> KitZone {
        KitZone(
            startKey: start, endKey: end, sampleName: name, rootKey: 60, pitched: false, pan: 0,
            adsr: (255, 0, 255, 0))
    }

    private func editSelected(_ edit: (inout KitZone) -> Void) {
        guard zones.indices.contains(selectedZone), !zones[selectedZone].locked else { return }
        var next = zones
        edit(&next[selectedZone])
        _ = commitZones(next)
        refresh()
    }

    @discardableResult private func commitZones(_ next: [KitZone]) -> Bool {
        guard next != zones else { return true }
        let accepted = activeMode == .drumkit ? draft.setDrumkitZones(next) : draft.setKeysplitZones(next)
        if accepted {
            statusText = ""
        } else {
            statusText = "Zones must stay within 0–127 and cannot overlap"
        }
        return accepted
    }

    @QtIgnored public func addSource(_ sample: ImportedSample) {
        changeSession { (target: KitSourceSession) in
            target.addSource(sample)
            activeSource = target.sources.last?.id
        }
    }

    public func selectSource(row: Int) {
        guard session.sources.indices.contains(row) else { return }
        activeSource = session.sources[row].id
        cursorFrame = 0
        selectionStartFrame = 0
        selectionEndFrame = 0
        refresh()
    }

    public func closeSource(row: Int) {
        guard session.sources.indices.contains(row) else { return }
        let id = session.sources[row].id
        guard session.canClose(source: id, usedNames: usedNames) else {
            statusText = "This source has slices in use"
            return
        }
        changeSession { _ = $0.removeSource(source: id, usedNames: usedNames) }
    }

    public func addMarkerAtCursor() {
        guard let id = activeSource else { return }
        changeSession { $0.setMarker(source: id, frame: cursorFrame, snap: snap) }
    }

    public func markerId(row: Int) -> Int {
        guard let source = currentSource, source.markers.indices.contains(row) else { return 0 }
        return draft.markerIds[KitDraft.MarkerKey(source: source.id, frame: source.markers[row])] ?? 0
    }

    public func removeMarker(id: Int) {
        guard let key = markerKey(id) else { return }
        changeSession { (target: KitSourceSession) in
            if let removed = target.removeMarker(source: key.source, frame: key.frame, usedNames: usedNames) {
                statusText = "\(removed) is used by a zone; remove those zones first."
            }
        }
    }

    public func moveMarker(id: Int, toFrame: Int) {
        guard let key = markerKey(id),
            let oldSource = session.sources.first(where: { $0.id == key.source })
        else { return }
        changeSession { (target: KitSourceSession) in
            target.moveMarker(source: key.source, from: key.frame, to: toFrame, snap: snap)
            if let source = target.sources.first(where: { $0.id == key.source }), !source.markers.contains(key.frame),
                let frame = source.markers.first(where: { !oldSource.markers.contains($0) })
            {
                draft.markerIds.removeValue(forKey: key)
                draft.markerIds[KitDraft.MarkerKey(source: key.source, frame: frame)] = id
            }
        }
    }

    public func sliceSelection() {
        guard let id = activeSource else { return }
        changeSession { (target: KitSourceSession) in
            if let removed = target.sliceSelection(
                source: id, startFrame: selectionStartFrame, endFrame: selectionEndFrame, snap: snap,
                usedNames: usedNames
            ) {
                statusText = "\(removed) is used by a zone; remove those zones first."
            }
        }
    }

    public func toggleSnap() { snap.toggle() }

    public func renameSlice(id: Int, name: String) {
        guard let address = sliceAddress(id), let source = session.sources.first(where: { $0.id == address.source })
        else { return }
        let oldName = source.slices[address.index].name
        var renamed = false
        draft.edit {
            guard session.renameSlice(source: address.source, slice: address.index, to: name) else {
                statusText = validateName?(SampleNames.sanitize(name)) ?? "Slice name is unavailable"
                return
            }
            guard let updated = session.sources.first(where: { $0.id == address.source }) else { return }
            let newName = updated.slices[address.index].name
            guard oldName != newName else { return }
            var drumkit = draft.drumkitZones
            var keysplit = draft.keysplitZones
            for index in drumkit.indices where !drumkit[index].locked && drumkit[index].sampleName == oldName {
                drumkit[index].sampleName = newName
            }
            for index in keysplit.indices where !keysplit[index].locked && keysplit[index].sampleName == oldName {
                keysplit[index].sampleName = newName
            }
            if drumkit != draft.drumkitZones { _ = draft.setDrumkitZones(drumkit) }
            if keysplit != draft.keysplitZones { _ = draft.setKeysplitZones(keysplit) }
            statusText = ""
            renamed = true
        }
        if renamed { refresh() }
    }

    public func removeSlice(id: Int) {
        guard let address = sliceAddress(id), let source = session.sources.first(where: { $0.id == address.source })
        else { return }
        guard !usedNames.contains(source.slices[address.index].name) else {
            statusText = "\(source.slices[address.index].name) is used by a zone; remove those zones first."
            return
        }
        changeSession { $0.removeSlice(source: address.source, slice: address.index) }
    }

    public func setSliceFades(id: Int, fadeIn: Bool, fadeOut: Bool) {
        guard let address = sliceAddress(id) else { return }
        changeSession {
            $0.setSliceFades(source: address.source, slice: address.index, fadeIn: fadeIn, fadeOut: fadeOut)
        }
    }

    public func setSourceRate(rate: Int) {
        guard let id = activeSource else { return }
        changeSession { (target: KitSourceSession) in
            if !target.setSourceRate(source: id, rate: rate) { statusText = "Unsupported source rate" }
        }
    }

    public func sliceId(row: Int) -> Int {
        guard let source = currentSource, source.slices.indices.contains(row) else { return 0 }
        return draft.sliceIds[KitDraft.SliceKey(source: source.id, identity: source.slices[row].id)] ?? 0
    }

    public func sliceName(id: Int) -> String { sliceValue(id)?.name ?? "" }
    public func sliceStartFrame(id: Int) -> Int { sliceValue(id)?.startFrame ?? 0 }
    public func sliceEndFrame(id: Int) -> Int { sliceValue(id)?.endFrame ?? 0 }
    public func sliceFadeIn(id: Int) -> Bool { sliceValue(id)?.fadeIn ?? false }
    public func sliceFadeOut(id: Int) -> Bool { sliceValue(id)?.fadeOut ?? true }

    public func playSlice(id: Int) { if sliceAddress(id) != nil { playPcm?(id) } }

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
        statusText = ""
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

    private func syncIds() {
        let liveMarkers = Set(
            session.sources.flatMap { (source: KitSourceSession.Source) in
                source.markers.map { KitDraft.MarkerKey(source: source.id, frame: $0) }
            })
        let liveSlices = Set(
            session.sources.flatMap { (source: KitSourceSession.Source) in
                source.slices.map { KitDraft.SliceKey(source: source.id, identity: $0.id) }
            })
        draft.markerIds = draft.markerIds.filter { liveMarkers.contains($0.key) }
        draft.sliceIds = draft.sliceIds.filter { liveSlices.contains($0.key) }
        for source in session.sources {
            for frame in source.markers {
                let key = KitDraft.MarkerKey(source: source.id, frame: frame)
                if draft.markerIds[key] == nil {
                    draft.markerIds[key] = nextId
                    nextId += 1
                }
            }
            for slice in source.slices {
                let key = KitDraft.SliceKey(source: source.id, identity: slice.id)
                if draft.sliceIds[key] == nil {
                    draft.sliceIds[key] = nextId
                    nextId += 1
                }
            }
        }
    }

    /// Re-publishes values after the workflow injects a waveform or value-only facts.
    @QtIgnored public func refresh() {
        mode = activeMode == .drumkit ? 0 : 1
        dirty = draft.dirty || activeMode != cleanMode || session.snapshot() != cleanSessionSnapshot
        canSave = picker.selectedSlot != nil && dirty
        canUndo = draft.canUndo
        canRedo = draft.canRedo
        selectedSlot = picker.selectedSlot ?? -1
        titleText = "Split Studio — \(song) · voice \(boundSlot)" + (dirty ? " •" : "")
        if !zones.indices.contains(selectedZone) { selectedZone = -1 }
        let zoneValues = zones.enumerated().map { (entry: (offset: Int, element: KitZone)) -> KitZoneRow in
            let selected = entry.offset == selectedZone
            if entry.offset < zoneRows.count,
                zoneRows[entry.offset].matches(zone: entry.element, selected: selected, mode: activeMode)
            {
                return zoneRows[entry.offset]
            }
            return KitZoneRow(zone: entry.element, selected: selected, mode: activeMode)
        }
        syncModel(zoneRows, zoneValues, matches: { (lhs: KitZoneRow, rhs: KitZoneRow) -> Bool in lhs === rhs })
        syncModel(
            slotRows, picker.rows(existing: slotRows),
            matches: { (lhs: KitSlotRow, rhs: KitSlotRow) -> Bool in lhs === rhs })
        if !session.sources.contains(where: { $0.id == activeSource }) { activeSource = session.sources.first?.id }
        let names = usedNames
        let sourceValues = session.sources.enumerated().map {
            (entry: (offset: Int, element: KitSourceSession.Source)) -> KitSourceRow in
            let active = entry.element.id == activeSource
            let closable = session.canClose(source: entry.element.id, usedNames: names)
            if entry.offset < sourceRows.count,
                sourceRows[entry.offset].matches(source: entry.element, active: active, closable: closable)
            {
                return sourceRows[entry.offset]
            }
            return KitSourceRow(source: entry.element, active: active, closable: closable)
        }
        syncModel(sourceRows, sourceValues, matches: { (lhs: KitSourceRow, rhs: KitSourceRow) -> Bool in lhs === rhs })
        syncIds()
        sliceCount = currentSource?.slices.count ?? 0
        sourceRate = currentSource.flatMap { Int(exactly: $0.targetRate.rounded()) } ?? 0
        rateChoices =
            currentSource.map { SampleRatePolicy.rateOptions(sourceRate: $0.sample.sampleRate).map(String.init) } ?? []
        if let waveform {
            if displayedWaveform !== waveform {
                waveform.onMarkerDragged = { [weak self] (id: Int, frame: Int) in
                    self?.moveMarker(id: id, toFrame: frame)
                }
            }
            if displayedSource != activeSource || displayedWaveform !== waveform {
                waveform.setSamples(
                    currentSource?.sample.buffer ?? [], sampleRate: currentSource?.sample.sampleRate ?? 1, gain: 1)
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
            } else {
                waveform.setMarkers([])
            }
        }
        slicesRevision += 1
        stateRevision += 1
    }
}
