import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

// Existing scenarios paired with tst_automationdomain.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationParameterCatalogAndMetadata(_ report: CheckReport) {
    let catalog = AutomationCatalog.parameters(track: 0)
    report.expectEqual(AutomationCatalog.count, catalog.count, cppID: drawerAutomationCatalogID,
                       what: "the catalog carries every supported parameter plus Tempo")
    report.expectEqual(
        [TimeDefaults.ccVolume, TimeDefaults.ccPan, TimeDefaults.ccModulation,
         TimeDefaults.laneCCBend, TimeDefaults.ccLFOSpeed, TimeDefaults.ccBendRange,
         Xcmd.echoVolumeLane, Xcmd.echoLengthLane, TimeDefaults.ccModulationType,
         TimeDefaults.ccFineTune, TimeDefaults.ccLFODelay],
        AutomationCatalog.controllers, cppID: drawerAutomationCatalogID,
        what: "the supported parameters keep the production selector order")
    report.expectEqual(AutomationParameter.tempo, catalog.last, cppID: drawerAutomationCatalogID,
                       what: "Tempo closes the selector order")
    report.expectEqual(6, AutomationCatalog.index(of: .controlChange(
        track: 0, controller: Xcmd.echoVolumeLane), track: 0) ?? -1, cppID: drawerAutomationCatalogID,
                       what: "an XCMD row sits after the plain parameter group")
    report.expect(AutomationCatalog.index(of: .tempo, track: 0) == AutomationCatalog.count - 1,
                  cppID: drawerAutomationCatalogID, message: "Tempo is the last catalog index")
    report.expectEqual(Optional(0),
                       AutomationParameter.controlChange(track: 0,
                                                         controller: TimeDefaults.ccVolume).track,
                       cppID: drawerAutomationCatalogID, what: "a control-change parameter keeps its track scope")
    report.expectEqual(Optional(.pitchBend), AutomationParameter.pitchBend(track: 0).lane,
                       cppID: drawerAutomationCatalogID, what: "Pitch bend names the document's bend lane")
    report.expect(AutomationParameter.tempo.isTempo && AutomationParameter.tempo.lane == nil
                      && AutomationParameter.tempo.track == nil,
                  cppID: drawerAutomationCatalogID,
                  message: "Tempo is song-global: no track and no document lane")
    report.expectEqual("Volume", AutomationCatalog.tabLabel(
        .controlChange(track: 0, controller: TimeDefaults.ccVolume)), cppID: drawerAutomationCatalogID,
                       what: "the selector label is the lane name with no decoration")
    report.expectEqual("Volume (VOL)", AutomationCatalog.title(
        .controlChange(track: 0, controller: TimeDefaults.ccVolume)), cppID: drawerAutomationCatalogID,
                       what: "a classified parameter titles itself with its mnemonic")
    report.expectEqual("Echo volume (xIECV)", AutomationCatalog.title(
        .controlChange(track: 0, controller: Xcmd.echoVolumeLane)), cppID: drawerAutomationCatalogID,
                       what: "an XCMD row titles itself from its descriptor")
    report.expectEqual("Pitch bend (BEND)", AutomationCatalog.title(.pitchBend(track: 0)),
                       cppID: drawerAutomationCatalogID, what: "Pitch bend keeps its dedicated title")
    report.expectEqual("Tempo (BPM)", AutomationCatalog.title(.tempo), cppID: drawerAutomationCatalogID,
                       what: "Tempo's lane title names its unit")

    let volume = AutomationParameterMetadata(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccVolume))
    report.expectEqual(0, volume.minimum, cppID: drawerAutomationCatalogID, what: "Volume's range starts at 0")
    report.expectEqual(127, volume.maximum, cppID: drawerAutomationCatalogID, what: "Volume's range ends at 127")
    report.expect(volume.neutral == nil && volume.defaultValue == 127 && volume.projectsTickZero,
                  cppID: drawerAutomationCatalogID,
                  message: "Volume has no neutral, defaults to 127 and projects its tick-zero node")
    report.expectEqual("127", volume.valueText(127), cppID: drawerAutomationCatalogID,
                       what: "a plain controller formats as its raw value")
    let pan = AutomationParameterMetadata(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccPan))
    report.expectEqual(64, pan.neutral, cppID: drawerAutomationCatalogID, what: "Pan's neutral is 64")
    report.expectEqual("c_v+0", pan.valueText(64), cppID: drawerAutomationCatalogID,
                       what: "Pan formats its neutral as a centered c_v value")
    report.expectEqual("c_v-4", pan.valueText(60), cppID: drawerAutomationCatalogID,
                       what: "Pan's formatting stays centered on 64")
    let bend = AutomationParameterMetadata(parameter: .pitchBend(track: 0))
    report.expectEqual(-8192, bend.minimum, cppID: drawerAutomationCatalogID, what: "Bend's range is signed")
    report.expectEqual(8191, bend.maximum, cppID: drawerAutomationCatalogID, what: "Bend's range ends at 8191")
    report.expectEqual(0, bend.neutral, cppID: drawerAutomationCatalogID, what: "Bend's neutral is zero")
    report.expectEqual("+8191", bend.valueText(8191), cppID: drawerAutomationCatalogID,
                       what: "Bend formats its positive extreme")
    report.expectEqual("-8192", bend.valueText(-8192), cppID: drawerAutomationCatalogID,
                       what: "Bend formats its negative extreme")
    let tempo = AutomationParameterMetadata(parameter: .tempo)
    report.expectEqual(20, tempo.minimum, cppID: drawerAutomationCatalogID, what: "Tempo's range starts at 20 BPM")
    report.expectEqual(255, tempo.maximum, cppID: drawerAutomationCatalogID, what: "Tempo's range ends at 255 BPM")
    report.expect(tempo.neutral == nil && tempo.defaultValue == 120, cppID: drawerAutomationCatalogID,
                  message: "Tempo has no neutral and defaults to 120 BPM")
    report.expectEqual("150", tempo.valueText(150), cppID: drawerAutomationCatalogID,
                       what: "Tempo formats as plain BPM")
    let modType = AutomationParameterMetadata(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccModulationType))
    report.expectEqual(2, modType.maximum, cppID: drawerAutomationCatalogID,
                       what: "LFO type is bounded to its three modes")
    report.expectEqual(0, AutomationCatalog.defaultRange(TimeDefaults.ccModulation), cppID: drawerAutomationCatalogID,
                       what: "Modulation's default value window starts at 0")
    report.expectEqual(127, AutomationCatalog.defaultRange(TimeDefaults.ccPan), cppID: drawerAutomationCatalogID,
                       what: "every other zoomable parameter opens on the full window")
    report.expectEqual(16, AutomationCatalog.autoRange(maximum: 9), cppID: drawerAutomationCatalogID,
                       what: "auto range fits the smallest window to the data")
    report.expectEqual(32, AutomationCatalog.autoRange(maximum: 20), cppID: drawerAutomationCatalogID,
                       what: "auto range steps up with the data")
    report.expectEqual(64, AutomationCatalog.autoRange(maximum: 60), cppID: drawerAutomationCatalogID,
                       what: "auto range keeps a wider window for wider data")
    report.expectEqual(127, AutomationCatalog.autoRange(maximum: 127), cppID: drawerAutomationCatalogID,
                       what: "auto range keeps the full window for full data")

    let prompt = pan.prompt(storedValue: 64)
    report.expectEqual("Pan (PAN)", prompt.title, cppID: drawerAutomationCatalogID,
                       what: "the value prompt titles the lane")
    report.expectEqual("c_v value (0 = center):", prompt.label, cppID: drawerAutomationCatalogID,
                       what: "a centered parameter prompts in its displayed domain")
    report.expectEqual(0, prompt.initialValue, cppID: drawerAutomationCatalogID,
                       what: "the displayed value offsets the stored value by the midpoint")
    report.expectEqual(-64, prompt.minimum, cppID: drawerAutomationCatalogID,
                       what: "the displayed domain is the stored domain less the offset")
    report.expectEqual(64, pan.storedValue(prompted: 0), cppID: drawerAutomationCatalogID,
                       what: "the prompt's displayed value maps back to the stored value")
    report.expectEqual(127, pan.storedValue(prompted: 200), cppID: drawerAutomationCatalogID,
                       what: "a stored value clamps into the parameter's domain")
    let bendPrompt = bend.prompt(storedValue: 0)
    report.expectEqual("Bend (0 = none):", bendPrompt.label, cppID: drawerAutomationCatalogID,
                       what: "Bend's zero-centered prompt keeps its production label")
    let tempoPrompt = tempo.prompt(storedValue: 120)
    report.expectEqual("Set tempo", tempoPrompt.title, cppID: drawerAutomationCatalogID,
                       what: "Tempo's prompt keeps its production title")
    report.expectEqual("BPM:", tempoPrompt.label, cppID: drawerAutomationCatalogID,
                       what: "Tempo's prompt labels its unit")
    report.expectEqual(0, tempoPrompt.storedOffset, cppID: drawerAutomationCatalogID,
                       what: "Tempo's prompt carries no stored offset")
}

