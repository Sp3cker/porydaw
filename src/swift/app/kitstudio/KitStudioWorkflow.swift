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

/// Owns the modeless window's lifetime and its project effects; per-window state lives in `KitStudioWindow`.
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
    private let beginSampleAudition: (@escaping @MainActor (SampleAuditionEvent) -> Void) -> SampleAuditionLease?
    private var window: KitStudioWindow?
    private let libraryHost: StudioLibraryHost
    private var loadTask: Task<Void, Never>?
    private var closeWaitTask: Task<Void, Never>?
    private var orphanCleanupTask: Task<Void, Never>?
    private var orphanCleanupCompletion: (() -> Void)?
    private let previewPreparation: SampleSourcePreparation
    private var kitAudition: SampleAuditionLease?

    @QtIgnored public convenience init(session: ApplicationSession) {
        self.init(
            session: session,
            beginSampleAudition: {
                [weak session] (onEvent: @escaping @MainActor (SampleAuditionEvent) -> Void) -> SampleAuditionLease? in
                session?.audio?.beginSampleAudition(onEvent: onEvent)
            })
    }

    @QtIgnored init(
        session: ApplicationSession,
        beginSampleAudition: @escaping (@escaping @MainActor (SampleAuditionEvent) -> Void) -> SampleAuditionLease?
    ) {
        self.beginSampleAudition = beginSampleAudition
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

    public func presenter() -> Optional<KitStudioPresenter> { window?.presenter }

    public func library() -> Optional<SampleLibraryModel> { libraryHost.library() }

    /// Opens an empty kit; only an open project is required, never a song.
    public func requestOpen() {
        guard let session, session.projectOpen, !saving else { return }
        if windowOpen {
            presenterRevision += 1
            return
        }
        loadTask?.cancel()
        loadTask = nil
        open(editing: nil)
    }

    /// Loads a song voice's subgroup for editing and saving to its original source.
    public func requestEdit(slot: Int) {
        // Cleanup overlap cancels the edit; retrying regenerates mappings from the surviving project.
        guard let session, session.projectOpen, !saving, !orphanCleanupBusy, !orphanCleanupOpen,
            let service = session.catalogService, session.voiceList.isBound, !session.voiceList.isLoading,
            session.voiceList.editingEnabled, let group = session.voiceList.voicegroup,
            session.voiceList.slots.indices.contains(slot),
            let parent = session.voiceList.slots[slot].voice,
            VoiceListSemantics.isKitMacro(parent.macro)
        else { return }
        if windowOpen, window?.presenter.dirty == true {
            guardClose(
                source: .window, proceed: { [weak self] in self?.requestEdit(slot: slot) }, cancel: {})
            return
        }
        let lease = group.value.lease
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            do {
                let expected = try await service.readKit(lease: lease, slot: slot)
                let loaded = try await KitEditLoader.load(
                    service: service, projectRoot: session.projectRoot, lease: lease, kit: expected, parent: parent)
                guard let self, !Task.isCancelled, session.catalogService === service,
                    session.voiceList.voicegroup === group, session.voiceList.editingEnabled,
                    !self.orphanCleanupBusy, !self.orphanCleanupOpen
                else { return }
                self.loadTask = nil
                self.open(
                    editing: (
                        kit: loaded,
                        target: KitStudioFootprint.EditTarget(name: loaded.name, group: group, expected: expected)
                    ))
            } catch {
                guard let self, !Task.isCancelled, session.catalogService === service else { return }
                self.loadTask = nil
                self.showAlert(error)
            }
        }
    }

    /// Replaces the window's whole state with a fresh kit, or with a loaded one being edited.
    private func open(editing loaded: (kit: KitEditLoader.LoadedKit, target: KitStudioFootprint.EditTarget)?) {
        guard let session else { return }
        stopAudition()
        alertText = ""
        let footprint = KitStudioFootprint(edit: loaded?.target)
        let effects = effects(for: footprint)
        let waveform = MarkerWaveformModel(palette: session.palette)
        waveform.setBaseFontPx(value: Double(session.baseFontPx))
        let presenter: KitStudioPresenter
        if let kit = loaded?.kit {
            presenter = KitStudioPresenter(
                loading: kit.zones, mode: kit.mode, name: kit.name, samples: kit.samples, progWaves: kit.waves,
                waveform: waveform, effects: effects)
        } else {
            presenter = KitStudioPresenter(waveform: waveform, effects: effects)
        }
        let next = KitStudioWindow(
            presenter: presenter, footprint: footprint,
            pcm: PcmAuditionPlayer(
                beginSampleAudition: beginSampleAudition))
        next.pcm.onPlayhead = { [weak self, weak next] (frame: Int) in
            guard let self, let next, self.window === next, let id = next.playingSlice else { return }
            next.presenter.waveform?.setPlayhead(
                frame: next.presenter.sourceFrame(sliceId: id, renderedPosition: Double(frame)))
        }
        next.pcm.onLifecycle = { [weak self, weak next] (lifecycle: PcmAuditionPlayer.Lifecycle) in
            guard let self, let next, self.window === next else { return }
            switch lifecycle {
            case .starting, .repeatGap:
                next.presenter.waveform?.setPlayhead(frame: nil)
                self.auditionPlaying = true
            case .sounding:
                self.auditionPlaying = true
            case .ended:
                next.playingSlice = nil
                next.presenter.waveform?.setPlayhead(frame: nil)
                self.auditionPlaying = false
            }
        }
        replaceWindow(next)
        if loaded == nil { presenter.applySuggestedVoicegroupName(nextFreeVoicegroupName(stem: "new_kit")) }
        restoreGeometry()
        windowOpen = true
        presenterRevision += 1
    }

    /// Closes the current window's work and publishes the replacement's save state.
    private func replaceWindow(_ next: KitStudioWindow?) {
        window?.close()
        window = next
        publishSave()
    }

    private func effects(for footprint: KitStudioFootprint) -> KitStudioEffects {
        var effects = KitStudioEffects()
        effects.onSaveRequested = { [weak self] in self?.saveVoicegroup() }
        effects.onAlert = { [weak self] (message: String) in
            self?.showAlert(ProjectServiceError.operationFailed(message))
        }
        effects.validateName = { [weak self] (name: String) -> String? in self?.validateName(name) }
        effects.validateVoicegroupName = { [weak self, weak footprint] (name: String) -> String? in
            guard let self, let footprint else { return "Split Studio is closed." }
            return self.validateVoicegroupName(name, footprint: footprint)
        }
        effects.beginKeyAudition = { [weak self] in
            guard let self else { return }
            self.stopAudition()
            self.kitAudition = self.beginSampleAudition(
                { [weak self] (event: SampleAuditionEvent) in
                    switch event {
                    case .finished: self?.kitAudition?.stop()
                    case .ended: self?.kitAudition = nil
                    case .started: break
                    }
                })
        }
        effects.publishKitTone = { [weak self] (tone: KitAuditionTone, key: UInt8) -> Bool in
            guard let lease = self?.kitAudition, lease.isCurrent else { return false }
            lease.play { (id: SampleAuditionNoteID) -> SampleAuditionNote in
                SampleAuditionNote(id: id, source: .kit(tone), key: key, adsr: AudioADSR(), toneKey: 60)
            }
            return true
        }
        effects.playPcm = { [weak self] (id: Int) in self?.playSlice(id: id) }
        return effects
    }

    /// Whether a save task's window is still the open one on the same project service.
    private func isCurrent(_ window: KitStudioWindow, service: ProjectService) -> Bool {
        !Task.isCancelled && self.window === window && session?.catalogService === service
    }

    private func validateName(_ name: String) -> String? {
        guard let session else { return "Project is closed." }
        let names = (window?.presenter.session.sources ?? []).flatMap { $0.slices.map(\.name) }
        var symbols = Set(VoicegroupSource.directSoundSymbols(session.projectRoot))
        symbols.formUnion(((window?.writingNames ?? []).union(names)).map { "DirectSoundWaveData_" + $0 })
        return SampleRegistrar.validate(projectRoot: session.projectRoot, name: name, existingSymbols: Array(symbols))
    }

    /// Nil when the name can be saved: a valid symbol that names no existing
    /// voicegroup, or one the window owns and may rewrite in place.
    private func validateVoicegroupName(_ name: String, footprint: KitStudioFootprint) -> String? {
        guard let session else { return "Project is closed." }
        guard ProjectService.isValidVoicegroupName(name: name) else {
            return "Voicegroup names use letters, digits and underscores, starting with a letter."
        }
        if !footprint.owns(voicegroup: name), voicegroupNameTaken(name, projectRoot: session.projectRoot) {
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

    /// The open window while no save is writing; source edits and previews need it.
    private var editableWindow: KitStudioWindow? { windowOpen && !saving ? window : nil }

    public func loadSource(path: String) {
        guard let state = editableWindow?.presenter, let url = libraryHost.sourceURL(path) else { return }
        stopAudition()
        do { try addSource(url, to: state, autoPlaceFirstSlice: true) } catch { showAlert(error) }
    }

    public func dropLibrarySample(path: String, onKey: Int) {
        guard let state = editableWindow?.presenter, let url = libraryHost.sourceURL(path) else { return }
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
        guard editableWindow != nil, libraryHost.pane != nil else { return }
        stopAudition()
        libraryHost.preview(
            path: path,
            accept: { [weak self] () -> Bool in self?.editableWindow != nil },
            key: { () -> Int? in nil })
    }

    public func keyName(key: Int) -> String { midiKeyName(key) }
    public func selectSource(row: Int) {
        stopAudition()
        window?.presenter.selectSource(row: row)
    }
    public func closeSource(row: Int) {
        stopAudition()
        window?.presenter.closeSource(row: row)
    }
    public func setSourceRate(rate: Int) {
        stopAudition()
        window?.presenter.setSourceRate(rate: rate)
    }
    public func sourceRateIndex(rate: Double) -> Int {
        window?.presenter.rateChoiceIndex(rate: rate) ?? -1
    }
    public func chooseSourceRate(index: Int) {
        guard let rate = window?.presenter.rate(forChoice: index) else { return }
        setSourceRate(rate: rate)
    }
    public func undo() {
        stopAudition()
        window?.presenter.undo()
    }
    public func redo() {
        stopAudition()
        window?.presenter.redo()
    }
    public func removeSlice(id: Int) {
        if window?.playingSlice == id { stopAudition() }
        window?.presenter.removeSlice(id: id)
    }
    private func playSlice(id: Int) {
        guard let window else { return }
        stopAudition()
        guard let lease = window.pcm.claim() else { return }
        let voice = window.presenter.sliceVoice(id: id)
        window.presenter.renderSlice(id: id) { [weak self, weak window] (rendered: ProcessedSample) in
            guard let self, let window, self.window === window, lease.isCurrent else { return }
            guard !rendered.s8.isEmpty else {
                lease.stop()
                return
            }
            window.playingSlice = id
            let note = SampleAuditionNote(
                id: .unassigned,
                source: .pcm(
                    samples: rendered.s8, frequency: rendered.freq,
                    loopStart: rendered.loopStart, looped: rendered.looped),
                key: voice?.note ?? 60, adsr: voice?.adsr ?? AudioADSR(), toneKey: 60)
            window.pcm.play(note, lease: lease, repeatPolicy: .repeatSame)
        }
    }
    public func tickAudition() {
        window?.pcm.tick()
        auditionPlaying = window?.pcm.playing ?? false
    }

    public func stopAudition() {
        window?.presenter.cancelAuditionRender()
        previewPreparation.cancel()
        window?.pcm.stop()
        kitAudition?.stop()
        libraryHost.clearPreview()
    }

    /// Writes slice assets and saves existing kit edits through their captured voicegroup; never writes songs.
    /// Re-saving rewrites in place, skipping unchanged audio and asking before overwriting saved audio.
    public func saveVoicegroup() { save(overwriteConfirmed: false) }

    public func answerOverwrite(overwrite: Bool) {
        guard let window, case .confirmingOverwrite = window.save else { return }
        setSave(.idle, on: window)
        if overwrite {
            save(overwriteConfirmed: true)
        } else {
            closeGuard.saveSettled(success: false)
        }
    }

    private func save(overwriteConfirmed: Bool) {
        if window?.saveInProgress == true { return }
        guard let session, let service = session.catalogService, let window, windowOpen, window.presenter.canSave
        else {
            closeGuard.saveSettled(success: false)
            return
        }
        let state = window.presenter
        let footprint = window.footprint
        let mode: KitMode = state.mode == 0 ? .drumkit : .keysplit
        let zones = mode == .drumkit ? state.draft.drumkitZones : state.draft.keysplitZones
        alertText = ""
        stopAudition()
        let root = session.projectRoot
        let name = state.voicegroupName
        let edit = footprint.edit?.name == name ? footprint.edit : nil
        let sources = state.session.sources
        var entries: [(name: String, key: KitStudioFootprint.RenderKey, written: KitStudioFootprint.SampleFile?)] = []
        var inputs: [(source: KitSourceSession.Source, slice: KitSourceSession.Slice)] = []
        var sliceSymbols: [String: String] = [:]
        for source in sources {
            for slice in source.slices {
                if let symbol = source.committedSymbol(of: slice) {
                    sliceSymbols[slice.name] = symbol
                    continue
                }
                sliceSymbols[slice.name] = "DirectSoundWaveData_" + slice.name
                let key = KitStudioFootprint.RenderKey(source: source.id, rate: source.targetRate, slice: slice)
                let previous = footprint.written[slice.name]
                let unchanged = previous?.key == key ? previous : nil
                entries.append((slice.name, key, unchanged))
                if unchanged == nil { inputs.append((source, slice)) }
            }
        }
        let names = Set(entries.map(\.name))
        let task = Task { [weak self] in
            guard let self else { return }
            var saveSucceeded = false
            var settleSave = true
            defer {
                if settleSave, self.window === window {
                    self.setSave(.idle, on: window)
                    self.closeGuard.saveSettled(success: saveSucceeded)
                }
            }
            let wavs = await KitSourceSession.renderWavs(inputs)
            guard self.isCurrent(window, service: service), wavs.count == inputs.count else { return }
            var rendered: [KitStudioFootprint.SampleFile] = []
            rendered.reserveCapacity(entries.count)
            var wavIndex = 0
            for entry in entries {
                if let written = entry.written {
                    rendered.append(written)
                } else {
                    rendered.append(
                        KitStudioFootprint.SampleFile(name: entry.name, key: entry.key, wav: wavs[wavIndex]))
                    wavIndex += 1
                }
            }
            // Project samples not written by this window must never be overwritten.
            let symbols = Set(VoicegroupSource.directSoundSymbols(root))
            for sample in rendered where footprint.written[sample.name] == nil {
                let symbol = "DirectSoundWaveData_" + sample.name
                if symbols.contains(symbol) || Self.sampleFileExists(projectRoot: root, name: sample.name) {
                    self.showAlert(
                        ProjectServiceError.operationFailed(
                            "Split Studio: \(sample.name) already exists in this project."))
                    return
                }
            }
            let changed = rendered.filter { (sample: KitStudioFootprint.SampleFile) -> Bool in
                footprint.written[sample.name].map { (written: KitStudioFootprint.SampleFile) -> Bool in
                    written.wav != sample.wav
                } ?? false
            }
            if !changed.isEmpty, !overwriteConfirmed {
                let names = changed.map(\.name).sorted()
                settleSave = false
                self.setSave(
                    .confirmingOverwrite(
                        prompt: "Overwrite \(names.count) saved samples?\n" + names.joined(separator: "\n")),
                    on: window)
                return
            }
            do {
                guard self.isCurrent(window, service: service) else { return }
                let new = rendered.filter { (sample: KitStudioFootprint.SampleFile) -> Bool in
                    footprint.written[sample.name] == nil
                }
                if !new.isEmpty {
                    let absentBefore = new.filter { (sample: KitStudioFootprint.SampleFile) -> Bool in
                        !ProjectFileStore.exists(root + "/sound/direct_sound_samples/" + sample.name + ".wav")
                    }
                    do {
                        try SampleRegistrar.registerBatch(
                            projectRoot: root,
                            samples: new.map { (sample: KitStudioFootprint.SampleFile) -> (name: String, wav: Data) in
                                (sample.name, sample.wav)
                            })
                    } catch {
                        for sample in absentBefore
                        where ProjectFileStore.exists(root + "/sound/direct_sound_samples/" + sample.name + ".wav") {
                            session.recordCreatedSample(name: sample.name)
                        }
                        throw error
                    }
                }
                for sample in new {
                    session.recordCreatedSample(name: sample.name)
                    footprint.written[sample.name] = sample
                }
                for sample in rendered {
                    if footprint.written[sample.name]?.wav != sample.wav {
                        // Like registrations, slice audio is a disk asset: kit undo restores
                        // references, not earlier audio. The service owns cache invalidation.
                        state.samples.removeValue(forKey: "DirectSoundWaveData_" + sample.name)
                        try await service.commitSample(
                            SampleCommitRequest(name: sample.name, wav: sample.wav, update: true))
                        guard self.isCurrent(window, service: service) else { return }
                    }
                    footprint.written[sample.name] = sample
                }
                if !footprint.owns(voicegroup: name) {
                    try VoicegroupSource.createVoicegroup(
                        projectRoot: root, name: name, copyFromFile: "", copySectionLabel: "")
                    session.recordCreatedSubgroup(symbol: "voicegroup_" + name)
                    try VoicegroupSource.appendIncludeLine(projectRoot: root, name: name)
                    footprint.createdVoicegroups.insert(name)
                }
                if let edit {
                    let value = KitDraftCodec.edit(
                        from: zones, mode: mode, name: name, expected: edit.expected, symbols: sliceSymbols)
                    _ = try await edit.group.applyKit(value, expected: edit.expected)
                    footprint.edit?.expected = value
                    // A closed window leaves the applied edit unsaved in the song's bank session.
                    guard self.isCurrent(window, service: service) else { return }
                    try await edit.group.save()
                } else {
                    try Self.writeKitChildren(
                        projectRoot: root, name: name, zones: zones, mode: mode, symbols: sliceSymbols)
                    if mode == .keysplit {
                        try Self.writeKeysplitTable(
                            projectRoot: root, name: "keysplit_" + name, zones: zones)
                    }
                }
                guard self.isCurrent(window, service: service) else { return }
                _ = await session.refreshVoicegroupCatalog()
                guard self.isCurrent(window, service: service) else { return }
                session.voiceList.refreshRetainedGroups()
                state.markClean()
                saveSucceeded = true
            } catch {
                guard self.isCurrent(window, service: service) else { return }
                session.voiceList.refreshRetainedGroups()
                self.showAlert(error)
            }
        }
        setSave(.writing(task, names: names), on: window)
    }

    private func setSave(_ save: KitStudioWindow.Save, on window: KitStudioWindow) {
        window.save = save
        if self.window === window { publishSave() }
    }

    /// Projects the current window's save onto the bridged `saving` flag and overwrite prompt.
    private func publishSave() {
        switch window?.save ?? .idle {
        case .idle:
            saving = false
            overwritePromptOpen = false
            overwritePromptText = ""
        case .confirmingOverwrite(let prompt):
            saving = false
            overwritePromptOpen = true
            overwritePromptText = prompt
        case .writing:
            saving = true
            overwritePromptOpen = false
            overwritePromptText = ""
        }
    }

    private static func sampleFileExists(projectRoot: String, name: String) -> Bool {
        for ext in [".wav", ".bin", ".aif"] {
            if ProjectFileStore.exists(projectRoot + "/sound/direct_sound_samples/" + name + ext) { return true }
        }
        return false
    }

    /// Writes a studio-created resource; edits of an assigned kit use its session.
    private static func writeKitChildren(
        projectRoot: String, name: String, zones: [KitZone], mode: KitMode, symbols: [String: String]
    ) throws {
        var children = KitDraftCodec.children(from: zones, mode: mode)
        for index in children.indices {
            if let voiceName = children[index]?.symbol, let symbol = symbols[voiceName] {
                children[index]?.symbol = symbol
            }
        }
        let destination = VoicegroupLocation(
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
        guard try source.save() else {
            throw VoicegroupStoreError.operationFailed("Cannot save \(path): edit superseded.")
        }
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
        if let window, case .writing(let task, _) = window.save {
            closeWaitTask = Task { [weak self] in
                await task.value
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
            source: source, dirty: window?.presenter.dirty ?? false,
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
                self.finishOrphanCleanup()
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
        closeGuard.request(source: .window, dirty: window?.presenter.dirty ?? false) { [weak self] in self?.close() }
    }
    public func answerPrompt(answer: Int) { closeGuard.answer(answer) }
    @QtIgnored public func close() {
        stopAudition()
        windowOpen = false
        pickerRequested = false
    }
    public func windowReleased() {
        guard !windowOpen else { return }
        loadTask?.cancel()
        loadTask = nil
        closeWaitTask?.cancel()
        closeWaitTask = nil
        replaceWindow(nil)
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
