import PorydawApp
import PorydawAppPresentation
import PorydawDocument

@MainActor
public struct WorkspacePresenterFixture {
    public let playhead: SharedPlayheadPresenter
    public let guides: PlayheadGuidesPresenter
    public let eventList: EventListPresenter
    public let workspace: DocumentWorkspace

    public init(
        viewport: DocumentViewport, audio: NativeAudio,
        callbacks: DocumentWorkspace.Callbacks
    ) {
        playhead = SharedPlayheadPresenter()
        guides = PlayheadGuidesPresenter()
        eventList = EventListPresenter()
        workspace = DocumentWorkspace(
            viewport: viewport, audio: audio, playhead: playhead,
            playheadGuides: guides, eventList: eventList, palette: GridPalette(),
            typography: Typography(baseFontPx: 13), callbacks: callbacks)
    }
}