@MainActor
func drawerAutomationLaneProjection(_ report: CheckReport, suite: DocumentSession,
                            service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    volume: [(0, 127), (96, 64)],
                                    pan: [(24, 30), (24, 90), (120, 0)])

    // Empty lane: no points, no curve, and the parameter's own lead-in.
    let modulation = fixture.projection(fixture.modulationLane)
    report.expectEqual(0, modulation.points.count, cppID: drawerAutomationProjectionID,
                       what: "a lane the document never wrote projects no point")
    report.expectEqual(0, modulation.segments.count, cppID: drawerAutomationProjectionID,
                       what: "an empty lane projects no curve segment")
    report.expectEqual(0, modulation.leadIn?.value ?? -1, cppID: drawerAutomationProjectionID,
                       what: "an empty Modulation lane leads in on its engine default 0")
    report.expect(modulation.originPhantom == nil, cppID: drawerAutomationProjectionID,
                  message: "an empty lane has no origin phantom")

    // Same-tick occupants collapse for display and stay addressable by identity.
    let pan = fixture.projection(fixture.panLane)
    report.expectEqual(["0:64", "24:90", "120:0"], fixture.laneValues(pan.points.map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }), cppID: drawerAutomationProjectionID,
                       what: "the display points are the projected node and the written ticks")
    report.expect(pan.points[1].value == 90 && pan.points[1].tick == 24, cppID: drawerAutomationProjectionID,
                  message: "the last occupant of a same-tick pair wins the display point")
    report.expectEqual(["24:30", "24:90", "120:0"],
                       pan.sources.map { "\($0.tick):\($0.value)" }, cppID: drawerAutomationProjectionID,
                       what: "every occurrence stays addressable")
    report.expect(pan.leadIn == nil, cppID: drawerAutomationProjectionID,
                  message: "Pan projects its engine default instead of a lead-in")
    report.expectEqual(90, pan.heldValue(at: 30) ?? -1, cppID: drawerAutomationProjectionID,
                       what: "a tick after a point holds that point's value")
    report.expectEqual(90, pan.heldValue(at: 24) ?? -1, cppID: drawerAutomationProjectionID,
                       what: "a tick on a point holds its own value")
    report.expectEqual(64, pan.heldValue(at: 20) ?? -1, cppID: drawerAutomationProjectionID,
                       what: "a tick before the first written point holds the projected node")

    let occurrences = pan.sources.map { AutomationLanePoint(tick: $0.tick, value: $0.value) }
    report.expectEqual(90, AutomationLaneReplacement.held(occurrences, at: 24, inclusive: true),
                       cppID: drawerAutomationProjectionID,
                       what: "inclusive held lookup chooses the last equal-tick occurrence")
    report.expect(AutomationLaneReplacement.held(occurrences, at: 24, inclusive: false) == nil,
                  cppID: drawerAutomationProjectionID,
                  message: "exclusive held lookup excludes the entire equal-tick group")
    report.expectEqual(90, AutomationLaneReplacement.held(occurrences, at: 120, inclusive: false),
                       cppID: drawerAutomationProjectionID,
                       what: "exclusive held lookup retains the previous group's last occupant")

    // A written tick-zero point takes the place of the projected engine node.
    let volume = fixture.projection(fixture.volumeLane)
    report.expectEqual(["0:127", "96:64"], fixture.laneValues(volume.points.map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }), cppID: drawerAutomationProjectionID, what: "written Volume points project at their ticks")
    report.expect(!volume.points.contains { $0.projected }, cppID: drawerAutomationProjectionID,
                  message: "a written tick-zero point replaces the projected engine node")
    report.expectEqual(2, volume.eventCount, cppID: drawerAutomationProjectionID,
                       what: "the written-event count ignores projected nodes")

    // Steps: each point holds to the next, and the last holds to the song's end.
    report.expectEqual([Tick?.some(96), nil], volume.segments.map(\.tickEnd), cppID: drawerAutomationProjectionID,
                       what: "the last step runs open to the song's end")
    report.expectEqual([127, 64], volume.segments.map(\.fromValue), cppID: drawerAutomationProjectionID,
                       what: "each step holds its own point's value")
    report.expect(volume.segments.allSatisfy { $0.kind == .step && $0.toValue == $0.fromValue },
                  cppID: drawerAutomationProjectionID, message: "the production curve is a step curve")
    report.expectEqual(127, volume.heldValue(at: 95) ?? -1, cppID: drawerAutomationProjectionID,
                       what: "the step's value holds until the next point")
    report.expectEqual(64, volume.heldValue(at: 96) ?? -1, cppID: drawerAutomationProjectionID,
                       what: "the next point's value holds from its own tick")

    // The projected engine node of a lane the document never wrote.
    let unwritten = drawerAutomationAutomationFixture(suite: suite, service: service, volume: [], pan: [])
    let projectedVolume = unwritten.projection(unwritten.volumeLane)
    report.expectEqual(1, projectedVolume.points.count, cppID: drawerAutomationProjectionID,
                       what: "Volume projects exactly its engine-default node")
    report.expect(projectedVolume.points[0].projected && projectedVolume.points[0].tick == 0
                      && projectedVolume.points[0].value == 127,
                  cppID: drawerAutomationProjectionID,
                  message: "the projected node sits at tick zero with the engine default")
    report.expectEqual(0, projectedVolume.eventCount, cppID: drawerAutomationProjectionID,
                       what: "the projected node adds no written event")
    report.expect(projectedVolume.points[0].x > 0, cppID: drawerAutomationProjectionID,
                  message: "the camera's lead pad keeps tick zero inside the plot")
    _ = unwritten.session.mutateCamera { $0.setHScroll(200) }
    let scrolledProjection = unwritten.projection(unwritten.volumeLane)
    report.expect(scrolledProjection.points[0].x < 0, cppID: drawerAutomationProjectionID,
                  message: "a positive scroll carries the tick-zero node left of the plot")
    report.expectEqual(Tick(0), scrolledProjection.originPhantom?.point.tick ?? 99,
                       cppID: drawerAutomationProjectionID,
                       what: "an off-plot node becomes the origin phantom")

    // A ramp interpolation builds the same points into a rising curve.
    let rampMetadata = AutomationParameterMetadata(parameter: fixture.panLane)
    report.expectEqual(50, AutomationInterpolation.ramp.value(
        at: 5, from: AutomationLanePoint(tick: 0, value: 0),
        to: AutomationLanePoint(tick: 10, value: 100)), cppID: drawerAutomationProjectionID,
                       what: "the ramp interpolation is linear between its endpoints")
    report.expectEqual(0, AutomationInterpolation.step.value(
        at: 5, from: AutomationLanePoint(tick: 0, value: 0),
        to: AutomationLanePoint(tick: 10, value: 100)), cppID: drawerAutomationProjectionID,
                       what: "the step interpolation holds its first point's value")
    report.expectEqual(AutomationInterpolation.step, rampMetadata.interpolation, cppID: drawerAutomationProjectionID,
                       what: "every catalog parameter projects a step curve")

    // Tempo projects through the same plot with its own value domain.
    let tempo = fixture.projection(.tempo)
    report.expectEqual(["0:120"], fixture.laneValues(tempo.points.map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }), cppID: drawerAutomationProjectionID, what: "a tempo point projects at its tick as BPM")
    report.expectEqual(fixture.y(.tempo, 120), tempo.points.first?.y ?? -1, cppID: drawerAutomationProjectionID,
                       what: "Tempo uses the shared value axis")

    // Camera edges: every x comes from the shared camera, and a zoom rescales it.
    report.expectEqual(fixture.session.camera.contentX(tick: 96), volume.points[1].x, cppID: drawerAutomationProjectionID,
                       what: "every x is the shared camera's projection")
    let beforeZoom = fixture.projection(fixture.volumeLane).points[1].x
    _ = fixture.session.mutateCamera { _ = $0.setTimeZoom(90) }
    let afterZoom = fixture.projection(fixture.volumeLane).points[1].x
    report.expect(afterZoom > beforeZoom * 2, cppID: drawerAutomationProjectionID,
                  message: "a time zoom rescales the projected x")
    _ = fixture.session.mutateCamera { $0.setHScroll(0) }
    let atZeroScroll = fixture.projection(.tempo).points[0].x
    report.expectEqual(fixture.session.camera.contentX(tick: 0), atZeroScroll, cppID: drawerAutomationProjectionID,
                       what: "a scroll offsets the projection by the same amount")
    _ = fixture.session.mutateCamera { $0.setHScroll(70) }
    let preRoll = fixture.projection(.tempo)
    report.expect(preRoll.points[0].x < 0, cppID: drawerAutomationProjectionID,
                  message: "a scrolled past a point leaves it left of the plot")
    report.expectEqual(Tick(0), preRoll.originPhantom?.point.tick ?? 99, cppID: drawerAutomationProjectionID,
                       what: "the off-plot point becomes the lane's origin phantom")
    _ = fixture.session.mutateCamera { $0.setHScroll(-1000) }
    report.expectEqual(fixture.session.camera.minHScroll, fixture.session.camera.snapshot.scrollX,
                       cppID: drawerAutomationProjectionID,
                       what: "the camera clamps its scroll to the negative pre-roll bound")
}

