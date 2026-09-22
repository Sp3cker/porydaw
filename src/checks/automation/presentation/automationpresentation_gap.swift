import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

private let automationPresentationGapID =
    "automation-presentation/AutomationPresentationTest::swiftPortableGaps"
private let automationPaintingGapID =
    "automation-presentation/AutomationPaintingTest::swiftPortableGaps"

@MainActor
func drawerAutomationTypedCursorIntent(_ report: CheckReport, suite: DocumentSession,
                                       service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64)])
    let page = fixture.page
    let panIndex = AutomationCatalog.index(of: fixture.panLane, track: 0) ?? -1
    report.expect(panIndex >= 0 && page.activateParameter(index: panIndex),
                  cppID: automationPresentationGapID,
                  message: "A017-A019 the production page activates its Pan row")
    report.expect(page.projection != nil && !page.valueLineSnapshots.isEmpty
        && !page.valueLabelSnapshots.isEmpty,
                  cppID: automationPresentationGapID,
                  message: "A020 Pan publishes a nonempty plot")

    let rows: [(id: String, dpr: Double)] = [
        ("A034-dpr1", 1), ("A037-dpr2", 2), ("A040-dpr1-again", 1),
    ]
    page.isPencilMode = true
    for row in rows {
        page.configureBody(width: 480, height: 120, gutter: 0,
                           devicePixelRatio: row.dpr, baseFontPx: 13, dragDistance: 10)
        let handled = page.pointerMove(x: fixture.x(72), y: 60, buttons: 0, modifiers: 0)
        report.expect(handled, cppID: automationPresentationGapID,
                      message: "\(row.id) plot move is accepted")
        report.expectEqual(AutomationCursorKind.pencil, page.observation.cursorIntent,
                           cppID: automationPresentationGapID,
                           what: "\(row.id) typed cursor intent remains pencil")
        report.expectEqual(AutomationCursorKind.pencil.rawValue, page.cursorKind,
                           cppID: automationPresentationGapID,
                           what: "\(row.id) published cursor kind matches typed intent")
    }

    let tempoIndex = AutomationCatalog.index(of: .tempo, track: 0) ?? -1
    report.expect(tempoIndex >= 0 && page.activateParameter(index: tempoIndex),
                  cppID: automationPresentationGapID,
                  message: "A023 the production page activates Tempo")
    _ = page.pointerMove(x: fixture.x(72), y: 60, buttons: 0, modifiers: 0)
    report.expectEqual(AutomationCursorKind.pencil, page.observation.cursorIntent,
                       cppID: automationPresentationGapID,
                       what: "A023 Tempo keeps pencil cursor intent over its plot")

    report.expect(page.activateParameter(index: panIndex),
                  cppID: automationPresentationGapID,
                  message: "A043-A044 Pan is restored for the pencil-off case")
    page.isPencilMode = false
    _ = page.pointerMove(x: fixture.x(72), y: 60, buttons: 0, modifiers: 0)
    report.expectEqual(AutomationCursorKind.arrow, page.observation.cursorIntent,
                       cppID: automationPresentationGapID,
                       what: "A046 disabling pencil mode restores typed arrow intent")
}

