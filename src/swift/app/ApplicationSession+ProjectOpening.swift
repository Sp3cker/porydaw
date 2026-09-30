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
    }

    @QtIgnored
    func restoreStartup() {
        guard persistenceConfigured else { return }
        let recipe = EditorViewStateCodec.loadTabs(store: preferences)
        guard !recipe.projectPath.isEmpty else { return }
        startProjectSwitch(path: recipe.projectPath, label: nil, restore: recipe)
    }

    func requestProjectSwitch(path: String, label: String?) {
        // A deliberate open wins over a recipe still loading in the background.
        startupRestoreTask?.cancel()
        startupRestoreTask = nil
        if let pending = pendingProjectSwitch, pending.restore != nil {
            pendingProjectSwitch = nil
            Task { await pending.service.close() }
        }
        startProjectSwitch(path: path, label: label, restore: nil)
    }

    private struct ProjectRead: Sendable {
        let service: ProjectService
        let labels: [String]

        static func load(path: String) async throws -> ProjectRead {
            let service = ProjectService()
            do {
                try await service.open(root: path)
                let labels = try await service.songLabels()
                return ProjectRead(service: service, labels: labels)
            } catch {
                await service.close()
                throw error
            }
        }
    }

    private func startProjectSwitch(path: String, label: String?,
                                    restore: WorkspaceTabRecipe?) {
        let priorTask = activeReplacementTask
        let read = Task { @concurrent in try await ProjectRead.load(path: path) }
        let replacement = Task { [weak self] in
            _ = await priorTask?.value
            let loaded: ProjectRead
            do {
                loaded = try await read.value
            } catch {
                guard let self, !Task.isCancelled else { return }
                if restore != nil, self.persistenceConfigured {
                    EditorViewStateCodec.saveTabs(
                        WorkspaceTabRecipe(projectPath: path, orderedSongs: [], selectedSong: ""),
                        store: self.preferences)
                }
                self.failOpen(String(describing: error))
                return
            }
            guard let self, !self.isDisposed, !Task.isCancelled else {
                await loaded.service.close()
                return
            }
            self.lastSaveError = ""
            let candidate = ProjectSwitchCandidate(
                path: path, label: label, restore: restore, service: loaded.service,
                labels: loaded.labels)
            self.pendingProjectSwitch = candidate
            self.songTabs.startProjectSwitchCloseAll()
        }
        activeReplacementTask = replacement
        if restore != nil { startupRestoreTask = replacement }
    }

    func failOpen(_ message: String) {
        lastSaveError = message
        openFailed(message: message)
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
        projectRoot = candidate.path
        projectRootChanged()
        labels = candidate.labels
        songDock.install(service: candidate.service, songs: [])
        voiceList.projectService = candidate.service
        resetVoicegroupCatalog()
        projectOpen = true
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
                operationFailed(message: "Song \(song) is not a playable song in this project.")
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
                    self.songDock.presenter.setSongs(songs)
                    self.songDock.syncSelection()
                }
                _ = await self.refreshVoicegroupCatalog()
            } catch {
                guard let self, !self.isDisposed, self.pendingProjectSwitch == nil,
                    self.catalogService === service
                else { return }
                self.operationFailed(message: String(describing: error))
            }
        }
    }
}