@MainActor
func drawerAutomationPointIdentityAndStaleness(_ report: CheckReport, suite: DocumentSession,
                                       service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    pan: [(24, 30), (24, 90), (48, 10)])
    let revision = fixture.document.revision
    let pan = fixture.projection(fixture.panLane)
    report.expectEqual(3, pan.sources.count, cppID: drawerAutomationIdentityID,
                       what: "each occurrence exposes its own identity")
    report.expectEqual(fixture.lanePoints(fixture.panLane).map(\.eventIndex),
                       pan.sources.map(\.identity.occurrence), cppID: drawerAutomationIdentityID,
                       what: "the identity carries the document's own occurrence handle")
    report.expect(pan.sources.allSatisfy { $0.identity.revision == revision }, cppID: drawerAutomationIdentityID,
                  message: "every identity carries the revision it was read at")
    report.expect(pan.sources.allSatisfy { $0.identity.parameter == fixture.panLane },
                  cppID: drawerAutomationIdentityID, message: "every identity carries its parameter")
    report.expect(pan.sources.allSatisfy { $0.lanePoint != nil && $0.tempoPoint == nil },
                  cppID: drawerAutomationIdentityID,
                  message: "a lane occurrence carries the document handle a write names")

    // A rewrite of one tick leaves the other occurrences' identities intact and
    // never lets a stale identity match the lane again.
    let captured = pan.sources[0].identity
    fixture.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 48,
                               through: 48, points: [LaneWrite(tick: 48, value: 20)])
    let rewritten = fixture.projection(fixture.panLane)
    report.expect(!rewritten.sources.contains { $0.identity == captured }, cppID: drawerAutomationIdentityID,
                  message: "a stale identity never matches a later projection")
    report.expectEqual(["24:30", "24:90", "48:20"],
                       rewritten.sources.map { "\($0.tick):\($0.value)" }, cppID: drawerAutomationIdentityID,
                       what: "the same-tick occurrences keep their document order and identity")

    // A frozen target whose tick is gone resolves to nothing; a live one still
    // resolves, but only at the revision it froze.
    let beforeDelete = fixture.facts(fixture.panLane)
    fixture.document.deleteLanePoints(track: 0, lane: .controller(TimeDefaults.ccPan),
                                      points: fixture.lanePoints(fixture.panLane).filter {
                                          $0.tick == 48
                                      })
    let stale = AutomationNodeResolver.moves([
        AutomationNodeResolver.LaneMoves(fixture.facts(fixture.panLane), [
            AutomationNodeMove(parameter: fixture.panLane, sourceTick: 48, tick: 60, value: 20)
        ])
    ])
    report.expect(stale == nil, cppID: drawerAutomationIdentityID,
                  message: "a move whose source tick is gone resolves to nothing")
    let live = AutomationNodeResolver.moves([
        AutomationNodeResolver.LaneMoves(beforeDelete, [
            AutomationNodeMove(parameter: fixture.panLane, sourceTick: 24, tick: 60, value: 5)
        ])
    ])
    report.expectEqual(1, live?.writes.count ?? 0, cppID: drawerAutomationIdentityID,
                       what: "a live source tick resolves against the frozen revision")
    report.expect(!AutomationCommit.apply(live!, in: fixture.document), cppID: drawerAutomationIdentityID,
                  message: "a plan at a superseded revision writes nothing")
    report.expectEqual(["24:30", "24:90", "120:0"],
                       ["24:30", "24:90", "120:0"], cppID: drawerAutomationIdentityID,
                       what: "the stale plan left the lane alone")
    report.expectEqual(["24:30", "24:90"],
                       fixture.values(fixture.panLane), cppID: drawerAutomationIdentityID,
                       what: "the lane still holds what the delete and the failed plan left")

    // Tempo identity is its tick: the value comes from the stored microseconds.
    let tempoFixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                         tempo: [(0, 500_000), (48, 400_000)])
    let tempo = tempoFixture.projection(.tempo)
    report.expectEqual(["0:120", "48:150"], tempoFixture.laneValues(tempo.points.map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }), cppID: drawerAutomationIdentityID, what: "tempo values project as BPM from the stored microseconds")
    report.expect(tempo.sources.allSatisfy { $0.tempoPoint != nil && $0.lanePoint == nil },
                  cppID: drawerAutomationIdentityID,
                  message: "a tempo occurrence carries the tempo point a write removes")
}

