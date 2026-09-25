import Foundation
import PorydawApp
import PorydawCore

@MainActor
func activityRemainsSilentAndRebuiltTracksRetainIdentity(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    // Like SongView::setSong, attachment starts at the settled paused fill.
    let silenceID = "swiftcore/TrackHeaders::activityRasterMatchesRolesAndIsSilentWhenUnchanged"
    let scopeID = "swiftcore/TrackHeaders::roleScopedUpdatesAndPhysicalPixelBoundaries"
    let pauseID = "swiftcore/TrackHeaders::pauseRasterAndIntensityCapUseObservedDpr"
    let identityID = "swiftcore/TrackHeaders::stereoRasterAndRebuiltTracksRetainIdentity"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let retained = fx.trackRows
    let rebuilds = h.rowRebuildCount
    let fullHeight = Double(h.rowHeight - h.separatorWidth)
    for playing in [false, true, false] {
        h.refreshPlayhead(tick: 24, playing: playing)
        h.refreshFromDocument()
        for (index, row) in fx.trackRows.enumerated() {
            report.expectEqual(expected: fullHeight, actual: row.activityLeftHeight, cppID: silenceID,
                               what: "playing \(playing), track \(index): position-only update retains paused left fill")
            report.expectEqual(expected: fullHeight, actual: row.activityRightHeight, cppID: pauseID,
                               what: "playing \(playing), track \(index): position-only update retains paused right fill")
            report.expect(row === retained[index], cppID: scopeID,
                          message: "playing \(playing), track \(index): unchanged silence publishes no new row")
        }
    }
    report.expectEqual(expected: rebuilds, actual: h.rowRebuildCount, cppID: silenceID,
                       what: "unchanged activity does not reset model")
    let colors = fx.trackRows.map(\.activityActiveColor)
    report.expect(colors[0] != colors[1], cppID: identityID,
                  message: "distinct engine tracks have distinct meter identities")
    fx.rebuild()
    report.expectEqual(expected: colors, actual: fx.trackRows.map(\.activityActiveColor), cppID: identityID,
                       what: "rebuild restores the same per-track meter colors")
    report.expect(fx.document.duplicateTrack(0) != nil, cppID: identityID,
                  message: "structural edit adds another track identity")
    report.expectEqual(expected: [0, 1, 2], actual: fx.trackRows.map(\.track), cppID: identityID,
                       what: "rebuilt meter rows address each current engine track exactly once")
    report.expectEqual(expected: colors, actual: Array(fx.trackRows.prefix(2)).map(\.activityActiveColor),
                       cppID: identityID, what: "existing track identities survive structural rebuild")
    for row in fx.trackRows {
        report.expect(row.activityLeftHeight == fullHeight && row.activityRightHeight == fullHeight,
                      cppID: identityID, message: "rebuilt track \(row.track) starts with settled paused fill")
    }
    let afterRebuild = fx.trackRows
    let afterCount = h.rowRebuildCount
    h.refreshFromDocument()
    report.expectEqual(expected: afterCount, actual: h.rowRebuildCount, cppID: identityID,
                       what: "unchanged rebuilt model remains quiet")
    report.expect(zip(afterRebuild, fx.trackRows).allSatisfy { pair in pair.0 === pair.1 }, cppID: identityID,
                  message: "unchanged rebuilt rows retain their published identities")
}

