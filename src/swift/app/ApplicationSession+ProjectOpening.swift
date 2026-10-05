import Foundation
import PorydawCore
import PorydawProject
import QtBridge
import PorydawAppAudio
import PorydawAppCommands

@MainActor
extension ApplicationSession {
    /// An opened project waiting to replace the current one. Song registration
    /// and voice editor catalogs are populated after its first tab opens.
    struct ProjectSwitchCandidate {
        let path: String
        let label: String?
        let restore: WorkspaceTabRecipe?
        let service: ProjectService
        let labels: [String]
        let song: PrefetchedSongLoad?
    }

    /// Restores a saved recipe unless a deliberate open already won.
    @QtIgnored
    func restoreStartup(recipe: WorkspaceTabRecipe) {
        guard persistenceConfigured, !deliberateOpenRequested, !isDisposed, !recipe.projectPath.isEmpty
        else { return }
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

    /// Takes the pre-Qt read before the shell can close or request another project.
    @QtIgnored
    func adoptStartupPrefetch() {
        guard let parked = StartupPrefetch.parked else { return }
        StartupPrefetch.parked = nil
        prefetchedProject = parked
        songDock.songsLoading = true
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
        if let prefetched = prefetchedProject, prefetched.selection.path == path {
            prefetchedProject = nil
            read = prefetched.read
        } else {
            discardPrefetchedProject()
            let song = label ?? restore?.startupSong
            read = Task { @concurrent in try await ProjectRead.load(path: path, song: song) }
        }
        let replacement = Task { [weak self] in
            _ = await priorTask?.value
            let loaded: ProjectRead
            do {
                loaded = try await read.value
            } catch {
                guard let self, !Task.isCancelled else {
                    Task { [read] in
                        if let loaded = try? await read.value { await loaded.service.close() }
                    }
                    return
                }
                if restore != nil, self.persistenceConfigured {
                    EditorViewStateCodec.saveTabs(
                        WorkspaceTabRecipe(projectPath: path, orderedSongs: [], selectedSong: ""),
                        store: self.preferences)
                }
                self.failOpen(String(describing: error))
                self.songDock.songsLoading = false
                return
            }
            guard let self, !self.isDisposed, !Task.isCancelled else {
                await loaded.service.close()
                return
            }
            self.publishLastSaveError("")
            let candidate = ProjectSwitchCandidate(
                path: path, label: label, restore: restore, service: loaded.service,
                labels: loaded.labels, song: loaded.song)
            self.pendingProjectSwitch = candidate
            self.songTabs.startProjectSwitchCloseAll()
        }
        activeReplacementTask = replacement
        if restore != nil { startupRestoreTask = replacement }
    }

    func failOpen(_ message: String) {
        publishLastSaveError(message)
        publishOpenFailure(message: message)
    }

    func finishProjectSwitch(_ candidate: ProjectSwitchCandidate) async {
        closeSampleStudio()
        isReplacingProject = true
        await releaseTabs()
        await catalogService?.close()
        guard !isDisposed, !Task.isCancelled else {
            isReplacingProject = false
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
        resetVoicegroupCatalog()
        projectOpen = true
        onProjectStateChanged?()
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
        isReplacingProject = false
        if candidate.restore == nil { persistTabRecipe() }
        populateProjectCatalogs(for: candidate.service)
    }

    private func populateProjectCatalogs(for service: ProjectService) {
        Task { [weak self] in
            do {
                let songs = try await service.songs()
                guard let self, !self.isDisposed, self.pendingProjectSwitch == nil,
                    self.catalogService === service
                else { return }
                if self.songDock.presenter.songListings.isEmpty {
                    self.songDock.publishSongs(songs)
                }
                self.songDock.songsLoading = false
                _ = await self.refreshVoicegroupCatalog()
            } catch {
                guard let self, !self.isDisposed, self.pendingProjectSwitch == nil,
                    self.catalogService === service
                else { return }
                self.publishOperationFailure(message: String(describing: error))
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
        let service = ProjectService()
        do {
            try await service.open(root: path)
            let labels = try await service.songLabels()
            var song: PrefetchedSongLoad?
            if let label, !label.isEmpty, labels.contains(label),
                let loaded = try? await service.openSong(label: label),
                let file = try? MidiFile.decode(loaded.midiBytes)
            {
                song = PrefetchedSongLoad(label: label, loaded: loaded, file: file)
            }
            return ProjectRead(service: service, labels: labels, song: song)
        } catch {
            await service.close()
            throw error
        }
    }
}
