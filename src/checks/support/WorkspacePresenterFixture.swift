import PorydawApp
import PorydawDocument

@MainActor
struct WorkspacePresenterFixture {
    let playhead: SharedPlayheadPresenter
    let guides: PlayheadGuidesPresenter
    let eventList: EventListPresenter
    let workspace: DocumentWorkspace

    init(
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
