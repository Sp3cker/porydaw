import Foundation
import PorydawAppAudio
import PorydawAppPresentation
import PorydawDocument
import PorydawKitStudio
import PorydawProject
import PorydawSample
import PorydawSampleUI
import PorydawVoicegroup
import QtBridge

/// Owns the modeless window, project effects and generation-guarded Save to Song.
@MainActor
@QtBridgeable
public final class KitStudioWorkflow: QmlUncreatable {
    public var windowOpen: Bool = false
    public var presenterRevision: Int = 0
    public var saving: Bool = false
    public var promptOpen: Bool = false
    public var promptForVoicegroup: Bool = false
    public var promptForClose: Bool = false
    public var orphanCleanupOpen: Bool = false
    public var orphanCleanupNames: [String] = []
    public var orphanCleanupSelectedNames: [String] = []
    public var orphanCleanupBusy: Bool = false
    public var orphanCleanupStatus: String = ""
    public var switchingVoicegroup: Bool = false
    public var switchBarText: String = ""
    public var switchBackText: String = ""
    public var alertText: String = ""
    public var alertRevision: Int = 0
    public var pickerRequested: Bool = false
    public var pickerFolder: String = ""
    public var copySharedKit: Bool = true
    public var auditionPlaying: Bool = false
    public var hasSavedWindowSize: Bool = false
    public var savedWindowWidth: Double = 0
    public var savedWindowHeight: Double = 0
    public var savedLibraryWidth: Double = 0
    public var savedSliceHeight: Double = 0
    @QtIgnored public let closeGuard = KitStudioCloseGuard()
    public private(set) weak var boundSong: DocumentSession?
    private weak var session: ApplicationSession?
    private var state: KitStudioPresenter?
    private var libraryPane: SampleLibraryModel?
    private var pcm: PcmAuditionPlayer?
    private var sessionGeneration = 0
    private var pendingTask: Task<Void, Never>?
    private var observerTask: Task<Void, Never>?
    private var closeWaitTask: Task<Void, Never>?
    private var orphanCleanupTask: Task<Void, Never>?
    private var orphanCleanupCompletion: (() -> Void)?
    private var switchBackTask: Task<Void, Never>?
    private var previousVoicegroupArg: String?
    private var followedSlot: Int = -1
    private var cleanSourceSnapshot: KitSourceSession.Snapshot?
    private var snapshots: [Int: KitEditValue] = [:]
    private var observedRevision: UInt64 = 0
    private var deferredBankRevision: UInt64?
    private var switchFailureText: String?
    private var ownSave: (generation: Int, after: KitEditValue)?
    private var savedWavs: [String: Data] = [:]
    private struct SliceRenderKey: Equatable {
        let source: Int
        let rate: Double
        let slice: KitSourceSession.Slice
    }
    private var savedRenderKeys: [String: SliceRenderKey] = [:]
    private var selectedMarker: Int?
    private var pendingNames: Set<String> = []
    private var playingSlice: Int?
    private var tickTime: TimeInterval?

    @QtIgnored public init(session: ApplicationSession) {
        self.session = session
        closeGuard.onChanged = { [weak self] in self?.promptOpen = self?.closeGuard.promptOpen ?? false }
        closeGuard.onSave = { [weak self] in self?.saveToSong() }
    }

    public func presenter() -> Optional<KitStudioPresenter> { state }

    public func library() -> Optional<SampleLibraryModel> {
        if let libraryPane { return libraryPane }
        guard let session else { return nil }
        let library = SampleLibraryModel(preferences: session.preferences)
        library.onLoadRequested = { [weak self] (path: String) in self?.loadSource(path: path) }
        library.onOpenFileRequested = { [weak self] in self?.requestOpenFile() }
        library.onPreviewRequested = { [weak self] (path: String) in self?.previewLibrary(path: path) }
        library.onPreviewStopRequested = { [weak self] in self?.stopAudition() }
        libraryPane = library
        return library
    }

    public func requestOpen() {
        guard let session, session.projectOpen, let song = session.selectedDocument,
            !saving, !switchingVoicegroup
        else { return }
        if windowOpen, boundSong === song {
            presenterRevision += 1
            return
        }
        closeGuard.request(source: .retarget, dirty: state?.dirty ?? false) { [weak self, weak song] in
            guard let self, let song else { return }
            self.open(song: song)
        }
    }

