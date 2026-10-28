import Foundation
import PorydawCore
import PorydawDocument
import PorydawProject
import PorydawNativeHost
import QtBridge
import PorydawAppAudio
import PorydawAppCommands
import PorydawAppPresentation

@MainActor
extension ApplicationSession {
    enum ProjectOpeningStage: Int {
        case idle, readingProject, openingSongs, indexingInstruments
    }

    /// An opened project waiting to replace the current one. Song registration
    /// and voice editor catalogs are populated after its first tab opens.
    struct ProjectSwitchCandidate {
        let path: String
        let generation: UInt64
        let label: String?
        let restore: WorkspaceTabRecipe?
        let service: ProjectService
        let labels: [String]
        let song: PrefetchedSongLoad?
    }

    private func beginProjectOpening() -> UInt64 {
        projectOpeningGeneration += 1
        publishLastSaveError("")
        projectOpeningStage = ProjectOpeningStage.readingProject.rawValue
        return projectOpeningGeneration
    }

    private func setProjectOpeningStage(_ stage: ProjectOpeningStage, generation: UInt64) {
        guard generation == projectOpeningGeneration, projectOpeningStage != 0, !isDisposed else { return }
        projectOpeningStage = stage.rawValue
    }

    @QtIgnored
    func finishProjectOpening(generation: UInt64) {
        guard generation == projectOpeningGeneration else { return }
        projectOpeningStage = ProjectOpeningStage.idle.rawValue
    }

    @QtIgnored
    func restoreStartup() {
        guard persistenceConfigured, !deliberateOpenRequested, !isDisposed else { return }
        let recipe = EditorViewStatePreferences.loadTabs(store: preferences)
        guard !recipe.projectPath.isEmpty else { return }
        startProjectSwitch(path: recipe.projectPath, label: nil, restore: recipe)
    }

    func requestProjectSwitch(path: String, label: String?) {
        deliberateOpenRequested = true
        // A deliberate open wins over a recipe still loading in the background.
        startupRestoreTask?.cancel()
        startupRestoreTask = nil
        if let pending = pendingProjectSwitch, pending.restore != nil {
            pendingProjectSwitch = nil
            Task { await pending.service.close() }
        }
        startProjectSwitch(path: path, label: label, restore: nil)
    }

    /// Starts the saved-project (and named-song) read during QML construction.
    /// The read never touches MainActor state; adoption still goes through
    /// restoreStartup/openStartup after chrome is restored.
    @QtIgnored
    func prefetchStartup(arguments: [String]) {
        guard prefetchedProject == nil, !isDisposed else { return }
        let cli = parseStartupArguments(arguments)
        let recipe = EditorViewStatePreferences.loadTabs(store: preferences)
        let path = cli.project.isEmpty ? recipe.projectPath : cli.project
        guard !path.isEmpty else { return }
        songDock.songsLoading = true
        let generation = beginProjectOpening()
        let song = startupSongChoice(
            label: cli.song.isEmpty ? nil : cli.song,
            selected: recipe.selectedSong, ordered: recipe.orderedSongs)
        prefetchedProject = (
            path, generation, Task { @concurrent in try await ProjectRead.load(path: path, song: song) }
        )
    }

    /// The one startup song worth opening off-main: the explicit label, else
    /// the recipe's selected song, else its first ordered song.
    private func startupSongChoice(label: String?, selected: String, ordered: [String]) -> String? {
        if let label, !label.isEmpty { return label }
        if !selected.isEmpty { return selected }
        return ordered.first
    }

    /// Takes the prefetched startup song when it matches this open exactly:
    /// same label on the same adopted service. Anything else loads as usual,
    /// and the untaken value drops with its bank lease like a failed open.
    @QtIgnored
    func takePrefetchedSong(label: String, service: ProjectService) -> PrefetchedSongLoad? {
        guard let prefetched = prefetchedSong, prefetched.service === service,
            prefetched.load.label == label
        else { return nil }
        prefetchedSong = nil
        return prefetched.load
    }

    /// Drops a startup prefetch that never reached a project switch (host
    /// closed before chrome restored), closing its service once the read
    /// settles. Reads adopted by a switch are unaffected (already nil).
    @QtIgnored
    func discardPrefetchedProject() {
        guard let prefetched = prefetchedProject else { return }
        prefetchedProject = nil
        finishProjectOpening(generation: prefetched.generation)
        Task { @concurrent in
            guard let loaded = try? await prefetched.read.value else { return }
            await loaded.service.close()
        }
    }