@MainActor
func drawerAutomationPublishedLabelsAndMetrics(_ report: CheckReport,
                                               suite: DocumentSession,
                                               service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(0, 127), (96, 64)], pan: [(24, 64)],
        tempo: [(0, 500_000)])
    let page = fixture.page
    let tabs = page.publishedTabs
    report.expectEqual(AutomationCatalog.count, page.parameterLabels.count,
                       cppID: automationPaintingGapID,
                       what: "A003 selector publishes one label per catalog parameter")
    report.expectEqual(page.parameterLabels, tabs.map(\.label),
                       cppID: automationPaintingGapID,
                       what: "A016 selector tab text equals the published labels")
    report.expectEqual(page.parameterLabels.count, page.rows.count,
                       cppID: automationPaintingGapID,
                       what: "A020 selector rows and labels have equal cardinality")
    report.expectEqual(page.rows.map(\.eventCount), tabs.map(\.eventCount),
                       cppID: automationPaintingGapID,
                       what: "A022 each selector count matches its automation row")
    report.expect(tabs.contains { $0.tempo }, cppID: automationPaintingGapID,
                  message: "A004 the published selector contains Tempo")
    report.expect(tabs.first { $0.tempo }?.label == "Tempo",
                  cppID: automationPaintingGapID,
                  message: "A005 the Tempo row keeps its catalog identity")

    let cases: [(id: String, parameter: AutomationParameter, texts: [String])] = [
        ("A158-A160-pan", fixture.panLane, ["c_v+63", "c_v-64", "c_v+0"]),
        ("A185-A187-volume", fixture.volumeLane, ["127", "0"]),
        ("A189-A191-tempo", .tempo, ["255", "20"]),
        ("A193-A195-bend", fixture.bendLane, ["+8191", "-8192", "0"]),
    ]
    for row in cases {
        fixture.activate(row.parameter)
        let labels = page.valueLabelSnapshots
        let rules = page.valueLineSnapshots
        report.expectEqual(row.texts, page.scaleLabels.map(\.text),
                           cppID: automationPaintingGapID,
                           what: "\(row.id) scale label model text")
        report.expectEqual(row.texts, labels.map(\.text),
                           cppID: automationPaintingGapID,
                           what: "\(row.id) published measured text")
        report.expectEqual(labels.count, rules.count, cppID: automationPaintingGapID,
                           what: "\(row.id) each label owns one scale rule")
        report.expect(labels.enumerated().allSatisfy { index, label in
            label.rect.x >= 0 && label.rect.width > 0 && label.rect.height > 0
                && label.rect.x + label.rect.width <= 480
                && label.rect.y >= 0 && label.rect.y + label.rect.height <= 120
                && abs(rules[index].y + rules[index].height / 2
                       - page.scaleLabels[index].y) <= 1
        }, cppID: automationPaintingGapID,
                      message: "\(row.id) native text metrics fit and align to curve-true rules")
        report.expect(Set(labels.map { Int($0.rect.y.rounded()) }).count == labels.count,
                      cppID: automationPaintingGapID,
                      message: "\(row.id) measured labels do not overlap vertically")
    }
    fixture.activate(fixture.panLane)
    let panLabels = page.valueLabelSnapshots
    let panRules = page.valueLineSnapshots
    let centers = panLabels.map { $0.rect.y + $0.rect.height / 2 }
    report.expect(panLabels.count == 3 && panLabels.allSatisfy { $0.rect.x < 120 },
                  cppID: automationPaintingGapID,
                  message: "A161 Pan scale labels hug the viewport's left quarter")
    report.expect(centers.count == 3 && centers[0] < 40
        && centers[2] >= 40 && centers[2] < 80 && centers[1] >= 80,
                  cppID: automationPaintingGapID,
                  message: "A162-A164 Pan maximum neutral and minimum occupy their thirds")
    report.expect(panLabels.indices.allSatisfy { left in
        panLabels.indices.allSatisfy { right in
            left == right || panLabels[left].rect.y + panLabels[left].rect.height
                <= panLabels[right].rect.y
                || panLabels[right].rect.y + panLabels[right].rect.height
                <= panLabels[left].rect.y
        }
    }, cppID: automationPaintingGapID,
                  message: "A165-A167 Pan scale labels do not intersect")
    report.expect(panLabels.count == 3 && page.scaleLabels.count == 3
        && abs(centers[1] - page.scaleLabels[1].y) <= panLabels[1].rect.height / 2,
                  cppID: automationPaintingGapID,
                  message: "A170 Pan minimum label remains on its curve height")
    report.expect(panRules.count == 3 && Set(panRules.map {
        Int(($0.y + $0.height / 2).rounded())
    }).count == 3 && panRules.indices.allSatisfy {
        abs(panRules[$0].y + panRules[$0].height / 2 - page.scaleLabels[$0].y) <= 1
    }, cppID: automationPaintingGapID,
                  message: "A171-A176 exactly one scale rule sits at each Pan label height")
}