    private func open(song: DocumentSession) {
        guard let session, let service = session.catalogService else { return }
        sessionGeneration += 1
        let generation = sessionGeneration
        pendingTask?.cancel()
        observerTask?.cancel()
        saving = false
        alertText = ""
        stopAudition()
        pendingTask = Task { [weak self, weak song] in
            guard let song else { return }
            do {
                let lease = song.bankLease
                let values = try await Self.readKits(lease: lease, service: service)
                guard !Task.isCancelled else { return }
                let assets = try await Self.readAssets(values: values, lease: lease, service: service)
                guard let self, !Task.isCancelled, self.sessionGeneration == generation,
                    self.session?.catalogService === service, !song.isClosed,
                    song.bankLease.publicationRevision == lease.publicationRevision
                else { return }
                let presenter = self.state ?? KitStudioPresenter()
                presenter.session.restore(KitSourceSession().snapshot())
                presenter.samples = assets.samples
                presenter.progWaves = assets.waves
                self.state = presenter
                self.boundSong = song
                self.snapshots = values
                self.observedRevision = lease.publicationRevision
                self.savedWavs.removeAll()
                self.savedRenderKeys.removeAll()
                self.selectedMarker = nil
                self.copySharedKit = true
                presenter.waveform = MarkerWaveformModel(palette: session.palette)
                presenter.waveform?.setBaseFontPx(value: Double(session.baseFontPx))
                presenter.waveform?.onMarkerPressed = { [weak self] (id: Int) in self?.selectedMarker = id }
                self.wire(presenter)
                let selected = session.voiceList.currentSlot
                let slot = values[selected] != nil ? selected : values.keys.sorted().first ?? -1
                self.followedSlot = slot
                self.previousVoicegroupArg = nil
                self.switchBarText = ""
                self.switchBackText = ""
                self.cleanSourceSnapshot = presenter.session.snapshot()
                presenter.bind(
                    song: song.document.source.label,
                    section: try KitUsageScanner.canonicalSection(
                        projectRoot: session.projectRoot, sourceRelativePath: lease.id.sourceRelativePath,
                        sectionLabel: lease.sectionLabel),
                    voices: lease.slotViews.map(\.voice),
                    undefinedSlots: Self.undefinedSlots(lease), slot: slot)
                self.restoreGeometry()
                self.pcm = PcmAuditionPlayer(lane: SampleAuditionArbiter(output: session.audio))
                self.pcm?.onPlayhead = { [weak self] (frame: Int?) in
                    guard let self, let id = self.playingSlice else { return }
                    let sourceFrame = frame.flatMap { _ in
                        self.state?.sourceFrame(sliceId: id, renderedPosition: self.pcm?.playheadPosition ?? 0)
                    }
                    self.state?.waveform?.setPlayhead(frame: sourceFrame)
                    self.auditionPlaying = self.pcm?.playing ?? false
                }
                self.windowOpen = true
                self.presenterRevision += 1
                self.pendingTask = nil
            } catch {
                guard let self, self.sessionGeneration == generation else { return }
                self.pendingTask = nil
                self.showAlert(error)
            }
        }
    }

    private func wire(_ presenter: KitStudioPresenter) {
        presenter.onSaveRequested = { [weak self] in self?.saveToSong() }
        presenter.validateName = { [weak self] (name: String) -> String? in self?.validateName(name) }
        presenter.onLoadKit = { [weak self] (slot: Int) -> KitLoadResult? in self?.loadResult(slot: slot) }
        presenter.usageScan = { [weak self] (subgroup: String, table: String?, section: String) -> [String] in
            guard let root = self?.session?.projectRoot else { return [] }
            return KitUsageScanner.usage(
                projectRoot: root, subgroupSymbol: subgroup, tableName: table, excludingSection: section)
        }
        presenter.onRetargetPrompt = { [weak self] (answer: Int) in
            if answer == 0 { self?.saveToSong() }
            if answer == 1 { self?.cleanSourceSnapshot = self?.state?.session.snapshot() }
        }
        presenter.onConflictAnswer = { [weak self] (keepMine: Bool) in self?.resolveConflict(keepMine: keepMine) }
        presenter.onSwitchBack = { [weak self] in self?.switchBack() }
        presenter.publishKitTone = { [weak self] (tone: KitAuditionTone, key: UInt8) -> Bool in
            guard let self else { return false }
            self.stopAudition()
            return self.session?.audio?.auditionKit(tone, key: key) ?? false
        }
        presenter.playPcm = { [weak self] (id: Int) in self?.playSlice(id: id) }
    }

    private static func readKits(
        lease: ProjectBankLease, service: ProjectService, selectedSlot: Int? = nil
    ) async throws -> [Int: KitEditValue] {
        let seedSlot: Int?
        if let selectedSlot, (0..<128).contains(selectedSlot) {
            seedSlot = selectedSlot
        } else {
            seedSlot = (0..<128).first { (slot: Int) -> Bool in
                let view = lease.slotViews[slot]
                return view.kind == .none || view.voice?.macro == .keysplitAll || view.voice?.macro == .keysplit
            }
        }
        guard let seedSlot else { return [:] }
        // The reader owns the -G identity, which is not the lease's display name.
        let seed = try await service.readKit(lease: lease, slot: seedSlot)
        var values: [Int: KitEditValue] = [:]
        values.reserveCapacity(128)
        values[seedSlot] = seed
        for slot in 0..<128 where slot != seedSlot {
            if Task.isCancelled { return values }
            let view = lease.slotViews[slot]
            if view.kind == .none {
                values[slot] = KitEditValue(
                    voicegroup: seed.voicegroup, slot: slot, parent: nil, subgroupSymbol: "",
                    children: [], tableName: nil, table: nil)
            } else if view.voice?.macro == .keysplitAll || view.voice?.macro == .keysplit {
                values[slot] = try await service.readKit(lease: lease, slot: slot)
            }
        }
        return values
    }

    private func loadResult(slot: Int) -> KitLoadResult? {
        guard let value = snapshots[slot] else { return nil }
        do {
            let parent = try value.parent.map(Self.projectVoice)
            let kind: KitSlotKind =
                parent?.macro == .keysplitAll ? .drumkit : parent?.macro == .keysplit ? .keysplit : .empty
            let table: KeysplitTable? =
                if let name = value.tableName, let bytes = value.table {
                    KeysplitTable(name: name, startingNote: 0, maxNote: 128, table: bytes)
                } else { nil }
            return KitLoadResult(
                kind: kind, parent: parent, children: try value.children.map { try $0.map(Self.projectVoice) },
                table: table)
        } catch {
            showAlert(error)
            return nil
        }
    }