    private func startProjectSwitch(
        path: String, label: String?,
        restore: WorkspaceTabRecipe?
    ) {
        if songDock.presenter.songListings.isEmpty { songDock.songsLoading = true }
        let priorTask = activeReplacementTask
        prefetchedSong = nil
        let read: Task<ProjectRead, Error>
        let generation: UInt64
        if let prefetched = prefetchedProject, prefetched.path == path {
            prefetchedProject = nil
            read = prefetched.read
            generation = prefetched.generation
        } else {
            discardPrefetchedProject()
            generation = beginProjectOpening()
            let song = startupSongChoice(
                label: label, selected: restore?.selectedSong ?? "",
                ordered: restore?.orderedSongs ?? [])
            read = Task { @concurrent in try await ProjectRead.load(path: path, song: song) }
        }
        let replacement = Task { [weak self] in
            _ = await priorTask?.value
            let loaded: ProjectRead
            do {
                loaded = try await read.value
            } catch {
                self?.finishProjectOpening(generation: generation)
                guard let self, !Task.isCancelled else {
                    Task { [read] in
                        if let loaded = try? await read.value { await loaded.service.close() }
                    }
                    return
                }
                if restore != nil, self.persistenceConfigured {
                    EditorViewStatePreferences.saveTabs(
                        WorkspaceTabRecipe(projectPath: path, orderedSongs: [], selectedSong: ""),
                        store: self.preferences)
                }
                self.failOpen(String(describing: error))
                self.songDock.songsLoading = false
                return
            }
            guard let self, !self.isDisposed, !Task.isCancelled else {
                self?.finishProjectOpening(generation: generation)
                await loaded.service.close()
                return
            }
            self.publishLastSaveError("")
            let candidate = ProjectSwitchCandidate(
                path: path, generation: generation, label: label, restore: restore, service: loaded.service,
                labels: loaded.labels, song: loaded.song)
            self.pendingProjectSwitch = candidate
            self.guardSplitStudioClose(
                proceed: { [weak self] in self?.songTabs.startProjectSwitchCloseAll() },
                cancel: { [weak self] in self?.closeAllResolved(closed: false) })
        }
        activeReplacementTask = replacement
        if restore != nil { startupRestoreTask = replacement }
    }

    func failOpen(_ message: String) {
        publishLastSaveError(message)
        publishOpenFailure(message: message)
    }

    func finishProjectSwitch(_ candidate: ProjectSwitchCandidate) async {
        pd_startup_trace_mark("project-switch-begin")
        defer { pd_startup_trace_mark("project-switch-end") }
        setProjectOpeningStage(.openingSongs, generation: candidate.generation)
        closeSampleStudio()
        isReplacingProject = true
        pd_startup_trace_mark("project-release-begin")
        voiceList.releaseVoicegroup()
        setEditingVoicegroup(enabled: false)
        await releaseTabs()
        await catalogService?.close()
        pd_startup_trace_mark("project-release-end")
        guard !isDisposed, !Task.isCancelled else {
            isReplacingProject = false
            finishProjectOpening(generation: candidate.generation)
            await candidate.service.close()
            return
        }
        catalogService = candidate.service
        if let song = candidate.song {
            prefetchedSong = (candidate.service, song)
        }
        projectRoot = candidate.path
        songDock.install(service: candidate.service, songs: [])
        voiceList.projectService = candidate.service
        songTabs.setClosingAll(false)
        resetVoicegroupCatalog()
        projectOpen = true
        onProjectStateChanged?()
        pd_startup_trace_mark("project-restore-tabs-begin")
        if let recipe = candidate.restore {
            let restored = recipe.normalized(available: candidate.labels)
            isRestoringTabs = true
            for song in restored.orderedSongs {
                guard !Task.isCancelled else { break }
                await openTab(label: song, at: nil)
            }
            if let selected = songTabs.tab(label: restored.selectedSong) {
                songTabs.selectTab(tabId: selected.tabId)
            }
            isRestoringTabs = false
            // A saved name the project no longer publishes is not a playable
            // song: the available tabs still restore, and each missing name
            // is reported like the fork's Reconcile failure instead of
            // failing the restore.
            let playable = Set(candidate.labels)
            var reported = Set<String>()
            for song in recipe.orderedSongs
            where !song.isEmpty && !playable.contains(song) && reported.insert(song).inserted {
                publishOperationFailure(message: "Song \(song) is not a playable song in this project.")
            }
        } else if let label = candidate.label {
            isReplacingProject = false
            await openTab(label: label, at: nil)
        }
        pd_startup_trace_mark("project-restore-tabs-end")
        isReplacingProject = false
        if candidate.restore == nil { persistTabRecipe() }
        populateProjectCatalogs(for: candidate.service, generation: candidate.generation)
    }