@MainActor
func trackActivityPhysicalPixelPredicates(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "TrackActivityMeterTest::roleScopedUpdatesAndPhysicalPixelBoundaries"
    for dpr in [1.0, 1.25, 2.0] {
        let fx = TrackHeadersFixture(suite: suite, service: service)
        let h = fx.headers
        h.configureViewport(width: 228, height: 240, fontPx: 13, dpr: dpr)
        let height = max(0, h.rowHeight - h.separatorWidth)
        report.expect(height > 0 && h.activityWidth > 0, cppID: id, message: "meter geometry exists")
        var levels = Array(repeating: AudioActivityLevel(), count: 16)
        h.advanceActivity(levels: levels, elapsedSeconds: 60, playing: true)
        levels[0] = AudioActivityLevel(left: 128, right: 128)
        let untouched = h.rows[1]
        h.advanceActivity(levels: levels, elapsedSeconds: 60, playing: true)
        report.expect(h.rows[1] === untouched, cppID: id, message: "activity does not publish another track")
        func physical(_ level: UInt8) -> Int {
            Int((Double(Float(level) / 255) * Double(height) * dpr).rounded())
        }
        report.expectEqual(expected: Double(physical(128)) / dpr, actual: h.rows[0].activityLeftHeight,
                           cppID: id, what: "left height follows physical pixel rounding")
        report.expectEqual(expected: Double(physical(128)) / dpr, actual: h.rows[0].activityRightHeight,
                           cppID: id, what: "right height follows physical pixel rounding")
        guard let shared = (128..<255).first(where: { physical(UInt8($0)) == physical(UInt8($0 + 1)) }) else {
            report.fail(id, "fixture has no two levels within a physical pixel")
            continue
        }
        levels[0] = AudioActivityLevel(left: UInt8(shared), right: UInt8(shared))
        h.advanceActivity(levels: levels, elapsedSeconds: 60, playing: true)
        let within = h.rows[0]
        levels[0] = AudioActivityLevel(left: UInt8(shared + 1), right: UInt8(shared + 1))
        h.advanceActivity(levels: levels, elapsedSeconds: 60, playing: true)
        report.expect(h.rows[0] === within, cppID: id, message: "same physical pixel publishes no row")
        guard let across = ((shared + 2)...255).first(where: { physical(UInt8($0)) > physical(UInt8(shared + 1)) }) else {
            report.fail(id, "fixture has no next physical pixel")
            continue
        }
        levels[0] = AudioActivityLevel(left: UInt8(across), right: UInt8(across))
        h.advanceActivity(levels: levels, elapsedSeconds: 60, playing: true)
        report.expect(h.rows[0].activityLeftHeight > within.activityLeftHeight, cppID: id,
                      message: "crossing physical boundary changes height")
        let paused = "TrackActivityMeterTest::pauseRasterAndIntensityCapUseObservedDpr"
        h.advanceActivity(levels: Array(repeating: AudioActivityLevel(), count: 16),
                          elapsedSeconds: 60, playing: false)
        report.expectEqual(expected: Double((Double(height) * dpr).rounded()) / dpr, actual: 
                           h.rows[0].activityLeftHeight, cppID: paused, what: "paused left fills row")
        report.expectEqual(expected: h.rows[0].activityLeftHeight, actual: h.rows[0].activityRightHeight,
                           cppID: paused, what: "paused right fills row")
        let capped = TrackActivity.physicalHeight(1, meterHeight: height, dpr: dpr,
                                                  playing: true, maximumIntensity: 0.15)
        report.expectEqual(expected: Int((0.15 * Double(height) * dpr).rounded()), actual: capped,
                           cppID: paused, what: "playing intensity obeys cap")
        report.expect(TrackActivity.physicalHeight(1, meterHeight: height, dpr: dpr,
                                                    playing: false, maximumIntensity: 0.15) > capped,
                      cppID: paused, message: "pause ignores playing cap")
        levels[0] = AudioActivityLevel(left: 255, right: 64)
        levels[1] = AudioActivityLevel(left: 96, right: 96)
        h.advanceActivity(levels: levels, elapsedSeconds: 60, playing: true)
        let stereo = "TrackActivityMeterTest::stereoRasterAndRebuiltTracksRetainIdentity"
        report.expect(h.rows[0].activityLeftHeight > h.rows[0].activityRightHeight,
                      cppID: stereo, message: "stereo channels keep independent heights")
        report.expect(h.rows[0].activityLeftHeight > h.rows[1].activityLeftHeight,
                      cppID: stereo, message: "tracks keep independent heights")
        let rows = fx.trackRows
        h.advanceActivity(levels: levels, elapsedSeconds: 60, playing: true)
        report.expect(zip(rows, fx.trackRows).allSatisfy { $0 === $1 }, cppID: stereo,
                      message: "unchanged converged levels retain all rows")
    }
}