    private func validateName(_ name: String) -> String? {
        guard let session else { return "Project is closed." }
        let names = (state?.session.sources ?? []).flatMap { $0.slices.map(\.name) }
        var symbols = Set(VoicegroupSource.directSoundSymbols(session.projectRoot))
        symbols.formUnion((pendingNames.union(names)).map { "DirectSoundWaveData_" + $0 })
        return SampleRegistrar.validate(projectRoot: session.projectRoot, name: name, existingSymbols: Array(symbols))
    }

    public func requestOpenFile() {
        guard windowOpen, !saving, let session else { return }
        let directory = session.preferences.string(key: "lastSampleDir", fallback: NSHomeDirectory())
        pickerFolder = URL(filePath: directory).absoluteString
        pickerRequested = true
    }
    public func cancelSource() { pickerRequested = false }
    public func chooseSource(fileURL: String) {
        pickerRequested = false
        loadSource(path: fileURL)
    }

    public func loadSource(path: String) {
        guard windowOpen, !saving, let state else { return }
        stopAudition()
        do {
            let url = Self.sourceURL(path)
            let sample = try SampleImport.decodeFile(path: url.path)
            state.addSource(sample)
            libraryPane?.setLoadedPath(path: url.path)
            session?.preferences.setString(key: "lastSampleDir", value: url.deletingLastPathComponent().path)
        } catch { showAlert(error) }
    }

    public func dropLibrarySample(path: String, onKey: Int) {
        guard windowOpen, !saving, let state, let session else { return }
        let url = Self.sourceURL(path)
        let name = url.deletingPathExtension().lastPathComponent
        let symbol = "DirectSoundWaveData_" + name
        if url.deletingLastPathComponent().path == session.projectRoot + "/sound/direct_sound_samples",
            VoicegroupSource.directSoundSymbols(session.projectRoot).contains(symbol)
        {
            if state.samples[symbol] != nil {
                state.dropSample(name: symbol, onKey: onKey)
                return
            }
            guard let service = session.catalogService, let song = boundSong else { return }
            let generation = sessionGeneration
            let slot = state.selectedSlot
            let mode = state.mode
            Task { [weak self] in
                do {
                    let asset = try await service.sampleAsset(lease: song.bankLease, symbol: symbol)
                    guard let self, self.windowOpen, self.sessionGeneration == generation,
                        self.boundSong === song, self.session?.catalogService === service,
                        state.selectedSlot == slot, state.mode == mode
                    else { return }
                    if let asset { state.samples[symbol] = Self.processed(asset) }
                    state.dropSample(name: symbol, onKey: onKey)
                } catch {
                    guard let self, self.sessionGeneration == generation else { return }
                    self.showAlert(error)
                }
            }
            return
        }
        stopAudition()
        do {
            let sample = try SampleImport.decodeFile(path: url.path)
            state.addSource(sample)
            state.selectionStartFrame = 0
            state.selectionEndFrame = sample.frameCount
            state.sliceSelection()
            let id = state.sliceId(row: 0)
            state.dropSample(name: state.sliceName(id: id), onKey: onKey)
        } catch { showAlert(error) }
    }

    private func previewLibrary(path: String) {
        guard windowOpen, !saving else { return }
        do {
            let url = Self.sourceURL(path)
            let sample = try SampleImport.decodeFile(path: url.path)
            let rendered = SampleRender.render(source: sample, params: SampleDocument.defaultParams(for: sample))
            playingSlice = nil
            pcm?.play(owner: self, rendered: rendered, looped: rendered.looped, key: 60, adsr: AudioADSR(), toneKey: 60)
            auditionPlaying = pcm?.playing ?? false
            tickTime = Date.timeIntervalSinceReferenceDate
            libraryPane?.setPreviewingPath(path: url.path)
        } catch { libraryPane?.showMessage(text: String(describing: error)) }
    }

