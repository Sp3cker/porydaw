import Foundation
@testable import PorydawApp
@testable import PorydawAppPresentation
import PorydawCore
@testable import PorydawDocument
import SwiftCoreCheckLogic

// Existing scenarios paired with tst_automationdomain.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationParameterCatalogAndMetadata(_ report: CheckReport) {
    let catalog = AutomationCatalog.parameters(track: 0)
    report.expectEqual(
        expected: AutomationCatalog.count, actual: catalog.count, cppID: drawerAutomationCatalogID,
        what: "the catalog carries every supported parameter plus Tempo")
    report.expectEqual(
        expected: [
            TimeDefaults.ccVolume, TimeDefaults.ccPan, TimeDefaults.ccModulation,
            TimeDefaults.laneCCBend, TimeDefaults.ccLFOSpeed, TimeDefaults.ccBendRange,
            Xcmd.echoVolumeLane, Xcmd.echoLengthLane, TimeDefaults.ccModulationType,
            TimeDefaults.ccFineTune, TimeDefaults.ccLFODelay,
        ], actual: AutomationCatalog.controllers, cppID: drawerAutomationCatalogID,
        what: "the supported parameters keep the production selector order")
    report.expectEqual(
        expected: AutomationParameter.tempo, actual: catalog.last, cppID: drawerAutomationCatalogID,
        what: "Tempo closes the selector order")
    report.expectEqual(
        expected: 6,
        actual: AutomationCatalog.index(
            of: .controlChange(
                track: 0, controller: Xcmd.echoVolumeLane), track: 0) ?? -1, cppID: drawerAutomationCatalogID,
        what: "an XCMD row sits after the plain parameter group")
    report.expect(
        AutomationCatalog.index(of: .tempo, track: 0) == AutomationCatalog.count - 1,
        cppID: drawerAutomationCatalogID, message: "Tempo is the last catalog index")
    report.expectEqual(
        expected: Optional(0),
        actual: AutomationParameter.controlChange(
            track: 0,
            controller: TimeDefaults.ccVolume
        ).track,
        cppID: drawerAutomationCatalogID, what: "a control-change parameter keeps its track scope")
    report.expectEqual(
        expected: Optional(.pitchBend), actual: AutomationParameter.pitchBend(track: 0).lane,
        cppID: drawerAutomationCatalogID, what: "Pitch bend names the document's bend lane")
    report.expect(
        AutomationParameter.tempo.isTempo && AutomationParameter.tempo.lane == nil
            && AutomationParameter.tempo.track == nil,
        cppID: drawerAutomationCatalogID,
        message: "Tempo is song-global: no track and no document lane")
    report.expectEqual(
        expected: "Volume",
        actual: AutomationCatalog.tabLabel(
            .controlChange(track: 0, controller: TimeDefaults.ccVolume)), cppID: drawerAutomationCatalogID,
        what: "the selector label is the lane name with no decoration")
    report.expectEqual(
        expected: "Volume (VOL)",
        actual: AutomationCatalog.title(
            .controlChange(track: 0, controller: TimeDefaults.ccVolume)), cppID: drawerAutomationCatalogID,
        what: "a classified parameter titles itself with its mnemonic")
    report.expectEqual(
        expected: "Echo volume (xIECV)",
        actual: AutomationCatalog.title(
            .controlChange(track: 0, controller: Xcmd.echoVolumeLane)), cppID: drawerAutomationCatalogID,
        what: "an XCMD row titles itself from its descriptor")
    report.expectEqual(
        expected: "Pitch bend (BEND)", actual: AutomationCatalog.title(.pitchBend(track: 0)),
        cppID: drawerAutomationCatalogID, what: "Pitch bend keeps its dedicated title")
    report.expectEqual(
        expected: "Tempo (BPM)", actual: AutomationCatalog.title(.tempo), cppID: drawerAutomationCatalogID,
        what: "Tempo's lane title names its unit")

    let volume = AutomationParameterMetadata(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccVolume))
    report.expectEqual(
        expected: 0, actual: volume.minimum, cppID: drawerAutomationCatalogID, what: "Volume's range starts at 0")
    report.expectEqual(
        expected: 127, actual: volume.maximum, cppID: drawerAutomationCatalogID, what: "Volume's range ends at 127")
    report.expect(
        volume.neutral == nil && volume.defaultValue == 127 && volume.projectsTickZero,
        cppID: drawerAutomationCatalogID,
        message: "Volume has no neutral, defaults to 127 and projects its tick-zero node")
    report.expectEqual(
        expected: "127", actual: volume.valueText(127), cppID: drawerAutomationCatalogID,
        what: "a plain controller formats as its raw value")
    let pan = AutomationParameterMetadata(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccPan))
    report.expectEqual(expected: 64, actual: pan.neutral, cppID: drawerAutomationCatalogID, what: "Pan's neutral is 64")
    report.expectEqual(
        expected: "c_v+0", actual: pan.valueText(64), cppID: drawerAutomationCatalogID,
        what: "Pan formats its neutral as a centered c_v value")
    report.expectEqual(
        expected: "c_v-4", actual: pan.valueText(60), cppID: drawerAutomationCatalogID,
        what: "Pan's formatting stays centered on 64")
    let bend = AutomationParameterMetadata(parameter: .pitchBend(track: 0))
    report.expectEqual(
        expected: -8192, actual: bend.minimum, cppID: drawerAutomationCatalogID, what: "Bend's range is signed")
    report.expectEqual(
        expected: 8191, actual: bend.maximum, cppID: drawerAutomationCatalogID, what: "Bend's range ends at 8191")
    report.expectEqual(
        expected: 0, actual: bend.neutral, cppID: drawerAutomationCatalogID, what: "Bend's neutral is zero")
    report.expectEqual(
        expected: "+8191", actual: bend.valueText(8191), cppID: drawerAutomationCatalogID,
        what: "Bend formats its positive extreme")
    report.expectEqual(
        expected: "-8192", actual: bend.valueText(-8192), cppID: drawerAutomationCatalogID,
        what: "Bend formats its negative extreme")
    let tempo = AutomationParameterMetadata(parameter: .tempo)
    report.expectEqual(
        expected: 20, actual: tempo.minimum, cppID: drawerAutomationCatalogID, what: "Tempo's range starts at 20 BPM")
    report.expectEqual(
        expected: 255, actual: tempo.maximum, cppID: drawerAutomationCatalogID, what: "Tempo's range ends at 255 BPM")
    report.expect(
        tempo.neutral == nil && tempo.defaultValue == 120, cppID: drawerAutomationCatalogID,
        message: "Tempo has no neutral and defaults to 120 BPM")
    report.expectEqual(
        expected: "150", actual: tempo.valueText(150), cppID: drawerAutomationCatalogID,
        what: "Tempo formats as plain BPM")
    let modType = AutomationParameterMetadata(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccModulationType))
    report.expectEqual(
        expected: 2, actual: modType.maximum, cppID: drawerAutomationCatalogID,
        what: "LFO type is bounded to its three modes")
    report.expectEqual(
        expected: 0, actual: AutomationCatalog.defaultRange(TimeDefaults.ccModulation),
        cppID: drawerAutomationCatalogID,
        what: "Modulation's default value window starts at 0")
    report.expectEqual(
        expected: 127, actual: AutomationCatalog.defaultRange(TimeDefaults.ccPan), cppID: drawerAutomationCatalogID,
        what: "every other zoomable parameter opens on the full window")
    report.expectEqual(
        expected: 16, actual: AutomationCatalog.autoRange(maximum: 9), cppID: drawerAutomationCatalogID,
        what: "auto range fits the smallest window to the data")
    report.expectEqual(
        expected: 32, actual: AutomationCatalog.autoRange(maximum: 20), cppID: drawerAutomationCatalogID,
        what: "auto range steps up with the data")
    report.expectEqual(
        expected: 64, actual: AutomationCatalog.autoRange(maximum: 60), cppID: drawerAutomationCatalogID,
        what: "auto range keeps a wider window for wider data")
    report.expectEqual(
        expected: 127, actual: AutomationCatalog.autoRange(maximum: 127), cppID: drawerAutomationCatalogID,
        what: "auto range keeps the full window for full data")

    let prompt = pan.prompt(storedValue: 64)
    report.expectEqual(
        expected: "Pan (PAN)", actual: prompt.title, cppID: drawerAutomationCatalogID,
        what: "the value prompt titles the lane")
    report.expectEqual(
        expected: "c_v value (0 = center):", actual: prompt.label, cppID: drawerAutomationCatalogID,
        what: "a centered parameter prompts in its displayed domain")
    report.expectEqual(
        expected: 0, actual: prompt.initialValue, cppID: drawerAutomationCatalogID,
        what: "the displayed value offsets the stored value by the midpoint")
    report.expectEqual(
        expected: -64, actual: prompt.minimum, cppID: drawerAutomationCatalogID,
        what: "the displayed domain is the stored domain less the offset")
    report.expectEqual(
        expected: 64, actual: pan.storedValue(prompted: 0), cppID: drawerAutomationCatalogID,
        what: "the prompt's displayed value maps back to the stored value")
    report.expectEqual(
        expected: 127, actual: pan.storedValue(prompted: 200), cppID: drawerAutomationCatalogID,
        what: "a stored value clamps into the parameter's domain")
    let bendPrompt = bend.prompt(storedValue: 0)
    report.expectEqual(
        expected: "Bend (0 = none):", actual: bendPrompt.label, cppID: drawerAutomationCatalogID,
        what: "Bend's zero-centered prompt keeps its production label")
    let tempoPrompt = tempo.prompt(storedValue: 120)
    report.expectEqual(
        expected: "Set tempo", actual: tempoPrompt.title, cppID: drawerAutomationCatalogID,
        what: "Tempo's prompt keeps its production title")
    report.expectEqual(
        expected: "BPM:", actual: tempoPrompt.label, cppID: drawerAutomationCatalogID,
        what: "Tempo's prompt labels its unit")
    report.expectEqual(
        expected: 0, actual: tempoPrompt.storedOffset, cppID: drawerAutomationCatalogID,
        what: "Tempo's prompt carries no stored offset")
}