    private func populateProjectCatalogs(for service: ProjectService, generation: UInt64) {
        setProjectOpeningStage(.indexingInstruments, generation: generation)
        Task { [weak self] in
            defer { self?.finishProjectOpening(generation: generation) }
            pd_startup_trace_mark("project-catalogs-begin")
            defer { pd_startup_trace_mark("project-catalogs-end") }
            do {
                pd_startup_trace_mark("project-song-listings-begin")
                let songs = try await service.songs()
                pd_startup_trace_mark("project-song-listings-end")
                guard let self, !self.isDisposed, self.pendingProjectSwitch == nil,
                    self.catalogService === service
                else { return }
                if self.songDock.presenter.songListings.isEmpty {
                    self.songDock.publishSongs(songs)
                }
                self.songDock.songsLoading = false
                pd_startup_trace_mark("project-instrument-catalog-begin")
                _ = await self.refreshVoicegroupCatalog()
                pd_startup_trace_mark("project-instrument-catalog-end")
            } catch {
                guard let self, !self.isDisposed, self.pendingProjectSwitch == nil,
                    self.catalogService === service
                else { return }
                self.publishOperationFailure(message: String(describing: error))
                pd_startup_trace_mark("project-catalogs-failed")
                self.songDock.songsLoading = false
            }
        }
    }
}

/// One startup song opened and decoded off the main actor. The bank lease is
/// owned: dropping the value releases it, the same as a failed open.
struct PrefetchedSongLoad: Sendable {
    let label: String
    let loaded: LoadedSong
    let file: MidiFile
}

/// A project read that never touches MainActor state: the service, its song
/// labels, and the named startup song already opened and decoded. The song
/// load is best-effort — a stale recipe name still restores the other tabs.
struct ProjectRead: Sendable {
    let service: ProjectService
    let labels: [String]
    let song: PrefetchedSongLoad?

    static func load(path: String, song label: String?) async throws -> ProjectRead {
        pd_startup_trace_mark("project-read-begin")
        defer { pd_startup_trace_mark("project-read-end") }
        let service = ProjectService()
        do {
            pd_startup_trace_mark("project-store-open-begin")
            try await service.open(root: path)
            pd_startup_trace_mark("project-store-open-end")
            pd_startup_trace_mark("project-song-labels-begin")
            let labels = try await service.songLabels()
            pd_startup_trace_mark("project-song-labels-end")
            var song: PrefetchedSongLoad?
            pd_startup_trace_mark("project-startup-song-begin")
            if let label, !label.isEmpty, labels.contains(label),
                let loaded = try? await service.openSong(label: label),
                let file = try? MidiFile.decode(loaded.midiBytes)
            {
                song = PrefetchedSongLoad(label: label, loaded: loaded, file: file)
            }
            pd_startup_trace_mark("project-startup-song-end")
            return ProjectRead(service: service, labels: labels, song: song)
        } catch {
            pd_startup_trace_mark("project-read-failed")
            await service.close()
            throw error
        }
    }
}

/// Startup CLI selection shared by prefetch and open: `--project` wins;
/// a lone `--song` uses the saved project, and empty means plain restore.
func parseStartupArguments(_ arguments: [String]) -> (project: String, song: String) {
    var project = ""
    var song = ""
    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        if argument == "--project" || argument == "--song" {
            if index + 1 < arguments.count {
                index += 1
                if argument == "--project" { project = arguments[index] } else { song = arguments[index] }
            }
        } else if argument.hasPrefix("--project=") {
            project = String(argument.dropFirst("--project=".count))
        } else if argument.hasPrefix("--song=") {
            song = String(argument.dropFirst("--song=".count))
        }
        index += 1
    }
    return (project, song)
}