    public func frameAt(x: Double) -> Int { state?.waveform?.frameAt(x) ?? 0 }
    public func removeSelectedMarker() {
        guard let id = selectedMarker else { return }
        state?.removeMarker(id: id)
        selectedMarker = nil
    }
    public func selectSource(row: Int) {
        stopAudition()
        selectedMarker = nil
        state?.selectSource(row: row)
    }
    public func closeSource(row: Int) {
        stopAudition()
        selectedMarker = nil
        state?.closeSource(row: row)
    }
    public func setSourceRate(rate: Int) {
        stopAudition()
        state?.setSourceRate(rate: rate)
    }
    public func sourceRateIndex(rate: Double) -> Int {
        state?.rateChoices.firstIndex(where: { (text: String) -> Bool in Double(text) == rate }) ?? -1
    }
    public func chooseSourceRate(index: Int) {
        guard let state, state.rateChoices.indices.contains(index), let rate = Int(state.rateChoices[index]) else {
            return
        }
        setSourceRate(rate: rate)
    }
    public func undo() {
        stopAudition()
        selectedMarker = nil
        state?.undo()
    }
    public func redo() {
        stopAudition()
        selectedMarker = nil
        state?.redo()
    }
    public func removeSlice(id: Int) {
        if playingSlice == id { stopAudition() }
        state?.removeSlice(id: id)
    }
    private func playSlice(id: Int) {
        guard let rendered = state?.renderedSlice(id: id) else { return }
        stopAudition()
        playingSlice = id
        pcm?.play(owner: self, rendered: rendered, looped: rendered.looped, key: 60, adsr: AudioADSR(), toneKey: 60)
        auditionPlaying = pcm?.playing ?? false
        tickTime = Date.timeIntervalSinceReferenceDate
    }
    public func tickAudition() {
        let now = Date.timeIntervalSinceReferenceDate
        if let previous = tickTime { pcm?.advance(bySeconds: max(0, now - previous)) }
        tickTime = now
        auditionPlaying = pcm?.playing ?? false
    }
    public func stopAudition() {
        pcm?.stop(owner: self)
        session?.audio?.auditionSampleOff()
        state?.waveform?.setPlayhead(frame: nil)
        playingSlice = nil
        tickTime = nil
        auditionPlaying = false
        libraryPane?.setPreviewingPath(path: "")
    }

    public func saveToSong() {
        if saving { return }
        guard let session, let service = session.catalogService, let song = boundSong,
            !song.isClosed, let state, state.canSave, !state.conflictVisible,
            let expected = snapshots[state.selectedSlot]
        else {
            closeGuard.saveSettled(success: false)
            return
        }
        saving = true
        alertText = ""
        stopAudition()
        let generation = sessionGeneration
        let root = session.projectRoot
        let slot = state.selectedSlot
        let mode: KitMode = state.mode == 0 ? .drumkit : .keysplit
        let zones = mode == .drumkit ? state.draft.drumkitZones : state.draft.keysplitZones
        var rendered: [(name: String, wav: Data)] = []
        var renderKeys: [String: SliceRenderKey] = [:]
        for source in state.session.sources {
            for (index, slice) in source.slices.enumerated() {
                let key = SliceRenderKey(source: source.id, rate: source.targetRate, slice: slice)
                renderKeys[slice.name] = key
                let wav: Data
                if savedRenderKeys[slice.name] == key, let saved = savedWavs[slice.name] {
                    wav = saved
                } else {
                    wav = SampleWavWriter.bytes(for: state.session.renderSlice(source: source.id, slice: index))
                }
                rendered.append((slice.name, wav))
            }
        }
        pendingNames = Set(rendered.map(\.name))
        pendingTask = Task { [weak self] in
            guard let self else { return }
            var saveSucceeded = false
            defer {
                if self.sessionGeneration == generation {
                    self.pendingTask = nil
                    self.saving = false
                    self.pendingNames.removeAll()
                    self.closeGuard.saveSettled(success: saveSucceeded)
                }
            }
            do {
                guard !Task.isCancelled, self.sessionGeneration == generation, self.session?.catalogService === service
                else { return }
                let before = expected
                let new = rendered.filter { self.savedWavs[$0.name] == nil }
                let absentBefore = new.filter {
                    !ProjectFileStore.exists(root + "/sound/direct_sound_samples/" + $0.name + ".wav")
                }
                do { try SampleRegistrar.registerBatch(projectRoot: root, samples: new) } catch {
                    for sample in absentBefore
                    where ProjectFileStore.exists(root + "/sound/direct_sound_samples/" + sample.name + ".wav") {
                        session.recordCreatedSample(name: sample.name)
                    }
                    throw error
                }
                for sample in new {
                    session.recordCreatedSample(name: sample.name)
                    self.savedWavs[sample.name] = sample.wav
                }
                for sample in rendered where self.savedWavs[sample.name] != sample.wav {
                    // Like registrations, slice audio is a disk asset: kit undo restores
                    // references, not earlier audio. The service owns cache invalidation.
                    state.samples.removeValue(forKey: "DirectSoundWaveData_" + sample.name)
                    try await service.commitSample(
                        SampleCommitRequest(name: sample.name, wav: sample.wav, update: true))
                    guard !Task.isCancelled, self.sessionGeneration == generation,
                        self.session?.catalogService === service
                    else { return }
                    self.savedWavs[sample.name] = sample.wav
                }
                var symbol = before.subgroupSymbol
                let create = symbol.isEmpty || (!state.usedByText.isEmpty && self.copySharedKit)
                if create {
                    let base = before.voicegroup.trimmingCharacters(in: CharacterSet(charactersIn: "_")) + "_kit\(slot)"
                    var name = base
                    var suffix = 1
                    let locator = VoicegroupLocator(layout: ProjectLayout(projectRoot: root).ensuringDeepScan())
                    while ProjectFileStore.exists(root + "/sound/voicegroups/" + name + ".inc")
                        || locator.locateSubgroup(symbol: Array(("voicegroup_" + name).utf8)[...]) != nil
                    {
                        name = base + "_\(suffix)"
                        suffix += 1
                    }
                    // New subgroup files/includes are structural assets written now.
                    // The parent, edited children and table stay staged until normal song save.
                    try VoicegroupSource.createVoicegroup(
                        projectRoot: root, name: name, copyFromFile: "", copySectionLabel: "")
                    session.recordCreatedSubgroup(symbol: "voicegroup_" + name)
                    try VoicegroupSource.appendIncludeLine(projectRoot: root, name: name)
                    symbol = "voicegroup_" + name
                }
                var children = KitDraftCodec.children(from: zones, mode: mode)
                let sliceNames = Set(rendered.map(\.name))
                for index in children.indices {
                    if let name = children[index]?.symbol, sliceNames.contains(name) {
                        children[index]?.symbol = "DirectSoundWaveData_" + name
                    }
                }
                let stem = symbol.hasPrefix("voicegroup_") ? String(symbol.dropFirst("voicegroup_".count)) : symbol
                let tableName =
                    mode == .keysplit ? (!create ? before.tableName ?? "keysplit_" + stem : "keysplit_" + stem) : nil
                let table = tableName.map { KitDraftCodec.table(from: zones, name: $0) }
                let parent = VgVoice(
                    macro: mode == .drumkit ? .keysplitAll : .keysplit, symbol: symbol, keysplitTable: tableName ?? "")
                let after = KitEditValue(
                    voicegroup: before.voicegroup, slot: slot, parent: Self.bankVoice(parent), subgroupSymbol: symbol,
                    children: children.map { $0.map(Self.bankVoice) }, tableName: tableName, table: table?.table)
                self.ownSave = (generation, after)
                do { _ = try await song.applyKitEdit(after, expected: before) } catch {
                    self.ownSave = nil
                    throw error
                }
                guard !Task.isCancelled, self.sessionGeneration == generation, self.session?.catalogService === service
                else { return }
                self.savedRenderKeys.merge(renderKeys) { _, current in current }
                self.snapshots[slot] = try await service.readKit(lease: song.bankLease, slot: slot)
                guard !Task.isCancelled, self.sessionGeneration == generation else { return }
                _ = await session.refreshVoicegroupCatalog()
                guard !Task.isCancelled, self.sessionGeneration == generation, self.session?.catalogService === service
                else { return }
                if create { state.usedByText = "" }
                state.markClean()
                self.cleanSourceSnapshot = state.session.snapshot()
                if state.retargetVisible { state.completeRetarget() }
                self.savedWavs = self.savedWavs.filter { renderKeys[$0.key] != nil }
                self.savedRenderKeys = renderKeys
                saveSucceeded = true
            } catch {
                guard self.sessionGeneration == generation else { return }
                self.ownSave = nil
                self.showAlert(error)
            }
        }
    }