@MainActor
func drawerAutomationLaneProjection(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(0, 127), (96, 64)],
        pan: [(24, 30), (24, 90), (120, 0)])

    // Empty lane: no points, no curve, and the parameter's own lead-in.
    let modulation = fixture.projection(fixture.modulationLane)
    report.expectEqual(
        expected: 0, actual: modulation.points.count, cppID: drawerAutomationProjectionID,
        what: "a lane the document never wrote projects no point")
    report.expectEqual(
        expected: 0, actual: modulation.segments.count, cppID: drawerAutomationProjectionID,
        what: "an empty lane projects no curve segment")
    report.expectEqual(
        expected: 0, actual: modulation.leadIn?.value ?? -1, cppID: drawerAutomationProjectionID,
        what: "an empty Modulation lane leads in on its engine default 0")
    report.expect(
        modulation.originPhantom == nil, cppID: drawerAutomationProjectionID,
        message: "an empty lane has no origin phantom")

    // Same-tick occupants collapse for display and stay addressable by identity.
    let pan = fixture.projection(fixture.panLane)
    report.expectEqual(
        expected: ["0:64", "24:90", "120:0"],
        actual: fixture.laneValues(
            pan.points.map {
                AutomationLanePoint(tick: $0.tick, value: $0.value)
            }), cppID: drawerAutomationProjectionID,
        what: "the display points are the projected node and the written ticks")
    report.expect(
        pan.points[1].value == 90 && pan.points[1].tick == 24, cppID: drawerAutomationProjectionID,
        message: "the last occupant of a same-tick pair wins the display point")
    report.expectEqual(
        expected: ["24:30", "24:90", "120:0"], actual: pan.sources.map { "\($0.tick):\($0.value)" },
        cppID: drawerAutomationProjectionID,
        what: "every occurrence stays addressable")
    report.expect(
        pan.leadIn == nil, cppID: drawerAutomationProjectionID,
        message: "Pan projects its engine default instead of a lead-in")
    report.expectEqual(
        expected: 90, actual: pan.heldValue(at: 30) ?? -1, cppID: drawerAutomationProjectionID,
        what: "a tick after a point holds that point's value")
    report.expectEqual(
        expected: 90, actual: pan.heldValue(at: 24) ?? -1, cppID: drawerAutomationProjectionID,
        what: "a tick on a point holds its own value")
    report.expectEqual(
        expected: 64, actual: pan.heldValue(at: 20) ?? -1, cppID: drawerAutomationProjectionID,
        what: "a tick before the first written point holds the projected node")

    let occurrences = pan.sources.map { AutomationLanePoint(tick: $0.tick, value: $0.value) }
    report.expectEqual(
        expected: 90, actual: AutomationLaneReplacement.held(occurrences, at: 24, inclusive: true),
        cppID: drawerAutomationProjectionID,
        what: "inclusive held lookup chooses the last equal-tick occurrence")
    report.expect(
        AutomationLaneReplacement.held(occurrences, at: 24, inclusive: false) == nil,
        cppID: drawerAutomationProjectionID,
        message: "exclusive held lookup excludes the entire equal-tick group")
    report.expectEqual(
        expected: 90, actual: AutomationLaneReplacement.held(occurrences, at: 120, inclusive: false),
        cppID: drawerAutomationProjectionID,
        what: "exclusive held lookup retains the previous group's last occupant")

    // A written tick-zero point takes the place of the projected engine node.
    let volume = fixture.projection(fixture.volumeLane)
    report.expectEqual(
        expected: ["0:127", "96:64"],
        actual: fixture.laneValues(
            volume.points.map {
                AutomationLanePoint(tick: $0.tick, value: $0.value)
            }), cppID: drawerAutomationProjectionID, what: "written Volume points project at their ticks")
    report.expect(
        !volume.points.contains { $0.projected }, cppID: drawerAutomationProjectionID,
        message: "a written tick-zero point replaces the projected engine node")
    report.expectEqual(
        expected: 2, actual: volume.eventCount, cppID: drawerAutomationProjectionID,
        what: "the written-event count ignores projected nodes")

    // Steps: each point holds to the next, and the last holds to the song's end.
    report.expectEqual(
        expected: [Tick?.some(96), nil], actual: volume.segments.map(\.tickEnd), cppID: drawerAutomationProjectionID,
        what: "the last step runs open to the song's end")
    report.expectEqual(
        expected: [127, 64], actual: volume.segments.map(\.fromValue), cppID: drawerAutomationProjectionID,
        what: "each step holds its own point's value")
    report.expect(
        volume.segments.allSatisfy { $0.kind == .step && $0.toValue == $0.fromValue },
        cppID: drawerAutomationProjectionID, message: "the production curve is a step curve")
    report.expectEqual(
        expected: 127, actual: volume.heldValue(at: 95) ?? -1, cppID: drawerAutomationProjectionID,
        what: "the step's value holds until the next point")
    report.expectEqual(
        expected: 64, actual: volume.heldValue(at: 96) ?? -1, cppID: drawerAutomationProjectionID,
        what: "the next point's value holds from its own tick")

    // The projected engine node of a lane the document never wrote.
    let unwritten = drawerAutomationAutomationFixture(suite: suite, service: service, volume: [], pan: [])
    let projectedVolume = unwritten.projection(unwritten.volumeLane)
    report.expectEqual(
        expected: 1, actual: projectedVolume.points.count, cppID: drawerAutomationProjectionID,
        what: "Volume projects exactly its engine-default node")
    report.expect(
        projectedVolume.points[0].projected && projectedVolume.points[0].tick == 0
            && projectedVolume.points[0].value == 127,
        cppID: drawerAutomationProjectionID,
        message: "the projected node sits at tick zero with the engine default")
    report.expectEqual(
        expected: 0, actual: projectedVolume.eventCount, cppID: drawerAutomationProjectionID,
        what: "the projected node adds no written event")
    report.expect(
        projectedVolume.points[0].x > 0, cppID: drawerAutomationProjectionID,
        message: "the camera's lead pad keeps tick zero inside the plot")
    _ = unwritten.viewport.mutateCamera { $0.setHScroll(200) }
    let scrolledProjection = unwritten.projection(unwritten.volumeLane)
    report.expect(
        scrolledProjection.points[0].x < 0, cppID: drawerAutomationProjectionID,
        message: "a positive scroll carries the tick-zero node left of the plot")
    report.expectEqual(
        expected: Tick(0), actual: scrolledProjection.originPhantom?.point.tick ?? 99,
        cppID: drawerAutomationProjectionID,
        what: "an off-plot node becomes the origin phantom")

    // A ramp interpolation builds the same points into a rising curve.
    let rampMetadata = AutomationParameterMetadata(parameter: fixture.panLane)
    report.expectEqual(
        expected: 50,
        actual: AutomationInterpolation.ramp.value(
            at: 5, from: AutomationLanePoint(tick: 0, value: 0),
            to: AutomationLanePoint(tick: 10, value: 100)), cppID: drawerAutomationProjectionID,
        what: "the ramp interpolation is linear between its endpoints")
    report.expectEqual(
        expected: 0,
        actual: AutomationInterpolation.step.value(
            at: 5, from: AutomationLanePoint(tick: 0, value: 0),
            to: AutomationLanePoint(tick: 10, value: 100)), cppID: drawerAutomationProjectionID,
        what: "the step interpolation holds its first point's value")
    report.expectEqual(
        expected: AutomationInterpolation.step, actual: rampMetadata.interpolation, cppID: drawerAutomationProjectionID,
        what: "every catalog parameter projects a step curve")

    // Tempo projects through the same plot with its own value domain.
    let tempo = fixture.projection(.tempo)
    report.expectEqual(
        expected: ["0:120"],
        actual: fixture.laneValues(
            tempo.points.map {
                AutomationLanePoint(tick: $0.tick, value: $0.value)
            }), cppID: drawerAutomationProjectionID, what: "a tempo point projects at its tick as BPM")
    report.expectEqual(
        expected: fixture.y(.tempo, 120), actual: tempo.points.first?.y ?? -1, cppID: drawerAutomationProjectionID,
        what: "Tempo uses the shared value axis")

    // Camera edges: every x comes from the shared camera, and a zoom rescales it.
    report.expectEqual(
        expected: fixture.viewport.camera.contentX(tick: 96), actual: volume.points[1].x,
        cppID: drawerAutomationProjectionID,
        what: "every x is the shared camera's projection")
    let beforeZoom = fixture.projection(fixture.volumeLane).points[1].x
    _ = fixture.viewport.mutateCamera { _ = $0.setTimeZoom(90) }
    let afterZoom = fixture.projection(fixture.volumeLane).points[1].x
    report.expect(
        afterZoom > beforeZoom * 2, cppID: drawerAutomationProjectionID,
        message: "a time zoom rescales the projected x")
    _ = fixture.viewport.mutateCamera { $0.setHScroll(0) }
    let atZeroScroll = fixture.projection(.tempo).points[0].x
    report.expectEqual(
        expected: fixture.viewport.camera.contentX(tick: 0), actual: atZeroScroll, cppID: drawerAutomationProjectionID,
        what: "a scroll offsets the projection by the same amount")
    _ = fixture.viewport.mutateCamera { $0.setHScroll(70) }
    let preRoll = fixture.projection(.tempo)
    report.expect(
        preRoll.points[0].x < 0, cppID: drawerAutomationProjectionID,
        message: "a scrolled past a point leaves it left of the plot")
    report.expectEqual(
        expected: Tick(0), actual: preRoll.originPhantom?.point.tick ?? 99, cppID: drawerAutomationProjectionID,
        what: "the off-plot point becomes the lane's origin phantom")
    _ = fixture.viewport.mutateCamera { $0.setHScroll(-1000) }
    report.expectEqual(
        expected: fixture.viewport.camera.minHScroll, actual: fixture.viewport.camera.snapshot.scrollX,
        cppID: drawerAutomationProjectionID,
        what: "the camera clamps its scroll to the negative pre-roll bound")
}

