import Foundation
import PorydawAppAudio
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import PorydawKitStudio
import PorydawPlayback
import PorydawProject
import PorydawSample
import PorydawSampleUI
import PorydawVoicegroup
import QtBridge

/// Owns the modeless window, project effects and generation-guarded voicegroup saves.
@MainActor
@QtBridgeable
public final class KitStudioWorkflow: QmlUncreatable {
    @QtTracked public var noteFormat = NumberFieldFormat(kind: .note)
    public var windowOpen: Bool = false
    public var presenterRevision: Int = 0
    public var saving: Bool = false
    public var promptOpen: Bool = false
    public var overwritePromptOpen: Bool = false
    public var overwritePromptText: String = ""
    public var orphanCleanupOpen: Bool = false
    public var orphanCleanupNames: [String] = []
    public var orphanCleanupSelectedNames: [String] = []
    public var orphanCleanupBusy: Bool = false
    public var orphanCleanupStatus: String = ""
    public var alertText: String = ""
    public var alertRevision: Int = 0
    public var pickerRequested: Bool = false
    public var pickerFolder: String = ""
    public var auditionPlaying: Bool = false
    public var hasSavedWindowSize: Bool = false
    public var savedWindowWidth: Double = 0
    public var savedWindowHeight: Double = 0
    public var savedLibraryWidth: Double = 0
    public var savedKeyboardHeight: Double = 0
    @QtIgnored public let closeGuard = KitStudioCloseGuard()
    private weak var session: ApplicationSession?
    private var state: KitStudioPresenter?
    private let libraryHost: StudioLibraryHost
    private var pcm: PcmAuditionPlayer?
    private var sessionGeneration = 0
    private var pendingTask: Task<Void, Never>?
    private var closeWaitTask: Task<Void, Never>?
    private var orphanCleanupTask: Task<Void, Never>?
    private var orphanCleanupCompletion: (() -> Void)?
    private var savedWavs: [String: Data] = [:]
    private struct SliceRenderKey: Equatable {
        let source: Int
        let rate: Double
        let slice: KitSourceSession.Slice
    }
    private var savedRenderKeys: [String: SliceRenderKey] = [:]
    private var createdVoicegroups: Set<String> = []
    private var createdSamples: Set<String> = []
    private var overwriteArmed = false
    private var editDestination: (name: String, location: VoicegroupLocation, tableName: String?, childCount: Int)?
    private var selectedMarker: Int?
    private var pendingNames: Set<String> = []
    private var playingSlice: Int?
    private let previewPreparation: SampleSourcePreparation


    @QtIgnored public init(session: ApplicationSession) {
        self.session = session
        let preparation = SampleSourcePreparation()
        previewPreparation = preparation
        libraryHost = StudioLibraryHost(session: session, preparation: preparation)
        libraryHost.onLoad = { [weak self] (path: String) in self?.loadSource(path: path) }
        libraryHost.onOpenFile = { [weak self] in self?.requestOpenFile() }
        libraryHost.onPreview = { [weak self] (path: String) in self?.previewLibrary(path: path) }
        libraryHost.onStop = { [weak self] in self?.stopAudition() }
        closeGuard.onChanged = { [weak self] in self?.promptOpen = self?.closeGuard.promptOpen ?? false }
        closeGuard.onSave = { [weak self] in self?.saveVoicegroup() }
    }

    public func presenter() -> Optional<KitStudioPresenter> { state }

    public func library() -> Optional<SampleLibraryModel> { libraryHost.library() }

    /// Opens an empty kit; only an open project is required, never a song.
    public func requestOpen() {
        guard let session, session.projectOpen, !saving else { return }
        if windowOpen {
            presenterRevision += 1
            return
        }
        open()
    }