    /// Called by the existing workspace publication callback; non-bank publications are cheap no-ops.
    @QtIgnored public func bankDidChange(song: DocumentSession) {
        guard windowOpen, boundSong === song, let state, let session, let service = session.catalogService else {
            return
        }
        if switchingVoicegroup {
            deferredBankRevision = song.bankLease.publicationRevision
            return
        }
        guard observedRevision != song.bankLease.publicationRevision else { return }
        let lease = song.bankLease
        let generation = sessionGeneration
        let slot = state.selectedSlot
        let undefined = Self.undefinedSlots(lease)
        observerTask?.cancel()
        observerTask = Task { [weak self] in
            do {
                let values = try await Self.readKits(lease: lease, service: service, selectedSlot: slot)
                guard !Task.isCancelled else { return }
                let assets = try await Self.readAssets(
                    values: values, lease: lease, service: service,
                    samples: state.samples, waves: state.progWaves)
                guard let self, !Task.isCancelled, self.sessionGeneration == generation,
                    self.boundSong === song, song.bankLease.publicationRevision == lease.publicationRevision
                else { return }
                self.observedRevision = lease.publicationRevision
                defer {
                    if let failure = self.switchFailureText {
                        state.statusText = failure
                        self.switchFailureText = nil
                    }
                }
                let old = self.snapshots[slot]
                self.snapshots = values
                state.samples = assets.samples
                state.progWaves = assets.waves
                state.refreshSlots(voices: lease.slotViews.map(\.voice), undefinedSlots: undefined)
                guard let value = values[slot] else { return }
                if state.selectedSlot != slot { return }
                if let tag = self.ownSave, tag.generation == generation, Self.matches(value, after: tag.after) {
                    self.ownSave = nil
                    return
                }
                guard value != old else { return }
                state.songKitChanged()
            } catch {
                guard let self, !Task.isCancelled, self.sessionGeneration == generation else { return }
                self.showAlert(error)
            }
        }
    }

    private static func matches(_ value: KitEditValue, after: KitEditValue) -> Bool {
        if value == after { return true }
        guard value.voicegroup == after.voicegroup, value.slot == after.slot, value.parent == after.parent,
            value.subgroupSymbol == after.subgroupSymbol, value.tableName == after.tableName, value.table == after.table
        else { return false }
        let blank = bankVoice(kitBlankChildVoice)
        return (0..<128).allSatisfy { (index: Int) -> Bool in
            let left = index < value.children.count ? value.children[index] ?? blank : blank
            let right = index < after.children.count ? after.children[index] ?? blank : blank
            return left == right
        }
    }

    private static func undefinedSlots(_ lease: ProjectBankLease) -> Set<Int> {
        Set(lease.slotViews.indices.filter { lease.slotViews[$0].kind == .none })
    }