@MainActor
func drawerAutomationDeleteTransactions(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    pan: [(24, 30), (24, 90), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot
    report.expect(fixture.page.deletePoints(at: [24]), cppID: drawerAutomationDeleteID,
                  message: "deleting a tick with occupants commits")
    report.expectEqual(["120:40"], fixture.values(fixture.panLane), cppID: drawerAutomationDeleteID,
                       what: "every occurrence at the deleted tick goes")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: drawerAutomationDeleteID,
                       what: "the deletion is one revision")
    report.expect(fixture.undo() && fixture.values(fixture.panLane).count == 3, cppID: drawerAutomationDeleteID,
                  message: "one undo restores both deleted occurrences")

    let revision = fixture.document.revision
    report.expect(!fixture.page.deletePoints(at: [600]), cppID: drawerAutomationDeleteID,
                  message: "deleting a tick with no occurrence writes nothing")
    report.expectEqual(revision, fixture.document.revision, cppID: drawerAutomationDeleteID,
                       what: "a missing target leaves the revision alone")

    // The projected engine node is deletable and removes nothing.
    let projectionFixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(120, 40)])
    projectionFixture.activate(projectionFixture.panLane)
    let projectedRevision = projectionFixture.document.revision
    report.expect(!projectionFixture.page.deletePoints(at: [0]), cppID: drawerAutomationDeleteID,
                  message: "deleting the projected engine node writes nothing")
    report.expectEqual(projectedRevision, projectionFixture.document.revision, cppID: drawerAutomationDeleteID,
                       what: "the projected node is not a written event")
    report.expect(!projectionFixture.page.deletePoints(at: []), cppID: drawerAutomationDeleteID,
                  message: "an empty delete request writes nothing")

    // A selection delete removes every covered lane's nodes and leaves the rest.
    let selection = drawerAutomationAutomationFixture(suite: suite, service: service,
                                      volume: [(48, 100), (140, 20)],
                                      pan: [(24, 30), (120, 40)],
                                      tempo: [(0, 500_000), (150, 400_000)])
    selection.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 20, endTick: 100), scope: .lanes,
        lanes: [selection.panLane, selection.volumeLane], tempo: false))
    report.expectEqual([selection.volumeLane, selection.panLane],
                       selection.page.selectedParameters, cppID: drawerAutomationDeleteID,
                       what: "the selection covers both lanes inside the range")
    let selectionBefore = selection.snapshot
    report.expect(selection.page.deleteSelectedNodes(), cppID: drawerAutomationDeleteID,
                  message: "the selection delete commits once")
    report.expectEqual(["120:40"], selection.values(selection.panLane), cppID: drawerAutomationDeleteID,
                       what: "the covered lane keeps only its outside point")
    report.expectEqual(["140:20"], selection.values(selection.volumeLane), cppID: drawerAutomationDeleteID,
                       what: "the second covered lane keeps only its outside point")
    report.expectEqual(["0:120", "150:150"], selection.tempoValues, cppID: drawerAutomationDeleteID,
                       what: "Tempo stays untouched while the selection excludes it")
    report.expectEqual(selectionBefore.revision + 1, selection.document.revision, cppID: drawerAutomationDeleteID,
                       what: "a multi-lane delete is one revision")
    report.expect(selection.undo(), cppID: drawerAutomationDeleteID, message: "the multi-lane delete is undoable")
    report.expectEqual(["24:30", "120:40"], selection.values(selection.panLane), cppID: drawerAutomationDeleteID,
                       what: "one undo restores the first lane")
    report.expectEqual(["48:100", "140:20"], selection.values(selection.volumeLane), cppID: drawerAutomationDeleteID,
                       what: "one undo restores the second lane")
    report.expect(!selection.document.history.canUndo, cppID: drawerAutomationDeleteID,
                  message: "one undo consumes the multi-lane delete's single history entry")
    report.expectEqual([selection.volumeLane, selection.panLane],
                       selection.page.selectedParameters, cppID: drawerAutomationDeleteID,
                       what: "the selection survives the delete it performed")
}

