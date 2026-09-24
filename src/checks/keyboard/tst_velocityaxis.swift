import Foundation
import PorydawApp
import PorydawCore

private let velocityContinuousAxisID = "keyboard/VelocityModelTest::continuousAxisGeometryAndDensity"
private let velocityIntrinsicAxisID = "keyboard/VelocityModelTest::intrinsicAxisRowsAndRoundTrip"
private let velocityMarkerAxisID = "keyboard/VelocityModelTest::markerCapAndAccessibility"

private func velocityParityGeometry(height: Double, labelWidth: Double = 200.0) -> VelocityAxisGeometry {
    var geometry = VelocityAxisGeometry()
    geometry.height = height
    geometry.verticalInset = 6.0
    geometry.labelWidth = labelWidth
    geometry.labelSideInset = 2.0
    geometry.labelColumnGap = 1.0
    geometry.labelHeight = 12.0
    geometry.continuousDensityD1 = 84.0
    geometry.continuousDensityD2 = 112.0
    geometry.continuousDensityD3 = 156.0
    geometry.continuousDensityD4 = 300.0
    return geometry
}

func runVelocityAxisParityChecks(_ report: CheckReport) {
    let unresolved = VelocityMap(voiceKind: .unresolved)
    let directSound = VelocityMap(voiceKind: .directSound)
    let invalid = VelocityMap(voiceKind: .invalid)
    let axis = VelocityAxisModel(map: unresolved, geometry: velocityParityGeometry(height: 200.0),
                                 activeValues: [12, 64, 100])
    report.expectEqual(VelocityAxisModel.Mode.continuous, axis.mode, cppID: velocityContinuousAxisID,
                       what: "A110 unresolved map uses the continuous ruler")
    report.expectEqual(6.0, axis.top, cppID: velocityContinuousAxisID, what: "A111 ruler top is the inset")
    report.expectEqual(194.0, axis.bottom, cppID: velocityContinuousAxisID, what: "A112 ruler bottom is height minus inset")
    report.expectEqual(6.0, axis.velocityToY(127), cppID: velocityContinuousAxisID,
                       what: "A113 maximum velocity draws at the top")
    report.expectEqual(194.0, axis.velocityToY(1), cppID: velocityContinuousAxisID,
                       what: "A114 minimum velocity draws at the bottom")
    report.expectEqual(100.0, axis.velocityToY(64), cppID: velocityContinuousAxisID,
                       what: "A115 velocity 64 draws midway")
    report.expectEqual(127, axis.yToVelocity(6.0), cppID: velocityContinuousAxisID,
                       what: "A116 ruler top reads back maximum velocity")
    report.expectEqual(1, axis.yToVelocity(194.0), cppID: velocityContinuousAxisID,
                       what: "A117 ruler bottom reads back minimum velocity")
    report.expectEqual(2, axis.markers.count, cppID: velocityContinuousAxisID,
                       what: "A118 interior active value folds into min/max markers")
    report.expectEqual(12, axis.markers[0].velocity, cppID: velocityContinuousAxisID,
                       what: "A119 first marker is the minimum active value")
    report.expectEqual(100, axis.markers[1].velocity, cppID: velocityContinuousAxisID,
                       what: "A120 second marker is the maximum active value")
    report.expectEqual(17, axis.ticks.count, cppID: velocityContinuousAxisID,
                       what: "A121 height 200 uses the 17-tick density band")
    report.expect(axis.hasLabel(127), cppID: velocityContinuousAxisID, message: "A122 band labels the maximum")
    report.expect(axis.hasLabel(112), cppID: velocityContinuousAxisID, message: "A123 band labels 112")
    report.expect(axis.hasLabel(1), cppID: velocityContinuousAxisID, message: "A124 band labels the minimum")
    report.expect(axis.inRuler(x: 0.0, rulerWidth: 200.0), cppID: velocityContinuousAxisID,
                  message: "A125 ruler owns its left edge")
    report.expect(!axis.inRuler(x: 200.0, rulerWidth: 200.0), cppID: velocityContinuousAxisID,
                  message: "A126 ruler excludes its trailing edge")
    report.expectEqual(axis.labels[0].velocity,
                       axis.rulerVelocityAt(y: axis.labels[0].y, labelHeight: 12.0),
                       cppID: velocityContinuousAxisID,
                       what: "A127 press on a label row takes that label value")
    report.expectEqual(-1,
                       axis.rulerVelocityAt(y: axis.labels[0].y + 6.01, labelHeight: 12.0),
                       cppID: velocityContinuousAxisID,
                       what: "A128 press past the text radius reports no value")
    report.expectEqual(127, axis.ticks[0].velocity, cppID: velocityContinuousAxisID,
                       what: "A129 first tick is the maximum velocity")
    report.expectEqual(axis.top, axis.ticks[0].y, cppID: velocityContinuousAxisID,
                       what: "A130 first tick draws at the ruler top")
    let directAxis = VelocityAxisModel(map: directSound, geometry: velocityParityGeometry(height: 200.0))
    report.expectEqual(VelocityAxisModel.Mode.continuous, directAxis.mode, cppID: velocityContinuousAxisID,
                       what: "A131 direct sound uses the continuous ruler")
    let invalidAxis = VelocityAxisModel(map: invalid, geometry: velocityParityGeometry(height: 200.0))
    report.expectEqual(VelocityAxisModel.Mode.continuous, invalidAxis.mode, cppID: velocityContinuousAxisID,
                       what: "A132 invalid voice uses the continuous ruler")
    report.expectEqual(5, VelocityAxisModel(map: unresolved, geometry: velocityParityGeometry(height: 83.0)).ticks.count,
                       cppID: velocityContinuousAxisID, what: "A133 below D1 thins to 5 ticks")
    report.expectEqual(9, VelocityAxisModel(map: unresolved, geometry: velocityParityGeometry(height: 84.0)).ticks.count,
                       cppID: velocityContinuousAxisID, what: "A134 at D1 steps to 9 ticks")
    report.expectEqual(9, VelocityAxisModel(map: unresolved, geometry: velocityParityGeometry(height: 112.0)).ticks.count,
                       cppID: velocityContinuousAxisID, what: "A135 at D2 holds 9 ticks")
    report.expectEqual(17, VelocityAxisModel(map: unresolved, geometry: velocityParityGeometry(height: 156.0)).ticks.count,
                       cppID: velocityContinuousAxisID, what: "A136 at D3 steps to 17 ticks")
    let dense = VelocityAxisModel(map: unresolved, geometry: velocityParityGeometry(height: 300.0))
    report.expectEqual(32, dense.ticks.count, cppID: velocityContinuousAxisID,
                       what: "A137 at D4 reaches the 32-tick cap")
    report.expectEqual(123, dense.ticks[1].velocity, cppID: velocityContinuousAxisID,
                       what: "A138 finest band steps ticks by four from 127")
    report.expectEqual(7, dense.ticks[30].velocity, cppID: velocityContinuousAxisID,
                       what: "A139 finest band ends its stride at 7")
    let belowD2 = VelocityAxisModel(map: unresolved, geometry: velocityParityGeometry(height: 111.999))
    let atD2 = VelocityAxisModel(map: unresolved, geometry: velocityParityGeometry(height: 112.0))
    let belowD2Labels = [127, 64, 1]
    let atD2Labels = [127, 96, 64, 32, 1]
    let denseLabels = [127, 120, 112, 104, 96, 88, 80, 72, 64, 56, 48, 40, 32, 24, 16, 8, 1]
    report.expectEqual(belowD2Labels.count, belowD2.labels.count, cppID: velocityContinuousAxisID,
                       what: "A140 below D2 labels three values")
    for index in belowD2Labels.indices {
        report.expectEqual(belowD2Labels[index], belowD2.labels[index].velocity,
                           cppID: velocityContinuousAxisID, what: "A141 below-D2 label \(index)")
    }
    report.expectEqual(atD2Labels.count, atD2.labels.count, cppID: velocityContinuousAxisID,
                       what: "A142 at D2 labels five values")
    for index in atD2Labels.indices {
        report.expectEqual(atD2Labels[index], atD2.labels[index].velocity,
                           cppID: velocityContinuousAxisID, what: "A143 at-D2 label \(index)")
    }
    report.expectEqual(denseLabels.count, dense.labels.count, cppID: velocityContinuousAxisID,
                       what: "A144 dense band labels seventeen values")
    for index in denseLabels.indices {
        report.expectEqual(denseLabels[index], dense.labels[index].velocity,
                           cppID: velocityContinuousAxisID, what: "A145 dense label \(index)")
    }

    let intrinsicMaps: [(String, VelocityMap)] = [
        ("square", VelocityMap(voiceKind: .square1)),
        ("noise", VelocityMap(voiceKind: .noise)),
        ("wave", VelocityMap(voiceKind: .wave)),
    ]
    for (name, map) in intrinsicMaps {
        let intrinsic = VelocityAxisModel(map: map, geometry: velocityParityGeometry(height: 200.0))
        report.expectEqual(VelocityAxisModel.Mode.intrinsic, intrinsic.mode, cppID: velocityIntrinsicAxisID,
                           what: "A146 \(name) uses the intrinsic ruler")
        report.expectEqual(map.levelCount, intrinsic.graduations.count, cppID: velocityIntrinsicAxisID,
                           what: "A147 \(name) publishes one row per level")
        for level in 0..<intrinsic.graduations.count {
            report.expectEqual(Int(map.representative(level)), intrinsic.graduations[level].velocity,
                               cppID: velocityIntrinsicAxisID,
                               what: "A148 \(name) level \(level) carries its representative")
            report.expect(intrinsic.graduations[level].y >= intrinsic.top, cppID: velocityIntrinsicAxisID,
                          message: "A149 \(name) level \(level) stays below the top")
            report.expect(intrinsic.graduations[level].y <= intrinsic.bottom, cppID: velocityIntrinsicAxisID,
                          message: "A150 \(name) level \(level) stays above the bottom")
            report.expectEqual(level, intrinsic.yToLevel(intrinsic.levelToY(level)),
                               cppID: velocityIntrinsicAxisID,
                               what: "A151 \(name) level \(level) round-trips through its center")
        }
    }
    let narrow = VelocityAxisModel(map: VelocityMap(voiceKind: .square1),
                                   geometry: velocityParityGeometry(height: 200.0, labelWidth: 2.0))
    report.expectEqual(0.0, narrow.intrinsicColumnWidth, cppID: velocityIntrinsicAxisID,
                       what: "A152 narrow label width collapses the intrinsic column")
    report.expectEqual(0.0, narrow.graduations[0].width, cppID: velocityIntrinsicAxisID,
                       what: "A153 narrow first graduation has no width")
    report.expect(narrow.graduations[0].x >= 0.0, cppID: velocityIntrinsicAxisID,
                  message: "A154 narrow first graduation stays in bounds")
    report.expect(narrow.graduations[1].x >= 0.0, cppID: velocityIntrinsicAxisID,
                  message: "A155 narrow second graduation stays in bounds")

    let selected = VelocityAxisModel(map: unresolved, geometry: velocityParityGeometry(height: 300.0),
                                     activeValues: [73])
    report.expectEqual(denseLabels.count, selected.labels.count, cppID: velocityMarkerAxisID,
                       what: "A156 selected dense ruler labels seventeen values")
    for index in denseLabels.indices {
        report.expectEqual(denseLabels[index], selected.labels[index].velocity,
                           cppID: velocityMarkerAxisID, what: "A157 selected dense label \(index)")
    }
    report.expectEqual(1, selected.markers.count, cppID: velocityMarkerAxisID,
                       what: "A158 one active value draws one marker")
    report.expectEqual(73, selected.markers[0].velocity, cppID: velocityMarkerAxisID,
                       what: "A159 marker carries the active value")
    let capped = VelocityAxisModel(map: unresolved, geometry: velocityParityGeometry(height: 200.0),
                                   activeValues: [12, 64, 100])
    report.expectEqual(VelocityAxisModel.maximumMarkers, capped.markers.count, cppID: velocityMarkerAxisID,
                       what: "A160 active set caps at the marker maximum")
    report.expectEqual(12, capped.markers[0].velocity, cppID: velocityMarkerAxisID,
                       what: "A161 capped first marker is the minimum")
    report.expectEqual(100, capped.markers[1].velocity, cppID: velocityMarkerAxisID,
                       what: "A162 capped second marker is the maximum")
    report.expectEqual("Velocity", capped.accessibleDescription, cppID: velocityMarkerAxisID,
                       what: "A163 continuous ruler description is the plain domain")
    report.expect(!VelocityAxisModel.nodesFocusable, cppID: velocityMarkerAxisID,
                  message: "A164 ruler nodes stay unfocusable")
    report.expect(!VelocityAxisModel.graduationLabelsFocusable, cppID: velocityMarkerAxisID,
                  message: "A165 graduation labels stay unfocusable")
}
