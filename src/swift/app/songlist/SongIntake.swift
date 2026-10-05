// Resolves the weak owners at each publication, preserving the controller's async lifetime.
@MainActor
func registerImportedSong(
    request: SongImportRequest, service: ProjectService,
    dock: @autoclosure () -> SongDockController?, session: @autoclosure () -> ApplicationSession?,
    isCurrent: () -> Bool, failurePrelude: (@MainActor (Error) async -> Void)? = nil
) async {
    do {
        let id = try await service.importSong(request)
        guard !Task.isCancelled, isCurrent() else { return }
        let songs = try await service.songs()
        guard !Task.isCancelled, isCurrent() else { return }
        dock()?.publishSongs(songs)
        session()?.publishStatusMessage(message: "Created and registered \(request.label) (song ID \(id))")
        if request.createVoicegroup {
            _ = await session()?.refreshVoicegroupCatalog()
            guard !Task.isCancelled, isCurrent() else { return }
            session()?.openSongFromDock(label: request.label, newTab: true)
        }
    } catch {
        guard !Task.isCancelled, isCurrent() else { return }
        if let failurePrelude {
            await failurePrelude(error)
            guard !Task.isCancelled, isCurrent() else { return }
        } else {
            session()?.publishOperationFailure(message: String(describing: error))
        }
        if let songs = try? await service.songs() {
            guard !Task.isCancelled, isCurrent() else { return }
            dock()?.publishSongs(songs)
        }
        if request.createVoicegroup {
            _ = await session()?.refreshVoicegroupCatalog()
            guard !Task.isCancelled, isCurrent() else { return }
        }
    }
}