    private func resolveConflict(keepMine: Bool) {
        guard !saving, let song = boundSong, let service = session?.catalogService, let state else { return }
        let generation = sessionGeneration
        let slot = state.selectedSlot
        saving = true
        pendingTask = Task { [weak self] in
            do {
                let value = try await service.readKit(lease: song.bankLease, slot: slot)
                guard let self, !Task.isCancelled, self.sessionGeneration == generation,
                    self.session?.catalogService === service
                else { return }
                self.snapshots[slot] = value
                if !keepMine, let result = self.loadResult(slot: slot) {
                    state.install(result, slot: slot)
                    self.cleanSourceSnapshot = state.session.snapshot()
                }
                self.saving = false
                self.pendingTask = nil
            } catch {
                guard let self, !Task.isCancelled, self.sessionGeneration == generation else { return }
                self.saving = false
                self.pendingTask = nil
                state.songKitChanged()
                self.showAlert(error)
            }
        }
    }

    private static func readAssets(
        values: [Int: KitEditValue], lease: ProjectBankLease, service: ProjectService,
        samples initialSamples: [String: ProcessedSample] = [:], waves initialWaves: [String: [UInt32]] = [:]
    ) async throws -> (samples: [String: ProcessedSample], waves: [String: [UInt32]]) {
        var samples = initialSamples
        var waves = initialWaves
        for value in values.values {
            for optional in value.children {
                guard let voice = optional, !voice.symbol.isEmpty else { continue }
                if voice.macro == VgMacro.progWave.rawValue || voice.macro == VgMacro.progWaveAlt.rawValue {
                    if waves[voice.symbol] == nil {
                        waves[voice.symbol] = try await service.progWaveWords(lease: lease, symbol: voice.symbol)
                    }
                } else if voice.macro <= VgMacro.directSoundAlt.rawValue, samples[voice.symbol] == nil,
                    let asset = try await service.sampleAsset(lease: lease, symbol: voice.symbol)
                {
                    samples[voice.symbol] = processed(asset)
                }
            }
        }
        return (samples, waves)
    }

    private static func processed(_ asset: KitSampleAsset) -> ProcessedSample {
        var sample = ProcessedSample()
        sample.s8 = asset.pcm
        sample.freq = asset.frequency
        sample.size = UInt32(asset.pcm.count)
        sample.looped = asset.looped
        sample.loopStart = UInt32(asset.loopStart)
        sample.outputRate = Double(asset.frequency) / 1024
        sample.effectiveRate = sample.outputRate
        return sample
    }

    /// The dropdown owns the dirty decision; this reuses the window's one close guard.
    @QtIgnored public func guardVoicegroupSwitch(proceed: @escaping () -> Void, cancel: @escaping () -> Void) {
        guard !promptOpen, !closeGuard.saving else {
            cancel()
            return
        }
        promptForVoicegroup = true
        closeGuard.request(
            source: .retarget, dirty: state?.dirty ?? true,
            proceed: { [weak self] in
                guard let self else { return }
                self.promptForVoicegroup = false
                if let state = self.state, state.dirty {
                    self.stopAudition()
                    if let clean = self.cleanSourceSnapshot { state.session.restore(clean) }
                    if let result = self.loadResult(slot: state.selectedSlot) {
                        state.install(result, slot: state.selectedSlot)
                    }
                }
                proceed()
            },
            cancel: { [weak self] in
                self?.promptForVoicegroup = false
                cancel()
            })
    }

    /// Selects directly, then follows the same slot through the newly bound lease.
    @QtIgnored public func selectVoicegroup(song: DocumentSession, arg: String) async throws {
        guard windowOpen, boundSong === song, let state, let session, let service = session.catalogService else {
            try await song.selectVoicegroup(arg)
            return
        }
        guard !saving, !switchingVoicegroup else {
            throw ProjectServiceError.operationFailed(
                "Split Studio: a voicegroup switch or save is already in progress.")
        }
        let previousArg = song.document.state.config.voicegroupArgument
        guard arg != previousArg else { return }
        let generation = sessionGeneration
        let slot = state.selectedSlot >= 0 ? state.selectedSlot : followedSlot
        switchingVoicegroup = true
        switchFailureText = nil
        stopAudition()
        observerTask?.cancel()
        defer {
            if sessionGeneration == generation {
                switchingVoicegroup = false
                let latestRevision = deferredBankRevision ?? song.bankLease.publicationRevision
                deferredBankRevision = nil
                if latestRevision != observedRevision || song.bankLease.publicationRevision != observedRevision {
                    bankDidChange(song: song)
                } else {
                    switchFailureText = nil
                }
            }
        }
        do {
            let oldLease = song.bankLease
            try await song.selectVoicegroup(arg)
            guard !Task.isCancelled, windowOpen, sessionGeneration == generation,
                boundSong === song, session.catalogService === service, !song.isClosed,
                song.bankLease.id != oldLease.id || song.bankLease.publicationRevision != oldLease.publicationRevision
            else {
                throw ProjectServiceError.operationFailed(
                    "Split Studio: the song changed during the voicegroup switch.")
            }
            let lease = song.bankLease
            let section = try KitUsageScanner.canonicalSection(
                projectRoot: session.projectRoot, sourceRelativePath: lease.id.sourceRelativePath,
                sectionLabel: lease.sectionLabel)
            let values = try await Self.readKits(lease: lease, service: service, selectedSlot: slot)
            let assets = try await Self.readAssets(values: values, lease: lease, service: service)
            guard !Task.isCancelled, windowOpen, sessionGeneration == generation,
                boundSong === song, session.catalogService === service, !song.isClosed,
                song.bankLease.id == lease.id, song.bankLease.publicationOwner == lease.publicationOwner,
                song.bankLease.publicationRevision == lease.publicationRevision
            else {
                throw ProjectServiceError.operationFailed(
                    "Split Studio: the song changed during the voicegroup switch.")
            }
            followedSlot = slot
            ownSave = nil
            savedWavs.removeAll()
            savedRenderKeys.removeAll()
            selectedMarker = nil
            copySharedKit = true
            state.session.restore(KitSourceSession().snapshot())
            cleanSourceSnapshot = state.session.snapshot()
            snapshots = values
            observedRevision = lease.publicationRevision
            state.samples = assets.samples
            state.progWaves = assets.waves
            state.bind(
                song: song.document.source.label, section: section,
                voices: lease.slotViews.map(\.voice), undefinedSlots: Self.undefinedSlots(lease), slot: slot)
            previousVoicegroupArg = previousArg
            switchBarText = "Voicegroup changed to \(VoiceListSemantics.voicegroupDisplayName(arg))"
            switchBackText = "Switch back to \(VoiceListSemantics.voicegroupDisplayName(previousArg))"
            state.switchBarVisible = true
            presenterRevision += 1
        } catch {
            guard sessionGeneration == generation, boundSong === song else { throw error }
            state.switchBarVisible = previousVoicegroupArg != nil
            state.statusText = String(describing: error)
            switchFailureText = state.statusText
            throw error
        }
    }