@MainActor
func drawerAutomationPointIdentityAndStaleness(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 30), (24, 90), (48, 10)])
    let revision = fixture.document.revision
    let pan = fixture.projection(fixture.panLane)
    report.expectEqual(
        expected: 3, actual: pan.sources.count, cppID: drawerAutomationIdentityID,
        what: "each occurrence exposes its own identity")
    report.expectEqual(
        expected: fixture.lanePoints(fixture.panLane).map(\.eventIndex), actual: pan.sources.map(\.identity.occurrence),
        cppID: drawerAutomationIdentityID,
        what: "the identity carries the document's own occurrence handle")
    report.expect(
        pan.sources.allSatisfy { $0.identity.revision == revision }, cppID: drawerAutomationIdentityID,
        message: "every identity carries the revision it was read at")
    report.expect(
        pan.sources.allSatisfy { $0.identity.parameter == fixture.panLane },
        cppID: drawerAutomationIdentityID, message: "every identity carries its parameter")
    report.expect(
        pan.sources.allSatisfy { $0.lanePoint != nil && $0.tempoPoint == nil },
        cppID: drawerAutomationIdentityID,
        message: "a lane occurrence carries the document handle a write names")

    // A rewrite of one tick leaves the other occurrences' identities intact and
    // never lets a stale identity match the lane again.
    let captured = pan.sources[0].identity
    fixture.document.writeLane(
        track: 0, lane: .controller(TimeDefaults.ccPan), from: 48,
        through: 48, points: [LaneWrite(tick: 48, value: 20)])
    let rewritten = fixture.projection(fixture.panLane)
    report.expect(
        !rewritten.sources.contains { $0.identity == captured }, cppID: drawerAutomationIdentityID,
        message: "a stale identity never matches a later projection")
    report.expectEqual(
        expected: ["24:30", "24:90", "48:20"], actual: rewritten.sources.map { "\($0.tick):\($0.value)" },
        cppID: drawerAutomationIdentityID,
        what: "the same-tick occurrences keep their document order and identity")

    // A frozen target whose tick is gone resolves to nothing; a live one still
    // resolves, but only at the revision it froze.
    let beforeDelete = fixture.facts(fixture.panLane)
    fixture.document.deleteLanePoints(
        track: 0, lane: .controller(TimeDefaults.ccPan),
        points: fixture.lanePoints(fixture.panLane).filter {
            $0.tick == 48
        })
    let stale = AutomationNodeResolver.moves([
        AutomationNodeResolver.LaneMoves(
            fixture.facts(fixture.panLane),
            [
                AutomationNodeMove(parameter: fixture.panLane, sourceTick: 48, tick: 60, value: 20)
            ])
    ])
    report.expect(
        stale == nil, cppID: drawerAutomationIdentityID,
        message: "a move whose source tick is gone resolves to nothing")
    let live = AutomationNodeResolver.moves([
        AutomationNodeResolver.LaneMoves(
            beforeDelete,
            [
                AutomationNodeMove(parameter: fixture.panLane, sourceTick: 24, tick: 60, value: 5)
            ])
    ])
    report.expectEqual(
        expected: 1, actual: live?.writes.count ?? 0, cppID: drawerAutomationIdentityID,
        what: "a live source tick resolves against the frozen revision")
    report.expect(
        !AutomationCommit.apply(live!, in: fixture.document), cppID: drawerAutomationIdentityID,
        message: "a plan at a superseded revision writes nothing")
    report.expectEqual(
        expected: ["24:30", "24:90"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationIdentityID,
        what: "the lane still holds what the delete and the failed plan left")

    // Tempo identity is its tick: the value comes from the stored microseconds.
    let tempoFixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        tempo: [(0, 500_000), (48, 400_000)])
    let tempo = tempoFixture.projection(.tempo)
    report.expectEqual(
        expected: ["0:120", "48:150"],
        actual: tempoFixture.laneValues(
            tempo.points.map {
                AutomationLanePoint(tick: $0.tick, value: $0.value)
            }), cppID: drawerAutomationIdentityID, what: "tempo values project as BPM from the stored microseconds")
    report.expect(
        tempo.sources.allSatisfy { $0.tempoPoint != nil && $0.lanePoint == nil },
        cppID: drawerAutomationIdentityID,
        message: "a tempo occurrence carries the tempo point a write removes")
}

