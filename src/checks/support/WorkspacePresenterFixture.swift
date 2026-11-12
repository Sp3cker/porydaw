import Foundation
@testable import PorydawPluginHost
import PorydawApp
import PorydawAppPresentation
import PorydawDocument

@MainActor
public struct WorkspacePresenterFixture {
    public let playhead: SharedPlayheadPresenter
    public let guides: PlayheadGuidesPresenter
    public let eventList: EventListPresenter
    public let workspace: DocumentWorkspace
    let catalog: PluginCatalog
    let catalogDirectory: URL

    public init(
        viewport: DocumentViewport, audio: NativeAudio,
        callbacks: DocumentWorkspace.Callbacks
    ) {
        playhead = SharedPlayheadPresenter()
        guides = PlayheadGuidesPresenter()
        eventList = EventListPresenter()
        catalogDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "porydaw-workspace-catalog-\(UUID().uuidString)", isDirectory: true)
        catalog = PluginCatalog(
            cacheDirectory: catalogDirectory, scannerURL: HelperProcess.executableURL, standardRoots: [])
        workspace = DocumentWorkspace(
            viewport: viewport, audio: audio, pluginCatalog: catalog, preferences: PreferencesStore(),
            playhead: playhead,
            playheadGuides: guides, eventList: eventList, palette: GridPalette(),
            typography: Typography(baseFontPx: 13), callbacks: callbacks)
    }
}