    private func switchBack() {
        guard let song = boundSong, let arg = previousVoicegroupArg else { return }
        switchBackTask = Task { [weak self, weak song] in
            guard let self, let song else { return }
            defer { self.switchBackTask = nil }
            do {
                try await self.selectVoicegroup(song: song, arg: arg)
            } catch {
                self.state?.statusText = String(describing: error)
            }
            if self.session?.selectedDocument === song {
                self.session?.voiceList.refresh(from: song)
            }
        }
    }

    @QtIgnored
    func guardClose(
        source: KitStudioCloseGuard.Source, song: DocumentSession? = nil,
        proceed: @escaping () -> Void, cancel: @escaping () -> Void
    ) {
        guard !orphanCleanupBusy, !orphanCleanupOpen, closeWaitTask == nil, !switchingVoicegroup else {
            cancel()
            return
        }
        guard windowOpen, song == nil || boundSong === song else {
            proceed()
            return
        }
        if saving {
            let task = pendingTask
            closeWaitTask = Task { [weak self] in
                await task?.value
                guard let self else { return }
                self.closeWaitTask = nil
                self.guardClose(source: source, song: song, proceed: proceed, cancel: cancel)
            }
            return
        }
        guard !promptOpen, !closeGuard.saving else {
            cancel()
            return
        }
        promptForClose = true
        closeGuard.request(
            source: source, dirty: state?.dirty ?? false,
            proceed: { [weak self] in
                self?.promptForClose = false
                self?.close()
                proceed()
            },
            cancel: { [weak self] in
                self?.promptForClose = false
                cancel()
            })
    }

    @QtIgnored
    func offerOrphanCleanup(proceed: @escaping () -> Void, cancel: @escaping () -> Void) {
        guard let session, orphanCleanupCompletion == nil, !orphanCleanupBusy else {
            cancel()
            return
        }
        orphanCleanupBusy = true
        orphanCleanupStatus = ""
        orphanCleanupCompletion = proceed
        orphanCleanupTask = Task { [weak self] in
            do {
                let names = try await session.orphanSplitStudioSamples()
                guard let self else { return }
                self.orphanCleanupTask = nil
                self.orphanCleanupBusy = false
                if names.isEmpty {
                    self.finishOrphanCleanup()
                } else {
                    self.orphanCleanupNames = names
                    self.orphanCleanupSelectedNames = names
                    self.orphanCleanupOpen = true
                }
            } catch {
                guard let self else { return }
                self.orphanCleanupTask = nil
                self.orphanCleanupBusy = false
                self.orphanCleanupCompletion = nil
                session.publishOperationFailure(message: String(describing: error))
                cancel()
            }
        }
    }

    public func setOrphanCleanupSelected(name: String, selected: Bool) {
        guard orphanCleanupOpen, !orphanCleanupBusy, orphanCleanupNames.contains(name) else { return }
        if selected {
            if !orphanCleanupSelectedNames.contains(name) { orphanCleanupSelectedNames.append(name) }
        } else {
            orphanCleanupSelectedNames.removeAll { $0 == name }
        }
    }

    public func answerOrphanCleanup(delete: Bool) {
        guard orphanCleanupOpen, !orphanCleanupBusy, let session else { return }
        guard delete else {
            finishOrphanCleanup()
            return
        }
        let selected = orphanCleanupSelectedNames
        orphanCleanupBusy = true
        orphanCleanupStatus = ""
        orphanCleanupTask = Task { [weak self] in
            do {
                try await session.deleteOrphanSamples(selected)
                guard let self else { return }
                self.orphanCleanupTask = nil
                self.orphanCleanupBusy = false
                if self.orphanCleanupStatus.isEmpty {
                    self.finishOrphanCleanup()
                } else {
                    self.orphanCleanupNames = []
                    self.orphanCleanupSelectedNames = []
                }
            } catch {
                guard let self else { return }
                self.orphanCleanupTask = nil
                self.orphanCleanupBusy = false
                self.orphanCleanupStatus = String(describing: error)
            }
        }
    }

