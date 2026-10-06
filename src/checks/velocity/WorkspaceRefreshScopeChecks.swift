import Foundation
import PorydawApp
import PorydawCore
import PorydawDocument

let workspaceRefreshScopeID = "swiftcore/DocumentWorkspace::refreshScope"

/// The fan-out rebuilds only presenters whose stamps moved: a note move reaches the
/// velocity page but not automation or headers; a lane edit reaches automation only;
/// a program change reaches velocity and headers. Undo retraces the same scope.
@MainActor
func workspaceRefreshScope(
    _ report: CheckReport, session: DocumentSession, service: ProjectService
) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let document = fixture.document
    let audio: NativeAudio
    do {
        audio = try runBlocking { try await NativeAudio() }
    } catch {
        report.fail(workspaceRefreshScopeID, "cannot create audio: \(error)")
        return
    }
    let presenters = WorkspacePresenterFixture(
        viewport: fixture.viewport, audio: audio,
        callbacks: DocumentWorkspace.Callbacks(
            changeTrackVoiceRequested: { _ in },
            revealTrackVoiceRequested: { _ in },
            gridCommandAvailabilityChanged: {}, sessionStateChanged: {},
            publicationFailed: { _ in }, timeSignaturePromptInvalidated: { _, _ in }))
    let workspace = presenters.workspace
    defer {
        workspace.teardown()
        withExtendedLifetime((audio, presenters)) {}
    }
    workspace.activate()
    workspace.velocityPage.configureBody(
        width: 400, height: 120, rulerWidth: 56, devicePixelRatio: 1, baseFontPx: 13, dragDistance: 10)
    workspace.automationPage.configureBody(
        width: 400, height: 120, gutter: 56, devicePixelRatio: 1, baseFontPx: 13, dragDistance: 10)
    let mapping = document.engineTracks.tracks[0]
    guard let chunk = mapping.midiChunk else {
        report.fail(workspaceRefreshScopeID, "track 0 has no chunk")
        return
    }
    let channel = mapping.channel

    struct Rebuilt: Equatable {
        var velocity: Bool
        var automation: Bool
        var headers: Bool
    }
    var last = (
        workspace.velocityPage.contentBuildCount, workspace.automationPage.contentBuildCount,
        workspace.trackHeaders.contentBuildCount
    )
    func rebuilt(after action: () -> Void) -> Rebuilt {
        action()
        let now = (
            workspace.velocityPage.contentBuildCount, workspace.automationPage.contentBuildCount,
            workspace.trackHeaders.contentBuildCount
        )
        defer { last = now }
        return Rebuilt(velocity: now.0 != last.0, automation: now.1 != last.1, headers: now.2 != last.2)
    }
    let noteMove = rebuilt { document.moveNotes([fixture.notes[0].id], byTicks: 24, byKeys: 0) }
    let laneEdit = rebuilt {
        document.insertRawEvent(
            chunk: chunk, event: .channel(tick: 10, status: 0xB0 | channel, data0: 7, data1: 100))
    }
    let programChange = rebuilt {
        document.insertRawEvent(
            chunk: chunk, event: .channel(tick: 10, status: 0xC0 | channel, data0: 5, data1: 0))
    }
    let undoProgram = rebuilt { _ = document.history.undoDocument() }
    let undoLane = rebuilt { _ = document.history.undoDocument() }
    let undoNote = rebuilt { _ = document.history.undoDocument() }

    let noteScope = Rebuilt(velocity: true, automation: false, headers: false)
    let laneScope = Rebuilt(velocity: false, automation: true, headers: false)
    let voiceScope = Rebuilt(velocity: true, automation: false, headers: true)
    report.expect(
        noteMove == noteScope, cppID: workspaceRefreshScopeID,
        message: "a note move rebuilds the velocity page only: \(noteMove)")
    report.expect(
        laneEdit == laneScope, cppID: workspaceRefreshScopeID,
        message: "a lane edit rebuilds the automation page only: \(laneEdit)")
    report.expect(
        programChange == voiceScope, cppID: workspaceRefreshScopeID,
        message: "a program change rebuilds velocity and headers, not automation: \(programChange)")
    report.expect(
        undoProgram == voiceScope && undoLane == laneScope && undoNote == noteScope,
        cppID: workspaceRefreshScopeID,
        message: "undo retraces each edit's refresh scope: \(undoProgram) \(undoLane) \(undoNote)")
}