// Exact legacy tempo/CC row fixtures for the resolver and commit boundary.
@MainActor
private final class DrawerDomainCheckFixture {
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 9216),
    ]))
    let parameter: AutomationParameter
    let camera: EditorCamera.Snapshot

    init(_ parameter: AutomationParameter, camera: EditorCamera.Snapshot) {
        self.parameter = parameter
        self.camera = camera
    }

    struct Snapshot: Equatable {
        let bytes: [UInt8]
        let revision: UInt64
        let identity: DocumentIdentity
    }

    var snapshot: Snapshot {
        Snapshot(bytes: try! document.captureSave().bytes, revision: document.revision,
                 identity: document.history.currentIdentity)
    }

    var lane: AutomationLaneSnapshot {
        AutomationLaneSnapshot(parameter: parameter, in: document, songEndTick: 9216)
    }

    var facts: AutomationFrozenFacts {
        AutomationFrozenFacts(parameter: parameter, snapshot: lane, camera: camera,
                              selection: nil, modifiers: .init(), songEndTick: 9216)
    }

    var points: [String] { lane.displaySeries.map { "\($0.tick):\($0.value)" } }

    func set(_ points: [(Tick, Int)]) {
        if parameter.isTempo {
            document.editTempo(TempoEdit(remove: document.state.tempo, add: points.map {
                TempoPoint(tick: $0.0,
                           microsecondsPerQuarterNote: TimeDefaults.microsecondsPerQuarterNote(forBPM: $0.1))
            }))
        } else {
            document.writeLane(track: 0, lane: parameter.lane!, from: 0,
                               through: TimeDefaults.noTick,
                               points: points.map { LaneWrite(tick: $0.0, value: $0.1) })
        }
    }

    func insert(_ tick: Tick, _ value: UInt8) {
        document.insertRawEvent(chunk: 0, event: .channel(tick: tick, status: 0xB0,
                                                         data0: 11, data1: value))
    }

    func raw(_ tick: Tick) -> [Int] {
        document.lanePoints(track: 0, lane: .controller(11))
            .filter { $0.tick == tick }.map(\.value)
    }

    func move(_ requests: [(Tick, Tick, Int)]) -> Bool {
        let moves = requests.map {
            AutomationNodeMove(parameter: parameter, sourceTick: $0.0, tick: $0.1, value: $0.2)
        }
        guard let plan = AutomationNodeResolver.moves([.init(facts, moves)]) else { return false }
        return AutomationCommit.apply(plan, in: document)
    }

    func delete(_ ticks: [Tick]) -> Bool {
        guard let plan = AutomationNodeResolver.deletions(revision: document.revision,
            [.init(parameter: parameter, snapshot: lane, ticks: ticks)]) else { return false }
        return AutomationCommit.apply(plan, in: document)
    }

    func replace(_ begin: Tick, _ end: Tick, _ points: [(Tick, Int)]) {
        // Like NodeLane::replaceSpan, this is an explicit accepted replacement,
        // below gesture no-op planning. The document compares the stored bytes.
        _ = AutomationCommit.apply(AutomationLaneEdit(
            parameter: parameter, revision: document.revision, tickBegin: begin,
            tickEnd: end, points: points.map { AutomationLanePoint(tick: $0.0, value: $0.1) },
            unchanged: false), in: document)
    }

    func oneEdit(_ before: Snapshot) -> Bool {
        document.revision == before.revision + 1 && document.history.currentIdentity != before.identity
    }

    func replay(_ before: Snapshot, _ beforePoints: [String], _ afterPoints: [String]) -> Bool {
        let afterIdentity = document.history.currentIdentity
        guard document.history.undoDocument() else { return false }
        let undone = snapshot.bytes == before.bytes && snapshot.identity == before.identity && points == beforePoints
        guard document.history.redoDocument() else { return false }
        let redone = snapshot.identity == afterIdentity && points == afterPoints
        guard document.history.undoDocument() else { return false }
        return undone && redone && snapshot.bytes == before.bytes && snapshot.identity == before.identity
            && points == beforePoints
    }
}