    /// Loads a song voice's subgroup for editing and saving to its original source.
    public func requestEdit(slot: Int) {
        // Cleanup overlap cancels the edit; retrying regenerates mappings from the surviving project.
        guard let session, session.projectOpen, !saving, !orphanCleanupBusy, !orphanCleanupOpen,
            let service = session.catalogService, session.voiceList.isBound, !session.voiceList.isLoading,
            let document = session.voiceList.session, !document.isClosed,
            session.voiceList.slots.indices.contains(slot),
            let parent = session.voiceList.slots[slot].voice,
            VoiceListSemantics.isKitMacro(parent.macro)
        else { return }
        if windowOpen, state?.dirty == true {
            guardClose(
                source: .window, proceed: { [weak self] in self?.requestEdit(slot: slot) }, cancel: {})
            return
        }
        sessionGeneration += 1
        let generation = sessionGeneration
        let lease = document.bankLease
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            defer {
                if self?.sessionGeneration == generation { self?.pendingTask = nil }
            }
            do {
                let loaded = try await KitEditLoader.load(
                    service: service, projectRoot: session.projectRoot, lease: lease, slot: slot, parent: parent)
                guard let self, self.current(generation: generation, service: service),
                    !document.isClosed, session.voiceList.session === document,
                    !self.orphanCleanupBusy, !self.orphanCleanupOpen
                else { return }
                self.open()
                self.editDestination = (loaded.name, loaded.location, loaded.tableName, loaded.childCount)
                self.createdVoicegroups.insert(loaded.name)
                self.state?.load(zones: loaded.zones, mode: loaded.mode, name: loaded.name)
                self.state?.samples = loaded.samples
                self.state?.progWaves = loaded.waves
                self.presenterRevision += 1
            } catch {
                guard let self, self.current(generation: generation, service: service) else { return }
                self.showAlert(error)
            }
        }
    }

    private func open() {
        guard let session else { return }
        sessionGeneration += 1
        pendingTask?.cancel()
        pendingTask = nil
        saving = false
        alertText = ""
        stopAudition()
        let presenter = KitStudioPresenter()
        presenter.open()
        presenter.waveform = MarkerWaveformModel(palette: session.palette)
        presenter.waveform?.setBaseFontPx(value: Double(session.baseFontPx))
        presenter.waveform?.onMarkerPressed = { [weak self] (id: Int) in self?.selectedMarker = id }
        wire(presenter)
        state = presenter
        savedWavs.removeAll()
        savedRenderKeys.removeAll()
        createdVoicegroups.removeAll()
        createdSamples.removeAll()
        pendingNames.removeAll()
        overwriteArmed = false
        overwritePromptOpen = false
        overwritePromptText = ""
        selectedMarker = nil
        editDestination = nil
        presenter.applySuggestedVoicegroupName(nextFreeVoicegroupName(stem: "new_kit"))
        restoreGeometry()
        pcm = PcmAuditionPlayer(lane: libraryHost.lane())
        pcm?.onPlayhead = { [weak self] (frame: Int?) in
            guard let self, let id = self.playingSlice else { return }
            let sourceFrame = frame.flatMap { (_: Int) -> Int? in
                self.state?.sourceFrame(sliceId: id, renderedPosition: self.pcm?.playheadPosition ?? 0)
            }
            self.state?.waveform?.setPlayhead(frame: sourceFrame)
            self.auditionPlaying = self.pcm?.playing ?? false
        }
        windowOpen = true
        presenterRevision += 1
    }

    private func wire(_ presenter: KitStudioPresenter) {
        presenter.onSaveRequested = { [weak self] in self?.saveVoicegroup() }
        presenter.onAlert = { [weak self] (message: String) in
            self?.showAlert(ProjectServiceError.operationFailed(message))
        }
        presenter.validateName = { [weak self] (name: String) -> String? in self?.validateName(name) }
        presenter.validateVoicegroupName = { [weak self] (name: String) -> String? in
            self?.validateVoicegroupName(name)
        }
        presenter.publishKitTone = { [weak self] (tone: KitAuditionTone, key: UInt8) -> Bool in
            guard let self else { return false }
            self.stopAudition()
            return self.session?.audio?.auditionKit(tone, key: key) ?? false
        }
        presenter.playPcm = { [weak self] (id: Int) in self?.playSlice(id: id) }
    }

    private func current(generation: Int, service: ProjectService? = nil) -> Bool {
        !Task.isCancelled && sessionGeneration == generation
            && (service == nil || session?.catalogService === service)
    }

    private func validateName(_ name: String) -> String? {
        guard let session else { return "Project is closed." }
        let names = (state?.session.sources ?? []).flatMap { $0.slices.map(\.name) }
        var symbols = Set(VoicegroupSource.directSoundSymbols(session.projectRoot))
        symbols.formUnion((pendingNames.union(names)).map { "DirectSoundWaveData_" + $0 })
        return SampleRegistrar.validate(projectRoot: session.projectRoot, name: name, existingSymbols: Array(symbols))
    }

    /// Nil when the name can be saved: a valid symbol that names no existing
    /// voicegroup, or one this window created and may rewrite in place.
    private func validateVoicegroupName(_ name: String) -> String? {
        guard let session else { return "Project is closed." }
        guard ProjectService.isValidVoicegroupName(name: name) else {
            return "Voicegroup names use letters, digits and underscores, starting with a letter."
        }
        if !createdVoicegroups.contains(name), voicegroupNameTaken(name, projectRoot: session.projectRoot) {
            return "Voicegroup \(name) already exists in this project."
        }
        return nil
    }

    private func voicegroupNameTaken(_ name: String, projectRoot: String) -> Bool {
        if ProjectFileStore.exists(projectRoot + "/sound/voicegroups/" + name + ".inc") { return true }
        let locator = VoicegroupLocator(layout: ProjectLayout(projectRoot: projectRoot).ensuringDeepScan())
        return locator.locateSubgroup(symbol: Array(("voicegroup_" + name).utf8)[...]) != nil
    }

    /// First free `<stem>` with `_2`, `_3` … suffixes; stems from file names
    /// gain a leading letter when sanitizing leaves a leading digit.
    private func nextFreeVoicegroupName(stem: String) -> String {
        var base = stem.isEmpty ? "new_kit" : stem
        if let first = base.unicodeScalars.first,
            !(65...90).contains(first.value) && !(97...122).contains(first.value)
        {
            base = "kit_" + base
        }
        guard let session else { return base }
        var candidate = base
        var suffix = 2
        while voicegroupNameTaken(candidate, projectRoot: session.projectRoot) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    public func requestOpenFile() {
        guard windowOpen, !saving, session != nil else { return }
        pickerFolder = libraryHost.pickerFolder()
        pickerRequested = true
    }
    public func cancelSource() { pickerRequested = false }
    public func chooseSource(fileURL: String) {
        pickerRequested = false
        loadSource(path: fileURL)
    }

    public func loadSource(path: String) {
        guard windowOpen, !saving, let state, let url = libraryHost.sourceURL(path) else { return }
        stopAudition()
        do { try addSource(url, to: state, autoPlaceFirstSlice: true) } catch { showAlert(error) }
    }

    public func dropLibrarySample(path: String, onKey: Int) {
        guard windowOpen, !saving, let state, let url = libraryHost.sourceURL(path) else { return }
        stopAudition()
        do {
            try addSource(url, to: state, autoPlaceFirstSlice: false)
            if let id = state.session.sources.last?.id {
                state.session.createFirstSlice(source: id)
            }
            let newest = state.newestSliceId()
            if newest != 0 {
                state.dropSample(name: state.sliceName(id: newest), onKey: onKey)
            }
        } catch { showAlert(error) }
    }

    /// Decodes and adds one file; the first file of an empty kit suggests the voicegroup name.
    private func addSource(_ url: URL, to state: KitStudioPresenter, autoPlaceFirstSlice: Bool) throws {
        let wasEmpty = state.session.sources.isEmpty
        let sample = try SampleImport.decodeFile(path: url.path)
        state.addSource(sample, autoPlaceFirstSlice: autoPlaceFirstSlice)
        if wasEmpty, !state.voicegroupNameEdited {
            let stem = SampleNames.sanitize(url.deletingPathExtension().lastPathComponent)
            state.applySuggestedVoicegroupName(nextFreeVoicegroupName(stem: stem.isEmpty ? "new_kit" : stem + "_kit"))
        }
        session?.preferences.setString(key: "lastSampleDir", value: url.deletingLastPathComponent().path)
    }

    /// Whether every entry of a dragged `text/uri-list` names an audio file drop targets may accept.
    public func areLoadableSources(uriList: String) -> Bool {
        let entries = DroppedURIList.entries(uriList)
        return !entries.isEmpty && entries.allSatisfy { (path: String) -> Bool in isLoadableSource(path) }
    }

    private func isLoadableSource(_ path: String) -> Bool {
        guard let url = libraryHost.sourceURL(path), url.isFileURL,
            SampleImport.fileExtensions.contains(url.pathExtension.lowercased())
        else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private func previewLibrary(path: String) {
        guard windowOpen, !saving, libraryHost.pane != nil else { return }
        stopAudition()
        libraryHost.preview(
            path: path,
            accept: { [weak self] () -> Bool in self?.windowOpen == true && self?.saving == false },
            key: { () -> Int? in nil })
    }

    public func keyName(key: Int) -> String { midiKeyName(key) }
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
        state?.rateChoiceIndex(rate: rate) ?? -1
    }
    public func chooseSourceRate(index: Int) {
        guard let rate = state?.rate(forChoice: index) else { return }
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
        let voice = state?.sliceVoice(id: id)
        pcm?.play(
            owner: self, rendered: rendered, looped: rendered.looped, key: voice?.note ?? 60,
            adsr: voice?.adsr ?? AudioADSR(), toneKey: 60)
        auditionPlaying = pcm?.playing ?? false
    }
    public func tickAudition() {
        pcm?.tick()
        auditionPlaying = pcm?.playing ?? false
    }
    public func stopAudition() {
        previewPreparation.cancel()
        pcm?.stop(owner: self)
        session?.audio?.auditionSampleOff()
        state?.waveform?.setPlayhead(frame: nil)
        playingSlice = nil
        auditionPlaying = false
        libraryHost.clearPreview()
    }

    /// Writes slice samples and `sound/voicegroups/<name>.inc` (plus keysplit table); never songs or banks.
    /// Re-saving rewrites in place, skipping unchanged audio and asking before overwriting saved audio.
    public func saveVoicegroup() {
        if saving { return }
        guard let session, let service = session.catalogService, let state, windowOpen, state.canSave else {
            closeGuard.saveSettled(success: false)
            return
        }
        let mode: KitMode = state.mode == 0 ? .drumkit : .keysplit
        let zones = mode == .drumkit ? state.draft.drumkitZones : state.draft.keysplitZones
        saving = true
        alertText = ""
        stopAudition()
        let generation = sessionGeneration
        let root = session.projectRoot
        let name = state.voicegroupName
        let destination = editDestination.flatMap { $0.name == name ? $0 : nil }
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
        // A slice name matching a project sample this window did not create is
        // never written; the rename validator rejects these, this is the backstop.
        let symbols = Set(VoicegroupSource.directSoundSymbols(root))
        for sample in rendered where !createdSamples.contains(sample.name) {
            let symbol = "DirectSoundWaveData_" + sample.name
            if symbols.contains(symbol) || Self.sampleFileExists(projectRoot: root, name: sample.name) {
                saving = false
                showAlert(
                    ProjectServiceError.operationFailed(
                        "Split Studio: \(sample.name) already exists in this project."))
                closeGuard.saveSettled(success: false)
                return
            }
        }
        let changed = rendered.filter { (sample: (name: String, wav: Data)) -> Bool in
            createdSamples.contains(sample.name) && savedWavs[sample.name] != sample.wav
        }
        if !changed.isEmpty, !overwriteArmed {
            let names = changed.map(\.name).sorted()
            overwritePromptText = "Overwrite \(names.count) saved samples?\n" + names.joined(separator: "\n")
            overwritePromptOpen = true
            saving = false
            return
        }
        overwriteArmed = false
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
                guard self.current(generation: generation, service: service) else { return }
                let new = rendered.filter { (sample: (name: String, wav: Data)) -> Bool in
                    !self.createdSamples.contains(sample.name)
                }
                let absentBefore = new.filter { (sample: (name: String, wav: Data)) -> Bool in
                    !ProjectFileStore.exists(root + "/sound/direct_sound_samples/" + sample.name + ".wav")
                }
                if !new.isEmpty {
                    do { try SampleRegistrar.registerBatch(projectRoot: root, samples: new) } catch {
                        for sample in absentBefore
                        where ProjectFileStore.exists(root + "/sound/direct_sound_samples/" + sample.name + ".wav") {
                            session.recordCreatedSample(name: sample.name)
                        }
                        throw error
                    }
                }
                for sample in new {
                    session.recordCreatedSample(name: sample.name)
                    self.createdSamples.insert(sample.name)
                    self.savedWavs[sample.name] = sample.wav
                }
                for sample in rendered where self.savedWavs[sample.name] != sample.wav {
                    // Like registrations, slice audio is a disk asset: kit undo restores
                    // references, not earlier audio. The service owns cache invalidation.
                    state.samples.removeValue(forKey: "DirectSoundWaveData_" + sample.name)
                    try await service.commitSample(
                        SampleCommitRequest(name: sample.name, wav: sample.wav, update: true))
                    guard self.current(generation: generation, service: service) else { return }
                    self.createdSamples.insert(sample.name)
                    self.savedWavs[sample.name] = sample.wav
                }
                if !self.createdVoicegroups.contains(name) {
                    try VoicegroupSource.createVoicegroup(
                        projectRoot: root, name: name, copyFromFile: "", copySectionLabel: "")
                    session.recordCreatedSubgroup(symbol: "voicegroup_" + name)
                    try VoicegroupSource.appendIncludeLine(projectRoot: root, name: name)
                    self.createdVoicegroups.insert(name)
                }
                let writtenChildCount = try Self.writeKitChildren(
                    projectRoot: root, name: name, zones: zones, mode: mode,
                    sliceNames: Set(rendered.map(\.name)), location: destination?.location,
                    previousChildCount: destination?.childCount)
                if destination != nil { self.editDestination?.childCount = writtenChildCount }
                if mode == .keysplit {
                    try Self.writeKeysplitTable(
                        projectRoot: root, name: destination?.tableName ?? "keysplit_" + name, zones: zones)
                }
                guard self.current(generation: generation, service: service) else { return }
                _ = await session.refreshVoicegroupCatalog()
                guard self.current(generation: generation, service: service) else { return }
                self.savedRenderKeys.merge(renderKeys) { _, current in current }
                state.markClean()
                self.savedWavs = self.savedWavs.filter { (entry: (key: String, value: Data)) -> Bool in
                    renderKeys[entry.key] != nil
                }
                self.savedRenderKeys = renderKeys
                saveSucceeded = true
            } catch {
                guard self.sessionGeneration == generation else { return }
                self.showAlert(error)
            }
        }
    }

    public func answerOverwrite(overwrite: Bool) {
        guard overwritePromptOpen, !saving else { return }
        overwritePromptOpen = false
        overwritePromptText = ""
        if overwrite {
            overwriteArmed = true
            saveVoicegroup()
        } else {
            closeGuard.saveSettled(success: false)
        }
    }

    private static func sampleFileExists(projectRoot: String, name: String) -> Bool {
        for ext in [".wav", ".bin", ".aif"] {
            if ProjectFileStore.exists(projectRoot + "/sound/direct_sound_samples/" + name + ext) { return true }
        }
        return false
    }

    /// Writes new groups or the original subgroup section through the voice-line serializer.
    private static func writeKitChildren(
        projectRoot: String, name: String, zones: [KitZone], mode: KitMode, sliceNames: Set<String>,
        location: VoicegroupLocation?, previousChildCount: Int?
    ) throws -> Int {
        var children = KitDraftCodec.children(from: zones, mode: mode)
        for index in children.indices {
            if let voiceName = children[index]?.symbol, sliceNames.contains(voiceName) {
                children[index]?.symbol = "DirectSoundWaveData_" + voiceName
            }
        }
        let destination =
            location
            ?? VoicegroupLocation(
                filePath: projectRoot + "/sound/voicegroups/" + name + ".inc", sectionLabel: "")
        let path = destination.filePath
        let source = VoicegroupSource()
        var error: String?
        guard source.open(location: destination, error: &error) else {
            throw VoicegroupStoreError.operationFailed(error ?? "Cannot open \(path).")
        }
        for (slot, child) in children.enumerated() {
            guard source.setVoice(slot: slot, voice: child ?? kitBlankChildVoice) else {
                throw VoicegroupStoreError.operationFailed("Cannot edit slot \(slot) in \(path).")
            }
        }
        let writtenChildCount = max(children.count, previousChildCount ?? 0)
        for slot in children.count..<writtenChildCount {
            guard source.setVoice(slot: slot, voice: kitBlankChildVoice) else {
                throw VoicegroupStoreError.operationFailed("Cannot clear slot \(slot) in \(path).")
            }
        }
        guard try source.save() else {
            throw VoicegroupStoreError.operationFailed("Cannot save \(path): edit superseded.")
        }
        return writtenChildCount
    }

    private static func writeKeysplitTable(projectRoot: String, name: String, zones: [KitZone]) throws {
        let table = KitDraftCodec.table(from: zones, name: name)
        let layout = ProjectLayout(projectRoot: projectRoot).ensuringDeepScan()
        var path = layout.keysplitTableFiles.first ?? projectRoot + "/sound/keysplit_tables.inc"
        do {
            for candidate in layout.keysplitTableFiles {
                if try KeysplitTables.parse(files: [candidate]).table(named: table.name) != nil {
                    path = candidate
                    break
                }
            }
        } catch {
            throw VoicegroupStoreError.operationFailed("Cannot read keysplit tables: \(error).")
        }
        do {
            try KeysplitTableWriter.replace(table: table, inFile: path)
        } catch {
            throw VoicegroupStoreError.operationFailed("Cannot write \(path): \(error).")
        }
    }



    @QtIgnored
    func guardClose(
        source: KitStudioCloseGuard.Source,
        proceed: @escaping () -> Void, cancel: @escaping () -> Void
    ) {
        guard !orphanCleanupBusy, !orphanCleanupOpen, closeWaitTask == nil else {
            cancel()
            return
        }
        guard windowOpen else {
            proceed()
            return
        }
        if saving {
            let task = pendingTask
            closeWaitTask = Task { [weak self] in
                await task?.value
                guard let self else { return }
                self.closeWaitTask = nil
                self.guardClose(source: source, proceed: proceed, cancel: cancel)
            }
            return
        }
        guard !promptOpen, !closeGuard.saving else {
            cancel()
            return
        }
        // The window holds no song state, so closing a song tab never waits on
        // it; project switches and quits still ask about unsaved voicegroup work.
        guard source != .tab else {
            proceed()
            return
        }
        closeGuard.request(
            source: source, dirty: state?.dirty ?? false,
            proceed: { [weak self] in
                self?.close()
                proceed()
            },
            cancel: cancel)
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
        guard !saving, !overwritePromptOpen else { return }
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
        closeWaitTask?.cancel()
        pendingTask = nil
        closeWaitTask = nil
        overwritePromptOpen = false
        overwritePromptText = ""
        overwriteArmed = false
        saving = false
        pcm?.close()
        pcm = nil
        state = nil
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
        let splits = session?.preferences.strings("splitStudioPanes") ?? []
        let library = splits.count == 2 ? Double(splits[0]) : nil
        let keyboard = splits.count == 2 ? Double(splits[1]) : nil
        savedLibraryWidth =
            library.flatMap { (value: Double) -> Double? in value.isFinite && value > 0 ? value : nil } ?? 0
        savedKeyboardHeight =
            keyboard.flatMap { (value: Double) -> Double? in value.isFinite && value > 0 ? value : nil } ?? 0
    }
    public func persistGeometry(width: Int, height: Int, libraryWidth: Int, keyboardHeight: Int) {
        guard let preferences = session?.preferences, width > 0, height > 0, libraryWidth > 0, keyboardHeight > 0
        else {
            return
        }
        let size = "\(width)x\(height)"
        let splits = [String(libraryWidth), String(keyboardHeight)]
        if preferences.string(key: "splitStudioWindowSize", fallback: "") != size {
            preferences.setString(key: "splitStudioWindowSize", value: size)
        }
        if preferences.strings("splitStudioPanes") != splits {
            preferences.setStrings("splitStudioPanes", splits)
        }
        hasSavedWindowSize = true
        savedWindowWidth = Double(width)
        savedWindowHeight = Double(height)
        savedLibraryWidth = Double(libraryWidth)
        savedKeyboardHeight = Double(keyboardHeight)
    }

    private func showAlert(_ error: any Error) {
        alertText = String(describing: error)
        alertRevision += 1
    }
}