@MainActor
func drawerAutomationDeleteTransactions(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 30), (24, 90), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot
    report.expect(
        fixture.page.deletePoints(at: [24]), cppID: drawerAutomationDeleteID,
        message: "deleting a tick with occupants commits")
    report.expectEqual(
        expected: ["120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationDeleteID,
        what: "every occurrence at the deleted tick goes")
    report.expectEqual(
        expected: before.revision + 1, actual: fixture.document.revision, cppID: drawerAutomationDeleteID,
        what: "the deletion is one revision")
    report.expect(
        fixture.undo() && fixture.values(fixture.panLane).count == 3, cppID: drawerAutomationDeleteID,
        message: "one undo restores both deleted occurrences")

    let revision = fixture.document.revision
    report.expect(
        !fixture.page.deletePoints(at: [600]), cppID: drawerAutomationDeleteID,
        message: "deleting a tick with no occurrence writes nothing")
    report.expectEqual(
        expected: revision, actual: fixture.document.revision, cppID: drawerAutomationDeleteID,
        what: "a missing target leaves the revision alone")

    // The projected engine node is deletable and removes nothing.
    let projectionFixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(120, 40)])
    projectionFixture.activate(projectionFixture.panLane)
    let projectedRevision = projectionFixture.document.revision
    report.expect(
        !projectionFixture.page.deletePoints(at: [0]), cppID: drawerAutomationDeleteID,
        message: "deleting the projected engine node writes nothing")
    report.expectEqual(
        expected: projectedRevision, actual: projectionFixture.document.revision, cppID: drawerAutomationDeleteID,
        what: "the projected node is not a written event")
    report.expect(
        !projectionFixture.page.deletePoints(at: []), cppID: drawerAutomationDeleteID,
        message: "an empty delete request writes nothing")

    // A selection delete removes every covered lane's nodes and leaves the rest.
    let selection = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(48, 100), (140, 20)],
        pan: [(24, 30), (120, 40)],
        tempo: [(0, 500_000), (150, 400_000)])
    selection.page.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 20, endTick: 100), scope: .lanes,
            lanes: [selection.panLane, selection.volumeLane], tempo: false))
    report.expectEqual(
        expected: [selection.volumeLane, selection.panLane], actual: selection.page.selectedParameters,
        cppID: drawerAutomationDeleteID,
        what: "the selection covers both lanes inside the range")
    let selectionBefore = selection.snapshot
    report.expect(
        selection.page.deleteSelectedNodes(), cppID: drawerAutomationDeleteID,
        message: "the selection delete commits once")
    report.expectEqual(
        expected: ["120:40"], actual: selection.values(selection.panLane), cppID: drawerAutomationDeleteID,
        what: "the covered lane keeps only its outside point")
    report.expectEqual(
        expected: ["140:20"], actual: selection.values(selection.volumeLane), cppID: drawerAutomationDeleteID,
        what: "the second covered lane keeps only its outside point")
    report.expectEqual(
        expected: ["0:120", "150:150"], actual: selection.tempoValues, cppID: drawerAutomationDeleteID,
        what: "Tempo stays untouched while the selection excludes it")
    report.expectEqual(
        expected: selectionBefore.revision + 1, actual: selection.document.revision, cppID: drawerAutomationDeleteID,
        what: "a multi-lane delete is one revision")
    report.expect(selection.undo(), cppID: drawerAutomationDeleteID, message: "the multi-lane delete is undoable")
    report.expectEqual(
        expected: ["24:30", "120:40"], actual: selection.values(selection.panLane), cppID: drawerAutomationDeleteID,
        what: "one undo restores the first lane")
    report.expectEqual(
        expected: ["48:100", "140:20"], actual: selection.values(selection.volumeLane), cppID: drawerAutomationDeleteID,
        what: "one undo restores the second lane")
    report.expect(
        !selection.document.history.canUndo, cppID: drawerAutomationDeleteID,
        message: "one undo consumes the multi-lane delete's single history entry")
    report.expectEqual(
        expected: [selection.volumeLane, selection.panLane], actual: selection.page.selectedParameters,
        cppID: drawerAutomationDeleteID,
        what: "the selection survives the delete it performed")
}
let drawerAutomationGestureLawID = "swiftcore/AutomationPage::gestureOneEditLaw"
let drawerAutomationParkedLawID = "swiftcore/AutomationPage::parkedGestureUnchangedLaw"

