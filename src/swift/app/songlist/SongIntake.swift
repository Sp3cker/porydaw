import PorydawDocument
// Resolves the weak owners at each publication, preserving the controller's async lifetime.
@MainActor
@discardableResult
func registerImportedSong(
    request: SongImportRequest, service: ProjectService,
    dock: @autoclosure () -> SongDockController?, session: @autoclosure () -> ApplicationSession?,
    isCurrent: () -> Bool, openInNewTab: Bool = false,
    failurePrelude: (@MainActor (Error) async -> Void)? = nil
) async -> Bool {
    do {
        let id = try await service.importSong(request)
        guard !Task.isCancelled, isCurrent() else { return false }
        let songs = try await service.songs()
        guard !Task.isCancelled, isCurrent() else { return false }
        dock()?.publishSongs(songs)
        session()?.publishStatusMessage(message: "Created and registered \(request.label) (song ID \(id))")
        if request.createVoicegroup {
            _ = await session()?.refreshVoicegroupCatalog()
            guard !Task.isCancelled, isCurrent() else { return false }
            session()?.openSongFromDock(label: request.label, newTab: true)
        } else if openInNewTab {
            session()?.openSongFromDock(label: request.label, newTab: true)
        }
        return true
    } catch {
        guard !Task.isCancelled, isCurrent() else { return false }
        if let failurePrelude {
            await failurePrelude(error)
            guard !Task.isCancelled, isCurrent() else { return false }
        } else {
            session()?.publishOperationFailure(message: String(describing: error))
        }
        if let songs = try? await service.songs() {
            guard !Task.isCancelled, isCurrent() else { return false }
            dock()?.publishSongs(songs)
        }
        if request.createVoicegroup {
            _ = await session()?.refreshVoicegroupCatalog()
            guard !Task.isCancelled, isCurrent() else { return false }
        }
        return false
    }
}