@MainActor
func drawerAutomationLegacyResolverRows(_ report: CheckReport, camera: EditorCamera.Snapshot) {
    for parameter in [AutomationParameter.tempo, .controlChange(track: 0, controller: 11)] {
        let row = parameter.isTempo ? "tempo" : "cc"
        func expect(_ condition: @autoclosure () -> Bool, _ line: Int) {
            report.expect(condition(), cppID: "automation-domain/AutomationDomainTest::legacyResolverRows",
                          message: "tst_automationdomain.cpp:\(line) row=\(row)")
        }

        let deletion = DrawerDomainCheckFixture(parameter, camera: camera)
        deletion.set([(0, 120), (96, 100), (288, 110)])
        let beforeDelete = deletion.snapshot
        expect(!deletion.delete([]), 303)
        expect(deletion.snapshot == beforeDelete, 304)
        expect(!deletion.delete([99999]), 305)
        expect(deletion.snapshot == beforeDelete, 306)
        expect(deletion.delete([96]), 307)
        expect(deletion.oneEdit(beforeDelete), 308)
        expect(deletion.points == ["0:120", "288:110"], 309)
        if !parameter.isTempo { expect(deletion.raw(96).isEmpty, 311) }
        expect(deletion.replay(beforeDelete, ["0:120", "96:100", "288:110"],
                               ["0:120", "288:110"]), 312)

        if !parameter.isTempo {
            deletion.set([(0, 64)])
            deletion.insert(96, 10)
            deletion.insert(96, 20)
            let groupedBefore = deletion.snapshot
            let groupedPoints = deletion.points
            expect(deletion.delete([96]), 320)
            expect(deletion.oneEdit(groupedBefore), 321)
            expect(deletion.points == ["0:64"], 322)
            expect(deletion.raw(96).isEmpty, 323)
            expect(deletion.replay(groupedBefore, groupedPoints, ["0:64"]), 324)
        }

        let moving = DrawerDomainCheckFixture(parameter, camera: camera)
        if parameter.isTempo {
            moving.document.editTempo(TempoEdit(add: [
                TempoPoint(tick: 96, microsecondsPerQuarterNote: 499999),
                TempoPoint(tick: 288, microsecondsPerQuarterNote: TimeDefaults.microsecondsPerQuarterNote(forBPM: 110)),
            ]))
        } else {
            moving.set([(288, 40)])
            moving.insert(96, 10)
            moving.insert(96, 20)
        }
        let movingBefore = moving.snapshot
        let movingPoints = moving.points
        let movedValue = parameter.isTempo ? 120 : 20
        expect(!moving.move([]), parameter.isTempo ? 346 : 372)
        expect(moving.snapshot == movingBefore, parameter.isTempo ? 347 : 373)
        expect(!moving.move([(99999, 192, movedValue)]), parameter.isTempo ? 348 : 374)
        expect(moving.snapshot == movingBefore, parameter.isTempo ? 349 : 375)
        expect(moving.move([(96, 192, movedValue)]), parameter.isTempo ? 351 : 376)
        expect(moving.oneEdit(movingBefore), parameter.isTempo ? 352 : 377)
        let movedPoints = parameter.isTempo ? ["192:120", "288:110"] : ["192:20", "288:40"]
        expect(moving.points == movedPoints, parameter.isTempo ? 353 : 378)
        if parameter.isTempo {
            expect(moving.document.state.tempo.first?.microsecondsPerQuarterNote == 499999, 354)
        } else {
            expect(moving.raw(192) == [10, 20], 379)
        }
        expect(moving.replay(movingBefore, movingPoints, movedPoints), parameter.isTempo ? 355 : 380)

        if parameter.isTempo {
            let rewriteBefore = moving.snapshot
            let rewritePoints = moving.points
            expect(moving.move([(96, 192, 140)]), 359)
            expect(moving.oneEdit(rewriteBefore), 360)
            expect(moving.document.state.tempo.first?.microsecondsPerQuarterNote
                == TimeDefaults.microsecondsPerQuarterNote(forBPM: 140), 361)
            expect(moving.replay(rewriteBefore, rewritePoints, ["192:140", "288:110"]), 362)
        }

        if !parameter.isTempo {
            moving.insert(192, 70)
            moving.insert(192, 80)
        }
        let collisionBefore = moving.snapshot
        let collisionPoints = moving.points
        let destination: Tick = parameter.isTempo ? 288 : 192
        expect(moving.move([(96, destination, movedValue)]), parameter.isTempo ? 402 : 417)
        expect(moving.oneEdit(collisionBefore), parameter.isTempo ? 403 : 418)
        let collisionAfter = parameter.isTempo ? ["288:120"] : ["192:20", "288:40"]
        expect(moving.points == collisionAfter, parameter.isTempo ? 404 : 419)
        if parameter.isTempo {
            expect(moving.document.state.tempo.first?.microsecondsPerQuarterNote == 499999, 405)
        } else {
            expect(moving.raw(192) == [10, 20], 420)
        }
        expect(moving.replay(collisionBefore, collisionPoints, collisionAfter), parameter.isTempo ? 406 : 421)
    }
}