    private func finishOrphanCleanup() {
        let completion = orphanCleanupCompletion
        orphanCleanupCompletion = nil
        orphanCleanupOpen = false
        orphanCleanupNames = []
        orphanCleanupSelectedNames = []
        completion?()
    }

    public func closeRequested() {
        guard !saving, !switchingVoicegroup else { return }
        closeGuard.request(source: .window, dirty: state?.dirty ?? false) { [weak self] in self?.close() }
    }
    public func answerPrompt(answer: Int) { closeGuard.answer(answer) }
    @QtIgnored public func close() {
        stopAudition()
        windowOpen = false
        pickerRequested = false
    }
    public func windowReleased() {
        guard !windowOpen else { return }
        sessionGeneration += 1
        pendingTask?.cancel()
        observerTask?.cancel()
        pendingTask = nil
        observerTask = nil
        switchBackTask?.cancel()
        switchBackTask = nil
        switchingVoicegroup = false
        deferredBankRevision = nil
        switchFailureText = nil
        promptForVoicegroup = false
        promptForClose = false
        previousVoicegroupArg = nil
        followedSlot = -1
        cleanSourceSnapshot = nil
        switchBarText = ""
        switchBackText = ""
        saving = false
        pcm?.close()
        pcm = nil
        state = nil
        boundSong = nil
        snapshots.removeAll()
        ownSave = nil
    }
    @QtIgnored public func dispose() {
        closeWaitTask?.cancel()
        closeWaitTask = nil
        orphanCleanupTask?.cancel()
        orphanCleanupTask = nil
        orphanCleanupCompletion = nil
        orphanCleanupOpen = false
        orphanCleanupBusy = false
        closeGuard.reset()
        close()
        windowReleased()
    }

    private func restoreGeometry() {
        let size = session?.preferences.string(key: "splitStudioWindowSize", fallback: "") ?? ""
        let parts = size.split(separator: "x", omittingEmptySubsequences: false)
        if parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]),
            width.isFinite, height.isFinite
        {
            hasSavedWindowSize = true
            savedWindowWidth = width
            savedWindowHeight = height
        } else {
            hasSavedWindowSize = false
            savedWindowWidth = 0
            savedWindowHeight = 0
        }
        let splits = session?.preferences.strings("splitStudioSplitters") ?? []
        let library = splits.count == 2 ? Double(splits[0]) : nil
        let slices = splits.count == 2 ? Double(splits[1]) : nil
        savedLibraryWidth =
            library.flatMap { (value: Double) -> Double? in value.isFinite && value > 0 ? value : nil } ?? 0
        savedSliceHeight =
            slices.flatMap { (value: Double) -> Double? in value.isFinite && value > 0 ? value : nil } ?? 0
    }
    public func persistGeometry(width: Int, height: Int, libraryWidth: Int, sliceHeight: Int) {
        guard let preferences = session?.preferences, width > 0, height > 0, libraryWidth > 0, sliceHeight > 0 else {
            return
        }
        let size = "\(width)x\(height)"
        let splits = [String(libraryWidth), String(sliceHeight)]
        if preferences.string(key: "splitStudioWindowSize", fallback: "") != size {
            preferences.setString(key: "splitStudioWindowSize", value: size)
        }
        if preferences.strings("splitStudioSplitters") != splits {
            preferences.setStrings("splitStudioSplitters", splits)
        }
        hasSavedWindowSize = true
        savedWindowWidth = Double(width)
        savedWindowHeight = Double(height)
        savedLibraryWidth = Double(libraryWidth)
        savedSliceHeight = Double(sliceHeight)
    }

    private func showAlert(_ error: any Error) {
        alertText = String(describing: error)
        alertRevision += 1
    }
    private static func sourceURL(_ path: String) -> URL {
        if let url = URL(string: path), url.isFileURL { return url.standardizedFileURL }
        return URL(filePath: path).standardizedFileURL
    }
    private static func bankVoice(_ voice: VgVoice) -> BankVoice {
        BankVoice(
            macro: voice.macro.rawValue, key: Int32(voice.key), pan: Int32(voice.pan), symbol: voice.symbol,
            keysplitTable: voice.keysplitTable, sweep: Int32(voice.sweep), duty: Int32(voice.duty),
            period: Int32(voice.period),
            attack: Int32(voice.attack), decay: Int32(voice.decay), sustain: Int32(voice.sustain),
            release: Int32(voice.release))
    }
    static func projectVoice(_ voice: BankVoice) throws -> VgVoice {
        guard let macro = VgMacro(rawValue: voice.macro) else {
            throw VoicegroupStoreError.operationFailed("Split Studio: unsupported voice macro \(voice.macro).")
        }
        return VgVoice(
            macro: macro, key: Int(voice.key), pan: Int(voice.pan), symbol: voice.symbol,
            keysplitTable: voice.keysplitTable, sweep: Int(voice.sweep), duty: Int(voice.duty),
            period: Int(voice.period),
            attack: Int(voice.attack), decay: Int(voice.decay), sustain: Int(voice.sustain), release: Int(voice.release)
        )
    }
}
