import PorydawApp
import PorydawCore
import PorydawDocument

@MainActor
public func makeSyntheticSession(
    suite: DocumentSession, service: ProjectService, file: MidiFile,
    sampleRate: Double = 48_000, config: SongConfig? = nil
) -> DocumentSession {
    let document = SongDocument(
        file: file, config: config ?? suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    return DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName, sampleRate: sampleRate)
}