@MainActor
func drawerAutomationLegacyMetadataRows(_ report: CheckReport, camera: EditorCamera.Snapshot) {
    func expect(_ condition: @autoclosure () -> Bool, _ line: Int, row: String) {
        report.expect(condition(), cppID: "automation-domain/AutomationDomainTest::legacyMetadataRows",
                      message: "tst_automationdomain.cpp:\(line) row=\(row)")
    }
    for parameter in [AutomationParameter.tempo, .controlChange(track: 0, controller: 11)] {
        let row = parameter.isTempo ? "tempo" : "cc"
        let fixture = DrawerDomainCheckFixture(parameter, camera: camera)
        expect(fixture.document.engineTracks.usedTrackCount == 1, 49, row: row)
        expect(fixture.document.engineTracks.tracks[0].midiChunk == 0, 50, row: row)
        expect(fixture.points.isEmpty, 223, row: row)
        if parameter.isTempo {
            fixture.set([(288, 110), (0, 120), (96, 150)])
            expect(fixture.points == ["0:120", "96:150", "288:110"], 226, row: row)
            fixture.document.editTempo(TempoEdit(remove: fixture.document.state.tempo, add: [
                TempoPoint(tick: 0, microsecondsPerQuarterNote: TimeDefaults.microsecondsPerQuarterNote(forBPM: 150)),
                TempoPoint(tick: 96, microsecondsPerQuarterNote: 398406),
            ]))
            let metadata = fixture.lane.metadata
            let fractional = Int(TimeDefaults.tempoBPM(forMicrosecondsPerQuarterNote: 398406).rounded())
            expect(AutomationCatalog.title(parameter) == "Tempo (BPM)", 253, row: row)
            expect(metadata.minimum == 20, 254, row: row)
            expect(metadata.maximum == 255, 255, row: row)
            expect(metadata.valueText(150) == "150", 258, row: row)
            expect(metadata.valueText(fractional) == String(fractional), 259, row: row)
            expect(fixture.points == ["0:150", "96:\(fractional)"], 260, row: row)
        } else {
            fixture.insert(288, 40)
            fixture.insert(0, 64)
            fixture.insert(96, 10)
            fixture.insert(96, 20)
            expect(fixture.points == ["0:64", "96:20", "288:40"], 234, row: row)
            expect(fixture.raw(96) == [10, 20], 235, row: row)
            let bend = AutomationParameterMetadata(parameter: .pitchBend(track: 0))
            let modType = AutomationParameterMetadata(parameter: .controlChange(track: 0, controller: TimeDefaults.ccModulationType))
            let tune = AutomationParameterMetadata(parameter: .controlChange(track: 0, controller: TimeDefaults.ccFineTune))
            expect(bend.minimum == -8192, 263, row: row)
            expect(bend.maximum == 8191, 264, row: row)
            expect(modType.minimum == 0, 266, row: row)
            expect(modType.maximum == 2, 267, row: row)
            let prompt = tune.prompt(storedValue: 64)
            expect(prompt.minimum == -64, 272, row: row)
            expect(prompt.maximum == 63, 273, row: row)
            expect(prompt.initialValue == 0, 274, row: row)
            expect(tune.neutral == 64, 275, row: row)
            fixture.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccFineTune),
                                       from: 0, through: 96, points: [
                LaneWrite(tick: 0, value: prompt.minimum + prompt.storedOffset),
                LaneWrite(tick: 48, value: prompt.initialValue + prompt.storedOffset),
                LaneWrite(tick: 96, value: prompt.maximum + prompt.storedOffset),
            ])
            let tuneSnapshot = AutomationLaneSnapshot(parameter: tune.parameter, in: fixture.document, songEndTick: 9216)
            expect(tuneSnapshot.displaySeries.map { "\($0.tick):\($0.value)" } == ["0:0", "48:64", "96:127"], 280, row: row)
            expect(bend.neutral == 0, 281, row: row)
            expect(bend.prompt(storedValue: 0).storedOffset == 0, 282, row: row)
            expect(modType.neutral == nil, 283, row: row)
        }
    }
}

