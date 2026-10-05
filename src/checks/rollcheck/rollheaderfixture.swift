import PorydawApp

@MainActor
func makeRollHeaderFixture(
    session: DocumentSession, viewport: (width: Double, height: Double)? = nil
) -> TrackHeadersPresenter {
    let headers = TrackHeadersPresenter()
    headers.attach(session: session, palette: GridPalette())
    if let viewport {
        headers.configureViewport(
            width: viewport.width, height: viewport.height, fontPx: 13, dpr: 1)
    }
    return headers
}