// The parity helper laws, executed as one predicate each through the page's
// production pointer route: a completed gesture is one edit with its nodes,
// a parked gesture mutates nothing.
@MainActor
func drawerAutomationCompletedGestureOneEditLaw(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = DrawerAutomationStagedSnapshot(fixture.document)
    let pressX = fixture.x(24)
    let pressY = fixture.y(fixture.panLane, 64)
    guard
        fixture.page.pointerPress(
            x: pressX, y: pressY, surface: 1,
            button: DrawerQtButton.left)
    else {
        report.fail(drawerAutomationGestureLawID, "a press grabs the node for the one-edit gesture")
        return
    }
    let travel = fixture.page.geometry.nodeDragActivationDistance + 2
    _ = fixture.page.pointerMove(x: pressX + travel, y: pressY, buttons: DrawerQtButton.left)
    _ = fixture.page.pointerMove(
        x: pressX + travel, y: fixture.y(fixture.panLane, 90),
        buttons: DrawerQtButton.left)
    _ = fixture.page.pointerRelease(
        x: pressX + travel, y: fixture.y(fixture.panLane, 90),
        button: DrawerQtButton.left)
    let after = DrawerAutomationStagedSnapshot(fixture.document)
    report.expect(
        after.revision == before.revision + 1
            && after.undoIndex == before.undoIndex + 1
            && after.undoCount == before.undoCount + 1
            && after.bytes != before.bytes
            && fixture.values(fixture.panLane) == ["24:90", "120:40"],
        cppID: drawerAutomationGestureLawID,
        message: "a completed gesture commits one edit with the shared node result")
}

@MainActor
func drawerAutomationParkedGestureUnchangedLaw(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = DrawerAutomationStagedSnapshot(fixture.document)
    guard
        fixture.page.pointerPress(
            x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1,
            button: DrawerQtButton.left)
    else {
        report.fail(drawerAutomationParkedLawID, "a press parks on the node for the unchanged law")
        return
    }
    _ = fixture.page.pointerMove(
        x: fixture.x(24) + 2, y: fixture.y(fixture.panLane, 64),
        buttons: DrawerQtButton.left)
    fixture.page.cancelSectionInteraction()
    report.expect(
        DrawerAutomationStagedSnapshot(fixture.document) == before,
        cppID: drawerAutomationParkedLawID,
        message: "a parked gesture mutates no song bytes revision or undo depth")
}