@MainActor
func drawerAutomationLegacyDefaultPromotion(_ report: CheckReport, camera: EditorCamera.Snapshot) {
    let fixture = DrawerDomainCheckFixture(.controlChange(track: 0, controller: 11), camera: camera)
    let document = fixture.document
    func expect(_ condition: @autoclosure () -> Bool, _ line: Int) {
        report.expect(condition(), cppID: "automation-domain/AutomationDomainTest::defaultNodePromotion",
                      message: "tst_automationdomain.cpp:\(line)")
    }
    func lane(_ parameter: AutomationParameter) -> AutomationLaneSnapshot {
        AutomationLaneSnapshot(parameter: parameter, in: document, songEndTick: 9216)
    }
    func points(_ parameter: AutomationParameter) -> [String] {
        lane(parameter).displaySeries.map { "\($0.tick):\($0.value)" }
    }
    let volume = AutomationParameter.controlChange(track: 0, controller: 7)
    let pan = AutomationParameter.controlChange(track: 0, controller: 10)
    let modulation = AutomationParameter.controlChange(track: 0, controller: 1)
    let bend = AutomationParameter.pitchBend(track: 0)
    expect(points(volume) == ["0:127"], 486)
    expect(points(pan) == ["0:64"], 487)
    expect(points(modulation).isEmpty, 488)
    expect(lane(modulation).leadInValue == 0, 490)
    expect(points(bend).isEmpty, 491)
    expect(lane(bend).leadInValue == 0, 493)
    expect(lane(.controlChange(track: 0, controller: TimeDefaults.ccFineTune)).leadInValue == 64, 499)
    expect(lane(.controlChange(track: 0, controller: TimeDefaults.ccModulationType)).leadInValue == 0, 502)
    expect(lane(.controlChange(track: 0, controller: TimeDefaults.ccLFODelay)).leadInValue == 0, 505)
    document.writeLane(track: 0, lane: .controller(TimeDefaults.ccModulationType), from: 0,
                       through: TimeDefaults.noTick, points: [LaneWrite(tick: 0, value: 7)])
    expect(document.lanePoints(track: 0, lane: .controller(TimeDefaults.ccModulationType))
        .filter { $0.tick == 0 }.map(\.value) == [2], 510)

    for (parameter, value, base, defaultPoints) in [
        (volume, 100, 514, ["0:127"]), (pan, 32, 527, ["0:64"]),
    ] {
        let before = fixture.snapshot
        let facts = AutomationFrozenFacts(parameter: parameter, snapshot: lane(parameter),
                                          camera: camera, selection: nil, modifiers: .init(),
                                          songEndTick: 9216)
        let resolved = AutomationNodeResolver.moves([.init(facts, [
            AutomationNodeMove(parameter: parameter, sourceTick: 0, tick: 96, value: value),
        ])])
        expect(resolved != nil, base)
        guard let resolved else { return }
        expect(!resolved.isEmpty, base + 3)
        _ = AutomationCommit.apply(resolved, in: document)
        expect(fixture.oneEdit(before), base + 5)
        expect(document.lanePoints(track: 0, lane: parameter.lane!)
            .filter { $0.tick == 96 }.map(\.value) == [value], base + 6)
        _ = document.history.undoDocument()
        expect(fixture.snapshot.bytes == before.bytes, base + 8)
        expect(points(parameter) == defaultPoints, base + 9)
    }
}

@MainActor
func drawerAutomationLegacySpanRows(_ report: CheckReport, camera: EditorCamera.Snapshot) {
    for parameter in [AutomationParameter.tempo, .controlChange(track: 0, controller: 11)] {
        let row = parameter.isTempo ? "tempo" : "cc"
        func expect(_ condition: @autoclosure () -> Bool, _ line: Int) {
            report.expect(condition(), cppID: "automation-domain/AutomationDomainTest::replaceSpans",
                          message: "tst_automationdomain.cpp:\(line) row=\(row)")
        }
        let fixture = DrawerDomainCheckFixture(parameter, camera: camera)
        let emptyBefore = fixture.snapshot
        fixture.replace(0, 10000, [])
        expect(fixture.snapshot == emptyBefore, 440)
        fixture.replace(0, 10000, [(96, 90)])
        expect(fixture.oneEdit(emptyBefore), 442)
        expect(fixture.points == ["96:90"], 443)
        expect(fixture.replay(emptyBefore, [], ["96:90"]), 444)

        let original = ["0:120", "96:100", "288:110"]
        fixture.set([(0, 120), (96, 100), (288, 110)])
        let before = fixture.snapshot
        fixture.replace(96, 96, [(96, 100)])
        expect(fixture.snapshot == before, 450)
        fixture.replace(96, 200, [(96, 80), (128, 70)])
        expect(fixture.oneEdit(before), 452)
        let replacement = ["0:120", "96:80", "128:70", "288:110"]
        expect(fixture.points == replacement, 454)
        expect(fixture.replay(before, original, replacement), 455)

        let clearBefore = fixture.snapshot
        fixture.replace(0, 10000, [])
        expect(fixture.oneEdit(clearBefore), 459)
        expect(fixture.points.isEmpty, 460)
        expect(fixture.replay(clearBefore, original, []), 461)

        if parameter.isTempo {
            fixture.document.editTempo(TempoEdit(remove: fixture.document.state.tempo, add: [
                TempoPoint(tick: 96, microsecondsPerQuarterNote: 398406),
            ]))
            let displayed = Int(TimeDefaults.tempoBPM(forMicrosecondsPerQuarterNote: 398406).rounded())
            let fractionalBefore = fixture.snapshot
            let beforePoints = fixture.points
            fixture.replace(96, 96, [(96, displayed)])
            expect(fixture.oneEdit(fractionalBefore), 469)
            expect(fixture.document.state.tempo.first?.microsecondsPerQuarterNote
                == TimeDefaults.microsecondsPerQuarterNote(forBPM: displayed), 470)
            expect(fixture.replay(fractionalBefore, beforePoints, ["96:\(displayed)"]), 471)
        }
    }
}
