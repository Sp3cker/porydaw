import Foundation

// Demo fixture for the standalone prototype: a lead line on track 0 and a
// ghosted harmony on track 1 (mus_route101-shaped). Runtime fixture data, not
// a test-only dependency — the app boots into this song.
enum GridFixture {
    static let firstNoteId = 1
    static let nextNoteId = 31

    @MainActor
    static func makeNotes() -> [GridNote] {
        let leadPitch = [60, 64, 67, 71, 74, 71, 67, 64, 60, 64, 67, 71, 74, 71, 67]
        let ghostPitch = [48, 55, 52, 57, 50, 57, 52, 55, 48, 55, 52, 57, 50, 57, 52]
        var fixture: [GridNote] = []
        fixture.reserveCapacity(30)
        for i in 0..<15 {
            fixture.append(
                GridNote(
                    noteId: i + 1, tick: 24 * i, duration: 18,
                    pitch: leadPitch[i], track: 0,
                    velocity: [98, 104, 110][i % 3], ghost: false))
        }
        for i in 0..<15 {
            fixture.append(
                GridNote(
                    noteId: 16 + i, tick: 12 + 24 * i, duration: 18,
                    pitch: ghostPitch[i], track: 1,
                    velocity: [86, 92, 98][i % 3], ghost: true))
        }
        return fixture
    }
}
